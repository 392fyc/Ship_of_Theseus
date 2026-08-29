extends SceneTree
## VA-5 Task 2：行动资源仪表盘接线回归。
##
## 生产改动若删除 action_resources payload、跳过玩家态显示门控、打破 6px 间距或
## 遗漏浮窗避让枚举，本测试应失败。测试使用真实 TacticalScene 及其真实 BottomDashboard。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_action_resource_dashboard (行动资源仪表盘接线) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	var scene: Node = load("res://scenes/tactical/TacticalScene.tscn").instantiate()
	root.add_child(scene)

	var tactical_manager: Object = scene.tactical_manager
	var dashboard: BottomDashboard = scene._bottom_dashboard
	var current_unit: Unit = tactical_manager._get_dashboard_unit()
	_check("真实 TacticalScene 提供当前信息单位", current_unit != null)
	_check("真实 TacticalScene 创建 BottomDashboard", dashboard != null)
	if current_unit == null or dashboard == null:
		_finish(scene)
		return

	var data: Dictionary = tactical_manager.get_dashboard_data()
	var resources: Dictionary = data.get("action_resources", {})
	_eq("movement_used 透传", resources.get("movement_used"), current_unit.movement_used)
	_eq("standard_used 透传", resources.get("standard_used"), current_unit.standard_used)
	_eq("swift_used 透传", resources.get("swift_used"), current_unit.swift_used)

	dashboard.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	dashboard.size = Vector2(1280.0, 720.0)
	dashboard.update_state(data.merged({"visible": true, "show_actions": true}, true))
	var resource_bar: Control = dashboard.get("_action_resource_bar") as Control
	_check("玩家操作态创建行动资源栏", resource_bar != null)
	if resource_bar != null:
		_check("玩家操作态显示行动资源栏", resource_bar.visible)
		dashboard.update_state(data.merged({"visible": false}, true))
		_check("仪表盘隐藏时立即隐藏行动资源栏", not resource_bar.visible)
		dashboard.update_state(data.merged({"visible": true, "show_actions": true}, true))
		_check("资源栏与技能栏精确间隔 6 像素", is_equal_approx(
			dashboard._skill_bar.position.y - (resource_bar.position.y + resource_bar.size.y), 6.0))
		_check("资源栏与技能栏水平中心一致", is_equal_approx(
			resource_bar.position.x + resource_bar.size.x * 0.5,
			dashboard._skill_bar.position.x + dashboard._skill_bar.size.x * 0.5))

		var expected_top: float = dashboard.size.y
		for control: Control in [dashboard._info_panel, dashboard._relic_panel, dashboard._action_shell, dashboard._skill_bar, resource_bar]:
			if control.visible:
				expected_top = minf(expected_top, control.position.y)
		_check("浮窗避让取全部可见底栏控件的最小 Y", is_equal_approx(dashboard.get_content_top_y(), expected_top))

		for control: Control in [dashboard._info_panel, dashboard._relic_panel, dashboard._action_shell, dashboard._skill_bar]:
			control.visible = false
		_check("只保留行动资源栏时仍参与避让", is_equal_approx(
			dashboard.get_content_top_y(), resource_bar.position.y))

		dashboard.update_state(data.merged({"visible": true, "mode": "player", "show_actions": false}, true))
		_check("玩家模式但 show_actions=false 时隐藏行动资源栏", not resource_bar.visible)

		dashboard.update_state(data.merged({"visible": true, "mode": "enemy", "show_actions": true}, true))
		_check("敌方信息态隐藏行动资源栏", not resource_bar.visible)

		var missing_payload: Dictionary = data.duplicate(true)
		missing_payload.erase("action_resources")
		dashboard.update_state(missing_payload.merged({"visible": true, "mode": "player", "show_actions": true}, true))
		_check("缺失 action_resources 字段时隐藏行动资源栏", not resource_bar.visible)

		for missing_field: String in ["movement_used", "standard_used", "swift_used"]:
			var partial_resources: Dictionary = resources.duplicate(true)
			partial_resources.erase(missing_field)
			dashboard.update_state(data.merged({
				"visible": true,
				"mode": "player",
				"show_actions": true,
				"action_resources": partial_resources,
			}, true))
			_check("缺少 %s 时隐藏行动资源栏" % missing_field, not resource_bar.visible)

	_finish(scene)


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
