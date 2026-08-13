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
	# 心眼数值（设计库 myrmidon_xinyan / kensei_xinyan 现行口径，2026-08-03 实装）：
	# 每 10 点剑气 → 暴击 +2；剑气 ≤ 上限 50% → 速度 +2，> 50% → 技巧 +2。
	_eq("sword_qi_config.crit_per_qi==2", cfg.get("crit_per_qi"), 2)
	_eq("sword_qi_config.qi_per_crit_pct==10", cfg.get("qi_per_crit_pct"), 10)
	_eq("sword_qi_config.qi_ratio_threshold_pct==50", cfg.get("qi_ratio_threshold_pct"), 50)
	_eq("sword_qi_config.low_qi_stat_key==SPD", cfg.get("low_qi_stat_key"), "SPD")
	_eq("sword_qi_config.low_qi_stat_bonus==2", cfg.get("low_qi_stat_bonus"), 2)
	_eq("sword_qi_config.high_qi_stat_key==DEX", cfg.get("high_qi_stat_key"), "DEX")
	_eq("sword_qi_config.high_qi_stat_bonus==2", cfg.get("high_qi_stat_bonus"), 2)
	# 旧的单一阈值键已随语义变化删除，不与新键并存
	_check("旧键 speed_threshold 已删除", not cfg.has("speed_threshold"))
	_check("旧键 speed_bonus 已删除", not cfg.has("speed_bonus"))
	_eq("sword_qi_config.mark_dex_bonus==2", cfg.get("mark_dex_bonus"), 2)
	_eq("sword_qi_config.mark_spd_bonus==2", cfg.get("mark_spd_bonus"), 2)
	_eq("sword_qi_config.mark_str_bonus==2", cfg.get("mark_str_bonus"), 2)
	_eq("sword_qi_config.mark_max==3", cfg.get("mark_max"), 3)
	_eq("skill_ids 长度==5", (cls.get("skill_ids", []) as Array).size(), 5)

	var zhanji: Dictionary = dl.skills.get("swordsman_zhanji", {})
	# 斩击产气 25（用户 2026-08-13 裁决，由 +10 提上来）：斩击是剑气经济的起点，
	# +10 撑不住「三刀攒满印记 + 一次拔刀 + 每回合招架」这个循环。设计库
	# kensei_zhanji / myrmidon_zhanji 的 effect 是权威，本行是它的镜像。
	_eq("斩击 qi_gain_on_hit==25", zhanji.get("qi_gain_on_hit"), 25)
	_eq("斩击 qi_cost==0", zhanji.get("qi_cost"), 0)
	_eq("斩击 power==100", zhanji.get("power"), 100)

	var yishan: Dictionary = dl.skills.get("swordsman_yishan", {})
	_eq("一闪 qi_cost==10", yishan.get("qi_cost"), 10)
	_eq("一闪 power==50", yishan.get("power"), 50)

	var zhaojia: Dictionary = dl.skills.get("swordsman_zhaojia", {})
	_eq("招架 qi_cost==10", zhaojia.get("qi_cost"), 10)
	_eq("招架 slot_swap_trigger==marks_full", zhaojia.get("slot_swap_trigger"), "marks_full")
	_eq("招架 slot_swap_target==swordsman_badao", zhaojia.get("slot_swap_target"), "swordsman_badao")

	var juhe: Dictionary = dl.skills.get("swordsman_juhe", {})
	_eq("居合 qi_cost==60", juhe.get("qi_cost"), 60)
	_eq("居合 guaranteed_hit==true", juhe.get("guaranteed_hit"), true)
	_eq("居合 guaranteed_crit==true", juhe.get("guaranteed_crit"), true)
	_eq("居合 qi_gain_on_kill==30", juhe.get("qi_gain_on_kill"), 30)
	_eq("居合 mark_gain==1", juhe.get("mark_gain"), 1)
	_eq("居合 ki_on_kill_cd_reduction==1", juhe.get("ki_on_kill_cd_reduction"), 1)
	_eq("居合 power==300", juhe.get("power"), 300)

	var badao: Dictionary = dl.skills.get("swordsman_badao", {})
	_eq("拔刀 requires_marks==3", badao.get("requires_marks"), 3)
	_eq("拔刀 mark_cost==3", badao.get("mark_cost"), 3)
	_eq("拔刀 qi_cost==20", badao.get("qi_cost"), 20)
	_eq("拔刀 crit_damage_mult==1.2（乘算通道）", badao.get("crit_damage_mult"), 1.2)
	_check("拔刀不再使用加算字段 crit_damage_bonus", not badao.has("crit_damage_bonus"))
	_eq("拔刀 slot_swap_provider==true", badao.get("slot_swap_provider"), true)
	_eq("拔刀 power==180", badao.get("power"), 180)


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
	print("\n[3] 心眼被动（暴击每10点+2 / 剑气比例分档属性）")
	var u: Unit = _make_unit(dl.classes["kensei"])
	var base_spd: int = u.stats.spd
	var base_dex: int = u.stats.dex
	# ── 暴击：floor(剑气/qi_per_crit_pct)×crit_per_qi → 每 10 点 +2 ──
	u.set_sword_qi(0)
	_eq("剑气0 → crit_bonus==0", u.crit_bonus, 0)
	u.set_sword_qi(9)
	_eq("剑气9 → crit_bonus==0(不足一档，向下取整)", u.crit_bonus, 0)
	u.set_sword_qi(10)
	_eq("剑气10 → crit_bonus==2(floor(10/10)×2)", u.crit_bonus, 2)
	u.set_sword_qi(70)
	_eq("剑气70 → crit_bonus==14(floor(70/10)×2)", u.crit_bonus, 14)
	u.set_sword_qi(100)
	_eq("剑气100(满) → crit_bonus==20(floor(100/10)×2)", u.crit_bonus, 20)
	# ── 剑气比例分档：≤上限50% 给速度，>50% 给技巧 ──
	u.set_sword_qi(0)
	_eq("剑气0(低气段) → SPD==基础+2", u.get_effective_stat("SPD"), base_spd + 2)
	_eq("剑气0(低气段) → DEX==基础(不给技巧)", u.get_effective_stat("DEX"), base_dex)
	u.set_sword_qi(50)
	_eq("剑气50(==上限50%，边界含等号) → SPD==基础+2",
		u.get_effective_stat("SPD"), base_spd + 2)
	_eq("剑气50 → DEX==基础", u.get_effective_stat("DEX"), base_dex)
	u.set_sword_qi(51)
	_eq("剑气51(>上限50%) → SPD==基础(不再给速度)",
		u.get_effective_stat("SPD"), base_spd)
	_eq("剑气51(高气段) → DEX==基础+2", u.get_effective_stat("DEX"), base_dex + 2)
	u.set_sword_qi(100)
	_eq("剑气100(高气段) → SPD==基础", u.get_effective_stat("SPD"), base_spd)
	_eq("剑气100(高气段) → DEX==基础+2(不叠加)",
		u.get_effective_stat("DEX"), base_dex + 2)
	# ── get_crit_value = weapon_crit + int(生效DEX/2) + crit_bonus ──
	# 剑气70 属高气段 → 生效 DEX = 基础+2，这 +2 再经 DEX/2 额外贡献暴击。
	u.set_sword_qi(70)
	_eq("剑气70 → get_crit_value(10)==10+int((基础DEX+2)/2)+14",
		u.get_crit_value(10), 10 + int((base_dex + 2) / 2.0) + 14)
	u.free()


# ── 4. 印记属性（心→DEX / 道→LCK / 势→STR 各+2）─────

func _test_mark_attributes(dl: Object) -> void:
	print("\n[4] 印记属性 +2")
	var u: Unit = _make_unit(dl.classes["kensei"])
	var base_spd: int = u.get_effective_stat("SPD")
	# 基线（base: DEX=9, LCK=5, STR=10）
	_eq("基线 DEX==9", u.get_effective_stat("DEX"), 9)
	_eq("基线 LCK==5", u.get_effective_stat("LCK"), 5)
	_eq("基线 STR==10", u.get_effective_stat("STR"), 10)
	# 心→DEX+2
	u.marks["心"] = true
	_eq("持心 → DEX==11", u.get_effective_stat("DEX"), 11)
	# 道→SPD+2
	# ⚠ 2026-08-03 更正：本条原先断言「道 → LCK+2」，钉的是引擎当时的实装，
	# 而设计库真源（/api/resources 的 mark 条目）逐字写的是「道为速度 SPD +2」。
	# 台账 D-8 已判定设计库为准（KB 那句是 2026-07-25 commit 8e09371 对齐生产库写入的），
	# 故引擎改为加 SPD，本断言随之改成验证正确口径。
	u.marks["道"] = true
	_eq("持道 → SPD+2", u.get_effective_stat("SPD"), base_spd + 2)
	_eq("持道 → LCK 不变", u.get_effective_stat("LCK"), 5)
	# 势→STR+2
	u.marks["势"] = true
	_eq("持势 → STR==12", u.get_effective_stat("STR"), 12)
	# clear_marks 后恢复
	u.clear_marks()
	_eq("clear后 DEX==9", u.get_effective_stat("DEX"), 9)
	_eq("clear后 STR==10", u.get_effective_stat("STR"), 10)
	_eq("clear后 SPD 复原", u.get_effective_stat("SPD"), base_spd)
	u.free()


# ── 5. 印记计数 + 满3→拔刀槽位替换 ───────────────────

func _test_slot_swap(dl: Object) -> void:
	print("\n[5] 印记计数 + 招架→拔刀槽位替换（数据驱动，替换规则读 JSON）")
	var u: Unit = _make_unit(dl.classes["kensei"])
	# 替换规则来自招架技能 JSON（slot_swap_trigger / slot_swap_target），不在代码硬编码
	var zj: Dictionary = dl.skills["swordsman_zhaojia"]
	var trig: String = str(zj.get("slot_swap_trigger", ""))
	var tgt: String = str(zj.get("slot_swap_target", ""))
	# 未满印记：招架槽显示招架
	_eq("印记0 招架槽→招架", u.get_visible_skill_id("swordsman_zhaojia", trig, tgt), "swordsman_zhaojia")
	# gain_random_mark ×3 → 满
	u.gain_random_mark()
	u.gain_random_mark()
	u.gain_random_mark()
	_eq("gain×3 → 印记数==3", u.get_mark_count(), 3)
	_check("印记满 is_marks_full()==true", u.is_marks_full())
	_eq("第4次 gain 返回空串", u.gain_random_mark(), "")
	# 满印记：招架槽按 JSON 声明替换为拔刀
	_eq("印记满 招架槽→拔刀", u.get_visible_skill_id("swordsman_zhaojia", trig, tgt), "swordsman_badao")
	# 无 slot_swap 声明的技能不替换
	_eq("斩击槽不替换", u.get_visible_skill_id("swordsman_zhanji", "", ""), "swordsman_zhanji")
	# 清印记后恢复招架
	u.clear_marks()
	_eq("clear后 招架槽→招架", u.get_visible_skill_id("swordsman_zhaojia", trig, tgt), "swordsman_zhaojia")
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
## 技能栏本身就是访问控制。剑士（myrmidon）共享剑气与剑意印记、也能靠斩击/居合把印记攒满，
## 但拔刀按 R2.4 是剑圣专属、不在其 skill_ids 内 → 招架槽必须保持为招架。
## 两侧都要覆盖：拥有 target 则替换生效（剑圣），不拥有则不替换（剑士）。
func _test_slot_swap_class_gate(dl: Object) -> void:
	print("\n[5b] 槽位替换职业校验（拔刀=剑圣专属，剑士不得替换）")
	var zj: Dictionary = dl.skills["swordsman_zhaojia"]
	var trig: String = str(zj.get("slot_swap_trigger", ""))
	var tgt: String = str(zj.get("slot_swap_target", ""))

	# ① 不拥有 target 的一侧：剑士
	var mm: Dictionary = dl.classes.get("myrmidon", {})
	_check("myrmidon 职业存在", not mm.is_empty())
	var m: Unit = _make_unit(mm)
	_check("剑士 skill_ids 不含拔刀", not m.skill_ids.has(tgt))
	_check("剑士持有招架（替换的 provider 槽确实在其技能表内）",
		m.skill_ids.has("swordsman_zhaojia"))
	m.gain_random_mark()
	m.gain_random_mark()
	m.gain_random_mark()
	_check("剑士印记同样能攒满（共享印记资源）", m.is_marks_full())
	_eq("剑士印记满 → 招架槽仍是招架（不得替换为剑圣专属拔刀）",
		m.get_visible_skill_id("swordsman_zhaojia", trig, tgt), "swordsman_zhaojia")
	m.free()

	# ② 拥有 target 的一侧：剑圣（对照组，确认校验没把正常替换一并挡掉）
	var k: Unit = _make_unit(dl.classes["kensei"])
	_check("剑圣 skill_ids 含拔刀", k.skill_ids.has(tgt))
	_eq("剑圣印记0 → 招架槽是招架",
		k.get_visible_skill_id("swordsman_zhaojia", trig, tgt), "swordsman_zhaojia")
	k.gain_random_mark()
	k.gain_random_mark()
	k.gain_random_mark()
	_eq("剑圣印记满 → 招架槽替换为拔刀（替换仍然生效）",
		k.get_visible_skill_id("swordsman_zhaojia", trig, tgt), "swordsman_badao")
	# ③ 声明了替换但目标不在技能表内的一般情形（用不存在的技能 id 兜底验证）
	_eq("剑圣印记满 + 目标为不存在的技能 → 不替换",
		k.get_visible_skill_id("swordsman_zhaojia", trig, "swordsman_not_owned"),
		"swordsman_zhaojia")
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

	# 7c. 心眼注入暴击率：sword_qi 0→70 时 crit_percent 增加 15，由两部分构成——
	#     ① crit_bonus = floor(70/10)×2 = 14；
	#     ② 剑气 70 > 上限 50% 属高气段 → 技巧 +2（DEX 10→12），经 int(DEX/2) 再 +1。
	#     旧口径下这里是 +7（每 10 点 +1，且高剑气只给速度不给技巧，无 ② 项）。
	atk.set_sword_qi(0)
	var pv_c0: Dictionary = DamageCalculator.preview_attack(atk, dft, {"weapon_crit": 10})
	atk.set_sword_qi(70)
	var pv_c7: Dictionary = DamageCalculator.preview_attack(atk, dft, {"weapon_crit": 10})
	_eq("心眼: 剑气70 暴击率比0高15(=14 暴击加成 + 1 技巧折算)",
		pv_c7["crit_percent"] - pv_c0["crit_percent"], 15)
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
		{"damage_type": "physical", "weapon_might": 0, "skill_multiplier": 1.0,
		 "guaranteed_hit": true, "guaranteed_crit": true})
	_check("暴击基线 1.5x (base20→30)", r_crit.crit and r_crit.damage == 30,
		"crit=%s dmg=%d" % [str(r_crit.crit), r_crit.damage])

	# 7h. 拔刀 crit_damage_mult=1.2（乘算）→ 1.5×1.2=1.8x：base 20 → 36
	var r_badao: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "physical", "weapon_might": 0, "skill_multiplier": 1.0,
		 "guaranteed_hit": true, "guaranteed_crit": true, "crit_damage_mult": 1.2})
	_eq("拔刀 1.8x = 1.5×1.2 (base20→36)", r_badao.damage, 36)

	# 7h-2. R1.3 加算先于乘算：(1.5 + 0.5) × 1.2 = 2.4 → base 20 → 48。
	#       若写成先乘后加会得 (1.5×1.2)+0.5 = 2.3 → 46，本断言即为二者的分辨点。
	var r_mix: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "physical", "weapon_might": 0, "skill_multiplier": 1.0,
		 "guaranteed_hit": true, "guaranteed_crit": true,
		 "crit_damage_bonus": 0.5, "crit_damage_mult": 1.2})
	_eq("加算先于乘算 (1.5+0.5)×1.2=2.4 (base20→48)", r_mix.damage, 48)

	# 7i. pure 不参与暴击判定（R1.3）：即使传 guaranteed_crit 与暴击倍率修正，
	#     也不进暴击乘区，base 20 → 20
	var r_pure: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "pure", "pure_atk_source": "phys", "weapon_might": 0,
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
		{"damage_type": "physical", "weapon_might": 0, "guaranteed_hit": true})
	_check("physical base==20", not r_phys.crit and r_phys.damage == 20,
		"crit=%s dmg=%d" % [str(r_phys.crit), r_phys.damage])

	# 7k. 伤害下限 0（max(0, ·)）：STR1 - DEF100 → 0（防御足够高时命中也结算 0 伤害）
	atk.stats.str_attr = 1
	dft.stats.def_attr = 100
	var r_floor: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "physical", "weapon_might": 0, "guaranteed_hit": true})
	_eq("physical 下限 max(0)==0", r_floor.damage, 0)

	# 7l. pure 无视防御：STR20, DEF100 → 仍 20
	atk.stats.str_attr = 20
	dft.stats.def_attr = 100
	var r_pureatk: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "pure", "pure_atk_source": "phys", "weapon_might": 0, "guaranteed_hit": true})
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
		{"damage_type": "hybrid", "weapon_might": 0, "guaranteed_hit": true})
	_check("hybrid DEF>RES：(10+16)/2==13", not r_a.crit and r_a.damage == 13,
		"crit=%s dmg=%d" % [str(r_a.crit), r_a.damage])

	# 8b. DEF < RES，两侧仍都不触地板：
	#     物理 30+0-4=26，魔法 20+0-12=8 → (26+8)/2 = 17
	dft.stats.def_attr = 4
	dft.stats.res = 12
	var r_b: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "hybrid", "weapon_might": 0, "guaranteed_hit": true})
	_check("hybrid DEF<RES：(26+8)/2==17", not r_b.crit and r_b.damage == 17,
		"crit=%s dmg=%d" % [str(r_b.crit), r_b.damage])

	# 8c. ★核心护栏：魔法一侧被地板截断。
	#     物理 30+0-10=20，魔法 20+0-100=-80 → 截断为 0 → (20+0)/2 = 10。
	#     若错写成「一次性减平均防御」= (30+20)/2 - (10+100)/2 = 25-55 < 0 → 0，
	#     两种写法在此处分叉（10 vs 0），本断言即为分辨点。
	dft.stats.def_attr = 10
	dft.stats.res = 100
	var r_c: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "hybrid", "weapon_might": 0, "guaranteed_hit": true})
	_eq("hybrid 魔法侧触地板：(20+0)/2==10", r_c.damage, 10)

	# 8d. 物理一侧被地板截断（对称验证）：
	#     物理 30+0-100=-70 → 0，魔法 20+0-5=15 → (0+15)/2 = 7.5 → 向下取整 7。
	dft.stats.def_attr = 100
	dft.stats.res = 5
	var r_d: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "hybrid", "weapon_might": 0, "guaranteed_hit": true})
	_eq("hybrid 物理侧触地板：(0+15)/2=7.5 → 向下取整 7", r_d.damage, 7)

	# 8e. 两侧都被截断 → 0（最终伤害下限 0，R1.1）
	dft.stats.def_attr = 100
	dft.stats.res = 100
	var r_e: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "hybrid", "weapon_might": 0, "guaranteed_hit": true})
	_eq("hybrid 两侧都触地板==0", r_e.damage, 0)

	# 8f. weapon_might 对物理、魔法两侧同时生效（无独立的 hybrid_might）：
	#     物理 30+6-20=16，魔法 20+6-4=22 → (16+22)/2 = 19
	dft.stats.def_attr = 20
	dft.stats.res = 4
	var r_f: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "hybrid", "weapon_might": 6, "guaranteed_hit": true})
	_eq("hybrid weapon_might 两侧共用：(16+22)/2==19", r_f.damage, 19)


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
		{"damage_type": "physical", "weapon_might": 0, "skill_multiplier": 1.75,
		 "guaranteed_hit": true})
	_eq("结算 17.5 → 向下取整 17（非四舍五入 18）", r_floor.damage, 17)

	# 预告路径同口径 → forecast == 实际伤害
	var pv_floor: Dictionary = DamageCalculator.preview_attack(atk, dft,
		{"damage_type": "physical", "weapon_might": 0, "skill_multiplier": 1.75,
		 "guaranteed_hit": true})
	_eq("预告 17.5 → 向下取整 17（与结算同口径）", int(pv_floor["damage"]), 17)

	# 0.9 这类不足 1 的残值向下取整为 0（下限本就是 0，不产生 1 点保底伤害）
	var r_sub_one: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "physical", "weapon_might": 0, "skill_multiplier": 0.09,
		 "guaranteed_hit": true})
	_eq("结算 0.9 → 向下取整 0", r_sub_one.damage, 0)
