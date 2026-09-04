extends SceneTree

const CAPTURE_FLAG: String = "--capture-hud-bottom-dynamic-states"
const SCENE_PATH: String = "res://scenes/dev/hud_bottom_dynamic_states_gallery.tscn"
const OUTPUT_DIRECTORY: String = "res://dev_doc/ui-art-research/hud-ghv5-bottom-dynamic-states/evidence"
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
const MAX_RENDER_ATTEMPTS: int = 12
const STATE_IDS: Array[StringName] = [
	&"capacity_1_ready_zero_shield",
	&"capacity_2_early_move_lock_long_values",
	&"capacity_3_move_exhausted",
]
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
	print("=== capture_hud_bottom_dynamic_states_gallery ===")
	if DisplayServer.get_name() == "headless":
		print("HUD_BOTTOM_DYNAMIC_CAPTURE_UNSUPPORTED_HEADLESS")
		quit(1)
		return
	if CAPTURE_FLAG not in OS.get_cmdline_user_args():
		print("HUD_BOTTOM_DYNAMIC_CAPTURE_FLAG_REQUIRED")
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
		_fail("无法加载动态状态画廊：%s" % SCENE_PATH)
		_finish()
		return
	var output_absolute: String = ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(output_absolute)
	if mkdir_error != OK:
		_fail("无法创建截图目录：%s" % error_string(mkdir_error))
		_finish()
		return
	for state_id: StringName in STATE_IDS:
		await _capture_one(packed, state_id, output_absolute)
	_finish()


func _capture_one(packed: PackedScene, state_id: StringName,
		output_absolute: String) -> void:
	root.size = CAPTURE_SIZE
	var viewport := SubViewport.new()
	viewport.name = "BottomDynamicCapture_%s" % state_id
	viewport.size = CAPTURE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)
	var gallery: Control = packed.instantiate() as Control
	gallery.call("configure_state", state_id)
	viewport.add_child(gallery)
	var image: Image = await _wait_for_stable_complete_image(viewport, gallery, state_id)
	if image == null:
		_fail("%s 未取得连续两帧完整画面" % state_id)
	else:
		var filename: String = _filename_for_state(state_id)
		var save_error: Error = image.save_png(output_absolute.path_join(filename))
		if save_error != OK:
			_fail("保存失败 %s：%s" % [filename, error_string(save_error)])
		else:
			print("CAPTURED %s" % output_absolute.path_join(filename))
	viewport.queue_free()
	await process_frame


func _wait_for_stable_complete_image(viewport: SubViewport, gallery: Control,
		state_id: StringName) -> Image:
	var complete_streak: int = 0
	var latest_complete: Image = null
	for attempt: int in MAX_RENDER_ATTEMPTS:
		await process_frame
		await RenderingServer.frame_post_draw
		var candidate: Image = viewport.get_texture().get_image()
		var structure_ready: bool = _gallery_structure_is_ready(gallery, state_id)
		var pixels_ready: bool = candidate.get_size() == CAPTURE_SIZE \
			and _image_has_required_regions(candidate)
		if structure_ready and pixels_ready:
			complete_streak += 1
			latest_complete = candidate
			if complete_streak >= 2:
				return latest_complete
		else:
			complete_streak = 0
			latest_complete = null
			print("WARMING %s attempt %d/%d structure=%s pixels=%s" % [
				state_id, attempt + 1, MAX_RENDER_ATTEMPTS,
				str(structure_ready), str(pixels_ready)])
	return null


func _gallery_structure_is_ready(gallery: Control, state_id: StringName) -> bool:
	if gallery.size != Vector2(CAPTURE_SIZE) or gallery.call("get_state_id") != state_id:
		return false
	var base: Control = gallery.get_node_or_null("BaseGallery") as Control
	var composition: Control = gallery.get_node_or_null(
		"BaseGallery/DesignRoot/BottomHudComposition") as Control
	var token: Sprite2D = gallery.get_node_or_null(
		"BaseGallery/DesignRoot/KenseiScaleAnchor") as Sprite2D
	if base == null or composition == null or token == null:
		return false
	if base.size != Vector2(CAPTURE_SIZE) or not bool(token.call("is_configured")):
		return false
	var shelf: Control = composition.get_node("BottomRow/SkillShelf") as Control
	return (shelf.call("get_skill_slots") as Array).size() == 5


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
			if color.r >= 0.17 and color.r >= color.g * 1.15 \
					and color.g >= color.b * 1.05:
				count += 1
				if count >= stop_at:
					return count
	return count


func _filename_for_state(state_id: StringName) -> String:
	match state_id:
		&"capacity_2_early_move_lock_long_values":
			return "hud_bottom_dynamic_capacity_2_early_lock_1280x720.png"
		&"capacity_3_move_exhausted":
			return "hud_bottom_dynamic_capacity_3_exhausted_1280x720.png"
		_:
			return "hud_bottom_dynamic_capacity_1_ready_1280x720.png"


func _fail(message: String) -> void:
	_failed = true
	print("CAPTURE_FAILED " + message)


func _finish() -> void:
	print("HUD_BOTTOM_DYNAMIC_CAPTURE_OK" if not _failed
		else "HUD_BOTTOM_DYNAMIC_CAPTURE_FAILED")
	quit(1 if _failed else 0)
