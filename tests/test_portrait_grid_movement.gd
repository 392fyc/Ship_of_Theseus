extends SceneTree
## Sample real player movement, including a corner, and stop it between segments.
const ENTRY: String = "res://scenes/tactical/character_pipeline/portrait_token_battle.tscn"
var checks: int = 0
var failures: Array[String] = []
var moved_count: int = 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, value: bool) -> void:
	checks += 1
	print("[", "PASS" if value else "FAIL", "] ", label)
	if not value:
		failures.append(label)


func _kensei_turn(session: Node) -> Node:
	await create_timer(0.1).timeout
	var manager: Node = session.manager
	manager.request_end_turn()
	await create_timer(0.1).timeout
	return manager


func _run() -> void:
	root.size = Vector2i(1280, 720)
	seed(20261027)
	var session: Node = load(ENTRY).instantiate()
	root.add_child(session)
	var manager: Node = await _kensei_turn(session)
	var actor: Unit = manager.current_unit
	var origin: Vector2i = actor.grid_position
	var destination := Vector2i(0, 6)
	var path: Array[Vector2i] = Pathfinding.find_path(manager.grid, origin, destination, actor.faction)
	check("real forest route contains multiple orthogonal steps and a corner", actor.unit_id == "kensei" and path.size() == 4 and origin.x != destination.x and origin.y != destination.y)
	actor.moved.connect(func(_from: Vector2i, _to: Vector2i) -> void: moved_count += 1)
	manager.handle_pointer_hover(root.get_canvas_transform() * manager.grid.grid_to_world(destination))
	check("preview uses the same route", manager._path_preview == path)
	manager.handle_pointer_click(root.get_canvas_transform() * manager.grid.grid_to_world(destination))
	var sampled_segments: Dictionary = {}
	var on_path: bool = true
	var facing_next: bool = true
	var locked: bool = true
	var occupancy_deferred: bool = true
	var progress_forward: bool = true
	var prior_progress: float = 0.0
	var started: int = Time.get_ticks_msec()
	var animation_seconds: float = 0.0
	while manager.input_state == manager.InputState.ANIMATING and Time.get_ticks_msec() - started < 3000:
		var best_distance: float = INF
		var best_progress: float = 0.0
		for index: int in range(1, path.size()):
			var a: Vector2 = manager.grid.grid_to_world(path[index - 1])
			var b: Vector2 = manager.grid.grid_to_world(path[index])
			var fraction: float = clampf((actor.position - a).dot(b - a) / a.distance_squared_to(b), 0.0, 1.0)
			var distance: float = actor.position.distance_to(a.lerp(b, fraction))
			if distance < best_distance:
				best_distance = distance
				best_progress = float(index - 1) + fraction
			if distance < 0.1 and fraction > 0.15 and fraction < 0.85:
				sampled_segments[index] = true
				var expected: StringName = actor.character_animation.direction_for_screen_vector(b - a)
				facing_next = facing_next and actor.get_facing() == expected
		on_path = on_path and best_distance < 0.1
		progress_forward = progress_forward and best_progress + 0.001 >= prior_progress
		prior_progress = best_progress
		occupancy_deferred = occupancy_deferred and actor.grid_position == origin and manager.grid.get_unit_at(origin) == actor and manager.grid.get_unit_at(destination) == null
		manager.request_end_turn()
		manager.request_cancel_action()
		locked = locked and manager.current_unit == actor and manager.input_state == manager.InputState.ANIMATING
		animation_seconds += root.get_process_delta_time()
		await process_frame
	check("every moving sample lies on an orthogonal route segment", on_path)
	check("every intermediate segment is shown in order", sampled_segments.size() == path.size() - 1 and progress_forward)
	check("turns face the next segment", facing_next)
	print("GRID_MOVEMENT_TIMING=", JSON.stringify({"animation_seconds": animation_seconds, "wall_ms": Time.get_ticks_msec() - started}))
	check("long movement takes per-cell animation time", animation_seconds >= 0.65)
	check("input remains locked until the full route finishes", locked and manager.input_state != manager.InputState.ANIMATING)
	check("occupancy moves once at the end", occupancy_deferred and moved_count == 1 and actor.grid_position == destination and manager.grid.get_unit_at(destination) == actor and manager.grid.get_unit_at(origin) == null)
	check("only movement resource is used", actor.movement_used and not actor.standard_used and not actor.swift_used)
	check("arrival returns idle at the exact cell center", actor.character_animation.action == "idle" and actor.position.is_equal_approx(manager.grid.grid_to_world(destination)))
	await session.select_layout("portrait_courtyard")
	manager = await _kensei_turn(session)
	actor = manager.current_unit
	origin = actor.grid_position
	moved_count = 0
	actor.moved.connect(func(_from: Vector2i, _to: Vector2i) -> void: moved_count += 1)
	manager.handle_pointer_click(root.get_canvas_transform() * manager.grid.grid_to_world(destination))
	await create_timer(0.32).timeout
	check("cancel fixture is moving beyond the first segment", actor.unit_id == "kensei" and manager.input_state == manager.InputState.ANIMATING and actor._movement_tween != null and actor.grid_position == origin and actor.position.distance_to(manager.grid.grid_to_world(origin)) > 36.0)
	manager.stop_battle()
	var stopped_at: Vector2 = actor.position
	await create_timer(0.7).timeout
	check("stop between segments prevents all remaining movement", actor._movement_tween == null and actor.position.is_equal_approx(stopped_at) and not actor.position.is_equal_approx(manager.grid.grid_to_world(destination)))
	check("canceled route does not emit completion or commit occupancy", moved_count == 0 and actor.grid_position == origin and manager.grid.get_unit_at(origin) == actor)
	session.queue_free()
	await process_frame
	print("GRID_MOVEMENT_RESULT=", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
