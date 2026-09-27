extends Node2D
## 可独立打开的战场候选，复用正式场景、寻路、行动和已定版 HUD。

const LAYOUTS_PATH := "res://assets/prototype/battlefield_courtyard/courtyard_layouts.json"
const PROFILE_PATH := "res://assets/prototype/battlefield_courtyard/visual_profile.json"
const LAYOUT_ORDER: Array[String] = ["overgrown", "flooded", "passage"]
const BOARD_HALF_TILE := Vector2(32.0, 16.0)
const UNIT_HEADROOM := 52.0
const WHEEL_ZOOM_FACTOR := 1.12
const MIN_FIT_ZOOM_FACTOR := 0.75
const MAX_FIT_ZOOM_FACTOR := 1.45
const BoardView := preload("res://scripts/ui/playground/courtyard_board_view.gd")
const TacticalScene := preload("res://scenes/tactical/TacticalScene.tscn")
const HudTheme := preload("res://assets/ui/themes/hud_m2.tres")

@export var layout_id: String = "overgrown"

var battle: Node2D
var board_view: Node2D
var manager: Variant
var camera: Camera2D
var visual_profile: Dictionary = {}
var layouts: Dictionary = {}
var current_layout_id: String = ""
var current_layout_data: Dictionary = {}

var _overlay: Control
var _tooltip: PanelContainer
var _tooltip_text: Label
var _buttons: HBoxContainer
var _title: Label
var _description: Label
var _layout_button_group: ButtonGroup
var _layout_buttons: Dictionary = {}
var _range_button: Button
var _tooltip_button: Button
var _map_snapshots: Dictionary = {}
var _active_map_id: String = ""
var _graybox: bool = false
var _grid_shown: bool = true
var _ranges_shown: bool = true
var _tooltip_enabled: bool = true
var _fit_zoom: float = 0.0


func _ready() -> void:
	var layouts_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUTS_PATH))
	var profile_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if not (layouts_value is Dictionary) or not (profile_value is Dictionary):
		push_error("[BattlefieldCourtyard] Failed to load courtyard layouts or visual profile")
		return
	layouts = layouts_value
	visual_profile = profile_value
	_build_overlay()
	get_viewport().size_changed.connect(_resize)
	await select_layout(layout_id)


## 切换场景时释放旧战斗、恢复该地图原有注册，再将新地图临时注册并重建战斗。
## 函数包含帧等待，调用方可 await，以便在重建后的节点进入稳定帧后继续操作。
func select_layout(id: String) -> void:
	if not layouts.has(id) or not (layouts[id] is Dictionary):
		push_warning("[BattlefieldCourtyard] Unknown layout: " + id)
		return
	_destroy_battle()
	_restore_active_map()
	current_layout_id = id
	current_layout_data = (layouts[id] as Dictionary).duplicate(true)
	_register_current_map()
	_create_battle()
	_update_scene_labels()
	_refresh_layout_buttons()
	_resize()
	await get_tree().process_frame


func _register_current_map() -> void:
	_active_map_id = str(current_layout_data.get("id", ""))
	if _active_map_id.is_empty():
		push_error("[BattlefieldCourtyard] Layout has no map id: " + current_layout_id)
		return
	if not _map_snapshots.has(_active_map_id):
		_map_snapshots[_active_map_id] = {
			"existed": DataLoader.maps.has(_active_map_id),
			"value": DataLoader.maps.get(_active_map_id),
		}
	DataLoader.maps[_active_map_id] = current_layout_data


func _restore_active_map() -> void:
	if _active_map_id.is_empty() or not _map_snapshots.has(_active_map_id):
		_active_map_id = ""
		return
	var snapshot: Dictionary = _map_snapshots[_active_map_id]
	if bool(snapshot["existed"]):
		DataLoader.maps[_active_map_id] = snapshot["value"]
	else:
		DataLoader.maps.erase(_active_map_id)
	_active_map_id = ""


func _create_battle() -> void:
	battle = TacticalScene.instantiate()
	battle.run_injected = true
	battle.debug_harness_enabled = false
	battle.injected_map_id = _active_map_id
	battle.injected_map_data = current_layout_data.duplicate(true)
	battle.injected_player_units = _spawns(current_layout_data["player_units"])
	battle.injected_enemy_units = _spawns(current_layout_data["enemy_units"])
	add_child(battle)
	battle.battle_ended.connect(_on_battle_ended)
	battle.return_button.pressed.connect(_on_restart_pressed)
	battle.return_button.text = "重新开始"
	manager = battle.tactical_manager
	manager.terrain_layer.hide()
	manager.highlight_layer.visible = _ranges_shown
	board_view = BoardView.new()
	board_view.name = "CourtyardBoardView"
	board_view.configure(manager.grid, visual_profile, current_layout_data)
	board_view.grid_visible = _grid_shown
	board_view.graybox = _graybox
	manager.add_child(board_view)
	manager.move_child(board_view, 0)
	for highlight: Node in manager.highlight_layer.get_children():
		_style_highlight(highlight)
	manager.highlight_layer.child_entered_tree.connect(_style_highlight)
	for unit: Unit in manager.units:
		_style_unit_marker(unit)
	# 可行走外形与单位仍使用相同的 Grid 坐标，装饰不进入寻路。
	camera = battle.get("_camera") as Camera2D
	var backdrop: ColorRect = battle.get_node("BattlefieldBackdrop/Ground") as ColorRect
	backdrop.color = Color(str(visual_profile["backdrop_color"]))


func _destroy_battle() -> void:
	if not is_instance_valid(battle):
		battle = null
		manager = null
		board_view = null
		camera = null
		return
	var old_battle: Node2D = battle
	battle = null
	manager = null
	board_view = null
	camera = null
	remove_child(old_battle)
	old_battle.free()


func _style_highlight(node: Node) -> void:
	# 保留正式范围与语义；这里只降低重复格边的视觉强度。
	if node is Polygon2D and node.color == manager.HIGHLIGHT_MOVE_FILL:
		node.color = Color(0.28, 0.57, 0.72, 0.18)
	elif node is Line2D and node.default_color == manager.HIGHLIGHT_MOVE_BORDER:
		node.default_color = Color(0.48, 0.81, 0.94, 0.72)
		node.width = 0.8


func _style_unit_marker(unit: Unit) -> void:
	# 本阶段保留已有职业文字棋子，统一缩小血条，避免测试方块吞没相邻格。
	unit.sprite.scale = Vector2(0.42, 0.42)
	unit.sprite.self_modulate = Color("315670") if unit.faction == "player" else Color("713e43")
	var label: Label = unit.get_node_or_null("UnitLabel") as Label
	if label != null:
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_constant_override("outline_size", 1)
		label.position = Vector2(-27, -15)
		label.size = Vector2(54, 30)
	unit.health_bar.position = Vector2(-19, -28)
	unit.health_bar.size = Vector2(38, 5)
	unit.health_bar.custom_minimum_size = Vector2(38, 5)
	var hp_label: Label = unit.get_node("HPLabel") as Label
	hp_label.position = Vector2(-24, -43)
	hp_label.size = Vector2(48, 13)
	hp_label.add_theme_font_size_override("font_size", 10)
	unit._update_health_bar()
	# 占格底座将人物落点与等距格心联系起来；颜色并非唯一阵营提示。
	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([Vector2(0, -8), Vector2(20, 2), Vector2(0, 12), Vector2(-20, 2)])
	base.color = Color("83bad25c") if unit.faction == "player" else Color("d39a8c5c")
	base.show_behind_parent = true
	unit.add_child(base)
	unit.move_child(base, 0)


func _exit_tree() -> void:
	if get_viewport().size_changed.is_connected(_resize):
		get_viewport().size_changed.disconnect(_resize)
	_destroy_battle()
	_restore_active_map()


func _spawns(records: Array) -> Array:
	var result: Array = []
	for record: Dictionary in records:
		var pos: Array = record["position"]
		result.append({"class_id": record["class_id"], "pos": Vector2i(pos[0], pos[1]), "facing": &"NE"})
	return result


func _resize() -> void:
	if _overlay != null:
		var viewport_size: Vector2 = get_viewport_rect().size
		var factor: float = minf(viewport_size.x / 1280.0, viewport_size.y / 720.0)
		_overlay.scale = Vector2.ONE * factor
	if not is_instance_valid(battle) or camera == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var factor: float = minf(viewport_size.x / 1280.0, viewport_size.y / 720.0)
	var turn_bar: Control = battle.get("_turn_order_bar") as Control
	turn_bar.scale = Vector2.ONE * factor
	turn_bar.position = Vector2(viewport_size.x - 200.0 * factor, 16.0 * factor)
	fit_board()


func fit_board() -> void:
	if camera == null or manager == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var factor: float = minf(viewport_size.x / 1280.0, viewport_size.y / 720.0)
	var zoom_value: float = float(visual_profile["board_zoom"]) * factor
	_fit_zoom = zoom_value
	camera.zoom = Vector2.ONE * zoom_value
	var target: Array = visual_profile["board_screen_center"]
	var screen_target := Vector2(viewport_size.x * 0.5 + (float(target[0]) - 640.0) * factor, float(target[1]) * factor)
	var grid_center: Vector2 = (manager.grid.grid_to_world(Vector2i.ZERO)
		+ manager.grid.grid_to_world(Vector2i(manager.grid.width - 1, manager.grid.height - 1))) * 0.5
	camera.position = grid_center - (screen_target - viewport_size * 0.5) / zoom_value
	camera.force_update_scroll()


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 12
	add_child(layer)
	_overlay = Control.new()
	_overlay.theme = HudTheme
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_overlay)
	_title = Label.new()
	_title.position = Vector2(34, 22)
	_title.add_theme_font_size_override("font_size", 25)
	_title.add_theme_color_override("font_color", Color("ddc99d"))
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_title)
	_description = Label.new()
	_description.position = Vector2(36, 58)
	_description.add_theme_font_size_override("font_size", 13)
	_description.add_theme_color_override("font_color", Color("aaa89e"))
	_description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_description)
	_buttons = HBoxContainer.new()
	_buttons.position = Vector2(34, 90)
	_buttons.add_theme_constant_override("separation", 5)
	_overlay.add_child(_buttons)
	var scene_label := Label.new()
	scene_label.text = "场景"
	scene_label.custom_minimum_size.y = 30
	scene_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	scene_label.add_theme_font_size_override("font_size", 13)
	scene_label.add_theme_color_override("font_color", Color("cfc8b5"))
	_buttons.add_child(scene_label)
	_layout_button_group = ButtonGroup.new()
	for id: String in LAYOUT_ORDER:
		var data: Dictionary = layouts.get(id, {})
		var button := _add_button(str(data.get("name", id)), _on_layout_button_pressed.bind(id))
		button.toggle_mode = true
		button.button_group = _layout_button_group
		button.custom_minimum_size.x = 86
		_layout_buttons[id] = button
	var divider := VSeparator.new()
	divider.custom_minimum_size.x = 8
	_buttons.add_child(divider)
	var view_label := Label.new()
	view_label.text = "视图"
	view_label.custom_minimum_size.y = 30
	view_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	view_label.add_theme_font_size_override("font_size", 13)
	view_label.add_theme_color_override("font_color", Color("cfc8b5"))
	_buttons.add_child(view_label)
	var grid_button: Button = _add_button("格线", func() -> void:
		_grid_shown = not _grid_shown
		if board_view != null:
			board_view.grid_visible = _grid_shown
			board_view.queue_redraw())
	grid_button.toggle_mode = true
	grid_button.button_pressed = _grid_shown
	_range_button = _add_button("范围", _toggle_ranges)
	_range_button.toggle_mode = true
	_range_button.button_pressed = _ranges_shown
	_tooltip_button = _add_button("提示", _toggle_tooltip)
	_tooltip_button.toggle_mode = true
	_tooltip_button.button_pressed = _tooltip_enabled
	var graybox_button: Button = _add_button("灰盒", func() -> void:
		_graybox = not _graybox
		if board_view != null:
			board_view.graybox = _graybox
			board_view.queue_redraw())
	graybox_button.toggle_mode = true
	_add_button("居中", fit_board)
	_add_button("重开", _on_restart_pressed)
	_tooltip = PanelContainer.new()
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.visible = false
	_tooltip.custom_minimum_size.x = 236
	var style := StyleBoxFlat.new()
	style.bg_color = Color("171c23f2")
	style.border_color = Color("a58b60")
	style.set_border_width_all(1)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	_tooltip.add_theme_stylebox_override("panel", style)
	_tooltip_text = Label.new()
	_tooltip_text.custom_minimum_size.x = 210
	_tooltip_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip_text.add_theme_font_size_override("font_size", 15)
	_tooltip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_child(_tooltip_text)
	_overlay.add_child(_tooltip)
	_update_scene_labels()


func _add_button(text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 30
	button.add_theme_font_size_override("font_size", 13)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("302e29") if state == "pressed" else Color("1a2027")
		style.border_color = Color("ab9166") if state != "normal" else Color("4e514f")
		style.set_border_width_all(1)
		style.content_margin_left = 10
		style.content_margin_right = 10
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(callback)
	_buttons.add_child(button)
	return button


func _on_layout_button_pressed(id: String) -> void:
	await select_layout(id)


func _on_restart_pressed() -> void:
	await select_layout(current_layout_id)


func _on_battle_ended(result: String) -> void:
	if is_instance_valid(battle):
		battle.result_label.text = "胜利" if result == "victory" else "战败"


func _toggle_ranges() -> void:
	_ranges_shown = not _ranges_shown
	if _range_button != null and _range_button.button_pressed != _ranges_shown:
		_range_button.button_pressed = _ranges_shown
	if manager != null:
		manager.highlight_layer.visible = _ranges_shown


func _toggle_tooltip() -> void:
	_tooltip_enabled = not _tooltip_enabled
	if _tooltip_button != null and _tooltip_button.button_pressed != _tooltip_enabled:
		_tooltip_button.button_pressed = _tooltip_enabled
	if not _tooltip_enabled and _tooltip != null:
		_tooltip.hide()


func _update_scene_labels() -> void:
	if _title == null or current_layout_data.is_empty():
		return
	_title.text = str(current_layout_data.get("name", current_layout_id))
	_description.text = str(current_layout_data.get("description", ""))


func _refresh_layout_buttons() -> void:
	for id_value: Variant in _layout_buttons.keys():
		var button: Button = _layout_buttons[id_value]
		button.button_pressed = str(id_value) == current_layout_id


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event: InputEventMouseButton = event
	if not mouse_event.pressed or mouse_event.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return
	if camera == null or manager == null or _wheel_is_over_ui(mouse_event.position):
		return
	if _fit_zoom <= 0.0:
		return
	var viewport: Viewport = get_viewport()
	var mouse_screen: Vector2 = mouse_event.position
	var world_before: Vector2 = viewport.get_canvas_transform().affine_inverse() * mouse_screen
	var zoom_factor: float = WHEEL_ZOOM_FACTOR if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / WHEEL_ZOOM_FACTOR
	var next_zoom: float = clampf(camera.zoom.x * zoom_factor,
		_fit_zoom * MIN_FIT_ZOOM_FACTOR, _fit_zoom * MAX_FIT_ZOOM_FACTOR)
	if is_equal_approx(next_zoom, camera.zoom.x):
		viewport.set_input_as_handled()
		return
	camera.zoom = Vector2.ONE * next_zoom
	camera.force_update_scroll()
	var world_after: Vector2 = viewport.get_canvas_transform().affine_inverse() * mouse_screen
	camera.global_position += world_before - world_after
	camera.force_update_scroll()
	viewport.set_input_as_handled()


func _wheel_is_over_ui(mouse_screen: Vector2) -> bool:
	if get_viewport().gui_get_hovered_control() != null:
		return true
	if _buttons == null:
		return false
	for child: Node in _buttons.get_children():
		if child is Button and child.is_visible_in_tree() \
				and (child as Button).get_global_rect().has_point(mouse_screen):
			return true
	return false


func _process(_delta: float) -> void:
	if manager == null or _tooltip == null:
		return
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var blocked_by_ui: bool = get_viewport().gui_get_hovered_control() != null
	var world: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * mouse
	var pos: Vector2i = manager.grid.world_to_grid(world)
	var visibility_cell: Vector2i = pos if not blocked_by_ui and manager.grid.is_valid(pos) else Vector2i(-1, -1)
	_update_board_visibility_context(visibility_cell)
	if not _tooltip_enabled:
		_tooltip.hide()
		return
	if blocked_by_ui or not manager.grid.is_valid(pos) or manager.grid.get_unit_at(pos) != null or manager.is_targeting_active():
		_tooltip.hide()
		return
	var cell: Cell = manager.grid.get_cell(pos)
	_tooltip_text.text = _terrain_description(cell)
	_tooltip.reset_size()
	if _position_tooltip(mouse):
		_tooltip.show()
	else:
		_tooltip.hide()


func _update_board_visibility_context(hover_cell: Vector2i) -> void:
	if board_view == null or not board_view.has_method("update_visibility_context"):
		return
	var unit_positions: Array[Vector2] = []
	for unit: Unit in manager.units:
		if is_instance_valid(unit):
			unit_positions.append(unit.global_position)
	# 消费实际显示的范围，不复制移动或技能规则。
	var highlight_positions: Array[Vector2] = []
	if manager.highlight_layer.visible:
		for highlight: Node in manager.highlight_layer.get_children():
			if highlight is Polygon2D and not highlight.is_queued_for_deletion() and highlight.is_visible_in_tree():
				var polygon: PackedVector2Array = highlight.polygon
				if polygon.size() == 4:
					var center := Vector2.ZERO
					for corner: Vector2 in polygon:
						center += corner * 0.25
					highlight_positions.append(highlight.to_global(center))
	board_view.call("update_visibility_context", hover_cell, unit_positions, highlight_positions)


func _terrain_description(cell: Cell) -> String:
	var move_cost: int = cell.get_move_cost()
	var modifiers: Dictionary = cell.get_combat_modifiers()
	match cell.terrain:
		Cell.Terrain.PLAIN:
			return "平原 · 移动消耗 %d" % move_cost
		Cell.Terrain.FOREST:
			var evasion_hint: String = " · 提高闪避" if int(modifiers.get("evade_bonus", 0)) > 0 else ""
			return "森林 · 移动消耗 %d%s" % [move_cost, evasion_hint]
		Cell.Terrain.SHALLOW_WATER:
			return "浅水 · 移动消耗 %d" % move_cost
		Cell.Terrain.DEEP_WATER:
			return "深水 · 不可通行\n不阻挡攻击线"
		Cell.Terrain.WALL:
			return "墙（残墙） · 不可通行\n不阻挡攻击线"
		_:
			if cell.is_passable():
				return "%s · 移动消耗 %d" % [Cell.get_terrain_name(cell.terrain), move_cost]
			return "%s · 不可通行\n不阻挡攻击线" % Cell.get_terrain_name(cell.terrain)


func _position_tooltip(mouse_screen: Vector2) -> bool:
	if camera == null or _overlay == null:
		return false
	_tooltip.reset_size()
	var viewport_size: Vector2 = get_viewport_rect().size
	var factor: float = minf(viewport_size.x / 1280.0, viewport_size.y / 720.0)
	if factor <= 0.0:
		return false
	var tooltip_size: Vector2 = _tooltip.size * factor
	var board_rect: Rect2 = _board_screen_rect()
	var gap: float = 14.0 * factor
	var left_space: float = board_rect.position.x - gap
	var right_start: float = board_rect.end.x + gap
	var fits_left: bool = tooltip_size.x <= left_space
	var fits_right: bool = right_start + tooltip_size.x <= viewport_size.x
	if not fits_left and not fits_right:
		return false
	var x_screen: float = board_rect.position.x - gap - tooltip_size.x if fits_left else right_start
	var min_y: float = 136.0 * factor
	var max_y: float = viewport_size.y - 220.0 * factor - tooltip_size.y
	if max_y < min_y:
		return false
	var y_screen: float = clampf(mouse_screen.y - tooltip_size.y * 0.5, min_y, max_y)
	_tooltip.position = Vector2(x_screen / factor, y_screen / factor)
	return true


func _board_screen_rect() -> Rect2:
	var grid: Grid = manager.grid
	var transform: Transform2D = get_viewport().get_canvas_transform()
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	var half_tile: Vector2 = BOARD_HALF_TILE * camera.zoom.x
	var headroom: float = UNIT_HEADROOM * camera.zoom.y
	for y: int in grid.height:
		for x: int in grid.width:
			var center: Vector2 = transform * grid.grid_to_world(Vector2i(x, y))
			min_point.x = minf(min_point.x, center.x - half_tile.x)
			max_point.x = maxf(max_point.x, center.x + half_tile.x)
			min_point.y = minf(min_point.y, center.y - half_tile.y - headroom)
			max_point.y = maxf(max_point.y, center.y + half_tile.y)
	return Rect2(min_point, max_point - min_point)
