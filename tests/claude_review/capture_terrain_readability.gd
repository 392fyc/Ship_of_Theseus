extends SceneTree
## Same-frame terrain readability capture for the formal TerrainBattleSession.
## Pixel capture requires --out=<absolute external directory>; --headless-check
## validates structure without writing images or claiming pixel evidence.

const EXAMPLES_PATH := "res://assets/prototype/battlefield_courtyard/terrain_examples.json"
const PROFILE_PATH := "res://assets/prototype/battlefield_courtyard/visual_profile.json"
const SESSION_SCRIPT_PATH := "res://scripts/tactical/terrain_battle_session.gd"
const CAPTURE_METADATA := preload("res://tests/claude_review/capture_metadata.gd")
const BOARD_SCRIPT_PATH := "res://scripts/ui/playground/courtyard_board_view.gd"
const REGION_ANNOTATION_PATH := "res://tests/claude_review/terrain_readability_crown_regions.json"
const DRAW_LAYER_SCRIPT := preload("res://tests/claude_review/terrain_mask_draw_layer.gd")
const CAPTURE_SCHEMA := "terrain-mask-capture/1"
const FIXTURE_NAME := "calibration_courtyard"
const CAPTURE_VARIANT_OVERRIDE := {"cell": [8, 7], "from": "pillar", "to": "ruined"}
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const REQUIRED_TYPES: PackedStringArray = ["tree", "wall", "pillar", "rubble"]
const SOURCE_PATHS: PackedStringArray = [
	"res://scenes/tactical/TacticalScene.tscn",
	"res://scripts/tactical/tactical_scene.gd",
	"res://scripts/tactical/terrain_battle_session.gd",
	"res://scripts/ui/playground/battlefield_courtyard.gd",
	"res://scripts/ui/playground/courtyard_board_view.gd",
	"res://scripts/ui/terrain/terrain_battle_definition.gd",
	"res://scripts/ui/terrain/terrain_surface.gd",
	"res://scripts/ui/terrain/terrain_blend.gdshader",
	"res://scripts/ui/terrain/terrain_catalog.gd",
	"res://assets/prototype/battlefield_courtyard/terrain_examples.json",
	"res://assets/prototype/battlefield_courtyard/visual_profile.json",
	"res://data/battlefields/terrain_workshop_test.json",
	"res://project.godot",
	"res://tests/claude_review/capture_terrain_readability.gd",
	"res://tests/claude_review/terrain_mask_draw_layer.gd",
	"res://tests/claude_review/terrain_readability_crown_regions.json",
	"res://tests/claude_review/capture_metadata.gd",
]
const MATERIAL_PATHS: PackedStringArray = [
	"res://assets/prototype/battlefield_courtyard/stone-ground-v1.png",
	"res://assets/prototype/battlefield_courtyard/meadow-ground-v2.png",
	"res://assets/prototype/battlefield_courtyard/moss-ground-v1.png",
	"res://assets/prototype/battlefield_courtyard/water-surface-v5.png",
	"res://assets/prototype/battlefield_courtyard/masonry-wall-v2.png",
	"res://assets/prototype/battlefield_courtyard/forest-tree-v2.png",
	"res://assets/prototype/battlefield_courtyard/low-rubble-v1.png",
	"res://assets/prototype/battlefield_courtyard/shrub-v1.png",
	"res://assets/prototype/battlefield_courtyard/courtyard-entry-v2.png",
	"res://assets/prototype/battlefield_courtyard/natural-rock-v1.png",
]
const PART_COLORS := {
	"wall_top": Color(1.0, 0.0, 0.0, 1.0),
	"wall_side": Color(0.0, 0.0, 1.0, 1.0),
	"pillar_top": Color(1.0, 0.0, 1.0, 1.0),
	"pillar_side": Color(0.0, 1.0, 1.0, 1.0),
	"pillar_base": Color(1.0, 1.0, 0.0, 1.0),
	"wall_outline": Color(0.0, 1.0, 0.0, 1.0),
	"tree_crown": Color(0.0, 1.0, 0.5, 1.0),
	"tree_dark_side": Color(0.5, 1.0, 0.0, 1.0),
	"tree_outline": Color(1.0, 0.5, 0.0, 1.0),
}
const FLAT_MASK_SHADER_CODE := """
shader_type canvas_item;
render_mode blend_mix;
uniform vec4 flat_rgb = vec4(1.0, 1.0, 1.0, 1.0);
void fragment() {
	COLOR = vec4(flat_rgb.rgb, COLOR.a);
}
"""
const TERRAIN_COLORS := {
	0: Color(0.0, 1.0, 0.0, 1.0), # plain / grass
	1: Color(0.0, 0.5, 0.0, 1.0), # forest
	2: Color(0.6, 0.4, 0.0, 1.0), # mountain
	3: Color(1.0, 0.0, 0.0, 1.0), # peak
	4: Color(0.5, 0.5, 0.5, 1.0), # wall
	5: Color(0.0, 1.0, 1.0, 1.0), # shallow water
	6: Color(0.0, 0.0, 0.5, 1.0), # deep water
	7: Color(0.72, 0.25, 0.0, 1.0), # lava
	8: Color(0.5, 0.0, 1.0, 1.0), # swamp
}

var _headless_check := false
var _output_directory := ""
var _map_sizes: Array[int] = [10, 25]
var _resolutions: Array[Vector2i] = RESOLUTIONS.duplicate()
var _failed := false
var _source_fixture_sha256 := ""
var _main_session: Node2D
var _reconstruction_session: Node2D
var _reconstruction_viewport: SubViewport
var _main_battle: Node2D
var _main_manager: Node
var _main_board: Node2D
var _passes: Dictionary = {}
var _instances: Array[Dictionary] = []
var _instance_color_by_id: Dictionary = {}
var _last_copied_nodes_by_id: Dictionary = {}
var _region_annotation: Dictionary = {}
var _region_annotation_status := "NOT_TESTED"
var _region_annotation_reason := "No texture-bound region annotation was provided."
var _crown_textures: Dictionary = {}
var _exclusion_runtime_record: Dictionary = {}
var _flat_mask_shader: Shader


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--headless-check":
			_headless_check = true
		elif argument.begins_with("--out="):
			_output_directory = argument.trim_prefix("--out=").simplify_path()
		elif argument.begins_with("--map-sizes="):
			_map_sizes = _parse_integer_list(argument.trim_prefix("--map-sizes="))
		elif argument.begins_with("--resolutions="):
			_resolutions = _parse_resolutions(argument.trim_prefix("--resolutions="))
	call_deferred("_run")


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
		"schema_version": CAPTURE_SCHEMA,
		"cases": _map_sizes.size() * _resolutions.size(),
		"output_directory": _output_directory,
		"pixel_capture": true,
		"all_images_hashed": true,
	}))
	quit(0)


func _run_headless_check() -> void:
	var examples_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXAMPLES_PATH))
	var profile_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if not examples_value is Dictionary or not profile_value is Dictionary:
		_abort("headless check could not read fixture inputs")
		return
	_source_fixture_sha256 = _sha256_text(JSON.stringify(examples_value["courtyard"]))
	_load_region_annotation(profile_value)
	var case_results: Array[Dictionary] = []
	for map_size: int in _map_sizes:
		var map_data := _make_map(examples_value["courtyard"], map_size)
		for resolution: Vector2i in _resolutions:
			root.size = resolution
			await _frames(4)
			if (root as Viewport).size != resolution:
				_abort("headless Window did not accept requested structure-check size %s" % resolution)
				return
			var validation: Dictionary = _configure_session(map_data)
			if not bool(validation.get("ok", false)):
				_abort("headless check could not configure a formal TerrainBattleSession for %d×%d" % [map_size, map_size])
				return
			_main_session = validation["session"] as Node2D
			await _wait_for_session(_main_session, root)
			if _failed:
				return
			_bind_scene(_main_session)
			if _failed:
				return
			await _frames(3)
			if not _verify_initial_fit(resolution):
				return
			_instances = _collect_instances()
			var counts := _count_types(_instances)
			if not _validate_instance_counts(counts):
				return
			if not _validate_structural_parts(_instances):
				return
			_instance_color_by_id.clear()
			for index: int in _instances.size():
				_instance_color_by_id[str(_instances[index]["stable_id"])] = _id_color(index + 1)
			if not await _create_reconstruction(map_data, resolution):
				return
			if not await _create_capture_passes(resolution, profile_value):
				return
			await _frames(3)
			_sync_reconstruction_animation_time()
			var clone_structure := _mask_clone_validation_summary()
			if _failed:
				return
			var viewport_records := _structural_viewport_records()
			if not _validate_viewport_structure(viewport_records, resolution, false):
				return
			var metadata_shape := _build_manifest_skeleton(map_data, resolution, "headless-structure-only")
			for key: String in ["capture_config", "candidate", "sources", "materials", "common_frame", "viewports", "images", "instances", "reconstruction", "limitations"]:
				if not metadata_shape.has(key):
					_abort("headless metadata schema is missing " + key)
					return
			case_results.append({
				"map_size": map_size,
				"resolution": _size_array(resolution),
				"actual_prop_counts": counts,
				"derived_map_sha256": _sha256_text(JSON.stringify(map_data)),
				"fixture": _fixture_record(map_size, map_data),
				"region_annotation_status": _region_annotation_status,
				"mask_clone_structure": clone_structure,
				"viewport_structure": viewport_records,
				"viewport_mapping_validation": "PASS_STRUCTURE_ONLY",
				"pixel_status": "NOT_TESTED_HEADLESS_RENDERING_DISABLED",
			})
			_close_sessions_and_passes()
			await _frames(3)
	print("TERRAIN_MASK_HEADLESS_CHECK " + JSON.stringify({
		"pass": true,
		"renderer": RenderingServer.get_current_rendering_method(),
		"formal_scene": "TerrainBattleSession -> TacticalScene",
		"map_sizes": _map_sizes,
		"resolutions": _resolutions,
		"cases": case_results,
		"pixel_metrics": "not available in headless mode",
	}))
	quit(0)


func _capture_case(map_size: int, resolution: Vector2i, source_map: Dictionary, profile: Dictionary) -> bool:
	var case_name := "%dx%d_%dx%d" % [map_size, map_size, resolution.x, resolution.y]
	var case_directory := _output_directory.path_join(case_name)
	if DirAccess.dir_exists_absolute(case_directory) or DirAccess.make_dir_recursive_absolute(case_directory) != OK:
		_abort("case output directory must be new and creatable: " + case_directory)
		return false
	root.size = resolution
	await _frames(8)
	var map_data := _make_map(source_map, map_size)
	var configured: Dictionary = _configure_session(map_data)
	if not bool(configured.get("ok", false)):
		_abort("formal TerrainBattleSession rejected fixture %s" % case_name)
		return false
	_main_session = configured["session"] as Node2D
	await _wait_for_session(_main_session, root)
	if _failed:
		return false
	_bind_scene(_main_session)
	if _failed:
		return false
	# Let the official _resize/fit path establish the initial camera and allow the
	# board's first stable draw before creating the synchronized capture viewports.
	await _frames(8)
	if not _verify_initial_fit(resolution):
		return false
	_instances = _collect_instances()
	if not _validate_instance_counts(_count_types(_instances)):
		return false
	if not _validate_structural_parts(_instances):
		return false
	_instance_color_by_id.clear()
	for index: int in _instances.size():
		var stable_id: String = str(_instances[index]["stable_id"])
		_instance_color_by_id[stable_id] = _id_color(index + 1)
	if not await _create_reconstruction(map_data, resolution):
		return false
	if not await _create_capture_passes(resolution, profile):
		return false
	await _frames(3)
	await _frames(2)
	var clone_structure := _mask_clone_validation_summary()
	if _failed:
		return false
	# Synchronize copy transforms after the final process frame, immediately
	# before the one post-draw callback used to read every viewport.
	_sync_reconstruction_animation_time()
	await RenderingServer.frame_post_draw
	var frames_drawn_before := Engine.get_frames_drawn()
	var process_frames_before := Engine.get_process_frames()
	var frame_id := frames_drawn_before
	var frame_images: Dictionary = {}
	frame_images["main"] = root.get_texture().get_image()
	frame_images["reconstruction"] = _reconstruction_viewport.get_texture().get_image()
	for role: String in _passes:
		var viewport := _passes[role] as SubViewport
		frame_images[role] = viewport.get_texture().get_image()
	var frames_drawn_after := Engine.get_frames_drawn()
	var process_frames_after := Engine.get_process_frames()
	if not _validate_frame_images(frame_images, resolution):
		return false
	var viewport_records := _viewport_records(frame_images)
	if not _validate_viewport_structure(viewport_records, resolution, true):
		return false
	var reconstruction_metrics := _compare_images(frame_images["main"] as Image, frame_images["reconstruction"] as Image)
	var image_records := _save_frame_images(frame_images, case_directory, frame_id)
	if _failed:
		return false
	var manifest := _build_manifest_skeleton(map_data, resolution, case_name)
	manifest["case"] = {
		"name": case_name,
		"map_size": [map_size, map_size],
		"requested_resolution": [resolution.x, resolution.y],
		"window_size": [root.size.x, root.size.y],
		"scene": "TerrainBattleSession -> scenes/tactical/TacticalScene.tscn",
		"initial_fit": _camera_record(),
		"map_sha256": _sha256_text(JSON.stringify(map_data)),
		"fixture": _fixture_record(map_size, map_data),
	}
	manifest["common_frame"] = {
		"callback": "RenderingServer.frame_post_draw",
		"frame_id": frame_id,
		"frames_drawn_before": frames_drawn_before,
		"frames_drawn_after": frames_drawn_after,
		"process_frames_before": process_frames_before,
		"process_frames_after": process_frames_after,
		"same_callback": true,
		"readback_order": ["main", "reconstruction"] + _passes.keys(),
		"readback_awaits_between_images": false,
	}
	manifest["viewports"] = viewport_records
	manifest["viewport_mapping_validation"] = {
		"status": "PASS_STRUCTURE_ONLY",
		"checked_roles": viewport_records.keys(),
		"checks": ["physical size", "readback and texture size", "canvas transform", "final transform", "visible_rect", "logical 2D override and stretch"],
		"pixel_alignment": "NOT_TESTED_BY_TRANSFORM_COMPARISON",
	}
	manifest["images"] = image_records
	manifest["captures"] = [_c8_capture_record(frame_images["main"] as Image, case_name, case_directory)]
	manifest["renderer"] = str(RenderingServer.get_current_rendering_method())
	manifest["project_stretch_mode"] = str(ProjectSettings.get_setting("display/window/stretch/mode"))
	manifest["runtime_evidence"] = true
	manifest["instances"] = _instance_records()
	manifest["mask_clone_structure"] = clone_structure
	manifest["reconstruction"] = reconstruction_metrics
	manifest["terrain_metrics"] = {
		"T3": {
			"contrast_status": "READY_FOR_INDEPENDENT_MEASUREMENT" if _region_scope_approved("crown_geometry") else "NOT_TESTED",
			"completeness_status": "NOT_TESTED",
			"contrast_inputs": ["tree_crown_union", "ground_types", "exclusions"],
			"full_T3_requires": ["crown_contrast", "dark_side_classification", "outline_classification_or_authoritatively_absent"],
			"thresholds_from_task_contract": {"delta_l_only": 12.0, "or_delta_l": 8.0, "and_delta_e00": 15.0},
		},
	}
	manifest["masks"] = _mask_legend()
	manifest["limitations"] = _capture_limitations()
	manifest["exclusions"] = _exclusion_record()
	var manifest_path := case_directory.path_join("capture-manifest.json")
	if not _write_json(manifest_path, manifest):
		return false
	print("TERRAIN_MASK_CASE " + JSON.stringify({
		"case": case_name,
		"frame_id": frame_id,
		"images": image_records.size(),
		"reconstruction": reconstruction_metrics,
		"instance_counts": _count_types(_instances),
		"manifest": manifest_path,
	}))
	_close_sessions_and_passes()
	await _frames(3)
	return true


func _configure_session(map_data: Dictionary) -> Dictionary:
	var script := load(SESSION_SCRIPT_PATH) as Script
	if script == null:
		return {"ok": false, "reason": "TerrainBattleSession script failed to load"}
	var session := script.new() as Node2D
	var result: Dictionary = session.call("configure_map", map_data.duplicate(true))
	if not bool(result.get("ok", false)):
		session.free()
		return {"ok": false, "reason": str(result.get("message", "configure_map failed"))}
	return {"ok": true, "session": session}


func _wait_for_session(session: Node2D, host: Viewport) -> void:
	if session.get_parent() == null:
		host.add_child(session)
	for _attempt: int in 180:
		await process_frame
		if is_instance_valid(session.get("battle")) and is_instance_valid(session.get("board_view")):
			var manager_value: Variant = session.get("manager")
			var board_value: Variant = session.get("board_view")
			if manager_value != null and board_value != null:
				return
	_abort("TerrainBattleSession did not finish building its formal TacticalScene")


func _bind_scene(session: Node2D) -> void:
	_main_battle = session.get("battle") as Node2D
	_main_manager = session.get("manager") as Node
	_main_board = session.get("board_view") as Node2D
	if _main_battle == null or _main_manager == null or _main_board == null:
		_abort("formal session is missing battle, manager, or CourtyardBoardView")
		return
	if _main_manager.get("grid") == null:
		_abort("formal TacticalManager has no Grid")
		return
	if _main_board.get("_props") is not Array:
		_abort("formal CourtyardBoardView has no runtime _props inventory")


func _make_map(source_map: Dictionary, size: int) -> Dictionary:
	if size < 10 or size > 25:
		var invalid := source_map.duplicate(true)
		invalid["width"] = size
		invalid["height"] = size
		return invalid
	var result := source_map.duplicate(true)
	var source_variants: Dictionary = result.get("terrain_variants", {}).duplicate(true)
	var override_cell: Array = CAPTURE_VARIANT_OVERRIDE["cell"]
	var override_key := "%d,%d" % [int(override_cell[0]), int(override_cell[1])]
	if str(source_variants.get(override_key, "")) != str(CAPTURE_VARIANT_OVERRIDE["from"]):
		_abort("capture fixture source variant changed at %s; refusing an unreviewed fixture derivation" % override_key)
		return {}
	source_variants[override_key] = str(CAPTURE_VARIANT_OVERRIDE["to"])
	result["terrain_variants"] = source_variants
	if size == 10:
		result["id"] = "calibration_courtyard_10"
		result["name"] = "校准庭院 10×10"
		return result
	var terrain_source: Array = result["terrain"]
	var terrain_rows: Array = []
	for y: int in size:
		var row: Array = []
		for x: int in size:
			row.append((terrain_source[y % 10] as Array)[x % 10])
		terrain_rows.append(row)
	result["width"] = size
	result["height"] = size
	result["terrain"] = terrain_rows
	result["id"] = "calibration_courtyard_%d" % size
	result["name"] = "校准庭院 %d×%d" % [size, size]
	var variants: Dictionary = {}
	source_variants = result.get("terrain_variants", {})
	for y: int in size:
		for x: int in size:
			var key := "%d,%d" % [x % 10, y % 10]
			if source_variants.has(key):
				variants["%d,%d" % [x, y]] = source_variants[key]
	result["terrain_variants"] = variants
	var paving: Array = []
	for repeat_y: int in range(0, size, 10):
		for repeat_x: int in range(0, size, 10):
			for cell: Array in source_map.get("paving", []):
				var x := repeat_x + int(cell[0])
				var y := repeat_y + int(cell[1])
				if x < size and y < size:
					paving.append([x, y])
	result["paving"] = paving
	return result


func _fixture_record(map_size: int, map_data: Dictionary) -> Dictionary:
	var override_cell: Array = CAPTURE_VARIANT_OVERRIDE["cell"]
	var repeated_cells: Array[Array] = []
	for y: int in range(int(override_cell[1]), map_size, 10):
		for x: int in range(int(override_cell[0]), map_size, 10):
			repeated_cells.append([x, y])
	return {
		"name": FIXTURE_NAME,
		"source_example": "assets/prototype/battlefield_courtyard/terrain_examples.json#courtyard",
		"source_map_sha256": _source_fixture_sha256,
		"derived_map_sha256": _sha256_text(JSON.stringify(map_data)),
		"map_variant_overrides": [{
			"cell_in_source_10x10": override_cell,
			"repeated_case_cells": repeated_cells,
			"from": CAPTURE_VARIANT_OVERRIDE["from"],
			"to": CAPTURE_VARIANT_OVERRIDE["to"],
			"purpose": "Meet the minimum count for production-generated rubble while retaining at least three pillars.",
		}],
		"expansion_rule": "Repeat the source 10x10 terrain and paving cells at x%10,y%10; repeat source variants modulo 10 after applying the declared calibration override.",
	}


func _collect_instances() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var prop_specs: Array = _main_board.get("_props")
	for spec_value: Variant in prop_specs:
		if not spec_value is Dictionary:
			continue
		var spec: Dictionary = spec_value
		var node := spec.get("node") as Node2D
		if not is_instance_valid(node) or not node.is_visible_in_tree():
			continue
		var kind := _classify_prop(node)
		if kind not in REQUIRED_TYPES:
			continue
		var coord := _logical_position(node.global_position)
		var stable_id := _stable_id(kind, coord)
		result.append({
			"stable_id": stable_id,
			"type": kind,
			"cell": [floori(coord.x), floori(coord.y)],
			"logical_position": [coord.x, coord.y],
			"source_node": str(node.get_path()),
			"source_node_name": node.name,
			"source_transform": _transform_array(node.global_transform),
			"source_modulate": _color_array(node.modulate),
			"texture_signature": _node_texture_signature(node),
			"parts": _parts_for_instance(node, kind),
			"classification_source": _classification_source(node, kind),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["stable_id"]) < str(b["stable_id"]))
	return result


func _stable_id(kind: String, coord: Vector2) -> String:
	return "%s@%s,%s" % [kind, _format_number(coord.x), _format_number(coord.y)]


func _classify_prop(node: Node2D) -> String:
	if node.name == "WeatheredStonePillar":
		return "pillar"
	if node.name == "CourtyardWall" or bool(node.get_meta("terrain_wall", false)):
		return "wall"
	var sprite := _first_sprite(node)
	if sprite != null:
		var atlas := sprite.texture as AtlasTexture
		if atlas != null and atlas.atlas != null:
			var path := atlas.atlas.resource_path.get_file().to_lower()
			if path.contains("forest-tree"):
				return "tree"
			if path.contains("low-rubble"):
				return "rubble"
			if path.contains("shrub"):
				return "shrub"
	# Godot may replace duplicate sibling names with generated names. Structural
	# wall/pillar classification therefore also binds the rendered polygons back
	# to their real Grid cell and declared terrain variant.
	for child: Node in node.get_children():
		if child is Polygon2D:
			var coord := _logical_position(node.global_position)
			var cell := Vector2i(roundi(coord.x), roundi(coord.y))
			var grid: Variant = _main_manager.get("grid") if is_instance_valid(_main_manager) else null
			if grid != null and grid.is_valid(cell) and grid.get_cell(cell).terrain == Cell.Terrain.WALL:
				return "pillar" if str(_main_board.call("visual_variant_at", cell)) == "pillar" else "wall"
			break
	return ""


func _parts_for_instance(node: Node2D, kind: String) -> Dictionary:
	if kind in ["wall", "pillar"]:
		var found: Array[Dictionary] = []
		for child_value: Variant in node.get_children():
			var child := child_value as CanvasItem
			if child is Polygon2D:
				var polygon := child as Polygon2D
				var child_kind := _classify_wall_child(node, polygon, kind)
				if not child_kind.is_empty():
					found.append({
						"role": child_kind,
						"status": "captured",
						"mask_role": "part_ids",
						"color": _hex_color(PART_COLORS[child_kind]),
						"classification_source": "actual Polygon2D texture assignment and stable source cell variant; pillar base/top from _add_pillar child order",
					})
			elif child is Line2D:
				found.append({
					"role": "outline",
					"status": "captured",
					"mask_role": "part_ids",
					"color": _hex_color(PART_COLORS["wall_outline"]),
					"classification_source": "actual Line2D child node",
				})
		var has_outline := false
		for part: Dictionary in found:
			if part.get("role") == "outline":
				has_outline = true
				break
		if not has_outline:
			found.append({
				"role": "outline",
				"status": "absent_authoritatively",
				"mask_role": "part_ids",
				"classification_source": "complete runtime prop child inventory contains no Line2D; applies only to an independent outline node, not baked raster pixels",
			})
		return {"parts": found}
	if kind == "tree":
		return {
		"tree_sprite": {"status": "captured_as_instance_only", "mask_role": "instance_ids"},
			"crown": _region_status_record("crown", "crown_geometry"),
			"dark_side": _region_status_record("dark_side", "dark_side_geometry"),
			"outline": _tree_outline_status(node),
			"contrast_measurement": {"status": "NOT_RUN_BY_CAPTURE", "mask_role": "tree_crown_union", "ground_role": "ground_types"},
			"complete_T3": {"status": "NOT_TESTED", "reason": "Dark-side and outline regions are not independently classified."},
		}
	return {"whole_instance": {"status": "captured", "mask_role": "instance_ids"}}


func _classify_wall_child(parent: Node2D, polygon: Polygon2D, kind: String) -> String:
	if kind == "wall":
		if polygon.texture != null and polygon.texture.resource_path.get_file().to_lower().contains("masonry-wall"):
			return "wall_side"
		return "wall_top"
	if kind == "pillar":
		if polygon.texture != null and polygon.texture.resource_path.get_file().to_lower().contains("masonry-wall"):
			return "pillar_side"
		# _add_pillar emits foot first, three sides, then the lit top face.
		var polygons: Array[Node] = []
		for candidate: Node in parent.get_children():
			if candidate is Polygon2D:
				polygons.append(candidate)
		var polygon_index := polygons.find(polygon)
		if polygon_index == 0:
			return "pillar_base"
		if polygon_index == polygons.size() - 1:
			return "pillar_top"
		return "pillar_side"
	return ""


func _tree_outline_status(node: Node2D) -> Dictionary:
	# The current tree is a single Sprite2D. A raster edge cannot establish a
	# separately authored outline, so only a validated annotation can classify it.
	if not _region_scope_approved("outline_geometry"):
		return {"status": "NOT_TESTED", "reason": _region_annotation_reason}
	if _region_regions().get("outline", []).is_empty():
		return {"status": "NOT_TESTED", "reason": "The source tree sprite does not expose an independently classified raster outline."}
	return {"status": "captured", "mask_role": "part_ids", "color": _hex_color(PART_COLORS["tree_outline"]), "classification_source": REGION_ANNOTATION_PATH}


func _region_status_record(name: String, scope: String) -> Dictionary:
	if not _region_scope_approved(scope):
		return {"status": "NOT_TESTED", "reason": _region_annotation_reason}
	if _region_regions().get(name, []).is_empty():
		return {"status": "NOT_TESTED", "reason": "The texture-bound annotation has no %s polygon." % name}
	return {"status": "captured", "mask_role": "part_ids", "color": _hex_color(PART_COLORS["tree_" + name]), "classification_source": REGION_ANNOTATION_PATH}


func _region_scope_approved(scope: String) -> bool:
	if str(_region_annotation.get("review_status", "pending")).to_lower() != "approved":
		return false
	var scopes: Variant = _region_annotation.get("approved_scope", [])
	return scopes is Array and scope in (scopes as Array)


func _classification_source(node: Node2D, kind: String) -> String:
	if kind in ["wall", "pillar"]:
		return "runtime node class/name and child Polygon2D texture assignment; pillar top/base by _add_pillar child order"
	if kind == "tree":
		return "Sprite2D atlas resource path; crown/dark-side/outline require the texture-hash-bound region annotation"
	if kind == "rubble":
		return "Sprite2D AtlasTexture atlas resource path"
	return "Sprite2D AtlasTexture atlas resource path"


func _create_reconstruction(map_data: Dictionary, resolution: Vector2i) -> bool:
	_reconstruction_viewport = _new_viewport("reconstruction", resolution, false)
	root.add_child(_reconstruction_viewport)
	var configured: Dictionary = _configure_session(map_data)
	if not bool(configured.get("ok", false)):
		_abort("could not create the independent formal-session reconstruction")
		return false
	_reconstruction_session = configured["session"] as Node2D
	await _wait_for_session(_reconstruction_session, _reconstruction_viewport)
	if _failed:
		return false
	var reconstruction_battle := _reconstruction_session.get("battle") as Node2D
	var reconstruction_manager := _reconstruction_session.get("manager") as Node
	var reconstruction_board := _reconstruction_session.get("board_view") as Node2D
	if reconstruction_battle == null or reconstruction_manager == null or reconstruction_board == null:
		_abort("reconstruction did not build the formal board and battle scene")
		return false
	return _replace_reconstruction_props(reconstruction_board)


func _replace_reconstruction_props(reconstruction_board: Node2D) -> bool:
	var source_layer := _main_board.get("_actor_layer") as Node2D
	var destination_layer := reconstruction_board.get("_actor_layer") as Node2D
	if source_layer == null or destination_layer == null:
		_abort("formal board prop actor layer is unavailable for reconstruction")
		return false
	var retained_specs: Array[Dictionary] = []
	for spec_value: Variant in reconstruction_board.get("_props") as Array:
		if not spec_value is Dictionary:
			continue
		var spec: Dictionary = spec_value
		var node := spec.get("node") as Node2D
		if is_instance_valid(node) and _classify_prop(node) in REQUIRED_TYPES:
			var parent := node.get_parent()
			if parent != null:
				parent.remove_child(node)
			node.free()
		else:
			retained_specs.append(spec)
	reconstruction_board.set("_props", retained_specs)
	if not _copy_props(source_layer, destination_layer, "props"):
		return false
	var source_specs: Array = _main_board.get("_props")
	for source_spec_value: Variant in source_specs:
		if not source_spec_value is Dictionary:
			continue
		var source_spec: Dictionary = source_spec_value
		var source_node := source_spec.get("node") as Node2D
		if not is_instance_valid(source_node):
			continue
		var kind := _classify_prop(source_node)
		if kind not in REQUIRED_TYPES:
			continue
		var stable_id := _stable_id(kind, _logical_position(source_node.global_position))
		var copied_node := _last_copied_nodes_by_id.get(stable_id) as Node2D
		if copied_node == null:
			_abort("full reconstruction is missing the copied prop %s" % stable_id)
			return false
		var copied_spec := source_spec.duplicate(true)
		copied_spec["node"] = copied_node
		retained_specs.append(copied_spec)
	reconstruction_board.set("_props", retained_specs)
	return true


func _sync_reconstruction_animation_time() -> void:
	if not is_instance_valid(_reconstruction_session):
		return
	var other_board := _reconstruction_session.get("board_view") as Node2D
	if other_board == null:
		return
	var shared_time := float(_main_board.get("_time"))
	other_board.set("_time", shared_time)
	var main_specs: Array = _main_board.get("_props")
	var other_specs: Array = other_board.get("_props")
	var other_by_id: Dictionary = {}
	for other_spec_value: Variant in other_specs:
		if other_spec_value is Dictionary:
			var other_node := (other_spec_value as Dictionary).get("node") as Node2D
			if other_node != null:
				if other_node.has_meta("terrain_capture_stable_id"):
					other_by_id[str(other_node.get_meta("terrain_capture_stable_id"))] = other_node
	for main_spec_value: Variant in main_specs:
		if not main_spec_value is Dictionary:
			continue
		var main_node := (main_spec_value as Dictionary).get("node") as Node2D
		if main_node == null:
			continue
		var kind := _classify_prop(main_node)
		if kind not in REQUIRED_TYPES:
			continue
		var stable_id := _stable_id(kind, _logical_position(main_node.global_position))
		var other_node := other_by_id.get(stable_id) as Node2D
		if other_node != null:
			other_node.transform = main_node.transform
			other_node.modulate = main_node.modulate
			other_node.self_modulate = main_node.self_modulate
			other_node.visible = main_node.visible


func _create_capture_passes(resolution: Vector2i, profile: Dictionary) -> bool:
	var main_viewport := root as Viewport
	var copied_roles: Array[String] = ["props", "instance_ids", "part_ids", "tree_crown_union", "ground", "ground_without_shadow", "grid", "contact_shadow", "ground_types", "exclusions"]
	for role: String in copied_roles:
		var viewport := _new_viewport(role, resolution, true)
		viewport.canvas_item_default_texture_filter = main_viewport.canvas_item_default_texture_filter
		viewport.canvas_item_default_texture_repeat = main_viewport.canvas_item_default_texture_repeat
		root.add_child(viewport)
		_passes[role] = viewport
	await process_frame
	for role: String in copied_roles:
		var viewport := _passes[role] as SubViewport
		viewport.canvas_transform = main_viewport.get_canvas_transform()
	var prop_source := _main_board.get("_actor_layer") as Node2D
	if prop_source == null:
		_abort("formal CourtyardBoardView has no prop actor layer")
		return false
	var props_layer := _pass_canvas("props")
	var ids_layer := _pass_canvas("instance_ids")
	var parts_layer := _pass_canvas("part_ids")
	var crown_union_layer := _pass_canvas("tree_crown_union")
	if not _copy_props(prop_source, props_layer, "props"):
		return false
	if not _copy_props(prop_source, ids_layer, "instance_ids"):
		return false
	if not _copy_props(prop_source, parts_layer, "part_ids"):
		return false
	if not _copy_props(prop_source, crown_union_layer, "tree_crown_union"):
		return false
	if not _add_ground_layers(profile):
		return false
	_add_exclusion_layers()
	return not _failed


func _copy_props(source_layer: Node2D, destination: Node2D, mode: String) -> bool:
	_last_copied_nodes_by_id.clear()
	destination.global_transform = source_layer.global_transform
	destination.y_sort_enabled = source_layer.y_sort_enabled
	destination.texture_filter = source_layer.texture_filter
	destination.texture_repeat = source_layer.texture_repeat
	var by_id: Dictionary = {}
	for record: Dictionary in _instances:
		by_id[str(record["stable_id"])] = record
	for spec_value: Variant in _main_board.get("_props") as Array:
		if not spec_value is Dictionary:
			continue
		var source := spec_value["node"] as Node2D
		if not is_instance_valid(source) or not source.is_visible_in_tree():
			continue
		var kind := _classify_prop(source)
		if kind not in REQUIRED_TYPES:
			continue
		var stable_id := _stable_id(kind, _logical_position(source.global_position))
		if mode == "props":
			var prop_copy := _duplicate_canvas_tree(source)
			if prop_copy == null:
				_abort("could not duplicate visual prop %s" % stable_id)
				return false
			prop_copy.transform = source.transform
			prop_copy.set_meta("terrain_capture_stable_id", stable_id)
			destination.add_child(prop_copy)
			_last_copied_nodes_by_id[stable_id] = prop_copy
		elif mode == "instance_ids":
			var id_copy := _duplicate_canvas_tree(source)
			if id_copy == null:
				_abort("could not duplicate id visual %s" % stable_id)
				return false
			id_copy.transform = source.transform
			var rgb: Color = _instance_color_by_id.get(stable_id, Color.WHITE)
			var id_validation := _apply_instance_id_color(source, id_copy as Node2D, rgb)
			if str(id_validation.get("status", "")) != "PASS_STRUCTURE_ONLY":
				_abort("actual ID clone failed uniform/alpha structure validation for %s: %s" % [stable_id, id_validation])
				return false
			_record_mask_validation(stable_id, "instance_ids", id_validation)
			id_copy.set_meta("terrain_capture_stable_id", stable_id)
			destination.add_child(id_copy)
			_last_copied_nodes_by_id[stable_id] = id_copy
		elif mode == "part_ids" or mode == "tree_crown_union":
			if kind in ["wall", "pillar"]:
				if mode == "tree_crown_union":
					continue
				var part_copy := _duplicate_canvas_tree(source)
				if part_copy == null:
					_abort("could not duplicate structural prop %s" % stable_id)
					return false
				part_copy.transform = source.transform
				var part_validation := _apply_part_colors(source, part_copy as Node2D)
				if str(part_validation.get("status", "")) != "PASS_STRUCTURE_ONLY":
					_abort("actual part clone failed uniform/alpha structure validation for %s: %s" % [stable_id, part_validation])
					return false
				_record_mask_validation(stable_id, "part_ids", part_validation)
				destination.add_child(part_copy)
			elif kind == "tree":
				if not _add_annotated_tree_parts(source, destination, mode):
					return false
	return true


func _apply_instance_id_color(source: Node2D, copy: Node2D, rgb: Color) -> Dictionary:
	var expected_colors: Dictionary = {}
	var stack: Array = [[source, copy, ""]]
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var source_node := pair[0] as Node
		var copy_node := pair[1] as Node
		var path := str(pair[2])
		if source_node.get_class() != copy_node.get_class() or source_node.get_child_count() != copy_node.get_child_count():
			return {"status": "FAIL", "reason": "source/copy node topology differs", "path": path}
		if _is_flat_mask_draw_node(source_node) and (source_node as CanvasItem).visible:
			_set_flat_mask_material(copy_node as CanvasItem, rgb)
			expected_colors[path] = rgb
		for child_index: int in source_node.get_child_count():
			var child_path := str(child_index) if path.is_empty() else path + "/" + str(child_index)
			stack.append([source_node.get_child(child_index), copy_node.get_child(child_index), child_path])
	return _validate_flat_mask_clone(source, copy, expected_colors, {}, "instance_ids")


func _apply_part_colors(source: Node2D, copy: Node2D) -> Dictionary:
	var kind := _classify_prop(source)
	var expected_colors: Dictionary = {}
	var hidden_paths: Dictionary = {}
	for index: int in source.get_child_count():
		var source_child := source.get_child(index) as CanvasItem
		var copy_child := copy.get_child(index) as CanvasItem
		if source_child == null or copy_child == null:
			continue
		if source_child is Polygon2D:
			var part_name := _classify_wall_child(source, source_child as Polygon2D, kind)
			if part_name.is_empty():
				copy_child.visible = false
				hidden_paths[str(index)] = true
			else:
				var color: Color = PART_COLORS[part_name]
				_set_flat_mask_material(copy_child, color)
				expected_colors[str(index)] = color
		elif source_child is Line2D:
			var outline_color: Color = PART_COLORS["wall_outline"]
			_set_flat_mask_material(copy_child, outline_color)
			expected_colors[str(index)] = outline_color
		else:
			copy_child.visible = false
			hidden_paths[str(index)] = true
	return _validate_flat_mask_clone(source, copy, expected_colors, hidden_paths, "part_ids")


func _is_flat_mask_draw_node(node: Node) -> bool:
	return node is Sprite2D or node is Polygon2D or node is Line2D


func _set_flat_mask_material(canvas_item: CanvasItem, rgb: Color) -> void:
	if _flat_mask_shader == null:
		_flat_mask_shader = Shader.new()
		_flat_mask_shader.code = FLAT_MASK_SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = _flat_mask_shader
	material.set_shader_parameter("flat_rgb", Color(rgb.r, rgb.g, rgb.b, 1.0))
	canvas_item.material = material


func _validate_flat_mask_clone(source: Node, copy: Node, expected_colors: Dictionary,
		hidden_paths: Dictionary, role: String) -> Dictionary:
	var stack: Array = [[source, copy, ""]]
	var draw_leaf_count := 0
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var source_node := pair[0] as Node
		var copy_node := pair[1] as Node
		var path := str(pair[2])
		if source_node.get_class() != copy_node.get_class():
			return {"status": "FAIL", "reason": "source/copy node class differs: %s vs %s" % [source_node.get_class(), copy_node.get_class()], "path": path}
		if source_node.get_child_count() != copy_node.get_child_count():
			return {"status": "FAIL", "reason": "source/copy child count differs", "path": path}
		if source_node is CanvasItem and copy_node is CanvasItem:
			var source_canvas := source_node as CanvasItem
			var copy_canvas := copy_node as CanvasItem
			if not is_equal_approx(source_canvas.modulate.a, copy_canvas.modulate.a) \
				or not is_equal_approx(source_canvas.self_modulate.a, copy_canvas.self_modulate.a):
				return {"status": "FAIL", "reason": "source modulation alpha changed", "path": path}
			if not hidden_paths.has(path) and source_canvas.visible != copy_canvas.visible:
				return {"status": "FAIL", "reason": "source visibility changed", "path": path}
		if source_node is Node2D and copy_node is Node2D:
			if not _numeric_arrays_equal(_transform_array((source_node as Node2D).transform), _transform_array((copy_node as Node2D).transform), 0.000001):
				return {"status": "FAIL", "reason": "source transform changed", "path": path}
		if _is_flat_mask_draw_node(source_node):
			var source_draw := source_node as CanvasItem
			var copy_draw := copy_node as CanvasItem
			if hidden_paths.has(path):
				if copy_draw.visible:
					return {"status": "FAIL", "reason": "excluded part remains visible", "path": path}
			elif source_draw.visible:
				if not expected_colors.has(path):
					return {"status": "FAIL", "reason": "visible draw node has no declared flat-color uniform", "path": path}
				var material := copy_draw.material as ShaderMaterial
				if material == null or material.shader == null or not material.shader.code.contains("COLOR = vec4(flat_rgb.rgb, COLOR.a);"):
					return {"status": "FAIL", "reason": "draw node lacks the flat RGB / source COLOR.a shader", "path": path}
				var uniform_value: Variant = material.get_shader_parameter("flat_rgb")
				var expected_color: Color = expected_colors[path]
				if not uniform_value is Color or not _colors_equal(uniform_value as Color, Color(expected_color.r, expected_color.g, expected_color.b, 1.0)):
					return {"status": "FAIL", "reason": "draw node flat-color uniform differs", "path": path}
				var source_alpha := _draw_node_alpha_signature(source_node)
				var copy_alpha := _draw_node_alpha_signature(copy_node)
				if JSON.stringify(source_alpha) != JSON.stringify(copy_alpha):
					return {"status": "FAIL", "reason": "draw node texture or primitive alpha changed", "path": path}
				draw_leaf_count += 1
		for child_index: int in source_node.get_child_count():
			var child_path := str(child_index) if path.is_empty() else path + "/" + str(child_index)
			stack.append([source_node.get_child(child_index), copy_node.get_child(child_index), child_path])
	if draw_leaf_count == 0:
		return {"status": "FAIL", "reason": "clone has no validated draw leaf"}
	return {
		"status": "PASS_STRUCTURE_ONLY",
		"mask_role": role,
		"draw_leaf_count": draw_leaf_count,
		"flat_rgb_uniform_per_leaf": true,
		"alpha_path": "shader outputs incoming COLOR.a; copied hierarchy modulation and Sprite2D texture / Polygon2D color / Line2D default-color alpha signatures match the source",
		"shader_source_sha256": _sha256_text(FLAT_MASK_SHADER_CODE),
		"pixel_alignment": "NOT_TESTED_UNTIL_RENDERED_PNG_READBACK",
	}


func _draw_node_alpha_signature(node: Node) -> Dictionary:
	var result: Dictionary = {}
	if node is CanvasItem:
		var canvas := node as CanvasItem
		result["modulate_alpha"] = canvas.modulate.a
		result["self_modulate_alpha"] = canvas.self_modulate.a
	if node is Sprite2D:
		var sprite := node as Sprite2D
		result["texture"] = _texture_record(sprite.texture)
		result["visible"] = sprite.visible
	elif node is Polygon2D:
		var polygon := node as Polygon2D
		result["texture"] = _texture_record(polygon.texture)
		result["primitive_alpha"] = polygon.color.a
		result["visible"] = polygon.visible
	elif node is Line2D:
		var line := node as Line2D
		result["primitive_alpha"] = line.default_color.a
		result["visible"] = line.visible
	return result


func _colors_equal(left: Color, right: Color) -> bool:
	return is_equal_approx(left.r, right.r) and is_equal_approx(left.g, right.g) \
		and is_equal_approx(left.b, right.b) and is_equal_approx(left.a, right.a)


func _record_mask_validation(stable_id: String, role: String, evidence: Dictionary) -> void:
	var index := _instance_index(stable_id)
	if index < 0:
		_abort("mask clone validation has no instance record for " + stable_id)
		return
	var record := _instances[index].duplicate(true)
	var validations: Dictionary = record.get("mask_clone_validation", {})
	if role in ["part_ids", "tree_crown_union"]:
		var entries: Array = validations.get(role, [])
		entries.append(evidence)
		validations[role] = entries
	else:
		validations[role] = evidence
	record["mask_clone_validation"] = validations
	_instances[index] = record


func _mask_clone_validation_summary() -> Dictionary:
	var by_type: Dictionary = {}
	var instance_records: Array[Dictionary] = []
	for record: Dictionary in _instances:
		var stable_id := str(record.get("stable_id", ""))
		var kind := str(record.get("type", ""))
		var validations: Dictionary = record.get("mask_clone_validation", {})
		var id_validation: Dictionary = validations.get("instance_ids", {})
		if str(id_validation.get("status", "")) != "PASS_STRUCTURE_ONLY" \
			or int(id_validation.get("draw_leaf_count", 0)) <= 0:
			_abort("actual cloned instance has no validated flat ID shader/alpha path: " + stable_id)
			return {}
		var part_validations: Array = validations.get("part_ids", [])
		if kind in ["wall", "pillar"]:
			if part_validations.size() != 1 or str((part_validations[0] as Dictionary).get("status", "")) != "PASS_STRUCTURE_ONLY":
				_abort("actual structural prop has no validated part-ID shader/alpha path: " + stable_id)
				return {}
		if kind == "tree" and _region_scope_approved("crown_geometry"):
			var crown_validations: Array = validations.get("tree_crown_union", [])
			if part_validations.is_empty() or crown_validations.is_empty():
				_abort("approved tree crown has no validated part/crown-union clone: " + stable_id)
				return {}
		for evidence_value: Variant in part_validations:
			if not evidence_value is Dictionary or str((evidence_value as Dictionary).get("status", "")) != "PASS_STRUCTURE_ONLY":
				_abort("tree/prop part clone lacks a validated flat shader/alpha path: " + stable_id)
				return {}
		for evidence_value: Variant in validations.get("tree_crown_union", []):
			if not evidence_value is Dictionary or str((evidence_value as Dictionary).get("status", "")) != "PASS_STRUCTURE_ONLY":
				_abort("tree crown-union clone lacks a validated flat shader/alpha path: " + stable_id)
				return {}
		by_type[kind] = int(by_type.get(kind, 0)) + 1
		instance_records.append({
			"stable_id": stable_id,
			"type": kind,
			"instance_ids": id_validation,
			"part_ids": part_validations,
			"tree_crown_union": validations.get("tree_crown_union", []),
		})
	return {
		"status": "PASS_STRUCTURE_ONLY",
		"actual_cloned_instances": instance_records.size(),
		"counts_by_type": by_type,
		"validated_instances": instance_records,
		"pixel_alignment": "NOT_TESTED_UNTIL_RENDERED_PNG_READBACK",
	}


func _add_annotated_tree_parts(source: Node2D, destination: Node2D, mode: String) -> bool:
	var regions: Dictionary = _region_regions()
	var sprite := _first_sprite(source)
	if sprite == null:
		return true
	var region_order: PackedStringArray = ["crown", "dark_side", "outline"]
	var coord := _logical_position(source.global_position)
	var stable_id := "tree@%s,%s" % [_format_number(coord.x), _format_number(coord.y)]
	if mode == "tree_crown_union":
		region_order = ["crown"]
	for region_name: String in region_order:
		var required_scope: String = str({
			"crown": "crown_geometry",
			"dark_side": "dark_side_geometry",
			"outline": "outline_geometry",
		}.get(region_name, ""))
		if required_scope.is_empty() or not _region_scope_approved(required_scope):
			continue
		var polygons: Array = regions.get(region_name, [])
		if polygons.is_empty():
			continue
		var texture_key := _tree_region_texture_key(sprite, region_name, polygons)
		if not _crown_textures.has(texture_key):
			var masked_texture := _make_annotated_texture(sprite, polygons)
			if masked_texture == null:
				_region_annotation_status = "NOT_TESTED"
				_region_annotation_reason = "The tree atlas image could not be cropped to the annotated region."
				return true
			_crown_textures[texture_key] = masked_texture
		var sprite_copy := sprite.duplicate() as Sprite2D
		if sprite_copy == null:
			_abort("annotated tree Sprite2D could not be duplicated")
			return false
		sprite_copy.texture = _crown_textures[texture_key] as Texture2D
		var rgb: Color = Color.WHITE if mode == "tree_crown_union" else PART_COLORS["tree_" + region_name]
		_set_flat_mask_material(sprite_copy, rgb)
		var root_copy := Node2D.new()
		root_copy.name = "AnnotatedTreeRegion_%s_%s" % [region_name, stable_id]
		root_copy.transform = source.transform
		root_copy.modulate = source.modulate
		root_copy.self_modulate = source.self_modulate
		root_copy.visible = source.visible
		root_copy.texture_filter = source.texture_filter
		root_copy.texture_repeat = source.texture_repeat
		root_copy.add_child(sprite_copy)
		root_copy.move_child(sprite_copy, 0)
		var validation := _validate_annotated_region_clone(source, sprite, root_copy, sprite_copy, rgb, region_name, mode)
		if str(validation.get("status", "")) != "PASS_STRUCTURE_ONLY":
			_abort("annotated tree region clone failed flat-color/alpha structure validation for %s/%s: %s" % [stable_id, region_name, validation])
			return false
		_record_mask_validation(stable_id, "tree_crown_union" if mode == "tree_crown_union" else "part_ids", validation)
		destination.add_child(root_copy)
	return true


func _validate_annotated_region_clone(source_root: Node2D, source_sprite: Sprite2D,
		copy_root: Node2D, copy_sprite: Sprite2D, rgb: Color, region_name: String, mode: String) -> Dictionary:
	if not _colors_equal(source_root.modulate, copy_root.modulate) \
		or not _colors_equal(source_root.self_modulate, copy_root.self_modulate) \
		or not is_equal_approx(source_sprite.modulate.a, copy_sprite.modulate.a) \
		or not is_equal_approx(source_sprite.self_modulate.a, copy_sprite.self_modulate.a):
		return {"status": "FAIL", "reason": "source root/sprite modulation alpha differs"}
	if not _numeric_arrays_equal(_transform_array(source_root.transform), _transform_array(copy_root.transform), 0.000001) \
		or not _numeric_arrays_equal(_transform_array(source_sprite.transform), _transform_array(copy_sprite.transform), 0.000001):
		return {"status": "FAIL", "reason": "source root/sprite transform differs"}
	var atlas_texture := source_sprite.texture as AtlasTexture
	if atlas_texture == null or atlas_texture.atlas == null:
		return {"status": "FAIL", "reason": "source tree sprite does not use the expected atlas texture"}
	var source_region_size: Vector2 = atlas_texture.region.size
	if copy_sprite.texture == null or copy_sprite.texture.get_size() != source_region_size:
		return {"status": "FAIL", "reason": "annotated copy texture size does not match the source atlas region"}
	var material := copy_sprite.material as ShaderMaterial
	if material == null or material.shader == null or not material.shader.code.contains("COLOR = vec4(flat_rgb.rgb, COLOR.a);"):
		return {"status": "FAIL", "reason": "annotated region lacks the flat RGB / source COLOR.a shader"}
	var uniform_value: Variant = material.get_shader_parameter("flat_rgb")
	var expected_color := Color(rgb.r, rgb.g, rgb.b, 1.0)
	if not uniform_value is Color or not _colors_equal(uniform_value as Color, expected_color):
		return {"status": "FAIL", "reason": "annotated region flat-color uniform differs"}
	var masked_image := copy_sprite.texture.get_image()
	if masked_image == null or masked_image.is_empty():
		return {"status": "FAIL", "reason": "annotated region texture has no source alpha image"}
	var alpha_pixels := 0
	for y: int in masked_image.get_height():
		for x: int in masked_image.get_width():
			if masked_image.get_pixel(x, y).a > 0.0:
				alpha_pixels += 1
	if alpha_pixels <= 0:
		return {"status": "FAIL", "reason": "approved atlas region produced an empty alpha mask"}
	return {
		"status": "PASS_STRUCTURE_ONLY",
		"mask_role": "tree_crown_union" if mode == "tree_crown_union" else "part_ids",
		"region": region_name,
		"draw_leaf_count": 1,
		"flat_rgb_uniform_per_leaf": true,
		"alpha_path": "ImageTexture copied from the SHA-bound source AtlasTexture alpha inside reviewed region geometry; flat shader forwards COLOR.a; source root and Sprite2D modulation alpha and transforms match",
		"source_texture_sha256": str(_region_annotation.get("texture_sha256", "")),
		"atlas_region": _region_annotation.get("atlas_region", []),
		"nonzero_alpha_pixels_in_region_mask": alpha_pixels,
		"shader_source_sha256": _sha256_text(FLAT_MASK_SHADER_CODE),
		"pixel_alignment": "NOT_TESTED_UNTIL_RENDERED_PNG_READBACK",
	}


func _make_annotated_texture(sprite: Sprite2D, polygon_records: Array) -> Texture2D:
	var atlas_texture := sprite.texture as AtlasTexture
	if atlas_texture == null or atlas_texture.atlas == null:
		return null
	var region := atlas_texture.region
	var source_image := atlas_texture.atlas.get_image()
	if source_image == null:
		return null
	var region_rect := Rect2i(roundi(region.position.x), roundi(region.position.y), roundi(region.size.x), roundi(region.size.y))
	if region_rect.size.x <= 0 or region_rect.size.y <= 0 or region_rect.end.x > source_image.get_width() or region_rect.end.y > source_image.get_height():
		return null
	var cropped := source_image.get_region(region_rect)
	var polygons: Array[PackedVector2Array] = []
	for polygon_value: Variant in polygon_records:
		if not polygon_value is Array:
			continue
		var points := PackedVector2Array()
		for point_value: Variant in polygon_value:
			if not point_value is Array or (point_value as Array).size() != 2:
				return null
			var point: Array = point_value
			points.append(Vector2(float(point[0]), float(point[1])))
		if points.size() < 3:
			return null
		polygons.append(points)
	if polygons.is_empty():
		return null
	var result := Image.create(cropped.get_width(), cropped.get_height(), false, Image.FORMAT_RGBA8)
	result.fill(Color(0, 0, 0, 0))
	for y: int in cropped.get_height():
		for x: int in cropped.get_width():
			var at := Vector2(x + 0.5, y + 0.5)
			var inside := false
			for polygon: PackedVector2Array in polygons:
				if Geometry2D.is_point_in_polygon(at, polygon):
					inside = true
					break
			if inside:
				result.set_pixel(x, y, cropped.get_pixel(x, y))
	return ImageTexture.create_from_image(result)


func _tree_region_texture_key(sprite: Sprite2D, region_name: String, polygons: Array) -> String:
	return "%s:%s:%s" % [str(sprite.texture.resource_path), region_name, _sha256_text(JSON.stringify(polygons))]


func _add_ground_layers(profile: Dictionary) -> bool:
	var ground_view := _pass_canvas("ground")
	var no_shadow_view := _pass_canvas("ground_without_shadow")
	var surface := _main_board.get("_surface_layer") as Polygon2D
	if surface == null:
		_abort("formal board has no SharedTerrainSurface polygon")
		return false
	var ground_copy := surface.duplicate() as Polygon2D
	var substrate_copy := surface.duplicate() as Polygon2D
	if ground_copy == null or substrate_copy == null:
		_abort("SharedTerrainSurface could not be duplicated")
		return false
	ground_copy.transform = surface.global_transform
	ground_view.add_child(ground_copy)
	substrate_copy.transform = surface.global_transform
	no_shadow_view.add_child(substrate_copy)
	var ground_footings := DRAW_LAYER_SCRIPT.new() as Node2D
	ground_footings.name = "SynchronizedTerrainWithWallApronAndShadow"
	ground_footings.configure("ground_with_footings", _main_board, Color.WHITE)
	ground_footings.transform = _main_board.global_transform
	ground_view.add_child(ground_footings)
	var control_aprons := DRAW_LAYER_SCRIPT.new() as Node2D
	control_aprons.name = "SynchronizedTerrainWithWallApronWithoutShadow"
	control_aprons.configure("ground_without_shadow", _main_board, Color.WHITE)
	control_aprons.transform = _main_board.global_transform
	no_shadow_view.add_child(control_aprons)
	var grid_draw := DRAW_LAYER_SCRIPT.new() as Node2D
	grid_draw.name = "SynchronizedGridMask"
	grid_draw.configure("grid", _main_board, Color.WHITE)
	grid_draw.transform = _main_board.global_transform
	_pass_canvas("grid").add_child(grid_draw)
	var shadow_draw := DRAW_LAYER_SCRIPT.new() as Node2D
	shadow_draw.name = "SynchronizedWallFootingContactShadowMask"
	shadow_draw.configure("contact_shadow", _main_board, Color.WHITE)
	shadow_draw.transform = _main_board.global_transform
	_pass_canvas("contact_shadow").add_child(shadow_draw)
	var types_draw := DRAW_LAYER_SCRIPT.new() as Node2D
	types_draw.name = "SynchronizedTerrainSemanticMask"
	types_draw.configure("ground_types", _main_board, Color.WHITE)
	types_draw.transform = _main_board.global_transform
	_pass_canvas("ground_types").add_child(types_draw)
	return true


func _add_exclusion_layers() -> void:
	_exclusion_runtime_record = {}
	var destination := _pass_canvas("exclusions")
	var actor_source := _main_manager.get_node_or_null("UnitLayer") as Node2D
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "ConservativeDrawableUIBounds"
	ui_layer.layer = 100
	destination.add_child(ui_layer)
	var unit_bounds: Array[Dictionary] = []
	if actor_source != null:
		var units_copy := Node2D.new()
		units_copy.name = "UnitVisualExclusions"
		units_copy.global_transform = actor_source.global_transform
		units_copy.y_sort_enabled = actor_source.y_sort_enabled
		destination.add_child(units_copy)
		for unit: Node in _main_manager.get("units") as Array:
			if unit is CanvasItem and unit.is_visible_in_tree():
				var screen_rect := _unit_screen_bounds(unit as CanvasItem)
				unit_bounds.append({"unit_id": str(unit.get("unit_id")), "rect": _rect_array(screen_rect)})
				_add_screen_rect(ui_layer, screen_rect, "UnitConservativeBounds")
				var clone := _duplicate_canvas_tree(unit)
				if clone != null:
					clone.transform = (unit as CanvasItem).get_transform()
					_apply_alpha_mask_white(unit as CanvasItem, clone as CanvasItem)
					units_copy.add_child(clone)
	var highlight_layer := _main_manager.get_node_or_null("HighlightLayer") as Node2D
	if highlight_layer != null and highlight_layer.visible:
		var highlights_copy := _duplicate_canvas_tree(highlight_layer)
		if highlights_copy != null:
			highlights_copy.transform = highlight_layer.global_transform
			_apply_alpha_mask_white(highlight_layer, highlights_copy as CanvasItem)
			destination.add_child(highlights_copy)
	# Only nodes that actually draw a visual are covered; fullscreen Control and
	# layout containers have no paint of their own and must not blank the board.
	var ui_bounds_count := 0
	for node: Node in _main_session.find_children("*", "Control", true, false):
		var control := node as Control
		if control == null or not control.is_visible_in_tree() or not _is_drawable_ui_control(control):
			continue
		var rect := control.get_global_rect()
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		_add_screen_rect(ui_layer, rect, "DrawableUIBounds")
		ui_bounds_count += 1
	_exclusion_runtime_record = {
		"unit_count": unit_bounds.size(),
		"unit_screen_bounds": unit_bounds,
		"drawable_ui_control_bounds": ui_bounds_count,
		"bounds_are_conservative": true,
	}


func _is_drawable_ui_control(control: Control) -> bool:
	return control is Label or control is Button or control is Panel or control is PanelContainer \
		or control is ColorRect or control is TextureRect or control is TextureButton \
		or control is ProgressBar or control is RichTextLabel or control is LineEdit \
		or control is CheckBox or control is HSeparator or control is VSeparator


func _add_screen_rect(canvas_layer: CanvasLayer, rect: Rect2, node_name: String) -> void:
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(root.size))
	var clipped := rect.intersection(viewport_rect)
	if clipped.size.x <= 0.0 or clipped.size.y <= 0.0:
		return
	var blocker := ColorRect.new()
	blocker.name = node_name
	blocker.position = clipped.position
	blocker.size = clipped.size
	blocker.color = Color.WHITE
	blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_layer.add_child(blocker)


func _unit_screen_bounds(unit: CanvasItem) -> Rect2:
	var screen_origin: Vector2 = unit.get_global_transform_with_canvas() * Vector2.ZERO
	var bounds := Rect2(screen_origin + Vector2(-56.0, -84.0), Vector2(112.0, 168.0))
	for node: Node in unit.find_children("*", "Control", true, false):
		var control := node as Control
		if control != null and control.is_visible_in_tree() and control.size.x > 0.0 and control.size.y > 0.0:
			bounds = bounds.merge(control.get_global_rect())
	return bounds


func _apply_alpha_mask_white(source: CanvasItem, copy: CanvasItem) -> void:
	var stack: Array[Node] = [source, copy]
	while not stack.is_empty():
		var source_node: Node = stack.pop_front()
		var copy_node: Node = stack.pop_front()
		if source_node is CanvasItem and copy_node is CanvasItem:
			var source_canvas := source_node as CanvasItem
			var copy_canvas := copy_node as CanvasItem
			copy_canvas.modulate = Color(1.0, 1.0, 1.0, source_canvas.modulate.a)
			copy_canvas.self_modulate = Color(1.0, 1.0, 1.0, source_canvas.self_modulate.a)
			if source_node is Polygon2D and copy_node is Polygon2D:
				(copy_node as Polygon2D).color = Color(1.0, 1.0, 1.0, (source_node as Polygon2D).color.a)
			elif source_node is Line2D and copy_node is Line2D:
				(copy_node as Line2D).default_color = Color(1.0, 1.0, 1.0, (source_node as Line2D).default_color.a)
		for child_index: int in source_node.get_child_count():
			stack.append(source_node.get_child(child_index))
			stack.append(copy_node.get_child(child_index))


func _duplicate_canvas_tree(source: Node) -> Node:
	var copy := source.duplicate() as Node
	if copy == null:
		return null
	_strip_scripts(copy)
	return copy


func _strip_scripts(node: Node) -> void:
	if node.get_script() != null:
		node.set_script(null)
	for child: Node in node.get_children():
		_strip_scripts(child)


func _new_viewport(role: String, size: Vector2i, transparent: bool) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "TerrainCapture_%s" % role
	viewport.size = size
	var main_visible_size := root.get_visible_rect().size
	if main_visible_size.x > 0.0 and main_visible_size.y > 0.0:
		viewport.size_2d_override = Vector2i(roundi(main_visible_size.x), roundi(main_visible_size.y))
		viewport.size_2d_override_stretch = true
	viewport.transparent_bg = transparent
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.gui_disable_input = true
	return viewport


func _pass_canvas(role: String) -> Node2D:
	var viewport := _passes[role] as SubViewport
	var canvas := Node2D.new()
	canvas.name = "Canvas_%s" % role
	viewport.add_child(canvas)
	return canvas


func _validate_frame_images(images: Dictionary, requested_size: Vector2i) -> bool:
	for role: String in images:
		var image := images[role] as Image
		if image == null or image.is_empty():
			_abort("post-draw image readback is empty: " + role)
			return false
		if image.get_size() != requested_size:
			_abort("post-draw image size differs from request for %s: got %s expected %s" % [role, image.get_size(), requested_size])
			return false
	return true


func _compare_images(actual: Image, reconstruction: Image) -> Dictionary:
	if actual.get_size() != reconstruction.get_size():
		return {"status": "FAIL_SIZE_MISMATCH", "actual_size": _size_array(actual.get_size()), "reconstruction_size": _size_array(reconstruction.get_size())}
	var actual_bytes := actual.get_data()
	var reconstructed_bytes := reconstruction.get_data()
	var pixels := actual.get_width() * actual.get_height()
	var mismatched_pixels := 0
	var max_channel_delta := 0
	for pixel: int in pixels:
		var offset := pixel * 4
		var changed := false
		for channel: int in 4:
			var delta: int = absi(int(actual_bytes[offset + channel]) - int(reconstructed_bytes[offset + channel]))
			max_channel_delta = maxi(max_channel_delta, delta)
			if delta != 0:
				changed = true
		if changed:
			mismatched_pixels += 1
	var ratio := 1.0 - float(mismatched_pixels) / float(maxi(1, pixels))
	return {
		"method": "independent full formal TerrainBattleSession/TacticalScene rebuild from identical validated map; same viewport size and fit path",
		"status": "PASS_EXACT" if mismatched_pixels == 0 else "FAIL_PIXEL_MISMATCH",
		"same_frame_id": true,
		"frame_comparison": "main image and full reconstruction image read from this frame_post_draw callback",
		"image_size": _size_array(actual.get_size()),
		"pixel_count": pixels,
		"exact_match_pixels": pixels - mismatched_pixels,
		"exact_match_ratio": ratio,
		"mismatched_pixels": mismatched_pixels,
		"max_channel_delta": max_channel_delta,
		"excludes_ui": false,
	}


func _save_frame_images(images: Dictionary, case_directory: String, frame_id: int) -> Dictionary:
	var records: Dictionary = {}
	var roles: Array[String] = ["main", "reconstruction"]
	roles.append_array(_passes.keys())
	for role: String in roles:
		var image := images[role] as Image
		var path := case_directory.path_join(role + ".png")
		var save_error := image.save_png(path)
		if save_error != OK:
			_abort("failed to save %s: %s" % [role, error_string(save_error)])
			return {}
		records[role] = {
			"role": role,
			"purpose": _image_purpose(role),
			"path": role + ".png",
			"sha256": FileAccess.get_sha256(path),
			"image_size": _size_array(image.get_size()),
			"frame_id": frame_id,
			"mime_type": "image/png",
		}
	return records


func _build_manifest_skeleton(map_data: Dictionary, resolution: Vector2i, case_name: String) -> Dictionary:
	return {
		"schema_version": CAPTURE_SCHEMA,
		"capture_config": {
			"case_name": case_name,
			"map_size": [int(map_data.get("width", 0)), int(map_data.get("height", 0))],
			"window_size": [resolution.x, resolution.y],
			"requested_resolution": [resolution.x, resolution.y],
			"renderer": RenderingServer.get_current_rendering_method(),
			"stretch_mode": str(ProjectSettings.get_setting("display/window/stretch/mode")),
			"scene": "TerrainBattleSession -> scenes/tactical/TacticalScene.tscn",
		"output_images": ["main", "reconstruction", "props", "instance_ids", "part_ids", "tree_crown_union", "ground", "ground_without_shadow", "grid", "contact_shadow", "exclusions", "ground_types"],
		},
		"candidate": _candidate_record(),
		"sources": _path_hashes(SOURCE_PATHS),
		"materials": _path_hashes(MATERIAL_PATHS),
		"materials_digest_sha256": _sha256_text(JSON.stringify(_path_hashes(MATERIAL_PATHS))),
		"common_frame": {},
		"viewports": {},
		"images": {},
		"instances": [],
		"reconstruction": {},
		"limitations": [],
	}


func _candidate_record() -> Dictionary:
	var head := _git_output(["rev-parse", "HEAD"]).strip_edges()
	var branch := _git_output(["branch", "--show-current"]).strip_edges()
	var dirty_paths: PackedStringArray = []
	var status_text := _git_output(["status", "--porcelain", "--untracked-files=all"])
	for line: String in status_text.split("\n", false):
		if line.length() > 3:
			dirty_paths.append(line.substr(3).strip_edges())
	var source_hashes: Dictionary = {}
	for source_path: String in ["tests/claude_review/capture_terrain_readability.gd", "tests/claude_review/terrain_mask_draw_layer.gd", "tests/claude_review/terrain_readability_crown_regions.json"]:
		var absolute := ProjectSettings.globalize_path("res://" + source_path)
		if FileAccess.file_exists(absolute):
			source_hashes[source_path] = FileAccess.get_sha256(absolute)
	return {
		"head": head,
		"branch": branch,
		"working_tree_candidate": not dirty_paths.is_empty(),
		"dirty": not dirty_paths.is_empty(),
		"dirty_paths": dirty_paths,
		"source_sha256": source_hashes,
		"candidate_digest_sha256": _sha256_text(JSON.stringify(source_hashes)),
	}


func _path_hashes(paths: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for path: String in paths:
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute):
			result[path] = FileAccess.get_sha256(absolute)
	return result


func _viewport_records(images: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	result["main"] = _viewport_record(root as Viewport, images["main"] as Image)
	for role: String in _passes:
		result[role] = _viewport_record(_passes[role] as Viewport, images[role] as Image)
	result["reconstruction"] = _viewport_record(_reconstruction_viewport, images["reconstruction"] as Image)
	return result


func _structural_viewport_records() -> Dictionary:
	var result: Dictionary = {}
	result["main"] = _viewport_structure_record(root as Viewport)
	for role: String in _passes:
		result[role] = _viewport_structure_record(_passes[role] as Viewport)
	result["reconstruction"] = _viewport_structure_record(_reconstruction_viewport)
	return result


func _viewport_record(viewport: Viewport, image: Image) -> Dictionary:
	var record := _viewport_structure_record(viewport)
	record["image_size"] = _size_array(image.get_size())
	return record


func _viewport_structure_record(viewport: Viewport) -> Dictionary:
	var texture_size := Vector2i.ZERO
	if viewport.get_texture() != null:
		texture_size = viewport.get_texture().get_size()
	var size_2d_override := Vector2i.ZERO
	var size_2d_override_stretch := false
	if viewport is SubViewport:
		size_2d_override = (viewport as SubViewport).size_2d_override
		size_2d_override_stretch = (viewport as SubViewport).size_2d_override_stretch
	return {
		"size": _size_array(viewport.size),
		"size_2d_override": _size_array(size_2d_override),
		"size_2d_override_stretch": size_2d_override_stretch,
		"canvas_transform": _transform_array(viewport.get_canvas_transform()),
		"final_transform": _transform_array(viewport.get_final_transform()),
		"texture_size": _size_array(texture_size),
		"visible_rect": _rect_array(viewport.get_visible_rect()),
	}


func _validate_viewport_structure(records: Dictionary, requested_size: Vector2i,
		require_exact_pixel_sizes: bool = false) -> bool:
	var expected_roles: Array[String] = ["main", "reconstruction"]
	expected_roles.append_array(_passes.keys())
	var main_visible: Vector2i = Vector2i.ZERO
	var main_visible_rect: Array = []
	var main_canvas: Array = []
	var main_final: Array = []
	if records.has("main"):
		var main_record: Dictionary = records["main"]
		main_canvas = main_record.get("canvas_transform", [])
		main_final = main_record.get("final_transform", [])
		main_visible_rect = main_record.get("visible_rect", [])
		if main_visible_rect.size() == 4:
			main_visible = Vector2i(roundi(float(main_visible_rect[2])), roundi(float(main_visible_rect[3])))
	for role: String in expected_roles:
		if not records.has(role):
			_abort("viewport structure record is missing role " + role)
			return false
		var record: Dictionary = records[role]
		if record.get("size") != _size_array(requested_size):
			_abort("viewport physical size differs for %s: %s expected %s" % [role, record.get("size"), requested_size])
			return false
		var texture_size: Array = record.get("texture_size", [])
		if texture_size.size() != 2 or int(texture_size[0]) <= 0 or int(texture_size[1]) <= 0:
			_abort("viewport %s has no positive texture size in structural metadata" % role)
			return false
		if require_exact_pixel_sizes:
			if record.get("texture_size") != _size_array(requested_size) or record.get("image_size") != _size_array(requested_size):
				_abort("viewport %s readback/texture size differs from requested native pixels" % role)
				return false
		var visible_rect: Array = record.get("visible_rect", [])
		if visible_rect.size() != 4 or not _numeric_arrays_equal(visible_rect, main_visible_rect, 0.001):
			_abort("viewport %s visible_rect mapping differs from main" % role)
			return false
		for transform_name: String in ["canvas_transform", "final_transform"]:
			var transform_value: Array = record.get(transform_name, [])
			if transform_value.size() != 6:
				_abort("viewport %s has no six-value %s" % [role, transform_name])
				return false
			for scalar: Variant in transform_value:
				if not scalar is float and not scalar is int:
					_abort("viewport %s %s contains a non-numeric value" % [role, transform_name])
					return false
			if role != "main":
				var reference: Array = main_canvas if transform_name == "canvas_transform" else main_final
				if not _numeric_arrays_equal(transform_value, reference, 0.001):
					_abort("viewport %s %s differs from main; structural transforms cannot establish same-pixel mapping" % [role, transform_name])
					return false
		if role != "main":
			if main_visible.x <= 0 or main_visible.y <= 0:
				_abort("main visible rect is unavailable; cannot validate auxiliary viewport scale")
				return false
			if record.get("size_2d_override") != _size_array(main_visible) or record.get("size_2d_override_stretch") != true:
				_abort("viewport %s does not preserve the main logical visible size with 2D override stretch" % role)
				return false
	return true


func _numeric_arrays_equal(left: Array, right: Array, epsilon: float) -> bool:
	if left.size() != right.size():
		return false
	for index: int in left.size():
		if absf(float(left[index]) - float(right[index])) > epsilon:
			return false
	return true


func _c8_capture_record(image: Image, capture_group: String, case_directory: String) -> Dictionary:
	var path := case_directory.path_join("main.png")
	var c8_record: Dictionary = CAPTURE_METADATA.capture_record(root as Window, image, path, {"capture_group": capture_group})
	c8_record["role"] = "main"
	return c8_record


func _instance_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in _instances:
		var copy := record.duplicate(true)
		var stable_id := str(copy["stable_id"])
		copy["visible_mask_role"] = "instance_ids"
		copy["color"] = _hex_color(_instance_color_by_id.get(stable_id, Color.WHITE))
		copy["edge_policy"] = {"alpha_threshold": 0.5, "uncertain_if_alpha_below": 0.98, "uncertain_mixed_id_color": true}
		result.append(copy)
	return result


func _mask_legend() -> Dictionary:
	var classes: Dictionary = {}
	for part_name: String in PART_COLORS:
		classes[part_name] = {"color": _hex_color(PART_COLORS[part_name]), "classification_source": "actual Polygon2D/Line2D structure or SHA-bound atlas annotation"}
	var terrain_classes: Dictionary = {}
	for terrain_id: int in TERRAIN_COLORS:
		terrain_classes[str(terrain_id)] = {"color": _hex_color(TERRAIN_COLORS[terrain_id]), "semantic": _terrain_name(terrain_id)}
	terrain_classes["paving"] = {"color": "#FF8000", "semantic": "_is_paved_at cell flag"}
	return {
		"instance_ids": {"role": "instance_ids", "encoding": "unique 24-bit RGB by stable_id; transparent pixels are no object; partially covered/antialiased edges are uncertain"},
		"part_ids": {"role": "part_ids", "encoding": "class RGB palette", "classes": classes},
		"tree_crown_union": {"role": "tree_crown_union", "encoding": "white alpha mask from approved crown geometry intersected with source AtlasTexture alpha; dark-side and outline remain separately NOT_TESTED if no reviewed polygons exist"},
		"ground": {"role": "ground", "encoding": "actual SharedTerrainSurface material plus production-equivalent wall apron and footing shadow, without props or grid"},
		"ground_without_shadow": {"role": "ground_without_shadow", "encoding": "same actual SharedTerrainSurface material and production-equivalent wall apron with only the footing shadow draw omitted"},
		"grid": {"role": "grid", "encoding": "white vector lines from exact TerrainDetails grid coordinates"},
		"contact_shadow": {"role": "contact_shadow", "encoding": "white wall-footing shadow geometry from _draw_wall_footings formula"},
		"exclusions": {"role": "exclusions", "encoding": "unit/highlight alpha clones plus conservative screen-space bounds for visible units and drawable leaf UI controls"},
		"ground_types": {"role": "ground_types", "encoding": "cell-diamond semantic palette", "classes": terrain_classes},
	}


func _capture_limitations() -> Array[String]:
	var result: Array[String] = [
		"A headless run validates map/node structure only and cannot validate pixels.",
		"T1, T2, T3, T4, T5, and T6 measurement outcomes are not calculated by this capture utility.",
		"The visible-instance mask contains four target prop classes only; visible unit/highlight/UI overlap is supplied separately by the exclusions role.",
		"The 25x25 fixture repeats the real 10x10 terrain source and is not a new authored battlefield.",
		"Only wall-footing shadow polygons have independent runtime geometry; tree contact shadows inside the tree Sprite2D cannot be isolated and are NOT_TESTED.",
	]
	if not _region_scope_approved("crown_geometry"):
		result.append("Tree crown geometry is NOT_TESTED: " + _region_annotation_reason)
	if not _region_scope_approved("dark_side_geometry"):
		result.append("Tree dark-side geometry is NOT_TESTED: no independent scope approval.")
	if not _region_scope_approved("outline_geometry"):
		result.append("Tree raster-outline geometry is NOT_TESTED: no independent scope approval; an empty annotation does not establish absence.")
	if _exclusion_has_stripped_draw_scripts():
		result.append("Some exclusion clone CanvasItems have scripts removed in the isolated mask; every visible unit also has a conservative screen-space exclusion bound, and HUD bounds cover only leaf controls with actual visual drawing.")
	return result


func _exclusion_record() -> Dictionary:
	var result := {
		"mask_role": "exclusions",
		"status": "CAPTURED_WITH_CONSERVATIVE_CONTROL_BOUNDS",
		"complete": true,
		"unit_source": "formal TacticalManager.units CanvasItem subtrees copied with original transforms, plus conservative screen-space bounds around every visible unit",
		"highlight_source": "formal TacticalManager.HighlightLayer CanvasItem subtree copied with original transforms",
		"ui_source": "visible leaf drawing controls only; fullscreen roots and layout containers are ignored",
		"stripped_canvasitem_scripts": _stripped_script_paths(),
	}
	result.merge(_exclusion_runtime_record, true)
	return result


func _exclusion_has_stripped_draw_scripts() -> bool:
	return not _stripped_script_paths().is_empty()


func _stripped_script_paths() -> Array[String]:
	var result: Array[String] = []
	if not is_instance_valid(_main_session) or not is_instance_valid(_main_manager):
		return result
	for unit: Node in _main_manager.get("units") as Array:
		_collect_script_paths(unit, result)
	var highlights := _main_manager.get_node_or_null("HighlightLayer")
	if highlights != null:
		_collect_script_paths(highlights, result)
	return result


func _collect_script_paths(node: Node, target: Array[String]) -> void:
	if node is CanvasItem and node.get_script() != null:
		var path := str(node.get_path())
		if not target.has(path):
			target.append(path)
	for child: Node in node.get_children():
		_collect_script_paths(child, target)


func _image_purpose(role: String) -> String:
	var purposes := {
		"main": "formal session native main viewport screenshot",
		"reconstruction": "independent full formal session reconstruction from same map and fit path",
		"props": "transparent pass of copied actual prop CanvasItems with original textures and transforms",
		"instance_ids": "RGB stable ID pass of copied actual prop CanvasItems in UnitLayer y-sort order",
		"part_ids": "structural part masks for wall/pillar and hash-bound tree-region annotation",
		"ground": "copied actual SharedTerrainSurface polygon and ShaderMaterial",
		"ground_without_shadow": "same actual surface polygon/material with props/details excluded",
		"grid": "synchronized vector reconstruction of the live board grid draw procedure",
		"contact_shadow": "synchronized wall-footing contact-shadow vector mask",
		"exclusions": "unit/highlight silhouettes plus conservative unit and drawable UI bounds",
		"ground_types": "semantic ground-cell type and paving mask",
	}
	return str(purposes.get(role, role))


func _verify_initial_fit(resolution: Vector2i) -> bool:
	var camera := _main_session.get("camera") as Camera2D
	var zoom_value: float = float(_main_session.get("_fit_zoom"))
	if camera == null or zoom_value <= 0.0 or not is_equal_approx(camera.zoom.x, camera.zoom.y):
		_abort("session did not establish its official initial fit camera")
		return false
	if (root as Viewport).size != resolution:
		_abort("root viewport size changed while initializing fit")
		return false
	return true


func _camera_record() -> Dictionary:
	var camera := _main_session.get("camera") as Camera2D
	if camera == null:
		return {"status": "UNAVAILABLE"}
	return {
		"status": "captured",
		"fit_call": "TerrainBattleSession._resize -> fit_board",
		"fit_zoom": float(_main_session.get("_fit_zoom")),
		"camera_zoom": [camera.zoom.x, camera.zoom.y],
		"camera_position": [camera.position.x, camera.position.y],
		"camera_global_transform": _transform_array(camera.global_transform),
		"manual_camera_override": false,
	}


func _collect_types() -> Dictionary:
	return _count_types(_instances)


func _count_types(records: Array[Dictionary]) -> Dictionary:
	var counts: Dictionary = {}
	for kind: String in REQUIRED_TYPES:
		counts[kind] = 0
	for record: Dictionary in records:
		var kind := str(record.get("type", ""))
		if counts.has(kind):
			counts[kind] = int(counts[kind]) + 1
	return counts


func _validate_instance_counts(counts: Dictionary) -> bool:
	for kind: String in REQUIRED_TYPES:
		if int(counts.get(kind, 0)) < 3:
			_abort("fixture has fewer than three actual %s instances: %s; prop inventory=%s" % [kind, counts, JSON.stringify(_prop_inventory_debug())])
			return false
	return true


func _validate_structural_parts(records: Array[Dictionary]) -> bool:
	for record: Dictionary in records:
		var kind := str(record.get("type", ""))
		if kind not in ["wall", "pillar"]:
			continue
		var parts: Dictionary = record.get("parts", {})
		var expected: PackedStringArray = ["wall_top", "wall_side"] if kind == "wall" else ["pillar_top", "pillar_side", "pillar_base"]
		var actual_roles: PackedStringArray = []
		for part_value: Variant in parts.get("parts", []):
			if part_value is Dictionary:
				actual_roles.append(str((part_value as Dictionary).get("role", "")))
		for role: String in expected:
			if role not in actual_roles:
				_abort("%s instance %s has no actual %s mask mapping; parts=%s" % [kind, record.get("stable_id"), role, actual_roles])
				return false
	return true


func _prop_inventory_debug() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_instance_valid(_main_board):
		return result
	var grid: Variant = _main_manager.get("grid")
	var wall_cells: Array[Dictionary] = []
	for y: int in grid.height:
		for x: int in grid.width:
			var cell := Vector2i(x, y)
			if grid.get_cell(cell).terrain == Cell.Terrain.WALL:
				wall_cells.append({"cell": [x, y], "variant": _main_board.call("visual_variant_at", cell), "architecture": (_main_board.get("_architecture_walls") as Dictionary).has(cell)})
	for spec_value: Variant in _main_board.get("_props") as Array:
		if not spec_value is Dictionary:
			continue
		var node := (spec_value as Dictionary).get("node") as Node2D
		if not is_instance_valid(node):
			continue
		result.append({
			"name": node.name,
			"type": _classify_prop(node),
			"visible": node.visible,
			"visible_in_tree": node.is_visible_in_tree(),
			"position": [node.global_position.x, node.global_position.y],
			"variant": _main_board.call("visual_variant_at", Vector2i(floori(_logical_position(node.global_position).x), floori(_logical_position(node.global_position).y))) if _classify_prop(node) in ["wall", "pillar"] else "",
		})
	result.append({"actual_grid_wall_cells": wall_cells})
	return result


func _first_sprite(node: Node) -> Sprite2D:
	for child: Node in node.find_children("*", "Sprite2D", true, false):
		return child as Sprite2D
	return null


func _node_texture_signature(node: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var queue: Array[Node] = [node]
	while not queue.is_empty():
		var current: Node = queue.pop_front()
		if current is Sprite2D:
			var sprite := current as Sprite2D
			result.append({"node": str(current.name), "class": "Sprite2D", "texture": _texture_record(sprite.texture), "transform": _transform_array(sprite.transform), "centered": sprite.centered, "offset": [sprite.offset.x, sprite.offset.y], "flip_h": sprite.flip_h, "flip_v": sprite.flip_v})
		elif current is Polygon2D:
			var polygon := current as Polygon2D
			result.append({"node": str(current.name), "class": "Polygon2D", "texture": _texture_record(polygon.texture), "point_count": polygon.polygon.size(), "transform": _transform_array(polygon.transform)})
		elif current is Line2D:
			var line := current as Line2D
			result.append({"node": str(current.name), "class": "Line2D", "point_count": line.points.size(), "width": line.width, "transform": _transform_array(line.transform)})
		for child: Node in current.get_children():
			queue.append(child)
	return result


func _texture_record(texture: Texture2D) -> Dictionary:
	if texture == null:
		return {"resource_path": "", "size": [0, 0]}
	var result := {"resource_path": texture.resource_path, "size": _size_array(texture.get_size())}
	if texture is AtlasTexture:
		var atlas := texture as AtlasTexture
		result["atlas_path"] = atlas.atlas.resource_path if atlas.atlas != null else ""
		result["atlas_sha256"] = FileAccess.get_sha256(ProjectSettings.globalize_path(atlas.atlas.resource_path)) if atlas.atlas != null and not atlas.atlas.resource_path.is_empty() else ""
		result["region"] = _rect_array(atlas.region)
	return result


func _load_region_annotation(profile: Dictionary) -> void:
	_region_annotation = {}
	_region_annotation_status = "NOT_TESTED"
	_region_annotation_reason = "Texture-bound tree region annotation is absent."
	var absolute := ProjectSettings.globalize_path(REGION_ANNOTATION_PATH)
	if not FileAccess.file_exists(absolute):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGION_ANNOTATION_PATH))
	if not parsed is Dictionary:
		_region_annotation_reason = "Tree region annotation is not a JSON object."
		return
	var annotation: Dictionary = parsed
	var tree_spec: Dictionary = profile.get("tree", {})
	var expected_texture := str(tree_spec.get("texture", ""))
	var expected_region: Array = tree_spec.get("region", [])
	var actual_sha := FileAccess.get_sha256(ProjectSettings.globalize_path(expected_texture))
	if annotation.get("schema_version") != "terrain-readability-regions/1":
		_region_annotation_reason = "Tree region annotation schema version is unsupported."
		return
	if str(annotation.get("texture_path", "")) != expected_texture or str(annotation.get("texture_sha256", "")) != actual_sha:
		_region_annotation_reason = "Tree region annotation texture path or SHA256 does not match the current source PNG."
		return
	if annotation.get("atlas_region", []) != expected_region or str(annotation.get("coordinate_space", "")) != "atlas_region_local_pixels":
		_region_annotation_reason = "Tree region annotation atlas rectangle or coordinate space does not match the current visual profile."
		return
	var regions: Variant = annotation.get("regions", {})
	if not regions is Dictionary or (regions as Dictionary).get("crown", []).is_empty():
		_region_annotation_reason = "Tree region annotation does not define a crown polygon."
		return
	_region_annotation = annotation
	if str(annotation.get("review_status", "pending")).to_lower() != "approved":
		_region_annotation_status = "PENDING_REVIEW"
		_region_annotation_reason = "Texture path, SHA256, and atlas coordinates match, but crown polygons have not passed independent original-image review."
		return
	var scopes: Variant = annotation.get("approved_scope", [])
	if not scopes is Array or (scopes as Array).is_empty():
		_region_annotation_status = "NOT_TESTED"
		_region_annotation_reason = "Annotation review is approved but no classification scope is explicitly approved."
		return
	_region_annotation_status = "PARTIAL_APPROVAL"
	if _region_scope_approved("crown_geometry") and _region_scope_approved("dark_side_geometry") and _region_scope_approved("outline_geometry"):
		_region_annotation_status = "APPROVED"
	_region_annotation_reason = "Texture path, SHA256, atlas rectangle, and only the listed approved_scope classifications passed independent review."


func _region_regions() -> Dictionary:
	var regions: Variant = _region_annotation.get("regions", {})
	return regions as Dictionary if regions is Dictionary else {}


func _instance_index(stable_id: String) -> int:
	for index: int in _instances.size():
		if str(_instances[index]["stable_id"]) == stable_id:
			return index
	return -1


func _logical_position(world: Vector2) -> Vector2:
	var grid: Variant = _main_manager.get("grid")
	var origin: Vector2 = grid.grid_to_world(Vector2i.ZERO)
	var delta := world - origin
	var x: float = (delta.x / 32.0 + delta.y / 16.0) * 0.5
	var y: float = (delta.y / 16.0 - delta.x / 32.0) * 0.5
	return Vector2(snappedf(x, 0.01), snappedf(y, 0.01))


func _frames(count: int) -> void:
	for _index: int in count:
		await process_frame


func _id_color(id: int) -> Color:
	# One stable 24-bit RGB code per sorted stable_id. Alpha remains the source
	# texture/material coverage so antialiased edges stay detectable as uncertain.
	var value: int = id & 0xFFFFFF
	if value == 0:
		value = 1
	return Color(float((value >> 16) & 0xFF) / 255.0, float((value >> 8) & 0xFF) / 255.0, float(value & 0xFF) / 255.0, 1.0)


func _terrain_name(terrain_id: int) -> String:
	return ["plain", "forest", "mountain", "peak", "wall", "shallow_water", "deep_water", "lava", "swamp"][terrain_id] if terrain_id >= 0 and terrain_id <= 8 else "unknown"


func _validate_output_directory() -> bool:
	if not _output_directory.is_absolute_path():
		_abort("output must be an absolute path outside the project")
		return false
	var project := ProjectSettings.globalize_path("res://").simplify_path().replace("\\", "/").to_lower().trim_suffix("/")
	var output := _output_directory.simplify_path().replace("\\", "/").to_lower().trim_suffix("/")
	if output == project or output.begins_with(project + "/"):
		_abort("output must be outside the project checkout")
		return false
	if DirAccess.dir_exists_absolute(_output_directory) and not DirAccess.get_files_at(_output_directory).is_empty():
		_abort("output directory must be empty to preserve prior capture batches")
		return false
	if DirAccess.make_dir_recursive_absolute(_output_directory) != OK:
		_abort("could not create output directory")
		return false
	return true


func _parse_integer_list(value: String) -> Array[int]:
	var result: Array[int] = []
	for item: String in value.split(",", false):
		var parsed := item.strip_edges().to_int()
		if parsed > 0 and not result.has(parsed):
			result.append(parsed)
	return result


func _parse_resolutions(value: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for item: String in value.split(",", false):
		var parts := item.to_lower().split("x", false)
		if parts.size() != 2:
			continue
		var resolution := Vector2i(parts[0].to_int(), parts[1].to_int())
		if resolution.x > 0 and resolution.y > 0 and not result.has(resolution):
			result.append(resolution)
	return result


func _write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_abort("could not write manifest: " + path)
		return false
	file.store_string(JSON.stringify(value, "  "))
	file.close()
	return true


func _git_output(arguments: PackedStringArray) -> String:
	var output: Array[String] = []
	var git_arguments := PackedStringArray(["-C", ProjectSettings.globalize_path("res://").simplify_path()])
	git_arguments.append_array(arguments)
	var result := OS.execute("git", git_arguments, output, true)
	return "" if result != 0 or output.is_empty() else "\n".join(output)


func _sha256_text(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()


func _size_array(size: Vector2i) -> Array[int]:
	return [size.x, size.y]


func _rect_array(rect: Rect2) -> Array[float]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _transform_array(transform: Transform2D) -> Array[float]:
	return [transform.x.x, transform.x.y, transform.y.x, transform.y.y, transform.origin.x, transform.origin.y]


func _color_array(color: Color) -> Array[float]:
	return [color.r, color.g, color.b, color.a]


func _format_number(value: float) -> String:
	var snapped := snappedf(value, 0.01)
	return "%.2f" % snapped


func _hex_color(color: Color) -> String:
	return "#%02X%02X%02X" % [roundi(color.r * 255.0), roundi(color.g * 255.0), roundi(color.b * 255.0)]


func _abort(message: String) -> void:
	_failed = true
	push_error("[TerrainMaskCapture] " + message)
	if _main_session != null or not _passes.is_empty():
		_close_sessions_and_passes()
	quit(1)


func _close_sessions_and_passes() -> void:
	for viewport_value: Variant in _passes.values():
		var viewport := viewport_value as SubViewport
		if is_instance_valid(viewport):
			viewport.queue_free()
	_passes.clear()
	if is_instance_valid(_reconstruction_viewport):
		_reconstruction_viewport.queue_free()
	_reconstruction_viewport = null
	if is_instance_valid(_main_session):
		_main_session.get_parent().remove_child(_main_session)
		_main_session.free()
	_main_session = null
	_main_battle = null
	_main_manager = null
	_main_board = null
	if is_instance_valid(_reconstruction_session):
		_reconstruction_session.get_parent().remove_child(_reconstruction_session)
		_reconstruction_session.free()
	_reconstruction_session = null
	_instances.clear()
	_instance_color_by_id.clear()
	_crown_textures.clear()
