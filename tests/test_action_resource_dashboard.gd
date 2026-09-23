extends SceneTree
## VA-5 Task 2：行动资源仪表盘接线回归。
##
## 生产改动若删除 action_resources payload、跳过玩家态显示门控、打破 6px 间距或
## 遗漏浮窗避让枚举，本测试应失败。测试使用真实 TacticalScene 及其 M2 HUD。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_action_resource_dashboard (行动资源仪表盘接线) ===")


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
	var dashboard: HudM2RuntimeDashboard = scene._bottom_dashboard
	var current_unit: Unit = tactical_manager._get_dashboard_unit()
	_check("真实 TacticalScene 提供当前信息单位", current_unit != null)
	_check("真实 TacticalScene 创建 M2 HUD", dashboard != null)
	if current_unit == null or dashboard == null:
		_finish(scene)
		return

	var data: Dictionary = tactical_manager.get_dashboard_data()
	var resources: Dictionary = data.get("action_resources", {})
	_eq("movement_used 透传", resources.get("movement_used"), current_unit.movement_used)
	_eq("standard_used 透传", resources.get("standard_used"), current_unit.standard_used)
	_eq("swift_used 透传", resources.get("swift_used"), current_unit.swift_used)
	_eq("标准显示容量映射", resources.get("standard_capacity"), 1)
	_eq("迅捷显示容量映射", resources.get("swift_capacity"), 1)

	dashboard.update_state(data.merged({"visible": true, "show_actions": true}, true))
	await process_frame
	var composition: Control = dashboard.get_composition()
	var resource_bar: Control = composition.get_node("ActionResourceStrip") as Control
	_check("玩家操作态创建行动资源栏", resource_bar != null)
	if resource_bar != null:
		_check("玩家操作态显示行动资源栏", resource_bar.is_visible_in_tree())
		dashboard.update_state(data.merged({"visible": false}, true))
		_check("仪表盘隐藏时立即隐藏行动资源栏", not resource_bar.is_visible_in_tree())
		dashboard.update_state(data.merged({"visible": true, "show_actions": true}, true))
		await process_frame
		var skill_shelf: Control = composition.get_node("BottomRow/SkillShelf") as Control
		_check("资源栏与技能栏精确间隔 6 像素", is_equal_approx(
			skill_shelf.global_position.y - resource_bar.get_global_rect().end.y, 6.0))
		_check("资源栏与技能栏水平中心一致", is_equal_approx(
			resource_bar.get_global_rect().get_center().x, skill_shelf.get_global_rect().get_center().x),
			"资源栏 %s，技能栏 %s" % [resource_bar.get_global_rect(), skill_shelf.get_global_rect()])

		_check("职业资源进入浮窗避让范围", is_equal_approx(dashboard.get_content_top_y(), 520.0))
		_check("行动资源栏进入输入阻挡范围", dashboard.get_input_blocking_rects().has(resource_bar.get_global_rect()))

		for control: Control in [composition.call("get_class_resource_host"), composition.call("get_marks_panel"), composition.get_node("BottomRow")]:
			control.visible = false
		_check("只保留行动资源栏时仍参与避让", is_equal_approx(
			dashboard.get_content_top_y(), resource_bar.get_global_rect().position.y))
		dashboard.update_state(data)

		dashboard.update_state(data.merged({"visible": true, "mode": "player", "show_actions": false}, true))
		_check("玩家模式但 show_actions=false 时隐藏行动资源栏", not resource_bar.visible)

		dashboard.update_state(data.merged({"visible": true, "mode": "enemy", "show_actions": true}, true))
		_check("敌方信息态隐藏行动资源栏", not resource_bar.visible)

		var missing_payload: Dictionary = data.duplicate(true)
		missing_payload.erase("action_resources")
		dashboard.update_state(missing_payload.merged({"visible": true, "mode": "player", "show_actions": true}, true))
		_check("缺失 action_resources 字段时隐藏行动资源栏", not resource_bar.visible)

		for missing_field: String in ["movement_remaining", "movement_available", "standard_capacity", "standard_remaining", "swift_capacity", "swift_remaining"]:
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
