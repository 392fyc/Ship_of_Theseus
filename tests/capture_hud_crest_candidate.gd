extends SceneTree

## 纹章接入使用正式场景与同一 manager 载荷捕获印记八态。
const OUTPUT := "res://dev_doc/ui-art-research/hud-freeze-godot/crest-candidate"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Native HUD capture requires a visible rendering display.")
		quit(1)
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var dashboard: HudM2RuntimeDashboard = scene.get("_bottom_dashboard") as HudM2RuntimeDashboard
	var state: Dictionary = scene.tactical_manager.get_dashboard_data()
	var failed: bool = not await _capture("production-000", dashboard)
	root.size = Vector2i(1920, 1080)
	await process_frame
	await process_frame
	failed = (not await _capture("production-1920-000", dashboard)) or failed
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	for amount: int in [65, 100]:
		var fixture: Dictionary = _fixture(state, amount, 7)
		dashboard.update_state(fixture)
		failed = (not await _capture("filled-111-qi-%d" % amount, dashboard)) or failed
	for mask: int in 8:
		var fixture: Dictionary = _fixture(state, 65, mask)
		dashboard.update_state(fixture)
		var bits: String = "%d%d%d" % [int(bool(mask & 4)), int(bool(mask & 2)), int(bool(mask & 1))]
		failed = (not await _capture("marks-" + bits, dashboard)) or failed
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


func _capture(name: String, dashboard: Control) -> bool:
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
	var directory: String = ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(directory)
	var path: String = directory.path_join(name + ".png")
	if image.save_png(path) != OK:
		push_error("PNG save failed: " + name)
		return false
	print("CREST_CAPTURE ", name, " ", image.get_width(), "x", image.get_height(), " ", FileAccess.get_sha256(path))
	return true
