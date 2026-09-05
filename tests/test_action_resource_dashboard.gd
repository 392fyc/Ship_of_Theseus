extends SceneTree
## 正式资源载荷与 BottomDashboard 接线回归。

const RESOURCE_FIELDS: Array[String] = [
	"movement_remaining", "movement_available", "standard_capacity",
	"standard_remaining", "swift_capacity", "swift_remaining",
]
const STRIP_SCENE_PATH := "res://scenes/tactical/hud/action_resource_strip.tscn"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
func _initialize() -> void:
	print("=== test_action_resource_dashboard ===")
	call_deferred("_run")


func _run() -> void:
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var manager: Object = scene.tactical_manager
	var dashboard: BottomDashboard = scene._bottom_dashboard
	var unit: Unit = manager._get_dashboard_unit() if manager != null else null
	_check("真实 TacticalScene 提供单位与仪表盘", manager != null and dashboard != null and unit != null)
	if manager == null or dashboard == null or unit == null:
		_finish(scene)
		return
	unit.configure_action_resource_capacities(2, 3)
	unit.consume_standard_resource()
	unit.consume_swift_resource()
	var data: Dictionary = manager.get_dashboard_data()
	var resources: Dictionary = data.get("action_resources", {}) as Dictionary
	_eq("正式载荷字段数严格为六", resources.size(), RESOURCE_FIELDS.size())
	for field: String in RESOURCE_FIELDS:
		_check("正式载荷含字段 %s" % field, resources.has(field))
	_eq("移动力来自当前单位", resources.get("movement_remaining"), maxi(0, unit.stats.mov))
	_eq("移动机会来自当前单位", resources.get("movement_available"), true)
	_eq("标准容量来自真实入口", resources.get("standard_capacity"), 2)
	_eq("标准剩余来自真实消费", resources.get("standard_remaining"), 1)
	_eq("迅捷容量来自真实入口", resources.get("swift_capacity"), 3)
	_eq("迅捷剩余来自真实消费", resources.get("swift_remaining"), 2)

	dashboard.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	dashboard.size = Vector2(1280.0, 720.0)
	dashboard.update_state(data.merged({"visible": true, "mode": "player", "show_actions": true}, true))
	await process_frame
	_check("仪表盘提供正式资源条属性", _has_property(dashboard, "_action_resource_strip"))
	if _has_property(dashboard, "_action_resource_strip"):
		var strip: Control = dashboard.get("_action_resource_strip") as Control
		_check("正式资源条来自冻结场景", strip != null and strip.scene_file_path == STRIP_SCENE_PATH)
		_check("玩家态显示正式资源条", strip != null and strip.visible)
		if strip != null:
			_eq("与技能栏净距为六像素", dashboard._skill_bar.position.y - (strip.position.y + strip.size.y), 6.0)
			_eq("与技能栏水平中心一致", strip.position.x + strip.size.x * 0.5,
				dashboard._skill_bar.position.x + dashboard._skill_bar.size.x * 0.5)
			_assert_invalid_payloads_hide(dashboard, strip, data)
	_finish(scene)


func _assert_invalid_payloads_hide(dashboard: BottomDashboard, strip: Control, data: Dictionary) -> void:
	for field: String in RESOURCE_FIELDS:
		var invalid: Dictionary = data.duplicate(true)
		(invalid["action_resources"] as Dictionary).erase(field)
		dashboard.update_state(invalid.merged({"visible": true, "mode": "player", "show_actions": true}, true))
		_check("缺少 %s 时隐藏" % field, not strip.visible)
	for replacement: Dictionary in [
		{"movement_remaining": 1.5}, {"movement_available": 1}, {"standard_capacity": 0},
		{"standard_remaining": 3}, {"swift_capacity": 4}, {"swift_remaining": -1},
	]:
		var invalid: Dictionary = data.duplicate(true)
		(invalid["action_resources"] as Dictionary).merge(replacement, true)
		dashboard.update_state(invalid.merged({"visible": true, "mode": "player", "show_actions": true}, true))
		_check("类型或范围无效时隐藏", not strip.visible)


func _has_property(value: Object, property_name: String) -> bool:
	for property: Dictionary in value.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _finish(scene: Node) -> void:
	if is_instance_valid(scene):
		scene.free()
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		for failure: String in _fails:
			print("  ✗ " + failure)
	else:
		print("OK")
	quit(0 if _fail == 0 else 1)


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
