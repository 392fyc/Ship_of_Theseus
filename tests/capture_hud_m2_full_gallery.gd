extends "res://tests/test_hud_m2_full_gallery.gd"

const CAPTURE_FLAG := "--capture-hud-m2-full"
const OUTPUT_DIRECTORY := "res://dev_doc/ui-art-research/hud-m2-p4/evidence"
const CASES: Array[Dictionary] = [
	{"name": "full-normal-1280", "count": 5, "size": Vector2i(1280, 720), "state": "normal"},
	{"name": "full-normal-1920", "count": 5, "size": Vector2i(1920, 1080), "state": "normal"},
	{"name": "full-normal-2560", "count": 5, "size": Vector2i(2560, 1440), "state": "normal"},
	{"name": "full-mixed-1280", "count": 6, "size": Vector2i(1280, 720), "state": "mixed"},
	{"name": "full-long-1280", "count": 7, "size": Vector2i(1280, 720), "state": "focus"},
	{"name": "full-missing-1280", "count": 6, "size": Vector2i(1280, 720), "state": "missing"},
	{"name": "full-disabled-1280", "count": 7, "size": Vector2i(1280, 720), "state": "utility_disabled"},
	{"name": "full-equipment-focus-1280", "count": 5, "size": Vector2i(1280, 720), "state": "utility_focus"},
	{"name": "full-potion-hover-1280", "count": 5, "size": Vector2i(1280, 720), "state": "normal", "interaction": "hover"},
	{"name": "full-potion-pressed-1280", "count": 5, "size": Vector2i(1280, 720), "state": "normal", "interaction": "pressed"},
]
const REGIONS: Array[Rect2i] = [
	Rect2i(32, 596, 226, 108), Rect2i(266, 596, 128, 108),
	Rect2i(402, 596, 476, 108), Rect2i(886, 596, 278, 108),
	Rect2i(1172, 596, 76, 108), Rect2i(503, 550, 274, 40),
]


func _initialize() -> void:
	if DisplayServer.get_name() == "headless" or not CAPTURE_FLAG in OS.get_cmdline_user_args():
		print("HUD_M2_FULL_CAPTURE_REQUIRES_NATIVE_AND_FLAG")
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	print("=== capture_hud_m2_full_gallery ===")
	root.size = Vector2i(1280, 720)
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var gallery: Control = packed.instantiate() as Control
	root.add_child(gallery)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	await _test_layout(gallery)
	await _test_character(gallery)
	await _test_slots_and_input(gallery)
	await _test_full_character_card(gallery)
	await _test_utility_composition(gallery)
	gallery.queue_free()
	await process_frame
	var directory: String = ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(directory)
	_check("P4原生证据目录", directory_error == OK)
	if directory_error != OK:
		quit(1)
		return
	var outputs: Array[Dictionary] = []
	for config: Dictionary in CASES:
		outputs.append(await _capture_one(packed, config, directory))
	var result: Dictionary = {
		"task_id": "UI-RESTART-1-P4-native", "engine": Engine.get_version_info()["string"],
		"renderer": DisplayServer.get_name(), "passed": _passed, "failed": _failed,
		"captures": outputs, "input_method": "root.push_input及SubViewport.push_input真实键鼠事件",
		"approval": "实现证据，等待独立审查"
	}
	var receipt: FileAccess = FileAccess.open(directory.path_join("native-capture.json"), FileAccess.WRITE)
	if receipt == null:
		_check("P4原生回执写入", false)
	else:
		receipt.store_string(JSON.stringify(result, "\t") + "\n")
		receipt.close()
	print("HUD_M2_FULL_NATIVE_RESULT passed=%d failed=%d captures=%d" % [_passed, _failed, outputs.size()])
	quit(1 if _failed > 0 else 0)


func _capture_one(packed: PackedScene, config: Dictionary, directory: String) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = config["size"] as Vector2i
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var gallery: Control = packed.instantiate() as Control
	gallery.call("configure", int(config["count"]), viewport.size, str(config["state"]))
	viewport.add_child(gallery)
	await process_frame
	await process_frame
	var interaction: String = str(config.get("interaction", ""))
	if not interaction.is_empty():
		var potion: Control = gallery.get_node("DesignRoot/BottomHudComposition/BottomRow/EquipmentHudPanel/PotionButton") as Control
		var motion := InputEventMouseMotion.new()
		motion.position = potion.get_global_rect().get_center()
		motion.global_position = motion.position
		viewport.push_input(motion)
		if interaction == "pressed":
			var event := InputEventMouseButton.new()
			event.position = motion.position
			event.global_position = motion.position
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = true
			viewport.push_input(event)
	var image: Image = await _wait_for_complete(viewport, gallery, config)
	var result: Dictionary = {"name": config["name"], "state": config["state"], "width": viewport.size.x, "height": viewport.size.y, "result": "fail"}
	_check("%s连续两帧完整" % config["name"], image != null)
	if image != null:
		var output: String = directory.path_join(str(config["name"]) + ".png")
		var save_error: Error = image.save_png(output)
		_check("%s保存" % config["name"], save_error == OK)
		if save_error == OK:
			result["result"] = "pass"
			result["path"] = "dev_doc/ui-art-research/hud-m2-p4/evidence/" + str(config["name"]) + ".png"
			result["sha256"] = FileAccess.get_sha256(output)
			result["complete_frames"] = 2
			result["interaction"] = interaction
			var panel: Control = gallery.call("get_character_panel") as Control
			var card: Control = panel.call("get_inspection_panel") as Control
			result["character_card_visible"] = card.visible
			result["character_content_top_y"] = panel.call("get_content_top_y")
			if card.visible:
				result["card_rect"] = [card.get_global_rect().position.x, card.get_global_rect().position.y, card.get_global_rect().size.x, card.get_global_rect().size.y]
				result["identity"] = card.get_node("InspectionLabel").text
				var values: Dictionary = {}
				for key: String in CharacterView.ATTRIBUTE_KEYS:
					values[key] = card.get_node("AttributeRows/" + key + "/Value").text
				result["attributes"] = values
			print("CAPTURED " + str(config["name"]) + ".png")
	viewport.queue_free()
	await process_frame
	return result


func _wait_for_complete(viewport: SubViewport, gallery: Control, config: Dictionary) -> Image:
	var streak: int = 0
	for attempt: int in 24:
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = viewport.get_texture().get_image()
		if image.get_size() == viewport.size and _structure_ready(gallery, config) and _pixels_ready(image, gallery):
			streak += 1
			if streak == 2:
				return image
		else:
			streak = 0
	return null


func _structure_ready(gallery: Control, config: Dictionary) -> bool:
	var composition: Control = gallery.get_node("DesignRoot/BottomHudComposition") as Control
	if composition.get_node("BottomRow").get_child_count() != 5:
		return false
	var slots: Array = gallery.call("get_skill_slots") as Array
	if slots.size() != int(config["count"]):
		return false
	for slot: Control in slots:
		if slot.find_child("IconRect", true, false).texture == null:
			return false
	var card: Control = (gallery.call("get_character_panel") as Control).call("get_inspection_panel") as Control
	if card.visible != (str(config["state"]) in ["mixed", "focus", "missing"]):
		return false
	if card.visible and card.get_node("AttributeRows").get_child_count() != 8:
		return false
	var potion: Control = composition.get_node("BottomRow/EquipmentHudPanel/PotionButton") as Control
	if str(config.get("interaction", "")) == "hover" and not potion.find_child("HoverOverlay", true, false).visible:
		return false
	if str(config.get("interaction", "")) == "pressed" and not potion.find_child("PressedShade", true, false).visible:
		return false
	return true


func _pixels_ready(image: Image, gallery: Control) -> bool:
	var factor: float = float(gallery.call("get_output_scale"))
	var regions: Array[Rect2i] = []
	for rect: Rect2i in REGIONS:
		regions.append(Rect2i(Vector2i(Vector2(rect.position) * factor), Vector2i(Vector2(rect.size) * factor)))
	var card: Control = (gallery.call("get_character_panel") as Control).call("get_inspection_panel") as Control
	if card.visible:
		regions.append(Rect2i(card.get_global_rect()))
	for region: Rect2i in regions:
		var warm: int = 0
		for y: int in range(region.position.y, region.end.y):
			for x: int in range(region.position.x, region.end.x):
				var color: Color = image.get_pixel(x, y)
				if color.r >= 0.17 and color.r >= color.g * 1.15 and color.g >= color.b * 1.05:
					warm += 1
					if warm >= 40:
						break
			if warm >= 40:
				break
		if warm < 40:
			return false
	return true
