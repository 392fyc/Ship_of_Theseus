extends SceneTree

const RuntimeDashboard := preload("res://scripts/ui/hud/m2/runtime_dashboard.gd")
const CAPTURE_FLAG := "--capture-hud-m2-runtime"
const OUTPUT_DIRECTORY := "res://dev_doc/ui-art-research/hud-m2-integration/evidence"
const CASES: Array[Dictionary] = [
	{"name": "runtime-normal-1280", "size": Vector2i(1280, 720), "mode": "normal"},
	{"name": "runtime-character-hover-1280", "size": Vector2i(1280, 720), "mode": "character_hover"},
	{"name": "runtime-passive-focus-1280", "size": Vector2i(1280, 720), "mode": "passive_focus"},
	{"name": "runtime-enemy-1280", "size": Vector2i(1280, 720), "mode": "enemy"},
	{"name": "runtime-normal-1920", "size": Vector2i(1920, 1080), "mode": "normal"},
	{"name": "runtime-normal-2560", "size": Vector2i(2560, 1440), "mode": "normal"},
]

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless" or not CAPTURE_FLAG in OS.get_cmdline_user_args():
		print("HUD_M2_RUNTIME_CAPTURE_REQUIRES_NATIVE_AND_FLAG")
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	print("=== capture_hud_m2_runtime_dashboard ===")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var directory: String = ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(directory)
	_check("原生证据目录", directory_error == OK)
	if directory_error != OK:
		quit(1)
		return
	var captures: Array[Dictionary] = []
	for config: Dictionary in CASES:
		captures.append(await _capture_one(config, directory))
	var manifest: Dictionary = {
		"task_id": "UI-RESTART-1-P5-C-native",
		"engine": Engine.get_version_info()["string"],
		"renderer": DisplayServer.get_name(),
		"passed": _passed,
		"failed": _failed,
		"captures": captures,
		"input_method": "真实 TacticalScene 中 root.push_input 鼠标悬停；纯被动使用焦点入口",
		"data_boundary": "人物、技能、行动资源、结束状态来自 TacticalManager；五张技能图片仅由捕获调用方按真实 skill_id 注入",
		"approval": "实现证据，等待独立审查",
	}
	var receipt: FileAccess = FileAccess.open(directory.path_join("runtime-native-capture.json"), FileAccess.WRITE)
	if receipt == null:
		_check("原生回执写入", false)
	else:
		receipt.store_string(JSON.stringify(manifest, "\t") + "\n")
		receipt.close()
	print("HUD_M2_RUNTIME_NATIVE_RESULT passed=%d failed=%d captures=%d" % [_passed, _failed, captures.size()])
	quit(0 if _failed == 0 else 1)


func _capture_one(config: Dictionary, directory: String) -> Dictionary:
	root.size = config["size"] as Vector2i
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var manager: Object = scene.tactical_manager
	var dashboard: Control = scene.get("_bottom_dashboard") as Control
	await process_frame
	_move_pointer(Vector2(640.0, 320.0))
	root.gui_release_focus()
	await process_frame
	await _apply_case(config, dashboard, manager)
	var image: Image = await _wait_for_complete(dashboard, config)
	var result: Dictionary = {"name": config["name"], "width": root.size.x, "height": root.size.y, "result": "fail"}
	_check("%s连续两帧完整" % config["name"], image != null)
	if image != null:
		var output: String = directory.path_join(str(config["name"]) + ".png")
		var save_error: Error = image.save_png(output)
		_check("%s保存" % config["name"], save_error == OK)
		if save_error == OK:
			result["result"] = "pass"
			result["path"] = "dev_doc/ui-art-research/hud-m2-integration/evidence/" + str(config["name"]) + ".png"
			result["sha256"] = FileAccess.get_sha256(output)
			result["complete_frames"] = 2
			result["mode"] = config["mode"]
			result["content_top_y"] = dashboard.get_content_top_y()
			result["payload_skill_count"] = (dashboard.get_last_state().get("skills", []) as Array).size()
			result["rendered_skill_count"] = (dashboard.get_composition().get_node("BottomRow/SkillShelf").get_skill_slots() as Array).size()
			result["action_strip_visible"] = dashboard.get_composition().get_node("ActionResourceStrip").visible
			result["formal_dashboard"] = dashboard is RuntimeDashboard
	scene.queue_free()
	await process_frame
	return result


func _apply_case(config: Dictionary, dashboard: Control, manager: Object) -> void:
	match str(config["mode"]):
		"character_hover":
			var character: Control = dashboard.get_composition().get_node("BottomRow/CharacterHudPanel") as Control
			_move_pointer(character.get_inspection_control().get_global_rect().get_center())
			await process_frame
		"passive_focus":
			var slots: Array = dashboard.get_composition().get_node("BottomRow/SkillShelf").get_skill_slots()
			if not slots.is_empty():
				(slots[0] as Control).grab_focus()
			await process_frame
		"enemy":
			var enemies: Array = manager.units.filter(func(unit: Object) -> bool: return unit.faction == "enemy")
			if not enemies.is_empty():
				var enemy: Object = enemies[0]
				var enemy_screen: Vector2 = manager.get_viewport().get_canvas_transform() * manager.grid.grid_to_world(enemy.grid_position)
				await _click(enemy_screen)
			await process_frame


func _wait_for_complete(dashboard: Control, config: Dictionary) -> Image:
	var streak: int = 0
	for attempt: int in 24:
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		if image.get_size() == root.size and _structure_ready(dashboard, config) and _pixels_ready(image, dashboard):
			streak += 1
			if streak == 2:
				return image
		else:
			streak = 0
	return null


func _structure_ready(dashboard: Control, config: Dictionary) -> bool:
	var composition: Control = dashboard.get_composition()
	var row: Control = composition.get_node("BottomRow") as Control
	if not dashboard is RuntimeDashboard or row.get_child_count() != 5 or not composition.visible:
		return false
	var factor: float = float(root.size.x) / 1280.0
	var positions: Array[float] = [32.0, 266.0, 402.0, 886.0, 1172.0]
	var widths: Array[float] = [226.0, 128.0, 476.0, 278.0, 76.0]
	for index: int in row.get_child_count():
		var zone: Control = row.get_child(index) as Control
		if not zone.get_global_rect().position.is_equal_approx(Vector2(positions[index], 596.0) * factor) or not zone.get_global_rect().size.is_equal_approx(Vector2(widths[index], 108.0) * factor):
			return false
	var action_strip: Control = composition.get_node("ActionResourceStrip") as Control
	if not action_strip.get_global_rect().position.is_equal_approx(Vector2(503.0, 550.0) * factor) or not action_strip.get_global_rect().size.is_equal_approx(Vector2(274.0, 40.0) * factor):
		return false
	var enemy: bool = str(config["mode"]) == "enemy"
	if action_strip.visible == enemy:
		return false
	var slots: Array = composition.get_node("BottomRow/SkillShelf").get_skill_slots()
	var payload_skills: Array = dashboard.get_last_state().get("skills", []) as Array
	if enemy and not slots.is_empty():
		return false
	if not enemy and slots.size() != payload_skills.size():
		return false
	for slot: Control in slots:
		if slot.find_child("IconRect", true, false).texture == null:
			return false
	var end_control: Control = composition.get_node("BottomRow/EndTurnControl") as Control
	if not end_control.visible or end_control.get_node("EndTurnButton").visible == enemy or end_control.get_node("EndLabel").visible == enemy:
		return false
	var character: Control = composition.get_node("BottomRow/CharacterHudPanel") as Control
	var character_card: Control = character.get_inspection_panel()
	var passive_card: Control = (slots[0] as Control).get_inspection_panel() if not slots.is_empty() else null
	if character_card.visible != (str(config["mode"]) == "character_hover"):
		return false
	if passive_card != null and passive_card.visible != (str(config["mode"]) == "passive_focus"):
		return false
	if passive_card != null and passive_card.visible:
		var label: Label = passive_card.find_child("InspectionLabel", true, false) as Label
		if label.position.y < 12.0 or label.position.y + label.size.y > passive_card.size.y - 12.0:
			return false
	return true


func _pixels_ready(image: Image, dashboard: Control) -> bool:
	var composition: Control = dashboard.get_composition()
	var regions: Array[Rect2] = dashboard.get_input_blocking_rects()
	for region: Rect2 in regions:
		if not _region_has_drawn_pixels(image, region):
			return false
	return true


func _region_has_drawn_pixels(image: Image, region: Rect2) -> bool:
	var bounds: Rect2i = Rect2i(region).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return false
	var warm_pixels: int = 0
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var color: Color = image.get_pixel(x, y)
			if color.r >= 0.17 and color.r >= color.g * 1.15 and color.g >= color.b * 1.05:
				warm_pixels += 1
				if warm_pixels >= 40:
					return true
	return false


func _real_skill_icons() -> Dictionary:
	return {
		"swordsman_xinyan": load("res://assets/prototype/hud_m2/skill-xinyan.png"),
		"swordsman_zhanji": load("res://assets/prototype/hud_m2/skill-zhanji.png"),
		"swordsman_yishan": load("res://assets/prototype/hud_m2/skill-yishan.png"),
		"swordsman_zhaojia": load("res://assets/prototype/hud_m2/skill-zhaojia.png"),
		"swordsman_juhe": load("res://assets/prototype/hud_m2/skill-juhe.png"),
	}


func _move_pointer(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	root.push_input(event, true)


func _click(position: Vector2) -> void:
	_move_pointer(position)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + label)
