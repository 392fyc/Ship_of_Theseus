extends Node2D
## BattleScene controller: spawns units, starts battle, handles victory/defeat.

@onready var battle_manager: BattleManager = $BattleManager
@onready var result_overlay: ColorRect = $UILayer/ResultOverlay
@onready var result_label: Label = $UILayer/ResultLabel

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
	battle_manager.initialize_battle("forest_01")

	for cfg: Dictionary in PLAYER_UNITS:
		var pos: Vector2i = cfg["pos"]
		battle_manager.spawn_unit(cfg["class_id"], pos, "player")

	for cfg: Dictionary in ENEMY_UNITS:
		var pos: Vector2i = cfg["pos"]
		battle_manager.spawn_unit(cfg["class_id"], pos, "enemy")

	print("[BattleScene] Units spawned: %d" % battle_manager.units.size())

	battle_manager.unit_killed.connect(_on_unit_killed)

	result_overlay.visible = false
	result_label.visible = false

	battle_manager.start_battle()


# ── Victory / Defeat ─────────────────────────────────

func _on_unit_killed(unit: Unit) -> void:
	print("[BattleScene] Unit killed: %s (%s) | remaining: %d" % [
		unit.unit_name, unit.faction, battle_manager.units.size()])
	if _battle_over:
		return
	_check_battle_end()


func _check_battle_end() -> void:
	var has_player: bool = false
	var has_enemy: bool = false
	for u in battle_manager.units:
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
	battle_manager.stop_battle()

	result_overlay.visible = true
	result_label.visible = true

	if result == "victory":
		result_label.text = "VICTORY"
		result_label.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.2))
		print("[BattleScene] === VICTORY ===")
	else:
		result_label.text = "DEFEAT"
		result_label.add_theme_color_override("font_color",
			Color(1.0, 0.3, 0.3))
		print("[BattleScene] === DEFEAT ===")

	battle_ended.emit(result)
