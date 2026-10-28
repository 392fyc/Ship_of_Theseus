extends SceneTree
## Ten-second original-roster real-entry capture with player-side input AI.
## Output: frames/frame_*.png plus facing-align-trace.json under --out.
const ENTRY_SCENE: String = "res://scenes/tactical/character_pipeline/portrait_token_battle.tscn"
const FPS: int = 30
const WIDTH: int = 1280
const HEIGHT: int = 720

var session: Node2D
var manager: Node
var output: String = ""
var frames_dir: String = ""
var total_frames: int = 300
var frame_index: int = 0
var busy: bool = false
var acted_turn: int = -1
var events: Array[Dictionary] = []
var states: Array[Dictionary] = []

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
		elif argument.begins_with("--frames="):
			total_frames = int(argument.trim_prefix("--frames="))
	if output.is_empty() or not output.is_absolute_path() \
			or total_frames < 240 or total_frames > 360 or DisplayServer.get_name() == "headless":
		push_error("Real alignment capture requires X11/Compatibility, --out=<absolute directory>, and 240-360 frames")
		quit(2)
		return
	frames_dir = output.path_join("frames")
	DirAccess.make_dir_recursive_absolute(frames_dir)
	root.size = Vector2i(WIDTH, HEIGHT)
	seed(20261027)
	_start.call_deferred()

func _event(kind: String, data: Dictionary) -> void:
	data["event"] = kind
	data["frame"] = frame_index
	data["seconds"] = float(frame_index) / float(FPS)
	events.append(data)
	print("FACING_ALIGN_EVENT=", JSON.stringify(data))

func _damage(amount: int, damage_type: String, unit: Unit) -> void:
	_event("damage", {"unit": unit.unit_id, "instance": unit.get_instance_id(),
		"faction": unit.faction, "amount": amount, "hp_after": unit.stats.hp,
		"damage_type": damage_type})

func _death(unit: Unit) -> void:
	_event("death", {"unit": unit.unit_id, "instance": unit.get_instance_id(), "faction": unit.faction})

func _turn(unit: Unit) -> void:
	_event("turn_started", {"unit": unit.unit_id, "instance": unit.get_instance_id(), "faction": unit.faction})

func _screen(cell: Vector2i) -> Vector2:
	return root.get_canvas_transform() * manager.get("grid").grid_to_world(cell)

func _screen_world(world: Vector2) -> Vector2:
	return root.get_canvas_transform() * world

func _visible_ring_data(unit: Unit, grid_center_screen: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for child: Node in unit.get_children():
		if child.name != "PersistentFactionRing" or not child.is_visible_in_tree():
			continue
		var center_offset: Vector2 = child.get("center_offset")
		var center_world: Vector2 = child.to_global(center_offset)
		var center_screen: Vector2 = _screen_world(center_world)
		result.append({"outline": "faction", "world_center": [center_world.x, center_world.y],
			"screen_center": [center_screen.x, center_screen.y],
			"grid_center_error_px": center_screen.distance_to(grid_center_screen),
			"visible": true})
		if bool(child.get("_active")):
			# The active outer ellipse is a second visible outline with the same support center.
			result.append({"outline": "active_selection", "world_center": [center_world.x, center_world.y],
				"screen_center": [center_screen.x, center_screen.y],
				"grid_center_error_px": center_screen.distance_to(grid_center_screen),
				"visible": true})
	return result

func _target_projection(actor: Unit) -> Dictionary:
	var best: Unit = null
	var best_distance: int = 1 << 30
	for enemy: Unit in manager.get("units"):
		if not is_instance_valid(enemy) or enemy.faction == actor.faction or not enemy.stats.is_alive():
			continue
		var delta: Vector2i = enemy.grid_position - actor.grid_position
		var distance: int = absi(delta.x) + absi(delta.y)
		if distance < best_distance:
			best = enemy
			best_distance = distance
	if best == null:
		return {}
	var world_delta: Vector2 = manager.get("grid").grid_to_world(best.grid_position) \
		- manager.get("grid").grid_to_world(actor.grid_position)
	var projected: Vector2 = root.get_canvas_transform().basis_xform(world_delta)
	return {"target": best.unit_id, "target_grid": str(best.grid_position),
		"projected_vector_screen": [projected.x, projected.y],
		"facing": str(actor.get_facing())}

func _unit_state(unit: Unit, current: Unit) -> Dictionary:
	var grid_center_world: Vector2 = manager.get("grid").grid_to_world(unit.grid_position)
	var grid_center_screen: Vector2 = _screen_world(grid_center_world)
	var view: Node = unit.character_animation if unit.has_character_animation() else null
	var foot_world: Vector2 = view.call("foot_support_world_position") as Vector2 if view != null else unit.global_position
	var foot_screen: Vector2 = _screen_world(foot_world)
	var visible_children: Array[Dictionary] = []
	for child: Node in unit.get_children():
		if child is CanvasItem and child.is_visible_in_tree():
			var item: CanvasItem = child as CanvasItem
			visible_children.append({"name": child.name, "type": child.get_class(),
				"position": [item.global_position.x, item.global_position.y]})
	var frame: Vector2i = view.frame_coords if view != null else Vector2i(-1, -1)
	var source_support: Vector2 = view.get("foot_support_center_source_px") as Vector2 if view != null else Vector2.ZERO
	var rings: Array[Dictionary] = _visible_ring_data(unit, grid_center_screen)
	var state: Dictionary = {
		"id": unit.unit_id,
		"instance": unit.get_instance_id(),
		"faction": unit.faction,
		"hp": unit.stats.hp,
		"grid": str(unit.grid_position),
		"unit_world": [unit.global_position.x, unit.global_position.y],
		"grid_center_world": [grid_center_world.x, grid_center_world.y],
		"grid_center_screen": [grid_center_screen.x, grid_center_screen.y],
		"facing": str(unit.get_facing()),
		"animation": view.get("action") if view != null else "legacy",
		"animation_frame": [frame.x, frame.y],
		"token_position": [view.position.x, view.position.y] if view != null else [0.0, 0.0],
		"foot_support_source_px": [source_support.x, source_support.y],
		"foot_world": [foot_world.x, foot_world.y],
		"foot_screen": [foot_screen.x, foot_screen.y],
		"foot_grid_center_error_px": foot_screen.distance_to(grid_center_screen),
		"visible_children": visible_children,
		"all_visible_ring_centers": rings,
		"standard_used": unit.standard_used,
		"movement_used": unit.movement_used,
	}
	if unit == current:
		state["nearest_target_projection"] = _target_projection(unit)
	return state

func _player_turn_key(actor: Unit) -> int:
	return actor.get_instance_id() * 1000 + manager.get("turn_manager").get_round_number()

func _drive_player_ai() -> void:
	await create_timer(0.8).timeout
	while frame_index < total_frames - 24 and is_instance_valid(manager) and bool(manager.get("battle_active")):
		var actor: Unit = manager.get("current_unit") as Unit
		if actor == null or actor.faction != "player" or manager.get("input_state") == manager.InputState.ANIMATING:
			await create_timer(0.08).timeout
			continue
		var turn_key: int = _player_turn_key(actor)
		if acted_turn == turn_key:
			await create_timer(0.08).timeout
			continue
		acted_turn = turn_key
		await create_timer(0.35).timeout
		if not is_instance_valid(manager) or not is_instance_valid(actor) or manager.get("current_unit") != actor:
			continue
		var target: Unit = null
		var distance: int = 1 << 30
		for enemy: Unit in manager.get("units"):
			if not is_instance_valid(enemy) or enemy.faction == actor.faction or not enemy.stats.is_alive():
				continue
			var delta: Vector2i = enemy.grid_position - actor.grid_position
			var current_distance: int = absi(delta.x) + absi(delta.y)
			if current_distance < distance:
				distance = current_distance
				target = enemy
		if target == null:
			manager.call("request_end_turn")
			continue
		if manager.get("input_state") == manager.InputState.MOVE_PHASE:
			var destination: Vector2i = actor.grid_position
			var best_distance: int = distance
			for cell_value: Variant in manager.get("_move_range").keys():
				var cell: Vector2i = cell_value as Vector2i
				if manager.get("grid").get_unit_at(cell) != null:
					continue
				var delta_to_target: Vector2i = target.grid_position - cell
				var value: int = absi(delta_to_target.x) + absi(delta_to_target.y)
				if value < best_distance and value >= actor.attack_min_range:
					best_distance = value
					destination = cell
			if destination != actor.grid_position:
				_event("player_move_input", {"actor": actor.unit_id, "from": str(actor.grid_position), "to": str(destination)})
				manager.call("handle_pointer_click", _screen(destination))
				while is_instance_valid(manager) and bool(manager.get("battle_active")) and manager.get("input_state") == manager.InputState.ANIMATING:
					await create_timer(0.04).timeout
			else:
				manager.call("request_end_move")
		await create_timer(0.18).timeout
		if not is_instance_valid(manager) or not is_instance_valid(actor) or not is_instance_valid(target) or manager.get("current_unit") != actor:
			continue
		_begin_strike(manager, target.grid_position)
		if target.grid_position in manager.get("_attack_cells"):
			var grid: Object = manager.get("grid")
			var projected: Vector2 = root.get_canvas_transform().basis_xform(
				grid.grid_to_world(target.grid_position) - grid.grid_to_world(actor.grid_position))
			_event("player_attack_input", {"actor": actor.unit_id, "target": target.unit_id,
				"actor_hp": actor.stats.hp, "target_hp_before": target.stats.hp,
				"target_projected_vector_screen": [projected.x, projected.y]})
			manager.call("handle_pointer_hover", _screen(target.grid_position))
			manager.call("handle_pointer_click", _screen(target.grid_position))
			while is_instance_valid(manager) and bool(manager.get("battle_active")) and manager.get("input_state") == manager.InputState.ANIMATING:
				await create_timer(0.04).timeout
		else:
			manager.call("request_cancel_action")
		if is_instance_valid(manager) and bool(manager.get("battle_active")) and manager.get("current_unit") == actor:
			manager.call("request_end_turn")

func _start() -> void:
	var packed: PackedScene = load(ENTRY_SCENE)
	session = packed.instantiate() as Node2D
	root.add_child(session)
	for _index: int in range(8):
		await process_frame
	manager = session.get("manager") as Node
	for unit: Unit in manager.get("units"):
		unit.damage_taken.connect(_damage.bind(unit))
		unit.unit_died.connect(_death.bind(unit))
	manager.get("turn_manager").turn_started.connect(_turn)
	process_frame.connect(_capture)
	_drive_player_ai.call_deferred()

func _capture() -> void:
	if busy:
		return
	busy = true
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(frames_dir.path_join("frame_%05d.png" % frame_index))
	if error != OK or image.get_size() != Vector2i(WIDTH, HEIGHT):
		push_error("Capture failed or dimensions changed")
		quit(2)
		return
	var units: Array[Dictionary] = []
	var current: Unit = manager.get("current_unit") as Unit
	for unit: Unit in manager.get("units"):
		if is_instance_valid(unit):
			units.append(_unit_state(unit, current))
	states.append({"frame": frame_index, "seconds": float(frame_index) / float(FPS),
		"input_state": manager.get("input_state"), "battle_active": manager.get("battle_active"), "units": units,
		"overhead": session.get("battle").get("_unit_overhead_layout").call("get_debug_snapshot")})
	frame_index += 1
	if frame_index >= total_frames:
		var report: Dictionary = {
			"rendering": "PortraitTokenBattle real TacticalScene / Compatibility viewport",
			"fps": FPS,
			"frames": frame_index,
			"duration_seconds": float(frame_index) / float(FPS),
			"size": [WIDTH, HEIGHT],
			"seed": 20261027,
			"fixture": {"source_layout": str(session.get("layout_id")),
				"roster": "original four-unit portrait-token battle",
				"stat_changes": false},
			"events": events,
			"states": states,
		}
		var file: FileAccess = FileAccess.open(output.path_join("facing-align-trace.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t") + "\n")
		manager.call("stop_battle")
		session.queue_free()
		await process_frame
		quit()
		return
	busy = false

## 剑士线没有普通攻击（gameplay-impl PR3，用户 2026-10-28 裁决 S2）。对没有普攻的单位改用其
## 技能栏第一格（剑士为斩击）：技能走同一条出手、动画锁与接触表现路径，录到的素材不变。
## 目标不在可攻击格内时响亮告警，不再静默跳过这一回合的出手。
func _begin_strike(manager: Node, target_cell: Vector2i) -> void:
	var actor: Unit = manager.get("current_unit")
	if actor != null and not actor.has_basic_attack and not actor.skill_ids.is_empty():
		manager.call("request_skill_selection", actor.skill_ids[0])
	else:
		manager.call("request_attack_targeting")
	if not target_cell in manager.get("_attack_cells"):
		push_warning("[capture] %s 本回合无法对 %s 出手，跳过" % [
			actor.unit_id if actor != null else "?", str(target_cell)])
