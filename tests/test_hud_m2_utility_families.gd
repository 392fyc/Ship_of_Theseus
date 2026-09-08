extends SceneTree

const SlotView := preload("res://scripts/ui/hud/m2/slot_view_data.gd")
const LegacySlotView := preload("res://scripts/ui/hud/slot_view_data.gd")
const PotionView := preload("res://scripts/ui/hud/potion_view_data.gd")
const EndView := preload("res://scripts/ui/hud/end_turn_view_data.gd")
const EquipmentScene: PackedScene = preload("res://scenes/tactical/hud/m2/equipment_hud_panel.tscn")
const RelicScene: PackedScene = preload("res://scenes/tactical/hud/m2/relic_grid.tscn")
const EndScene: PackedScene = preload("res://scenes/tactical/hud/m2/end_turn_control.tscn")

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	_run.call_deferred()


func _run() -> void:
	await _test_equipment()
	await _test_relics()
	await _test_end_action()
	_test_materials()
	print("test_hud_m2_utility_families: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _slot(id: String, occupied: bool = false) -> SlotView:
	var view := SlotView.new()
	view.slot_id = id
	view.occupied = occupied
	view.content_id = "fixture_content" if occupied else ""
	view.icon_texture = GradientTexture2D.new() if occupied else null
	view.tooltip_text = "显示测试夹具"
	return view


func _test_equipment() -> void:
	var equipment: Panel = EquipmentScene.instantiate()
	equipment.position = Vector2(100, 100)
	var weapon: SlotView = _slot("weapon", true)
	var armor: SlotView = _slot("armor")
	armor.empty_kind = &"armor"
	var potion := PotionView.new()
	potion.content_id = "fixture_potion"
	potion.icon_texture = GradientTexture2D.new()
	equipment.apply_view(weapon, armor, potion)
	root.add_child(equipment)
	await process_frame
	var weapon_button: Button = equipment.get_node("WeaponSlot")
	var armor_button: Button = equipment.get_node("ArmorSlot")
	var potion_button: Button = equipment.get_node("PotionButton")
	_check("装备128×108", equipment.size == Vector2(128, 108))
	_check("装备标签固定几何", equipment.get_node("EquipmentLabel").get_rect() == Rect2(12, 15, 56, 16))
	_check("武器52槽固定几何", weapon_button.get_rect() == Rect2(10, 46, 52, 52))
	_check("护甲52槽固定几何", armor_button.get_rect() == Rect2(66, 46, 52, 52))
	_check("血瓶32槽固定几何", potion_button.get_rect() == Rect2(86, 10, 32, 32))
	_check("武器图6px内距", weapon_button.get_node("Content/IconRect").get_rect() == Rect2(6, 6, 40, 40))
	_check("血瓶图6px内距", potion_button.get_node("Content/IconRect").get_rect() == Rect2(6, 6, 20, 20))
	_check("血瓶禁用层24px", potion_button.get_node("Content/UnavailableShade").get_rect() == Rect2(4, 4, 24, 24))
	_check("护甲空槽24×28轮廓定位", armor_button.get_node("Content/EmptyGlyph").get_rect() == Rect2(14, 12, 24, 28))
	_check("占用武器图可见", weapon_button.get_node("Content/IconRect").visible)
	_check("空护甲轮廓可见", armor_button.get_node("Content/EmptyGlyph").visible)
	_check("空护甲不画占用图", not armor_button.get_node("Content/IconRect").visible)
	var requests: Array[String] = []
	weapon_button.slot_requested.connect(func(slot_id: String, content_id: String) -> void: requests.append(slot_id + "/" + content_id))
	armor_button.slot_requested.connect(func(slot_id: String, content_id: String) -> void: requests.append(slot_id + "/" + content_id))
	potion_button.potion_requested.connect(func() -> void: requests.append("potion"))
	await _move(weapon_button.get_global_rect().get_center())
	_check("装备悬停边可见", weapon_button.get_node("Content/HoverOverlay").visible)
	await _mouse_button(weapon_button.get_global_rect().get_center(), true)
	_check("装备按下层可见", weapon_button.get_node("Content/PressedShade").visible)
	await _mouse_button(weapon_button.get_global_rect().get_center(), false)
	_check("鼠标发出槽与内容请求", requests == ["weapon/fixture_content"])
	_check("松开关闭按下层", not weapon_button.get_node("Content/PressedShade").visible)
	armor_button.grab_focus()
	await _key(KEY_ENTER)
	_check("键盘可请求空装备槽", requests.back() == "armor/")
	_check("空槽焦点层可见", armor_button.get_node("Content/FocusOverlay").visible)
	await _click(potion_button.get_global_rect().get_center())
	_check("血瓶保持无参请求", requests.back() == "potion")
	var count: int = requests.size()
	weapon.enabled = false
	potion.enabled = false
	equipment.apply_view(weapon, armor, potion)
	await _click(weapon_button.get_global_rect().get_center())
	await _click(potion_button.get_global_rect().get_center())
	potion_button.grab_focus()
	await _key(KEY_ENTER)
	_check("禁用装备与血瓶拒绝鼠标键盘", requests.size() == count)
	_check("禁用武器仅覆盖内部", weapon_button.get_node("Content/UnavailableShade").visible and weapon_button.modulate == Color.WHITE)
	_check("禁用血瓶保留原皮肤颜色", potion_button.get_node("Content/UnavailableShade").visible and potion_button.modulate == Color.WHITE)
	_check("禁用后的悬停及按下层关闭", not weapon_button.get_node("Content/HoverOverlay").visible and not weapon_button.get_node("Content/PressedShade").visible)
	weapon.occupied = false
	weapon.empty_kind = &"weapon"
	weapon.enabled = true
	equipment.apply_view(weapon, armor, potion)
	_check("空武器由显示数据选择轮廓", weapon_button.get_node("Content/EmptyGlyph").visible and not weapon_button.get_node("Content/IconRect").visible)
	var legacy := LegacySlotView.new()
	legacy.slot_id = "legacy_slot"
	weapon_button.apply_view(legacy)
	await _click(weapon_button.get_global_rect().get_center())
	_check("兼容旧显示类", requests.back() == "legacy_slot/")
	legacy.slot_id = ""
	weapon_button.apply_view(legacy)
	count = requests.size()
	weapon_button.pressed.emit()
	_check("缺槽标识不发伪造请求", requests.size() == count)
	equipment.queue_free()
	await process_frame


func _test_relics() -> void:
	var relics: Panel = RelicScene.instantiate()
	relics.position = Vector2(100, 240)
	root.add_child(relics)
	await process_frame
	await process_frame
	var grid: GridContainer = relics.get_node("VisualGrid")
	_check("遗物区域278×108", relics.size == Vector2(278, 108))
	_check("遗物网格位置与250×88", grid.get_rect() == Rect2(14, 10, 250, 88))
	_check("只声明8个视觉位置", grid.get_child_count() == 8)
	var views: Array[RefCounted] = []
	for index: int in 8:
		views.append(_slot("relic_%d" % index, index == 2))
	views[0].locked = true
	views[4].enabled = false
	relics.apply_slots(views)
	await process_frame
	for index: int in 8:
		var slot: Button = grid.get_child(index)
		_check("遗物40槽与30/8间隔", slot.get_rect() == Rect2((index % 4) * 70, int(index / 4) * 48, 40, 40))
	var locked: Button = grid.get_child(0)
	var occupied: Button = grid.get_child(2)
	var final_slot: Button = grid.get_child(7)
	_check("第1格显式锁定", locked.disabled and locked.get_node("Content/LockGlyph").visible)
	_check("第8格可显式解锁", not final_slot.disabled and not final_slot.get_node("Content/LockGlyph").visible)
	_check("锁定内部30px暗层", locked.get_node("Content/StateOverlay").get_rect() == Rect2(5, 5, 30, 30))
	_check("锁图形12×14", locked.get_node("Content/LockGlyph").get_rect() == Rect2(14, 13, 12, 14))
	_check("锁定皮肤不整体压暗", locked.modulate == Color.WHITE)
	_check("占用遗物使用调用方图像", occupied.get_node("Content/IconRect").visible and occupied.get_node("Content/IconRect").texture == views[2].icon_texture)
	var requests: Array[String] = []
	for child: Node in grid.get_children():
		child.slot_requested.connect(func(id: String, _content: String) -> void: requests.append(id))
	await _click(locked.get_global_rect().get_center())
	locked.grab_focus()
	await _key(KEY_ENTER)
	locked.pressed.emit()
	_check("锁定拒绝鼠标键盘和直接pressed", requests.is_empty())
	await _click(final_slot.get_global_rect().get_center())
	_check("第8视觉槽可发请求", requests == ["relic_7"])
	views[7].locked = true
	views[0].locked = false
	relics.apply_slots(views)
	_check("锁定位置随显示数据改变", not locked.disabled and final_slot.disabled)
	await _click(locked.get_global_rect().get_center())
	_check("解锁后可请求", requests.back() == "relic_0")
	var no_views: Array[RefCounted] = []
	relics.apply_slots(no_views)
	_check("未提供数据不推导锁定位置", not final_slot.get_node("Content/LockGlyph").visible)
	_check("未提供数据不生成交互标识", final_slot.disabled)
	relics.queue_free()
	await process_frame


func _test_end_action() -> void:
	var host := Control.new()
	root.add_child(host)
	var end: Panel = EndScene.instantiate()
	end.position = Vector2(100, 380)
	host.add_child(end)
	await process_frame
	var button: Button = end.get_node("EndTurnButton")
	var label: Label = end.get_node("EndLabel")
	_check("结束区76×108", end.size == Vector2(76, 108))
	_check("52点击区位置", button.get_rect() == Rect2(12, 28, 52, 52))
	_check("44菱形精确位置", button.get_node("DiamondFrame").get_rect() == Rect2(4, 4, 44, 44))
	_check("18×24沙漏精确位置", button.get_node("HourglassEmblem").get_rect() == Rect2(17, 14, 18, 24))
	_check("结束文字64×15", label.get_rect() == Rect2(6, 86, 64, 15))
	var requests: Array[String] = []
	end.end_turn_requested.connect(func() -> void: requests.append("turn"))
	end.end_move_requested.connect(func() -> void: requests.append("move"))
	var view := EndView.new()
	end.apply_view(view)
	_check("结束回合文字", label.text == "结束回合")
	await _move(button.get_global_rect().get_center())
	_check("结束悬停可见", button.get_node("HoverOverlay").visible)
	await _mouse_button(button.get_global_rect().get_center(), true)
	_check("结束按下可见", button.get_node("PressedShade").visible)
	await _mouse_button(button.get_global_rect().get_center(), false)
	_check("结束回合鼠标请求", requests == ["turn"])
	view.action_kind = &"end_move"
	end.apply_view(view)
	button.grab_focus()
	await _key(KEY_ENTER)
	_check("结束移动文字与键盘请求", label.text == "结束移动" and requests == ["turn", "move"])
	_check("结束焦点可见", button.get_node("FocusOverlay").visible)
	view.enabled = false
	end.apply_view(view)
	await _click(button.get_global_rect().get_center())
	await _key(KEY_ENTER)
	_check("结束禁用拒绝输入", requests.size() == 2)
	_check("结束仅局部52暗层", button.get_node("UnavailableShade").size == Vector2(52, 52) and button.get_node("UnavailableShade").visible and button.modulate == Color.WHITE)
	_check("结束禁用文字颜色", label.get_theme_color(&"font_color") == Color("#756C79"))
	view.enabled = true
	view.action_kind = &"invalid_fixture"
	end.apply_view(view)
	button.pressed.emit()
	_check("非法结束类型拒绝且不造文字", button.disabled and label.text.is_empty() and requests.size() == 2)
	view.action_kind = &"end_turn"
	view.visible = false
	end.apply_view(view)
	button.pressed.emit()
	_check("隐藏结束入口拒绝", not end.visible and requests.size() == 2)
	view.visible = true
	end.apply_view(view)
	host.hide()
	button.pressed.emit()
	_check("祖先隐藏也拒绝", requests.size() == 2)
	host.queue_free()
	await process_frame


func _test_materials() -> void:
	var theme: Theme = load("res://assets/ui/themes/hud_m2.tres")
	var slot: StyleBox = theme.get_stylebox(&"panel", &"HudM2SlotFrame")
	var potion: StyleBox = theme.get_stylebox(&"panel", &"HudM2PotionFrame")
	_check("默认槽框为获批材质StyleBoxTexture", slot is StyleBoxTexture and (slot as StyleBoxTexture).texture.resource_path.ends_with("slot-active.png"))
	_check("默认血瓶框为获批材质StyleBoxTexture", potion is StyleBoxTexture and (potion as StyleBoxTexture).texture.resource_path.ends_with("slot-potion.png"))
	for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		_check("槽第%d边内容边距6px" % side, is_equal_approx(slot.get_content_margin(side), 6.0))
		_check("血瓶第%d边内容边距5px" % side, is_equal_approx(potion.get_content_margin(side), 5.0))
	_check("锁定暗层alpha36%", is_equal_approx((theme.get_stylebox(&"panel", &"HudM2LockedShade") as StyleBoxFlat).bg_color.a, 0.36))
	_check("血瓶禁用暗层alpha60%", is_equal_approx((theme.get_stylebox(&"panel", &"HudM2PotionUnavailable") as StyleBoxFlat).bg_color.a, 0.6))
	_check("P3默认字体仍MSDF", theme.default_font.get("multichannel_signed_distance_field") == true)
	_check("P3数字字体仍MSDF", theme.get_font(&"font", &"HudM2NumericLabel").get("multichannel_signed_distance_field") == true)


func _move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	root.push_input(event, true)
	await process_frame


func _mouse_button(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	root.push_input(event, true)
	await process_frame


func _click(point: Vector2) -> void:
	await _move(point)
	await _mouse_button(point, true)
	await _mouse_button(point, false)


func _key(code: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)
	await process_frame


func _check(label: String, value: bool) -> void:
	if value:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + label)
