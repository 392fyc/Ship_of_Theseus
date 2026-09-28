extends SceneTree
## 仅用于固定像素几何的单元测试，不代表运行配置；截图仅作诊断，不得作为视觉验收证据。
## 用独立样例与实际像素曲线验证水深连续性；错误对照使用同一检查器。

const CaptureMetadata := preload("res://tests/claude_review/capture_metadata.gd")
const CONTRACT := "res://dev_doc/ui-art-research/visual-review/water-depth-continuity-contract.json"
const PROFILE := "res://assets/prototype/battlefield_courtyard/visual_profile.json"
const BOARD := "res://scripts/ui/playground/courtyard_board_view.gd"
const VIEW_SIZE := Vector2i(560, 380)
const VIEW_SCALE := 1.15

class InspectBoard:
	extends "res://scripts/ui/playground/courtyard_board_view.gd"
	var mode: String = "current"
	var neutral: bool = true

	func _draw_ripple(p: Vector2, phase: float, deep: bool) -> void:
		if not neutral:
			super._draw_ripple(p, phase, deep)

	func _draw_water_surface(pos: Vector2i, ripple: bool = true) -> void:
		if mode == "current":
			super._draw_water_surface(pos, ripple)
			return
		var tint := Color("234f62") if visual_water_terrain(pos) == Cell.Terrain.DEEP_WATER else Color("89b9be")
		_surface(pos.x - 0.5, pos.y - 0.5, pos.x + 0.5, pos.y + 0.5, _water, tint)

	func _draw_terrain_transitions() -> void:
		super._draw_terrain_transitions()
		if mode != "legacy":
			return
		for edge: Dictionary in _transition_cache:
			if edge["kind"] != "depth_blend":
				continue
			var pos: Vector2i = edge["cell"]
			var points: PackedVector2Array = diamond(pos)
			var index: int = edge["edge"]
			var a: Vector2 = points[index]
			var b: Vector2 = points[(index + 1) % 4]
			var inward: Vector2 = (grid.grid_to_world(pos) - (a + b) * 0.5).normalized()
			for strip: int in 5:
				var outer: Vector2 = inward * (-4.0 + float(strip) * 1.6)
				var inner: Vector2 = outer + inward * 1.6
				var tint: Color = Color("234f62").lerp(Color("89b9be"), float(strip + 1) / 6.0)
				_textured_ground_polygon(PackedVector2Array([a + outer, b + outer, b + inner, a + inner]), _water, tint)

var _spec: Dictionary
var _profile: Dictionary
var _cases: Dictionary = {}
var _output: String
var _sources: Dictionary = {}
var _image_hashes: Dictionary = {}
var _capture_records: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			_output = arg.trim_prefix("--output=")
	if DisplayServer.get_name() == "headless" or not _output.is_absolute_path():
		push_error("连续性检查需要实际图形渲染与绝对路径 --output。")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_output)
	_spec = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT))
	_profile = JSON.parse_string(FileAccess.get_file_as_string(PROFILE))
	for path: String in [CONTRACT, PROFILE, BOARD, get_script().resource_path, str(_profile["water"])]:
		_sources[path] = FileAccess.get_sha256(path)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1232, 346)
	_make_case("basin", "basin_fixture")
	_make_case("hard", "basin_fixture", "hard")
	_make_case("legacy", "basin_fixture", "legacy")
	_make_case("extension", "flooded_extension_fixture")
	_make_case("single", "single_cell_fixture")
	_make_case("material", "basin_fixture", "current", false)
	_make_case("single-material", "single_cell_fixture", "current", false)
	for frame: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var results: Dictionary = _check_all()
	var image_ok: bool = true
	var names: Dictionary = {"basin":"water-depth-neutral.png", "hard":"water-depth-hard-cut-negative.png",
		"legacy":"water-depth-narrow-strip-negative.png", "extension":"water-depth-extension-neutral.png",
		"single":"water-depth-single-neutral.png", "material":"water-depth-basin.png", "single-material":"water-depth-single-cell.png"}
	for key: String in names:
		image_ok = _save_image(str(names[key]), (_cases[key]["viewport"] as SubViewport).get_texture().get_image()) and image_ok
	_show_comparison()
	for frame: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	image_ok = _save_image("water-depth-continuity-comparison.png", root.get_texture().get_image()) and image_ok
	var stable: bool = true
	for path: String in _sources:
		stable = stable and FileAccess.get_sha256(path) == _sources[path]
	var metadata_ok: bool = CaptureMetadata.write_manifest(root, _output.path_join("capture-metadata.json"),
		_capture_records, {"runtime_evidence": false, "diagnostic_purpose": "fixed-pixel water depth contract"})
	var overall: bool = bool(results["positive_samples_passed"]) and bool(results["negative_samples_blocked"]) and image_ok and stable and metadata_ok
	var report: Dictionary = {"overall":"PASS" if overall else "FAIL", "contract_id":_spec["contract_id"],
		"captured_at_utc":Time.get_datetime_string_from_system(true), "engine":Engine.get_version_info()["string"],
		"renderer":str(RenderingServer.get_current_rendering_method()),
		"project_stretch_mode":str(ProjectSettings.get_setting("display/window/stretch/mode")),
		"runtime_evidence":false, "capture_metadata_saved":metadata_ok, "captures":_capture_records,
		"viewport_px":[VIEW_SIZE.x, VIEW_SIZE.y], "board_scale":VIEW_SCALE, "fixed_animation_time":0.0,
		"neutral_curves_ripples":false, "material_preview_ripples":true,
		"positive_samples_passed":results["positive_samples_passed"], "negative_samples_blocked":results["negative_samples_blocked"],
		"checker_results":results, "source_sha256":_sources, "image_sha256":_image_hashes,
		"images_saved":image_ok, "source_hashes_stable":stable, "limits":_spec["limitations"]}
	var file := FileAccess.open(_output.path_join("water-depth-continuity-report.json"), FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("COURTYARD_WATER_DEPTH_CONTINUITY_RESULT ", JSON.stringify({"overall":report["overall"],
		"positive_samples_passed":report["positive_samples_passed"], "negative_samples_blocked":report["negative_samples_blocked"],
		"images_saved":image_ok, "source_hashes_stable":stable}))
	quit(0 if overall else 1)

func _make_case(key: String, fixture_name: String, mode: String = "current", neutral: bool = true) -> void:
	var fixture: Dictionary = _spec[fixture_name]
	var grid := Grid.new()
	var layout: Dictionary = {"id":key, "width":fixture["width"], "height":fixture["height"],
		"terrain":fixture["terrain_rows"], "paving":[], "transition_preview":fixture_name != "flooded_extension_fixture"}
	if fixture.has("environment"):
		layout["environment"] = fixture["environment"]
	grid.initialize(layout)
	var viewport := SubViewport.new()
	viewport.size = VIEW_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var view := InspectBoard.new()
	view.mode = mode
	view.neutral = neutral
	view.configure(grid, _profile, layout)
	if neutral:
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.width = 8
		texture.height = 8
		view.set("_water", texture)
	view.grid_visible = false
	view.scale = Vector2.ONE * VIEW_SCALE
	var center := Vector2((float(fixture["width"]) - 1.0) * 0.5, (float(fixture["height"]) - 1.0) * 0.5)
	view.position = Vector2(VIEW_SIZE) * 0.5 - view.point(center.x, center.y) * VIEW_SCALE
	viewport.add_child(view)
	view.set_process(false)
	_cases[key] = {"viewport":viewport, "view":view, "grid":grid}

func _check_all() -> Dictionary:
	var curves: Dictionary = {}
	var bad: Dictionary = {}
	var positive: bool = true
	var negatives: bool = true
	var sampling: Dictionary = _spec["neutral_curve_sampling"]
	for path: Dictionary in sampling["required_curves"]:
		var key: String = "extension" if path["fixture"] == "flooded_extension_fixture" else "basin"
		var points: Dictionary = _sample_line(key, path["from"], path["to"], int(sampling["samples_per_curve"]))
		var result: Dictionary = _check_curve(points)
		curves[path["name"]] = result
		positive = positive and bool(result["passed"])
		if key == "basin":
			for fault: String in ["hard", "legacy"]:
				var failed: Dictionary = _check_curve(_sample_line(fault, path["from"], path["to"], int(sampling["samples_per_curve"])))
				bad[fault + "/" + str(path["name"])] = failed
				negatives = negatives and not bool(failed["passed"])
	var single: Dictionary = _check_single()
	positive = positive and bool(single["passed"]) and curves.size() == 4
	negatives = negatives and bad.size() == 6
	return {"curves":curves, "negative_curves":bad, "single_cell":single,
		"positive_samples_passed":positive, "negative_samples_blocked":negatives}

func _sample_line(key: String, start: Array, finish: Array, count: int) -> Dictionary:
	var view: Node2D = _cases[key]["view"]
	var image: Image = (_cases[key]["viewport"] as SubViewport).get_texture().get_image()
	var a: Vector2 = view.get_global_transform_with_canvas() * view.call("point", float(start[0]), float(start[1]))
	var b: Vector2 = view.get_global_transform_with_canvas() * view.call("point", float(finish[0]), float(finish[1]))
	var values: Array[float] = []
	for i: int in count:
		values.append(_sample_mean(image, a.lerp(b, float(i) / float(count - 1))))
	return {"values":values, "span_px":a.distance_to(b), "from_px":[a.x,a.y], "to_px":[b.x,b.y]}

func _sample_mean(image: Image, pos: Vector2) -> float:
	var x: int = clampi(floori(pos.x), 0, image.get_width() - 2)
	var y: int = clampi(floori(pos.y), 0, image.get_height() - 2)
	var tx: float = clampf(pos.x - x, 0.0, 1.0)
	var ty: float = clampf(pos.y - y, 0.0, 1.0)
	var a: Color = image.get_pixel(x,y).lerp(image.get_pixel(x+1,y),tx)
	var b: Color = image.get_pixel(x,y+1).lerp(image.get_pixel(x+1,y+1),tx)
	var c: Color = a.lerp(b,ty)
	return (c.r + c.g + c.b) / 3.0

func _check_curve(points: Dictionary) -> Dictionary:
	var rule: Dictionary = _spec["neutral_curve_sampling"]["common_checker"]
	var values: Array = points["values"]
	var delta: float = float(values[0]) - float(values[-1])
	var mid: int = 0
	var bins: Dictionary = {}
	var monotonic: int = 0
	var jump: float = 0.0
	var first_mid: int = -1
	var last_mid: int = -1
	for i: int in values.size():
		var value: float = values[i]
		if value >= float(values[-1]) + delta * 0.1 and value <= float(values[0]) - delta * 0.1:
			mid += 1
			bins[floori(value / float(rule["midrange_bin_width"]))] = true
			if first_mid < 0:
				first_mid = i
			last_mid = i
		if i > 0:
			var step: float = value - float(values[i-1])
			monotonic += 1 if step <= float(rule["monotonic_slack"]) else 0
			jump = maxf(jump, absf(step))
	var passed: bool = delta >= float(rule["minimum_endpoint_rgb_mean_difference"]) and mid >= int(rule["minimum_samples_in_endpoint_contrast_10_to_90_percent"])
	passed = passed and bins.size() >= int(rule["minimum_distinct_midrange_bins"]) and monotonic >= int(rule["minimum_monotonic_steps_out_of_16"])
	passed = passed and jump <= float(rule["maximum_adjacent_rgb_mean_step"])
	var result: Dictionary = points.duplicate(true)
	result.merge({"passed":passed, "endpoint_delta":delta, "middle_samples":mid, "middle_bins":bins.size(),
		"monotonic_steps":monotonic, "maximum_step":jump,
		"middle_span_px":float(maxi(0,last_mid-first_mid)) / float(values.size()-1) * float(points["span_px"])})
	return result

func _check_single() -> Dictionary:
	var rule: Dictionary = _spec["single_cell_checker"]
	var n: int = int(rule["samples_per_half"])
	var path: Dictionary = rule["path"]
	var left: Array = _sample_line("single",path["from"],path["through"],n)["values"]
	var right: Array = _sample_line("single",path["through"],path["to"],n)["values"]
	var core: float = _sample_line("basin",[3,3],[3,3],2)["values"][0]
	var darkening: float = (float(left[0]) + float(right[-1])) * 0.5 - float(left[-1])
	var lift: float = float(left[-1]) - core
	var jump: float = 0.0
	var left_steps: int = 0
	var right_steps: int = 0
	for i: int in range(1,n):
		left_steps += 1 if float(left[i])-float(left[i-1]) <= float(rule["monotonic_slack"]) else 0
		right_steps += 1 if float(right[i-1])-float(right[i]) <= float(rule["monotonic_slack"]) else 0
		jump = maxf(jump,maxf(absf(float(left[i])-float(left[i-1])),absf(float(right[i])-float(right[i-1]))))
	var passed: bool = absf(float(left[0])-float(right[-1])) <= float(rule["maximum_endpoint_rgb_mean_difference"])
	passed = passed and darkening >= float(rule["minimum_center_darkening_from_shallow_endpoint"]) and lift >= float(rule["minimum_center_lift_over_multicell_basin_core"])
	passed = passed and jump <= float(rule["maximum_adjacent_rgb_mean_step"]) and mini(left_steps,right_steps) >= int(rule["minimum_monotonic_steps_per_half"])
	return {"passed":passed,"left_values":left,"right_values":right,"center_darkening":darkening,"center_lift_from_basin_core":lift,"maximum_step":jump,"left_monotonic_steps":left_steps,"right_monotonic_steps":right_steps}

func _save_image(filename: String, image: Image) -> bool:
	var path: String = _output.path_join(filename)
	if image.save_png(path) != OK:
		return false
	_image_hashes[filename] = FileAccess.get_sha256(path)
	_capture_records.append(CaptureMetadata.capture_record(root, image, path, {
		"capture_kind": "diagnostic", "runtime_evidence": false,
		"diagnostic_purpose": "fixed-pixel water depth contract",
	}))
	return true

func _show_comparison() -> void:
	var keys: Array[String] = ["basin","hard","legacy"]
	var labels: Array[String] = ["当前：连续深度场（中性材质）","错误对照：按格硬切","错误对照：五条窄色带"]
	for i: int in 3:
		var display := TextureRect.new()
		display.texture = (_cases[keys[i]]["viewport"] as SubViewport).get_texture()
		display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		display.position = Vector2(8+i*408,40)
		display.size = Vector2(400,272)
		root.add_child(display)
		var label := Label.new()
		label.theme = load("res://assets/ui/themes/hud_m2.tres") as Theme
		label.add_theme_font_size_override("font_size",16)
		label.position = Vector2(12+i*408,10)
		label.text = labels[i]
		root.add_child(label)
