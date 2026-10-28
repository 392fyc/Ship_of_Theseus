extends SceneTree
## Few real TacticalScene keyframes before any full recording. No map/stat mutation.
var session: Node2D
var manager: Node
var output: String
var rows: Array[Dictionary] = []
var failures: Array[String] = []
var zoom_probe: bool = false

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--zoom-probe":
			zoom_probe = true
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	if output.is_empty() or not output.is_absolute_path() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(output)
	seed(20261027)
	_run.call_deferred()

func _wait_free() -> void:
	var elapsed: float = 0
	while is_instance_valid(manager) and manager.get("input_state") == manager.InputState.ANIMATING and elapsed < 10:
		await create_timer(0.03).timeout
		elapsed += 0.03
	await create_timer(0.18).timeout

func _click(cell: Vector2i) -> void:
	var grid: Grid = manager.get("grid")
	manager.call("handle_pointer_click", root.get_canvas_transform() * grid.grid_to_world(cell))

func _shot(name: String) -> void:
	await create_timer(0.22).timeout
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = output.path_join(name + ".png")
	var error: Error = image.save_png(path)
	if error != OK or image.get_size() != Vector2i(1280, 720):
		failures.append("capture failed: " + name)
	var units: Array[Dictionary] = []
	for unit: Unit in manager.get("units"):
		units.append({"id":unit.unit_id,"instance":unit.get_instance_id(),"grid":unit.grid_position,
			"world":unit.global_position,"hp":unit.stats.hp,"facing":str(unit.get_facing()),
			"animation":unit.character_animation.get("action")})
	var overhead: Dictionary = session.get("battle").get("_unit_overhead_layout").call("get_debug_snapshot")
	for row: Dictionary in overhead["units"]:
		var group: Rect2 = row["group_rect"]
		var foot: Vector2 = row["unit_screen_anchor"]
		if absf(group.get_center().x - foot.x) > float(row["screen_tile_width"]) + 0.01:
			failures.append(name + ": head UI lost owner projection")
	rows.append({"name":name,"path":path,"units":units,
		"trees":session.get("tree_presentation").call("debug_snapshot"),
		"overhead":overhead})
	print("PORTRAIT_ENVIRONMENT_FRAME=",name)

func _run() -> void:
	session = load("res://scenes/tactical/character_pipeline/portrait_token_battle.tscn").instantiate()
	root.add_child(session)
	for _i: int in 8:
		await process_frame
	manager = session.get("manager")
	await _shot("01-clear")
	if zoom_probe:
		for _i: int in 8:
			var wheel := InputEventMouseButton.new()
			wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
			wheel.pressed = true
			wheel.position = Vector2(850,300)
			session.call("_unhandled_input",wheel)
			await process_frame
		await _shot("02-minimum-wheel-zoom")
		var zoom_file := FileAccess.open(output.path_join("probe.json"),FileAccess.WRITE)
		zoom_file.store_string(JSON.stringify({"frames":rows,"failures":failures,"camera_zoom":session.get("camera").zoom,"fit_zoom":session.get("_fit_zoom"),"input":"existing wheel-down handler, eight legal scroll events"},"\t")+"\n")
		manager.call("stop_battle")
		session.queue_free()
		await process_frame
		quit(0 if failures.is_empty() else 1)
		return
	manager.call("request_end_turn")
	await _wait_free()
	var actor: Unit = manager.get("current_unit") as Unit
	if actor == null or actor.unit_id != "kensei":
		failures.append("expected real kensei turn")
	else:
		_click(Vector2i(0, 6))
		await _wait_free()
		if actor.grid_position != Vector2i(0,6):
			failures.append("legal forest MOVE did not reach (0,6)")
		await _shot("02-forest-occupied")
		manager.call("request_end_turn")
		var elapsed: float = 0.0
		while elapsed < 15.0:
			await create_timer(0.05).timeout
			elapsed += 0.05
			var current: Unit = manager.get("current_unit") as Unit
			if current == actor and manager.get("input_state") != manager.InputState.ANIMATING:
				break
			if current != null and current.faction == "player" and current != actor and manager.get("input_state") != manager.InputState.ANIMATING:
				manager.call("request_end_turn")
		_click(Vector2i(1, 6))
		await _wait_free()
		if actor.grid_position != Vector2i(1,6):
			failures.append("legal exit MOVE did not reach (1,6)")
		await _shot("03-forest-restored")
	var file := FileAccess.open(output.path_join("probe.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames":rows,"failures":failures,"input":"real handle_pointer_click/GameAction MOVE and real EnemyAI turns; no map/HP edits"},"\t")+"\n")
	print("PORTRAIT_ENVIRONMENT_RESULT=",JSON.stringify({"frames":rows.size(),"failures":failures}))
	manager.call("stop_battle")
	session.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
