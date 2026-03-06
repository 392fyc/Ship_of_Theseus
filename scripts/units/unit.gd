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
var attack_range: int = 1

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

# ── 阵营颜色 ─────────────────────────────────────────
const FACTION_COLORS: Dictionary = {
	"player": Color(0.30, 0.55, 1.00),
	"enemy":  Color(1.00, 0.30, 0.30),
}

const UNIT_LABELS: Dictionary = {
	"soldier":       "兵",
	"archer":        "弓",
	"knight":        "骑",
	"mage":          "法",
	"cleric":        "僧",
	"goblin_melee":  "哥战",
	"goblin_archer": "哥弓",
	"goblin_shaman": "哥巫",
}

# ── HP Bar — Proposal B Classic TRPG ─────────────────
const HP_FULL_COLOR  := Color(0.24, 0.68, 0.24)
const HP_LOW_COLOR   := Color(0.82, 0.55, 0.15)
const HP_CRIT_COLOR  := Color(0.82, 0.18, 0.18)
const HP_BAR_BG      := Color(0.15, 0.15, 0.18)
const HP_BAR_BORDER  := Color(0.06, 0.06, 0.08)

# ── 节点引用 ─────────────────────────────────────────
@onready var sprite: AnimatedSprite2D = $Sprite
@onready var health_bar: ProgressBar  = $HealthBar
var _unit_label: Label = null
var _hp_label: Label = null


func _ready() -> void:
	_update_health_bar()


func setup(class_data: Dictionary) -> void:
	unit_id   = class_data.get("id", "")
	unit_name = class_data.get("name", "Unit")
	stats = UnitStats.new()
	var stat_dict: Dictionary = class_data.get("base_stats", {}).duplicate()
	# MOV and VIS are top-level fields in the JSON
	for key: String in ["MOV", "VIS"]:
		if class_data.has(key):
			stat_dict[key] = class_data[key]
	stats.load_from_dict(stat_dict)
	# Load growth rates if present (class JSON has them, enemy JSON doesn't)
	if class_data.has("growth_rates"):
		stats.load_growth_rates(class_data["growth_rates"])
	var atk_type: String = class_data.get("attack_type", "melee")
	attack_range = 2 if atk_type == "ranged" else 1
	_update_health_bar()
	_apply_visuals()


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
	modulate = Color.WHITE


func mark_done() -> void:
	has_attacked = true
	modulate = Color(0.6, 0.6, 0.6)


# ── 私有方法 ─────────────────────────────────────────

func _apply_visuals() -> void:
	sprite.self_modulate = FACTION_COLORS.get(faction, Color.WHITE)

	# B-style HP bar: dark bg with border
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = HP_BAR_BG
	bg_style.border_width_left = 2
	bg_style.border_width_top = 2
	bg_style.border_width_right = 2
	bg_style.border_width_bottom = 2
	bg_style.border_color = HP_BAR_BORDER
	health_bar.add_theme_stylebox_override("background", bg_style)
	_update_health_bar()

	# HP number overlay centered on bar
	_hp_label = Label.new()
	_hp_label.name = "HPLabel"
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_label.position = health_bar.position
	_hp_label.size = health_bar.size
	_hp_label.add_theme_font_size_override("font_size", 9)
	_hp_label.add_theme_color_override("font_color", Color.WHITE)
	_hp_label.add_theme_color_override("font_outline_color",
		Color(0.0, 0.0, 0.0, 0.80))
	_hp_label.add_theme_constant_override("outline_size", 2)
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_label)

	_unit_label = Label.new()
	_unit_label.name = "UnitLabel"
	_unit_label.text = UNIT_LABELS.get(unit_id, unit_name.left(2))
	_unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_unit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_unit_label.position = Vector2(-32, -14)
	_unit_label.size = Vector2(64, 28)
	_unit_label.add_theme_font_size_override("font_size", 18)
	_unit_label.add_theme_color_override("font_color", Color.WHITE)
	_unit_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_unit_label.add_theme_constant_override("outline_size", 3)
	_unit_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_unit_label)


func _update_health_bar() -> void:
	if health_bar == null or stats == null:
		return
	health_bar.max_value = stats.max_hp
	health_bar.value     = stats.hp

	var ratio := float(stats.hp) / float(stats.max_hp) if stats.max_hp > 0 else 0.0
	var fill_color: Color
	if ratio > 0.6:
		fill_color = HP_FULL_COLOR
	elif ratio > 0.3:
		fill_color = HP_LOW_COLOR
	else:
		fill_color = HP_CRIT_COLOR
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	health_bar.add_theme_stylebox_override("fill", fill_style)

	if _hp_label:
		_hp_label.text = "%d / %d" % [stats.hp, stats.max_hp]


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
