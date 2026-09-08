extends "res://tests/test_hud_m2_p3_gallery.gd"

const HOVER_POINTS: Dictionary = {
	"头像": Vector2(48, 54), "身份": Vector2(150, 23),
	"等级": Vector2(110, 45), "经验": Vector2(180, 45),
	"HP": Vector2(170, 72), "SH": Vector2(170, 86),
	"左上边距": Vector2(2, 2), "右下边距": Vector2(224, 106),
	"头像信息间距": Vector2(87, 54),
}


func _run() -> void:
	print("=== test_hud_m2_character_hover ===")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var gallery: Control = (load(SCENE_PATH) as PackedScene).instantiate() as Control
	root.add_child(gallery)
	await process_frame
	await process_frame
	await _test_character_hover(gallery)
	await _test_resource_obstacles(gallery)
	gallery.queue_free()
	await process_frame
	print("HUD_M2_CHARACTER_HOVER_RESULT passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _test_character_hover(gallery: Control) -> void:
	var panel: Control = gallery.call("get_character_panel") as Control
	var button: Button = panel.call("get_inspection_control") as Button
	var card: Control = panel.call("get_inspection_panel") as Control
	_check("同一透明入口覆盖226乘108", button.position == Vector2.ZERO and button.size == Vector2(226, 108))
	for output_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		root.size = output_size
		gallery.call("configure", 5, output_size, "normal")
		_move_pointer(root, Vector2(8, 8))
		await process_frame
		await process_frame
		var factor: float = float(output_size.x) / 1280.0
		_check("%s常态隐藏" % output_size, not card.visible)
		for point_name: String in HOVER_POINTS:
			_move_pointer(root, panel.get_global_rect().position + (HOVER_POINTS[point_name] as Vector2) * factor)
			await process_frame
			await process_frame
			_check("%s%s真实鼠标显示卡" % [output_size, point_name], card.visible)
			_check("%s%s显示卡几何" % [output_size, point_name], card.get_global_rect().is_equal_approx(Rect2(Vector2(32, 394) * factor, Vector2(304, 188) * factor)))
		_check("%s只有身份与八属性" % output_size, card.get_node("AttributeRows").get_child_count() == 8 and card.get_node("InspectionLabel").text == "剑圣 · fyc")
		_check("%s卡仍参与避让与阻挡" % output_size, is_equal_approx(float(panel.call("get_content_top_y")), 394.0 * factor) and (panel.call("get_input_blocking_rects") as Array).has(card.get_global_rect()))
		_move_pointer(root, card.get_global_rect().get_center())
		await process_frame
		await process_frame
		_check("%s鼠标在浮卡时保持" % output_size, card.visible and card.mouse_filter == Control.MOUSE_FILTER_STOP)
		for outside: Vector2 in [Vector2(280, 620), Vector2(640, 320), Vector2(259, 650)]:
			_move_pointer(root, outside * factor)
			await process_frame
			await process_frame
			_check("%s装备棋盘与外间距不触发" % output_size, not card.visible)
		_key(KEY_TAB)
		await process_frame
		_check("%s真实Tab焦点保留检视" % output_size, button.has_focus() and card.visible)
		button.release_focus()
		await process_frame
		_check("%s释放焦点后隐藏" % output_size, not card.visible)
	root.size = Vector2i(1280, 720)
	gallery.call("configure", 5, Vector2i(1280, 720), "normal")
	await process_frame
	await process_frame
	var hp_point := Vector2(202, 668)
	_move_pointer(root, hp_point)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = hp_point
		event.global_position = hp_point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame
	await process_frame
	_check("点击不锁定键盘焦点", not button.has_focus())
	_move_pointer(root, Vector2(640, 320))
	await process_frame
	await process_frame
	_check("点击后移出仍会关闭", not card.visible)


func _move_pointer(viewport: Viewport, point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	viewport.push_input(event, true)


func _test_resource_obstacles(gallery: Control) -> void:
	var panel: Control = gallery.get_character_panel()
	var card: Control = panel.get_inspection_panel()
	var obstacles: Array[Rect2] = [Rect2(32, 540, 366, 56)]
	panel.set_inspection_obstacles(obstacles)
	_move_pointer(root, Vector2(140, 650))
	await process_frame
	await process_frame
	_check("A资源出现时人物卡完整向上避让", card.visible and card.get_global_rect() == Rect2(32, 338, 304, 188))
	for y: int in [590, 575, 552, 534, 520, 480]:
		_move_pointer(root, Vector2(140, y))
		await process_frame
		await process_frame
		_check("人物经过资源与间隙保持检视%d" % y, card.visible)
	_move_pointer(root, Vector2(900, 300))
	await process_frame
	await process_frame
	_check("离开过渡路径关闭人物卡", not card.visible)
	obstacles.clear()
	panel.set_inspection_obstacles(obstacles)
