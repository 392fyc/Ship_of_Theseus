extends "res://tests/test_hud_m2_p3_gallery.gd"

const CAPTURE_FLAG := "--capture-hud-m2-p3"
const OUTPUT_DIRECTORY := "res://dev_doc/ui-art-research/hud-m2-p3/evidence"
const CASES: Array[Dictionary] = [
	{"name": "normal5-1280", "count": 5, "size": Vector2i(1280, 720), "state": "normal"},
	{"name": "normal5-1920", "count": 5, "size": Vector2i(1920, 1080), "state": "normal"},
	{"name": "normal5-2560", "count": 5, "size": Vector2i(2560, 1440), "state": "normal"},
	{"name": "mixed6-1280", "count": 6, "size": Vector2i(1280, 720), "state": "mixed"},
	{"name": "compact7-1280", "count": 7, "size": Vector2i(1280, 720), "state": "compact"},
	{"name": "missing-1280", "count": 6, "size": Vector2i(1280, 720), "state": "missing"},
	{"name": "focus-1280", "count": 7, "size": Vector2i(1280, 720), "state": "focus"},
	{"name": "passive-focus-1280", "count": 7, "size": Vector2i(1280, 720), "state": "passive_focus"},
]
const REGIONS: Array[Rect2i] = [
	Rect2i(32, 596, 226, 108), Rect2i(266, 596, 128, 108),
	Rect2i(402, 596, 476, 108), Rect2i(886, 596, 278, 108),
	Rect2i(1172, 596, 76, 108), Rect2i(503, 550, 274, 40),
]


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("HUD_M2_P3_CAPTURE_UNSUPPORTED_HEADLESS")
		quit(1)
		return
	if not CAPTURE_FLAG in OS.get_cmdline_user_args():
		print("HUD_M2_P3_CAPTURE_FLAG_REQUIRED")
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	print("=== capture_hud_m2_p3_gallery ===")
	root.size = Vector2i(1280, 720)
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_check("原生图库可以加载", packed != null)
	if packed == null:
		quit(1)
		return
	var gallery: Control = packed.instantiate() as Control
	root.add_child(gallery)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	await _test_layout(gallery)
	await _test_character(gallery)
	await _test_slots_and_input(gallery)
	gallery.queue_free()
	await process_frame
	var directory: String = ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(directory)
	_check("原生证据目录可用", directory_error == OK)
	if directory_error != OK:
		quit(1)
		return
	var outputs: Array[Dictionary] = []
	for config: Dictionary in CASES:
		outputs.append(await _capture_one(packed, config, directory))
	var receipt: Dictionary = {
		"task_id": "UI-RESTART-1-P3-native",
		"renderer": DisplayServer.get_name(),
		"engine": Engine.get_version_info()["string"],
		"passed": _passed, "failed": _failed,
		"input_method": "root.push_input: InputEventMouseMotion/InputEventMouseButton/InputEventKey",
		"inputs": "主动鼠标、混合被动数字键；冷却/不可用/纯被动拒绝鼠标数字键；纯被动焦点和Enter；人物悬停与焦点",
		"captures": outputs,
		"approval": "实现证据，等待独立审查",
	}
	var file: FileAccess = FileAccess.open(directory.path_join("native-capture.json"), FileAccess.WRITE)
	if file == null:
		_check("原生回执写入", false)
	else:
		file.store_string(JSON.stringify(receipt, "\t") + "\n")
		file.close()
	print("HUD_M2_P3_NATIVE_RESULT passed=%d failed=%d captures=%d" % [_passed, _failed, outputs.size()])
	quit(1 if _failed > 0 else 0)


func _capture_one(packed: PackedScene, config: Dictionary, directory: String) -> Dictionary:
	var capture_size: Vector2i = config["size"] as Vector2i
	var viewport := SubViewport.new()
	viewport.size = capture_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)
	var gallery: Control = packed.instantiate() as Control
	gallery.call("configure", int(config["count"]), capture_size, str(config["state"]))
	viewport.add_child(gallery)
	if str(config["state"]) == "passive_focus":
		await process_frame
		var slots: Array = gallery.call("get_skill_slots") as Array
		(slots[1] as Control).grab_focus()
		_key(KEY_TAB, viewport)
		await process_frame
		_key(KEY_TAB, viewport)
		await process_frame
	var image: Image = await _wait_for_complete(viewport, gallery, config)
	var result: Dictionary = {"name": config["name"], "state": config["state"], "width": capture_size.x, "height": capture_size.y, "skill_count": config["count"], "result": "fail"}
	_check("%s连续两帧完整" % config["name"], image != null)
	if image != null:
		var filename: String = str(config["name"]) + ".png"
		var output_path: String = directory.path_join(filename)
		var save_error: Error = image.save_png(output_path)
		_check("%s保存PNG" % config["name"], save_error == OK)
		if save_error == OK:
			result["result"] = "pass"
			result["path"] = "dev_doc/ui-art-research/hud-m2-p3/evidence/" + filename
			result["sha256"] = FileAccess.get_sha256(output_path)
			result["complete_frames"] = 2
			result["design_scale"] = gallery.call("get_output_scale")
			result["slot_size"] = 56 if int(config["count"]) == 7 else 64
			result["character_information_borders"] = "原坐标向内0.75px #514637"
			if str(config["state"]) == "passive_focus":
				var pure: Control = (gallery.call("get_skill_slots") as Array)[3] as Control
				result["inspection_visible"] = pure.call("is_inspection_visible")
				result["inspection_text"] = pure.call("get_inspection_text")
				result["pure_passive_has_focus"] = pure.has_focus()
				result["focus_input"] = "SubViewport.push_input: 两次真实Tab键事件"
			print("CAPTURED " + filename)
	viewport.queue_free()
	await process_frame
	return result


func _wait_for_complete(viewport: SubViewport, gallery: Control, config: Dictionary) -> Image:
	var complete_frames: int = 0
	for attempt: int in 24:
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = viewport.get_texture().get_image()
		var scale_value: float = float(gallery.call("get_output_scale"))
		if image.get_size() == viewport.size and _structure_ready(gallery, config) and _pixels_ready(image, scale_value, gallery):
			complete_frames += 1
			if complete_frames >= 2:
				return image
		else:
			complete_frames = 0
	return null


func _structure_ready(gallery: Control, config: Dictionary) -> bool:
	var slots: Array = gallery.call("get_skill_slots") as Array
	if slots.size() != int(config["count"]):
		return false
	for node: Control in slots:
		var icon: TextureRect = node.find_child("IconRect", true, false) as TextureRect
		if icon.texture == null or not node.visible:
			return false
	var panel: Control = gallery.call("get_character_panel") as Control
	var inspection_expected: bool = str(config["state"]) in ["focus", "missing"]
	if str(config["state"]) == "passive_focus":
		var pure: Control = slots[3] as Control
		if not pure.has_focus() or not bool(pure.call("is_inspection_visible")) or not "纯被动示例" in str(pure.call("get_inspection_text")):
			return false
		var inspection_rect: Rect2 = (pure.call("get_inspection_panel") as Control).get_global_rect()
		var composition: Control = gallery.get_node("DesignRoot/BottomHudComposition") as Control
		if inspection_rect.intersects((composition.get_node("ActionResourceStrip") as Control).get_global_rect()) or inspection_rect.intersects((composition.get_node("BottomRow") as Control).get_global_rect()):
			return false
	return panel.get_node("InspectionPanel").visible == inspection_expected and panel.find_child("HpValue", true, false).text != ""


func _pixels_ready(image: Image, scale_value: float, gallery: Control) -> bool:
	var areas: Array[Rect2i] = []
	for rect: Rect2i in REGIONS:
		areas.append(Rect2i(Vector2i(Vector2(rect.position) * scale_value), Vector2i(Vector2(rect.size) * scale_value)))
	# 三个信息区的顶部内边必须实际进入原生像素，不能只检查节点存在。
	for top: int in [609, 633, 659]:
		areas.append(Rect2i(Vector2i(127 * scale_value, top * scale_value), Vector2i(114 * scale_value, ceilf(1.5 * scale_value))))
	if str(gallery.call("get_state")) == "passive_focus":
		var pure: Control = (gallery.call("get_skill_slots") as Array)[3] as Control
		var inspection: Control = pure.call("get_inspection_panel") as Control
		areas.append(Rect2i(inspection.get_global_rect()))
	for area: Rect2i in areas:
		var warm_pixels: int = 0
		for y: int in range(area.position.y, area.end.y):
			for x: int in range(area.position.x, area.end.x):
				var color: Color = image.get_pixel(x, y)
				if color.r >= 0.17 and color.r >= color.g * 1.15 and color.g >= color.b * 1.05:
					warm_pixels += 1
					if warm_pixels >= 40:
						break
			if warm_pixels >= 40:
				break
		if warm_pixels < 40:
			return false
	return true
