extends "res://tests/claude_review/capture_cr10_font_frames.gd"
## Windows 原生 GPU 字重对照；内部输入只用于展开文字，不移动系统鼠标。
## 保留项目拉伸；整屏与局部均来自同一次 frame_post_draw 的同一个 Image。

var _body_weight: String = "Medium"
var _target: Node2D
var _fixture: Dictionary = {}
var _requested := Vector2.ZERO
var _font_hashes: Dictionary = {}


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--weight="):
			_body_weight = argument.trim_prefix("--weight=")
	super._initialize()


func _run() -> void:
	if OS.get_name() != "Windows" or DisplayServer.get_name() != "Windows":
		_abort("本采集必须使用 Windows 显示服务")
		return
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_abort("本采集必须使用 Compatibility")
		return
	if not bool(ProjectSettings.get_setting("display/window/size/no_focus", false)):
		_abort("启动配置必须预先设置 no_focus")
		return
	if _body_weight not in ["Regular", "Medium"]:
		_abort("只接受 Regular 或 Medium 对照")
		return
	print("CR10_WINDOWS_PROCESS_ID ", OS.get_process_id())
	var project: String = ProjectSettings.globalize_path("res://").simplify_path().replace("\\", "/").to_lower().trim_suffix("/")
	var output: String = _output.simplify_path().replace("\\", "/").to_lower().trim_suffix("/")
	if not _output.is_absolute_path() or output == project or output.begins_with(project + "/"):
		_abort("需要仓库外绝对输出目录")
		return
	if DirAccess.dir_exists_absolute(_output) and not DirAccess.get_files_at(_output).is_empty():
		_abort("输出目录必须为空")
		return
	if DirAccess.make_dir_recursive_absolute(_output) != OK:
		_abort("无法创建输出目录")
		return
	root.unfocusable = true
	root.borderless = true
	root.position = Vector2i(-12000, -12000)
	for dimensions: Vector2i in SIZES:
		root.size = dimensions
		await _frames(8)
		if not await _create_session():
			return
		# 场景持有主题后再切换；否则 load() 的局部引用释放后会重新载入默认字重。
		if not _set_comparison_weight():
			_abort("对照字体链设置失败")
			return
		await _frames(4)
		_move_pointer(Vector2(20, 100))
		await _frames(12)
		await _capture("font-normal")
		_manager.request_end_move()
		await _frames(12)
		_move_pointer(_slot.get_global_rect().get_center())
		await _frames(90)
		await _capture("font-skill-tooltip")
		_move_pointer(_character.get_inspection_control().get_global_rect().get_center())
		await _frames(30)
		await _capture("font-portrait-inspection")
		_move_pointer(Vector2(20, 100))
		await _frames(12)
		_manager.request_skill_selection("swordsman_zhanji")
		_move_pointer(_target.get_global_transform_with_canvas().origin)
		await _frames(12)
		await _capture("font-forecast")
	quit(1 if _failed else 0)


func _set_comparison_weight() -> bool:
	# 对照只发生在当前测试进程，不写入资源文件或生产配置。
	var checks: Script = load("res://tests/claude_review/cr10_font_runtime_check.gd")
	_font_hashes.clear()
	return bool(checks.call("configure_capture_weight", _body_weight))


func _create_session() -> bool:
	if is_instance_valid(_session):
		root.remove_child(_session)
		_session.free()
		await _frames(3)
	var examples: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXAMPLES))
	var session_script: Script = load("res://scripts/tactical/terrain_battle_session.gd") as Script
	_session = session_script.new()
	var configured: Dictionary = _session.configure_map(examples["courtyard"].duplicate(true))
	if not bool(configured.get("ok", false)):
		_abort("courtyard 地形无法配置")
		return false
	var map: Dictionary = _session.get("_configured_map")
	var grid := Grid.new()
	grid.initialize(map)
	var spawn: Array = map["player_units"][0]["position"]
	var actor_cell := Vector2i(int(spawn[0]), int(spawn[1]))
	var original_enemy: Array = map["enemy_units"][0]["position"].duplicate()
	var neighbor := Vector2i(-1, -1)
	for cell: Vector2i in grid.get_neighbors(actor_cell):
		if grid.get_cell(cell).is_passable():
			neighbor = cell
			break
	if neighbor == Vector2i(-1, -1):
		_abort("测试出生点没有合法相邻格")
		return false
	map["enemy_units"][0]["position"] = [neighbor.x, neighbor.y]
	_fixture = {"kind": "font_overlay_spawn_only", "original_enemy_spawn": original_enemy,
		"test_enemy_spawn": [neighbor.x, neighbor.y], "terrain_modified": false, "gameplay_values_modified": false}
	root.add_child(_session)
	await _frames(45)
	_scene = _session.get("battle") as Node2D
	_manager = _session.get("manager")
	if _scene == null or _manager == null or _manager.grid.width != 10 or _manager.grid.height != 10:
		_abort("正式试战场景尺寸不正确")
		return false
	_target = _manager.units[1] as Node2D
	_session.fit_board()
	await _frames(8)
	var composition: Control = _scene.get("_bottom_dashboard").get_composition()
	_character = composition.get_node("BottomRow/CharacterHudPanel") as Control
	var shelf: Node = composition.get_node("BottomRow/SkillShelf")
	_slot = null
	for node: Node in shelf.get_skill_slots():
		var view: RefCounted = node.get("_view") as RefCounted
		if view != null and str(view.get("skill_id")) == "swordsman_zhanji":
			_slot = node as Control
			break
	if _slot == null:
		_abort("正式 M2 技能栏没有斩击")
		return false
	return true


func _move_pointer(point: Vector2) -> void:
	_requested = point
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)


func _capture(group: String) -> void:
	await RenderingServer.frame_post_draw
	var frame: int = Engine.get_process_frames()
	var texture: ViewportTexture = root.get_texture()
	var image: Image = texture.get_image()
	var tooltip_visible: bool = _slot.is_inspection_visible()
	var inspection_visible: bool = _character.get_inspection_panel().is_visible_in_tree()
	var forecast: Control = _scene.get("_damage_forecaster") as Control
	var texts: Array[Dictionary] = []
	_collect_texts(root, texts)
	var expected_font: String = "res://assets/fonts/noto_sans_cjk_sc/NotoSansCJKsc-%s-subset.otf" % _body_weight
	var theme: Theme = load("res://assets/ui/themes/hud_m2.tres")
	var actual_cjk: Dictionary = _font_record(theme.default_font, {}).get("fallbacks", [])[0]
	if str(actual_cjk.get("font_data_sha256", "")) != FileAccess.get_sha256(expected_font):
		_abort("实际 HUD 正文字重与对照用例不符")
		return
	var panels: Dictionary = {"character": _character, "turn-order": _scene.get("_turn_order_bar"),
		"tooltip": _slot.get_inspection_panel(), "attributes": _character.get_inspection_panel(), "forecast": forecast}
	var regions: Array[Dictionary] = []
	for id: String in panels:
		var panel: Control = panels[id] as Control
		if panel != null and panel.is_visible_in_tree():
			regions.append({"id": id, "node": str(panel.get_path()), "image_rect": _image_rect(panel),
				"local_size": [panel.size.x, panel.size.y], "global_rect": _rect_array(panel.get_global_rect())})
	var state := {"capture_group": group, "body_weight": _body_weight, "title_weight": "Bold",
		"input_origin": "viewport.push_input only; no operating-system mouse calls", "requested_pointer": [_requested.x, _requested.y],
		"map_source": EXAMPLES, "example": "courtyard", "map_size": [10, 10], "fixture": _fixture,
		"runtime_scene": _scene.scene_file_path, "tooltip_visible": tooltip_visible, "inspection_visible": inspection_visible,
		"forecast_visible": forecast.is_visible_in_tree(), "texts": texts, "regions": regions,
		"window_size": [root.size.x, root.size.y], "window_position": [root.position.x, root.position.y], "window_unfocusable": root.unfocusable,
		"viewport_size": [root.get_visible_rect().size.x, root.get_visible_rect().size.y],
		"texture_size": [texture.get_width(), texture.get_height()], "image_size": [image.get_width(), image.get_height()],
		"frame_binding": {"phase": "frame_post_draw", "start": frame, "end": Engine.get_process_frames()},
		"marks_visible": _scene.get("_bottom_dashboard").get_composition().get_marks_panel().is_visible_in_tree()}
	if frame != int(state["frame_binding"]["end"]) or image.get_size() != root.size:
		_abort("截图与状态跨帧或不是原生尺寸")
		return
	if tooltip_visible != (group == "font-skill-tooltip") or inspection_visible != (group == "font-portrait-inspection") or forecast.is_visible_in_tree() != (group == "font-forecast") or bool(state["marks_visible"]):
		_failed = true
		push_error("字重测试状态不符合用例：" + group)
	var basename: String = "%s-%dx%d" % [group, root.size.x, root.size.y]
	var png_path: String = _output.path_join(basename + ".png")
	if image.save_png(png_path) != OK:
		_abort("无法保存原始整屏 PNG")
		return
	var source_sha: String = FileAccess.get_sha256(png_path)
	for region: Dictionary in regions:
		var r: Array = region["image_rect"]
		var start := Vector2i(floori(r[0]), floori(r[1]))
		var end := Vector2i(ceili(r[0] + r[2]), ceili(r[1] + r[3]))
		var crop_rect := Rect2i(start, end - start).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		var crop_name: String = basename + "-" + str(region["id"]) + ".png"
		if image.get_region(crop_rect).save_png(_output.path_join(crop_name)) != OK:
			_abort("无法保存同帧局部")
			return
		region["file"] = crop_name
		region["sha256"] = FileAccess.get_sha256(_output.path_join(crop_name))
		region["source_sha256"] = source_sha
		region["crop_rect"] = [crop_rect.position.x, crop_rect.position.y, crop_rect.size.x, crop_rect.size.y]
	var state_path: String = _output.path_join(basename + ".json")
	var file := FileAccess.open(state_path, FileAccess.WRITE)
	if file == null:
		_abort("无法保存同帧状态")
		return
	file.store_string(JSON.stringify(state, "  "))
	file.close()
	var record: Dictionary = CaptureMetadata.capture_record(root, image, png_path, state)
	record["state_file"] = basename + ".json"
	record["state_sha256"] = FileAccess.get_sha256(state_path)
	_records.append(record)
	var written: bool = CaptureMetadata.write_manifest(root, _output.path_join("capture-metadata.json"), _records,
		{"script": "res://tests/claude_review/capture_cr10_windows_weights.gd", "capture_schema": "cr10-windows-weights/1", "body_weight": _body_weight,
		"engine": Engine.get_version_info(), "os": OS.get_name(), "display_server": DisplayServer.get_name(),
		"video_adapter": RenderingServer.get_video_adapter_name(), "audio_driver": AudioServer.get_driver_name()})
	if not written:
		_abort("无法保存采集元数据清单")
		return
	print("CR10_WINDOWS_CAPTURE ", JSON.stringify({"file": basename, "sha256": source_sha, "frame": frame, "regions": regions.size()}))


func _collect_texts(node: Node, result: Array[Dictionary]) -> void:
	if node is Label and (node as Label).is_visible_in_tree() and not (node as Label).text.is_empty():
		var label := node as Label
		var font: Font = label.get_theme_font("font")
		var fs: int = label.get_theme_font_size("font_size")
		result.append({"node": str(label.get_path()), "kind": "Label", "text": label.text, "image_rect": _image_rect(label),
			"font_size": fs, "font": _font_record(font, {}), "font_height": font.get_height(fs), "line_count": label.get_line_count(),
			"minimum_size": [label.get_minimum_size().x, label.get_minimum_size().y], "local_size": [label.size.x, label.size.y],
			"clip_text": label.clip_text, "font_color": str(label.get_theme_color("font_color"))})
	elif node is RichTextLabel and (node as RichTextLabel).is_visible_in_tree():
		var rich := node as RichTextLabel
		result.append({"node": str(rich.get_path()), "kind": "RichTextLabel", "text": rich.get_parsed_text(), "image_rect": _image_rect(rich),
			"font_size": rich.get_theme_font_size("normal_font_size"), "normal_font": _font_record(rich.get_theme_font("normal_font"), {}),
			"bold_font": _font_record(rich.get_theme_font("bold_font"), {}), "content_height": rich.get_content_height(),
			"local_size": [rich.size.x, rich.size.y], "visible_content_rect": _image_rect(rich)})
	for child: Node in node.get_children():
		_collect_texts(child, result)


func _font_record(font: Font, seen: Dictionary) -> Dictionary:
	var record: Dictionary = super._font_record(font, seen)
	if font == null or record.is_empty():
		return record
	record["style"] = font.get_font_style_name()
	if font is FontFile:
		if not _font_hashes.has(font.get_instance_id()):
			var hash := HashingContext.new()
			hash.start(HashingContext.HASH_SHA256)
			hash.update((font as FontFile).data)
			_font_hashes[font.get_instance_id()] = hash.finish().hex_encode()
		record["font_data_sha256"] = _font_hashes[font.get_instance_id()]
	return record


func _image_rect(control: Control) -> Array:
	var transform: Transform2D = root.get_stretch_transform() * control.get_global_transform_with_canvas()
	return _rect_array(transform * Rect2(Vector2.ZERO, control.size))


func _rect_array(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
