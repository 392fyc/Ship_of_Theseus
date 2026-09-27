extends Control
## 中文地形拼图工作台。编辑布局后可进入正式战斗试用，返回时保留创作状态。

const BoardViewScript := preload("res://scripts/ui/playground/courtyard_board_view.gd")
const TerrainCatalog := preload("res://scripts/ui/terrain/terrain_catalog.gd")
const PROFILE_PATH := "res://assets/prototype/battlefield_courtyard/visual_profile.json"
const SAMPLE_PATH := "res://assets/prototype/battlefield_courtyard/courtyard_layouts.json"
const EXAMPLES_PATH := "res://assets/prototype/battlefield_courtyard/terrain_examples.json"
const TERRAIN_BATTLE_SESSION_PATH := "res://scripts/tactical/terrain_battle_session.gd"
const MIN_MAP_SIDE := TerrainCatalog.MIN_MAP_SIDE
const MAX_MAP_SIDE := TerrainCatalog.MAX_MAP_SIDE
const TERRAIN_LABELS: Array[String] = [
	"平原", "森林", "山地", "山峰", "墙体", "浅水", "深水", "熔岩", "沼泽",
]
const VARIANT_LABELS: Dictionary = {
	"meadow": "草地", "paving": "铺石", "rocky": "岩质", "mossy": "苔质",
	"forest": "森林", "foothill": "山麓", "shallow": "浅水", "deep": "深水",
	"lava": "熔岩", "marsh": "沼泽", "dressed": "整砌", "ruined": "残墙", "pillar": "石柱",
}

var current_map: Dictionary = {}
var current_grid: Grid
var board_view: Node2D
var board_container: SubViewportContainer
var terrain_buttons: Dictionary = {}
var selected_terrain: int = Cell.Terrain.PLAIN
var selected_variant: String = "meadow"
var grid_lines_visible: bool = true

var _profile: Dictionary = {}
var _terrain_catalog: Dictionary = {}
var _subviewport: SubViewport
var _variant_picker: OptionButton
var _sample_picker: OptionButton
var _status_label: Label
var _undo_button: Button
var _battle_button: Button
var _map_side_input: SpinBox
var _resize_button: Button
var _dialog: FileDialog
var _dialog_action: String = ""
var _battle_session_script: Script
var _battle_session: Node2D
var _battle_start_in_progress: bool = false
var _battle_return_in_progress: bool = false
var _saved_canvas_transform := Transform2D.IDENTITY
var _has_saved_canvas_transform: bool = false
var _saved_process_state: bool = true
var _saved_input_state: bool = true
var _saved_unhandled_input_state: bool = true
var _saved_unhandled_key_input_state: bool = true
var _undo_stack: Array[Dictionary] = []
var _painting: bool = false
var _stroke_snapshot: Dictionary = {}
var _stroke_changed: bool = false
var _stroke_last_cell: Vector2i = Vector2i(-1, -1)
var _error_message: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_profile = _read_dictionary(PROFILE_PATH)
	_terrain_catalog = TerrainCatalog.catalog()
	_build_interface()
	current_map = _make_empty_map(MIN_MAP_SIDE, MIN_MAP_SIDE)
	_replace_board()
	_update_undo_button()
	set_process(true)


func _exit_tree() -> void:
	_dispose_battle_session(false, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		call_deferred("_fit_board")


func _process(_delta: float) -> void:
	if _subviewport != null and board_container != null:
		var desired := Vector2i(maxi(1, roundi(board_container.size.x)), maxi(1, roundi(board_container.size.y)))
		if _subviewport.size != desired:
			_subviewport.size = desired
			_fit_board()


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = Color("172126")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 16)
	outer.add_theme_constant_override("margin_top", 14)
	outer.add_theme_constant_override("margin_right", 16)
	outer.add_theme_constant_override("margin_bottom", 14)
	add_child(outer)
	var columns := VBoxContainer.new()
	columns.add_theme_constant_override("separation", 10)
	outer.add_child(columns)

	var heading := HBoxContainer.new()
	columns.add_child(heading)
	var title := Label.new()
	title.text = "地形拼图工作台"
	title.add_theme_font_size_override("font_size", 24)
	heading.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "  自动衔接地形边缘"
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.modulate = Color("c4d0ce")
	heading.add_child(subtitle)
	var heading_spacer := Control.new()
	heading_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(heading_spacer)
	var side_label := Label.new()
	side_label.text = "边长（10–25）"
	side_label.add_theme_font_size_override("font_size", 16)
	heading.add_child(side_label)
	_map_side_input = SpinBox.new()
	_map_side_input.min_value = MIN_MAP_SIDE
	_map_side_input.max_value = MAX_MAP_SIDE
	_map_side_input.step = 1
	_map_side_input.value = MIN_MAP_SIDE
	_map_side_input.suffix = "格"
	_map_side_input.select_all_on_focus = true
	_map_side_input.custom_minimum_size = Vector2(100, 44)
	_map_side_input.get_line_edit().add_theme_font_size_override("font_size", 18)
	_map_side_input.tooltip_text = "仅支持正方形地图，边长为 10 至 25 格"
	heading.add_child(_map_side_input)
	_resize_button = _add_button(heading, "调整大小", _apply_map_size)
	_resize_button.size_flags_horizontal = Control.SIZE_FILL
	_resize_button.custom_minimum_size = Vector2(124, 44)
	_resize_button.tooltip_text = "扩大时补平原；超出新边界的格子会裁去，可撤销恢复"
	_battle_button = Button.new()
	_battle_button.text = "开始试战"
	_battle_button.custom_minimum_size = Vector2(136, 44)
	_battle_button.add_theme_font_size_override("font_size", 18)
	_battle_button.pressed.connect(_start_battle)
	heading.add_child(_battle_button)

	var workspace := HBoxContainer.new()
	workspace.add_theme_constant_override("separation", 12)
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(workspace)
	workspace.add_child(_build_tool_panel())
	workspace.add_child(_build_canvas_panel())

	_status_label = Label.new()
	_status_label.text = "左键绘制 · 右键取样 · 拖动连续绘制"
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size.y = 42
	columns.add_child(_status_label)

	_dialog = FileDialog.new()
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.add_filter("*.json ; JSON 地形布局")
	_dialog.size = Vector2i(900, 620)
	_dialog.file_selected.connect(_on_file_selected)
	add_child(_dialog)


func _build_tool_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 350
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var tools := VBoxContainer.new()
	tools.add_theme_constant_override("separation", 9)
	scroll.add_child(tools)

	_add_section_label(tools, "示例布局")
	var sample_row := HBoxContainer.new()
	tools.add_child(sample_row)
	_sample_picker = OptionButton.new()
	_sample_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sample_picker.add_theme_font_size_override("font_size", 16)
	_sample_picker.add_item("庭院示例")
	_sample_picker.add_item("湿地示例")
	_sample_picker.add_item("高地示例")
	_refresh_sample_labels()
	sample_row.add_child(_sample_picker)
	_add_button(sample_row, "载入", _load_selected_sample)

	_add_section_label(tools, "选择地形")
	var palette := GridContainer.new()
	palette.columns = 3
	palette.add_theme_constant_override("h_separation", 6)
	palette.add_theme_constant_override("v_separation", 6)
	tools.add_child(palette)
	var group := ButtonGroup.new()
	for terrain_id: int in TERRAIN_LABELS.size():
		var button := Button.new()
		button.text = TERRAIN_LABELS[terrain_id]
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(100, 54)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(_select_terrain.bind(terrain_id))
		palette.add_child(button)
		terrain_buttons[terrain_id] = button
	terrain_buttons[Cell.Terrain.PLAIN].button_pressed = true

	_add_section_label(tools, "地形外观")
	_variant_picker = OptionButton.new()
	_variant_picker.add_theme_font_size_override("font_size", 16)
	_variant_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_variant_picker.item_selected.connect(_on_variant_selected)
	tools.add_child(_variant_picker)
	_refresh_variant_picker()

	_add_section_label(tools, "编辑操作")
	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	tools.add_child(actions)
	_undo_button = _add_button(actions, "撤销", _undo)
	_add_button(actions, "清空", _clear_map)
	_add_button(actions, "格线：显示", _toggle_grid_lines)
	_add_button(actions, "保存 JSON", _show_save_dialog)
	_add_button(actions, "加载 JSON", _show_open_dialog)

	var help := Label.new()
	help.text = "边缘会随相邻地形自动更新，保存后可继续编辑。"
	help.add_theme_font_size_override("font_size", 16)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color("c4d0ce")
	tools.add_child(help)
	return panel


func _build_canvas_panel() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	board_container = SubViewportContainer.new()
	board_container.stretch = true
	board_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_container.clip_contents = true
	board_container.resized.connect(_fit_board.call_deferred)
	margin.add_child(board_container)
	_subviewport = SubViewport.new()
	_subviewport.size = Vector2i(800, 600)
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_subviewport.handle_input_locally = false
	board_container.add_child(_subviewport)
	return panel


func _add_section_label(parent: Control, value: String) -> void:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", 18)
	parent.add_child(label)


func _add_button(parent: Control, value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 42
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _make_empty_map(width: int, height: int) -> Dictionary:
	var rows: Array = []
	for _y: int in height:
		var row: Array[int] = []
		for _x: int in width:
			row.append(Cell.Terrain.PLAIN)
		rows.append(row)
	return {"width": width, "height": height, "terrain": rows, "paving": [],
		"terrain_variants": {}, "transition_preview": true, "environment": "terrain_workshop"}


func _read_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _replace_board() -> void:
	if _subviewport == null:
		return
	if board_view != null and is_instance_valid(board_view):
		_subviewport.remove_child(board_view)
		board_view.queue_free()
	current_grid = Grid.new()
	current_grid.initialize(current_map)
	if _map_side_input != null:
		_map_side_input.set_value_no_signal(current_grid.width)
	board_view = BoardViewScript.new()
	board_view.configure(current_grid, _profile, current_map)
	board_view.grid_visible = grid_lines_visible
	_subviewport.add_child(board_view)
	_fit_board()


func _fit_board() -> void:
	if board_view == null or current_grid == null or _subviewport == null:
		return
	var canvas_size := Vector2(_subviewport.size)
	if canvas_size.x <= 2 or canvas_size.y <= 2:
		return
	var terrain_bounds := Rect2()
	var has_points: bool = false
	var has_mountain_art: bool = false
	for y: int in current_grid.height:
		for x: int in current_grid.width:
			var cell := Vector2i(x, y)
			if current_grid.get_cell(cell).terrain in [Cell.Terrain.MOUNTAIN, Cell.Terrain.PEAK]:
				has_mountain_art = true
			for point: Vector2 in board_view.diamond(cell):
				if has_points:
					terrain_bounds = terrain_bounds.expand(point)
				else:
					terrain_bounds = Rect2(point, Vector2.ZERO)
					has_points = true
	if not has_points:
		var iso_width: float = float(current_grid.width + current_grid.height) * 32.0
		terrain_bounds = Rect2(Vector2.ZERO, Vector2(iso_width, iso_width * 0.5))
	var headroom: float = 112.0 if has_mountain_art else 22.0
	var padded_bounds := Rect2(terrain_bounds.position - Vector2(18.0, headroom),
		terrain_bounds.size + Vector2(36.0, headroom + 24.0))
	var map_width: float = maxf(padded_bounds.size.x, float(current_grid.width + current_grid.height) * 32.0)
	var map_height: float = padded_bounds.size.y
	var zoom: float = minf(1.45, minf((canvas_size.x - 32.0) / map_width, (canvas_size.y - 32.0) / map_height))
	zoom = maxf(0.3, zoom)
	board_view.scale = Vector2.ONE * zoom
	board_view.position = (canvas_size - padded_bounds.size * zoom) * 0.5 - padded_bounds.position * zoom


func cell_to_screen(cell: Vector2i) -> Vector2:
	if current_grid == null or board_view == null or board_container == null:
		return Vector2.ZERO
	var viewport_pos: Vector2 = board_view.position + current_grid.grid_to_world(cell) * board_view.scale
	return board_container.global_position + viewport_pos


func _cell_at_screen(screen_pos: Vector2) -> Vector2i:
	if board_container == null or current_grid == null or not board_container.get_global_rect().has_point(screen_pos):
		return Vector2i(-1, -1)
	var viewport_pos: Vector2 = screen_pos - board_container.global_position
	var board_local: Vector2 = (viewport_pos - board_view.position) / board_view.scale
	return current_grid.world_to_grid(board_local)


func _input(event: InputEvent) -> void:
	if _dialog != null and _dialog.visible:
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		var hovered_cell := _cell_at_screen(mouse_button.position)
		_update_board_hover(hovered_cell)
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button.pressed:
				var start_cell := _cell_at_screen(mouse_button.position)
				if current_grid.is_valid(start_cell):
					_begin_stroke(start_cell)
			else:
				_finish_stroke()
		elif mouse_button.button_index == MOUSE_BUTTON_RIGHT and mouse_button.pressed:
			var sample_cell := _cell_at_screen(mouse_button.position)
			if current_grid.is_valid(sample_cell):
				_sample_cell(sample_cell)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var next_cell := _cell_at_screen(motion.position)
		_update_board_hover(next_cell)
		if _painting and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if current_grid.is_valid(next_cell):
				_paint_segment(_stroke_last_cell, next_cell)
				_stroke_last_cell = next_cell


func _begin_stroke(cell: Vector2i) -> void:
	_finish_stroke()
	_painting = true
	_stroke_snapshot = current_map.duplicate(true)
	_stroke_changed = false
	_stroke_last_cell = cell
	_paint_segment(cell, cell)


func _finish_stroke() -> void:
	if not _painting:
		return
	_painting = false
	if _stroke_changed:
		_undo_stack.append(_stroke_snapshot)
		_update_undo_button()
	_stroke_snapshot = {}
	_stroke_changed = false
	_stroke_last_cell = Vector2i(-1, -1)


func _paint_segment(from: Vector2i, to: Vector2i) -> void:
	var dx: int = absi(to.x - from.x)
	var dy: int = absi(to.y - from.y)
	var steps: int = maxi(dx, dy)
	if steps == 0:
		_apply_brush(to)
		return
	for i: int in steps + 1:
		var ratio: float = float(i) / float(steps)
		var cell := Vector2i(roundi(lerpf(float(from.x), float(to.x), ratio)),
			roundi(lerpf(float(from.y), float(to.y), ratio)))
		_apply_brush(cell)


func _apply_brush(cell: Vector2i) -> void:
	if not current_grid.is_valid(cell):
		return
	var candidate: Dictionary = current_map.duplicate(true)
	var rows: Array = candidate["terrain"]
	rows[cell.y][cell.x] = selected_terrain
	candidate["terrain"] = rows
	var coordinate_key := "%d,%d" % [cell.x, cell.y]
	var paving: Array = candidate["paving"]
	var variants: Dictionary = candidate["terrain_variants"]
	_remove_coordinate(paving, cell)
	variants.erase(coordinate_key)
	if selected_terrain == Cell.Terrain.PLAIN and selected_variant == "paving":
		paving.append([cell.x, cell.y])
	if selected_variant in _variants_for(selected_terrain):
		variants[coordinate_key] = selected_variant
	candidate["paving"] = paving
	candidate["terrain_variants"] = variants
	var errors: Array[Dictionary] = TerrainCatalog.validate_map(candidate)
	if not errors.is_empty():
		_report_catalog_error(errors[0])
		return
	current_map = candidate
	_stroke_changed = true
	_error_message = ""
	_replace_board()
	_update_status("已绘制：%s · 格子 (%d, %d)" % [TERRAIN_LABELS[selected_terrain], cell.x, cell.y])


func _remove_coordinate(coords: Array, cell: Vector2i) -> void:
	for i: int in range(coords.size() - 1, -1, -1):
		var entry: Variant = coords[i]
		if entry is Array and entry.size() == 2 and int(entry[0]) == cell.x and int(entry[1]) == cell.y:
			coords.remove_at(i)


func _sample_cell(cell: Vector2i) -> void:
	selected_terrain = current_grid.get_cell(cell).terrain
	var key := "%d,%d" % [cell.x, cell.y]
	var variants: Dictionary = current_map.get("terrain_variants", {})
	if selected_terrain == Cell.Terrain.PLAIN:
		selected_variant = str(variants.get(key, "paving" if _has_coordinate(current_map.get("paving", []), cell) else "meadow"))
	else:
		var options: Array[String] = _variants_for(selected_terrain)
		selected_variant = str(variants.get(key, options[0] if not options.is_empty() else ""))
	if terrain_buttons.has(selected_terrain):
		terrain_buttons[selected_terrain].button_pressed = true
	_refresh_variant_picker()
	_update_status("已取样：%s · 格子 (%d, %d)" % [TERRAIN_LABELS[selected_terrain], cell.x, cell.y])


func _has_coordinate(coords: Array, cell: Vector2i) -> bool:
	for entry: Variant in coords:
		if entry is Array and entry.size() == 2 and int(entry[0]) == cell.x and int(entry[1]) == cell.y:
			return true
	return false


func _select_terrain(terrain_id: int) -> void:
	selected_terrain = terrain_id
	var options: Array[String] = _variants_for(terrain_id)
	if not options.is_empty() and selected_variant not in options:
		selected_variant = str(options[0])
	_refresh_variant_picker()
	_update_status("画笔：%s" % TERRAIN_LABELS[terrain_id])


func _refresh_variant_picker() -> void:
	if _variant_picker == null:
		return
	_variant_picker.clear()
	var options: Array[String] = _variants_for(selected_terrain)
	if options.is_empty():
		_variant_picker.add_item("无额外外观")
		_variant_picker.disabled = true
		return
	_variant_picker.disabled = false
	for variant: String in options:
		_variant_picker.add_item(str(VARIANT_LABELS.get(variant, variant)))
		_variant_picker.set_item_metadata(_variant_picker.item_count - 1, variant)
		if variant == selected_variant:
			_variant_picker.select(_variant_picker.item_count - 1)


func _on_variant_selected(index: int) -> void:
	var metadata: Variant = _variant_picker.get_item_metadata(index)
	if metadata is String:
		selected_variant = metadata


func _toggle_grid_lines() -> void:
	grid_lines_visible = not grid_lines_visible
	if board_view != null:
		board_view.grid_visible = grid_lines_visible
		board_view.queue_redraw()
	var button: Button = _find_button("格线：显示")
	if button != null:
		button.text = "格线：显示" if grid_lines_visible else "格线：隐藏"


func _find_button(value: String) -> Button:
	for node: Node in find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == value or button.text == "格线：隐藏":
			return button
	return null


func _undo() -> void:
	_finish_stroke()
	if _undo_stack.is_empty():
		return
	current_map = _undo_stack.pop_back()
	_error_message = ""
	_replace_board()
	_update_undo_button()
	_update_status("已撤销上一步操作")


func _apply_map_size() -> void:
	_map_side_input.apply()
	_resize_map(int(_map_side_input.value))


func _resize_map(side: int) -> bool:
	_finish_stroke()
	if side < MIN_MAP_SIDE or side > MAX_MAP_SIDE:
		_update_status("边长必须为 %d 至 %d 格" % [MIN_MAP_SIDE, MAX_MAP_SIDE])
		return false
	if current_grid.width == side and current_grid.height == side:
		_update_status("当前地图已是 %d×%d" % [side, side])
		return true
	var resized := current_map.duplicate(true)
	var rows: Array = []
	for y: int in side:
		var row: Array[int] = []
		for x: int in side:
			row.append(int(current_map["terrain"][y][x]) if x < current_grid.width and y < current_grid.height else Cell.Terrain.PLAIN)
		rows.append(row)
	resized["width"] = side
	resized["height"] = side
	resized["terrain"] = rows
	var paving: Array = []
	for at: Array in current_map["paving"]:
		if int(at[0]) < side and int(at[1]) < side:
			paving.append(at.duplicate())
	resized["paving"] = paving
	var variants: Dictionary = {}
	for key: String in current_map["terrain_variants"]:
		var parts := key.split(",")
		if int(parts[0]) < side and int(parts[1]) < side:
			variants[key] = current_map["terrain_variants"][key]
	resized["terrain_variants"] = variants
	var errors := TerrainCatalog.validate_map(resized)
	if not errors.is_empty():
		_update_status("调整失败：" + str(errors[0]["reason"]))
		return false
	_replace_map(resized, "地图已调整为 %d×%d，可撤销" % [side, side])
	return true


func _clear_map() -> void:
	var width: int = current_grid.width
	var height: int = current_grid.height
	var cleared := _make_empty_map(width, height)
	if cleared == current_map:
		_update_status("地图已经是空白")
		return
	_undo_stack.append(current_map.duplicate(true))
	current_map = cleared
	_replace_board()
	_update_undo_button()
	_update_status("地图已清空，可撤销")


func _update_undo_button() -> void:
	if _undo_button != null:
		_undo_button.disabled = _undo_stack.is_empty()


func _load_selected_sample() -> void:
	var sample_path := EXAMPLES_PATH if FileAccess.file_exists(EXAMPLES_PATH) else SAMPLE_PATH
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(sample_path))
	if not (parsed is Dictionary):
		_update_status("示例布局文件无法读取")
		return
	var keys: Array[String] = []
	if sample_path == EXAMPLES_PATH:
		keys.append_array(["courtyard", "wetland", "highland"])
	else:
		keys.append_array(["overgrown", "flooded", "passage"])
	var key: String = keys[clampi(_sample_picker.selected, 0, keys.size() - 1)]
	var source: Dictionary = parsed.get(key, {})
	var candidate: Dictionary = _map_from_sample(source)
	var validation := _normalize_import(candidate)
	if not validation["ok"]:
		_update_status("示例布局校验失败：%s" % validation["message"])
		return
	_replace_map(validation["map"], "已载入示例：%s" % str(source.get("name", key)))


func _map_from_sample(source: Dictionary) -> Dictionary:
	var data := _make_empty_map(MIN_MAP_SIDE, MIN_MAP_SIDE)
	for key: String in ["terrain", "width", "height", "paving", "terrain_variants"]:
		if source.has(key):
			data[key] = source[key].duplicate(true) if source[key] is Array or source[key] is Dictionary else source[key]
	return data


func _refresh_sample_labels() -> void:
	if _sample_picker == null or not FileAccess.file_exists(EXAMPLES_PATH):
		return
	var examples: Dictionary = _read_dictionary(EXAMPLES_PATH)
	var keys: Array[String] = ["courtyard", "wetland", "highland"]
	for i: int in keys.size():
		var sample: Variant = examples.get(keys[i], {})
		if sample is Dictionary and sample.has("name"):
			_sample_picker.set_item_text(i, str(sample["name"]))


func _replace_map(value: Dictionary, message: String) -> void:
	_finish_stroke()
	_undo_stack.append(current_map.duplicate(true))
	current_map = value.duplicate(true)
	_error_message = ""
	_replace_board()
	_update_undo_button()
	_update_status(message)


func _show_save_dialog() -> void:
	_dialog_action = "save"
	_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_dialog.title = "保存地形布局"
	_dialog.current_dir = OS.get_user_data_dir()
	_dialog.current_file = "terrain-layout.json"
	_dialog.popup_centered_ratio(0.78)


func _show_open_dialog() -> void:
	_dialog_action = "open"
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.title = "加载地形布局"
	_dialog.current_dir = OS.get_user_data_dir()
	_dialog.popup_centered_ratio(0.78)


func _on_file_selected(path: String) -> void:
	if _dialog_action == "save":
		_save_to_path(path)
	elif _dialog_action == "open":
		_load_from_path(path)


func _save_to_path(path: String) -> bool:
	var errors := TerrainCatalog.validate_map(current_map)
	if not errors.is_empty():
		_update_status("保存失败：" + str(errors[0]["reason"]))
		return false
	var save_path := path
	if save_path.get_extension().to_lower() != "json":
		save_path += ".json"
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		_update_status("保存失败：无法写入选定文件")
		return false
	file.store_string(JSON.stringify(current_map, "  "))
	file.close()
	_update_status("已保存 JSON：%s" % save_path)
	return true


func _load_from_path(path: String) -> bool:
	if not FileAccess.file_exists(path):
		_update_status("加载失败：文件不存在")
		return false
	var parser := JSON.new()
	var parse_error: Error = parser.parse(FileAccess.get_file_as_string(path))
	if parse_error != OK:
		_update_status("JSON 格式错误：第 %d 行，%s" % [parser.get_error_line(), parser.get_error_message()])
		return false
	if not (parser.data is Dictionary):
		_update_status("导入失败：JSON 顶层必须是对象")
		return false
	var validation := _normalize_import(parser.data)
	if not validation["ok"]:
		_update_status("导入失败：%s" % validation["message"])
		return false
	_replace_map(validation["map"], "已加载并校验地形布局")
	return true


func _normalize_import(input: Dictionary) -> Dictionary:
	if not input.has("terrain") or not (input["terrain"] is Array):
		return _invalid("terrain 必须是二维数组")
	var rows: Array = input["terrain"]
	var height: int = rows.size()
	if height < MIN_MAP_SIDE or height > MAX_MAP_SIDE:
		return _invalid("地图边长必须为 %d 至 %d 格" % [MIN_MAP_SIDE, MAX_MAP_SIDE])
	if not (rows[0] is Array):
		return _invalid("terrain 的每一行都必须是数组")
	var width: int = rows[0].size()
	if width != height:
		return _invalid("地图必须为正方形，宽度与高度须相同")
	if input.has("width"):
		var declared_width := _json_integer(input["width"])
		if not declared_width["ok"] or declared_width["value"] != width:
			return _invalid("width 必须是与 terrain 行宽一致的整数")
	if input.has("height"):
		var declared_height := _json_integer(input["height"])
		if not declared_height["ok"] or declared_height["value"] != height:
			return _invalid("height 必须是与 terrain 行数一致的整数")
	if input.has("transition_preview") and (not (input["transition_preview"] is bool) or not input["transition_preview"]):
		return _invalid("transition_preview 必须为 true")
	if input.has("environment") and (not (input["environment"] is String) or input["environment"] != "terrain_workshop"):
		return _invalid("environment 必须为 terrain_workshop")
	var normalized_rows: Array = []
	for y: int in height:
		if not (rows[y] is Array) or rows[y].size() != width:
			return _invalid("terrain 第 %d 行宽度不一致" % y)
		var normalized_row: Array[int] = []
		for x: int in width:
			var terrain_value := _json_integer(rows[y][x])
			if not terrain_value["ok"] or terrain_value["value"] < 0 or terrain_value["value"] > 8:
				return _invalid("terrain[%d][%d] 必须是 0 到 8 的整数" % [y, x])
			normalized_row.append(terrain_value["value"])
		normalized_rows.append(normalized_row)

	var normalized := _make_empty_map(width, height)
	normalized["terrain"] = normalized_rows
	var paving_values: Variant = input.get("paving", [])
	if not (paving_values is Array):
		return _invalid("paving 必须是坐标数组")
	var paving: Array = []
	for coordinate: Variant in paving_values:
		var parsed_coordinate := _parse_coordinate(coordinate, width, height)
		if not parsed_coordinate["ok"]:
			return _invalid(str(parsed_coordinate["message"]))
		var cell: Vector2i = parsed_coordinate["cell"]
		if normalized_rows[cell.y][cell.x] != Cell.Terrain.PLAIN:
			return _invalid("铺石坐标必须落在 PLAIN 地形上")
		if _has_coordinate(paving, cell):
			return _invalid("paving 中存在重复坐标")
		paving.append([cell.x, cell.y])
	var variants_value: Variant = input.get("terrain_variants", {})
	if not (variants_value is Dictionary):
		return _invalid("terrain_variants 必须是对象")
	var variants: Dictionary = {}
	for raw_key: Variant in variants_value.keys():
		if not (raw_key is String):
			return _invalid("terrain_variants 的坐标键必须是字符串")
		var split: PackedStringArray = str(raw_key).split(",")
		if split.size() != 2 or not split[0].is_valid_int() or not split[1].is_valid_int():
			return _invalid("变体坐标格式必须是 x,y")
		var cell := Vector2i(int(split[0]), int(split[1]))
		if cell.x < 0 or cell.x >= width or cell.y < 0 or cell.y >= height:
			return _invalid("变体坐标超出地图范围")
		if not (variants_value[raw_key] is String):
			return _invalid("地形变体值必须是字符串")
		var variant_name: String = variants_value[raw_key]
		var terrain_id: int = normalized_rows[cell.y][cell.x]
		if terrain_id == Cell.Terrain.PLAIN and variant_name in ["meadow", "paving"]:
			if variant_name == "meadow":
				_remove_coordinate(paving, cell)
			elif not _has_coordinate(paving, cell):
				paving.append([cell.x, cell.y])
			variants["%d,%d" % [cell.x, cell.y]] = variant_name
			continue
		var allowed: Array[String] = _variants_for(terrain_id)
		if variant_name not in allowed:
			return _invalid("%s 地形不支持变体 %s" % [Cell.TERRAIN_KEY_BY_ID.get(terrain_id, terrain_id), variant_name])
		variants["%d,%d" % [cell.x, cell.y]] = variant_name
	for coordinate: Array in paving:
		var paved_cell := Vector2i(int(coordinate[0]), int(coordinate[1]))
		var paved_key := "%d,%d" % [paved_cell.x, paved_cell.y]
		if not variants.has(paved_key):
			variants[paved_key] = "paving"
	normalized["paving"] = paving
	normalized["terrain_variants"] = variants
	var errors: Array[Dictionary] = TerrainCatalog.validate_map(normalized)
	if not errors.is_empty():
		return _invalid(_catalog_error_text(errors[0]))
	return {"ok": true, "map": normalized, "message": ""}


func _parse_coordinate(value: Variant, width: int, height: int) -> Dictionary:
	if not (value is Array) or value.size() != 2:
		return {"ok": false, "message": "每个 paving 坐标必须是 [x, y]"}
	var x_value := _json_integer(value[0])
	var y_value := _json_integer(value[1])
	if not x_value["ok"] or not y_value["ok"]:
		return {"ok": false, "message": "坐标 x、y 必须是整数"}
	var cell := Vector2i(x_value["value"], y_value["value"])
	if cell.x < 0 or cell.x >= width or cell.y < 0 or cell.y >= height:
		return {"ok": false, "message": "坐标超出地图范围"}
	return {"ok": true, "cell": cell}


func _json_integer(value: Variant) -> Dictionary:
	if value is int:
		return {"ok": true, "value": value}
	if value is float and is_finite(value) and floorf(value) == value:
		return {"ok": true, "value": int(value)}
	return {"ok": false, "value": 0}


func _invalid(message: String) -> Dictionary:
	return {"ok": false, "map": {}, "message": message}


func _report_catalog_error(error: Dictionary) -> void:
	_error_message = _catalog_error_text(error)
	_update_status("未绘制：%s" % _error_message)


func _catalog_error_text(error: Dictionary) -> String:
	var cell: Variant = error.get("cell", [])
	var neighbor: Variant = error.get("neighbor", [])
	var reason: String = str(error.get("reason", "邻接不符合地形规则"))
	if cell is Array and cell.size() == 2 and neighbor is Array and neighbor.size() == 2:
		return "(%s,%s) 与 (%s,%s)：%s" % [cell[0], cell[1], neighbor[0], neighbor[1], reason]
	return reason


func _variants_for(terrain_id: int) -> Array[String]:
	var result: Array[String] = []
	var terrains: Dictionary = _terrain_catalog.get("terrains", {})
	var definition: Variant = terrains.get(str(terrain_id), {})
	if not definition is Dictionary:
		return result
	for value: Variant in definition.get("variants", []):
		if value is String:
			result.append(value)
	return result


func _update_board_hover(cell: Vector2i) -> void:
	if board_view == null:
		return
	var no_actor_positions: Array[Vector2] = []
	var no_highlights: Array[Vector2] = []
	board_view.update_visibility_context(cell, no_actor_positions, no_highlights)


func _update_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message
		_status_label.modulate = Color("ffbe87") if message.begins_with("未绘制") or message.begins_with("导入失败") or message.begins_with("加载失败") else Color("e2e9e7")


func _start_battle() -> void:
	if _battle_start_in_progress or _battle_return_in_progress:
		return
	if is_instance_valid(_battle_session):
		_update_status("试战已在进行中")
		return
	_finish_stroke()
	if _battle_session_script == null and ResourceLoader.exists(TERRAIN_BATTLE_SESSION_PATH):
		_battle_session_script = load(TERRAIN_BATTLE_SESSION_PATH) as Script
	if _battle_session_script == null:
		_update_status("试战模块尚未就绪")
		return
	var owner_node: Node = get_parent()
	if owner_node == null:
		_update_status("无法开始试战：工作台没有场景父节点")
		return
	_battle_start_in_progress = true
	var session_node: Variant = _battle_session_script.new()
	if not (session_node is Node2D) or not session_node.has_method("configure_map"):
		if session_node is Node:
			(session_node as Node).free()
		_battle_start_in_progress = false
		_update_status("试战模块接口不完整")
		return
	var session := session_node as Node2D
	var configuration: Variant = session.call("configure_map", current_map.duplicate(true))
	if not (configuration is Dictionary) or not bool(configuration.get("ok", false)):
		var reason: String = str(configuration.get("message", "无法生成试战地图")) if configuration is Dictionary else "无法生成试战地图"
		session.free()
		_battle_start_in_progress = false
		_update_status("无法开始试战：%s" % reason)
		return
	if not session.has_signal("editing_resumed"):
		session.free()
		_battle_start_in_progress = false
		_update_status("试战模块缺少返回信号")
		return
	_saved_process_state = is_processing()
	_saved_input_state = is_processing_input()
	_saved_unhandled_input_state = is_processing_unhandled_input()
	_saved_unhandled_key_input_state = is_processing_unhandled_key_input()
	_saved_canvas_transform = get_viewport().get_canvas_transform()
	_has_saved_canvas_transform = true
	_battle_session = session
	session.connect("editing_resumed", _on_battle_editing_resumed, CONNECT_DEFERRED)
	hide()
	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	set_process_unhandled_key_input(false)
	owner_node.add_child(session)
	_battle_start_in_progress = false


func _on_battle_editing_resumed() -> void:
	if _battle_return_in_progress:
		return
	_battle_return_in_progress = true
	_dispose_battle_session(true)
	_battle_return_in_progress = false


func _dispose_battle_session(restore_editor: bool, defer_release: bool = false) -> void:
	var session: Node2D = _battle_session
	_battle_session = null
	if is_instance_valid(session):
		if defer_release:
			session.queue_free()
		else:
			var owner_node: Node = session.get_parent()
			if owner_node != null:
				owner_node.remove_child(session)
			session.free()
	if not _has_saved_canvas_transform:
		return
	var viewport: Viewport = get_viewport()
	if is_instance_valid(viewport):
		if defer_release:
			viewport.set_deferred("canvas_transform", _saved_canvas_transform)
		else:
			viewport.canvas_transform = _saved_canvas_transform
	_has_saved_canvas_transform = false
	if not restore_editor or not is_inside_tree():
		return
	show()
	set_process(_saved_process_state)
	set_process_input(_saved_input_state)
	set_process_unhandled_input(_saved_unhandled_input_state)
	set_process_unhandled_key_input(_saved_unhandled_key_input_state)
	_fit_board()
	_update_status("已返回工作台，可继续编辑")
