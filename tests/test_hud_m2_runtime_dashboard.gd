extends SceneTree

const RuntimeDashboard := preload("res://scripts/ui/hud/m2/runtime_dashboard.gd")

var _passed: int = 0
var _failed: int = 0
var _equipment_requests: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== test_hud_m2_runtime_dashboard ===")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var manager: Object = scene.tactical_manager
	var dashboard: Control = scene.get("_bottom_dashboard") as Control
	_check("运行环境读取正式M2实例", dashboard is RuntimeDashboard)
	await process_frame
	await _test_reserved_equipment(dashboard, manager)
	await _test_player_state(dashboard, manager)
	await _test_sizes_and_inspection(dashboard)
	await _test_enemy_and_no_action(dashboard, manager)
	scene.queue_free()
	await process_frame
	print("HUD_M2_RUNTIME_DASHBOARD_RESULT passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_reserved_equipment(dashboard: Control, manager: Object) -> void:
	var composition: Control = dashboard.get_composition()
	composition.slot_requested.connect(func(slot: String, content: String) -> void: _equipment_requests.append(slot + ":" + content))
	var icons: Dictionary = _real_skill_icons()
	icons["verified_weapon_texture"] = GradientTexture2D.new()
	dashboard.set_icon_textures(icons)
	for mode: String in ["player", "enemy"]:
		var state: Dictionary = manager.get_dashboard_data().duplicate(true)
		state["mode"] = mode
		state["weapon_display"] = {"content_id": "verified_weapon_texture", "display_name": "有效武器显示数据"}
		var before: Dictionary = state.duplicate(true)
		dashboard.update_state(state)
		await process_frame
		var equipment: Node = composition.get_node("BottomRow/EquipmentHudPanel")
		var slots: Array[Button] = [equipment.get_node("WeaponSlot") as Button, equipment.get_node("ArmorSlot") as Button]
		for slot: Node in composition.get_node("BottomRow/RelicGrid/VisualGrid").get_children():
			slots.append(slot as Button)
		for slot: Button in slots:
			var view: RefCounted = slot.get("_view") as RefCounted
			_check(mode + " " + str(slot.name) + " 实际渲染保持预留接口", not view.slot_id.is_empty() and view.content_id.is_empty() and not view.occupied and view.icon_texture == null and view.empty_kind == &"" and not view.locked and not view.can_request())
			_check(mode + " " + str(slot.name) + " 无装备图和占位轮廓", slot.disabled and not slot.find_child("IconRect", true, false).visible and not slot.find_child("EmptyGlyph", true, false).visible and not slot.find_child("LockGlyph", true, false).visible)
			await _click(slot.get_global_rect().get_center())
		_check(mode + " 装备和遗物点击不发请求", _equipment_requests.is_empty())
		_check(mode + " 完整武器源载荷未改变", state == before and dashboard.get_last_state() == before)
	dashboard.update_state(manager.get_dashboard_data())
	await process_frame


func _test_player_state(dashboard: Control, manager: Object) -> void:
	var composition: Control = dashboard.get_composition()
	_check("运行时仅创建一个固定组合", composition != null and composition.get_parent() == dashboard)
	_check("宿主默认关闭技能架数字键", not composition.get_node("BottomRow/SkillShelf").shortcut_input_enabled)
	_check("真实载荷显示五区和行动条", composition.visible and composition.get_node("ActionResourceStrip").visible)
	var character: Control = composition.get_node("BottomRow/CharacterHudPanel") as Control
	var character_card: Control = character.get_inspection_panel()
	var portrait_image: TextureRect = character.get_node("PortraitContent") as TextureRect
	var portrait_frame: Control = character.get_node("PortraitFrame") as Control
	_check("真实剑圣显示头像而非轮廓占位", portrait_image.texture is AtlasTexture and not character.get_node("PortraitFallback").visible)
	_check("头像图像铺到画框内缘", portrait_image.position.x <= portrait_frame.position.x + 1.0 and portrait_image.position.y <= portrait_frame.position.y + 3.0 and portrait_image.get_rect().end.x >= portrait_frame.get_rect().end.x - 1.0 and portrait_image.get_rect().end.y >= portrait_frame.get_rect().end.y - 1.0)
	var portrait_button: Button = character.get_inspection_control()
	_check("只有头像区域承担属性查看入口", portrait_button.get_rect() == Rect2(12, 13, 72, 82))
	_move_pointer(character.get_inspection_control().get_global_rect().get_center())
	await process_frame
	_check("人物栏真实鼠标移入展开信息卡", character_card.visible and dashboard.get_input_blocking_rects().has(character_card.get_global_rect()))
	var sword: Control = composition.get_class_resource_host()
	_check("属性卡位于人物栏上方且避开剑气槽", character_card.get_global_rect().end.y < character.get_global_rect().position.y and not character_card.get_global_rect().intersects(sword.get_global_rect()))
	_check("属性卡显示中文标签与实时数值", (character_card.get_node("AttributeRows/STR/Key") as Label).text == "力量" and (character_card.get_node("AttributeRows/STR/Value") as Label).text == str(manager.get_dashboard_data()["stats"]["str"]))
	var travel_x: float = portrait_button.get_global_rect().get_center().x
	var bridge_stayed_open: bool = true
	for y: int in range(int(portrait_button.get_global_rect().get_center().y), int(character_card.get_global_rect().get_center().y), -8):
		_move_pointer(Vector2(travel_x, float(y)))
		await process_frame
		bridge_stayed_open = bridge_stayed_open and character_card.visible
	_check("从头像逐步经过空隙和剑气区域到属性卡时不闪退", bridge_stayed_open)
	_move_pointer(portrait_button.get_global_rect().get_center())
	await process_frame
	var diagonal_start: Vector2 = portrait_button.get_global_rect().get_center()
	var diagonal_end: Vector2 = character_card.get_global_rect().position + Vector2(character_card.size.x * 0.75, character_card.size.y * 0.8)
	var diagonal_stayed_open: bool = true
	for step: int in range(1, 31):
		_move_pointer(diagonal_start.lerp(diagonal_end, float(step) / 30.0))
		await process_frame
		diagonal_stayed_open = diagonal_stayed_open and character_card.visible
	_check("从头像斜向移到属性卡右列时不闪退", diagonal_stayed_open)
	_move_pointer(character_card.get_global_rect().get_center())
	await process_frame
	_check("鼠标进入属性卡后保持展开", character_card.visible)
	_move_pointer(character.get_global_rect().position + Vector2(150, 55))
	await process_frame
	_check("鼠标仅经过人物栏文字不会展开属性卡", not character_card.visible)
	portrait_button.grab_focus()
	await process_frame
	_check("键盘聚焦头像可查看属性", character_card.visible)
	portrait_button.release_focus()
	await process_frame
	_check("键盘离开头像收起属性卡", not character_card.visible)
	_move_pointer(Vector2(640.0, 320.0))
	await process_frame
	_check("人物栏真实鼠标移出收起信息卡", not character_card.visible)
	_move_pointer(Vector2(640.0, 320.0))
	await process_frame
	_check("棋盘空白鼠标不被全屏宿主或组合背景阻挡", root.gui_get_hovered_control() == null and scene_allows_board_pointer())
	var end_button: Button = composition.get_node("BottomRow/EndTurnControl/EndTurnButton") as Button
	var phase_before: Variant = manager.input_state
	await _click(end_button.get_global_rect().get_center())
	await process_frame
	_check("真实鼠标结束操作请求到管理器", manager.input_state != phase_before)
	_check("结束移动后正式M2保持可见", dashboard.visible and dashboard.get_composition().visible)
	var slots: Array = composition.get_node("BottomRow/SkillShelf").get_skill_slots()
	_check("真实技能由正式catalog解析图片", slots.size() > 1 and (slots[0] as Control).find_child("IconRect", true, false).texture != null)
	var preserved_slot: Control = slots[0] as Control
	preserved_slot.grab_focus()
	dashboard.update_state(manager.get_dashboard_data())
	await process_frame
	_check("同一状态刷新复用技能控件并保持焦点", (composition.get_node("BottomRow/SkillShelf").get_skill_slots() as Array)[0] == preserved_slot and preserved_slot.has_focus())
	var entries: Array = manager.get_dashboard_data().get("skills", [])
	var active_index: int = -1
	for index: int in entries.size():
		var entry: Dictionary = entries[index] as Dictionary
		if bool(entry.get("available", false)) and not bool(entry.get("is_passive", false)):
			active_index = index
			break
	_check("真实载荷存在可用主动技能", active_index >= 0)
	var before_skill: String = manager.get_selected_skill_id()
	if active_index >= 0:
		await _click((slots[active_index] as Control).get_global_rect().get_center())
	await process_frame
	_check("真实鼠标技能槽请求到管理器", active_index >= 0 and manager.get_selected_skill_id() != before_skill)
	_check("鼠标技能后正式M2保持可见", dashboard.visible and dashboard.get_composition().visible)
	manager.request_cancel_action()
	await process_frame
	var key_before: String = manager.get_selected_skill_id()
	_key(KEY_1)
	await process_frame
	_check("真实数字键单次选择技能", key_before.is_empty() and not manager.get_selected_skill_id().is_empty())
	_check("数字键后正式M2保持可见", dashboard.visible and dashboard.get_composition().visible)
	var changed: Dictionary = manager.get_dashboard_data().duplicate(true)
	if active_index >= 0:
		(changed["skills"] as Array)[active_index]["available"] = false
		dashboard.update_state(changed)
		await process_frame
		_check("状态字段变化复用控件并更新可用性", (composition.get_node("BottomRow/SkillShelf").get_skill_slots() as Array)[active_index] == slots[active_index] and (slots[active_index] as Control).disabled)
		dashboard.update_state(manager.get_dashboard_data())
	_check("宿主自身不占满屏鼠标", dashboard.mouse_filter == Control.MOUSE_FILTER_IGNORE and composition.mouse_filter == Control.MOUSE_FILTER_IGNORE)


func _test_sizes_and_inspection(dashboard: Control) -> void:
	var composition: Control = dashboard.get_composition()
	root.gui_release_focus()
	_move_pointer(Vector2(900, 300))
	for output_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		root.size = output_size
		dashboard.update_state(dashboard.get_last_state())
		await process_frame
		await process_frame
		var factor: float = float(output_size.x) / 1280.0
		var row: Control = composition.get_node("BottomRow") as Control
		var positions: Array[float] = [32.0, 266.0, 402.0, 886.0, 1172.0]
		var widths: Array[float] = [226.0, 128.0, 476.0, 278.0, 76.0]
		for index: int in row.get_child_count():
			var zone: Control = row.get_child(index) as Control
			_check("%s五区%d全局几何" % [output_size, index], zone.get_global_rect().position.is_equal_approx(Vector2(positions[index], 596.0) * factor) and zone.get_global_rect().size.is_equal_approx(Vector2(widths[index], 108.0) * factor))
		var strip: Control = composition.get_node("ActionResourceStrip") as Control
		_check("%s行动条全局几何" % output_size, strip.get_global_rect().position.is_equal_approx(Vector2(503.0, 550.0) * factor) and strip.get_global_rect().size.is_equal_approx(Vector2(274.0, 40.0) * factor))
		var host_offset := Vector2(17.0, -11.0)
		var strip_before_translation: Rect2 = strip.get_global_rect()
		dashboard.position = host_offset
		await process_frame
		var shifted_blockers: Array[Rect2] = dashboard.get_input_blocking_rects()
		var shifted_strip: Rect2 = strip.get_global_rect()
		var resource: Control = composition.get_class_resource_host()
		var expected_top: float = resource.get_global_rect().position.y if resource.visible else shifted_strip.position.y
		_check("%s宿主平移后阻挡矩形保持全局坐标" % output_size, shifted_strip.position.is_equal_approx(strip_before_translation.position + host_offset) and shifted_blockers.has(shifted_strip) and is_equal_approx(dashboard.get_content_top_y(), expected_top))
		if resource.visible:
			_check("%s职业资源按宿主同步缩放" % output_size, resource.get_global_rect().size.is_equal_approx(Vector2(366, 56) * factor) and _point_in_rectangles(shifted_blockers, resource.get_global_rect().position + Vector2(16, 16) * factor))
		dashboard.position = Vector2.ZERO
		await process_frame
		var character: Control = composition.get_node("BottomRow/CharacterHudPanel") as Control
		var inspect_button: Button = character.get_inspection_control()
		inspect_button.grab_focus()
		await process_frame
		var card: Control = character.get_inspection_panel()
		var blockers: Array[Rect2] = dashboard.get_input_blocking_rects()
		_check("%s人物浮卡采用全局矩形并参与阻挡" % output_size, card.visible and blockers.has(card.get_global_rect()))
		_check("%s顶部避让来自可见浮卡" % output_size, is_equal_approx(dashboard.get_content_top_y(), card.get_global_rect().position.y))
		inspect_button.release_focus()
		await process_frame
	root.size = Vector2i(1280, 720)
	dashboard.update_state(dashboard.get_last_state())
	await process_frame
	var passive_slot: Control = (composition.get_node("BottomRow/SkillShelf").get_skill_slots() as Array)[0] as Control
	passive_slot.grab_focus()
	await process_frame
	var passive_card: Control = passive_slot.get_inspection_panel()
	var passive_label: Label = passive_card.find_child("InspectionLabel", true, false) as Label
	_check("真实纯被动说明向上增高且不越框", passive_card.visible and passive_card.size.x == 260.0 and passive_card.size.y > 104.0 and passive_label.position.y >= 12.0 and passive_label.position.y + passive_label.size.y <= passive_card.size.y - 12.0)
	_move_pointer(passive_card.get_global_rect().get_center())
	await process_frame
	_check("可见纯被动浮卡实际阻挡鼠标", passive_card.mouse_filter == Control.MOUSE_FILTER_STOP and not scene_allows_board_pointer())
	passive_slot.release_focus()
	_move_pointer(Vector2(640.0, 320.0))
	await process_frame
	_check("移开浮卡且释放焦点后收起", not passive_card.visible)


func _test_enemy_and_no_action(dashboard: Control, manager: Object) -> void:
	var player_state: Dictionary = manager.get_dashboard_data().duplicate(true)
	player_state["show_actions"] = false
	dashboard.update_state(player_state)
	await process_frame
	_check("真实玩家无行动态保留已有资源", dashboard.get_composition().get_class_resource_host().visible == (int(player_state.get("sword_qi_max", 0)) > 0))
	var enemy: Object = manager.units.filter(func(unit: Object) -> bool: return unit.faction == "enemy")[0]
	var enemy_screen: Vector2 = manager.get_viewport().get_canvas_transform() * manager.grid.grid_to_world(enemy.grid_position)
	await _right_click(Vector2(640.0, 320.0))
	await _click(enemy_screen)
	await process_frame
	var composition: Control = dashboard.get_composition()
	_check("敌方保持五区位置但不显示行动条", composition.visible and not composition.get_node("ActionResourceStrip").visible)
	_check("切换无资源敌人不残留玩家资源", composition.get_class_resource_host().visible == (int(manager.get_dashboard_data().get("sword_qi_max", 0)) > 0))
	_check("敌方按skills_visible隐藏技能且结束区保留外框", (composition.get_node("BottomRow/SkillShelf").get_skill_slots() as Array).is_empty() and composition.get_node("BottomRow/EndTurnControl").visible and not composition.get_node("BottomRow/EndTurnControl/EndTurnButton").visible and not composition.get_node("BottomRow/EndTurnControl/EndLabel").visible)
	await _right_click(enemy_screen)
	await process_frame
	_check("真实右键退出敌方检视", str(manager.get_dashboard_data().get("mode", "")) == "player")
	var no_action: Dictionary = manager.get_dashboard_data().duplicate(true)
	no_action["show_actions"] = false
	no_action["skills"] = []
	dashboard.update_state(no_action)
	await process_frame
	_check("无行动无虚假技能槽", (composition.get_node("BottomRow/SkillShelf").get_skill_slots() as Array).is_empty())
	var resource_host: Control = composition.get_class_resource_host()
	var expected_top: float = resource_host.get_global_rect().position.y if resource_host.visible else composition.get_node("BottomRow").get_global_rect().position.y
	_check("无行动回退到当前可见内容顶部", dashboard.get_content_top_y() == expected_top)
	dashboard.update_state({"visible": false})
	await process_frame
	_check("无可见内容返回视口底边且无阻挡", is_equal_approx(dashboard.get_content_top_y(), root.get_visible_rect().end.y) and dashboard.get_input_blocking_rects().is_empty())


func _real_skill_icons() -> Dictionary:
	return {
		"swordsman_xinyan": load("res://assets/prototype/hud_m2/skill-xinyan.png"),
		"swordsman_zhanji": load("res://assets/prototype/hud_m2/skill-zhanji.png"),
		"swordsman_yishan": load("res://assets/prototype/hud_m2/skill-yishan.png"),
		"swordsman_zhaojia": load("res://assets/prototype/hud_m2/skill-zhaojia.png"),
		"swordsman_juhe": load("res://assets/prototype/hud_m2/skill-juhe.png"),
	}


func _point_in_rectangles(rectangles: Array[Rect2], point: Vector2) -> bool:
	return rectangles.any(func(rectangle: Rect2) -> bool: return rectangle.has_point(point))


func _click(position: Vector2) -> void:
	_move_pointer(position)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


func _right_click(position: Vector2) -> void:
	_move_pointer(position)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


func _move_pointer(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	root.push_input(event, true)


func _key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		event.keycode = keycode
		event.pressed = pressed
		root.push_input(event, true)


func scene_allows_board_pointer() -> bool:
	for node: Node in root.get_children():
		if node.has_method("_should_ignore_board_pointer"):
			return not bool(node.call("_should_ignore_board_pointer"))
	return false


func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + label)
