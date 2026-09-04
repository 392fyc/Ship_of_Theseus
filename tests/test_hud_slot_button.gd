extends SceneTree

const SLOT_VIEW_PATH: String = "res://scripts/ui/hud/slot_view_data.gd"
const POTION_VIEW_PATH: String = "res://scripts/ui/hud/potion_view_data.gd"
const SLOT_SCENE_PATH: String = "res://scenes/tactical/hud/slot_button.tscn"
const POTION_SCENE_PATH: String = "res://scenes/tactical/hud/potion_button.tscn"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_hud_slot_button ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var slot_view_script: GDScript = load(SLOT_VIEW_PATH) as GDScript
	var potion_view_script: GDScript = load(POTION_VIEW_PATH) as GDScript
	var slot_packed: PackedScene = load(SLOT_SCENE_PATH) as PackedScene
	var potion_packed: PackedScene = load(POTION_SCENE_PATH) as PackedScene
	_check("通用槽纯显示数据存在", slot_view_script != null)
	_check("血瓶纯显示数据存在", potion_view_script != null)
	_check("通用槽场景存在", slot_packed != null)
	_check("血瓶按钮场景存在", potion_packed != null)

	if slot_view_script != null:
		_test_slot_view_contract(slot_view_script)
	if potion_view_script != null:
		_test_potion_view_contract(potion_view_script)
	if slot_packed != null and slot_view_script != null:
		await _test_slot_component(slot_packed, slot_view_script)
	if potion_packed != null and potion_view_script != null:
		await _test_potion_component(potion_packed, potion_view_script)
	_finish()


func _test_slot_view_contract(view_script: GDScript) -> void:
	var view: RefCounted = view_script.new()
	var properties: Array[String] = _property_names(view)
	for expected: String in ["slot_id", "content_id", "icon_texture", "tooltip_text", "occupied", "enabled"]:
		_check("通用槽显示数据声明 %s" % expected, expected in properties)
	for forbidden: String in ["unit", "run_state", "game_action", "tactical_manager",
			"bottom_dashboard", "relic_capacity", "relic_slot_max"]:
		_check("通用槽显示数据不持有 %s" % forbidden,
			properties.all(func(name: String) -> bool: return forbidden not in name))


func _test_potion_view_contract(view_script: GDScript) -> void:
	var view: RefCounted = view_script.new()
	var properties: Array[String] = _property_names(view)
	for expected: String in ["content_id", "icon_texture", "tooltip_text", "enabled"]:
		_check("血瓶显示数据声明 %s" % expected, expected in properties)
	for forbidden: String in ["unit", "run_state", "game_action", "count", "charge_count",
			"charges", "cooldown", "cooldown_turns", "healing", "healing_amount",
			"heal_amount", "replenish"]:
		_check("血瓶显示数据不持有 %s" % forbidden,
			forbidden not in properties)


func _test_slot_component(packed: PackedScene, view_script: GDScript) -> void:
	var slot: Button = packed.instantiate() as Button
	_check("通用槽根节点为 Button", slot != null)
	if slot == null:
		return
	_check("通用槽静态层由 tscn 声明",
		slot.get_node_or_null("Content/IconRect") is TextureRect
		and slot.get_node_or_null("Content/StateOverlay") is Control
		and slot.get_node_or_null("Content/FocusOverlay") is Control)
	root.add_child(slot)
	await process_frame
	var view: RefCounted = view_script.new()
	view.set("slot_id", "weapon")
	view.set("content_id", "mock_weapon")
	view.set("occupied", true)
	view.set("tooltip_text", "mock-only weapon")
	view.set("enabled", true)
	slot.call("apply_view", view)
	_eq("通用槽 tooltip 由显示数据绑定", slot.tooltip_text, "mock-only weapon")
	_check("通用槽可用状态由显示数据绑定", not slot.disabled)
	_check("通用槽不显示审核文字", _visible_label_text(slot).is_empty())
	slot.queue_free()
	await process_frame


func _test_potion_component(packed: PackedScene, view_script: GDScript) -> void:
	var potion: Button = packed.instantiate() as Button
	_check("血瓶根节点为 Button", potion != null)
	if potion == null:
		return
	_eq("血瓶按钮固定为 32×32", potion.custom_minimum_size, Vector2(32, 32))
	_check("血瓶图标接口由 tscn 声明",
		potion.get_node_or_null("Content/IconRect") is TextureRect)
	_check("血瓶组件没有次数或冷却文字层", _all_label_nodes(potion).is_empty())
	root.add_child(potion)
	await process_frame
	var requested: Array[bool] = []
	potion.connect("potion_requested", func() -> void: requested.append(true))
	var view: RefCounted = view_script.new()
	view.set("content_id", "mock_universal_potion")
	view.set("tooltip_text", "mock-only potion")
	view.set("enabled", true)
	potion.call("apply_view", view)
	potion.pressed.emit()
	_eq("可用血瓶发出无玩法参数的请求", requested, [true])
	view.set("enabled", false)
	potion.call("apply_view", view)
	potion.pressed.emit()
	_eq("禁用血瓶不追加请求", requested, [true])
	potion.queue_free()
	await process_frame


func _property_names(object: Object) -> Array[String]:
	var result: Array[String] = []
	for property: Dictionary in object.get_property_list():
		result.append(str(property["name"]).to_lower())
	return result


func _visible_label_text(node: Node) -> Array[String]:
	var result: Array[String] = []
	var label: Label = node as Label
	if label != null and label.visible and label.text != "":
		result.append(label.text)
	for child: Node in node.get_children():
		result.append_array(_visible_label_text(child))
	return result


func _all_label_nodes(node: Node) -> Array[Label]:
	var result: Array[Label] = []
	var label: Label = node as Label
	if label != null:
		result.append(label)
	for child: Node in node.get_children():
		result.append_array(_all_label_nodes(child))
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
