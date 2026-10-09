extends "res://tests/claude_review/capture_terrain_readability_v4.gd"
## v5 keeps v4 capture inputs and replaces only frozen redraw observation/diagnostics.

const CAPTURE_SCHEMA_V5 := "terrain-mask-capture/5"
const V5_SOURCE_PATHS: PackedStringArray = [
	"res://tests/claude_review/capture_terrain_readability_v5.gd",
	"res://tests/claude_review/validate_terrain_readability_capture_v5.py",
	"res://tests/claude_review/test_terrain_readability_capture_v5.py",
	"res://dev_doc/ui-art-research/terrain-readability/capture-v5-task.md",
]
const V5_MAX_PROCESS_FRAME_BOUNDARIES := 3
const V5_INPUT_DIGEST_KEYS: Array[String] = [
	"draw_input_sha256",
	"terrain_configuration_sha256",
	"water_configuration_sha256",
	"profile_sha256",
	"material_inputs_sha256",
	"mesh_inputs_sha256",
]

var _v5_draw_observation: Dictionary = {}
var _v5_active_case_index := 0
var _v5_capture_request_id := 0
var _v5_event_ordinal := 0
var _v5_phase_at_callback := "before_frame_pre_draw"
var _v5_event_mutex := Mutex.new()
var _v5_render_sequence := 0
var _v5_current_render_sequence := 0
var _v5_frame_pre_draw_events: Array[Dictionary] = []
var _v5_frame_post_draw_events: Array[Dictionary] = []
var _v5_process_boundaries: Array[Dictionary] = []
var _v5_node_draw_callables: Array[Dictionary] = []
var _v5_render_signal_callables: Array[Dictionary] = []
var _v5_active_failure_stage := ""
var _v5_failure_reason := ""
var _v5_spawn_configuration: Dictionary = {}
var _v5_active_map_size: Array = []
var _v5_active_resolution: Array = []


func _initialize() -> void:
	var v5_diagnostic_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--v5-diagnostic="):
			v5_diagnostic_path = argument.trim_prefix("--v5-diagnostic=").simplify_path()
	super._initialize()
	if not v5_diagnostic_path.is_empty():
		_v4_diagnostic_path = v5_diagnostic_path


func _abort(message: String) -> void:
	_failed = true
	_v5_failure_reason = message
	if _v5_active_failure_stage.is_empty():
		_v5_active_failure_stage = "inherited_abort"
	_v4_write_external_diagnostic()
	super._abort(message)


func _establish_frozen_capture_state() -> bool:
	_v5_active_case_index = _v4_case_diagnostics.size() + 1
	_v5_active_failure_stage = "inherited_v4_frozen_capture_state"
	_v5_draw_observation = {}
	_v5_spawn_configuration = {}
	_v5_active_map_size = []
	_v5_active_resolution = _size_array(root.size) if is_instance_valid(root) else []
	if is_instance_valid(_main_session):
		var configured_map: Dictionary = _main_session.get("_configured_map") as Dictionary
		var map_size := int(configured_map.get("width", 0))
		if map_size > 0:
			_v5_active_map_size = [map_size, map_size]
	var succeeded: bool = await super._establish_frozen_capture_state()
	if not succeeded:
		if _v5_active_failure_stage == "inherited_v4_frozen_capture_state":
			_v5_active_failure_stage = "inherited_v4_frozen_capture_state_failed"
		_v4_write_external_diagnostic()
	return succeeded


func _v4_runtime_spawn_state(map_size: int) -> Dictionary:
	var result: Dictionary = super._v4_runtime_spawn_state(map_size)
	_v5_spawn_configuration = result.duplicate(true)
	return result


func _v4_request_frozen_redraw(main_board: Node2D, reconstruction_board: Node2D,
		before_inputs: Dictionary) -> bool:
	_v5_active_failure_stage = "frozen_redraw_setup"
	_v5_capture_request_id += 1
	var capture_request_id := _v5_capture_request_id
	_v5_event_mutex.lock()
	_v5_render_sequence = 0
	_v5_current_render_sequence = 0
	_v5_phase_at_callback = "before_frame_pre_draw"
	_v5_event_mutex.unlock()
	_v5_frame_pre_draw_events.clear()
	_v5_frame_post_draw_events.clear()
	_v5_process_boundaries.clear()
	_v5_node_draw_callables.clear()
	_v5_render_signal_callables.clear()

	var main_detail := main_board.get("_detail_layer") as CanvasItem if is_instance_valid(main_board) else null
	var reconstruction_detail := reconstruction_board.get("_detail_layer") as CanvasItem if is_instance_valid(reconstruction_board) else null
	var target_nodes: Dictionary = {
		"main_board": main_board,
		"main_detail_layer": main_detail,
		"reconstruction_board": reconstruction_board,
		"reconstruction_detail_layer": reconstruction_detail,
	}
	var side_by_role: Dictionary = {
		"main_board": "main",
		"main_detail_layer": "main",
		"reconstruction_board": "reconstruction",
		"reconstruction_detail_layer": "reconstruction",
	}
	var nodes: Dictionary = {}
	var setup_errors: Array[String] = []
	for role: String in V4_DRAW_ROLES:
		var node := target_nodes.get(role) as CanvasItem
		var side: String = str(side_by_role[role])
		var expected_input: Dictionary = _v5_input_summary(before_inputs.get(side, {}))
		var valid_node: bool = is_instance_valid(node)
		var visible: bool = valid_node and node.is_visible_in_tree()
		var node_record := {
			"node_path": str(node.get_path()) if valid_node else "",
			"node_class": node.get_class() if valid_node else "",
			"side": side,
			"visible_in_tree": visible,
			"queue_redraw_called": false,
			"draw_input_sha256": expected_input.get("draw_input_sha256", ""),
			"input_summary": expected_input,
			"draw_events": [],
		}
		nodes[role] = node_record
		if not valid_node:
			setup_errors.append("missing redraw target: " + role)
			continue
		var board: Node2D = main_board if side == "main" else reconstruction_board
		var callback := Callable(self, "_v5_on_canvas_item_draw").bind(role, node, board, capture_request_id)
		if node.draw.is_connected(callback):
			node.draw.disconnect(callback)
		var connect_error: Error = node.draw.connect(callback)
		if connect_error != OK:
			setup_errors.append("could not connect draw callback: " + role)
		else:
			_v5_node_draw_callables.append({"node": node, "callback": callback})

	var request_frames_drawn := Engine.get_frames_drawn()
	var request_process_frame := Engine.get_process_frames()
	_v4_draw_refresh = {
		"request_method": "CanvasItem.queue_redraw",
		"phase": "after_both_formal_sessions_frozen",
		"headless_structure_only": DisplayServer.get_name() == "headless",
		"frame_post_draw_before_request": request_frames_drawn,
		"frame_post_draw_after_request": request_frames_drawn,
		"queue_redraw_requested": true,
		"request_process_frame": request_process_frame,
		"nodes": nodes,
		"draw_signals_verified": false,
	}
	_v5_draw_observation = {
		"schema_version": "terrain-readability-draw-observation-v5/1",
		"status": "IN_PROGRESS",
		"capture_request_id": capture_request_id,
		"headless_structure_only": DisplayServer.get_name() == "headless",
		"request_frames_drawn": request_frames_drawn,
		"request_process_frame": request_process_frame,
		"max_process_frame_boundaries": V5_MAX_PROCESS_FRAME_BOUNDARIES,
		"frame_pre_draw_events": _v5_frame_pre_draw_events,
		"frame_post_draw_events": _v5_frame_post_draw_events,
		"process_frame_boundaries": _v5_process_boundaries,
		"matched_render_sequence": -1,
		"predicates": _v5_empty_predicates(),
	}

	for role: String in V4_DRAW_ROLES:
		var node := target_nodes.get(role) as CanvasItem
		if not is_instance_valid(node):
			continue
		node.queue_redraw()
		var node_record: Dictionary = nodes[role]
		node_record["queue_redraw_called"] = true
		nodes[role] = node_record
	_v4_draw_refresh["nodes"] = nodes
	_v5_active_failure_stage = "frozen_redraw_queued"

	if not setup_errors.is_empty():
		_v4_draw_refresh["status"] = "FAIL"
		_v5_finish_observation("FAIL", false)
		_v5_disconnect_observers()
		_abort("v5 redraw setup failed: " + "; ".join(setup_errors))
		return false

	if DisplayServer.get_name() == "headless":
		_v4_draw_refresh["status"] = "NOT_TESTED_HEADLESS"
		_v4_draw_refresh["headless_structure_only"] = true
		_v5_draw_observation["status"] = "NOT_TESTED_HEADLESS"
		_v5_draw_observation["predicates"] = {
			"all_signals_seen": "NOT_TESTED",
			"draw_sequence_aligned": "NOT_TESTED",
			"frame_post_draw_seen_for_sequence": "NOT_TESTED",
			"counter_advanced_at_process_boundary": "NOT_TESTED",
			"input_summaries_match": "NOT_TESTED",
		}
		_v5_active_failure_stage = "headless_structure_only"
		_v5_disconnect_observers()
		return true

	_v5_active_failure_stage = "render_signal_subscription"
	if not _v5_connect_render_signals(capture_request_id):
		_v5_finish_observation("FAIL", false)
		_v5_disconnect_observers()
		_abort("v5 could not subscribe to RenderingServer frame signals")
		return false
	_v5_active_failure_stage = "bounded_render_observation"
	for boundary_index: int in range(V5_MAX_PROCESS_FRAME_BOUNDARIES):
		await process_frame
		_v5_event_mutex.lock()
		_v5_event_ordinal += 1
		var boundary_ordinal := _v5_event_ordinal
		var latest_post_sequence := _v5_latest_post_draw_sequence()
		_v5_process_boundaries.append({
			"capture_request_id": capture_request_id,
			"event_ordinal": boundary_ordinal,
			"phase": "process_frame_after_render_return",
			"boundary_index": boundary_index + 1,
			"process_frame": Engine.get_process_frames(),
			"frames_drawn_after_return": Engine.get_frames_drawn(),
			"latest_completed_render_sequence": latest_post_sequence,
			"callback_thread_model": _v5_thread_model(),
		})
		_v5_event_mutex.unlock()
		var matched_sequence := _v5_find_complete_draw_sequence()
		if matched_sequence > 0 and _v5_has_advanced_boundary(matched_sequence, request_frames_drawn):
			break

	_v5_disconnect_observers()
	var matched_render_sequence := _v5_find_complete_draw_sequence()
	var predicates := _v5_compute_predicates(matched_render_sequence, before_inputs, request_frames_drawn)
	_v5_event_mutex.lock()
	var final_nodes: Dictionary = (_v4_draw_refresh.get("nodes", {}) as Dictionary).duplicate(true)
	var final_pre_events: Array[Dictionary] = _v5_frame_pre_draw_events.duplicate(true)
	var final_post_events: Array[Dictionary] = _v5_frame_post_draw_events.duplicate(true)
	var final_boundaries: Array[Dictionary] = _v5_process_boundaries.duplicate(true)
	_v5_event_mutex.unlock()
	var all_passed := true
	for predicate_name: String in predicates:
		if predicates[predicate_name] != true:
			all_passed = false
	_v5_draw_observation["matched_render_sequence"] = matched_render_sequence
	_v5_draw_observation["predicates"] = predicates
	_v5_draw_observation["frame_pre_draw_events"] = final_pre_events
	_v5_draw_observation["frame_post_draw_events"] = final_post_events
	_v5_draw_observation["process_frame_boundaries"] = final_boundaries
	_v5_draw_observation["draw_render_associations"] = _v5_sequence_associations()
	_v5_draw_observation["observed_process_frame_boundaries"] = final_boundaries.size()
	_v5_draw_observation["status"] = "PASS" if all_passed else "FAIL"
	_v4_draw_refresh["frame_post_draw_after_request"] = _v5_last_boundary_frames_drawn(request_frames_drawn)
	_v4_draw_refresh["draw_signals_verified"] = predicates["all_signals_seen"]
	_v4_draw_refresh["headless_structure_only"] = false
	_v4_draw_refresh["status"] = "PASS" if all_passed else "FAIL"
	_v4_draw_refresh["nodes"] = final_nodes
	_v5_active_failure_stage = "frozen_redraw_observed" if all_passed else "frozen_redraw_observation_failed"
	if not all_passed:
		_abort("v5 frozen redraw did not satisfy bounded callback, sequence, input, and process-boundary predicates")
		return false
	return true


func _v5_on_frame_pre_draw(capture_request_id: int) -> void:
	_v5_event_mutex.lock()
	_v5_event_ordinal += 1
	_v5_render_sequence += 1
	_v5_current_render_sequence = _v5_render_sequence
	_v5_phase_at_callback = "after_frame_pre_draw"
	_v5_frame_pre_draw_events.append({
		"capture_request_id": capture_request_id,
		"event_ordinal": _v5_event_ordinal,
		"phase": "frame_pre_draw",
		"render_sequence": _v5_current_render_sequence,
		"frames_drawn_at_callback": Engine.get_frames_drawn(),
		"process_frame": Engine.get_process_frames(),
		"callback_thread_model": _v5_thread_model(),
	})
	_v5_event_mutex.unlock()


func _v5_on_frame_post_draw(capture_request_id: int) -> void:
	_v5_event_mutex.lock()
	_v5_event_ordinal += 1
	_v5_frame_post_draw_events.append({
		"capture_request_id": capture_request_id,
		"event_ordinal": _v5_event_ordinal,
		"phase": "frame_post_draw",
		"render_sequence": _v5_current_render_sequence,
		"frames_drawn_at_callback": Engine.get_frames_drawn(),
		"process_frame": Engine.get_process_frames(),
		"callback_thread_model": _v5_thread_model(),
	})
	_v5_phase_at_callback = "after_frame_post_draw"
	_v5_current_render_sequence = 0
	_v5_event_mutex.unlock()


func _v5_on_canvas_item_draw(role: String, draw_node: CanvasItem, board: Node2D,
		capture_request_id: int) -> void:
	_v5_event_mutex.lock()
	_v5_event_ordinal += 1
	var event_ordinal := _v5_event_ordinal
	var original_phase := _v5_phase_at_callback
	var live_input: Dictionary = _v4_board_input_snapshot(board)
	var summary: Dictionary = _v5_input_summary(live_input)
	var event := {
		"capture_request_id": capture_request_id,
		"event_ordinal": event_ordinal,
		"phase": original_phase,
		"frames_drawn": Engine.get_frames_drawn(),
		"frames_drawn_at_callback": Engine.get_frames_drawn(),
		"process_frame": Engine.get_process_frames(),
		"callback_thread_model": _v5_thread_model(),
		"draw_node_visible_in_tree": draw_node.is_visible_in_tree(),
		"input_summary": summary,
		"time": live_input.get("time", null),
		"draw_input_sha256": live_input.get("draw_input_sha256", ""),
		"terrain_configuration_sha256": live_input.get("terrain_configuration_sha256", ""),
		"water_configuration_sha256": live_input.get("water_configuration_sha256", ""),
		"profile_sha256": live_input.get("profile_sha256", ""),
		"material_inputs_sha256": live_input.get("material_inputs_sha256", ""),
		"mesh_inputs_sha256": live_input.get("mesh_inputs_sha256", ""),
	}
	var nodes: Dictionary = (_v4_draw_refresh.get("nodes", {}) as Dictionary).duplicate(true)
	var node_record: Dictionary = nodes.get(role, {})
	var events: Array = node_record.get("draw_events", [])
	events.append(event)
	node_record["draw_events"] = events
	nodes[role] = node_record
	_v4_draw_refresh["nodes"] = nodes
	_v5_event_mutex.unlock()


func _v5_connect_render_signals(capture_request_id: int) -> bool:
	var pre_callback := Callable(self, "_v5_on_frame_pre_draw").bind(capture_request_id)
	var post_callback := Callable(self, "_v5_on_frame_post_draw").bind(capture_request_id)
	if RenderingServer.frame_pre_draw.is_connected(pre_callback):
		RenderingServer.frame_pre_draw.disconnect(pre_callback)
	if RenderingServer.frame_post_draw.is_connected(post_callback):
		RenderingServer.frame_post_draw.disconnect(post_callback)
	var pre_error: Error = RenderingServer.frame_pre_draw.connect(pre_callback)
	if pre_error != OK:
		return false
	_v5_render_signal_callables.append({"signal": "pre", "callback": pre_callback})
	var post_error: Error = RenderingServer.frame_post_draw.connect(post_callback)
	if post_error != OK:
		RenderingServer.frame_pre_draw.disconnect(pre_callback)
		_v5_render_signal_callables.clear()
		return false
	_v5_render_signal_callables.append({"signal": "post", "callback": post_callback})
	return true


func _v5_disconnect_observers() -> void:
	for entry: Dictionary in _v5_node_draw_callables:
		var node := entry.get("node") as CanvasItem
		var callback: Callable = entry.get("callback", Callable())
		if is_instance_valid(node) and node.draw.is_connected(callback):
			node.draw.disconnect(callback)
	for entry: Dictionary in _v5_render_signal_callables:
		var callback: Callable = entry.get("callback", Callable())
		if entry.get("signal") == "pre":
			if RenderingServer.frame_pre_draw.is_connected(callback):
				RenderingServer.frame_pre_draw.disconnect(callback)
		elif entry.get("signal") == "post":
			if RenderingServer.frame_post_draw.is_connected(callback):
				RenderingServer.frame_post_draw.disconnect(callback)
	_v5_node_draw_callables.clear()
	_v5_render_signal_callables.clear()


func _v5_compute_predicates(matched_sequence: int, before_inputs: Dictionary,
		request_frames_drawn: int) -> Dictionary:
	var all_signals_seen := true
	var input_summaries_match := true
	_v5_event_mutex.lock()
	var nodes: Dictionary = (_v4_draw_refresh.get("nodes", {}) as Dictionary).duplicate(true)
	_v5_event_mutex.unlock()
	var side_by_role: Dictionary = {
		"main_board": "main",
		"main_detail_layer": "main",
		"reconstruction_board": "reconstruction",
		"reconstruction_detail_layer": "reconstruction",
	}
	for role: String in V4_DRAW_ROLES:
		var node: Dictionary = nodes.get(role, {})
		var events: Array = node.get("draw_events", [])
		var request_events: Array = []
		for event_value: Variant in events:
			if event_value is Dictionary and int((event_value as Dictionary).get("capture_request_id", -1)) == _v5_capture_request_id:
				request_events.append(event_value)
		if request_events.is_empty():
			all_signals_seen = false
		var expected: Dictionary = _v5_input_summary(before_inputs.get(side_by_role[role], {}))
		if node.get("input_summary", {}) != expected:
			input_summaries_match = false
		for event_value: Variant in request_events:
			if not event_value is Dictionary:
				input_summaries_match = false
				continue
			var event: Dictionary = event_value
			if event.get("input_summary", {}) != expected:
				input_summaries_match = false
			for key: String in V5_INPUT_DIGEST_KEYS:
				if event.get(key) != expected.get(key):
					input_summaries_match = false
	var matched_has_post_draw := false
	var process_boundary_observed := false
	for association: Dictionary in _v5_sequence_associations():
		if int(association.get("render_sequence", -1)) != matched_sequence:
			continue
		if int(association.get("frame_post_draw_event_ordinal", 0)) > int(association.get("frame_pre_draw_event_ordinal", 0)):
			matched_has_post_draw = true
		if int(association.get("process_boundary_event_ordinal", 0)) > int(association.get("frame_post_draw_event_ordinal", 0)):
			process_boundary_observed = true
	var advanced_at_boundary := matched_sequence > 0 and _v5_has_advanced_boundary(matched_sequence, request_frames_drawn)
	return {
		"all_signals_seen": all_signals_seen,
		"draw_sequence_aligned": matched_sequence > 0,
		"frame_post_draw_seen_for_sequence": matched_has_post_draw,
		"counter_advanced_at_process_boundary": advanced_at_boundary,
		"input_summaries_match": input_summaries_match,
		"process_boundary_after_render_return": process_boundary_observed,
	}


func _v5_find_complete_draw_sequence() -> int:
	for association: Dictionary in _v5_sequence_associations():
		var sequence := int(association.get("render_sequence", 0))
		if sequence > 0:
			return sequence
	return -1


func _v5_sequence_associations() -> Array[Dictionary]:
	var associations: Array[Dictionary] = []
	_v5_event_mutex.lock()
	var nodes: Dictionary = (_v4_draw_refresh.get("nodes", {}) as Dictionary).duplicate(true)
	var pre_events: Array[Dictionary] = _v5_frame_pre_draw_events.duplicate(true)
	var post_events: Array[Dictionary] = _v5_frame_post_draw_events.duplicate(true)
	var boundaries: Array[Dictionary] = _v5_process_boundaries.duplicate(true)
	var request_id := _v5_capture_request_id
	_v5_event_mutex.unlock()
	for pre_event: Dictionary in pre_events:
		if int(pre_event.get("capture_request_id", -1)) != request_id \
				or pre_event.get("phase") != "frame_pre_draw":
			continue
		var sequence := int(pre_event.get("render_sequence", 0))
		var pre_ordinal := int(pre_event.get("event_ordinal", 0))
		if sequence <= 0 or pre_ordinal <= 0:
			continue
		var draw_ordinals_by_role: Dictionary = {}
		var all_roles_seen := true
		for role: String in V4_DRAW_ROLES:
			var role_ordinals: Array[int] = []
			var node: Dictionary = nodes.get(role, {})
			for draw_value: Variant in node.get("draw_events", []):
				if not draw_value is Dictionary:
					continue
				var draw_event: Dictionary = draw_value
				var draw_ordinal := int(draw_event.get("event_ordinal", 0))
				if int(draw_event.get("capture_request_id", -1)) == request_id \
						and draw_event.get("phase") == "before_frame_pre_draw" \
						and draw_ordinal > 0 and draw_ordinal < pre_ordinal:
					role_ordinals.append(draw_ordinal)
			if role_ordinals.is_empty():
				all_roles_seen = false
				draw_ordinals_by_role[role] = []
			else:
				role_ordinals.sort()
				draw_ordinals_by_role[role] = role_ordinals
		if not all_roles_seen:
			continue
		for post_event: Dictionary in post_events:
			var post_ordinal := int(post_event.get("event_ordinal", 0))
			if int(post_event.get("capture_request_id", -1)) != request_id \
					or post_event.get("phase") != "frame_post_draw" \
					or int(post_event.get("render_sequence", 0)) != sequence \
					or post_ordinal <= pre_ordinal:
				continue
			var matching_boundaries: Array[Dictionary] = []
			for boundary: Dictionary in boundaries:
				var boundary_ordinal := int(boundary.get("event_ordinal", 0))
				if int(boundary.get("capture_request_id", -1)) == request_id \
						and boundary.get("phase") == "process_frame_after_render_return" \
						and boundary_ordinal > post_ordinal \
						and int(boundary.get("latest_completed_render_sequence", 0)) >= sequence:
					matching_boundaries.append(boundary)
			if matching_boundaries.is_empty():
				associations.append({
					"capture_request_id": request_id,
					"render_sequence": sequence,
					"draw_event_ordinals_by_role": draw_ordinals_by_role,
					"frame_pre_draw_event_ordinal": pre_ordinal,
					"frame_post_draw_event_ordinal": post_ordinal,
					"process_boundary_event_ordinal": 0,
					"process_boundary_index": 0,
					"process_boundary_frames_drawn": -1,
					"latest_completed_render_sequence": 0,
				})
			else:
				for boundary: Dictionary in matching_boundaries:
					associations.append({
						"capture_request_id": request_id,
						"render_sequence": sequence,
						"draw_event_ordinals_by_role": draw_ordinals_by_role,
						"frame_pre_draw_event_ordinal": pre_ordinal,
						"frame_post_draw_event_ordinal": post_ordinal,
						"process_boundary_event_ordinal": int(boundary.get("event_ordinal", 0)),
						"process_boundary_index": int(boundary.get("boundary_index", 0)),
						"process_boundary_frames_drawn": int(boundary.get("frames_drawn_after_return", -1)),
						"latest_completed_render_sequence": int(boundary.get("latest_completed_render_sequence", 0)),
					})
	return associations


func _v5_has_advanced_boundary(sequence: int, request_frames_drawn: int) -> bool:
	for association: Dictionary in _v5_sequence_associations():
		if int(association.get("render_sequence", 0)) == sequence \
				and int(association.get("process_boundary_event_ordinal", 0)) > int(association.get("frame_post_draw_event_ordinal", 0)) \
				and int(association.get("process_boundary_frames_drawn", -1)) > request_frames_drawn:
			return true
	return false


func _v5_latest_post_draw_sequence() -> int:
	var latest := 0
	for event: Dictionary in _v5_frame_post_draw_events:
		if int(event.get("capture_request_id", -1)) == _v5_capture_request_id:
			latest = maxi(latest, int(event.get("render_sequence", 0)))
	return latest


func _v5_last_boundary_frames_drawn(default_value: int) -> int:
	if _v5_process_boundaries.is_empty():
		return default_value
	return int(_v5_process_boundaries.back().get("frames_drawn_after_return", default_value))


func _v5_input_summary(value: Variant) -> Dictionary:
	var source: Dictionary = value as Dictionary if value is Dictionary else {}
	var result: Dictionary = {"time": source.get("time", null)}
	for key: String in V5_INPUT_DIGEST_KEYS:
		result[key] = source.get(key, "")
	return result


func _v5_thread_model() -> String:
	return "main_thread" if Thread.is_main_thread() else "render_or_worker_thread"


func _v5_empty_predicates() -> Dictionary:
	return {
		"all_signals_seen": false,
		"draw_sequence_aligned": false,
		"frame_post_draw_seen_for_sequence": false,
		"counter_advanced_at_process_boundary": false,
		"input_summaries_match": false,
		"process_boundary_after_render_return": false,
	}


func _v5_finish_observation(status: String, headless: bool) -> void:
	_v5_draw_observation["status"] = status
	_v5_draw_observation["headless_structure_only"] = headless
	_v5_draw_observation["frame_pre_draw_events"] = _v5_frame_pre_draw_events.duplicate(true)
	_v5_draw_observation["frame_post_draw_events"] = _v5_frame_post_draw_events.duplicate(true)
	_v5_draw_observation["process_frame_boundaries"] = _v5_process_boundaries.duplicate(true)
	_v5_draw_observation["draw_render_associations"] = _v5_sequence_associations()
	_v5_draw_observation["observed_process_frame_boundaries"] = _v5_process_boundaries.size()
	_v5_draw_observation["predicates"] = _v5_empty_predicates()


func _build_manifest_skeleton(map_data: Dictionary, resolution: Vector2i, case_name: String) -> Dictionary:
	var manifest: Dictionary = super._build_manifest_skeleton(map_data, resolution, case_name)
	manifest["schema_version"] = CAPTURE_SCHEMA_V5
	manifest["sources"] = _path_hashes(SOURCE_PATHS)
	var state: Dictionary = manifest.get("capture_state", {}).duplicate(true)
	state["terrain_v5_draw_observation"] = _v5_draw_observation.duplicate(true)
	manifest["capture_state"] = state
	return manifest


func _path_hashes(paths: PackedStringArray) -> Dictionary:
	var extended: PackedStringArray = paths.duplicate()
	for path: String in V5_SOURCE_PATHS:
		if path not in extended:
			extended.append(path)
	return super._path_hashes(extended)


func _candidate_record() -> Dictionary:
	var candidate: Dictionary = super._candidate_record()
	var source_hashes: Dictionary = candidate.get("source_sha256", {}).duplicate(true)
	for path: String in V5_SOURCE_PATHS:
		var relative: String = path.trim_prefix("res://")
		var absolute: String = ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(absolute):
			_abort("v5 candidate source is missing: " + relative)
			continue
		source_hashes[relative] = FileAccess.get_sha256(absolute)
	candidate["source_sha256"] = source_hashes
	candidate["candidate_digest_sha256"] = _sha256_text(JSON.stringify(source_hashes))
	return candidate


func _v4_write_external_diagnostic() -> bool:
	var active_case := _v5_active_case_record()
	var output := {
		"schema_version": "terrain-readability-capture-v5-state-diagnostic/1",
		"run_status": "FAIL" if _failed or active_case.get("case_status") == "FAIL" else "STATE_READY",
		"failure_reason": _v5_failure_reason,
		"active_case_status": active_case.get("case_status", "IN_PROGRESS"),
		"candidate_head": _git_output(["rev-parse", "HEAD"]).strip_edges(),
		"branch": _git_output(["branch", "--show-current"]).strip_edges(),
		"headless_structure_only": DisplayServer.get_name() == "headless",
		"pixel_status": "NOT_TESTED_HEADLESS_RENDERING_DISABLED" if DisplayServer.get_name() == "headless" else "NOT_TESTED_SOURCE_ONLY",
		"case_count": _v4_case_diagnostics.size(),
		"cases": _v4_case_diagnostics.duplicate(true),
		"active_case_persisted": not active_case.is_empty(),
		"active_case": active_case,
	}
	if _v4_diagnostic_path.is_empty():
		output["diagnostic_destination"] = "stdout"
		print("TERRAIN_MASK_CAPTURE_V5_DIAGNOSTIC " + JSON.stringify(output))
		return true
	if not _v4_diagnostic_path.is_absolute_path():
		output["diagnostic_destination"] = "stdout_fallback"
		print("TERRAIN_MASK_CAPTURE_V5_DIAGNOSTIC " + JSON.stringify(output))
		return false
	var parent_path := _v4_diagnostic_path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(parent_path) != OK and not DirAccess.dir_exists_absolute(parent_path):
		output["diagnostic_destination"] = "stdout_fallback"
		print("TERRAIN_MASK_CAPTURE_V5_DIAGNOSTIC " + JSON.stringify(output))
		return false
	var file := FileAccess.open(_v4_diagnostic_path, FileAccess.WRITE)
	if file == null:
		output["diagnostic_destination"] = "stdout_fallback"
		print("TERRAIN_MASK_CAPTURE_V5_DIAGNOSTIC " + JSON.stringify(output))
		return false
	output["diagnostic_destination"] = "external_file"
	file.store_string(JSON.stringify(output, "\t") + "\n")
	file.close()
	print("TERRAIN_MASK_CAPTURE_V5_DIAGNOSTIC " + JSON.stringify({
		"active_case_status": output["active_case_status"],
		"active_case_persisted": output["active_case_persisted"],
		"case_count": output["case_count"],
		"diagnostic_destination": "external_file",
	}))
	return true


func _v5_active_case_record() -> Dictionary:
	_v5_event_mutex.lock()
	var nodes: Dictionary = (_v4_draw_refresh.get("nodes", {}) as Dictionary).duplicate(true)
	var pre_draw_events: Array[Dictionary] = _v5_frame_pre_draw_events.duplicate(true)
	var post_draw_events: Array[Dictionary] = _v5_frame_post_draw_events.duplicate(true)
	var process_boundaries: Array[Dictionary] = _v5_process_boundaries.duplicate(true)
	_v5_event_mutex.unlock()
	var draw_observation: Dictionary = _v5_draw_observation.duplicate(true)
	if draw_observation.is_empty():
		draw_observation = {
			"schema_version": "terrain-readability-draw-observation-v5/1",
			"status": "NOT_TESTED",
			"capture_request_id": _v5_capture_request_id,
			"matched_render_sequence": -1,
			"frame_pre_draw_events": pre_draw_events,
			"frame_post_draw_events": post_draw_events,
			"process_frame_boundaries": process_boundaries,
			"draw_render_associations": _v5_sequence_associations(),
			"predicates": _v5_empty_predicates(),
		}
	else:
		draw_observation["frame_pre_draw_events"] = pre_draw_events
		draw_observation["frame_post_draw_events"] = post_draw_events
		draw_observation["process_frame_boundaries"] = process_boundaries
		draw_observation["draw_render_associations"] = _v5_sequence_associations()
	var observed_draw_callbacks: Dictionary = {}
	var missing_nodes: Array[String] = []
	var side_by_role: Dictionary = {
		"main_board": "main",
		"main_detail_layer": "main",
		"reconstruction_board": "reconstruction",
		"reconstruction_detail_layer": "reconstruction",
	}
	for role: String in V4_DRAW_ROLES:
		var node_record: Dictionary = nodes.get(role, {})
		if node_record.is_empty():
			var node := _v5_node_for_role(role)
			var side: String = str(side_by_role[role])
			node_record = {
				"node_path": str(node.get_path()) if is_instance_valid(node) else "",
				"node_class": node.get_class() if is_instance_valid(node) else "",
				"side": side,
				"visible_in_tree": is_instance_valid(node) and node.is_visible_in_tree(),
				"queue_redraw_called": false,
				"draw_input_sha256": _v5_input_summary(_v4_board_inputs.get(side, {})).get("draw_input_sha256", ""),
				"input_summary": _v5_input_summary(_v4_board_inputs.get(side, {})),
				"draw_events": [],
			}
			nodes[role] = node_record
		var events: Array = node_record.get("draw_events", [])
		observed_draw_callbacks[role] = events.duplicate(true)
		if events.is_empty():
			missing_nodes.append(role)
	var status := "IN_PROGRESS"
	if _failed or _v4_draw_refresh.get("status", "") == "FAIL":
		status = "FAIL"
	elif _v4_case_diagnostics.size() >= _v5_active_case_index and not _v4_case_diagnostics.is_empty():
		status = "STATE_READY"
	var predicates: Dictionary = _v5_draw_observation.get("predicates", _v5_empty_predicates()).duplicate(true)
	var board_input_summaries := {
		"main": _v5_input_summary(_v4_board_inputs.get("main", {})),
		"reconstruction": _v5_input_summary(_v4_board_inputs.get("reconstruction", {})),
	}
	return {
		"case_index": _v5_active_case_index,
		"case_status": status,
		"failure_stage": _v5_active_failure_stage,
		"failure_reason": _v5_failure_reason,
		"map_size": _v5_active_map_size.duplicate(),
		"resolution": _v5_active_resolution.duplicate(),
		"spawn_configuration": _v5_spawn_configuration.duplicate(true),
		"board_input_summaries": board_input_summaries,
		"retained_sample_coverage": _v4_retained_coverage.duplicate(true),
		"draw_refresh": {
			"request_method": _v4_draw_refresh.get("request_method", ""),
			"status": _v4_draw_refresh.get("status", ""),
			"headless_structure_only": _v4_draw_refresh.get("headless_structure_only", false),
			"frame_post_draw_before_request": _v4_draw_refresh.get("frame_post_draw_before_request", null),
			"frame_post_draw_after_request": _v4_draw_refresh.get("frame_post_draw_after_request", null),
			"queue_redraw_requested": _v4_draw_refresh.get("queue_redraw_requested", false),
		},
		"draw_observation": draw_observation,
		"nodes": nodes,
		"observed_draw_callbacks": observed_draw_callbacks,
		"missing_nodes": missing_nodes,
		"failure_predicates": predicates,
		"active_case_persisted": true,
	}


func _v5_node_for_role(role: String) -> CanvasItem:
	var main_detail := _main_board.get("_detail_layer") as CanvasItem if is_instance_valid(_main_board) else null
	var reconstruction_board := _reconstruction_session.get("board_view") as Node2D if is_instance_valid(_reconstruction_session) else null
	var reconstruction_detail := reconstruction_board.get("_detail_layer") as CanvasItem if is_instance_valid(reconstruction_board) else null
	match role:
		"main_board":
			return _main_board
		"main_detail_layer":
			return main_detail
		"reconstruction_board":
			return reconstruction_board
		"reconstruction_detail_layer":
			return reconstruction_detail
	return null
