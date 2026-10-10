extends "res://tests/claude_review/capture_terrain_readability_v6.gd"
## Adds independently reviewed tree-region semantics to the frozen V6 capture.

const TREE_SEMANTICS_SCHEMA := "terrain-readability-tree-semantics/1"
const TREE_SEMANTICS_REVIEW_SCHEMA := "terrain-readability-tree-semantics-review/1"
const TREE_SEMANTICS_ANNOTATION_PATH := "res://tests/claude_review/terrain_readability_tree_semantics.json"
const TREE_SEMANTICS_REVIEW_PATH := "res://tests/claude_review/terrain_readability_tree_semantics_review.json"
const TREE_SEMANTICS_SOURCE_PATHS: PackedStringArray = [
	"res://tests/claude_review/capture_terrain_readability_v6_regions.gd",
	"res://tests/claude_review/test_terrain_readability_tree_semantics.gd",
	"res://dev_doc/ui-art-research/terrain-readability/t3-semantic-input-task.md",
]
const TREE_SEMANTICS_INPUT_PATHS: PackedStringArray = [
	TREE_SEMANTICS_ANNOTATION_PATH,
	TREE_SEMANTICS_REVIEW_PATH,
]
const TREE_SEMANTICS_EPSILON := 0.000001

var _tree_semantic_status := "NOT_TESTED"
var _tree_semantic_reason := "The author annotation and independent review have not been loaded."
var _tree_semantic_regions: Dictionary = {}
var _tree_semantic_approved_scopes: Array[String] = []
var _tree_semantic_outline_present := false
var _tree_semantic_outline_reason := ""
var _tree_semantic_author_sha256 := ""
var _tree_semantic_review_sha256 := ""
var _tree_semantic_texture_sha256 := ""
var _tree_semantic_base_crown_sha256 := ""
var _tree_semantic_author_present := false
var _tree_semantic_review_present := false
var _tree_semantic_input_record: Dictionary = {}


func _initialize() -> void:
	super._initialize()


func _load_region_annotation(profile: Dictionary) -> void:
	super._load_region_annotation(profile)
	_tree_semantic_status = "REJECTED_MISSING_INPUT"
	_tree_semantic_reason = "Both the author semantic annotation and independent review are required."
	_tree_semantic_regions = {}
	_tree_semantic_approved_scopes.clear()
	_tree_semantic_outline_present = false
	_tree_semantic_outline_reason = ""
	_tree_semantic_author_sha256 = ""
	_tree_semantic_review_sha256 = ""
	_tree_semantic_texture_sha256 = ""
	_tree_semantic_base_crown_sha256 = ""
	_tree_semantic_author_present = false
	_tree_semantic_review_present = false
	_tree_semantic_input_record = {
		"schema_version": TREE_SEMANTICS_SCHEMA,
		"status": _tree_semantic_status,
		"reason": _tree_semantic_reason,
		"author_annotation_path": TREE_SEMANTICS_ANNOTATION_PATH,
		"author_annotation_sha256": "",
		"independent_review_path": TREE_SEMANTICS_REVIEW_PATH,
		"independent_review_sha256": "",
		"texture_path": "",
		"texture_sha256": "",
		"base_crown_annotation_path": REGION_ANNOTATION_PATH,
		"base_crown_annotation_sha256": "",
		"approved_scope": [],
		"outline_semantics": {},
		"dark_side_mask_intersection": "NOT_TESTED",
		"complete_T3_status": "NOT_RUN_BY_CAPTURE",
	}

	var annotation_absolute := ProjectSettings.globalize_path(TREE_SEMANTICS_ANNOTATION_PATH)
	var review_absolute := ProjectSettings.globalize_path(TREE_SEMANTICS_REVIEW_PATH)
	var annotation_snapshot := _read_tree_semantic_json_snapshot(TREE_SEMANTICS_ANNOTATION_PATH)
	var review_snapshot := _read_tree_semantic_json_snapshot(TREE_SEMANTICS_REVIEW_PATH)
	_tree_semantic_author_present = bool(annotation_snapshot.get("read_ok", false))
	_tree_semantic_review_present = bool(review_snapshot.get("read_ok", false))
	var annotation_exists := _tree_semantic_author_present
	var review_exists := _tree_semantic_review_present
	if annotation_exists:
		_tree_semantic_author_sha256 = str(annotation_snapshot.get("sha256", ""))
	if review_exists:
		_tree_semantic_review_sha256 = str(review_snapshot.get("sha256", ""))
	var tree_spec: Dictionary = profile.get("tree", {})
	var texture_path := str(tree_spec.get("texture", ""))
	var texture_absolute := ProjectSettings.globalize_path(texture_path) if not texture_path.is_empty() else ""
	if not texture_absolute.is_empty() and FileAccess.file_exists(texture_absolute):
		_tree_semantic_texture_sha256 = FileAccess.get_sha256(texture_absolute)
	var base_absolute := ProjectSettings.globalize_path(REGION_ANNOTATION_PATH)
	if FileAccess.file_exists(base_absolute):
		_tree_semantic_base_crown_sha256 = FileAccess.get_sha256(base_absolute)
	_tree_semantic_input_record["author_annotation_sha256"] = _tree_semantic_author_sha256
	_tree_semantic_input_record["independent_review_sha256"] = _tree_semantic_review_sha256
	_tree_semantic_input_record["texture_path"] = texture_path
	_tree_semantic_input_record["texture_sha256"] = _tree_semantic_texture_sha256
	_tree_semantic_input_record["base_crown_annotation_sha256"] = _tree_semantic_base_crown_sha256
	_tree_semantic_input_record["author_annotation_present"] = annotation_exists
	_tree_semantic_input_record["independent_review_present"] = review_exists

	if not annotation_exists or not review_exists:
		_tree_semantic_reason = "Required semantic input is missing: author annotation present=%s, independent review present=%s." % [annotation_exists, review_exists]
		_tree_semantic_input_record["reason"] = _tree_semantic_reason
		_tree_semantic_input_record["author_annotation_present"] = annotation_exists
		_tree_semantic_input_record["independent_review_present"] = review_exists
		return
	if not _region_scope_approved("crown_geometry") or _region_regions().get("crown", []).is_empty():
		_tree_semantic_reason = "The frozen, independently approved crown annotation is unavailable; semantic extension is rejected."
		_tree_semantic_input_record["status"] = "REJECTED_BASE_CROWN"
		_tree_semantic_input_record["reason"] = _tree_semantic_reason
		return
	if _tree_semantic_texture_sha256.is_empty() or _tree_semantic_base_crown_sha256.is_empty():
		_tree_semantic_reason = "The bound tree texture or base crown annotation could not be hashed."
		_tree_semantic_input_record["status"] = "REJECTED_SOURCE_MISSING"
		_tree_semantic_input_record["reason"] = _tree_semantic_reason
		return

	var annotation_value: Variant = annotation_snapshot.get("value", null)
	var review_value: Variant = review_snapshot.get("value", null)
	var decision := _validate_tree_semantic_payload(annotation_value, review_value, profile,
		_tree_semantic_texture_sha256, _tree_semantic_base_crown_sha256, _tree_semantic_author_sha256)
	_tree_semantic_status = str(decision.get("status", "REJECTED"))
	_tree_semantic_reason = str(decision.get("reason", "Semantic input validation failed."))
	_tree_semantic_input_record["status"] = _tree_semantic_status
	_tree_semantic_input_record["reason"] = _tree_semantic_reason
	_tree_semantic_input_record["author_annotation_present"] = annotation_exists
	_tree_semantic_input_record["independent_review_present"] = review_exists
	_tree_semantic_input_record["outline_semantics"] = decision.get("outline_semantics", {})
	_tree_semantic_input_record["approved_scope"] = decision.get("approved_scope", [])
	_tree_semantic_input_record["dark_side_polygon_count"] = (decision.get("regions", {}) as Dictionary).get("dark_side", []).size()
	_tree_semantic_input_record["outline_polygon_count"] = (decision.get("regions", {}) as Dictionary).get("outline", []).size()
	if not bool(decision.get("accepted", false)):
		return

	_tree_semantic_regions = (decision.get("regions", {}) as Dictionary).duplicate(true)
	_tree_semantic_approved_scopes.clear()
	for scope_value: Variant in decision.get("approved_scope", []):
		_tree_semantic_approved_scopes.append(str(scope_value))
	var outline_semantics: Dictionary = decision.get("outline_semantics", {})
	_tree_semantic_outline_present = bool(outline_semantics.get("present", false))
	_tree_semantic_outline_reason = str(outline_semantics.get("reason", ""))
	_region_annotation = _merge_approved_tree_regions(_region_annotation, decision)
	_tree_semantic_input_record["dark_side_mask_intersection"] = "dark_side polygon mask AND frozen crown polygon mask AND original AtlasTexture alpha"
	_tree_semantic_input_record["effective_outline_status"] = _semantic_outline_status(decision).get("status", "NOT_TESTED")


func _validate_tree_semantic_payload(annotation_value: Variant, review_value: Variant,
		profile: Dictionary, actual_texture_sha256: String, actual_base_crown_sha256: String,
		actual_annotation_sha256: String) -> Dictionary:
	if not annotation_value is Dictionary:
		return _tree_semantic_decision(false, "REJECTED", "Author semantic annotation is missing or not a JSON object.")
	if not review_value is Dictionary:
		return _tree_semantic_decision(false, "REJECTED", "Independent semantic review is missing or not a JSON object.")
	var annotation: Dictionary = annotation_value
	var review: Dictionary = review_value
	var tree_spec: Dictionary = profile.get("tree", {})
	var expected_texture_path := str(tree_spec.get("texture", ""))
	var expected_atlas: Array = tree_spec.get("region", [])
	if annotation.get("schema_version") != TREE_SEMANTICS_SCHEMA:
		return _tree_semantic_decision(false, "REJECTED", "Author semantic annotation schema is unsupported.")
	if review.get("schema_version") != TREE_SEMANTICS_REVIEW_SCHEMA:
		return _tree_semantic_decision(false, "REJECTED", "Independent semantic review schema is unsupported.")
	if str(annotation.get("review_status", "")) != "pending_author_review":
		return _tree_semantic_decision(false, "REJECTED", "Author review_status must remain pending_author_review; only the separate reviewer can approve scopes.")
	if str(annotation.get("texture_path", "")) != expected_texture_path \
			or str(annotation.get("texture_sha256", "")) != actual_texture_sha256 \
			or str(review.get("texture_sha256", "")) != actual_texture_sha256:
		return _tree_semantic_decision(false, "REJECTED", "Author and reviewer texture path/SHA256 do not match the current source image.")
	if annotation.get("atlas_region", []) != expected_atlas \
			or str(annotation.get("coordinate_space", "")) != "atlas_region_local_pixels":
		return _tree_semantic_decision(false, "REJECTED", "Author atlas region or coordinate space does not match the active visual profile.")
	if str(annotation.get("base_crown_annotation_path", "")) != REGION_ANNOTATION_PATH \
			or str(annotation.get("base_crown_annotation_sha256", "")) != actual_base_crown_sha256 \
			or str(review.get("base_crown_annotation_sha256", "")) != actual_base_crown_sha256:
		return _tree_semantic_decision(false, "REJECTED", "Author and reviewer base-crown annotation path/SHA256 do not match the frozen source.")
	if actual_annotation_sha256.is_empty() \
			or str(review.get("annotation_sha256", "")) != actual_annotation_sha256:
		return _tree_semantic_decision(false, "REJECTED", "Independent review is stale or is not bound to the exact author annotation bytes.")
	if str(review.get("verdict", "")) != "PASS":
		return _tree_semantic_decision(false, "REJECTED", "Independent reviewer verdict is not PASS.")
	var outline_semantics_value: Variant = annotation.get("outline_semantics", null)
	if not outline_semantics_value is Dictionary:
		return _tree_semantic_decision(false, "REJECTED", "Author outline_semantics must explicitly define presence and reason.")
	var outline_semantics: Dictionary = outline_semantics_value
	if typeof(outline_semantics.get("present", null)) != TYPE_BOOL \
			or str(outline_semantics.get("reason", "")).strip_edges().is_empty():
		return _tree_semantic_decision(false, "REJECTED", "Outline semantics must include a boolean present field and a non-empty reason.")
	var regions_value: Variant = annotation.get("regions", null)
	if not regions_value is Dictionary:
		return _tree_semantic_decision(false, "REJECTED", "Author semantic regions must be a JSON object.")
	var regions: Dictionary = regions_value
	var dark_side_value: Variant = regions.get("dark_side", null)
	var outline_value: Variant = regions.get("outline", null)
	if not dark_side_value is Array or (dark_side_value as Array).is_empty():
		return _tree_semantic_decision(false, "REJECTED", "Author dark_side geometry is empty or missing.")
	var atlas_width := float(expected_atlas[2]) if expected_atlas.size() == 4 else 0.0
	var atlas_height := float(expected_atlas[3]) if expected_atlas.size() == 4 else 0.0
	var dark_side_error := _polygon_set_error(dark_side_value as Array, atlas_width, atlas_height)
	if not dark_side_error.is_empty():
		return _tree_semantic_decision(false, "REJECTED", "Author dark_side geometry is invalid: " + dark_side_error)
	if not outline_value is Array:
		return _tree_semantic_decision(false, "REJECTED", "Author outline polygons must be an array, including when the semantic claim is absence.")
	var outline_present := bool(outline_semantics["present"])
	var outline_regions: Array = outline_value
	if not outline_present and not outline_regions.is_empty():
		return _tree_semantic_decision(false, "REJECTED", "Author declares outline absence but supplies outline polygons.")
	if outline_present and not outline_regions.is_empty():
		var outline_error := _polygon_set_error(outline_regions, atlas_width, atlas_height)
		if not outline_error.is_empty():
			return _tree_semantic_decision(false, "REJECTED", "Author outline geometry is invalid: " + outline_error)

	var expected_scopes: Array[String] = ["dark_side_geometry", "outline_absence" if not outline_present else "outline_geometry"]
	var scopes_value: Variant = review.get("approved_scope", null)
	if not scopes_value is Array or not _scope_array_matches(scopes_value as Array, expected_scopes):
		return _tree_semantic_decision(false, "REJECTED", "Independent review approved_scope does not exactly match the declared semantic claims.")
	var final_regions := {
		"dark_side": (dark_side_value as Array).duplicate(true),
		"outline": outline_regions.duplicate(true),
	}
	var result_status := "APPROVED"
	if outline_present and outline_regions.is_empty():
		result_status = "PARTIAL_APPROVAL"
	return {
		"accepted": true,
		"status": result_status,
		"reason": "Exact author, reviewer, texture, atlas, and frozen crown inputs are bound; only explicit reviewer scopes are merged.",
		"approved_scope": expected_scopes,
		"regions": final_regions,
		"outline_semantics": outline_semantics.duplicate(true),
	}


func _tree_semantic_decision(accepted: bool, status: String, reason: String) -> Dictionary:
	return {
		"accepted": accepted,
		"status": status,
		"reason": reason,
		"approved_scope": [],
		"regions": {},
		"outline_semantics": {},
	}


func _read_tree_semantic_json_snapshot(path: String) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return {"read_ok": false, "sha256": "", "value": null, "bytes": 0}
	var file := FileAccess.open(absolute, FileAccess.READ)
	if file == null:
		return {"read_ok": false, "sha256": "", "value": null, "bytes": 0}
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return {
		"read_ok": true,
		"sha256": _v4_sha256_bytes(bytes),
		"value": JSON.parse_string(bytes.get_string_from_utf8()),
		"bytes": bytes.size(),
	}


func _scope_array_matches(actual_scopes: Array, expected_scopes: Array[String]) -> bool:
	if actual_scopes.size() != expected_scopes.size():
		return false
	var seen: Dictionary = {}
	for scope_value: Variant in actual_scopes:
		if not scope_value is String or seen.has(scope_value):
			return false
		seen[scope_value] = true
	for scope: String in expected_scopes:
		if not seen.has(scope):
			return false
	return true


func _polygon_set_error(polygons: Array, width: float, height: float) -> String:
	if width <= 0.0 or height <= 0.0:
		return "atlas dimensions are invalid"
	if polygons.is_empty():
		return "polygon set is empty"
	for polygon_index: int in polygons.size():
		var polygon_value: Variant = polygons[polygon_index]
		if not polygon_value is Array or (polygon_value as Array).size() < 3:
			return "polygon %d has fewer than three vertices" % polygon_index
		var point_values: Array = polygon_value
		var points: Array[Vector2] = []
		for point_value: Variant in point_values:
			if not point_value is Array or (point_value as Array).size() != 2:
				return "polygon %d has a malformed point" % polygon_index
			var point: Array = point_value
			if typeof(point[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(point[1]) not in [TYPE_INT, TYPE_FLOAT]:
				return "polygon %d contains a non-numeric coordinate" % polygon_index
			var x := float(point[0])
			var y := float(point[1])
			if not is_finite(x) or not is_finite(y) or x < 0.0 or y < 0.0 \
					or x > width or y > height:
				return "polygon %d contains a non-finite or out-of-atlas coordinate" % polygon_index
			points.append(Vector2(x, y))
		if points.size() > 3 and points[0].is_equal_approx(points[points.size() - 1]):
			points.pop_back()
		if points.size() < 3:
			return "polygon %d has fewer than three distinct vertices" % polygon_index
		var unique_points: Array[Vector2] = []
		for point: Vector2 in points:
			if point in unique_points:
				return "polygon %d repeats a vertex" % polygon_index
			unique_points.append(point)
		var twice_area := 0.0
		for point_index: int in points.size():
			var first: Vector2 = points[point_index]
			var second: Vector2 = points[(point_index + 1) % points.size()]
			twice_area += first.x * second.y - second.x * first.y
		if absf(twice_area) <= TREE_SEMANTICS_EPSILON:
			return "polygon %d has zero area" % polygon_index
		if _polygon_self_intersects(points):
			return "polygon %d self-intersects" % polygon_index
	return ""


func _polygon_self_intersects(points: Array[Vector2]) -> bool:
	for first_index: int in points.size():
		var first_start: Vector2 = points[first_index]
		var first_end: Vector2 = points[(first_index + 1) % points.size()]
		for second_index: int in range(first_index + 1, points.size()):
			if second_index == first_index + 1 \
					or (first_index == 0 and second_index == points.size() - 1):
				continue
			var second_start: Vector2 = points[second_index]
			var second_end: Vector2 = points[(second_index + 1) % points.size()]
			if _segments_intersect(first_start, first_end, second_start, second_end):
				return true
	return false


func _segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var o1 := _cross_2d(b - a, c - a)
	var o2 := _cross_2d(b - a, d - a)
	var o3 := _cross_2d(d - c, a - c)
	var o4 := _cross_2d(d - c, b - c)
	if ((o1 > TREE_SEMANTICS_EPSILON and o2 < -TREE_SEMANTICS_EPSILON) \
			or (o1 < -TREE_SEMANTICS_EPSILON and o2 > TREE_SEMANTICS_EPSILON)) \
			and ((o3 > TREE_SEMANTICS_EPSILON and o4 < -TREE_SEMANTICS_EPSILON) \
			or (o3 < -TREE_SEMANTICS_EPSILON and o4 > TREE_SEMANTICS_EPSILON)):
		return true
	return (absf(o1) <= TREE_SEMANTICS_EPSILON and _point_on_segment(c, a, b)) \
		or (absf(o2) <= TREE_SEMANTICS_EPSILON and _point_on_segment(d, a, b)) \
		or (absf(o3) <= TREE_SEMANTICS_EPSILON and _point_on_segment(a, c, d)) \
		or (absf(o4) <= TREE_SEMANTICS_EPSILON and _point_on_segment(b, c, d))


func _cross_2d(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


func _point_on_segment(point: Vector2, start: Vector2, end: Vector2) -> bool:
	return point.x >= minf(start.x, end.x) - TREE_SEMANTICS_EPSILON \
		and point.x <= maxf(start.x, end.x) + TREE_SEMANTICS_EPSILON \
		and point.y >= minf(start.y, end.y) - TREE_SEMANTICS_EPSILON \
		and point.y <= maxf(start.y, end.y) + TREE_SEMANTICS_EPSILON


func _merge_approved_tree_regions(base_annotation: Dictionary, decision: Dictionary) -> Dictionary:
	var merged := base_annotation.duplicate(true)
	var regions: Dictionary = (merged.get("regions", {}) as Dictionary).duplicate(true)
	var accepted_regions: Dictionary = decision.get("regions", {})
	regions["dark_side"] = (accepted_regions.get("dark_side", []) as Array).duplicate(true)
	regions["outline"] = (accepted_regions.get("outline", []) as Array).duplicate(true)
	merged["regions"] = regions
	return merged


func _semantic_outline_status(decision: Dictionary) -> Dictionary:
	if not bool(decision.get("accepted", false)):
		return {"status": "NOT_TESTED", "reason": str(decision.get("reason", "Semantic input is not approved."))}
	var outline_semantics: Dictionary = decision.get("outline_semantics", {})
	var present := bool(outline_semantics.get("present", false))
	var regions: Dictionary = decision.get("regions", {})
	var outlines: Array = regions.get("outline", [])
	var scopes: Array = decision.get("approved_scope", [])
	if not present and "outline_absence" in scopes:
		return {"status": "absent_authoritatively", "reason": str(outline_semantics.get("reason", ""))}
	if present and not outlines.is_empty() and "outline_geometry" in scopes:
		return {"status": "captured", "reason": "Independently reviewed outline geometry is available."}
	return {"status": "NOT_TESTED", "reason": "Outline is declared present but no validated outline polygon is available."}


func _tree_semantic_approved() -> bool:
	return _tree_semantic_status in ["APPROVED", "PARTIAL_APPROVAL"]


func _region_scope_approved(scope: String) -> bool:
	if scope == "crown_geometry":
		return super._region_scope_approved(scope)
	if scope == "dark_side_geometry":
		return _tree_semantic_approved() and scope in _tree_semantic_approved_scopes \
			and not _tree_semantic_regions.get("dark_side", []).is_empty()
	if scope == "outline_geometry":
		return _tree_semantic_approved() and _tree_semantic_outline_present \
			and scope in _tree_semantic_approved_scopes \
			and not _tree_semantic_regions.get("outline", []).is_empty()
	return super._region_scope_approved(scope)


func _region_status_record(name: String, scope: String) -> Dictionary:
	if scope != "dark_side_geometry":
		return super._region_status_record(name, scope)
	if not _region_scope_approved(scope):
		return {"status": "NOT_TESTED", "reason": _tree_semantic_reason}
	if _region_regions().get(name, []).is_empty():
		return {"status": "NOT_TESTED", "reason": "The reviewed semantic input has no dark-side polygon."}
	return {
		"status": "captured",
		"mask_role": "part_ids",
		"color": _hex_color(PART_COLORS["tree_dark_side"]),
		"classification_source": _tree_semantic_classification_source(),
		"mask_intersection": "dark_side polygons intersect the frozen crown polygons and the original AtlasTexture alpha at source pixel centers",
		"author_annotation_sha256": _tree_semantic_author_sha256,
		"review_sha256": _tree_semantic_review_sha256,
	}


func _tree_outline_status(_node: Node2D) -> Dictionary:
	var decision := {
		"accepted": _tree_semantic_approved(),
		"status": _tree_semantic_status,
		"reason": _tree_semantic_reason,
		"approved_scope": _tree_semantic_approved_scopes,
		"regions": _tree_semantic_regions,
		"outline_semantics": {
			"present": _tree_semantic_outline_present,
			"reason": _tree_semantic_outline_reason,
		},
	}
	var outline_status := _semantic_outline_status(decision)
	var common := {
		"status": outline_status.get("status", "NOT_TESTED"),
		"mask_role": "part_ids",
		"classification_source": _tree_semantic_classification_source(),
		"author_annotation_sha256": _tree_semantic_author_sha256,
		"review_sha256": _tree_semantic_review_sha256,
		"reason": outline_status.get("reason", _tree_semantic_reason),
	}
	if common["status"] == "captured":
		common["color"] = _hex_color(PART_COLORS["tree_outline"])
	elif common["status"] == "absent_authoritatively":
		common["absence_basis"] = "explicit outline_semantics.present=false plus independently reviewed outline_absence scope; empty polygon array alone is not evidence"
	return common


func _parts_for_instance(node: Node2D, kind: String) -> Dictionary:
	var result: Dictionary = super._parts_for_instance(node, kind)
	if kind == "tree":
		result["complete_T3"] = {
			"status": "NOT_RUN_BY_CAPTURE",
			"reason": "The capture records source semantics only; frozen metrics must calculate contrast and complete T3 eligibility.",
		}
		result["contact_shadow"] = {
			"status": "NOT_TESTED",
			"reason": "Tree contact shadow remains baked into the sprite/material and is not isolated by the wall-footing mask.",
		}
	return result


func _classification_source(node: Node2D, kind: String) -> String:
	if kind == "tree":
		return "Sprite2D AtlasTexture; crown uses the frozen base annotation; dark_side and outline use the byte-bound author semantics only when the matching independent review passes. " + _tree_semantic_classification_source()
	return super._classification_source(node, kind)


func _tree_semantic_classification_source() -> String:
	if not _tree_semantic_author_sha256.is_empty() and not _tree_semantic_review_sha256.is_empty():
		return "%s sha256=%s; %s sha256=%s" % [TREE_SEMANTICS_ANNOTATION_PATH, _tree_semantic_author_sha256, TREE_SEMANTICS_REVIEW_PATH, _tree_semantic_review_sha256]
	return "%s and %s; approval unavailable" % [TREE_SEMANTICS_ANNOTATION_PATH, TREE_SEMANTICS_REVIEW_PATH]


func _make_annotated_texture(sprite: Sprite2D, polygon_records: Array) -> Texture2D:
	var selected_texture: Texture2D = super._make_annotated_texture(sprite, polygon_records)
	if selected_texture == null or not _region_scope_approved("dark_side_geometry"):
		return selected_texture
	var dark_side: Array = _tree_semantic_regions.get("dark_side", [])
	if _sha256_text(JSON.stringify(polygon_records)) != _sha256_text(JSON.stringify(dark_side)):
		return selected_texture
	var crown_texture: Texture2D = super._make_annotated_texture(sprite, _region_regions().get("crown", []))
	if crown_texture == null:
		return null
	var intersected_image := _intersect_dark_side_with_crown(selected_texture.get_image(), crown_texture.get_image())
	if intersected_image == null or intersected_image.is_empty():
		return null
	return ImageTexture.create_from_image(intersected_image)


func _intersect_dark_side_with_crown(dark_side_image: Image, crown_image: Image) -> Image:
	if dark_side_image == null or crown_image == null or dark_side_image.is_empty() \
			or crown_image.is_empty() or dark_side_image.get_size() != crown_image.get_size():
		return null
	var result := dark_side_image.duplicate()
	for y: int in result.get_height():
		for x: int in result.get_width():
			var dark_pixel := dark_side_image.get_pixel(x, y)
			if dark_pixel.a <= 0.0 or crown_image.get_pixel(x, y).a <= 0.0:
				result.set_pixel(x, y, Color(0, 0, 0, 0))
	return result


func _build_manifest_skeleton(map_data: Dictionary, resolution: Vector2i, case_name: String) -> Dictionary:
	var manifest: Dictionary = super._build_manifest_skeleton(map_data, resolution, case_name)
	manifest["tree_semantic_input"] = _tree_semantic_input_record.duplicate(true)
	manifest["complete_T3_status"] = "NOT_RUN_BY_CAPTURE"
	return manifest


func _capture_case(map_size: int, resolution: Vector2i, source_map: Dictionary, profile: Dictionary) -> bool:
	if not _tree_semantic_inputs_unchanged():
		_abort("tree semantic inputs changed after exact-byte parsing; refusing to capture against unbound review data")
		return false
	var succeeded: bool = await super._capture_case(map_size, resolution, source_map, profile)
	if not succeeded:
		return false
	if not _tree_semantic_inputs_unchanged():
		_abort("tree semantic inputs changed while the case was being captured; refusing the mismatched manifest")
		return false
	return true


func _write_json(path: String, value: Dictionary) -> bool:
	if path.get_file() == "capture-manifest.json":
		# Add the final T3 state before serialization. Godot's JSON parser converts
		# JSON numbers to floats, so reopening and rewriting loses integer evidence.
		var terrain_metrics: Dictionary = value.get("terrain_metrics", {}).duplicate(true)
		var t3: Dictionary = terrain_metrics.get("T3", {}).duplicate(true)
		t3["completeness_status"] = "NOT_RUN_BY_CAPTURE"
		t3["full_T3_status"] = "NOT_RUN_BY_CAPTURE"
		t3["measurement_status"] = "NOT_RUN_BY_CAPTURE"
		t3["semantic_input_status"] = _tree_semantic_status
		terrain_metrics["T3"] = t3
		value["terrain_metrics"] = terrain_metrics
		value["tree_semantic_input"] = _tree_semantic_input_record.duplicate(true)
		value["complete_T3_status"] = "NOT_RUN_BY_CAPTURE"
	return super._write_json(path, value)


func _path_hashes(paths: PackedStringArray) -> Dictionary:
	var extended: PackedStringArray = paths.duplicate()
	for path: String in TREE_SEMANTICS_SOURCE_PATHS:
		if path not in extended:
			extended.append(path)
	for path: String in TREE_SEMANTICS_INPUT_PATHS:
		if path not in extended:
			extended.append(path)
	return super._path_hashes(extended)


func _candidate_record() -> Dictionary:
	var candidate: Dictionary = super._candidate_record()
	var source_hashes: Dictionary = candidate.get("source_sha256", {}).duplicate(true)
	for path: String in TREE_SEMANTICS_SOURCE_PATHS:
		var relative: String = path.trim_prefix("res://")
		var absolute: String = ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(absolute):
			_abort("tree semantic capture source is missing: " + relative)
			continue
		source_hashes[relative] = FileAccess.get_sha256(absolute)
	for path: String in TREE_SEMANTICS_INPUT_PATHS:
		var relative: String = path.trim_prefix("res://")
		var absolute: String = ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute):
			source_hashes[relative] = FileAccess.get_sha256(absolute)
	candidate["source_sha256"] = source_hashes
	candidate["candidate_digest_sha256"] = _sha256_text(JSON.stringify(source_hashes))
	return candidate


func _tree_semantic_inputs_unchanged() -> bool:
	var annotation_snapshot := _read_tree_semantic_json_snapshot(TREE_SEMANTICS_ANNOTATION_PATH)
	var review_snapshot := _read_tree_semantic_json_snapshot(TREE_SEMANTICS_REVIEW_PATH)
	if bool(annotation_snapshot.get("read_ok", false)) != _tree_semantic_author_present \
			or bool(review_snapshot.get("read_ok", false)) != _tree_semantic_review_present:
		return false
	if _tree_semantic_author_present \
			and str(annotation_snapshot.get("sha256", "")) != _tree_semantic_author_sha256:
		return false
	if _tree_semantic_review_present \
			and str(review_snapshot.get("sha256", "")) != _tree_semantic_review_sha256:
		return false
	return true
