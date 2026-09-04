extends SceneTree

const VIEW_DATA_PATH: String = "res://scripts/ui/hud/end_turn_view_data.gd"
const BUTTON_SCENE_PATH: String = "res://scenes/tactical/hud/end_turn_button.tscn"
const CONTROL_SCENE_PATH: String = "res://scenes/tactical/hud/end_turn_control.tscn"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_hud_end_turn_control ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var view_script: GDScript = load(VIEW_DATA_PATH) as GDScript
	var button_packed: PackedScene = load(BUTTON_SCENE_PATH) as PackedScene
	var control_packed: PackedScene = load(CONTROL_SCENE_PATH) as PackedScene
	_check("结束区纯显示数据存在", view_script != null)
	_check("结束按钮场景存在", button_packed != null)
	_check("结束区场景存在", control_packed != null)
	if view_script != null:
		_test_view_contract(view_script)
	if button_packed != null:
		_test_button_layers(button_packed)
	if view_script != null and control_packed != null:
		await _test_dual_semantics(view_script, control_packed)
	_finish()


func _test_view_contract(view_script: GDScript) -> void:
	var view: RefCounted = view_script.new()
	var properties: Array[String] = []
	for property: Dictionary in view.get_property_list():
		properties.append(str(property["name"]).to_lower())
	for expected: String in ["action_kind", "visible", "enabled", "tooltip_text"]:
		_check("结束区显示数据声明 %s" % expected, expected in properties)
	for forbidden: String in ["unit", "run_state", "game_action", "tactical_manager",
			"bottom_dashboard"]:
		_check("结束区显示数据不持有 %s" % forbidden,
			properties.all(func(name: String) -> bool: return forbidden not in name))
	view.set("action_kind", &"end_turn")
	_check("end_turn 是有效语义", bool(view.call("is_valid_action_kind")))
	view.set("action_kind", &"end_move")
	_check("end_move 是有效语义", bool(view.call("is_valid_action_kind")))
	view.set("action_kind", &"unknown")
	_check("未知结束语义被拒绝", not bool(view.call("is_valid_action_kind")))


func _test_button_layers(packed: PackedScene) -> void:
	var button: Button = packed.instantiate() as Button
	_check("结束按钮根节点为 Button", button != null)
	if button == null:
		return
	_eq("结束按钮固定为 52×52", button.custom_minimum_size, Vector2(52, 52))
	var diamond: Control = button.get_node_or_null("DiamondFrame") as Control
	var hourglass: Control = button.get_node_or_null("HourglassEmblem") as Control
	_check("菱形框与沙漏图形由 tscn 分层声明", diamond != null and hourglass != null)
	if diamond != null and hourglass != null:
		_check("菱形明显大于沙漏且边缘不接触",
			diamond.custom_minimum_size.x > hourglass.custom_minimum_size.x
			and diamond.custom_minimum_size.y > hourglass.custom_minimum_size.y)
		_eq("菱形框固定为 44×44", diamond.custom_minimum_size, Vector2(44, 44))
		_eq("沙漏图形固定为 18×24", hourglass.custom_minimum_size, Vector2(18, 24))
		var gap := minf(
			hourglass.position.x - diamond.position.x,
			minf(hourglass.position.y - diamond.position.y,
				minf(
					diamond.position.x + diamond.size.x - hourglass.position.x - hourglass.size.x,
					diamond.position.y + diamond.size.y - hourglass.position.y - hourglass.size.y)))
		_check("菱形与沙漏至少保留 10 像素空隙", gap >= 10.0)
	_check("结束按钮不含 END 文字", _visible_label_text(button).is_empty())
	button.free()


func _test_dual_semantics(view_script: GDScript, packed: PackedScene) -> void:
	var control: Control = packed.instantiate() as Control
	_check("结束区根节点可实例化", control != null)
	if control == null:
		return
	var button: Button = control.get_node_or_null("EndTurnButton") as Button
	_check("结束区声明独立按钮", button != null)
	if button == null:
		control.free()
		return
	root.add_child(control)
	await process_frame
	await process_frame
	_eq("结束区固定为 76×108", control.size, Vector2(76, 108))
	_eq("结束按钮固定位置", button.position, Vector2(12, 28))
	_check("结束区保留 end_turn_requested 信号", control.has_signal("end_turn_requested"))
	_check("结束区保留 end_move_requested 信号", control.has_signal("end_move_requested"))
	var turn_requests: Array[bool] = []
	var move_requests: Array[bool] = []
	control.connect("end_turn_requested", func() -> void: turn_requests.append(true))
	control.connect("end_move_requested", func() -> void: move_requests.append(true))

	var view: RefCounted = view_script.new()
	view.set("action_kind", &"end_turn")
	view.set("visible", true)
	view.set("enabled", true)
	view.set("tooltip_text", "结束本回合")
	control.call("apply_view", view)
	button.pressed.emit()
	_eq("end_turn 只发出结束回合请求", [turn_requests.size(), move_requests.size()], [1, 0])
	view.set("action_kind", &"end_move")
	view.set("tooltip_text", "结束移动")
	control.call("apply_view", view)
	button.pressed.emit()
	_eq("end_move 只发出结束移动请求", [turn_requests.size(), move_requests.size()], [1, 1])
	view.set("enabled", false)
	control.call("apply_view", view)
	button.pressed.emit()
	_eq("禁用时不追加请求", [turn_requests.size(), move_requests.size()], [1, 1])
	view.set("enabled", true)
	view.set("visible", false)
	control.call("apply_view", view)
	button.pressed.emit()
	_eq("隐藏时不追加请求", [turn_requests.size(), move_requests.size()], [1, 1])
	control.queue_free()
	await process_frame


func _visible_label_text(node: Node) -> Array[String]:
	var result: Array[String] = []
	var label: Label = node as Label
	if label != null and label.visible and label.text != "":
		result.append(label.text)
	for child: Node in node.get_children():
		result.append_array(_visible_label_text(child))
	return result


func _finish() -> void:
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
