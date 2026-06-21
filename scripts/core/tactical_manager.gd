class_name TacticalManager
extends Node

@onready var turn_manager: TurnManager = $TurnManager
@onready var terrain_layer: Node2D = $TerrainLayer
@onready var highlight_layer: Node2D = $HighlightLayer
@onready var popup_layer: Node2D = $PopupLayer

var grid: Grid = Grid.new()
var units: Array = []
var battle_active: bool = false

signal battle_started
signal unit_killed(unit: Unit)
signal dashboard_state_changed

enum InputState {
	IDLE,
	MOVE_PHASE,
	ACTION_PHASE,
	SKILL_TARGETING,
	ATTACK_TARGETING,
	SWIFT_PHASE,
	ANIMATING,
}
const ATTACK_MODE_BASIC: String = "attack"
const ATTACK_MODE_SKILL: String = "skill"

var input_state: InputState = InputState.IDLE
var current_unit: Unit = null
var selected_unit: Unit = null
var _move_range: Dictionary = {}
var _range_display_cells: Array[Vector2i] = []
var _attack_cells: Array[Vector2i] = []
var _area_preview_cells: Array[Vector2i] = []
var _direction_selector_cells: Array[Vector2i] = []
var _path_preview: Array[Vector2i] = []
var _hover_cell: Vector2i = Vector2i.ZERO
var _has_hover_cell: bool = false
var _attack_mode: String = ATTACK_MODE_BASIC
var _selected_skill_id: String = ""
var _targeting_direction: Vector2i = Vector2i.ZERO
var _skill_bar_expanded: bool = false
var _inspected_unit: Unit = null
var _pre_move_position: Vector2i = Vector2i.ZERO
var _move_committed: bool = false
var _combat_forecast: Dictionary = {}
var _targeting_origin_state: InputState = InputState.IDLE


func _ready() -> void:
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.turn_ended.connect(_on_turn_ended)
	turn_manager.round_ended.connect(_on_round_ended)


# ── Public API (called by tactical_scene.gd) ─────────

func initialize_battle(map_id: String) -> void:
	var map_data: Dictionary = DataLoader.maps.get(map_id, {})
	if map_data.is_empty():
		push_error("[TacticalManager] Map not found: " + map_id)
		return
	grid.initialize(map_data)
	_render_terrain()
	battle_started.emit()


func start_battle() -> void:
	battle_active = true
	var typed_units: Array[Unit] = []
	for u in units:
		typed_units.append(u)
	turn_manager.add_units(typed_units)
	turn_manager.start()


func stop_battle() -> void:
	battle_active = false
	turn_manager.stop()
	_clear_hover_state()
	_clear_highlights()
	_clear_dashboard_state()
	_emit_dashboard_state_changed()


func get_selected_skill_id() -> String:
	return _selected_skill_id


func get_dashboard_data() -> Dictionary:
	var info_unit: Unit = _get_dashboard_unit()
	if info_unit == null:
		return {"visible": false}

	var is_enemy_info: bool = _is_enemy_info_mode()
	return {
		"visible": true,
		"mode": "enemy" if is_enemy_info else "player",
		"unit_name": info_unit.unit_name,
		"unit_label": info_unit.get_short_label(),
		"hp": info_unit.stats.hp,
		"hp_max": info_unit.stats.max_hp,
		"hp_ratio": float(info_unit.stats.hp) / maxf(1.0, float(info_unit.stats.max_hp)),
		"status_text": info_unit.get_action_status_summary(),
		"phase_text": _get_phase_text(),
		"show_actions": not is_enemy_info and _is_player_turn_active(),
		"buttons": _build_primary_button_state(),
		"skills_visible": _skill_bar_expanded and not is_enemy_info and _is_player_turn_active(),
		"skills": _get_skill_entries(),
		"selected_skill_id": _selected_skill_id,
		"forecast": _combat_forecast.duplicate(true),
		"hint_text": _get_dashboard_hint_text(),
		# ── 主属性面板：基础值 + 括号加成（stats_delta=生效−基础，含印记/心眼/buff）──
		"stats": {
			"str": info_unit.stats.str_attr, "mag": info_unit.stats.mag,
			"dex": info_unit.stats.dex, "spd": info_unit.stats.spd,
			"def": info_unit.stats.def_attr, "res": info_unit.stats.res,
			"lck": info_unit.stats.lck, "mov": info_unit.stats.mov,
		},
		"stats_delta": {
			"str": info_unit.get_effective_stat("STR") - info_unit.stats.str_attr,
			"mag": info_unit.get_effective_stat("MAG") - info_unit.stats.mag,
			"dex": info_unit.get_effective_stat("DEX") - info_unit.stats.dex,
			"spd": info_unit.get_effective_stat("SPD") - info_unit.stats.spd,
			"def": info_unit.get_effective_stat("DEF") - info_unit.stats.def_attr,
			"res": info_unit.get_effective_stat("RES") - info_unit.stats.res,
			"lck": info_unit.get_effective_stat("LCK") - info_unit.stats.lck,
			"mov": info_unit.get_effective_stat("MOV") - info_unit.stats.mov,
		},
		# ── 剑圣专属资源（非剑圣单位：sword_qi=-1 隐藏显示）──
		"sword_qi": info_unit.sword_qi if info_unit._qi_max > 0 else -1,
		"sword_qi_max": info_unit._qi_max,
		"marks": info_unit.marks.duplicate() if info_unit._qi_max > 0 else {},
	}


func request_skill_selection(skill_id: String) -> void:
	var unit: Unit = _get_player_dashboard_unit()
	if unit == null:
		return
	if _selected_skill_id == skill_id and input_state == InputState.SKILL_TARGETING:
		_cancel_targeting()
		return

	var skill_data: Dictionary = _get_skill_data(skill_id)
	var entry: Dictionary = _build_skill_entry(unit, skill_id)
	if not bool(entry.get("available", false)):
		print("[Skill] %s unavailable: %s" % [skill_id, str(entry.get("reason", ""))])
		return
	var validation: Dictionary = GameAction.validate_skill_usage(unit, skill_data)
	if not bool(validation.get("ok", false)):
		print("[Skill] %s unavailable: %s" % [skill_id, str(validation.get("reason", ""))])
		return

	_selected_skill_id = skill_id
	_skill_bar_expanded = true
	_clear_targeting_buffers()
	var range_data: Dictionary = skill_data.get("range", {})
	if str(range_data.get("type", "")) == "self":
		var action: GameAction = _build_skill_action(
			unit, unit.grid_position, grid.get_unit_at(unit.grid_position))
		if action != null:
			_execute_skill_from_input(action)
		return

	_targeting_origin_state = input_state
	input_state = InputState.SKILL_TARGETING
	_attack_mode = ATTACK_MODE_SKILL
	_refresh_attack_cells()
	_recalculate_hover_artifacts()
	_show_attack_highlights()
	_emit_dashboard_state_changed()


func request_end_turn() -> void:
	if not _is_player_turn_active():
		return
	_end_player_turn()


func request_attack_targeting() -> void:
	if not _can_enter_attack_targeting():
		return
	_inspected_unit = null
	_skill_bar_expanded = false
	_selected_skill_id = ""
	_clear_targeting_buffers()
	_attack_mode = ATTACK_MODE_BASIC
	_targeting_origin_state = input_state
	input_state = InputState.ATTACK_TARGETING
	_refresh_attack_cells()
	_recalculate_hover_artifacts()
	_show_attack_highlights()
	_emit_dashboard_state_changed()


func request_toggle_skill_bar() -> void:
	if not _is_player_turn_active():
		return
	_inspected_unit = null
	_skill_bar_expanded = not _skill_bar_expanded
	_emit_dashboard_state_changed()


func request_end_move() -> void:
	if input_state != InputState.MOVE_PHASE:
		return
	if current_unit == null:
		return
	_complete_move_phase(false)


func request_cancel_action() -> void:
	_handle_cancel_action()


func handle_pointer_hover(screen_pos: Vector2) -> void:
	if not battle_active:
		return
	if current_unit == null or current_unit.faction != "player":
		return
	if input_state == InputState.ANIMATING:
		return
	var world_pos: Vector2 = _screen_to_world(screen_pos)
	_update_hover(grid.world_to_grid(world_pos))


func handle_pointer_click(screen_pos: Vector2) -> void:
	if not battle_active:
		return
	if current_unit == null or current_unit.faction != "player":
		return
	if input_state == InputState.ANIMATING:
		return
	var world_pos: Vector2 = _screen_to_world(screen_pos)
	var grid_pos: Vector2i = grid.world_to_grid(world_pos)
	_handle_click(grid_pos)


func spawn_unit(class_id: String, spawn_pos: Vector2i,
				faction: String) -> Unit:
	var class_data: Dictionary = DataLoader.classes.get(class_id, {})
	if class_data.is_empty():
		class_data = DataLoader.enemies.get(class_id, {})
	if class_data.is_empty():
		push_error("[TacticalManager] Class/enemy not found: " + class_id)
		return null
	var unit_scene := preload("res://scenes/tactical/Unit.tscn")
	var unit: Unit = unit_scene.instantiate()
	unit.faction = faction
	add_child(unit)
	unit.setup(class_data)
	unit.position = grid.grid_to_world(spawn_pos)
	grid.place_unit(unit, spawn_pos)
	units.append(unit)
	unit.unit_died.connect(_on_unit_died.bind(unit))
	return unit


func _on_unit_died(unit: Unit) -> void:
	print("[TacticalManager] %s (%s) died at %s | HP=%d" % [
		unit.unit_name, unit.faction, unit.grid_position, unit.stats.hp])
	grid.remove_unit(unit)
	units.erase(unit)
	var was_active := (turn_manager.current_unit == unit)
	turn_manager.remove_unit(unit)
	if was_active:
		_deselect_unit()
	unit_killed.emit(unit)
	if was_active and battle_active:
		turn_manager.force_advance.call_deferred()


# ── Turn callbacks ───────────────────────────────────

func _on_turn_started(unit: Unit) -> void:
	if not battle_active:
		return
	current_unit = unit
	unit.reset_turn_state()
	var turn_start_result: Dictionary = unit.process_turn_start_buffs()
	if not battle_active or turn_manager.current_unit != unit:
		return
	if not unit.stats.is_alive():
		return
	print("[TurnManager] Turn: %s (%s)" % [unit.unit_name, unit.faction])
	if bool(turn_start_result.get("skip_turn", false)):
		print("[Buff] %s skips turn due to control effect" % unit.unit_name)
		if unit.faction != "player":
			_clear_hover_state()
			_clear_dashboard_state()
			_emit_dashboard_state_changed()
		else:
			_deselect_unit()
		turn_manager.end_current_turn.call_deferred()
		return
	if unit.faction != "player":
		_clear_hover_state()
		_clear_dashboard_state()
		_emit_dashboard_state_changed()
		_do_enemy_turn(unit)
	else:
		_prepare_player_turn(unit)


func _on_turn_ended(unit: Unit) -> void:
	unit.process_turn_end_buffs()
	_deselect_unit()


func _on_round_ended() -> void:
	print("[TurnManager] === Round ended ===")


func _do_enemy_turn(unit: Unit) -> void:
	await get_tree().create_timer(0.3).timeout
	if not battle_active or turn_manager.current_unit != unit:
		return

	var actions: Array[GameAction] = EnemyAI.decide_actions(unit, grid, units)

	if actions.is_empty():
		print("[AI] %s: no actions (idle)" % unit.unit_name)

	for action in actions:
		if not battle_active or turn_manager.current_unit != unit:
			break
		if not unit.stats.is_alive():
			break
		match action.type:
			GameAction.Type.MOVE:
				var from := unit.grid_position
				var move_check: Dictionary = GameAction.can_use_normal_move(unit)
				if not bool(move_check.get("ok", false)):
					continue
				print("[AI] %s: move %s → %s" % [
					unit.unit_name, from, action.target_pos])
				GameAction.consume_normal_move(unit)
				unit.refresh_status_icons()
				await unit.move_to(action.target_pos, grid)
				grid.move_unit(unit, from, action.target_pos)
				await get_tree().create_timer(0.15).timeout
			GameAction.Type.ATTACK:
				print("[AI] %s: attack %s" % [
					unit.unit_name, action.target_unit.unit_name])
				_execute_attack_action(action)
			GameAction.Type.SKILL:
				var skill_name := str(action.data.get("skill_name", action.data.get("skill_id", "skill")))
				print("[AI] %s: skill %s" % [unit.unit_name, skill_name])
				_execute_skill_action(action)

	if battle_active and unit.stats.is_alive() \
			and turn_manager.current_unit == unit:
		turn_manager.end_current_turn()


# ── Input handling ───────────────────────────────────

func _input(event: InputEvent) -> void:
	if not battle_active:
		return
	if current_unit == null or current_unit.faction != "player":
		return
	if input_state == InputState.ANIMATING:
		return
	if event.is_action_pressed("ui_left"):
		_move_test_cursor(Vector2i.LEFT)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_right"):
		_move_test_cursor(Vector2i.RIGHT)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_up"):
		_move_test_cursor(Vector2i.UP)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_down"):
		_move_test_cursor(Vector2i.DOWN)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept"):
		if _has_hover_cell and grid.is_valid(_hover_cell):
			_handle_click(_hover_cell)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		_handle_cancel_action()
		get_viewport().set_input_as_handled()
		return


func _unhandled_input(_event: InputEvent) -> void:
	pass


func _handle_click(grid_pos: Vector2i) -> void:
	var unit: Unit = grid.get_unit_at(grid_pos)
	match input_state:
		InputState.IDLE:
			if unit != null and unit.faction == "player" \
					and unit == current_unit:
				_select_unit(unit)
		InputState.MOVE_PHASE:
			if selected_unit == null:
				return
			if unit != null and unit.faction == "enemy":
				_show_enemy_info(unit)
			elif grid_pos == selected_unit.grid_position:
				_complete_move_phase(false)
			elif _move_range.has(grid_pos):
				_execute_move(selected_unit, grid_pos)
		InputState.ACTION_PHASE:
			if unit != null:
				_show_unit_info(unit)
		InputState.SKILL_TARGETING:
			if _is_waiting_for_line_direction():
				if grid_pos in _direction_selector_cells:
					_targeting_direction = RangeCalculator.direction_from_to(
						current_unit.grid_position, grid_pos)
					_refresh_attack_cells()
					_recalculate_hover_artifacts()
					_show_attack_highlights()
					_emit_dashboard_state_changed()
				else:
					_cancel_targeting()
			elif _can_confirm_skill_target(grid_pos):
				var skill_action: GameAction = _build_skill_action(
					current_unit, grid_pos, unit)
				if skill_action != null:
					_execute_skill_from_input(skill_action)
			else:
				_cancel_targeting()
		InputState.ATTACK_TARGETING:
			if unit != null and unit.faction != current_unit.faction \
					and grid_pos in _attack_cells:
				var action: GameAction = GameAction.make_attack(current_unit, unit)
				_execute_attack_from_input(action)
			else:
				_cancel_targeting()
		InputState.SWIFT_PHASE:
			pass


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	return canvas_transform.affine_inverse() * screen_pos


func _select_unit(unit: Unit) -> void:
	selected_unit = unit
	_inspected_unit = null
	_skill_bar_expanded = false
	_attack_mode = ATTACK_MODE_BASIC
	_selected_skill_id = ""
	_clear_targeting_buffers()
	_combat_forecast = {}
	input_state = InputState.MOVE_PHASE
	_pre_move_position = unit.grid_position
	_move_committed = false
	_refresh_move_range(unit)
	_recalculate_hover_artifacts()
	_show_move_highlights()
	_emit_dashboard_state_changed()


func _deselect_unit() -> void:
	selected_unit = null
	input_state = InputState.IDLE
	_move_range = {}
	_clear_targeting_buffers()
	_path_preview = []
	_attack_mode = ATTACK_MODE_BASIC
	_selected_skill_id = ""
	_skill_bar_expanded = false
	_inspected_unit = null
	_move_committed = false
	_combat_forecast = {}
	_clear_hover_state()
	_emit_dashboard_state_changed()


func _enter_attack_select() -> void:
	if not _can_enter_attack_targeting():
		return
	_move_range = {}
	_clear_targeting_buffers()
	input_state = InputState.ATTACK_TARGETING
	_attack_mode = ATTACK_MODE_BASIC
	_selected_skill_id = ""
	_skill_bar_expanded = false
	_refresh_attack_cells()
	_recalculate_hover_artifacts()
	_show_attack_highlights()
	_emit_dashboard_state_changed()


func _end_turn_from_attack_select() -> void:
	_end_player_turn()


# ── Highlight colors（方案B — GBA经典明亮）─────────────

const HIGHLIGHT_MOVE_FILL      := Color(0.24, 0.47, 1.00, 0.35)
const HIGHLIGHT_MOVE_BORDER    := Color(0.40, 0.70, 1.00, 0.90)
const HIGHLIGHT_ATTACK_RANGE_FILL := Color(0.92, 0.18, 0.18, 0.20)
const HIGHLIGHT_ATTACK_RANGE_BORDER := Color(1.00, 0.42, 0.28, 0.90)
const HIGHLIGHT_SUPPORT_RANGE_FILL := Color(0.18, 0.72, 0.28, 0.20)
const HIGHLIGHT_SUPPORT_RANGE_BORDER := Color(0.52, 0.94, 0.56, 0.90)
const HIGHLIGHT_ATTACK_TARGET_FILL := Color(1.00, 0.24, 0.24, 0.40)
const HIGHLIGHT_ATTACK_TARGET_BORDER := Color(1.00, 0.60, 0.36, 0.98)
const HIGHLIGHT_SUPPORT_TARGET_FILL := Color(0.18, 0.78, 0.34, 0.42)
const HIGHLIGHT_SUPPORT_TARGET_BORDER := Color(0.62, 1.00, 0.70, 0.98)
const HIGHLIGHT_AREA_FILL      := Color(1.00, 0.30, 0.22, 0.32)
const HIGHLIGHT_AREA_BORDER    := Color(1.00, 0.65, 0.28, 0.94)
const HIGHLIGHT_SELECTOR_FILL  := Color(0.10, 0.78, 0.88, 0.24)
const HIGHLIGHT_SELECTOR_BORDER := Color(0.52, 0.98, 1.00, 0.96)
const HIGHLIGHT_HOVER_FILL     := Color(1.00, 0.94, 0.24, 0.35)
const HIGHLIGHT_HOVER_BORDER   := Color(1.00, 1.00, 0.60, 0.90)
const PATH_PREVIEW_COLOR       := Color(1.00, 0.98, 0.65, 0.95)
const HIGHLIGHT_BORDER_WIDTH   := 2.0


func _show_move_highlights() -> void:
	_refresh_highlights()


func _show_attack_highlights() -> void:
	_refresh_highlights()


func _add_highlight(cell_pos: Vector2i, fill_color: Color, border_color: Color) -> void:
	var center: Vector2 = grid.grid_to_world(cell_pos)
	var points: PackedVector2Array = _diamond_points(center)

	var poly := Polygon2D.new()
	poly.polygon = points
	poly.color = fill_color
	highlight_layer.add_child(poly)

	var line := Line2D.new()
	line.points = PackedVector2Array([points[0], points[1], points[2], points[3], points[0]])
	line.width = HIGHLIGHT_BORDER_WIDTH
	line.default_color = border_color
	highlight_layer.add_child(line)


func _clear_highlights() -> void:
	for child in highlight_layer.get_children():
		child.queue_free()


func _update_hover(grid_pos: Vector2i) -> void:
	var valid_hover: bool = grid.is_valid(grid_pos)
	if valid_hover and _has_hover_cell and _hover_cell == grid_pos:
		return
	if not valid_hover and not _has_hover_cell and _path_preview.is_empty():
		return
	_has_hover_cell = valid_hover
	if valid_hover:
		_hover_cell = grid_pos
	_recalculate_hover_artifacts()
	_refresh_highlights()


func _clear_hover_state() -> void:
	_has_hover_cell = false
	_path_preview = []
	_area_preview_cells = []
	_refresh_highlights()


func _move_test_cursor(direction: Vector2i) -> void:
	var base: Vector2i
	if _has_hover_cell and grid.is_valid(_hover_cell):
		base = _hover_cell
	elif current_unit != null:
		base = current_unit.grid_position
	else:
		base = Vector2i.ZERO
	var target := base + direction
	target.x = clampi(target.x, 0, grid.width - 1)
	target.y = clampi(target.y, 0, grid.height - 1)
	_update_hover(target)


func _handle_cancel_action() -> void:
	if _inspected_unit != null:
		_inspected_unit = null
		_combat_forecast = {}
		_emit_dashboard_state_changed()
		return
	match input_state:
		InputState.MOVE_PHASE:
			_deselect_unit()
		InputState.ACTION_PHASE:
			if not _move_committed:
				_undo_move()
		InputState.SKILL_TARGETING:
			_cancel_targeting()
		InputState.ATTACK_TARGETING:
			_cancel_targeting()
		InputState.SWIFT_PHASE:
			pass


func _recalculate_hover_artifacts() -> void:
	_path_preview = []
	_combat_forecast = {}
	_area_preview_cells = []
	if not _has_hover_cell or not grid.is_valid(_hover_cell):
		_emit_dashboard_state_changed()
		return
	if input_state == InputState.MOVE_PHASE \
			and selected_unit != null \
			and _move_range.has(_hover_cell):
		_path_preview = Pathfinding.find_path(
			grid, selected_unit.grid_position, _hover_cell, selected_unit.faction)
	elif input_state == InputState.ATTACK_TARGETING:
		_combat_forecast = _build_attack_forecast_for_hover(_hover_cell)
	elif input_state == InputState.SKILL_TARGETING \
			and not _is_waiting_for_line_direction() \
			and _hover_cell in _attack_cells:
		var skill_data: Dictionary = _get_skill_data(_selected_skill_id)
		var area_data: Dictionary = skill_data.get("area", {})
		var area_direction: Vector2i = _get_skill_area_direction(
			current_unit.grid_position, _hover_cell, skill_data)
		_area_preview_cells = AreaCalculator.calculate_cells(
			grid, _hover_cell, area_data, area_direction)
	_emit_dashboard_state_changed()


func _refresh_highlights() -> void:
	_clear_highlights()
	match input_state:
		InputState.MOVE_PHASE:
			for cell_pos: Vector2i in _move_range:
				_add_highlight(cell_pos, HIGHLIGHT_MOVE_FILL, HIGHLIGHT_MOVE_BORDER)
			if _path_preview.size() > 1:
				_add_path_preview(_path_preview)
		InputState.SKILL_TARGETING:
			var range_fill: Color = _get_skill_range_fill_color()
			var range_border: Color = _get_skill_range_border_color()
			var target_fill: Color = _get_skill_target_fill_color()
			var target_border: Color = _get_skill_target_border_color()
			for cell_pos: Vector2i in _direction_selector_cells:
				_add_highlight(
					cell_pos, HIGHLIGHT_SELECTOR_FILL, HIGHLIGHT_SELECTOR_BORDER)
			for cell_pos: Vector2i in _range_display_cells:
				_add_highlight(cell_pos, range_fill, range_border)
			for cell_pos: Vector2i in _attack_cells:
				_add_highlight(cell_pos, target_fill, target_border)
			for cell_pos: Vector2i in _area_preview_cells:
				_add_highlight(cell_pos, HIGHLIGHT_AREA_FILL, HIGHLIGHT_AREA_BORDER)
		InputState.ATTACK_TARGETING:
			for cell_pos: Vector2i in _range_display_cells:
				_add_highlight(
					cell_pos, HIGHLIGHT_ATTACK_RANGE_FILL, HIGHLIGHT_ATTACK_RANGE_BORDER)
			for cell_pos: Vector2i in _attack_cells:
				_add_highlight(
					cell_pos, HIGHLIGHT_ATTACK_TARGET_FILL, HIGHLIGHT_ATTACK_TARGET_BORDER)
	if _has_hover_cell and grid.is_valid(_hover_cell):
		_add_highlight(_hover_cell, HIGHLIGHT_HOVER_FILL, HIGHLIGHT_HOVER_BORDER)


func _add_path_preview(path: Array[Vector2i]) -> void:
	var line := Line2D.new()
	var points: PackedVector2Array = []
	for cell_pos: Vector2i in path:
		points.append(grid.grid_to_world(cell_pos))
	line.points = points
	line.width = 4.0
	line.default_color = PATH_PREVIEW_COLOR
	line.z_index = 5
	highlight_layer.add_child(line)


func _get_attack_range(origin: Vector2i, atk_range: int = 1) -> Array[Vector2i]:
	return RangeCalculator.calculate_cells(grid, origin, {
		"type": "diamond",
		"min": 1,
		"max": atk_range,
	})


func _get_attack_range_band(origin: Vector2i, min_range: int = 1,
		max_range: int = 1) -> Array[Vector2i]:
	return RangeCalculator.calculate_cells(grid, origin, {
		"type": "diamond",
		"min": min_range,
		"max": max_range,
	})


func _refresh_move_range(unit: Unit) -> void:
	_move_range = {}
	if unit == null or unit.movement_used:
		return
	_move_range = Pathfinding.get_move_range(
		grid, unit.grid_position, unit.stats.mov, unit.faction)
	_move_range.erase(unit.grid_position)


func _clear_selected_skill() -> void:
	_selected_skill_id = ""
	_attack_mode = ATTACK_MODE_BASIC
	_clear_targeting_buffers()
	if input_state == InputState.SKILL_TARGETING:
		_refresh_attack_cells()
		_recalculate_hover_artifacts()
		_show_attack_highlights()
	_emit_dashboard_state_changed()


func _clear_targeting_buffers() -> void:
	_range_display_cells = []
	_attack_cells = []
	_area_preview_cells = []
	_direction_selector_cells = []
	_targeting_direction = Vector2i.ZERO


func _restore_action_phase_state() -> void:
	if current_unit == null or turn_manager.current_unit != current_unit:
		return
	if not current_unit.stats.is_alive():
		return
	selected_unit = current_unit
	input_state = InputState.ACTION_PHASE
	_attack_mode = ATTACK_MODE_BASIC
	_selected_skill_id = ""
	_clear_targeting_buffers()
	_path_preview = []
	_combat_forecast = {}
	_skill_bar_expanded = false
	_recalculate_hover_artifacts()
	_show_move_highlights()
	_resolve_post_action_phase()


func _build_skill_entry(unit: Unit, skill_id: String) -> Dictionary:
	var skill_data: Dictionary = _get_skill_data(skill_id)
	var cooldown_turns: int = unit.get_skill_cooldown(skill_id)
	var entry: Dictionary = {
		"skill_id": skill_id,
		"name": str(skill_data.get("name", skill_id)),
		"action_cost": str(skill_data.get("action_cost", "standard")),
		"timing_constraint": str(skill_data.get("timing_constraint", "any")),
		"swift_limit": int(skill_data.get("swift_limit", 1)),
		"cooldown": cooldown_turns,
		"available": false,
		"reason": "",
		"selected": skill_id == _selected_skill_id,
	}
	var phase_reason: String = _get_phase_mismatch_reason(skill_data)
	if phase_reason != "":
		entry["reason"] = phase_reason
		return entry
	var validation: Dictionary = GameAction.validate_skill_usage(unit, skill_data)
	if not bool(validation.get("ok", false)):
		entry["reason"] = _localize_skill_unavailable_reason(skill_data, validation)
		return entry
	if not _is_supported_runtime_skill(skill_data):
		entry["reason"] = "当前战斗原型暂不支持此技能范围/目标"
		return entry
	# ── 剑圣资源条件检查 ─────────────────────────────────
	var qi_cost: int = int(skill_data.get("qi_cost", 0))
	if qi_cost > 0 and unit.sword_qi < qi_cost:
		entry["reason"] = "剑气不足（需要 %d，当前 %d）" % [qi_cost, unit.sword_qi]
		return entry
	var requires_marks: int = int(skill_data.get("requires_marks", 0))
	if requires_marks > 0 and unit.get_mark_count() < requires_marks:
		entry["reason"] = "印记不足（需要 %d 个，当前 %d）" % [requires_marks, unit.get_mark_count()]
		return entry
	entry["available"] = true
	return entry


func _get_skill_entries() -> Array[Dictionary]:
	var unit: Unit = _get_player_dashboard_unit()
	var entries: Array[Dictionary] = []
	if unit == null:
		return entries
	for skill_id: String in unit.skill_ids:
		# ── 槽位替换（数据驱动）：替换规则由技能 JSON 的 slot_swap_* 声明 ──
		var slot_skill_data: Dictionary = _get_skill_data(skill_id)
		var display_id: String = unit.get_visible_skill_id(skill_id,
			str(slot_skill_data.get("slot_swap_trigger", "")),
			str(slot_skill_data.get("slot_swap_target", "")))
		var entry: Dictionary = _build_skill_entry(unit, display_id)
		# 保留原始槽位 ID 以便取消时恢复（附加字段，UI 可忽略）
		entry["slot_origin_id"] = skill_id
		entries.append(entry)
	return entries


func _emit_dashboard_state_changed() -> void:
	dashboard_state_changed.emit()


func _prepare_player_turn(unit: Unit) -> void:
	selected_unit = unit
	_inspected_unit = null
	_skill_bar_expanded = false
	_attack_mode = ATTACK_MODE_BASIC
	_selected_skill_id = ""
	_clear_targeting_buffers()
	_combat_forecast = {}
	_pre_move_position = unit.grid_position
	_move_committed = false
	input_state = InputState.MOVE_PHASE
	_refresh_move_range(unit)
	_update_hover(unit.grid_position)
	_show_move_highlights()
	_emit_dashboard_state_changed()


func _clear_dashboard_state() -> void:
	selected_unit = null
	_move_range = {}
	_clear_targeting_buffers()
	_path_preview = []
	_attack_mode = ATTACK_MODE_BASIC
	_selected_skill_id = ""
	_skill_bar_expanded = false
	_inspected_unit = null
	_move_committed = false
	_combat_forecast = {}
	_targeting_origin_state = InputState.IDLE
	input_state = InputState.IDLE


func _get_dashboard_unit() -> Unit:
	if _inspected_unit != null and _inspected_unit.stats.is_alive():
		return _inspected_unit
	return _get_player_dashboard_unit()


func _get_player_dashboard_unit() -> Unit:
	if not _is_player_turn_active():
		return null
	if input_state == InputState.IDLE:
		return null
	return current_unit


func _is_player_turn_active() -> bool:
	return current_unit != null \
		and current_unit.faction == "player" \
		and turn_manager.current_unit == current_unit


func _is_enemy_info_mode() -> bool:
	return _inspected_unit != null and _inspected_unit.faction == "enemy"


func _build_primary_button_state() -> Dictionary:
	return {
		"attack_visible": input_state != InputState.SWIFT_PHASE,
		"attack_disabled": not _can_enter_attack_targeting(),
		"attack_reason": _get_attack_button_reason(),
		"skill_visible": true,
		"skill_disabled": false,
		"skill_reason": "",
		"item_visible": input_state != InputState.SWIFT_PHASE,
		"item_disabled": true,
		"item_reason": "暂未开放",
		"end_turn_visible": true,
		"end_turn_disabled": false,
		"end_move_visible": input_state == InputState.MOVE_PHASE,
		"end_move_disabled": false,
		"cancel_visible": input_state != InputState.SWIFT_PHASE,
		"cancel_disabled": input_state == InputState.IDLE,
		"cancel_reason": "",
	}


func _get_phase_text() -> String:
	match input_state:
		InputState.MOVE_PHASE:
			return "移动阶段"
		InputState.ACTION_PHASE:
			return "行动阶段"
		InputState.SKILL_TARGETING:
			return "技能瞄准"
		InputState.ATTACK_TARGETING:
			return "攻击瞄准"
		InputState.SWIFT_PHASE:
			return "迅捷阶段"
		InputState.ANIMATING:
			return "执行中"
		_:
			return "待机"


func _get_dashboard_hint_text() -> String:
	if _is_enemy_info_mode():
		return "只读信息，右键或 ESC 关闭"
	match input_state:
		InputState.MOVE_PHASE:
			return "选择移动格，或点自身/结束移动进入行动阶段"
		InputState.ACTION_PHASE:
			return "可攻击、用技能，或右键/ESC 撤销移动"
		InputState.SKILL_TARGETING:
			if _is_waiting_for_line_direction():
				return "先选择施法方向，再选择目标格"
			return "选择合法目标，右键或 ESC 取消"
		InputState.ATTACK_TARGETING:
			return "悬停敌人查看预测，左键确认攻击"
		InputState.SWIFT_PHASE:
			return "仅可使用迅捷技能，或直接结束回合"
		_:
			return ""


func _show_enemy_info(unit: Unit) -> void:
	_inspected_unit = unit
	_combat_forecast = {}
	_emit_dashboard_state_changed()


func _show_unit_info(unit: Unit) -> void:
	if unit.faction == "enemy":
		_show_enemy_info(unit)
	else:
		_inspected_unit = null
		_emit_dashboard_state_changed()


func _complete_move_phase(moved: bool) -> void:
	if current_unit == null:
		return
	if not moved:
		_pre_move_position = current_unit.grid_position
		_move_committed = false
	selected_unit = current_unit
	_inspected_unit = null
	_clear_targeting_buffers()
	_move_range = {}
	_path_preview = []
	_attack_mode = ATTACK_MODE_BASIC
	_selected_skill_id = ""
	_skill_bar_expanded = false
	_combat_forecast = {}
	input_state = InputState.ACTION_PHASE
	_recalculate_hover_artifacts()
	_refresh_highlights()
	_emit_dashboard_state_changed()


func _undo_move() -> void:
	if current_unit == null:
		return
	var from_pos: Vector2i = current_unit.grid_position
	if from_pos != _pre_move_position:
		current_unit.position = grid.grid_to_world(_pre_move_position)
		grid.move_unit(current_unit, from_pos, _pre_move_position)
	else:
		current_unit.position = grid.grid_to_world(_pre_move_position)
	current_unit.restore_movement_resource()
	current_unit.refresh_status_icons()
	selected_unit = current_unit
	_clear_targeting_buffers()
	_selected_skill_id = ""
	_skill_bar_expanded = false
	_inspected_unit = null
	_combat_forecast = {}
	_move_committed = false
	input_state = InputState.MOVE_PHASE
	_refresh_move_range(current_unit)
	_recalculate_hover_artifacts()
	_show_move_highlights()
	_emit_dashboard_state_changed()


func _cancel_targeting() -> void:
	var origin_state: InputState = _targeting_origin_state
	var keep_skill_bar_open: bool = input_state == InputState.SKILL_TARGETING
	_clear_targeting_buffers()
	_selected_skill_id = ""
	_attack_mode = ATTACK_MODE_BASIC
	_combat_forecast = {}
	_skill_bar_expanded = keep_skill_bar_open
	_targeting_origin_state = InputState.IDLE
	if origin_state == InputState.MOVE_PHASE:
		input_state = InputState.MOVE_PHASE
		_refresh_move_range(current_unit)
	else:
		input_state = InputState.ACTION_PHASE
		_move_range = {}
	_recalculate_hover_artifacts()
	_refresh_highlights()
	_emit_dashboard_state_changed()


func _end_player_turn() -> void:
	if not _is_player_turn_active():
		return
	_clear_hover_state()
	_clear_highlights()
	_clear_dashboard_state()
	turn_manager.end_current_turn()


func _can_enter_attack_targeting() -> bool:
	if input_state != InputState.ACTION_PHASE:
		return false
	if current_unit == null:
		return false
	var validation: Dictionary = GameAction.can_use_normal_attack(current_unit)
	return bool(validation.get("ok", false))


func _get_attack_button_reason() -> String:
	if current_unit == null:
		return ""
	if input_state == InputState.MOVE_PHASE:
		return "当前处于移动阶段，请先完成移动"
	var validation: Dictionary = GameAction.can_use_normal_attack(current_unit)
	if bool(validation.get("ok", false)):
		return ""
	return "攻击机会已使用"


func _resolve_post_action_phase() -> void:
	if not _is_player_turn_active():
		return
	if current_unit.standard_used:
		if _has_available_swift_skill(current_unit):
			input_state = InputState.SWIFT_PHASE
			_clear_targeting_buffers()
			_move_range = {}
			_path_preview = []
			_attack_mode = ATTACK_MODE_BASIC
			_selected_skill_id = ""
			_skill_bar_expanded = true
			_emit_dashboard_state_changed()
		else:
			_end_player_turn()
	else:
		input_state = InputState.ACTION_PHASE
		_emit_dashboard_state_changed()


func _handle_post_skill_execution(previous_state: InputState,
		action: GameAction) -> void:
	var action_cost: String = str(action.data.get("action_cost", "standard"))
	var source_state: InputState = previous_state
	if previous_state == InputState.SKILL_TARGETING:
		source_state = _targeting_origin_state
	_targeting_origin_state = InputState.IDLE
	match action_cost:
		"move":
			_complete_move_phase(true)
		"standard":
			_restore_action_phase_state()
		"swift":
			match source_state:
				InputState.MOVE_PHASE:
					input_state = InputState.MOVE_PHASE
					_skill_bar_expanded = false
					_refresh_move_range(current_unit)
					_recalculate_hover_artifacts()
					_show_move_highlights()
					_emit_dashboard_state_changed()
				InputState.SWIFT_PHASE:
					_restore_action_phase_state()
				_:
					input_state = InputState.ACTION_PHASE
					_skill_bar_expanded = false
					_clear_targeting_buffers()
					_recalculate_hover_artifacts()
					_refresh_highlights()
					_emit_dashboard_state_changed()
		_:
			_restore_action_phase_state()


func _has_available_swift_skill(unit: Unit) -> bool:
	for skill_id: String in unit.skill_ids:
		var skill_data: Dictionary = _get_skill_data(skill_id)
		if str(skill_data.get("action_cost", "")) != "swift":
			continue
		if _get_phase_mismatch_reason(skill_data) != "":
			continue
		if not _is_supported_runtime_skill(skill_data):
			continue
		var validation: Dictionary = GameAction.validate_skill_usage(unit, skill_data)
		if bool(validation.get("ok", false)):
			return true
	return false


func _get_phase_mismatch_reason(skill_data: Dictionary) -> String:
	var action_cost: String = str(skill_data.get("action_cost", "standard"))
	if input_state == InputState.MOVE_PHASE and action_cost == "standard":
		return "当前处于移动阶段，请先完成移动"
	return ""


func _localize_skill_unavailable_reason(skill_data: Dictionary,
		validation: Dictionary) -> String:
	var reason: String = str(validation.get("reason", ""))
	var skill_id: String = str(skill_data.get("id", ""))
	if skill_id != "" and current_unit != null and current_unit.get_skill_cooldown(skill_id) > 0:
		return "冷却中 (%d 回合后恢复)" % current_unit.get_skill_cooldown(skill_id)
	match reason:
		"Movement already used":
			return "已失去移动机会"
		"Standard Action already used":
			return "攻击机会已使用"
		"Swift Action already used":
			return "迅捷机会已使用"
		"Must use before moving":
			return "需要在移动前使用"
		"Must use after moving":
			return "需要在移动后使用"
		"Must use before attacking":
			return "需要在攻击前使用"
		"Must use after attacking":
			return "需要在攻击后使用"
		_:
			return reason


func _build_attack_forecast_for_hover(grid_pos: Vector2i) -> Dictionary:
	if current_unit == null or input_state != InputState.ATTACK_TARGETING:
		return {}
	if grid_pos not in _attack_cells:
		return {}
	var target: Unit = grid.get_unit_at(grid_pos)
	if target == null or target.faction == current_unit.faction:
		return {}
	var action: GameAction = GameAction.make_attack(current_unit, target)
	var preview_data: Dictionary = _build_hostile_action_context(
		current_unit, target, action.data)
	var preview: Dictionary = DamageCalculator.preview_attack(
		current_unit, target, preview_data)
	return {
		"visible": true,
		"target_name": target.unit_name,
		"hit_percent": int(preview.get("hit_percent", 0)),
		"crit_percent": int(preview.get("crit_percent", 0)),
		"damage": int(preview.get("damage", 0)),
		"counter_expected": _can_counterattack(preview_data, target, current_unit),
		"terrain_name": str(preview.get("terrain_name", "PLAIN")),
		"terrain_evade_bonus": int(preview.get("terrain_evade_bonus", 0)),
		"terrain_def_bonus": int(preview.get("terrain_def_bonus", 0)),
		"terrain_res_bonus": int(preview.get("terrain_res_bonus", 0)),
	}

# ── Action execution ─────────────────────────────────

func _execute_move(unit: Unit, target: Vector2i) -> void:
	var move_check: Dictionary = GameAction.can_use_normal_move(unit)
	if not bool(move_check.get("ok", false)):
		print("[Action] Move blocked: %s" % str(move_check.get("reason", "")))
		return
	_pre_move_position = unit.grid_position
	_move_committed = false
	input_state = InputState.ANIMATING
	var from: Vector2i = unit.grid_position
	GameAction.consume_normal_move(unit)
	unit.refresh_status_icons()
	_path_preview = []
	_clear_highlights()
	_move_range = {}
	await unit.move_to(target, grid)
	grid.move_unit(unit, from, target)
	selected_unit = current_unit
	_complete_move_phase(true)


func _execute_attack_from_input(action: GameAction) -> void:
	var previous_state: InputState = input_state
	input_state = InputState.ANIMATING
	_clear_highlights()
	_clear_targeting_buffers()
	_combat_forecast = {}
	var executed: bool = _execute_attack_action(action)
	if current_unit and current_unit.stats.is_alive() \
			and turn_manager.current_unit == current_unit:
		if executed:
			_restore_action_phase_state()
		else:
			input_state = previous_state
			_refresh_attack_cells()
			_recalculate_hover_artifacts()
			_show_attack_highlights()


func _execute_skill_from_input(action: GameAction) -> void:
	var previous_state: InputState = input_state
	input_state = InputState.ANIMATING
	_clear_highlights()
	_clear_targeting_buffers()
	_combat_forecast = {}
	var executed: bool = _execute_skill_action(action)
	if current_unit and current_unit.stats.is_alive() \
			and turn_manager.current_unit == current_unit:
		if executed:
			_handle_post_skill_execution(previous_state, action)
		else:
			input_state = previous_state
			_refresh_attack_cells()
			_recalculate_hover_artifacts()
			_show_attack_highlights()


func _execute_attack_action(action: GameAction) -> bool:
	var attacker: Unit = action.actor
	var defender: Unit = action.target_unit
	if not _can_execute_hostile_action(attacker, defender):
		return false
	var attack_check: Dictionary = GameAction.can_use_normal_attack(attacker)
	if not bool(attack_check.get("ok", false)):
		print("[Action] Attack blocked: %s" % str(attack_check.get("reason", "")))
		return false

	GameAction.consume_normal_attack(attacker)
	_move_committed = true
	attacker.refresh_status_icons()
	_execute_hostile_action(attacker, defender, action.data)
	return true


func _execute_skill_action(action: GameAction) -> bool:
	var user: Unit = action.actor
	var data: Dictionary = action.data
	if user == null:
		return false
	var skill_id: String = str(data.get("skill_id", ""))
	if skill_id == "":
		return false

	var skill_data: Dictionary = _get_skill_data(skill_id)
	if skill_data.is_empty():
		return false
	var validation: Dictionary = GameAction.validate_skill_usage(user, skill_data)
	if not bool(validation.get("ok", false)):
		print("[Skill] %s blocked: %s" % [skill_id, str(validation.get("reason", ""))])
		return false

	var target_pos: Vector2i = action.target_pos
	if not grid.is_valid(target_pos):
		return false
	var area_direction: Vector2i = _deserialize_vector2i(
		data.get("target_direction", {}))
	var area_cells: Array[Vector2i] = _extract_cells_from_payload(
		data.get("affected_cells", []))
	if area_cells.is_empty():
		area_direction = _get_skill_area_direction(
			user.grid_position, target_pos, skill_data)
		area_cells = AreaCalculator.calculate_cells(
			grid, target_pos, skill_data.get("area", {}), area_direction)
	var target_units: Array[Unit] = _get_units_in_skill_area(
		user, skill_data, area_cells)
	if not _is_ground_target_skill(skill_data) and target_units.is_empty():
		return false

	var action_cost: String = str(skill_data.get("action_cost", "standard"))
	var swift_limit: int = int(skill_data.get("swift_limit", 1))
	GameAction.consume_action_cost(user, action_cost, swift_limit)
	if action_cost in ["move", "standard", "swift"]:
		_move_committed = true

	# ── 剑圣资源消耗（施放时）────────────────────────────
	var qi_cost: int = int(skill_data.get("qi_cost", 0))
	if qi_cost > 0:
		user.set_sword_qi(user.sword_qi - qi_cost)
	var mark_cost: int = int(skill_data.get("mark_cost", 0))
	if mark_cost > 0:
		user.spend_marks(mark_cost)

	var cooldown_turns: int = int(data.get("cooldown", 0))
	user.consume_skill(skill_id, cooldown_turns)
	user.refresh_status_icons()
	var skill_name: String = str(data.get("skill_name", skill_id))
	if _is_support_skill(skill_data):
		print("[Skill] %s uses %s (%d target(s))" % [
			user.unit_name,
			skill_name,
			target_units.size(),
		])
		_apply_support_skill(user, skill_data, target_units)
		return true

	var hostile_payload: Dictionary = data.duplicate(true)
	if target_units.is_empty():
		print("[Skill] %s uses %s on empty area %s" % [
			user.unit_name,
			skill_name,
			target_pos,
		])
		return true

	for target_unit: Unit in target_units:
		if not _can_execute_hostile_action(user, target_unit):
			continue
		print("[Skill] %s uses %s on %s" % [
			user.unit_name,
			skill_name,
			target_unit.unit_name,
		])
		_execute_hostile_action(user, target_unit, hostile_payload)
	return true


func _can_execute_hostile_action(attacker: Unit, defender: Unit) -> bool:
	if not attacker or not defender:
		return false
	if not attacker.stats.is_alive() or not defender.stats.is_alive():
		return false
	return true


func _execute_hostile_action(attacker: Unit, defender: Unit,
		data: Dictionary) -> void:
	var action_data: Dictionary = _build_hostile_action_context(attacker, defender, data)
	var damage_type: String = str(action_data.get("damage_type", "physical"))
	var defender_disabled_before_attack: bool = defender.has_buff("stun") \
		or defender.has_buff("freeze")
	defender.handle_attacked()

	# Main attack: calculate → popup → apply
	var result: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(
		attacker, defender, action_data)
	_log_attack(attacker, defender, result, "")
	if result.hit:
		DamagePopup.spawn(popup_layer, defender.position,
			result.damage, damage_type, result.crit)
		defender.take_damage(result.damage, damage_type)
	else:
		DamagePopup.spawn_miss(popup_layer, defender.position)

	if result.hit and defender.stats.is_alive():
		_apply_hostile_skill_effects(attacker, defender, data)

	# ── 剑圣资源：命中得气、击杀得气+减CD+得印记 ──────────
	_apply_sword_qi_on_hit(attacker, result, action_data)

	if result.defender_died:
		return

	# Counter-attack
	if _can_counterattack(action_data, defender, attacker, defender_disabled_before_attack):
		var counter_data: Dictionary = _build_basic_attack_action_data(defender, attacker, {
			"allow_counter": false,
		})
		var counter_result: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(
			defender, attacker, counter_data)
		_log_attack(defender, attacker, counter_result, "Counterattack")
		if counter_result.hit:
			var counter_damage_type: String = str(counter_data.get("damage_type", "physical"))
			DamagePopup.spawn(popup_layer, attacker.position,
				counter_result.damage, counter_damage_type, counter_result.crit)
			attacker.take_damage(counter_result.damage, counter_damage_type)
		else:
			DamagePopup.spawn_miss(popup_layer, attacker.position)
		if counter_result.defender_died:
			result.attacker_died = true
			return


func _is_waiting_for_line_direction() -> bool:
	if input_state != InputState.SKILL_TARGETING or _selected_skill_id == "":
		return false
	var skill_data: Dictionary = _get_skill_data(_selected_skill_id)
	var range_data: Dictionary = skill_data.get("range", {})
	return str(range_data.get("type", "")) == "line" \
		and _targeting_direction == Vector2i.ZERO


func _can_confirm_skill_target(grid_pos: Vector2i) -> bool:
	if current_unit == null or _selected_skill_id == "":
		return false
	if grid_pos not in _attack_cells:
		return false
	var skill_data: Dictionary = _get_skill_data(_selected_skill_id)
	if _is_ground_target_skill(skill_data):
		return true
	var target_unit: Unit = grid.get_unit_at(grid_pos)
	return _matches_target_relation(
		current_unit, target_unit, _get_skill_target_relation(skill_data))


func _get_units_in_skill_area(user: Unit, skill_data: Dictionary,
		area_cells: Array[Vector2i]) -> Array[Unit]:
	var relation: String = _get_skill_target_relation(skill_data)
	var units_by_id: Dictionary = {}
	for cell_pos: Vector2i in area_cells:
		var target_unit: Unit = grid.get_unit_at(cell_pos)
		if _matches_target_relation(user, target_unit, relation):
			units_by_id[target_unit.get_instance_id()] = target_unit
	var units_in_area: Array[Unit] = []
	for unit_value: Variant in units_by_id.values():
		if unit_value is Unit:
			units_in_area.append(unit_value)
	return units_in_area


func _get_skill_target_relation(skill_data: Dictionary) -> String:
	var range_data: Dictionary = skill_data.get("range", {})
	var area_data: Dictionary = skill_data.get("area", {})
	if str(range_data.get("type", "")) == "self" \
			and str(area_data.get("type", "single")) == "single":
		return "self"
	if _is_support_skill(skill_data):
		return "ally"
	return "enemy"


func _matches_target_relation(user: Unit, target_unit: Unit,
		relation: String) -> bool:
	if user == null or target_unit == null or not target_unit.stats.is_alive():
		return false
	match relation:
		"self":
			return target_unit == user
		"ally":
			return target_unit.faction == user.faction
		"enemy":
			return target_unit.faction != user.faction
		_:
			return false


func _is_support_skill(skill_data: Dictionary) -> bool:
	return int(skill_data.get("power", 0)) <= 0


func _is_ground_target_skill(skill_data: Dictionary) -> bool:
	var range_data: Dictionary = skill_data.get("range", {})
	if str(range_data.get("type", "")) == "self":
		return false
	var area_data: Dictionary = skill_data.get("area", {})
	return str(area_data.get("type", "single")) != "single"


func _apply_support_skill(user: Unit, skill_data: Dictionary,
		target_units: Array[Unit]) -> void:
	for target_unit: Unit in target_units:
		for effect_value: Variant in skill_data.get("effects", []):
			if not (effect_value is Dictionary):
				continue
			_apply_skill_effect_to_unit(
				user, target_unit, effect_value as Dictionary, false)


func _apply_hostile_skill_effects(user: Unit, target_unit: Unit,
		action_data: Dictionary) -> void:
	var effect_entries: Variant = action_data.get("effects", [])
	if not (effect_entries is Array):
		return
	for effect_value: Variant in effect_entries:
		if not (effect_value is Dictionary):
			continue
		_apply_skill_effect_to_unit(
			user, target_unit, effect_value as Dictionary, true)


func _apply_skill_effect_to_unit(user: Unit, target_unit: Unit,
		effect_data: Dictionary, is_hostile: bool) -> void:
	var effect_type: String = str(
		effect_data.get("effect_id", effect_data.get("type", "")))
	var effect_value: int = int(effect_data.get("value", 0))
	match effect_type:
		"heal":
			if effect_value > 0:
				target_unit.heal(effect_value)
		"damage", "dot":
			if effect_value > 0:
				target_unit.take_damage(effect_value, "pure")
		_:
			if not _roll_effect_application(target_unit, effect_data, is_hostile):
				return
			var buff: BuffEffect = _make_buff_effect_instance(user, effect_data)
			if buff != null:
				target_unit.add_buff(buff)


func _roll_effect_application(target_unit: Unit, effect_data: Dictionary,
		is_hostile: bool) -> bool:
	var base_chance: float = float(effect_data.get("chance", 100))
	if base_chance <= 0.0:
		return false
	var actual_percent: float = base_chance
	if is_hostile:
		actual_percent *= target_unit.get_status_resist_multiplier()
	return randf() <= clampf(actual_percent / 100.0, 0.0, 1.0)


func _make_buff_effect_instance(user: Unit,
		effect_data: Dictionary) -> BuffEffect:
	var effect_id: String = str(
		effect_data.get("effect_id", effect_data.get("type", "")))
	var template_data: Dictionary = DataLoader.buffs.get(effect_id, {})
	if template_data.is_empty():
		return null
	var buff_payload: Dictionary = template_data.duplicate(true)
	if effect_data.has("duration"):
		var duration_value: int = int(effect_data.get("duration", buff_payload.get("duration", -1)))
		buff_payload["duration"] = duration_value
		buff_payload["max_duration"] = duration_value
	if effect_data.has("value"):
		buff_payload["value"] = float(effect_data.get("value", buff_payload.get("value", 0)))
	buff_payload["source_unit_id"] = user.unit_id
	return BuffEffect.from_dict(buff_payload)


func _get_skill_range_fill_color() -> Color:
	if _selected_skill_id == "":
		return HIGHLIGHT_ATTACK_RANGE_FILL
	var skill_data: Dictionary = _get_skill_data(_selected_skill_id)
	if _is_support_skill(skill_data):
		return HIGHLIGHT_SUPPORT_RANGE_FILL
	return HIGHLIGHT_ATTACK_RANGE_FILL


func _get_skill_range_border_color() -> Color:
	if _selected_skill_id == "":
		return HIGHLIGHT_ATTACK_RANGE_BORDER
	var skill_data: Dictionary = _get_skill_data(_selected_skill_id)
	if _is_support_skill(skill_data):
		return HIGHLIGHT_SUPPORT_RANGE_BORDER
	return HIGHLIGHT_ATTACK_RANGE_BORDER


func _get_skill_target_fill_color() -> Color:
	if _selected_skill_id == "":
		return HIGHLIGHT_ATTACK_TARGET_FILL
	var skill_data: Dictionary = _get_skill_data(_selected_skill_id)
	if _is_support_skill(skill_data):
		return HIGHLIGHT_SUPPORT_TARGET_FILL
	return HIGHLIGHT_ATTACK_TARGET_FILL


func _get_skill_target_border_color() -> Color:
	if _selected_skill_id == "":
		return HIGHLIGHT_ATTACK_TARGET_BORDER
	var skill_data: Dictionary = _get_skill_data(_selected_skill_id)
	if _is_support_skill(skill_data):
		return HIGHLIGHT_SUPPORT_TARGET_BORDER
	return HIGHLIGHT_ATTACK_TARGET_BORDER


func _refresh_attack_cells() -> void:
	_range_display_cells = []
	_attack_cells = []
	_area_preview_cells = []
	_direction_selector_cells = []
	if current_unit == null:
		return
	if _attack_mode == ATTACK_MODE_SKILL and _selected_skill_id != "":
		var skill_data: Dictionary = _get_skill_data(_selected_skill_id)
		var range_data: Dictionary = skill_data.get("range", {})
		if str(range_data.get("type", "")) == "line" \
				and _targeting_direction == Vector2i.ZERO:
			_direction_selector_cells = RangeCalculator.get_line_selector_cells(
				grid, current_unit.grid_position, range_data)
			return
		var candidate_cells: Array[Vector2i] = RangeCalculator.calculate_cells(
			grid, current_unit.grid_position, range_data, _targeting_direction)
		_range_display_cells = candidate_cells
		_attack_cells = _filter_targetable_cells(candidate_cells, skill_data)
	else:
		var basic_pattern: Dictionary = {
			"type": "diamond",
			"min": current_unit.attack_min_range,
			"max": current_unit.attack_range,
		}
		var basic_cells: Array[Vector2i] = RangeCalculator.calculate_cells(
			grid, current_unit.grid_position, basic_pattern)
		_range_display_cells = basic_cells
		_attack_cells = _filter_enemy_target_cells(basic_cells)


func _filter_targetable_cells(candidate_cells: Array[Vector2i],
		skill_data: Dictionary) -> Array[Vector2i]:
	if current_unit == null:
		return []
	if _is_ground_target_skill(skill_data):
		return candidate_cells
	var filtered_cells: Array[Vector2i] = []
	var relation: String = _get_skill_target_relation(skill_data)
	for cell_pos: Vector2i in candidate_cells:
		var target_unit: Unit = grid.get_unit_at(cell_pos)
		if _matches_target_relation(current_unit, target_unit, relation):
			filtered_cells.append(cell_pos)
	return filtered_cells


func _filter_enemy_target_cells(candidate_cells: Array[Vector2i]) -> Array[Vector2i]:
	if current_unit == null:
		return []
	var filtered_cells: Array[Vector2i] = []
	for cell_pos: Vector2i in candidate_cells:
		var target_unit: Unit = grid.get_unit_at(cell_pos)
		if target_unit != null and target_unit.faction != current_unit.faction:
			filtered_cells.append(cell_pos)
	return filtered_cells


func _get_skill_area_direction(origin: Vector2i, target_pos: Vector2i,
		skill_data: Dictionary) -> Vector2i:
	var area_data: Dictionary = skill_data.get("area", {})
	if str(area_data.get("type", "")) == "line" \
			and _targeting_direction != Vector2i.ZERO:
		return _targeting_direction
	return RangeCalculator.direction_from_to(origin, target_pos)


func _build_skill_action(user: Unit, target_pos: Vector2i,
		target: Unit) -> GameAction:
	if user == null or _selected_skill_id == "":
		return null
	var skill_data: Dictionary = _get_skill_data(_selected_skill_id)
	if skill_data.is_empty():
		return null
	var area_data: Dictionary = skill_data.get("area", {})
	var area_type: String = str(area_data.get("type", "single"))
	var area_direction: Vector2i = _get_skill_area_direction(
		user.grid_position, target_pos, skill_data)
	var affected_cells: Array[Vector2i] = AreaCalculator.calculate_cells(
		grid, target_pos, area_data, area_direction)
	var is_area_skill: bool = area_type != "single"
	var basic_attack_profile: Dictionary = _get_unit_basic_attack_profile(user)
	var payload: Dictionary = {
		"skill_name": str(skill_data.get("name", _selected_skill_id)),
		"action_cost": str(skill_data.get("action_cost", "standard")),
		"timing_constraint": str(skill_data.get("timing_constraint", "any")),
		"swift_limit": int(skill_data.get("swift_limit", 1)),
		"cooldown": int(skill_data.get("cooldown", 0)),
		"damage_type": str(skill_data.get("damage_type", "physical")),
		"attack_type": str(skill_data.get("attack_type", "melee")),
		"skill_multiplier": float(skill_data.get("power", 100)) / 100.0,
		"terrain_multiplier": 1.0,
		"weapon_might": int(basic_attack_profile.get("weapon_might", 0)),
		"weapon_hit": int(basic_attack_profile.get("weapon_hit", 0))
			+ int(skill_data.get("hit_bonus", 0)),
		"weapon_crit": int(basic_attack_profile.get("weapon_crit", 0))
			+ int(skill_data.get("crit_bonus", 0)),
		"range_type": str(skill_data.get("range", {}).get("type", "diamond")),
		"area_type": area_type,
		"effect_timing": str(skill_data.get("effect_timing", "after_damage")),
		"effects": skill_data.get("effects", []).duplicate(true),
		"target_direction": _serialize_vector2i(area_direction),
		"affected_cells": _serialize_cells(affected_cells),
		"allow_counter": not is_area_skill,
		# ── 剑圣专属字段（缺省安全，非剑圣技能此处为 0/false）──
		"skill_id": _selected_skill_id,
		"guaranteed_hit": bool(skill_data.get("guaranteed_hit", false)),
		"guaranteed_crit": bool(skill_data.get("guaranteed_crit", false)),
		"crit_damage_bonus": float(skill_data.get("crit_damage_bonus", 0.0)),
		"qi_gain_on_hit": int(skill_data.get("qi_gain_on_hit", 0)),
		"qi_gain_on_kill": int(skill_data.get("qi_gain_on_kill", 0)),
		"mark_gain": int(skill_data.get("mark_gain", 0)),
		"ki_on_kill_cd_reduction": int(skill_data.get("ki_on_kill_cd_reduction", 0)),
	}
	return GameAction.make_skill(user, _selected_skill_id, target_pos, target, payload)


func _serialize_cells(cells: Array[Vector2i]) -> Array[Dictionary]:
	var serialized_cells: Array[Dictionary] = []
	for cell_pos: Vector2i in cells:
		serialized_cells.append(_serialize_vector2i(cell_pos))
	return serialized_cells


func _serialize_vector2i(cell_pos: Vector2i) -> Dictionary:
	return {"x": cell_pos.x, "y": cell_pos.y}


func _deserialize_vector2i(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Dictionary:
		return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
	return Vector2i.ZERO


func _extract_cells_from_payload(value: Variant) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not (value is Array):
		return cells
	for cell_value: Variant in value:
		var cell_pos: Vector2i = _deserialize_vector2i(cell_value)
		if grid.is_valid(cell_pos):
			cells.append(cell_pos)
	return cells


func _get_skill_data(skill_id: String) -> Dictionary:
	return DataLoader.skills.get(skill_id, {})


func _is_supported_runtime_skill(skill_data: Dictionary) -> bool:
	if skill_data.is_empty():
		return false
	var action_cost: String = str(skill_data.get("action_cost", "standard"))
	if action_cost not in ["move", "standard", "swift"]:
		return false
	var range_data: Dictionary = skill_data.get("range", {})
	if str(range_data.get("type", "")) not in [
		"diamond", "line", "cross", "square", "self",
	]:
		return false
	var area_data: Dictionary = skill_data.get("area", {})
	if str(area_data.get("type", "single")) not in [
		"single", "diamond", "line", "cross", "square",
	]:
		return false
	if _is_support_skill(skill_data):
		return true
	var damage_type: String = str(skill_data.get("damage_type", ""))
	if damage_type not in ["physical", "magical", "pure", "hybrid", "holy"]:
		return false
	return int(skill_data.get("power", 0)) > 0


func _is_adjacent(a: Unit, b: Unit) -> bool:
	var dist: int = absi(a.grid_position.x - b.grid_position.x) \
			  + absi(a.grid_position.y - b.grid_position.y)
	return dist <= 1


func _build_hostile_action_context(attacker: Unit, defender: Unit,
		base_data: Dictionary) -> Dictionary:
	var action_data: Dictionary = base_data.duplicate(true)
	var basic_attack_profile: Dictionary = _get_unit_basic_attack_profile(attacker)
	var terrain_context: Dictionary = _get_unit_terrain_context(defender)
	if not action_data.has("weapon_might"):
		action_data["weapon_might"] = int(basic_attack_profile.get("weapon_might", 0))
	if not action_data.has("weapon_hit"):
		action_data["weapon_hit"] = int(basic_attack_profile.get("weapon_hit", 0))
	if not action_data.has("weapon_crit"):
		action_data["weapon_crit"] = int(basic_attack_profile.get("weapon_crit", 0))
	if str(action_data.get("damage_type", "")) == "":
		action_data["damage_type"] = str(basic_attack_profile.get("damage_type", "physical"))
	if str(action_data.get("attack_type", "")) == "":
		action_data["attack_type"] = str(basic_attack_profile.get("attack_type", "melee"))
	# 基础攻击（普攻/反击，无 skill 的 qi 字段）按职业基础攻击产气量补默认值；
	# 技能动作已带 qi_gain_on_hit，不会被覆盖。
	if not action_data.has("qi_gain_on_hit"):
		action_data["qi_gain_on_hit"] = int(basic_attack_profile.get("basic_attack_qi_gain", 0))
	action_data["terrain_evade_bonus"] = int(terrain_context.get("terrain_evade_bonus", 0))
	action_data["terrain_def_bonus"] = int(terrain_context.get("terrain_def_bonus", 0))
	action_data["terrain_res_bonus"] = int(terrain_context.get("terrain_res_bonus", 0))
	action_data["defender_terrain_name"] = str(terrain_context.get("terrain_name", "PLAIN"))
	return action_data


func _build_basic_attack_action_data(attacker: Unit, defender: Unit,
		extra_data: Dictionary = {}) -> Dictionary:
	var basic_attack_profile: Dictionary = _get_unit_basic_attack_profile(attacker)
	var action_data: Dictionary = {
		"damage_type": str(basic_attack_profile.get("damage_type", "physical")),
		"attack_type": str(basic_attack_profile.get("attack_type", "melee")),
		"skill_multiplier": 1.0,
		"terrain_multiplier": 1.0,
		"relic_multiplier": 1.0,
		"final_multiplier": 1.0,
		"weapon_might": int(basic_attack_profile.get("weapon_might", 0)),
		"weapon_hit": int(basic_attack_profile.get("weapon_hit", 0)),
		"weapon_crit": int(basic_attack_profile.get("weapon_crit", 0)),
		"pure_atk_source": str(basic_attack_profile.get("pure_atk_source", "phys")),
		"allow_counter": true,
	}
	for key_value: Variant in extra_data.keys():
		var key: String = str(key_value)
		action_data[key] = extra_data[key]
	return _build_hostile_action_context(attacker, defender, action_data)


func _get_unit_basic_attack_profile(unit: Unit) -> Dictionary:
	var source_data: Dictionary = _get_unit_source_data(unit)
	var fallback_profiles: Dictionary = _get_basic_attack_profile_defaults()
	var fallback_key: String = _get_basic_attack_profile_key(source_data)
	var fallback_profile: Dictionary = fallback_profiles.get(fallback_key, {})
	var range_data: Dictionary = source_data.get("basic_attack_range", fallback_profile.get(
		"basic_attack_range", {"min": 1, "max": 1}))
	var attack_type: String = "melee" if int(range_data.get("max", 1)) <= 1 else "ranged"
	return {
		"weapon_might": int(source_data.get("weapon_might", fallback_profile.get("weapon_might", 0))),
		"weapon_hit": int(source_data.get("weapon_hit", fallback_profile.get("weapon_hit", 0))),
		"weapon_crit": int(source_data.get("weapon_crit", fallback_profile.get("weapon_crit", 0))),
		"damage_type": str(source_data.get("damage_type", fallback_profile.get("damage_type", "physical"))),
		"pure_atk_source": str(source_data.get("pure_atk_source", fallback_profile.get(
			"pure_atk_source", "phys"))),
		"attack_type": attack_type,
		# 剑圣等职业：基础攻击（普攻/反击）命中产气，数值从职业 JSON 读，非剑圣缺省 0
		"basic_attack_qi_gain": int(source_data.get("basic_attack_qi_gain",
			fallback_profile.get("basic_attack_qi_gain", 0))),
		"basic_attack_range": {
			"min": maxi(1, int(range_data.get("min", 1))),
			"max": maxi(1, int(range_data.get("max", 1))),
		},
	}


func _get_unit_source_data(unit: Unit) -> Dictionary:
	if unit == null:
		return {}
	var class_data: Dictionary = DataLoader.classes.get(unit.unit_id, {})
	if not class_data.is_empty():
		return class_data
	return DataLoader.enemies.get(unit.unit_id, {})


func _get_basic_attack_profile_defaults() -> Dictionary:
	var defaults_entry: Dictionary = DataLoader.classes.get("basic_weapon_profiles", {})
	return defaults_entry.get("profiles", {})


func _get_basic_attack_profile_key(source_data: Dictionary) -> String:
	var attack_type: String = str(source_data.get("attack_type", "melee"))
	var damage_type: String = str(source_data.get("damage_type", ""))
	if damage_type == "":
		damage_type = _infer_damage_type_from_skills(source_data)
	if damage_type == "":
		damage_type = "physical"
	return "%s_%s" % [damage_type, attack_type]


func _infer_damage_type_from_skills(source_data: Dictionary) -> String:
	var skill_ids: Array = source_data.get("skill_ids", [])
	for skill_id_value: Variant in skill_ids:
		var skill_id: String = str(skill_id_value)
		var skill_data: Dictionary = DataLoader.skills.get(skill_id, {})
		if skill_data.is_empty():
			continue
		if _is_support_skill(skill_data):
			continue
		return str(skill_data.get("damage_type", ""))
	return ""


func _get_unit_terrain_context(unit: Unit) -> Dictionary:
	if unit == null or grid == null:
		return {
			"terrain_name": "PLAIN",
			"terrain_evade_bonus": 0,
			"terrain_def_bonus": 0,
			"terrain_res_bonus": 0,
		}
	var cell: Cell = grid.get_cell(unit.grid_position)
	if cell == null:
		return {
			"terrain_name": "PLAIN",
			"terrain_evade_bonus": 0,
			"terrain_def_bonus": 0,
			"terrain_res_bonus": 0,
		}
	var combat_modifiers: Dictionary = cell.get_combat_modifiers()
	return {
		"terrain_name": str(combat_modifiers.get("terrain_name", "PLAIN")),
		"terrain_evade_bonus": int(combat_modifiers.get("evade_bonus", 0)),
		"terrain_def_bonus": int(combat_modifiers.get("def_bonus", 0)),
		"terrain_res_bonus": int(combat_modifiers.get("res_bonus", 0)),
	}


func _can_counterattack(action_data: Dictionary, defender: Unit, attacker: Unit,
		defender_disabled: bool = false) -> bool:
	if not bool(action_data.get("allow_counter", true)):
		return false
	if str(action_data.get("attack_type", "melee")) == "area":
		return false
	if defender == null or attacker == null:
		return false
	if not defender.stats.is_alive():
		return false
	if defender_disabled:
		return false
	if defender.has_buff("stun") or defender.has_buff("freeze"):
		return false
	return _is_within_basic_attack_range(defender, attacker.grid_position)


func _is_within_basic_attack_range(unit: Unit, target_pos: Vector2i) -> bool:
	var basic_attack_profile: Dictionary = _get_unit_basic_attack_profile(unit)
	var range_data: Dictionary = basic_attack_profile.get("basic_attack_range", {})
	var min_range: int = maxi(1, int(range_data.get("min", 1)))
	var max_range: int = maxi(min_range, int(range_data.get("max", min_range)))
	var distance: int = absi(unit.grid_position.x - target_pos.x) \
		+ absi(unit.grid_position.y - target_pos.y)
	return distance >= min_range and distance <= max_range


func _log_attack(attacker: Unit, defender: Unit,
		result: DamageCalculator.AttackResult, tag: String) -> void:
	var prefix := (tag + ": ") if tag != "" else ""
	print("[Attack] %s%s→%s | hit=%s | crit=%s | dmg=%d" % [
		prefix, attacker.unit_name, defender.unit_name,
		result.hit, result.crit, result.damage])


# ── Terrain rendering ────────────────────────────────

const TERRAIN_COLORS: Dictionary = {
	Cell.Terrain.PLAIN:         Color(0.44, 0.78, 0.28),
	Cell.Terrain.FOREST:        Color(0.22, 0.53, 0.29),
	Cell.Terrain.MOUNTAIN:      Color(0.78, 0.66, 0.41),
	Cell.Terrain.PEAK:          Color(0.69, 0.69, 0.72),
	Cell.Terrain.WALL:          Color(0.53, 0.53, 0.60),
	Cell.Terrain.SHALLOW_WATER: Color(0.35, 0.69, 0.85),
	Cell.Terrain.DEEP_WATER:    Color(0.19, 0.38, 0.63),
	Cell.Terrain.LAVA:          Color(0.88, 0.41, 0.19),
	Cell.Terrain.SWAMP:         Color(0.41, 0.47, 0.22),
}

const TERRAIN_LABELS: Dictionary = {
	Cell.Terrain.PLAIN:         "",
	Cell.Terrain.FOREST:        "林",
	Cell.Terrain.MOUNTAIN:      "山",
	Cell.Terrain.PEAK:          "峰",
	Cell.Terrain.WALL:          "墙",
	Cell.Terrain.SHALLOW_WATER: "浅",
	Cell.Terrain.DEEP_WATER:    "深",
	Cell.Terrain.LAVA:          "火",
	Cell.Terrain.SWAMP:         "沼",
}


func _render_terrain() -> void:
	for child in terrain_layer.get_children():
		child.queue_free()

	for row in grid.height:
		for col in grid.width:
			var cell := grid.get_cell(Vector2i(col, row))
			if cell == null:
				continue
			var center: Vector2 = grid.grid_to_world(Vector2i(col, row))
			var points: PackedVector2Array = _diamond_points(center)

			var poly := Polygon2D.new()
			poly.polygon = points
			poly.color = TERRAIN_COLORS.get(cell.terrain, Color.WHITE)
			terrain_layer.add_child(poly)

			var line := Line2D.new()
			line.points = PackedVector2Array([points[0], points[1], points[2], points[3], points[0]])
			line.width = 1.0
			line.default_color = Color(0.0, 0.0, 0.0, 0.25)
			terrain_layer.add_child(line)

			var label_text: String = TERRAIN_LABELS.get(cell.terrain, "")
			if label_text != "":
				var label := Label.new()
				label.text = label_text
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				label.size = Vector2(Grid.TILE_WIDTH, Grid.TILE_HEIGHT)
				label.position = center - label.size / 2.0
				label.add_theme_font_size_override("font_size", 11)
				label.add_theme_color_override("font_color",
					Color(1, 1, 1, 0.6))
				label.mouse_filter = Control.MOUSE_FILTER_IGNORE
				terrain_layer.add_child(label)


func _diamond_points(center: Vector2) -> PackedVector2Array:
	var hw: float = Grid.TILE_WIDTH / 2.0
	var hh: float = Grid.TILE_HEIGHT / 2.0
	return PackedVector2Array([
		center + Vector2(0.0, -hh),
		center + Vector2(hw, 0.0),
		center + Vector2(0.0, hh),
		center + Vector2(-hw, 0.0),
	])


# ── 剑圣资源：命中/击杀后的气与印记结算 ─────────────────

func _apply_sword_qi_on_hit(attacker: Unit,
		result: DamageCalculator.AttackResult,
		action_data: Dictionary) -> void:
	# 仅在命中时触发；普通攻击 action_data 无此字段，缺省为 0/false
	if not result.hit:
		return
	# 命中得气（如斩击 qi_gain_on_hit=1）
	var qi_on_hit: int = int(action_data.get("qi_gain_on_hit", 0))
	if qi_on_hit > 0:
		attacker.set_sword_qi(attacker.sword_qi + qi_on_hit)
		print("[SwordQi] %s +%d qi on hit → %d" % [
			attacker.unit_name, qi_on_hit, attacker.sword_qi])
	# 命中后得印记（如居合 mark_gain=1，命中即结算）
	var mark_gain: int = int(action_data.get("mark_gain", 0))
	if mark_gain > 0:
		var gained_mark: String = attacker.gain_random_mark()
		if gained_mark != "":
			print("[SwordMark] %s gained mark 「%s」 on hit, total=%d" % [
				attacker.unit_name, gained_mark, attacker.get_mark_count()])
	# 击杀触发：得气 + 技能 CD 减少
	if not result.defender_died:
		return
	var qi_on_kill: int = int(action_data.get("qi_gain_on_kill", 0))
	if qi_on_kill > 0:
		attacker.set_sword_qi(attacker.sword_qi + qi_on_kill)
		print("[SwordQi] %s +%d qi on kill → %d" % [
			attacker.unit_name, qi_on_kill, attacker.sword_qi])
	var cd_reduce: int = int(action_data.get("ki_on_kill_cd_reduction", 0))
	var origin_skill_id: String = str(action_data.get("skill_id", ""))
	if cd_reduce > 0 and origin_skill_id != "":
		var current_cd: int = attacker.get_skill_cooldown(origin_skill_id)
		var new_cd: int = maxi(0, current_cd - cd_reduce)
		if new_cd == 0:
			attacker.skill_cooldowns.erase(origin_skill_id)
		else:
			attacker.skill_cooldowns[origin_skill_id] = new_cd
		print("[SwordQi] %s %s CD %d→%d on kill" % [
			attacker.unit_name, origin_skill_id, current_cd, new_cd])
