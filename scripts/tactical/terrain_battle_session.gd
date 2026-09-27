extends "res://scripts/ui/playground/battlefield_courtyard.gd"
## 正式 TacticalScene 的自定义地形入口，复用已批准的显示、遮挡及战斗操作。

signal editing_resumed

const Definition := preload("res://scripts/ui/terrain/terrain_battle_definition.gd")
var _configured_map: Dictionary = {}
var _closing := false
var _restarting := false


func configure_map(source: Dictionary) -> Dictionary:
	if is_inside_tree():
		return {"ok": false, "message": "战斗开始后不能替换地图，请先返回编辑。"}
	var result := Definition.build(source)
	if result["ok"]:
		_configured_map = result["map"].duplicate(true)
	return {"ok": result["ok"], "message": result["message"]}


func _ready() -> void:
	if _configured_map.is_empty():
		push_error("TerrainBattleSession requires a validated map before entering the tree.")
		return
	visual_profile = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	layouts = {"workshop": _configured_map}
	_build_overlay()
	get_viewport().size_changed.connect(_resize)
	await select_layout("workshop")


func _register_current_map() -> void:
	# 只向正式场景注入独立地图副本，不覆盖同名内置地图。
	_active_map_id = str(current_layout_data["id"])


func _create_battle() -> void:
	super._create_battle()
	if battle.return_button.pressed.is_connected(_on_restart_pressed):
		battle.return_button.pressed.disconnect(_on_restart_pressed)
	battle.return_button.text = "返回编辑"
	battle.return_button.pressed.connect(request_return)


func _destroy_battle() -> void:
	if is_instance_valid(battle):
		battle.tactical_manager.stop_battle()
	super._destroy_battle()


func _build_overlay() -> void:
	super._build_overlay()
	# 沿用相同工具栏样式，仅提供当前地图所需的操作。
	for child: Node in _buttons.get_children():
		child.free()
	_layout_buttons.clear()
	_add_button("返回编辑", request_return)
	_add_button("重新试战", _on_restart_pressed)
	_add_button("居中", fit_board)
	var grid_button := _add_button("格线", _toggle_session_grid)
	grid_button.toggle_mode = true
	grid_button.button_pressed = _grid_shown
	_range_button = _add_button("范围", _toggle_ranges)
	_range_button.toggle_mode = true
	_range_button.button_pressed = _ranges_shown
	_tooltip_button = _add_button("地形提示", _toggle_tooltip)
	_tooltip_button.toggle_mode = true
	_tooltip_button.button_pressed = _tooltip_enabled


func _toggle_session_grid() -> void:
	_grid_shown = not _grid_shown
	if is_instance_valid(board_view):
		board_view.grid_visible = _grid_shown
		board_view.queue_redraw()


func _on_restart_pressed() -> void:
	if _closing or _restarting:
		return
	_restarting = true
	await select_layout("workshop")
	_restarting = false


func request_return() -> void:
	if _closing:
		return
	_closing = true
	if is_instance_valid(battle):
		battle.tactical_manager.stop_battle()
	process_mode = Node.PROCESS_MODE_DISABLED
	editing_resumed.emit()


func fit_board() -> void:
	if camera == null or manager == null:
		return
	var size := get_viewport_rect().size
	var factor := minf(size.x / 1280.0, size.y / 720.0)
	var usable := Rect2(Vector2(30, 132) * factor, Vector2(size.x - 260 * factor, size.y - 352 * factor))
	var span := float(manager.grid.width + manager.grid.height)
	var extent := Vector2(span * 32.0, span * 16.0 + 80.0)
	_fit_zoom = minf(float(visual_profile["board_zoom"]) * factor,
		minf(usable.size.x / extent.x, usable.size.y / extent.y))
	camera.zoom = Vector2.ONE * maxf(_fit_zoom, 0.1)
	var center: Vector2 = (manager.grid.grid_to_world(Vector2i.ZERO)
		+ manager.grid.grid_to_world(Vector2i(manager.grid.width - 1, manager.grid.height - 1))) * 0.5
	center.y -= 40.0
	camera.position = center - (usable.get_center() - size * 0.5) / camera.zoom.x
	camera.force_update_scroll()


func _terrain_description(cell: Cell) -> String:
	var catalog: Dictionary = Definition.Catalog.catalog()
	var title := str(catalog["terrains"][str(cell.terrain)]["name"])
	if cell.terrain == Cell.Terrain.WALL:
		var variant: String = board_view.visual_variant_at(cell.position)
		title = str({"dressed": "砌石墙", "ruined": "残墙", "pillar": "石柱"}.get(variant, title))
	if not cell.is_passable():
		return "%s · 当前职业不可通行\n不阻挡攻击线" % title
	var description := "%s · 移动消耗 %d" % [title, cell.get_move_cost()]
	if cell.get_evade_bonus() > 0:
		description += " · 提高闪避"
	return description
