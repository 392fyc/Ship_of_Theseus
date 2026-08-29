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
var attack_min_range: int = 1
var attack_range: int = 1
var skill_ids: Array[String] = []
var skill_cooldowns: Dictionary = {}
# 该单位持有的天赋 id（Wave 1 · A1）。默认空 = 现有战斗零影响；
# 填充方（肉鸽层选天赋 / 测试）自行写入，分发见 tactical_manager._dispatch_talents。
# 只有在 TalentRegistry 里注册成功的 id 才会真正触发——写进来但被拒收的卡不会生效，
# 且拒收理由可从 TalentRegistry.rejection_reason() 查到。
var talent_ids: Array[String] = []

# ── 武器槽（Wave 2 · 副手槽）─────────────────────────
# 主手武器 id，setup() 时从 class/enemy JSON 的 weapon_id 读入。值指向 data/weapons/。
# 存在 Unit 上是为了让状态判定能自包含——StateRegistry 是独立类、拿不到 DataLoader，
# 而〔双持〕的判据「武器栏与副手武器槽同时装备武器」必须能从单位本身读出来。
#
# ⚠ **这是主手武器 id 的第二份存储**。真正决定伤害结算的那一份在
# `TacticalManager._get_unit_weapon_data()`，它每次直接从 class/enemy 档案读
# `weapon_id`。两份现在恒等（都源自同一个 setup 输入），但没有任何机制保证不分叉——
# 将来装备层能换主手武器时，**必须同时更新这里**，否则 is_dual_wielding() 会用旧值
# 判定、而伤害结算用新值，正是 lane §2.2 要封杀的双写静默分叉（只不过发生在引擎内部）。
var weapon_id: String = ""
# 副手武器 id。空 = 未装备副手 = 不处于双持。**职业专属特例**，不进通用装备槽枚举
# （设计库 EquipSlot 两槽定稿，2026-07-05 用户裁决 Q7：「职业特殊机制作专属特例」）。
# 值指向 **data/equipment/**——主手与副手是同一个装备池（设计库那 22 把剑），
# 二天一流只是让剑圣多用一个槽装第二把剑，不是另一套武器数据。
var offhand_weapon_id: String = ""

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

# ── 战斗派生值修正钩子（来源：天赋 L2 / 装备 L4 / 符文 L5 / 肉鸽）──
# 默认 0，不绑武器；由上层写入修正系数（暴击回避等）。
var crit_avoid_bonus: int = 0
# 暴击率加法钩子（同源；心眼被动写入此字段，其他天赋/符文也可叠加）
var crit_bonus: int = 0

# ── 剑气类资源（仅在职业 JSON 带 sword_qi_config 时初始化/有意义）─
# 剑气：整数 0~qi_max（从职业 JSON 的 sword_qi_config 读取，如 kensei.json / myrmidon.json）
var sword_qi: int = 0
var _qi_max: int = 0
# 印记：三个离散布尔值，键名对应印记类型
var marks: Dictionary = {"心": false, "道": false, "势": false}
# 印记上限（0=未初始化/非剑圣）；从 sword_qi_config.mark_max 读，默认=印记类型数
var _mark_max: int = 0
# 心眼参数缓存（从 JSON 读取后存放此处，避免重复查表）
# 暴击：每 _xinyan_qi_per_crit_pct 点剑气 → 暴击率 +_xinyan_crit_per_qi 个百分点（向下取整）。
var _xinyan_crit_per_qi: int = 0
var _xinyan_qi_per_crit_pct: int = 10  # 每多少点剑气计一档暴击（剑气 0-100 标度）
# 属性分档：剑气 ≤ 上限的 _xinyan_qi_ratio_threshold_pct% → 低气段属性加成；
# 高于该比例 → 高气段属性加成。属性键与加成值全部来自职业 JSON，不在代码里写死。
var _xinyan_qi_ratio_threshold_pct: int = 0
var _xinyan_low_qi_stat_key: String = ""
var _xinyan_low_qi_stat_bonus: int = 0
var _xinyan_high_qi_stat_key: String = ""
var _xinyan_high_qi_stat_bonus: int = 0
# ── 兼容字段：仅供 tactical_manager 的剑气条阈值线与被动描述文本读取 ──
# 新口径下速度加成不再是「达到阈值即 +N」，而是剑气比例分档，因此这两个字段
# 已不参与任何属性计算，只是把「分档界线」与「低气段速度加成」派生出来给 UI 用。
# tactical_manager.gd 不在本次写入范围内，故保留原字段名不改。
var _xinyan_speed_threshold: int = 0
var _xinyan_speed_bonus: int = 0
# 印记属性加成缓存
var _mark_dex_bonus: int = 0
var _mark_spd_bonus: int = 0
var _mark_str_bonus: int = 0

# ── 敌人词条（affix）系统 v0 —— 纯加法，无词条单位零影响 ─────────
# 与「心眼」同构（spawn 后注入 → 缓存字段 → get_effective_stat/damage 读），不走 BuffEffect。
# 无词条单位下列字段恒为初始值，行为/数值与引入前完全一致。
# 挂载的词条定义（base + special 合并），每项为完整 affix 字典（含 id/type/params）。
var _affixes: Array[Dictionary] = []
var _affixes_applied: bool = false  # 幂等守卫：apply_affixes 每单位仅注入一次
# 数值增强系数（HP + 输出乘区）；1.0 = 无增强（无词条单位恒为 1.0）。
var _affix_stat_scale: float = 1.0
# 常驻平铺属性加值累积（normalized stat_key → 累积加值），供 get_effective_stat 叠加。
var _affix_stat_flat: Dictionary = {}
# 常驻百分比属性加值累积（normalized stat_key → 百分比），供 get_effective_stat 叠加。
var _affix_stat_pct: Dictionary = {}
# 伤害增强乘区（供 damage_calculator 读）；1.0 = 无增强（无词条单位恒为 1.0）。
var affix_damage_mult: float = 1.0
# af_vanguard（先手部署）首回合速度加成：挂载即激活（战斗从 round 1 开始），
# tactical_manager 在 round_ended（round 1 结束）调 expire_vanguard() 关闭。
# 无该词条单位下列两字段恒为 0/false → SPD 计算零影响。
var _affix_vanguard_spd_bonus: int = 0
var _affix_vanguard_active: bool = false

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

# ── 节点引用 ─────────────────────────────────────────
@onready var sprite: AnimatedSprite2D = $Sprite
@onready var map_token_view: Sprite2D = $MapTokenView
@onready var health_bar: ProgressBar = $HealthBar
@onready var status_icons: Node2D = $StatusIcons
var _unit_label: Label = null
var _hp_label: Label = null
var _facing: StringName = &"SE"
var _map_token_active := false
var _map_token_layout: Dictionary = {}


func _ready() -> void:
	_update_health_bar()
	_rebuild_status_icons()


func setup(class_data: Dictionary, initial_facing: StringName = &"SE") -> void:
	unit_id = str(class_data.get("id", ""))
	unit_name = str(class_data.get("name", "Unit"))
	priority = 0
	var valid_directions: Array[StringName] = [&"NW", &"NE", &"SW", &"SE"]
	_facing = initial_facing if valid_directions.has(initial_facing) else &"SE"
	_map_token_active = false
	_map_token_layout = {}
	map_token_view.visible = false
	stats = UnitStats.new()
	buffs.clear()
	# 主手武器随职业/敌人档案带入；副手槽默认空（要由天赋或装备层显式装上）。
	weapon_id = str(class_data.get("weapon_id", ""))
	offhand_weapon_id = ""
	skill_ids.clear()
	for skill_id_value: Variant in class_data.get("skill_ids", []):
		skill_ids.append(str(skill_id_value))
	skill_cooldowns.clear()
	var stat_dict: Dictionary = class_data.get("base_stats", {}).duplicate()
	for key: String in ["MOV"]:
		if class_data.has(key):
			stat_dict[key] = class_data[key]
	stats.load_from_dict(stat_dict)
	if class_data.has("growth_rates"):
		stats.load_growth_rates(class_data["growth_rates"], class_data.get("ss_growth_stats", []))
	# ── 剑圣专属资源初始化 ─────────────────────────────────
	_init_sword_qi_resource(class_data)
	var basic_attack_range: Dictionary = class_data.get("basic_attack_range", {})
	if basic_attack_range.is_empty():
		var atk_type: String = str(class_data.get("attack_type", "melee"))
		attack_min_range = 1
		attack_range = 2 if atk_type == "ranged" else 1
	else:
		attack_min_range = maxi(1, int(basic_attack_range.get("min", 1)))
		attack_range = maxi(attack_min_range, int(basic_attack_range.get("max", attack_min_range)))
	_update_health_bar()
	_map_token_active = _try_apply_map_token_visual(class_data)
	_apply_visuals()
	_rebuild_status_icons()
	_emit_buffs_changed()


func _try_apply_map_token_visual(class_data: Dictionary) -> bool:
	var profile_id := str(class_data.get("map_token_profile_id", ""))
	if profile_id == "":
		return false
	var data_loader := get_node_or_null("/root/DataLoader")
	if data_loader == null:
		push_error("[Unit] Map token data loader unavailable for %s" % unit_id)
		return false
	var visual_profiles: Dictionary = data_loader.get("visual_profiles") as Dictionary
	var profile: Dictionary = visual_profiles.get(profile_id, {})
	if profile.is_empty() or not bool(map_token_view.call("configure", profile)):
		push_error("[Unit] Map token profile unavailable for %s: %s" % [unit_id, profile_id])
		return false
	_map_token_layout = map_token_view.call("get_overhead_layout") as Dictionary
	_map_token_active = true
	refresh_map_token_visual()
	return true


func set_facing(direction: StringName) -> bool:
	if not [&"NW", &"NE", &"SW", &"SE"].has(direction):
		return false
	_facing = direction
	refresh_map_token_visual()
	return true


func get_facing() -> StringName:
	return _facing


func refresh_map_token_visual() -> void:
	if _map_token_active:
		map_token_view.call("set_visual_state", _facing, is_dual_wielding())


func has_runtime_map_token() -> bool:
	return _map_token_active


func get_combat_text_anchor_world(fallback_offset_y: float) -> Vector2:
	var offset_y := float(_map_token_layout.get("popup_anchor_y", fallback_offset_y)) if _map_token_active else fallback_offset_y
	return global_position + Vector2(0.0, offset_y)


# ── 战斗接口 ─────────────────────────────────────────

func take_damage(amount: int, damage_type: String = "physical") -> void:
	stats.take_damage(amount)
	damage_taken.emit(amount, damage_type)
	_update_health_bar()
	if not stats.is_alive():
		unit_died.emit()
		_on_death()


func heal(amount: int) -> void:
	# 敌人词条 af_heal_resist（愈合迟滞）：受治疗量按 incoming_heal_pct 打折。
	# 无词条单位 _affixes 为空 → final_amount == amount（零影响）。
	var final_amount: int = amount
	if not _affixes.is_empty():
		final_amount = _apply_affix_heal_resist(amount)
	stats.heal(final_amount)
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


## 装上副手武器（Wave 2）。weapon_id 需指向 data/weapons/ 的条目；
## 传空串等于卸下。装备层与测试都走这里，不要直接赋值字段。
func equip_offhand(new_weapon_id: String) -> void:
	offhand_weapon_id = new_weapon_id
	refresh_map_token_visual()


## 卸下副手武器。
func unequip_offhand() -> void:
	offhand_weapon_id = ""
	refresh_map_token_visual()


## 是否处于双持——**判据照设计库〔双持〕定义逐字**：
## 「武器栏与副手武器槽同时装备武器时，即视为双持」。
## 只看两个槽是否都非空，不看武器种类；即时判定、不快照。
func is_dual_wielding() -> bool:
	return weapon_id != "" and offhand_weapon_id != ""


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
	# ── 心眼：剑气比例分档属性加成（低气段 / 高气段各给一种属性）──────
	# 非剑气类单位（_qi_max<=0）恒返回 0 → 零影响。
	effective_value += float(_get_xinyan_stat_bonus(normalized_key))
	# ── 敌人词条 af_vanguard：首回合（round 1）速度加成（仅 SPD 键）──────────
	# 无该词条单位 _affix_vanguard_active 恒 false → 零影响。
	if normalized_key == "SPD" and _affix_vanguard_active:
		effective_value += float(_affix_vanguard_spd_bonus)
	# ── 印记属性加成（心/道/势）───────────────────────────
	if normalized_key == "DEX" and bool(marks.get("心", false)):
		effective_value += float(_mark_dex_bonus)
	if normalized_key == "SPD" and bool(marks.get("道", false)):
		effective_value += float(_mark_spd_bonus)
	if normalized_key == "STR" and bool(marks.get("势", false)):
		effective_value += float(_mark_str_bonus)
	# ── 敌人词条常驻数值加成（无词条单位两 dict 均空 → 零影响）────────
	if not _affix_stat_flat.is_empty():
		effective_value += float(_affix_stat_flat.get(normalized_key, 0))
	if not _affix_stat_pct.is_empty():
		effective_value += float(base_value) \
			* float(_affix_stat_pct.get(normalized_key, 0)) / 100.0
	return roundi(effective_value)


func get_effective_priority() -> int:
	return get_effective_stat("PRIORITY")


func get_hit_value(weapon_hit: int = 90) -> int:
	var effective_dex: int = get_effective_stat("DEX")
	return weapon_hit + effective_dex * 2


func get_avoid_value(terrain_evade_bonus: int = 0) -> int:
	var effective_spd: int = get_effective_stat("SPD")
	return effective_spd * 2 + terrain_evade_bonus


func get_crit_value(weapon_crit: int = 0) -> int:
	var effective_dex: int = get_effective_stat("DEX")
	# crit_bonus: 加法钩子，心眼被动 floor(剑气/qi_per_crit_pct)×crit_per_qi 写入此处
	return weapon_crit + int(effective_dex / 2.0) + crit_bonus


func get_crit_avoid_value() -> int:
	# LCK + 通用修正钩子（来源：天赋/装备/肉鸽；不绑武器）
	return get_effective_stat("LCK") + crit_avoid_bonus


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
	if not _map_token_active:
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


# ── 剑圣专属资源 API ─────────────────────────────────

func get_mark_count() -> int:
	var count: int = 0
	for mark_held: Variant in marks.values():
		if bool(mark_held):
			count += 1
	return count


func is_marks_full() -> bool:
	# 上限从 JSON 配置（_mark_max）读，默认=印记类型数；非剑圣 _mark_max==0 → 永远 false
	return _mark_max > 0 and get_mark_count() >= _mark_max


## 返回此槽位当前应显示的技能 ID（数据驱动：替换规则由技能 JSON 的
## slot_swap_trigger / slot_swap_target 声明，本函数只按触发类型求值，不硬编码技能 ID）。
## 触发类型 marks_full = 印记满 3 时切换到 slot_swap_target（如招架→拔刀）。
## 未来多种技能替换 / 印记改写天赋可新增触发类型而无需改动调用方。
##
## ★职业校验：替换目标必须真的在本单位的 skill_ids 内，否则不替换。
## 全仓只有「建技能栏」与「扫迅捷技能」两处读 skill_ids，施放路径上没有任何职业检查——
## 技能栏本身就是访问控制。若此处不校验，共享剑气/印记资源的下位职业（剑士 myrmidon）
## 会在印记满 3 时把招架槽换成拔刀并真的放得出来，而拔刀按 R2.4 是剑圣（kensei）专属。
func get_visible_skill_id(skill_id: String, slot_swap_trigger: String = "",
		slot_swap_target: String = "") -> String:
	if slot_swap_target == "":
		return skill_id
	if not skill_ids.has(slot_swap_target):
		return skill_id
	match slot_swap_trigger:
		"marks_full":
			if is_marks_full():
				return slot_swap_target
	return skill_id


## 修改剑气值并更新心眼被动。
func set_sword_qi(new_qi: int) -> void:
	if _qi_max <= 0:
		return
	sword_qi = clampi(new_qi, 0, _qi_max)
	_apply_xinyan_passive()


## 得到一个未持有的随机印记；返回印记名称，如果已满则返回 ""。
func gain_random_mark() -> String:
	var available_marks: Array[String] = []
	for mark_key: String in ["心", "道", "势"]:
		if not bool(marks.get(mark_key, false)):
			available_marks.append(mark_key)
	if available_marks.is_empty():
		return ""
	var chosen: String = available_marks[randi() % available_marks.size()]
	marks[chosen] = true
	return chosen


## 清空所有印记。
func clear_marks() -> void:
	marks["心"] = false
	marks["道"] = false
	marks["势"] = false


## 按数量扣减已持有的印记（默认按印记字典顺序 心→道→势 扣减），返回实际扣除数。
## 用于按量消耗（如 mark_cost）；count >= 持有数时等价于全清。
func spend_marks(count: int) -> int:
	var removed: int = 0
	for mark_key: String in marks.keys():
		if removed >= count:
			break
		if bool(marks[mark_key]):
			marks[mark_key] = false
			removed += 1
	return removed


# ── 私有方法 ─────────────────────────────────────────

func _apply_visuals() -> void:
	if _map_token_active:
		sprite.visible = false
		map_token_view.visible = true
		map_token_view.self_modulate = Color.WHITE
		var health_bottom := float(_map_token_layout["health_bar_bottom_y"])
		health_bar.position.y = health_bottom - health_bar.size.y
	else:
		sprite.visible = true
		map_token_view.visible = false
		sprite.self_modulate = FACTION_COLORS.get(faction, Color.WHITE)
		sprite.scale = UNIT_ICON_SCALE
		health_bar.position.y = -44.0

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

	if not _map_token_active:
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
		set_facing(&"NE")
	elif dir.y > 0:
		set_facing(&"SW")
	elif dir.x < 0:
		set_facing(&"NW")
	else:
		set_facing(&"SE")
	if not _map_token_active and dir.y < 0:
		sprite.play("walk_north")
	elif not _map_token_active and dir.y > 0:
		sprite.play("walk_south")
	elif not _map_token_active and dir.x < 0:
		sprite.play("walk_west")
	elif not _map_token_active:
		sprite.play("walk_east")


func _on_death() -> void:
	if _map_token_active:
		queue_free()
		return
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(&"death") or sprite.sprite_frames.get_animation_loop(&"death"):
		queue_free()
		return
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
		"PRIORITY":
			return priority
	return 0


## 剑圣资源初始化：从 class_data["sword_qi_config"] 读取参数。
## 非剑圣单位调用此函数后字段保持零值，不影响其他职业。
func _init_sword_qi_resource(class_data: Dictionary) -> void:
	var cfg: Dictionary = class_data.get("sword_qi_config", {})
	if cfg.is_empty():
		return
	_qi_max = int(cfg.get("qi_max", 10))
	sword_qi = clampi(int(cfg.get("qi_initial", 0)), 0, _qi_max)
	marks = {"心": false, "道": false, "势": false}
	_mark_max = int(cfg.get("mark_max", marks.size()))
	_xinyan_crit_per_qi = int(cfg.get("crit_per_qi", 0))
	_xinyan_qi_per_crit_pct = maxi(1, int(cfg.get("qi_per_crit_pct", 10)))
	_xinyan_qi_ratio_threshold_pct = clampi(
		int(cfg.get("qi_ratio_threshold_pct", 0)), 0, 100)
	_xinyan_low_qi_stat_key = _normalize_stat_key(str(cfg.get("low_qi_stat_key", "")))
	_xinyan_low_qi_stat_bonus = int(cfg.get("low_qi_stat_bonus", 0))
	_xinyan_high_qi_stat_key = _normalize_stat_key(str(cfg.get("high_qi_stat_key", "")))
	_xinyan_high_qi_stat_bonus = int(cfg.get("high_qi_stat_bonus", 0))
	# 兼容字段（仅供 UI 读，见字段声明处说明）：分档界线换算成剑气绝对值。
	_xinyan_speed_threshold = int(
		float(_qi_max) * float(_xinyan_qi_ratio_threshold_pct) / 100.0)
	_xinyan_speed_bonus = _xinyan_low_qi_stat_bonus \
		if _xinyan_low_qi_stat_key == "SPD" else 0
	_mark_dex_bonus = int(cfg.get("mark_dex_bonus", 2))
	_mark_spd_bonus = int(cfg.get("mark_spd_bonus", 2))
	_mark_str_bonus = int(cfg.get("mark_str_bonus", 2))
	_apply_xinyan_passive()


## 心眼被动更新：暴击加成 = floor(剑气 / qi_per_crit_pct) × crit_per_qi（剑气 0-100 标度，
## 当前配置 = 每 10 点剑气 +2 → 满气 floor(100/10)×2 = +20 暴击）写入 crit_bonus 钩子。
## 分档属性加成通过 get_effective_stat 实时计算，不需要此处写入。
func _apply_xinyan_passive() -> void:
	if _xinyan_crit_per_qi <= 0:
		return
	crit_bonus = (sword_qi / _xinyan_qi_per_crit_pct) * _xinyan_crit_per_qi


## 心眼剑气分档属性加成：剑气 ≤ 上限的 qi_ratio_threshold_pct% 时给低气段属性，
## 高于该比例时给高气段属性。两段属性键与加成值均来自职业 JSON（sword_qi_config）。
## 非剑气类单位（_qi_max<=0）恒返回 0，对其他职业零影响。
func _get_xinyan_stat_bonus(normalized_key: String) -> int:
	if _qi_max <= 0:
		return 0
	# 用整数交叉相乘比较，避免除法取整带来的边界漂移：剑气/上限 ≤ 比例/100。
	var in_low_band: bool = sword_qi * 100 <= _qi_max * _xinyan_qi_ratio_threshold_pct
	if in_low_band:
		if _xinyan_low_qi_stat_key != "" and normalized_key == _xinyan_low_qi_stat_key:
			return _xinyan_low_qi_stat_bonus
		return 0
	if _xinyan_high_qi_stat_key != "" and normalized_key == _xinyan_high_qi_stat_key:
		return _xinyan_high_qi_stat_bonus
	return 0


# ── 敌人词条（affix）公开接口 ─────────────────────────
# 挂载路径：spawn_unit(class_id,...) 之后由上层（BattleAssembler → 运行时）调用 apply_affixes。
# 与「心眼」同构：数值类立即写入缓存，触发类（on_hit/on_kill/on_turn_start/aura）
# 保留在 _affixes 供 tactical_manager 按时机分发。纯加法：无词条单位不调用即零影响。

## 注入词条。affix_ids: 基础词条 id 列表；special_affix_id: 特殊词条 id（可为 null/""）；
## stat_scale: 数值增强系数（HP + 输出乘区，1.0=无增强）；affix_pool: id→定义（=DataLoader.affixes）。
func apply_affixes(affix_ids: Array, special_affix_id: Variant,
		stat_scale: float, affix_pool: Dictionary) -> void:
	# 幂等守卫：每单位仅注入一次（spawn 后注入契约）。已挂载词条则忽略重复调用，
	# 防 HP 累乘 / 属性重复叠加（词条数值增强单位 _affixes 必非空）。
	if _affixes_applied:
		push_warning("[Affix] apply_affixes 重复调用已忽略（每单位仅注入一次）")
		return
	_affixes_applied = true
	# 合并 base + special 的 id 列表（special 可能为 null / 空串）。
	var all_ids: Array[String] = []
	for aid_value: Variant in affix_ids:
		all_ids.append(str(aid_value))
	var special_id: String = ""
	if special_affix_id != null:
		special_id = str(special_affix_id)
	if special_id != "":
		all_ids.append(special_id)

	# 逐 id 查定义并挂载；数值类立即结算，触发类留 _affixes。
	for aid: String in all_ids:
		var affix_def: Dictionary = affix_pool.get(aid, {})
		if affix_def.is_empty():
			push_warning("[Affix] 未找到词条定义（跳过）: " + aid)
			continue
		_affixes.append(affix_def)
		var affix_type: String = str(affix_def.get("type", ""))
		var params: Dictionary = affix_def.get("params", {})
		match affix_type:
			"stat_flat":
				# 常驻平铺属性（须带 params.stat_key）；无 stat_key 的特化型不常驻。
				if params.has("stat_key"):
					var k_flat: String = _normalize_stat_key(str(params["stat_key"]))
					_affix_stat_flat[k_flat] = float(_affix_stat_flat.get(k_flat, 0)) \
						+ float(params.get("value", 0))
			"stat_pct":
				# 仅「常驻属性百分比」（带 stat_key）进入常驻叠加；
				# 条件性(afs_frenzy) 无 stat_key → 留 _affixes 交
				# damage_calculator / 时机分发处理，不常驻。
				if params.has("stat_key"):
					var k_pct: String = _normalize_stat_key(str(params["stat_key"]))
					_affix_stat_pct[k_pct] = float(_affix_stat_pct.get(k_pct, 0)) \
						+ float(params.get("value", 0))
		# af_vanguard（先手部署）：首回合速度加成，挂载即激活（战斗从 round 1 开始）。
		# 数值从 params.first_round_spd 读取；round 1 结束由 expire_vanguard() 关闭。
		if aid == "af_vanguard":
			_affix_vanguard_spd_bonus = int(params.get("first_round_spd", 0))
			_affix_vanguard_active = true

	# 数值增强系数（HP + 输出乘区）。
	_affix_stat_scale = stat_scale
	affix_damage_mult = stat_scale
	if stat_scale != 1.0 and stats != null:
		var base_max_hp: int = stats.max_hp
		stats.max_hp = roundi(float(base_max_hp) * stat_scale)
		stats.hp = stats.max_hp
		_update_health_bar()


## 是否携带指定词条。
func has_affix(affix_id: String) -> bool:
	for affix: Dictionary in _affixes:
		if str(affix.get("id", "")) == affix_id:
			return true
	return false


## 返回已挂载的词条定义列表（供 UI / 时机分发 / 门预告 / 测试读取）。
func get_affixes() -> Array[Dictionary]:
	return _affixes


## af_vanguard（先手部署）首回合结束（round 1 end）关闭速度加成。
## 无该词条单位为空操作（_affix_vanguard_active 本就 false）→ 零影响。
## 由 tactical_manager 在 turn_manager.round_ended 时对全场单位调用。
func expire_vanguard() -> void:
	_affix_vanguard_active = false


## af_heal_resist（愈合迟滞）：按 incoming_heal_pct 折算受治疗量。无该词条 → 原样返回。
func _apply_affix_heal_resist(amount: int) -> int:
	for affix: Dictionary in _affixes:
		if str(affix.get("id", "")) != "af_heal_resist":
			continue
		var params: Dictionary = affix.get("params", {})
		var pct: float = float(params.get("incoming_heal_pct", 0))
		return maxi(0, roundi(float(amount) * (1.0 + pct / 100.0)))
	return amount
