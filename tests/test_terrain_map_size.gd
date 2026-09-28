extends SceneTree

const CaptureMetadata := preload("res://tests/claude_review/capture_metadata.gd")
var _capture_records: Array[Dictionary] = []
## 正方形地图尺寸的真实工作台操作、边界输入和正式试战检查。

const Catalog := preload("res://scripts/ui/terrain/terrain_catalog.gd")
const Definition := preload("res://scripts/ui/terrain/terrain_battle_definition.gd")
var editor: Control
var output: String
var checks := 0
var failures: Array[String] = []
var captures: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, success: bool) -> void:
	checks += 1
	print("[PASS] " if success else "[FAIL] ", label)
	if not success:
		failures.append(label)


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	if not output.is_absolute_path() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	var scene := load("res://scenes/playground/terrain_painter.tscn") as PackedScene
	editor = scene.instantiate() as Control
	root.add_child(editor)
	await frames(5)
	check("默认地图为10×10且边长只接受10至25整数", editor.current_grid.width == 10
		and editor.current_grid.height == 10 and editor._map_side_input.value == 10
		and editor._map_side_input.min_value == 10 and editor._map_side_input.max_value == 25
		and editor._map_side_input.step == 1)
	check("1280窗口内边长、调整和试战控件可见且不重叠", _heading_fits())
	for control: Control in editor.terrain_buttons.values():
		check("地形按钮仍可见：" + control.text, root.get_visible_rect().encloses(control.get_global_rect()))

	editor._sample_picker.select(0)
	editor._load_selected_sample()
	await frames(4)
	var initial: Dictionary = editor.current_map.duplicate(true)
	editor._undo_stack.clear()
	editor._update_undo_button()
	await capture("map-size-10-editor-1280x720.png")
	await resize_by_click(25)
	check("输入25并真实点击调整得到625格", editor.current_grid.width == 25
		and editor.current_grid.height == 25 and editor.current_grid.cells.size() == 25
		and (editor.current_grid.cells as Array).all(func(row: Array) -> bool: return row.size() == 25))
	if editor.current_grid.width != 25:
		quit(1)
		return
	check("扩图保留原区域、铺石和外观", _retained_region(initial)
		and editor.current_map.paving == initial.paving
		and editor.current_map.terrain_variants == initial.terrain_variants)
	check("扩出的格子全部补平原", _expanded_plain())
	check("扩图只建立一步撤销", editor._undo_stack.size() == 1)
	await click_control(editor._undo_button)
	check("撤销扩图恢复10×10及尺寸输入", editor.current_map == initial and editor._map_side_input.value == 10)
	await resize_by_click(25)
	var undo_count: int = editor._undo_stack.size()
	await resize_by_click(25)
	check("同尺寸调整不会重复建立撤销", editor._undo_stack.size() == undo_count)
	for invalid_side: int in [9, 26]:
		var before: Dictionary = editor.current_map.duplicate(true)
		check("直接调整拒绝越界边长%d且状态不变" % invalid_side,
			not editor._resize_map(invalid_side) and editor.current_map == before and editor._undo_stack.size() == undo_count)

	# 对扩大后最远的边角进行真实鼠标绘制，并检查取样与坐标。
	await click_control(editor.terrain_buttons[Cell.Terrain.FOREST])
	await click_at(editor.cell_to_screen(Vector2i(24, 24)))
	check("25×25最远角可真实绘制", editor.current_grid.get_cell(Vector2i(24, 24)).terrain == Cell.Terrain.FOREST)
	await click_control(editor.terrain_buttons[Cell.Terrain.WALL])
	_set_variant("pillar")
	await click_at(editor.cell_to_screen(Vector2i(24, 0)))
	check("扩大区域可保存石柱变体", editor.current_map.terrain_variants.get("24,0", "") == "pillar")
	await click_control(editor.terrain_buttons[Cell.Terrain.PLAIN])
	_set_variant("paving")
	await click_at(editor.cell_to_screen(Vector2i(0, 24)))
	check("扩大区域可保存铺石", editor.current_map.paving.has([0, 24]))
	await click_at(editor.cell_to_screen(Vector2i(24, 24)), MOUSE_BUTTON_RIGHT)
	check("扩大区域右键取样坐标准确", editor.selected_terrain == Cell.Terrain.FOREST)
	var large: Dictionary = editor.current_map.duplicate(true)
	check("25×25完整地图通过统一校验", Catalog.validate_map(large).is_empty())
	await resize_by_click(10)
	check("缩图裁去范围外地形且原区域相同", editor.current_grid.width == 10
		and editor.current_grid.height == 10 and _retained_region(initial))
	check("缩图裁去范围外铺石及外观", editor.current_map.paving == initial.paving
		and editor.current_map.terrain_variants == initial.terrain_variants)
	await click_control(editor._undo_button)
	await frames(4)
	check("撤销缩图完整恢复625格和边长显示", editor.current_map == large and editor._map_side_input.value == 25)
	check("25×25所有格角都在画布内", _editor_board_fits())

	var save_path := output.path_join("roundtrip-25.json")
	check("25×25可保存", editor._save_to_path(save_path))
	editor._clear_map()
	check("清空仍保持25×25", editor.current_grid.width == 25 and editor.current_grid.height == 25)
	check("25×25保存再加载保持数据一致", editor._load_from_path(save_path)
		and editor.current_map == large and editor._map_side_input.value == 25)
	await frames(4)
	await _check_invalid_inputs()
	check("拒绝无效文件后仍可重新加载25×25", editor._load_from_path(save_path))
	await capture("map-size-25-editor-1280x720.png")

	var map_before: Dictionary = editor.current_map.duplicate(true)
	var undo_before: Array[Dictionary] = editor._undo_stack.duplicate(true)
	var loader: Node = root.get_node("DataLoader")
	var global_maps: Dictionary = loader.maps.duplicate(true)
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await frames(5)
		check("尺寸%d下工作台全部格角在画布内" % resolution.x, _editor_board_fits() and _heading_fits())
		if resolution.x == 1920:
			await capture("map-size-25-editor-1920x1080.png")
		await click_control(editor._battle_button)
		await frames(10)
		var session: Node2D = editor._battle_session as Node2D
		check("25×25进入正式试战%d" % resolution.x, is_instance_valid(session))
		if not is_instance_valid(session):
			continue
		check("正式试战使用25×25及两个不同出生点", session.manager.grid.width == 25
			and session.manager.grid.height == 25 and session.manager.units.size() == 2
			and session.manager.units[0].grid_position != session.manager.units[1].grid_position)
		check("正式试战棋盘避开上下HUD%d" % resolution.x, _battle_board_fits(session, resolution))
		# 通过正式输入路径移动一格，验证缩小镜头的选格仍正确。
		var hero: Unit = session.manager.units[0]
		var target := Vector2i(-1, -1)
		for neighbor: Vector2i in session.manager.grid.get_neighbors(hero.grid_position):
			if session.manager._move_range.has(neighbor) and session.manager.grid.get_unit_at(neighbor) == null:
				target = neighbor
				break
		if target.x >= 0:
			await click_at(root.get_canvas_transform() * session.manager.grid.grid_to_world(target))
			await create_timer(0.5).timeout
		check("25×25正式场景点击格子可移动%d" % resolution.x, target.x >= 0 and hero.grid_position == target)
		await capture("map-size-25-battle-%dx%d.png" % [resolution.x, resolution.y])
		var back := _find_button(session, "返回编辑")
		if back != null:
			await click_control(back)
		await frames(5)
		check("返回编辑保留25×25及完整撤销栈%d" % resolution.x,
			not is_instance_valid(session) and editor.visible and editor.current_map == map_before
			and editor._undo_stack == undo_before and editor._map_side_input.value == 25)
	check("尺寸调整与试战不污染全局地图表", loader.maps == global_maps)
	var old_path := output.path_join("roundtrip-10.json")
	var old_file := FileAccess.open(old_path, FileAccess.WRITE)
	old_file.store_string(JSON.stringify(initial))
	old_file.close()
	check("原10×10文件可加载且控件同步", editor._load_from_path(old_path)
		and editor.current_map == initial and editor._map_side_input.value == 10)
	editor.queue_free()
	await frames(3)
	check("记录真实采集配置", CaptureMetadata.write_manifest(root, output.path_join("capture-metadata.json"), _capture_records, {"script": "res://tests/test_terrain_map_size.gd"}))
	var report := {"result": "pass" if failures.is_empty() else "fail", "checks": checks,
		"failures": failures, "captures": captures, "min_side": 10, "max_side": 25, "square_only": true}
	var file := FileAccess.open(output.path_join("terrain-map-size-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("TERRAIN_MAP_SIZE_RESULT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)


func _check_invalid_inputs() -> void:
	var cases: Dictionary = {
		"低于10": editor._make_empty_map(9, 9), "超过25": editor._make_empty_map(26, 26),
		"宽大于高": editor._make_empty_map(11, 10), "高大于宽": editor._make_empty_map(10, 11),
		"声明不符": editor._make_empty_map(10, 10), "非整数边长": editor._make_empty_map(10, 10),
		"非整数地形": editor._make_empty_map(10, 10), "坏行": editor._make_empty_map(10, 10),
	}
	# 模拟文件解码，防测试本身把1.5截断为整数。
	cases = JSON.parse_string(JSON.stringify(cases))
	cases["声明不符"]["width"] = 11
	cases["非整数边长"]["width"] = 10.5
	cases["非整数地形"]["terrain"][0][0] = 1.5
	cases["坏行"]["terrain"][1] = []
	for label: String in cases:
		var source: Dictionary = cases[label]
		check("地图校验与试战拒绝：" + label, not Catalog.validate_map(source).is_empty()
			and not Definition.build(source)["ok"])
		var before: Dictionary = editor.current_map.duplicate(true)
		var undo_before: Array[Dictionary] = editor._undo_stack.duplicate(true)
		var file_path := output.path_join("invalid-import.json")
		var file := FileAccess.open(file_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(source))
		file.close()
		check("导入拒绝并保留当前地图与撤销：" + label, not editor._load_from_path(file_path)
			and editor.current_map == before and editor._undo_stack == undo_before)
		# 保存入口也不得把不符合尺寸的内部数据写出。
		editor.current_map = source
		check("保存拒绝：" + label, not editor._save_to_path(output.path_join("must-not-write.json")))
		editor.current_map = before
	check("无效保存未创建文件", not FileAccess.file_exists(output.path_join("must-not-write.json")))
	for side: int in [10, 17, 25]:
		check("有效边长%d导入与试战接受" % side, editor._normalize_import(editor._make_empty_map(side, side))["ok"]
			and Definition.build(editor._make_empty_map(side, side))["ok"])


func _heading_fits() -> bool:
	var viewport := root.get_visible_rect()
	var previous_end := 0.0
	for control: Control in editor._map_side_input.get_parent().get_children():
		var rect := control.get_global_rect()
		if not viewport.encloses(rect) or rect.position.x < previous_end:
			return false
		previous_end = rect.end.x
	return true


func _editor_board_fits() -> bool:
	var canvas: Rect2 = editor.board_container.get_global_rect()
	var center: Vector2 = (editor.cell_to_screen(Vector2i.ZERO) + editor.cell_to_screen(Vector2i(24, 24))) * 0.5
	if center.distance_to(canvas.get_center()) > 10.0:
		return false
	var half: Vector2 = Vector2(32, 16) * editor.board_view.scale
	for at: Vector2i in [Vector2i(0, 0), Vector2i(24, 0), Vector2i(0, 24), Vector2i(24, 24)]:
		if not canvas.encloses(Rect2(editor.cell_to_screen(at) - half, half * 2)):
			return false
	return true


func _battle_board_fits(session: Node2D, _resolution: Vector2i) -> bool:
	var factor := root.get_visible_rect().size.x / 1280.0
	var safe := Rect2(Vector2(20, 130) * factor, Vector2(1040, 380) * factor)
	for at: Vector2i in [Vector2i(0, 0), Vector2i(24, 0), Vector2i(0, 24), Vector2i(24, 24)]:
		var point: Vector2 = root.get_canvas_transform() * session.manager.grid.grid_to_world(at)
		var half: Vector2 = Vector2(32, 16) * session.camera.zoom
		if not safe.encloses(Rect2(point - half, half * 2)):
			return false
	return true


func _retained_region(original: Dictionary) -> bool:
	for y: int in 10:
		for x: int in 10:
			if editor.current_map.terrain[y][x] != original.terrain[y][x]:
				return false
	return true


func _expanded_plain() -> bool:
	for y: int in 25:
		for x: int in 25:
			if (x >= 10 or y >= 10) and editor.current_map.terrain[y][x] != Cell.Terrain.PLAIN:
				return false
	return true


func _set_variant(value: String) -> void:
	for index: int in editor._variant_picker.item_count:
		if editor._variant_picker.get_item_metadata(index) == value:
			editor._variant_picker.select(index)
			editor._on_variant_selected(index)
			return


func _find_button(node: Node, label: String) -> Button:
	for child: Node in node.find_children("*", "Button", true, false):
		if child is Button and child.text == label and child.is_visible_in_tree():
			return child
	return null


func resize_by_click(side: int) -> void:
	# 故意不预先提交文本：真实按钮必须应用仍在编辑的SpinBox内容。
	var line: LineEdit = editor._map_side_input.get_line_edit()
	line.grab_focus()
	await frames(2)
	line.text = str(side)
	await click_control(editor._resize_button)
	await frames(4)


func click_control(control: Control) -> void:
	await click_at(control.get_global_rect().get_center())


func click_at(at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	Input.warp_mouse(root.get_stretch_transform() * at)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)
	await frames(2)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = button
		event.pressed = pressed
		root.push_input(event, true)
		await frames(2)


func frames(count: int) -> void:
	for _index: int in count:
		await process_frame


func capture(name: String) -> void:
	await frames(3)
	await RenderingServer.frame_post_draw
	var path := output.path_join(name)
	var image := root.get_texture().get_image()
	check("原生截帧：" + name, image.get_size() == root.size and image.save_png(path) == OK)
	captures[name] = FileAccess.get_sha256(path)
	_capture_records.append(CaptureMetadata.capture_record(root, image, path))
