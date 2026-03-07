extends Node2D
## TacticalScene controller: spawns units, starts battle, handles victory/defeat.

@onready var tactical_manager: TacticalManager = $TacticalManager
@onready var result_overlay: ColorRect = $UILayer/ResultOverlay
@onready var result_label: Label = $UILayer/ResultLabel

var _turn_order_bar: TurnOrderBar = null

signal battle_ended(result: String)

# ── Spawn configuration ──────────────────────────────

const PLAYER_UNITS: Array[Dictionary] = [
	{"class_id": "soldier",  "pos": Vector2i(1, 3)},
	{"class_id": "soldier",  "pos": Vector2i(1, 4)},
	{"class_id": "archer",   "pos": Vector2i(2, 2)},
]

const ENEMY_UNITS: Array[Dictionary] = [
	{"class_id": "goblin_melee",  "pos": Vector2i(6, 3)},
	{"class_id": "goblin_archer", "pos": Vector2i(6, 5)},
]

var _battle_over: bool = false


func _ready() -> void:
	tactical_manager.initialize_battle("forest_01")

	for cfg: Dictionary in PLAYER_UNITS:
		var pos: Vector2i = cfg["pos"]
		tactical_manager.spawn_unit(cfg["class_id"], pos, "player")

	for cfg: Dictionary in ENEMY_UNITS:
		var pos: Vector2i = cfg["pos"]
		tactical_manager.spawn_unit(cfg["class_id"], pos, "enemy")

	print("[TacticalScene] Units spawned: %d" % tactical_manager.units.size())

	tactical_manager.unit_killed.connect(_on_unit_killed)

	_turn_order_bar = TurnOrderBar.new()
	$UILayer.add_child(_turn_order_bar)
	tactical_manager.turn_manager.turn_started.connect(_on_turn_changed)
	tactical_manager.turn_manager.turn_ended.connect(_on_turn_changed)

	result_overlay.visible = false
	result_label.visible = false

	tactical_manager.start_battle()


# ── Victory / Defeat ─────────────────────────────────

func _on_turn_changed(_unit: Unit) -> void:
	_refresh_turn_order()


func _refresh_turn_order() -> void:
	if _turn_order_bar == null:
		return
	var queue := tactical_manager.turn_manager.get_display_queue()
	_turn_order_bar.update_queue(queue,
		tactical_manager.turn_manager.current_unit)


func _on_unit_killed(unit: Unit) -> void:
	print("[TacticalScene] Unit killed: %s (%s) | remaining: %d" % [
		unit.unit_name, unit.faction, tactical_manager.units.size()])
	_refresh_turn_order.call_deferred()
	if _battle_over:
		return
	_check_battle_end()


func _check_battle_end() -> void:
	var has_player: bool = false
	var has_enemy: bool = false
	for u in tactical_manager.units:
		if u.stats.is_alive():
			if u.faction == "player":
				has_player = true
			else:
				has_enemy = true

	if not has_player:
		_end_battle("defeat")
	elif not has_enemy:
		_end_battle("victory")


func _end_battle(result: String) -> void:
	_battle_over = true
	tactical_manager.stop_battle()

	result_overlay.visible = true
	result_label.visible = true

	if result == "victory":
		result_label.text = "VICTORY"
		result_label.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.2))
		print("[TacticalScene] === VICTORY ===")
	else:
		result_label.text = "DEFEAT"
		result_label.add_theme_color_override("font_color",
			Color(1.0, 0.3, 0.3))
		print("[TacticalScene] === DEFEAT ===")

	battle_ended.emit(result)
