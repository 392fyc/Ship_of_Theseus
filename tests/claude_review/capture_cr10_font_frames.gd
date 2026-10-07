extends SceneTree
## CR-10：正式 10×10 场景中采集普通文字、技能提示和属性卡。
## 输入来自测试脚本；此批只检查包内字体，不作为真实鼠标交互验收。

const CaptureMetadata := preload("res://tests/claude_review/capture_metadata.gd")
const EXAMPLES := "res://assets/prototype/battlefield_courtyard/terrain_examples.json"
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]
var _output: String = ""
var _check_scene: bool = false
var _session: Node2D
var _scene: Node2D
var _manager: Object
var _character: Control
var _slot: Control
var _records: Array[Dictionary] = []
var _failed: bool = false


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
		elif argument == "--check-scene":
			_check_scene = true
	_run.call_deferred()


func _run() -> void:
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_abort("采集只使用 Compatibility")
		return
	if _check_scene:
		if not await _create_session():
			return
		print("CR10_SCENE_BINDING ", JSON.stringify({"pass": true, "map_size": [10, 10],
			"slot_script": _slot.get_script().resource_path,
			"input_origin": "headless_scene_binding; not visual or desktop acceptance"}))
		quit(0)
		return
	var project: String = ProjectSettings.globalize_path("res://").simplify_path().replace("\\", "/").to_lower().trim_suffix("/")
	var output: String = _output.simplify_path().replace("\\", "/").to_lower().trim_suffix("/")
	if not _output.is_absolute_path() or output == project or output.begins_with(project + "/"):
		_abort("需要仓库外绝对输出目录")
		return
	if DisplayServer.get_name().to_lower() == "headless":
		_abort("整屏采集需要真实显示服务")
		return
	if DirAccess.dir_exists_absolute(_output) and not DirAccess.get_files_at(_output).is_empty():
		_abort("输出目录必须为空")
		return
	if DirAccess.make_dir_recursive_absolute(_output) != OK:
		_abort("无法创建输出目录")
		return
	root.borderless = true
	root.position = Vector2i.ZERO
	for dimensions: Vector2i in SIZES:
		root.size = dimensions
		await _frames(8)
		if not await _create_session():
			return
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
	quit(1 if _failed else 0)


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
	root.add_child(_session)
	await _frames(45)
	_scene = _session.get("battle") as Node2D
	_manager = _session.get("manager")
	if _scene == null or _manager == null or _manager.grid.width != 10 or _manager.grid.height != 10:
		_abort("正式试战场景尺寸不正确")
		return false
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


func _capture(group: String) -> void:
	await RenderingServer.frame_post_draw
	var frame: int = Engine.get_process_frames()
	var texture: ViewportTexture = root.get_texture()
	var image: Image = texture.get_image()
	var tooltip_visible: bool = _slot.is_inspection_visible()
	var inspection_visible: bool = _character.get_inspection_panel().is_visible_in_tree()
	var labels: Array[Dictionary] = []
	_collect_labels(root, labels)
	var fonts: Dictionary = _font_record(ThemeDB.fallback_font, {})
	var packaged_fonts_only: bool = _system_fallback_disabled(fonts)
	for label: Dictionary in labels:
		packaged_fonts_only = packaged_fonts_only and _system_fallback_disabled(label["font"])
	var state: Dictionary = {"capture_group": group, "input_origin": "script_warp_and_push_input",
		"map_source": EXAMPLES, "example": "courtyard", "map_size": [10, 10],
		"runtime_scene": _scene.scene_file_path, "tooltip_visible": tooltip_visible,
		"inspection_visible": inspection_visible, "visible_labels": labels,
		"global_fallback_font": fonts, "system_fallback_disabled": packaged_fonts_only,
		"window_size": [root.size.x, root.size.y],
		"viewport_size": [root.get_visible_rect().size.x, root.get_visible_rect().size.y],
		"texture_size": [texture.get_width(), texture.get_height()],
		"image_size": [image.get_width(), image.get_height()],
		"frame_binding": {"phase": "frame_post_draw", "start": frame, "end": Engine.get_process_frames()},
		"marks_visible": _scene.get("_bottom_dashboard").get_composition().get_marks_panel().is_visible_in_tree()}
	if frame != int(state["frame_binding"]["end"]) or image.get_size() != root.size:
		_abort("截图与状态跨帧或不是原生尺寸")
		return
	if tooltip_visible != (group == "font-skill-tooltip") or inspection_visible != (group == "font-portrait-inspection") or bool(state["marks_visible"]):
		_failed = true
		push_error("字体测试状态不符合用例：" + group)
	if not packaged_fonts_only:
		_failed = true
		push_error("实际显示字体仍允许系统回退")
	var basename: String = "%s-%dx%d" % [group, root.size.x, root.size.y]
	var png_path: String = _output.path_join(basename + ".png")
	if image.save_png(png_path) != OK:
		_abort("无法保存原始 PNG")
		return
	var state_path: String = _output.path_join(basename + ".json")
	var file: FileAccess = FileAccess.open(state_path, FileAccess.WRITE)
	if file == null:
		_abort("无法保存当帧字体状态")
		return
	file.store_string(JSON.stringify(state, "  "))
	file.close()
	var record: Dictionary = CaptureMetadata.capture_record(root, image, png_path, state)
	record["state_file"] = basename + ".json"
	record["state_sha256"] = FileAccess.get_sha256(state_path)
	_records.append(record)
	if not CaptureMetadata.write_manifest(root, _output.path_join("capture-metadata.json"), _records,
		{"script": "res://tests/claude_review/capture_cr10_font_frames.gd", "capture_schema": "cr10-font/1",
		"engine": Engine.get_version_info(), "display_server": DisplayServer.get_name(),
		"video_adapter": RenderingServer.get_video_adapter_name(), "audio_driver": AudioServer.get_driver_name()}):
		_abort("无法保存采集清单")
	print("CR10_FONT_CAPTURE ", JSON.stringify(record))


func _collect_labels(node: Node, result: Array[Dictionary]) -> void:
	if node is Label and (node as Label).is_visible_in_tree() and not (node as Label).text.is_empty():
		var label: Label = node as Label
		result.append({"node": str(label.get_path()), "text": label.text,
			"font_size": label.get_theme_font_size("font_size"), "font": _font_record(label.get_theme_font("font"), {})})
	for child: Node in node.get_children():
		_collect_labels(child, result)


func _font_record(font: Font, seen: Dictionary) -> Dictionary:
	if font == null or seen.has(font.get_instance_id()):
		return {}
	seen[font.get_instance_id()] = true
	var record: Dictionary = {"resource_path": font.resource_path, "name": font.get_font_name(), "fallbacks": []}
	if font is FontFile:
		record["allow_system_fallback"] = (font as FontFile).allow_system_fallback
		record["msdf"] = (font as FontFile).multichannel_signed_distance_field
	if font is FontVariation:
		record["base_font"] = _font_record((font as FontVariation).base_font, seen)
	for fallback: Font in font.fallbacks:
		record["fallbacks"].append(_font_record(fallback, seen))
	return record


func _move_pointer(point: Vector2) -> void:
	Input.warp_mouse(root.get_stretch_transform() * point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)


func _system_fallback_disabled(font: Dictionary) -> bool:
	if bool(font.get("allow_system_fallback", false)):
		return false
	if font.has("base_font") and not _system_fallback_disabled(font["base_font"]):
		return false
	for fallback: Dictionary in font.get("fallbacks", []):
		if not _system_fallback_disabled(fallback):
			return false
	return true


func _frames(count: int) -> void:
	for unused: int in count:
		await process_frame


func _abort(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)
