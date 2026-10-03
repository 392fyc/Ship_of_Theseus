extends SceneTree

const CaptureMetadata := preload("res://tests/claude_review/capture_metadata.gd")
const CAPTURE_RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]
var _output_dir: String = ""

## 纹章接入使用正式场景与同一 manager 载荷捕获印记八态。


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			_output_dir = arg.trim_prefix("--output=")
	if _output_dir.is_empty():
		_output_dir = ProjectSettings.globalize_path("user://visual_style_playground/capture_hud_crest_candidate/batch_%d_%d_%d" % [int(Time.get_unix_time_from_system()), OS.get_process_id(), Time.get_ticks_usec()])
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
	var dashboard: HudM2RuntimeDashboard = scene.get("_bottom_dashboard") as HudM2RuntimeDashboard
	var state: Dictionary = scene.tactical_manager.get_dashboard_data()
	var failed: bool = not await _capture_group("production-000", dashboard)
	for amount: int in [65, 100]:
		var fixture: Dictionary = _fixture(state, amount, 7)
		dashboard.update_state(fixture)
		failed = (not await _capture_group("filled-111-qi-%d" % amount, dashboard)) or failed
	for mask: int in 8:
		var fixture: Dictionary = _fixture(state, 65, mask)
		dashboard.update_state(fixture)
		var bits: String = "%d%d%d" % [int(bool(mask & 4)), int(bool(mask & 2)), int(bool(mask & 1))]
		failed = (not await _capture_group("marks-" + bits, dashboard)) or failed
	scene.queue_free()
	await process_frame
	quit(1 if failed else 0)


func _fixture(state: Dictionary, amount: int, mask: int) -> Dictionary:
	var fixture: Dictionary = state.duplicate(true)
	fixture["sword_qi"] = amount
	fixture["sword_qi_max"] = 100
	fixture["marks"] = {"心": bool(mask & 4), "道": bool(mask & 2), "势": bool(mask & 1)}
	fixture["class_resource_display"] = {
		"class_id": "kensei", "mark_capacity": 3,
		"qi_threshold_ratio": 0.5, "qi_band": &"high",
	}
	return fixture


func _capture_group(name: String, dashboard: Control) -> bool:
	var success: bool = true
	for resolution: Vector2i in CAPTURE_RESOLUTIONS:
		root.size = resolution
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
	if image.get_size() != root.size or root.size not in CAPTURE_RESOLUTIONS:
		push_error("Viewport size mismatch: " + name)
		return false
	var directory: String = _output_dir
	DirAccess.make_dir_recursive_absolute(directory)
	var path: String = directory.path_join("%s-%dx%d.png" % [name, root.size.x, root.size.y])
	if CaptureMetadata.save_png(root, image, path, {"capture_group": name}) != OK:
		push_error("PNG save failed: " + path.get_file())
		return false
	print("CREST_CAPTURE ", path.get_file(), " ", image.get_width(), "x", image.get_height(), " ", FileAccess.get_sha256(path))
	return true
