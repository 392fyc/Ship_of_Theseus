extends "res://tests/claude_review/capture_terrain_readability_v6_regions.gd"

var _semantic_test_failures: Array[String] = []
var _semantic_test_count := 0


func _initialize() -> void:
	super._initialize()


func _run_headless_check() -> void:
	var profile_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if not profile_value is Dictionary:
		_abort("tree semantic tests could not read the frozen visual profile")
		return
	var profile: Dictionary = profile_value
	var texture_path := str((profile.get("tree", {}) as Dictionary).get("texture", ""))
	var texture_absolute := ProjectSettings.globalize_path(texture_path)
	var base_absolute := ProjectSettings.globalize_path(REGION_ANNOTATION_PATH)
	if not FileAccess.file_exists(texture_absolute) or not FileAccess.file_exists(base_absolute):
		_abort("tree semantic tests require the source texture, frozen crown annotation, and Main author input")
		return
	var texture_sha := FileAccess.get_sha256(texture_absolute)
	var base_sha := FileAccess.get_sha256(base_absolute)
	var author_snapshot := _read_tree_semantic_json_snapshot(TREE_SEMANTICS_ANNOTATION_PATH)
	if not bool(author_snapshot.get("read_ok", false)):
		_abort("Main author semantic input could not be read as a byte-bound JSON snapshot")
		return
	var annotation_sha := str(author_snapshot.get("sha256", ""))
	var author_value: Variant = author_snapshot.get("value", null)
	if not author_value is Dictionary:
		_abort("Main author semantic input is not a JSON object")
		return
	var author: Dictionary = author_value
	var passing_review := _make_review_fixture(annotation_sha, texture_sha, base_sha, ["dark_side_geometry", "outline_absence"])
	var positive := _validate_tree_semantic_payload(author, passing_review, profile, texture_sha, base_sha, annotation_sha)
	_expect(bool(positive.get("accepted", false)), "current author input binds to an exact positive review fixture")
	_expect(str(positive.get("status", "")) == "APPROVED", "explicit absent outline and valid dark-side regions form an approved semantic input")
	_expect(_semantic_outline_status(positive).get("status") == "absent_authoritatively", "outline absence requires an explicit reviewed outline_absence scope")
	_expect(author.get("review_status") == "pending_author_review", "author annotation remains pending and is never rewritten as approved")
	_expect((positive.get("regions", {}) as Dictionary).get("dark_side", []).size() > 0, "non-empty reviewed dark-side polygons are merged")
	var source_records := _path_hashes(PackedStringArray())
	var candidate_record := _candidate_record()
	var candidate_hashes: Dictionary = candidate_record.get("source_sha256", {})
	for source_path: String in TREE_SEMANTICS_SOURCE_PATHS:
		_expect(source_records.has(source_path) and candidate_hashes.has(source_path.trim_prefix("res://")), "new capture source is present in manifest and candidate hashes: " + source_path)
	for input_path: String in TREE_SEMANTICS_INPUT_PATHS:
		_expect(source_records.has(input_path) and candidate_hashes.has(input_path.trim_prefix("res://")), "semantic input is present in manifest and candidate hashes: " + input_path)

	var missing_annotation := _validate_tree_semantic_payload(null, passing_review, profile, texture_sha, base_sha, annotation_sha)
	_expect(not bool(missing_annotation.get("accepted", false)), "missing author annotation is rejected")
	var missing_review := _validate_tree_semantic_payload(author, null, profile, texture_sha, base_sha, annotation_sha)
	_expect(not bool(missing_review.get("accepted", false)), "missing reviewer report is rejected")
	var stale_review: Dictionary = passing_review.duplicate(true)
	stale_review["annotation_sha256"] = "0".repeat(64)
	_expect(not bool(_validate_tree_semantic_payload(author, stale_review, profile, texture_sha, base_sha, annotation_sha).get("accepted", false)), "old review summary bound to different annotation bytes is rejected")
	var wrong_texture: Dictionary = passing_review.duplicate(true)
	wrong_texture["texture_sha256"] = "1".repeat(64)
	_expect(not bool(_validate_tree_semantic_payload(author, wrong_texture, profile, texture_sha, base_sha, annotation_sha).get("accepted", false)), "review texture digest mismatch is rejected")
	var wrong_base: Dictionary = passing_review.duplicate(true)
	wrong_base["base_crown_annotation_sha256"] = "2".repeat(64)
	_expect(not bool(_validate_tree_semantic_payload(author, wrong_base, profile, texture_sha, base_sha, annotation_sha).get("accepted", false)), "review base-crown digest mismatch is rejected")
	var wrong_verdict: Dictionary = passing_review.duplicate(true)
	wrong_verdict["verdict"] = "PENDING"
	_expect(not bool(_validate_tree_semantic_payload(author, wrong_verdict, profile, texture_sha, base_sha, annotation_sha).get("accepted", false)), "non-PASS review verdict is rejected")

	var empty_dark: Dictionary = author.duplicate(true)
	(empty_dark["regions"] as Dictionary)["dark_side"] = []
	_expect(not bool(_validate_tree_semantic_payload(empty_dark, passing_review, profile, texture_sha, base_sha, annotation_sha).get("accepted", false)), "empty dark-side polygon input is rejected")
	var malformed_polygon: Dictionary = author.duplicate(true)
	(malformed_polygon["regions"] as Dictionary)["dark_side"] = [[[0, 0], [12, 12], [24, 24]]]
	_expect(not bool(_validate_tree_semantic_payload(malformed_polygon, passing_review, profile, texture_sha, base_sha, annotation_sha).get("accepted", false)), "zero-area geometry is rejected")
	var duplicate_vertex: Dictionary = author.duplicate(true)
	(duplicate_vertex["regions"] as Dictionary)["dark_side"] = [[[10, 10], [80, 10], [80, 80], [80, 10]]]
	_expect(not bool(_validate_tree_semantic_payload(duplicate_vertex, passing_review, profile, texture_sha, base_sha, annotation_sha).get("accepted", false)), "repeated polygon vertices are rejected rather than silently normalized")
	var extra_scope: Dictionary = passing_review.duplicate(true)
	extra_scope["approved_scope"] = ["dark_side_geometry", "outline_absence", "crown_geometry"]
	_expect(not bool(_validate_tree_semantic_payload(author, extra_scope, profile, texture_sha, base_sha, annotation_sha).get("accepted", false)), "unrequested review scope cannot be added during merge")
	var contradictory_absence: Dictionary = author.duplicate(true)
	(contradictory_absence["regions"] as Dictionary)["outline"] = (author.get("regions", {}) as Dictionary).get("dark_side", []).duplicate(true)
	_expect(not bool(_validate_tree_semantic_payload(contradictory_absence, passing_review, profile, texture_sha, base_sha, annotation_sha).get("accepted", false)), "outline polygons conflict with explicit absence and are rejected")

	var present_empty: Dictionary = author.duplicate(true)
	(present_empty["outline_semantics"] as Dictionary)["present"] = true
	(present_empty["regions"] as Dictionary)["outline"] = []
	var present_empty_review := _make_review_fixture(annotation_sha, texture_sha, base_sha, ["dark_side_geometry", "outline_geometry"])
	var present_empty_decision := _validate_tree_semantic_payload(present_empty, present_empty_review,
		profile, texture_sha, base_sha, annotation_sha)
	_expect(bool(present_empty_decision.get("accepted", false)), "valid dark-side geometry remains usable when declared-present outline geometry is absent")
	_expect(str(present_empty_decision.get("status", "")) == "PARTIAL_APPROVAL", "present outline with no polygon records partial semantic approval")
	_expect(_semantic_outline_status(present_empty_decision).get("status") == "NOT_TESTED", "present outline with an empty polygon array remains NOT_TESTED")
	var present_with_geometry: Dictionary = author.duplicate(true)
	(present_with_geometry["outline_semantics"] as Dictionary)["present"] = true
	(present_with_geometry["regions"] as Dictionary)["outline"] = [((author.get("regions", {}) as Dictionary).get("dark_side", []) as Array)[0].duplicate(true)]
	var present_geometry_decision := _validate_tree_semantic_payload(present_with_geometry,
		present_empty_review, profile, texture_sha, base_sha, annotation_sha)
	_expect(bool(present_geometry_decision.get("accepted", false)), "present outline geometry is accepted only with reviewed outline_geometry scope")
	_expect(_semantic_outline_status(present_geometry_decision).get("status") == "captured", "non-empty reviewed outline geometry is classified as captured")

	var base_annotation: Dictionary = {"review_status": "approved", "approved_scope": ["crown_geometry"], "regions": {"crown": [["frozen-crown"]], "dark_side": [], "outline": []}}
	var merged := _merge_approved_tree_regions(base_annotation, positive)
	_expect((merged.get("regions", {}) as Dictionary).get("crown", []) == [["frozen-crown"]], "merge preserves the frozen crown geometry unchanged")
	_expect((merged.get("regions", {}) as Dictionary).get("dark_side", []).size() == (positive.get("regions", {}) as Dictionary).get("dark_side", []).size(), "merge adds only the reviewed dark-side polygons")
	_expect(merged.get("review_status") == "approved" and merged.get("approved_scope", []) == ["crown_geometry"], "merge does not rewrite the author's pending review state or broaden base approval scope")

	var dark_image := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	dark_image.fill(Color(0.4, 0.2, 0.1, 0.0))
	dark_image.set_pixel(0, 0, Color(0.4, 0.2, 0.1, 0.5))
	dark_image.set_pixel(1, 0, Color(0.4, 0.2, 0.1, 0.75))
	var crown_image := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	crown_image.fill(Color(1.0, 1.0, 1.0, 0.0))
	crown_image.set_pixel(0, 0, Color(1.0, 1.0, 1.0, 1.0))
	var intersected: Image = _intersect_dark_side_with_crown(dark_image, crown_image)
	_expect(intersected != null and is_equal_approx(intersected.get_pixel(0, 0).a, dark_image.get_pixel(0, 0).a), "dark-side intersection preserves source alpha where crown and dark-side overlap")
	_expect(intersected != null and is_zero_approx(intersected.get_pixel(1, 0).a), "dark-side mask is transparent outside the frozen crown")

	var actual_review_snapshot := _read_tree_semantic_json_snapshot(TREE_SEMANTICS_REVIEW_PATH)
	if bool(actual_review_snapshot.get("read_ok", false)):
		var actual_review: Variant = actual_review_snapshot.get("value", null)
		var actual_decision := _validate_tree_semantic_payload(author, actual_review, profile,
			texture_sha, base_sha, annotation_sha)
		_expect(bool(actual_decision.get("accepted", false)), "current independent report binds the actual author, texture, and base-crown bytes")
		_expect(_semantic_outline_status(actual_decision).get("status") == "absent_authoritatively", "actual outline absence claim has its own reviewer evidence")
		_load_region_annotation(profile)
		_expect(_tree_semantic_status == "APPROVED", "runtime loader merges the actual independently reviewed semantic input")
		_expect(_region_scope_approved("crown_geometry") and _region_scope_approved("dark_side_geometry"), "runtime loader preserves frozen crown approval and adds only reviewed dark-side scope")
		_expect(_region_regions().get("dark_side", []).size() == 9, "runtime region view contains the nine source-bound dark-side polygons")
		_expect(_tree_outline_status(null).get("status") == "absent_authoritatively", "runtime outline status is backed by explicit outline_absence approval")
		_expect(_tree_semantic_inputs_unchanged(), "loaded author and reviewer byte snapshots still match on-disk inputs")
		var tree_parts := _parts_for_instance(null, "tree")
		_expect((tree_parts.get("complete_T3", {}) as Dictionary).get("status") == "NOT_RUN_BY_CAPTURE", "tree semantic availability never marks complete T3 measured")
		_expect((tree_parts.get("contact_shadow", {}) as Dictionary).get("status") == "NOT_TESTED", "tree contact shadow remains explicitly NOT_TESTED")

	if not _semantic_test_failures.is_empty():
		_abort("tree semantic input tests failed: " + "; ".join(_semantic_test_failures))
		return
	print("TERRAIN_TREE_SEMANTIC_INPUT_TEST " + JSON.stringify({
		"test_count": _semantic_test_count,
		"result": "PASS",
		"actual_review_file_present": bool(actual_review_snapshot.get("read_ok", false)),
		"actual_author_sha256": annotation_sha,
		"pixel_capture": false,
		"T3_status": "NOT_RUN_BY_CAPTURE",
	}))
	quit(0)


func _make_review_fixture(annotation_sha: String, texture_sha: String, base_sha: String,
		approved_scope: Array[String]) -> Dictionary:
	return {
		"verdict": "PASS",
		"schema_version": TREE_SEMANTICS_REVIEW_SCHEMA,
		"annotation_sha256": annotation_sha,
		"texture_sha256": texture_sha,
		"base_crown_annotation_sha256": base_sha,
		"approved_scope": approved_scope,
	}


func _expect(condition: bool, label: String) -> void:
	_semantic_test_count += 1
	if not condition:
		_semantic_test_failures.append(label)
