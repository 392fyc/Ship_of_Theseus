class_name BattleManager
extends Node

@onready var turn_manager: TurnManager = $TurnManager
@onready var terrain_layer: Node2D = $TerrainLayer
@onready var highlight_layer: Node2D = $HighlightLayer

var grid: Grid = Grid.new()
var units: Array = []

signal battle_started
signal unit_action_completed(unit: Unit)

enum InputState { IDLE, UNIT_SELECTED, ATTACK_SELECT, ANIMATING }
var input_state := InputState.IDLE
var current_unit: Unit = null
var selected_unit: Unit = null
var _move_range: Dictionary = {}
var _attack_cells: Array[Vector2i] = []


func _ready() -> void:
	setup_battle("forest_01")
	_render_terrain()
	spawn_unit("soldier", Vector2i(1, 1), "player")
	spawn_unit("goblin_melee", Vector2i(5, 5), "enemy")
	print("[Test] Units spawned: ", units.size())

	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.turn_ended.connect(_on_turn_ended)
	turn_manager.round_ended.connect(_on_round_ended)

	var typed_units: Array[Unit] = []
	for u in units:
		typed_units.append(u)
	turn_manager.add_units(typed_units)
	turn_manager.start()

	_print_deduction_data()


func setup_battle(map_id: String) -> void:
	var map_data: Dictionary = DataLoader.maps.get(map_id, {})
	if map_data.is_empty():
		push_error("[BattleManager] Map not found: " + map_id)
		return
	grid.initialize(map_data)
	battle_started.emit()


func spawn_unit(class_id: String, spawn_pos: Vector2i,
				faction: String) -> Unit:
	var class_data: Dictionary = DataLoader.classes.get(class_id, {})
	if class_data.is_empty():
		class_data = DataLoader.enemies.get(class_id, {})
	if class_data.is_empty():
		push_error("[BattleManager] Class/enemy not found: " + class_id)
		return null
	var unit_scene := preload("res://scenes/battle/Unit.tscn")
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
	grid.remove_unit(unit)
	units.erase(unit)
	var was_active := (turn_manager.current_unit == unit)
	turn_manager.remove_unit(unit)
	if was_active:
		_deselect_unit()
		turn_manager.force_advance.call_deferred()
	_check_battle_end()


func _check_battle_end() -> void:
	var has_player := false
	var has_enemy := false
	for u in units:
		if u.stats.is_alive():
			if u.faction == "player":
				has_player = true
			else:
				has_enemy = true
	if not has_player:
		print("[Battle] Defeat!")
	elif not has_enemy:
		print("[Battle] Victory!")


# ── Turn callbacks ───────────────────────────────────

func _on_turn_started(unit: Unit) -> void:
	current_unit = unit
	unit.reset_turn_state()
	print("[TurnManager] Turn: %s (%s)" % [unit.unit_name, unit.faction])
	if unit.faction != "player":
		_do_enemy_turn(unit)


func _on_turn_ended(_unit: Unit) -> void:
	_deselect_unit()


func _on_round_ended() -> void:
	print("[TurnManager] === Round ended ===")


func _do_enemy_turn(unit: Unit) -> void:
	await get_tree().create_timer(0.3).timeout
	if turn_manager.current_unit != unit:
		return
	var target := _find_adjacent_enemy(unit)
	if target:
		var action := GameAction.make_attack(unit, target)
		_execute_attack_action(action)
	if turn_manager.current_unit == unit:
		turn_manager.end_current_turn()


func _find_adjacent_enemy(unit: Unit) -> Unit:
	for offset: Vector2i in [Vector2i(0, -1), Vector2i(0, 1),
					Vector2i(-1, 0), Vector2i(1, 0)]:
		var pos: Vector2i = unit.grid_position + offset
		var target = grid.get_unit_at(pos)
		if target and target.faction != unit.faction \
				and target.stats.is_alive():
			return target
	return null


# ── Input handling ───────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if current_unit == null or current_unit.faction != "player":
		return
	if input_state == InputState.ANIMATING:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var world_pos := Vector2(get_viewport().get_mouse_position())
		var grid_pos := grid.world_to_grid(world_pos)
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
			elif grid_pos in _move_range:
				_execute_move(selected_unit, grid_pos)
		InputState.ATTACK_SELECT:
			var target = grid.get_unit_at(grid_pos)
			if target and target.faction != current_unit.faction \
					and grid_pos in _attack_cells:
				var action := GameAction.make_attack(current_unit, target)
				_execute_attack_from_input(action)
			else:
				_end_turn_from_attack_select()


func _select_unit(unit: Unit) -> void:
	selected_unit = unit
	input_state = InputState.UNIT_SELECTED
	_move_range = Pathfinding.get_move_range(
		grid, unit.grid_position, unit.stats.move, unit.faction)
	_move_range.erase(unit.grid_position)
	_show_move_highlights()


func _deselect_unit() -> void:
	selected_unit = null
	input_state = InputState.IDLE
	_move_range = {}
	_attack_cells = []
	_clear_highlights()


func _enter_attack_select() -> void:
	_clear_highlights()
	_move_range = {}
	input_state = InputState.ATTACK_SELECT
	_attack_cells = _get_attack_range(current_unit.grid_position)
	_show_attack_highlights()


func _end_turn_from_attack_select() -> void:
	_clear_highlights()
	_attack_cells = []
	input_state = InputState.IDLE
	selected_unit = null
	turn_manager.end_current_turn()


# ── Highlight ────────────────────────────────────────

func _show_move_highlights() -> void:
	_clear_highlights()
	for cell_pos: Vector2i in _move_range:
		_add_highlight(cell_pos, Color(0.2, 0.5, 1.0, 0.4))


func _show_attack_highlights() -> void:
	_clear_highlights()
	for cell_pos: Vector2i in _attack_cells:
		_add_highlight(cell_pos, Color(1.0, 0.2, 0.2, 0.4))


func _add_highlight(cell_pos: Vector2i, color: Color) -> void:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size = Vector2(Grid.CELL_SIZE)
	rect.position = grid.grid_to_world(cell_pos) - Vector2(Grid.CELL_SIZE) / 2.0
	highlight_layer.add_child(rect)


func _clear_highlights() -> void:
	for child in highlight_layer.get_children():
		child.queue_free()


func _get_attack_range(origin: Vector2i, _atk_range: int = 1) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset: Vector2i in [Vector2i(0, -1), Vector2i(0, 1),
					Vector2i(-1, 0), Vector2i(1, 0)]:
		var pos: Vector2i = origin + offset
		if grid.is_valid(pos):
			result.append(pos)
	return result


# ── Action execution ─────────────────────────────────

func _execute_move(unit: Unit, target: Vector2i) -> void:
	input_state = InputState.ANIMATING
	var from := unit.grid_position
	unit.has_moved = true
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


func _execute_attack_action(action: GameAction) -> void:
	var attacker: Unit = action.actor
	var defender: Unit = action.target_unit
	if not attacker or not defender:
		return
	if not attacker.stats.is_alive() or not defender.stats.is_alive():
		return

	attacker.has_attacked = true
	var data: Dictionary = action.data

	# Steps 1-7: main attack
	var result := DamageCalculator.resolve_attack(attacker, defender, data)
	_log_attack(attacker, defender, result, "")

	if result.defender_died:
		return

	# Step 8: counter-attack
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
		if counter_result.defender_died:
			result.attacker_died = true
			return

	# Step 9: pursuit
	var allow_pursuit: bool = data.get("allow_pursuit", true)
	if allow_pursuit and result.hit \
			and attacker.stats.is_alive() and defender.stats.is_alive():
		var pursuit_chance := clampf(
			(attacker.stats.speed - defender.stats.speed) * 0.1, 0.0, 1.0)
		if randf() < pursuit_chance:
			var pursuit_data := {
				"damage_type": data.get("damage_type", "physical"),
				"skill_multiplier": 1.0,
				"terrain_multiplier": 1.0,
			}
			var pursuit_result := DamageCalculator.resolve_attack(
				attacker, defender, pursuit_data)
			_log_attack(attacker, defender, pursuit_result, "Pursuit")


func _is_adjacent(a: Unit, b: Unit) -> bool:
	var dist := absi(a.grid_position.x - b.grid_position.x) \
			  + absi(a.grid_position.y - b.grid_position.y)
	return dist <= 1


func _log_attack(attacker: Unit, defender: Unit,
		result: DamageCalculator.AttackResult, tag: String) -> void:
	var prefix := (tag + ": ") if tag != "" else ""
	print("[Attack] %s%s→%s | hit=%s | blocked=%s | crit=%s | dmg=%d" % [
		prefix, attacker.unit_name, defender.unit_name,
		result.hit, result.blocked, result.crit, result.damage])


# ── Terrain rendering ────────────────────────────────

const TERRAIN_COLORS: Dictionary = {
	Cell.Terrain.PLAIN:         Color(0.72, 0.85, 0.55),
	Cell.Terrain.FOREST:        Color(0.30, 0.58, 0.32),
	Cell.Terrain.MOUNTAIN:      Color(0.65, 0.55, 0.40),
	Cell.Terrain.PEAK:          Color(0.45, 0.45, 0.50),
	Cell.Terrain.WALL:          Color(0.40, 0.35, 0.30),
	Cell.Terrain.SHALLOW_WATER: Color(0.50, 0.72, 0.88),
	Cell.Terrain.DEEP_WATER:    Color(0.22, 0.40, 0.70),
	Cell.Terrain.LAVA:          Color(0.88, 0.30, 0.12),
	Cell.Terrain.SWAMP:         Color(0.42, 0.50, 0.30),
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

	var cell_size := Vector2(Grid.CELL_SIZE)

	for row in grid.height:
		for col in grid.width:
			var cell := grid.get_cell(Vector2i(col, row))
			if cell == null:
				continue
			var world_pos: Vector2 = grid.grid_to_world(Vector2i(col, row)) \
				- cell_size / 2.0

			var rect := ColorRect.new()
			rect.color = TERRAIN_COLORS.get(cell.terrain, Color.WHITE)
			rect.size = cell_size
			rect.position = world_pos
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			terrain_layer.add_child(rect)

			var border := ReferenceRect.new()
			border.size = cell_size
			border.position = world_pos
			border.border_color = Color(0.0, 0.0, 0.0, 0.25)
			border.border_width = 1.0
			border.editor_only = false
			border.mouse_filter = Control.MOUSE_FILTER_IGNORE
			terrain_layer.add_child(border)

			var label_text: String = TERRAIN_LABELS.get(cell.terrain, "")
			if label_text != "":
				var label := Label.new()
				label.text = label_text
				label.position = world_pos + Vector2(2, 1)
				label.add_theme_font_size_override("font_size", 11)
				label.add_theme_color_override("font_color",
					Color(1, 1, 1, 0.6))
				label.mouse_filter = Control.MOUSE_FILTER_IGNORE
				terrain_layer.add_child(label)


# ── Deduction Data (M5) ─────────────────────────────

func _print_deduction_data() -> void:
	var soldier: Unit = null
	var goblin: Unit = null
	for u in units:
		if u.unit_id == "soldier":
			soldier = u
		elif u.unit_id == "goblin_melee":
			goblin = u
	if not soldier or not goblin:
		return

	var s_base_dmg := maxi(0, soldier.stats.phys_atk - goblin.stats.physical_defense)
	var g_base_dmg := maxi(0, goblin.stats.phys_atk - soldier.stats.physical_defense)
	var s_hit_rate := clampi(soldier.stats.hit - goblin.stats.evade, 20, 100)
	var g_hit_rate := clampi(goblin.stats.hit - soldier.stats.evade, 20, 100)

	var s_ttk_clean: int = ceili(float(goblin.stats.max_hp) / s_base_dmg) if s_base_dmg > 0 else 999
	var s_ttk_expected: float = ceil(float(s_ttk_clean) / (s_hit_rate / 100.0))
	var g_ttk_clean: int = ceili(float(soldier.stats.max_hp) / g_base_dmg) if g_base_dmg > 0 else 999
	var g_ttk_expected: float = ceil(float(g_ttk_clean) / (g_hit_rate / 100.0))

	print("[DEDUCTION_DATA] ========================================")
	print("[DEDUCTION_DATA] M5 属性推演基础数据")
	print("[DEDUCTION_DATA] ----------------------------------------")
	print("[DEDUCTION_DATA] soldier: phys_atk=%d, def=%d, hit=%d, crit=%d, speed=%d, HP=%d" % [
		soldier.stats.phys_atk, soldier.stats.physical_defense,
		soldier.stats.hit, soldier.stats.crit, soldier.stats.speed, soldier.stats.max_hp])
	print("[DEDUCTION_DATA] goblin:  phys_atk=%d, def=%d, evade=%d, block=%d, speed=%d, HP=%d" % [
		goblin.stats.phys_atk, goblin.stats.physical_defense,
		goblin.stats.evade, goblin.stats.block, goblin.stats.speed, goblin.stats.max_hp])
	print("[DEDUCTION_DATA] ----------------------------------------")
	print("[DEDUCTION_DATA] soldier→goblin 单次基础伤害: %d" % s_base_dmg)
	print("[DEDUCTION_DATA] soldier 命中率: %d%%" % s_hit_rate)
	print("[DEDUCTION_DATA] soldier TTK(全命中): %d 回合" % s_ttk_clean)
	print("[DEDUCTION_DATA] soldier TTK(期望): %.1f 回合" % s_ttk_expected)
	print("[DEDUCTION_DATA] ----------------------------------------")
	print("[DEDUCTION_DATA] goblin→soldier 单次基础伤害: %d" % g_base_dmg)
	print("[DEDUCTION_DATA] goblin 命中率: %d%%" % g_hit_rate)
	print("[DEDUCTION_DATA] goblin TTK(全命中): %d 回合" % g_ttk_clean)
	print("[DEDUCTION_DATA] goblin TTK(期望): %.1f 回合" % g_ttk_expected)
	print("[DEDUCTION_DATA] ----------------------------------------")
	print("[DEDUCTION_DATA] 防御比率 goblin.def/soldier.atk = %.0f%%" % (
		goblin.stats.physical_defense * 100.0 / soldier.stats.phys_atk))
	print("[DEDUCTION_DATA] 防御比率 soldier.def/goblin.atk = %.0f%%" % (
		soldier.stats.physical_defense * 100.0 / goblin.stats.phys_atk))
	print("[DEDUCTION_DATA] ========================================")
