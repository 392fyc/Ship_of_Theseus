extends SceneTree

const CaptureMetadata := preload("res://tests/claude_review/capture_metadata.gd")

## Claude 审查采集：RunScene 的非战斗界面——选门、备战（运输队、商店）、事件选项、事件结果与结束面板。
## 按项目真实拉伸设置运行；通过宿主既有回调推进流程，不改运行逻辑；输出只写入仓库外目录。
## 运行：Godot_console.exe --path <project> --rendering-method <与发行一致的渲染器> \
##   --script res://tests/claude_review/capture_run_flow_ui.gd -- --output=<仓库外绝对目录> [--event=event_blessing_altar]

var _output: String = ""
var _event_id: String = "event_blessing_altar"
var _records: Array[Dictionary] = []
var _failed: bool = false
var _pointer_position: Vector2 = Vector2(20, 100)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			_output = arg.trim_prefix("--output=")
		elif arg.begins_with("--event="):
			_event_id = arg.trim_prefix("--event=")
	if DisplayServer.get_name().to_lower() == "headless" or _output.is_empty() or not _output.is_absolute_path():
		push_error("需要可见窗口与仓库外 --output=<绝对目录>。")
		quit(1)
		return
	var project_dir: String = ProjectSettings.globalize_path("res://").simplify_path().replace("\\", "/").to_lower().trim_suffix("/")
	var output_dir: String = _output.simplify_path().replace("\\", "/").to_lower().trim_suffix("/")
	if output_dir == project_dir or output_dir.begins_with(project_dir + "/"):
		push_error("输出目录必须位于仓库外。")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_output)
	root.borderless = true
	root.size = Vector2i(1280, 720)
	var packed: PackedScene = load("res://scenes/roguelite/RunScene.tscn") as PackedScene
	if packed == null:
		push_error("无法加载 RunScene")
		quit(1)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	await _frames(60)
	await _shot_sizes("01-battle")
	for step: Array in [
		["_on_battle_ended", ["victory"], "02-door-select"],
		["_on_door_chosen", [0], "03-prep"],
		["_clear_prep", [], ""],
		["_enter_event", [{"event_id": _event_id}], "04-event-choices"],
		["_on_event_choice", [0], "05-event-outcome"],
		["_clear_event_panel", [], ""],
		["_show_end_panel", [true], "06-end-panel"],
	]:
		if not scene.has_method(step[0]):
			push_error("RunScene 缺少回调：" + str(step[0]))
			_failed = true
			break
		scene.callv(step[0], step[1])
		if not str(step[2]).is_empty():
			await _frames(30)
			await _shot_sizes(step[2])
	var file := FileAccess.open(_output.path_join("run-flow-manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"scene": "res://scenes/roguelite/RunScene.tscn",
		"event_id": _event_id,
		"renderer": RenderingServer.get_current_rendering_method(),
		"content_scale_mode": int(root.content_scale_mode),
		"content_scale_size": [root.content_scale_size.x, root.content_scale_size.y],
		"captures": _records,
	}, "  "))
	file.close()
	if not CaptureMetadata.write_manifest(root, _output.path_join("capture-metadata.json"), _records, {
		"scene": "res://scenes/roguelite/RunScene.tscn", "event_id": _event_id,
	}):
		push_error("无法写入三档整屏采集清单")
		_failed = true
	scene.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _frames(count: int) -> void:
	for unused: int in count:
		await process_frame


func _shot_sizes(name: String) -> void:
	var original_size: Vector2i = root.size
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		root.size = dimensions
		await _frames(5)
		_move_pointer(Vector2(20, 100))
		await _frames(2)
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var file_name: String = "%s-%dx%d.png" % [name, dimensions.x, dimensions.y]
		var path: String = _output.path_join(file_name)
		if root.size != dimensions or image == null or image.get_size() != dimensions or image.save_png(path) != OK:
			push_error("无法保存尺寸为 %s 的截图：%s" % [dimensions, name])
			_failed = true
			continue
		var record: Dictionary = CaptureMetadata.capture_record(root, image, path)
		record["size"] = [image.get_width(), image.get_height()]
		_records.append(record)
		print("CLAUDE_RUN_FLOW_CAPTURE=%s" % path)
	root.size = original_size
	await _frames(3)


func _move_pointer(point: Vector2) -> void:
	_pointer_position = point
	Input.warp_mouse(root.get_stretch_transform() * point)
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event, true)
