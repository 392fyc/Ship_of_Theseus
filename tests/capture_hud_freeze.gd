extends SceneTree

const CaptureMetadata := preload("res://tests/claude_review/capture_metadata.gd")
const CAPTURE_RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]
var _output_dir: String = ""

## 原生窗口捕获：正式场景一张，以及从同一 manager 载荷派生的显示边界。

var _failed: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			_output_dir = arg.trim_prefix("--output=")
	if _output_dir.is_empty():
		_output_dir = ProjectSettings.globalize_path("user://visual_style_playground/capture_hud_freeze/batch_%d_%d_%d" % [int(Time.get_unix_time_from_system()), OS.get_process_id(), Time.get_ticks_usec()])
	if not _output_dir.is_absolute_path():
		push_error("采集输出须为绝对路径。")
		quit(1)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Native HUD capture requires a visible rendering display.")
		quit(1)
		return
	root.borderless = true
	root.size = Vector2i(1280, 720)
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var dashboard: Control = scene.get("_bottom_dashboard") as Control
	var state: Dictionary = scene.tactical_manager.get_dashboard_data()
	_failed = not await _capture_group("production", dashboard)
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	_move_pointer(Vector2(140, 650))
	await process_frame
	await process_frame
	_failed = (not await _capture_group("hover-character", dashboard, true)) or _failed
	_move_pointer(Vector2(640, 320))
	await process_frame
	var spent: Dictionary = state.duplicate(true)
	spent["action_resources"]["movement_available"] = false
	spent["action_resources"]["standard_remaining"] = 0
	spent["action_resources"]["swift_remaining"] = 0
	dashboard.update_state(spent)
	_failed = (not await _capture_group("action-spent", dashboard)) or _failed
	for amount: int in [0, 1, 50, 51, 100]:
		var fixture: Dictionary = state.duplicate(true)
		fixture["sword_qi"] = amount
		fixture["sword_qi_max"] = 100
		fixture["marks"] = {"心": true, "道": true, "势": true}
		fixture["class_resource_display"] = {
			"class_id": "kensei", "mark_capacity": 3,
			"qi_threshold_ratio": 0.5, "qi_band": &"low" if amount <= 50 else &"high",
		}
		dashboard.update_state(fixture)
		_failed = (not await _capture_group("fixture-%d-111" % amount, dashboard)) or _failed
	for mask: int in 8:
		var fixture: Dictionary = state.duplicate(true)
		fixture["sword_qi"] = 65
		fixture["sword_qi_max"] = 100
		fixture["marks"] = {"心": bool(mask & 4), "道": bool(mask & 2), "势": bool(mask & 1)}
		fixture["class_resource_display"] = {
			"class_id": "kensei", "mark_capacity": 3,
			"qi_threshold_ratio": 0.5, "qi_band": &"high",
		}
		dashboard.update_state(fixture)
		var bits: String = "%d%d%d" % [int(bool(mask & 4)), int(bool(mask & 2)), int(bool(mask & 1))]
		_failed = (not await _capture_group("marks-" + bits, dashboard)) or _failed
	scene.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _capture_group(name: String, dashboard: Control, hover_character: bool = false) -> bool:
	var success: bool = true
	for resolution: Vector2i in CAPTURE_RESOLUTIONS:
		root.size = resolution
		await process_frame
		await process_frame
		if hover_character:
			var scale: Vector2 = Vector2(resolution) / Vector2(1280, 720)
			_move_pointer(Vector2(140, 650) * scale)
			await process_frame
			await process_frame
		success = await _capture_at_resolution(name, dashboard) and success
	return success


func _capture_at_resolution(name: String, dashboard: Control) -> bool:
	for unused: int in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	if dashboard == null or not dashboard.visible:
		push_error("HUD is not visible: " + name)
		return false
	var image: Image = root.get_texture().get_image()
	if image.get_size() != root.size:
		push_error("Viewport size mismatch: " + name)
		return false
	var directory: String = _output_dir
	DirAccess.make_dir_recursive_absolute(directory)
	var path: String = directory.path_join("%s-%dx%d.png" % [name, root.size.x, root.size.y])
	var err: Error = CaptureMetadata.save_png(root, image, path, {"capture_group": name})
	if err != OK:
		push_error("PNG save failed: " + path.get_file())
		return false
	print("CAPTURE ", path.get_file(), " ", image.get_width(), "x", image.get_height(), " ", FileAccess.get_sha256(path))
	return true


func _move_pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event, true)
