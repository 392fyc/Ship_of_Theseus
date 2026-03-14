class_name Unit
extends Node2D

# ── 身份 ────────────────────────────────────────────
@export var unit_id: String = ""
@export var unit_name: String = "Unit"
@export var faction: String = "player"  # "player" | "enemy"
var priority: int = 0  # initiative tie-breaker (0/+1/+2)

# ── 数据 ────────────────────────────────────────────
var stats: UnitStats = null
var buffs: Array[BuffEffect] = []
var attack_range: int = 1
var skill_ids: Array[String] = []
var skill_cooldowns: Dictionary = {}

# ── 位置（ADR-3 双向引用）──────────────────────────
var grid_position: Vector2i = Vector2i.ZERO

# ── 行动资源（Milestone 8 Action Economy）───────────
var has_moved: bool = false
var has_attacked: bool = false
var has_used_swift: bool = false
var movement_used: bool = false
var standard_used: bool = false
var swift_used: bool = false
var reaction_available: bool = true

# ── 信号 ────────────────────────────────────────────
signal damage_taken(amount: int, damage_type: String)
signal unit_died
signal moved(from: Vector2i, to: Vector2i)
signal buffs_changed(unit: Unit)

# ── 阵营颜色 ─────────────────────────────────────────
const FACTION_COLORS: Dictionary = {
	"player": Color(0.30, 0.55, 1.00),
	"enemy": Color(1.00, 0.30, 0.30),
}

const UNIT_LABELS: Dictionary = {
	"soldier": "兵",
	"archer": "弓",
	"knight": "骑",
	"mage": "法",
	"cleric": "僧",
	"goblin_melee": "哥战",
	"goblin_archer": "哥弓",
	"goblin_shaman": "哥巫",
}

# ── HP Bar — Proposal B Classic TRPG ─────────────────
const HP_FULL_COLOR := Color(0.24, 0.68, 0.24)
const HP_LOW_COLOR := Color(0.82, 0.55, 0.15)
const HP_CRIT_COLOR := Color(0.82, 0.18, 0.18)
const HP_BAR_BG := Color(0.15, 0.15, 0.18)
const HP_BAR_BORDER := Color(0.06, 0.06, 0.08)
const UNIT_ICON_SCALE: Vector2 = Vector2(0.45, 0.45)
const STATUS_BADGE_STEP: float = 18.0
const STATUS_BADGE_Y: float = -58.0
const ACTION_BADGE_Y: float = 20.0

# ── 节点引用 ─────────────────────────────────────────
@onready var sprite: AnimatedSprite2D = $Sprite
@onready var health_bar: ProgressBar = $HealthBar
@onready var status_icons: Node2D = $StatusIcons
var _unit_label: Label = null
var _hp_label: Label = null


func _ready() -> void:
	_update_health_bar()
	_rebuild_status_icons()


func setup(class_data: Dictionary) -> void:
	unit_id = str(class_data.get("id", ""))
	unit_name = str(class_data.get("name", "Unit"))
	priority = 0
	stats = UnitStats.new()
	buffs.clear()
	skill_ids.clear()
	for skill_id_value: Variant in class_data.get("skill_ids", []):
		skill_ids.append(str(skill_id_value))
	skill_cooldowns.clear()
	var stat_dict: Dictionary = class_data.get("base_stats", {}).duplicate()
	for key: String in ["MOV", "VIS"]:
		if class_data.has(key):
			stat_dict[key] = class_data[key]
	stats.load_from_dict(stat_dict)
	if class_data.has("growth_rates"):
		stats.load_growth_rates(class_data["growth_rates"])
	var atk_type: String = str(class_data.get("attack_type", "melee"))
	attack_range = 2 if atk_type == "ranged" else 1
	_update_health_bar()
	_apply_visuals()
	_rebuild_status_icons()
	_emit_buffs_changed()


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


# ── Buff / Debuff 接口 ──────────────────────────────

func add_buff(buff: BuffEffect) -> void:
	if buff == null:
		return
	var existing: BuffEffect = get_buff(buff.buff_id)
	if existing != null and not buff.stackable:
		if buff.refresh_on_reapply:
			existing.duration = buff.max_duration
			existing.max_duration = buff.max_duration
			existing.value = buff.value
			existing.stat_key = buff.stat_key
			existing.is_percentage = buff.is_percentage
			existing.source_unit_id = buff.source_unit_id
			existing.apply(self)
			_emit_buffs_changed()
		return
	if buff.stackable:
		var stack_count: int = count_buff_stacks(buff.buff_id)
		if buff.max_stacks > 0 and stack_count >= buff.max_stacks:
			return
	buffs.append(buff)
	buff.apply(self)
	_emit_buffs_changed()


func remove_buff(buff: BuffEffect) -> void:
	if buff == null or buff not in buffs:
		return
	buff.unapply(self)
	buffs.erase(buff)
	_emit_buffs_changed()


func get_buff(buff_id: String) -> BuffEffect:
	for buff: BuffEffect in buffs:
		if buff.buff_id == buff_id:
			return buff
	return null


func has_buff(buff_id: String) -> bool:
	return get_buff(buff_id) != null


func count_buff_stacks(buff_id: String) -> int:
	var stack_count: int = 0
	for buff: BuffEffect in buffs:
		if buff.buff_id == buff_id:
			stack_count += 1
	return stack_count


func process_turn_start_buffs() -> Dictionary:
	var result: Dictionary = {"skip_turn": false}
	var buff_snapshot: Array[BuffEffect] = buffs.duplicate()
	for buff: BuffEffect in buff_snapshot:
		if buff.trigger != "turn_start":
			continue
		var tick_result: Dictionary = buff.tick(self)
		if bool(tick_result.get("skip_turn", false)):
			result["skip_turn"] = true
		if not stats.is_alive():
			break
	return result


func process_turn_end_buffs() -> void:
	var buff_snapshot: Array[BuffEffect] = buffs.duplicate()
	var duration_changed: bool = false
	for buff: BuffEffect in buff_snapshot:
		if buff.duration > 0:
			buff.duration -= 1
			duration_changed = true
		if buff.duration == 0:
			remove_buff(buff)
	if duration_changed:
		_emit_buffs_changed()


func handle_attacked() -> void:
	var freeze_buff: BuffEffect = get_buff("freeze")
	if freeze_buff != null:
		remove_buff(freeze_buff)


func get_effective_stat(stat_key: String) -> int:
	var normalized_key: String = _normalize_stat_key(stat_key)
	var base_value: int = _get_base_stat_value(normalized_key)
	var flat_modifier: float = 0.0
	var percentage_modifier: float = 0.0
	for buff: BuffEffect in buffs:
		if buff.effect_type != "stat_mod":
			continue
		if _normalize_stat_key(buff.stat_key) != normalized_key:
			continue
		if buff.is_percentage:
			percentage_modifier += buff.value
		else:
			flat_modifier += buff.value
	var effective_value: float = float(base_value) + flat_modifier
	effective_value += float(base_value) * percentage_modifier / 100.0
	return roundi(effective_value)


func get_effective_priority() -> int:
	return get_effective_stat("PRIORITY")


func get_hit_value(weapon_hit: int = 90) -> int:
	var effective_dex: int = get_effective_stat("DEX")
	var effective_lck: int = get_effective_stat("LCK")
	return weapon_hit + effective_dex * 2 + roundi(effective_lck * 0.5)


func get_avoid_value(terrain_evade_bonus: int = 0) -> int:
	var effective_spd: int = get_effective_stat("SPD")
	var effective_lck: int = get_effective_stat("LCK")
	return effective_spd * 2 + roundi(effective_lck * 0.5) + terrain_evade_bonus


func get_crit_value(weapon_crit: int = 0) -> int:
	var effective_dex: int = get_effective_stat("DEX")
	return weapon_crit + int(effective_dex / 2.0)


func get_crit_avoid_value() -> int:
	return get_effective_stat("LCK")


func get_status_resist_multiplier() -> float:
	var effective_lck: int = get_effective_stat("LCK")
	return maxf(0.1, 1.0 - float(effective_lck) / 100.0)


func serialize_buffs() -> Array[Dictionary]:
	var serialized: Array[Dictionary] = []
	for buff: BuffEffect in buffs:
		serialized.append(buff.to_dict())
	return serialized


func load_buffs_from_state(buff_state: Array[Dictionary]) -> void:
	buffs.clear()
	for buff_entry: Dictionary in buff_state:
		buffs.append(BuffEffect.from_dict(buff_entry))
	_emit_buffs_changed()


# ── 移动动画 ─────────────────────────────────────────

func move_to(target_pos: Vector2i, grid: Grid) -> void:
	var world_target: Vector2 = grid.grid_to_world(target_pos)
	var dir: Vector2i = target_pos - grid_position
	_set_walk_direction(dir)
	var tween: Tween = create_tween()
	tween.tween_property(self, "position", world_target, 0.25)
	await tween.finished
	sprite.play("idle")
	moved.emit(grid_position, target_pos)


# ── 回合状态重置（TurnManager 调用）─────────────────

func reset_turn_state() -> void:
	reset_action_resources()
	modulate = Color.WHITE
	_tick_skill_cooldowns()
	_rebuild_status_icons()


func mark_done() -> void:
	modulate = Color(0.6, 0.6, 0.6)
	_rebuild_status_icons()


func get_short_label() -> String:
	return str(UNIT_LABELS.get(unit_id, unit_name.left(2)))


func get_action_status_summary() -> String:
	var parts: PackedStringArray = []
	parts.append("M✓" if not movement_used else "M×")
	parts.append("A✓" if not standard_used else "A×")
	parts.append("S✓" if not swift_used else "S×")
	return " ".join(parts)


func refresh_status_icons() -> void:
	_rebuild_status_icons()


func reset_action_resources() -> void:
	movement_used = false
	standard_used = false
	swift_used = false
	reaction_available = true
	_sync_legacy_action_flags()


func consume_movement_resource() -> void:
	movement_used = true
	_sync_legacy_action_flags()


func restore_movement_resource() -> void:
	movement_used = false
	_sync_legacy_action_flags()


func consume_standard_resource() -> void:
	standard_used = true
	_sync_legacy_action_flags()


func restore_standard_resource() -> void:
	standard_used = false
	_sync_legacy_action_flags()


func consume_swift_resource() -> void:
	swift_used = true
	_sync_legacy_action_flags()


func restore_swift_resource() -> void:
	swift_used = false
	_sync_legacy_action_flags()


func consume_reaction_resource() -> void:
	reaction_available = false


func can_take_normal_move() -> bool:
	return not movement_used


func can_take_normal_attack() -> bool:
	return not standard_used


func can_use_swift_skill(swift_limit: int = 1) -> bool:
	if swift_limit == -1:
		return true
	return not swift_used


func are_active_resources_exhausted() -> bool:
	return movement_used and standard_used and swift_used


func is_skill_available(skill_id: String) -> bool:
	return get_skill_cooldown(skill_id) <= 0


func get_skill_cooldown(skill_id: String) -> int:
	return int(skill_cooldowns.get(skill_id, 0))


func consume_skill(skill_id: String, cooldown_turns: int) -> void:
	if cooldown_turns > 0:
		skill_cooldowns[skill_id] = cooldown_turns
	else:
		skill_cooldowns.erase(skill_id)


# ── 私有方法 ─────────────────────────────────────────

func _apply_visuals() -> void:
	sprite.self_modulate = FACTION_COLORS.get(faction, Color.WHITE)
	sprite.scale = UNIT_ICON_SCALE

	var bg_style: StyleBoxFlat = StyleBoxFlat.new()
	bg_style.bg_color = HP_BAR_BG
	bg_style.border_width_left = 2
	bg_style.border_width_top = 2
	bg_style.border_width_right = 2
	bg_style.border_width_bottom = 2
	bg_style.border_color = HP_BAR_BORDER
	health_bar.add_theme_stylebox_override("background", bg_style)
	_update_health_bar()

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
	_unit_label.text = str(UNIT_LABELS.get(unit_id, unit_name.left(2)))
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

	_rebuild_status_icons()


func _update_health_bar() -> void:
	if health_bar == null or stats == null:
		return
	health_bar.max_value = stats.max_hp
	health_bar.value = stats.hp

	var ratio: float = float(stats.hp) / float(stats.max_hp) if stats.max_hp > 0 else 0.0
	var fill_color: Color
	if ratio > 0.6:
		fill_color = HP_FULL_COLOR
	elif ratio > 0.3:
		fill_color = HP_LOW_COLOR
	else:
		fill_color = HP_CRIT_COLOR
	var fill_style: StyleBoxFlat = StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	health_bar.add_theme_stylebox_override("fill", fill_style)

	if _hp_label != null:
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


func _tick_skill_cooldowns() -> void:
	var next_cooldowns: Dictionary = {}
	for skill_id_value: Variant in skill_cooldowns.keys():
		var skill_id: String = str(skill_id_value)
		var turns_left: int = maxi(0, int(skill_cooldowns.get(skill_id, 0)) - 1)
		if turns_left > 0:
			next_cooldowns[skill_id] = turns_left
	skill_cooldowns = next_cooldowns


func _rebuild_status_icons() -> void:
	if status_icons == null:
		return
	for child: Node in status_icons.get_children():
		child.queue_free()

	var action_badges: Array[Dictionary] = [
		{"text": "M", "spent": movement_used, "color": Color(0.40, 0.70, 1.00)},
		{"text": "A", "spent": standard_used, "color": Color(1.00, 0.50, 0.30)},
		{"text": "S", "spent": swift_used, "color": Color(1.00, 0.90, 0.35)},
	]
	for index: int in range(action_badges.size()):
		var action_badge: Dictionary = action_badges[index]
		var action_label: Label = _make_badge(
			str(action_badge["text"]),
			Vector2(-18.0 + float(index) * STATUS_BADGE_STEP, ACTION_BADGE_Y),
			action_badge["color"],
			bool(action_badge["spent"]))
		status_icons.add_child(action_label)

	var total_statuses: int = buffs.size()
	var start_x: float = -0.5 * STATUS_BADGE_STEP * float(maxi(total_statuses - 1, 0))
	for index: int in range(total_statuses):
		var buff: BuffEffect = buffs[index]
		var icon_text: String = buff.icon.strip_edges()
		if icon_text == "":
			icon_text = buff.buff_id.left(2).to_upper()
		var duration_text: String = ""
		if buff.duration > 0:
			duration_text = str(buff.duration)
		var effect_label: Label = _make_badge(
			icon_text + duration_text,
			Vector2(start_x + float(index) * STATUS_BADGE_STEP, STATUS_BADGE_Y),
			Color(0.95, 0.30, 0.30) if buff.is_debuff() else Color(0.30, 0.85, 0.45),
			false)
		status_icons.add_child(effect_label)


func _make_badge(text: String, pos: Vector2, color: Color, spent: bool) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.position = pos
	label.size = Vector2(18, 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color",
		color.darkened(0.5) if spent else color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.90))
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _sync_legacy_action_flags() -> void:
	has_moved = movement_used
	has_attacked = standard_used
	has_used_swift = swift_used


func _emit_buffs_changed() -> void:
	_rebuild_status_icons()
	buffs_changed.emit(self)


func _normalize_stat_key(stat_key: String) -> String:
	var normalized: String = stat_key.strip_edges().to_upper()
	match normalized:
		"PHYS_ATK":
			return "STR"
		"MAG_ATK":
			return "MAG"
		"SPEED":
			return "SPD"
		"PHYSICAL_DEFENSE":
			return "DEF"
		"MAGICAL_DEFENSE":
			return "RES"
		"MOVE":
			return "MOV"
		"VISION":
			return "VIS"
	return normalized


func _get_base_stat_value(stat_key: String) -> int:
	match stat_key:
		"HP":
			return stats.max_hp
		"STR":
			return stats.str_attr
		"MAG":
			return stats.mag
		"DEX":
			return stats.dex
		"SPD":
			return stats.spd
		"LCK":
			return stats.lck
		"DEF":
			return stats.def_attr
		"RES":
			return stats.res
		"MOV":
			return stats.mov
		"VIS":
			return stats.vis
		"PRIORITY":
			return priority
	return 0
