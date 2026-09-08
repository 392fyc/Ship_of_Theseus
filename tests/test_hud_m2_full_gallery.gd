extends "res://tests/test_hud_m2_p3_gallery.gd"

var _utility_requests: Array[String] = []
var _card_clicks: int = 0


func _run() -> void:
	print("=== test_hud_m2_full_gallery ===")
	root.size = Vector2i(1280, 720)
	var gallery: Control = (load(SCENE_PATH) as PackedScene).instantiate() as Control
	root.add_child(gallery)
	await process_frame
	await process_frame
	await _test_layout(gallery)
	await _test_character(gallery)
	await _test_slots_and_input(gallery)
	await _test_full_character_card(gallery)
	await _test_utility_composition(gallery)
	gallery.queue_free()
	await process_frame
	print("HUD_M2_FULL_GALLERY_RESULT passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _test_full_character_card(gallery: Control) -> void:
	var panel: Control = gallery.call("get_character_panel") as Control
	var card: Control = panel.call("get_inspection_panel") as Control
	for output_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		gallery.call("configure", 7, output_size, "focus")
		await process_frame
		await process_frame
		var factor: float = float(output_size.x) / 1280.0
		_check("%s完整卡原生边界" % output_size, card.get_global_rect().is_equal_approx(Rect2(Vector2(32, 394) * factor, Vector2(304, 188) * factor)))
		_check("%s可见卡参与顶部避让查询" % output_size, is_equal_approx(float(panel.call("get_content_top_y")), 394.0 * factor))
		var blockers: Array = panel.call("get_input_blocking_rects") as Array
		_check("%s可见卡加入鼠标阻挡范围" % output_size, blockers.has(card.get_global_rect()))
		var title: Label = card.get_node("InspectionLabel") as Label
		_check("%s完整名字保留且无裁切" % output_size, "远行于群星与长夜之间的 fyc" in title.text and not title.clip_text and title.get_line_count() <= 2)
		_check("%s标题区272乘40" % output_size, title.size == Vector2(272, 40))
		var rows: Control = card.get_node("AttributeRows") as Control
		_check("%s两列八属性" % output_size, rows.get_child_count() == 8)
		for index: int in CharacterView.ATTRIBUTE_KEYS.size():
			var key: String = CharacterView.ATTRIBUTE_KEYS[index]
			var row: Control = rows.get_node(key) as Control
			_check("%s属性%s几何" % [output_size, key], row.position == Vector2((index % 2) * 142, (index / 2) * 25) and row.size == Vector2(130, 21))
			_check("%s属性%s字号" % [output_size, key], row.get_node("Value").get_theme_font_size("font_size") == 11)
	gallery.call("configure", 6, Vector2i(1280, 720), "mixed")
	await process_frame
	await process_frame
	_check("STR整数和增量", card.get_node("AttributeRows/STR/Value").text == "18 (+2)")
	_check("MAG整数", card.get_node("AttributeRows/MAG/Value").text == "7")
	_check("DEF整数和增量", card.get_node("AttributeRows/DEF/Value").text == "14 (+3)")
	gallery.call("configure", 6, Vector2i(1280, 720), "missing")
	await process_frame
	await process_frame
	for key: String in CharacterView.ATTRIBUTE_KEYS:
		_check("缺失%s显示破折号" % key, card.get_node("AttributeRows/" + key + "/Value").text == "—")
	_check("缺值卡仍保留已知HP", panel.find_child("HpValue", true, false).text == "160/200")
	var view := CharacterView.new()
	view.attribute_descriptions = {"STR": 0, "MAG": {"value": 12.0, "delta": -2.0}, "DEX": {"value": 8, "delta": 0}, "SPE": {"value": 7, "delta": "2"}, "DEF": 1.5, "RES": true, "LCK": {"delta": 2}}
	panel.call("apply_view", view)
	_check("真实零属性", card.get_node("AttributeRows/STR/Value").text == "0")
	_check("负增量", card.get_node("AttributeRows/MAG/Value").text == "12 (-2)")
	_check("零增量不增加伪后缀", card.get_node("AttributeRows/DEX/Value").text == "8")
	_check("非法增量保留已知整数", card.get_node("AttributeRows/SPE/Value").text == "7")
	for key: String in ["DEF", "RES", "LCK", "MOV"]:
		_check("非法或缺失%s不造数" % key, card.get_node("AttributeRows/" + key + "/Value").text == "—")
	view.player_name = "完整身份不会裁切".repeat(12)
	panel.call("apply_view", view)
	await process_frame
	await process_frame
	_check("更长身份扩展标题且属性不重叠", card.get_node("AttributeRows").position.y >= card.get_node("InspectionLabel").position.y + card.get_node("InspectionLabel").size.y + 17.0)
	_check("更长身份向上扩展卡且底边稳定", card.size.y > 188.0 and is_equal_approx(card.get_global_rect().end.y, 582.0))
	gallery.call("configure", 7, Vector2i(1280, 720), "focus")
	await process_frame
	await process_frame
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_card_clicks += 1)
	_click(card.get_global_rect().get_center())
	await process_frame
	_check("可见浮卡接收鼠标并阻挡输入", _card_clicks == 1 and card.mouse_filter == Control.MOUSE_FILTER_STOP)
	(panel.call("get_inspection_control") as Control).release_focus()
	_mouse_move(Vector2(8, 8))
	await process_frame
	await process_frame
	_check("鼠标离开且无焦点时卡关闭", not card.visible)
	_check("隐藏卡退出顶部与鼠标阻挡查询", is_equal_approx(float(panel.call("get_content_top_y")), 596.0) and (panel.call("get_input_blocking_rects") as Array).size() == 1)


func _test_utility_composition(gallery: Control) -> void:
	gallery.call("configure", 5, Vector2i(1280, 720), "normal")
	await process_frame
	await process_frame
	var composition: Control = gallery.get_node("DesignRoot/BottomHudComposition") as Control
	var equipment: Control = composition.get_node("BottomRow/EquipmentHudPanel") as Control
	var grid: Control = composition.get_node("BottomRow/RelicGrid/VisualGrid") as Control
	var end: Control = composition.get_node("BottomRow/EndTurnControl") as Control
	var weapon: Button = equipment.get_node("WeaponSlot") as Button
	var armor: Button = equipment.get_node("ArmorSlot") as Button
	var potion: Button = equipment.get_node("PotionButton") as Button
	var end_button: Button = end.get_node("EndTurnButton") as Button
	_check("组合接入新装备场景", equipment.scene_file_path == "res://scenes/tactical/hud/m2/equipment_hud_panel.tscn")
	_check("组合接入新遗物场景", grid.get_parent().scene_file_path == "res://scenes/tactical/hud/m2/relic_grid.tscn")
	_check("组合接入新结束场景", end.scene_file_path == "res://scenes/tactical/hud/m2/end_turn_control.tscn")
	_check("装备两个52点击区", weapon.position == Vector2(10, 46) and armor.position == Vector2(66, 46) and weapon.size == Vector2(52, 52) and armor.size == Vector2(52, 52))
	_check("血瓶32点击区", potion.position == Vector2(86, 10) and potion.size == Vector2(32, 32))
	_check("遗物40槽与既定网格", grid.position == Vector2(14, 10) and grid.size == Vector2(250, 88) and grid.get_child_count() == 8)
	_check("结束点击区", end_button.position == Vector2(12, 28) and end_button.size == Vector2(52, 52))
	_check("结束回合文本", end.get_node("EndLabel").text == "结束回合")
	composition.connect("slot_requested", func(slot: String, content: String) -> void: _utility_requests.append(slot + ":" + content))
	composition.connect("potion_requested", func() -> void: _utility_requests.append("potion"))
	composition.connect("end_turn_requested", func() -> void: _utility_requests.append("end_turn"))
	composition.connect("end_move_requested", func() -> void: _utility_requests.append("end_move"))
	_click(weapon.get_global_rect().get_center())
	await process_frame
	_click(armor.get_global_rect().get_center())
	await process_frame
	_click(potion.get_global_rect().get_center())
	await process_frame
	_click(end_button.get_global_rect().get_center())
	await process_frame
	_check("预留装备不请求且血瓶结束请求保留", _utility_requests == ["potion", "end_turn"])
	weapon.grab_focus()
	_key(KEY_ENTER)
	await process_frame
	_check("预留装备键盘操作不请求", _utility_requests == ["potion", "end_turn"])
	_mouse_move(potion.get_global_rect().get_center())
	await process_frame
	_check("血瓶真实悬停状态", potion.find_child("HoverOverlay", true, false).visible)
	var press := InputEventMouseButton.new()
	press.position = potion.get_global_rect().get_center()
	press.global_position = press.position
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press)
	await process_frame
	_check("血瓶真实按下状态", potion.find_child("PressedShade", true, false).visible)
	press = press.duplicate() as InputEventMouseButton
	press.pressed = false
	root.push_input(press)
	await process_frame
	gallery.call("configure", 6, Vector2i(1280, 720), "mixed")
	await process_frame
	await process_frame
	_check("结束移动文本", end.get_node("EndLabel").text == "结束移动")
	_click(end_button.get_global_rect().get_center())
	await process_frame
	_check("结束移动发正确请求", _utility_requests.back() == "end_move")
	gallery.call("configure", 7, Vector2i(1280, 720), "utility_disabled")
	await process_frame
	await process_frame
	var count_before: int = _utility_requests.size()
	for control: Control in [weapon, potion, end_button, grid.get_child(2), grid.get_child(6)]:
		_click(control.get_global_rect().get_center())
		await process_frame
	_check("禁用血瓶结束按钮和预留槽均不请求", _utility_requests.size() == count_before)
	for state: String in ["utility_hidden", "utility_invalid"]:
		gallery.call("configure", 5, Vector2i(1280, 720), state)
		await process_frame
		await process_frame
		var previous: int = _utility_requests.size()
		_click(end_button.get_global_rect().get_center())
		await process_frame
		_check("%s拒绝结束请求" % state, _utility_requests.size() == previous)
	for state: String in ["normal", "mixed", "compact", "focus", "missing", "utility_disabled", "utility_hidden", "utility_invalid", "utility_occupied"]:
		gallery.call("configure", 5, Vector2i(1280, 720), state)
		await process_frame
		await process_frame
		var controls: Array[Button] = [weapon, armor]
		for slot: Node in grid.get_children():
			controls.append(slot as Button)
		var request_count: int = _utility_requests.size()
		for slot: Button in controls:
			var view: RefCounted = slot.get("_view") as RefCounted
			_check("%s %s 保留空槽接口" % [state, slot.name], not view.slot_id.is_empty() and view.content_id.is_empty() and not view.occupied and view.icon_texture == null and view.empty_kind == &"")
			_check("%s %s 不锁定不可请求且无内容轮廓" % [state, slot.name], not view.locked and not view.can_request() and slot.disabled and not slot.find_child("IconRect", true, false).visible and not slot.find_child("EmptyGlyph", true, false).visible and not slot.find_child("LockGlyph", true, false).visible)
			_click(slot.get_global_rect().get_center())
			await process_frame
		_check("%s 全部装备遗物点击不请求" % state, _utility_requests.size() == request_count)
