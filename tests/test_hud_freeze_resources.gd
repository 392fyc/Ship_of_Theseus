extends SceneTree

const Adapter := preload("res://scripts/ui/hud/m2/dashboard_view_adapter.gd")
const ResourceLayout := preload("res://assets/ui/layouts/hud_m2_class_resource.tres")

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var manager: Object = scene.tactical_manager
	var unit: Unit = manager._get_dashboard_unit()
	var dashboard: Control = scene.get("_bottom_dashboard")
	var composition: Control = dashboard.get_composition()
	var sword: Control = composition.call("get_class_resource_host")
	var marks: Control = composition.call("get_marks_panel")
	_check("主场景接入冻结布局", ResourceLayout.bounds == Rect2(32, 520, 366, 56) and ResourceLayout.marks_bounds == Rect2(886, 520, 278, 56))
	_check("剑与印记独立悬浮", sword.get_parent() == composition and marks.get_parent() == composition and sword != marks)
	_check("悬浮模块不抢战场鼠标", sword.mouse_filter == Control.MOUSE_FILTER_IGNORE and marks.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("真实单位使用定版基础职业", unit != null and unit.unit_id == "kensei")
	if unit != null:
		for amount: int in [0, 1, 50, 51, 100]:
			unit.set_sword_qi(amount)
			var state: Dictionary = manager.get_dashboard_data()
			var expected_band: StringName = &"low" if amount <= 50 else &"high"
			var view: RefCounted = Adapter.new().build(state)["class_resources"]
			_check("剑气 %d 来源和分段" % amount, state["sword_qi"] == amount and state["class_resource_display"]["qi_band"] == expected_band and view.body.qi.current_value == amount and view.body.band == expected_band)
			_check("剑气 %d 当前数值和上限" % amount, view.body.qi.maximum_value == unit._qi_max and view.body.qi.current_value == amount)
		for mask: int in 8:
			var bits: String = "%d%d%d" % [int(bool(mask & 4)), int(bool(mask & 2)), int(bool(mask & 1))]
			unit.marks = {"心": bool(mask & 4), "道": bool(mask & 2), "势": bool(mask & 1)}
			var state: Dictionary = manager.get_dashboard_data()
			var view: RefCounted = Adapter.new().build(state)["class_resources"]
			dashboard.update_state(state)
			_check("印记 %s 独立布尔数据" % bits, view.body.marks.size() == 3 and bool(view.body.marks[0]["held"]) == bool(mask & 4) and bool(view.body.marks[1]["held"]) == bool(mask & 2) and bool(view.body.marks[2]["held"]) == bool(mask & 1))
			_check("印记 %s 选择同源状态图" % bits, marks.visible and str(marks.get("_state")) == bits and marks.get_theme_icon(StringName("marks_" + bits), &"HudM2FrozenResource").resource_path.ends_with("marks-" + bits + ".png"))
		var unknown: Dictionary = manager.get_dashboard_data().duplicate(true)
		unknown["class_resource_display"]["class_id"] = "unregistered"
		dashboard.update_state(unknown)
		_check("未注册职业保留剑气通用宿主", sword.visible and not marks.visible)
		_check("两位和三位通用职业费用", manager._build_resource_cost_display({"resource_cost_display": {"amount": 12, "resource_name": "斗志"}}) == {"amount": 12, "resource_name": "斗志"} and manager._build_resource_cost_display({"resource_cost_display": {"amount": 234, "resource_name": "法力"}}) == {"amount": 234, "resource_name": "法力"})
		_check("印记没有普通数字费用回填", manager._build_resource_cost_display({"mark_cost": 3}).is_empty())
	scene.queue_free()
	await process_frame
	print("HUD_FREEZE_RESOURCES_RESULT passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + label)
