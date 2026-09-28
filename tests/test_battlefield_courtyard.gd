extends SceneTree

const CaptureMetadata := preload("res://tests/claude_review/capture_metadata.gd")

const CANDIDATE_PATH := "res://scenes/playground/battlefield_courtyard.tscn"
const LAYOUT_IDS: Array[String] = ["overgrown", "flooded", "passage"]
const PLAYER_START := Vector2i(1, 5)
const MOVE_TARGET := Vector2i(2, 5)
const HudTop := 100.0
const HudBottom := 510.0

var _failed: int = 0
var _passed: int = 0
var _captures: Array[String] = []
var _output: String = ""
var _data_loader: Variant


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, success: bool) -> void:
	if success:
		_passed += 1
	else:
		_failed += 1
		push_error(label)
	print("[%s] %s" % ["PASS" if success else "FAIL", label])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			_output = arg.trim_prefix("--output=")
	if not _output.is_empty():
		DirAccess.make_dir_recursive_absolute(_output)
	_data_loader = root.get_node("DataLoader")
	var before_maps: Dictionary = _data_loader.maps.duplicate(true)
	var candidate := load(CANDIDATE_PATH) as PackedScene
	if candidate == null:
		_check("候选场景可加载", false)
		quit(1)
		return
	var scene := candidate.instantiate()
	root.add_child(scene)
	await _frames(5)
	_check("默认场景为荒草中庭", scene.current_layout_id == "overgrown")
	var previous_battle: Node = null
	for layout_key: String in LAYOUT_IDS:
		previous_battle = scene.battle
		await scene.select_layout(layout_key)
		await _frames(3)
		var layout_data: Dictionary = scene.current_layout_data
		var manager: Object = scene.manager
		var grid: Grid = manager.grid
		_check("%s 已选择且标题说明来自当前地图" % layout_key,
			scene.current_layout_id == layout_key
			and scene._title.text == str(layout_data["name"])
			and scene._description.text == str(layout_data["description"])
			and scene._layout_buttons[layout_key].button_pressed)
		_check("%s 切图保留范围显示状态" % layout_key,
			manager.highlight_layer.visible == scene._ranges_shown)
		_check("%s 切换释放旧战斗且只保留一个战斗与棋盘" % layout_key,
			(not is_instance_valid(previous_battle))
			and _named_child_count(scene, "TacticalScene") == 1
			and _named_child_count(manager, "CourtyardBoardView") == 1)
		_check("%s 数据表只临时注册当前地图" % layout_key,
			_data_loader_matches_active_map(before_maps, layout_data))
		_check("%s 为 8×8 棋盘，基础剑士无印记" % layout_key,
			grid.width == 8 and grid.height == 8
			and manager.current_unit != null
			and manager.current_unit.unit_id == "myrmidon"
			and manager.current_unit._qi_max > 0
			and manager.current_unit._mark_max == 0)
		_check("%s 四名单位都位于可通行地块" % layout_key,
			manager.units.size() == 4
			and manager.units.all(func(unit: Unit) -> bool:
				return grid.get_cell(unit.grid_position).is_passable()))

		var empty_grid := Grid.new()
		empty_grid.initialize(layout_data)
		var all_reachable: Dictionary = Pathfinding.get_move_range(empty_grid, PLAYER_START, 200, "player")
		var passable_count: int = 0
		var blocked_count: int = 0
		for y: int in empty_grid.height:
			for x: int in empty_grid.width:
				var cell: Cell = empty_grid.get_cell(Vector2i(x, y))
				if cell.is_passable():
					passable_count += 1
				else:
					blocked_count += 1
		_check("%s 所有可通行地块从玩家入口连通" % layout_key,
			all_reachable.size() == passable_count and passable_count + blocked_count == 64)
		_check("%s 不可通行地块不进入路径与实际移动范围" % layout_key,
			manager._move_range.keys().all(func(pos: Vector2i) -> bool:
				return grid.get_cell(pos).is_passable())
			and _all_blocked_excluded(empty_grid, all_reachable))

		var hero: Unit = manager.current_unit
		var initial_position: Vector2i = hero.grid_position
		var target_cell: Cell = grid.get_cell(MOVE_TARGET)
		var blocked_pos: Vector2i = _find_terrain(grid, Cell.Terrain.WALL, true)
		_check("%s 选格路径使用 Cell 移动消耗" % layout_key,
			manager._move_range.has(MOVE_TARGET)
			and manager._move_range[MOVE_TARGET] == hero.stats.mov - target_cell.get_move_cost())
		manager.handle_pointer_click(_screen(grid, blocked_pos))
		await _frames(2)
		_check("%s 点击残垣不移动且不消费移动资源" % layout_key,
			hero.grid_position == initial_position and not hero.movement_used)

		var forest_pos: Vector2i = _find_terrain(grid, Cell.Terrain.FOREST, true)
		if forest_pos != Vector2i(-1, -1):
			var forest: Cell = grid.get_cell(forest_pos)
			await _hover_cell(scene, grid, forest_pos)
			_check("%s 森林提示采用正式类型与定性闪避说明" % layout_key,
				scene._tooltip.visible
				and scene._tooltip_text.text.contains("森林")
				and scene._tooltip_text.text.contains(str(forest.get_move_cost()))
				and scene._tooltip_text.text.contains("提高闪避")
				and not scene._tooltip_text.text.contains("闪避 +"))
			var forest_tree: Node2D = _tree_at_cell(manager, forest_pos)
			_check("%s 悬停森林格时树冠实际淡化" % layout_key,
				forest_tree != null and forest_tree.modulate.a <= 0.20)
		else:
			_check("%s 地图包含可悬停森林地块" % layout_key, false)

		var plain_pos: Vector2i = _find_terrain(grid, Cell.Terrain.PLAIN, true)
		await _hover_cell(scene, grid, plain_pos)
		var plain: Cell = grid.get_cell(plain_pos)
		_check("%s 平原提示读取正式地形与 Cell 移动消耗" % layout_key,
			scene._tooltip.visible
			and scene._tooltip_text.text == "平原 · 移动消耗 %d" % plain.get_move_cost())
		var ranges_were_shown: bool = scene._ranges_shown
		if not ranges_were_shown:
			scene._toggle_ranges()
		await _frames(3)
		var forest_in_range_count: int = 0
		var range_visible: bool = true
		for cell_pos: Vector2i in manager._move_range:
			if grid.get_cell(cell_pos).terrain == Cell.Terrain.FOREST:
				var tree: Node2D = _tree_at_cell(manager, cell_pos)
				forest_in_range_count += 1
				range_visible = range_visible and tree != null and tree.modulate.a <= 0.33
		if forest_in_range_count > 0:
			_check("%s 行动范围内的森林树冠不盖住选格标记" % layout_key, range_visible)
		if not ranges_were_shown:
			scene._toggle_ranges()
		var wall_pos: Vector2i = _find_terrain(grid, Cell.Terrain.WALL, true)
		await _hover_cell(scene, grid, wall_pos)
		_check("%s 残垣不通行但不阻挡攻击线" % layout_key,
			scene._tooltip.visible
			and scene._tooltip_text.text.contains("墙")
			and scene._tooltip_text.text.contains("不可通行")
			and scene._tooltip_text.text.contains("不阻挡攻击线"))

		if layout_key == "flooded":
			var shallow_pos: Vector2i = _find_terrain(grid, Cell.Terrain.SHALLOW_WATER, true)
			var deep_pos: Vector2i = _find_terrain(grid, Cell.Terrain.DEEP_WATER, true)
			var shallow: Cell = grid.get_cell(shallow_pos)
			var deep: Cell = grid.get_cell(deep_pos)
			await _hover_cell(scene, grid, shallow_pos)
			var shallow_tip: String = scene._tooltip_text.text
			var shallow_valid: bool = scene._tooltip.visible and shallow.is_passable() \
				and shallow_tip.contains("浅水") \
				and shallow_tip.contains(str(shallow.get_move_cost()))
			await _hover_cell(scene, grid, deep_pos)
			var deep_tip: String = scene._tooltip_text.text
			_check("积水花园区分可通行浅水和不可通行深水", shallow_valid
				and scene._tooltip.visible and not deep.is_passable()
				and deep.get_move_cost() >= Cell.IMPASSABLE
				and deep_tip.contains("深水") and deep_tip.contains("不可通行")
				and deep_tip.contains("不阻挡攻击线"))

		for size_value: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
			root.size = size_value
			await _frames(4)
			scene.fit_board()
			await _frames(2)
			var logical_size: Vector2 = root.get_visible_rect().size
			var factor: float = logical_size.y / 720.0
			var all_clear: bool = true
			for y: int in grid.height:
				for x: int in grid.width:
					var center: Vector2 = _screen(grid, Vector2i(x, y))
					all_clear = all_clear and center.x >= 48.0 * factor \
						and center.x <= logical_size.x - 48.0 * factor \
						and center.y - 22.0 * factor > HudTop * factor \
						and center.y + 22.0 * factor < HudBottom * factor
			_check("%s %d 全部格子留在棋盘显示区并避开 HUD" % [layout_key, size_value.x], all_clear)
			_check("%s %d 屏幕选格往返一致" % [layout_key, size_value.x],
				grid.world_to_grid(root.get_canvas_transform().affine_inverse()
					* _screen(grid, Vector2i(6, 5))) == Vector2i(6, 5))
			_move_pointer(Vector2(20, 200) * factor)
			await _capture("%s-courtyard-%d" % [layout_key, size_value.x])
			_move_pointer(_screen(grid, MOVE_TARGET))
			await _frames(3)
			_check("%s %d 鼠标悬停产生正式寻路预览" % [layout_key, size_value.x], manager._path_preview.size() > 1)
			await _capture("%s-path-%d" % [layout_key, size_value.x])
			var composition: Control = scene.battle._bottom_dashboard.get_composition()
			_check("%s %d 保留原 HUD 且隐藏印记面板" % [layout_key, size_value.x],
				not composition.get_marks_panel().visible)

		if layout_key == "overgrown":
			scene.fit_board()
			await _frames(2)
			var test_hover: Vector2i = _find_terrain(grid, Cell.Terrain.PLAIN, true)
			await _hover_cell(scene, grid, test_hover)
			var default_rect: Rect2 = scene._tooltip.get_global_rect()
			var default_board_rect: Rect2 = scene._board_screen_rect()
			_check("居中棋盘时提示框使用左侧空白", scene._tooltip.visible
				and default_rect.end.x <= default_board_rect.position.x)
			var zoom_before: Vector2 = scene.camera.zoom
			var camera_before: Vector2 = scene.camera.position
			_pan(scene, Vector2(-200, 0))
			await _frames(3)
			_check("镜头缩放后拖动按屏幕像素跟手", scene.camera.position.is_equal_approx(
				camera_before - Vector2(-200, 0) / zoom_before))
			await _hover_cell(scene, grid, test_hover)
			var panned_rect: Rect2 = scene._tooltip.get_global_rect()
			var panned_board_rect: Rect2 = scene._board_screen_rect()
			_check("平移棋盘后提示框改放另一侧且不压棋盘", scene._tooltip.visible
				and panned_rect.position.x >= panned_board_rect.end.x)
			scene.fit_board()
			await _frames(3)
			scene.camera.zoom = Vector2.ONE * 3.0
			scene.camera.force_update_scroll()
			await _frames(3)
			await _hover_cell(scene, grid, Vector2i(4, 4))
			_check("棋盘放大后左右空间不足时隐藏提示框", not scene._tooltip.visible)
			scene.fit_board()
			await _frames(3)
			await _test_camera_zoom(scene, grid)
			var move_range_before_toggle: Dictionary = manager._move_range.duplicate()
			scene._toggle_ranges()
			_check("范围按钮只隐藏高亮且不改变移动范围", not manager.highlight_layer.visible
				and manager._move_range == move_range_before_toggle)
			scene._toggle_tooltip()
			_check("提示按钮可隐藏地形卡而不切换地图", not scene._tooltip_enabled
				and scene.current_layout_id == layout_key)
			await _hover_cell(scene, grid, test_hover)
			_check("关闭提示后持续悬停仍不显示地形卡", not scene._tooltip.visible)
			scene._toggle_tooltip()
			await _hover_cell(scene, grid, test_hover)
			_check("重新开启提示后悬停可显示地形卡", scene._tooltip_enabled
				and scene._tooltip.visible)

		# 通过正式点击入口和 GameAction 执行一次真实移动。
		scene.fit_board()
		await _frames(2)
		manager.handle_pointer_click(_screen(grid, MOVE_TARGET))
		await create_timer(0.7).timeout
		_check("%s 实际移动到选格并更新占格" % layout_key,
			hero.grid_position == MOVE_TARGET
			and grid.get_unit_at(MOVE_TARGET) == hero
			and grid.get_unit_at(initial_position) == null)
		_check("%s 移动行动消费移动资源" % layout_key,
			hero.movement_used)
		await _capture("%s-moved-1280" % layout_key)
		previous_battle = scene.battle
		await scene.select_layout(layout_key)
		await _frames(2)
		_check("%s 重开保留场景并重置单位站位" % layout_key,
			scene.current_layout_id == layout_key
			and scene.manager.current_unit.grid_position == PLAYER_START
			and not scene.manager.current_unit.movement_used
			and not is_instance_valid(previous_battle))
		_check("%s 重开后地图注册仍无泄漏" % layout_key,
			_data_loader_matches_active_map(before_maps, scene.current_layout_data))

	scene.queue_free()
	await _frames(3)
	_check("退出候选恢复全部 DataLoader 地图注册", _data_loader.maps == before_maps)
	var result: Dictionary = {
		"passed": _passed,
		"failed": _failed,
		"captures": _captures,
		"engine": Engine.get_version_info().string,
	}
	if not _output.is_empty():
		var file := FileAccess.open(_output.path_join("verification.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(result, "  "))
	print("BATTLEFIELD_COURTYARD_RESULT " + JSON.stringify(result))
	quit(0 if _failed == 0 else 1)


func _data_loader_matches_active_map(before_maps: Dictionary, layout_data: Dictionary) -> bool:
	var expected: Dictionary = before_maps.duplicate(true)
	expected[str(layout_data["id"])] = layout_data
	return _data_loader.maps == expected


func _all_blocked_excluded(grid: Grid, reachable: Dictionary) -> bool:
	for y: int in grid.height:
		for x: int in grid.width:
			var pos := Vector2i(x, y)
			if not grid.get_cell(pos).is_passable() and reachable.has(pos):
				return false
	return true


func _named_child_count(node: Node, child_name: String) -> int:
	var count: int = 0
	for child: Node in node.get_children():
		if child.name == child_name:
			count += 1
	return count


func _find_terrain(grid: Grid, terrain_id: int, empty_only: bool) -> Vector2i:
	for y: int in grid.height:
		for x: int in grid.width:
			var pos := Vector2i(x, y)
			if grid.get_cell(pos).terrain == terrain_id \
					and (not empty_only or grid.get_unit_at(pos) == null):
				return pos
	return Vector2i(-1, -1)


func _test_camera_zoom(scene: Node, grid: Grid) -> void:
	root.size = Vector2i(1280, 720)
	await _frames(3)
	scene.fit_board()
	await _frames(2)
	var fit_zoom: float = scene._fit_zoom
	var fit_position: Vector2 = scene.camera.position
	var anchor_screen: Vector2 = _screen(grid, Vector2i(4, 5))
	_move_pointer(anchor_screen)
	await _frames(2)
	var anchor_world_before: Vector2 = root.get_canvas_transform().affine_inverse() * anchor_screen
	_send_wheel(scene, anchor_screen, MOUSE_BUTTON_WHEEL_UP)
	await _frames(2)
	var anchor_world_after: Vector2 = root.get_canvas_transform().affine_inverse() * anchor_screen
	_check("滚轮缩放以鼠标世界点为锚", anchor_world_before.distance_to(anchor_world_after) < 0.1)
	_check("滚轮缩放位于 fit_zoom 的 0.75 至 1.45 倍", scene.camera.zoom.x >= fit_zoom * 0.75
		and scene.camera.zoom.x <= fit_zoom * 1.45)
	for unused: int in 24:
		_send_wheel(scene, anchor_screen, MOUSE_BUTTON_WHEEL_UP)
	_check("滚轮放大受 fit_zoom 上限约束", is_equal_approx(scene.camera.zoom.x, fit_zoom * 1.45))
	scene.fit_board()
	await _frames(2)
	_check("居中恢复 fit_zoom 和默认位置", is_equal_approx(scene.camera.zoom.x, fit_zoom)
		and scene.camera.position.is_equal_approx(fit_position))
	for unused: int in 24:
		_send_wheel(scene, anchor_screen, MOUSE_BUTTON_WHEEL_DOWN)
	_check("滚轮缩小受 fit_zoom 下限约束", is_equal_approx(scene.camera.zoom.x, fit_zoom * 0.75))
	scene.fit_board()
	await _frames(2)
	var ui_button: Button = scene._layout_buttons["flooded"]
	var ui_point: Vector2 = ui_button.get_global_rect().get_center()
	_move_pointer(ui_point)
	await _frames(2)
	var ui_zoom_before: float = scene.camera.zoom.x
	_send_wheel(scene, ui_point, MOUSE_BUTTON_WHEEL_UP)
	await _frames(2)
	_check("指针位于场景按钮时滚轮不缩放", is_equal_approx(scene.camera.zoom.x, ui_zoom_before))
	scene.fit_board()
	await _frames(2)


func _send_wheel(scene: Node, position: Vector2, button_index: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = true
	event.position = position
	scene._unhandled_input(event)


func _screen(grid: Grid, pos: Vector2i) -> Vector2:
	return root.get_canvas_transform() * grid.grid_to_world(pos)


func _hover_cell(scene: Node, grid: Grid, pos: Vector2i) -> void:
	_move_pointer(_screen(grid, pos))
	await _frames(3)
	scene._process(0.0)


func _move_pointer(pos: Vector2) -> void:
	Input.warp_mouse(root.get_stretch_transform() * pos)
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	root.push_input(motion, true)


func _pan(scene: Node, delta: Vector2) -> void:
	var start_position := Vector2(600, 140)
	var pan_start := InputEventMouseButton.new()
	pan_start.button_index = MOUSE_BUTTON_MIDDLE
	pan_start.pressed = true
	pan_start.position = start_position
	scene.battle._input(pan_start)
	var motion := InputEventMouseMotion.new()
	motion.position = start_position + delta
	motion.relative = delta
	scene.battle._input(motion)
	var pan_end := InputEventMouseButton.new()
	pan_end.button_index = MOUSE_BUTTON_MIDDLE
	pan_end.pressed = false
	pan_end.position = start_position + delta
	scene.battle._input(pan_end)


func _tree_at_cell(manager: Object, cell: Vector2i) -> Node2D:
	for child: Node in manager.unit_layer.get_children():
		if child is Node2D and child.get_meta("courtyard_cell", Vector2i(-1, -1)) == cell:
			return child as Node2D
	return null


func _frames(count: int) -> void:
	for unused: int in count:
		await process_frame


func _capture(file_name: String) -> void:
	if _output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _frames(3)
	await RenderingServer.frame_post_draw
	var file_path: String = _output.path_join(file_name + ".png")
	var error: Error = CaptureMetadata.save_png(root, root.get_texture().get_image(), file_path)
	_check("保存 " + file_name, error == OK)
	if error == OK:
		_captures.append(file_name + ".png")
