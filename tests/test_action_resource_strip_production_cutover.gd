extends SceneTree
## HUD-PROD-1C：正式 ActionResourceStrip 切换回归。

const DASHBOARD_SCENE_PATH := "res://scenes/tactical/bottom_dashboard.tscn"
const TACTICAL_SCENE_PATH := "res://scenes/tactical/TacticalScene.tscn"
const STRIP_SCENE_PATH := "res://scenes/tactical/hud/action_resource_strip.tscn"
const RESOURCE_FIELDS: Array[String] = [
	"movement_remaining", "movement_available", "standard_capacity",
	"standard_remaining", "swift_capacity", "swift_remaining",
]

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
func _initialize() -> void:
	print("=== test_action_resource_strip_production_cutover ===")
	call_deferred("_run")


func _run() -> void:
	await _test_standalone_facade()
	await _test_tactical_data_chain()
	_finish()


func _test_standalone_facade() -> void:
	var packed: PackedScene = load(DASHBOARD_SCENE_PATH) as PackedScene
	var dashboard: BottomDashboard = packed.instantiate() as BottomDashboard if packed != null else null
	_check("正式 BottomDashboard 可实例化", dashboard != null)
	if dashboard == null:
		return
	dashboard.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	dashboard.size = Vector2(1280.0, 720.0)
	root.add_child(dashboard)
	await process_frame
	await process_frame
	_check("正式门面声明资源条属性", _has_property(dashboard, "_action_resource_strip"))
	if not _has_property(dashboard, "_action_resource_strip"):
		dashboard.queue_free()
		await process_frame
		return
	var strip: Control = dashboard.get("_action_resource_strip") as Control
	_check("正式门面创建冻结候选实例", strip != null and strip.scene_file_path == STRIP_SCENE_PATH)
	_eq("冻结候选实例严格唯一", _count_scene_instances(dashboard, STRIP_SCENE_PATH), 1)
	_eq("初始资源条隐藏", strip.visible if strip != null else true, false)
	_eq("正式实例阻止鼠标穿透", strip.mouse_filter if strip != null else -1, Control.MOUSE_FILTER_STOP)
	await _assert_stylebox_isolation(strip)

	var valid_state: Dictionary = _state_with_resources({
		"movement_remaining": 6,
		"movement_available": true,
		"standard_capacity": 1,
		"standard_remaining": 1,
		"swift_capacity": 1,
		"swift_remaining": 1,
	})
	var original: Dictionary = valid_state.duplicate(true)
	dashboard.update_state(valid_state)
	await process_frame
	_eq("门面不修改输入状态", valid_state, original)
	_check("合法六字段显示资源条", strip.visible)
	var view: RefCounted = strip.get("_view") as RefCounted
	_check("门面创建私有 ViewData", view != null)
	if view != null:
		for field: String in RESOURCE_FIELDS:
			_eq("ViewData 映射 %s" % field, view.get(field), valid_state["action_resources"][field])
	_eq("正式资源条固定尺寸", strip.size, Vector2(274.0, 40.0))
	_eq("资源条与技能栏净距", dashboard._skill_bar.position.y - (strip.position.y + strip.size.y), 6.0)
	_eq("资源条与技能栏水平居中", strip.position.x + strip.size.x * 0.5,
		dashboard._skill_bar.position.x + dashboard._skill_bar.size.x * 0.5)
	await _assert_content_top_y(dashboard, strip, valid_state)
	_assert_invalid_states_hide(dashboard, strip, valid_state)
	dashboard.update_state(valid_state)
	await process_frame
	_assert_all_controls_focus_none(strip)
	await _assert_mouse_blocking(dashboard, strip, valid_state)
	dashboard.queue_free()
	await process_frame


func _assert_stylebox_isolation(strip: Control) -> void:
	var source: Control = (load(STRIP_SCENE_PATH) as PackedScene).instantiate() as Control
	root.add_child(source)
	await process_frame
	await process_frame
	_eq("冻结源场景保留忽略鼠标", source.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	var source_style: StyleBoxTexture = source.get_theme_stylebox(&"panel") as StyleBoxTexture
	var instance_style: StyleBoxTexture = strip.get_theme_stylebox(&"panel") as StyleBoxTexture
	_check("源与正式实例均使用纹理 StyleBox", source_style != null and instance_style != null)
	if source_style != null and instance_style != null:
		_eq("冻结源上内容边距保持 5", source_style.content_margin_top, 5.0)
		_eq("冻结源下内容边距保持 5", source_style.content_margin_bottom, 5.0)
		_check("正式实例具有专属 StyleBox 覆盖", strip.has_theme_stylebox_override(&"panel"))
		_check("正式实例 StyleBox 与冻结源不是同一对象", instance_style != source_style)
		_eq("正式实例上内容边距为 2", instance_style.content_margin_top, 2.0)
		_eq("正式实例下内容边距为 2", instance_style.content_margin_bottom, 2.0)
		_eq("正式实例保留冻结源纹理", instance_style.texture, source_style.texture)
	# 同一环境完成字体布局后，内部高 36；源边距 5+5 得 46，实例边距 2+2 得 40。
	_eq("冻结源内部组合最小高度为 36", (source.get_node("Margin") as Control).get_combined_minimum_size().y, 36.0)
	_eq("正式实例内部组合最小高度为 36", (strip.get_node("Margin") as Control).get_combined_minimum_size().y, 36.0)
	_eq("冻结源组合最小尺寸为 274×46", source.get_combined_minimum_size(), Vector2(274.0, 46.0))
	_eq("正式实例组合最小尺寸为 274×40", strip.get_combined_minimum_size(), Vector2(274.0, 40.0))
	_eq("正式实例实际尺寸为 274×40", strip.size, Vector2(274.0, 40.0))

	# 冻结组合场景同样用实例样式覆盖维持批准高度 40；正式门面复制源 StyleBox 后覆盖。
	var composition: Control = (load("res://scenes/tactical/hud/bottom_hud_composition.tscn") as PackedScene).instantiate() as Control
	root.add_child(composition)
	await process_frame
	await process_frame
	var composed_strip: Control = composition.get_node("ActionResourceStrip") as Control
	var composed_style: StyleBoxTexture = composed_strip.get_theme_stylebox(&"panel") as StyleBoxTexture
	_check("冻结组合使用资源条实例覆盖", composed_strip.scene_file_path == STRIP_SCENE_PATH
		and composed_strip.has_theme_stylebox_override(&"panel"))
	_eq("冻结组合实例上内容边距为 2", composed_style.content_margin_top, 2.0)
	_eq("冻结组合实例下内容边距为 2", composed_style.content_margin_bottom, 2.0)
	_eq("冻结组合资源条最小尺寸为 274×40", composed_strip.get_combined_minimum_size(), Vector2(274.0, 40.0))
	_eq("冻结组合资源条实际尺寸为 274×40", composed_strip.size, Vector2(274.0, 40.0))
	composition.queue_free()
	source.queue_free()
	await process_frame


func _assert_content_top_y(dashboard: BottomDashboard, strip: Control, valid_state: Dictionary) -> void:
	var other_panels: Array[Control] = [dashboard._info_panel, dashboard._relic_panel, dashboard._action_shell]
	var previous_visibility: Array[bool] = []
	for panel: Control in other_panels:
		previous_visibility.append(panel.visible)
		panel.hide()
	var skill_was_visible: bool = dashboard._skill_bar.visible
	dashboard._skill_bar.show()
	await process_frame
	_check("显示态资源条高于剩余可见技能栏", strip.position.y < dashboard._skill_bar.position.y)
	_eq("显示态内容顶边精确等于资源条顶边", dashboard.get_content_top_y(), strip.position.y)

	dashboard.update_state(valid_state.merged({"show_actions": false}, true))
	await process_frame
	for panel: Control in other_panels:
		panel.hide()
	dashboard._skill_bar.show()
	_check("隐藏态资源条确实隐藏", not strip.visible)
	var expected_top: float = dashboard.size.y
	for panel: Control in [dashboard._info_panel, dashboard._relic_panel, dashboard._action_shell, dashboard._skill_bar]:
		if panel.visible:
			expected_top = minf(expected_top, panel.position.y)
	_check("隐藏态预期顶边与资源条顶边不同", expected_top > strip.position.y)
	_eq("隐藏态内容顶边只取剩余可见控件", dashboard.get_content_top_y(), expected_top)

	dashboard.update_state(valid_state)
	for index: int in other_panels.size():
		other_panels[index].visible = previous_visibility[index]
	dashboard._skill_bar.visible = skill_was_visible
	await process_frame


func _test_tactical_data_chain() -> void:
	var scene: Node = (load(TACTICAL_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var manager: Object = scene.tactical_manager
	var dashboard: BottomDashboard = scene._bottom_dashboard
	var unit: Unit = manager._get_dashboard_unit() if manager != null else null
	_check("真实 TacticalScene 提供单位与门面", manager != null and dashboard != null and unit != null)
	if manager == null or dashboard == null or unit == null or not _has_property(dashboard, "_action_resource_strip"):
		scene.queue_free()
		await process_frame
		return
	var strip: Control = dashboard.get("_action_resource_strip") as Control
	var expected_movement: int = maxi(0, unit.stats.mov)
	unit.reset_action_resources()
	await _apply_manager_data(manager, dashboard)
	_assert_resource_state("默认容量", strip, expected_movement, true, 1, 1, 1, 1)
	unit.consume_movement_resource()
	unit.consume_standard_resource()
	await _apply_manager_data(manager, dashboard)
	_assert_resource_state("正式消费", strip, expected_movement, false, 1, 0, 1, 1)
	unit.configure_action_resource_capacities(2, 1)
	unit.consume_standard_resource()
	await _apply_manager_data(manager, dashboard)
	_assert_resource_state("标准容量二", strip, expected_movement, true, 2, 1, 1, 1)
	unit.configure_action_resource_capacities(3, 1)
	unit.consume_standard_resource()
	unit.consume_standard_resource()
	await _apply_manager_data(manager, dashboard)
	_assert_resource_state("标准容量三", strip, expected_movement, true, 3, 1, 1, 1)
	unit.configure_action_resource_capacities(1, 3)
	unit.consume_swift_resource()
	await _apply_manager_data(manager, dashboard)
	_assert_resource_state("迅捷容量三部分消费", strip, expected_movement, true, 1, 1, 3, 2)
	unit.consume_swift_resource()
	unit.consume_swift_resource()
	await _apply_manager_data(manager, dashboard)
	_assert_resource_state("迅捷容量三耗尽", strip, expected_movement, true, 1, 1, 3, 0)
	scene.queue_free()
	await process_frame


func _apply_manager_data(manager: Object, dashboard: BottomDashboard) -> void:
	var data: Dictionary = manager.get_dashboard_data()
	var resources: Dictionary = data.get("action_resources", {}) as Dictionary
	_eq("正式载荷只含六字段", resources.keys().size(), RESOURCE_FIELDS.size())
	for field: String in RESOURCE_FIELDS:
		_check("正式载荷具有 %s" % field, resources.has(field))
	dashboard.update_state(data.merged({"visible": true, "mode": "player", "show_actions": true}, true))
	await process_frame


func _assert_resource_state(label: String, strip: Control, movement: int, movement_available: bool,
		standard_capacity: int, standard_remaining: int, swift_capacity: int, swift_remaining: int) -> void:
	_check("%s 条可见" % label, strip.visible)
	_eq("%s 固定尺寸" % label, strip.size, Vector2(274.0, 40.0))
	var view: RefCounted = strip.get("_view") as RefCounted
	if view != null:
		_eq("%s 移动力" % label, view.get("movement_remaining"), movement)
		_eq("%s 移动可用" % label, view.get("movement_available"), movement_available)
		_eq("%s 标准容量" % label, view.get("standard_capacity"), standard_capacity)
		_eq("%s 标准剩余" % label, view.get("standard_remaining"), standard_remaining)
		_eq("%s 迅捷容量" % label, view.get("swift_capacity"), swift_capacity)
		_eq("%s 迅捷剩余" % label, view.get("swift_remaining"), swift_remaining)
	var standard: Array = strip.call("get_standard_pips") as Array
	var swift: Array = strip.call("get_swift_pips") as Array
	_eq("%s 标准点数量" % label, standard.size(), standard_capacity)
	_eq("%s 迅捷点数量" % label, swift.size(), swift_capacity)
	_eq("%s 标准点消费态" % label, _spent_states(standard), _expected_spent(standard_capacity, standard_remaining))
	_eq("%s 迅捷点消费态" % label, _spent_states(swift), _expected_spent(swift_capacity, swift_remaining))
	var footprint: Control = strip.get_node("Margin/MainRow/MovementZone/MovementCluster/FootprintGlyph") as Control
	var movement_value: Label = strip.get_node("Margin/MainRow/MovementZone/MovementCluster/MovementValue") as Label
	_eq("%s 移动数值保持" % label, movement_value.text, str(movement))
	_eq("%s 足迹灰化" % label, bool(footprint.get("spent")), not movement_available)
	for zone_name: String in ["MovementZone", "StandardZone", "SwiftZone"]:
		var zone: PanelContainer = strip.get_node("Margin/MainRow/%s" % zone_name) as PanelContainer
		_check("%s %s 保留完整分区边框" % [label, zone_name], zone != null
			and zone.theme_type_variation == &"ActionResourceSegment"
			and zone.get_theme_stylebox(&"panel") != null)


func _assert_invalid_states_hide(dashboard: BottomDashboard, strip: Control, valid_state: Dictionary) -> void:
	var invalid_states: Array[Dictionary] = [
		valid_state.merged({"visible": false}, true),
		valid_state.merged({"mode": "enemy"}, true),
		valid_state.merged({"mode": "unknown"}, true),
		valid_state.merged({"show_actions": false}, true),
		valid_state.merged({"action_resources": null}, true),
		valid_state.merged({"action_resources": []}, true),
	]
	for field: String in RESOURCE_FIELDS:
		var missing: Dictionary = valid_state.duplicate(true)
		var missing_resources: Dictionary = missing["action_resources"] as Dictionary
		missing_resources.erase(field)
		invalid_states.append(missing)
	var malformed: Array[Dictionary] = [
		{"movement_remaining": 1.5}, {"movement_remaining": "6"}, {"movement_remaining": true},
		{"movement_available": 1}, {"movement_remaining": -1},
		{"standard_capacity": 0}, {"standard_capacity": 4}, {"standard_remaining": -1}, {"standard_remaining": 2},
		{"swift_capacity": 0}, {"swift_capacity": 4}, {"swift_remaining": -1}, {"swift_remaining": 2},
	]
	for patch: Dictionary in malformed:
		var malformed_state: Dictionary = valid_state.duplicate(true)
		(malformed_state["action_resources"] as Dictionary).merge(patch, true)
		invalid_states.append(malformed_state)
	for invalid_state: Dictionary in invalid_states:
		dashboard.update_state(invalid_state)
		_check("非法载荷立即隐藏", not strip.visible)


func _assert_mouse_blocking(dashboard: BottomDashboard, strip: Control, valid_state: Dictionary) -> void:
	var probe: ColorRect = ColorRect.new()
	probe.color = Color(0.0, 0.0, 0.0, 0.0)
	probe.mouse_filter = Control.MOUSE_FILTER_STOP
	probe.size = dashboard.size
	dashboard.add_child(probe)
	dashboard.move_child(probe, 0)
	var probe_count: Array[int] = [0]
	var strip_count: Array[int] = [0]
	probe.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			probe_count[0] += 1)
	_connect_gui_input(strip, func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			strip_count[0] += 1)
	dashboard.update_state(valid_state.merged({"show_actions": false}, true))
	if dashboard._visibility_tween != null and dashboard._visibility_tween.is_running():
		await dashboard._visibility_tween.finished
	await process_frame
	var rect: Rect2 = strip.get_global_rect()
	for point: Vector2 in _hit_points(rect):
		probe_count[0] = 0
		await _send_click(point)
		_eq("隐藏态探针接收每点点击", probe_count[0], 1)
	dashboard.update_state(valid_state)
	if dashboard._visibility_tween != null and dashboard._visibility_tween.is_running():
		await dashboard._visibility_tween.finished
	await process_frame
	for point: Vector2 in _hit_points(strip.get_global_rect()):
		probe_count[0] = 0
		strip_count[0] = 0
		await _send_click(point)
		var hovered: Control = root.gui_get_hovered_control()
		_check("显示态五点悬停资源条子树", hovered != null and _is_descendant_or_self(strip, hovered))
		_check("显示态五点触发资源条 gui_input", strip_count[0] > 0)
		_eq("显示态五点不穿透探针", probe_count[0], 0)
	probe.queue_free()
	await process_frame


func _send_click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	var press := InputEventMouseButton.new()
	press.position = point
	press.global_position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	var release := InputEventMouseButton.new()
	release.position = point
	release.global_position = point
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	root.push_input(release, true)
	await process_frame


func _hit_points(rect: Rect2) -> Array[Vector2]:
	return [rect.get_center(), Vector2(rect.position.x + 2.0, rect.get_center().y),
		Vector2(rect.end.x - 2.0, rect.get_center().y), Vector2(rect.get_center().x, rect.position.y + 2.0),
		Vector2(rect.get_center().x, rect.end.y - 2.0)]


func _connect_gui_input(node: Node, callback: Callable) -> void:
	var control: Control = node as Control
	if control != null:
		control.gui_input.connect(callback)
	for child: Node in node.get_children():
		_connect_gui_input(child, callback)


func _is_descendant_or_self(ancestor: Node, candidate: Node) -> bool:
	return candidate == ancestor or ancestor.is_ancestor_of(candidate)


func _assert_all_controls_focus_none(node: Node) -> void:
	var control: Control = node as Control
	if control != null:
		_eq("资源条控件不获取键盘焦点：%s" % control.name, control.focus_mode, Control.FOCUS_NONE)
	for child: Node in node.get_children():
		_assert_all_controls_focus_none(child)


func _state_with_resources(resources: Dictionary) -> Dictionary:
	return {"visible": true, "mode": "player", "show_actions": true, "action_resources": resources}


func _count_scene_instances(node: Node, scene_path: String) -> int:
	var total: int = 1 if node.scene_file_path == scene_path else 0
	for child: Node in node.get_children():
		total += _count_scene_instances(child, scene_path)
	return total


func _expected_spent(capacity: int, remaining: int) -> Array[bool]:
	var result: Array[bool] = []
	for index: int in capacity:
		result.append(index >= remaining)
	return result


func _spent_states(nodes: Array) -> Array[bool]:
	var result: Array[bool] = []
	for node: Variant in nodes:
		result.append(bool((node as Object).get("spent")))
	return result


func _has_property(value: Object, property_name: String) -> bool:
	for property: Dictionary in value.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _finish() -> void:
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
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
