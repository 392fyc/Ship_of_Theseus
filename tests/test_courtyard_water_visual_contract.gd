extends SceneTree
## 仅用于固定像素几何的单元测试，不代表运行配置；截图仅作诊断，不得作为视觉验收证据。
## 在固定 Godot 视口中采集正确样本及三种错误样本，并用同一图像检查器测量。

const CaptureMetadata := preload("res://tests/claude_review/capture_metadata.gd")
const BoardView := preload("res://scripts/ui/playground/courtyard_board_view.gd")
const PROFILE_PATH := "res://assets/prototype/battlefield_courtyard/visual_profile.json"
const CONTRACT_PATH := "res://dev_doc/ui-art-research/visual-review/water-visual-contract.json"
const CENTER := Vector2i(2, 2)
const BANK_CENTER := Vector2i(1, 1)
const SHALLOW_RING_DEEP_CENTER: Array = [
	[5,5,5,5,5], [5,6,6,6,5], [5,6,6,6,5], [5,6,6,6,5], [5,5,5,5,5],
]
const ALL_SHALLOW: Array = [
	[5,5,5,5,5], [5,5,5,5,5], [5,5,5,5,5], [5,5,5,5,5], [5,5,5,5,5],
]
const STONE_SHORE: Array = [[0, 0, 0], [0, 5, 0], [0, 0, 0]]
const BOARD_VIEWPORT := Vector2i(360, 280)
const BOARD_SCALE := 1.5
const LABELS := [
	"多格深水核心：端点色调校准",
	"浅水中心参照",
	"故意错误：深水画成浅水",
	"无岸沿图像参照",
	"当前石岸渲染",
	"故意错误：旧式等宽实色岸沿",
]
const CASE_NAMES := [
	"depth-correct",
	"depth-shallow-reference",
	"depth-shallow-tint-fault",
	"bank-no-edge-reference",
	"bank-current",
	"bank-legacy-band-fault",
]
const SOURCE_PATHS: Array[String] = [
	"res://tests/test_courtyard_water_visual_contract.gd",
	"res://tests/test_courtyard_terrain_adjacency.gd",
	"res://dev_doc/ui-art-research/visual-review/water-visual-contract.json",
	"res://scripts/ui/playground/courtyard_board_view.gd",
	"res://assets/prototype/battlefield_courtyard/visual_profile.json",
]

class ShallowTintFaultView:
	extends "res://scripts/ui/playground/courtyard_board_view.gd"

	func _draw_cell_surface(pos: Vector2i) -> void:
		if grid.get_cell(pos).terrain == Cell.Terrain.DEEP_WATER:
			_surface(pos.x - 0.5, pos.y - 0.5, pos.x + 0.5, pos.y + 0.5,
				_water, Color("89b9be"), 8.0)
			_draw_ripple(grid.grid_to_world(pos), float(pos.x * 7 + pos.y * 3), false)
			return
		super._draw_cell_surface(pos)


class LegacyStoneBandOverlay:
	extends Node2D

	var board: Node2D

	func _draw() -> void:
		var edges: Array = board.call("transition_edges", Vector2i(1, 1))
		var corners: PackedVector2Array = board.call("diamond", Vector2i(1, 1))
		var grid: Grid = board.get("grid")
		var center: Vector2 = grid.grid_to_world(Vector2i(1, 1))
		for transition: Dictionary in edges:
			if transition["kind"] != "stone_bank":
				continue
			var edge: int = int(transition["edge"])
			var a: Vector2 = corners[edge]
			var b: Vector2 = corners[(edge + 1) % 4]
			var inward: Vector2 = (center - (a + b) * 0.5).normalized()
			var land: Vector2 = -inward * 4.5
			var cap := PackedVector2Array([a, b, b + land * 0.65, a + land * 0.65])
			var uv := PackedVector2Array()
			var origin: Vector2 = grid.grid_to_world(Vector2i.ZERO)
			for point: Vector2 in cap:
				var relative: Vector2 = point - origin
				uv.append(Vector2((relative.x / 32.0 + relative.y / 16.0) * 0.5,
					(relative.y / 16.0 - relative.x / 32.0) * 0.5) / 8.0)
			var ground: Texture2D = board.get("_ground")
			draw_colored_polygon(cap, Color("a4a38f"), uv, ground)
			var water_band := PackedVector2Array([a, b, b + inward * 2.5, a + inward * 2.5])
			draw_colored_polygon(water_band, Color("424b3b"))


var _contract: Dictionary = {}
var _output: String = ""
var _cases: Array[Dictionary] = []
var _source_hashes: Dictionary = {}
var _capture_records: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			_output = arg.trim_prefix("--output=")
	if DisplayServer.get_name() == "headless":
		push_error("水面视觉合同要求实际 Godot 图形渲染，不能在 headless 模式采集。")
		quit(1)
		return
	if _output.is_empty() or not _output.is_absolute_path():
		push_error("视觉合同采集需要 --output=<absolute-directory>。")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(_output) != OK:
		push_error("无法创建视觉合同输出目录。")
		quit(1)
		return
	_contract = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	if str(_contract.get("contract_id", "")) != "water-visual-contract-v2":
		push_error("水面视觉合同缺失或版本不符。")
		quit(1)
		return
	var source_paths: Array[String] = SOURCE_PATHS.duplicate()
	for source: String in source_paths:
		_source_hashes[source] = FileAccess.get_sha256(source)
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	var water_path: String = str(profile["water"])
	if not source_paths.has(water_path):
		source_paths.append(water_path)
	_source_hashes[water_path] = FileAccess.get_sha256(water_path)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1248, 664)
	root.title = "Courtyard water visual contract"
	_create_case("depth-correct", SHALLOW_RING_DEEP_CENTER, [], false)
	_create_case("depth-shallow-reference", ALL_SHALLOW, [], false)
	_create_case("depth-shallow-tint-fault", SHALLOW_RING_DEEP_CENTER, [], true)
	_create_case("bank-no-edge-reference", STONE_SHORE, _all_paving(), false, true, false)
	_create_case("bank-current", STONE_SHORE, _all_paving(), false, false, false)
	_create_case("bank-legacy-band-fault", STONE_SHORE, _all_paving(), false, true, true)
	await _frames(4)
	for item: Dictionary in _cases:
		var view: Node2D = item["view"]
		view.set("_time", float(_contract["capture"]["fixed_water_animation_time_seconds"]))
		view.set_process(false)
		view.queue_redraw()
	await _frames(2)
	await RenderingServer.frame_post_draw
	var results := _run_checkers()
	var images_ok: bool = _save_case_images()
	var stable_sources: bool = _source_hashes_unchanged()
	var diagnostic_image := root.get_texture().get_image()
	var diagnostic_path: String = _output.path_join("water-visual-diagnostic-comparison.png")
	var diagnostic_saved: bool = diagnostic_image.save_png(diagnostic_path) == OK
	if diagnostic_saved:
		_capture_records.append(CaptureMetadata.capture_record(root, diagnostic_image, diagnostic_path, {
			"capture_kind": "diagnostic", "runtime_evidence": false,
			"diagnostic_purpose": "fixed-pixel water contract comparison",
		}))
	var metadata_ok: bool = CaptureMetadata.write_manifest(root, _output.path_join("capture-metadata.json"),
		_capture_records, {"runtime_evidence": false, "diagnostic_purpose": "fixed-pixel water contract comparison"})
	var negative_blocked: bool = bool(results["negative_samples_blocked"])
	var positives_passed: bool = bool(results["positive_samples_passed"])
	var overall_pass: bool = negative_blocked and positives_passed and images_ok and stable_sources and diagnostic_saved and metadata_ok
	var image_hashes: Dictionary = {}
	for filename: String in [
		"water-depth-correct.png",
		"water-depth-semantic-negative.png",
		"water-depth-render-negative.png",
		"stone-bank-reference.png",
		"stone-bank-current.png",
		"stone-bank-legacy-negative.png",
		"water-visual-diagnostic-comparison.png",
	]:
		var image_path: String = _output.path_join(filename)
		if FileAccess.file_exists(image_path):
			image_hashes[filename] = FileAccess.get_sha256(image_path)
	var report: Dictionary = {
		"contract_id": _contract["contract_id"],
		"captured_at_utc": Time.get_datetime_string_from_system(true),
		"engine": Engine.get_version_info()["string"],
		"fixed_animation_time_seconds": _contract["capture"]["fixed_water_animation_time_seconds"],
		"viewport_px": _contract["capture"]["viewport_px"],
		"board_scale": _contract["capture"]["board_scale"],
		"depth_core_board_scale": _contract["capture"]["depth_core_board_scale"],
		"source_sha256": _source_hashes,
		"image_sha256": image_hashes,
		"renderer": str(RenderingServer.get_current_rendering_method()),
		"project_stretch_mode": str(ProjectSettings.get_setting("display/window/stretch/mode")),
		"runtime_evidence": false,
		"capture_metadata_saved": metadata_ok,
		"captures": _capture_records,
		"checker_results": results["checker_results"],
		"negative_samples_blocked": negative_blocked,
		"positive_samples_passed": positives_passed,
		"image_files_saved": images_ok and diagnostic_saved,
		"source_hashes_stable_after_capture": stable_sources,
		"overall": "PASS" if overall_pass else "FAIL",
		"limits": _contract["stone_bank_checker"]["limitations"],
	}
	var report_file := FileAccess.open(_output.path_join("water-visual-contract-report.json"), FileAccess.WRITE)
	if report_file == null:
		push_error("水面视觉检查报告无法保存。")
		quit(1)
		return
	report_file.store_string(JSON.stringify(report, "  "))
	report_file.close()
	print("COURTYARD_WATER_VISUAL_CONTRACT_RESULT ", JSON.stringify({
		"overall": report["overall"],
		"negative_samples_blocked": negative_blocked,
		"positive_samples_passed": positives_passed,
		"images_saved": report["image_files_saved"],
		"source_hashes_stable": stable_sources,
		"report": "water-visual-contract-report.json",
	}))
	quit(0 if overall_pass else 1)


func _create_case(case_name: String, rows: Array, paving: Array, shallow_tint_fault: bool,
		without_bank: bool = false, legacy_overlay: bool = false) -> void:
	var index: int = _cases.size()
	var viewport := SubViewport.new()
	viewport.size = BOARD_VIEWPORT
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.transparent_bg = false
	var grid := Grid.new()
	var layout: Dictionary = {"id": case_name, "width": rows[0].size(), "height": rows.size(),
		"terrain": rows.duplicate(true), "transition_preview": true, "paving": paving.duplicate(true)}
	grid.initialize(layout)
	var view: Node2D = ShallowTintFaultView.new() if shallow_tint_fault else BoardView.new()
	view.call("configure", grid, _profile(), layout)
	view.set("grid_visible", false)
	var case_center: Vector2i = CENTER if case_name.begins_with("depth-") else BANK_CENTER
	var zoom: float = float(_contract["capture"]["depth_core_board_scale"]) if case_name.begins_with("depth-") else BOARD_SCALE
	view.scale = Vector2.ONE * zoom
	view.position = Vector2(BOARD_VIEWPORT) * 0.5 - grid.grid_to_world(case_center) * zoom
	viewport.add_child(view)
	var container := SubViewportContainer.new()
	container.stretch = false
	container.position = Vector2(16 + (index % 3) * 408, 42 + floori(float(index) / 3.0) * 320)
	container.size = Vector2(BOARD_VIEWPORT)
	container.add_child(viewport)
	root.add_child(container)
	var label := Label.new()
	label.text = LABELS[index]
	label.position = container.position + Vector2(0, -25)
	label.theme = load("res://assets/ui/themes/hud_m2.tres") as Theme
	label.add_theme_color_override("font_color", Color("e4dfc9"))
	label.add_theme_font_size_override("font_size", 17)
	root.add_child(label)
	_cases.append({"name": case_name, "rows": rows.duplicate(true), "grid": grid,
		"view": view, "viewport": viewport, "label": label})
	if without_bank:
		await _frames(1)
		_remove_stone_bank_edges(view)
	if legacy_overlay:
		await _frames(1)
		var overlay := LegacyStoneBandOverlay.new()
		overlay.board = view
		view.add_child(overlay)
		overlay.queue_redraw()


func _remove_stone_bank_edges(view: Node2D) -> void:
	var kept: Array[Dictionary] = []
	for transition: Dictionary in view.get("_transition_cache"):
		if transition["kind"] != "stone_bank":
			kept.append(transition)
	view.set("_transition_cache", kept)
	view.queue_redraw()


func _profile() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))


func _all_paving() -> Array:
	var paving: Array = []
	for y: int in 3:
		for x: int in 3:
			paving.append([x, y])
	return paving


func _run_checkers() -> Dictionary:
	var correct: Dictionary = _case("depth-correct")
	var shallow_reference: Dictionary = _case("depth-shallow-reference")
	var bad_data: Dictionary = _case("depth-shallow-reference")
	var bad_tint: Dictionary = _case("depth-shallow-tint-fault")
	var expected: int = int(_contract["fixture"]["expected_center_terrain_id"])
	var observed_correct: int = (correct["grid"] as Grid).get_cell(CENTER).terrain
	var observed_bad_data: int = (bad_data["grid"] as Grid).get_cell(CENTER).terrain
	var fixture_matches_contract: bool = _matrix_matches(
		correct["rows"], _contract["fixture"]["terrain_rows"])
	var semantic_good: bool = observed_correct == expected and fixture_matches_contract
	var semantic_bad: bool = observed_bad_data == expected
	var shallow_mean: float = _mean_luma_patch(shallow_reference, "depth_image_checker")
	var deep_mean: float = _mean_luma_patch(correct, "depth_image_checker")
	var bad_tint_mean: float = _mean_luma_patch(bad_tint, "depth_image_checker")
	var minimum_depth_delta: float = float(_contract["depth_image_checker"]["minimum_shallow_minus_deep_mean"])
	var correct_delta: float = shallow_mean - deep_mean
	var bad_tint_delta: float = shallow_mean - bad_tint_mean
	var depth_image_good: bool = correct_delta >= minimum_depth_delta
	var depth_image_bad: bool = bad_tint_delta >= minimum_depth_delta
	var bank_reference: Dictionary = _case("bank-no-edge-reference")
	var bank_current: Dictionary = _case("bank-current")
	var bank_legacy: Dictionary = _case("bank-legacy-band-fault")
	var current_bank_metrics: Dictionary = _bank_metrics(bank_reference, bank_current)
	var legacy_bank_metrics: Dictionary = _bank_metrics(bank_reference, bank_legacy)
	var current_bank_good: bool = _bank_passes(current_bank_metrics)
	var legacy_bank_rejected: bool = not _bank_passes(legacy_bank_metrics)
	var checker_results: Dictionary = {
		"depth_semantics": {
			"expected_center_terrain_id": expected,
			"correct_fixture_matches_independent_contract": fixture_matches_contract,
			"correct_sample_observed_center_terrain_id": observed_correct,
			"correct_sample_result": "PASS" if semantic_good else "FAIL",
			"negative_shallow_center_observed_terrain_id": observed_bad_data,
			"negative_shallow_center_result": "PASS" if semantic_bad else "FAIL",
			"negative_blocked": not semantic_bad,
		},
		"depth_rendered_luminance": {
			"metric": "shallow_reference_mean_channel_value - deep_center_mean_channel_value",
			"minimum_delta": minimum_depth_delta,
			"shallow_reference_mean": shallow_mean,
			"deep_correct_mean": deep_mean,
			"correct_delta": correct_delta,
			"correct_sample_result": "PASS" if depth_image_good else "FAIL",
			"deep_data_shallow_tint_mean": bad_tint_mean,
			"negative_shallow_tint_delta": bad_tint_delta,
			"negative_shallow_tint_result": "FAIL" if not depth_image_bad else "PASS",
			"negative_blocked": not depth_image_bad,
		},
		"stone_bank_uniform_band": {
			"reject_positive_brightness_coverage_at_or_above": float(
				_contract["stone_bank_checker"]["reject_positive_brightness_coverage"]),
			"reject_uniform_color_band_coverage_at_or_above": float(
				_contract["stone_bank_checker"]["reject_uniform_color_band_coverage"]),
			"current_bank_metrics": current_bank_metrics,
			"current_bank_result": "PASS" if current_bank_good else "FAIL",
			"negative_legacy_metrics": legacy_bank_metrics,
			"negative_legacy_result": "FAIL" if legacy_bank_rejected else "PASS",
			"negative_blocked": legacy_bank_rejected,
		},
	}
	var negatives_blocked: bool = not semantic_bad and not depth_image_bad and legacy_bank_rejected
	var positives_passed: bool = semantic_good and depth_image_good and current_bank_good
	return {"checker_results": checker_results,
		"negative_samples_blocked": negatives_blocked,
		"positive_samples_passed": positives_passed}


func _mean_luma_patch(item: Dictionary, checker_name: String) -> float:
	var viewport: SubViewport = item["viewport"]
	var image: Image = viewport.get_texture().get_image()
	var contract: Dictionary = _contract[checker_name]
	var offset: Array = contract["sample_local_offset_from_center_px"]
	var view: Node2D = item["view"]
	var grid: Grid = item["grid"]
	var center_local: Vector2 = grid.grid_to_world(CENTER) + Vector2(offset[0], offset[1])
	var center_pixel: Vector2 = view.get_global_transform_with_canvas() * center_local
	var half: int = floori(float(contract["sample_patch_px"]) / 2.0)
	var sum: float = 0.0
	var count: int = 0
	for y: int in range(floori(center_pixel.y) - half, floori(center_pixel.y) + half + 1):
		for x: int in range(floori(center_pixel.x) - half, floori(center_pixel.x) + half + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			var pixel: Color = image.get_pixel(x, y)
			sum += _channel_mean(pixel)
			count += 1
	return sum / float(maxi(count, 1))


func _bank_metrics(reference_case: Dictionary, candidate_case: Dictionary) -> Dictionary:
	var reference: Image = (reference_case["viewport"] as SubViewport).get_texture().get_image()
	var candidate: Image = (candidate_case["viewport"] as SubViewport).get_texture().get_image()
	var reference_view: Node2D = reference_case["view"]
	var candidate_view: Node2D = candidate_case["view"]
	var reference_grid: Grid = reference_case["grid"]
	var candidate_grid: Grid = candidate_case["grid"]
	var contract: Dictionary = _contract["stone_bank_checker"]
	var fractions: Array = contract["edge_sample_fractions"]
	var start: float = float(contract["scan_from_water_edge_px"])
	var finish: float = float(contract["scan_to_water_interior_px"])
	var step: float = float(contract["scan_step_px"])
	var min_delta: float = float(contract["minimum_channel_delta"])
	var min_width: float = float(contract["uniform_band_min_width_px"])
	var detected_rays: int = 0
	var ray_count: int = 0
	var widths: Array[float] = []
	var maximum_positive_luma: float = 0.0
	var positive_rays: int = 0
	var minimum_positive_luma: float = float(contract["minimum_positive_luminance_delta"])
	var maximum_channel_delta: float = 0.0
	var corners: PackedVector2Array = candidate_view.call("diamond", BANK_CENTER)
	for edge_value: Variant in contract["scanned_edges"]:
		var edge: int = int(edge_value)
		var a: Vector2 = corners[edge]
		var b: Vector2 = corners[(edge + 1) % 4]
		var local_inward: Vector2 = (candidate_grid.grid_to_world(BANK_CENTER) - (a + b) * 0.5).normalized()
		var candidate_transform: Transform2D = candidate_view.get_global_transform_with_canvas()
		var reference_transform: Transform2D = reference_view.get_global_transform_with_canvas()
		var a_candidate: Vector2 = candidate_transform * a
		var b_candidate: Vector2 = candidate_transform * b
		var inward_candidate: Vector2 = candidate_transform.basis_xform(local_inward).normalized()
		var a_reference: Vector2 = reference_transform * a
		var b_reference: Vector2 = reference_transform * b
		var inward_reference: Vector2 = reference_transform.basis_xform(local_inward).normalized()
		for fraction_value: Variant in fractions:
			var fraction: float = float(fraction_value)
			var candidate_edge_point: Vector2 = a_candidate.lerp(b_candidate, fraction)
			var reference_edge_point: Vector2 = a_reference.lerp(b_reference, fraction)
			var run: int = 0
			var longest_run: int = 0
			var positive_at_ray: bool = false
			var ray_positive_peak: float = 0.0
			var distance: float = start
			while distance <= finish + 0.001:
				var candidate_pixel: Vector2 = candidate_edge_point + inward_candidate * distance
				var reference_pixel: Vector2 = reference_edge_point + inward_reference * distance
				var color_delta: Color = _sample_bilinear(candidate, candidate_pixel) - _sample_bilinear(reference, reference_pixel)
				var max_delta: float = maxf(absf(color_delta.r), maxf(absf(color_delta.g), absf(color_delta.b)))
				maximum_channel_delta = maxf(maximum_channel_delta, max_delta)
				if max_delta >= min_delta:
					run += 1
					longest_run = maxi(longest_run, run)
				else:
					run = 0
				var luma_delta: float = _channel_mean(_sample_bilinear(candidate, candidate_pixel)) \
					- _channel_mean(_sample_bilinear(reference, reference_pixel))
				maximum_positive_luma = maxf(maximum_positive_luma, luma_delta)
				ray_positive_peak = maxf(ray_positive_peak, luma_delta)
				distance += step
			var run_width: float = float(longest_run) * step
			if run_width >= min_width:
				detected_rays += 1
				widths.append(run_width)
			if ray_positive_peak >= minimum_positive_luma:
				positive_at_ray = true
			if positive_at_ray:
				positive_rays += 1
			ray_count += 1
	widths.sort()
	var median_width: float = 0.0
	if not widths.is_empty():
		median_width = widths[floori(float(widths.size()) / 2.0)]
	return {
		"scanned_edge_samples": ray_count,
		"uniform_color_band_coverage": float(detected_rays) / float(maxi(ray_count, 1)),
		"detected_band_ray_count": detected_rays,
		"median_detected_band_width_px": median_width,
		"maximum_positive_luminance_delta": maximum_positive_luma,
		"positive_brightness_coverage": float(positive_rays) / float(maxi(ray_count, 1)),
		"maximum_absolute_channel_delta": maximum_channel_delta,
	}


func _bank_passes(metrics: Dictionary) -> bool:
	var checker: Dictionary = _contract["stone_bank_checker"]
	var uniform_color_clear: bool = float(metrics["uniform_color_band_coverage"]) < float(
		checker["reject_uniform_color_band_coverage"])
	var brightness_clear: bool = float(metrics["positive_brightness_coverage"]) < float(
		checker["reject_positive_brightness_coverage"])
	return uniform_color_clear and brightness_clear


func _sample_bilinear(image: Image, position: Vector2) -> Color:
	var x0: int = clampi(floori(position.x), 0, image.get_width() - 1)
	var y0: int = clampi(floori(position.y), 0, image.get_height() - 1)
	var x1: int = mini(x0 + 1, image.get_width() - 1)
	var y1: int = mini(y0 + 1, image.get_height() - 1)
	var fx: float = clampf(position.x - floorf(position.x), 0.0, 1.0)
	var fy: float = clampf(position.y - floorf(position.y), 0.0, 1.0)
	var top: Color = image.get_pixel(x0, y0).lerp(image.get_pixel(x1, y0), fx)
	var bottom: Color = image.get_pixel(x0, y1).lerp(image.get_pixel(x1, y1), fx)
	return top.lerp(bottom, fy)


func _channel_mean(color: Color) -> float:
	return (color.r + color.g + color.b) / 3.0


func _matrix_matches(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for y: int in left.size():
		var left_row: Array = left[y]
		var right_row: Array = right[y]
		if left_row.size() != right_row.size():
			return false
		for x: int in left_row.size():
			if int(left_row[x]) != int(right_row[x]):
				return false
	return true


func _case(case_name: String) -> Dictionary:
	for item: Dictionary in _cases:
		if item["name"] == case_name:
			return item
	return {}


func _save_case_images() -> bool:
	var filenames: Array[String] = [
		"water-depth-correct.png",
		"water-depth-semantic-negative.png",
		"water-depth-render-negative.png",
		"stone-bank-reference.png",
		"stone-bank-current.png",
		"stone-bank-legacy-negative.png",
	]
	var success: bool = true
	for index: int in _cases.size():
		var item: Dictionary = _cases[index]
		var image: Image = (item["viewport"] as SubViewport).get_texture().get_image()
		var path: String = _output.path_join(filenames[index])
		var saved: bool = image.save_png(path) == OK
		success = saved and success
		if saved:
			_capture_records.append(CaptureMetadata.capture_record(root, image, path, {
				"capture_kind": "diagnostic", "runtime_evidence": false,
				"diagnostic_purpose": "fixed-pixel water contract sample",
			}))
	return success


func _source_hashes_unchanged() -> bool:
	for path: String in _source_hashes.keys():
		if FileAccess.get_sha256(path) != _source_hashes[path]:
			return false
	return true


func _frames(count: int) -> void:
	for unused: int in count:
		await process_frame
