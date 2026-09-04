extends SceneTree

const VIEW_DATA_PATH: String = "res://scripts/ui/hud/skill_slot_view_data.gd"
const SCENE_PATH: String = "res://scenes/tactical/hud/skill_slot_button.tscn"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_hud_skill_slot_button ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var view_script: GDScript = load(VIEW_DATA_PATH) as GDScript
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_check("有类型技能槽显示数据脚本存在", view_script != null)
	_check("技能槽场景存在", packed != null)
	if view_script == null or packed == null:
		_finish()
		return

	_test_view_data_contract(view_script)
	await _test_declared_scene_and_binding(view_script, packed)
	await _test_interaction_states(view_script, packed)
	_finish()


func _test_view_data_contract(view_script: GDScript) -> void:
	var view: RefCounted = view_script.new()
	view.skill_id = "counter_stance"
	view.passive = true
	view.active_capable = true
	view.enabled = true
	view.cooldown_turns = 0
	_check("可主动触发的被动技能可用", view.can_activate())

	view.active_capable = false
	_check("没有主动能力时不可触发", not view.can_activate())
	view.active_capable = true
	view.cooldown_turns = 2
	_check("冷却中不可触发", not view.can_activate())
	view.cooldown_turns = 0
	view.enabled = false
	_check("禁用时不可触发", not view.can_activate())

	var property_names: Array[String] = []
	for property: Dictionary in view.get_property_list():
		property_names.append(str(property["name"]))
	for forbidden: String in ["unit", "unit_ref", "unit_data", "game_action"]:
		_check("显示数据不持有 %s" % forbidden, not forbidden in property_names)
	_check("显示数据不再持有冷却比例", not "cooldown_ratio" in property_names)


func _test_declared_scene_and_binding(view_script: GDScript, packed: PackedScene) -> void:
	var slot: Button = packed.instantiate() as Button
	_check("技能槽根节点是 Button", slot != null)
	if slot == null:
		return

	_check("静态节点在进入场景树前已由 tscn 声明", slot.get_node_or_null("Content/IconRect") != null
		and slot.get_node_or_null("Content/CooldownShade") != null
		and slot.get_node_or_null("Content/CooldownTurnsLabel") != null
		and slot.get_node_or_null("Content/SelectedOverlay") != null
		and slot.get_node_or_null("Content/HotkeyBadge") != null
		and slot.get_node_or_null("Content/HotkeyBadge/HotkeyText") != null
		and slot.get_node_or_null("Content/ChargeText") != null)
	_check("场景序列化了完整组件树", packed.get_state().get_node_count() >= 7)

	root.add_child(slot)
	await process_frame
	_eq("技能槽 Theme 类型", slot.theme_type_variation, &"SkillSlotButton")
	_check("技能槽使用独立 Theme 资源", slot.theme != null)

	var hotkey_badge: Control = slot.get_node("Content/HotkeyBadge") as Control
	var hotkey_text: Label = slot.get_node("Content/HotkeyBadge/HotkeyText") as Label
	_check("未绑定数据时快捷键角标隐藏", not hotkey_badge.visible)
	_eq("未绑定数据时快捷键文字为空", hotkey_text.text, "")
	_eq("快捷键角标随文字放大为 18×18", hotkey_badge.custom_minimum_size, Vector2(18.0, 18.0))
	_eq("快捷键水平居中", hotkey_text.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER)
	_eq("快捷键垂直居中", hotkey_text.vertical_alignment, VERTICAL_ALIGNMENT_CENTER)
	_eq("快捷键使用 11px", hotkey_text.get_theme_font_size(&"font_size"), 11)
	var charge_text: Label = slot.get_node("Content/ChargeText") as Label
	_eq("技能次数使用 12px", charge_text.get_theme_font_size(&"font_size"), 12)
	_eq("技能次数承载区随文字放大为 24×20", charge_text.size, Vector2(24.0, 20.0))
	var cooldown_shade: Control = slot.get_node_or_null("Content/CooldownShade") as Control
	var cooldown_label: Label = slot.get_node_or_null("Content/CooldownTurnsLabel") as Label
	_check("冷却暗层存在", cooldown_shade != null)
	_check("冷却回合数字层存在", cooldown_label != null)
	_check("技能槽不再使用比例进度条", not _contains_range(slot))
	if cooldown_shade == null or cooldown_label == null:
		slot.free()
		return
	_eq("冷却数字水平居中", cooldown_label.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER)
	_eq("冷却数字垂直居中", cooldown_label.vertical_alignment, VERTICAL_ALIGNMENT_CENTER)
	_eq("冷却数字使用 22px", cooldown_label.get_theme_font_size(&"font_size"), 22)

	var view: RefCounted = view_script.new()
	view.skill_id = "counter_stance"
	view.hotkey_text = "K"
	view.enabled = true
	view.passive = true
	view.active_capable = true
	view.selected = true
	view.cooldown_turns = 0
	view.charges = 2
	view.show_charges = true
	slot.call("apply_view", view)

	_eq("快捷键绑定", hotkey_text.text, "K")
	_eq("次数绑定", (slot.get_node("Content/ChargeText") as Label).text, "2")
	_check("选择覆盖层显示", (slot.get_node("Content/SelectedOverlay") as CanvasItem).visible)
	_check("可主动触发的被动技能不会被禁用", not slot.disabled)
	var visible_text: PackedStringArray = _collect_visible_label_text(slot)
	for forbidden_text: String in ["ACTIVE", "PASSIVE", "P"]:
		_check("不显示类别标记 %s" % forbidden_text, not forbidden_text in visible_text, str(visible_text))

	slot.free()


func _test_interaction_states(view_script: GDScript, packed: PackedScene) -> void:
	var slot: Button = packed.instantiate() as Button
	root.add_child(slot)
	await process_frame
	var activated_ids: Array[String] = []
	slot.connect("skill_activated", func(skill_id: String) -> void: activated_ids.append(skill_id))

	var view: RefCounted = view_script.new()
	view.skill_id = "counter_stance"
	view.enabled = true
	view.passive = true
	view.active_capable = true
	slot.call("apply_view", view)
	slot.pressed.emit()
	_eq("被动技能发出激活信号", activated_ids, ["counter_stance"])

	view.active_capable = false
	slot.call("apply_view", view)
	slot.pressed.emit()
	_eq("无主动能力不会追加信号", activated_ids, ["counter_stance"])

	view.active_capable = true
	view.cooldown_turns = 2
	slot.call("apply_view", view)
	var cooldown_shade: Control = slot.get_node_or_null("Content/CooldownShade") as Control
	var cooldown_label: Label = slot.get_node_or_null("Content/CooldownTurnsLabel") as Label
	_check("冷却暗层存在于交互实例", cooldown_shade != null)
	_check("冷却数字存在于交互实例", cooldown_label != null)
	if cooldown_shade == null or cooldown_label == null:
		slot.free()
		return
	_eq("冷却显示剩余回合数", cooldown_label.text, "2")
	_check("冷却数字显示", cooldown_label.visible)
	_check("冷却暗层显示", cooldown_shade.visible)
	_check("冷却时根按钮禁用", slot.disabled)
	slot.pressed.emit()
	_eq("冷却中不会追加信号", activated_ids, ["counter_stance"])

	view.cooldown_turns = 0
	slot.call("apply_view", view)
	_check("冷却归零后数字隐藏", not cooldown_label.visible)
	_check("冷却归零后暗层隐藏", not cooldown_shade.visible)
	_check("冷却归零后技能恢复可用", not slot.disabled)
	view.cooldown_turns = -1
	slot.call("apply_view", view)
	_check("负数冷却不会显示", not cooldown_label.visible and cooldown_label.text == "")

	slot.free()


func _collect_visible_label_text(node: Node) -> PackedStringArray:
	var result: PackedStringArray = []
	var label: Label = node as Label
	if label != null and label.visible and label.text != "":
		result.append(label.text)
	for child: Node in node.get_children():
		result.append_array(_collect_visible_label_text(child))
	return result


func _contains_range(node: Node) -> bool:
	if node is Range:
		return true
	for child: Node in node.get_children():
		if _contains_range(child):
			return true
	return false


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
