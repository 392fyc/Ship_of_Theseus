extends SceneTree
## R1.1 共用伤害结算回归（gameplay-impl PR1，gap-list S1+S3）
##
## ① 伤害公式（DamageCalculator.preview_attack，不掷骰、不暴击）：
##    技能威力加算与 0 地板、技能系数、hybrid 两侧各自地板再平均、「以力量计算」的魔法、
##    纯粹伤害无视防御、普通天赋提升（相加后乘）与总增总降（逐项相乘）两层倍率。
## ② tactical_manager 接线：设计库伤害条目驱动的 payload 不含武器威力（R1.7），
##    条目枚举（必定命中 / 不可暴击 / 力量 / 纯粹）正确映射；segments>1 判为不支持；
##    设计库外的旧技能按等价桥接，skill_power == 原武器威力、系数 == power/100。
## ③ 挂载护栏：TacticalScene 的 tactical_manager 脚本真的挂上且是期望的那一个。

const TEST_SKILL_ID: String = "test_r11_entry_skill"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_damage_r11 (R1.1 共用伤害结算) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	var scene: Node = load("res://scenes/tactical/TacticalScene.tscn").instantiate()
	root.add_child(scene)
	var tm: Object = scene.tactical_manager
	_check("tactical_manager 脚本已挂载", tm != null and tm.get_script() != null)
	if tm == null or tm.get_script() == null:
		_finish(scene)
		return
	_eq("tactical_manager 挂的是 tactical_manager.gd",
		(tm.get_script() as Script).resource_path, "res://scripts/core/tactical_manager.gd")
	if tm.turn_manager != null:
		tm.turn_manager.stop()
	tm.input_state = 2  # ACTION_PHASE
	var sword: Unit = _find(tm, "kensei")
	var dummy: Unit = _find_enemy(tm)
	if sword == null or dummy == null:
		_check("场景含剑圣+敌人", false)
		_finish(scene)
		return
	_place_adjacent(tm, sword, dummy)

	_test_formula(sword, dummy)
	_test_entry_payload(tm, sword, dummy)
	_test_legacy_bridge(tm, sword, dummy)

	_finish(scene)


# ── ① 公式 ───────────────────────────────────────────

func _test_formula(atk: Unit, dfn: Unit) -> void:
	print("\n[①] R1.1 公式")
	atk.stats.str_attr = 10
	atk.stats.mag = 4
	dfn.stats.def_attr = 6
	dfn.stats.res = 2
	var s: int = atk.get_effective_stat("STR")
	var m: int = atk.get_effective_stat("MAG")
	var d: int = dfn.get_effective_stat("DEF")
	var r: int = dfn.get_effective_stat("RES")

	_eq("物理：力量 + 技能威力 − 防御",
		_dmg(atk, dfn, {"damage_type": "physical", "skill_power": 3}), maxi(0, s + 3 - d))
	_eq("物理 0 地板：防御高于力量 + 威力时为 0",
		_dmg(atk, dfn, {"damage_type": "physical", "skill_power": -999}), 0)
	_eq("系数在地板之后乘：(力量 + 4 − 防御) × 1.5 向下取整",
		_dmg(atk, dfn, {"damage_type": "physical", "skill_power": 4, "skill_multiplier": 1.5}),
		floori(float(maxi(0, s + 4 - d)) * 1.5))
	_eq("魔法默认读魔力",
		_dmg(atk, dfn, {"damage_type": "magical", "skill_power": 5}), maxi(0, m + 5 - r))
	_eq("「以力量计算」的魔法：力量 + 威力 − 魔防",
		_dmg(atk, dfn, {"damage_type": "magical", "skill_power": 5, "base_attribute": "STR"}),
		maxi(0, s + 5 - r))
	var phys_part: int = maxi(0, s + 1 - d)
	var mag_part: int = maxi(0, m + 1 - r)
	_eq("hybrid：两侧各自地板后平均",
		_dmg(atk, dfn, {"damage_type": "hybrid", "skill_power": 1}),
		floori(float(phys_part + mag_part) / 2.0))
	_eq("纯粹：无视防御，以力量计算",
		_dmg(atk, dfn, {"damage_type": "pure", "skill_power": 2, "base_attribute": "STR"}), s + 2)

	var base: float = float(maxi(0, s + 10 - d))
	_eq("普通天赋提升相加后乘：(1 + 20% + 30%)",
		_dmg(atk, dfn, {"damage_type": "physical", "skill_power": 10,
			"damage_increase_pcts": [20, 30]}), floori(base * 1.5))
	_eq("总增总降逐项相乘：× 1.2 × 0.5",
		_dmg(atk, dfn, {"damage_type": "physical", "skill_power": 10,
			"damage_total_modifiers": [1.2, 0.5]}), floori(base * 1.2 * 0.5))
	_eq("两层合计：(1 + 50%) × 0.8",
		_dmg(atk, dfn, {"damage_type": "physical", "skill_power": 10,
			"damage_increase_pcts": [50], "damage_total_modifiers": [0.8]}),
		floori(base * 1.5 * 0.8))
	_eq("两层缺省时倍率为 1",
		DamageCalculator.outer_layer_multiplier({}), 1.0)


func _dmg(atk: Unit, dfn: Unit, data: Dictionary) -> int:
	return int(DamageCalculator.preview_attack(atk, dfn, data).get("damage", -1))


# ── ② 条目驱动 payload ───────────────────────────────

func _test_entry_payload(tm: Object, sword: Unit, dummy: Unit) -> void:
	print("\n[②] 设计库伤害条目 → payload")
	var dl: Node = root.get_node_or_null("/root/DataLoader")
	_check("取到 DataLoader autoload", dl != null)
	if dl == null:
		return
	var skill: Dictionary = {
		"name": "条目测试", "action_cost": "standard",
		"range": {"type": "diamond", "min": 1, "max": 1},
		"area": {"type": "single"},
		"damage_type": "魔法",
		"damage_entries": [
			{"sort": 1, "power": 9, "coefficient": 2.0, "hit_bonus": 0,
				"hit_mode": "正常", "crit_mode": "正常", "crit_multiplier": 1.0,
				"base_attribute": "默认", "damage_type": null, "segments": 1},
			{"sort": 0, "power": 4, "coefficient": 1.6, "hit_bonus": 7,
				"hit_mode": "必定命中", "crit_mode": "不可暴击", "crit_multiplier": 1.2,
				"base_attribute": "力量", "damage_type": "纯粹", "segments": 1},
		],
	}
	dl.skills[TEST_SKILL_ID] = skill
	_check("有伤害条目的技能视为可用", tm._is_supported_runtime_skill(skill))
	tm._selected_skill_id = TEST_SKILL_ID
	var act: Object = tm._build_skill_action(sword, dummy.grid_position, dummy)
	_check("构建出技能动作", act != null)
	if act != null:
		var data: Dictionary = act.data
		var profile: Dictionary = tm._get_unit_basic_attack_profile(sword)
		_eq("按 sort 取第一条：skill_power == 条目威力 4（不加武器威力）",
			data.get("skill_power"), 4.0)
		_check("payload 不含 weapon_might", not data.has("weapon_might"))
		_eq("skill_multiplier == 条目系数", data.get("skill_multiplier"), 1.6)
		_eq("条目 damage_type「纯粹」→ pure", data.get("damage_type"), "pure")
		_eq("「力量」→ base_attribute STR", data.get("base_attribute"), "STR")
		_eq("「必定命中」→ guaranteed_hit", data.get("guaranteed_hit"), true)
		_eq("「不可暴击」→ disable_crit", data.get("disable_crit"), true)
		_eq("crit_multiplier → crit_damage_mult", data.get("crit_damage_mult"), 1.2)
		_eq("命中以主手武器为底 + 条目 hit_bonus",
			data.get("weapon_hit"), int(profile.get("weapon_hit", 0)) + 7)

	var inherit_skill: Dictionary = skill.duplicate(true)
	(inherit_skill["damage_entries"] as Array).remove_at(1)
	dl.skills[TEST_SKILL_ID] = inherit_skill
	var act2: Object = tm._build_skill_action(sword, dummy.grid_position, dummy)
	if act2 != null:
		_eq("条目未写伤害类型时继承技能「魔法」→ magical", act2.data.get("damage_type"), "magical")
		_check("「默认」不写 base_attribute", not act2.data.has("base_attribute"))

	var multi: Dictionary = inherit_skill.duplicate(true)
	(multi["damage_entries"] as Array)[0]["segments"] = 3
	_check("segments>1 暂判为不支持", not tm._is_supported_runtime_skill(multi))
	dl.skills.erase(TEST_SKILL_ID)


# ── ② 旧技能等价桥接 ─────────────────────────────────

func _test_legacy_bridge(tm: Object, sword: Unit, dummy: Unit) -> void:
	print("\n[②'] 设计库外的旧技能：等价桥接")
	var profile: Dictionary = tm._get_unit_basic_attack_profile(sword)
	var might: int = int(profile.get("weapon_might", 0))
	tm._selected_skill_id = "swordsman_zhanji"
	var act: Object = tm._build_skill_action(sword, dummy.grid_position, dummy)
	_check("构建出旧技能动作", act != null)
	if act != null:
		var skill: Dictionary = tm._get_skill_data("swordsman_zhanji")
		_eq("旧技能 skill_power == 原武器威力", act.data.get("skill_power"), float(might))
		_eq("旧技能系数 == power/100", act.data.get("skill_multiplier"),
			float(skill.get("power", 100)) / 100.0)
		_check("旧技能 payload 不含 weapon_might", not act.data.has("weapon_might"))
	var basic: Dictionary = tm._build_basic_attack_action_data(sword, dummy)
	_eq("普通攻击 skill_power == 原武器威力", basic.get("skill_power"), float(might))


# ── 工具 ─────────────────────────────────────────────

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


func _find(tm: Object, uid: String) -> Unit:
	for u: Unit in tm.units:
		if u.unit_id == uid:
			return u
	return null


func _find_enemy(tm: Object) -> Unit:
	for u: Unit in tm.units:
		if u.faction == "enemy" and u.stats.is_alive():
			return u
	return null


func _place_adjacent(tm: Object, mover: Unit, target: Unit) -> void:
	for nb: Vector2i in tm.grid.get_neighbors(target.grid_position):
		var c: Object = tm.grid.get_cell(nb)
		if c == null or not c.is_passable() or c.occupant != null:
			continue
		var old_cell: Object = tm.grid.get_cell(mover.grid_position)
		if old_cell != null and old_cell.occupant == mover:
			old_cell.occupant = null
		c.occupant = mover
		mover.grid_position = nb
		return


func _finish(scene: Node) -> void:
	scene.queue_free()
	print("\n=== 结果：%d 通过，%d 失败 ===" % [_pass, _fail])
	for f: String in _fails:
		print("  ✗ " + f)
	quit(0 if _fail == 0 else 1)
