extends SceneTree

const PAINTER_SCENE_PATH := "res://scenes/playground/terrain_painter.tscn"

var _passed: int = 0
var _failed: int = 0
var _editor: Control
var _output_dir: String = ""
var _data_loader: Variant


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % label)
	else:
		_failed += 1
		push_error("%s%s" % [label, ": " + detail if not detail.is_empty() else ""])
		print("[FAIL] %s%s" % [label, ": " + detail if not detail.is_empty() else ""])


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	_output_dir = _argument_value("--output=")
	if not _output_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_output_dir)
	_data_loader = root.get_node("DataLoader")
	var maps_before: Dictionary = _data_loader.maps.duplicate(true)
	var painter_scene := load(PAINTER_SCENE_PATH) as PackedScene
	if painter_scene == null:
		_check("地形工作台场景可加载", false)
		quit(1)
		return
	_editor = painter_scene.instantiate() as Control
	root.add_child(_editor)
	await _frames(4)
	_check("1280×720 工作台显示试战按钮", _editor._battle_button.is_visible_in_tree()
		and _editor._battle_button.text == "开始试战"
		and _editor._battle_button.get_global_rect().has_point(_editor._battle_button.get_global_rect().get_center()))

	# 绘制一格地形，建立非空撤销记录；再保存、改动并加载，确保进入试战的是已加载的数据。
	_editor._replace_map(_editor._make_empty_map(10, 10), "测试空白地图")
	_editor._undo_stack.clear()
	_editor._update_undo_button()
	await _click_control(_editor.terrain_buttons[Cell.Terrain.PEAK] as Control)
	_set_variant(_editor, "mossy")
	var peak_cell := Vector2i(0, 0)
	await _click_at(_editor.cell_to_screen(peak_cell), MOUSE_BUTTON_LEFT)
	var authored_map: Dictionary = _editor.current_map.duplicate(true)
	_check("试战前手工地形已写入并可撤销",
		(_editor.current_map["terrain"] as Array)[peak_cell.y][peak_cell.x] == Cell.Terrain.PEAK
		and _editor._undo_stack.size() == 1)
	await _click_control(_editor.terrain_buttons[Cell.Terrain.FOREST] as Control)
	_set_variant(_editor, "forest")
	var save_path := "user://terrain_painter_battle_flow.json"
	var save_ok: bool = _editor._save_to_path(save_path)
	_editor._clear_map()
	var load_ok: bool = _editor._load_from_path(save_path)
	var loaded_map: Dictionary = _editor.current_map.duplicate(true)
	_check("保存后重新加载恢复同一地图", save_ok and load_ok and loaded_map == authored_map)

	var editor_map_before: Dictionary = _editor.current_map.duplicate(true)
	var undo_before: Array[Dictionary] = _editor._undo_stack.duplicate(true)
	var brush_terrain_before: int = _editor.selected_terrain
	var brush_variant_before: String = _editor.selected_variant
	var board_position_before: Vector2 = _editor.board_view.position
	var board_scale_before: Vector2 = _editor.board_view.scale
	var canvas_before: Transform2D = root.get_canvas_transform()

	await _click_control(_editor._battle_button)
	await _frames(8)
	var first_session: Node2D = _editor._battle_session as Node2D
	_check("开始试战真实点击创建同级战斗会话", is_instance_valid(first_session)
		and first_session.get_parent() == _editor.get_parent() and not _editor.visible)
	_editor._start_battle()
	_check("活动试战期间重复启动不会创建第二个会话",
		_editor._battle_session == first_session and _named_session_count(root) == 1)
	var first_battle: Node2D = first_session.get("battle") as Node2D if is_instance_valid(first_session) else null
	var first_manager: Node = first_session.get("manager") as Node if is_instance_valid(first_session) else null
	var turn_bar: Node = first_battle.get("_turn_order_bar") as Node if is_instance_valid(first_battle) else null
	var dashboard: Node = first_battle.get("_bottom_dashboard") as Node if is_instance_valid(first_battle) else null
	_check("试战显示正式 TacticalScene HUD 与战斗单位",
		is_instance_valid(first_battle) and is_instance_valid(first_manager)
		and is_instance_valid(turn_bar) and turn_bar.is_visible_in_tree()
		and is_instance_valid(dashboard) and dashboard.is_visible_in_tree()
		and (first_manager.get("units") as Array).size() == 2)
	_check("战斗地图不写入 DataLoader 全局地图表", _data_loader.maps == maps_before)
	_check("进入试战完整保留编辑地图、笔刷与撤销栈",
		_editor.current_map == editor_map_before and _editor._undo_stack == undo_before
		and _editor.selected_terrain == brush_terrain_before
		and _editor.selected_variant == brush_variant_before)
	var battle_capture_ok: bool = await _capture("terrain-painter-battle-1280x720.png")
	if DisplayServer.get_name() != "headless":
		_check("保存正式战斗 HUD 截图", battle_capture_ok)
	var first_return_button: Button = _find_button(first_session, "返回编辑") if is_instance_valid(first_session) else null
	_check("战斗画面提供真实可点的返回编辑按钮", is_instance_valid(first_return_button)
		and first_return_button.is_visible_in_tree())
	if is_instance_valid(first_return_button):
		await _click_control(first_return_button)
	await _frames(4)
	_check("点击返回编辑释放会话并恢复工作台", not is_instance_valid(first_session)
		and _editor.visible and _editor.is_processing_input())
	_check("返回后地图、撤销栈、画布位置与镜头变换完整恢复",
		_editor.current_map == editor_map_before and _editor._undo_stack == undo_before
		and _editor.selected_terrain == brush_terrain_before
		and _editor.selected_variant == brush_variant_before
		and _editor.board_view.position == board_position_before
		and _editor.board_view.scale == board_scale_before
		and root.get_canvas_transform() == canvas_before)
	var return_capture_ok: bool = await _capture("terrain-painter-return-1280x720.png")
	if DisplayServer.get_name() != "headless":
		_check("保存返回后的工作台截图", return_capture_ok)

	# 返回后继续通过真实画笔点击编辑，再撤销以确认绘图路径恢复。
	var continue_cell := Vector2i(9, 0)
	var old_cell_terrain: int = _editor.current_grid.get_cell(continue_cell).terrain
	await _click_at(_editor.cell_to_screen(continue_cell), MOUSE_BUTTON_LEFT)
	_check("返回后可继续绘制且沿用已选森林画笔",
		_editor.current_grid.get_cell(continue_cell).terrain == Cell.Terrain.FOREST)
	await _click_control(_editor._undo_button)
	_check("返回后撤销可恢复继续绘制前的地图",
		_editor.current_grid.get_cell(continue_cell).terrain == old_cell_terrain)

	# 第二次真实进入与返回，覆盖重复生命周期和保存加载后的试战入口。
	var second_map_before: Dictionary = _editor.current_map.duplicate(true)
	await _click_control(_editor._battle_button)
	await _frames(8)
	var second_session: Node2D = _editor._battle_session as Node2D
	_check("第二次点击仍能进入正式试战", is_instance_valid(second_session)
		and is_instance_valid(second_session.get("battle")))
	var second_return_button: Button = _find_button(second_session, "返回编辑") if is_instance_valid(second_session) else null
	if is_instance_valid(second_return_button):
		await _click_control(second_return_button)
	await _frames(4)
	_check("重复进出后编辑状态仍保留且无全局地图污染",
		not is_instance_valid(second_session) and _editor.visible
		and _editor.current_map == second_map_before and _data_loader.maps == maps_before)

	# 全深水地图没有可达出生区域；开始试战的真实按钮点击必须拒绝且不改编辑状态。
	var blocked_map: Dictionary = _editor._make_empty_map(10, 10)
	for row: Array in blocked_map["terrain"]:
		row.fill(Cell.Terrain.DEEP_WATER)
	_editor._replace_map(blocked_map, "测试无出生地图")
	var blocked_before: Dictionary = _editor.current_map.duplicate(true)
	var blocked_undo: Array[Dictionary] = _editor._undo_stack.duplicate(true)
	var blocked_brush: int = _editor.selected_terrain
	var blocked_variant: String = _editor.selected_variant
	var blocked_position: Vector2 = _editor.board_view.position
	var blocked_scale: Vector2 = _editor.board_view.scale
	await _click_control(_editor._battle_button)
	await _frames(2)
	_check("不可达地图被中文说明拒绝且编辑状态不变",
		_editor.visible and not is_instance_valid(_editor._battle_session)
		and _editor.current_map == blocked_before and _editor._undo_stack == blocked_undo
		and _editor.selected_terrain == blocked_brush
		and _editor.selected_variant == blocked_variant
		and _editor.board_view.position == blocked_position
		and _editor.board_view.scale == blocked_scale
		and _editor._status_label.text.begins_with("无法开始试战："))

	# 退出工作台时仍有活动会话，也必须同步清理战斗节点。
	_editor._replace_map(loaded_map, "恢复可试战地图")
	await _click_control(_editor._battle_button)
	await _frames(8)
	var exiting_session: Node2D = _editor._battle_session as Node2D
	_editor.queue_free()
	await _frames(4)
	_check("退出编辑器会清理仍活动的试战会话", not is_instance_valid(exiting_session)
		and _named_session_count(root) == 0 and _data_loader.maps == maps_before)
	var user_data_dir: String = OS.get_user_data_dir()
	DirAccess.remove_absolute(user_data_dir.path_join("terrain_painter_battle_flow.json"))
	_capture_report()
	print("TERRAIN_PAINTER_BATTLE_FLOW_RESULT " + JSON.stringify({"passed": _passed, "failed": _failed}))
	quit(1 if _failed > 0 else 0)


func _set_variant(editor: Control, variant: String) -> void:
	var picker: OptionButton = editor._variant_picker
	for index: int in picker.item_count:
		if str(picker.get_item_metadata(index)) == variant:
			picker.select(index)
			editor._on_variant_selected(index)
			return
	_check("外观选项包含 %s" % variant, false)


func _find_button(parent: Node, label: String) -> Button:
	for node: Node in parent.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == label and button.is_visible_in_tree():
			return button
	return null


func _named_session_count(parent: Node) -> int:
	var count := 0
	for child: Node in parent.get_children():
		if is_instance_valid(child) and child.get_script() != null \
				and str(child.get_script().resource_path) == "res://scripts/tactical/terrain_battle_session.gd":
			count += 1
	return count


func _capture(file_name: String) -> bool:
	if DisplayServer.get_name() == "headless" or _output_dir.is_empty():
		return false
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image.get_size() != Vector2i(1280, 720):
		return false
	return image.save_png(_output_dir.path_join(file_name)) == OK


func _capture_report() -> void:
	if _output_dir.is_empty():
		return
	var file := FileAccess.open(_output_dir.path_join("terrain-painter-battle-flow.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"resolution": [1280, 720], "passed": _passed, "failed": _failed,
			"battle_capture": "terrain-painter-battle-1280x720.png",
			"return_capture": "terrain-painter-return-1280x720.png"}, "  "))
		file.close()


func _argument_value(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


func _click_control(control: Control) -> void:
	await _click_at(control.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)


func _click_at(position: Vector2, button_index: MouseButton) -> void:
	var down := InputEventMouseButton.new()
	down.position = position
	down.button_index = button_index
	down.pressed = true
	root.push_input(down)
	await process_frame
	var up := InputEventMouseButton.new()
	up.position = position
	up.button_index = button_index
	up.pressed = false
	root.push_input(up)
	await process_frame


func _frames(count: int) -> void:
	for _index: int in count:
		await process_frame
