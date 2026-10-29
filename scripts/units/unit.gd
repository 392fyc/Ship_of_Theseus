class_name Unit
extends Node2D

# ── 身份 ────────────────────────────────────────────
@export var unit_id: String = ""
@export var unit_name: String = "Unit"
@export var faction: String = "player"  # "player" | "enemy"
var priority: int = 0  # initiative tie-breaker (0/+1/+2)
var _movement_tween: Tween

# ── 数据 ────────────────────────────────────────────
var stats: UnitStats = null
var buffs: Array[BuffEffect] = []
# 持有型状态（设计库 State 中有层数、有持续时间的那一类，见 held_state_set.gd）。
# 与旧 buff 并存、互不迁移；定义在 setup() 时从 DataLoader.held_states 注入。
var held_states: HeldStateSet = HeldStateSet.new()
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
# 是否正在进行自己的回合（TacticalManager 在回合开始置 true、回合结束置 false）。
# 施加持有型状态时据此判断「在自身回合内获得」，影响「到下个自身回合结束」的计数。
var is_taking_turn: bool = false
# 护盾（R1.17）：与生命分开的数值，受到伤害时先扣护盾。每场战斗从 0 开始（setup 清零）。
var shield: int = 0
# 是否有普通攻击（职业 JSON 的 basic_attack，缺省 true）。设计上没有普通攻击（技能设计要点 §3），
# 用户 2026-10-28 裁决 S2：先只去掉剑士线，其他职业与敌人在敌人技能 AI 落地前保留。
var has_basic_attack: bool = true
# 心眼被动条目的技能 id（职业 JSON 的 passive_skill_id）；剑士 myrmidon_xinyan，剑圣 kensei_xinyan。
var passive_skill_id: String = ""
# 职业原本的被动（基础〔心眼〕）。被回忆升级后 passive_skill_id 变成升级技能，基础心眼的
# 剑气与印记属性加成随之失效（升级技能完整替换基础技能，KB 天赋设计要点 §12）。
var _base_passive_skill_id: String = ""
# 〔空想〕期间实际失去的剑气累计，每满一档得一层〔剑痕〕；不足一档的进度在空想结束时清空。
var _qi_loss_scar_progress: int = 0
# 回忆升级记录（gameplay-impl PR5，差距清单 M10）：setup() 时清空，由 apply_memory 写入。
var memory_upgrades: MemoryUpgrades = MemoryUpgrades.new()

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
# 「剑气每比上限少 N 点，某属性 +M」口径（设计库 myrmidon_xinyan）。step > 0 时启用并取代上面的
# 高低分档；为 0 时沿用分档（剑圣在其 PR 前仍是分档）。三项都从职业 JSON 读。
var _xinyan_qi_deficit_per_step: int = 0
var _xinyan_deficit_stat_key: String = ""
var _xinyan_deficit_stat_bonus: int = 0
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
# 印记的百分比提升（设计库 kensei_xinyan：〔心〕技巧、〔道〕速度、〔势〕力量各提升 N%），
# 按 R1.8 与其他同类提升相加后乘在「基础值 + 全部固定加值」上。从职业 JSON 读，缺省 0。
var _mark_dex_pct: float = 0.0
var _mark_spd_pct: float = 0.0
var _mark_str_pct: float = 0.0

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
signal movement_finished(completed: bool)
signal buffs_changed(unit: Unit)
## 剑气经统一入口变动后发出。kind = 最终生效的方向（gain / spend / lose，拦截器可改写），
## requested = 请求量（正数），actual = 实际变化量（有符号，超过上限作废、最低到 0）。
signal sword_qi_changed(unit: Unit, kind: String, requested: int, actual: int, source: String)

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
var _overhead_ui_managed: bool = false
var character_animation: Sprite2D = null


func _init() -> void:
	held_states.changed.connect(_emit_buffs_changed)


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
	shield = 0
	buffs.clear()
	held_states.clear()
	_load_held_state_definitions()
	# 主手武器随职业/敌人档案带入；副手槽默认空（要由天赋或装备层显式装上）。
	weapon_id = str(class_data.get("weapon_id", ""))
	offhand_weapon_id = ""
	has_basic_attack = bool(class_data.get("basic_attack", true))
	passive_skill_id = str(class_data.get("passive_skill_id", ""))
	_base_passive_skill_id = passive_skill_id
	_qi_loss_scar_progress = 0
	skill_ids.clear()
	for skill_id_value: Variant in class_data.get("skill_ids", []):
		skill_ids.append(str(skill_id_value))
	skill_cooldowns.clear()
	memory_upgrades.clear()
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


## Original portrait-token entry; reuses the existing presentation scheduling interface.
func enable_portrait_token(target_height: float = 72.0, presentation: Dictionary = {}) -> bool:
	var view: Sprite2D = preload("res://scripts/units/portrait_token_view.gd").new()
	add_child(view)
	if not view.configure(target_height, presentation):
		view.queue_free()
		return false
	if is_instance_valid(character_animation):
		character_animation.queue_free()
	character_animation = view
	view.name = "PortraitToken"
	view.play("idle", _facing)
	sprite.hide()
	map_token_view.hide()
	if _unit_label != null:
		_unit_label.hide()
	_map_token_layout = {"popup_anchor_y": -target_height - 12.0, "health_bar_bottom_y": -target_height - 5.0}
	return true


func has_character_animation() -> bool:
	return is_instance_valid(character_animation)


func _character_direction(target: Vector2i) -> StringName:
	var delta: Vector2i = target - grid_position
	# Portrait entry resolves the projected target, not the first non-zero grid axis.
	if has_character_animation() and character_animation.has_method("direction_for_screen_vector"):
		var projected := Vector2(float(delta.x - delta.y) * Grid.TILE_WIDTH * 0.5, float(delta.x + delta.y) * Grid.TILE_HEIGHT * 0.5)
		return character_animation.direction_for_screen_vector(projected)
	if delta.y < 0:
		return &"NE"
	if delta.y > 0:
		return &"SW"
	return &"NW" if delta.x < 0 else &"SE"


func begin_attack_visual(target: Vector2i) -> float:
	if not has_character_animation():
		return 0.0
	set_facing(_character_direction(target))
	character_animation.play("melee", _facing)
	return character_animation.impact_delay()


func show_attack_contact(target: Vector2i) -> void:
	if has_character_animation():
		# AOE impacts share the original cast direction until recovery.
		if not character_animation.has_method("direction_for_screen_vector") or character_animation.action != "melee":
			set_facing(_character_direction(target))
		character_animation.show_contact(_facing)


func set_facing(direction: StringName) -> bool:
	if not [&"NW", &"NE", &"SW", &"SE"].has(direction):
		return false
	# Keep the portrait cast target bound through windup, impact and recovery.
	if has_character_animation() and character_animation.has_method("direction_for_screen_vector") \
			and character_animation.action == "melee" and character_animation.elapsed < character_animation.duration():
		return direction == _facing
	_facing = direction
	refresh_map_token_visual()
	return true


func get_facing() -> StringName:
	return _facing


func refresh_map_token_visual() -> void:
	if has_character_animation():
		character_animation.facing = _facing
		return
	if _map_token_active:
		map_token_view.call("set_visual_state", _facing, is_dual_wielding())


func has_runtime_map_token() -> bool:
	return _map_token_active


func get_combat_text_anchor_world(fallback_offset_y: float) -> Vector2:
	var offset_y := float(_map_token_layout.get("popup_anchor_y", fallback_offset_y)) if _map_token_active else fallback_offset_y
	if has_character_animation():
		offset_y = float(_map_token_layout.get("popup_anchor_y", fallback_offset_y))
	return global_position + Vector2(0.0, offset_y)


## 战术场景头顶控件所需的纯呈现数据；不参与预测或战斗计算。
func get_overhead_presentation_data() -> Dictionary:
	var hp: int = stats.hp if stats != null else 0
	var max_hp: int = stats.max_hp if stats != null else 0
	var ratio: float = float(hp) / float(max_hp) if max_hp > 0 else 0.0
	var fill_color: Color = HP_FULL_COLOR
	if ratio <= 0.3:
		fill_color = HP_CRIT_COLOR
	elif ratio <= 0.6:
		fill_color = HP_LOW_COLOR
	var label_text: String = _unit_label.text if _unit_label != null else ""
	return {
		"unit_id": unit_id,
		"unit_name": unit_name,
		"faction": faction,
		"faction_color": FACTION_COLORS.get(faction, Color.WHITE),
		"grid_position": grid_position,
		"instance_id": get_instance_id(),
		"name_text": label_text,
		"name_font_size": _unit_label.get_theme_font_size("font_size") if _unit_label != null else 18,
		"hp_text": "%d / %d" % [hp, max_hp] if stats != null else "",
		"hp_value": hp,
		"hp_max": max_hp,
		"hp_font_size": _hp_label.get_theme_font_size("font_size") if _hp_label != null else 9,
		"hp_ratio": ratio,
		"hp_color": fill_color,
		"alive": stats != null and stats.is_alive(),
		"body_rect": get_overhead_body_rect_screen(),
	}


## 返回当前可见 MapToken 或 Sprite 的屏幕空间绘制矩形。
func get_overhead_body_rect_screen() -> Rect2:
	var bounds: Rect2 = Rect2()
	var has_bounds: bool = false
	if has_character_animation():
		return _canvas_item_rect_screen(character_animation, character_animation.visible_local_rect())
	if _map_token_active and map_token_view != null and map_token_view.visible:
		bounds = _canvas_item_rect_screen(map_token_view, map_token_view.get_rect())
		has_bounds = true
	elif sprite != null and sprite.visible:
		var sprite_rect: Rect2 = _animated_sprite_local_rect(sprite)
		if sprite_rect.size.x > 0.0 and sprite_rect.size.y > 0.0:
			bounds = _canvas_item_rect_screen(sprite, sprite_rect)
			has_bounds = true
	return bounds if has_bounds else Rect2(global_position, Vector2.ZERO)


func _animated_sprite_local_rect(animated_sprite: AnimatedSprite2D) -> Rect2:
	var frames: SpriteFrames = animated_sprite.sprite_frames
	if frames == null or not frames.has_animation(animated_sprite.animation):
		return Rect2()
	var frame_count: int = frames.get_frame_count(animated_sprite.animation)
	if frame_count <= 0:
		return Rect2()
	var frame_index: int = clampi(animated_sprite.frame, 0, frame_count - 1)
	var frame_texture: Texture2D = frames.get_frame_texture(animated_sprite.animation, frame_index)
	if frame_texture == null:
		return Rect2()
	var frame_size: Vector2 = frame_texture.get_size()
	var frame_position: Vector2 = animated_sprite.offset
	if animated_sprite.centered:
		frame_position -= frame_size * 0.5
	return Rect2(frame_position, frame_size)


## 启用统一头顶控件后关闭单位节点内的旧副本，避免两个坐标层同时绘制。
func set_overhead_ui_managed(managed: bool) -> void:
	_overhead_ui_managed = managed
	if health_bar != null:
		health_bar.visible = not managed
	if _hp_label != null:
		_hp_label.visible = not managed
	if _unit_label != null:
		_unit_label.visible = not managed


func _canvas_item_rect_screen(item: CanvasItem, local_rect: Rect2) -> Rect2:
	var transform: Transform2D = item.get_global_transform_with_canvas()
	var top_left: Vector2 = transform * local_rect.position
	var top_right: Vector2 = transform * Vector2(local_rect.end.x, local_rect.position.y)
	var bottom_left: Vector2 = transform * Vector2(local_rect.position.x, local_rect.end.y)
	var bottom_right: Vector2 = transform * local_rect.end
	var min_x: float = minf(minf(top_left.x, top_right.x), minf(bottom_left.x, bottom_right.x))
	var max_x: float = maxf(maxf(top_left.x, top_right.x), maxf(bottom_left.x, bottom_right.x))
	var min_y: float = minf(minf(top_left.y, top_right.y), minf(bottom_left.y, bottom_right.y))
	var max_y: float = maxf(maxf(top_left.y, top_right.y), maxf(bottom_left.y, bottom_right.y))
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))


# ── 战斗接口 ─────────────────────────────────────────

func take_damage(amount: int, damage_type: String = "physical") -> void:
	# R1.17：伤害先扣护盾，超过当前护盾的部分再扣生命。damage_taken 仍报整次伤害量。
	var absorbed: int = mini(shield, maxi(0, amount))
	shield -= absorbed
	stats.take_damage(amount - absorbed)
	if amount > 0 and has_character_animation():
		character_animation.show_hit()
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
	# R1.8：先把所有固定点数相加，再把所有写作「提升 / 降低」的百分比合并计算，
	# 计算过程中不取整，最后向下取整。flat_total 从基础值起累加全部固定加值。
	var flat_total: float = float(base_value)
	var pct_total: float = 0.0
	for buff: BuffEffect in buffs:
		if buff.effect_type != "stat_mod":
			continue
		if _normalize_stat_key(buff.stat_key) != normalized_key:
			continue
		if buff.is_percentage:
			pct_total += buff.value
		else:
			flat_total += buff.value
	# ── 心眼：剑气带来的属性加成（固定点数）。非剑气类单位恒为 0 → 零影响。
	flat_total += float(_get_xinyan_stat_bonus(normalized_key))
	# ── 持有型状态给的、随剑气即时变化的固定加值（如剑士〔招架〕的防御与魔防 +N）──
	flat_total += float(_get_held_state_stat_bonus(normalized_key))
	# ── 敌人词条 af_vanguard：首回合（round 1）速度加成（仅 SPD 键）──────────
	# 无该词条单位 _affix_vanguard_active 恒 false → 零影响。
	if normalized_key == "SPD" and _affix_vanguard_active:
		flat_total += float(_affix_vanguard_spd_bonus)
	# ── 印记（心/道/势）：固定加值与百分比提升都可配置，未配置的一项为 0 ──
	# 这组加成属于基础〔心眼〕（设计库 kensei_xinyan effect），心眼被升级后不再生效。
	var mark_bonus_active: bool = has_base_xinyan()
	if mark_bonus_active and normalized_key == "DEX" and bool(marks.get("心", false)):
		flat_total += float(_mark_dex_bonus)
		pct_total += _mark_dex_pct
	if mark_bonus_active and normalized_key == "SPD" and bool(marks.get("道", false)):
		flat_total += float(_mark_spd_bonus)
		pct_total += _mark_spd_pct
	if mark_bonus_active and normalized_key == "STR" and bool(marks.get("势", false)):
		flat_total += float(_mark_str_bonus)
		pct_total += _mark_str_pct
	# ── 敌人词条常驻数值加成（无词条单位两 dict 均空 → 零影响）────────
	if not _affix_stat_flat.is_empty():
		flat_total += float(_affix_stat_flat.get(normalized_key, 0))
	if not _affix_stat_pct.is_empty():
		pct_total += float(_affix_stat_pct.get(normalized_key, 0))
	# 1e-6 只吸收浮点表示误差（如 20 × 1.15 = 22.999…），不改变向下取整的口径。
	return floori(flat_total * (100.0 + pct_total) / 100.0 + 0.000001)


func get_effective_priority() -> int:
	return get_effective_stat("PRIORITY")


func get_hit_value(weapon_hit: int = 90) -> int:
	var effective_dex: int = get_effective_stat("DEX")
	return weapon_hit + effective_dex * 2


func get_avoid_value(terrain_evade_bonus: int = 0) -> int:
	var effective_spd: int = get_effective_stat("SPD")
	# R1.2：目标闪避 = 速度 × 2 + 地形闪避 + 其他闪避加减（如剑圣〔招架〕的额外闪避）。
	return effective_spd * 2 + terrain_evade_bonus + _get_held_state_avoid_bonus()


## 是否带有嘲讽（R1.18）：持有 taunt 状态，或某个持有型状态的参数写了 grants_taunt
## （〔见切〕给的〔架势〕：「〔架势〕期间具有嘲讽」，与架势同存同灭，Q5）。
func has_taunt() -> bool:
	if held_states.has("taunt"):
		return true
	for entry: Dictionary in held_states.to_array():
		if bool((entry.get("params", {}) as Dictionary).get("grants_taunt", false)):
			return true
	return false


## 持有型状态 params 里的 stat_scaled_avoid_bonus：{stat, pct} → 当前该属性 × pct%（向下取整）。
## 每次命中判定时读取当前属性，不快照（设计库 kensei_zhaojia rules）。
func _get_held_state_avoid_bonus() -> int:
	var total: int = 0
	# 按层数给的闪避（〔剑痕〕每层闪避 +3），R1.2 其他闪避加减。
	for state_id: String in held_states.held_ids():
		var per_stack: int = int(_held_state_definition(state_id).get("engine_avoid_per_stack", 0))
		if per_stack != 0:
			total += per_stack * held_states.stacks(state_id)
	for entry: Dictionary in held_states.to_array():
		var params: Dictionary = entry.get("params", {})
		var scaled: Variant = params.get("stat_scaled_avoid_bonus", null)
		if not scaled is Dictionary:
			continue
		var spec: Dictionary = scaled
		var stat_value: int = get_effective_stat(str(spec.get("stat", "")))
		total += floori(float(stat_value) * float(spec.get("pct", 0)) / 100.0)
	return total


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
	var path: Array[Vector2i] = Pathfinding.find_path(grid, grid_position, target_pos, faction)
	if path.size() < 2:
		return
	_begin_walk_segment(path[1] - path[0])
	var tween: Tween = create_tween()
	_movement_tween = tween
	# Follow the same orthogonal route as the preview. Grid occupancy is committed
	# once by TacticalManager after the entire presentation has finished.
	for index: int in range(1, path.size()):
		if index > 1:
			tween.tween_callback(_begin_walk_segment.bind(path[index] - path[index - 1]))
		tween.tween_property(self, "position", grid.grid_to_world(path[index]), 0.25)
	tween.finished.connect(_on_movement_tween_finished, CONNECT_ONE_SHOT)
	var completed: bool = await movement_finished
	_movement_tween = null
	if has_character_animation():
		character_animation.play("idle", _facing)
	if not completed:
		return
	if not _map_token_active and not has_character_animation():
		sprite.play("idle")
	moved.emit(grid_position, target_pos)


func _begin_walk_segment(direction: Vector2i) -> void:
	_set_walk_direction(direction)
	if has_character_animation():
		character_animation.play("walk", _facing)


func _on_movement_tween_finished() -> void:
	movement_finished.emit(true)


func cancel_movement() -> void:
	if has_character_animation() and character_animation.has_method("cancel_presentation"):
		character_animation.cancel_presentation()
	if _movement_tween == null or not _movement_tween.is_valid():
		return
	_movement_tween.kill()
	movement_finished.emit(false)


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


# ── 回忆升级（gameplay-impl PR5，差距清单 M10）─────────

## 兑现一张回忆：把基础技能永久换成升级技能，返回 {"ok": bool, "reason": String}。
## 规则与拒绝原因见 MemoryUpgrades.check。memories / skills 缺省时读 DataLoader，测试可传入自己的表。
## 战斗中途兑现时，基础技能剩余的冷却转给升级技能 [推断：避免借升级刷新冷却]。
func apply_memory(memory_id: String, memories: Dictionary = {}, skills: Dictionary = {}) -> Dictionary:
	var data_loader := get_node_or_null("/root/DataLoader")
	if memories.is_empty() and data_loader != null:
		memories = data_loader.get("memories")
	if skills.is_empty() and data_loader != null:
		skills = data_loader.get("skills")
	var memory: Dictionary = memories.get(memory_id, {})
	var loadout: Array[String] = skill_ids.duplicate()
	if passive_skill_id != "":
		loadout.append(passive_skill_id)
	var reason: String = memory_upgrades.check(memory, unit_id, loadout, skills)
	if reason != "":
		return {"ok": false, "reason": reason}
	var base_id: String = str(memory.get("base_skill_id", ""))
	var upgrade_id: String = str(memory.get("upgrade_skill_id", ""))
	memory_upgrades.record(memory)
	var index: int = skill_ids.find(base_id)
	if index >= 0:
		skill_ids[index] = upgrade_id
	if passive_skill_id == base_id:
		passive_skill_id = upgrade_id
		_apply_xinyan_passive()
	if skill_cooldowns.has(base_id):
		skill_cooldowns[upgrade_id] = skill_cooldowns[base_id]
		skill_cooldowns.erase(base_id)
	return {"ok": true, "reason": ""}


## 技能身份（R2.5）：升级技能及其各形态返回它取代的基础技能 id，其余原样返回。
func get_skill_identity(skill_id: String) -> String:
	return memory_upgrades.get_identity(skill_id)


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
## 技能栏本身就是访问控制。若此处不校验，只共享剑气的下位职业（剑士 myrmidon）
## 会在印记满 3 时把招架槽换成拔刀并真的放得出来，而拔刀按 R2.4 是剑圣（kensei）专属。
## 触发类型 marks_and_qi = 持有印记数与剑气都达到 slot_swap_requires 的门槛（设计库 kensei_zhaojia：
## 3 枚印记且剑气不少于 20 → 拔刀；条件不再成立立即恢复）。
## R3.6：替换形态仍在冷却时保持原技能；冷却结束后条件仍成立即替换。
func get_visible_skill_id(skill_id: String, slot_swap_trigger: String = "",
		slot_swap_target: String = "", slot_swap_requires: Dictionary = {}) -> String:
	if slot_swap_target == "":
		return skill_id
	# R2.5：替换目标已被回忆升级时，换上来的是它的升级形态（槽位里也只剩升级技能）。
	if not skill_ids.has(memory_upgrades.resolve(slot_swap_target)):
		return skill_id
	# 多形态回忆（兵无常势）：按形态组顺序逐个判定，每个形态用它自己 JSON 里的
	# slot_swap_requires（没写时用槽位声明的门槛）。R3.6：条件成立的形态还在冷却时不替换，
	# 原技能保持可用；各形态冷却分别记录。
	var skills: Dictionary = _skill_table()
	for form_id: String in memory_upgrades.resolve_forms(slot_swap_target):
		var form_data: Variant = skills.get(form_id, {})
		var requires: Dictionary = slot_swap_requires
		if form_data is Dictionary and (form_data as Dictionary).get("slot_swap_requires", null) is Dictionary:
			requires = (form_data as Dictionary)["slot_swap_requires"]
		if not _slot_swap_condition_met(skill_id, slot_swap_trigger, requires):
			continue
		return form_id if is_skill_available(form_id) else skill_id
	return skill_id


## 同槽替换的条件。marks_and_qi：印记数（`marks_exact` 为真时要求正好这么多枚）且剑气不少于门槛。
func _slot_swap_condition_met(skill_id: String, trigger: String, requires: Dictionary) -> bool:
	match trigger:
		"marks_full":
			return is_marks_full()
		"marks_and_qi":
			if requires.is_empty():
				push_warning("[Unit] marks_and_qi 缺 slot_swap_requires，不替换: " + skill_id)
				return false
			var marks: int = get_mark_count()
			var need_marks: int = int(requires.get("marks", 0))
			var marks_ok: bool = marks == need_marks if bool(requires.get("marks_exact", false)) \
				else marks >= need_marks
			return marks_ok and sword_qi >= int(requires.get("qi", 0))
	return false


func _skill_table() -> Dictionary:
	var data_loader := get_node_or_null("/root/DataLoader")
	if data_loader == null:
		return {}
	var skills: Variant = data_loader.get("skills")
	return skills if skills is Dictionary else {}


# ── 护盾（R1.17）────────────────────────────────────

## 获得护盾：与现有护盾相加（回天 rules）。返回获得后的护盾值。
func gain_shield(amount: int) -> int:
	if amount > 0:
		shield += amount
		_update_health_bar()
	return shield


## 自身回合开始时的自然衰减（R1.17）：衰减量 = 当前护盾 × decay_pct% × res_scale ÷ (res_scale + 魔抗)，
## 向上取整；衰减后最多保留衰减前的 max_keep_pct%（向下取整）。不是伤害，不触发受伤类效果。
## 参数在 data/rules/shield.json。返回衰减量。
func decay_shield() -> int:
	if shield <= 0:
		return 0
	var rule: Dictionary = {}
	var data_loader := get_node_or_null("/root/DataLoader")
	if data_loader != null and data_loader.get("rules") is Dictionary:
		rule = (data_loader.get("rules") as Dictionary).get("shield", {})
	if rule.is_empty():
		push_warning("[Unit] 缺 data/rules/shield.json，护盾不衰减")
		return 0
	var before: int = shield
	var res_scale: float = float(rule.get("res_scale", 100))
	var res: float = float(maxi(0, get_effective_stat("RES")))
	var decay: int = ceili(float(before) * float(rule.get("decay_pct", 0)) / 100.0
		* res_scale / (res_scale + res))
	var keep_cap: int = floori(float(before) * float(rule.get("max_keep_pct", 100)) / 100.0)
	shield = maxi(0, mini(before - decay, keep_cap))
	_update_health_bar()
	return before - shield


## 直接设定剑气值并更新心眼被动。只用于战斗开始、调试复位这类「重置」；
## 战斗中的获得、消耗、失去一律走 gain_sword_qi / spend_sword_qi / lose_sword_qi，
## 这样拦截器与 sword_qi_changed 的监听方（〔空想〕〔太阳〕〔太阴〕〔剑痕〕等）不会漏算。
func set_sword_qi(new_qi: int) -> void:
	if _qi_max <= 0:
		return
	sword_qi = clampi(new_qi, 0, _qi_max)
	_apply_xinyan_passive()


const QI_GAIN := "gain"
const QI_SPEND := "spend"
const QI_LOSE := "lose"

## 剑气变动拦截器：Callable(unit: Unit, kind: String, amount: int, source: String) -> Dictionary，
## 返回 {"kind": ..., "amount": ...} 改写本次变动，返回空字典表示不改。
## 按添加顺序依次作用；例如〔空想〕会把 gain 改成 lose。
var _qi_interceptors: Array[Callable] = []


func add_qi_interceptor(interceptor: Callable) -> void:
	if not _qi_interceptors.has(interceptor):
		_qi_interceptors.append(interceptor)


func remove_qi_interceptor(interceptor: Callable) -> void:
	_qi_interceptors.erase(interceptor)


## 获得剑气。返回实际变化量（有符号；被拦截改为失去时为负）。
func gain_sword_qi(amount: int, source: String = "") -> int:
	return _change_sword_qi(QI_GAIN, amount, source)


## 技能等主动消耗剑气。返回实际变化量（≤ 0）。
func spend_sword_qi(amount: int, source: String = "") -> int:
	return _change_sword_qi(QI_SPEND, amount, source)


## 被效果夺走或清空剑气（不是主动消耗）。返回实际变化量（≤ 0）。
func lose_sword_qi(amount: int, source: String = "") -> int:
	return _change_sword_qi(QI_LOSE, amount, source)


## 剑气变动的唯一入口：先过拦截器，再按上限 / 下限结算，最后发 sword_qi_changed。
func _change_sword_qi(kind: String, amount: int, source: String) -> int:
	if _qi_max <= 0 or amount <= 0:
		return 0
	var final_kind: String = kind
	var final_amount: int = amount
	# 〔空想〕：任何来源原本使自身获得剑气时，改为失去等量剑气（不产生获得剑气事件）。
	if final_kind == QI_GAIN and _held_state_flag("engine_qi_gain_becomes_loss") != "":
		final_kind = QI_LOSE
	for interceptor: Callable in _qi_interceptors.duplicate():
		if not interceptor.is_valid():
			continue
		var rewrite: Variant = interceptor.call(self, final_kind, final_amount, source)
		if rewrite is Dictionary and not (rewrite as Dictionary).is_empty():
			final_kind = str((rewrite as Dictionary).get("kind", final_kind))
			final_amount = maxi(0, int((rewrite as Dictionary).get("amount", final_amount)))
	var before: int = sword_qi
	var signed: int = final_amount if final_kind == QI_GAIN else -final_amount
	set_sword_qi(sword_qi + signed)
	var actual: int = sword_qi - before
	_track_qi_loss_scars(actual, source)
	sword_qi_changed.emit(self, final_kind, amount, actual, source)
	return actual


## 〔空想〕期间实际失去的剑气每累计一档（状态定义 engine_qi_loss_scar.qi_per_stack）得一层〔剑痕〕。
## 技能消耗与「获得改失去」的实际损失都计入；没有实际发生的损失、空想结束时清空的剩余剑气不计入。
## 剑痕满层时不保存多出的进度。
func _track_qi_loss_scars(actual: int, source: String) -> void:
	if actual >= 0 or source == QI_SOURCE_KONGXIANG_CLEAR:
		return
	var state_id: String = _held_state_flag("engine_qi_loss_scar")
	if state_id == "":
		return
	var spec: Dictionary = _held_state_definition(state_id).get("engine_qi_loss_scar", {})
	var scar_id: String = str(spec.get("state_id", ""))
	var per_stack: int = maxi(1, int(spec.get("qi_per_stack", 1)))
	var cap: int = int(_held_state_definition(scar_id).get("max_stacks", 0))
	_qi_loss_scar_progress += -actual
	while _qi_loss_scar_progress >= per_stack:
		if cap > 0 and held_states.stacks(scar_id) >= cap:
			_qi_loss_scar_progress = 0
			return
		_qi_loss_scar_progress -= per_stack
		apply_held_state(scar_id, 1, {"kind": "permanent"})
	if cap > 0 and held_states.stacks(scar_id) >= cap:
		_qi_loss_scar_progress = 0


const QI_SOURCE_KONGXIANG_CLEAR := "kongxiang_clear"


## 进入〔空想〕时从零开始累计（上一次空想若没走到回合结束就消失，例如战斗在回合中途结束，
## 残留的进度不能带进来：「不足 25 点的进度只在当前〔空想〕内保留」）。
func begin_qi_loss_scar_state() -> void:
	_qi_loss_scar_progress = 0


## 〔空想〕结束：清空剩余剑气（不计入剑痕）与不足一档的进度。
func end_qi_loss_scar_state() -> void:
	if sword_qi > 0:
		lose_sword_qi(sword_qi, QI_SOURCE_KONGXIANG_CLEAR)
	_qi_loss_scar_progress = 0


## 持有的状态里，第一个在定义中写了 key 的状态 id；没有时为空串。
func _held_state_flag(key: String) -> String:
	for state_id: String in held_states.held_ids():
		if _held_state_definition(state_id).has(key):
			return state_id
	return ""


func _held_state_definition(state_id: String) -> Dictionary:
	var data_loader := get_node_or_null("/root/DataLoader")
	if data_loader == null or not data_loader.get("held_states") is Dictionary:
		return {}
	return (data_loader.get("held_states") as Dictionary).get(state_id, {})


## 剑气不足时也能发动需要消耗剑气的技能（〔空想〕），发动后剑气降至 0。
func allows_qi_overdraft() -> bool:
	return _held_state_flag("engine_qi_overdraft") != ""


## 施加持有型状态；「是否在自身回合内获得」由 is_taking_turn 决定。参数含义见 HeldStateSet.apply。
func apply_held_state(state_id: String, stacks: int = 1, duration: Dictionary = {},
		params: Dictionary = {}, source_unit_id: String = "") -> bool:
	return held_states.apply(state_id, stacks, duration, params, source_unit_id, is_taking_turn)


## 得到一个未持有的随机印记；返回印记名称，如果已满则返回 ""。
func gain_random_mark() -> String:
	if _mark_max <= 0 or get_mark_count() >= _mark_max:
		return ""
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

	set_overhead_ui_managed(_overhead_ui_managed)
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
	if has_character_animation() and character_animation.has_method("direction_for_screen_vector"):
		set_facing(_character_direction(grid_position + dir))
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
	# 在自己回合内死亡时 turn_ended 不会发出，这里复位，免得之后被当成「仍在自身回合内」。
	is_taking_turn = false
	if has_character_animation():
		cancel_movement()
		queue_free()
		return
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


## 持有型状态 params 里的 qi_scaled_stat_bonus：{stats, base, qi_step} → base + 剑气 ÷ qi_step（向下取整）。
## 每次读取按当前剑气即时计算，不快照（设计库〔招架〕rules：N 随当前剑气即时变化）。
func _get_held_state_stat_bonus(normalized_key: String) -> int:
	var total: int = 0
	for entry: Dictionary in held_states.to_array():
		var params: Dictionary = entry.get("params", {})
		var scaled: Variant = params.get("qi_scaled_stat_bonus", null)
		if not scaled is Dictionary:
			continue
		var spec: Dictionary = scaled
		var stats_list: Array = spec.get("stats", [])
		var matched: bool = false
		for stat_name: Variant in stats_list:
			if _normalize_stat_key(str(stat_name)) == normalized_key:
				matched = true
				break
		if not matched:
			continue
		var step: int = int(spec.get("qi_step", 0))
		var per_step: int = sword_qi / step if step > 0 else 0
		total += int(spec.get("base", 0)) + per_step
	return total


## 从 DataLoader.held_states 注入持有型状态的定义；拿不到 DataLoader 时保持空表
## （施加未注册的状态会报错，不会静默生效）。
func _load_held_state_definitions() -> void:
	var data_loader := get_node_or_null("/root/DataLoader")
	if data_loader == null:
		return
	var defs: Variant = data_loader.get("held_states")
	if defs is Dictionary:
		held_states.set_definitions(defs)


## 剑士线资源初始化：从 class_data["sword_qi_config"] 读取参数。
## 未配置该资源的单位保持零值；只有印记容量大于零的职业可获得印记。
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
	_xinyan_qi_deficit_per_step = maxi(0, int(cfg.get("qi_deficit_per_step", 0)))
	_xinyan_deficit_stat_key = _normalize_stat_key(str(cfg.get("deficit_stat_key", "")))
	_xinyan_deficit_stat_bonus = int(cfg.get("deficit_stat_bonus", 0))
	# 兼容字段（仅供 UI 读，见字段声明处说明）：分档界线换算成剑气绝对值。
	_xinyan_speed_threshold = int(
		float(_qi_max) * float(_xinyan_qi_ratio_threshold_pct) / 100.0)
	_xinyan_speed_bonus = _xinyan_low_qi_stat_bonus \
		if _xinyan_low_qi_stat_key == "SPD" else 0
	_mark_dex_bonus = int(cfg.get("mark_dex_bonus", 2))
	_mark_spd_bonus = int(cfg.get("mark_spd_bonus", 2))
	_mark_str_bonus = int(cfg.get("mark_str_bonus", 2))
	_mark_dex_pct = float(cfg.get("mark_dex_pct", 0))
	_mark_spd_pct = float(cfg.get("mark_spd_pct", 0))
	_mark_str_pct = float(cfg.get("mark_str_pct", 0))
	_apply_xinyan_passive()


## 心眼被动更新：暴击加成 = floor(剑气 / qi_per_crit_pct) × crit_per_qi（剑气 0-100 标度，
## 当前配置 = 每 10 点剑气 +2 → 满气 floor(100/10)×2 = +20 暴击）写入 crit_bonus 钩子。
## 分档属性加成通过 get_effective_stat 实时计算，不需要此处写入。
func _apply_xinyan_passive() -> void:
	if _xinyan_crit_per_qi <= 0:
		return
	if not has_base_xinyan():
		crit_bonus = 0
		return
	crit_bonus = (sword_qi / _xinyan_qi_per_crit_pct) * _xinyan_crit_per_qi


## 基础〔心眼〕是否还在生效：被动没有被回忆升级。升级后（心眼·澄、心眼·梦）不保留基础心眼的
## 剑气与印记属性加成（〔心眼·梦〕notes 明写；升级技能完整替换基础技能，KB 天赋设计要点 §12）。
func has_base_xinyan() -> bool:
	return passive_skill_id == _base_passive_skill_id


## 心眼剑气分档属性加成：剑气 ≤ 上限的 qi_ratio_threshold_pct% 时给低气段属性，
## 高于该比例时给高气段属性。两段属性键与加成值均来自职业 JSON（sword_qi_config）。
## 非剑气类单位（_qi_max<=0）恒返回 0，对其他职业零影响。
func _get_xinyan_stat_bonus(normalized_key: String) -> int:
	if _qi_max <= 0 or not has_base_xinyan():
		return 0
	if _xinyan_qi_deficit_per_step > 0:
		# 整档计算、不足一档不计（设计库 myrmidon_xinyan rules）：剑气 0 → (100−0)/40 = 2 档。
		if _xinyan_deficit_stat_key == "" or normalized_key != _xinyan_deficit_stat_key:
			return 0
		return ((_qi_max - sword_qi) / _xinyan_qi_deficit_per_step) * _xinyan_deficit_stat_bonus
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
