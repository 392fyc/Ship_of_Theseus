extends SceneTree

const CaptureMetadata := preload("res://tests/claude_review/capture_metadata.gd")

## Claude 审查采集：默认战斗中的移动范围、技能悬停提示、技能范围与伤害预测浮窗。
## 通过真实输入路径推进：向根视口推送鼠标移动事件，由场景的输入处理调用悬停逻辑；
## 技能选择调用宿主既有的 request_skill_selection。保留项目拉伸；输出只写入仓库外目录。
## 运行：Godot_console.exe --path <project> --rendering-method <与发行一致的渲染器> \
##   --script res://tests/claude_review/capture_battle_overlays.gd -- --output=<仓库外绝对目录>

var _output: String = ""
var _records: Array[Dictionary] = []
var _failed: bool = false
var _pointer_position: Vector2 = Vector2(20, 100)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			_output = arg.trim_prefix("--output=")
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
	var packed: PackedScene = load("res://scenes/tactical/TacticalScene.tscn") as PackedScene
	if packed == null:
		push_error("无法加载 TacticalScene")
		quit(1)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	await _frames(60)
	await _shot_sizes("01-move-range")

	var manager: Object = scene.get("tactical_manager")
	var dashboard: Object = scene.get("_bottom_dashboard")
	if manager == null or dashboard == null:
		_fail_now("场景未创建战斗管理器或底栏")
		return
	var shelf: Control = dashboard.get_composition().get_node("BottomRow/SkillShelf") as Control
	var buttons: Array[Button] = []
	for node: Node in shelf.find_children("*", "Button", true, false):
		if (node as Button).is_visible_in_tree():
			buttons.append(node as Button)
	if buttons.size() < 2:
		_fail_now("技能栏按钮不足")
		return
	_move_pointer(buttons[1].get_global_rect().get_center())
	await _frames(90)
	await _shot_sizes("02-skill-tooltip")

	# 先按真实点击路径把当前单位移到最近敌人的相邻格（剑圣攻击技能都是近战），再结束移动进入行动阶段。
	var actor: Node = manager._get_dashboard_unit()
	var target: Node = _nearest_enemy(manager, actor)
	var moved: bool = false
	if actor != null and target != null:
		var start_cell: Vector2i = actor.grid_position
		for offset: Vector2i in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			var cell: Vector2i = target.grid_position + offset
			if not manager.grid.is_valid(cell):
				continue
			await _click(_cell_screen(manager, actor, cell))
			await _frames(90)
			if actor.grid_position != start_cell:
				moved = true
				break
	manager.request_end_move()
	await _frames(10)
	var chosen: String = ""
	for entry: Dictionary in manager.get_dashboard_data().get("skills", []):
		if bool(entry.get("available", false)) and str(entry.get("action_cost", "")) == "standard":
			chosen = str(entry.get("skill_id", ""))
			break
	if chosen.is_empty():
		_fail_now("没有可用的标准行动技能")
		return
	manager.request_skill_selection(chosen)
	_move_pointer(Vector2(640, 200))
	await _frames(20)
	await _shot_sizes("03-skill-range")

	var forecast_found: bool = false
	var candidates: Array = [target] if target != null else []
	for unit: Node in manager.units:
		if str(unit.get("faction")) == "enemy" and unit != target:
			candidates.append(unit)
	for unit: Node in candidates:
		_move_pointer(_cell_screen(manager, actor, unit.grid_position))
		await _frames(12)
		var forecaster: CanvasItem = scene.get("_damage_forecaster") as CanvasItem
		if forecaster != null and forecaster.visible:
			await _shot_sizes("04-forecast")
			forecast_found = true
			break
	if not forecast_found:
		push_warning("没有敌人进入所选技能的预测范围；未生成伤害预测截图。")

	var file := FileAccess.open(_output.path_join("battle-overlays-manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"scene": "res://scenes/tactical/TacticalScene.tscn",
		"selected_skill": chosen,
		"moved_next_to_enemy": moved,
		"forecast_captured": forecast_found,
		"renderer": RenderingServer.get_current_rendering_method(),
		"content_scale_mode": int(root.content_scale_mode),
		"content_scale_size": [root.content_scale_size.x, root.content_scale_size.y],
		"captures": _records,
	}, "  "))
	file.close()
	if not CaptureMetadata.write_manifest(root, _output.path_join("capture-metadata.json"), _records, {
		"scene": "res://scenes/tactical/TacticalScene.tscn", "selected_skill": chosen,
		"moved_next_to_enemy": moved, "forecast_captured": forecast_found,
	}):
		_fail_now("无法写入三档整屏采集清单")
		return
	scene.queue_free()
	await process_frame
	quit(1 if _failed else 0)


func _nearest_enemy(manager: Object, actor: Node) -> Node:
	var best: Node = null
	var best_d: int = 1 << 30
	for unit: Node in manager.units:
		if actor == null or str(unit.get("faction")) != "enemy":
			continue
		var d: int = absi(unit.grid_position.x - actor.grid_position.x) + absi(unit.grid_position.y - actor.grid_position.y)
		if d < best_d:
			best_d = d
			best = unit
	return best


func _cell_screen(manager: Object, reference: Node, cell: Vector2i) -> Vector2:
	# 以参考单位的画布位置为锚，按网格世界坐标差换算目标格的屏幕位置。
	var ref_world: Vector2 = manager.grid.grid_to_world(reference.grid_position)
	var ref_screen: Vector2 = (reference as CanvasItem).get_global_transform_with_canvas().origin
	var scale: Vector2 = (reference as CanvasItem).get_global_transform_with_canvas().get_scale()
	return ref_screen + (manager.grid.grid_to_world(cell) - ref_world) * scale


func _click(point: Vector2) -> void:
	_move_pointer(point)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		root.push_input(event, true)
		await process_frame


func _move_pointer(point: Vector2) -> void:
	_pointer_position = point
	Input.warp_mouse(root.get_stretch_transform() * point)
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event, true)


func _frames(count: int) -> void:
	for unused: int in count:
		await process_frame


func _shot_sizes(name: String) -> void:
	var original_size: Vector2i = root.size
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		root.size = dimensions
		await _frames(5)
		_move_pointer(_pointer_position)
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
		print("CLAUDE_OVERLAY_CAPTURE=%s" % path)
	root.size = original_size
	await _frames(3)


func _fail_now(message: String) -> void:
	push_error(message)
	quit(1)
