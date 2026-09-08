extends "res://tests/test_hud_m2_skin_theme.gd"

## Main 独占原生运行。所有主图来自同一个真实 TacticalScene 和同一个 HUD 实例。
const CAPTURE_FLAG := "--capture-hud-m2-skin"
const FE_CAPTURE_FLAG := "--capture-hud-m2-fe-import"
const FE_OUTPUT_DIRECTORY := "res://dev_doc/ui-art-research/hud-m2-fe-import/evidence"
const OUTPUT_DIRECTORY := "res://dev_doc/ui-art-research/hud-m2-skin/evidence"
const INITIAL_CAPTURE_DIRECTORY := "res://.omc/ui-m2/skin-r1-native-initial/evidence"
const CAPTURE_CASES: Array[Dictionary] = [
	{"name": "skin-default-normal-1280", "size": Vector2i(1280, 720), "mode": "normal", "skin": "default"},
	{"name": "skin-default-character-1280", "size": Vector2i(1280, 720), "mode": "character", "skin": "default"},
	{"name": "skin-default-passive-1280", "size": Vector2i(1280, 720), "mode": "passive", "skin": "default"},
	{"name": "skin-texture-passive-1280", "size": Vector2i(1280, 720), "mode": "passive", "skin": "texture"},
	{"name": "skin-texture-normal-1280", "size": Vector2i(1280, 720), "mode": "normal", "skin": "texture"},
	{"name": "skin-texture-character-1280", "size": Vector2i(1280, 720), "mode": "character", "skin": "texture"},
	{"name": "skin-restored-character-1280", "size": Vector2i(1280, 720), "mode": "character", "skin": "restored"},
	{"name": "skin-restored-normal-1280", "size": Vector2i(1280, 720), "mode": "normal", "skin": "restored"},
	{"name": "skin-default-normal-1920", "size": Vector2i(1920, 1080), "mode": "normal", "skin": "default"},
	{"name": "skin-texture-normal-1920", "size": Vector2i(1920, 1080), "mode": "normal", "skin": "texture"},
	{"name": "skin-default-normal-2560", "size": Vector2i(2560, 1440), "mode": "normal", "skin": "default"},
	{"name": "skin-texture-normal-2560", "size": Vector2i(2560, 1440), "mode": "normal", "skin": "texture"},
	{"name": "skin-texture-enemy-1280", "size": Vector2i(1280, 720), "mode": "enemy", "skin": "texture"},
]

var _output_directory: String = OUTPUT_DIRECTORY
var _display_fixture_active: bool = false
var _alternate_theme: Theme
var _normal_hud_images: Dictionary = {}


func _initialize() -> void:
	if "--verify-existing-skin-icons" in OS.get_cmdline_user_args():
		_verify_existing_icons.call_deferred()
		return
	if FE_CAPTURE_FLAG in OS.get_cmdline_user_args():
		_output_directory = FE_OUTPUT_DIRECTORY
	if DisplayServer.get_name() == "headless" or not (CAPTURE_FLAG in OS.get_cmdline_user_args() or FE_CAPTURE_FLAG in OS.get_cmdline_user_args()):
		print("HUD_M2_SKIN_CAPTURE_REQUIRES_NATIVE_AND_FLAG")
		quit(1)
		return
	_run.call_deferred()


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var directory: String = ProjectSettings.globalize_path(_output_directory)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(directory)
	_check("原生输出目录", directory_error == OK)
	if directory_error != OK:
		quit(1)
		return
	_alternate_theme = make_alternate_theme()
	var environment: Dictionary = await _make_runtime()
	var dashboard: Control = environment["dashboard"]
	var composition: Control = dashboard.get_composition()
	var initial_id: int = composition.get_instance_id()
	var records: Array[Dictionary] = []
	var capture_cases: Array[Dictionary] = CAPTURE_CASES.duplicate(true)
	if _output_directory == FE_OUTPUT_DIRECTORY:
		for count: int in [0, 7]:
			capture_cases.insert(capture_cases.size() - 1, {"name": "skin-default-skills-%d-1280" % count, "size": Vector2i(1280, 720), "mode": "skill_boundary", "skill_count": count, "skin": "default"})
		capture_cases.insert(capture_cases.size() - 1, {"name": "skin-default-capacity-3-1280", "size": Vector2i(1280, 720), "mode": "capacity_boundary", "skin": "default"})
	for config: Dictionary in capture_cases:
		if _output_directory == FE_OUTPUT_DIRECTORY:
			config["name"] = str(config["name"]).replace("skin-", "fe-")
		records.append(await _capture_case(config, environment, directory))
		_check("连续切换复用唯一组合", dashboard.get_composition().get_instance_id() == initial_id)
	_check_image_changes()
	var manifest: Dictionary = {
		"task_id": "FE-IMPORT-R1-native" if _output_directory == FE_OUTPUT_DIRECTORY else "SKIN-R1-native", "engine": Engine.get_version_info()["string"],
		"display_server": DisplayServer.get_name(), "captures": records,
		"passed": _passed, "failed": _failed,
		"data_source": "主图来自同一个真实TacticalScene/TacticalManager；明确标注的skill_boundary与capacity_boundary仅覆盖显示载荷边界，不改玩法对象。技能图片按skill_id注入。",
		"alternate_theme": "默认Theme的副本；普通槽替换为不透明中心的程序化StyleBoxTexture夹具，人物、被动、结束及共享框改变样式；不作为美术资产。",
		"stability": "每张主图至少连续两帧结构就绪且HUD区域图像摘要一致；连接放大区直接裁自对应主图。",
		"approval": "原生实现证据，等待独立审查与用户实机确认",
	}
	var file: FileAccess = FileAccess.open(directory.path_join("fe-native-capture.json" if _output_directory == FE_OUTPUT_DIRECTORY else "skin-native-capture.json"), FileAccess.WRITE)
	_check("原生清单可写", file != null)
	if file != null:
		file.store_string(JSON.stringify(manifest, "\t") + "\n")
		file.close()
	(environment["scene"] as Node).queue_free()
	await _settle()
	print("HUD_M2_SKIN_NATIVE_RESULT passed=%d failed=%d captures=%d" % [_passed, _failed, records.size()])
	quit(0 if _failed == 0 else 1)


func _capture_case(config: Dictionary, environment: Dictionary, directory: String) -> Dictionary:
	var dashboard: Control = environment["dashboard"]
	var composition: Control = dashboard.get_composition()
	var manager: Object = environment["manager"]
	if _display_fixture_active:
		dashboard.update_state(manager.get_dashboard_data())
		_display_fixture_active = false
		await _settle()
	var steps: Array[String] = []
	root.size = config["size"] as Vector2i
	await _settle()
	var old_focus: Control = root.gui_get_focus_owner()
	var old_character_visible: bool = composition.get_node("BottomRow/CharacterHudPanel").get_inspection_panel().visible
	var old_slots: Array = composition.get_node("BottomRow/SkillShelf").get_skill_slots()
	var previous_skin: Theme = dashboard.get_skin_theme()
	if str(config["skin"]) == "texture":
		dashboard.set_skin_theme(_alternate_theme)
		steps.append("在原宿主调用set_skin_theme(替换Theme)")
	else:
		dashboard.set_skin_theme(null)
		steps.append("在原宿主调用set_skin_theme(null)，使用默认Theme")
	await _settle()
	var identity_preserved: bool = old_slots == composition.get_node("BottomRow/SkillShelf").get_skill_slots()
	var focus_preserved: bool = old_focus == root.gui_get_focus_owner()
	var hover_preserved: bool = old_character_visible == composition.get_node("BottomRow/CharacterHudPanel").get_inspection_panel().visible
	_check(str(config["name"]) + "切换保留槽实例、焦点和悬浮", identity_preserved and focus_preserved and hover_preserved)
	root.gui_release_focus()
	_move_pointer(Vector2(320, 250))
	await _settle()
	match str(config["mode"]):
		"skill_boundary", "capacity_boundary":
			var state: Dictionary = manager.get_dashboard_data().duplicate(true)
			if str(config["mode"]) == "skill_boundary":
				var source: Array = state.get("skills", []) as Array
				var entries: Array[Dictionary] = []
				for index: int in int(config["skill_count"]):
					entries.append((source[index % source.size()] as Dictionary).duplicate(true))
				state["skills"] = entries
			else:
				state["action_resources"] = {"movement_remaining": 4, "movement_available": false, "standard_capacity": 3, "standard_remaining": 1, "swift_capacity": 3, "swift_remaining": 1}
			dashboard.update_state(state)
			_display_fixture_active = true
			steps.append("只覆盖显示载荷验证边界；TacticalManager实际状态未修改")

		"character":
			var character: Control = composition.get_node("BottomRow/CharacterHudPanel") as Control
			_move_pointer(character.get_inspection_control().get_global_rect().get_center())
			steps.append("root.push_input将鼠标移入整个人物栏中心")
		"passive":
			var passive: Control = _real_passive_slot(dashboard)
			if passive != null:
				passive.grab_focus()
			steps.append("按真实载荷is_passive和active_capable定位纯被动并获得焦点")
		"enemy":
			var enemies: Array = manager.units.filter(func(unit: Object) -> bool: return unit.faction == "enemy")
			if not enemies.is_empty():
				var enemy: Object = enemies[0]
				var enemy_screen: Vector2 = manager.get_viewport().get_canvas_transform() * manager.grid.grid_to_world(enemy.grid_position)
				await _click(enemy_screen)
			steps.append("root.push_input真实点击敌方屏幕坐标进入检视")
		_:
			steps.append("释放焦点并将鼠标移至战场空白")
	var image: Image = await _stable_image(dashboard, config)
	var record: Dictionary = {
		"name": config["name"], "mode": config["mode"], "skin": config["skin"],
		"width": root.size.x, "height": root.size.y, "result": "fail", "steps": steps,
		"data_kind": "display_boundary_fixture" if _display_fixture_active else "real_tactical_manager", "composition_instance_id": composition.get_instance_id(),
		"theme_resource_changed": previous_skin != dashboard.get_skin_theme(),
		"slots_preserved": identity_preserved, "focus_preserved": focus_preserved, "hover_preserved": hover_preserved,
	}
	_check(str(config["name"]) + "连续两帧稳定", image != null)
	if image == null:
		return record
	var output: String = directory.path_join(str(config["name"]) + ".png")
	var save_error: Error = image.save_png(output)
	_check(str(config["name"]) + "保存主图", save_error == OK)
	if save_error != OK:
		return record
	record["result"] = "pass"
	if not identity_preserved or not focus_preserved or not hover_preserved:
		record["result"] = "fail"
	record["path"] = _output_directory.trim_prefix("res://") + "/" + str(config["name"]) + ".png"
	record["sha256"] = FileAccess.get_sha256(output)
	record["complete_frames"] = 2
	record["payload_skill_count"] = (dashboard.get_last_state().get("skills", []) as Array).size()
	record["rendered_skill_count"] = (composition.get_node("BottomRow/SkillShelf").get_skill_slots() as Array).size()
	record["action_strip_visible"] = composition.get_node("ActionResourceStrip").visible
	record["content_top_y"] = dashboard.get_content_top_y()
	var factor: float = float(root.size.x) / 1280.0
	var crop_rect := Rect2i(Vector2(450, 534) * factor, Vector2(380, 86) * factor)
	var connection_image: Image = image.get_region(crop_rect)
	var connection_path: String = directory.path_join(str(config["name"]) + "-connections.png")
	var crop_error: Error = connection_image.save_png(connection_path)
	_check(str(config["name"]) + "保存连接区域", crop_error == OK)
	if crop_error == OK:
		record["connections"] = {"path": _output_directory.trim_prefix("res://") + "/" + str(config["name"]) + "-connections.png",
			"width": connection_image.get_width(), "height": connection_image.get_height(),
			"sha256": FileAccess.get_sha256(connection_path), "source_rect": [crop_rect.position.x, crop_rect.position.y, crop_rect.size.x, crop_rect.size.y]}
	if str(config["skin"]) == "texture":
		var marker_count: int = _count_color(image, composition.get_node("BottomRow").get_global_rect(), TEXTURE_MARKER)
		record["texture_marker_pixels"] = marker_count
		_check(str(config["name"]) + "StyleBoxTexture真实参与绘制", marker_count >= 20)
		if marker_count < 20:
			record["result"] = "fail"
		var frame_markers: int = _count_color(image, Rect2(Vector2(32, 550) * factor, Vector2(1216, 154) * factor), SHARED_MARKER)
		record["shared_marker_pixels"] = frame_markers
		_check(str(config["name"]) + "共享框真正改变颜色", frame_markers >= 20)
		if frame_markers < 20:
			record["result"] = "fail"
	if str(config["mode"]) == "normal" and root.size == Vector2i(1280, 720):
		_normal_hud_images[str(config["skin"])] = image.get_region(Rect2i(32, 548, 1216, 156))
	var icon_records: Array[Dictionary] = _active_icon_pixels(image, dashboard)
	record["active_icon_pixels"] = icon_records
	for icon_record: Dictionary in icon_records:
		_check(str(config["name"]) + "主动图标实际内容：" + str(icon_record["skill_id"]), bool(icon_record["passed"]))
		if not bool(icon_record["passed"]):
			record["result"] = "fail"
	return record


func _stable_image(dashboard: Control, config: Dictionary) -> Image:
	var last_digest: String = ""
	var streak: int = 0
	for attempt: int in 60:
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		if image.get_size() != root.size or not _capture_structure_ready(dashboard, config):
			streak = 0
			last_digest = ""
			continue
		var factor: float = float(root.size.x) / 1280.0
		var frame: Control = dashboard.get_composition().get_node("SharedFrame") as Control
		var frame_style: StyleBox = frame.get_frame_style()
		var frame_color: Color = frame_style.get("border_color")
		var material: Texture2D = frame_style.get("material_texture") as Texture2D
		if material != null:
			# 从实际获批材质选取顶部铜边颜色，等待真正绘制而非只检查节点可见。
			frame_color = material.get_image().get_pixel(600, 1)
		if _count_color(image, Rect2(Vector2(32, 550) * factor, Vector2(1216, 154) * factor), frame_color) < 20:
			streak = 0
			last_digest = ""
			continue
		var region: Image = image.get_region(Rect2i(Vector2(32, 360) * factor, Vector2(1216, 344) * factor))
		var digest: String = _image_digest(region)
		streak = streak + 1 if digest == last_digest else 1
		last_digest = digest
		if streak >= 2:
			return image
	return null


func _capture_structure_ready(dashboard: Control, config: Dictionary) -> bool:
	var composition: Control = dashboard.get_composition()
	if not dashboard is RuntimeDashboard or not composition.visible or not _geometry_ready(composition):
		return false
	var enemy: bool = str(config["mode"]) == "enemy"
	if composition.get_node("ActionResourceStrip").visible == enemy:
		return false
	var slots: Array = composition.get_node("BottomRow/SkillShelf").get_skill_slots()
	if enemy:
		if not slots.is_empty():
			return false
	else:
		if slots.size() != (dashboard.get_last_state().get("skills", []) as Array).size():
			return false
		for slot: Control in slots:
			if slot.get_node("Content/IconRect").texture == null:
				return false
	var character_card: Control = composition.get_node("BottomRow/CharacterHudPanel").get_inspection_panel()
	if character_card.visible != (str(config["mode"]) == "character"):
		return false
	var passive: Control = _real_passive_slot(dashboard)
	if str(config["mode"]) == "passive" and (passive == null or not passive.is_inspection_visible()):
		return false
	if passive != null and str(config["mode"]) != "passive" and passive.is_inspection_visible():
		return false
	return true


func _real_passive_slot(dashboard: Control) -> Control:
	var source: Array = dashboard.get_last_state().get("skills", []) as Array
	var slots: Array = dashboard.get_composition().get_node("BottomRow/SkillShelf").get_skill_slots()
	for index: int in mini(source.size(), slots.size()):
		var entry: Dictionary = source[index] as Dictionary
		if bool(entry.get("is_passive", false)) and not bool(entry.get("active_capable", false)):
			return slots[index] as Control
	return null


func _count_color(image: Image, region: Rect2, expected: Color) -> int:
	var bounds: Rect2i = Rect2i(region).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var count: int = 0
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			var sample: Color = image.get_pixel(x, y)
			if absf(sample.r - expected.r) < 0.035 and absf(sample.g - expected.g) < 0.035 and absf(sample.b - expected.b) < 0.035:
				count += 1
	return count


func _image_digest(image: Image) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(image.get_data())
	return context.finish().hex_encode()


func _check_image_changes() -> void:
	if not _normal_hud_images.has_all(["default", "texture", "restored"]):
		_check("三种1280常态图齐全", false)
		return
	var default_image: Image = _normal_hud_images["default"]
	var alternate_image: Image = _normal_hud_images["texture"]
	var restored_image: Image = _normal_hud_images["restored"]
	_check("换肤前后HUD实际像素不同", _image_digest(default_image) != _image_digest(alternate_image))
	_check("切回默认HUD实际像素恢复", _image_digest(default_image) == _image_digest(restored_image))


func _active_icon_pixels(image: Image, dashboard: Control) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var source: Array = dashboard.get_last_state().get("skills", []) as Array
	var slots: Array = dashboard.get_composition().get_node("BottomRow/SkillShelf").get_skill_slots()
	for index: int in mini(source.size(), slots.size()):
		var entry: Dictionary = source[index] as Dictionary
		if not bool(entry.get("active_capable", not bool(entry.get("is_passive", false)))):
			continue
		var icon: TextureRect = (slots[index] as Node).get_node("Content/IconRect") as TextureRect
		var icon_rect: Rect2 = icon.get_global_rect()
		# 中间横带避开右上快捷键、底部行动和费用叠层；只采样已注入图标的内容。
		var sample := Rect2i(icon_rect.position + icon_rect.size * Vector2(0.2, 0.35), icon_rect.size * Vector2(0.6, 0.3))
		sample = sample.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		var colors: Dictionary = {}
		var low := Vector3.ONE
		var high := Vector3.ZERO
		var total: int = sample.size.x * sample.size.y
		var dominant: int = 0
		for y: int in range(sample.position.y, sample.end.y):
			for x: int in range(sample.position.x, sample.end.x):
				var pixel: Color = image.get_pixel(x, y)
				var key: int = pixel.to_rgba32()
				colors[key] = int(colors.get(key, 0)) + 1
				dominant = maxi(dominant, int(colors[key]))
				low = Vector3(minf(low.x, pixel.r), minf(low.y, pixel.g), minf(low.z, pixel.b))
				high = Vector3(maxf(high.x, pixel.r), maxf(high.y, pixel.g), maxf(high.z, pixel.b))
		var contrast: float = maxf(high.x - low.x, maxf(high.y - low.y, high.z - low.z))
		var visible_content: bool = icon.texture != null and colors.size() >= 8 and total - dominant >= 8 and contrast >= 0.04
		records.append({"skill_id": str(entry.get("skill_id", "")), "passed": visible_content,
			"sample_rect": [sample.position.x, sample.position.y, sample.size.x, sample.size.y],
			"distinct_colors": colors.size(), "non_uniform_pixels": total - dominant,
			"max_channel_range": contrast, "sample_pixels": total})
	return records


func _verify_existing_icons() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var environment: Dictionary = await _make_runtime()
	var records: Array[Dictionary] = []
	for name: String in ["skin-default-normal-1280", "skin-texture-normal-1280", "skin-restored-normal-1280"]:
		var source_path: String = INITIAL_CAPTURE_DIRECTORY.path_join(name + ".png")
		var image: Image = Image.load_from_file(source_path)
		if image == null:
			_check(name + "既有图像可读", false)
			continue
		var icons: Array[Dictionary] = _active_icon_pixels(image, environment["dashboard"] as Control)
		records.append({"source": source_path.trim_prefix("res://"), "sha256": FileAccess.get_sha256(source_path), "icons": icons})
		for icon_record: Dictionary in icons:
			print("SKIN_ICON_PIXEL_TRACE %s %s" % [name, JSON.stringify(icon_record)])
			_check(name + "主动图标内容" + str(icon_record["skill_id"]), bool(icon_record["passed"]))
	var output: FileAccess = FileAccess.open("res://.omc/ui-m2/skin-r1-test-icon-pixels-before.json", FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify({"source_kind": "修复前原生截图，只读核验", "passed": _passed, "failed": _failed, "captures": records}, "\t") + "\n")
		output.close()
	(environment["scene"] as Node).queue_free()
	await _settle()
	print("HUD_M2_SKIN_EXISTING_ICON_RESULT passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
