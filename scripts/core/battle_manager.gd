class_name BattleManager
extends Node

@onready var turn_manager: TurnManager = $TurnManager
@onready var highlight_layer: Node2D = $HighlightLayer

var grid: Grid = Grid.new()
var units: Array = []

signal battle_started
signal unit_action_completed(unit: Unit)

enum InputState { IDLE, UNIT_SELECTED }
var input_state := InputState.IDLE
var current_unit: Unit = null
var selected_unit: Unit = null
var _move_range: Dictionary = {}


func _ready() -> void:
	setup_battle("forest_01")
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
	turn_manager.remove_unit(unit)


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
	await get_tree().create_timer(0.5).timeout
	if turn_manager.current_unit == unit:
		turn_manager.end_current_turn()


# ── Input handling ───────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if current_unit == null or current_unit.faction != "player":
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
			if grid_pos in _move_range:
				_execute_move(selected_unit, grid_pos)
			elif selected_unit != null \
					and grid_pos == selected_unit.grid_position:
				_deselect_unit()


func _select_unit(unit: Unit) -> void:
	selected_unit = unit
	input_state = InputState.UNIT_SELECTED
	_move_range = Pathfinding.get_move_range(
		grid, unit.grid_position, unit.stats.move, unit.faction)
	_move_range.erase(unit.grid_position)
	_show_highlights()


func _deselect_unit() -> void:
	selected_unit = null
	input_state = InputState.IDLE
	_move_range = {}
	_clear_highlights()


# ── Highlight ────────────────────────────────────────

func _show_highlights() -> void:
	_clear_highlights()
	for cell_pos: Vector2i in _move_range:
		var rect := ColorRect.new()
		rect.color = Color(0.2, 0.5, 1.0, 0.4)
		rect.size = Vector2(Grid.CELL_SIZE)
		rect.position = grid.grid_to_world(cell_pos) - Vector2(Grid.CELL_SIZE) / 2.0
		highlight_layer.add_child(rect)


func _clear_highlights() -> void:
	for child in highlight_layer.get_children():
		child.queue_free()


# ── Action execution ─────────────────────────────────

func _execute_move(unit: Unit, target: Vector2i) -> void:
	var action := GameAction.make_move(unit, target)
	_apply_action(action)


func _apply_action(action: GameAction) -> void:
	match action.type:
		GameAction.Type.MOVE:
			var from := action.actor.grid_position
			action.actor.has_moved = true
			_clear_highlights()
			input_state = InputState.IDLE
			selected_unit = null
			_move_range = {}
			await action.actor.move_to(action.target_pos, grid)
			grid.move_unit(action.actor, from, action.target_pos)
			turn_manager.end_current_turn()
		GameAction.Type.END_TURN:
			turn_manager.end_current_turn()
