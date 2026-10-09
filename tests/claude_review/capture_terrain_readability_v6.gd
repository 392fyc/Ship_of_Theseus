extends "res://tests/claude_review/capture_terrain_readability_v5.gd"
## v6 changes only conservative exclusion-overlay raster alignment.

const CAPTURE_SCHEMA_V6 := "terrain-mask-capture/6"
const V6_MASK_QUANTIZATION_SCHEMA := "terrain-readability-mask-quantization-v6/1"
const V6_MASK_ALGORITHM := "native-pixel-center-half-open-cell-alignment-v1"
const V6_SOURCE_PATHS: PackedStringArray = [
	"res://tests/claude_review/capture_terrain_readability_v6.gd",
	"res://tests/claude_review/validate_terrain_readability_capture_v6.py",
	"res://tests/claude_review/test_terrain_readability_capture_v6.py",
	"res://dev_doc/ui-art-research/terrain-readability/capture-v6-task.md",
]
const V6_AXIS_EPSILON := 0.000001

var _v6_mask_draw_records: Array[Dictionary] = []
var _v6_mask_transform: Array = []
var _v6_mask_transform_consistent := true


func _add_exclusion_layers() -> void:
	_v6_mask_draw_records.clear()
	_v6_mask_transform = []
	_v6_mask_transform_consistent = true
	super._add_exclusion_layers()
	_v6_mask_transform = _transform_array((root as Viewport).get_final_transform())


func _add_screen_rect(canvas_layer: CanvasLayer, rect: Rect2, node_name: String) -> void:
	var final_transform: Transform2D = (root as Viewport).get_final_transform()
	var transform_record: Array = _transform_array(final_transform)
	if _v6_mask_transform.is_empty():
		_v6_mask_transform = transform_record.duplicate()
	elif not _v6_vectors_close(_v6_mask_transform, transform_record, V6_AXIS_EPSILON):
		_v6_mask_transform_consistent = false

	# Preserve the original call bounds, then clip in the same logical viewport
	# space used by the frozen v2 pixel-center validator.
	var nominal_rect := rect
	var root_clip := Rect2(Vector2.ZERO, Vector2(root.size))
	var clipped_rect := _v6_rect_intersection(nominal_rect, root_clip)
	clipped_rect = _v6_rect_intersection(clipped_rect, (root as Viewport).get_visible_rect())
	var quantized := _v6_quantize_rect(clipped_rect, final_transform)
	var record := {
		"node_name": node_name,
		"nominal_rect": _rect_array(nominal_rect),
		"logical_clipped_rect": _rect_array(clipped_rect),
		"final_transform": transform_record,
		"native_nominal_bounds": quantized.get("native_nominal_bounds", []),
		"native_pixel_cell_bounds": quantized.get("native_pixel_cell_bounds", []),
		"quantized_draw_rect": quantized.get("quantized_draw_rect", []),
		"quantization_status": quantized.get("status", "FAIL"),
		"draw_created": false,
	}
	_v6_mask_draw_records.append(record)
	if quantized.get("status") != "QUANTIZED":
		return

	var draw_rect: Rect2 = quantized["rect"]
	var blocker := ColorRect.new()
	blocker.name = node_name
	blocker.position = draw_rect.position
	blocker.size = draw_rect.size
	blocker.color = Color.WHITE
	blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_layer.add_child(blocker)
	_v6_mask_draw_records[_v6_mask_draw_records.size() - 1]["draw_created"] = true


func _v6_quantize_rect(rect: Rect2, final_transform: Transform2D) -> Dictionary:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return {
			"status": "CLIPPED_EMPTY",
			"native_nominal_bounds": [],
			"native_pixel_cell_bounds": [],
			"quantized_draw_rect": _rect_array(Rect2()),
			"rect": Rect2(),
		}
	if final_transform.x.x <= 0.0 or final_transform.y.y <= 0.0 \
			or absf(final_transform.x.y) > V6_AXIS_EPSILON \
			or absf(final_transform.y.x) > V6_AXIS_EPSILON:
		return {
			"status": "UNSUPPORTED_FINAL_TRANSFORM",
			"native_nominal_bounds": [],
			"native_pixel_cell_bounds": [],
			"quantized_draw_rect": [],
			"rect": Rect2(),
		}

	var top_left := final_transform * rect.position
	var top_right := final_transform * Vector2(rect.end.x, rect.position.y)
	var bottom_left := final_transform * Vector2(rect.position.x, rect.end.y)
	var bottom_right := final_transform * rect.end
	var native_left := minf(minf(top_left.x, top_right.x), minf(bottom_left.x, bottom_right.x))
	var native_top := minf(minf(top_left.y, top_right.y), minf(bottom_left.y, bottom_right.y))
	var native_right := maxf(maxf(top_left.x, top_right.x), maxf(bottom_left.x, bottom_right.x))
	var native_bottom := maxf(maxf(top_left.y, top_right.y), maxf(bottom_left.y, bottom_right.y))
	var cell_left := ceili(native_left - 0.5)
	var cell_top := ceili(native_top - 0.5)
	var cell_right := ceili(native_right - 0.5)
	var cell_bottom := ceili(native_bottom - 0.5)
	var native_bounds := [native_left, native_top, native_right, native_bottom]
	var cell_bounds := [cell_left, cell_top, cell_right, cell_bottom]
	if cell_right <= cell_left or cell_bottom <= cell_top:
		return {
			"status": "NO_NATIVE_PIXEL_CENTERS",
			"native_nominal_bounds": native_bounds,
			"native_pixel_cell_bounds": cell_bounds,
			"quantized_draw_rect": _rect_array(Rect2()),
			"rect": Rect2(),
		}

	var inverse_transform := final_transform.affine_inverse()
	var draw_position := inverse_transform * Vector2(float(cell_left), float(cell_top))
	var draw_end := inverse_transform * Vector2(float(cell_right), float(cell_bottom))
	var draw_rect := Rect2(draw_position, draw_end - draw_position)
	return {
		"status": "QUANTIZED",
		"native_nominal_bounds": native_bounds,
		"native_pixel_cell_bounds": cell_bounds,
		"quantized_draw_rect": _rect_array(draw_rect),
		"rect": draw_rect,
	}


func _v6_rect_intersection(rect: Rect2, clip: Rect2) -> Rect2:
	var left := maxf(rect.position.x, clip.position.x)
	var top := maxf(rect.position.y, clip.position.y)
	var right := minf(rect.end.x, clip.end.x)
	var bottom := minf(rect.end.y, clip.end.y)
	return Rect2(Vector2(left, top), Vector2(maxf(0.0, right - left), maxf(0.0, bottom - top)))


func _exclusion_record() -> Dictionary:
	var result: Dictionary = super._exclusion_record()
	var quantization_status := "CAPTURED"
	for record: Dictionary in _v6_mask_draw_records:
		if record.get("quantization_status") in ["UNSUPPORTED_FINAL_TRANSFORM", "NO_NATIVE_PIXEL_CENTERS"]:
			quantization_status = "FAIL"
	if not _v6_mask_transform_consistent or _v6_mask_draw_records.is_empty():
		quantization_status = "FAIL"
	result["mask_draw_quantization"] = {
		"schema_version": V6_MASK_QUANTIZATION_SCHEMA,
		"status": quantization_status,
		"algorithm": V6_MASK_ALGORITHM,
		"pixel_center_rule": "Native pixel centers are index + 0.5; logical source rectangles are half-open; align only the native cells whose centers satisfy the original source rectangle.",
		"source_bounds_are_unchanged": true,
		"source_validator": "tests/claude_review/validate_terrain_readability_capture_v2.py::_bound_coverage",
		"bounds_coordinate_space": "main Window visible logical viewport before the viewport stretch transform",
		"final_transform_source": "viewports.main.final_transform",
		"final_transform": _v6_mask_transform.duplicate(),
		"transform_consistent_across_draw_calls": _v6_mask_transform_consistent,
		"draw_call_count": _v6_mask_draw_records.size(),
		"records": _v6_mask_draw_records.duplicate(true),
	}
	return result


func _build_manifest_skeleton(map_data: Dictionary, resolution: Vector2i, case_name: String) -> Dictionary:
	var manifest: Dictionary = super._build_manifest_skeleton(map_data, resolution, case_name)
	manifest["schema_version"] = CAPTURE_SCHEMA_V6
	return manifest


func _path_hashes(paths: PackedStringArray) -> Dictionary:
	var extended: PackedStringArray = paths.duplicate()
	for path: String in V6_SOURCE_PATHS:
		if path not in extended:
			extended.append(path)
	return super._path_hashes(extended)


func _candidate_record() -> Dictionary:
	var candidate: Dictionary = super._candidate_record()
	var source_hashes: Dictionary = candidate.get("source_sha256", {}).duplicate(true)
	for path: String in V6_SOURCE_PATHS:
		var relative: String = path.trim_prefix("res://")
		var absolute: String = ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(absolute):
			_abort("v6 candidate source is missing: " + relative)
			continue
		source_hashes[relative] = FileAccess.get_sha256(absolute)
	candidate["source_sha256"] = source_hashes
	candidate["candidate_digest_sha256"] = _sha256_text(JSON.stringify(source_hashes))
	return candidate


func _v6_vectors_close(left: Array, right: Array, tolerance: float) -> bool:
	if left.size() != right.size():
		return false
	for index: int in left.size():
		if absf(float(left[index]) - float(right[index])) > tolerance:
			return false
	return true
