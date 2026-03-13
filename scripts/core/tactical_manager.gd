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
var _attack_cells: Array[Vector2i] = []
var _path_preview: Array[Vector2i] = []
var _hover_cell: Vector2i = Vector2i.ZERO
var _has_hover_cell: bool = false
var _attack_mode: String = ATTACK_MODE_BASIC
var _selected_skill_id: String = ""
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
	var range_data: Dictionary = skill_data.get("range", {})
	if str(range_data.get("type", "")) == "self":
		var action: GameAction = _build_skill_action(unit, unit.grid_position, unit)
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
	unit.trigger_turn_start_effects()
	print("[TurnManager] Turn: %s (%s)" % [unit.unit_name, unit.faction])
	if unit.faction != "player":
		_clear_hover_state()
		_clear_dashboard_state()
		_emit_dashboard_state_changed()
		_do_enemy_turn(unit)
	else:
		_prepare_player_turn(unit)


func _on_turn_ended(unit: Unit) -> void:
	unit.trigger_turn_end_effects()
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
			if unit != null and grid_pos in _attack_cells:
				var skill_action: GameAction = _build_skill_action(current_unit, grid_pos, unit)
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
	_attack_cells = []
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

const HIGHLIGHT_MOVE_FILL    := Color(0.24, 0.47, 1.00, 0.35)
const HIGHLIGHT_MOVE_BORDER  := Color(0.40, 0.70, 1.00, 0.90)
const HIGHLIGHT_ATK_FILL     := Color(1.00, 0.24, 0.24, 0.35)
const HIGHLIGHT_ATK_BORDER   := Color(1.00, 0.50, 0.30, 0.90)
const HIGHLIGHT_HOVER_FILL   := Color(1.00, 0.94, 0.24, 0.35)
const HIGHLIGHT_HOVER_BORDER := Color(1.00, 1.00, 0.60, 0.90)
const PATH_PREVIEW_COLOR     := Color(1.00, 0.98, 0.65, 0.95)
const HIGHLIGHT_BORDER_WIDTH := 2.0


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
	_emit_dashboard_state_changed()


func _refresh_highlights() -> void:
	_clear_highlights()
	match input_state:
		InputState.MOVE_PHASE:
			for cell_pos: Vector2i in _move_range:
				_add_highlight(cell_pos, HIGHLIGHT_MOVE_FILL, HIGHLIGHT_MOVE_BORDER)
			if _path_preview.size() > 1:
				_add_path_preview(_path_preview)
		InputState.SKILL_TARGETING, InputState.ATTACK_TARGETING:
			for cell_pos: Vector2i in _attack_cells:
				_add_highlight(cell_pos, HIGHLIGHT_ATK_FILL, HIGHLIGHT_ATK_BORDER)
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
	return _get_attack_range_band(origin, 1, atk_range)


func _get_attack_range_band(origin: Vector2i, min_range: int = 1,
		max_range: int = 1) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dy in range(-max_range, max_range + 1):
		for dx in range(-max_range, max_range + 1):
			var dist: int = absi(dx) + absi(dy)
			if dist < min_range or dist > max_range:
				continue
			var pos: Vector2i = origin + Vector2i(dx, dy)
			if grid.is_valid(pos):
				result.append(pos)
	return result


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
	if input_state == InputState.SKILL_TARGETING:
		_refresh_attack_cells()
		_recalculate_hover_artifacts()
		_show_attack_highlights()
	_emit_dashboard_state_changed()


func _restore_action_phase_state() -> void:
	if current_unit == null or turn_manager.current_unit != current_unit:
		return
	if not current_unit.stats.is_alive():
		return
	selected_unit = current_unit
	input_state = InputState.ACTION_PHASE
	_attack_mode = ATTACK_MODE_BASIC
	_selected_skill_id = ""
	_attack_cells = []
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
	entry["available"] = true
	return entry


func _apply_self_skill_effects(user: Unit, skill_data: Dictionary) -> void:
	for effect_value: Variant in skill_data.get("effects", []):
		if not (effect_value is Dictionary):
			continue
		var effect_data: Dictionary = effect_value
		user.add_status_effect({
			"id": "%s_%s" % [
				str(skill_data.get("id", "skill")),
				str(effect_data.get("type", "buff")),
			],
			"name": str(effect_data.get("type", "buff")),
			"kind": "buff",
			"icon": "+",
			"duration": int(effect_data.get("duration", 1)),
			"effect_type": str(effect_data.get("type", "buff")),
			"value": int(effect_data.get("value", 0)),
			"trigger": "manual",
		})


func _get_skill_entries() -> Array[Dictionary]:
	var unit: Unit = _get_player_dashboard_unit()
	var entries: Array[Dictionary] = []
	if unit == null:
		return entries
	for skill_id: String in unit.skill_ids:
		entries.append(_build_skill_entry(unit, skill_id))
	return entries


func _emit_dashboard_state_changed() -> void:
	dashboard_state_changed.emit()


func _prepare_player_turn(unit: Unit) -> void:
	selected_unit = unit
	_inspected_unit = null
	_skill_bar_expanded = false
	_attack_mode = ATTACK_MODE_BASIC
	_selected_skill_id = ""
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
	_attack_cells = []
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
	_attack_cells = []
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
	_attack_cells = []
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
	_attack_cells = []
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
			_attack_cells = []
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
					_attack_cells = []
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
	var preview: Dictionary = DamageCalculator.preview_attack(
		current_unit, target, action.data)
	return {
		"visible": true,
		"target_name": target.unit_name,
		"hit_percent": int(preview.get("hit_percent", 0)),
		"crit_percent": int(preview.get("crit_percent", 0)),
		"damage": int(preview.get("damage", 0)),
		"counter_expected": bool(preview.get("counter_expected", false))
			and _is_adjacent(target, current_unit),
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
	_attack_cells = []
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
	_attack_cells = []
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
	var target: Unit = action.target_unit
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

	var range_data: Dictionary = skill_data.get("range", {})
	var range_type: String = str(range_data.get("type", ""))
	if range_type == "self":
		target = user
	elif not _can_execute_hostile_action(user, target):
		return false

	var action_cost: String = str(skill_data.get("action_cost", "standard"))
	var swift_limit: int = int(skill_data.get("swift_limit", 1))
	GameAction.consume_action_cost(user, action_cost, swift_limit)
	if action_cost in ["move", "standard", "swift"]:
		_move_committed = true

	var cooldown_turns: int = int(data.get("cooldown", 0))
	user.consume_skill(skill_id, cooldown_turns)
	user.refresh_status_icons()
	if range_type == "self":
		print("[Skill] %s uses %s" % [
			user.unit_name,
			str(data.get("skill_name", skill_id))])
		_apply_self_skill_effects(user, skill_data)
	else:
		print("[Skill] %s uses %s on %s" % [
			user.unit_name,
			str(data.get("skill_name", skill_id)),
			target.unit_name])
		_execute_hostile_action(user, target, data)
	return true


func _can_execute_hostile_action(attacker: Unit, defender: Unit) -> bool:
	if not attacker or not defender:
		return false
	if not attacker.stats.is_alive() or not defender.stats.is_alive():
		return false
	return true


func _execute_hostile_action(attacker: Unit, defender: Unit,
		data: Dictionary) -> void:
	var damage_type: String = data.get("damage_type", "physical")

	# Main attack: calculate → popup → apply
	var result := DamageCalculator.resolve_attack(attacker, defender, data)
	_log_attack(attacker, defender, result, "")
	if result.hit:
		DamagePopup.spawn(popup_layer, defender.position,
			result.damage, damage_type, result.crit)
		defender.take_damage(result.damage, damage_type)
	else:
		DamagePopup.spawn_miss(popup_layer, defender.position)

	if result.defender_died:
		return

	# Counter-attack (melee range only)
	var allow_counter: bool = data.get("allow_counter", true)
	if allow_counter and result.hit \
			and defender.stats.is_alive() \
			and _is_adjacent(defender, attacker):
		var counter_data := {
			"damage_type": "physical",
			"skill_multiplier": 1.0,
			"terrain_multiplier": 1.0,
		}
		var counter_result := DamageCalculator.resolve_attack(
			defender, attacker, counter_data)
		_log_attack(defender, attacker, counter_result, "Counterattack")
		if counter_result.hit:
			DamagePopup.spawn(popup_layer, attacker.position,
				counter_result.damage, "physical", counter_result.crit)
			attacker.take_damage(counter_result.damage, "physical")
		else:
			DamagePopup.spawn_miss(popup_layer, attacker.position)
		if counter_result.defender_died:
			result.attacker_died = true
			return

	# Pursuit
	var allow_pursuit: bool = data.get("allow_pursuit", true)
	if allow_pursuit and result.hit \
			and attacker.stats.is_alive() and defender.stats.is_alive():
		var pursuit_chance := clampf(
			(attacker.stats.spd - defender.stats.spd) * 0.1, 0.0, 1.0)
		if randf() < pursuit_chance:
			var pursuit_data := {
				"damage_type": data.get("damage_type", "physical"),
				"skill_multiplier": 1.0,
				"terrain_multiplier": 1.0,
			}
			var pursuit_result := DamageCalculator.resolve_attack(
				attacker, defender, pursuit_data)
			_log_attack(attacker, defender, pursuit_result, "Pursuit")
			if pursuit_result.hit:
				var p_type: String = pursuit_data.get("damage_type", "physical")
				DamagePopup.spawn(popup_layer, defender.position,
					pursuit_result.damage, p_type, pursuit_result.crit)
				defender.take_damage(pursuit_result.damage, p_type)
			else:
				DamagePopup.spawn_miss(popup_layer, defender.position)


func _refresh_attack_cells() -> void:
	if current_unit == null:
		_attack_cells = []
		return
	if _attack_mode == ATTACK_MODE_SKILL and _selected_skill_id != "":
		var skill_data := _get_skill_data(_selected_skill_id)
		var range_data: Dictionary = skill_data.get("range", {})
		var min_range: int = int(range_data.get("min", 1))
		var max_range: int = int(range_data.get("max", 1))
		_attack_cells = _get_attack_range_band(
			current_unit.grid_position, min_range, max_range)
	else:
		_attack_cells = _get_attack_range(
			current_unit.grid_position, current_unit.attack_range)


func _build_skill_action(user: Unit, target_pos: Vector2i,
		target: Unit) -> GameAction:
	if user == null or _selected_skill_id == "":
		return null
	var skill_data := _get_skill_data(_selected_skill_id)
	if skill_data.is_empty():
		return null
	var payload := {
		"skill_name": str(skill_data.get("name", _selected_skill_id)),
		"action_cost": str(skill_data.get("action_cost", "standard")),
		"timing_constraint": str(skill_data.get("timing_constraint", "any")),
		"swift_limit": int(skill_data.get("swift_limit", 1)),
		"cooldown": int(skill_data.get("cooldown", 0)),
		"damage_type": str(skill_data.get("damage_type", "physical")),
		"skill_multiplier": float(skill_data.get("power", 100)) / 100.0,
		"terrain_multiplier": 1.0,
		"weapon_hit": 90 + int(skill_data.get("hit_bonus", 0)),
		"weapon_crit": int(skill_data.get("crit_bonus", 0)),
		"allow_counter": true,
		"allow_pursuit": true,
	}
	return GameAction.make_skill(user, _selected_skill_id, target_pos, target, payload)


func _get_skill_data(skill_id: String) -> Dictionary:
	return DataLoader.skills.get(skill_id, {})


func _is_supported_runtime_skill(skill_data: Dictionary) -> bool:
	if skill_data.is_empty():
		return false
	var range_data: Dictionary = skill_data.get("range", {})
	if str(range_data.get("type", "")) == "self":
		return true
	if str(skill_data.get("action_cost", "")) != "standard":
		return false
	if int(skill_data.get("power", 0)) <= 0:
		return false
	var damage_type: String = str(skill_data.get("damage_type", ""))
	if damage_type not in ["physical", "magical", "pure", "hybrid"]:
		return false
	if str(range_data.get("type", "")) != "diamond":
		return false
	var area_data: Dictionary = skill_data.get("area", {})
	return str(area_data.get("type", "single")) == "single"


func _is_adjacent(a: Unit, b: Unit) -> bool:
	var dist := absi(a.grid_position.x - b.grid_position.x) \
			  + absi(a.grid_position.y - b.grid_position.y)
	return dist <= 1


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
