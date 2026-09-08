extends SceneTree

const M2View := preload("res://scripts/ui/hud/m2/skill_slot_view_data.gd")
const ShelfScene: PackedScene = preload("res://scenes/tactical/hud/m2/skill_shelf.tscn")

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	_run.call_deferred()


func _run() -> void:
	await _test_shelf_contract()
	print("test_hud_m2_skill_shelf_integration: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _fixture(index: int) -> M2View:
	var view := M2View.new()
	view.skill_id = "fixture_%d" % index
	view.active_capable = true
	view.enabled = true
	view.hotkey_text = str(index + 1)
	view.tooltip_text = "技能夹具"
	view.icon_texture = GradientTexture2D.new()
	return view


func _test_shelf_contract() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var shelf: Panel = ShelfScene.instantiate()
	root.add_child(shelf)
	await process_frame
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		root.size = viewport_size
		var factor: float = viewport_size.x / 1280.0
		shelf.scale = Vector2.ONE * factor
		shelf.position = Vector2(402, 596) * factor
		_check("%dx%d技能架1/%s缩放" % [viewport_size.x, viewport_size.y, factor], shelf.get_global_rect().is_equal_approx(Rect2(Vector2(402, 596) * factor, Vector2(476, 108) * factor)))
		for count: int in range(0, 8):
			var views: Array[RefCounted] = []
			for index: int in count:
				views.append(_fixture(index))
			shelf.apply_skills(views)
			await process_frame
			await process_frame
			var slots: Array = shelf.get_skill_slots()
			_check("%dx%d %d项真实数量" % [viewport_size.x, viewport_size.y, count], slots.size() == count)
			if count > 0 and not slots.is_empty():
				var extent: float = 56.0 if count == 7 else 64.0
				var group_width: float = count * extent + (count - 1) * 8.0
				var expected_first: Vector2 = shelf.global_position + Vector2((476.0 - group_width) / 2.0, (108.0 - extent) / 2.0) * factor
				_check("%dx%d %d项槽尺寸" % [viewport_size.x, viewport_size.y, count], slots[0].get_global_rect().size.is_equal_approx(Vector2(extent, extent) * factor))
				_check("%dx%d %d项全局居中" % [viewport_size.x, viewport_size.y, count], slots[0].global_position.is_equal_approx(expected_first))
				if count > 1:
					_check("%dx%d %d项全局间距8" % [viewport_size.x, viewport_size.y, count], is_equal_approx(slots[1].global_position.x - slots[0].global_position.x, (extent + 8.0) * factor))

	root.size = Vector2i(1280, 720)
	shelf.scale = Vector2.ONE
	shelf.position = Vector2(402, 596)
	var activated: Array[String] = []
	shelf.skill_activated.connect(func(id: String) -> void: activated.append(id))
	var action_views: Array[RefCounted] = [_fixture(0), _fixture(1)]
	shelf.apply_skills(action_views)
	await process_frame
	await process_frame
	_check("正式宿主提供数字键开关", shelf.has_method("set_shortcut_input_enabled"))
	if not shelf.has_method("set_shortcut_input_enabled") or shelf.get_skill_slots().size() != 2:
		shelf.queue_free()
		await process_frame
		return
	if shelf.has_method("set_shortcut_input_enabled"):
		shelf.call("set_shortcut_input_enabled", false)
		await _key(KEY_1)
		_check("关闭开关时数字键不激活", activated.is_empty())
		shelf.call("set_shortcut_input_enabled", true)
		await _key(KEY_1)
		_check("默认图库行为数字键激活", activated == ["fixture_0"])
	var slot: Button = shelf.get_skill_slots()[0]
	await _click(slot.get_global_rect().get_center())
	_check("鼠标点击激活回归", activated == ["fixture_0", "fixture_0"])
	var focus_slot: Button = shelf.get_skill_slots()[1]
	focus_slot.grab_focus()
	await _key(KEY_ENTER)
	_check("键盘焦点激活回归", activated == ["fixture_0", "fixture_0", "fixture_1"])
	shelf.queue_free()
	await process_frame


func _click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame


func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + label)
