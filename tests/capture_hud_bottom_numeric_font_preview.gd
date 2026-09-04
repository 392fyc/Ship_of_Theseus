extends SceneTree

const CAPTURE_FLAG: String = "--capture-hud-bottom-numeric-font-preview"
const SCENE_PATH: String = "res://scenes/dev/hud_bottom_numeric_font_preview.tscn"
const OUTPUT_PATH: String = "res://dev_doc/ui-art-research/hud-gha4-numeric-font/evidence/hud_bottom_numeric_font_preview_1280x720.png"
const CAPTURE_SIZE := Vector2i(1280, 720)
const MAX_RENDER_ATTEMPTS: int = 12
const REQUIRED_WARM_REGIONS: Array[Dictionary] = [
	{"rect": Rect2i(32, 596, 226, 108), "minimum": 40},
	{"rect": Rect2i(266, 596, 128, 108), "minimum": 40},
	{"rect": Rect2i(402, 596, 476, 108), "minimum": 40},
	{"rect": Rect2i(886, 596, 278, 108), "minimum": 40},
	{"rect": Rect2i(1172, 596, 76, 108), "minimum": 20},
	{"rect": Rect2i(503, 550, 274, 40), "minimum": 40},
	{"rect": Rect2i(615, 360, 50, 70), "minimum": 10},
]

var _ran: bool = false


func _initialize() -> void:
	print("=== capture_hud_bottom_numeric_font_preview ===")
	if DisplayServer.get_name() == "headless":
		print("HUD_BOTTOM_NUMERIC_FONT_CAPTURE_UNSUPPORTED_HEADLESS")
		quit(1)
		return
	if CAPTURE_FLAG not in OS.get_cmdline_user_args():
		print("HUD_BOTTOM_NUMERIC_FONT_CAPTURE_FLAG_REQUIRED")
		quit(1)


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_capture()
	return false


func _capture() -> void:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("无法加载 HUD 字体实景预览")
		return
	root.size = CAPTURE_SIZE
	var viewport := SubViewport.new()
	viewport.name = "BottomNumericFontPreviewCapture"
	viewport.size = CAPTURE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)
	var preview: Control = packed.instantiate() as Control
	viewport.add_child(preview)
	var image: Image = await _wait_for_stable_image(viewport, preview)
	if image == null:
		_fail("未取得连续两帧完整 HUD 字体预览")
		return
	var output_absolute: String = ProjectSettings.globalize_path(OUTPUT_PATH)
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(output_absolute.get_base_dir())
	if mkdir_error != OK:
		_fail("无法创建证据目录：%s" % error_string(mkdir_error))
		return
	var save_error: Error = image.save_png(output_absolute)
	if save_error != OK:
		_fail("保存失败：%s" % error_string(save_error))
		return
	print("CAPTURED %s" % output_absolute)
	print("HUD_BOTTOM_NUMERIC_FONT_CAPTURE_OK")
	quit(0)


func _wait_for_stable_image(viewport: SubViewport, preview: Control) -> Image:
	var complete_streak: int = 0
	var latest: Image = null
	for attempt: int in MAX_RENDER_ATTEMPTS:
		await process_frame
		await RenderingServer.frame_post_draw
		var candidate: Image = viewport.get_texture().get_image()
		var structure_ready: bool = _structure_ready(preview)
		var pixels_ready: bool = candidate.get_size() == CAPTURE_SIZE \
			and _image_has_required_regions(candidate)
		if structure_ready and pixels_ready:
			complete_streak += 1
			latest = candidate
			if complete_streak >= 2:
				return latest
		else:
			complete_streak = 0
			latest = null
			print("WARMING attempt %d/%d structure=%s pixels=%s" % [
				attempt + 1, MAX_RENDER_ATTEMPTS, str(structure_ready), str(pixels_ready)])
	return null


func _structure_ready(preview: Control) -> bool:
	if preview.size != Vector2(CAPTURE_SIZE) or not preview.has_method("get_value_labels"):
		return false
	var values: Array = preview.call("get_value_labels") as Array
	if values.size() != 3:
		return false
	for value: Variant in values:
		var label: Label = value as Label
		if label == null or label.text != "999999/999999" \
				or label.get_theme_font_size(&"font_size") != 9:
			return false
	return true


func _image_has_required_regions(image: Image) -> bool:
	for requirement: Dictionary in REQUIRED_WARM_REGIONS:
		var region: Rect2i = requirement["rect"] as Rect2i
		var minimum: int = int(requirement["minimum"])
		if _count_warm_pixels(image, region, minimum) < minimum:
			return false
	return true


func _count_warm_pixels(image: Image, region: Rect2i, stop_at: int) -> int:
	var bounded: Rect2i = region.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var count: int = 0
	for y: int in range(bounded.position.y, bounded.end.y):
		for x: int in range(bounded.position.x, bounded.end.x):
			var color: Color = image.get_pixel(x, y)
			if color.r >= 0.17 and color.r >= color.g * 1.15 and color.g >= color.b * 1.05:
				count += 1
				if count >= stop_at:
					return count
	return count


func _fail(message: String) -> void:
	print("HUD_BOTTOM_NUMERIC_FONT_CAPTURE_FAILED " + message)
	quit(1)
