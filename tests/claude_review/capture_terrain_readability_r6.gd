extends "res://tests/claude_review/capture_terrain_readability_v6_atlas.gd"
## R6 shares wall-footing drawing with the production courtyard board.

const R6_ENTRY_SCRIPT := "res://tests/claude_review/capture_terrain_readability_r6.gd"
const R6_DRAW_LAYER_SCRIPT_PATH := "res://tests/claude_review/terrain_mask_draw_layer_r6.gd"
const R6_DRAW_LAYER_SCRIPT := preload("res://tests/claude_review/terrain_mask_draw_layer_r6.gd")
const BASE_DRAW_LAYER_SCRIPT := preload("res://tests/claude_review/terrain_mask_draw_layer.gd")
const R6_CAPTURE_SCRIPT_CHAIN: PackedStringArray = [
	R6_ENTRY_SCRIPT,
	"res://tests/claude_review/capture_terrain_readability_v6_atlas.gd",
	"res://tests/claude_review/capture_terrain_readability_v6_regions_semantic_sidecar.gd",
	"res://tests/claude_review/capture_terrain_readability_v6_regions.gd",
	"res://tests/claude_review/capture_terrain_readability_v6.gd",
	"res://tests/claude_review/capture_terrain_readability.gd",
]
const R6_SOURCE_PATHS: PackedStringArray = [
	R6_ENTRY_SCRIPT,
	R6_DRAW_LAYER_SCRIPT_PATH,
	"res://scripts/ui/playground/courtyard_board_view.gd",
	"res://assets/prototype/battlefield_courtyard/visual_profile.json",
	"res://assets/prototype/battlefield_courtyard/masonry-wall-limestone-r6.png",
	"res://assets/prototype/battlefield_courtyard/masonry-wall-limestone-r6.png.import",
	"res://assets/prototype/battlefield_courtyard/coping-limestone-r6.png",
	"res://assets/prototype/battlefield_courtyard/coping-limestone-r6.png.import",
]
const R6_PROP_METADATA_KEYS: Array[String] = [
	"r6_height",
	"r6_side_count",
	"r6_break_levels",
]


func _add_ground_layers(profile: Dictionary) -> bool:
	if not super._add_ground_layers(profile):
		return false
	if not is_instance_valid(_main_board):
		_abort("R6 capture has no live production courtyard board")
		return false
	for method_name: String in ["draw_wall_footing_visuals", "wall_footing_visuals"]:
		if not _main_board.has_method(method_name):
			_abort("R6 production board is missing required method: " + method_name)
			return false
	var replacements: Array[Dictionary] = [
		{
			"pass": "ground",
			"node": "SynchronizedTerrainWithWallApronAndShadow",
			"mode": "ground_with_footings",
		},
		{
			"pass": "ground_without_shadow",
			"node": "SynchronizedTerrainWithWallApronWithoutShadow",
			"mode": "ground_without_shadow",
		},
		{
			"pass": "contact_shadow",
			"node": "SynchronizedWallFootingContactShadowMask",
			"mode": "contact_shadow",
		},
	]
	for replacement: Dictionary in replacements:
		if not _replace_r6_draw_layer(replacement):
			return false
	return true


func _replace_r6_draw_layer(replacement: Dictionary) -> bool:
	var pass_name := str(replacement["pass"])
	var viewport := _passes.get(pass_name) as SubViewport
	if viewport == null:
		_abort("R6 capture pass is missing: " + pass_name)
		return false
	var canvas := viewport.get_node_or_null(NodePath("Canvas_" + pass_name)) as Node2D
	if canvas == null:
		_abort("R6 capture canvas is missing: Canvas_" + pass_name)
		return false
	var draw_node := canvas.get_node_or_null(NodePath(str(replacement["node"]))) as Node2D
	if draw_node == null or draw_node.get_parent() != canvas:
		_abort("R6 expected synchronized draw node is missing from " + pass_name)
		return false
	if draw_node.get_script() != BASE_DRAW_LAYER_SCRIPT:
		_abort("R6 expected inherited base draw layer before replacement: " + str(replacement["node"]))
		return false
	var original_parent := draw_node.get_parent()
	var original_index := draw_node.get_index()
	var original_transform := draw_node.transform
	var original_name := draw_node.name
	draw_node.set_script(R6_DRAW_LAYER_SCRIPT)
	draw_node.name = original_name
	draw_node.transform = original_transform
	if draw_node.get_parent() != original_parent or draw_node.get_index() != original_index \
			or draw_node.transform != original_transform:
		_abort("R6 script replacement changed draw-node order, parent, or transform: " + original_name)
		return false
	if not draw_node.has_method("configure") or not draw_node.has_signal("capture_failed"):
		_abort("R6 draw layer does not expose configure() and capture_failed")
		return false
	var failure_handler := Callable(self, "_abort")
	if not draw_node.is_connected("capture_failed", failure_handler):
		var connection_error := draw_node.connect("capture_failed", failure_handler)
		if connection_error != OK:
			_abort("R6 draw layer could not connect its capture_failed signal")
			return false
	draw_node.call("configure", str(replacement["mode"]), _main_board, Color.WHITE)
	return true


func _build_manifest_skeleton(map_data: Dictionary, resolution: Vector2i, case_name: String) -> Dictionary:
	var manifest: Dictionary = super._build_manifest_skeleton(map_data, resolution, case_name)
	var capture_config: Dictionary = manifest.get("capture_config", {}).duplicate(true)
	capture_config["capture_entry_script"] = R6_ENTRY_SCRIPT
	capture_config["capture_script_inheritance"] = R6_CAPTURE_SCRIPT_CHAIN.duplicate()
	capture_config["draw_layer_script"] = R6_DRAW_LAYER_SCRIPT_PATH
	capture_config["wall_footing_geometry"] = {
		"ground_draw": "courtyard_board_view.gd:draw_wall_footing_visuals(canvas, include_shadow)",
		"contact_shadow_mask": "courtyard_board_view.gd:wall_footing_visuals()['shadows'] as board-local polygons",
		"contact_shadow_mask_color": "white",
	}
	capture_config["r6_board_geometry_metadata"] = _r6_board_geometry_record()
	manifest["capture_config"] = capture_config
	return manifest


func _path_hashes(paths: PackedStringArray) -> Dictionary:
	var extended: PackedStringArray = paths.duplicate()
	for path: String in R6_SOURCE_PATHS:
		if path not in extended:
			extended.append(path)
	var result: Dictionary = super._path_hashes(extended)
	for path: String in R6_SOURCE_PATHS:
		var absolute := ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(absolute):
			_abort("R6 capture source is missing: " + path.trim_prefix("res://"))
			continue
		if not result.has(path):
			_abort("R6 capture source was not included in inherited SHA256 collection: " + path.trim_prefix("res://"))
	return result


func _candidate_record() -> Dictionary:
	var candidate: Dictionary = super._candidate_record()
	var source_hashes: Dictionary = candidate.get("source_sha256", {}).duplicate(true)
	for path: String in R6_SOURCE_PATHS:
		var relative := path.trim_prefix("res://")
		var absolute := ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(absolute):
			_abort("R6 candidate source is missing: " + relative)
			continue
		source_hashes[relative] = FileAccess.get_sha256(absolute)
	candidate["capture_entry_script"] = R6_ENTRY_SCRIPT
	candidate["capture_script_inheritance"] = R6_CAPTURE_SCRIPT_CHAIN.duplicate()
	candidate["draw_layer_script"] = R6_DRAW_LAYER_SCRIPT_PATH
	candidate["source_sha256"] = source_hashes
	candidate["candidate_digest_sha256"] = _sha256_text(JSON.stringify(source_hashes))
	return candidate


func _mask_legend() -> Dictionary:
	var legend: Dictionary = super._mask_legend()
	legend = legend.duplicate(true)
	legend["ground"] = {
		"role": "ground",
		"encoding": "actual SharedTerrainSurface plus footing visuals drawn by the production courtyard-board method, without props or grid",
	}
	legend["ground_without_shadow"] = {
		"role": "ground_without_shadow",
		"encoding": "same actual SharedTerrainSurface plus production courtyard-board apron visuals with footing shadow omitted",
	}
	legend["contact_shadow"] = {
		"role": "contact_shadow",
		"encoding": "white polygons read from production courtyard-board wall_footing_visuals()['shadows']",
	}
	return legend


func _r6_board_geometry_record() -> Dictionary:
	if not is_instance_valid(_main_board):
		return {"status": "UNAVAILABLE", "reason": "The production board is not bound at manifest construction."}
	var result := {
		"status": "captured",
		"board_global_transform": _transform_array(_main_board.global_transform),
		"metadata_keys": R6_PROP_METADATA_KEYS.duplicate(),
		"prop_roots_with_r6_metadata": [],
	}
	var props_value: Variant = _main_board.get("_props")
	if not props_value is Array:
		result["status"] = "PROP_LIST_UNAVAILABLE"
		return result
	var metadata_records: Array[Dictionary] = []
	for prop_value: Variant in props_value:
		if not prop_value is Dictionary:
			continue
		var prop: Dictionary = prop_value
		var prop_node := prop.get("node") as Node2D
		if not is_instance_valid(prop_node):
			continue
		var metadata: Dictionary = {}
		if prop_node.has_meta("r6_height"):
			metadata["r6_height"] = float(prop_node.get_meta("r6_height"))
		if prop_node.has_meta("r6_side_count"):
			metadata["r6_side_count"] = int(prop_node.get_meta("r6_side_count"))
		if prop_node.has_meta("r6_break_levels"):
			metadata["r6_break_levels"] = int(prop_node.get_meta("r6_break_levels"))
		if metadata.is_empty():
			continue
		var logical_position := _logical_position(prop_node.global_position)
		metadata_records.append({
			"node_name": str(prop_node.name),
			"logical_position": [logical_position.x, logical_position.y],
			"global_transform": _transform_array(prop_node.global_transform),
			"metadata": metadata,
		})
	result["prop_roots_with_r6_metadata"] = metadata_records
	result["metadata_root_count"] = metadata_records.size()
	if metadata_records.is_empty():
		result["status"] = "NO_R6_PROP_METADATA_PRESENT"
	return result
