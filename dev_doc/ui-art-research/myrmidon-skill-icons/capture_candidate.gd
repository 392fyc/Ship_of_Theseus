extends SceneTree

const OUTPUT := "res://dev_doc/ui-art-research/myrmidon-skill-icons/candidate-v2"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This capture needs a visible rendering display")
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
	var dashboard: Control = scene.get("_bottom_dashboard") as Control
	scene.tactical_manager.current_unit.set_sword_qi(65)
	scene.tactical_manager._emit_dashboard_state_changed()
	var ok: bool = await _capture("move-1280", dashboard)
	scene.tactical_manager.request_end_move()
	ok = (await _capture("action-1280", dashboard)) and ok
	ok = _capture_detail(dashboard) and ok
	root.size = Vector2i(1920, 1080)
	ok = (await _capture("action-1920", dashboard)) and ok
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
	var directory: String = ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(directory)
	var path: String = directory.path_join(name + ".png")
	if image.save_png(path) != OK:
		push_error("Cannot save capture: " + name)
		return false
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
	var source: Image = Image.load_from_file(ProjectSettings.globalize_path(OUTPUT.path_join("action-1280.png")))
	var detail: Image = source.get_region(region)
	detail.resize(region.size.x * 4, region.size.y * 4, Image.INTERPOLATE_NEAREST)
	var path: String = ProjectSettings.globalize_path(OUTPUT.path_join("skills-detail-4x.png"))
	if detail.save_png(path) != OK:
		push_error("Cannot save skill detail")
		return false
	print("MYRMIDON_HUD_CAPTURE detail ", region, " ", FileAccess.get_sha256(path))
	return true
