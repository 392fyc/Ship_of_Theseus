extends SceneTree

const CAPTURE_FLAG: String = "--capture-hud-utility-slices"
const SCENE_PATH: String = "res://scenes/dev/hud_utility_vertical_slice_gallery.tscn"
const OUTPUT_DIRECTORY: String = "res://dev_doc/ui-art-research/hud-ghv3-utility-slice/evidence"
const CAPTURE_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const STATE_NAMES: Array[String] = ["EmptyState", "OccupiedState", "DisabledState"]

var _ran: bool = false
var _failed: bool = false


func _initialize() -> void:
	print("=== capture_hud_utility_vertical_slice_gallery ===")
	if DisplayServer.get_name() == "headless":
		print("HUD_UTILITY_CAPTURE_UNSUPPORTED_HEADLESS")
		quit(1)
		return
	if not CAPTURE_FLAG in OS.get_cmdline_user_args():
		print("HUD_UTILITY_CAPTURE_FLAG_REQUIRED")
		quit(1)


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_capture_all()
	return false


func _capture_all() -> void:
	if not CAPTURE_FLAG in OS.get_cmdline_user_args():
		return
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("无法加载实用 HUD 画廊：%s" % SCENE_PATH)
		_finish()
		return

	var output_absolute := ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(output_absolute)
	if mkdir_error != OK:
		_fail("无法创建截图目录：%s" % error_string(mkdir_error))
		_finish()
		return

	for capture_size: Vector2i in CAPTURE_SIZES:
		await _capture_one(packed, capture_size, output_absolute)
	_finish()


func _capture_one(packed: PackedScene, capture_size: Vector2i,
		output_absolute: String) -> void:
	root.size = capture_size
	var viewport := SubViewport.new()
	viewport.name = "UtilityCaptureViewport_%dx%d" % [capture_size.x, capture_size.y]
	viewport.size = capture_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)

	var gallery: Control = packed.instantiate() as Control
	gallery.call("set_reference_size", capture_size)
	viewport.add_child(gallery)
	await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

	if not _all_components_inside_safe_area(gallery):
		_fail("%dx%d 有实用 HUD 组件超出安全画布" % [capture_size.x, capture_size.y])
		viewport.queue_free()
		await process_frame
		return

	var image: Image = viewport.get_texture().get_image()
	if image.get_size() != capture_size:
		_fail("截图尺寸错误：期望 %s，实际 %s" % [capture_size, image.get_size()])
		viewport.queue_free()
		await process_frame
		return

	var filename := "hud_utility_slice_%dx%d.png" % [capture_size.x, capture_size.y]
	var output_path := output_absolute.path_join(filename)
	var save_error := image.save_png(output_path)
	if save_error != OK:
		_fail("保存失败 %s：%s" % [filename, error_string(save_error)])
	else:
		print("CAPTURED %s" % output_path)

	viewport.queue_free()
	await process_frame


func _all_components_inside_safe_area(gallery: Control) -> bool:
	var safe_area: Control = gallery.get_node("SafeArea") as Control
	if safe_area == null:
		return false
	var safe_rect := safe_area.get_global_rect()
	for state_name: String in STATE_NAMES:
		var components_path := "SafeArea/Layout/Content/States/%s/Components" % state_name
		for component_name: String in ["EquipmentHudPanel", "RelicGrid", "EndTurnControl"]:
			var component: Control = gallery.get_node_or_null(
				components_path + "/" + component_name) as Control
			if component == null or not _contains_rect(safe_rect, component.get_global_rect()):
				return false
	return true


func _contains_rect(outer: Rect2, inner: Rect2) -> bool:
	return inner.position.x >= outer.position.x - 0.01 \
		and inner.position.y >= outer.position.y - 0.01 \
		and inner.end.x <= outer.end.x + 0.01 \
		and inner.end.y <= outer.end.y + 0.01


func _fail(message: String) -> void:
	_failed = true
	print("CAPTURE_FAILED " + message)


func _finish() -> void:
	print("HUD_UTILITY_CAPTURE_OK" if not _failed else "HUD_UTILITY_CAPTURE_FAILED")
	quit(1 if _failed else 0)
