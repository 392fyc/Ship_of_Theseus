extends "res://tests/claude_review/capture_terrain_readability_r6.gd"
## Adds a thresholded occupancy pass while retaining every R6 capture byte path.

const R7_ENTRY_SCRIPT := "res://tests/claude_review/capture_terrain_readability_r7.gd"
const R7_OCCUPANCY_SHADER_PATH := "res://tests/claude_review/terrain_composite_occupancy.gdshader"
const R7_PART_PALETTE_POLICY := "production-terrain-part/2"
const R7_SOURCE_PATHS: PackedStringArray = [
	R7_ENTRY_SCRIPT,
	R7_OCCUPANCY_SHADER_PATH,
	"res://tests/claude_review/terrain_contour_v3.py",
	"res://tests/claude_review/validate_terrain_acceptance_v3.py",
	"res://tests/claude_review/test_terrain_acceptance_v3.py",
]
const R7_CONTROLS_SIZE := Vector2i(176, 40)
const R7_CAPTURE_SCRIPT_CHAIN: PackedStringArray = [
	R7_ENTRY_SCRIPT,
	"res://tests/claude_review/capture_terrain_readability_r6.gd",
	"res://tests/claude_review/capture_terrain_readability_v6_atlas.gd",
	"res://tests/claude_review/capture_terrain_readability_v6_regions_semantic_sidecar.gd",
	"res://tests/claude_review/capture_terrain_readability_v6_regions.gd",
	"res://tests/claude_review/capture_terrain_readability_v6.gd",
	"res://tests/claude_review/capture_terrain_readability.gd",
]

var _r7_occupancy_shader: Shader
var _r7_controls_viewport: SubViewport
var _r7_occupancy_record: Dictionary = {}
var _r7_controls_record: Dictionary = {}
var _r7_occupancy_material_bindings: Array[Dictionary] = []


func _create_semantic_sidecar_passes(resolution: Vector2i) -> bool:
	if not super._create_semantic_sidecar_passes(resolution):
		return false
	_r7_occupancy_shader = load(R7_OCCUPANCY_SHADER_PATH) as Shader
	if _r7_occupancy_shader == null \
			or not _r7_occupancy_shader.code.contains("render_mode blend_disabled") \
			or not _r7_occupancy_shader.code.contains("COLOR.a <= 0.5"):
		_abort("R7 composite occupancy shader is missing its blend-disabled alpha cutoff")
		return false
	var main_viewport := root as Viewport
	var source_layer := _main_board.get("_actor_layer") as Node2D if is_instance_valid(_main_board) else null
	if not is_instance_valid(source_layer):
		_abort("R7 occupancy pass has no live prop actor layer")
		return false
	var occupancy_viewport := _new_viewport("semantic_occupancy", resolution, true)
	occupancy_viewport.canvas_item_default_texture_filter = main_viewport.canvas_item_default_texture_filter
	occupancy_viewport.canvas_item_default_texture_repeat = main_viewport.canvas_item_default_texture_repeat
	occupancy_viewport.use_hdr_2d = false
	occupancy_viewport.msaa_2d = Viewport.MSAA_DISABLED
	root.add_child(occupancy_viewport)
	occupancy_viewport.canvas_transform = main_viewport.get_canvas_transform()
	_semantic_sidecar_viewports["occupancy"] = occupancy_viewport
	if not _semantic_build_layer(occupancy_viewport, source_layer, "occupancy"):
		_abort("R7 occupancy layer could not reproduce the recorded source draw leaves: " + "; ".join(_semantic_sidecar_errors))
		return false
	if not _r7_validate_occupancy_signatures():
		_abort("R7 occupancy source draw signatures differ from semantic_pair: " + "; ".join(_semantic_sidecar_errors))
		return false
	if not _r7_validate_occupancy_viewport(occupancy_viewport, resolution):
		return false
	return _r7_create_native_controls()


func _r7_validate_occupancy_signatures() -> bool:
	for record: Dictionary in _semantic_sidecar_instance_records:
		var signatures: Dictionary = record.get("draw_leaf_signatures", {})
		if JSON.stringify(signatures.get("pair", [])) != JSON.stringify(signatures.get("occupancy", [])):
			_semantic_sidecar_errors.append("occupancy draw leaves differ from semantic_pair for token %s" % str(record.get("token", "")))
	return _semantic_sidecar_errors.is_empty()


func _semantic_material(rgb: Array, part_code: int, mode: String) -> ShaderMaterial:
	if mode != "occupancy":
		return super._semantic_material(rgb, part_code, mode)
	var material := ShaderMaterial.new()
	material.shader = _r7_occupancy_shader
	material.set_shader_parameter("instance_token_rgb", Vector3(float(rgb[0]) / 255.0,
		float(rgb[1]) / 255.0, float(rgb[2]) / 255.0))
	return material


func _semantic_observed_material_records() -> Array[Dictionary]:
	var legacy_records: Array[Dictionary] = []
	_r7_occupancy_material_bindings.clear()
	for record: Dictionary in super._semantic_observed_material_records():
		if str(record.get("mode", "")) == "occupancy":
			var binding := record.duplicate(true)
			var stable_id := str(binding.get("stable_id", ""))
			var relative_path := str(binding.get("relative_path", ""))
			for instance: Dictionary in _semantic_sidecar_instance_records:
				if str(instance.get("stable_id", "")) != stable_id:
					continue
				var signatures: Dictionary = instance.get("draw_leaf_signatures", {})
				for leaf: Dictionary in signatures.get("occupancy", []):
					if str(leaf.get("relative_path", "")) == relative_path:
						binding["effective_alpha_source"] = leaf.get("alpha_source", "")
						break
				break
			_r7_occupancy_material_bindings.append(binding)
		else:
			legacy_records.append(record)
	return legacy_records


func _semantic_apply_tree_classification_map(source_root: Node2D, source_to_copy: Dictionary,
		record_index: int, mode: String) -> bool:
	if mode == "occupancy":
		# Occupancy samples only the unchanged original Sprite2D alpha. The reviewed
		# category map belongs to semantic_pair and is intentionally not sampled here.
		return true
	return super._semantic_apply_tree_classification_map(source_root, source_to_copy, record_index, mode)


func _r7_validate_occupancy_viewport(viewport: SubViewport, resolution: Vector2i) -> bool:
	var main := root as Viewport
	if viewport.size != resolution or viewport.size_2d_override_stretch != true \
			or viewport.size_2d_override != Vector2i(roundi(main.get_visible_rect().size.x), roundi(main.get_visible_rect().size.y)) \
			or viewport.transparent_bg != true or viewport.use_hdr_2d:
		_abort("R7 occupancy viewport is not transparent RGBA8-sized like the main capture")
		return false
	if not _numeric_arrays_equal(_transform_array(viewport.get_canvas_transform()), _transform_array(main.get_canvas_transform()), 0.001) \
			or not _numeric_arrays_equal(_transform_array(viewport.get_final_transform()), _transform_array(main.get_final_transform()), 0.001):
		_abort("R7 occupancy viewport transform differs from the frozen main view")
		return false
	return true


func _r7_create_native_controls() -> bool:
	_r7_controls_viewport = SubViewport.new()
	_r7_controls_viewport.name = "TerrainCapture_R7_OccupancyControls"
	_r7_controls_viewport.size = R7_CONTROLS_SIZE
	_r7_controls_viewport.size_2d_override = Vector2i.ZERO
	_r7_controls_viewport.size_2d_override_stretch = false
	_r7_controls_viewport.transparent_bg = true
	_r7_controls_viewport.use_hdr_2d = false
	_r7_controls_viewport.msaa_2d = Viewport.MSAA_DISABLED
	_r7_controls_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_r7_controls_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_r7_controls_viewport.gui_disable_input = true
	root.add_child(_r7_controls_viewport)
	var canvas := Node2D.new()
	canvas.name = "R7NativeOccupancyControls"
	_r7_controls_viewport.add_child(canvas)
	# N1: a same-token alpha-0.48 seam over an opaque body leaves the body token.
	_r7_add_control_rect(canvas, 101, Rect2(4, 6, 24, 24), 1.0, "N1_body")
	_r7_add_control_rect(canvas, 101, Rect2(10, 16, 12, 4), 0.48, "N1_seam")
	# N2: four same-token faces preserve a genuine empty center.
	_r7_add_control_rect(canvas, 102, Rect2(38, 6, 24, 6), 1.0, "N2_top")
	_r7_add_control_rect(canvas, 102, Rect2(38, 24, 24, 6), 1.0, "N2_bottom")
	_r7_add_control_rect(canvas, 102, Rect2(38, 12, 6, 12), 1.0, "N2_left")
	_r7_add_control_rect(canvas, 102, Rect2(56, 12, 6, 12), 1.0, "N2_right")
	# N3: another instance at alpha 0.4 cannot replace the underlying owner token.
	_r7_add_control_rect(canvas, 103, Rect2(72, 6, 24, 24), 1.0, "N3_body")
	_r7_add_control_rect(canvas, 106, Rect2(90, 6, 6, 24), 0.4, "N3_other_translucent")
	# N4: an opaque unknown item replaces the previous owner token.
	_r7_add_control_rect(canvas, 104, Rect2(106, 6, 24, 24), 1.0, "N4_body")
	_r7_add_control_rect(canvas, 199, Rect2(124, 6, 6, 24), 1.0, "N4_unknown_opaque")
	# N5: a standalone half-alpha draw writes no token.
	_r7_add_control_rect(canvas, 105, Rect2(140, 6, 24, 24), 0.5, "N5_translucent_only")
	return true


func _r7_add_control_rect(canvas: Node2D, token: int, rect: Rect2,
		alpha: float, node_name: String) -> void:
	var polygon := Polygon2D.new()
	polygon.name = node_name
	polygon.polygon = PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])
	polygon.color = Color.WHITE
	polygon.self_modulate = Color(1.0, 1.0, 1.0, alpha)
	polygon.material = _r7_occupancy_material(token)
	canvas.add_child(polygon)


func _r7_occupancy_material(token: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _r7_occupancy_shader
	var rgb := _semantic_token_rgb(token)
	material.set_shader_parameter("instance_token_rgb", Vector3(float(rgb[0]) / 255.0,
		float(rgb[1]) / 255.0, float(rgb[2]) / 255.0))
	return material


func _save_frame_images(images: Dictionary, case_directory: String, frame_id: int) -> Dictionary:
	if images.size() != SEMANTIC_EXPECTED_CAPTURE_IMAGE_COUNT:
		_abort("R7 must leave the frozen 12-image dictionary unchanged")
		return {}
	var occupancy_viewport := _semantic_sidecar_viewports.get("occupancy") as SubViewport
	if not is_instance_valid(occupancy_viewport) or not is_instance_valid(_r7_controls_viewport):
		_abort("R7 occupancy or native control viewport was released before same-frame readback")
		return {}
	var frames_before := Engine.get_frames_drawn()
	var process_before := Engine.get_process_frames()
	if frame_id != frames_before:
		_abort("R7 occupancy readback frame differs from the frozen 12-image callback")
		return {}
	var occupancy_image := occupancy_viewport.get_texture().get_image()
	var controls_image := _r7_controls_viewport.get_texture().get_image()
	var frames_after := Engine.get_frames_drawn()
	var process_after := Engine.get_process_frames()
	if occupancy_image == null or occupancy_image.is_empty() \
			or controls_image == null or controls_image.is_empty():
		_abort("R7 occupancy or native control readback is empty")
		return {}
	if occupancy_image.get_size() != root.size or controls_image.get_size() != R7_CONTROLS_SIZE:
		_abort("R7 occupancy/control image size differs from its recorded native viewport")
		return {}
	if frames_before != frames_after or frames_after != frame_id or process_before != process_after:
		_abort("R7 occupancy/control readback crossed the frozen frame/process boundary")
		return {}
	occupancy_image.convert(Image.FORMAT_RGBA8)
	controls_image.convert(Image.FORMAT_RGBA8)
	var occupancy_path := case_directory.path_join("composite_occupancy.png")
	var controls_path := case_directory.path_join("composite_occupancy_controls.png")
	if occupancy_image.save_png(occupancy_path) != OK or controls_image.save_png(controls_path) != OK:
		_abort("R7 occupancy/control PNG could not be saved")
		return {}
	var controls_check := _r7_native_control_samples(controls_image)
	if not controls_check.get("pass", false):
		_abort("R7 native occupancy N1-N5 control failed: " + JSON.stringify(controls_check.get("errors", [])))
		return {}
	var candidate := _candidate_record()
	_r7_occupancy_record = {
		"schema_version": "terrain-composite-occupancy/1",
		"role": "composite_occupancy",
		"image": _semantic_image_record("composite_occupancy", occupancy_image, occupancy_path, frame_id),
		"viewport": _viewport_record(occupancy_viewport, occupancy_image),
		"candidate_source_sha256": candidate.get("source_sha256", {}).duplicate(true),
		"capture_candidate_digest_sha256": candidate.get("candidate_digest_sha256", ""),
		"callback": "RenderingServer.frame_post_draw",
		"frame_id": frame_id,
		"same_frame": true,
		"effective_alpha_rule": "discard when effective COLOR.a <= 0.5; write the instance token when COLOR.a > 0.5",
		"blend_mode": "blend_disabled",
		"draw_order": "actual _props source order, then each source hierarchy's original draw-leaf order",
		"last_qualifying_draw_owns_pixel": true,
		"unknown_props_keep_nonzero_tokens": true,
		"source_alpha_coverage_unchanged": true,
		"source_alpha_uncertainty_unchanged": true,
		"shader_path": R7_OCCUPANCY_SHADER_PATH,
		"shader_source_sha256": candidate.get("source_sha256", {}).get(R7_OCCUPANCY_SHADER_PATH.trim_prefix("res://"), ""),
	}
	_r7_controls_record = {
		"schema_version": "terrain-composite-occupancy-controls/1",
		"role": "composite_occupancy_controls",
		"image": _semantic_image_record("native_occupancy_controls", controls_image, controls_path, frame_id),
		"viewport": _viewport_record(_r7_controls_viewport, controls_image),
		"candidate_source_sha256": candidate.get("source_sha256", {}).duplicate(true),
		"capture_candidate_digest_sha256": candidate.get("candidate_digest_sha256", ""),
		"callback": "RenderingServer.frame_post_draw",
		"frame_id": frame_id,
		"same_frame": true,
		"samples": controls_check.get("samples", []),
		"pass": true,
	}
	var result: Dictionary = super._save_frame_images(images, case_directory, frame_id)
	_r7_occupancy_record["material_bindings"] = _r7_occupancy_material_bindings.duplicate(true)
	_r7_occupancy_material_bindings.clear()
	return result


func _r7_native_control_samples(image: Image) -> Dictionary:
	var samples: Array[Dictionary] = []
	var errors: Array[String] = []
	var expected_samples: Array[Dictionary] = [
		{"case": "N1_same_instance_alpha_0_48_seam", "xy": [6, 8], "token": 101, "effective_alpha": 1.0},
		{"case": "N1_same_instance_alpha_0_48_seam", "xy": [16, 18], "token": 101, "effective_alpha": 0.48},
		{"case": "N2_true_hole", "xy": [40, 8], "token": 102, "effective_alpha": 1.0},
		{"case": "N2_true_hole", "xy": [50, 18], "token": 0, "effective_alpha": 0.0},
		{"case": "N3_other_alpha_0_4_overlay", "xy": [76, 10], "token": 103, "effective_alpha": 1.0},
		{"case": "N3_other_alpha_0_4_overlay", "xy": [92, 18], "token": 103, "effective_alpha": 0.4},
		{"case": "N4_unknown_opaque_overlay", "xy": [110, 10], "token": 104, "effective_alpha": 1.0},
		{"case": "N4_unknown_opaque_overlay", "xy": [126, 18], "token": 199, "effective_alpha": 1.0},
		{"case": "N5_standalone_alpha_0_5", "xy": [152, 18], "token": 0, "effective_alpha": 0.5},
	]
	var bytes := image.get_data()
	for expected: Dictionary in expected_samples:
		var point: Array = expected["xy"]
		var x := int(point[0])
		var y := int(point[1])
		var offset := (y * image.get_width() + x) * 4
		var rgba := [int(bytes[offset]), int(bytes[offset + 1]), int(bytes[offset + 2]), int(bytes[offset + 3])]
		var token: int = (rgba[0] << 16) | (rgba[1] << 8) | rgba[2] if rgba[3] == 255 else 0
		var matched: bool = token == int(expected["token"])
		if not matched:
			errors.append("%s sample %s expected token %d, got %d" % [expected["case"], str(point), int(expected["token"]), token])
		samples.append({"case": expected["case"], "xy": point.duplicate(),
			"expected_token": int(expected["token"]), "observed_rgba": rgba,
			"observed_token": token, "matched": matched,
			"polygon_color_a": 1.0,
			"self_modulate_a": float(expected["effective_alpha"]),
			"effective_alpha_expected": float(expected["effective_alpha"]),
			"effective_alpha_input": "incoming COLOR.a from Polygon2D.color * CanvasItem.self_modulate"})
	return {"pass": errors.is_empty(), "errors": errors, "samples": samples}


func _build_manifest_skeleton(map_data: Dictionary, resolution: Vector2i, case_name: String) -> Dictionary:
	var manifest: Dictionary = super._build_manifest_skeleton(map_data, resolution, case_name)
	var capture_config: Dictionary = manifest.get("capture_config", {}).duplicate(true)
	capture_config["capture_entry_script"] = R7_ENTRY_SCRIPT
	capture_config["capture_script_inheritance"] = R7_CAPTURE_SCRIPT_CHAIN.duplicate()
	capture_config["composite_occupancy_shader"] = R7_OCCUPANCY_SHADER_PATH
	capture_config["composite_occupancy_rule"] = "last draw item with effective COLOR.a > 0.5 owns the pixel; blend_disabled"
	capture_config["r7_board_geometry_metadata"] = _r7_board_geometry_record()
	manifest["capture_config"] = capture_config
	return manifest


func _path_hashes(paths: PackedStringArray) -> Dictionary:
	var extended: PackedStringArray = paths.duplicate()
	for path: String in R7_SOURCE_PATHS:
		if path not in extended:
			extended.append(path)
	return super._path_hashes(extended)


func _candidate_record() -> Dictionary:
	var candidate: Dictionary = super._candidate_record()
	var source_hashes: Dictionary = candidate.get("source_sha256", {}).duplicate(true)
	for path: String in R7_SOURCE_PATHS:
		var relative := path.trim_prefix("res://")
		var absolute := ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(absolute):
			_abort("R7 occupancy source is missing: " + relative)
			continue
		source_hashes[relative] = FileAccess.get_sha256(absolute)
	candidate["capture_entry_script"] = R7_ENTRY_SCRIPT
	candidate["capture_script_inheritance"] = R7_CAPTURE_SCRIPT_CHAIN.duplicate()
	candidate["occupancy_shader"] = R7_OCCUPANCY_SHADER_PATH
	candidate["part_palette_policy"] = R7_PART_PALETTE_POLICY
	candidate["source_sha256"] = source_hashes
	candidate["candidate_digest_sha256"] = _sha256_text(JSON.stringify(source_hashes))
	return candidate


func _semantic_write_json(path: String, value: Dictionary) -> bool:
	if path.get_file() == SEMANTIC_SIDECAR_MANIFEST:
		if _r7_occupancy_record.is_empty() or _r7_controls_record.is_empty():
			_abort("R7 occupancy/control source-bound readback records are missing")
			return false
		value["composite_occupancy"] = _r7_occupancy_record.duplicate(true)
		value["native_occupancy_controls"] = _r7_controls_record.duplicate(true)
	return super._semantic_write_json(path, value)


func _semantic_validate_sidecar_readback_record() -> bool:
	return super._semantic_validate_sidecar_readback_record() \
		and not _r7_occupancy_record.is_empty() and not _r7_controls_record.is_empty()


func _close_sessions_and_passes() -> void:
	if is_instance_valid(_r7_controls_viewport):
		_r7_controls_viewport.queue_free()
	_r7_controls_viewport = null
	_r7_occupancy_record.clear()
	_r7_controls_record.clear()
	_r7_occupancy_material_bindings.clear()
	super._close_sessions_and_passes()


## R7 stone geometry labels bind the authored part to the captured draw leaf.
## Both part-ID and semantic passes use the live leaf's structural role.
func _r7_stone_part(leaf: CanvasItem, kind: String) -> String:
	if kind not in ["wall", "pillar"] or not leaf.has_meta("terrain_part"):
		return ""
	var part_name := str(leaf.get_meta("terrain_part"))
	var allowed: Array = ["wall_side", "wall_top", "wall_outline"] if kind == "wall" else ["pillar_base", "pillar_side", "pillar_top", "wall_outline"]
	if part_name not in allowed or not SEMANTIC_PART_CODES.has(part_name):
		_abort("R7 stone draw has an invalid terrain_part: " + part_name)
		return ""
	return part_name


func _classify_wall_child(parent: Node2D, polygon: Polygon2D, kind: String) -> String:
	var part_name := _r7_stone_part(polygon, kind)
	if not part_name.is_empty():
		return part_name
	return super._classify_wall_child(parent, polygon, kind)


func _semantic_part_for_leaf(leaf: CanvasItem, prop_root: Node2D, kind: String) -> Dictionary:
	var part_name := _r7_stone_part(leaf, kind)
	if not part_name.is_empty():
		return {"name": part_name, "code": int(SEMANTIC_PART_CODES[part_name]),
			"source": "actual production terrain_part metadata on the captured draw leaf"}
	return super._semantic_part_for_leaf(leaf, prop_root, kind)


func _apply_part_colors(source: Node2D, copy: Node2D) -> Dictionary:
	var kind := _classify_prop(source)
	if kind not in ["wall", "pillar"]:
		return super._apply_part_colors(source, copy)
	if source.get_child_count() != copy.get_child_count():
		return {"status": "FAIL", "reason": "stone source/copy topology differs"}
	var expected_colors: Dictionary = {}
	var hidden_paths: Dictionary = {}
	for index: int in source.get_child_count():
		var source_child := source.get_child(index) as CanvasItem
		var copy_child := copy.get_child(index) as CanvasItem
		if source_child == null or copy_child == null:
			continue
		if source_child is Polygon2D or source_child is Line2D:
			var part_name := _r7_stone_part(source_child, kind)
			if part_name.is_empty():
				return {"status": "FAIL", "reason": "stone part-ID draw lacks terrain_part", "path": str(index)}
			var color: Color = PART_COLORS[part_name]
			_set_flat_mask_material(copy_child, color)
			expected_colors[str(index)] = color
		else:
			copy_child.visible = false
			hidden_paths[str(index)] = true
	return _validate_flat_mask_clone(source, copy, expected_colors, hidden_paths, "part_ids")


func _parts_for_instance(node: Node2D, kind: String) -> Dictionary:
	var result: Dictionary = super._parts_for_instance(node, kind)
	if kind not in ["wall", "pillar"]:
		return result
	var parts: Array = result.get("parts", [])
	var index := 0
	for child: Node in node.get_children():
		if child is not Polygon2D and child is not Line2D:
			continue
		if index >= parts.size():
			_abort("R7 stone part inventory is shorter than its draw leaves")
			return result
		var canvas := child as CanvasItem
		var part_name := _r7_stone_part(canvas, kind)
		if part_name.is_empty():
			_abort("R7 stone draw is missing its production terrain_part metadata")
			return result
		var part: Dictionary = parts[index]
		part["production_structural_role"] = part_name
		part["classification_source"] = "actual production terrain_part metadata on the captured draw leaf"
		if child is Line2D:
			part["role"] = part_name
			part["color"] = _hex_color(PART_COLORS[part_name])
			part["part_ids_line_policy"] = R7_PART_PALETTE_POLICY
		parts[index] = part
		index += 1
	result["parts"] = parts
	result["structural_classification"] = "R7 production terrain_part metadata"
	result["part_palette_policy"] = R7_PART_PALETTE_POLICY
	return result


func _r7_board_geometry_record() -> Dictionary:
	var result := {"status": "captured", "prop_roots": []}
	if not is_instance_valid(_main_board):
		_abort("R7 geometry metadata has no live production board")
		return {"status": "UNAVAILABLE", "prop_roots": []}
	var props_value: Variant = _main_board.get("_props")
	if not props_value is Array:
		_abort("R7 geometry metadata has no production prop list")
		return {"status": "PROP_LIST_UNAVAILABLE", "prop_roots": []}
	var records: Array[Dictionary] = []
	for prop_value: Variant in props_value:
		if not prop_value is Dictionary:
			continue
		var prop: Dictionary = prop_value
		var prop_node := prop.get("node") as Node2D
		if not is_instance_valid(prop_node) or not prop_node.has_meta("r7_height"):
			continue
		var logical_position := _logical_position(prop_node.global_position)
		var draw_leaf_count := 0
		for child: Node in prop_node.get_children():
			if child is Polygon2D or child is Line2D:
				draw_leaf_count += 1
		records.append({"node_name": str(prop_node.name),
			"logical_position": [logical_position.x, logical_position.y],
			"global_transform": _transform_array(prop_node.global_transform),
			"r7_height": float(prop_node.get_meta("r7_height")),
			"r7_height_level": int(prop_node.get_meta("r7_height_level")),
			"draw_leaf_count": draw_leaf_count})
	result["prop_roots"] = records
	return result
