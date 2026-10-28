extends SceneTree
## Capture the actual TacticalScene, driving its existing pointer/action APIs only.
var session: Node2D
var manager: Node
var output: String = ""
var frame_index: int = 0
var total_frames: int = 450
var busy: bool = false
var events: Array[Dictionary] = []
var states: Array[Dictionary] = []
var acted_turn: int = -1

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
		elif argument.begins_with("--frames="):
			total_frames = int(argument.trim_prefix("--frames="))
	if output.is_empty() or not output.is_absolute_path() or DisplayServer.get_name() == "headless":
		push_error("Real battle capture requires X11/Compatibility and --out=<absolute directory>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	seed(20261027) # Reproducible normal RNG input; no deterministic/debug outcome override.
	_start.call_deferred()

func _start() -> void:
	# Load after SceneTree autoload initialization; preloading before it hides DataLoader.
	var packed: PackedScene = load("res://scenes/tactical/character_pipeline/portrait_token_battle.tscn")
	session = packed.instantiate()
	root.add_child(session)
	for index: int in range(8):
		await process_frame
	manager = session.manager
	for unit: Unit in manager.units:
		unit.damage_taken.connect(_damage.bind(unit))
		unit.unit_died.connect(_death.bind(unit))
	manager.turn_manager.turn_started.connect(_turn)
	process_frame.connect(_capture)
	_drive.call_deferred()

func _event(kind: String, data: Dictionary) -> void:
	data["event"] = kind
	data["frame"] = frame_index
	data["seconds"] = float(frame_index) / 30.0
	events.append(data)
	print("BATTLE_EVENT=", JSON.stringify(data))

func _damage(amount: int, damage_type: String, unit: Unit) -> void:
	_event("damage", {"unit": unit.unit_id, "instance": unit.get_instance_id(), "faction": unit.faction,
		"amount": amount, "hp_after": unit.stats.hp, "damage_type": damage_type})

func _death(unit: Unit) -> void:
	_event("death", {"unit": unit.unit_id, "instance": unit.get_instance_id(), "faction": unit.faction})

func _turn(unit: Unit) -> void:
	_event("turn_started", {"unit": unit.unit_id, "instance": unit.get_instance_id(), "faction": unit.faction})

func _screen(cell: Vector2i) -> Vector2:
	return root.get_canvas_transform() * manager.grid.grid_to_world(cell)

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _drive() -> void:
	await _wait(1.2)
	while frame_index < total_frames - 30 and is_instance_valid(manager) and manager.battle_active:
		var actor: Unit = manager.current_unit
		if not is_instance_valid(actor) or actor.faction != "player" or manager.input_state == manager.InputState.ANIMATING:
			await _wait(0.1)
			continue
		var turn_key: int = actor.get_instance_id() * 1000 + manager.turn_manager.get_round_number()
		if acted_turn == turn_key:
			await _wait(0.1)
			continue
		acted_turn = turn_key
		await _wait(0.5)
		if not is_instance_valid(actor) or manager.current_unit != actor:
			continue
		var target: Unit = null
		var distance: int = 999
		for enemy: Unit in manager.units:
			if enemy.faction != actor.faction and enemy.stats.is_alive():
				var delta: Vector2i = enemy.grid_position - actor.grid_position
				var value: int = absi(delta.x) + absi(delta.y)
				if value < distance:
					distance = value
					target = enemy
		if target == null:
			break
		if manager.input_state == manager.InputState.MOVE_PHASE:
			var destination: Vector2i = actor.grid_position
			var best: int = distance
			for cell: Vector2i in manager._move_range:
				if manager.grid.get_unit_at(cell) != null:
					continue
				var d: Vector2i = target.grid_position - cell
				var value: int = absi(d.x) + absi(d.y)
				if value < best and value >= actor.attack_min_range:
					best = value
					destination = cell
			if destination != actor.grid_position:
				_event("player_move_input", {"actor": actor.unit_id, "from": str(actor.grid_position), "to": str(destination)})
				manager.handle_pointer_click(_screen(destination))
				while manager.input_state == manager.InputState.ANIMATING:
					await _wait(0.04)
			else:
				manager.request_end_move()
		await _wait(0.6)
		if not is_instance_valid(actor) or not is_instance_valid(target) or manager.current_unit != actor:
			continue
		manager.request_attack_targeting()
		if target.grid_position in manager._attack_cells:
			_event("player_attack_input", {"actor": actor.unit_id, "target": target.unit_id,
				"actor_hp": actor.stats.hp, "target_hp_before": target.stats.hp})
			manager.handle_pointer_hover(_screen(target.grid_position))
			manager.handle_pointer_click(_screen(target.grid_position))
			# Normal action lock must reject duplicate pointer attacks and End Turn during windup.
			manager.handle_pointer_click(_screen(target.grid_position))
			manager.request_end_turn()
			while manager.battle_active and manager.input_state == manager.InputState.ANIMATING:
				await _wait(0.04)
		await _wait(0.6)
		if manager.battle_active and is_instance_valid(actor) and manager.current_unit == actor:
			manager.request_end_turn()

func _capture() -> void:
	if busy:
		return
	busy = true
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(output.path_join("frame_%05d.png" % frame_index))
	if error != OK or image.get_size() != Vector2i(1280, 720):
		push_error("Capture failed or dimensions changed")
		quit(2)
		return
	var units: Array[Dictionary] = []
	for unit: Unit in manager.units:
		if is_instance_valid(unit):
			units.append({"id": unit.unit_id, "instance": unit.get_instance_id(), "faction": unit.faction,
				"hp": unit.stats.hp, "grid": str(unit.grid_position), "movement_used": unit.movement_used,
				"standard_used": unit.standard_used, "facing": str(unit.get_facing()),
				"animation": unit.character_animation.action if unit.has_character_animation() else "legacy",
				"static_direction_column": unit.character_animation.frame_coords.x if unit.has_character_animation() else -1, "contact_count": unit.character_animation.contact_count if unit.has_character_animation() else 0})
	states.append({"frame": frame_index, "input_state": manager.input_state, "battle_active": manager.battle_active, "units": units})
	frame_index += 1
	if frame_index >= total_frames:
		var report: Dictionary = {"rendering": "Godot actual TacticalScene viewport / Compatibility", "fps": 30,
			"frames": frame_index, "size": [1280, 720], "seed": 20261027, "events": events, "states": states}
		var file: FileAccess = FileAccess.open(output.path_join("battle-trace.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t") + "\n")
		manager.stop_battle()
		session.queue_free()
		await process_frame
		quit()
		return
	busy = false
