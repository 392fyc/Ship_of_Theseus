extends Node
## 发行副本的采集观察器；仅显式采集参数存在时调整窗口并记录真实画面。

var _output: String = ""
var _records: Array[Dictionary] = []
var _size := Vector2i.ZERO
var _frames_directory: String = ""
var _warmup: int = 90


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-config="):
			_output = argument.trim_prefix("--capture-config=")
		elif argument.begins_with("--capture-size="):
			var parts := argument.trim_prefix("--capture-size=").split("x")
			if parts.size() == 2:
				_size = Vector2i(int(parts[0]), int(parts[1]))
		elif argument.begins_with("--capture-directory="):
			_frames_directory = argument.trim_prefix("--capture-directory=")
	if _output.is_empty():
		return
	if not _output.is_absolute_path():
		push_error("发行采集配置输出必须使用绝对路径。")
		get_tree().quit(1)
		return
	if not _frames_directory.is_absolute_path() or _size not in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		push_error("发行采集需要绝对输出目录与三档标准尺寸。")
		get_tree().quit(1)
		return
	get_tree().root.borderless = true
	get_tree().root.size = _size
	RenderingServer.frame_post_draw.connect(_record_frame)


func _record_frame() -> void:
	if _warmup > 0:
		_warmup -= 1
		return
	if _records.size() >= 10:
		return
	var window: Window = get_tree().root
	var visible: Rect2 = window.get_visible_rect()
	var image: Image = window.get_texture().get_image()
	if window.size != _size or image.get_size() != _size:
		push_error("发行截图尺寸与目标窗口不符。")
		get_tree().quit(1)
		return
	var frame_path := _frames_directory.path_join("hud-preview-%d-frame%04d.png" % [_size.x, _records.size()])
	if image.save_png(frame_path) != OK:
		push_error("无法保存发行截图。")
		get_tree().quit(1)
		return
	_records.append({
		"renderer": RenderingServer.get_current_rendering_method(),
		"project_stretch_mode": ProjectSettings.get_setting("display/window/stretch/mode"),
		"content_scale_mode": int(window.content_scale_mode),
		"content_scale_size": [window.content_scale_size.x, window.content_scale_size.y],
		"window_size": [window.size.x, window.size.y],
		"visible_rect": [visible.position.x, visible.position.y, visible.size.x, visible.size.y],
		"image_size": [image.get_width(), image.get_height()],
	})
	var file: FileAccess = FileAccess.open(_output, FileAccess.WRITE)
	if file == null:
		push_error("无法保存发行采集实测配置。")
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify({"frames": _records}, "  "))
	file.close()
	if _records.size() == 10:
		get_tree().quit()
