extends SceneTree
const CaptureMetadata := preload("res://tests/claude_review/capture_metadata.gd")
## 在真实 TacticalScene 中捕获行动资源栏的视觉证据。
##
## 运行：Godot_console.exe --path <project-root> \
##   --script res://tests/capture_action_resource_bar_tactical.gd -- --capture-action-resources

const CAPTURE_ROOT := "user://visual_style_playground/action_resource_bar_tactical/"
const CAPTURE_NAMES := [
	"action_resources_all_available.png",
	"action_resources_mixed_spent.png",
]
const CAPTURE_WIDTH := 1280
const CAPTURE_HEIGHT := 720
const CAPTURE_RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]

var _capture_directory := ""


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			_capture_directory = arg.trim_prefix("--output=")
	if not OS.get_cmdline_user_args().has("--capture-action-resources"):
		print("ACTION_RESOURCE_CAPTURE_ARGUMENT_ERROR=missing --capture-action-resources")
		quit(1)
		return
	if DisplayServer.get_name().to_lower() == "headless":
		print("ACTION_RESOURCE_CAPTURE_UNSUPPORTED_HEADLESS=use windowed Godot console")
		quit(1)
		return
	root.borderless = true
	root.size = Vector2i(CAPTURE_WIDTH, CAPTURE_HEIGHT)
	call_deferred("_capture_all")


func _capture_all() -> void:
	if not _prepare_capture_directory():
		quit(1)
		return
	var tactical_scene := load("res://scenes/tactical/TacticalScene.tscn") as PackedScene
	if tactical_scene == null:
		push_error("Unable to load TacticalScene")
		quit(1)
		return
	var scene := tactical_scene.instantiate()
	if scene == null:
		push_error("Unable to instantiate TacticalScene")
		quit(1)
		return
	root.add_child(scene)
	await process_frame
	await process_frame

	var tactical_manager: Object = scene.tactical_manager
	var dashboard: Control = scene._bottom_dashboard as Control
	var unit: Unit = tactical_manager._get_dashboard_unit() if tactical_manager != null else null
	if tactical_manager == null or dashboard == null or unit == null:
		push_error("TacticalScene did not provide the tactical manager, dashboard, and current unit")
		scene.queue_free()
		quit(1)
		return

	unit.reset_action_resources()
	scene._refresh_dashboard()
	var success := await _capture_state(scene, tactical_manager, dashboard, unit,
		CAPTURE_NAMES[0], false, false, false)
	if success:
		unit.consume_movement_resource()
		unit.consume_standard_resource()
		scene._refresh_dashboard()
		success = await _capture_state(scene, tactical_manager, dashboard, unit,
			CAPTURE_NAMES[1], true, true, false)

	scene.queue_free()
	if not success:
		quit(1)
		return
	print("ACTION_RESOURCE_CAPTURE_DIR=%s" % _capture_directory)
	quit(0)


func _prepare_capture_directory() -> bool:
	if _capture_directory.is_empty():
		var batch_name := "batch_%d_%d_%d" % [
			int(Time.get_unix_time_from_system()), OS.get_process_id(), Time.get_ticks_usec(),
		]
		_capture_directory = ProjectSettings.globalize_path(CAPTURE_ROOT.path_join(batch_name))
	if not _capture_directory.is_absolute_path():
		push_error("Capture output must be an absolute directory")
		return false
	var make_result := DirAccess.make_dir_recursive_absolute(_capture_directory)
	if make_result != OK:
		push_error("Cannot create capture directory: %s (error %d)" % [_capture_directory, make_result])
		return false
	return true


func _capture_state(scene: Node, tactical_manager: Object, dashboard: Control, unit: Unit,
		file_name: String, movement_spent: bool, standard_spent: bool, swift_spent: bool) -> bool:
	var capture_group: String = file_name.get_basename()
	for resolution: Vector2i in CAPTURE_RESOLUTIONS:
		root.size = resolution
		await process_frame
		await process_frame
		var composition: Control = dashboard.call("get_composition") as Control
		var resource_bar: Control
		var skill_bar: Control
		if composition != null:
			resource_bar = composition.get_node_or_null("ActionResourceStrip") as Control
			skill_bar = composition.get_node_or_null("BottomRow/SkillShelf") as Control
		if not _validate_capture_state(tactical_manager, resource_bar, skill_bar, unit,
			movement_spent, standard_spent, swift_spent):
			return false
		await RenderingServer.frame_post_draw
		var viewport: Viewport = root
		var image := viewport.get_texture().get_image()
		if image == null:
			push_error("Root viewport did not provide a capture image")
			return false
		if image.get_size() != resolution or root.size != resolution:
			push_error("Capture size must be %dx%d, got %dx%d" % [
				resolution.x, resolution.y, image.get_width(), image.get_height()])
			return false
		var output_name: String = "%s-%dx%d.png" % [capture_group, resolution.x, resolution.y]
		var output_path := _capture_directory.path_join(output_name)
		var save_result := CaptureMetadata.save_png(root, image, output_path, {"capture_group": capture_group})
		if save_result != OK:
			push_error("Cannot save capture: %s (error %d)" % [output_path, save_result])
			return false
		print("ACTION_RESOURCE_CAPTURED=%s" % output_path)
	return true


func _validate_capture_state(tactical_manager: Object, resource_bar: Control, skill_bar: Control,
		unit: Unit, movement_spent: bool, standard_spent: bool, swift_spent: bool) -> bool:
	if resource_bar == null or skill_bar == null:
		push_error("Action resource bar or skill bar is unavailable")
		return false
	if not resource_bar.visible:
		push_error("Action resource bar must be visible before capture")
		return false
	var action_rect: Rect2 = resource_bar.get_global_rect()
	var skill_rect: Rect2 = skill_bar.get_global_rect()
	if action_rect.end.y > skill_rect.position.y:
		push_error("Action resource bar must be above the skill bar before capture")
		return false
	if not _has_expected_spent_state(resource_bar, "movement", movement_spent) \
			or not _has_expected_spent_state(resource_bar, "standard", standard_spent) \
			or not _has_expected_spent_state(resource_bar, "swift", swift_spent):
		push_error("Action resource bar segment state did not match capture state")
		return false
	if unit.movement_used != movement_spent or unit.standard_used != standard_spent \
			or unit.swift_used != swift_spent:
		push_error("Current unit resource state did not match capture state")
		return false
	if _map_has_action_badges(tactical_manager):
		push_error("Map StatusIcons must not contain M/A/S action badges")
		return false
	return true


func _has_expected_spent_state(resource_bar: Control, resource_id: String, expected_spent: bool) -> bool:
	if resource_id == "movement":
		var footprint: HudM2ActionResourceGlyph = resource_bar.get_node_or_null(
			"MovementZone/FootprintGlyph") as HudM2ActionResourceGlyph
		return footprint != null and footprint.spent == expected_spent
	var pips_value: Variant = resource_bar.call(
		"get_standard_pips" if resource_id == "standard" else "get_swift_pips")
	if not pips_value is Array:
		return false
	var pips: Array = pips_value
	if pips.is_empty():
		return false
	for pip_value: Variant in pips:
		var pip: HudM2ActionResourceGlyph = pip_value as HudM2ActionResourceGlyph
		if pip == null or pip.spent != expected_spent:
			return false
	return true


func _map_has_action_badges(tactical_manager: Object) -> bool:
	var units: Array = tactical_manager.units as Array
	for unit_value: Variant in units:
		var unit := unit_value as Unit
		if unit == null:
			continue
		var status_icons := unit.get_node_or_null("StatusIcons") as Node2D
		if status_icons == null:
			continue
		for child: Node in status_icons.get_children():
			var label := child as Label
			if label != null and label.text in ["M", "A", "S"]:
				return true
	return false
