extends "res://tests/claude_review/capture_terrain_readability.gd"
## 继承冻结 v1 的同帧采集与全部 mask/readback 门禁，仅固定会话状态并补充 v2 尺寸元数据。

const CAPTURE_SCHEMA_V2 := "terrain-mask-capture/2"
const V2_SOURCE_PATHS: PackedStringArray = [
	"res://tests/claude_review/capture_terrain_readability_v2.gd",
	"res://tests/claude_review/validate_terrain_readability_capture_v2.py",
	"res://tests/claude_review/test_terrain_readability_capture_v2.py",
]
const NO_HOVER_CELL := Vector2i(-1, -1)

var _capture_state_v2: Dictionary = {}
var _requested_pointer_logical := Vector2.ZERO
var _requested_pointer_cell := Vector2i(-999999, -999999)
var _actual_pointer_logical := Vector2.ZERO
var _active_case_directory := ""
var _active_case_name := ""
var _last_frame_images: Dictionary = {}
var _state_sync_counts := {"canvas_items": 0, "props": 0, "frozen_nodes": 0,
	"animation_players_paused": 0, "animated_sprites_paused": 0,
	"animation_trees_disabled": 0, "timers_stopped": 0, "draw_payload_nodes": 0}
var _v2_drawable_ui_bounds: Array[Dictionary] = []
var _v2_excluded_fullscreen_controls: Array[Dictionary] = []
var _v2_exclusion_coverage: Dictionary = {}


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
		"schema_version": CAPTURE_SCHEMA_V2,
		"cases": _map_sizes.size() * _resolutions.size(),
		"output_directory": _output_directory,
		"pixel_capture": true,
		"all_images_hashed": true,
	}))
	quit(0)


func _create_capture_passes(resolution: Vector2i, profile: Dictionary) -> bool:
	if not await _establish_frozen_capture_state():
		return false
	return await super._create_capture_passes(resolution, profile)


func _capture_case(map_size: int, resolution: Vector2i, source_map: Dictionary, profile: Dictionary) -> bool:
	_active_case_name = "%dx%d_%dx%d" % [map_size, map_size, resolution.x, resolution.y]
	_active_case_directory = _output_directory.path_join(_active_case_name)
	_last_frame_images = {}
	return await super._capture_case(map_size, resolution, source_map, profile)


func _establish_frozen_capture_state() -> bool:
	_capture_state_v2 = {}
	_state_sync_counts = {"canvas_items": 0, "props": 0, "frozen_nodes": 0,
		"animation_players_paused": 0, "animated_sprites_paused": 0,
		"animation_trees_disabled": 0, "timers_stopped": 0,
		"sibling_index_matches": 0, "terrain_draw_nodes_verified": 0,
		"highlight_shapes_copied": 0, "draw_payload_nodes": 0}
	if not is_instance_valid(_main_session) or not is_instance_valid(_reconstruction_session):
		_abort("both formal sessions must exist before freezing capture state")
		return false
	var reconstruction_board := _reconstruction_session.get("board_view") as Node2D
	var reconstruction_manager := _reconstruction_session.get("manager") as Node
	if reconstruction_board == null or reconstruction_manager == null:
		_abort("reconstruction session is missing its board or manager")
		return false
	if DisplayServer.get_name() != "headless" and not await _request_outside_world_pointer():
		return false
	# Disable only the two pointer-reading session roots while their boards consume
	# the explicit state below. Their board processes run for one settled frame.
	_main_session.set_process(false)
	_reconstruction_session.set_process(false)
	var context := _collect_visual_context(_main_manager)
	if not bool(context.get("ok", false)):
		_abort("could not read the main session unit/highlight context")
		return false
	_apply_visual_context(_main_board, context)
	_apply_visual_context(reconstruction_board, context)
	_hide_tooltip(_main_session)
	_hide_tooltip(_reconstruction_session)
	await process_frame
	# Capture the source board's current animation phase, then stop all session
	# processing before synchronizing visuals or constructing masks.
	super._sync_reconstruction_animation_time()
	_freeze_tree(_main_session)
	_freeze_tree(_reconstruction_session)
	if not _synchronize_all_props(_main_board, reconstruction_board):
		return false
	if not _synchronize_session_canvas_state(_main_session, _reconstruction_session,
			_main_board.get("_actor_layer") as Node2D):
		return false
	var source_tooltip := _tooltip_record(_main_session)
	var reconstruction_tooltip := _tooltip_record(_reconstruction_session)
	if source_tooltip.get("visible", true) or reconstruction_tooltip.get("visible", true):
		_abort("both terrain tooltips must remain hidden for the explicit no-hover capture state")
		return false
	var source_hover: Vector2i = _main_board.get("_hover_cell")
	var reconstruction_hover: Vector2i = reconstruction_board.get("_hover_cell")
	if source_hover != NO_HOVER_CELL or reconstruction_hover != NO_HOVER_CELL:
		_abort("explicit no-hover cell did not reach both board visibility contexts")
		return false
	var actual_cell := _grid_cell_at(_actual_pointer_logical)
	_capture_state_v2 = {
		"state_source": "explicit capture override copied from the main validated session",
		"pointer": {
			"purpose": "legal-window no-hover input and observation only; visual state is explicitly assigned",
			"requested_logical_position": _point_array(_requested_pointer_logical),
			"actual_logical_position": _point_array(_actual_pointer_logical),
			"requested_grid_cell": [_requested_pointer_cell.x, _requested_pointer_cell.y],
			"actual_grid_cell": [actual_cell.x, actual_cell.y],
			"reconstruction_pointer_used": false,
			"physical_input_used_as_state_authority": false,
		},
		"hover": {
			"requested_cell": [NO_HOVER_CELL.x, NO_HOVER_CELL.y],
			"main_cell": [source_hover.x, source_hover.y],
			"reconstruction_cell": [reconstruction_hover.x, reconstruction_hover.y],
			"main_tooltip": source_tooltip,
			"reconstruction_tooltip": reconstruction_tooltip,
			"main_gui_hovered_control_observation": _hovered_control_path(root as Viewport),
			"reconstruction_gui_hit_test_used": false,
		},
		"unit_highlight_context": context.get("record", {}),
		"prop_synchronization": {
			"stable_id_scheme": "kind plus logical cell plus texture identity and duplicate occurrence",
			"main_prop_count": _state_sync_counts["props"],
			"reconstruction_prop_count": _state_sync_counts["props"],
			"includes_shrub_and_relief": true,
			"property_order_copied_from_main": true,
		},
		"canvas_state_synchronization": {
			"matched_canvas_items": _state_sync_counts["canvas_items"],
			"sibling_index_class_matches": _state_sync_counts["sibling_index_matches"],
			"terrain_draw_nodes_verified": _state_sync_counts["terrain_draw_nodes_verified"],
			"highlight_shapes_copied": _state_sync_counts["highlight_shapes_copied"],
			"copied_draw_payload_nodes": _state_sync_counts["draw_payload_nodes"],
			"copied_properties": ["visible", "modulate", "self_modulate", "z_index", "Node2D.transform", "Control anchors/offsets/size", "Sprite2D texture/region/frame", "Label text", "ProgressBar value", "Polygon2D/Line2D draw payload", "AnimatedSprite2D frame"],
			"terrain_branch": "independently generated from the same validated map; draw payload equality checked before runtime CanvasItem state sync",
			"independent_state_calculation_tested": false,
		},
		"freeze": {
			"scope": "all descendants of both formal TerrainBattleSession roots before mask-pass construction",
			"main_frozen_nodes": _count_nodes(_main_session),
			"reconstruction_frozen_nodes": _count_nodes(_reconstruction_session),
			"total_frozen_nodes": _state_sync_counts["frozen_nodes"],
			"animation_players_paused": _state_sync_counts["animation_players_paused"],
			"animated_sprites_paused": _state_sync_counts["animated_sprites_paused"],
			"animation_trees_disabled": _state_sync_counts["animation_trees_disabled"],
			"timers_stopped": _state_sync_counts["timers_stopped"],
		},
		"headless_structure_only": DisplayServer.get_name() == "headless",
	}
	if _headless_check:
		print("TERRAIN_MASK_CAPTURE_STATE_V2 " + JSON.stringify(_capture_state_v2))
	return true


func _request_outside_world_pointer() -> bool:
	var visible := root.get_visible_rect()
	var candidates: Array[Vector2] = [
		visible.position + Vector2(visible.size.x - 8.0, visible.size.y - 8.0),
		visible.position + Vector2(8.0, visible.size.y - 8.0),
		visible.position + Vector2(visible.size.x - 8.0, 8.0),
		visible.position + Vector2(8.0, 8.0),
		visible.position + Vector2(visible.size.x * 0.5, visible.size.y - 8.0),
		visible.position + Vector2(visible.size.x - 8.0, visible.size.y * 0.5),
	]
	for logical_position: Vector2 in candidates:
		var requested_cell := _grid_cell_at(logical_position)
		if _grid_cell_is_valid(requested_cell):
			continue
		_requested_pointer_logical = logical_position
		_requested_pointer_cell = requested_cell
		Input.warp_mouse(root.get_stretch_transform() * logical_position)
		var motion := InputEventMouseMotion.new()
		motion.position = logical_position
		motion.global_position = logical_position
		root.push_input(motion, true)
		await process_frame
		await process_frame
		_actual_pointer_logical = root.get_mouse_position()
		var actual_cell := _grid_cell_at(_actual_pointer_logical)
		if not _grid_cell_is_valid(actual_cell) and _hovered_control_path(root as Viewport).is_empty():
			return true
	_abort("no legal window point outside the terrain and UI controls was available for the no-hover input")
	return false


func _grid_cell_at(logical_position: Vector2) -> Vector2i:
	var grid: Variant = _main_manager.get("grid") if is_instance_valid(_main_manager) else null
	if grid == null or not grid.has_method("world_to_grid"):
		return Vector2i(-999999, -999999)
	var world := root.get_canvas_transform().affine_inverse() * logical_position
	var result: Vector2i = grid.call("world_to_grid", world)
	return result


func _grid_cell_is_valid(cell: Vector2i) -> bool:
	var grid: Variant = _main_manager.get("grid") if is_instance_valid(_main_manager) else null
	return grid != null and grid.has_method("is_valid") and bool(grid.call("is_valid", cell))


func _collect_visual_context(manager: Node) -> Dictionary:
	var units: Array[Vector2] = []
	var unit_records: Array[Dictionary] = []
	var unit_values: Variant = manager.get("units")
	if unit_values is not Array:
		return {"ok": false}
	for unit_value: Variant in unit_values:
		if not is_instance_valid(unit_value) or not unit_value is Node2D:
			continue
		var unit := unit_value as Node2D
		units.append(unit.global_position)
		unit_records.append({"node": str(unit.name), "position": _point_array(unit.global_position),
			"visible": unit.is_visible_in_tree()})
	var highlights: Array[Vector2] = []
	var highlight_records: Array[Dictionary] = []
	var layer := manager.get("highlight_layer") as Node2D
	if layer != null and layer.visible:
		for child: Node in layer.get_children():
			if child is Polygon2D and child.is_visible_in_tree():
				var polygon := child as Polygon2D
				if polygon.polygon.size() != 4:
					continue
				var center := Vector2.ZERO
				for corner: Vector2 in polygon.polygon:
					center += corner * 0.25
				var world_position := polygon.to_global(center)
				highlights.append(world_position)
				highlight_records.append({"node": str(polygon.name), "position": _point_array(world_position)})
	return {"ok": true, "units": units, "highlights": highlights, "record": {
		"source": "main manager units and visible four-corner highlight polygons",
		"hover_cell": [NO_HOVER_CELL.x, NO_HOVER_CELL.y],
		"unit_count": units.size(), "units": unit_records,
		"highlight_count": highlights.size(), "highlights": highlight_records,
		"copied_to_reconstruction": true,
	}}


func _apply_visual_context(board: Node2D, context: Dictionary) -> void:
	var units: Array[Vector2] = context["units"]
	var highlights: Array[Vector2] = context["highlights"]
	board.call("update_visibility_context", NO_HOVER_CELL, units, highlights)


func _hide_tooltip(session: Node) -> void:
	var tooltip := session.get("_tooltip") as Control
	if tooltip != null:
		tooltip.hide()


func _tooltip_record(session: Node) -> Dictionary:
	var tooltip := session.get("_tooltip") as Control
	if tooltip == null:
		return {"available": false, "visible": false}
	return {"available": true, "visible": tooltip.visible,
		"visible_in_tree": tooltip.is_visible_in_tree(), "text": str((session.get("_tooltip_text") as Label).text) if session.get("_tooltip_text") is Label else ""}


func _hovered_control_path(viewport: Viewport) -> String:
	var hovered := viewport.gui_get_hovered_control()
	return str(hovered.get_path()) if hovered != null else ""


func _freeze_tree(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	_state_sync_counts["frozen_nodes"] = int(_state_sync_counts["frozen_nodes"]) + 1
	if node is AnimationPlayer:
		var player := node as AnimationPlayer
		if player.is_playing():
			player.pause()
			_state_sync_counts["animation_players_paused"] = int(_state_sync_counts["animation_players_paused"]) + 1
	if node is AnimatedSprite2D:
		var sprite := node as AnimatedSprite2D
		if sprite.is_playing():
			sprite.pause()
			_state_sync_counts["animated_sprites_paused"] = int(_state_sync_counts["animated_sprites_paused"]) + 1
	if node is AnimationTree:
		var animation_tree := node as AnimationTree
		if animation_tree.active:
			animation_tree.active = false
			_state_sync_counts["animation_trees_disabled"] = int(_state_sync_counts["animation_trees_disabled"]) + 1
	if node is Timer:
		var timer := node as Timer
		if timer.is_stopped() == false:
			timer.stop()
			_state_sync_counts["timers_stopped"] = int(_state_sync_counts["timers_stopped"]) + 1
	for child: Node in node.get_children():
		_freeze_tree(child)


func _synchronize_all_props(source_board: Node2D, destination_board: Node2D) -> bool:
	var source_specs: Array = source_board.get("_props")
	var destination_specs: Array = destination_board.get("_props")
	var source_inventory := _prop_inventory(source_specs)
	var destination_inventory := _prop_inventory(destination_specs)
	if source_inventory.size() != source_specs.size() or destination_inventory.size() != destination_specs.size():
		_abort("stable prop identifiers are not unique in both sessions")
		return false
	if source_inventory.size() != destination_inventory.size():
		_abort("main and reconstruction _props inventories differ in size")
		return false
	var source_layer := source_board.get("_actor_layer") as Node2D
	var destination_layer := destination_board.get("_actor_layer") as Node2D
	if source_layer == null or destination_layer == null:
		_abort("main or reconstruction actor layer is missing")
		return false
	var source_prop_by_instance: Dictionary = {}
	var destination_node_by_id: Dictionary = {}
	for stable_id: String in source_inventory:
		var source_node := (source_inventory[stable_id] as Dictionary).get("node") as Node2D
		var destination_node := (destination_inventory[stable_id] as Dictionary).get("node") as Node2D
		if source_node.get_parent() != source_layer or destination_node.get_parent() != destination_layer:
			_abort("actor layers do not contain the complete _props inventories")
			return false
		source_prop_by_instance[source_node.get_instance_id()] = stable_id
		destination_node_by_id[stable_id] = destination_node
	var source_non_props := _actor_non_prop_inventory(source_layer, source_prop_by_instance)
	var destination_non_props := _actor_non_prop_inventory(destination_layer, _node_instance_set(destination_inventory))
	if not bool(source_non_props.get("ok", false)) or not bool(destination_non_props.get("ok", false)):
		_abort("actor layer has a missing or ambiguous non-prop child identity")
		return false
	var source_keys: Array = source_non_props["nodes"].keys()
	var destination_keys: Array = destination_non_props["nodes"].keys()
	if source_keys.size() != destination_keys.size():
		_abort("main and reconstruction actor layers have different unit children")
		return false
	for key: String in source_keys:
		if not destination_non_props["nodes"].has(key):
			_abort("reconstruction actor layer is missing unit %s" % key)
			return false
		var source_unit := source_non_props["nodes"][key] as Node
		var destination_unit := destination_non_props["nodes"][key] as Node
		if not _copy_canvas_tree_state(source_unit, destination_unit, "unit/" + key):
			return false
	var reordered: Array[Dictionary] = []
	for index: int in source_specs.size():
		var source_spec: Dictionary = source_specs[index]
		var source_node := source_spec.get("node") as Node2D
		var stable_id := str(source_node.get_meta("terrain_capture_stable_id_v2", ""))
		var destination_spec: Dictionary = destination_inventory[stable_id]
		var destination_node := destination_spec.get("node") as Node2D
		if not _copy_canvas_tree_state(source_node, destination_node, stable_id):
			return false
		var ordered_spec: Dictionary = source_spec.duplicate(true)
		ordered_spec["node"] = destination_node
		reordered.append(ordered_spec)
		destination_node.set_meta("terrain_capture_stable_id_v2", stable_id)
		source_node.set_meta("terrain_capture_stable_id_v2", stable_id)
	var ordered_actor_nodes: Array[Node] = []
	for source_child: Node in source_layer.get_children():
		if source_prop_by_instance.has(source_child.get_instance_id()):
			ordered_actor_nodes.append(destination_node_by_id[source_prop_by_instance[source_child.get_instance_id()]] as Node)
		else:
			var identity := _unit_layer_child_identity(source_child)
			ordered_actor_nodes.append(destination_non_props["nodes"][identity] as Node)
	for index: int in ordered_actor_nodes.size():
		destination_layer.move_child(ordered_actor_nodes[index], index)
	destination_board.set("_props", reordered)
	_state_sync_counts["props"] = source_inventory.size()
	return true


func _node_instance_set(inventory: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for spec_value: Variant in inventory.values():
		var node := (spec_value as Dictionary).get("node") as Node2D
		result[node.get_instance_id()] = true
	return result


func _actor_non_prop_inventory(layer: Node2D, prop_instances: Dictionary) -> Dictionary:
	var nodes: Dictionary = {}
	for child: Node in layer.get_children():
		if prop_instances.has(child.get_instance_id()):
			continue
		var identity := _unit_layer_child_identity(child)
		if identity.is_empty() or nodes.has(identity):
			return {"ok": false}
		nodes[identity] = child
	return {"ok": true, "nodes": nodes}


func _unit_layer_child_identity(node: Node) -> String:
	var unit_id_value: Variant = node.get("unit_id")
	if unit_id_value == null or str(unit_id_value).is_empty():
		return ""
	return "%s|%s" % [str(unit_id_value), node.get_class()]


func _prop_inventory(specs: Array) -> Dictionary:
	var inventory: Dictionary = {}
	var occurrences: Dictionary = {}
	for spec_value: Variant in specs:
		if not spec_value is Dictionary:
			continue
		var spec: Dictionary = spec_value
		var node := spec.get("node") as Node2D
		if not is_instance_valid(node):
			continue
		var base_id := _prop_identity_base(node)
		var occurrence := int(occurrences.get(base_id, 0))
		occurrences[base_id] = occurrence + 1
		var stable_id := "%s#%d" % [base_id, occurrence]
		node.set_meta("terrain_capture_stable_id_v2", stable_id)
		inventory[stable_id] = spec
	return inventory


func _prop_identity_base(node: Node2D) -> String:
	var kind := _classify_prop(node)
	if kind.is_empty():
		kind = "relief" if node is MeshInstance2D else str(node.get_class())
		var sprite := _first_sprite(node)
		if sprite != null and sprite.texture != null:
			var atlas := sprite.texture as AtlasTexture
			var texture_path := atlas.atlas.resource_path if atlas != null and atlas.atlas != null else sprite.texture.resource_path
			if texture_path.contains("courtyard-entry"):
				kind = "entry"
			elif texture_path.contains("natural-rock"):
				kind = "rock"
	var coordinate := _logical_position(node.global_position)
	var signature := ""
	var sprite_node := _first_sprite(node)
	if sprite_node != null and sprite_node.texture != null:
		var atlas_texture := sprite_node.texture as AtlasTexture
		signature = atlas_texture.atlas.resource_path if atlas_texture != null and atlas_texture.atlas != null else sprite_node.texture.resource_path
	return "%s@%s,%s|%s|%s" % [kind, _format_number(coordinate.x), _format_number(coordinate.y), node.get_class(), signature]


func _copy_canvas_tree_state(source: Node, destination: Node, path: String) -> bool:
	if source.get_class() != destination.get_class() or source.get_child_count() != destination.get_child_count():
		_abort("prop clone topology differs for %s at %s" % [path, source.name])
		return false
	if source is CanvasItem and destination is CanvasItem:
		_copy_canvas_item_state(source as CanvasItem, destination as CanvasItem)
		_copy_canvas_payload(source as CanvasItem, destination as CanvasItem)
		_state_sync_counts["canvas_items"] = int(_state_sync_counts["canvas_items"]) + 1
	if source is AnimationPlayer and destination is AnimationPlayer:
		var source_player := source as AnimationPlayer
		var destination_player := destination as AnimationPlayer
		if not source_player.current_animation.is_empty():
			destination_player.play(source_player.current_animation)
			destination_player.seek(source_player.current_animation_position, true)
			destination_player.pause()
	if source is AnimatedSprite2D and destination is AnimatedSprite2D:
		var source_sprite := source as AnimatedSprite2D
		var destination_sprite := destination as AnimatedSprite2D
		destination_sprite.animation = source_sprite.animation
		destination_sprite.frame = source_sprite.frame
		destination_sprite.frame_progress = source_sprite.frame_progress
		destination_sprite.pause()
	for index: int in source.get_child_count():
		if not _copy_canvas_tree_state(source.get_child(index), destination.get_child(index), path + "/" + str(index)):
			return false
	return true


func _synchronize_session_canvas_state(source: Node, destination: Node,
		source_actor_layer: Node2D) -> bool:
	if source.get_class() != destination.get_class():
		_abort("main and reconstruction session root classes differ")
		return false
	if source == _main_manager.get_node_or_null("TerrainLayer"):
		if not _verify_static_generated_branch(source, destination, str(source.get_path())):
			return false
	if source is CanvasItem and destination is CanvasItem:
		_copy_canvas_item_state(source as CanvasItem, destination as CanvasItem)
		if not _is_descendant_of(source, _main_manager.get_node_or_null("TerrainLayer")):
			_copy_canvas_payload(source as CanvasItem, destination as CanvasItem)
		_state_sync_counts["canvas_items"] = int(_state_sync_counts["canvas_items"]) + 1
	var used: Dictionary = {}
	for source_index: int in source.get_child_count():
		var source_child := source.get_child(source_index)
		if source_child == source_actor_layer:
			continue
		var match_index := _matching_child_index(source_child, source_index, source, destination, used)
		if match_index < 0:
			if source_child is CanvasItem:
				_abort("reconstruction is missing CanvasItem %s" % source_child.get_path())
				return false
			continue
		used[match_index] = true
		var destination_child := destination.get_child(match_index)
		if match_index != source_index:
			_state_sync_counts["sibling_index_matches"] = int(_state_sync_counts["sibling_index_matches"]) + 1
		if source == _main_manager.get_node_or_null("HighlightLayer"):
			if not _copy_highlight_branch(source_child, destination_child, str(source.get_path())):
				return false
		elif not _synchronize_session_canvas_state(source_child, destination_child, source_actor_layer):
			return false
	return true


func _matching_child_index(source_child: Node, source_index: int, source_parent: Node,
		destination: Node, used: Dictionary) -> int:
	for index: int in destination.get_child_count():
		if used.has(index):
			continue
		var candidate := destination.get_child(index)
		if candidate.name == source_child.name and candidate.get_class() == source_child.get_class():
			return index
	if source_parent.get_child_count() == destination.get_child_count() and source_index < destination.get_child_count():
		if not used.has(source_index) and destination.get_child(source_index).get_class() == source_child.get_class():
			return source_index
	return -1


func _verify_static_generated_branch(source: Node, destination: Node, path: String) -> bool:
	if source.get_class() != destination.get_class() or source.get_child_count() != destination.get_child_count():
		_abort("independently generated TerrainLayer topology differs at %s" % path)
		return false
	if source is Polygon2D and destination is Polygon2D:
		var source_polygon := source as Polygon2D
		var destination_polygon := destination as Polygon2D
		if source_polygon.polygon != destination_polygon.polygon or source_polygon.color != destination_polygon.color \
				or source_polygon.texture != destination_polygon.texture:
			_abort("independently generated TerrainLayer polygon payload differs at %s" % path)
			return false
		_state_sync_counts["terrain_draw_nodes_verified"] = int(_state_sync_counts["terrain_draw_nodes_verified"]) + 1
	elif source is Line2D and destination is Line2D:
		var source_line := source as Line2D
		var destination_line := destination as Line2D
		if source_line.points != destination_line.points or source_line.default_color != destination_line.default_color \
				or not is_equal_approx(source_line.width, destination_line.width):
			_abort("independently generated TerrainLayer line payload differs at %s" % path)
			return false
		_state_sync_counts["terrain_draw_nodes_verified"] = int(_state_sync_counts["terrain_draw_nodes_verified"]) + 1
	elif source is Label and destination is Label:
		if (source as Label).text != (destination as Label).text:
			_abort("independently generated TerrainLayer label payload differs at %s" % path)
			return false
		_state_sync_counts["terrain_draw_nodes_verified"] = int(_state_sync_counts["terrain_draw_nodes_verified"]) + 1
	for index: int in source.get_child_count():
		var source_child := source.get_child(index)
		var destination_child := destination.get_child(index)
		if source_child.get_class() != destination_child.get_class():
			_abort("independently generated TerrainLayer child class differs at %s/%d" % [path, index])
			return false
		if not _verify_static_generated_branch(source_child, destination_child, "%s/%d" % [path, index]):
			return false
	return true


func _copy_highlight_branch(source: Node, destination: Node, path: String) -> bool:
	if source.get_class() != destination.get_class() or source.get_child_count() != destination.get_child_count():
		_abort("main and reconstruction highlight topology differs at %s" % path)
		return false
	if source is CanvasItem and destination is CanvasItem:
		_copy_canvas_item_state(source as CanvasItem, destination as CanvasItem)
		_state_sync_counts["canvas_items"] = int(_state_sync_counts["canvas_items"]) + 1
	if source is Polygon2D and destination is Polygon2D:
		var source_polygon := source as Polygon2D
		var destination_polygon := destination as Polygon2D
		destination_polygon.polygon = source_polygon.polygon
		destination_polygon.color = source_polygon.color
		destination_polygon.texture = source_polygon.texture
		destination_polygon.texture_offset = source_polygon.texture_offset
		destination_polygon.texture_scale = source_polygon.texture_scale
		destination_polygon.texture_rotation = source_polygon.texture_rotation
		_state_sync_counts["highlight_shapes_copied"] = int(_state_sync_counts["highlight_shapes_copied"]) + 1
	elif source is Line2D and destination is Line2D:
		var source_line := source as Line2D
		var destination_line := destination as Line2D
		destination_line.points = source_line.points
		destination_line.width = source_line.width
		destination_line.default_color = source_line.default_color
		destination_line.closed = source_line.closed
		destination_line.antialiased = source_line.antialiased
		_state_sync_counts["highlight_shapes_copied"] = int(_state_sync_counts["highlight_shapes_copied"]) + 1
	for index: int in source.get_child_count():
		if not _copy_highlight_branch(source.get_child(index), destination.get_child(index), "%s/%d" % [path, index]):
			return false
	return true


func _copy_canvas_item_state(source: CanvasItem, destination: CanvasItem) -> void:
	destination.visible = source.visible
	destination.modulate = source.modulate
	destination.self_modulate = source.self_modulate
	destination.z_index = source.z_index
	destination.z_as_relative = source.z_as_relative
	destination.show_behind_parent = source.show_behind_parent
	destination.light_mask = source.light_mask
	if source is Node2D and destination is Node2D:
		var source_2d := source as Node2D
		var destination_2d := destination as Node2D
		destination_2d.transform = source_2d.transform
		destination_2d.y_sort_enabled = source_2d.y_sort_enabled
		destination_2d.top_level = source_2d.top_level
	if source is Control and destination is Control:
		var source_control := source as Control
		var destination_control := destination as Control
		destination_control.anchor_left = source_control.anchor_left
		destination_control.anchor_top = source_control.anchor_top
		destination_control.anchor_right = source_control.anchor_right
		destination_control.anchor_bottom = source_control.anchor_bottom
		destination_control.offset_left = source_control.offset_left
		destination_control.offset_top = source_control.offset_top
		destination_control.offset_right = source_control.offset_right
		destination_control.offset_bottom = source_control.offset_bottom
		destination_control.custom_minimum_size = source_control.custom_minimum_size
		destination_control.pivot_offset = source_control.pivot_offset
		destination_control.scale = source_control.scale
		destination_control.rotation = source_control.rotation
	if source is AnimatedSprite2D and destination is AnimatedSprite2D:
		var source_sprite := source as AnimatedSprite2D
		var destination_sprite := destination as AnimatedSprite2D
		destination_sprite.animation = source_sprite.animation
		destination_sprite.frame = source_sprite.frame
		destination_sprite.frame_progress = source_sprite.frame_progress


func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	if ancestor == null:
		return false
	var current: Node = node
	while current != null:
		if current == ancestor:
			return true
		current = current.get_parent()
	return false


func _copy_canvas_payload(source: CanvasItem, destination: CanvasItem) -> void:
	var copied := false
	if source is Polygon2D and destination is Polygon2D:
		var source_polygon := source as Polygon2D
		var destination_polygon := destination as Polygon2D
		destination_polygon.polygon = source_polygon.polygon
		destination_polygon.color = source_polygon.color
		destination_polygon.texture = source_polygon.texture
		destination_polygon.texture_offset = source_polygon.texture_offset
		destination_polygon.texture_scale = source_polygon.texture_scale
		destination_polygon.texture_rotation = source_polygon.texture_rotation
		copied = true
	elif source is Line2D and destination is Line2D:
		var source_line := source as Line2D
		var destination_line := destination as Line2D
		destination_line.points = source_line.points
		destination_line.width = source_line.width
		destination_line.default_color = source_line.default_color
		destination_line.closed = source_line.closed
		destination_line.antialiased = source_line.antialiased
		copied = true
	elif source is Sprite2D and destination is Sprite2D:
		var source_sprite := source as Sprite2D
		var destination_sprite := destination as Sprite2D
		destination_sprite.texture = source_sprite.texture
		destination_sprite.centered = source_sprite.centered
		destination_sprite.offset = source_sprite.offset
		destination_sprite.flip_h = source_sprite.flip_h
		destination_sprite.flip_v = source_sprite.flip_v
		destination_sprite.region_enabled = source_sprite.region_enabled
		destination_sprite.region_rect = source_sprite.region_rect
		destination_sprite.hframes = source_sprite.hframes
		destination_sprite.vframes = source_sprite.vframes
		destination_sprite.frame = source_sprite.frame
		destination_sprite.frame_coords = source_sprite.frame_coords
		copied = true
	elif source is ColorRect and destination is ColorRect:
		(destination as ColorRect).color = (source as ColorRect).color
		copied = true
	elif source is TextureRect and destination is TextureRect:
		var source_rect := source as TextureRect
		var destination_rect := destination as TextureRect
		destination_rect.texture = source_rect.texture
		destination_rect.expand_mode = source_rect.expand_mode
		destination_rect.stretch_mode = source_rect.stretch_mode
		copied = true
	elif source is ProgressBar and destination is ProgressBar:
		var source_bar := source as ProgressBar
		var destination_bar := destination as ProgressBar
		destination_bar.min_value = source_bar.min_value
		destination_bar.max_value = source_bar.max_value
		destination_bar.value = source_bar.value
		destination_bar.show_percentage = source_bar.show_percentage
		copied = true
	elif source is Label and destination is Label:
		var source_label := source as Label
		var destination_label := destination as Label
		destination_label.text = source_label.text
		destination_label.horizontal_alignment = source_label.horizontal_alignment
		destination_label.vertical_alignment = source_label.vertical_alignment
		destination_label.autowrap_mode = source_label.autowrap_mode
		destination_label.clip_text = source_label.clip_text
		copied = true
	elif source is RichTextLabel and destination is RichTextLabel:
		(destination as RichTextLabel).text = (source as RichTextLabel).text
		copied = true
	elif source is Button and destination is Button:
		var source_button := source as Button
		var destination_button := destination as Button
		destination_button.text = source_button.text
		destination_button.toggle_mode = source_button.toggle_mode
		destination_button.button_pressed = source_button.button_pressed
		destination_button.disabled = source_button.disabled
		copied = true
	elif source is TextureButton and destination is TextureButton:
		var source_button := source as TextureButton
		var destination_button := destination as TextureButton
		destination_button.texture_normal = source_button.texture_normal
		destination_button.texture_pressed = source_button.texture_pressed
		destination_button.texture_hover = source_button.texture_hover
		destination_button.texture_disabled = source_button.texture_disabled
		destination_button.texture_focused = source_button.texture_focused
		destination_button.disabled = source_button.disabled
		copied = true
	if copied:
		_state_sync_counts["draw_payload_nodes"] = int(_state_sync_counts["draw_payload_nodes"]) + 1


func _add_exclusion_layers() -> void:
	_v2_drawable_ui_bounds.clear()
	_v2_excluded_fullscreen_controls.clear()
	_v2_exclusion_coverage = {}
	super._add_exclusion_layers()
	_exclusion_runtime_record.merge({
		"ui_source": "visible drawable controls in the formal session, preserving actual UI bounds; only the verified BattlefieldBackdrop/Ground role is excluded",
		"bounds_coordinate_space": "main Window visible logical viewport before the viewport stretch transform",
		"drawable_ui_control_bounds": _v2_drawable_ui_bounds.size(),
		"drawable_ui_control_bound_records": _v2_drawable_ui_bounds.duplicate(true),
		"drawable_ui_bounds_union_logical_pixels": _rect_union_area(_v2_drawable_ui_bounds),
		"excluded_background_controls": _v2_excluded_fullscreen_controls.duplicate(true),
		"background_role_filter": "relative TacticalScene/BattlefieldBackdrop/Ground path, ColorRect class, negative CanvasLayer, and at least 99% visible-rect coverage",
		"unit_screen_bounds_union_logical_pixels": _unit_bounds_union_area(_exclusion_runtime_record.get("unit_screen_bounds", [])),
		"full_frame_bounds_removed": not _v2_excluded_fullscreen_controls.is_empty(),
	}, true)
	_exclusion_runtime_record.merge(_v2_exclusion_coverage, true)
	if _headless_check:
		print("TERRAIN_MASK_EXCLUSION_STRUCTURE " + JSON.stringify({
			"drawable_ui_control_bounds": _v2_drawable_ui_bounds.size(),
			"drawable_ui_bounds_union_logical_pixels": _exclusion_runtime_record["drawable_ui_bounds_union_logical_pixels"],
			"excluded_background_controls": _v2_excluded_fullscreen_controls,
			"unit_screen_bounds": _exclusion_runtime_record.get("unit_screen_bounds", []),
			"unit_screen_bounds_union_logical_pixels": _exclusion_runtime_record["unit_screen_bounds_union_logical_pixels"],
			"mask_coverage_status": "NOT_TESTED_HEADLESS",
		}))


func _is_drawable_ui_control(control: Control) -> bool:
	if not super._is_drawable_ui_control(control):
		return false
	var canvas_layer := _nearest_canvas_layer(control)
	var relative_path := str(_main_session.get_path_to(control)) if is_instance_valid(_main_session) else str(control.get_path())
	var rect := control.get_global_rect()
	var visible_rect := root.get_visible_rect()
	var clipped := rect.intersection(visible_rect)
	var control_record := {
		"relative_path": relative_path,
		"class": control.get_class(),
		"canvas_layer": canvas_layer.layer if canvas_layer != null else null,
		"rect": _rect_array(rect),
		"clipped_rect": _rect_array(clipped),
		"area_logical_pixels": clipped.size.x * clipped.size.y,
	}
	if _is_verified_fullscreen_backdrop(control, relative_path, canvas_layer, rect, visible_rect):
		control_record["reason"] = "formal scene background, not HUD"
		_v2_excluded_fullscreen_controls.append(control_record)
		return false
	_v2_drawable_ui_bounds.append(control_record)
	return true


func _nearest_canvas_layer(node: Node) -> CanvasLayer:
	var current: Node = node
	while current != null and current != _main_session:
		if current is CanvasLayer:
			return current as CanvasLayer
		current = current.get_parent()
	return null


func _is_verified_fullscreen_backdrop(control: Control, relative_path: String,
		canvas_layer: CanvasLayer, rect: Rect2, visible_rect: Rect2) -> bool:
	if relative_path != "TacticalScene/BattlefieldBackdrop/Ground" or control.get_class() != "ColorRect":
		return false
	if canvas_layer == null or canvas_layer.layer >= 0 or control.get_parent().name != "BattlefieldBackdrop":
		return false
	var visible_area := visible_rect.size.x * visible_rect.size.y
	if visible_area <= 0.0:
		return false
	var covered := rect.intersection(visible_rect).size
	return covered.x * covered.y >= visible_area * 0.99


func _rect_union_area(records: Array) -> float:
	var rects: Array[Rect2] = []
	for record_value: Variant in records:
		if not record_value is Dictionary:
			continue
		var values: Array = (record_value as Dictionary).get("clipped_rect", [])
		if values.size() == 4 and float(values[2]) > 0.0 and float(values[3]) > 0.0:
			rects.append(Rect2(Vector2(float(values[0]), float(values[1])), Vector2(float(values[2]), float(values[3]))))
	var boundaries: Array[float] = []
	for rect: Rect2 in rects:
		boundaries.append(rect.position.x)
		boundaries.append(rect.end.x)
	boundaries.sort()
	var unique_boundaries: Array[float] = []
	for boundary: float in boundaries:
		if unique_boundaries.is_empty() or not is_equal_approx(boundary, unique_boundaries.back()):
			unique_boundaries.append(boundary)
	var area := 0.0
	for index: int in maxi(0, unique_boundaries.size() - 1):
		var left := unique_boundaries[index]
		var right := unique_boundaries[index + 1]
		if right <= left:
			continue
		var intervals: Array[Vector2] = []
		for rect: Rect2 in rects:
			if rect.position.x < right and rect.end.x > left:
				intervals.append(Vector2(rect.position.y, rect.end.y))
		intervals.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var covered_y := 0.0
		var interval_start := 0.0
		var interval_end := 0.0
		var has_interval := false
		for interval: Vector2 in intervals:
			if not has_interval:
				interval_start = interval.x
				interval_end = interval.y
				has_interval = true
			elif interval.x > interval_end:
				covered_y += maxf(0.0, interval_end - interval_start)
				interval_start = interval.x
				interval_end = interval.y
			else:
				interval_end = maxf(interval_end, interval.y)
		if has_interval:
			covered_y += maxf(0.0, interval_end - interval_start)
		area += (right - left) * covered_y
	return area


func _unit_bounds_union_area(unit_bounds: Variant) -> float:
	if not unit_bounds is Array:
		return 0.0
	var records: Array[Dictionary] = []
	for bound: Variant in unit_bounds:
		if not bound is Dictionary:
			continue
		var rect: Array = (bound as Dictionary).get("rect", [])
		if rect.size() != 4:
			continue
		var clipped := Rect2(Vector2(float(rect[0]), float(rect[1])), Vector2(float(rect[2]), float(rect[3]))).intersection(root.get_visible_rect())
		records.append({"clipped_rect": _rect_array(clipped)})
	return _rect_union_area(records)


func _viewport_records(images: Dictionary) -> Dictionary:
	_last_frame_images = images.duplicate()
	var records: Dictionary = super._viewport_records(images)
	var image := images.get("exclusions") as Image
	if image == null or image.is_empty():
		_v2_exclusion_coverage = {"mask_coverage_status": "UNAVAILABLE", "mask_covered_pixels": 0, "mask_total_pixels": 0}
	else:
		var total := image.get_width() * image.get_height()
		var covered := 0
		var bytes := image.get_data()
		if image.get_format() == Image.FORMAT_RGBA8 and bytes.size() == total * 4:
			for pixel: int in total:
				if bytes[pixel * 4 + 3] > 127:
					covered += 1
		else:
			for y: int in image.get_height():
				for x: int in image.get_width():
					if image.get_pixel(x, y).a > 0.5:
						covered += 1
		_v2_exclusion_coverage = {
			"mask_coverage_status": "CAPTURED",
			"mask_covered_pixels": covered,
			"mask_total_pixels": total,
			"mask_covered_ratio": float(covered) / float(maxi(1, total)),
			"mask_entire_frame_opaque": covered == total,
			"mask_native_image_size": _size_array(image.get_size()),
		}
	_exclusion_runtime_record.merge(_v2_exclusion_coverage, true)
	return records


func _validate_frame_images(images: Dictionary, requested_size: Vector2i) -> bool:
	var failures: Array[String] = []
	for role: String in images:
		var image := images[role] as Image
		if image == null or image.is_empty():
			failures.append("%s: Image readback is empty" % role)
		elif image.get_size() != requested_size:
			failures.append("%s: Image native_size=%s requested=%s" % [role, _size_array(image.get_size()), _size_array(requested_size)])
	if failures.is_empty():
		return true
	_last_frame_images = images.duplicate()
	var records := _diagnostic_viewport_records(images)
	var message := "post-draw Image validation failed: " + "; ".join(failures)
	var evidence_path := _persist_viewport_failure(message, images, records, requested_size)
	_abort("%s; original readback evidence=%s" % [message, evidence_path])
	return false


func _validate_viewport_structure(records: Dictionary, requested_size: Vector2i,
		require_exact_pixel_sizes: bool = false) -> bool:
	var errors := _viewport_structure_errors(records, requested_size, require_exact_pixel_sizes)
	if errors.is_empty():
		return true
	var message := "viewport structure validation failed: " + "; ".join(errors)
	var evidence_path := _persist_viewport_failure(message, _last_frame_images, records, requested_size)
	_abort("%s; original readback evidence=%s" % [message, evidence_path])
	return false


func _viewport_structure_errors(records: Dictionary, requested_size: Vector2i,
		require_exact_pixel_sizes: bool) -> Array[String]:
	var errors: Array[String] = []
	var expected_roles: Array[String] = ["main", "reconstruction"]
	expected_roles.append_array(_passes.keys())
	var main: Dictionary = records.get("main", {})
	var expected_size := _size_array(requested_size)
	var main_visible: Array = main.get("visible_rect", [])
	var main_canvas: Array = main.get("canvas_transform", [])
	var main_final: Array = main.get("final_transform", [])
	var logical_size := Vector2i.ZERO
	if _finite_numeric_array(main_visible, 4):
		logical_size = Vector2i(roundi(float(main_visible[2])), roundi(float(main_visible[3])))
	else:
		errors.append("main: visible_rect 缺失或包含非有限值")
	if main.get("viewport_kind") != "Window" or main.get("window_size") != expected_size:
		errors.append("main: Window physical size 与请求不符，observed=%s requested=%s" % [main.get("window_size", []), expected_size])
	var main_scale: Array = main.get("stretch_scale", [])
	var main_stretch: Array = main.get("stretch_transform", [])
	if not _finite_numeric_array(main_scale, 2) or not _finite_numeric_array(main_stretch, 6) \
			or float(main_scale[0]) <= 0.0 or float(main_scale[1]) <= 0.0:
		errors.append("main: Window stretch transform/scale 缺失或无效")
	else:
		var basis_scale := [
			sqrt(pow(float(main_stretch[0]), 2.0) + pow(float(main_stretch[1]), 2.0)),
			sqrt(pow(float(main_stretch[2]), 2.0) + pow(float(main_stretch[3]), 2.0)),
		]
		if not _numeric_arrays_equal(basis_scale, main_scale, 0.000001):
			errors.append("main: stretch_scale 与 stretch_transform basis 不符")
	var expected_window_report := expected_size
	if _finite_numeric_array(main_scale, 2) and float(main_scale[0]) > 0.0 and float(main_scale[1]) > 0.0:
		expected_window_report = [ceili(float(requested_size.x) * float(main_scale[0])),
			ceili(float(requested_size.y) * float(main_scale[1]))]
	for role: String in expected_roles:
		if not records.has(role):
			errors.append("%s: viewport metadata record missing" % role)
			continue
		var record: Dictionary = records[role]
		if record.get("size") != expected_size:
			errors.append("%s: viewport size observed=%s requested=%s" % [role, record.get("size", []), expected_size])
		var expected_texture := expected_window_report if role == "main" else expected_size
		if record.get("texture_reported_size") != expected_texture or record.get("texture_size") != expected_texture:
			errors.append("%s: Texture reported/actual size observed=%s/%s expected=%s" % [role,
				record.get("texture_reported_size", []), record.get("texture_size", []), expected_texture])
		if require_exact_pixel_sizes and (record.get("image_size") != expected_size or record.get("native_size") != expected_size):
			errors.append("%s: original Image native_size/image_size observed=%s/%s requested=%s" % [role,
				record.get("native_size", []), record.get("image_size", []), expected_size])
		if role == "main":
			if record.get("viewport_kind") != "Window" or record.get("window_size") != expected_size:
				errors.append("main: viewport kind/window size mapping invalid")
		else:
			if record.get("viewport_kind") != "SubViewport" or record.get("window_size") != []:
				errors.append("%s: expected SubViewport, observed kind/window_size=%s/%s" % [role,
					record.get("viewport_kind", ""), record.get("window_size", [])])
			if logical_size.x <= 0 or logical_size.y <= 0 or record.get("size_2d_override") != _size_array(logical_size) \
					or record.get("size_2d_override_stretch") != true:
				errors.append("%s: logical 2D override/stretch does not map to main visible_rect" % role)
		var visible: Array = record.get("visible_rect", [])
		if not _finite_numeric_array(visible, 4) or not _numeric_arrays_equal(visible, main_visible, 0.001):
			errors.append("%s: visible_rect differs from main, observed=%s main=%s" % [role, visible, main_visible])
		for transform_name: String in ["canvas_transform", "final_transform"]:
			var transform_value: Array = record.get(transform_name, [])
			if not _finite_numeric_array(transform_value, 6):
				errors.append("%s: %s missing/nonfinite, observed=%s" % [role, transform_name, transform_value])
			elif role != "main":
				var reference: Array = main_canvas if transform_name == "canvas_transform" else main_final
				if not _numeric_arrays_equal(transform_value, reference, 0.001):
					errors.append("%s: %s mapping differs from main, observed=%s main=%s" % [role,
						transform_name, transform_value, reference])
		for transform_name: String in ["stretch_transform", "stretch_scale"]:
			var transform_array: Array = record.get(transform_name, [])
			var length := 6 if transform_name == "stretch_transform" else 2
			if not _finite_numeric_array(transform_array, length):
				errors.append("%s: %s missing/nonfinite" % [role, transform_name])
	return errors


func _finite_numeric_array(values: Array, expected_length: int) -> bool:
	if values.size() != expected_length:
		return false
	for value: Variant in values:
		if (not value is float and not value is int) or not is_finite(float(value)):
			return false
	return true


func _diagnostic_viewport_records(images: Dictionary) -> Dictionary:
	var roles: Array[String] = ["main", "reconstruction"]
	roles.append_array(_passes.keys())
	for role: String in roles:
		if not images.has(role) or not images[role] is Image:
			return _structural_viewport_records()
	return _viewport_records(images)


func _persist_viewport_failure(message: String, images: Dictionary, records: Dictionary,
		requested_size: Vector2i) -> String:
	var outputs: Array[Dictionary] = []
	var can_write := not _headless_check and not _active_case_directory.is_empty() \
			and DirAccess.dir_exists_absolute(_active_case_directory)
	if can_write:
		var roles: Array[String] = ["main", "reconstruction"]
		roles.append_array(_passes.keys())
		for role: String in roles:
			if not images.has(role) or not images[role] is Image:
				continue
			var image := images[role] as Image
			if image.is_empty():
				continue
			var path := _active_case_directory.path_join("viewport-failure-original-%s.png" % role)
			var save_error := image.save_png(path)
			outputs.append({
				"role": role,
				"path": path.get_file(),
				"saved": save_error == OK,
				"native_size": _size_array(image.get_size()),
				"sha256": FileAccess.get_sha256(path) if save_error == OK else "",
			})
	var evidence := {
		"schema_version": "terrain-mask-capture-failure/2",
		"case_name": _active_case_name,
		"requested_resolution": _size_array(requested_size),
		"window_size_observed": _size_array(root.size),
		"failure": message,
		"readback_callback": "RenderingServer.frame_post_draw; all available raw Images saved before failing",
		"frame_id_observed": Engine.get_frames_drawn(),
		"capture_state": _capture_state_v2.duplicate(true),
		"viewport_records": records.duplicate(true),
		"original_images": outputs,
		"png_transform": "none; original Image.save_png bytes only",
	}
	var evidence_path := "NOT_SAVED"
	if can_write:
		evidence_path = _active_case_directory.path_join("viewport-failure-evidence.json")
		var file := FileAccess.open(evidence_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(evidence, "\t") + "\n")
			file.close()
		else:
			evidence_path = "FAILED_TO_OPEN:" + evidence_path
	print("TERRAIN_MASK_VIEWPORT_FAILURE_EVIDENCE " + JSON.stringify(evidence))
	return evidence_path


func _freeze_tree_count(node: Node) -> int:
	var total := 1
	for child: Node in node.get_children():
		total += _freeze_tree_count(child)
	return total


func _count_nodes(node: Node) -> int:
	return _freeze_tree_count(node)


func _sync_reconstruction_animation_time() -> void:
	# The sessions and all animation nodes are frozen before this call in pixel
	# capture. Headless structural checks retain the base synchronization behavior.
	if DisplayServer.get_name() == "headless":
		super._sync_reconstruction_animation_time()


func _build_manifest_skeleton(map_data: Dictionary, resolution: Vector2i, case_name: String) -> Dictionary:
	var manifest: Dictionary = super._build_manifest_skeleton(map_data, resolution, case_name)
	manifest["schema_version"] = CAPTURE_SCHEMA_V2
	manifest["sources"] = _path_hashes(SOURCE_PATHS)
	manifest["capture_state"] = _capture_state_v2.duplicate(true)
	return manifest


func _path_hashes(paths: PackedStringArray) -> Dictionary:
	var extended := paths.duplicate()
	for path: String in V2_SOURCE_PATHS:
		if path not in extended:
			extended.append(path)
	return super._path_hashes(extended)


func _candidate_record() -> Dictionary:
	var candidate: Dictionary = super._candidate_record()
	var source_hashes: Dictionary = candidate.get("source_sha256", {}).duplicate()
	for path: String in V2_SOURCE_PATHS:
		var relative := path.trim_prefix("res://")
		var absolute := ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(absolute):
			_abort("v2 candidate source is missing: " + relative)
			continue
		source_hashes[relative] = FileAccess.get_sha256(absolute)
	candidate["source_sha256"] = source_hashes
	candidate["candidate_digest_sha256"] = _sha256_text(JSON.stringify(source_hashes))
	return candidate


func _viewport_structure_record(viewport: Viewport) -> Dictionary:
	var record: Dictionary = super._viewport_structure_record(viewport)
	var stretch_transform: Transform2D = viewport.get_stretch_transform()
	var reported_size: Vector2i = viewport.get_texture().get_size() if viewport.get_texture() != null else Vector2i.ZERO
	record["viewport_kind"] = "Window" if viewport is Window else "SubViewport"
	record["window_size"] = _size_array(viewport.size) if viewport is Window else []
	record["stretch_transform"] = _transform_array(stretch_transform)
	record["stretch_scale"] = _point_array(stretch_transform.get_scale())
	record["texture_reported_size"] = _size_array(reported_size)
	return record


func _viewport_record(viewport: Viewport, image: Image) -> Dictionary:
	var record: Dictionary = super._viewport_record(viewport, image)
	record["native_size"] = _size_array(image.get_size())
	return record


func _point_array(point: Vector2) -> Array[float]:
	return [point.x, point.y]
