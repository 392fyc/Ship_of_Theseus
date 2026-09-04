extends SceneTree

const CAPTURE_FLAG: String = "--capture-hud-bottom-composition"
const SCENE_PATH: String = "res://scenes/dev/hud_bottom_composition_gallery.tscn"
const OUTPUT_DIRECTORY: String = "res://dev_doc/ui-art-research/hud-ghv4-bottom-composition/evidence"
const CAPTURE_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const SKILL_COUNTS: Array[int] = [5, 6, 7]
const MAX_RENDER_ATTEMPTS: int = 12
const REQUIRED_WARM_REGIONS: Array[Dictionary] = [
	{"name": "character", "rect": Rect2i(32, 596, 226, 108), "minimum": 40},
	{"name": "equipment", "rect": Rect2i(266, 596, 128, 108), "minimum": 40},
	{"name": "skills", "rect": Rect2i(402, 596, 476, 108), "minimum": 40},
	{"name": "relics", "rect": Rect2i(886, 596, 278, 108), "minimum": 40},
	{"name": "end_turn", "rect": Rect2i(1172, 596, 76, 108), "minimum": 20},
	{"name": "actions", "rect": Rect2i(503, 550, 274, 40), "minimum": 40},
	{"name": "token", "rect": Rect2i(615, 360, 50, 70), "minimum": 10},
]

var _ran: bool = false
var _failed: bool = false


func _initialize() -> void:
	print("=== capture_hud_bottom_composition_gallery ===")
	if DisplayServer.get_name() == "headless":
		print("HUD_BOTTOM_COMPOSITION_CAPTURE_UNSUPPORTED_HEADLESS")
		quit(1)
		return
	if not CAPTURE_FLAG in OS.get_cmdline_user_args():
		print("HUD_BOTTOM_COMPOSITION_CAPTURE_FLAG_REQUIRED")
		quit(1)


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_capture_all()
	return false


func _capture_all() -> void:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("无法加载完整底部 HUD 画廊：%s" % SCENE_PATH)
		_finish()
		return
	var output_absolute: String = ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(output_absolute)
	if mkdir_error != OK:
		_fail("无法创建截图目录：%s" % error_string(mkdir_error))
		_finish()
		return
	for skill_count: int in SKILL_COUNTS:
		for capture_size: Vector2i in CAPTURE_SIZES:
			await _capture_one(packed, skill_count, capture_size, output_absolute)
	_finish()


func _capture_one(packed: PackedScene, skill_count: int, capture_size: Vector2i,
		output_absolute: String) -> void:
	root.size = capture_size
	var viewport := SubViewport.new()
	viewport.name = "BottomHudCapture_%d_%dx%d" % [skill_count, capture_size.x, capture_size.y]
	viewport.size = capture_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)
	var gallery: Control = packed.instantiate() as Control
	gallery.call("configure", skill_count, capture_size)
	viewport.add_child(gallery)

	var expected_scale: float = float(capture_size.x) / 1280.0
	var image: Image = await _wait_for_stable_complete_image(
		viewport, gallery, skill_count, capture_size, expected_scale)
	if image == null:
		_fail("%d 技能 %s 未取得连续两帧完整画面" % [skill_count, str(capture_size)])
	elif image.get_size() != capture_size:
		_fail("%d 技能截图尺寸错误：期望 %s，实际 %s" % [
			skill_count, str(capture_size), str(image.get_size())])
	else:
		var filename: String = "hud_bottom_composition_%dskills_%dx%d.png" % [
			skill_count, capture_size.x, capture_size.y]
		var save_error: Error = image.save_png(output_absolute.path_join(filename))
		if save_error != OK:
			_fail("保存失败 %s：%s" % [filename, error_string(save_error)])
		else:
			print("CAPTURED %s" % output_absolute.path_join(filename))
	viewport.queue_free()
	await process_frame


func _wait_for_stable_complete_image(viewport: SubViewport, gallery: Control,
		skill_count: int, capture_size: Vector2i, expected_scale: float) -> Image:
	var complete_streak: int = 0
	var latest_complete: Image = null
	for attempt: int in MAX_RENDER_ATTEMPTS:
		await process_frame
		await RenderingServer.frame_post_draw
		var candidate: Image = viewport.get_texture().get_image()
		var structure_ready: bool = _gallery_structure_is_ready(
			gallery, skill_count, capture_size, expected_scale)
		var pixels_ready: bool = candidate.get_size() == capture_size \
			and _image_has_required_regions(candidate, expected_scale)
		if structure_ready and pixels_ready:
			complete_streak += 1
			latest_complete = candidate
			if complete_streak >= 2:
				return latest_complete
		else:
			complete_streak = 0
			latest_complete = null
			print("WARMING %d skills %s attempt %d/%d structure=%s pixels=%s" % [
				skill_count, str(capture_size), attempt + 1, MAX_RENDER_ATTEMPTS,
				str(structure_ready), str(pixels_ready)])
	return null


func _gallery_structure_is_ready(gallery: Control, skill_count: int,
		capture_size: Vector2i, expected_scale: float) -> bool:
	if gallery.size != Vector2(capture_size):
		return false
	if not is_equal_approx(float(gallery.call("get_output_scale")), expected_scale):
		return false
	var design_root: Control = gallery.get_node_or_null("DesignRoot") as Control
	var composition: Control = gallery.get_node_or_null(
		"DesignRoot/BottomHudComposition") as Control
	var token: Sprite2D = gallery.get_node_or_null(
		"DesignRoot/KenseiScaleAnchor") as Sprite2D
	if design_root == null or composition == null or token == null:
		return false
	if design_root.scale != Vector2(expected_scale, expected_scale):
		return false
	if not bool(token.call("is_configured")) or not token.visible:
		return false
	var row: HBoxContainer = composition.get_node_or_null("BottomRow") as HBoxContainer
	var strip: Control = composition.get_node_or_null("ActionResourceStrip") as Control
	if row == null or strip == null or not row.visible or not strip.visible:
		return false
	var required_components: Array[String] = [
		"CharacterHudPanel", "EquipmentHudPanel", "SkillShelf", "RelicGrid",
		"EndTurnControl",
	]
	for component_name: String in required_components:
		var component: Control = row.get_node_or_null(component_name) as Control
		if component == null or not component.visible:
			return false
	var shelf: Control = row.get_node("SkillShelf") as Control
	return (shelf.call("get_skill_slots") as Array).size() == skill_count


func _image_has_required_regions(image: Image, output_scale: float) -> bool:
	for requirement: Dictionary in REQUIRED_WARM_REGIONS:
		var logical_rect: Rect2i = requirement["rect"] as Rect2i
		var scaled_rect := Rect2i(
			Vector2i(
				roundi(float(logical_rect.position.x) * output_scale),
				roundi(float(logical_rect.position.y) * output_scale)),
			Vector2i(
				roundi(float(logical_rect.size.x) * output_scale),
				roundi(float(logical_rect.size.y) * output_scale)))
		var minimum: int = ceili(float(requirement["minimum"]) * output_scale * output_scale)
		if _count_warm_pixels(image, scaled_rect, minimum) < minimum:
			return false
	return true


func _count_warm_pixels(image: Image, region: Rect2i, stop_at: int) -> int:
	var image_bounds := Rect2i(Vector2i.ZERO, image.get_size())
	var bounded: Rect2i = region.intersection(image_bounds)
	var count: int = 0
	for y: int in range(bounded.position.y, bounded.end.y):
		for x: int in range(bounded.position.x, bounded.end.x):
			var color: Color = image.get_pixel(x, y)
			if color.r >= 0.17 and color.r >= color.g * 1.15 \
					and color.g >= color.b * 1.05:
				count += 1
				if count >= stop_at:
					return count
	return count


func _fail(message: String) -> void:
	_failed = true
	print("CAPTURE_FAILED " + message)


func _finish() -> void:
	print("HUD_BOTTOM_COMPOSITION_CAPTURE_OK" if not _failed
		else "HUD_BOTTOM_COMPOSITION_CAPTURE_FAILED")
	quit(1 if _failed else 0)
