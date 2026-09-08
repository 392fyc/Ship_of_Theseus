extends "res://tests/test_hud_m2_character_hover.gd"

const OUTPUT_DIRECTORY := "res://dev_doc/ui-art-research/hud-m2-character-hover/evidence"
const CASES: Array[Dictionary] = [
	{"name": "character-normal-1280", "size": Vector2i(1280, 720), "state": "normal"},
	{"name": "character-hp-hover-1280", "size": Vector2i(1280, 720), "state": "hover"},
	{"name": "character-mouse-left-1280", "size": Vector2i(1280, 720), "state": "left"},
	{"name": "character-hp-hover-1920", "size": Vector2i(1920, 1080), "state": "hover"},
	{"name": "character-hp-hover-2560", "size": Vector2i(2560, 1440), "state": "hover"},
]
const REGIONS: Array[Rect2i] = [
	Rect2i(32, 596, 226, 108), Rect2i(266, 596, 128, 108),
	Rect2i(402, 596, 476, 108), Rect2i(886, 596, 278, 108),
	Rect2i(1172, 596, 76, 108), Rect2i(503, 550, 274, 40),
]


func _initialize() -> void:
	if DisplayServer.get_name() == "headless" or not "--capture-hud-m2-character-hover" in OS.get_cmdline_user_args():
		print("HUD_M2_CHARACTER_HOVER_CAPTURE_REQUIRES_NATIVE_AND_FLAG")
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var gallery: Control = packed.instantiate() as Control
	root.add_child(gallery)
	await process_frame
	await process_frame
	await _test_character_hover(gallery)
	gallery.queue_free()
	await process_frame
	var directory: String = ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(directory)
	_check("悬浮原生证据目录", directory_error == OK)
	if directory_error != OK:
		quit(1)
		return
	var captures: Array[Dictionary] = []
	for config: Dictionary in CASES:
		captures.append(await _capture_one(packed, config, directory))
	var file: FileAccess = FileAccess.open(directory.path_join("native-capture.json"), FileAccess.WRITE)
	if file == null:
		_check("悬浮原生回执写入", false)
	else:
		file.store_string(JSON.stringify({
			"task_id": "HOVER-R1", "passed": _passed, "failed": _failed,
			"engine": Engine.get_version_info()["string"], "renderer": DisplayServer.get_name(),
			"captures": captures, "approval": "实现证据，等待独立审查"
		}, "\t") + "\n")
		file.close()
	print("HUD_M2_CHARACTER_HOVER_NATIVE_RESULT passed=%d failed=%d captures=%d" % [_passed, _failed, captures.size()])
	quit(1 if _failed > 0 else 0)


func _capture_one(packed: PackedScene, config: Dictionary, directory: String) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = config["size"] as Vector2i
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var gallery: Control = packed.instantiate() as Control
	gallery.call("configure", 5, viewport.size, "normal")
	viewport.add_child(gallery)
	await process_frame
	await process_frame
	var factor: float = float(viewport.size.x) / 1280.0
	var state: String = str(config["state"])
	if state != "normal":
		_move_pointer(viewport, Vector2(202, 668) * factor)
		await process_frame
		await process_frame
	if state != "hover":
		_move_pointer(viewport, Vector2(640, 320) * factor)
	var panel: Control = gallery.call("get_character_panel") as Control
	var card: Control = panel.call("get_inspection_panel") as Control
	var latest: Image = null
	var streak: int = 0
	for attempt: int in 24:
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = viewport.get_texture().get_image()
		if image.get_size() == viewport.size and card.visible == (state == "hover") and _pixels_complete(image, factor, card):
			streak += 1
			if streak == 2:
				latest = image
				break
		else:
			streak = 0
	_check("%s连续两帧完整" % config["name"], latest != null)
	var result: Dictionary = {"name": config["name"], "width": viewport.size.x, "height": viewport.size.y, "card_visible": card.visible, "result": "fail"}
	if latest != null:
		var path: String = directory.path_join(str(config["name"]) + ".png")
		var save_error: Error = latest.save_png(path)
		_check("%s保存原生PNG" % config["name"], save_error == OK)
		if save_error == OK:
			result["result"] = "pass"
			result["path"] = "dev_doc/ui-art-research/hud-m2-character-hover/evidence/" + str(config["name"]) + ".png"
			result["sha256"] = FileAccess.get_sha256(path)
			result["complete_frames"] = 2
			result["pointer_region"] = "HP" if state == "hover" else "棋盘"
			result["input_method"] = "SubViewport.push_input真实鼠标移动"
			print("CAPTURED " + str(config["name"]) + ".png")
	viewport.queue_free()
	await process_frame
	return result


func _pixels_complete(image: Image, factor: float, card: Control) -> bool:
	var regions: Array[Rect2i] = []
	for rect: Rect2i in REGIONS:
		regions.append(Rect2i(Vector2i(Vector2(rect.position) * factor), Vector2i(Vector2(rect.size) * factor)))
	if card.visible:
		regions.append(Rect2i(card.get_global_rect()))
	for rect: Rect2i in regions:
		var warm: int = 0
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				var color: Color = image.get_pixel(x, y)
				if color.r > 0.17 and color.r > color.g * 1.15 and color.g > color.b * 1.05:
					warm += 1
					if warm >= 40:
						break
			if warm >= 40:
				break
		if warm < 40:
			return false
	return true
