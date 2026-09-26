extends SceneTree

const OUTPUT := "res://dev_doc/ui-art-research/hud-myrmidon-portrait/candidate"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This review capture requires a rendering display")
		quit(1)
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
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
	var directory: String = ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(directory)
	var ok: bool = image.save_png(directory.path_join("combat-1280.png")) == OK
	var composition: Control = scene.get("_bottom_dashboard").get_composition()
	var portrait_frame: Control = composition.get_node("BottomRow/CharacterHudPanel/PortraitFrame") as Control
	var end_button: Control = composition.get_node("BottomRow/EndTurnControl/EndTurnButton") as Control
	ok = _save_detail(image, portrait_frame.get_global_rect(), directory.path_join("portrait-detail-4x.png")) and ok
	ok = _save_detail(image, end_button.get_global_rect(), directory.path_join("end-turn-detail-4x.png")) and ok
	scene.queue_free()
	await process_frame
	print("MYRMIDON_PORTRAIT_END_TURN_CAPTURE result=", "pass" if ok else "fail")
	quit(0 if ok else 1)


func _save_detail(source: Image, rect: Rect2, path: String) -> bool:
	var region := Rect2i(int(rect.position.x) - 3, int(rect.position.y) - 3, int(rect.size.x) + 6, int(rect.size.y) + 6)
	var detail: Image = source.get_region(region)
	detail.resize(region.size.x * 4, region.size.y * 4, Image.INTERPOLATE_NEAREST)
	return detail.save_png(path) == OK
