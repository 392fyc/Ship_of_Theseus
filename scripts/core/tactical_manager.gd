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

enum InputState { IDLE, UNIT_SELECTED, ATTACK_SELECT, ANIMATING }
const ATTACK_MODE_BASIC := "attack"
const ATTACK_MODE_SKILL := "skill"

var input_state := InputState.IDLE
var current_unit: Unit = null
var selected_unit: Unit = null
var _move_range: Dictionary = {}
var _attack_cells: Array[Vector2i] = []
var _path_preview: Array[Vector2i] = []
var _hover_cell: Vector2i = Vector2i.ZERO
var _has_hover_cell: bool = false
var _attack_mode: String = ATTACK_MODE_BASIC
var _representative_skill_id: String = ""


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
		_do_enemy_turn(unit)
	else:
		_update_hover(unit.grid_position)


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
				print("[AI] %s: move %s → %s" % [
					unit.unit_name, from, action.target_pos])
				unit.has_moved = true
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


func _unhandled_input(event: InputEvent) -> void:
	if not battle_active:
		return
	if current_unit == null or current_unit.faction != "player":
		return
	if input_state == InputState.ANIMATING:
		return
	if event is InputEventMouseMotion:
		_update_hover(grid.world_to_grid(event.position))
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var grid_pos := grid.world_to_grid(event.position)
		_handle_click(grid_pos)


func _handle_click(grid_pos: Vector2i) -> void:
	match input_state:
		InputState.IDLE:
			var unit = grid.get_unit_at(grid_pos)
			if unit != null and unit.faction == "player" \
					and unit == current_unit and not unit.has_moved:
				_select_unit(unit)
		InputState.UNIT_SELECTED:
			if selected_unit and grid_pos == selected_unit.grid_position:
				_enter_attack_select()
			elif _move_range.has(grid_pos):
				_execute_move(selected_unit, grid_pos)
		InputState.ATTACK_SELECT:
			if current_unit != null \
					and grid_pos == current_unit.grid_position \
					and _representative_skill_id != "":
				_toggle_attack_mode()
				return
			var target = grid.get_unit_at(grid_pos)
			if target and target.faction != current_unit.faction \
					and grid_pos in _attack_cells:
				if _attack_mode == ATTACK_MODE_SKILL:
					var skill_action := _build_skill_action(current_unit, grid_pos, target)
					if skill_action != null:
						_execute_skill_from_input(skill_action)
					else:
						_end_turn_from_attack_select()
				else:
					var action := GameAction.make_attack(current_unit, target)
					_execute_attack_from_input(action)
			else:
				_end_turn_from_attack_select()


func _select_unit(unit: Unit) -> void:
	selected_unit = unit
	_attack_mode = ATTACK_MODE_BASIC
	_representative_skill_id = _get_representative_skill_id(unit)
	input_state = InputState.UNIT_SELECTED
	_move_range = Pathfinding.get_move_range(
		grid, unit.grid_position, unit.stats.mov, unit.faction)
	_move_range.erase(unit.grid_position)
	_recalculate_hover_artifacts()
	_show_move_highlights()


func _deselect_unit() -> void:
	selected_unit = null
	input_state = InputState.IDLE
	_move_range = {}
	_attack_cells = []
	_path_preview = []
	_attack_mode = ATTACK_MODE_BASIC
	_representative_skill_id = ""
	_clear_hover_state()


func _enter_attack_select() -> void:
	_move_range = {}
	input_state = InputState.ATTACK_SELECT
	_attack_mode = ATTACK_MODE_BASIC
	_representative_skill_id = _get_representative_skill_id(current_unit)
	_refresh_attack_cells()
	if _representative_skill_id != "":
		var skill_data := _get_skill_data(_representative_skill_id)
		print("[Skill] %s ready on %s | select own tile again to toggle" % [
			str(skill_data.get("name", _representative_skill_id)),
			current_unit.unit_name])
	_recalculate_hover_artifacts()
	_show_attack_highlights()


func _end_turn_from_attack_select() -> void:
	_attack_cells = []
	input_state = InputState.IDLE
	selected_unit = null
	_clear_hover_state()
	turn_manager.end_current_turn()


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
	match input_state:
		InputState.UNIT_SELECTED:
			_deselect_unit()
		InputState.ATTACK_SELECT:
			_end_turn_from_attack_select()


func _recalculate_hover_artifacts() -> void:
	_path_preview = []
	if not _has_hover_cell or not grid.is_valid(_hover_cell):
		return
	if input_state == InputState.UNIT_SELECTED \
			and selected_unit != null \
			and _move_range.has(_hover_cell):
		_path_preview = Pathfinding.find_path(
			grid, selected_unit.grid_position, _hover_cell, selected_unit.faction)


func _refresh_highlights() -> void:
	_clear_highlights()
	match input_state:
		InputState.UNIT_SELECTED:
			for cell_pos: Vector2i in _move_range:
				_add_highlight(cell_pos, HIGHLIGHT_MOVE_FILL, HIGHLIGHT_MOVE_BORDER)
			if _path_preview.size() > 1:
				_add_path_preview(_path_preview)
		InputState.ATTACK_SELECT:
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


# ── Action execution ─────────────────────────────────

func _execute_move(unit: Unit, target: Vector2i) -> void:
	input_state = InputState.ANIMATING
	var from := unit.grid_position
	unit.has_moved = true
	unit.refresh_status_icons()
	_path_preview = []
	_clear_highlights()
	_move_range = {}
	selected_unit = null
	await unit.move_to(target, grid)
	grid.move_unit(unit, from, target)
	_enter_attack_select()


func _execute_attack_from_input(action: GameAction) -> void:
	input_state = InputState.ANIMATING
	_clear_highlights()
	_attack_cells = []
	selected_unit = null
	_execute_attack_action(action)
	if current_unit and current_unit.stats.is_alive() \
			and turn_manager.current_unit == current_unit:
		turn_manager.end_current_turn()


func _execute_skill_from_input(action: GameAction) -> void:
	input_state = InputState.ANIMATING
	_clear_highlights()
	_attack_cells = []
	selected_unit = null
	_execute_skill_action(action)
	if current_unit and current_unit.stats.is_alive() \
			and turn_manager.current_unit == current_unit:
		turn_manager.end_current_turn()


func _execute_attack_action(action: GameAction) -> void:
	var attacker: Unit = action.actor
	var defender: Unit = action.target_unit
	if not _can_execute_hostile_action(attacker, defender):
		return

	attacker.has_attacked = true
	attacker.refresh_status_icons()
	_execute_hostile_action(attacker, defender, action.data)


func _execute_skill_action(action: GameAction) -> void:
	var user: Unit = action.actor
	var target: Unit = action.target_unit
	var data: Dictionary = action.data
	if user == null:
		return
	var skill_id: String = str(data.get("skill_id", ""))
	if skill_id == "":
		return
	if not _can_execute_hostile_action(user, target):
		return

	var action_cost: String = str(data.get("action_cost", "standard"))
	match action_cost:
		"swift":
			user.has_used_swift = true
		_:
			user.has_attacked = true

	var cooldown_turns: int = int(data.get("cooldown", 0))
	user.consume_skill(skill_id, cooldown_turns)
	user.refresh_status_icons()
	print("[Skill] %s uses %s on %s" % [
		user.unit_name,
		str(data.get("skill_name", skill_id)),
		target.unit_name])
	_execute_hostile_action(user, target, data)


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
	if _attack_mode == ATTACK_MODE_SKILL and _representative_skill_id != "":
		var skill_data := _get_skill_data(_representative_skill_id)
		var range_data: Dictionary = skill_data.get("range", {})
		var min_range: int = int(range_data.get("min", 1))
		var max_range: int = int(range_data.get("max", 1))
		_attack_cells = _get_attack_range_band(
			current_unit.grid_position, min_range, max_range)
	else:
		_attack_cells = _get_attack_range(
			current_unit.grid_position, current_unit.attack_range)


func _toggle_attack_mode() -> void:
	if current_unit == null or _representative_skill_id == "":
		return
	if _attack_mode == ATTACK_MODE_BASIC:
		if not current_unit.is_skill_available(_representative_skill_id):
			print("[Skill] %s is on cooldown for %d turn(s)" % [
				_representative_skill_id,
				current_unit.get_skill_cooldown(_representative_skill_id)])
			return
		_attack_mode = ATTACK_MODE_SKILL
	else:
		_attack_mode = ATTACK_MODE_BASIC
	_refresh_attack_cells()
	_recalculate_hover_artifacts()
	_show_attack_highlights()
	var mode_label := "Attack"
	if _attack_mode == ATTACK_MODE_SKILL:
		var skill_data := _get_skill_data(_representative_skill_id)
		mode_label = str(skill_data.get("name", _representative_skill_id))
	print("[Action] %s selected for %s" % [mode_label, current_unit.unit_name])


func _build_skill_action(user: Unit, target_pos: Vector2i,
		target: Unit) -> GameAction:
	if user == null or target == null or _representative_skill_id == "":
		return null
	var skill_data := _get_skill_data(_representative_skill_id)
	if skill_data.is_empty():
		return null
	var payload := {
		"skill_name": str(skill_data.get("name", _representative_skill_id)),
		"action_cost": str(skill_data.get("action_cost", "standard")),
		"cooldown": int(skill_data.get("cooldown", 0)),
		"damage_type": str(skill_data.get("damage_type", "physical")),
		"skill_multiplier": float(skill_data.get("power", 100)) / 100.0,
		"terrain_multiplier": 1.0,
		"weapon_hit": 90 + int(skill_data.get("hit_bonus", 0)),
		"weapon_crit": 0,
		"allow_counter": true,
		"allow_pursuit": true,
	}
	return GameAction.make_skill(user, _representative_skill_id, target_pos, target, payload)


func _get_representative_skill_id(unit: Unit) -> String:
	if unit == null:
		return ""
	var fallback_skill_id := ""
	for skill_id: String in unit.skill_ids:
		var skill_data := _get_skill_data(skill_id)
		if not _is_supported_runtime_skill(skill_data):
			continue
		var tags: Array = skill_data.get("tags", [])
		if not tags.has("basic"):
			return skill_id
		if fallback_skill_id == "":
			fallback_skill_id = skill_id
	return fallback_skill_id


func _get_skill_data(skill_id: String) -> Dictionary:
	return DataLoader.skills.get(skill_id, {})


func _is_supported_runtime_skill(skill_data: Dictionary) -> bool:
	if skill_data.is_empty():
		return false
	if str(skill_data.get("action_cost", "")) != "standard":
		return false
	if int(skill_data.get("power", 0)) <= 0:
		return false
	var damage_type: String = str(skill_data.get("damage_type", ""))
	if damage_type not in ["physical", "magical", "pure", "hybrid"]:
		return false
	var range_data: Dictionary = skill_data.get("range", {})
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
