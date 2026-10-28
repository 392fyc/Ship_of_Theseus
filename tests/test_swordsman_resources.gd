extends SceneTree
## 剑圣资源引擎 headless 回归测试（批次1：单位级 + 伤害计算）
##
## 覆盖「真理源」代码（unit.gd / damage_calculator.gd）+ JSON 数据层：
##   居合必中必暴、满印记→拔刀槽位替换（含职业校验）、心眼(暴击/剑气分档属性)、印记属性+2、
##   暴击倍率(1.5x 基线 / 拔刀乘算 ×1.2 → 1.8x)、纯粹伤害不参与暴击判定、命中 1% 下限、
##   hybrid 基础伤害（物理魔法各算一次再取平均）。
## tactical_manager.gd 的运行时接线（命中产气/施放扣气/击杀返气/cd-1/mark_gain）
##   由批次2 集成测试覆盖（test_swordsman_integration.gd）。
##
## 运行：
##   <Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##     --script res://tests/test_swordsman_resources.gd
## 退出码 0=全过，1=有失败。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_swordsman_resources (批次1) ===")


## 自定义 SceneTree 主循环下，节点的 _ready/@onready 要到第一帧才触发；
## 故在首帧 _process 里跑测试，确保 Unit.tscn 的 @onready 子节点（sprite 等）已绑定。
func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	var dl: Object = load("res://scripts/data/data_loader.gd").new()
	dl.load_all()

	_test_data_layer(dl)
	_test_unit_resource(dl)
	_test_xinyan_passive(dl)
	_test_mark_attributes(dl)
	_test_slot_swap(dl)
	_test_slot_swap_class_gate(dl)
	_test_class_isolation(dl)
	_test_damage_formulas(dl)

	dl.free()

	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  ✗ " + f)
	quit(0 if _fail == 0 else 1)


# ── 断言工具 ─────────────────────────────────────────

func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		_fails.append(name + ("  [" + detail + "]" if detail != "" else ""))
		print("  ✗ " + name + ("  [" + detail + "]" if detail != "" else ""))


func _eq(name: String, actual: Variant, expected: Variant) -> void:
	_check(name, actual == expected, "期望 %s 实际 %s" % [str(expected), str(actual)])


func _make_unit(class_data: Dictionary) -> Unit:
	var u: Unit = load("res://scenes/tactical/Unit.tscn").instantiate()
	root.add_child(u)
	u.setup(class_data)
	return u


# ── 1. 数据层（JSON 值）──────────────────────────────

func _test_data_layer(dl: Object) -> void:
	print("\n[1] 数据层 JSON 值")
	var cls: Dictionary = dl.classes.get("kensei", {})
	_check("kensei 职业存在", not cls.is_empty())
	var cfg: Dictionary = cls.get("sword_qi_config", {})
	_eq("sword_qi_config.qi_max==100", cfg.get("qi_max"), 100)
	_eq("sword_qi_config.qi_initial==0", cfg.get("qi_initial"), 0)
	# 心眼数值（设计库 762393b kensei_xinyan，gameplay-impl PR4 实装）：每 20 点剑气暴击 +1；
	# 剑气每比 100 少 40 点速度 +1；旧的高低分档键已删除。
	_eq("sword_qi_config.crit_per_qi==1", int(cfg.get("crit_per_qi", 0)), 1)
	_eq("sword_qi_config.qi_per_crit_pct==20", int(cfg.get("qi_per_crit_pct", 0)), 20)
	_eq("sword_qi_config.qi_ratio_threshold_pct==50", cfg.get("qi_ratio_threshold_pct"), 50)
	_eq("sword_qi_config.qi_deficit_per_step==40", int(cfg.get("qi_deficit_per_step", 0)), 40)
	_eq("sword_qi_config.deficit_stat_key==SPD", cfg.get("deficit_stat_key"), "SPD")
	_eq("sword_qi_config.deficit_stat_bonus==1", int(cfg.get("deficit_stat_bonus", 0)), 1)
	_check("旧分档键已删除", not cfg.has("low_qi_stat_key") and not cfg.has("high_qi_stat_key"))
	# 旧的单一阈值键已随语义变化删除，不与新键并存
	_check("旧键 speed_threshold 已删除", not cfg.has("speed_threshold"))
	_check("旧键 speed_bonus 已删除", not cfg.has("speed_bonus"))
	# 印记改为百分比提升 10%（kensei_xinyan），固定加值置 0。
	_eq("sword_qi_config.mark_dex_bonus==0", int(cfg.get("mark_dex_bonus", -1)), 0)
	_eq("sword_qi_config.mark_spd_bonus==0", int(cfg.get("mark_spd_bonus", -1)), 0)
	_eq("sword_qi_config.mark_str_bonus==0", int(cfg.get("mark_str_bonus", -1)), 0)
	_eq("sword_qi_config.mark_*_pct==10",
		[int(cfg.get("mark_dex_pct", 0)), int(cfg.get("mark_spd_pct", 0)), int(cfg.get("mark_str_pct", 0))],
		[10, 10, 10])
	_eq("sword_qi_config.mark_max==3", cfg.get("mark_max"), 3)
	_eq("skill_ids 长度==5", (cls.get("skill_ids", []) as Array).size(), 5)
	# 剑圣五个技能的字段值逐项对照设计库，在 test_kensei_base 里断言；这里只确认
	# 职业指向 kensei_*，且旧的 swordsman_* 技能文件已经下线、不会被误装载。
	_eq("剑圣 skill_ids 全部是 kensei_*",
		str(cls.get("skill_ids", [])),
		str(["kensei_zhanji", "kensei_yishan", "kensei_zhaojia", "kensei_juhe", "kensei_badao"]))
	for old_id: String in ["swordsman_zhanji", "swordsman_yishan", "swordsman_zhaojia",
			"swordsman_juhe", "swordsman_badao"]:
		_check("旧技能 %s 已下线（DataLoader 里没有）" % old_id, not dl.skills.has(old_id))


# ── 2. unit.gd 剑气资源（钳制 / 隔离写入）────────────

func _test_unit_resource(dl: Object) -> void:
	print("\n[2] unit.gd 剑气钳制")
	var u: Unit = _make_unit(dl.classes["kensei"])
	_eq("初始 _qi_max==100", u._qi_max, 100)
	_eq("初始 sword_qi==0", u.sword_qi, 0)
	_eq("初始印记数==0", u.get_mark_count(), 0)
	u.set_sword_qi(5)
	_eq("set_sword_qi(5)→5", u.sword_qi, 5)
	u.set_sword_qi(150)
	_eq("set_sword_qi(150)→钳到100", u.sword_qi, 100)
	u.set_sword_qi(-3)
	_eq("set_sword_qi(-3)→钳到0", u.sword_qi, 0)
	u.free()


# ── 3. 心眼（暴击 + 剑气比例分档属性）────────────────

## 设计库现行口径（myrmidon_xinyan / kensei_xinyan）：
##   每 10 点剑气 = 暴击 +2（向下取整）；
##   剑气 ≤ 上限的 50% 时速度 +2，> 50% 时技巧 +2。
## 旧口径（每 10 点 +1、剑气 ≥70 时速度 +1）已废弃。
func _test_xinyan_passive(dl: Object) -> void:
	# 设计库 762393b kensei_xinyan（gameplay-impl PR4）：每 20 点剑气暴击 +1；剑气每比 100 少 40 点
	# 速度 +1；都按整档、随剑气即时变化；不再给技巧。
	print("\n[3] 心眼被动（每 20 点剑气暴击 +1 / 每比 100 少 40 点速度 +1）")
	var u: Unit = _make_unit(dl.classes["kensei"])
	var base_spd: int = u.stats.spd
	var base_dex: int = u.stats.dex
	# ── 暴击：floor(剑气/20)×1 ──
	for c: Array in [[0, 0], [19, 0], [20, 1], [70, 3], [100, 5]]:
		u.set_sword_qi(int(c[0]))
		_eq("剑气%d → crit_bonus==%d" % [c[0], c[1]], u.crit_bonus, int(c[1]))
	# ── 速度：floor((100−剑气)/40)×1；技巧不变 ──
	for c: Array in [[0, 2], [20, 2], [21, 1], [60, 1], [61, 0], [100, 0]]:
		u.set_sword_qi(int(c[0]))
		_eq("剑气%d → SPD==基础+%d" % [c[0], c[1]], u.get_effective_stat("SPD"), base_spd + int(c[1]))
		_eq("剑气%d → DEX==基础(心眼不再给技巧)" % c[0], u.get_effective_stat("DEX"), base_dex)
	# ── get_crit_value = weapon_crit + int(生效DEX/2) + crit_bonus ──
	u.set_sword_qi(70)
	_eq("剑气70 → get_crit_value(10)==10+int(基础DEX/2)+3",
		u.get_crit_value(10), 10 + int(base_dex / 2.0) + 3)
	u.free()


# ── 4. 印记属性（心→DEX / 道→LCK / 势→STR 各+2）─────

func _test_mark_attributes(dl: Object) -> void:
	# 设计库 kensei_xinyan（gameplay-impl PR4）：〔心〕技巧、〔道〕速度、〔势〕力量各提升 10%；
	# 按 R1.8 先把固定点数相加，再乘百分比，最后向下取整。
	print("\n[4] 印记属性提升 10%")
	var u: Unit = _make_unit(dl.classes["kensei"])
	u.stats.dex = 10          # 10 × 1.1 = 11，避开 9 × 1.1 = 9.9 → 9 这种测不出提升的值
	var base_spd: int = u.get_effective_stat("SPD")   # 剑气 0：含心眼速度 +2 的固定点数
	# 基线（STR=10, LCK=5）
	_eq("基线 DEX==10", u.get_effective_stat("DEX"), 10)
	_eq("基线 LCK==5", u.get_effective_stat("LCK"), 5)
	_eq("基线 STR==10", u.get_effective_stat("STR"), 10)
	# 心→DEX 提升 10%
	u.marks["心"] = true
	_eq("持心 → DEX==11（10 × 1.1）", u.get_effective_stat("DEX"), 11)
	# 道→SPD+2
	# ⚠ 2026-08-03 更正：本条原先断言「道 → LCK+2」，钉的是引擎当时的实装，
	# 而设计库真源（/api/resources 的 mark 条目）逐字写的是「道为速度 SPD +2」。
	# 台账 D-8 已判定设计库为准（KB 那句是 2026-07-25 commit 8e09371 对齐生产库写入的），
	# 故引擎改为加 SPD，本断言随之改成验证正确口径。
	u.marks["道"] = true
	_eq("持道 → SPD == floor((基础 + 心眼 +2) × 1.1)",
		u.get_effective_stat("SPD"), floori(float(base_spd) * 1.1 + 0.000001))
	_eq("持道 → LCK 不变", u.get_effective_stat("LCK"), 5)
	# 势→STR 提升 10%
	u.marks["势"] = true
	_eq("持势 → STR==11（10 × 1.1）", u.get_effective_stat("STR"), 11)
	# clear_marks 后恢复
	u.clear_marks()
	_eq("clear后 DEX==10", u.get_effective_stat("DEX"), 10)
	_eq("clear后 STR==10", u.get_effective_stat("STR"), 10)
	_eq("clear后 SPD 复原", u.get_effective_stat("SPD"), base_spd)
	u.free()


# ── 5. 印记计数 + 满3→拔刀槽位替换 ───────────────────

func _test_slot_swap(dl: Object) -> void:
	print("\n[5] 印记计数 + 招架→拔刀槽位替换（数据驱动，替换规则读 JSON）")
	var u: Unit = _make_unit(dl.classes["kensei"])
	# 替换规则来自剑圣招架 kensei_zhaojia 的 JSON（gameplay-impl PR4）：3 印记且剑气 ≥ 20 → 拔刀
	var zj: Dictionary = dl.skills["kensei_zhaojia"]
	var trig: String = str(zj.get("slot_swap_trigger", ""))
	var tgt: String = str(zj.get("slot_swap_target", ""))
	var req: Dictionary = zj.get("slot_swap_requires", {})
	u.set_sword_qi(20)
	# 未满印记：招架槽显示招架
	_eq("印记0 招架槽→招架", u.get_visible_skill_id("kensei_zhaojia", trig, tgt, req), "kensei_zhaojia")
	# gain_random_mark ×3 → 满
	u.gain_random_mark()
	u.gain_random_mark()
	u.gain_random_mark()
	_eq("gain×3 → 印记数==3", u.get_mark_count(), 3)
	_check("印记满 is_marks_full()==true", u.is_marks_full())
	_eq("第4次 gain 返回空串", u.gain_random_mark(), "")
	# 满印记且剑气 ≥ 20：招架槽按 JSON 声明替换为拔刀
	_eq("印记满 + 剑气20 招架槽→拔刀", u.get_visible_skill_id("kensei_zhaojia", trig, tgt, req), "kensei_badao")
	u.set_sword_qi(19)
	_eq("印记满但剑气19 → 仍是招架", u.get_visible_skill_id("kensei_zhaojia", trig, tgt, req), "kensei_zhaojia")
	u.set_sword_qi(20)
	# 无 slot_swap 声明的技能不替换
	_eq("斩击槽不替换", u.get_visible_skill_id("kensei_zhanji", "", ""), "kensei_zhanji")
	# 清印记后恢复招架
	u.clear_marks()
	_eq("clear后 招架槽→招架", u.get_visible_skill_id("kensei_zhaojia", trig, tgt, req), "kensei_zhaojia")
	# 印记上限来自 JSON（mark_max），不再硬编码 3
	_eq("_mark_max==3 (来自 JSON mark_max)", u._mark_max, 3)
	# spend_marks 按量扣减（非全清）
	u.marks["心"] = true
	u.marks["道"] = true
	u.marks["势"] = true
	_eq("spend_marks(1) 返回扣除数1", u.spend_marks(1), 1)
	_eq("spend 1 后 印记数==2", u.get_mark_count(), 2)
	_eq("spend_marks(5) 超量 → 返回剩余2", u.spend_marks(5), 2)
	_eq("全扣后 印记数==0", u.get_mark_count(), 0)
	u.free()


# ── 5b. 槽位替换的职业校验（替换目标必须在本单位 skill_ids 内）──

## 全仓只有「建技能栏」与「扫迅捷技能」两处读 skill_ids，施放路径不另做职业检查，
## 技能栏本身就是访问控制。剑士（myrmidon）只使用剑气，印记容量为零；
## 但拔刀按 R2.4 是剑圣专属、不在其 skill_ids 内 → 招架槽必须保持为招架。
## 两侧都要覆盖：拥有 target 则替换生效（剑圣），不拥有则不替换（剑士）。
func _test_slot_swap_class_gate(dl: Object) -> void:
	print("\n[5b] 槽位替换职业校验（拔刀=剑圣专属，剑士不得替换）")
	# 拿剑圣招架 kensei_zhaojia 的替换声明去问剑士，验证职业门控本身。
	var zj: Dictionary = dl.skills["kensei_zhaojia"]
	var trig: String = str(zj.get("slot_swap_trigger", ""))
	var tgt: String = str(zj.get("slot_swap_target", ""))
	var req: Dictionary = zj.get("slot_swap_requires", {})

	# ① 不拥有 target 的一侧：剑士
	var mm: Dictionary = dl.classes.get("myrmidon", {})
	_check("myrmidon 职业存在", not mm.is_empty())
	var m: Unit = _make_unit(mm)
	_check("剑士 skill_ids 不含拔刀", not m.skill_ids.has(tgt))
	# 剑士的招架是自己的 myrmidon_zhaojia（gameplay-impl PR3），它不声明拔刀替换。
	_check("剑士持有自己的招架，且不声明拔刀替换",
		m.skill_ids.has("myrmidon_zhaojia")
		and not (dl.skills["myrmidon_zhaojia"] as Dictionary).has("slot_swap_target"))
	m.gain_random_mark()
	m.gain_random_mark()
	m.gain_random_mark()
	_check("剑士没有印记系统", m._mark_max == 0 and not m.is_marks_full() and m.get_mark_count() == 0)
	m.set_sword_qi(100)
	_eq("剑士无印记 → 招架槽仍是招架（不得替换为剑圣专属拔刀）",
		m.get_visible_skill_id("kensei_zhaojia", trig, tgt, req), "kensei_zhaojia")
	m.free()

	# ② 拥有 target 的一侧：剑圣（对照组，确认校验没把正常替换一并挡掉）。剑圣的招架是
	# kensei_zhaojia（gameplay-impl PR4），替换目标 kensei_badao，门槛 3 印记且剑气 ≥ 20。
	var kzj: Dictionary = dl.skills["kensei_zhaojia"]
	var ktrig: String = str(kzj.get("slot_swap_trigger", ""))
	var ktgt: String = str(kzj.get("slot_swap_target", ""))
	var kreq: Dictionary = kzj.get("slot_swap_requires", {})
	var k: Unit = _make_unit(dl.classes["kensei"])
	k.set_sword_qi(20)
	_check("剑圣 skill_ids 含拔刀", k.skill_ids.has(ktgt))
	_eq("剑圣印记0 → 招架槽是招架",
		k.get_visible_skill_id("kensei_zhaojia", ktrig, ktgt, kreq), "kensei_zhaojia")
	k.gain_random_mark()
	k.gain_random_mark()
	k.gain_random_mark()
	_eq("剑圣印记满 → 招架槽替换为拔刀（替换仍然生效）",
		k.get_visible_skill_id("kensei_zhaojia", ktrig, ktgt, kreq), "kensei_badao")
	# ③ 声明了替换但目标不在技能表内的一般情形（用不存在的技能 id 兜底验证）
	_eq("剑圣印记满 + 目标为不存在的技能 → 不替换",
		k.get_visible_skill_id("kensei_zhaojia", ktrig, "kensei_not_owned", kreq),
		"kensei_zhaojia")
	k.free()


# ── 6. 职业隔离（非剑圣 _qi_max==0，资源写入失效）────

func _test_class_isolation(_dl: Object) -> void:
	print("\n[6] 职业隔离（非剑圣无剑气）")
	var dummy: Dictionary = {
		"id": "dummy_nonsword",
		"name": "测试傀儡",
		"base_stats": {"HP": 20, "STR": 5, "DEX": 5, "SPD": 5, "LCK": 3, "DEF": 4, "RES": 2},
	}
	var u: Unit = _make_unit(dummy)
	_eq("非剑圣 _qi_max==0", u._qi_max, 0)
	u.set_sword_qi(5)
	_eq("非剑圣 set_sword_qi(5) 无效→0", u.sword_qi, 0)
	_eq("非剑圣 crit_bonus==0", u.crit_bonus, 0)
	u.free()


# ── 7. damage_calculator.gd 公式（确定性，用 preview/guaranteed）──

func _test_damage_formulas(dl: Object) -> void:
	print("\n[7] 伤害公式 / 必中必暴 / 暴击倍率")
	var atk: Unit = _make_unit(dl.classes["kensei"])
	var dft: Unit = _make_unit({
		"id": "target", "name": "靶子",
		"base_stats": {"HP": 999, "STR": 0, "DEX": 0, "SPD": 0, "LCK": 50, "DEF": 0, "RES": 0},
	})

	# 7a. 命中下限 1%（原 20%）：命中远低于回避时钳到 0.01
	atk.stats.dex = 0
	dft.stats.spd = 50  # 回避=100
	var pv_floor: Dictionary = DamageCalculator.preview_attack(atk, dft, {"weapon_hit": 0})
	_eq("命中下限==1%(非20%)", pv_floor["hit_percent"], 1)

	# 7b. 命中公式正常档(R1.2)：dex=10,weapon_hit=80; 目标 spd=15 → (80+20-30)/100=70%
	#     LCK 不参与命中与闪避(R2.1)，不是本公式的输入；下面 dft.stats.lck = 0 是给紧随其后的
	#     7c 暴击用例压低暴击回避用的(LCK 是暴击回避基值)，与本条命中断言无关。
	atk.stats.dex = 10
	dft.stats.spd = 15
	dft.stats.lck = 0
	var pv_hit: Dictionary = DamageCalculator.preview_attack(atk, dft, {"weapon_hit": 80})
	_eq("命中公式 ==70%", pv_hit["hit_percent"], 70)

	# 7c. 心眼注入暴击率（kensei_xinyan，gameplay-impl PR4）：sword_qi 0→70 时 crit_bonus =
	#     floor(70/20) = 3；心眼不再给技巧，所以没有经 DEX/2 折算的额外暴击。
	atk.set_sword_qi(0)
	var pv_c0: Dictionary = DamageCalculator.preview_attack(atk, dft, {"weapon_crit": 10})
	atk.set_sword_qi(70)
	var pv_c7: Dictionary = DamageCalculator.preview_attack(atk, dft, {"weapon_crit": 10})
	_eq("心眼: 剑气70 暴击率比0高3(= floor(70/20))",
		pv_c7["crit_percent"] - pv_c0["crit_percent"], 3)
	atk.set_sword_qi(0)

	# 7d. 居合必中：guaranteed_hit 无视回避 → 100%
	dft.stats.spd = 99
	var pv_gh: Dictionary = DamageCalculator.preview_attack(atk, dft, {"guaranteed_hit": true})
	_eq("guaranteed_hit → 命中100%", pv_gh["hit_percent"], 100)

	# 7e. 居合必暴（physical）：guaranteed_crit → 100%
	var pv_gc: Dictionary = DamageCalculator.preview_attack(atk, dft,
		{"damage_type": "physical", "guaranteed_crit": true})
	_eq("guaranteed_crit(physical) → 暴击100%", pv_gc["crit_percent"], 100)

	# 7f. pure 不参与暴击判定（R1.3，无条件）：guaranteed_crit 对 pure 无效
	var pv_pc_guar: Dictionary = DamageCalculator.preview_attack(atk, dft,
		{"damage_type": "pure", "guaranteed_crit": true})
	_eq("pure + guaranteed_crit → 暴击 0%", pv_pc_guar["crit_percent"], 0)
	var pv_pc_forced: Dictionary = DamageCalculator.preview_attack(atk, dft,
		{"damage_type": "pure", "guaranteed_crit": true, "enable_pure_crit": true})
	_eq("pure 无论传什么暴击开关都不暴 → 0%", pv_pc_forced["crit_percent"], 0)

	# ── 暴击倍率（用 resolve_attack 强制必中必暴，控制 base=20）──
	atk.clear_marks()
	atk.set_sword_qi(0)
	atk.stats.str_attr = 20
	dft.stats.def_attr = 0
	dft.stats.res = 0
	dft.stats.hp = 999

	# 7g. 基线暴击 1.5x：base 20 → 30
	var r_crit: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "physical", "skill_power": 0, "skill_multiplier": 1.0,
		 "guaranteed_hit": true, "guaranteed_crit": true})
	_check("暴击基线 1.5x (base20→30)", r_crit.crit and r_crit.damage == 30,
		"crit=%s dmg=%d" % [str(r_crit.crit), r_crit.damage])

	# 7h. 拔刀 crit_damage_mult=1.2（乘算）→ 1.5×1.2=1.8x：base 20 → 36
	var r_badao: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "physical", "skill_power": 0, "skill_multiplier": 1.0,
		 "guaranteed_hit": true, "guaranteed_crit": true, "crit_damage_mult": 1.2})
	_eq("拔刀 1.8x = 1.5×1.2 (base20→36)", r_badao.damage, 36)

	# 7h-2. R1.3 加算先于乘算：(1.5 + 0.5) × 1.2 = 2.4 → base 20 → 48。
	#       若写成先乘后加会得 (1.5×1.2)+0.5 = 2.3 → 46，本断言即为二者的分辨点。
	var r_mix: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "physical", "skill_power": 0, "skill_multiplier": 1.0,
		 "guaranteed_hit": true, "guaranteed_crit": true,
		 "crit_damage_bonus": 0.5, "crit_damage_mult": 1.2})
	_eq("加算先于乘算 (1.5+0.5)×1.2=2.4 (base20→48)", r_mix.damage, 48)

	# 7i. pure 不参与暴击判定（R1.3）：即使传 guaranteed_crit 与暴击倍率修正，
	#     也不进暴击乘区，base 20 → 20
	var r_pure: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "pure", "pure_atk_source": "phys", "skill_power": 0,
		 "skill_multiplier": 1.0, "guaranteed_hit": true, "guaranteed_crit": true,
		 "crit_damage_bonus": 0.5, "crit_damage_mult": 1.2})
	_check("pure 不暴击且无暴击乘区 (base20→20)", not r_pure.crit and r_pure.damage == 20,
		"crit=%s dmg=%d" % [str(r_pure.crit), r_pure.damage])

	# ── 基础伤害公式（非暴击；crit_rate=0 由目标高 LCK 保证）──
	dft.stats.lck = 50  # crit dodge 高 → 不会暴击

	# 7j. physical = max(0, STR+might-DEF)：20+0-0=20
	atk.stats.str_attr = 20
	dft.stats.def_attr = 0
	var r_phys: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "physical", "skill_power": 0, "guaranteed_hit": true})
	_check("physical base==20", not r_phys.crit and r_phys.damage == 20,
		"crit=%s dmg=%d" % [str(r_phys.crit), r_phys.damage])

	# 7k. 伤害下限 0（max(0, ·)）：STR1 - DEF100 → 0（防御足够高时命中也结算 0 伤害）
	atk.stats.str_attr = 1
	dft.stats.def_attr = 100
	var r_floor: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "physical", "skill_power": 0, "guaranteed_hit": true})
	_eq("physical 下限 max(0)==0", r_floor.damage, 0)

	# 7l. pure 无视防御：STR20, DEF100 → 仍 20
	atk.stats.str_attr = 20
	dft.stats.def_attr = 100
	var r_pureatk: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "pure", "pure_atk_source": "phys", "skill_power": 0, "guaranteed_hit": true})
	_eq("pure 无视防御==20", r_pureatk.damage, 20)

	_test_hybrid_formula(atk, dft)
	_test_final_damage_floor(atk, dft)

	atk.free()
	dft.free()


# ── 8. hybrid 基础伤害（裁决 A：各算一次再取平均）──────

## hybrid = ( max(0, STR + might - DEF) + max(0, MAG + might - RES) ) / 2。
## 与「一次性减去平均防御」的分辨点在于地板：任一侧被 max(0,·) 截断时两种写法结果不同。
## 复用 _test_damage_formulas 里已构造好的攻防单位（dft.lck=50 → 不会暴击）。
func _test_hybrid_formula(atk: Unit, dft: Unit) -> void:
	print("\n[8] hybrid 基础伤害（物理魔法各算一次再取平均）")
	atk.clear_marks()
	atk.set_sword_qi(0)
	dft.stats.hp = 999
	dft.stats.lck = 50

	# 8a. DEF > RES，两侧都不触地板：
	#     物理 30+0-20=10，魔法 20+0-4=16 → (10+16)/2 = 13
	atk.stats.str_attr = 30
	atk.stats.mag = 20
	dft.stats.def_attr = 20
	dft.stats.res = 4
	var r_a: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "hybrid", "skill_power": 0, "guaranteed_hit": true})
	_check("hybrid DEF>RES：(10+16)/2==13", not r_a.crit and r_a.damage == 13,
		"crit=%s dmg=%d" % [str(r_a.crit), r_a.damage])

	# 8b. DEF < RES，两侧仍都不触地板：
	#     物理 30+0-4=26，魔法 20+0-12=8 → (26+8)/2 = 17
	dft.stats.def_attr = 4
	dft.stats.res = 12
	var r_b: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "hybrid", "skill_power": 0, "guaranteed_hit": true})
	_check("hybrid DEF<RES：(26+8)/2==17", not r_b.crit and r_b.damage == 17,
		"crit=%s dmg=%d" % [str(r_b.crit), r_b.damage])

	# 8c. ★核心护栏：魔法一侧被地板截断。
	#     物理 30+0-10=20，魔法 20+0-100=-80 → 截断为 0 → (20+0)/2 = 10。
	#     若错写成「一次性减平均防御」= (30+20)/2 - (10+100)/2 = 25-55 < 0 → 0，
	#     两种写法在此处分叉（10 vs 0），本断言即为分辨点。
	dft.stats.def_attr = 10
	dft.stats.res = 100
	var r_c: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "hybrid", "skill_power": 0, "guaranteed_hit": true})
	_eq("hybrid 魔法侧触地板：(20+0)/2==10", r_c.damage, 10)

	# 8d. 物理一侧被地板截断（对称验证）：
	#     物理 30+0-100=-70 → 0，魔法 20+0-5=15 → (0+15)/2 = 7.5 → 向下取整 7。
	dft.stats.def_attr = 100
	dft.stats.res = 5
	var r_d: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "hybrid", "skill_power": 0, "guaranteed_hit": true})
	_eq("hybrid 物理侧触地板：(0+15)/2=7.5 → 向下取整 7", r_d.damage, 7)

	# 8e. 两侧都被截断 → 0（最终伤害下限 0，R1.1）
	dft.stats.def_attr = 100
	dft.stats.res = 100
	var r_e: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "hybrid", "skill_power": 0, "guaranteed_hit": true})
	_eq("hybrid 两侧都触地板==0", r_e.damage, 0)

	# 8f. skill_power 对物理、魔法两侧同时生效（无独立的 hybrid_might）：
	#     物理 30+6-20=16，魔法 20+6-4=22 → (16+22)/2 = 19
	dft.stats.def_attr = 20
	dft.stats.res = 4
	var r_f: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "hybrid", "skill_power": 6, "guaranteed_hit": true})
	_eq("hybrid skill_power 两侧共用：(16+22)/2==19", r_f.damage, 19)


# ── 9. 最终伤害向下取整（R1.8）────────────────────────

## R1.8：中间量不取整，最终量向下取整。旧实装用四舍五入（roundi），
## 于 2026-08-03 一并改为 floori；forecast 与结算两条路径必须同口径。
func _test_final_damage_floor(atk: Unit, dft: Unit) -> void:
	print("\n[9] 最终伤害向下取整（R1.8）")
	atk.clear_marks()
	atk.set_sword_qi(0)
	dft.stats.hp = 999
	dft.stats.lck = 50
	atk.stats.str_attr = 10
	dft.stats.def_attr = 0
	dft.stats.res = 0

	# base 10 × power 175% = 17.5 → 向下取整 17（四舍五入会得 18）
	var r_floor: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "physical", "skill_power": 0, "skill_multiplier": 1.75,
		 "guaranteed_hit": true})
	_eq("结算 17.5 → 向下取整 17（非四舍五入 18）", r_floor.damage, 17)

	# 预告路径同口径 → forecast == 实际伤害
	var pv_floor: Dictionary = DamageCalculator.preview_attack(atk, dft,
		{"damage_type": "physical", "skill_power": 0, "skill_multiplier": 1.75,
		 "guaranteed_hit": true})
	_eq("预告 17.5 → 向下取整 17（与结算同口径）", int(pv_floor["damage"]), 17)

	# 0.9 这类不足 1 的残值向下取整为 0（下限本就是 0，不产生 1 点保底伤害）
	var r_sub_one: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "physical", "skill_power": 0, "skill_multiplier": 0.09,
		 "guaranteed_hit": true})
	_eq("结算 0.9 → 向下取整 0", r_sub_one.damage, 0)
