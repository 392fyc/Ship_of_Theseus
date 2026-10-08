extends "res://tests/claude_review/capture_terrain_readability_v3.gd"
## v4 records formal test-spawn overrides and proves frozen BoardView redraws.

const CAPTURE_SCHEMA_V4 := "terrain-mask-capture/4"
const V4_CASES_PATH := "res://tests/claude_review/terrain_readability_capture_v4_cases.json"
const V4_SOURCE_PATHS: PackedStringArray = [
	"res://tests/claude_review/capture_terrain_readability_v4.gd",
	"res://tests/claude_review/validate_terrain_readability_capture_v4.py",
	"res://tests/claude_review/test_terrain_readability_capture_v4.py",
	V4_CASES_PATH,
]
const V4_ALLOWED_CHANGED_PATHS: Array[String] = [
	"enemy_units[0].position",
	"player_units[0].position",
]
const V4_DRAW_ROLES: Array[String] = [
	"main_board",
	"main_detail_layer",
	"reconstruction_board",
	"reconstruction_detail_layer",
]
const V4_SURFACE_PARAMETERS: Array[String] = [
	"terrain_map", "pair_styles", "paving_bank", "map_origin", "map_size",
	"meadow", "moss", "paving", "rock", "relief",
]
const V4_RETAINED_SAMPLE_IDS: Array[String] = [
	"pillar@1.00,4.00",
	"rubble@3.12,2.08",
]

var _v4_diagnostic_path: String = ""
var _v4_case_data: Dictionary = {}
var _v4_case_file_sha256: String = ""
var _v4_next_configuration_role: String = "main"
var _v4_spawn_records: Dictionary = {}
var _v4_board_inputs: Dictionary = {}
var _v4_draw_refresh: Dictionary = {}
var _v4_retained_coverage: Dictionary = {}
var _v4_time_sync_observation: Dictionary = {}
var _v4_frame_state_binding: Dictionary = {}
var _v4_frame_input_snapshot: Dictionary = {}
var _v4_case_diagnostics: Array[Dictionary] = []


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--v4-diagnostic="):
			_v4_diagnostic_path = argument.trim_prefix("--v4-diagnostic=").simplify_path()
	super._initialize()


func _configure_session(map_data: Dictionary) -> Dictionary:
	if not _v4_load_cases():
		return {"ok": false, "reason": "v4 test-case JSON could not be loaded"}
	var role: String = _v4_next_configuration_role
	var configured: Dictionary = super._configure_session(map_data)
	if not bool(configured.get("ok", false)):
		_abort("v4 formal session configuration failed: " + str(configured.get("reason", "unspecified base configuration failure")))
		return configured
	var session := configured.get("session") as Node2D
	if not is_instance_valid(session):
		return {"ok": false, "reason": "formal TerrainBattleSession instance is missing"}
	var formal_map := session.get("_configured_map") as Dictionary
	var case_spec: Dictionary = _v4_case_spec(int(map_data.get("width", 0)))
	if formal_map.is_empty() or case_spec.is_empty():
		session.free()
		_abort("v4 formal configuration or map-size case is empty (formal=%s, case=%s)" % [not formal_map.is_empty(), not case_spec.is_empty()])
		return {"ok": false, "reason": "formal Definition.build configuration or v4 case is empty"}
	var original_map: Dictionary = formal_map.duplicate(true)
	var player_units: Variant = formal_map.get("player_units", [])
	var enemy_units: Variant = formal_map.get("enemy_units", [])
	if not player_units is Array or not enemy_units is Array \
			or (player_units as Array).size() != 1 or (enemy_units as Array).size() != 1 \
			or not (player_units as Array)[0] is Dictionary or not (enemy_units as Array)[0] is Dictionary:
		session.free()
		_abort("v4 formal Definition.build must produce exactly one player and one enemy unit (players=%s, enemies=%s)" % [player_units.size() if player_units is Array else -1, enemy_units.size() if enemy_units is Array else -1])
		return {"ok": false, "reason": "formal Definition.build must return one player and one enemy unit"}
	var desired_player: Array = case_spec.get("player_unit_position", [])
	var desired_enemy: Array = case_spec.get("enemy_unit_position", [])
	if not _v4_position_array(desired_player) or not _v4_position_array(desired_enemy):
		session.free()
		_abort("v4 case spawn coordinates must be finite whole-number pairs")
		return {"ok": false, "reason": "v4 case has invalid test-unit positions"}
	desired_player = [int(desired_player[0]), int(desired_player[1])]
	desired_enemy = [int(desired_enemy[0]), int(desired_enemy[1])]
	var before_player: Dictionary = (player_units as Array)[0]
	var before_enemy: Dictionary = (enemy_units as Array)[0]
	var original_player_position: Variant = before_player.get("position")
	var original_enemy_position: Variant = before_enemy.get("position")
	before_player["position"] = desired_player.duplicate()
	before_enemy["position"] = desired_enemy.duplicate()
	formal_map["player_units"] = player_units
	formal_map["enemy_units"] = enemy_units
	session.set("_configured_map", formal_map)
	var normalized_actual: Dictionary = formal_map.duplicate(true)
	var normalized_players: Array = normalized_actual["player_units"]
	var normalized_enemies: Array = normalized_actual["enemy_units"]
	(normalized_players[0] as Dictionary)["position"] = original_player_position
	(normalized_enemies[0] as Dictionary)["position"] = original_enemy_position
	var changed_paths: Array[String] = []
	if original_enemy_position != desired_enemy:
		changed_paths.append("enemy_units[0].position")
	if original_player_position != desired_player:
		changed_paths.append("player_units[0].position")
	changed_paths.sort()
	var other_fields_equal: bool = normalized_actual == original_map
	if not other_fields_equal or changed_paths != V4_ALLOWED_CHANGED_PATHS:
		session.free()
		_abort("v4 pre-tree override changed fields beyond the two declared unit positions")
		return {"ok": false, "reason": "v4 position-only override check failed"}
	var record := {
		"builder": "TerrainBattleSession.configure_map -> TerrainBattleDefinition.build",
		"role": role,
		"session_instance_id": session.get_instance_id(),
		"applied_before_entering_tree": not session.is_inside_tree(),
		"original_formal_configuration_sha256": _sha256_text(JSON.stringify(original_map)),
		"actual_formal_configuration_sha256": _sha256_text(JSON.stringify(formal_map)),
		"original_positions": {
			"player": _v4_position_json(original_player_position),
			"enemy": _v4_position_json(original_enemy_position),
		},
		"desired_positions": {
			"player": desired_player.duplicate(),
			"enemy": desired_enemy.duplicate(),
		},
		"actual_positions": {
			"player": _v4_position_json((formal_map["player_units"] as Array)[0]["position"]),
			"enemy": _v4_position_json((formal_map["enemy_units"] as Array)[0]["position"]),
		},
		"allowed_changed_paths": V4_ALLOWED_CHANGED_PATHS.duplicate(),
		"changed_paths": changed_paths,
		"all_other_fields_equal": other_fields_equal,
		"position_fields_only": true,
		"unit_counts_before": {"player": original_map["player_units"].size(), "enemy": original_map["enemy_units"].size()},
		"unit_counts_after": {"player": formal_map["player_units"].size(), "enemy": formal_map["enemy_units"].size()},
		"unit_counts_preserved": original_map["player_units"].size() == formal_map["player_units"].size() \
			and original_map["enemy_units"].size() == formal_map["enemy_units"].size(),
		"class_ids_before": _v4_class_ids(original_map),
		"class_ids_after": _v4_class_ids(formal_map),
		"class_ids_preserved": _v4_class_ids(original_map) == _v4_class_ids(formal_map),
	}
	_v4_spawn_records[role] = record
	_v4_next_configuration_role = "reconstruction" if role == "main" else "main"
	return configured


func _establish_frozen_capture_state() -> bool:
	_v4_board_inputs = {}
	_v4_draw_refresh = {}
	_v4_retained_coverage = {}
	_v4_frame_state_binding = {}
	_v4_frame_input_snapshot = {}
	var time_before_freeze: Dictionary = _v4_board_time_pair()
	if not await super._establish_frozen_capture_state():
		return false
	_v4_time_sync_observation = {
		"before_existing_v2_freeze_sync": time_before_freeze,
		"after_existing_v2_freeze_sync": _v4_board_time_pair(),
		"sync_source": "inherited v2 _sync_reconstruction_animation_time",
		"root_cause_inferred": false,
	}
	var map_size := int((_main_session.get("_configured_map") as Dictionary).get("width", 0))
	var spawn_state: Dictionary = _v4_runtime_spawn_state(map_size)
	if _failed or spawn_state.is_empty():
		return false
	_v4_retained_coverage = _v4_retained_sample_coverage()
	if _failed:
		return false
	var board_main := _main_board
	var reconstruction_board := _reconstruction_session.get("board_view") as Node2D
	if not is_instance_valid(board_main) or not is_instance_valid(reconstruction_board):
		_abort("v4 input capture requires both actual BoardView instances")
		return false
	var before_inputs: Dictionary = {
		"main": _v4_board_input_snapshot(board_main),
		"reconstruction": _v4_board_input_snapshot(reconstruction_board),
	}
	_v4_board_inputs = before_inputs.duplicate(true)
	var draw_ok: bool = await _v4_request_frozen_redraw(board_main, reconstruction_board, before_inputs)
	if not draw_ok:
		_v4_write_external_diagnostic()
		return false
	_v4_board_inputs = {
		"main": _v4_board_input_snapshot(board_main),
		"reconstruction": _v4_board_input_snapshot(reconstruction_board),
	}
	var runtime_case := {
		"map_size": [map_size, map_size],
		"resolution": _size_array(root.size),
		"spawn_configuration": spawn_state,
		"board_inputs": _v4_board_inputs,
		"draw_refresh": _v4_draw_refresh,
		"retained_sample_coverage": _v4_retained_coverage,
		"time_sync_observation": _v4_time_sync_observation,
		"pixel_status": "NOT_TESTED_HEADLESS_RENDERING_DISABLED" if DisplayServer.get_name() == "headless" else "NOT_TESTED_SOURCE_ONLY",
	}
	_v4_case_diagnostics.append(runtime_case)
	if not _v4_write_external_diagnostic():
		_abort("could not write v4 diagnostic outside the repository")
		return false
	_capture_state_v2["terrain_v4_spawn_configuration"] = spawn_state.duplicate(true)
	_capture_state_v2["terrain_v4_board_inputs"] = _v4_board_inputs.duplicate(true)
	_capture_state_v2["terrain_v4_draw_refresh"] = _v4_draw_refresh.duplicate(true)
	_capture_state_v2["terrain_v4_retained_sample_coverage"] = _v4_retained_coverage.duplicate(true)
	_capture_state_v2["terrain_v4_time_sync_observation"] = _v4_time_sync_observation.duplicate(true)
	if _headless_check:
		print("TERRAIN_MASK_CAPTURE_V4_CASE_STATE " + JSON.stringify({
			"map_size": runtime_case["map_size"],
			"resolution": runtime_case["resolution"],
			"spawn_positions": spawn_state.get("expected_positions", {}),
			"positions_passable": spawn_state.get("positions_passable", false),
			"positions_avoid_prop_cells": spawn_state.get("positions_avoid_prop_cells", false),
			"retained_sample_coverage": _v4_retained_coverage,
			"draw_status": _v4_draw_refresh.get("status", ""),
			"pixel_status": runtime_case["pixel_status"],
		}))
	return true


func _v4_request_frozen_redraw(main_board: Node2D, reconstruction_board: Node2D,
		before_inputs: Dictionary) -> bool:
	var main_detail := main_board.get("_detail_layer") as CanvasItem
	var reconstruction_detail := reconstruction_board.get("_detail_layer") as CanvasItem
	if main_detail == null or reconstruction_detail == null:
		_abort("both formal BoardView DetailLayer nodes must exist")
		return false
	var target_nodes: Dictionary = {
		"main_board": main_board,
		"main_detail_layer": main_detail,
		"reconstruction_board": reconstruction_board,
		"reconstruction_detail_layer": reconstruction_detail,
	}
	var side_by_role := {
		"main_board": "main",
		"main_detail_layer": "main",
		"reconstruction_board": "reconstruction",
		"reconstruction_detail_layer": "reconstruction",
	}
	var refresh_frame_before := Engine.get_frames_drawn()
	var nodes: Dictionary = {}
	for role: String in V4_DRAW_ROLES:
		var node := target_nodes[role] as CanvasItem
		if not is_instance_valid(node) or not node.is_visible_in_tree():
			_abort("v4 redraw target is missing or hidden: " + role)
			return false
		var side: String = str(side_by_role[role])
		var board: Node2D = main_board if side == "main" else reconstruction_board
		var callback := Callable(self, "_v4_on_canvas_item_draw").bind(role, node, board)
		if not node.draw.is_connected(callback):
			node.draw.connect(callback)
		nodes[role] = {
			"node_path": str(node.get_path()),
			"node_class": node.get_class(),
			"visible_in_tree": node.is_visible_in_tree(),
			"queue_redraw_called": false,
			"draw_input_sha256": before_inputs[side].get("draw_input_sha256", ""),
			"draw_events": [],
		}
	_v4_draw_refresh = {
		"request_method": "CanvasItem.queue_redraw",
		"phase": "after_both_formal_sessions_frozen",
		"headless_structure_only": DisplayServer.get_name() == "headless",
		"frame_post_draw_before_request": refresh_frame_before,
		"frame_post_draw_after_request": refresh_frame_before,
		"queue_redraw_requested": true,
		"nodes": nodes,
		"draw_signals_verified": false,
	}
	for role: String in V4_DRAW_ROLES:
		var node := target_nodes[role] as CanvasItem
		node.queue_redraw()
		var node_record: Dictionary = nodes[role]
		node_record["queue_redraw_called"] = true
		nodes[role] = node_record
	_v4_draw_refresh["nodes"] = nodes
	if DisplayServer.get_name() == "headless":
		_v4_draw_refresh["status"] = "NOT_TESTED_HEADLESS"
		_v4_draw_refresh["headless_structure_only"] = true
		_v4_draw_refresh["draw_signals_verified"] = false
		return true
	await RenderingServer.frame_post_draw
	var refresh_frame_after := Engine.get_frames_drawn()
	_v4_draw_refresh["frame_post_draw_after_request"] = refresh_frame_after
	var all_signals_seen := true
	for role: String in V4_DRAW_ROLES:
		var node_record: Dictionary = (nodes[role] as Dictionary)
		var events: Array = node_record.get("draw_events", [])
		if events.is_empty():
			all_signals_seen = false
	_v4_draw_refresh["draw_signals_verified"] = all_signals_seen
	_v4_draw_refresh["status"] = "PASS" if all_signals_seen and refresh_frame_after > refresh_frame_before else "FAIL"
	_v4_draw_refresh["headless_structure_only"] = false
	if not all_signals_seen or refresh_frame_after <= refresh_frame_before:
		_v4_write_external_diagnostic()
		_abort("frozen redraw did not emit all four real CanvasItem.draw signals in an advanced frame")
		return false
	return true


func _v4_on_canvas_item_draw(role: String, draw_node: CanvasItem, board: Node2D) -> void:
	var nodes: Dictionary = _v4_draw_refresh.get("nodes", {})
	var node_record: Dictionary = nodes.get(role, {})
	var events: Array = node_record.get("draw_events", [])
	var live_input: Dictionary = _v4_board_input_snapshot(board)
	events.append({
		"frames_drawn": Engine.get_frames_drawn(),
		"process_frame": Engine.get_process_frames(),
		"draw_node_visible_in_tree": draw_node.is_visible_in_tree(),
		"draw_input_sha256": live_input.get("draw_input_sha256", ""),
		"time": live_input.get("time", null),
		"terrain_configuration_sha256": live_input.get("terrain_configuration_sha256", ""),
		"water_configuration_sha256": live_input.get("water_configuration_sha256", ""),
		"profile_sha256": live_input.get("profile_sha256", ""),
		"material_inputs_sha256": live_input.get("material_inputs_sha256", ""),
		"mesh_inputs_sha256": live_input.get("mesh_inputs_sha256", ""),
	})
	node_record["draw_events"] = events
	nodes[role] = node_record
	_v4_draw_refresh["nodes"] = nodes


func _v4_runtime_spawn_state(map_size: int) -> Dictionary:
	var case_spec: Dictionary = _v4_case_spec(map_size)
	var main_record: Dictionary = _v4_spawn_records.get("main", {})
	var reconstruction_record: Dictionary = _v4_spawn_records.get("reconstruction", {})
	if case_spec.is_empty() or main_record.is_empty() or reconstruction_record.is_empty():
		_abort("both independently built formal configurations must be present")
		return {}
	var player_position: Array = case_spec.get("player_unit_position", [])
	var enemy_position: Array = case_spec.get("enemy_unit_position", [])
	if not _v4_position_array(player_position) or not _v4_position_array(enemy_position):
		_abort("v4 spawn state could not normalize its fixed test-case coordinates")
		return {}
	var expected_positions := {
		"player": [int(player_position[0]), int(player_position[1])],
		"enemy": [int(enemy_position[0]), int(enemy_position[1])],
	}
	var actual_main: Dictionary = _v4_manager_unit_positions(_main_manager)
	var reconstruction_manager: Node = _reconstruction_session.get("manager") as Node
	var actual_reconstruction: Dictionary = _v4_manager_unit_positions(reconstruction_manager)
	var positions_match: bool = actual_main == expected_positions and actual_reconstruction == expected_positions
	var grid := _main_manager.get("grid") as Grid if is_instance_valid(_main_manager) else null
	var positions_passable := grid != null
	var position_vectors: Array[Vector2i] = []
	for faction: String in ["player", "enemy"]:
		var point_value: Variant = expected_positions.get(faction, [])
		if not _v4_position_array(point_value):
			positions_passable = false
			continue
		var point: Vector2i = Vector2i(int(point_value[0]), int(point_value[1]))
		position_vectors.append(point)
		if grid == null or not grid.is_valid(point):
			positions_passable = false
		else:
			var cell := grid.get_cell(point)
			if cell == null or not cell.is_passable():
				positions_passable = false
	var positions_distinct: bool = position_vectors.size() == 2 and position_vectors[0] != position_vectors[1]
	var prop_cells: Array[Dictionary] = _v4_actual_prop_cells(_main_board)
	var positions_avoid_props := positions_passable
	for point: Vector2i in position_vectors:
		for prop_cell: Dictionary in prop_cells:
			if prop_cell.get("cell") == [point.x, point.y]:
				positions_avoid_props = false
	var main_highlights_visible := _v4_manager_highlights_visible(_main_manager)
	var reconstruction_highlights_visible := _v4_manager_highlights_visible(reconstruction_manager)
	var units_visible := _v4_manager_units_visible(_main_manager) and _v4_manager_units_visible(reconstruction_manager)
	var result := {
		"schema_version": "terrain-readability-spawn-state/1",
		"case_file": V4_CASES_PATH,
		"case_file_sha256": _v4_case_file_sha256,
		"map_size": [map_size, map_size],
		"resolution": _size_array(root.size),
		"builder": "TerrainBattleSession.configure_map -> TerrainBattleDefinition.build",
		"expected_positions": expected_positions,
		"main": main_record.duplicate(true),
		"reconstruction": reconstruction_record.duplicate(true),
		"actual_manager_positions": {"main": actual_main, "reconstruction": actual_reconstruction},
		"positions_distinct": positions_distinct,
		"positions_passable": positions_passable,
		"positions_avoid_prop_cells": positions_avoid_props,
		"positions_avoid_prop_cell_evidence": prop_cells,
		"manager_positions_match_config": positions_match,
		"units_visible": units_visible,
		"highlights_visible": main_highlights_visible and reconstruction_highlights_visible,
		"initial_fit_unchanged": true,
		"all_fields_except_positions_preserved": bool(main_record.get("all_other_fields_equal", false)) \
			and bool(reconstruction_record.get("all_other_fields_equal", false)),
	}
	if not positions_distinct or not positions_passable or not positions_avoid_props \
			or not positions_match or not units_visible or not bool(result["highlights_visible"]) \
			or not bool(result["all_fields_except_positions_preserved"]):
		_capture_state_v2["terrain_v4_spawn_configuration"] = result.duplicate(true)
		print("TERRAIN_MASK_CAPTURE_V4_SPAWN_FAILURE " + JSON.stringify({
			"expected_positions": expected_positions,
			"actual_manager_positions": result["actual_manager_positions"],
			"positions_distinct": positions_distinct,
			"positions_passable": positions_passable,
			"positions_avoid_prop_cells": positions_avoid_props,
			"manager_positions_match_config": positions_match,
			"units_visible": units_visible,
			"highlights_visible": result["highlights_visible"],
			"all_fields_except_positions_preserved": result["all_fields_except_positions_preserved"],
		}))
		_v4_case_diagnostics.append({"map_size": result["map_size"], "resolution": result["resolution"], "spawn_configuration": result})
		_v4_write_external_diagnostic()
		_abort("v4 formal spawn state failed distinct/passable/prop-clear or preservation checks")
		return {}
	return result


func _v4_manager_unit_positions(manager: Node) -> Dictionary:
	var result: Dictionary = {}
	if not is_instance_valid(manager):
		return result
	var units: Variant = manager.get("units")
	if not units is Array:
		return result
	for unit_value: Variant in units:
		if not is_instance_valid(unit_value) or not unit_value is Node2D:
			continue
		var unit := unit_value as Node2D
		var faction := str(unit.get("faction"))
		var position_value: Variant = unit.get("grid_position")
		if position_value is Vector2i:
			var point: Vector2i = position_value
			result[faction] = [point.x, point.y]
	return result


func _v4_manager_units_visible(manager: Node) -> bool:
	if not is_instance_valid(manager):
		return false
	var units: Variant = manager.get("units")
	if not units is Array or (units as Array).size() != 2:
		return false
	for unit_value: Variant in units:
		if not is_instance_valid(unit_value) or not unit_value is CanvasItem \
				or not (unit_value as CanvasItem).is_visible_in_tree():
			return false
	return true


func _v4_manager_highlights_visible(manager: Node) -> bool:
	if not is_instance_valid(manager):
		return false
	var layer := manager.get_node_or_null("HighlightLayer") as CanvasItem
	return layer != null and layer.is_visible_in_tree()


func _v4_actual_prop_cells(board: Node2D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_instance_valid(board):
		return result
	var actor_layer := board.get("_actor_layer") as Node2D
	var specs: Variant = board.get("_props")
	if actor_layer == null or not specs is Array:
		return result
	for spec_value: Variant in specs:
		if not spec_value is Dictionary:
			continue
		var node := (spec_value as Dictionary).get("node") as Node2D
		if not is_instance_valid(node):
			continue
		var logical: Vector2 = _logical_position(node.global_position)
		result.append({
			"stable_id": _stable_id(_classify_prop(node), logical),
			"cell": [floori(logical.x), floori(logical.y)],
			"position": _point_array(logical),
		})
	return result


func _v4_retained_sample_coverage() -> Dictionary:
	var result: Dictionary = {}
	var source_by_id: Dictionary = {}
	for record: Dictionary in _instances:
		source_by_id[str(record.get("stable_id", ""))] = record
	var specs: Variant = _main_board.get("_props") if is_instance_valid(_main_board) else null
	var found: Dictionary = {}
	var grid := _main_manager.get("grid") as Grid if is_instance_valid(_main_manager) else null
	var actor_layer := _main_board.get("_actor_layer") as Node2D if is_instance_valid(_main_board) else null
	var units: Variant = _main_board.get("_unit_positions") if is_instance_valid(_main_board) else null
	var highlights: Variant = _main_board.get("_highlight_positions") if is_instance_valid(_main_board) else null
	if grid == null or actor_layer == null or not specs is Array or not units is Array or not highlights is Array:
		_abort("v4 retained-instance coverage requires actual Grid, props, units, and HighlightLayer centers")
		return {}
	for spec_value: Variant in specs:
		if not spec_value is Dictionary:
			continue
		var spec: Dictionary = spec_value
		var node := spec.get("node") as Node2D
		if not is_instance_valid(node):
			continue
		var kind := _classify_prop(node)
		var logical := _logical_position(node.global_position)
		var stable_id := _stable_id(kind, logical)
		if stable_id not in V4_RETAINED_SAMPLE_IDS:
			continue
		var bounds_value: Variant = spec.get("bounds")
		if not bounds_value is Rect2:
			_abort("v4 retained prop is missing actual _process bounds: " + stable_id)
			return {}
		var bounds: Rect2 = bounds_value
		var hover_cell: Vector2i = _main_board.get("_hover_cell")
		var covered := false
		var hover_source: Dictionary = {}
		if grid.is_valid(hover_cell):
			var hover_world: Vector2 = grid.grid_to_world(hover_cell)
			if hover_world.y <= node.position.y and bounds.has_point(hover_world - node.position + Vector2(0, -10)):
				covered = true
				hover_source = {"hover_cell": [hover_cell.x, hover_cell.y]}
		var covered_units: Array[Dictionary] = []
		for unit_index: int in (units as Array).size():
			var unit_world: Vector2 = (units as Array)[unit_index]
			var unit_pos: Vector2 = actor_layer.to_local(unit_world)
			var unit_rect := Rect2(unit_pos - node.position + Vector2(-24, -44), Vector2(48, 64))
			if unit_pos.y <= node.position.y and bounds.intersects(unit_rect):
				covered = true
			covered_units.append({"unit_index": unit_index, "world_position": _point_array(unit_world),
				"covers_instance": unit_pos.y <= node.position.y and bounds.intersects(unit_rect)})
		var range_covered := false
		var covering_highlights: Array[Dictionary] = []
		for highlight_index: int in (highlights as Array).size():
			var highlight_world: Vector2 = (highlights as Array)[highlight_index]
			var highlight_pos: Vector2 = actor_layer.to_local(highlight_world)
			var covers: bool = highlight_pos.y <= node.position.y and bounds.grow(4.0).has_point(highlight_pos - node.position)
			if covers:
				range_covered = true
			covering_highlights.append({"highlight_index": highlight_index,
				"world_position": _point_array(highlight_world), "covers_instance": covers})
		var target_alpha: float = 0.18 if covered else (0.32 if range_covered else 1.0)
		var source_record: Dictionary = source_by_id.get(stable_id, {})
		var source_modulate: Array = source_record.get("source_modulate", [])
		var source_alpha: float = float(source_modulate[3]) if source_modulate.size() == 4 else -1.0
		var actual_alpha: float = node.modulate.a
		found[stable_id] = {
			"instance_retained": true,
			"stable_id": stable_id,
			"logical_position": _point_array(logical),
			"bounds": _rect_array(bounds),
			"covered": covered,
			"range_covered": range_covered,
			"hover_coverage_source": hover_source,
			"covering_units": covered_units,
			"covering_highlights": covering_highlights,
			"covered_source": "CourtyardBoardView._process unit and hover bounds",
			"range_covered_source": "CourtyardBoardView._process actual HighlightLayer polygon centers",
			"source_modulate_alpha": source_alpha,
			"actual_modulate_alpha": actual_alpha,
			"target_alpha": target_alpha,
			"alpha_matches_source_state": is_equal_approx(actual_alpha, source_alpha),
			"alpha_matches_coverage_target": is_equal_approx(actual_alpha, target_alpha),
			"alpha_mutated_by_v4": false,
			"alpha_threshold_for_instance_measurement": 0.5,
		}
	for stable_id: String in V4_RETAINED_SAMPLE_IDS:
		if not found.has(stable_id):
			_abort("v4 did not retain required source instance " + stable_id)
			return {}
		result[stable_id] = found[stable_id]
		if bool(found[stable_id]["covered"]) or bool(found[stable_id]["range_covered"]):
			_abort("v4 fixed spawn positions still cover required sample " + stable_id)
			return result
	return result


func _v4_board_time_pair() -> Dictionary:
	var result: Dictionary = {}
	if is_instance_valid(_main_board):
		result["main"] = float(_main_board.get("_time"))
	var reconstruction_board := _reconstruction_session.get("board_view") as Node2D if is_instance_valid(_reconstruction_session) else null
	if is_instance_valid(reconstruction_board):
		result["reconstruction"] = float(reconstruction_board.get("_time"))
	return result


func _v4_board_input_snapshot(board: Node2D) -> Dictionary:
	var grid := board.get("grid") as Grid
	var layout: Dictionary = board.get("layout_data") as Dictionary
	var profile: Dictionary = board.get("profile") as Dictionary
	if grid == null:
		return {}
	var terrain_rows: Array[Array] = []
	var water_cells: Array[Array] = []
	for y: int in grid.height:
		var row: Array[int] = []
		for x: int in grid.width:
			var terrain_id: int = grid.get_cell(Vector2i(x, y)).terrain
			row.append(terrain_id)
			if terrain_id in [Cell.Terrain.SHALLOW_WATER, Cell.Terrain.DEEP_WATER]:
				water_cells.append([x, y, terrain_id])
		terrain_rows.append(row)
	var surface := board.get("_surface_layer") as CanvasItem
	var surface_material := surface.material as ShaderMaterial if surface != null else null
	var material_inputs := {
		"surface": _v4_shader_material_snapshot(surface_material),
		"relief": _v4_shader_material_snapshot(board.get("_relief_material") as ShaderMaterial),
		"textures": {
			"ground": _v4_texture_fingerprint(board.get("_ground") as Texture2D),
			"meadow": _v4_texture_fingerprint(board.get("_meadow") as Texture2D),
			"moss": _v4_texture_fingerprint(board.get("_moss") as Texture2D),
			"water": _v4_texture_fingerprint(board.get("_water") as Texture2D),
			"masonry": _v4_texture_fingerprint(board.get("_masonry") as Texture2D),
			"rock": _v4_texture_fingerprint(board.get("_rock") as Texture2D),
		},
	}
	var mesh_inputs := _v4_mesh_inputs(board)
	var terrain_configuration := {
		"grid_size": [grid.width, grid.height],
		"terrain_rows": terrain_rows,
		"layout_data": layout.duplicate(true),
		"layout_sha256": _sha256_text(JSON.stringify(layout)),
		"water_cells": water_cells,
	}
	var water_configuration := {
		"profile_water_surface": profile.get("water_surface", {}).duplicate(true),
		"water_texture": _v4_texture_fingerprint(board.get("_water") as Texture2D),
		"water_cell_count": water_cells.size(),
		"water_cells_sha256": _sha256_text(JSON.stringify(water_cells)),
	}
	var canvas_state := {
		"time": float(board.get("_time")),
		"grid_visible": bool(board.get("grid_visible")),
		"graybox": bool(board.get("graybox")),
		"hover_cell": _v4_vector2i_json(board.get("_hover_cell")),
		"unit_positions": _v4_vector2_array_json(board.get("_unit_positions")),
		"highlight_positions": _v4_vector2_array_json(board.get("_highlight_positions")),
	}
	var snapshot := {
		"time": float(board.get("_time")),
		"terrain_configuration": terrain_configuration,
		"water_configuration": water_configuration,
		"profile": profile.duplicate(true),
		"materials": material_inputs,
		"mesh_inputs": mesh_inputs,
		"canvas_state": canvas_state,
	}
	var material_sha256 := _sha256_text(JSON.stringify(material_inputs))
	var profile_sha256 := _sha256_text(JSON.stringify(profile))
	var terrain_sha256 := _sha256_text(JSON.stringify(terrain_configuration))
	var water_sha256 := _sha256_text(JSON.stringify(water_configuration))
	var mesh_sha256 := _sha256_text(JSON.stringify(mesh_inputs))
	var draw_input := {
		"terrain_configuration_sha256": terrain_sha256,
		"water_configuration_sha256": water_sha256,
		"profile_sha256": profile_sha256,
		"material_inputs_sha256": material_sha256,
		"mesh_inputs_sha256": mesh_sha256,
		"canvas_state": canvas_state,
	}
	snapshot["terrain_configuration_sha256"] = terrain_sha256
	snapshot["water_configuration_sha256"] = water_sha256
	snapshot["profile_sha256"] = profile_sha256
	snapshot["material_inputs_sha256"] = material_sha256
	snapshot["mesh_inputs_sha256"] = mesh_sha256
	snapshot["draw_input_sha256"] = _sha256_text(JSON.stringify(draw_input))
	return snapshot


func _v4_shader_material_snapshot(material: ShaderMaterial) -> Dictionary:
	if material == null:
		return {"available": false}
	var parameters: Dictionary = {}
	for parameter: String in V4_SURFACE_PARAMETERS:
		parameters[parameter] = _v4_stable_value(material.get_shader_parameter(parameter))
	var shader_path := str(material.shader.resource_path) if material.shader != null else ""
	var shader_sha256 := ""
	if not shader_path.is_empty() and shader_path.begins_with("res://"):
		shader_sha256 = FileAccess.get_sha256(ProjectSettings.globalize_path(shader_path))
	return {
		"available": true,
		"class": material.get_class(),
		"shader_resource_path": shader_path,
		"shader_sha256": shader_sha256,
		"parameters": parameters,
		"parameters_sha256": _sha256_text(JSON.stringify(parameters)),
	}


func _v4_texture_fingerprint(texture: Texture2D) -> Dictionary:
	if texture == null:
		return {"available": false}
	var path := str(texture.resource_path)
	var result: Dictionary = {"available": true, "class": texture.get_class(), "resource_path": path}
	if texture is AtlasTexture:
		var atlas := texture as AtlasTexture
		result["region"] = _rect_array(atlas.region)
		result["atlas"] = _v4_texture_fingerprint(atlas.atlas)
	elif texture is ImageTexture:
		var image := (texture as ImageTexture).get_image()
		if image != null and not image.is_empty():
			result["image_size"] = _size_array(image.get_size())
			result["image_format"] = image.get_format()
			result["image_sha256"] = _v4_sha256_bytes(image.get_data())
	if path.begins_with("res://"):
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute):
			result["source_file_sha256"] = FileAccess.get_sha256(absolute)
	return result


func _v4_mesh_inputs(board: Node2D) -> Dictionary:
	var water_meshes: Dictionary = board.get("_water_surface_meshes") as Dictionary
	var water_records: Array[Dictionary] = []
	var water_keys: Array = water_meshes.keys()
	water_keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	for key: Variant in water_keys:
		var mesh := water_meshes[key] as Mesh
		water_records.append({"cell": _v4_vector2i_json(key), "mesh": _v4_mesh_fingerprint(mesh)})
	var relief_records: Array[Dictionary] = []
	var mesh_nodes: Array[Node] = board.find_children("*", "MeshInstance2D", true, false)
	for mesh_node: Node in mesh_nodes:
		var mesh_instance := mesh_node as MeshInstance2D
		if not mesh_node.name.begins_with("TerrainRelief") or mesh_instance.mesh == null:
			continue
		relief_records.append({
			"position": _point_array(mesh_instance.position),
			"mesh": _v4_mesh_fingerprint(mesh_instance.mesh),
		})
	return {
		"water_surface_mesh_count": water_records.size(),
		"water_surface_meshes": water_records,
		"terrain_relief_mesh_count": relief_records.size(),
		"terrain_relief_meshes": relief_records,
		"surface_layer_polygon": _v4_stable_value((board.get("_surface_layer") as Polygon2D).polygon) \
			if board.get("_surface_layer") is Polygon2D else [],
		"water_surface_meshes_sha256": _sha256_text(JSON.stringify(water_records)),
		"terrain_relief_meshes_sha256": _sha256_text(JSON.stringify(relief_records)),
	}


func _v4_mesh_fingerprint(mesh: Mesh) -> Dictionary:
	if mesh == null:
		return {"available": false}
	var surfaces: Array[Dictionary] = []
	for surface_index: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var array_records: Dictionary = {}
		for array_index: int in arrays.size():
			var array_value: Variant = arrays[array_index]
			if array_value == null:
				continue
			var stable_value: Variant = _v4_stable_value(array_value)
			array_records[str(array_index)] = {
				"count": _v4_array_count(array_value),
				"sha256": _sha256_text(JSON.stringify(stable_value)),
			}
		surfaces.append({
			"primitive": mesh.surface_get_primitive_type(surface_index),
			"vertex_count": mesh.surface_get_array_len(surface_index),
			"arrays": array_records,
		})
	return {
		"available": true,
		"class": mesh.get_class(),
		"surface_count": mesh.get_surface_count(),
		"surfaces": surfaces,
		"sha256": _sha256_text(JSON.stringify(surfaces)),
	}


func _v4_array_count(value: Variant) -> int:
	if value is Array or value is PackedByteArray or value is PackedInt32Array \
			or value is PackedInt64Array or value is PackedFloat32Array \
			or value is PackedVector2Array or value is PackedVector3Array \
			or value is PackedColorArray:
		return value.size()
	return 1


func _v4_stable_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2:
			var point: Vector2 = value
			return [point.x, point.y]
		TYPE_VECTOR2I:
			var point_i: Vector2i = value
			return [point_i.x, point_i.y]
		TYPE_VECTOR3:
			var point3: Vector3 = value
			return [point3.x, point3.y, point3.z]
		TYPE_COLOR:
			var color: Color = value
			return [color.r, color.g, color.b, color.a]
		TYPE_RECT2:
			var rect: Rect2 = value
			return _rect_array(rect)
		TYPE_ARRAY:
			var array_result: Array = []
			for item: Variant in value as Array:
				array_result.append(_v4_stable_value(item))
			return array_result
		TYPE_DICTIONARY:
			var dictionary_result: Dictionary = {}
			var keys: Array = (value as Dictionary).keys()
			keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
			for key: Variant in keys:
				dictionary_result[str(key)] = _v4_stable_value((value as Dictionary)[key])
			return dictionary_result
		TYPE_PACKED_VECTOR2_ARRAY:
			var point_array: Array = []
			var packed_points: PackedVector2Array = value
			for point: Vector2 in packed_points:
				point_array.append([point.x, point.y])
			return point_array
		TYPE_PACKED_VECTOR3_ARRAY:
			var point3_array: Array = []
			var packed_points3: PackedVector3Array = value
			for point: Vector3 in packed_points3:
				point3_array.append([point.x, point.y, point.z])
			return point3_array
		TYPE_PACKED_COLOR_ARRAY:
			var color_array: Array = []
			var packed_colors: PackedColorArray = value
			for color: Color in packed_colors:
				color_array.append([color.r, color.g, color.b, color.a])
			return color_array
		TYPE_PACKED_FLOAT32_ARRAY:
			var floats: Array = []
			var packed_floats: PackedFloat32Array = value
			for number: float in packed_floats:
				floats.append(number)
			return floats
		TYPE_PACKED_INT32_ARRAY:
			var ints32: Array = []
			var packed_ints32: PackedInt32Array = value
			for number: int in packed_ints32:
				ints32.append(number)
			return ints32
		TYPE_PACKED_INT64_ARRAY:
			var ints64: Array = []
			var packed_ints64: PackedInt64Array = value
			for number: int in packed_ints64:
				ints64.append(number)
			return ints64
		TYPE_PACKED_BYTE_ARRAY:
			var bytes: PackedByteArray = value
			return bytes.hex_encode()
		TYPE_OBJECT:
			if value == null:
				return null
			if value is Texture2D:
				return _v4_texture_fingerprint(value as Texture2D)
			if value is Resource:
				var resource := value as Resource
				return {"class": resource.get_class(), "resource_path": resource.resource_path}
			if value is Node:
				return {"class": value.get_class()}
			return {"class": value.get_class()}
		TYPE_STRING_NAME:
			return str(value)
	return value


func _v4_sha256_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()


func _v4_runtime_unit_positions(manager: Node) -> Dictionary:
	var result: Dictionary = {}
	if not is_instance_valid(manager):
		return result
	var units: Variant = manager.get("units")
	if not units is Array:
		return result
	for unit_value: Variant in units:
		if not is_instance_valid(unit_value) or not unit_value is Node2D:
			continue
		var unit := unit_value as Node2D
		var cell_value: Variant = unit.get("grid_position")
		if cell_value is Vector2i:
			var cell: Vector2i = cell_value
			result[str(unit.get("faction"))] = [cell.x, cell.y]
	return result


func _v4_board_time(board: Node2D) -> float:
	return float(board.get("_time")) if is_instance_valid(board) else -1.0


func _v4_case_spec(map_size: int) -> Dictionary:
	if not _v4_load_cases():
		return {}
	for case_value: Variant in _v4_case_data.get("cases", []):
		if not case_value is Dictionary:
			continue
		var case: Dictionary = case_value
		var size: Array = case.get("map_size", [])
		if size.size() == 2 and int(size[0]) == map_size and int(size[1]) == map_size:
			return case
	return {}


func _v4_load_cases() -> bool:
	if not _v4_case_data.is_empty():
		return true
	if not FileAccess.file_exists(V4_CASES_PATH):
		_abort("v4 versioned case JSON is missing")
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(V4_CASES_PATH))
	if not parsed is Dictionary or str((parsed as Dictionary).get("schema_version", "")) != "terrain-readability-capture-v4-cases/1":
		_abort("v4 versioned case JSON has an invalid schema")
		return false
	_v4_case_data = parsed as Dictionary
	_v4_case_file_sha256 = FileAccess.get_sha256(ProjectSettings.globalize_path(V4_CASES_PATH))
	return not _v4_case_file_sha256.is_empty()


func _v4_position_array(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 2:
		return false
	for coordinate: Variant in value as Array:
		if typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT] \
				or not is_finite(float(coordinate)) \
				or float(coordinate) != float(int(coordinate)):
			return false
	return true


func _v4_position_json(value: Variant) -> Array[int]:
	if value is Array and (value as Array).size() == 2:
		return [int((value as Array)[0]), int((value as Array)[1])]
	if value is Vector2i:
		var point: Vector2i = value
		return [point.x, point.y]
	return []


func _v4_class_ids(map_data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for faction: String in ["player_units", "enemy_units"]:
		var values: Variant = map_data.get(faction, [])
		var ids: Array[String] = []
		if values is Array:
			for unit_value: Variant in values:
				if unit_value is Dictionary:
					ids.append(str((unit_value as Dictionary).get("class_id", "")))
		result[faction] = ids
	return result


func _v4_vector2i_json(value: Variant) -> Array[int]:
	if value is Vector2i:
		var point: Vector2i = value
		return [point.x, point.y]
	return []


func _v4_vector2_array_json(value: Variant) -> Array[Array]:
	var result: Array[Array] = []
	if value is Array:
		for item: Variant in value as Array:
			if item is Vector2:
				result.append(_point_array(item as Vector2))
	return result


func _build_manifest_skeleton(map_data: Dictionary, resolution: Vector2i, case_name: String) -> Dictionary:
	var manifest: Dictionary = super._build_manifest_skeleton(map_data, resolution, case_name)
	manifest["schema_version"] = CAPTURE_SCHEMA_V4
	manifest["sources"] = _path_hashes(SOURCE_PATHS)
	var state: Dictionary = manifest.get("capture_state", {}).duplicate(true)
	state["terrain_v4_spawn_configuration"] = _v4_runtime_spawn_state(int(map_data.get("width", 0))).duplicate(true)
	state["terrain_v4_board_inputs"] = _v4_board_inputs.duplicate(true)
	state["terrain_v4_draw_refresh"] = _v4_draw_refresh.duplicate(true)
	state["terrain_v4_retained_sample_coverage"] = _v4_retained_coverage.duplicate(true)
	state["terrain_v4_time_sync_observation"] = _v4_time_sync_observation.duplicate(true)
	manifest["capture_state"] = state
	return manifest


func _save_frame_images(images: Dictionary, case_directory: String, frame_id: int) -> Dictionary:
	if images.size() != 12:
		_abort("v4 requires all 12 original capture Images in the existing single-frame callback")
		return {}
	var image_roles: Array[String] = []
	for role: String in images:
		image_roles.append(role)
	image_roles.sort()
	_v4_frame_state_binding = {
		"callback": "RenderingServer.frame_post_draw",
		"frame_id": frame_id,
		"same_frame": true,
		"image_count": images.size(),
		"image_roles": image_roles,
		"readback_awaits_between_images": false,
		"board_state_snapshot_captured": true,
		"board_inputs_sha256": {
			"main": _v4_board_inputs.get("main", {}).get("draw_input_sha256", ""),
			"reconstruction": _v4_board_inputs.get("reconstruction", {}).get("draw_input_sha256", ""),
		},
		"draw_refresh_completed_before_capture_frame": true,
	}
	_v4_frame_input_snapshot = {
		"frame_id": frame_id,
		"main": _v4_board_input_snapshot(_main_board),
		"reconstruction": _v4_board_input_snapshot(_reconstruction_session.get("board_view") as Node2D),
	}
	return super._save_frame_images(images, case_directory, frame_id)


func _write_json(path: String, value: Dictionary) -> bool:
	if path.get_file() != "capture-manifest.json" or not value.has("common_frame"):
		return super._write_json(path, value)
	var manifest: Dictionary = value.duplicate(true)
	var common_frame: Dictionary = manifest.get("common_frame", {}).duplicate(true)
	common_frame["terrain_v4_draw_refresh"] = _v4_draw_refresh.duplicate(true)
	common_frame["terrain_v4_state_snapshot"] = _v4_frame_state_binding.duplicate(true)
	manifest["common_frame"] = common_frame
	manifest["terrain_v4_frame_input_snapshot"] = _v4_frame_input_snapshot.duplicate(true)
	return super._write_json(path, manifest)


func _path_hashes(paths: PackedStringArray) -> Dictionary:
	var extended: PackedStringArray = paths.duplicate()
	for path: String in V4_SOURCE_PATHS:
		if path not in extended:
			extended.append(path)
	return super._path_hashes(extended)


func _candidate_record() -> Dictionary:
	var candidate: Dictionary = super._candidate_record()
	var source_hashes: Dictionary = candidate.get("source_sha256", {}).duplicate(true)
	for path: String in V4_SOURCE_PATHS:
		var relative: String = path.trim_prefix("res://")
		var absolute: String = ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(absolute):
			_abort("v4 candidate source is missing: " + relative)
			continue
		source_hashes[relative] = FileAccess.get_sha256(absolute)
	candidate["source_sha256"] = source_hashes
	candidate["candidate_digest_sha256"] = _sha256_text(JSON.stringify(source_hashes))
	return candidate


func _v4_write_external_diagnostic() -> bool:
	if _v4_diagnostic_path.is_empty():
		return true
	if not _v4_diagnostic_path.is_absolute_path():
		return false
	var parent_path := _v4_diagnostic_path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(parent_path) != OK and not DirAccess.dir_exists_absolute(parent_path):
		return false
	var file := FileAccess.open(_v4_diagnostic_path, FileAccess.WRITE)
	if file == null:
		return false
	var output := {
		"schema_version": "terrain-readability-capture-v4-state-diagnostic/1",
		"candidate_head": _git_output(["rev-parse", "HEAD"]).strip_edges(),
		"branch": _git_output(["branch", "--show-current"]).strip_edges(),
		"headless_structure_only": DisplayServer.get_name() == "headless",
		"pixel_status": "NOT_TESTED_HEADLESS_RENDERING_DISABLED" if DisplayServer.get_name() == "headless" else "NOT_TESTED_SOURCE_ONLY",
		"case_count": _v4_case_diagnostics.size(),
		"cases": _v4_case_diagnostics,
	}
	file.store_string(JSON.stringify(output, "\t") + "\n")
	file.close()
	return true
