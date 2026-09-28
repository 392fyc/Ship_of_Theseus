extends SceneTree

const CaptureMetadata := preload("res://tests/claude_review/capture_metadata.gd")
const OUTPUT := "user://art-review/hud-myrmidon-portrait"
var _output: String = ""
var _captures: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			_output = arg.trim_prefix("--output=")
	if DisplayServer.get_name() == "headless":
		push_error("This review capture requires a rendering display")
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
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	scene.run_injected = true
	scene.injected_map_id = "test_arena"
	scene.injected_player_units = [{"class_id": "myrmidon", "pos": Vector2i(1, 2)}]
	scene.injected_enemy_units = [{"class_id": "test_lancer", "pos": Vector2i(5, 2)}]
	scene.debug_harness_enabled = false
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.tactical_manager.current_unit.set_sword_qi(65)
	scene.tactical_manager._emit_dashboard_state_changed()
	scene.tactical_manager.request_end_move()
	for unused: int in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_output)
	var full_path: String = _output.path_join("combat-1280.png")
	var ok: bool = CaptureMetadata.save_png(root, image, full_path) == OK
	if ok:
		_captures.append(CaptureMetadata.capture_record(root, image, full_path))
	var composition: Control = scene.get("_bottom_dashboard").get_composition()
	var portrait_frame: Control = composition.get_node("BottomRow/CharacterHudPanel/PortraitFrame") as Control
	var end_button: Control = composition.get_node("BottomRow/EndTurnControl/EndTurnButton") as Control
	ok = _save_detail(image, portrait_frame.get_global_rect(), full_path, "portrait-detail-4x.png") and ok
	ok = _save_detail(image, end_button.get_global_rect(), full_path, "end-turn-detail-4x.png") and ok
	var source_fields: Dictionary = {"engine": Engine.get_version_info().get("string", "unknown"),
		"scene": "res://scenes/tactical/TacticalScene.tscn", "runtime_evidence": true}
	ok = CaptureMetadata.write_manifest(root, _output.path_join("capture-metadata.json"), _captures, source_fields) and ok
	scene.queue_free()
	await process_frame
	print("MYRMIDON_PORTRAIT_END_TURN_CAPTURE result=", "pass" if ok else "fail")
	quit(0 if ok else 1)


func _save_detail(source: Image, rect: Rect2, source_path: String, file_name: String) -> bool:
	var region := Rect2i(int(rect.position.x) - 3, int(rect.position.y) - 3, int(rect.size.x) + 6, int(rect.size.y) + 6)
	var detail: Image = source.get_region(region)
	detail.resize(region.size.x * 4, region.size.y * 4, Image.INTERPOLATE_NEAREST)
	var path: String = _output.path_join(file_name)
	var details: Dictionary = {"capture_kind": "derived_detail", "source_file": source_path.get_file(),
		"source_sha256": FileAccess.get_sha256(source_path),
		"source_region": [region.position.x, region.position.y, region.size.x, region.size.y], "scale": 4}
	if CaptureMetadata.save_png(root, detail, path, details) != OK:
		return false
	_captures.append(CaptureMetadata.capture_record(root, detail, path, details))
	return true
