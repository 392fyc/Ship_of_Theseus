extends SceneTree
## 剑圣资源引擎 headless 回归测试（批次1：单位级 + 伤害计算）
##
## 覆盖「真理源」代码（unit.gd / damage_calculator.gd）+ JSON 数据层：
##   居合必中必暴、满印记→拔刀槽位替换、心眼(暴击/速度)、印记属性+2、
##   暴击倍率(1.5x 基线 / 拔刀 2.0x / pure 固定 1.5x)、命中 1% 下限。
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
	var cls: Dictionary = dl.classes.get("swordsman", {})
	_check("swordsman 职业存在", not cls.is_empty())
	var cfg: Dictionary = cls.get("sword_qi_config", {})
	_eq("sword_qi_config.qi_max==10", cfg.get("qi_max"), 10)
	_eq("sword_qi_config.qi_initial==0", cfg.get("qi_initial"), 0)
	_eq("sword_qi_config.crit_per_qi==1", cfg.get("crit_per_qi"), 1)
	_eq("sword_qi_config.speed_threshold==7", cfg.get("speed_threshold"), 7)
	_eq("sword_qi_config.speed_bonus==1", cfg.get("speed_bonus"), 1)
	_eq("sword_qi_config.mark_dex_bonus==2", cfg.get("mark_dex_bonus"), 2)
	_eq("sword_qi_config.mark_lck_bonus==2", cfg.get("mark_lck_bonus"), 2)
	_eq("sword_qi_config.mark_str_bonus==2", cfg.get("mark_str_bonus"), 2)
	_eq("sword_qi_config.mark_max==3", cfg.get("mark_max"), 3)
	_eq("skill_ids 长度==5", (cls.get("skill_ids", []) as Array).size(), 5)

	var zhanji: Dictionary = dl.skills.get("swordsman_zhanji", {})
	_eq("斩击 qi_gain_on_hit==1", zhanji.get("qi_gain_on_hit"), 1)
	_eq("斩击 qi_cost==0", zhanji.get("qi_cost"), 0)
	_eq("斩击 power==100", zhanji.get("power"), 100)

	var yishan: Dictionary = dl.skills.get("swordsman_yishan", {})
	_eq("一闪 qi_cost==1", yishan.get("qi_cost"), 1)
	_eq("一闪 power==50", yishan.get("power"), 50)

	var zhaojia: Dictionary = dl.skills.get("swordsman_zhaojia", {})
	_eq("招架 qi_cost==1", zhaojia.get("qi_cost"), 1)
	_eq("招架 slot_swap_trigger==marks_full", zhaojia.get("slot_swap_trigger"), "marks_full")
	_eq("招架 slot_swap_target==swordsman_badao", zhaojia.get("slot_swap_target"), "swordsman_badao")

	var juhe: Dictionary = dl.skills.get("swordsman_juhe", {})
	_eq("居合 qi_cost==6", juhe.get("qi_cost"), 6)
	_eq("居合 guaranteed_hit==true", juhe.get("guaranteed_hit"), true)
	_eq("居合 guaranteed_crit==true", juhe.get("guaranteed_crit"), true)
	_eq("居合 qi_gain_on_kill==3", juhe.get("qi_gain_on_kill"), 3)
	_eq("居合 mark_gain==1", juhe.get("mark_gain"), 1)
	_eq("居合 ki_on_kill_cd_reduction==1", juhe.get("ki_on_kill_cd_reduction"), 1)
	_eq("居合 power==300", juhe.get("power"), 300)

	var badao: Dictionary = dl.skills.get("swordsman_badao", {})
	_eq("拔刀 requires_marks==3", badao.get("requires_marks"), 3)
	_eq("拔刀 mark_cost==3", badao.get("mark_cost"), 3)
	_eq("拔刀 qi_cost==2", badao.get("qi_cost"), 2)
	_eq("拔刀 crit_damage_bonus==1.5", badao.get("crit_damage_bonus"), 1.5)
	_eq("拔刀 slot_swap_provider==true", badao.get("slot_swap_provider"), true)
	_eq("拔刀 power==180", badao.get("power"), 180)


# ── 2. unit.gd 剑气资源（钳制 / 隔离写入）────────────

func _test_unit_resource(dl: Object) -> void:
	print("\n[2] unit.gd 剑气钳制")
	var u: Unit = _make_unit(dl.classes["swordsman"])
	_eq("初始 _qi_max==10", u._qi_max, 10)
	_eq("初始 sword_qi==0", u.sword_qi, 0)
	_eq("初始印记数==0", u.get_mark_count(), 0)
	u.set_sword_qi(5)
	_eq("set_sword_qi(5)→5", u.sword_qi, 5)
	u.set_sword_qi(99)
	_eq("set_sword_qi(99)→钳到10", u.sword_qi, 10)
	u.set_sword_qi(-3)
	_eq("set_sword_qi(-3)→钳到0", u.sword_qi, 0)
	u.free()


# ── 3. 心眼（暴击 + 速度阈值）────────────────────────

func _test_xinyan_passive(dl: Object) -> void:
	print("\n[3] 心眼被动")
	var u: Unit = _make_unit(dl.classes["swordsman"])
	# 暴击：每点剑气 +1 crit_bonus
	u.set_sword_qi(0)
	_eq("剑气0 → crit_bonus==0", u.crit_bonus, 0)
	u.set_sword_qi(7)
	_eq("剑气7 → crit_bonus==7", u.crit_bonus, 7)
	# get_crit_value 反映 crit_bonus（weapon_crit + dex/2 + crit_bonus）
	var base_dex_half: int = int(u.stats.dex / 2.0)
	_eq("get_crit_value(10)==10+dex/2+7", u.get_crit_value(10), 10 + base_dex_half + 7)
	# 速度阈值：剑气≥7 时 SPD +1（base SPD=8）
	u.set_sword_qi(6)
	_eq("剑气6 → SPD==8(无加成)", u.get_effective_stat("SPD"), 8)
	u.set_sword_qi(7)
	_eq("剑气7 → SPD==9(+1)", u.get_effective_stat("SPD"), 9)
	u.set_sword_qi(10)
	_eq("剑气10 → SPD==9(+1 不再叠)", u.get_effective_stat("SPD"), 9)
	u.free()


# ── 4. 印记属性（心→DEX / 道→LCK / 势→STR 各+2）─────

func _test_mark_attributes(dl: Object) -> void:
	print("\n[4] 印记属性 +2")
	var u: Unit = _make_unit(dl.classes["swordsman"])
	# 基线（base: DEX=9, LCK=5, STR=10）
	_eq("基线 DEX==9", u.get_effective_stat("DEX"), 9)
	_eq("基线 LCK==5", u.get_effective_stat("LCK"), 5)
	_eq("基线 STR==10", u.get_effective_stat("STR"), 10)
	# 心→DEX+2
	u.marks["心"] = true
	_eq("持心 → DEX==11", u.get_effective_stat("DEX"), 11)
	# 道→LCK+2
	u.marks["道"] = true
	_eq("持道 → LCK==7", u.get_effective_stat("LCK"), 7)
	# 势→STR+2
	u.marks["势"] = true
	_eq("持势 → STR==12", u.get_effective_stat("STR"), 12)
	# clear_marks 后恢复
	u.clear_marks()
	_eq("clear后 DEX==9", u.get_effective_stat("DEX"), 9)
	_eq("clear后 STR==10", u.get_effective_stat("STR"), 10)
	u.free()


# ── 5. 印记计数 + 满3→拔刀槽位替换 ───────────────────

func _test_slot_swap(dl: Object) -> void:
	print("\n[5] 印记计数 + 招架→拔刀槽位替换（数据驱动，替换规则读 JSON）")
	var u: Unit = _make_unit(dl.classes["swordsman"])
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
	var atk: Unit = _make_unit(dl.classes["swordsman"])
	var dft: Unit = _make_unit({
		"id": "target", "name": "靶子",
		"base_stats": {"HP": 999, "STR": 0, "DEX": 0, "SPD": 0, "LCK": 50, "DEF": 0, "RES": 0},
	})

	# 7a. 命中下限 1%（原 20%）：命中远低于回避时钳到 0.01
	atk.stats.dex = 0
	atk.stats.lck = 0
	dft.stats.spd = 50  # 回避=100
	var pv_floor: Dictionary = DamageCalculator.preview_attack(atk, dft, {"weapon_hit": 0})
	_eq("命中下限==1%(非20%)", pv_floor["hit_percent"], 1)

	# 7b. 命中公式正常档：dex=10,lck=0,weapon_hit=80; 目标 spd=15,lck=0 → (80+20-30)/100=70%
	atk.stats.dex = 10
	atk.stats.lck = 0
	dft.stats.spd = 15
	dft.stats.lck = 0
	var pv_hit: Dictionary = DamageCalculator.preview_attack(atk, dft, {"weapon_hit": 80})
	_eq("命中公式 ==70%", pv_hit["hit_percent"], 70)

	# 7c. 心眼注入暴击率：sword_qi 0→7 时 crit_percent 增加 7
	atk.set_sword_qi(0)
	var pv_c0: Dictionary = DamageCalculator.preview_attack(atk, dft, {"weapon_crit": 10})
	atk.set_sword_qi(7)
	var pv_c7: Dictionary = DamageCalculator.preview_attack(atk, dft, {"weapon_crit": 10})
	_eq("心眼: 剑气7 暴击率比0高7", pv_c7["crit_percent"] - pv_c0["crit_percent"], 7)
	atk.set_sword_qi(0)

	# 7d. 居合必中：guaranteed_hit 无视回避 → 100%
	dft.stats.spd = 99
	var pv_gh: Dictionary = DamageCalculator.preview_attack(atk, dft, {"guaranteed_hit": true})
	_eq("guaranteed_hit → 命中100%", pv_gh["hit_percent"], 100)

	# 7e. 居合必暴（physical）：guaranteed_crit → 100%
	var pv_gc: Dictionary = DamageCalculator.preview_attack(atk, dft,
		{"damage_type": "physical", "guaranteed_crit": true})
	_eq("guaranteed_crit(physical) → 暴击100%", pv_gc["crit_percent"], 100)

	# 7f. pure 必暴被拦截（未开 enable_pure_crit）
	var pv_pc_off: Dictionary = DamageCalculator.preview_attack(atk, dft,
		{"damage_type": "pure", "guaranteed_crit": true})
	_eq("pure guaranteed_crit 默认被拦截 → 0%", pv_pc_off["crit_percent"], 0)
	var pv_pc_on: Dictionary = DamageCalculator.preview_attack(atk, dft,
		{"damage_type": "pure", "guaranteed_crit": true, "enable_pure_crit": true})
	_eq("pure 开 enable_pure_crit → 100%", pv_pc_on["crit_percent"], 100)

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

	# 7h. 拔刀 crit_damage_bonus=1.5 → 3.0x：base 20 → 60（基础1.5x + 1.5）
	var r_badao: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "physical", "weapon_might": 0, "skill_multiplier": 1.0,
		 "guaranteed_hit": true, "guaranteed_crit": true, "crit_damage_bonus": 1.5})
	_eq("拔刀 3.0x (base20→60)", r_badao.damage, 60)

	# 7i. pure 暴击固定 1.5x，不受 crit_damage_bonus 影响：base 20 → 30
	var r_pure: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "pure", "pure_atk_source": "phys", "weapon_might": 0,
		 "skill_multiplier": 1.0, "guaranteed_hit": true, "guaranteed_crit": true,
		 "enable_pure_crit": true, "crit_damage_bonus": 1.5})
	_eq("pure 暴击固定1.5x (base20→30, 不吃+1.5)", r_pure.damage, 30)

	# ── 基础伤害公式（非暴击；crit_rate=0 由目标高 LCK 保证）──
	dft.stats.lck = 50  # crit dodge 高 → 不会暴击

	# 7j. physical = max(1, STR+might-DEF)：20+0-0=20
	atk.stats.str_attr = 20
	dft.stats.def_attr = 0
	var r_phys: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "physical", "weapon_might": 0, "guaranteed_hit": true})
	_check("physical base==20", not r_phys.crit and r_phys.damage == 20,
		"crit=%s dmg=%d" % [str(r_phys.crit), r_phys.damage])

	# 7k. max(1) 下限：STR1 - DEF100 → 1
	atk.stats.str_attr = 1
	dft.stats.def_attr = 100
	var r_floor: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "physical", "weapon_might": 0, "guaranteed_hit": true})
	_eq("physical 下限 max(1)==1", r_floor.damage, 1)

	# 7l. pure 无视防御：STR20, DEF100 → 仍 20
	atk.stats.str_attr = 20
	dft.stats.def_attr = 100
	var r_pureatk: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft,
		{"damage_type": "pure", "pure_atk_source": "phys", "weapon_might": 0, "guaranteed_hit": true})
	_eq("pure 无视防御==20", r_pureatk.damage, 20)

	atk.free()
	dft.free()
