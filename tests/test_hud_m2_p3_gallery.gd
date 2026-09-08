extends SceneTree

const SCENE_PATH := "res://scenes/dev/hud_m2_p3_gallery.tscn"
const CharacterView := preload("res://scripts/ui/hud/m2/character_hud_view_data.gd")
const MeterView := preload("res://scripts/ui/hud/value_meter_view_data.gd")

var _passed: int = 0
var _failed: int = 0
var _activated: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== test_hud_m2_p3_gallery ===")
	root.size = Vector2i(1280, 720)
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_check("新图库可以加载", packed != null)
	if packed == null:
		quit(1)
		return
	var gallery: Control = packed.instantiate() as Control
	root.add_child(gallery)
	await process_frame
	await process_frame
	await _test_layout(gallery)
	await _test_character(gallery)
	await _test_slots_and_input(gallery)
	gallery.queue_free()
	await process_frame
	print("HUD_M2_P3_GALLERY_RESULT passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _test_layout(gallery: Control) -> void:
	var composition: Control = gallery.get_node("DesignRoot/BottomHudComposition") as Control
	var row: HBoxContainer = composition.get_node("BottomRow") as HBoxContainer
	var positions: Array[int] = [32, 266, 402, 886, 1172]
	var widths: Array[int] = [226, 128, 476, 278, 76]
	for output_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		gallery.call("configure", 5, output_size)
		await process_frame
		await process_frame
		var scale_value: float = float(output_size.x) / 1280.0
		_check("%s 统一画布比例" % output_size, gallery.get_node("DesignRoot").scale == Vector2.ONE * scale_value)
		_check("%s 逻辑画布不变" % output_size, gallery.get_node("DesignRoot").size == Vector2(1280, 720))
		_check("%s 完整五区" % output_size, row.get_child_count() == 5)
		for index: int in 5:
			var component: Control = row.get_child(index) as Control
			_check("%s 区域%d边界" % [output_size, index], component.position + row.position == Vector2(positions[index], 596) and component.size == Vector2(widths[index], 108))
			_check("%s 区域%d原生位置" % [output_size, index], component.get_global_rect().position.is_equal_approx(Vector2(positions[index], 596) * scale_value))
		var strip: Control = composition.get_node("ActionResourceStrip") as Control
		_check("%s 行动条边界" % output_size, strip.position == Vector2(503, 550) and strip.size == Vector2(274, 40))
	for count: int in [5, 6, 7]:
		gallery.call("configure", count, Vector2i(1280, 720), "compact" if count == 7 else "normal")
		await process_frame
		await process_frame
		var slots: Array = gallery.call("get_skill_slots") as Array
		_check("%d个实际槽" % count, slots.size() == count)
		var side: float = 56.0 if count == 7 else 64.0
		var left: float = 402.0 + (476.0 - (side * count + 8.0 * (count - 1))) * 0.5
		for index: int in slots.size():
			var slot: Control = slots[index] as Control
			_check("%d槽第%d个尺寸位置" % [count, index], slot.size == Vector2.ONE * side and is_equal_approx(slot.get_global_rect().position.x, left + index * (side + 8.0)))
		var cost: Label = (slots[1] as Control).find_child("ResourceCostText", true, false) as Label
		_check("%d槽999数字容纳" % count, cost.text == "999" and cost.get_theme_font("font").get_string_size(cost.text, HORIZONTAL_ALIGNMENT_LEFT, -1, cost.get_theme_font_size("font_size")).x <= cost.size.x)
	var character: Control = gallery.call("get_character_panel") as Control
	var frame: StyleBoxTexture = character.get_node("PortraitFrame").get_theme_stylebox("panel") as StyleBoxTexture
	_check("组合人物区只使用共享外框", not character.get_node("MetalFrame").visible)
	_check("人物框消费获批轮廓并保留九宫格角部", frame != null and frame.texture.resource_path.ends_with("portrait-frame.png") and frame.texture_margin_left == 6.0 and frame.texture_margin_top == 6.0)
	_check("人物框原生素材保留透明角与顶部2px扩展", frame != null and frame.texture.get_image().get_pixel(0, 0).a < 1.0 and frame.expand_margin_top == 2.0 and not frame.draw_center)


func _test_character(gallery: Control) -> void:
	gallery.call("configure", 5, Vector2i(1280, 720))
	await process_frame
	var panel: Control = gallery.call("get_character_panel") as Control
	_check("头像框几何", _rect(panel, "PortraitFrame") == Rect2(12, 13, 72, 82))
	_check("头像内部裁切几何", _rect(panel, "PortraitContent") == Rect2(18, 19, 60, 70))
	var portrait: AtlasTexture = panel.get_node("PortraitContent").texture as AtlasTexture
	_check("头像使用原图运行时裁切", portrait != null and portrait.region == Rect2(160, 200, 220, 235))
	_check("信息列几何", _rect(panel, "InfoColumn") == Rect2(90, 13, 124, 82))
	_check("身份细边保留原坐标", _rect(panel, "InfoColumn/IdentityFrame") == Rect2(0, 0, 124, 20))
	_check("等级经验细边保留原坐标", _rect(panel, "InfoColumn/LevelExperienceRow") == Rect2(0, 24, 124, 22))
	_check("生命护盾细边保留原坐标", _rect(panel, "InfoColumn/SurvivalFrame") == Rect2(0, 50, 124, 32))
	_check("人物细边绘制层可见且不拦输入", panel.get_node("InfoColumn/InfoBorders").visible and panel.get_node("InfoColumn/InfoBorders").mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("经验轨道114乘2", _rect(panel, "InfoColumn/LevelExperienceRow/ExperienceTrack").size == Vector2(114, 2))
	_check("经验动态填充", is_equal_approx(panel.find_child("ExperienceFill", true, false).size.x, 114.0 * 0.34))
	_check("HP动态填充", is_equal_approx(panel.find_child("HpFill", true, false).size.x, 114.0 * 0.8))
	_check("SH动态填充", is_equal_approx(panel.find_child("ShieldFill", true, false).size.x, 114.0 * 0.75))
	for name: String in ["HpValue", "ShieldValue"]:
		_check("%s为11px数字" % name, panel.find_child(name, true, false).get_theme_font_size("font_size") == 11)
	gallery.call("configure", 6, Vector2i(1280, 720), "missing")
	await process_frame
	await process_frame
	_check("缺值身份", panel.find_child("IdentityLabel", true, false).text == "身份未提供")
	_check("缺值等级", panel.find_child("LevelLabel", true, false).text == "Lv.—")
	_check("缺值经验", panel.find_child("ExperienceValue", true, false).text == "—/— XP")
	_check("缺值护盾", panel.find_child("ShieldValue", true, false).text == "—/—")
	_check("已知真实HP仍保留", panel.find_child("HpValue", true, false).text == "160/200")
	_check("缺失经验护盾为空填充", panel.find_child("ExperienceFill", true, false).size.x == 0 and panel.find_child("ShieldFill", true, false).size.x == 0)
	_check("缺失头像使用轮廓", panel.get_node("PortraitContent").texture == null and panel.get_node("PortraitFallback").visible)
	_check("人物键盘焦点可检视", panel.get_node("PortraitInspectButton").has_focus() and panel.get_node("InspectionPanel").visible)
	var view := CharacterView.new()
	view.has_level = true
	view.level = 0
	view.hp = MeterView.new()
	view.hp.maximum_value = 200
	panel.call("apply_view", view)
	_check("已知零等级不变成缺值", panel.find_child("LevelLabel", true, false).text == "Lv.0")
	_check("已知零HP不变成缺值", panel.find_child("HpValue", true, false).text == "0/200")
	gallery.call("configure", 7, Vector2i(1280, 720), "focus")
	await process_frame
	await process_frame
	_check("长身份常驻列限制宽度", panel.find_child("IdentityLabel", true, false).size.x == 114.0)
	_check("检视保留完整长身份", "远行于群星与长夜之间的 fyc" in panel.find_child("InspectionLabel", true, false).text)
	var inspect_button: Button = panel.call("get_inspection_control") as Button
	inspect_button.release_focus()
	_mouse_move(inspect_button.get_global_rect().get_center())
	await process_frame
	_check("真实鼠标悬停可检视", panel.get_node("InspectionPanel").visible)
	_mouse_move(Vector2(8, 8))
	await process_frame
	_check("离开且无焦点后关闭检视", not panel.get_node("InspectionPanel").visible)


func _test_slots_and_input(gallery: Control) -> void:
	gallery.call("configure", 7, Vector2i(1280, 720), "compact")
	await process_frame
	await process_frame
	var slots: Array = gallery.call("get_skill_slots") as Array
	var composition: Control = gallery.get_node("DesignRoot/BottomHudComposition") as Control
	composition.connect("skill_activated", func(id: String) -> void: _activated.append(id))
	var pure: Button = slots[3] as Button
	_check("纯被动保留内容和凹槽", pure.find_child("IconRect", true, false).texture != null and pure.find_child("PassiveFrame", true, false).visible)
	_check("纯被动取消操作角标", not pure.find_child("HotkeyBadge", true, false).visible and not pure.find_child("ActionBadge", true, false).visible and not pure.find_child("ResourceCostBadge", true, false).visible)
	_check("混合被动保留999法力说明", (slots[1] as Control).find_child("ResourceCostText", true, false).text == "999" and "法力" in (slots[1] as Control).tooltip_text)
	_check("冷却与不可用不同层", (slots[2] as Control).find_child("CooldownShade", true, false).visible and (slots[4] as Control).find_child("UnavailableShade", true, false).visible)
	_check("选中可见", (slots[0] as Control).find_child("SelectedOverlay", true, false).visible)
	_check("明确无费用和非法金额不显示", not (slots[5] as Control).find_child("ResourceCostBadge", true, false).visible and not (slots[6] as Control).find_child("ResourceCostBadge", true, false).visible)
	_click((slots[0] as Control).get_global_rect().get_center())
	await process_frame
	_check("真实鼠标激活主动技能", _activated == ["fixture_slash"])
	_key(KEY_2)
	await process_frame
	_check("真实数字键激活被动可触发技能", _activated == ["fixture_slash", "fixture_counter"])
	var count_before: int = _activated.size()
	for index: int in [2, 3, 4]:
		_click((slots[index] as Control).get_global_rect().get_center())
		await process_frame
		_key(KEY_1 + index)
		await process_frame
	_check("冷却纯被动不可用均拒绝鼠标数字键", _activated.size() == count_before)
	(slots[1] as Control).grab_focus()
	_key(KEY_TAB)
	await process_frame
	_key(KEY_TAB)
	await process_frame
	_check("真实Tab键进入纯被动焦点（实际槽索引%d）" % slots.find(root.gui_get_focus_owner()), pure.has_focus() and pure.find_child("FocusOverlay", true, false).visible)
	_check("纯被动焦点显示可见说明", bool(pure.call("is_inspection_visible")) and (pure.call("get_inspection_panel") as Control).is_visible_in_tree())
	_check("纯被动说明显示已有内容", "纯被动示例" in str(pure.call("get_inspection_text")))
	var inspection_rect: Rect2 = (pure.call("get_inspection_panel") as Control).get_global_rect()
	_check("纯被动说明不遮挡行动条", not inspection_rect.intersects((composition.get_node("ActionResourceStrip") as Control).get_global_rect()))
	_check("纯被动说明不遮挡底栏", not inspection_rect.intersects((composition.get_node("BottomRow") as Control).get_global_rect()))
	_key(KEY_ENTER)
	await process_frame
	_check("纯被动Enter不能激活", _activated.size() == count_before)
	(slots[0] as Control).grab_focus()
	await process_frame
	_check("纯被动失焦关闭说明", not bool(pure.call("is_inspection_visible")))


func _rect(parent: Control, path: String) -> Rect2:
	var control: Control = parent.get_node(path) as Control
	return Rect2(control.position, control.size)


func _mouse_move(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion)


func _click(position: Vector2) -> void:
	_mouse_move(position)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event)


func _key(code: int, target_viewport: Viewport = null) -> void:
	var receiver: Viewport = root if target_viewport == null else target_viewport
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		receiver.push_input(event)


func _check(description: String, passed: bool) -> void:
	if passed:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: " + description)
