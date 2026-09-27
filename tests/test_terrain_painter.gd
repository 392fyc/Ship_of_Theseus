extends SceneTree

const PainterScene := preload("res://scenes/playground/terrain_painter.tscn")
const TerrainCatalog := preload("res://scripts/ui/terrain/terrain_catalog.gd")
const EXAMPLES_PATH := "res://assets/prototype/battlefield_courtyard/terrain_examples.json"

var _passed: int = 0
var _failed: int = 0
var _editor: Control
var _output_dir: String = ""
var _workbench_capture_saved: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % label)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [label, ": " + detail if not detail.is_empty() else ""])


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	_output_dir = _argument_value("--output=")
	_editor = PainterScene.instantiate() as Control
	root.add_child(_editor)
	await _frames(4)
	_check("工作台启动为 10×10 且使用外观预览数据",
		_editor.current_grid.width == 10 and _editor.current_grid.height == 10
		and _editor.current_map["transition_preview"] == true
		and _editor.current_map["environment"] == "terrain_workshop")
	for sample_index: int in 3:
		_editor._sample_picker.select(sample_index)
		_editor._load_selected_sample()
		await _frames(2)
		_check("示例选项 %d 可载入并通过同一校验器" % (sample_index + 1),
			_editor.current_grid.width >= 10 and _editor.current_grid.width <= 25
			and _editor.current_grid.height == _editor.current_grid.width)
		if sample_index == 1:
			_check("湿地示例名称按 JSON 展示", _editor._sample_picker.get_item_text(1) == "湿地山麓")
			_workbench_capture_saved = await _capture_workbench()
	_editor._replace_map(_editor._make_empty_map(10, 10), "测试起始空图")
	_editor._undo_stack.clear()
	_editor._update_undo_button()
	for terrain_id: int in range(9):
		var palette_button: Control = _editor.terrain_buttons[terrain_id]
		await _ensure_control_visible(palette_button)
		await _click_control(palette_button)
		_check("1280×720 下地形按钮 %s 可真实点击" % _editor.TERRAIN_LABELS[terrain_id],
			_editor.selected_terrain == terrain_id, "实际选择=%d" % _editor.selected_terrain)

	var valid_terrain := _terrain_allowed_with_plain()
	var paint_cell := Vector2i(4, 4)
	await _click_control(_editor.terrain_buttons[valid_terrain] as Control)
	_check("真实点击调色板会选中目标地形", _editor.selected_terrain == valid_terrain)
	await _click_at(_editor.cell_to_screen(paint_cell), MOUSE_BUTTON_LEFT)
	_check("点击地形按钮并点击格子会写入选中地形",
		_editor.current_grid.get_cell(paint_cell).terrain == valid_terrain)
	await _click_at(_editor.cell_to_screen(paint_cell), MOUSE_BUTTON_RIGHT)
	_check("右键取样会选择格子地形", _editor.selected_terrain == valid_terrain)
	await _click_control(_editor._undo_button)
	_check("点击撤销按钮恢复绘制前的地形",
		_editor.current_grid.get_cell(paint_cell).terrain == Cell.Terrain.PLAIN)

	await _click_control(_editor.terrain_buttons[Cell.Terrain.PLAIN] as Control)
	_editor._variant_picker.select(1)
	_editor._on_variant_selected(1)
	var drag_start := Vector2i(1, 1)
	var drag_end := Vector2i(4, 1)
	await _drag_cells(_editor, drag_start, drag_end)
	var paved_count: int = (_editor.current_map["paving"] as Array).size()
	_check("拖动绘制会连续铺过中间格子", paved_count == 4, "实际铺石格数=%d" % paved_count)
	await _click_control(_editor._undo_button)
	_check("一次拖动作为一步撤销", (_editor.current_map["paving"] as Array).is_empty())

	var pave_cell := Vector2i(2, 2)
	await _click_at(_editor.cell_to_screen(pave_cell), MOUSE_BUTTON_LEFT)
	await _paint_variant_cell(Cell.Terrain.WALL, "ruined", Vector2i(5, 5))
	await _paint_variant_cell(Cell.Terrain.PEAK, "mossy", Vector2i(8, 8))
	var roundtrip_path := "user://terrain_painter_roundtrip_test.json"
	var save_ok: bool = _editor._save_to_path(roundtrip_path)
	_check("手工绘制结果含平原铺石、残墙和苔峰变体",
		_editor.current_map["paving"].size() == 1
		and (_editor.current_map["terrain"] as Array)[5][5] == Cell.Terrain.WALL
		and (_editor.current_map["terrain"] as Array)[8][8] == Cell.Terrain.PEAK
		and _editor.current_map["terrain_variants"].get("5,5", "") == "ruined"
		and _editor.current_map["terrain_variants"].get("8,8", "") == "mossy")

	var before_bad_import: Dictionary = _editor.current_map.duplicate(true)
	var invalid_path := "user://terrain_painter_invalid_test.json"
	var bad_file := FileAccess.open(invalid_path, FileAccess.WRITE)
	var invalid_map: Dictionary = _editor._make_empty_map(10, 10)
	# JSON 解码数组不保留 Array[int]，使用同一输入形态测试小数拒绝。
	invalid_map = JSON.parse_string(JSON.stringify(invalid_map))
	invalid_map["terrain"][0][0] = 1.75
	bad_file.store_string(JSON.stringify(invalid_map))
	bad_file.close()
	var bad_import_ok: bool = _editor._load_from_path(invalid_path)
	_check("导入拒绝非整数地形值且保持原地图",
		not bad_import_ok and _editor.current_map == before_bad_import)
	_editor._dialog.show()
	await _click_at(_editor.cell_to_screen(Vector2i(1, 1)), MOUSE_BUTTON_LEFT)
	_check("文件对话框显示时点击不会穿透并绘制地图", _editor.current_map == before_bad_import)
	_editor._dialog.hide()

	var second_editor: Control = PainterScene.instantiate() as Control
	root.add_child(second_editor)
	await _frames(3)
	var load_ok: bool = second_editor._load_from_path(roundtrip_path)
	var same_map_data: bool = load_ok and second_editor.current_map["terrain"] == _editor.current_map["terrain"] \
		and second_editor.current_map["paving"] == _editor.current_map["paving"] \
		and second_editor.current_map["terrain_variants"] == _editor.current_map["terrain_variants"]
	_check("手工绘制与加载同一 JSON 的 terrain/paving/variants 完全相等", same_map_data)
	_freeze_board_for_capture(_editor.board_view)
	_freeze_board_for_capture(second_editor.board_view)
	await _frames(4)
	await RenderingServer.frame_post_draw
	var manual_image: Image = _editor._subviewport.get_texture().get_image()
	var loaded_image: Image = second_editor._subviewport.get_texture().get_image()
	var same_pixels: bool = manual_image.get_size() == loaded_image.get_size() \
		and manual_image.get_data() == loaded_image.get_data()
	var capture_result := _save_pixel_comparison(manual_image, loaded_image, same_map_data, same_pixels)
	_check("固定帧下手工绘制与 JSON 加载预览像素完全一致", same_pixels,
		"两张预览尺寸 %s / %s" % [manual_image.get_size(), loaded_image.get_size()])

	var pair: Vector2i = _find_invalid_pair()
	if pair.x >= 0:
		var small_map: Dictionary = _editor._make_empty_map(10, 10)
		(small_map["terrain"] as Array)[0][0] = pair.x
		_editor._replace_map(small_map, "测试邻接撤销")
		await _frames(2)
		_editor._select_terrain(pair.y)
		await _click_at(_editor.cell_to_screen(Vector2i(1, 0)), MOUSE_BUTTON_LEFT)
		_check("非法地形组合显示说明并回滚该次点击",
			_editor.current_grid.get_cell(Vector2i(0, 0)).terrain == pair.x
			and _editor.current_grid.get_cell(Vector2i(1, 0)).terrain == Cell.Terrain.PLAIN
			and _editor._status_label.text.begins_with("未绘制："), _editor._status_label.text)
	else:
		_check("存在可用于回滚验收的非法相邻地形对", false)

	var user_data_dir: String = OS.get_user_data_dir()
	DirAccess.remove_absolute(user_data_dir.path_join("terrain_painter_roundtrip_test.json"))
	DirAccess.remove_absolute(user_data_dir.path_join("terrain_painter_invalid_test.json"))
	second_editor.queue_free()
	_editor.queue_free()
	await _frames(2)
	_capture_report(same_map_data, same_pixels, _workbench_capture_saved)
	print("TERRAIN_PAINTER_RESULT " + JSON.stringify({"passed": _passed, "failed": _failed}))
	quit(1 if _failed > 0 else 0)


func _paint_variant_cell(terrain: int, variant: String, cell: Vector2i) -> void:
	await _click_control(_editor.terrain_buttons[terrain] as Control)
	var picker: OptionButton = _editor._variant_picker
	var variant_found: bool = false
	for index: int in picker.item_count:
		if str(picker.get_item_metadata(index)) == variant:
			picker.select(index)
			_editor._on_variant_selected(index)
			variant_found = true
			break
	var screen_position: Vector2 = _editor.cell_to_screen(cell)
	var hit_cell: Vector2i = _editor._cell_at_screen(screen_position)
	print("PAINT_DIAGNOSTIC terrain=%d selected=%d variant=%s selected_variant=%s cell=%s screen=%s hit=%s"
		% [terrain, _editor.selected_terrain, variant, _editor.selected_variant, cell, screen_position, hit_cell])
	await _click_at(screen_position, MOUSE_BUTTON_LEFT)
	var coordinate_key := "%d,%d" % [cell.x, cell.y]
	print("PAINT_RESULT terrain=%d variant_found=%s grid_terrain=%d map_terrain=%d map_variant=%s"
		% [terrain, variant_found, _editor.current_grid.get_cell(cell).terrain,
		(_editor.current_map["terrain"] as Array)[cell.y][cell.x],
		str((_editor.current_map["terrain_variants"] as Dictionary).get(coordinate_key, ""))])


func _ensure_control_visible(control: Control) -> void:
	var ancestor: Node = control.get_parent()
	while ancestor != null and not (ancestor is ScrollContainer):
		ancestor = ancestor.get_parent()
	if ancestor is ScrollContainer:
		(ancestor as ScrollContainer).ensure_control_visible(control)
	await _frames(2)


func _capture_workbench() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var no_actor_positions: Array[Vector2] = []
	var no_highlights: Array[Vector2] = []
	_editor.board_view.update_visibility_context(Vector2i(-1, -1), no_actor_positions, no_highlights)
	await _frames(3)
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check("湿地工作台截帧为 1280×720", image.get_size() == Vector2i(1280, 720), str(image.get_size()))
	if _output_dir.is_empty():
		return true
	DirAccess.make_dir_recursive_absolute(_output_dir)
	var path := _output_dir.path_join("terrain-painter-workbench-1280x720.png")
	var save_error: Error = image.save_png(path)
	_check("保存湿地工作台交付图", save_error == OK)
	return save_error == OK


func _freeze_board_for_capture(board: Node2D) -> void:
	board.set_process(false)
	var no_actor_positions: Array[Vector2] = []
	var no_highlights: Array[Vector2] = []
	board.update_visibility_context(Vector2i(-1, -1), no_actor_positions, no_highlights)
	board.set("_time", 1.0)
	board._process(1.0)


func _capture_report(map_equal: bool, pixel_equal: bool, workbench_saved: bool) -> void:
	if _output_dir.is_empty():
		return
	var report := {"resolution": [1280, 720], "workbench_wetland_capture_saved": workbench_saved,
		"manual_and_json_map_data_equal": map_equal, "manual_and_json_pixels_equal": pixel_equal}
	var file := FileAccess.open(_output_dir.path_join("terrain-painter-validation.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()


func _save_pixel_comparison(manual: Image, loaded: Image, same_map: bool, same_pixels: bool) -> Dictionary:
	var result := {"same_map_data": same_map, "same_pixels": same_pixels,
		"manual_size": [manual.get_width(), manual.get_height()],
		"loaded_size": [loaded.get_width(), loaded.get_height()]}
	if _output_dir.is_empty():
		return result
	DirAccess.make_dir_recursive_absolute(_output_dir)
	var manual_path := _output_dir.path_join("terrain-painter-manual.png")
	var loaded_path := _output_dir.path_join("terrain-painter-json.png")
	manual.save_png(manual_path)
	loaded.save_png(loaded_path)
	result["manual_sha256"] = FileAccess.get_sha256(manual_path)
	result["loaded_sha256"] = FileAccess.get_sha256(loaded_path)
	var report := FileAccess.open(_output_dir.path_join("terrain-painter-comparison.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify(result, "  "))
	report.close()
	return result


func _argument_value(prefix: String) -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


func _terrain_allowed_with_plain() -> int:
	for terrain_id: int in range(1, 9):
		if bool(TerrainCatalog.pair_rule(Cell.Terrain.PLAIN, terrain_id).get("allowed", false)):
			return terrain_id
	return Cell.Terrain.PLAIN


func _find_invalid_pair() -> Vector2i:
	for anchor: int in range(1, 9):
		if not bool(TerrainCatalog.pair_rule(Cell.Terrain.PLAIN, anchor).get("allowed", false)):
			continue
		for target: int in range(9):
			if not bool(TerrainCatalog.pair_rule(anchor, target).get("allowed", false)):
				return Vector2i(anchor, target)
	return Vector2i(-1, -1)


func _click_control(control: Control) -> void:
	await _click_at(control.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)


func _click_at(position: Vector2, button_index: MouseButton) -> void:
	Input.warp_mouse(position)
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)
	await _frames(2)
	var down := InputEventMouseButton.new()
	down.position = position
	down.button_index = button_index
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(2)
	var up := InputEventMouseButton.new()
	up.position = position
	up.button_index = button_index
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)


func _drag_cells(editor: Control, start: Vector2i, finish: Vector2i) -> void:
	var first: Vector2 = editor.cell_to_screen(start)
	var last: Vector2 = editor.cell_to_screen(finish)
	var down := InputEventMouseButton.new()
	down.position = first
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	root.push_input(down)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = last
	motion.relative = last - first
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion)
	await process_frame
	var up := InputEventMouseButton.new()
	up.position = last
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	root.push_input(up)
	await process_frame


func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame
