extends SceneTree

## 从正式战斗场景捕获行动资源、技能、人物悬停与职业资源的整屏联动。
## 使用项目拉伸配置采集；--output=<仓库外绝对目录> 可指定输出位置。

const OUTPUT_ROOT := "user://visual_style_playground/hud_final_acceptance"
const CaptureMetadata := preload("res://tests/claude_review/capture_metadata.gd")

var _directory: String = ""
var _batch_name: String = ""
var _records: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var output_argument: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output_argument = arg.trim_prefix("--output=")
	if DisplayServer.get_name().to_lower() == "headless":
		push_error("Final HUD capture requires a visible rendering display")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	_batch_name = "batch_%d" % int(Time.get_unix_time_from_system())
	_directory = output_argument if not output_argument.is_empty() else ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(_batch_name))
	if not _directory.is_absolute_path():
		push_error("Capture output must be an absolute path")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(_directory) != OK:
		push_error("Cannot create capture directory")
		quit(1)
		return

	var packed: PackedScene = load("res://scenes/tactical/TacticalScene.tscn") as PackedScene
	if packed == null:
		push_error("Cannot load TacticalScene")
		quit(1)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var dashboard: HudM2RuntimeDashboard = scene.get("_bottom_dashboard") as HudM2RuntimeDashboard
	var manager: Object = scene.get("tactical_manager")
	var unit: Unit = manager._get_dashboard_unit() if manager != null else null
	if dashboard == null or unit == null:
		push_error("TacticalScene did not create the current unit and dashboard")
		scene.queue_free()
		quit(1)
		return
	var composition: Control = dashboard.get_composition()
	var strip: Control = composition.get_node("ActionResourceStrip") as Control
	var shelf: Control = composition.get_node("BottomRow/SkillShelf") as Control
	var character: HudM2CharacterPanel = composition.get_node("BottomRow/CharacterHudPanel") as HudM2CharacterPanel
	if strip == null or shelf == null or character == null:
		push_error("Required HUD panels are missing")
		scene.queue_free()
		quit(1)
		return

	unit.reset_action_resources()
	scene._refresh_dashboard()
	var success: bool = true
	for target_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = target_size
		await process_frame
		await process_frame
		_move_pointer(Vector2(target_size) * Vector2(0.5, 0.4))
		await process_frame
		success = (await _capture("available-%d" % target_size.x, dashboard, strip, shelf)) and success
		if target_size.x == 1280:
			unit.consume_movement_resource()
			unit.consume_standard_resource()
			scene._refresh_dashboard()
			await process_frame
			var state: Object = strip.get("_view") as Object
			if state == null or bool(state.get("movement_available")) \
					or int(state.get("standard_remaining")) != 0 \
					or int(state.get("swift_remaining")) != 1:
				push_error("Mixed capture did not receive the movement and standard resource use")
				success = false
			else:
				success = (await _capture("mixed-1280", dashboard, strip, shelf)) and success
			unit.consume_swift_resource()
			scene._refresh_dashboard()
			await process_frame
			state = strip.get("_view") as Object
			if state == null or bool(state.get("movement_available")) \
					or int(state.get("standard_remaining")) != 0 \
					or int(state.get("swift_remaining")) != 0:
				push_error("Spent capture did not receive the three consumed resources")
				success = false
			else:
				success = (await _capture("spent-1280", dashboard, strip, shelf)) and success
			unit.reset_action_resources()
			scene._refresh_dashboard()
			await process_frame
		_move_pointer(character.get_inspection_control().get_global_rect().get_center())
		await process_frame
		await process_frame
		if not character.get_inspection_panel().visible:
			push_error("Portrait hover did not reveal the attribute panel")
			success = false
		elif (character.get_node("PortraitFocus") as Control).visible:
			push_error("Mouse hover added a second portrait frame")
			success = false
		else:
			success = (await _capture("hover-%d" % target_size.x, dashboard, strip, shelf)) and success

	scene.queue_free()
	success = _validate_portrait_frame() and success
	success = _save_manifest() and success
	print("HUD_FINAL_CAPTURE_DIR=%s" % _directory)
	quit(0 if success else 1)


func _capture(name: String, dashboard: HudM2RuntimeDashboard,
		strip: Control, shelf: Control) -> bool:
	for unused: int in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	if not dashboard.visible or not strip.is_visible_in_tree() or not shelf.is_visible_in_tree():
		push_error("HUD panels are not visible: " + name)
		return false
	if not is_equal_approx(shelf.get_global_rect().position.y - strip.get_global_rect().end.y,
			6.0 * dashboard.get_composition().scale.y):
		push_error("Action strip is not six design pixels above the skill shelf: " + name)
		return false
	var screenshot: Image = root.get_texture().get_image()
	if screenshot == null or screenshot.get_size() != root.size:
		push_error("Viewport size mismatch: " + name)
		return false
	var path: String = _directory.path_join(name + ".png")
	if CaptureMetadata.save_png(root, screenshot, path) != OK:
		push_error("Cannot save capture: " + name)
		return false
	var digest: String = FileAccess.get_sha256(path)
	var record: Dictionary = CaptureMetadata.capture_record(root, screenshot, path)
	record["width"] = screenshot.get_width()
	record["height"] = screenshot.get_height()
	_records.append(record)
	print("HUD_FINAL_CAPTURE=%s SHA256=%s" % [path, digest])
	return true


func _save_manifest() -> bool:
	var path: String = _directory.path_join("capture-manifest.json")
	var source_fields: Dictionary = {
		"batch": _batch_name,
		"engine": Engine.get_version_info().get("string", "unknown"),
		"scene": "res://scenes/tactical/TacticalScene.tscn",
	}
	if not CaptureMetadata.write_manifest(root, path, _records, source_fields):
		push_error("Cannot write capture manifest")
		return false
	print("HUD_FINAL_CAPTURE_MANIFEST=%s" % path)
	return true


func _validate_portrait_frame() -> bool:
	var available: Image = Image.load_from_file(_directory.path_join("available-1280.png"))
	var hovered: Image = Image.load_from_file(_directory.path_join("hover-1280.png"))
	if available == null or hovered == null:
		push_error("Cannot compare portrait frame captures")
		return false
	var frame: Rect2i = Rect2i(43, 608, 74, 84)
	if available.get_region(frame).get_data() != hovered.get_region(frame).get_data():
		push_error("Portrait frame pixels changed on hover")
		return false
	print("HUD_FINAL_PORTRAIT_FRAME_MATCH=true")
	return true


func _move_pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event, true)
