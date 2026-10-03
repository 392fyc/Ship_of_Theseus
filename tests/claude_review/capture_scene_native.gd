extends SceneTree

const CaptureMetadata := preload("res://tests/claude_review/capture_metadata.gd")

## Claude 审查采集：按项目真实拉伸设置（或关闭拉伸作对照）加载任意场景，逐尺寸保存视口原图、摘要与窗口参数。
## 运行：Godot_console.exe --path <project> --rendering-method gl_compatibility \
##   --script res://tests/claude_review/capture_scene_native.gd -- \
##   --scene=res://scenes/tactical/TacticalScene.tscn --output=<仓库外绝对目录> \
##   [--sizes=1280x720,1920x1080,2560x1440] [--stretch=project|disabled] [--wait=90] [--prefix=名称]
## stretch=project 保留 project.godot 的 canvas_items 拉伸，代表实际游戏；disabled 复现既有 HUD 采集脚本的做法。

var _scene_path: String = ""
var _output: String = ""
var _sizes: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]
var _stretch: String = "project"
var _wait_frames: int = 90
var _prefix: String = "capture"
var _records: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			_scene_path = arg.trim_prefix("--scene=")
		elif arg.begins_with("--output="):
			_output = arg.trim_prefix("--output=")
		elif arg.begins_with("--sizes="):
			_sizes.clear()
			for token: String in arg.trim_prefix("--sizes=").split(","):
				var parts: PackedStringArray = token.split("x")
				_sizes.append(Vector2i(int(parts[0]), int(parts[1])))
		elif arg.begins_with("--stretch="):
			_stretch = arg.trim_prefix("--stretch=")
		elif arg.begins_with("--wait="):
			_wait_frames = int(arg.trim_prefix("--wait="))
		elif arg.begins_with("--prefix="):
			_prefix = arg.trim_prefix("--prefix=")
	if DisplayServer.get_name().to_lower() == "headless":
		_fail("采集需要可见渲染窗口。")
		return
	if _scene_path.is_empty() or _output.is_empty() or not _output.is_absolute_path():
		_fail("需要 --scene=res://... 与仓库外的 --output=<绝对目录>。")
		return
	var project_dir: String = ProjectSettings.globalize_path("res://").simplify_path().replace("\\", "/").to_lower().trim_suffix("/")
	var output_dir: String = _output.simplify_path().replace("\\", "/").to_lower().trim_suffix("/")
	if output_dir == project_dir or output_dir.begins_with(project_dir + "/"):
		_fail("输出目录必须位于仓库外。")
		return
	if _stretch not in ["project", "disabled"]:
		_fail("--stretch 只接受 project 或 disabled。")
		return
	DirAccess.make_dir_recursive_absolute(_output)
	if _stretch == "disabled":
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		root.content_scale_size = Vector2i.ZERO
	root.borderless = true
	var packed: PackedScene = load(_scene_path) as PackedScene
	if packed == null:
		_fail("无法加载场景：" + _scene_path)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	for target: Vector2i in _sizes:
		root.size = target
		for unused: int in _wait_frames:
			await process_frame
		_move_pointer_to_blank()
		for unused: int in 2:
			await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var file_name: String = "%s-%s-%dx%d.png" % [_prefix, _stretch, target.x, target.y]
		var path: String = _output.path_join(file_name)
		if image == null or root.size != target or image.get_size() != target or image.save_png(path) != OK:
			_fail("无法保存：" + file_name)
			return
		_records.append(CaptureMetadata.capture_record(root, image, path, {
			"capture_group": "%s-%s" % [_prefix, _stretch],
		}))
		print("CLAUDE_CAPTURE=%s" % path)
	var manifest := FileAccess.open(_output.path_join("%s-%s-manifest.json" % [_prefix, _stretch]), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({
		"scene": _scene_path,
		"stretch": _stretch,
		"engine": Engine.get_version_info().get("string", "unknown"),
		"renderer": RenderingServer.get_current_rendering_method(),
		"project_stretch_mode": ProjectSettings.get_setting("display/window/stretch/mode"),
		"captures": _records,
	}, "  "))
	manifest.close()
	if not CaptureMetadata.write_manifest(root, _output.path_join("capture-metadata.json"), _records, {
		"scene": _scene_path, "stretch": _stretch, "runtime_evidence": _stretch == "project",
	}):
		_fail("无法写入 C8 采集清单。")
		return
	scene.queue_free()
	await process_frame
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _move_pointer_to_blank() -> void:
	var logical_position := Vector2(20, 100)
	Input.warp_mouse(root.get_stretch_transform() * logical_position)
	var motion := InputEventMouseMotion.new()
	motion.position = logical_position
	motion.global_position = logical_position
	root.push_input(motion, true)
