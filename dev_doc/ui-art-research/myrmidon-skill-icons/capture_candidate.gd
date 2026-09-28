extends SceneTree

const CaptureMetadata := preload("res://tests/claude_review/capture_metadata.gd")
const OUTPUT := "user://art-review/myrmidon-skill-icons"
var _output: String = ""
var _captures: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			_output = arg.trim_prefix("--output=")
	if DisplayServer.get_name() == "headless":
		push_error("This capture needs a visible rendering display")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	if _output.is_empty():
		var batch_name: String = "batch_%d_%d_%d" % [
			int(Time.get_unix_time_from_system()), OS.get_process_id(), Time.get_ticks_usec(),
		]
		_output = ProjectSettings.globalize_path(OUTPUT.path_join(batch_name))
	if not _output.is_absolute_path():
		push_error("Capture output must be an absolute directory")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_output)
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	scene.run_injected = true
	scene.injected_map_id = "test_arena"
	scene.injected_player_units = [{"class_id": "myrmidon", "pos": Vector2i(1, 2)}]
	scene.injected_enemy_units = [{"class_id": "test_lancer", "pos": Vector2i(5, 2)}]
	scene.debug_harness_enabled = false
	root.add_child(scene)
	await process_frame
	await process_frame
	var dashboard: Control = scene.get("_bottom_dashboard") as Control
	scene.tactical_manager.current_unit.set_sword_qi(65)
	scene.tactical_manager._emit_dashboard_state_changed()
	var ok: bool = await _capture("move-1280", dashboard)
	scene.tactical_manager.request_end_move()
	ok = (await _capture("action-1280", dashboard)) and ok
	ok = _capture_detail(dashboard) and ok
	root.size = Vector2i(1920, 1080)
	ok = (await _capture("action-1920", dashboard)) and ok
	var source_fields: Dictionary = {"engine": Engine.get_version_info().get("string", "unknown"),
		"scene": "res://scenes/tactical/TacticalScene.tscn", "runtime_evidence": true}
	ok = CaptureMetadata.write_manifest(root, _output.path_join("capture-metadata.json"), _captures, source_fields) and ok
	scene.queue_free()
	await process_frame
	quit(0 if ok else 1)


func _capture(name: String, dashboard: Control) -> bool:
	for unused: int in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	if not dashboard.visible:
		push_error("Dashboard hidden at " + name)
		return false
	var image: Image = root.get_texture().get_image()
	var path: String = _output.path_join(name + ".png")
	if CaptureMetadata.save_png(root, image, path) != OK:
		push_error("Cannot save capture: " + name)
		return false
	_captures.append(CaptureMetadata.capture_record(root, image, path))
	print("MYRMIDON_HUD_CAPTURE ", name, " ", image.get_size(), " ", FileAccess.get_sha256(path))
	return true


func _capture_detail(dashboard: Control) -> bool:
	var shelf: Control = dashboard.get_composition().get_node("BottomRow/SkillShelf") as Control
	var slots: Array = shelf.get_skill_slots()
	if slots.size() != 5:
		push_error("Expected five myrmidon skills")
		return false
	for slot: Button in slots:
		var icon: TextureRect = slot.get_node("%IconRect") as TextureRect
		print("MYRMIDON_SLOT ", slot._view.skill_id, " ", icon.texture.resource_path if icon.texture != null else "null")
	var first: Rect2 = (slots[0] as Control).get_global_rect()
	var last: Rect2 = (slots[4] as Control).get_global_rect()
	var region := Rect2i(int(first.position.x) - 4, int(first.position.y) - 4, int(last.end.x - first.position.x) + 8, int(first.size.y) + 8)
	var source_path: String = _output.path_join("action-1280.png")
	var source: Image = Image.load_from_file(source_path)
	var detail: Image = source.get_region(region)
	detail.resize(region.size.x * 4, region.size.y * 4, Image.INTERPOLATE_NEAREST)
	var path: String = _output.path_join("skills-detail-4x.png")
	var details: Dictionary = {"capture_kind": "derived_detail", "source_file": source_path.get_file(),
		"source_sha256": FileAccess.get_sha256(source_path),
		"source_region": [region.position.x, region.position.y, region.size.x, region.size.y], "scale": 4}
	if CaptureMetadata.save_png(root, detail, path, details) != OK:
		push_error("Cannot save skill detail")
		return false
	_captures.append(CaptureMetadata.capture_record(root, detail, path, details))
	print("MYRMIDON_HUD_CAPTURE detail ", region, " ", FileAccess.get_sha256(path))
	return true
