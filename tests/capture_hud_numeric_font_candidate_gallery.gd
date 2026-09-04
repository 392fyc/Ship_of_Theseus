extends SceneTree

const CAPTURE_FLAG: String = "--capture-hud-numeric-font-candidate"
const SCENE_PATH: String = "res://scenes/dev/hud_numeric_font_candidate_gallery.tscn"
const OUTPUT_PATH: String = "res://dev_doc/ui-art-research/hud-gha4-numeric-font/evidence/hud_numeric_font_candidate_1280x720.png"
const CAPTURE_SIZE := Vector2i(1280, 720)
const MAX_RENDER_ATTEMPTS: int = 12
const REFERENCE_REGION := Rect2i(188, 154, 360, 416)
const CANDIDATE_REGION := Rect2i(612, 154, 360, 416)

var _ran: bool = false


func _initialize() -> void:
	print("=== capture_hud_numeric_font_candidate_gallery ===")
	if DisplayServer.get_name() == "headless":
		print("HUD_NUMERIC_FONT_CAPTURE_UNSUPPORTED_HEADLESS")
		quit(1)
		return
	if CAPTURE_FLAG not in OS.get_cmdline_user_args():
		print("HUD_NUMERIC_FONT_CAPTURE_FLAG_REQUIRED")
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
		_fail("无法加载字体候选画廊")
		return
	root.size = CAPTURE_SIZE
	var viewport := SubViewport.new()
	viewport.name = "NumericFontCandidateCapture"
	viewport.size = CAPTURE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)
	var gallery: Control = packed.instantiate() as Control
	viewport.add_child(gallery)
	var image: Image = await _wait_for_stable_image(viewport, gallery)
	if image == null:
		_fail("未取得连续两帧完整字体候选画面")
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
	print("HUD_NUMERIC_FONT_CAPTURE_OK")
	quit(0)


func _wait_for_stable_image(viewport: SubViewport, gallery: Control) -> Image:
	var complete_streak: int = 0
	var latest: Image = null
	for attempt: int in MAX_RENDER_ATTEMPTS:
		await process_frame
		await RenderingServer.frame_post_draw
		var candidate: Image = viewport.get_texture().get_image()
		var structure_ready: bool = _structure_ready(gallery)
		var pixels_ready: bool = candidate.get_size() == CAPTURE_SIZE \
			and _count_light_pixels(candidate, REFERENCE_REGION, 100) >= 100 \
			and _count_light_pixels(candidate, CANDIDATE_REGION, 100) >= 100
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


func _structure_ready(gallery: Control) -> bool:
	if gallery.size != Vector2(CAPTURE_SIZE):
		return false
	if not gallery.has_method("get_reference_labels") \
			or not gallery.has_method("get_candidate_labels"):
		return false
	var references: Array = gallery.call("get_reference_labels") as Array
	var candidates: Array = gallery.call("get_candidate_labels") as Array
	if references.size() != 7 or candidates.size() != 7:
		return false
	for label_value: Variant in candidates:
		var label: Label = label_value as Label
		if label == null or label.text == "" or not label.is_visible_in_tree():
			return false
	return true


func _count_light_pixels(image: Image, region: Rect2i, stop_at: int) -> int:
	var bounded: Rect2i = region.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var count: int = 0
	for y: int in range(bounded.position.y, bounded.end.y):
		for x: int in range(bounded.position.x, bounded.end.x):
			var color: Color = image.get_pixel(x, y)
			if color.get_luminance() >= 0.38:
				count += 1
				if count >= stop_at:
					return count
	return count


func _fail(message: String) -> void:
	print("HUD_NUMERIC_FONT_CAPTURE_FAILED " + message)
	quit(1)
