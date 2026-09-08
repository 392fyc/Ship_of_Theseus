extends SceneTree

const Adapter := preload("res://scripts/ui/hud/m2/dashboard_view_adapter.gd")
var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var state: Dictionary = _state("kensei", 65, 130, {"心": true, "道": false, "势": false})
	var before: Dictionary = state.duplicate(true)
	var views: Dictionary = Adapter.new().build(state)
	_check("真实显示载荷具有独立职业视图", views.has("class_resources"))
	_check("转换不修改源载荷", state == before)
	if views.has("class_resources"):
		var view: RefCounted = views["class_resources"]
		_check("无行动状态仍显示资源", view.visible)
		_check("动态上限精确值和相等低段", view.body.qi.display_text == "65/130" and view.body.band == &"low")
	_test_data_contract()
	await _test_manager_projection()
	await _test_visible_geometry_and_pointer()
	print("HUD_M2_CLASS_RESOURCES_RESULT passed=%d failed=%d" % [_passed, _failed])
	quit(1 if _failed else 0)


func _test_data_contract() -> void:
	var adapter := Adapter.new()
	for pair: Vector2i in [Vector2i(0, 100), Vector2i(1, 100), Vector2i(50, 100), Vector2i(51, 100), Vector2i(65, 130), Vector2i(66, 130)]:
		var source: Dictionary = _state("kensei", pair.x, pair.y, {"心": true, "道": false, "势": true})
		var before: Dictionary = source.duplicate(true)
		var view: RefCounted = adapter.build(source)["class_resources"]
		_check("边界%s精确值和连续比例" % pair, view.visible and view.body.qi.display_text == "%d/%d" % [pair.x, pair.y] and is_equal_approx(view.body.qi.ratio, float(pair.x) / pair.y))
		_check("边界%s保持上游分档" % pair, view.body.band == source["class_resource_display"]["qi_band"])
		_check("边界%s没有修改输入或伪造印记实体" % pair, source == before and view.body.marks.size() == 2 and view.body.marks[0]["display_text"] == "心" and view.body.marks[1]["display_text"] == "势" and view.body.marks.all(func(mark: Dictionary) -> bool: return mark["instance_id"] == "" and mark["special_marker"] == &""))
	for class_id: String in ["myrmidon", "kensei", "sword_immortal", "unknown_resource_class"]:
		var view: RefCounted = adapter.build(_state(class_id, 65, 100, {"心": true}))["class_resources"]
		_check(class_id + "资源独立可见且按身份选择印记", view.visible and view.body.marks_visible == (class_id == "kensei"))
		if class_id == "unknown_resource_class":
			_check("未知职业回退只注明真实qi来源", view.source_kind == &"runtime_qi_only" and view.body.marks.is_empty())
	for field: String in ["sword_qi", "sword_qi_max"]:
		for invalid: Variant in [null, "3", true, 1.5, INF, NAN, -1]:
			var state: Dictionary = _state("kensei", 65, 100)
			state[field] = invalid
			_check("拒绝非法数值%s=%s" % [field, invalid], not adapter.build(state)["class_resources"].visible)
	var partial: Dictionary = _state("kensei", 1, 100)
	partial["class_resource_display"].erase("qi_threshold_ratio")
	var partial_view: RefCounted = adapter.build(partial)["class_resources"]
	_check("缺阈值保留数值并隐藏线与分档", partial_view.visible and partial_view.body.threshold_ratio == -1.0 and partial_view.body.band == &"none")
	partial.erase("marks")
	partial_view = adapter.build(partial)["class_resources"]
	_check("缺印记源只隐藏印记部分", partial_view.visible and not partial_view.body.marks_visible)
	partial.erase("class_resource_display")
	partial_view = adapter.build(partial)["class_resources"]
	_check("缺profile不丢已有合法qi", partial_view.visible and not partial_view.body.marks_visible)
	_check("Unit无资源哨兵保持隐藏", not adapter.build(_state("goblin_melee", -1, 0))["class_resources"].visible)
	partial["visible"] = false
	_check("全局隐藏清空资源视图", not adapter.build(partial)["class_resources"].visible)


func _test_manager_projection() -> void:
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	scene.run_injected = true
	scene.debug_harness_enabled = false
	scene.injected_map_id = "forest_01"
	scene.injected_player_units = [{"class_id": "kensei", "pos": Vector2i(0, 2), "level": 1}, {"class_id": "myrmidon", "pos": Vector2i(1, 2), "level": 1}]
	scene.injected_enemy_units = [{"class_id": "goblin_melee", "pos": Vector2i(6, 3)}]
	root.add_child(scene)
	await process_frame
	await process_frame
	var manager: Object = scene.tactical_manager
	for unit: Node in manager.units:
		manager._inspected_unit = unit
		var state: Dictionary = manager.get_dashboard_data()
		var before: Dictionary = state.duplicate(true)
		var resource: RefCounted = Adapter.new().build(state)["class_resources"]
		var metadata: Dictionary = state["class_resource_display"]
		_check("真实manager职业身份与容量 " + unit.unit_id, metadata["class_id"] == unit.unit_id and metadata["mark_capacity"] == unit._mark_max)
		_check("真实manager单位资源可见性 " + unit.unit_id, resource.visible == (unit._qi_max > 0))
		if unit._qi_max > 0:
			_check("真实manager数值完整转发 " + unit.unit_id, resource.body.qi.current_value == unit.sword_qi and resource.body.qi.maximum_value == unit._qi_max and resource.body.marks_visible == (unit.unit_id == "kensei"))
			for amount: int in [50, 51]:
				unit.set_sword_qi(amount)
				var changed: Dictionary = manager.get_dashboard_data()
				_check("manager真实分档%s:%d" % [unit.unit_id, amount], changed["class_resource_display"]["qi_band"] == (&"low" if amount * 100 <= unit._qi_max * unit._xinyan_qi_ratio_threshold_pct else &"high"))
		_check("真实manager转换没有副作用 " + unit.unit_id, state == before)
	manager.stop_battle()
	_check("manager无单位显示元数据为空", manager.get_dashboard_data().get("class_resource_display") == {})
	scene.queue_free()
	await process_frame


func _test_visible_geometry_and_pointer() -> void:
	var dashboard: Control = load("res://scripts/ui/hud/m2/runtime_dashboard.gd").new()
	root.add_child(dashboard)
	await process_frame
	var composition: Control = dashboard.get_composition()
	var host: Control = composition.get_class_resource_host()
	var shared: Control = composition.get_shared_frame()
	_check("资源宿主与五区同级", host.get_parent() == composition and composition.get_node("BottomRow").get_child_count() == 5)
	for resources: bool in [false, true]:
		for actions: bool in [false, true]:
			var state: Dictionary = _visual_state(actions)
			if not resources:
				state["sword_qi"] = -1
				state["sword_qi_max"] = 0
			dashboard.update_state(state)
			await process_frame
			await process_frame
			var expected: StringName = (&"panel_resources" if actions else &"collapsed_resources") if resources else (&"panel" if actions else &"collapsed")
			_check("四组合%s/%s共享皮肤" % [resources, actions], shared.get_frame_style() == composition.get_skin_theme().get_stylebox(expected, &"HudM2SharedFrame") and host.visible == resources)
			_check("四组合%s/%s行动独立" % [resources, actions], composition.get_node("ActionResourceStrip").visible == actions)
			_check("四组合%s/%s轮廓空角透传" % [resources, actions], not shared._has_point(Vector2(392, 550)) and not shared._has_point(Vector2(450, 560)) and shared._has_point(Vector2(48, 556)) == resources)
			_move_pointer(Vector2(392, 550))
			await process_frame
			_check("四组合%s/%s实际肩角透传" % [resources, actions], root.gui_get_hovered_control() == null and not _point_blocked(dashboard, Vector2(392, 550)))
			if resources:
				_check("A资源位置不随行动改变", host.get_global_rect() == Rect2(32, 540, 366, 56))
				_move_pointer(Vector2(48, 556))
				await process_frame
				_check("实际资源实心区域阻挡", root.gui_get_hovered_control() != null and _point_blocked(dashboard, Vector2(48, 556)))
	for pair: Vector2i in [Vector2i(0, 100), Vector2i(1, 100), Vector2i(50, 100), Vector2i(51, 100), Vector2i(65, 100), Vector2i(65, 130), Vector2i(66, 130), Vector2i(100, 100)]:
		dashboard.update_state(_state("kensei", pair.x, pair.y, {"势": true}))
		await process_frame
		var renderer: Control = host.get_renderer()
		_check("实际填充%s保持连续" % pair, is_equal_approx(renderer.get_node("QiFill").size.x, 210.0 * pair.x / pair.y))
		_check("实际标签%s显示精确值" % pair, renderer.get_node("QiValue").text == "%d/%d" % [pair.x, pair.y])
		_check("印记压紧且空槽补在右侧", renderer.get_node("Mark0").text == "势" and renderer.get_node("Mark1").text.is_empty() and renderer.get_node("Mark2").text.is_empty())
	dashboard.update_state(_visual_state(true))
	await process_frame
	await process_frame
	var character: Control = composition.get_node("BottomRow/CharacterHudPanel")
	var card: Control = character.get_inspection_panel()
	_move_pointer(Vector2(140, 650))
	await process_frame
	await process_frame
	_check("A人物卡底边526且资源无交叠", card.visible and is_equal_approx(card.get_global_rect().end.y, 526.0) and not card.get_global_rect().intersects(host.get_global_rect()))
	for y: int in [600, 594, 580, 560, 542, 534, 528, 524, 510]:
		_move_pointer(Vector2(140, y))
		await process_frame
		await process_frame
		_check("连续实际鼠标经过资源进入人物卡y=%d" % y, card.visible)
	_move_pointer(Vector2(900, 300))
	await process_frame
	await process_frame
	_check("移到战场关闭人物卡", not card.visible)
	var slots: Array = composition.get_node("BottomRow/SkillShelf").get_skill_slots()
	var slot: Control = slots[0]
	_move_pointer(slot.get_global_rect().get_center())
	await process_frame
	await process_frame
	var skill_card: Control = slot.get_inspection_panel()
	_check("A最左技能卡底边532且不重叠资源", skill_card.visible and is_equal_approx(skill_card.get_global_rect().end.y, 532.0) and not skill_card.get_global_rect().intersects(host.get_global_rect()))
	_check("最长说明保持实际文本完整且增加高度", skill_card.size.y > 104.0 and slot.get_inspection_text().contains("长说明末行") and skill_card.get_node("InspectionLabel").get_rect().end.y <= skill_card.size.y - 12.0)
	_check("技能受控面板阻挡且原生tooltip关闭", dashboard.get_input_blocking_rects().has(skill_card.get_global_rect()) and slot.get_tooltip() == "")
	_move_pointer(skill_card.get_global_rect().get_center())
	await process_frame
	await process_frame
	_check("鼠标可留在技能说明卡中", skill_card.visible and root.gui_get_hovered_control() != null)
	_move_pointer(Vector2(900, 300))
	await process_frame
	await process_frame
	slot = slots[1]
	slot.grab_focus()
	await process_frame
	_check("主动技能焦点也使用受控说明", slot.is_inspection_visible())
	root.gui_release_focus()
	dashboard.queue_free()
	await process_frame


func _visual_state(actions: bool) -> Dictionary:
	var state: Dictionary = _state("kensei", 65, 100, {"心": true, "势": true})
	state["show_actions"] = actions
	state["skills_visible"] = true
	state["action_resources"] = {"movement_remaining": 4, "movement_available": true, "standard_capacity": 1, "standard_remaining": 1, "swift_capacity": 1, "swift_remaining": 1}
	state["skills"] = []
	for index: int in 7:
		state["skills"].append({"skill_id": "fixture_%d" % index, "name": "技能显示夹具", "description": "完整说明第一行\n第二行\n第三行\n第四行\n第五行\n第六行\n第七行\n长说明末行", "is_passive": index == 0, "available": true})
	return state


func _move_pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event, true)


func _point_blocked(dashboard: Control, point: Vector2) -> bool:
	for rect: Rect2 in dashboard.get_input_blocking_rects():
		if rect.has_point(point):
			return true
	return false


func _state(class_id: String, current: int, maximum: int, marks: Dictionary = {}) -> Dictionary:
	return {"visible": true, "show_actions": false, "mode": "player",
		"sword_qi": current, "sword_qi_max": maximum, "marks": marks.duplicate(),
		"class_resource_display": {"class_id": class_id, "mark_capacity": 3,
			"qi_threshold_ratio": 0.5, "qi_band": &"low" if current * 2 <= maximum else &"high"}}


func _check(label: String, passed: bool) -> void:
	if passed:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + label)
