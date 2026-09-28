extends Node
## 发行副本的只读采集观察器，仅在显式 --capture-config 参数存在时记录配置。

var _output: String = ""
var _records: Array[Dictionary] = []


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-config="):
			_output = argument.trim_prefix("--capture-config=")
	if _output.is_empty():
		return
	if not _output.is_absolute_path():
		push_error("发行采集配置输出必须使用绝对路径。")
		return
	RenderingServer.frame_post_draw.connect(_record_frame)


func _record_frame() -> void:
	var window: Window = get_tree().root
	var visible: Rect2 = window.get_visible_rect()
	_records.append({
		"renderer": RenderingServer.get_current_rendering_method(),
		"project_stretch_mode": ProjectSettings.get_setting("display/window/stretch/mode"),
		"content_scale_mode": int(window.content_scale_mode),
		"content_scale_size": [window.content_scale_size.x, window.content_scale_size.y],
		"window_size": [window.size.x, window.size.y],
		"visible_rect": [visible.position.x, visible.position.y, visible.size.x, visible.size.y],
		"image_size": [window.get_texture().get_width(), window.get_texture().get_height()],
	})
	var file: FileAccess = FileAccess.open(_output, FileAccess.WRITE)
	if file == null:
		push_error("无法保存发行采集实测配置。")
		return
	file.store_string(JSON.stringify({"frames": _records}, "  "))
	file.close()
