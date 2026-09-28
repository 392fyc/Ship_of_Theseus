extends SceneTree

const CaptureMetadata := preload("res://tests/claude_review/capture_metadata.gd")
const CANDIDATE_PATH := "res://scenes/playground/battlefield_courtyard.tscn"
const CAPTURE_FPS := 24
const CAPTURE_FRAME_COUNT := 192
const LAYOUT_IDS: Array[String] = ["overgrown", "flooded", "passage"]
const PLAYER_START := Vector2i(1, 5)
const MOVE_TARGET := Vector2i(2, 5)

var _output: String = ""
var _layout_id: String = "overgrown"
var _captures: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			_output = arg.trim_prefix("--output=")
		elif arg.begins_with("--layout="):
			_layout_id = arg.trim_prefix("--layout=")
	if DisplayServer.get_name() == "headless":
		_fail("动态捕捉需要 Godot 实际渲染窗口；headless 不生成替代图像。")
		return
	if not LAYOUT_IDS.has(_layout_id):
		_fail("未知场景布局：%s" % _layout_id)
		return
	if _output.is_empty() or not _output.is_absolute_path():
		_fail("请通过 --output= 指定仓库外的绝对输出目录。")
		return
	var output_normalized: String = _output.simplify_path().replace("\\", "/").to_lower()
	var project_normalized: String = ProjectSettings.globalize_path("res://").simplify_path().replace("\\", "/").to_lower()
	if output_normalized == project_normalized or output_normalized.begins_with(project_normalized.trim_suffix("/") + "/"):
		_fail("动态帧输出目录必须位于项目仓库外。")
		return
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(_output)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		_fail("无法创建动态帧输出目录：%s" % error_string(mkdir_error))
		return
	var candidate := load(CANDIDATE_PATH) as PackedScene
	if candidate == null:
		_fail("无法加载庭院候选场景。")
		return
	var scene: Node = candidate.instantiate()
	scene.layout_id = _layout_id
	root.add_child(scene)
	await _frames(5)
	if scene.manager == null or scene.camera == null:
		_fail("候选战斗场景未完成初始化。")
		scene.queue_free()
		quit(1)
		return
	scene.fit_board()
	var base_zoom: float = scene._fit_zoom
	var base_camera_position: Vector2 = scene.camera.position
	var forest_cell: Vector2i = _find_open_forest(scene.manager.grid)
	if forest_cell == Vector2i(-1, -1):
		_fail("场景 %s 没有可悬停的空森林格。" % _layout_id)
		scene.queue_free()
		quit(1)
		return
	var hovered_tree: Node2D = null
	for prop: Node in scene.manager.unit_layer.get_children():
		if prop is Node2D and prop.get_meta("courtyard_cell", Vector2i(-1, -1)) == forest_cell:
			hovered_tree = prop as Node2D
			break
	if hovered_tree == null:
		_fail("森林格缺少对应的树木物体。")
		return
	if not scene.manager._move_range.has(MOVE_TARGET):
		scene.manager.handle_pointer_click(_screen(scene.manager.grid, PLAYER_START))
	await _frames(2)
	var moving_unit: Unit = scene.manager.current_unit
	var move_started: bool = false
	var move_completed: bool = false
	var canopy_fade_observed: bool = false
	var annotations_hidden: bool = false
	var capture_index: int = 0
	while capture_index < CAPTURE_FRAME_COUNT:
		var elapsed: float = float(capture_index) / CAPTURE_FPS
		var progress: float = float(capture_index) / float(CAPTURE_FRAME_COUNT - 1)
		var zoom_wave: float = (1.0 - cos(progress * TAU)) * 0.5
		var zoom_value: float = base_zoom * lerpf(1.0, 1.28, zoom_wave)
		scene.camera.zoom = Vector2.ONE * zoom_value
		scene.camera.position = base_camera_position + Vector2(
			24.0 * sin(progress * TAU), 10.0 * sin(progress * TAU * 0.5))
		scene.camera.force_update_scroll()
		var forest_screen: Vector2 = _screen(scene.manager.grid, forest_cell)
		_move_pointer(forest_screen)
		if not annotations_hidden and elapsed >= 5.0:
			if scene._ranges_shown:
				scene._toggle_ranges()
			if scene._tooltip_enabled:
				scene._toggle_tooltip()
			if scene._grid_shown:
				scene._grid_shown = false
				scene.board_view.grid_visible = false
				scene.board_view.queue_redraw()
			annotations_hidden = true
		if not move_started and elapsed >= 3.0:
			if scene.manager.current_unit != null \
					and scene.manager.current_unit.grid_position == PLAYER_START \
					and scene.manager._move_range.has(MOVE_TARGET):
				scene.manager.handle_pointer_click(_screen(scene.manager.grid, MOVE_TARGET))
				move_started = true
		await process_frame
		await RenderingServer.frame_post_draw
		canopy_fade_observed = canopy_fade_observed or hovered_tree.modulate.a <= 0.20
		if annotations_hidden and (scene._tooltip_enabled or scene._tooltip.visible):
			_fail("提示关闭后仍显示地形卡 (enabled=%s, visible=%s)。" % [
				scene._tooltip_enabled, scene._tooltip.visible,
			])
			scene.queue_free()
			quit(1)
			return
		if move_started and moving_unit.grid_position == MOVE_TARGET and moving_unit.movement_used:
			move_completed = true
		var rendered_frame: Image = root.get_texture().get_image()
		var filename: String = "frame_%06d.png" % capture_index
		var output_path: String = _output.path_join(filename)
		var save_error: Error = CaptureMetadata.save_png(root, rendered_frame, output_path)
		if save_error != OK:
			_fail("保存真实渲染帧 %s 失败：%s" % [filename, error_string(save_error)])
			scene.queue_free()
			quit(1)
			return
		_captures.append(CaptureMetadata.capture_record(root, rendered_frame, output_path, {
			"layout": _layout_id, "frame_index": capture_index, "elapsed_seconds": elapsed,
		}))
		capture_index += 1
	if not move_started or not move_completed:
		_fail("8 秒动态捕捉期间未能完成一次合法单位移动。")
		scene.queue_free()
		quit(1)
		return
	if not canopy_fade_observed:
		_fail("真实渲染期间未观察到目标森林格的树冠淡化。")
		return
	var manifest_path: String = _output.path_join("capture-metadata.json")
	var source_fields: Dictionary = {"layout": _layout_id, "frames": capture_index,
		"fps": CAPTURE_FPS, "duration_seconds": float(capture_index) / CAPTURE_FPS,
		"move_completed": move_completed, "canopy_faded": canopy_fade_observed,
		"annotations_hidden": annotations_hidden}
	if not CaptureMetadata.write_manifest(root, manifest_path, _captures, source_fields):
		_fail("无法写入动态捕捉清单。")
		return
	print("BATTLEFIELD_ENVIRONMENT_CAPTURE layout=%s frames=%d fps=%d duration_seconds=%.2f move_completed=%s canopy_faded=%s output=%s" % [
		_layout_id, capture_index, CAPTURE_FPS, float(capture_index) / CAPTURE_FPS,
		move_completed, canopy_fade_observed, _output,
	])
	scene.queue_free()
	await _frames(2)
	quit(0)


func _find_open_forest(grid: Grid) -> Vector2i:
	for y: int in grid.height:
		for x: int in grid.width:
			var pos := Vector2i(x, y)
			if grid.get_cell(pos).terrain == Cell.Terrain.FOREST \
					and grid.get_unit_at(pos) == null:
				return pos
	return Vector2i(-1, -1)


func _screen(grid: Grid, pos: Vector2i) -> Vector2:
	return root.get_canvas_transform() * grid.grid_to_world(pos)


func _move_pointer(position: Vector2) -> void:
	Input.warp_mouse(position)
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)


func _frames(count: int) -> void:
	for unused: int in count:
		await process_frame


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
