extends SceneTree

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_multi_action_resources (多行动点运行时) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	var unit: Unit = load("res://scenes/tactical/Unit.tscn").instantiate()
	root.add_child(unit)
	var initial_property_names: Array[String] = []
	for property: Dictionary in unit.get_property_list():
		initial_property_names.append(str(property.get("name", "")))
	_check("容量配置接口存在", unit.has_method("configure_action_resource_capacities"))
	for property_name: String in [
		"standard_capacity", "standard_remaining", "standard_spent_this_turn",
		"swift_capacity", "swift_remaining",
	]:
		_check("计数属性 %s 存在" % property_name, initial_property_names.has(property_name))
	if not unit.has_method("configure_action_resource_capacities") \
			or not initial_property_names.has("standard_capacity"):
		unit.free()
		_finish()
		return

	_eq("默认标准容量为 1", unit.standard_capacity, 1)
	_eq("默认标准剩余为 1", unit.standard_remaining, 1)
	_eq("默认迅捷容量为 1", unit.swift_capacity, 1)
	_eq("默认迅捷剩余为 1", unit.swift_remaining, 1)

	unit.configure_action_resource_capacities(2, 3)
	_eq("标准容量可设为 2", unit.standard_capacity, 2)
	_eq("标准剩余随配置回满", unit.standard_remaining, 2)
	_eq("迅捷容量可设为 3", unit.swift_capacity, 3)
	_eq("迅捷剩余随配置回满", unit.swift_remaining, 3)

	_check("首次标准消费前允许 before_attack",
		bool(GameAction.validate_timing_constraint(unit, "before_attack").get("ok", false)))
	GameAction.consume_action_cost(unit, "standard")
	_eq("首次标准消费只减一点", unit.standard_remaining, 1)
	_eq("首次标准消费立即关闭移动", unit.movement_used, true)
	_eq("首次标准消费累计一次", unit.standard_spent_this_turn, 1)
	_check("剩余一点时普通攻击仍可用",
		bool(GameAction.can_use_normal_attack(unit).get("ok", false)))
	_check("首次标准消费后拒绝 before_attack",
		not bool(GameAction.validate_timing_constraint(unit, "before_attack").get("ok", false)))
	_check("首次标准消费后允许 after_attack",
		bool(GameAction.validate_timing_constraint(unit, "after_attack").get("ok", false)))

	GameAction.consume_action_cost(unit, "standard")
	GameAction.consume_action_cost(unit, "standard")
	_eq("标准点不会低于零", unit.standard_remaining, 0)
	_eq("无点时累计消费不增加", unit.standard_spent_this_turn, 2)

	for index: int in 4:
		GameAction.consume_action_cost(unit, "swift")
	_eq("迅捷点不会低于零", unit.swift_remaining, 0)

	unit.reset_action_resources()
	_eq("回合开始标准回满", unit.standard_remaining, 2)
	_eq("回合开始迅捷回满", unit.swift_remaining, 3)
	_eq("回合开始清零标准消费历史", unit.standard_spent_this_turn, 0)
	_eq("回合开始恢复移动", unit.movement_used, false)

	unit.configure_action_resource_capacities(0, 4)
	_eq("标准容量下限为 1", unit.standard_capacity, 1)
	_eq("迅捷容量上限为 3", unit.swift_capacity, 3)

	unit.configure_action_resource_capacities(1, 1)
	unit.consume_swift_resource()
	var legacy_swift: Dictionary = {
		"id": "legacy_swift_probe",
		"action_cost": "swift",
		"timing_constraint": "any",
		"swift_limit": -1,
	}
	_check("旧 -1 字段不能绕过耗尽的迅捷点",
		not bool(GameAction.validate_skill_usage(unit, legacy_swift).get("ok", false)))

	var before_free: Array[int] = [
		unit.standard_remaining,
		unit.swift_remaining,
		unit.standard_spent_this_turn,
	]
	GameAction.consume_action_cost(unit, "free")
	_eq("free 不改变三项计数", [
		unit.standard_remaining,
		unit.swift_remaining,
		unit.standard_spent_this_turn,
	], before_free)

	var removed_properties: Array[String] = [
		"standard_used", "swift_used", "has_moved", "has_attacked", "has_used_swift",
	]
	var property_names: Array[String] = []
	for property: Dictionary in unit.get_property_list():
		property_names.append(str(property.get("name", "")))
	for property_name: String in removed_properties:
		_check("已移除属性 %s 不暴露" % property_name, not property_names.has(property_name))

	var removed_methods: Array[String] = [
		"_sync_legacy_action_flags", "restore_standard_resource", "restore_swift_resource",
	]
	for method_name: String in removed_methods:
		_check("已移除方法 %s 不暴露" % method_name, not unit.has_method(method_name))

	unit.free()
	_finish()


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


func _finish() -> void:
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for failure: String in _fails:
			print("  ✗ " + failure)
	else:
		print("OK")
	quit(0 if _fail == 0 else 1)
