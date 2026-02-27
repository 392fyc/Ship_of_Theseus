class_name Unit
extends Node2D

# ── 身份 ────────────────────────────────────────────
@export var unit_id:    String = ""
@export var unit_name:  String = "Unit"
@export var faction:    String = "player"  # "player" | "enemy"
var priority: int = 0  # initiative tie-breaker (0/+1/+2)

# ── 数据 ────────────────────────────────────────────
var stats: UnitStats = null
var buffs: Array = []

# ── 位置（ADR-3 双向引用）──────────────────────────
var grid_position: Vector2i = Vector2i.ZERO

# ── 行动资源（Milestone 4）──────────────────────────
var has_moved:      bool = false
var has_attacked:   bool = false
var has_used_swift: bool = false

# ── 信号 ────────────────────────────────────────────
signal damage_taken(amount: int, damage_type: String)
signal unit_died
signal moved(from: Vector2i, to: Vector2i)

# ── 节点引用 ─────────────────────────────────────────
@onready var sprite: AnimatedSprite2D = $Sprite
@onready var health_bar: ProgressBar  = $HealthBar


func _ready() -> void:
	_update_health_bar()


func setup(class_data: Dictionary) -> void:
	unit_id   = class_data.get("id", "")
	unit_name = class_data.get("name", "Unit")
	stats = UnitStats.new()
	var stat_dict: Dictionary = class_data.get("base_stats", {}).duplicate()
	for key in ["speed", "move", "vision", "block"]:
		if class_data.has(key):
			stat_dict[key] = class_data[key]
	stats.load_from_dict(stat_dict)
	_update_health_bar()


# ── 战斗接口 ─────────────────────────────────────────

func take_damage(amount: int, damage_type: String = "physical") -> void:
	stats.take_damage(amount)
	damage_taken.emit(amount, damage_type)
	_update_health_bar()
	if not stats.is_alive():
		unit_died.emit()
		_on_death()


func heal(amount: int) -> void:
	stats.heal(amount)
	_update_health_bar()


# ── 移动动画 ─────────────────────────────────────────

func move_to(target_pos: Vector2i, grid: Grid) -> void:
	var world_target := grid.grid_to_world(target_pos)
	var dir := target_pos - grid_position
	_set_walk_direction(dir)
	var tween := create_tween()
	tween.tween_property(self, "position", world_target, 0.25)
	await tween.finished
	sprite.play("idle")
	moved.emit(grid_position, target_pos)


# ── 回合状态重置（TurnManager 调用）─────────────────

func reset_turn_state() -> void:
	has_moved      = false
	has_attacked   = false
	has_used_swift = false
	sprite.modulate = Color.WHITE


func mark_done() -> void:
	has_attacked = true
	sprite.modulate = Color(0.5, 0.5, 0.5)


# ── 私有方法 ─────────────────────────────────────────

func _update_health_bar() -> void:
	if health_bar == null or stats == null:
		return
	health_bar.max_value = stats.max_hp
	health_bar.value     = stats.hp


func _set_walk_direction(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO:
		return
	if dir.y < 0:
		sprite.play("walk_north")
	elif dir.y > 0:
		sprite.play("walk_south")
	elif dir.x < 0:
		sprite.play("walk_west")
	else:
		sprite.play("walk_east")


func _on_death() -> void:
	sprite.play("death")
	await sprite.animation_finished
	queue_free()
