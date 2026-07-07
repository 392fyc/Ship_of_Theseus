extends SceneTree
## P0 修复回归（2026-06-30，源自核心战斗循环实证 sot-swordsman-resource-experiment）
##
## ① 资源门槛强制：validate_skill_usage 现校验 qi_cost / requires_marks / mark_cost。
##    居合剑气不足、拔刀印记不足、一闪剑气不足 → 拦截，不执行、不消耗。
## ② 拔刀印记消耗推迟到伤害结算之后：拔刀吃到自身正在消耗的势(STR+2) → 非暴击 29 而非 25。
##
## 经正式 TacticalScene 走 _build_skill_action → _execute_skill_action 真实链路。
## 坑规避：断言放 _process 首帧；tm/action 用 Object。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_swordsman_p0_fixes (P0 资源门槛 + 拔刀印记时序) ===")


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
	if tm.turn_manager != null:
		tm.turn_manager.stop()
	tm.input_state = 2  # ACTION_PHASE
	var sword: Unit = _find(tm, "swordsman")
	var dummy: Unit = _find_enemy(tm)
	if sword == null or dummy == null:
		_check("场景含剑圣+敌人", false)
		_finish(scene)
		return
	# 木桩化：必中、不死、不暴（确定性）
	dummy.stats.spd = 0
	dummy.stats.lck = 0
	dummy.stats.def_attr = 2
	dummy.stats.max_hp = 9999
	dummy.stats.hp = 9999
	dummy.crit_avoid_bonus = 999  # 压死暴击 → 确定性非暴击
	_place_adjacent(tm, sword, dummy)

	_test_gate_juhe(tm, sword, dummy)
	_test_gate_badao(tm, sword, dummy)
	_test_gate_yishan(tm, sword)
	_test_badao_mark_timing(tm, sword, dummy)

	_finish(scene)


# ── P0-① 居合剑气门槛 ────────────────────────────────────

func _test_gate_juhe(tm: Object, sword: Unit, dummy: Unit) -> void:
	print("\n[①a] 居合剑气门槛：qi<60 拦截、qi>=60 放行")
	var data: Dictionary = tm._get_skill_data("swordsman_juhe")
	_reset(sword)
	sword.set_sword_qi(50)  # < qi_cost 60
	var v_low: Dictionary = GameAction.validate_skill_usage(sword, data)
	_check("居合 qi=50 validate ok=false", not bool(v_low.get("ok", true)))
	tm._selected_skill_id = "swordsman_juhe"
	var act_low: Object = tm._build_skill_action(sword, dummy.grid_position, dummy)
	var ok_low: bool = tm._execute_skill_action(act_low)
	_check("居合 qi=50 execute 返回 false", not ok_low)
	_eq("居合被拦截 → 剑气未消耗(仍50)", sword.sword_qi, 50)
	_eq("居合被拦截 → 未进冷却", sword.get_skill_cooldown("swordsman_juhe"), 0)

	_reset(sword)
	sword.set_sword_qi(60)  # == qi_cost
	var v_ok: Dictionary = GameAction.validate_skill_usage(sword, data)
	_check("居合 qi=60 validate ok=true", bool(v_ok.get("ok", false)))
	tm._selected_skill_id = "swordsman_juhe"
	var act_ok: Object = tm._build_skill_action(sword, dummy.grid_position, dummy)
	_check("居合 qi=60 execute 返回 true", tm._execute_skill_action(act_ok))


# ── P0-① 拔刀印记门槛 ────────────────────────────────────

func _test_gate_badao(tm: Object, sword: Unit, dummy: Unit) -> void:
	print("\n[①b] 拔刀印记门槛：印记<3 拦截、满3 放行")
	var data: Dictionary = tm._get_skill_data("swordsman_badao")
	_reset(sword)
	sword.set_sword_qi(20)  # >= qi_cost 20（隔离出印记不足的失败原因）
	sword.clear_marks()
	sword.marks["心"] = true
	sword.marks["道"] = true  # 仅2枚 < requires_marks 3
	var v_low: Dictionary = GameAction.validate_skill_usage(sword, data)
	_check("拔刀 印记=2 validate ok=false", not bool(v_low.get("ok", true)))
	tm._selected_skill_id = "swordsman_badao"
	var act_low: Object = tm._build_skill_action(sword, dummy.grid_position, dummy)
	_check("拔刀 印记=2 execute 返回 false", not tm._execute_skill_action(act_low))
	_eq("拔刀被拦截 → 印记未消耗(仍2)", sword.get_mark_count(), 2)

	_reset(sword)
	sword.set_sword_qi(20)  # >= qi_cost 20
	sword.clear_marks()
	sword.marks["心"] = true
	sword.marks["道"] = true
	sword.marks["势"] = true  # 满3
	var v_ok: Dictionary = GameAction.validate_skill_usage(sword, data)
	_check("拔刀 满印记 validate ok=true", bool(v_ok.get("ok", false)))


# ── P0-① 一闪剑气门槛 ────────────────────────────────────

func _test_gate_yishan(tm: Object, sword: Unit) -> void:
	print("\n[①c] 一闪剑气门槛：qi=0 拦截")
	var data: Dictionary = tm._get_skill_data("swordsman_yishan")
	_reset(sword)
	sword.set_sword_qi(0)  # < qi_cost 1
	var v: Dictionary = GameAction.validate_skill_usage(sword, data)
	_check("一闪 qi=0 validate ok=false", not bool(v.get("ok", true)))


# ── P0-② 拔刀印记消耗时序 ────────────────────────────────

func _test_badao_mark_timing(tm: Object, sword: Unit, dummy: Unit) -> void:
	print("\n[②] 拔刀伤害结算后才扣印记 → 吃到自身势(STR+2)")
	_reset(sword)
	sword.set_sword_qi(20)            # >= qi_cost 20
	sword.clear_marks()
	sword.marks["心"] = true
	sword.marks["道"] = true
	sword.marks["势"] = true          # 势 → STR +2 → 10→12
	# 期望非暴击伤害 = (STR12 + weapon_might6 − def2) × power1.8 = 16 × 1.8 = 28.8 → 29
	# 若印记在伤害前被扣（旧 bug），STR=10 → (10+6−2)×1.8 = 25.2 → 25
	dummy.stats.hp = dummy.stats.max_hp
	var hp_before: int = dummy.stats.hp
	tm._selected_skill_id = "swordsman_badao"
	var act: Object = tm._build_skill_action(sword, dummy.grid_position, dummy)
	_check("拔刀 满印记 execute 返回 true", tm._execute_skill_action(act))
	var dmg: int = hp_before - dummy.stats.hp
	_eq("拔刀非暴击伤害=29（吃到势，非旧 bug 的 25）", dmg, 29)
	_eq("拔刀施放后印记清空(get_mark_count==0)", sword.get_mark_count(), 0)


# ── 工具 ─────────────────────────────────────────────

func _reset(sword: Unit) -> void:
	sword.standard_used = false
	sword.movement_used = false
	sword.swift_used = false
	sword.skill_cooldowns.clear()
	sword.set_sword_qi(0)
	sword.clear_marks()


func _check(name: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		_fails.append(name)
		print("  ✗ " + name)


func _eq(name: String, actual: Variant, expected: Variant) -> void:
	_check(name + ("  [期望 %s 实际 %s]" % [str(expected), str(actual)] if actual != expected else ""),
		actual == expected)


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


func _find_empty_neighbor(tm: Object, origin: Vector2i) -> Vector2i:
	for nb: Vector2i in tm.grid.get_neighbors(origin):
		var c: Object = tm.grid.get_cell(nb)
		if c != null and c.is_passable() and c.occupant == null:
			return nb
	return Vector2i(-1, -1)


func _place_adjacent(tm: Object, mover: Unit, target: Unit) -> void:
	var dest: Vector2i = _find_empty_neighbor(tm, target.grid_position)
	if dest == Vector2i(-1, -1):
		return
	var old_cell: Object = tm.grid.get_cell(mover.grid_position)
	if old_cell != null and old_cell.occupant == mover:
		old_cell.occupant = null
	tm.grid.place_unit(mover, dest)


func _finish(scene: Node) -> void:
	if is_instance_valid(scene):
		scene.free()
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		for f: String in _fails:
			print("  ✗ " + f)
	else:
		print("OK")
	quit(0 if _fail == 0 else 1)
