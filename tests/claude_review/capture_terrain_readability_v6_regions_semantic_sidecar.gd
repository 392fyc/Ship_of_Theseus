extends "res://tests/claude_review/capture_terrain_readability_v6_regions.gd"
## Adds independently rendered byte-exact labels and source-alpha coverage beside frozen V6 images.

const SEMANTIC_SIDECAR_SCHEMA := "terrain-semantic-sidecar/1"
const SEMANTIC_SIDECAR_SHADER_PATH := "res://tests/claude_review/terrain_semantic_sidecar.gdshader"
const SEMANTIC_SIDECAR_MANIFEST := "semantic-sidecar-manifest.json"
const SEMANTIC_SIDECAR_SOURCE_PATHS: PackedStringArray = [
	"res://tests/claude_review/capture_terrain_readability_v6_regions_semantic_sidecar.gd",
	SEMANTIC_SIDECAR_SHADER_PATH,
	"res://tests/claude_review/validate_terrain_semantic_sidecar.py",
	"res://tests/claude_review/test_terrain_semantic_sidecar.py",
	"res://dev_doc/ui-art-research/terrain-readability/semantic-sidecar-task.md",
]
const SEMANTIC_PART_CODES := {
	"wall_top": 1,
	"wall_side": 2,
	"pillar_top": 3,
	"pillar_side": 4,
	"pillar_base": 5,
	"wall_outline": 6,
	"tree_crown": 7,
	"tree_dark_side": 8,
	"tree_outline": 9,
	"whole_instance": 10,
	"unknown": 255,
}
const SEMANTIC_UNKNOWN_PART_CODE := 255
const SEMANTIC_MAX_TOKEN := 16777215
const SEMANTIC_EXPECTED_CAPTURE_IMAGE_COUNT := 12
const SEMANTIC_TREE_REGION_ORDER: PackedStringArray = ["crown", "dark_side", "outline"]
const SEMANTIC_WRITE_PROBE_SIZE := Vector2i(128, 16)
const SEMANTIC_BLEND_FENCE_SHADER := "shader_type canvas_item;\nrender_mode unshaded, blend_mix;\nvoid fragment() { COLOR = vec4(0.0); }\n"

var _semantic_sidecar_shader: Shader
var _semantic_sidecar_viewports: Dictionary = {}
var _semantic_sidecar_draw_order: Array[Node2D] = []
var _semantic_sidecar_runtime_records: Array[Dictionary] = []
var _semantic_measurement_view_state: Dictionary = {}
var _semantic_sidecar_record_index_by_node_id: Dictionary = {}
var _semantic_sidecar_instance_records: Array[Dictionary] = []
var _semantic_sidecar_readback_record: Dictionary = {}
var _semantic_sidecar_errors: Array[String] = []
var _semantic_tree_classification_image: Image
var _semantic_tree_classification_texture: ImageTexture
var _semantic_tree_classification_record: Dictionary = {}
var _semantic_tree_classification_cache_key := ""
var _semantic_write_probe_viewport: SubViewport
var _semantic_write_probe_samples: Array[Dictionary] = []
var _semantic_material_observations: Array[Dictionary] = []
var _semantic_blend_fence_material: ShaderMaterial
var _semantic_blend_fence_observations: Array[Dictionary] = []


func _run() -> void:
	# Structural checks intentionally retain the inherited six-case traversal.
	# A native invocation must be one process per map-size/resolution so the
	# caller can read the pilot before deciding whether to start later cases.
	if _headless_check:
		await super._run()
		return
	if _map_sizes.size() != 1 or _resolutions.size() != 1:
		_abort("Native semantic-sidecar capture accepts exactly one map size and one resolution per process; run the 10x10/1280x720 pilot, validate it with --phase=pilot, then start each remaining case in a separate process.")
		return
	await super._run()


func _create_capture_passes(resolution: Vector2i, profile: Dictionary) -> bool:
	if not await super._create_capture_passes(resolution, profile):
		return false
	return _create_semantic_sidecar_passes(resolution)


func _establish_frozen_capture_state() -> bool:
	# Use the formal cancellation action, retaining both units and HighlightLayer.
	# Range-tinted props are unsuitable for the static material comparison state.
	_semantic_measurement_view_state = {"action": "ui_cancel", "synthetic_input": true,
		"camera_changed": false, "units_hidden": false, "sessions": []}
	for session: Node2D in [_main_session, _reconstruction_session]:
		var manager := session.get("manager") as Node
		if not is_instance_valid(manager) or not manager.has_method("_input"):
			_abort("formal cancellation input is unavailable")
			return false
		var selected_before: bool = is_instance_valid(manager.get("selected_unit"))
		var cancel := InputEventAction.new()
		cancel.action = "ui_cancel"
		cancel.pressed = true
		manager.call("_input", cancel)
		_semantic_measurement_view_state["sessions"].append({
			"selected_before": selected_before,
			"selected_after": is_instance_valid(manager.get("selected_unit")),
		})
	# Settle deferred range removal and the production alpha recovery. No prop
	# alpha, unit location, terrain, camera or material is assigned by this step.
	await _frames(16)
	for session: Node2D in [_main_session, _reconstruction_session]:
		var manager := session.get("manager") as Node
		var layer := manager.get("highlight_layer") as Node2D
		if is_instance_valid(manager.get("selected_unit")) or not is_instance_valid(layer) \
				or not layer.is_visible_in_tree() or layer.get_child_count() != 0:
			_abort("ui_cancel did not settle an unselected state with visible empty HighlightLayer")
			return false
	_semantic_measurement_view_state["settle_process_frames"] = 16
	_semantic_measurement_view_state["highlight_layers_visible_and_empty"] = true
	return await super._establish_frozen_capture_state()


func _create_semantic_sidecar_passes(resolution: Vector2i) -> bool:
	_semantic_sidecar_shader = load(SEMANTIC_SIDECAR_SHADER_PATH) as Shader
	if _semantic_sidecar_shader == null or not _semantic_sidecar_shader.code.contains("render_mode blend_disabled"):
		_abort("semantic sidecar shader is missing or does not use blend_disabled")
		return false
	_semantic_sidecar_errors.clear()
	_semantic_blend_fence_observations.clear()
	var fence_shader := Shader.new()
	fence_shader.code = SEMANTIC_BLEND_FENCE_SHADER
	_semantic_blend_fence_material = ShaderMaterial.new()
	_semantic_blend_fence_material.shader = fence_shader
	if not _semantic_prepare_inventory():
		_abort("SEMANTIC_SIDECAR_NOT_TESTED_INPUT_INVENTORY: " + "; ".join(_semantic_sidecar_errors))
		return false
	var main_viewport := root as Viewport
	var source_layer := _main_board.get("_actor_layer") as Node2D if is_instance_valid(_main_board) else null
	if not is_instance_valid(source_layer):
		_abort("SEMANTIC_SIDECAR_NOT_TESTED_INPUT_LAYER: actual prop actor layer is unavailable")
		return false
	if not _semantic_validate_actor_ancestors(source_layer):
		_abort("SEMANTIC_SIDECAR_NOT_TESTED_UNSUPPORTED_ALPHA_ANCESTOR: " + "; ".join(_semantic_sidecar_errors))
		return false
	for mode: String in ["pair", "coverage"]:
		var viewport := _new_viewport("semantic_%s" % mode, resolution, true)
		viewport.canvas_item_default_texture_filter = main_viewport.canvas_item_default_texture_filter
		viewport.canvas_item_default_texture_repeat = main_viewport.canvas_item_default_texture_repeat
		viewport.use_hdr_2d = false
		viewport.msaa_2d = Viewport.MSAA_DISABLED
		root.add_child(viewport)
		viewport.canvas_transform = main_viewport.get_canvas_transform()
		_semantic_sidecar_viewports[mode] = viewport
		if not _semantic_build_layer(viewport, source_layer, mode):
			_abort("SEMANTIC_SIDECAR_NOT_TESTED_UNSUPPORTED_ALPHA_OR_DRAW_PATH: " + "; ".join(_semantic_sidecar_errors))
			return false
	if not _semantic_validate_parallel_inputs():
		_abort("SEMANTIC_SIDECAR_NOT_TESTED_PARALLEL_INPUT_MISMATCH: " + "; ".join(_semantic_sidecar_errors))
		return false
	if not _semantic_validate_viewports(resolution):
		_abort("SEMANTIC_SIDECAR_NOT_TESTED_VIEWPORT_MAPPING: " + "; ".join(_semantic_sidecar_errors))
		return false
	_create_semantic_write_probe()
	return true


func _semantic_prepare_inventory() -> bool:
	_semantic_sidecar_draw_order.clear()
	_semantic_sidecar_runtime_records.clear()
	_semantic_sidecar_record_index_by_node_id.clear()
	_semantic_sidecar_instance_records.clear()
	_semantic_tree_classification_image = null
	_semantic_tree_classification_texture = null
	_semantic_tree_classification_record.clear()
	_semantic_tree_classification_cache_key = ""
	_semantic_material_observations.clear()
	var specs: Variant = _main_board.get("_props") if is_instance_valid(_main_board) else null
	if not specs is Array:
		_semantic_sidecar_errors.append("CourtyardBoardView._props is not an Array")
		return false
	var raw_records: Array[Dictionary] = []
	var occurrences: Dictionary = {}
	for spec_value: Variant in specs:
		if not spec_value is Dictionary:
			continue
		var node := (spec_value as Dictionary).get("node") as Node2D
		if not is_instance_valid(node) or not node.is_visible_in_tree():
			continue
		var classified_kind := _classify_prop(node)
		var semantic_kind := classified_kind if not classified_kind.is_empty() else "unknown"
		var logical := _logical_position(node.global_position)
		var stable_base := _stable_id(semantic_kind, logical)
		var occurrence := int(occurrences.get(stable_base, 0)) + 1
		occurrences[stable_base] = occurrence
		var stable_id := stable_base if occurrence == 1 else "%s#%d" % [stable_base, occurrence]
		var leaf_inputs: Array[Dictionary] = []
		_semantic_collect_source_inputs(node, "", node, leaf_inputs)
		if leaf_inputs.is_empty():
			_semantic_sidecar_errors.append("visible prop has no supported draw leaves: " + str(node.get_path()))
		raw_records.append({
			"source_node": node,
			"source_node_id": node.get_instance_id(),
			"stable_id": stable_id,
			"classified_kind": classified_kind,
			"type": semantic_kind,
			"logical_position": _point_array(logical),
			"duplicate_occurrence": occurrence,
			"source_order": raw_records.size(),
			"leaf_inputs": leaf_inputs,
	})
	if not _semantic_sidecar_errors.is_empty():
		return false
	if raw_records.is_empty():
		_semantic_sidecar_errors.append("no visible props were found in the actual _props list")
		return false
	raw_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["stable_id"]) < str(b["stable_id"]))
	if raw_records.size() > SEMANTIC_MAX_TOKEN:
		_semantic_sidecar_errors.append("visible prop count exceeds the 24-bit token capacity")
		return false
	for index: int in raw_records.size():
		var raw: Dictionary = raw_records[index]
		var node := raw["source_node"] as Node2D
		var token := index + 1
		var token_bytes := _semantic_token_rgb(token)
		var record := {
			"stable_id": str(raw["stable_id"]),
			"token": token,
			"token_rgb": token_bytes,
			"type": str(raw["type"]),
			"classified_kind": str(raw["classified_kind"]),
			"source_node_path": str(node.get_path()),
			"source_node_name": str(node.name),
			"source_node_class": node.get_class(),
			"logical_position": raw["logical_position"],
			"source_order": int(raw["source_order"]),
			"duplicate_occurrence": int(raw["duplicate_occurrence"]),
			"source_visible": node.is_visible_in_tree(),
			"source_global_transform": _transform_array(node.global_transform),
			"source_modulate": _color_array(node.modulate),
			"source_self_modulate": _color_array(node.self_modulate),
			"source_texture_filter": int(node.texture_filter),
			"source_texture_repeat": int(node.texture_repeat),
			"classification_source": _classification_source(node, str(raw["classified_kind"])) if not str(raw["classified_kind"]).is_empty() else "unknown actual visible _props item; kept in original _props sibling order with dedicated nonzero unknown part code",
			"draw_leaf_inputs": raw["leaf_inputs"],
			"draw_leaf_signatures": {"pair": [], "coverage": []},
			"tree_region_inputs": _semantic_tree_region_input_record(node) if str(raw["type"]) == "tree" else {},
		}
		_semantic_sidecar_draw_order.append(node)
		_semantic_sidecar_record_index_by_node_id[int(raw["source_node_id"])] = _semantic_sidecar_instance_records.size()
		_semantic_sidecar_runtime_records.append({"source": node, "record": record})
		_semantic_sidecar_instance_records.append(record)
	_semantic_sidecar_draw_order.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		var a_record_index := int(_semantic_sidecar_record_index_by_node_id.get(a.get_instance_id(), -1))
		var b_record_index := int(_semantic_sidecar_record_index_by_node_id.get(b.get_instance_id(), -1))
		return int(_semantic_sidecar_instance_records[a_record_index].get("source_order", -1)) \
			< int(_semantic_sidecar_instance_records[b_record_index].get("source_order", -1)))
	return true


func _semantic_collect_source_inputs(root_node: Node, path: String, prop_root: Node2D,
		target: Array[Dictionary]) -> void:
	if root_node is CanvasItem:
		var canvas := root_node as CanvasItem
		if canvas.is_visible_in_tree():
			if canvas.material != null:
				_semantic_sidecar_errors.append("custom CanvasItem material has an unsupported semantic alpha path at " + str(root_node.get_path()))
			if _semantic_script_has_custom_draw(root_node):
				_semantic_sidecar_errors.append("custom _draw source alpha cannot be forwarded by the sidecar shader at " + str(root_node.get_path()))
			if root_node is Sprite2D or root_node is Polygon2D or root_node is Line2D:
				target.append(_semantic_draw_leaf_input(root_node as CanvasItem, path))
			elif not root_node is Node2D or root_node.get_child_count() == 0:
				_semantic_sidecar_errors.append("unsupported visible CanvasItem draw leaf %s (%s)" % [str(root_node.get_path()), root_node.get_class()])
	for child_index: int in root_node.get_child_count():
		var child := root_node.get_child(child_index)
		var child_path := str(child_index) if path.is_empty() else path + "/" + str(child_index)
		_semantic_collect_source_inputs(child, child_path, prop_root, target)


func _semantic_script_has_custom_draw(node: Node) -> bool:
	var script := node.get_script() as Script
	if script == null:
		return false
	var source := script.get_source_code()
	var expression := RegEx.new()
	if expression.compile("(?m)^\\s*func\\s+_draw\\s*\\(") != OK:
		return false
	return expression.search(source) != null


func _semantic_draw_leaf_input(canvas: CanvasItem, relative_path: String) -> Dictionary:
	var record := {
		"relative_path": relative_path,
		"node_name": str(canvas.name),
		"node_class": canvas.get_class(),
		"visible": canvas.is_visible_in_tree(),
		"global_transform": _transform_array((canvas as Node2D).global_transform) if canvas is Node2D else [],
		"modulate": _color_array(canvas.modulate),
		"self_modulate": _color_array(canvas.self_modulate),
		"texture_filter": int(canvas.texture_filter),
		"texture_repeat": int(canvas.texture_repeat),
		"alpha_source": "incoming CanvasItem COLOR.a after source texture/primitive alpha and inherited modulation",
		"draw_bounds_local": _semantic_draw_bounds_local(canvas),
		"material_class": canvas.material.get_class() if canvas.material != null else "",
		"ancestor_canvas_inputs": _semantic_ancestor_canvas_inputs(canvas),
	}
	if canvas is Sprite2D:
		var sprite := canvas as Sprite2D
		record["texture"] = _texture_record(sprite.texture)
		record["centered"] = sprite.centered
		record["offset"] = _point_array(sprite.offset)
		record["flip_h"] = sprite.flip_h
		record["flip_v"] = sprite.flip_v
		record["frame"] = sprite.frame
		record["region_enabled"] = sprite.region_enabled
		record["region_rect"] = _rect_array(sprite.region_rect)
	elif canvas is Polygon2D:
		var polygon := canvas as Polygon2D
		record["texture"] = _texture_record(polygon.texture)
		record["polygon"] = _semantic_vector_array(polygon.polygon)
		record["uv"] = _semantic_vector_array(polygon.uv)
		record["primitive_color"] = _color_array(polygon.color)
	elif canvas is Line2D:
		var line := canvas as Line2D
		record["points"] = _semantic_vector_array(line.points)
		record["width"] = line.width
		record["default_color"] = _color_array(line.default_color)
		record["texture"] = _texture_record(line.texture)
		record["texture_mode"] = int(line.texture_mode)
	return record


func _semantic_draw_bounds_local(canvas: CanvasItem) -> Array:
	# Conservative primitive bounds are independent of the encoded labels. They
	# only identify unambiguous registration anchors, never measurement samples.
	if canvas is Sprite2D:
		return _rect_array((canvas as Sprite2D).get_rect())
	var points := PackedVector2Array()
	var margin := 0.0
	if canvas is Polygon2D:
		points = (canvas as Polygon2D).polygon
	elif canvas is Line2D:
		var line := canvas as Line2D
		points = line.points
		margin = line.width * maxf(1.0, line.sharp_limit)
	if points.is_empty():
		return []
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return _rect_array(bounds.grow(margin))


func _semantic_ancestor_canvas_inputs(canvas: CanvasItem) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cursor: Node = canvas
	while cursor != null:
		if cursor is CanvasItem:
			var item := cursor as CanvasItem
			result.append({
				"node_path": str(cursor.get_path()),
				"node_class": cursor.get_class(),
				"visible": item.is_visible_in_tree(),
				"modulate": _color_array(item.modulate),
				"self_modulate": _color_array(item.self_modulate),
				"texture_filter": int(item.texture_filter),
				"texture_repeat": int(item.texture_repeat),
			})
		if cursor == _main_session:
			break
		cursor = cursor.get_parent()
	return result


func _semantic_validate_actor_ancestors(source_layer: Node2D) -> bool:
	var cursor: Node = source_layer
	while cursor != null:
		if cursor is CanvasItem and (cursor as CanvasItem).material != null:
			_semantic_sidecar_errors.append("custom material on prop actor ancestor has unsupported alpha behavior: " + str(cursor.get_path()))
		if cursor == _main_session:
			break
		cursor = cursor.get_parent()
	return _semantic_sidecar_errors.is_empty()


func _semantic_actor_inherited_modulate(source_layer: Node2D) -> Color:
	var combined := Color.WHITE
	var cursor: Node = source_layer
	while cursor != null:
		if cursor is CanvasItem:
			combined = combined * (cursor as CanvasItem).modulate
		if cursor == _main_session:
			break
		cursor = cursor.get_parent()
	return combined


func _semantic_vector_array(points: PackedVector2Array) -> Array[Array]:
	var result: Array[Array] = []
	for point: Vector2 in points:
		result.append(_point_array(point))
	return result


func _semantic_build_layer(viewport: SubViewport, source_layer: Node2D, mode: String) -> bool:
	var canvas := Node2D.new()
	canvas.name = "SemanticCanvas_%s" % mode
	canvas.global_transform = source_layer.global_transform
	canvas.modulate = _semantic_actor_inherited_modulate(source_layer)
	canvas.self_modulate = Color.WHITE
	canvas.visible = source_layer.visible
	canvas.z_index = source_layer.z_index
	canvas.z_as_relative = source_layer.z_as_relative
	canvas.y_sort_enabled = source_layer.y_sort_enabled
	canvas.texture_filter = source_layer.texture_filter
	canvas.texture_repeat = source_layer.texture_repeat
	viewport.add_child(canvas)
	for source: Node2D in _semantic_sidecar_draw_order:
		var node_id := source.get_instance_id()
		var record_index := int(_semantic_sidecar_record_index_by_node_id.get(node_id, -1))
		if record_index < 0:
			_semantic_sidecar_errors.append("visible prop has no stable semantic token: " + str(source.get_path()))
			return false
		var copy := _duplicate_canvas_tree(source) as Node2D
		if copy == null:
			_semantic_sidecar_errors.append("could not duplicate visible prop for semantic sidecar: " + str(source.get_path()))
			return false
		copy.transform = source.transform
		copy.set_meta("semantic_sidecar_stable_id", str(_semantic_sidecar_instance_records[record_index]["stable_id"]))
		canvas.add_child(copy)
		var source_to_copy: Dictionary = {}
		if not _semantic_apply_leaf_materials(source, copy, record_index, mode, "", source_to_copy):
			return false
		if str(_semantic_sidecar_instance_records[record_index].get("type", "")) == "tree":
			if not _semantic_apply_tree_classification_map(source, source_to_copy, record_index, mode):
				return false
		var instance_record: Dictionary = _semantic_sidecar_instance_records[record_index]
		var draw_signatures: Dictionary = instance_record["draw_leaf_signatures"]
		draw_signatures[mode] = _semantic_signature_list(source, record_index, mode)
		instance_record["draw_leaf_signatures"] = draw_signatures
		_semantic_sidecar_instance_records[record_index] = instance_record
		if mode == "pair":
			# Complete all original hierarchy/state comparisons before adding
			# zero-output children. Source draw leaves and their order stay intact.
			for observation: Dictionary in _semantic_material_observations:
				if observation["mode"] != mode or observation["stable_id"] != instance_record["stable_id"]:
					continue
				var leaf := observation["canvas"] as CanvasItem
				if not _semantic_add_blend_fence(leaf):
					return false
	return true


func _semantic_apply_leaf_materials(source: Node, copy: Node, record_index: int,
		mode: String, relative_path: String, source_to_copy: Dictionary) -> bool:
	if source.get_class() != copy.get_class() or source.get_child_count() != copy.get_child_count():
		_semantic_sidecar_errors.append("source/copy hierarchy differs at %s" % str(source.get_path()))
		return false
	source_to_copy[source.get_instance_id()] = copy
	if source is Node2D and copy is Node2D:
		if not _numeric_arrays_equal(_transform_array((source as Node2D).transform), _transform_array((copy as Node2D).transform), 0.000001):
			_semantic_sidecar_errors.append("source/copy local transform differs at %s" % str(source.get_path()))
			return false
	if source is CanvasItem and copy is CanvasItem:
		var source_canvas := source as CanvasItem
		var copy_canvas := copy as CanvasItem
		if not _colors_equal(source_canvas.modulate, copy_canvas.modulate) \
				or not _colors_equal(source_canvas.self_modulate, copy_canvas.self_modulate) \
				or source_canvas.visible != copy_canvas.visible \
				or source_canvas.texture_filter != copy_canvas.texture_filter \
				or source_canvas.texture_repeat != copy_canvas.texture_repeat:
			_semantic_sidecar_errors.append("source/copy CanvasItem state differs at %s" % str(source.get_path()))
			return false
		if source_canvas.is_visible_in_tree() and (source is Sprite2D or source is Polygon2D or source is Line2D):
			var part := _semantic_part_for_leaf(source as CanvasItem, source.get_parent() as Node2D,
				str(_semantic_sidecar_instance_records[record_index].get("classified_kind", "")))
			_set_semantic_material(copy_canvas, record_index, part, mode)
			_semantic_material_observations.append({
				"canvas": copy_canvas, "mode": mode, "relative_path": relative_path,
				"stable_id": str(_semantic_sidecar_instance_records[record_index]["stable_id"]),
			})
		elif source_canvas.is_visible_in_tree() and (not source is Node2D or source.get_child_count() == 0):
			_semantic_sidecar_errors.append("unsupported visible semantic draw leaf %s (%s)" % [str(source.get_path()), source.get_class()])
			return false
	for child_index: int in source.get_child_count():
		var child_path := str(child_index) if relative_path.is_empty() else relative_path + "/" + str(child_index)
		if not _semantic_apply_leaf_materials(source.get_child(child_index), copy.get_child(child_index),
				record_index, mode, child_path, source_to_copy):
			return false
	return true


func _semantic_part_for_leaf(leaf: CanvasItem, prop_root: Node2D, kind: String) -> Dictionary:
	if kind in ["wall", "pillar"]:
		if leaf is Polygon2D:
			var part_name := _classify_wall_child(prop_root, leaf as Polygon2D, kind)
			if SEMANTIC_PART_CODES.has(part_name):
				return {"name": part_name, "code": int(SEMANTIC_PART_CODES[part_name]), "source": "actual Polygon2D child and inherited _classify_wall_child"}
		if leaf is Line2D and kind == "wall":
			return {"name": "wall_outline", "code": int(SEMANTIC_PART_CODES["wall_outline"]), "source": "actual Line2D child node"}
		return {"name": "unknown", "code": SEMANTIC_UNKNOWN_PART_CODE, "source": "visible draw leaf has no actual structural Polygon2D/Line2D classification"}
	if kind == "tree":
		return {"name": "unknown", "code": SEMANTIC_UNKNOWN_PART_CODE, "source": "original AtlasTexture alpha silhouette; reviewed region-local category map is sampled by the same Sprite2D draw"}
	if kind == "unknown":
		return {"name": "unknown", "code": SEMANTIC_UNKNOWN_PART_CODE, "source": "unclassified actual visible prop; nonzero token is retained and occludes earlier draws"}
	return {"name": "whole_instance", "code": int(SEMANTIC_PART_CODES["whole_instance"]), "source": "whole visible actual prop; no subpart metric is assigned"}


func _set_semantic_material(canvas: CanvasItem, record_index: int, part: Dictionary, mode: String) -> void:
	var record: Dictionary = _semantic_sidecar_instance_records[record_index]
	var rgb: Array = record.get("token_rgb", [])
	canvas.material = _semantic_material(rgb, int(part.get("code", SEMANTIC_UNKNOWN_PART_CODE)), mode)


func _semantic_material(rgb: Array, part_code: int, mode: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _semantic_sidecar_shader
	material.set_shader_parameter("instance_token_rgb", Vector3(float(rgb[0]) / 255.0,
		float(rgb[1]) / 255.0, float(rgb[2]) / 255.0))
	material.set_shader_parameter("part_code_alpha", float(part_code) / 255.0)
	material.set_shader_parameter("coverage_output", mode == "coverage")
	material.set_shader_parameter("semantic_region_map_enabled", false)
	material.set_shader_parameter("semantic_atlas_size", Vector2.ONE)
	material.set_shader_parameter("semantic_atlas_region", Vector4(0.0, 0.0, 1.0, 1.0))
	return material


func _semantic_add_blend_fence(leaf: CanvasItem) -> bool:
	# GLES3 4.6.3 can re-enable blending on a disabled->disabled color change.
	# A transparent MIX draw immediately behind the label leaf forces the next
	# MIX->DISABLED transition. It writes zero source alpha, leaving RGBA intact.
	# Clone the primitive to keep identical clipping/bounds, including Sprite2D
	# leaves whose origin is outside the viewport but whose texture is visible.
	var leaf_2d := leaf as Node2D
	if leaf_2d == null or leaf.get_child_count() != 0 or leaf_2d.y_sort_enabled:
		_semantic_sidecar_errors.append("blend fence requires a childless unsorted Node2D draw leaf: " + str(leaf.get_path()))
		return false
	var fence := _duplicate_canvas_tree(leaf) as Node2D
	if fence == null:
		_semantic_sidecar_errors.append("could not duplicate semantic primitive for zero-output blend fence")
		return false
	fence.name = "SemanticZeroOutputBlendFence"
	fence.transform = Transform2D.IDENTITY
	fence.modulate = Color.WHITE
	fence.self_modulate = Color.WHITE
	fence.z_index = 0
	fence.z_as_relative = true
	fence.show_behind_parent = true
	fence.use_parent_material = false
	fence.material = _semantic_blend_fence_material
	leaf.add_child(fence)
	_semantic_blend_fence_observations.append({
		"leaf": leaf, "fence": fence,
		"zero_output_shader_sha256": _sha256_text(SEMANTIC_BLEND_FENCE_SHADER),
		"source_geometry_unchanged": true, "source_canvas_state_unchanged": true,
	})
	return true


func _semantic_observed_blend_fences() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for observation: Dictionary in _semantic_blend_fence_observations:
		var leaf := observation["leaf"] as CanvasItem
		var fence := observation["fence"] as Node2D
		var record: Dictionary = observation.duplicate()
		record.erase("leaf")
		record.erase("fence")
		record["leaf_path"] = str(leaf.get_path())
		record["fence_path"] = str(fence.get_path())
		record["show_behind_parent"] = fence.show_behind_parent
		record["z_index"] = fence.z_index
		record["z_as_relative"] = fence.z_as_relative
		record["local_transform"] = _transform_array(fence.transform)
		record["shader_bound"] = fence.material == _semantic_blend_fence_material
		result.append(record)
	return result


func _create_semantic_write_probe() -> void:
	# This isolated control diagnoses label-byte loss. It never supplies terrain
	# masks or changes the frozen twelve-image capture and acceptance rules.
	_semantic_write_probe_samples.clear()
	_semantic_write_probe_viewport = _new_viewport("semantic_write_probe", SEMANTIC_WRITE_PROBE_SIZE, true)
	_semantic_write_probe_viewport.size_2d_override = Vector2i.ZERO
	_semantic_write_probe_viewport.size_2d_override_stretch = false
	_semantic_write_probe_viewport.use_hdr_2d = false
	_semantic_write_probe_viewport.msaa_2d = Viewport.MSAA_DISABLED
	root.add_child(_semantic_write_probe_viewport)
	var colors: Array[Array] = [[0, 0, 25], [255, 73, 19]]
	var part_codes: Array[int] = [1, 2, 7, 255]
	var groups: Array[String] = ["constant_white", "varying_color_unfenced", "varying_color_fenced", "varying_alpha_fenced"]
	var source_alphas: Array[float] = [1.0, 0.5, 0.125, 0.0]
	for group_index: int in groups.size():
		for row: int in colors.size():
			for column: int in part_codes.size():
				var polygon := Polygon2D.new()
				var x := group_index * 32 + column * 8
				polygon.position = Vector2(x, row * 8)
				polygon.polygon = PackedVector2Array([Vector2.ZERO, Vector2(8, 0), Vector2(8, 8), Vector2(0, 8)])
				polygon.color = Color.WHITE
				if group_index > 0:
					polygon.modulate = Color(0.75, 0.5, 0.25, 1.0) if column % 2 == 0 else Color.WHITE
				if group_index == 3:
					polygon.modulate.a = source_alphas[column]
				polygon.material = _semantic_material(colors[row], part_codes[column], "pair")
				_semantic_write_probe_viewport.add_child(polygon)
				if group_index >= 2 and not _semantic_add_blend_fence(polygon):
					_abort("semantic blend-fence control construction failed")
					return
				_semantic_write_probe_samples.append({
					"group": groups[group_index], "rect": [x, row * 8, 8, 8],
					"source_modulate": [polygon.modulate.r, polygon.modulate.g, polygon.modulate.b, polygon.modulate.a],
					"source_alpha": polygon.modulate.a,
					"expected_rgba": colors[row] + [part_codes[column]] if polygon.modulate.a > 0.0 else [0, 0, 0, 0],
				})


func _semantic_observed_material_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for observation: Dictionary in _semantic_material_observations:
		var canvas := observation.get("canvas") as CanvasItem
		var record: Dictionary = observation.duplicate()
		record.erase("canvas")
		record["canvas_valid"] = is_instance_valid(canvas)
		if is_instance_valid(canvas):
			record["use_parent_material"] = canvas.use_parent_material
			var material := canvas.material as ShaderMaterial
			record["shader_material_bound"] = material != null and material.shader != null
			if material != null and material.shader != null:
				var rgb: Variant = material.get_shader_parameter("instance_token_rgb")
				record["shader_code_sha256"] = _sha256_text(material.shader.code)
				record["shader_declares_blend_disabled"] = material.shader.code.contains("render_mode blend_disabled")
				record["instance_token_rgb"] = [rgb.x, rgb.y, rgb.z] if rgb is Vector3 else str(rgb)
				record["part_code_alpha"] = material.get_shader_parameter("part_code_alpha")
				record["coverage_output"] = material.get_shader_parameter("coverage_output")
				record["semantic_region_map_enabled"] = material.get_shader_parameter("semantic_region_map_enabled")
		result.append(record)
	return result


func _semantic_write_probe_record(image: Image, path: String, frame_id: int) -> Dictionary:
	var bytes := image.get_data()
	var samples: Array[Dictionary] = []
	for sample: Dictionary in _semantic_write_probe_samples:
		var rect: Array = sample["rect"]
		var expected: Array = sample["expected_rgba"]
		var mismatches := 0
		var observed: Dictionary = {}
		# Read only the 6x6 interior of each solid primitive, excluding raster edges.
		for y: int in range(int(rect[1]) + 1, int(rect[1]) + 7):
			for x: int in range(int(rect[0]) + 1, int(rect[0]) + 7):
				var offset := (y * image.get_width() + x) * 4
				var rgba: Array[int] = [bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3]]
				var key := str(rgba)
				observed[key] = int(observed.get(key, 0)) + 1
				if rgba != expected:
					mismatches += 1
		var record: Dictionary = sample.duplicate(true)
		record["sampled_pixels"] = 36
		record["mismatched_pixels"] = mismatches
		record["observed_rgba_counts"] = observed
		samples.append(record)
	return {
		"image": _semantic_image_record("semantic_write_probe", image, path, frame_id),
		"diagnostic_only": true, "supplies_acceptance_masks": false,
		"source_alpha": "per-sample source_modulate.a; primitive alpha is 1", "samples": samples,
		"gpu_blend_state": "NOT_OBSERVED; material declarations and raw pixels are recorded separately",
	}


func _semantic_apply_tree_classification_map(source_root: Node2D, source_to_copy: Dictionary,
		record_index: int, mode: String) -> bool:
	var record: Dictionary = _semantic_sidecar_instance_records[record_index]
	var tree_input: Dictionary = record.get("tree_region_inputs", {})
	var sprite := _first_sprite(source_root)
	if sprite == null:
		_semantic_sidecar_errors.append("visible tree prop has no Sprite2D source texture for reviewed region classification: " + str(source_root.get_path()))
		return false
	var copy_sprite := source_to_copy.get(sprite.get_instance_id()) as Sprite2D
	if not is_instance_valid(copy_sprite):
		_semantic_sidecar_errors.append("tree source sprite is absent from its single-draw duplicate hierarchy: " + str(sprite.get_path()))
		return false
	var atlas_texture := sprite.texture as AtlasTexture
	if atlas_texture == null or atlas_texture.atlas == null:
		_semantic_sidecar_errors.append("visible tree does not use the reviewed AtlasTexture source-alpha path: " + str(sprite.get_path()))
		return false
	if not _semantic_ensure_tree_classification_map(atlas_texture):
		return false
	var material := copy_sprite.material as ShaderMaterial
	if material == null:
		_semantic_sidecar_errors.append("tree Sprite2D semantic shader material is missing after source copy")
		return false
	var atlas_size := atlas_texture.atlas.get_size()
	material.set_shader_parameter("semantic_region_map", _semantic_tree_classification_texture)
	material.set_shader_parameter("semantic_atlas_size", atlas_size)
	material.set_shader_parameter("semantic_atlas_region", Vector4(
		_semantic_tree_classification_record["atlas_region"][0],
		_semantic_tree_classification_record["atlas_region"][1],
		_semantic_tree_classification_record["atlas_region"][2],
		_semantic_tree_classification_record["atlas_region"][3]))
	material.set_shader_parameter("semantic_region_map_enabled", mode == "pair")
	tree_input["classification_map"] = _semantic_tree_classification_record.duplicate(true)
	tree_input["classification_map"]["sampler_usage"] = {
		"semantic_pair": "nearest_category_sample",
		"semantic_coverage": "not_sampled",
	}
	tree_input["source_alpha_sampler"] = "original Sprite2D AtlasTexture COLOR.a; source texture filter/repeat/mipmap remain unchanged"
	tree_input["single_source_sprite_draw_preserves_order"] = true
	tree_input["region_map_does_not_supply_alpha"] = true
	record["tree_region_inputs"] = tree_input
	_semantic_sidecar_instance_records[record_index] = record
	return true


func _semantic_ensure_tree_classification_map(atlas_texture: AtlasTexture) -> bool:
	var atlas := atlas_texture.atlas
	var source_image := atlas.get_image()
	if source_image == null or source_image.is_empty():
		_semantic_sidecar_errors.append("original tree source AtlasTexture image pixels are unavailable")
		return false
	var region: Rect2 = atlas_texture.region
	var annotation_region: Array = _region_annotation.get("atlas_region", [])
	var region_values := _rect_array(region)
	if annotation_region.size() != 4 or not _numeric_arrays_equal(region_values, annotation_region, 0.000001):
		_semantic_sidecar_errors.append("tree AtlasTexture UV region differs from the SHA-bound reviewed atlas_region")
		return false
	for coordinate: float in [region.position.x, region.position.y, region.size.x, region.size.y]:
		if not is_equal_approx(coordinate, roundf(coordinate)):
			_semantic_sidecar_errors.append("reviewed tree atlas region must align to integer source-pixel boundaries")
			return false
	var rect := Rect2i(roundi(region.position.x), roundi(region.position.y),
		roundi(region.size.x), roundi(region.size.y))
	if rect.size.x <= 0 or rect.size.y <= 0 or rect.position.x < 0 or rect.position.y < 0 \
			or rect.end.x > source_image.get_width() or rect.end.y > source_image.get_height():
		_semantic_sidecar_errors.append("tree AtlasTexture region is outside its original atlas image")
		return false
	var atlas_path := str(atlas.resource_path)
	var cache_key := "%s|%s|%s|%s" % [atlas_path, str(source_image.get_size()), str(region_values),
		str(_tree_semantic_input_record.get("texture_sha256", ""))]
	if not _semantic_tree_classification_cache_key.is_empty():
		if cache_key != _semantic_tree_classification_cache_key:
			_semantic_sidecar_errors.append("visible trees do not share the reviewed AtlasTexture atlas/region")
			return false
		return true

	var local_size := Vector2i(rect.size)
	var classification := Image.create(local_size.x, local_size.y, false, Image.FORMAT_RGBA8)
	classification.fill(Color(0.0, 0.0, 0.0, 0.0))
	var crown_polygons := _semantic_polygon_set(_region_regions().get("crown", []), "crown")
	var dark_polygons: Array[PackedVector2Array] = []
	if _region_scope_approved("dark_side_geometry"):
		dark_polygons = _semantic_polygon_set(_region_regions().get("dark_side", []), "dark_side")
	var outline_polygons: Array[PackedVector2Array] = []
	if str(_tree_semantic_input_record.get("effective_outline_status", "NOT_TESTED")) == "captured":
		outline_polygons = _semantic_polygon_set(_region_regions().get("outline", []), "outline")
	if not _semantic_sidecar_errors.is_empty():
		return false
	for y: int in local_size.y:
		for x: int in local_size.x:
			var source_point := Vector2(float(x) + 0.5, float(y) + 0.5)
			var code := 0
			var in_crown := _semantic_point_in_polygon_set(source_point, crown_polygons)
			if in_crown:
				code = int(SEMANTIC_PART_CODES["tree_crown"])
				if _semantic_point_in_polygon_set(source_point, dark_polygons):
					code = int(SEMANTIC_PART_CODES["tree_dark_side"])
				if _semantic_point_in_polygon_set(source_point, outline_polygons):
					code = int(SEMANTIC_PART_CODES["tree_outline"])
			if code > 0:
				classification.set_pixel(x, y, Color(float(code) / 255.0, 0.0, 0.0, 1.0))
	_semantic_tree_classification_image = classification
	_semantic_tree_classification_texture = ImageTexture.create_from_image(classification)
	if _semantic_tree_classification_texture == null or classification.has_mipmaps():
		_semantic_sidecar_errors.append("tree category map must be a valid base-level-only ImageTexture")
		return false
	_semantic_tree_classification_cache_key = cache_key
	_semantic_tree_classification_record = {
		"status": "READY",
		"path": "semantic_tree_region_map.png",
		"pixel_format": "RGBA8_CODE_ONLY",
		"image_size": [local_size.x, local_size.y],
		"atlas_size": _size_array(source_image.get_size()),
		"atlas_region": [region.position.x, region.position.y, region.size.x, region.size.y],
		"atlas_uv_mapping": {
			"uv_space": "Godot 4.6 CanvasItem UV is normalized over the original atlas texture used by AtlasTexture",
			"atlas_pixel": "UV * atlas_size",
			"region_local_uv": "(atlas_pixel - atlas_region.position) / atlas_region.size",
			"region_texel": "floor(region_local_uv * region_map_size); map texels represent source region pixel centers",
			"sampler": "filter_nearest, repeat_disable",
		},
		"map_has_mipmaps": classification.has_mipmaps(),
		"map_rgb_role": "R is a code byte normalized to 0..1; G/B are zero",
		"map_alpha_role": "255 marks a reviewed code texel; it is never used as source opacity",
		"source_alpha_sampler": "original Sprite2D AtlasTexture TEXTURE through incoming COLOR.a",
		"coverage_samples_classification_map": false,
		"pair_samples_classification_map": true,
		"fallback_part_code": SEMANTIC_UNKNOWN_PART_CODE,
		"code_generation": "reviewed atlas-region-local pixel centers; dark_side requires both dark-side and crown geometry; outline only when reviewed present geometry exists; no color/brightness inference",
		"atlas_resource_path": atlas_path,
		"source_texture_sha256": str(_tree_semantic_input_record.get("texture_sha256", "")),
		"source_data_sha256": _v4_sha256_bytes(classification.get_data()),
	}
	return true


func _semantic_polygon_set(value: Variant, label: String) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if not value is Array:
		_semantic_sidecar_errors.append("reviewed %s polygon set is not an Array" % label)
		return result
	for polygon_value: Variant in value:
		if not polygon_value is Array or (polygon_value as Array).size() < 3:
			_semantic_sidecar_errors.append("reviewed %s polygon has fewer than three points" % label)
			continue
		var points := PackedVector2Array()
		for point_value: Variant in polygon_value:
			if not point_value is Array or (point_value as Array).size() != 2:
				_semantic_sidecar_errors.append("reviewed %s polygon point is malformed" % label)
				break
			var coordinates: Array = point_value
			points.append(Vector2(float(coordinates[0]), float(coordinates[1])))
		if points.size() >= 3:
			result.append(points)
	return result


func _semantic_point_in_polygon_set(point: Vector2, polygons: Array[PackedVector2Array]) -> bool:
	for polygon: PackedVector2Array in polygons:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false


func _semantic_signature_list(_source: Node, record_index: int, _mode: String) -> Array[Dictionary]:
	var record: Dictionary = _semantic_sidecar_instance_records[record_index]
	var values: Variant = record.get("draw_leaf_inputs", [])
	var result: Array[Dictionary] = []
	if values is Array:
		for value: Variant in values:
			if value is Dictionary:
				result.append((value as Dictionary).duplicate(true))
	return result


func _semantic_tree_region_input_record(node: Node2D) -> Dictionary:
	var outline := _tree_outline_status(node)
	return {
		"tree_semantic_status": _tree_semantic_status,
		"tree_semantic_reason": _tree_semantic_reason,
		"author_annotation_sha256": _tree_semantic_author_sha256,
		"independent_review_sha256": _tree_semantic_review_sha256,
		"base_crown_annotation_sha256": _tree_semantic_base_crown_sha256,
		"tree_texture_sha256": _tree_semantic_texture_sha256,
		"crown_scope_approved": _region_scope_approved("crown_geometry"),
		"dark_side_scope_approved": _region_scope_approved("dark_side_geometry"),
		"outline_status": outline.get("status", "NOT_TESTED"),
		"outline_reason": outline.get("reason", ""),
		"source_texture_signature": _node_texture_signature(node),
		"source_alpha_rule": "reviewed source-pixel geometry intersected with original AtlasTexture alpha; unknown pixels remain labeled unknown",
	}


func _semantic_validate_parallel_inputs() -> bool:
	for record: Dictionary in _semantic_sidecar_instance_records:
		var signatures: Dictionary = record.get("draw_leaf_signatures", {})
		if JSON.stringify(signatures.get("pair", [])) != JSON.stringify(signatures.get("coverage", [])):
			_semantic_sidecar_errors.append("pair/coverage source draw inputs differ for token %s" % str(record.get("token", "")))
			continue
		if str(record.get("type", "")) == "tree":
			var tree_inputs: Dictionary = record.get("tree_region_inputs", {})
			var class_map: Dictionary = tree_inputs.get("classification_map", {})
			if class_map.get("status") != "READY" or class_map.get("map_has_mipmaps") != false \
					or class_map.get("coverage_samples_classification_map") != false \
					or class_map.get("pair_samples_classification_map") != true \
					or class_map.get("fallback_part_code") != SEMANTIC_UNKNOWN_PART_CODE:
				_semantic_sidecar_errors.append("tree classification map sampler/source-alpha contract is incomplete for token %s" % str(record.get("token", "")))
			if tree_inputs.get("region_map_does_not_supply_alpha") != true \
					or tree_inputs.get("single_source_sprite_draw_preserves_order") != true:
				_semantic_sidecar_errors.append("tree classification map must preserve source alpha and the original single draw for token %s" % str(record.get("token", "")))
	if not _semantic_sidecar_errors.is_empty():
		return false
	return true


func _semantic_validate_viewports(resolution: Vector2i) -> bool:
	var main := root as Viewport
	for mode: String in ["pair", "coverage"]:
		var viewport := _semantic_sidecar_viewports.get(mode) as SubViewport
		if not is_instance_valid(viewport):
			_semantic_sidecar_errors.append("missing semantic %s viewport" % mode)
			continue
		if viewport.size != resolution or viewport.size_2d_override_stretch != true \
				or viewport.size_2d_override != Vector2i(roundi(main.get_visible_rect().size.x), roundi(main.get_visible_rect().size.y)) \
				or viewport.transparent_bg != true or viewport.use_hdr_2d:
			_semantic_sidecar_errors.append("semantic %s viewport is not transparent RGBA8-sized like main" % mode)
		if not _numeric_arrays_equal(_transform_array(viewport.get_canvas_transform()), _transform_array(main.get_canvas_transform()), 0.001) \
				or not _numeric_arrays_equal(_transform_array(viewport.get_final_transform()), _transform_array(main.get_final_transform()), 0.001):
			_semantic_sidecar_errors.append("semantic %s transform record differs from main; this is only structure evidence" % mode)
	if not _semantic_sidecar_errors.is_empty():
		return false
	return true


func _save_frame_images(images: Dictionary, case_directory: String, frame_id: int) -> Dictionary:
	if images.size() != SEMANTIC_EXPECTED_CAPTURE_IMAGE_COUNT:
		_abort("semantic sidecar must preserve the frozen 12-image dictionary passed to V4")
		return {}
	_semantic_sidecar_readback_record = {}
	var frames_before := Engine.get_frames_drawn()
	var process_before := Engine.get_process_frames()
	if frame_id != frames_before:
		_abort("semantic sidecar readback frame does not match the frozen 12-image callback frame")
		return {}
	var pair_viewport := _semantic_sidecar_viewports.get("pair") as SubViewport
	var coverage_viewport := _semantic_sidecar_viewports.get("coverage") as SubViewport
	if not is_instance_valid(pair_viewport) or not is_instance_valid(coverage_viewport):
		_abort("semantic sidecar viewport was released before same-frame readback")
		return {}
	var pair_image := pair_viewport.get_texture().get_image()
	var coverage_image := coverage_viewport.get_texture().get_image()
	if not is_instance_valid(_semantic_write_probe_viewport):
		_abort("semantic label-write control viewport was released before same-frame readback")
		return {}
	var probe_image := _semantic_write_probe_viewport.get_texture().get_image()
	var observed_materials := _semantic_observed_material_records()
	var frames_after := Engine.get_frames_drawn()
	var process_after := Engine.get_process_frames()
	if pair_image == null or pair_image.is_empty() or coverage_image == null or coverage_image.is_empty():
		_abort("semantic sidecar readback is empty")
		return {}
	if pair_image.get_size() != root.size or coverage_image.get_size() != root.size:
		_abort("semantic sidecar images do not match the frozen main image native size")
		return {}
	if probe_image == null or probe_image.get_format() != Image.FORMAT_RGBA8 or probe_image.get_size() != SEMANTIC_WRITE_PROBE_SIZE:
		_abort("semantic label-write control must provide its original 128x16 RGBA8 readback")
		return {}
	if frames_before != frames_after or frames_after != frame_id or process_before != process_after:
		_abort("semantic sidecar readback crossed the frozen frame/process boundary")
		return {}
	var pair_path := case_directory.path_join("semantic_pair.png")
	var coverage_path := case_directory.path_join("semantic_coverage.png")
	if pair_image.save_png(pair_path) != OK or coverage_image.save_png(coverage_path) != OK:
		_abort("failed to save semantic sidecar PNG readback")
		return {}
	var probe_path := case_directory.path_join("semantic_write_probe.png")
	if probe_image.save_png(probe_path) != OK:
		_abort("failed to save semantic label-write control PNG")
		return {}
	var classification_maps: Dictionary = {}
	if _semantic_tree_classification_image != null:
		var map_path := case_directory.path_join("semantic_tree_region_map.png")
		if _semantic_tree_classification_image.save_png(map_path) != OK:
			_abort("failed to persist the generated tree region code map")
			return {}
		var map_record := _semantic_tree_classification_record.duplicate(true)
		map_record["path"] = map_path.get_file()
		map_record["sha256"] = FileAccess.get_sha256(map_path)
		map_record["bytes"] = FileAccess.get_file_as_bytes(map_path).size()
		map_record["mime_type"] = "image/png"
		classification_maps["tree_regions"] = map_record
		for index: int in _semantic_sidecar_instance_records.size():
			var instance_record: Dictionary = _semantic_sidecar_instance_records[index]
			if str(instance_record.get("type", "")) != "tree":
				continue
			var tree_inputs: Dictionary = instance_record.get("tree_region_inputs", {})
			tree_inputs["classification_map"] = map_record.duplicate(true)
			instance_record["tree_region_inputs"] = tree_inputs
			_semantic_sidecar_instance_records[index] = instance_record
	else:
		for instance_record: Dictionary in _semantic_sidecar_instance_records:
			if str(instance_record.get("type", "")) == "tree":
				_abort("visible tree instances exist but no reviewed atlas classification map was produced")
				return {}
	var viewports := {
		"main": _viewport_record(root as Viewport, images.get("main") as Image),
		"semantic_pair": _viewport_record(pair_viewport, pair_image),
		"semantic_coverage": _viewport_record(coverage_viewport, coverage_image),
	}
	_semantic_sidecar_readback_record = {
		"schema_version": SEMANTIC_SIDECAR_SCHEMA,
		"case_name": _active_case_name,
		"frame_id": frame_id,
		"callback": "RenderingServer.frame_post_draw",
		"frames_drawn_before": frames_before,
		"frames_drawn_after": frames_after,
		"process_frames_before": process_before,
		"process_frames_after": process_after,
		"same_frame": true,
		"readback_awaits_between_images": false,
		"original_capture_image_count_unchanged": images.size(),
		"original_capture_roles_unchanged": _semantic_sorted_keys(images),
		"window_size": _size_array(root.size),
		"images": {
			"semantic_pair": _semantic_image_record("semantic_pair", pair_image, pair_path, frame_id),
			"semantic_coverage": _semantic_image_record("semantic_coverage", coverage_image, coverage_path, frame_id),
		},
		"classification_maps": classification_maps,
		"label_write_diagnostic": _semantic_write_probe_record(probe_image, probe_path, frame_id),
		"zero_output_blend_fences": _semantic_observed_blend_fences(),
		"observed_copy_materials": observed_materials,
		"viewports": viewports,
		"instance_tokens": _semantic_sidecar_instance_records.duplicate(true),
		"draw_order_stable_ids": _semantic_sidecar_draw_order_stable_ids(),
		"part_codes": SEMANTIC_PART_CODES.duplicate(true),
		"unknown_part_code": SEMANTIC_UNKNOWN_PART_CODE,
		"unknown_visible_props_preserved_and_occluding": true,
		"zero_source_alpha_discarded": true,
		"source_alpha_path": "COLOR.a after source texture/primitive and inherited modulation; custom materials and custom _draw paths fail with NOT_TESTED",
		"tree_region_code_map_changes_source_alpha": false,
		"tree_region_code_map_changes_draw_order": false,
		"tag_alpha_is_not_opacity": true,
		"coverage_channels": {"R": "original effective source alpha in RGBA8", "A": "255 means a visible source draw covered this pixel"},
		"measurement_view_state": _semantic_measurement_view_state.duplicate(true),
		"pixel_alignment": "NOT_TESTED_UNTIL_RAW_PIXEL_VALIDATOR_CROSS_CHECKS_EXACT_RGBA_SOURCE_ANCHORS_AND_TREE_CROWN",
		"complete_T2_status": "NOT_RUN_BY_CAPTURE",
		"complete_T3_status": "NOT_RUN_BY_CAPTURE",
	}
	return super._save_frame_images(images, case_directory, frame_id)


func _semantic_image_record(role: String, image: Image, path: String, frame_id: int) -> Dictionary:
	return {
		"role": role,
		"path": path.get_file(),
		"sha256": FileAccess.get_sha256(path),
		"bytes": FileAccess.get_file_as_bytes(path).size(),
		"image_size": _size_array(image.get_size()),
		"frame_id": frame_id,
		"mime_type": "image/png",
		"pixel_format": "RGBA8",
	}


func _write_json(path: String, value: Dictionary) -> bool:
	var succeeded: bool = super._write_json(path, value)
	if not succeeded or path.get_file() != "capture-manifest.json":
		return succeeded
	if _semantic_sidecar_readback_record.is_empty():
		_abort("semantic sidecar readback record is missing when the final capture manifest is written")
		return false
	var manifest_bytes := FileAccess.get_file_as_bytes(path)
	# The parent serializes this same dictionary once. Keep its native integer
	# fields while binding the sidecar to the exact final file bytes.
	var capture_manifest: Dictionary = value.duplicate(true)
	var candidate: Dictionary = capture_manifest.get("candidate", {})
	var source_hashes: Dictionary = candidate.get("source_sha256", {}).duplicate(true)
	var input_paths := PackedStringArray(TREE_SEMANTICS_INPUT_PATHS)
	if REGION_ANNOTATION_PATH not in input_paths:
		input_paths.append(REGION_ANNOTATION_PATH)
	var tree_texture_path := str(_tree_semantic_input_record.get("texture_path", ""))
	if not tree_texture_path.is_empty() and tree_texture_path not in input_paths:
		input_paths.append(tree_texture_path)
	var input_hashes: Dictionary = _semantic_file_hashes(input_paths)
	var sidecar_manifest := {
		"schema_version": SEMANTIC_SIDECAR_SCHEMA,
		"capture_manifest_path": "capture-manifest.json",
		"capture_manifest_sha256": _v4_sha256_bytes(manifest_bytes),
		"capture_candidate": candidate.duplicate(true),
		"candidate_source_sha256": source_hashes,
		"semantic_input_sha256": input_hashes,
		"case": capture_manifest.get("case", {}).duplicate(true),
		"frame": _semantic_sidecar_readback_record.duplicate(true),
		"classification_maps": _semantic_sidecar_readback_record.get("classification_maps", {}).duplicate(true),
		"tree_semantic_input": capture_manifest.get("tree_semantic_input", {}).duplicate(true),
		"source_alpha_policy": {
			"alpha_threshold_for_visible_measurement": 0.5,
			"uncertain_if_source_alpha_below": 0.98,
			"uncertain_pixels_remain_in_measurement_samples": true,
			"tag_alpha_is_part_code": true,
			"coverage_red_is_source_effective_alpha": true,
			"coverage_alpha_is_coverage_marker": true,
			"tree_alpha_sampler": "original AtlasTexture sampled by Sprite2D default TEXTURE; incoming COLOR.a",
			"tree_category_sampler": "separate region-local RGBA8 code map; filter_nearest; repeat_disable; no mipmaps",
			"tree_coverage_samples_category_map": false,
			"tree_source_draw_count_changed_by_category_map": false,
			"unsupported_custom_alpha_path": "NOT_TESTED_AND_CAPTURE_FAILS_WITH_SPECIFIC_REASON",
		},
		"alignment_claim": "NOT_TESTED_UNTIL_EXACT_PIXEL_CHECKS; transform equality alone does not establish pixel registration",
	}
	var sidecar_path := path.get_base_dir().path_join(SEMANTIC_SIDECAR_MANIFEST)
	if not _semantic_write_json(sidecar_path, sidecar_manifest):
		_abort("could not persist semantic sidecar sibling manifest bound to the final capture-manifest bytes")
		return false
	return true


func _semantic_write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t") + "\n")
	var write_error := file.get_error()
	file.close()
	return write_error == OK


func _semantic_file_hashes(paths: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for path: String in paths:
		var relative := path.trim_prefix("res://")
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute):
			result[relative] = FileAccess.get_sha256(absolute)
	return result


func _semantic_validate_sidecar_readback_record() -> bool:
	return not _semantic_sidecar_readback_record.is_empty()


func _semantic_sorted_keys(value: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in value.keys():
		result.append(str(key))
	result.sort()
	return result


func _semantic_sidecar_draw_order_stable_ids() -> Array[String]:
	var result: Array[String] = []
	for source: Node2D in _semantic_sidecar_draw_order:
		var record_index := int(_semantic_sidecar_record_index_by_node_id.get(source.get_instance_id(), -1))
		if record_index < 0:
			continue
		result.append(str(_semantic_sidecar_instance_records[record_index].get("stable_id", "")))
	return result


func _semantic_token_rgb(token: int) -> Array[int]:
	return [(token >> 16) & 255, (token >> 8) & 255, token & 255]


func _path_hashes(paths: PackedStringArray) -> Dictionary:
	var extended: PackedStringArray = paths.duplicate()
	for path: String in SEMANTIC_SIDECAR_SOURCE_PATHS:
		if path not in extended:
			extended.append(path)
	return super._path_hashes(extended)


func _candidate_record() -> Dictionary:
	var candidate: Dictionary = super._candidate_record()
	var source_hashes: Dictionary = candidate.get("source_sha256", {}).duplicate(true)
	for path: String in SEMANTIC_SIDECAR_SOURCE_PATHS:
		var relative := path.trim_prefix("res://")
		var absolute := ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(absolute):
			_abort("semantic sidecar candidate source is missing: " + relative)
			continue
		source_hashes[relative] = FileAccess.get_sha256(absolute)
	candidate["source_sha256"] = source_hashes
	candidate["candidate_digest_sha256"] = _sha256_text(JSON.stringify(source_hashes))
	return candidate


func _close_sessions_and_passes() -> void:
	var sidecar_viewports := _semantic_sidecar_viewports.duplicate()
	_semantic_sidecar_viewports.clear()
	if is_instance_valid(_semantic_write_probe_viewport):
		_semantic_write_probe_viewport.queue_free()
	_semantic_write_probe_viewport = null
	_semantic_write_probe_samples.clear()
	_semantic_material_observations.clear()
	super._close_sessions_and_passes()
	for viewport_value: Variant in sidecar_viewports.values():
		var viewport := viewport_value as SubViewport
		if is_instance_valid(viewport):
			viewport.queue_free()
	_semantic_sidecar_draw_order.clear()
	_semantic_sidecar_runtime_records.clear()
	_semantic_sidecar_record_index_by_node_id.clear()
	_semantic_sidecar_instance_records.clear()
