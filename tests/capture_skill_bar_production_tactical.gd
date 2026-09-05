extends SceneTree
## 捕获真实角色配置；仅通过正式选择和结束移动入口切换状态。

const CAPTURE_ROOT := "res://dev_doc/ui-art-research/hud-prod-1d-skill-bar-cutover/evidence/"
var _scene: Node
var _dashboard: BottomDashboard
var _manager: Object
var _captures: Array = []
var _resolution := Vector2i(1280, 720)


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--capture-skill-bar") or DisplayServer.get_name().to_lower() == "headless":
		push_error("请使用窗口模式及 --capture-skill-bar 参数")
		quit(1)
		return
	root.gui_embed_subwindows = true
	call_deferred("_run")


func _run() -> void:
	_resolution = root.size
	if _resolution not in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		_fail("捕获分辨率不在任务范围")
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_ROOT)) != OK:
		_fail("无法创建本次证据目录")
		return
	var metadata_path: String = CAPTURE_ROOT.path_join("capture-metadata.json")
	if FileAccess.file_exists(metadata_path):
		var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(metadata_path)) as Dictionary
		_captures = previous.get("captures", [])
	_scene = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	_dashboard = _scene._bottom_dashboard
	_manager = _scene.tactical_manager
	await _settle()
	if not await _save("default"):
		return
	if _resolution == Vector2i(1280, 720):
		_manager.request_end_move()
		await _settle()
		var selected_slot: Button = _find_slot("swordsman_zhanji")
		await _click(selected_slot.get_global_rect().get_center())
		await _settle()
		if _manager._selected_skill_id != "swordsman_zhanji" or not _find_slot("swordsman_zhanji").get_node("Content/SelectedOverlay").visible:
			_fail("真实GUI未选择斩击")
			return
		if not await _save("selected"):
			return
		_manager.request_cancel_action()
		await _settle()
		var unavailable: Button = _find_slot("swordsman_juhe")
		if not unavailable.disabled or not "剑气不足" in unavailable.tooltip_text:
			_fail("真实居合未提供剑气不足状态")
			return
		if not await _save("unavailable"):
			return
		unavailable = _find_slot("swordsman_juhe")
		var expected_tooltip: String = unavailable.tooltip_text
		_move_pointer(unavailable.get_global_rect().get_center())
		await create_timer(1.0).timeout
		var actual_tooltip: Label = _find_visible_label(root, expected_tooltip)
		if root.gui_get_hovered_control() != unavailable or actual_tooltip == null:
			_fail("实际悬停未显示原生限宽tooltip")
			return
		if not await _save("tooltip", actual_tooltip):
			return
	var metadata: Dictionary = {
		"task_id": "HUD-PROD-1D-ICON-LABELS",
		"source_scene": "scenes/tactical/TacticalScene.tscn",
		"starting_head": "80452bf696dcc7c086f4263298e5793ada5bf3e4",
		"godot_version": Engine.get_version_info().string,
		"captures": _captures,
		"character_configuration": "真实TacticalScene剑圣配置，未注入合成技能数量。",
	}
	var file: FileAccess = FileAccess.open(metadata_path, FileAccess.WRITE)
	if file == null:
		_fail("无法写捕获元数据")
		return
	file.store_string(JSON.stringify(metadata, "  ") + "\n")
	file.close()
	_scene.queue_free()
	print("SKILL_BAR_CAPTURE_OK=%dx%d" % [_resolution.x, _resolution.y])
	quit(0)


func _save(state: String, tooltip: Label = null) -> bool:
	var bar: SkillBar = _dashboard._skill_bar
	var strip: Control = _dashboard._action_resource_strip
	var gap: float = bar.position.y - strip.position.y - strip.size.y
	if bar.size != Vector2(476.0, 108.0) or strip.size != Vector2(274.0, 40.0) or gap != 6.0:
		_fail("技能架或资源条尺寸/间距不匹配")
		return false
	if bar.get_global_rect().get_center().x != strip.get_global_rect().get_center().x:
		_fail("技能架与资源条未对齐")
		return false
	var source_costs: Dictionary = {}
	for entry: Dictionary in _manager.get_dashboard_data().skills:
		source_costs[entry.skill_id] = entry.get("resource_cost_display", {})
	var visible_skills: Array[Dictionary] = []
	for slot: Button in bar._list.get_children():
		var view: RefCounted = slot.get("_view")
		var action_label: Label = slot.get_node("Content/ActionTypeLabel") as Label
		var resource_label: Label = slot.get_node("Content/CostLabel") as Label
		var action_rect: Rect2 = action_label.get_rect()
		var resource_rect: Rect2 = resource_label.get_rect()
		visible_skills.append({"skill_id": view.skill_id, "name": slot.get("_title"),
			"hotkey": view.hotkey_text, "enabled": view.enabled, "disabled": slot.disabled,
			"selected": view.selected, "cooldown": view.cooldown_turns, "passive": view.passive,
			"action_type_text": action_label.text, "resource_cost_text": resource_label.text,
			"resource_cost_display": source_costs.get(view.skill_id, {}),
			"action_type_visible": action_label.is_visible_in_tree(), "resource_cost_visible": resource_label.is_visible_in_tree(),
			"action_type_rect": [action_rect.position.x, action_rect.position.y, action_rect.size.x, action_rect.size.y],
			"resource_cost_rect": [resource_rect.position.x, resource_rect.position.y, resource_rect.size.x, resource_rect.size.y],
			"badge_rect_coordinate_space": "slot_content_local", "size": [slot.size.x, slot.size.y]})
	await RenderingServer.frame_post_draw
	var capture: Image = root.get_texture().get_image()
	if capture == null or capture.get_size() != _resolution:
		_fail("原始图像分辨率不匹配")
		return false
	var path: String = CAPTURE_ROOT.path_join("skill_bar_%s_%dx%d.png" % [state, _resolution.x, _resolution.y])
	if capture.save_png(ProjectSettings.globalize_path(path)) != OK:
		_fail("保存原始PNG失败")
		return false
	var saved: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	if saved == null or saved.get_size() != _resolution:
		_fail("PNG回读验证失败")
		return false
	var record: Dictionary = {
		"path": path.trim_prefix("res://"), "resolution": [_resolution.x, _resolution.y],
		"sha256": FileAccess.get_sha256(path), "state": state, "skill_entries": visible_skills,
		"skill_shelf_size": [bar.size.x, bar.size.y], "action_resource_size": [strip.size.x, strip.size.y],
		"gap": gap, "tooltip_visible": tooltip != null,
	}
	if tooltip != null:
		record["tooltip_text"] = tooltip.text
		record["tooltip_content_width"] = tooltip.size.x
		record["tooltip_trigger"] = "root.push_input鼠标悬停后，原生tooltip自动出现。"
	for index: int in range(_captures.size() - 1, -1, -1):
		if _captures[index].path == record.path:
			_captures.remove_at(index)
	_captures.append(record)
	print("SKILL_BAR_CAPTURED=" + path)
	return true


func _find_slot(skill_id: String) -> Button:
	for slot: Button in _dashboard._skill_bar._list.get_children():
		if slot.get("_view").skill_id == skill_id:
			return slot
	return null


func _find_visible_label(node: Node, text: String) -> Label:
	if node is Label and node.text == text and node.is_visible_in_tree():
		return node as Label
	for child: Node in node.get_children(true):
		var found: Label = _find_visible_label(child, text)
		if found != null:
			return found
	return null


func _settle() -> void:
	if _dashboard._visibility_tween != null and _dashboard._visibility_tween.is_running():
		await _dashboard._visibility_tween.finished
	await process_frame
	await process_frame
	await process_frame


func _move_pointer(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)


func _click(point: Vector2) -> void:
	_move_pointer(point)
	var press := InputEventMouseButton.new()
	press.position = point
	press.global_position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	var release: InputEventMouseButton = press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await process_frame


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
