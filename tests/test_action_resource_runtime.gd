extends SceneTree
## HUD-PROD-1C：真实 TacticalScene 行动资源刷新链回归。
##
## 每个状态变化均从生产入口触发：TurnManager.turn_started、真实移动、真实普攻与
## 真实迅捷技能。测试只监听 dashboard_state_changed，不主动发射或调用其内部包装方法。

const INVALID_CELL: Vector2i = Vector2i(-1, -1)
const INPUT_ACTION_PHASE: int = 2

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false
var _dashboard_signal_count: int = 0


func _initialize() -> void:
	print("=== test_action_resource_runtime (真实行动资源刷新链) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var scene: Node = load("res://scenes/tactical/TacticalScene.tscn").instantiate()
	root.add_child(scene)
	var tactical_manager: Object = scene.tactical_manager
	var dashboard: BottomDashboard = scene._bottom_dashboard
	var unit: Unit = tactical_manager._get_dashboard_unit()
	var enemy: Unit = _find_alive_dummy(tactical_manager)
	var strip: Control = dashboard.get("_action_resource_strip") as Control if dashboard != null and _has_property(dashboard, "_action_resource_strip") else null

	_check("真实 TacticalScene 提供当前玩家单位", unit != null and unit.faction == "player")
	_check("真实 TacticalScene 提供木桩单位", enemy != null and enemy.unit_id.begins_with("test_dummy"))
	_check("真实 TacticalScene 创建行动资源栏", strip != null)
	if unit == null or enemy == null or strip == null:
		_finish(scene)
		return
	_check("当前单位支持容量配置", unit.has_method("configure_action_resource_capacities"))
	if not unit.has_method("configure_action_resource_capacities"):
		_finish(scene)
		return

	tactical_manager.dashboard_state_changed.connect(_on_dashboard_state_changed)
	tactical_manager.debug_deterministic = true
	_check_runtime_state("场景初始化", tactical_manager, unit, strip, true, 1, 1, 1, 1)

	unit.configure_action_resource_capacities(2, 1)
	var before_turn_start: int = _dashboard_signal_count
	tactical_manager.turn_manager.current_unit = unit
	tactical_manager.turn_manager.turn_started.emit(unit)
	await process_frame
	_check("回合开始自动发出仪表盘刷新", _dashboard_signal_count > before_turn_start)
	_check_runtime_state("回合开始", tactical_manager, unit, strip, true, 2, 2, 1, 1)

	var move_target: Vector2i = _find_empty_neighbor(tactical_manager, unit.grid_position)
	_check("移动目标显式非空且有效", move_target != INVALID_CELL and tactical_manager.grid.is_valid(move_target))
	if move_target == INVALID_CELL:
		_finish(scene)
		return
	var before_move: int = _dashboard_signal_count
	await tactical_manager._execute_move(unit, move_target)
	await process_frame
	_check("移动完成自动发出仪表盘刷新", _dashboard_signal_count > before_move)
	_check_runtime_state("移动后", tactical_manager, unit, strip, false, 2, 2, 1, 1)

	enemy.stats.max_hp = 9999
	enemy.stats.hp = 9999
	enemy.stats.spd = 0
	enemy.stats.lck = 0
	enemy.crit_avoid_bonus = 999
	_check("攻击木桩设置为高血存活状态", enemy.stats.hp == 9999 and enemy.stats.is_alive())
	var enemy_target: Vector2i = _find_empty_neighbor(tactical_manager, unit.grid_position)
	_check("攻击木桩存在合法相邻格", enemy_target != INVALID_CELL)
	if enemy_target == INVALID_CELL:
		_finish(scene)
		return
	_reposition_unit(tactical_manager, enemy, enemy_target)
	_check("攻击木桩与攻击者合法相邻", _manhattan_distance(unit.grid_position, enemy.grid_position) == 1)
	var attack: GameAction = GameAction.make_attack(unit, enemy)
	_check("真实标准攻击动作可构造", attack != null)
	var attack_validation: Dictionary = GameAction.can_use_normal_attack(unit)
	_check("真实标准攻击动作当前有效", attack != null and bool(attack_validation.get("ok", false)))
	if attack == null:
		_finish(scene)
		return
	attack.data.merge(tactical_manager._build_basic_attack_action_data(unit, enemy), true)
	var before_attack: int = _dashboard_signal_count
	tactical_manager._execute_attack_from_input(attack)
	await process_frame
	_check("标准行动自动发出仪表盘刷新", _dashboard_signal_count > before_attack)
	_check("标准攻击后高血木桩仍存活", enemy.stats.is_alive())
	_eq("首次攻击后标准剩余一点", unit.standard_remaining, 1)
	_eq("首次攻击后累计消费一次", unit.standard_spent_this_turn, 1)
	_eq("首次攻击后移动失效", unit.movement_used, true)
	_eq("首次攻击后仍在行动阶段", tactical_manager.input_state, INPUT_ACTION_PHASE)
	_check("首次攻击后第二次普通攻击仍可用",
		bool(GameAction.can_use_normal_attack(unit).get("ok", false)))
	_check_runtime_state("首次标准行动后", tactical_manager, unit, strip, false, 2, 1, 1, 1)

	var second_attack: GameAction = GameAction.make_attack(unit, enemy)
	_check("第二次真实标准攻击动作可构造", second_attack != null)
	if second_attack == null:
		_finish(scene)
		return
	second_attack.data.merge(tactical_manager._build_basic_attack_action_data(unit, enemy), true)
	var before_second_attack: int = _dashboard_signal_count
	tactical_manager._execute_attack_from_input(second_attack)
	await process_frame
	_check("第二次标准行动自动发出仪表盘刷新", _dashboard_signal_count > before_second_attack)
	_check("第二次标准攻击后高血木桩仍存活", enemy.stats.is_alive())
	_eq("第二次攻击后标准点耗尽", unit.standard_remaining, 0)
	_check("标准点耗尽后普通攻击被拒绝",
		not bool(GameAction.can_use_normal_attack(unit).get("ok", false)))
	_check_runtime_state("第二次标准行动后", tactical_manager, unit, strip, false, 2, 0, 1, 1)

	var before_swift_turn: int = _dashboard_signal_count
	tactical_manager.turn_manager.current_unit = unit
	tactical_manager.turn_manager.turn_started.emit(unit)
	await process_frame
	_check("迅捷技能前的新回合自动刷新", _dashboard_signal_count > before_swift_turn)
	_check_runtime_state("迅捷技能前的新回合", tactical_manager, unit, strip, true, 2, 2, 1, 1)

	tactical_manager._selected_skill_id = "swordsman_zhaojia"
	var swift_action: GameAction = tactical_manager._build_skill_action(
		unit, unit.grid_position, unit)
	var swift_skill_data: Dictionary = tactical_manager._get_skill_data("swordsman_zhaojia")
	var swift_validation: Dictionary = GameAction.validate_skill_usage(unit, swift_skill_data)
	_check("真实招架动作显式非空", swift_action != null)
	_check("真实招架动作当前有效", swift_action != null and bool(swift_validation.get("ok", false)))
	if swift_action == null or not bool(swift_validation.get("ok", false)):
		_finish(scene)
		return
	var before_swift: int = _dashboard_signal_count
	tactical_manager._execute_skill_from_input(swift_action)
	await process_frame
	_check("迅捷技能自动发出仪表盘刷新", _dashboard_signal_count > before_swift)
	_check_runtime_state("迅捷技能后", tactical_manager, unit, strip, true, 2, 2, 1, 0)

	var before_final_turn: int = _dashboard_signal_count
	tactical_manager.turn_manager.current_unit = unit
	tactical_manager.turn_manager.turn_started.emit(unit)
	await process_frame
	_check("最后回合开始自动发出仪表盘刷新", _dashboard_signal_count > before_final_turn)
	_check_runtime_state("最后回合开始", tactical_manager, unit, strip, true, 2, 2, 1, 1)

	_finish(scene)


func _on_dashboard_state_changed() -> void:
	_dashboard_signal_count += 1


func _check_runtime_state(stage: String, manager: Object, unit: Unit, strip: Control,
		movement_available: bool, standard_capacity: int, standard_remaining: int,
		swift_capacity: int, swift_remaining: int) -> void:
	_eq("%s Unit.movement_used" % stage, unit.movement_used, not movement_available)
	_eq("%s Unit.standard_capacity" % stage, unit.standard_capacity, standard_capacity)
	_eq("%s Unit.standard_remaining" % stage, unit.standard_remaining, standard_remaining)
	_eq("%s Unit.swift_capacity" % stage, unit.swift_capacity, swift_capacity)
	_eq("%s Unit.swift_remaining" % stage, unit.swift_remaining, swift_remaining)
	_assert_view(stage, strip, maxi(0, unit.stats.mov), movement_available,
		standard_capacity, standard_remaining, swift_capacity, swift_remaining)
	_check("%s 地图 StatusIcons 不含 M/A/S" % stage, not _has_action_badges(manager))


func _assert_view(label: String, strip: Control, movement: int, available: bool,
		standard_capacity: int, standard_remaining: int, swift_capacity: int, swift_remaining: int) -> void:
	_check("%s 正式资源条可见" % label, strip.visible)
	var view: RefCounted = strip.get("_view") as RefCounted
	_check("%s 有私有 ViewData" % label, view != null)
	if view != null:
		_eq("%s 移动力" % label, view.get("movement_remaining"), movement)
		_eq("%s 移动可用" % label, view.get("movement_available"), available)
		_eq("%s 标准容量" % label, view.get("standard_capacity"), standard_capacity)
		_eq("%s 标准剩余" % label, view.get("standard_remaining"), standard_remaining)
		_eq("%s 迅捷容量" % label, view.get("swift_capacity"), swift_capacity)
		_eq("%s 迅捷剩余" % label, view.get("swift_remaining"), swift_remaining)
	_eq("%s 标准点阵" % label, _spent_states(strip.call("get_standard_pips") as Array),
		_expected_spent(standard_capacity, standard_remaining))
	_eq("%s 迅捷点阵" % label, _spent_states(strip.call("get_swift_pips") as Array),
		_expected_spent(swift_capacity, swift_remaining))
	var movement_value: Label = strip.get_node("Margin/MainRow/MovementZone/MovementCluster/MovementValue") as Label
	_eq("%s 移动数值保持" % label, movement_value.text, str(movement))
	var footprint: Control = strip.get_node("Margin/MainRow/MovementZone/MovementCluster/FootprintGlyph") as Control
	_eq("%s 足迹灰化" % label, bool(footprint.get("spent")), not available)


func _expected_spent(capacity: int, remaining: int) -> Array[bool]:
	var result: Array[bool] = []
	for index: int in capacity:
		result.append(index >= remaining)
	return result


func _spent_states(nodes: Array) -> Array[bool]:
	var result: Array[bool] = []
	for node: Variant in nodes:
		result.append(bool((node as Object).get("spent")))
	return result


func _has_action_badges(manager: Object) -> bool:
	for candidate: Variant in manager.units as Array:
		var unit: Unit = candidate as Unit
		var icons: Node2D = unit.get_node_or_null("StatusIcons") as Node2D if unit != null else null
		if icons == null:
			continue
		for child: Node in icons.get_children():
			var label: Label = child as Label
			if label != null and label.text in ["M", "A", "S"]:
				return true
	return false


func _has_property(value: Object, property_name: String) -> bool:
	for property: Dictionary in value.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _find_alive_dummy(tactical_manager: Object) -> Unit:
	for candidate: Unit in tactical_manager.units:
		if candidate.unit_id.begins_with("test_dummy") and candidate.stats.is_alive():
			return candidate
	return null


func _find_empty_neighbor(tactical_manager: Object,
		origin: Vector2i) -> Vector2i:
	for neighbor: Vector2i in tactical_manager.grid.get_neighbors(origin):
		var cell: Object = tactical_manager.grid.get_cell(neighbor)
		if cell != null and cell.is_passable() and cell.occupant == null:
			return neighbor
	return INVALID_CELL


func _reposition_unit(tactical_manager: Object, unit: Unit,
		target: Vector2i) -> void:
	var from: Vector2i = unit.grid_position
	tactical_manager.grid.move_unit(unit, from, target)
	unit.position = tactical_manager.grid.grid_to_world(target)


func _manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  ✓ " + name)
		return
	_fail += 1
	_fails.append(name + ("  [" + detail + "]" if detail != "" else ""))
	print("  ✗ " + name + ("  [" + detail + "]" if detail != "" else ""))


func _eq(name: String, actual: Variant, expected: Variant) -> void:
	_check(name, actual == expected, "期望 %s 实际 %s" % [str(expected), str(actual)])


func _finish(scene: Node) -> void:
	if is_instance_valid(scene):
		scene.free()
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for failure: String in _fails:
			print("  ✗ " + failure)
	else:
		print("OK")
	quit(0 if _fail == 0 else 1)
