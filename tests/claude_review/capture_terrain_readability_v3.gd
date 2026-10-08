extends "res://tests/claude_review/capture_terrain_readability_v2.gd"
## v3 仅归一化两个正式 TacticalManager 的悬停，并核验独立生成的绘制树。

const CAPTURE_SCHEMA_V3 := "terrain-mask-capture/3"
const V3_SOURCE_PATHS: PackedStringArray = [
	"res://tests/claude_review/capture_terrain_readability_v3.gd",
	"res://tests/claude_review/validate_terrain_readability_capture_v3.py",
	"res://tests/claude_review/test_terrain_readability_capture_v3.py",
	"res://tests/claude_review/test_terrain_capture_input_routing_v3.gd",
]
const V3_NO_HOVER_CELL := Vector2i(-1, -1)
const V3_IGNORED_RENDER_PROPERTIES: PackedStringArray = [
	"name", "owner", "scene_file_path", "unique_name_in_owner", "script",
	"resource_name", "resource_path", "metadata",
]

var _v3_manager_hover_normalization: Dictionary = {}
var _v3_highlight_comparison: Dictionary = {}
var _v3_diagnostic_path: String = ""


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--v3-diagnostic="):
			_v3_diagnostic_path = argument.trim_prefix("--v3-diagnostic=").simplify_path()
	super._initialize()


func _run() -> void:
	if _map_sizes.is_empty() or _resolutions.is_empty():
		_abort("map sizes and resolutions must be non-empty")
		return
	if _headless_check:
		await _run_headless_check()
		return
	if DisplayServer.get_name() == "headless":
		_abort("Pixel capture requires a rendered desktop; use --headless-check for structure only.")
		return
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_abort("Pixel capture requires the project's Compatibility renderer.")
		return
	if not _validate_output_directory():
		return
	var examples_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXAMPLES_PATH))
	var profile_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if not examples_value is Dictionary or not profile_value is Dictionary:
		_abort("terrain examples or visual profile could not be read")
		return
	_source_fixture_sha256 = _sha256_text(JSON.stringify(examples_value["courtyard"]))
	_load_region_annotation(profile_value)
	root.borderless = true
	root.position = Vector2i.ZERO
	for map_size: int in _map_sizes:
		for resolution: Vector2i in _resolutions:
			if not await _capture_case(map_size, resolution, examples_value["courtyard"], profile_value):
				return
	print("TERRAIN_MASK_CAPTURE_COMPLETE " + JSON.stringify({
		"schema_version": CAPTURE_SCHEMA_V3,
		"cases": _map_sizes.size() * _resolutions.size(),
		"output_directory": _output_directory,
		"pixel_capture": true,
		"all_images_hashed": true,
	}))
	quit(0)


func _request_outside_world_pointer() -> bool:
	if not await super._request_outside_world_pointer():
		return false
	return await _normalize_manager_hover()


func _establish_frozen_capture_state() -> bool:
	if DisplayServer.get_name() == "headless" and not await _normalize_manager_hover():
		return false
	return await super._establish_frozen_capture_state()


func _normalize_manager_hover() -> bool:
	_v3_manager_hover_normalization = {}
	_v3_highlight_comparison = {}
	var reconstruction_manager: Node = _reconstruction_session.get("manager") as Node if is_instance_valid(_reconstruction_session) else null
	if not is_instance_valid(_main_manager) or not is_instance_valid(reconstruction_manager):
		_abort("both actual TacticalManager instances must exist before hover normalization")
		return false
	if not _main_manager.has_method("handle_pointer_hover") or not reconstruction_manager.has_method("handle_pointer_hover"):
		_abort("both actual TacticalManager instances must expose handle_pointer_hover")
		return false
	var main_grid: Variant = _main_manager.get("grid")
	var reconstruction_grid: Variant = reconstruction_manager.get("grid")
	if main_grid == null or reconstruction_grid == null:
		_abort("both TacticalManager instances must have their formal Grid")
		return false
	var main_target_world: Vector2 = main_grid.call("grid_to_world", V3_NO_HOVER_CELL)
	var reconstruction_target_world: Vector2 = reconstruction_grid.call("grid_to_world", V3_NO_HOVER_CELL)
	if main_target_world != reconstruction_target_world \
			or bool(main_grid.call("is_valid", V3_NO_HOVER_CELL)) \
			or bool(reconstruction_grid.call("is_valid", V3_NO_HOVER_CELL)):
		_abort("the shared no-hover grid cell must map to the same invalid board world position")
		return false
	var main_viewport := _main_manager.get_viewport()
	var reconstruction_viewport := reconstruction_manager.get_viewport()
	var main_viewport_position: Vector2 = main_viewport.get_canvas_transform() * main_target_world
	var reconstruction_viewport_position: Vector2 = reconstruction_viewport.get_canvas_transform() * reconstruction_target_world
	var before := {
		"main": _manager_hover_state(_main_manager),
		"reconstruction": _manager_hover_state(reconstruction_manager),
	}
	_main_manager.call("handle_pointer_hover", main_viewport_position)
	reconstruction_manager.call("handle_pointer_hover", reconstruction_viewport_position)
	# handle_pointer_hover rebuilds highlights with queue_free; settle deferred removals first.
	await process_frame
	await process_frame
	var after := {
		"main": _manager_hover_state(_main_manager),
		"reconstruction": _manager_hover_state(reconstruction_manager),
	}
	if bool(after["main"].get("has_hover", true)) or bool(after["reconstruction"].get("has_hover", true)):
		_abort("both actual TacticalManager instances must be no-hover after normalization")
		return false
	_v3_manager_hover_normalization = {
		"input_method": "TacticalManager.handle_pointer_hover",
		"target_grid_cell": [V3_NO_HOVER_CELL.x, V3_NO_HOVER_CELL.y],
		"target_is_invalid_in_both_grids": true,
		"target_world_position": [main_target_world.x, main_target_world.y],
		"main_viewport_position": _point_array(main_viewport_position),
		"reconstruction_viewport_position": _point_array(reconstruction_viewport_position),
		"before": before,
		"after": after,
		"deferred_frees_waited": true,
		"normalized": true,
	}
	if not _record_independent_highlight_comparison():
		return false
	return true


func _manager_hover_state(manager: Node) -> Dictionary:
	var cell_value: Variant = manager.get("_hover_cell")
	var cell: Vector2i = cell_value if cell_value is Vector2i else Vector2i(-999999, -999999)
	var grid: Variant = manager.get("grid")
	return {
		"has_hover": bool(manager.get("_has_hover_cell")),
		"hover_cell": [cell.x, cell.y],
		"hover_cell_valid": bool(grid.call("is_valid", cell)) if grid != null else false,
	}


func _record_independent_highlight_comparison() -> bool:
	var reconstruction_manager: Node = _reconstruction_session.get("manager") as Node if is_instance_valid(_reconstruction_session) else null
	var main_layer := _main_manager.get_node_or_null("HighlightLayer") as Node2D if is_instance_valid(_main_manager) else null
	var reconstruction_layer := reconstruction_manager.get_node_or_null("HighlightLayer") as Node2D if is_instance_valid(reconstruction_manager) else null
	if main_layer == null or reconstruction_layer == null:
		_abort("both independently generated HighlightLayer nodes must exist")
		return false
	var counters_main := {"nodes": 0, "draw_payload_nodes": 0}
	var counters_reconstruction := {"nodes": 0, "draw_payload_nodes": 0}
	var main_signature: Dictionary = _render_branch_signature(main_layer, counters_main)
	var reconstruction_signature: Dictionary = _render_branch_signature(reconstruction_layer, counters_reconstruction)
	var equal: bool = main_signature == reconstruction_signature
	var main_siblings := _sibling_class_list(main_layer)
	var reconstruction_siblings := _sibling_class_list(reconstruction_layer)
	_v3_highlight_comparison = {
		"source": "independently generated main and reconstruction TacticalManager.HighlightLayer after handle_pointer_hover normalization",
		"independently_generated": true,
		"strict_sibling_order_and_class": true,
		"main_sibling_classes": main_siblings,
		"reconstruction_sibling_classes": reconstruction_siblings,
		"sibling_classes_match": main_siblings == reconstruction_siblings,
		"main_payload_sha256": _sha256_text(JSON.stringify(main_signature)),
		"reconstruction_payload_sha256": _sha256_text(JSON.stringify(reconstruction_signature)),
		"payload_equal": equal,
		"copied_to_reconstruction": false,
		"main_nodes_compared": counters_main["nodes"],
		"reconstruction_nodes_compared": counters_reconstruction["nodes"],
		"main_draw_payload_nodes_compared": counters_main["draw_payload_nodes"],
		"reconstruction_draw_payload_nodes_compared": counters_reconstruction["draw_payload_nodes"],
		"deferred_frees_waited": true,
	}
	if not equal:
		_abort("independently generated HighlightLayer sibling order, class, draw payload, or CanvasItem state differs")
		return false
	return true


func _sibling_class_list(node: Node) -> Array[String]:
	var classes: Array[String] = []
	for child: Node in node.get_children():
		classes.append(child.get_class())
	return classes


func _synchronize_session_canvas_state(source: Node, destination: Node,
		source_actor_layer: Node2D) -> bool:
	if is_instance_valid(_main_manager) and source == _main_manager.get_node_or_null("HighlightLayer"):
		# This whole branch was compared independently after deferred removals; never copy it.
		return _compare_independent_render_branches(source, destination, "HighlightLayer")
	return super._synchronize_session_canvas_state(source, destination, source_actor_layer)


func _matching_child_index(source_child: Node, source_index: int, source_parent: Node,
		destination: Node, used: Dictionary) -> int:
	if is_instance_valid(_main_manager):
		var highlight_layer := _main_manager.get_node_or_null("HighlightLayer")
		if source_parent == highlight_layer or _is_descendant_of(source_parent, highlight_layer):
			if source_index < destination.get_child_count() \
					and destination.get_child(source_index).get_class() == source_child.get_class() \
					and not used.has(source_index):
				return source_index
			return -1
	return super._matching_child_index(source_child, source_index, source_parent, destination, used)


func _verify_static_generated_branch(source: Node, destination: Node, path: String) -> bool:
	return _compare_independent_render_branches(source, destination, "TerrainLayer " + path)


func _compare_independent_render_branches(source: Node, destination: Node, label: String) -> bool:
	if not is_instance_valid(source) or not is_instance_valid(destination):
		_abort("independently generated %s branch is missing" % label)
		return false
	var source_counters := {"nodes": 0, "draw_payload_nodes": 0}
	var destination_counters := {"nodes": 0, "draw_payload_nodes": 0}
	var source_signature: Dictionary = _render_branch_signature(source, source_counters)
	var destination_signature: Dictionary = _render_branch_signature(destination, destination_counters)
	if source_signature != destination_signature:
		_abort("independently generated %s sibling order, class, draw payload, or CanvasItem state differs" % label)
		return false
	if label.begins_with("TerrainLayer"):
		_state_sync_counts["terrain_draw_nodes_verified"] = int(_state_sync_counts.get("terrain_draw_nodes_verified", 0)) + int(source_counters["draw_payload_nodes"])
	return true


func _render_branch_signature(node: Node, counters: Dictionary) -> Dictionary:
	counters["nodes"] = int(counters.get("nodes", 0)) + 1
	var signature: Dictionary = {"class": node.get_class()}
	if node is CanvasItem:
		signature["draw_state"] = _stored_render_properties(node)
		if node is Polygon2D or node is Line2D or node is Sprite2D or node is Label or node is RichTextLabel:
			counters["draw_payload_nodes"] = int(counters.get("draw_payload_nodes", 0)) + 1
	var children: Array[Dictionary] = []
	for child: Node in node.get_children():
		children.append(_render_branch_signature(child, counters))
	signature["children"] = children
	return signature


func _stored_render_properties(object: Object) -> Dictionary:
	var result: Dictionary = {}
	var seen_resources: Dictionary = {}
	for property_info: Dictionary in object.get_property_list():
		var property_name: String = str(property_info.get("name", ""))
		var usage: int = int(property_info.get("usage", 0))
		if property_name in V3_IGNORED_RENDER_PROPERTIES or (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		result[property_name] = _stable_render_value(object.get(property_name), seen_resources)
	return result


func _stable_render_value(value: Variant, seen_resources: Dictionary) -> Variant:
	match typeof(value):
		TYPE_VECTOR2:
			var point: Vector2 = value
			return [point.x, point.y]
		TYPE_VECTOR2I:
			var point_i: Vector2i = value
			return [point_i.x, point_i.y]
		TYPE_RECT2:
			var rect: Rect2 = value
			return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
		TYPE_RECT2I:
			var rect_i: Rect2i = value
			return [rect_i.position.x, rect_i.position.y, rect_i.size.x, rect_i.size.y]
		TYPE_COLOR:
			var color: Color = value
			return [color.r, color.g, color.b, color.a]
		TYPE_TRANSFORM2D:
			var transform: Transform2D = value
			return [transform.x.x, transform.x.y, transform.y.x, transform.y.y,
				transform.origin.x, transform.origin.y]
		TYPE_STRING_NAME:
			return str(value)
		TYPE_ARRAY:
			var array_result: Array = []
			for item: Variant in value as Array:
				array_result.append(_stable_render_value(item, seen_resources))
			return array_result
		TYPE_DICTIONARY:
			var dictionary_result: Dictionary = {}
			var keys: Array = (value as Dictionary).keys()
			keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
			for key: Variant in keys:
				dictionary_result[str(key)] = _stable_render_value((value as Dictionary)[key], seen_resources)
			return dictionary_result
		TYPE_PACKED_VECTOR2_ARRAY:
			var points: Array = []
			for point: Vector2 in value as PackedVector2Array:
				points.append([point.x, point.y])
			return points
		TYPE_PACKED_COLOR_ARRAY:
			var colors: Array = []
			for color: Color in value as PackedColorArray:
				colors.append([color.r, color.g, color.b, color.a])
			return colors
		TYPE_OBJECT:
			if value == null:
				return null
			if value is Resource:
				return _stable_resource_value(value as Resource, seen_resources)
			if value is Node:
				return {"class": value.get_class(), "path": str((value as Node).get_path())}
			return {"class": value.get_class()}
	return value


func _stable_resource_value(resource: Resource, seen_resources: Dictionary) -> Dictionary:
	var instance_id: int = resource.get_instance_id()
	if seen_resources.has(instance_id):
		return {"class": resource.get_class(), "cycle": true}
	seen_resources[instance_id] = true
	var properties: Dictionary = {}
	for property_info: Dictionary in resource.get_property_list():
		var property_name: String = str(property_info.get("name", ""))
		var usage: int = int(property_info.get("usage", 0))
		if property_name in ["resource_name", "resource_path", "script"] or (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		properties[property_name] = _stable_render_value(resource.get(property_name), seen_resources)
	seen_resources.erase(instance_id)
	return {"class": resource.get_class(), "resource_path": resource.resource_path, "properties": properties}


func _run_headless_check() -> void:
	var route_result: Dictionary = await _run_input_routing_regression()
	if _failed:
		return
	if not _write_route_diagnostic(route_result):
		_abort("could not save the concise v3 input-routing diagnostic")
		return
	print("TERRAIN_MASK_CAPTURE_V3_ROUTE_REGRESSION " + JSON.stringify({
		"route_divergence_observed": route_result.get("route_divergence_observed", false),
		"normalization_pass": route_result.get("normalization_pass", false),
		"highlight_payload_pass": route_result.get("highlight_payload_pass", false),
		"diagnostic_saved": true,
	}))
	await super._run_headless_check()


func _run_input_routing_regression() -> Dictionary:
	var examples_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXAMPLES_PATH))
	var profile_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if not examples_value is Dictionary or not profile_value is Dictionary:
		_abort("routing regression could not read formal terrain inputs")
		return {}
	_source_fixture_sha256 = _sha256_text(JSON.stringify(examples_value["courtyard"]))
	_load_region_annotation(profile_value)
	var resolution: Vector2i = RESOLUTIONS[0]
	root.size = resolution
	await _frames(4)
	if (root as Viewport).size != resolution:
		_abort("routing regression could not configure the root Window size")
		return {}
	var map_data: Dictionary = _make_map(examples_value["courtyard"], 10)
	var configured: Dictionary = _configure_session(map_data)
	if not bool(configured.get("ok", false)):
		_abort("routing regression could not configure the formal main TerrainBattleSession")
		return {}
	_main_session = configured["session"] as Node2D
	await _wait_for_session(_main_session, root)
	if _failed:
		return {}
	_bind_scene(_main_session)
	await _frames(3)
	if _failed or not _verify_initial_fit(resolution):
		return {}
	if not await _create_reconstruction(map_data, resolution):
		return {}
	var reconstruction_manager: Node = _reconstruction_session.get("manager") as Node
	if not is_instance_valid(reconstruction_manager):
		_abort("routing regression is missing the real reconstruction TacticalManager")
		return {}
	var main_unit: Node2D = _main_manager.get("current_unit") as Node2D
	var reconstruction_unit: Node2D = reconstruction_manager.get("current_unit") as Node2D
	if main_unit == null or reconstruction_unit == null \
			or str(main_unit.get("faction")) != "player" \
			or str(reconstruction_unit.get("faction")) != "player":
		_abort("routing regression requires each formal manager's initial player unit")
		return {}
	var initial_cell: Vector2i = main_unit.get("grid_position")
	if Vector2i(reconstruction_unit.get("grid_position")) != initial_cell:
		_abort("formal sessions do not share the same initial player grid cell")
	if not _apply_manager_hover_at_grid(_main_manager, initial_cell) \
			or not _apply_manager_hover_at_grid(reconstruction_manager, initial_cell):
		_abort("could not establish the same initial player hover through both real manager APIs")
		return {}
	var initial_main: Dictionary = _manager_hover_state(_main_manager)
	var initial_reconstruction: Dictionary = _manager_hover_state(reconstruction_manager)
	if not bool(initial_main.get("has_hover", false)) \
			or not bool(initial_reconstruction.get("has_hover", false)) \
			or initial_main.get("hover_cell") != initial_reconstruction.get("hover_cell"):
		_abort("both real managers must begin the routing regression at the same player hover")
		return {}
	var outside_position: Vector2 = _single_outside_board_pointer()
	if outside_position.x < 0.0:
		_abort("routing regression could not find a UI-free point outside the board")
		return {}
	var outside_cell: Vector2i = _grid_cell_at(outside_position)
	var motion := InputEventMouseMotion.new()
	motion.position = outside_position
	motion.global_position = outside_position
	root.push_input(motion, true)
	await process_frame
	await process_frame
	var after_root_event := {
		"main": _manager_hover_state(_main_manager),
		"reconstruction": _manager_hover_state(reconstruction_manager),
	}
	var hovered_control_path: String = _hovered_control_path(root as Viewport)
	if not hovered_control_path.is_empty():
		_abort("single root input landed on a GUI control: " + hovered_control_path)
		return {}
	var divergence: bool = bool(after_root_event["main"].get("has_hover", true)) \
		!= bool(after_root_event["reconstruction"].get("has_hover", true))
	if not divergence:
		_abort("one root.push_input outside-board motion did not produce real manager hover divergence")
		return {}
	if not await _normalize_manager_hover():
		return {}
	var route_normalization := _v3_manager_hover_normalization.duplicate(true)
	var route_highlight := _v3_highlight_comparison.duplicate(true)
	if not _freeze_and_sync_routing_sessions():
		return {}
	var after_sync := {
		"main": _manager_hover_state(_main_manager),
		"reconstruction": _manager_hover_state(reconstruction_manager),
	}
	var normalization_pass: bool = not bool(after_sync["main"].get("has_hover", true)) \
		and not bool(after_sync["reconstruction"].get("has_hover", true))
	var highlight_pass: bool = bool(route_highlight.get("payload_equal", false)) \
		and not bool(route_highlight.get("copied_to_reconstruction", true))
	if not normalization_pass or not highlight_pass:
		_abort("routing regression failed no-hover normalization or independent highlight equality after sync")
		return {}
	var diagnostic := {
		"schema_version": "terrain-capture-v3-input-routing-diagnostic/1",
		"test": "formal-root-Window-to-independent-SubViewport-hover-routing",
		"headless_structure_only": true,
		"initial_player_grid_cell": [initial_cell.x, initial_cell.y],
		"initial_manager_hover": {"main": initial_main, "reconstruction": initial_reconstruction},
		"root_push_input": {"event_count": 1, "event_type": "InputEventMouseMotion",
			"position": _point_array(outside_position), "requested_grid_cell": [outside_cell.x, outside_cell.y],
			"hovered_control_path": hovered_control_path},
		"after_root_event": after_root_event,
		"route_divergence_observed": divergence,
		"normalization": route_normalization,
		"after_freeze_and_sync": after_sync,
		"freeze_and_sync_pass": true,
		"highlight_payload": route_highlight,
		"normalization_pass": normalization_pass,
		"highlight_payload_pass": highlight_pass,
		"pixel_status": "NOT_TESTED_HEADLESS_RENDERING_DISABLED",
	}
	_close_sessions_and_passes()
	await _frames(2)
	return diagnostic


func _apply_manager_hover_at_grid(manager: Node, cell: Vector2i) -> bool:
	var grid: Variant = manager.get("grid")
	if grid == null or not manager.has_method("handle_pointer_hover"):
		return false
	var viewport := manager.get_viewport()
	var world_position: Vector2 = grid.call("grid_to_world", cell)
	var viewport_position: Vector2 = viewport.get_canvas_transform() * world_position
	manager.call("handle_pointer_hover", viewport_position)
	var state := _manager_hover_state(manager)
	return bool(state.get("has_hover", false)) and state.get("hover_cell") == [cell.x, cell.y]


func _single_outside_board_pointer() -> Vector2:
	var visible: Rect2 = root.get_visible_rect()
	var candidates: Array[Vector2] = [
		visible.position + Vector2(8.0, visible.size.y * 0.5),
		visible.position + Vector2(visible.size.x - 8.0, visible.size.y * 0.5),
		visible.position + Vector2(visible.size.x - 8.0, visible.size.y - 8.0),
		visible.position + Vector2(8.0, visible.size.y - 8.0),
		visible.position + Vector2(8.0, 8.0),
		visible.position + Vector2(visible.size.x - 8.0, 8.0),
	]
	for candidate: Vector2 in candidates:
		if not _grid_cell_is_valid(_grid_cell_at(candidate)):
			return candidate
	return Vector2(-1.0, -1.0)


func _freeze_and_sync_routing_sessions() -> bool:
	_state_sync_counts = {"canvas_items": 0, "props": 0, "frozen_nodes": 0,
		"animation_players_paused": 0, "animated_sprites_paused": 0,
		"animation_trees_disabled": 0, "timers_stopped": 0,
		"sibling_index_matches": 0, "terrain_draw_nodes_verified": 0,
		"highlight_shapes_copied": 0, "draw_payload_nodes": 0}
	_main_session.set_process(false)
	_reconstruction_session.set_process(false)
	_freeze_tree(_main_session)
	_freeze_tree(_reconstruction_session)
	var reconstruction_board := _reconstruction_session.get("board_view") as Node2D
	if not _synchronize_all_props(_main_board, reconstruction_board):
		return false
	if not _synchronize_session_canvas_state(_main_session, _reconstruction_session,
			_main_board.get("_actor_layer") as Node2D):
		return false
	return true


func _write_route_diagnostic(diagnostic: Dictionary) -> bool:
	if _v3_diagnostic_path.is_empty():
		_v3_diagnostic_path = OS.get_environment("SOT_TERRAIN_V3_DIAGNOSTIC_PATH")
	if _v3_diagnostic_path.is_empty() or not _v3_diagnostic_path.is_absolute_path():
		return false
	var parent_path: String = _v3_diagnostic_path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(parent_path) != OK and not DirAccess.dir_exists_absolute(parent_path):
		return false
	var file := FileAccess.open(_v3_diagnostic_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(diagnostic, "\t") + "\n")
	file.close()
	return true


func _build_manifest_skeleton(map_data: Dictionary, resolution: Vector2i, case_name: String) -> Dictionary:
	var manifest: Dictionary = super._build_manifest_skeleton(map_data, resolution, case_name)
	manifest["schema_version"] = CAPTURE_SCHEMA_V3
	manifest["sources"] = _path_hashes(SOURCE_PATHS)
	var state: Dictionary = manifest.get("capture_state", {}).duplicate(true)
	state["manager_hover_normalization"] = _v3_manager_hover_normalization.duplicate(true)
	var canvas: Dictionary = state.get("canvas_state_synchronization", {}).duplicate(true)
	canvas["independent_highlight_payload"] = _v3_highlight_comparison.duplicate(true)
	state["canvas_state_synchronization"] = canvas
	manifest["capture_state"] = state
	return manifest


func _path_hashes(paths: PackedStringArray) -> Dictionary:
	var extended: PackedStringArray = paths.duplicate()
	for path: String in V3_SOURCE_PATHS:
		if path not in extended:
			extended.append(path)
	return super._path_hashes(extended)


func _candidate_record() -> Dictionary:
	var candidate: Dictionary = super._candidate_record()
	var source_hashes: Dictionary = candidate.get("source_sha256", {}).duplicate(true)
	for path: String in V3_SOURCE_PATHS:
		var relative: String = path.trim_prefix("res://")
		var absolute: String = ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(absolute):
			_abort("v3 candidate source is missing: " + relative)
			continue
		source_hashes[relative] = FileAccess.get_sha256(absolute)
	candidate["source_sha256"] = source_hashes
	candidate["candidate_digest_sha256"] = _sha256_text(JSON.stringify(source_hashes))
	return candidate
