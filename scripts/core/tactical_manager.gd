class_name TacticalManager
extends Node

@onready var turn_manager: TurnManager = $TurnManager
@onready var terrain_layer: Node2D = $TerrainLayer
@onready var highlight_layer: Node2D = $HighlightLayer
@onready var unit_layer: Node2D = $UnitLayer
@onready var popup_layer: Node2D = $PopupLayer

var grid: Grid = Grid.new()
var units: Array = []
var battle_active: bool = false
var _enemy_pacing_timer: Timer
# 天赋载体（Wave 1 · A1）。懒构造：首次分发时按 DataLoader 的 states/talents 建立。
# 无天赋数据或全部被拒收时，_dispatch_talents 立即 return，正式战斗零影响。
#
# ★ 必须用 preload 而不是写 `StateRegistry.new()`：Godot 的全局类名缓存
# （.godot/global_script_class_cache.cfg）只在**编辑器导入时**重建，headless
# `--script` 与 `--headless` 启动都不会重建它。新加的 class_name 在编辑器里能用、
# 在 headless 下会直接 "Identifier not declared in the current scope" 解析失败，
# 整个 tactical_manager.gd 加载不了。preload 走的是资源路径，编译期解析，两边都稳。
const StateRegistryScript := preload("res://scripts/data/state_registry.gd")
const TalentRegistryScript := preload("res://scripts/data/talent_registry.gd")

## 伤害来源标签（对应设计库 `trigger_source` 的闭集值）。用常量而不是散落的
## 字面量——某处多打一个空格就会静默失配，而失配的表现是「卡不触发」，最难查。
const SOURCE_MAIN_HAND: String = "主手"
const SOURCE_OFFHAND: String = "副手"

## 目标选择方式（对应设计库 `Skill.target_mode` 的闭集值，**引擎只读镜像**）。
## 用中文原值、不另造英文枚举，同 trigger 五段的既有决定（`talent_registry.gd` 逐字：
## 「设计库 trigger_event 的中文原值，不另造英文枚举避免双写」）。
##
## ⚠ 别拿 `damage_type` 的 physical/magical/pure 当反例——那是**引擎独有 taxonomy**、
## 不是镜像（见 `talent_registry.gd` 的 SUPPORTED_DAMAGE_TYPES 注释）。英文用于引擎自有
## 概念，中文用于镜像。收成常量而非散落字面量的理由同 SOURCE_MAIN_HAND 那条。
const TARGET_MODE_UNIT: String = "单位"
const TARGET_MODE_CELL: String = "格子"
const TARGET_MODE_DIRECTION: String = "方向"
const TARGET_MODE_SELF: String = "自身"
const SUPPORTED_TARGET_MODES: Array[String] = [
	TARGET_MODE_UNIT, TARGET_MODE_CELL, TARGET_MODE_DIRECTION, TARGET_MODE_SELF,
]

## 技能 JSON `landing_mode`：选完敌人后再选落点。`adjacent_to_target` = 该敌人上下左右相邻的
## 空格（〔踏影〕）。`LANDING_ANCHOR_NONE` 表示还没选敌人。
const LANDING_MODE_ADJACENT: String = "adjacent_to_target"
const LANDING_ANCHOR_NONE: Vector2i = Vector2i(-1, -1)

## 伤害产生路径标签（对应天赋的 `requires_contexts`）。当前只有主动攻击一条路径。
##
## ⚠ 这里原先写着「Wave 4 的防御侧反应会加第二条，那时这个维度才真正开始区分」
## ——**Wave 4 做完了，那句话是错的**。防御侧事件分发的仍然是同一次主动攻击产生的
## 伤害，只是收件人换成被攻击者；产生路径没多出第二条。要等**反击 / 回合外反应
## 攻击**回归，这个维度才会开始区分。
const CONTEXT_ACTIVE_ATTACK: String = "active_attack"

## 事件相对**被作用者**回合的位置（对应天赋的 `requires_turn_phase`）。
## 与上面那条同病相怜：引擎目前没有任何能让单位在自己回合内被攻击的路径
## （`_execute_hostile_action` 只可能由当前行动单位发起），所以它此刻恒成立。
const TURN_PHASE_OUTSIDE_OWN: String = "outside_own_turn"
const TURN_PHASE_OWN: String = "own_turn"

## 招架架势的 buff id。减伤参数（概率属性 / 基础幅度 / 幅度属性）读它的 JSON
## `parry` 段——招架架势与交刃**共读这一份**，这就是设计库「按招架的减伤结算」
## 那句话在引擎侧的落法。
const PARRY_STANCE_BUFF_ID: String = "swordsman_parry_stance"

## 九属性的显示名（R2.1 的九项，中文名取 KB `01-Game-Design/Core-Systems/battle-calculation.md`
## 的 UnitStats 表）。只用于**给玩家看的文案**，不参与任何结算；属性键本身仍是英文
## （引擎自有 taxonomy），查不到就原样回退英文键，不静默变空。
const STAT_DISPLAY_NAMES: Dictionary = {
	"HP": "生命", "STR": "力量", "MAG": "魔力", "DEX": "技巧", "SPD": "速度",
	"LCK": "幸运", "DEF": "防御", "RES": "抗性", "MOV": "移动力",
}

## 副手追加的链长上限。**护栏，不是游戏数值**：燕返的链长期望本就有限
## （DEX% 起始、每成功一次 ×80% 衰减），真撞上这个数说明概率或衰减参数填错了，
## 所以撞上时要响亮告警而不是静默截断。
##
## 名字里的 PER_ACTION 要照 R1.10 读：范围技能对每个目标各调一次
## `_execute_hostile_action`，所以它实际是**每目标**每次攻击动作 20 次，一发 AOE
## 打 3 个人的总上限是 60。这是对的，不是漏算——R1.10 逐字「计次按被作用的目标
## 单位分别进行」，每个目标本就是各自独立的一次结算。
const MAX_OFFHAND_FOLLOWUPS_PER_ACTION: int = 20
var _talent_registry: RefCounted = null
var _state_registry: RefCounted = null

signal battle_started
signal enemy_pacing_finished
signal unit_killed(unit: Unit)
signal dashboard_state_changed

enum InputState {
	IDLE,
	MOVE_PHASE,
	ACTION_PHASE,
	SKILL_TARGETING,
	ATTACK_TARGETING,
	SWIFT_PHASE,
	ANIMATING,
}
const ATTACK_MODE_BASIC: String = "attack"
const ATTACK_MODE_SKILL: String = "skill"

var input_state: InputState = InputState.IDLE
var current_unit: Unit = null
var selected_unit: Unit = null
var _move_range: Dictionary = {}
var _range_display_cells: Array[Vector2i] = []
var _attack_cells: Array[Vector2i] = []
var _area_preview_cells: Array[Vector2i] = []
var _direction_selector_cells: Array[Vector2i] = []
var _path_preview: Array[Vector2i] = []
var _hover_cell: Vector2i = Vector2i.ZERO
var _has_hover_cell: bool = false
var _attack_mode: String = ATTACK_MODE_BASIC
var _selected_skill_id: String = ""
var _targeting_direction: Vector2i = Vector2i.ZERO
## 本次攻击动作里受到敌方命中判定、动作结束后可能反应（〔见切〕反击）的单位：攻击者 → 被攻击者。
var _pending_reactions: Array[Dictionary] = []
## 当前技能动作的主手伤害段里是否造成过伤害（〔若离〕「造成技能伤害时」）。
var _action_dealt_damage: bool = false
## 两段选目标（landing_mode）时已选中的敌人格；第二段在它周围选落点。
var _landing_anchor: Vector2i = LANDING_ANCHOR_NONE
var _skill_bar_expanded: bool = false
var _inspected_unit: Unit = null
var _pre_move_position: Vector2i = Vector2i.ZERO
var _move_committed: bool = false
var _combat_forecast: Dictionary = {}
var _targeting_origin_state: InputState = InputState.IDLE

# ── 调试 harness（测试场景专用，默认全关，不影响正式战斗）──────────
# 确定性开关：开时所有敌对结算强制命中 + 暴击三态可控。
enum CritMode { RANDOM, FORCE, DISABLE }
enum DummyBehavior { IDLE, AUTO }
## 总开关：仅测试场景在 _ready 置 true；false 时所有调试行为 inert，正式战斗不受影响。
var debug_harness_active: bool = false
var debug_deterministic: bool = false
var debug_crit_mode: CritMode = CritMode.RANDOM
var debug_dummy_behavior: DummyBehavior = DummyBehavior.IDLE
# 记录初始站位，供软重置回位（spawn 时填充）。
var _debug_spawn_positions: Dictionary = {}

# ── 敌人词条（affix）时机分发 —— 纯加法，无词条单位零影响 ─────────
# v0 声明式占位词条 id（挂载但效果待后续时机 hook 实装；非静默，_notify 一次性提示）。
# afs_bulwark→_build_hostile_action_context 防御乘区、af_vanguard→unit SPD 首回合态 均已实装并移出；
# af_zone_expand（控制区）随 ZOC 系统于 2026-07-06 完全移除；其余占位词条已随所依赖系统废弃而移除。
# 当前无占位词条，列表为空（机制对空数组安全，扫描空转）。
const _AFFIX_V0_PLACEHOLDERS: Array[String] = []
# 占位提示去重（affix_id → 已提示），保证「未实装」显式可见但不刷屏。
var _affix_placeholder_seen: Dictionary = {}
# 已做过占位扫描的单位实例 id 集合（每单位仅扫描一次）。
var _affix_swept_units: Dictionary = {}


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
	initialize_battle_data(map_data)


## 调用方验证过的地图可直接进入战斗，不需要写入 DataLoader 的全局地图表。
func initialize_battle_data(map_data: Dictionary) -> void:
	grid.initialize(map_data.duplicate(true))
	_render_terrain()
	battle_started.emit()


func start_battle() -> void:
	battle_active = true
	var typed_units: Array[Unit] = []
	for u in units:
		typed_units.append(u)
		# 持有型状态（含永久状态）每场战斗开始时为 0 层（设计库〔澄心〕〔剑痕〕〔太阳〕等 effect）。
		var battle_unit: Unit = u as Unit
		if battle_unit != null:
			battle_unit.held_states.clear()
			battle_unit.is_taking_turn = false
	turn_manager.add_units(typed_units)
	turn_manager.start()


func stop_battle() -> void:
	battle_active = false
	_finish_enemy_pacing()
	for unit: Unit in units:
		if is_instance_valid(unit):
			unit.cancel_movement()
			# 战斗在某人回合中途结束时 turn_ended 不会发出。
			unit.is_taking_turn = false
	turn_manager.stop()
	_clear_hover_state()
	_clear_highlights()
	_clear_dashboard_state()
	_emit_dashboard_state_changed()


func get_selected_skill_id() -> String:
	return _selected_skill_id


func get_dashboard_data() -> Dictionary:
	var info_unit: Unit = _get_dashboard_unit()
	if info_unit == null:
		return {"visible": false}

	var is_enemy_info: bool = _is_enemy_info_mode()
	var qi_threshold_pct: int = info_unit._xinyan_qi_ratio_threshold_pct
	var qi_band: StringName = &"none"
	if info_unit._qi_max > 0 and qi_threshold_pct >= 0:
		qi_band = &"low" if info_unit.sword_qi * 100 <= info_unit._qi_max * qi_threshold_pct else &"high"
	return {
		"visible": true,
		"mode": "enemy" if is_enemy_info else "player",
		"unit_name": info_unit.unit_name,
		"unit_label": info_unit.get_short_label(),
		"hp": info_unit.stats.hp,
		"hp_max": info_unit.stats.max_hp,
		"hp_ratio": float(info_unit.stats.hp) / maxf(1.0, float(info_unit.stats.max_hp)),
		"shield": info_unit.shield,
		"status_text": info_unit.get_action_status_summary(),
		"action_resources": {
			"movement_used": info_unit.movement_used,
			"standard_used": info_unit.standard_used,
			"swift_used": info_unit.swift_used,
			"movement_remaining": maxi(0, info_unit.stats.mov),
			"movement_available": not info_unit.movement_used,
			"standard_capacity": 1,
			"standard_remaining": 0 if info_unit.standard_used else 1,
			"swift_capacity": 1,
			"swift_remaining": 0 if info_unit.swift_used else 1,
		},
		"phase_text": _get_phase_text(),
		"show_actions": not is_enemy_info and _is_player_turn_active(),
		"buttons": _build_primary_button_state(),
		# B1：技能栏玩家回合常驻（去掉 _skill_bar_expanded 闸；施放后不再自动隐藏）。
		"skills_visible": not is_enemy_info and _is_player_turn_active(),
		"skills": _get_skill_entries(),
		"selected_skill_id": _selected_skill_id,
		"forecast": _combat_forecast.duplicate(true),
		"hint_text": _get_dashboard_hint_text(),
		"class_resource_display": {
			"class_id": info_unit.unit_id,
			"mark_capacity": info_unit._mark_max,
			"qi_threshold_ratio": float(qi_threshold_pct) / 100.0 if qi_threshold_pct >= 0 else -1.0,
			"qi_band": qi_band,
		},
		# ── 主属性面板：基础值 + 括号加成（stats_delta=生效−基础，含印记/心眼/buff）──
		"stats": {
			"str": info_unit.stats.str_attr, "mag": info_unit.stats.mag,
			"dex": info_unit.stats.dex, "spd": info_unit.stats.spd,
			"def": info_unit.stats.def_attr, "res": info_unit.stats.res,
			"lck": info_unit.stats.lck, "mov": info_unit.stats.mov,
		},
		"stats_delta": {
			"str": info_unit.get_effective_stat("STR") - info_unit.stats.str_attr,
			"mag": info_unit.get_effective_stat("MAG") - info_unit.stats.mag,
			"dex": info_unit.get_effective_stat("DEX") - info_unit.stats.dex,
			"spd": info_unit.get_effective_stat("SPD") - info_unit.stats.spd,
			"def": info_unit.get_effective_stat("DEF") - info_unit.stats.def_attr,
			"res": info_unit.get_effective_stat("RES") - info_unit.stats.res,
			"lck": info_unit.get_effective_stat("LCK") - info_unit.stats.lck,
			"mov": info_unit.get_effective_stat("MOV") - info_unit.stats.mov,
		},
		# ── 剑圣专属资源（非剑圣单位：sword_qi=-1 隐藏显示）──
		"sword_qi": info_unit.sword_qi if info_unit._qi_max > 0 else -1,
		"sword_qi_max": info_unit._qi_max,
		"marks": info_unit.marks.duplicate() if info_unit._mark_max > 0 else {},
		# 剑气分段条阈值（速度+1）供 UI 读，纯加法（缺省由 UI 侧回退 7）。
		"sword_qi_config": {
			"speed_threshold": info_unit._xinyan_speed_threshold,
		} if info_unit._qi_max > 0 else {},
	}


## 当前悬停格的世界坐标（供浮窗定位）。纯只读 helper、纯加法。
## 无有效悬停格时返回 has=false；调用方据此隐藏浮窗。
func get_hover_world_pos() -> Dictionary:
	if not _has_hover_cell or not grid.is_valid(_hover_cell):
		return {"has": false, "world": Vector2.ZERO}
	return {"has": true, "world": grid.grid_to_world(_hover_cell)}


## 是否处于攻击/技能瞄准态（供浮窗只在瞄准时显示）。纯只读 helper。
func is_targeting_active() -> bool:
	return input_state == InputState.ATTACK_TARGETING \
		or input_state == InputState.SKILL_TARGETING


func request_skill_selection(skill_id: String) -> void:
	if input_state == InputState.ANIMATING:
		return
	var unit: Unit = _get_player_dashboard_unit()
	if unit == null:
		return
	if _selected_skill_id == skill_id and input_state == InputState.SKILL_TARGETING:
		_cancel_targeting()
		return

	var skill_data: Dictionary = _get_skill_data(skill_id)
	var entry: Dictionary = _build_skill_entry(unit, skill_id)
	if not bool(entry.get("available", false)):
		print("[Skill] %s unavailable: %s" % [skill_id, str(entry.get("reason", ""))])
		return
	var validation: Dictionary = GameAction.validate_skill_usage(unit, skill_data)
	if not bool(validation.get("ok", false)):
		print("[Skill] %s unavailable: %s" % [skill_id, str(validation.get("reason", ""))])
		return

	_selected_skill_id = skill_id
	_skill_bar_expanded = true
	_clear_targeting_buffers()
	var range_data: Dictionary = skill_data.get("range", {})
	if str(range_data.get("type", "")) == "self":
		var action: GameAction = _build_skill_action(
			unit, unit.grid_position, grid.get_unit_at(unit.grid_position))
		if action != null:
			_execute_skill_from_input(action)
		return

	_targeting_origin_state = input_state
	input_state = InputState.SKILL_TARGETING
	_attack_mode = ATTACK_MODE_SKILL
	_refresh_attack_cells()
	_recalculate_hover_artifacts()
	_show_attack_highlights()
	_emit_dashboard_state_changed()


## 兑现回忆（gameplay-impl PR5，差距清单 M10）：测试与调试入口，经 GameAction.APPLY_MEMORY 执行。
## 不消耗行动资源 [推断：回忆是构筑选择，设计没有给战斗内兑现规定代价]。
## 该单位正在为技能选目标时拒绝，免得选中的技能在目标选择途中被换掉；
## 动作动画结算途中也拒绝，免得冷却记到已被替换的基础技能上。
func request_apply_memory(unit: Unit, memory_id: String) -> Dictionary:
	if unit == null:
		return {"ok": false, "reason": "没有单位"}
	return _execute_apply_memory(GameAction.make_apply_memory(unit, memory_id))


func _execute_apply_memory(action: GameAction) -> Dictionary:
	if action == null or action.type != GameAction.Type.APPLY_MEMORY or action.actor == null:
		return {"ok": false, "reason": "不是回忆兑现动作"}
	var actor: Unit = action.actor
	if input_state == InputState.ANIMATING:
		return {"ok": false, "reason": "动作结算中，不能兑现回忆"}
	if actor == current_unit and input_state == InputState.SKILL_TARGETING:
		return {"ok": false, "reason": "正在为技能选择目标，不能兑现回忆"}
	var memory_id: String = str(action.data.get("memory_id", ""))
	var result: Dictionary = actor.apply_memory(memory_id)
	if bool(result.get("ok", false)):
		print("[TacticalManager] %s 兑现回忆 %s" % [actor.unit_name, memory_id])
		_emit_dashboard_state_changed()
	else:
		push_warning("[TacticalManager] 回忆 %s 未兑现：%s" % [memory_id, str(result.get("reason", ""))])
	return result


func request_end_turn() -> void:
	if input_state == InputState.ANIMATING:
		return
	if not _is_player_turn_active():
		return
	_end_player_turn()


func request_attack_targeting() -> void:
	if not _can_enter_attack_targeting():
		return
	_inspected_unit = null
	_skill_bar_expanded = false
	_selected_skill_id = ""
	_clear_targeting_buffers()
	_attack_mode = ATTACK_MODE_BASIC
	_targeting_origin_state = input_state
	input_state = InputState.ATTACK_TARGETING
	_refresh_attack_cells()
	_recalculate_hover_artifacts()
	_show_attack_highlights()
	_emit_dashboard_state_changed()


func request_toggle_skill_bar() -> void:
	if input_state == InputState.ANIMATING:
		return
	if not _is_player_turn_active():
		return
	_inspected_unit = null
	_skill_bar_expanded = not _skill_bar_expanded
	_emit_dashboard_state_changed()


func request_end_move() -> void:
	if input_state != InputState.MOVE_PHASE:
		return
	if current_unit == null:
		return
	_complete_move_phase(false)


func request_cancel_action() -> void:
	if input_state != InputState.ANIMATING:
		_handle_cancel_action()


func handle_pointer_hover(screen_pos: Vector2) -> void:
	if not battle_active:
		return
	if current_unit == null or current_unit.faction != "player":
		return
	if input_state == InputState.ANIMATING:
		return
	var world_pos: Vector2 = _screen_to_world(screen_pos)
	_update_hover(grid.world_to_grid(world_pos))


func handle_pointer_click(screen_pos: Vector2) -> void:
	if not battle_active:
		return
	if current_unit == null or current_unit.faction != "player":
		return
	if input_state == InputState.ANIMATING:
		return
	var world_pos: Vector2 = _screen_to_world(screen_pos)
	var grid_pos: Vector2i = grid.world_to_grid(world_pos)
	_handle_click(grid_pos)


func spawn_unit(class_id: String, spawn_pos: Vector2i,
				faction: String, initial_facing: StringName = &"SE") -> Unit:
	var class_data: Dictionary = DataLoader.classes.get(class_id, {})
	if class_data.is_empty():
		class_data = DataLoader.enemies.get(class_id, {})
	if class_data.is_empty():
		push_error("[TacticalManager] Class/enemy not found: " + class_id)
		return null
	var unit_scene := preload("res://scenes/tactical/Unit.tscn")
	var unit: Unit = unit_scene.instantiate()
	unit.faction = faction
	unit_layer.add_child(unit)
	unit.setup(class_data, initial_facing)
	unit.position = grid.grid_to_world(spawn_pos)
	grid.place_unit(unit, spawn_pos)
	units.append(unit)
	# 记录初始站位（调试软重置回位用），不影响正式流程。
	_debug_spawn_positions[unit.get_instance_id()] = spawn_pos
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
	unit.is_taking_turn = true
	# 持有型状态的「到其后第 N 个自身回合开始」在此计数；额外回合尚未实现，统一按常规回合。
	unit.held_states.on_own_turn_started()
	# R1.17：护盾在每个自身回合开始时自然衰减（不是伤害，不触发受伤类效果）。
	unit.decay_shield()
	_apply_passive_turn_start(unit)
	var turn_start_result: Dictionary = unit.process_turn_start_buffs()
	if not battle_active or turn_manager.current_unit != unit:
		return
	if not unit.stats.is_alive():
		return
	# 敌人词条：回合开始时机分发 + 一次性占位提示（纯加法：无词条 get_affixes() 空即 return）。
	_apply_affixes(unit, "on_turn_start", {})
	_notify_affix_placeholders(unit)
	print("[TurnManager] Turn: %s (%s)" % [unit.unit_name, unit.faction])
	if bool(turn_start_result.get("skip_turn", false)):
		print("[Buff] %s skips turn due to control effect" % unit.unit_name)
		if unit.faction != "player":
			_clear_hover_state()
			_clear_dashboard_state()
			_emit_dashboard_state_changed()
		else:
			_deselect_unit()
		turn_manager.end_current_turn.call_deferred()
		return
	if unit.faction != "player":
		_clear_hover_state()
		_clear_dashboard_state()
		_emit_dashboard_state_changed()
		_do_enemy_turn(unit)
	else:
		_prepare_player_turn(unit)


func _on_turn_ended(unit: Unit) -> void:
	_apply_passive_turn_end(unit)
	unit.process_turn_end_buffs()
	unit.held_states.on_own_turn_ended()
	unit.is_taking_turn = false
	_deselect_unit()


## 被动技能的「自身回合开始时」（〔心眼·梦〕：剑气为上限时进入〔空想〕，持续到本回合结束）。
## 写在被动技能 JSON 的 passive_turn_start 里。
func _apply_passive_turn_start(unit: Unit) -> void:
	var spec: Variant = _get_skill_data(unit.passive_skill_id).get("passive_turn_start", null)
	if not spec is Dictionary or not unit.stats.is_alive():
		return
	var start: Dictionary = spec
	if bool(start.get("requires_qi_full", false)) and (unit._qi_max <= 0 or unit.sword_qi < unit._qi_max):
		return
	var state_id: String = str(start.get("gain_state", ""))
	if state_id == "":
		return
	var duration: Variant = start.get("duration", {})
	unit.apply_held_state(state_id, 1, duration if duration is Dictionary else {})
	unit.refresh_status_icons()
	print("[Passive] %s 进入 %s" % [unit.unit_name, state_id])


## 被动技能的「自身回合结束时」（〔心眼·澄〕：剑气足够则消耗换一层〔澄心〕，否则失去一层）；
## 以及〔空想〕结束时清空剩余剑气与剑痕进度。
func _apply_passive_turn_end(unit: Unit) -> void:
	if unit == null or not unit.stats.is_alive():
		return
	var spec: Variant = _get_skill_data(unit.passive_skill_id).get("passive_turn_end", null)
	if spec is Dictionary:
		var end: Dictionary = spec
		var state_id: String = str(end.get("state_id", ""))
		var qi_cost: int = int(end.get("qi_cost", 0))
		if state_id != "":
			if unit.sword_qi >= qi_cost:
				unit.spend_sword_qi(qi_cost, "passive_turn_end:" + unit.passive_skill_id)
				unit.apply_held_state(state_id, 1, {"kind": "permanent"})
			else:
				unit.held_states.consume_stacks(state_id, 1)
			unit.refresh_status_icons()
	# 〔空想〕「持续到本回合结束」：结束时清空剩余剑气（不计入剑痕）。状态本身由回合计时移除。
	for state_id: String in unit.held_states.held_ids():
		if (DataLoader.held_states.get(state_id, {}) as Dictionary).has("engine_qi_loss_scar"):
			unit.end_qi_loss_scar_state()
			break


func _on_round_ended() -> void:
	print("[TurnManager] === Round ended ===")
	# 敌人词条 af_vanguard（先手部署）：首回合（round 1）结束后关闭速度加成。
	# 无该词条单位 expire_vanguard() 为空操作 → 零影响。round 1 之后再触发亦幂等无害。
	for u_variant: Variant in units:
		var u: Unit = u_variant as Unit
		if u != null:
			u.expire_vanguard()


func _do_enemy_turn(unit: Unit) -> void:
	await _start_enemy_pacing(0.3)
	if not battle_active or turn_manager.current_unit != unit:
		return

	# ── 调试木桩行为开关：仅 AUTO 走正式敌方 AI；IDLE 不主动行动 ──
	# 门控：debug_harness_active=false（正式战斗）时跳过木桩逻辑，直接走敌方 AI。
	if debug_harness_active and debug_dummy_behavior != DummyBehavior.AUTO:
		print("[AI] %s: dummy behavior=%s (no proactive action)" % [
			unit.unit_name, _debug_dummy_behavior_label()])
		if battle_active and is_instance_valid(unit) and unit.stats.is_alive() \
				and turn_manager.current_unit == unit:
			turn_manager.end_current_turn()
		return

	var actions: Array[GameAction] = EnemyAI.decide_actions(unit, grid, units)

	if actions.is_empty():
		print("[AI] %s: no actions (idle)" % unit.unit_name)

	for action in actions:
		if not battle_active or turn_manager.current_unit != unit:
			break
		if not is_instance_valid(unit) or not unit.stats.is_alive():
			break
		match action.type:
			GameAction.Type.MOVE:
				var from := unit.grid_position
				var move_check: Dictionary = GameAction.can_use_normal_move(unit)
				if not bool(move_check.get("ok", false)):
					continue
				print("[AI] %s: move %s → %s" % [
					unit.unit_name, from, action.target_pos])
				GameAction.consume_normal_move(unit)
				unit.refresh_status_icons()
				_emit_dashboard_state_changed()
				await unit.move_to(action.target_pos, grid)
				if not battle_active or not is_instance_valid(unit) or turn_manager.current_unit != unit:
					return
				grid.move_unit(unit, from, action.target_pos)
				await _start_enemy_pacing(0.15)
			GameAction.Type.ATTACK:
				if not is_instance_valid(action.target_unit):
					continue
				print("[AI] %s: attack %s" % [
					unit.unit_name, action.target_unit.unit_name])
				await _execute_presented_attack(action)
			GameAction.Type.SKILL:
				var skill_name := str(action.data.get("skill_name", action.data.get("skill_id", "skill")))
				print("[AI] %s: skill %s" % [unit.unit_name, skill_name])
				await _execute_presented_skill(action)

	if battle_active and is_instance_valid(unit) and unit.stats.is_alive() \
			and turn_manager.current_unit == unit:
		turn_manager.end_current_turn()


func _start_enemy_pacing(seconds: float) -> Signal:
	# 到期与停止战斗共用完成信号，让等待中的动作先退出，再释放场景。
	var timer := Timer.new()
	timer.one_shot = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	timer.timeout.connect(_finish_enemy_pacing)
	add_child(timer)
	_enemy_pacing_timer = timer
	timer.start(seconds)
	return enemy_pacing_finished


func _finish_enemy_pacing() -> void:
	if not is_instance_valid(_enemy_pacing_timer):
		return
	_enemy_pacing_timer.stop()
	_enemy_pacing_timer.queue_free()
	_enemy_pacing_timer = null
	enemy_pacing_finished.emit()


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


func _unhandled_input(_event: InputEvent) -> void:
	pass


func _handle_click(grid_pos: Vector2i) -> void:
	var unit: Unit = grid.get_unit_at(grid_pos)
	match input_state:
		InputState.IDLE:
			if unit != null and unit.faction == "player" \
					and unit == current_unit:
				_select_unit(unit)
		InputState.MOVE_PHASE:
			if selected_unit == null:
				return
			if unit != null and unit.faction == "enemy":
				_show_enemy_info(unit)
			elif grid_pos == selected_unit.grid_position:
				_complete_move_phase(false)
			elif _move_range.has(grid_pos):
				_execute_move(selected_unit, grid_pos)
		InputState.ACTION_PHASE:
			if unit != null:
				_show_unit_info(unit)
		InputState.SKILL_TARGETING:
			if _is_waiting_for_line_direction():
				if grid_pos in _direction_selector_cells:
					_targeting_direction = RangeCalculator.direction_from_to(
						current_unit.grid_position, grid_pos)
					_refresh_attack_cells()
					_recalculate_hover_artifacts()
					_show_attack_highlights()
					_emit_dashboard_state_changed()
				else:
					_cancel_targeting()
			elif _is_waiting_for_landing_target():
				if grid_pos in _attack_cells:
					_landing_anchor = grid_pos
					_refresh_attack_cells()
					_recalculate_hover_artifacts()
					_show_attack_highlights()
					_emit_dashboard_state_changed()
				else:
					_cancel_targeting()
			elif _landing_anchor != LANDING_ANCHOR_NONE:
				if grid_pos in _attack_cells:
					var landing_action: GameAction = _build_skill_action(
						current_unit, _landing_anchor,
						grid.get_unit_at(_landing_anchor), grid_pos)
					if landing_action != null:
						_execute_skill_from_input(landing_action)
				else:
					_cancel_targeting()
			elif _can_confirm_skill_target(grid_pos):
				var skill_action: GameAction = _build_skill_action(
					current_unit, grid_pos, unit)
				if skill_action != null:
					_execute_skill_from_input(skill_action)
			else:
				_cancel_targeting()
		InputState.ATTACK_TARGETING:
			if unit != null and unit.faction != current_unit.faction \
					and grid_pos in _attack_cells:
				var action: GameAction = GameAction.make_attack(current_unit, unit)
				_execute_attack_from_input(action)
			else:
				_cancel_targeting()
		InputState.SWIFT_PHASE:
			pass


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	return canvas_transform.affine_inverse() * screen_pos


func _select_unit(unit: Unit) -> void:
	selected_unit = unit
	_inspected_unit = null
	_skill_bar_expanded = false
	_attack_mode = ATTACK_MODE_BASIC
	_selected_skill_id = ""
	_clear_targeting_buffers()
	_combat_forecast = {}
	input_state = InputState.MOVE_PHASE
	_pre_move_position = unit.grid_position
	_move_committed = false
	_refresh_move_range(unit)
	_recalculate_hover_artifacts()
	_show_move_highlights()
	_emit_dashboard_state_changed()


func _deselect_unit() -> void:
	selected_unit = null
	input_state = InputState.IDLE
	_move_range = {}
	_clear_targeting_buffers()
	_path_preview = []
	_attack_mode = ATTACK_MODE_BASIC
	_selected_skill_id = ""
	_skill_bar_expanded = false
	_inspected_unit = null
	_move_committed = false
	_combat_forecast = {}
	_clear_hover_state()
	_emit_dashboard_state_changed()


func _enter_attack_select() -> void:
	if not _can_enter_attack_targeting():
		return
	_move_range = {}
	_clear_targeting_buffers()
	input_state = InputState.ATTACK_TARGETING
	_attack_mode = ATTACK_MODE_BASIC
	_selected_skill_id = ""
	_skill_bar_expanded = false
	_refresh_attack_cells()
	_recalculate_hover_artifacts()
	_show_attack_highlights()
	_emit_dashboard_state_changed()


func _end_turn_from_attack_select() -> void:
	_end_player_turn()


# ── Highlight colors（方案B — GBA经典明亮）─────────────

const HIGHLIGHT_MOVE_FILL      := Color(0.24, 0.47, 1.00, 0.35)
const HIGHLIGHT_MOVE_BORDER    := Color(0.40, 0.70, 1.00, 0.90)
const HIGHLIGHT_ATTACK_RANGE_FILL := Color(0.92, 0.18, 0.18, 0.20)
const HIGHLIGHT_ATTACK_RANGE_BORDER := Color(1.00, 0.42, 0.28, 0.90)
const HIGHLIGHT_SUPPORT_RANGE_FILL := Color(0.18, 0.72, 0.28, 0.20)
const HIGHLIGHT_SUPPORT_RANGE_BORDER := Color(0.52, 0.94, 0.56, 0.90)
const HIGHLIGHT_ATTACK_TARGET_FILL := Color(1.00, 0.24, 0.24, 0.40)
const HIGHLIGHT_ATTACK_TARGET_BORDER := Color(1.00, 0.60, 0.36, 0.98)
const HIGHLIGHT_SUPPORT_TARGET_FILL := Color(0.18, 0.78, 0.34, 0.42)
const HIGHLIGHT_SUPPORT_TARGET_BORDER := Color(0.62, 1.00, 0.70, 0.98)
const HIGHLIGHT_AREA_FILL      := Color(1.00, 0.30, 0.22, 0.32)
const HIGHLIGHT_AREA_BORDER    := Color(1.00, 0.65, 0.28, 0.94)
const HIGHLIGHT_SELECTOR_FILL  := Color(0.10, 0.78, 0.88, 0.24)
const HIGHLIGHT_SELECTOR_BORDER := Color(0.52, 0.98, 1.00, 0.96)
const HIGHLIGHT_HOVER_FILL     := Color(1.00, 0.94, 0.24, 0.35)
const HIGHLIGHT_HOVER_BORDER   := Color(1.00, 1.00, 0.60, 0.90)
const PATH_PREVIEW_COLOR       := Color(1.00, 0.98, 0.65, 0.95)
const HIGHLIGHT_BORDER_WIDTH   := 2.0


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
	_area_preview_cells = []
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
	if _inspected_unit != null:
		_inspected_unit = null
		_combat_forecast = {}
		_emit_dashboard_state_changed()
		return
	match input_state:
		InputState.MOVE_PHASE:
			_deselect_unit()
		InputState.ACTION_PHASE:
			if not _move_committed:
				_undo_move()
		InputState.SKILL_TARGETING:
			_cancel_targeting()
		InputState.ATTACK_TARGETING:
			_cancel_targeting()
		InputState.SWIFT_PHASE:
			pass


func _recalculate_hover_artifacts() -> void:
	_path_preview = []
	_combat_forecast = {}
	_area_preview_cells = []
	if not _has_hover_cell or not grid.is_valid(_hover_cell):
		_emit_dashboard_state_changed()
		return
	if input_state == InputState.MOVE_PHASE \
			and selected_unit != null \
			and _move_range.has(_hover_cell):
		_path_preview = Pathfinding.find_path(
			grid, selected_unit.grid_position, _hover_cell, selected_unit.faction)
	elif input_state == InputState.ATTACK_TARGETING:
		_combat_forecast = _build_attack_forecast_for_hover(_hover_cell)
	elif input_state == InputState.SKILL_TARGETING \
			and not _is_waiting_for_line_direction() \
			and _hover_cell in _attack_cells:
		var skill_data: Dictionary = _get_skill_data(_selected_skill_id)
		# 两段选目标的第二段：悬停的是落点，预告与范围仍落在已选中的敌人上。
		var forecast_cell: Vector2i = _landing_anchor \
			if _landing_anchor != LANDING_ANCHOR_NONE else _hover_cell
		var area_direction: Vector2i = _get_skill_area_direction(
			current_unit.grid_position, forecast_cell)
		_area_preview_cells = _compute_skill_area_cells(
			current_unit, skill_data, forecast_cell, area_direction)
		_combat_forecast = _build_skill_forecast_for_hover(forecast_cell)
	_emit_dashboard_state_changed()


func _refresh_highlights() -> void:
	_clear_highlights()
	match input_state:
		InputState.MOVE_PHASE:
			for cell_pos: Vector2i in _move_range:
				_add_highlight(cell_pos, HIGHLIGHT_MOVE_FILL, HIGHLIGHT_MOVE_BORDER)
			if _path_preview.size() > 1:
				_add_path_preview(_path_preview)
		InputState.SKILL_TARGETING:
			var range_fill: Color = _get_skill_range_fill_color()
			var range_border: Color = _get_skill_range_border_color()
			var target_fill: Color = _get_skill_target_fill_color()
			var target_border: Color = _get_skill_target_border_color()
			for cell_pos: Vector2i in _direction_selector_cells:
				_add_highlight(
					cell_pos, HIGHLIGHT_SELECTOR_FILL, HIGHLIGHT_SELECTOR_BORDER)
			for cell_pos: Vector2i in _range_display_cells:
				_add_highlight(cell_pos, range_fill, range_border)
			for cell_pos: Vector2i in _attack_cells:
				_add_highlight(cell_pos, target_fill, target_border)
			for cell_pos: Vector2i in _area_preview_cells:
				_add_highlight(cell_pos, HIGHLIGHT_AREA_FILL, HIGHLIGHT_AREA_BORDER)
		InputState.ATTACK_TARGETING:
			for cell_pos: Vector2i in _range_display_cells:
				_add_highlight(
					cell_pos, HIGHLIGHT_ATTACK_RANGE_FILL, HIGHLIGHT_ATTACK_RANGE_BORDER)
			for cell_pos: Vector2i in _attack_cells:
				_add_highlight(
					cell_pos, HIGHLIGHT_ATTACK_TARGET_FILL, HIGHLIGHT_ATTACK_TARGET_BORDER)
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
	return RangeCalculator.calculate_cells(grid, origin, {
		"type": "diamond",
		"min": 1,
		"max": atk_range,
	})


func _get_attack_range_band(origin: Vector2i, min_range: int = 1,
		max_range: int = 1) -> Array[Vector2i]:
	return RangeCalculator.calculate_cells(grid, origin, {
		"type": "diamond",
		"min": min_range,
		"max": max_range,
	})


func _refresh_move_range(unit: Unit) -> void:
	_move_range = {}
	if unit == null or unit.movement_used:
		return
	_move_range = Pathfinding.get_move_range(
		grid, unit.grid_position, unit.stats.mov, unit.faction)
	_move_range.erase(unit.grid_position)


func _clear_selected_skill() -> void:
	_selected_skill_id = ""
	_attack_mode = ATTACK_MODE_BASIC
	_clear_targeting_buffers()
	if input_state == InputState.SKILL_TARGETING:
		_refresh_attack_cells()
		_recalculate_hover_artifacts()
		_show_attack_highlights()
	_emit_dashboard_state_changed()


func _clear_targeting_buffers() -> void:
	_range_display_cells = []
	_attack_cells = []
	_area_preview_cells = []
	_direction_selector_cells = []
	_targeting_direction = Vector2i.ZERO
	_landing_anchor = LANDING_ANCHOR_NONE


func _restore_action_phase_state() -> void:
	if current_unit == null or turn_manager.current_unit != current_unit:
		return
	if not current_unit.stats.is_alive():
		return
	selected_unit = current_unit
	input_state = InputState.ACTION_PHASE
	_attack_mode = ATTACK_MODE_BASIC
	_selected_skill_id = ""
	_clear_targeting_buffers()
	_path_preview = []
	_combat_forecast = {}
	_skill_bar_expanded = false
	_recalculate_hover_artifacts()
	_show_move_highlights()
	_resolve_post_action_phase()


## 只归一 HUD 费用标签，不改变技能消耗和可用性。
func _build_resource_cost_display(skill_data: Dictionary) -> Dictionary:
	var display: Variant = skill_data.get("resource_cost_display", {
		"amount": skill_data.get("qi_cost", 0), "resource_name": "剑气",
	})
	if not display is Dictionary:
		return {}
	var amount: Variant = display.get("amount")
	var resource_name: Variant = display.get("resource_name")
	if not (amount is int or amount is float) or not (resource_name is String or resource_name is StringName):
		return {}
	if not is_finite(float(amount)) or float(amount) != floorf(float(amount)) or int(amount) <= 0 or int(amount) > 999:
		return {}
	var name: String = str(resource_name).strip_edges()
	return {"amount": int(amount), "resource_name": name} if not name.is_empty() else {}


func _build_skill_entry(unit: Unit, skill_id: String) -> Dictionary:
	var skill_data: Dictionary = _get_skill_data(skill_id)
	var cooldown_turns: int = unit.get_skill_cooldown(skill_id)
	var description: String = str(skill_data.get("description", ""))
	var class_descriptions: Variant = skill_data.get("class_descriptions", {})
	if class_descriptions is Dictionary:
		description = str(class_descriptions.get(unit.unit_id, description))
	var display_name: String = str(skill_data.get("name", skill_id))
	var name_form: Dictionary = skill_data.get("held_state_form", {})
	if not name_form.is_empty() and not unit.held_states.has(str(name_form.get("state_id", ""))):
		display_name = str(name_form.get("name_without_state", display_name))
	var entry: Dictionary = {
		"skill_id": skill_id,
		"name": display_name,
		"action_cost": str(skill_data.get("action_cost", "standard")),
		"timing_constraint": str(skill_data.get("timing_constraint", "any")),
		"swift_limit": int(skill_data.get("swift_limit", 1)),
		"cooldown": cooldown_turns,
		"cooldown_max": int(skill_data.get("cooldown", 0)),
		"description": description,
		"available": false,
		"reason": "",
		"selected": skill_id == _selected_skill_id,
		"qi_cost": int(skill_data.get("qi_cost", 0)),
		"mark_cost": int(skill_data.get("mark_cost", 0)),
		"requires_marks": int(skill_data.get("requires_marks", 0)),
		"resource_cost_display": _build_resource_cost_display(skill_data),
	}
	var phase_reason: String = _get_phase_mismatch_reason(skill_data)
	if phase_reason != "":
		entry["reason"] = phase_reason
		return entry
	var validation: Dictionary = GameAction.validate_skill_usage(unit, skill_data)
	if not bool(validation.get("ok", false)):
		entry["reason"] = _localize_skill_unavailable_reason(skill_data, validation)
		return entry
	if not _is_supported_runtime_skill(skill_data):
		entry["reason"] = "当前战斗原型暂不支持此技能范围/目标"
		return entry
	# ── 剑圣资源条件检查 ─────────────────────────────────
	var qi_cost: int = int(skill_data.get("qi_cost", 0))
	if qi_cost > 0 and unit.sword_qi < qi_cost and not unit.allows_qi_overdraft():
		entry["reason"] = "剑气不足（需要 %d，当前 %d）" % [qi_cost, unit.sword_qi]
		return entry
	var requires_marks: int = int(skill_data.get("requires_marks", 0))
	if requires_marks > 0 and unit.get_mark_count() < requires_marks:
		entry["reason"] = "印记不足（需要 %d 个，当前 %d）" % [requires_marks, unit.get_mark_count()]
		return entry
	if bool(skill_data.get("requires_enemy_in_area", false)) \
			and not _has_enemy_in_required_area(unit, skill_data):
		entry["reason"] = "范围内没有敌人"
		return entry
	if _skill_landing_mode(skill_data) == LANDING_MODE_ADJACENT \
			and _get_landing_target_cells(unit, skill_data).is_empty():
		entry["reason"] = "射程内没有可落脚的敌人"
		return entry
	entry["available"] = true
	return entry


func _skill_landing_mode(skill_data: Dictionary) -> String:
	return str(skill_data.get("landing_mode", ""))


## 两段选目标的第一段：还没选敌人。
func _is_waiting_for_landing_target() -> bool:
	if input_state != InputState.SKILL_TARGETING or _selected_skill_id == "":
		return false
	return _skill_landing_mode(_get_skill_data(_selected_skill_id)) == LANDING_MODE_ADJACENT \
		and _landing_anchor == LANDING_ANCHOR_NONE


## 目标上下左右相邻、自身能站立且没被其他单位占据的格（踏影 effect）。自身当前所在格也合法：
## 已经站在目标旁边时原地出手。不检查沿途（直接位移）。多格目标的「完整占据区域」口径未承载（Q7）。
func _get_adjacent_landing_cells(user: Unit, target_pos: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for direction: Vector2i in RangeCalculator.CARDINAL_DIRECTIONS:
		var cell_pos: Vector2i = target_pos + direction
		if not grid.is_valid(cell_pos):
			continue
		var cell: Cell = grid.get_cell(cell_pos)
		if cell == null or not cell.is_passable():
			continue
		if cell.occupant != null and cell.occupant != user:
			continue
		cells.append(cell_pos)
	return cells


## 两段选目标的第一段可选格：射程内、符合目标关系、至少有一个合法落点的单位
## （没有合法落点的敌人不能成为目标）。
func _get_landing_target_cells(user: Unit, skill_data: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var relation: String = _get_skill_target_relation(skill_data)
	for cell_pos: Vector2i in RangeCalculator.calculate_cells(
			grid, user.grid_position, skill_data.get("range", {})):
		if not _matches_target_relation(user, grid.get_unit_at(cell_pos), relation):
			continue
		if _get_adjacent_landing_cells(user, cell_pos).is_empty():
			continue
		cells.append(cell_pos)
	return cells


## 「范围内至少有一名敌人」是否成立。以自身为中心的技能（拔刀）看自身周围；
## 直线射程的方向型技能（裂空「前方直线 3 格」）只要任一方向的范围内有敌人即可。
func _has_enemy_in_required_area(unit: Unit, skill_data: Dictionary) -> bool:
	var range_data: Dictionary = skill_data.get("range", {})
	if str(range_data.get("type", "")) != "line":
		return not _get_enemies_in_cells(unit,
			_compute_skill_area_cells(unit, skill_data, unit.grid_position, Vector2i.ZERO)).is_empty()
	for direction: Vector2i in RangeCalculator.get_line_directions(
			grid, unit.grid_position, range_data):
		for target_pos: Vector2i in RangeCalculator.calculate_cells(
				grid, unit.grid_position, range_data, direction):
			if not _get_enemies_in_cells(unit,
					_compute_skill_area_cells(unit, skill_data, target_pos, direction)).is_empty():
				return true
	return false


## 格子里的敌人（去重；多格单位只算一名）。「范围内有 N 名敌人」类条件只数敌人，
## 与技能自己的作用关系无关（回天是增益技能，作用于自身，却要数周围的敌人）。
func _get_enemies_in_cells(user: Unit, cells: Array[Vector2i]) -> Array[Unit]:
	var by_id: Dictionary = {}
	for cell_pos: Vector2i in cells:
		var unit: Unit = grid.get_unit_at(cell_pos)
		if _matches_target_relation(user, unit, "enemy"):
			by_id[unit.get_instance_id()] = unit
	var out: Array[Unit] = []
	for value: Variant in by_id.values():
		if value is Unit:
			out.append(value)
	return out


## 技能 JSON 的 slot_swap_requires（门槛字典）；没写时为空字典。
func _slot_swap_requires(skill_data: Dictionary) -> Dictionary:
	var requires: Variant = skill_data.get("slot_swap_requires", {})
	return requires if requires is Dictionary else {}


func _get_skill_entries() -> Array[Dictionary]:
	var unit: Unit = _get_player_dashboard_unit()
	var entries: Array[Dictionary] = []
	if unit == null:
		return entries
	# ── 被动技能（心眼）置于技能栏最左侧（仅剑气类单位=剑圣；不可点/无键位/无冷却）──
	var passive_entry: Dictionary = _build_passive_entry(unit)
	if not passive_entry.is_empty():
		entries.append(passive_entry)
	for skill_id: String in unit.skill_ids:
		var slot_skill_data: Dictionary = _get_skill_data(skill_id)
		# ── 槽位提供者（如拔刀 slot_swap_provider）不独立列槽：仅作其 provider 槽
		#    （招架）满印记时的替换形态，避免一开始就常驻为第 5 个技能。──
		if bool(slot_skill_data.get("slot_swap_provider", false)):
			continue
		# ── 槽位替换（数据驱动）：替换规则由技能 JSON 的 slot_swap_* 声明 ──
		var display_id: String = unit.get_visible_skill_id(skill_id,
			str(slot_skill_data.get("slot_swap_trigger", "")),
			str(slot_skill_data.get("slot_swap_target", "")),
			_slot_swap_requires(slot_skill_data))
		var entry: Dictionary = _build_skill_entry(unit, display_id)
		# 保留原始槽位 ID 以便取消时恢复（附加字段，UI 可忽略）
		entry["slot_origin_id"] = skill_id
		entries.append(entry)
	return entries


## 心眼被动条目：技能栏最左侧、不可点、无键位、无冷却（仅剑气类=剑圣）。
## 描述只放效果本体（名字由 UI 的悬停标题补「【心眼】（被动）」）。
##
## ★ 说明文字必须照 _apply_xinyan_passive / Unit._get_xinyan_stat_bonus 的**实际**口径写。
## 2026-08-13 修正前这里写的是「每点剑气 +N% 暴击率；剑气达到 M 时速度 +K」，三处都不对：
## ① 暴击是每 qi_per_crit_pct（10）点剑气加 crit_per_qi（2）**点**，不是每 1 点加 2%，
##    而且它落 R1.3 暴击链的暴击层、是点数不是百分比；
## ② 分档方向是反的——剑气 **≤** 上限比例时给低气段属性（速度），**高于**时换成高气段
##    属性（技巧）。旧文案的「达到 50 时速度 +2」读起来是「攒够就有速度」，恰好相反，
##    会把玩家的经营决策带到反方向；
## ③ 完全没提印记的持有加成，而那是设计库 kensei_xinyan effect 的一整句。
## 旧文案读的 _xinyan_speed_threshold / _xinyan_speed_bonus 是 2026-08-03 换新口径时为兼容
## 它而**派生**出来的两个量（见 unit.gd 的声明），本函数改用新口径的原始配置，不再读它们。
func _build_passive_entry(unit: Unit) -> Dictionary:
	if unit._qi_max <= 0:
		return {}
	# 被动槽在某状态期间换成可用的技能（〔心眼·梦〕在〔空想〕期间变为〔空想剑〕）。
	var swapped: String = _passive_slot_skill_id(unit)
	if swapped != "":
		var swapped_entry: Dictionary = _build_skill_entry(unit, swapped)
		swapped_entry["slot_origin_id"] = unit.passive_skill_id
		return swapped_entry
	# 心眼被回忆升级后：名字与说明取升级技能自己的，基础心眼的加成说明不再适用。
	if not unit.has_base_xinyan():
		var upgraded: Dictionary = _get_skill_data(unit.passive_skill_id)
		return {
			"skill_id": unit.passive_skill_id,
			"name": str(upgraded.get("name", unit.passive_skill_id)),
			"is_passive": true,
			"available": true,
			"description": str(upgraded.get("description", "")),
			"reason": "",
			"cooldown": 0,
			"cooldown_max": 0,
			"action_cost": "",
			"qi_cost": 0,
			"mark_cost": 0,
			"slot_origin_id": unit.passive_skill_id,
		}
	var threshold_qi: int = unit._qi_max * unit._xinyan_qi_ratio_threshold_pct / 100
	var desc: String = ""
	if unit._xinyan_qi_deficit_per_step > 0:
		desc = "每 %d 点剑气，暴击 +%d。剑气每比 %d 点少 %d 点，%s +%d。（均按整档计算）" % [
			unit._xinyan_qi_per_crit_pct, unit._xinyan_crit_per_qi,
			unit._qi_max, unit._xinyan_qi_deficit_per_step,
			_stat_display_name(unit._xinyan_deficit_stat_key), unit._xinyan_deficit_stat_bonus]
	else:
		desc = "每 %d 点剑气，暴击 +%d（向下取整）。剑气不高于 %d 时 %s +%d，高于 %d 时 %s +%d。" % [
			unit._xinyan_qi_per_crit_pct, unit._xinyan_crit_per_qi,
			threshold_qi, _stat_display_name(unit._xinyan_low_qi_stat_key),
			unit._xinyan_low_qi_stat_bonus,
			threshold_qi, _stat_display_name(unit._xinyan_high_qi_stat_key),
			unit._xinyan_high_qi_stat_bonus]
	# 印记持有加成：只在真的有印记的单位上说（_mark_max<=0 的单位拿不到印记）。
	# 三种印记对应哪个属性写死在 Unit.get_effective_stat 里，加成值从职业 JSON 读。
	if unit._mark_max > 0 and (unit._mark_dex_pct > 0 or unit._mark_spd_pct > 0 or unit._mark_str_pct > 0):
		desc += "持有的每枚印记按种类提升属性：心 → %s +%d%%，道 → %s +%d%%，势 → %s +%d%%。" % [
			_stat_display_name("DEX"), int(unit._mark_dex_pct),
			_stat_display_name("SPD"), int(unit._mark_spd_pct),
			_stat_display_name("STR"), int(unit._mark_str_pct)]
	elif unit._mark_max > 0:
		desc += "持有的每枚印记按种类提供属性加成：心 → %s +%d，道 → %s +%d，势 → %s +%d。" % [
			_stat_display_name("DEX"), unit._mark_dex_bonus,
			_stat_display_name("SPD"), unit._mark_spd_bonus,
			_stat_display_name("STR"), unit._mark_str_bonus]
	return {
		"skill_id": unit.passive_skill_id,
		"name": "心眼",
		"is_passive": true,
		"available": true,
		"description": desc,
		"reason": "",
		"cooldown": 0,
		"cooldown_max": 0,
		"action_cost": "",
		"qi_cost": 0,
		"mark_cost": 0,
		"slot_origin_id": unit.passive_skill_id,
	}


## 被动槽此刻换成的技能 id：被动技能 JSON 的 slot_swap_on_state = {state_id, skill_id}，
## 持有该状态时返回 skill_id，否则为空串。
func _passive_slot_skill_id(unit: Unit) -> String:
	var spec: Variant = _get_skill_data(unit.passive_skill_id).get("slot_swap_on_state", null)
	if not spec is Dictionary:
		return ""
	if not unit.held_states.has(str((spec as Dictionary).get("state_id", ""))):
		return ""
	return str((spec as Dictionary).get("skill_id", ""))


## 属性键 → 玩家可见的中文名。查不到就原样返回英文键（宁可露出 "SPE" 也不要显示空白）。
func _stat_display_name(stat_key: String) -> String:
	return str(STAT_DISPLAY_NAMES.get(stat_key, stat_key))


func _emit_dashboard_state_changed() -> void:
	dashboard_state_changed.emit()


func _prepare_player_turn(unit: Unit) -> void:
	selected_unit = unit
	_inspected_unit = null
	_skill_bar_expanded = false
	_attack_mode = ATTACK_MODE_BASIC
	_selected_skill_id = ""
	_clear_targeting_buffers()
	_combat_forecast = {}
	_pre_move_position = unit.grid_position
	_move_committed = false
	input_state = InputState.MOVE_PHASE
	_refresh_move_range(unit)
	_update_hover(unit.grid_position)
	_show_move_highlights()
	_emit_dashboard_state_changed()


func _clear_dashboard_state() -> void:
	selected_unit = null
	_move_range = {}
	_clear_targeting_buffers()
	_path_preview = []
	_attack_mode = ATTACK_MODE_BASIC
	_selected_skill_id = ""
	_skill_bar_expanded = false
	_inspected_unit = null
	_move_committed = false
	_combat_forecast = {}
	_targeting_origin_state = InputState.IDLE
	input_state = InputState.IDLE


func _get_dashboard_unit() -> Unit:
	if _inspected_unit != null and _inspected_unit.stats.is_alive():
		return _inspected_unit
	return _get_player_dashboard_unit()


func _get_player_dashboard_unit() -> Unit:
	if not _is_player_turn_active():
		return null
	if input_state == InputState.IDLE:
		return null
	return current_unit


func _is_player_turn_active() -> bool:
	return current_unit != null \
		and current_unit.faction == "player" \
		and turn_manager.current_unit == current_unit


func _is_enemy_info_mode() -> bool:
	return _inspected_unit != null and _inspected_unit.faction == "enemy"


func _build_primary_button_state() -> Dictionary:
	return {
		"attack_visible": input_state != InputState.SWIFT_PHASE,
		"attack_disabled": not _can_enter_attack_targeting(),
		"attack_reason": _get_attack_button_reason(),
		"skill_visible": true,
		"skill_disabled": false,
		"skill_reason": "",
		"item_visible": input_state != InputState.SWIFT_PHASE,
		"item_disabled": true,
		"item_reason": "暂未开放",
		"end_turn_visible": true,
		"end_turn_disabled": false,
		"end_move_visible": input_state == InputState.MOVE_PHASE,
		"end_move_disabled": false,
		"cancel_visible": input_state != InputState.SWIFT_PHASE,
		"cancel_disabled": input_state == InputState.IDLE,
		"cancel_reason": "",
	}


func _get_phase_text() -> String:
	match input_state:
		InputState.MOVE_PHASE:
			return "移动阶段"
		InputState.ACTION_PHASE:
			return "行动阶段"
		InputState.SKILL_TARGETING:
			return "技能瞄准"
		InputState.ATTACK_TARGETING:
			return "攻击瞄准"
		InputState.SWIFT_PHASE:
			return "迅捷阶段"
		InputState.ANIMATING:
			return "执行中"
		_:
			return "待机"


func _get_dashboard_hint_text() -> String:
	if _is_enemy_info_mode():
		return "只读信息，右键或 ESC 关闭"
	match input_state:
		InputState.MOVE_PHASE:
			return "选择移动格，或点自身/结束移动进入行动阶段"
		InputState.ACTION_PHASE:
			return "可攻击、用技能，或右键/ESC 撤销移动"
		InputState.SKILL_TARGETING:
			if _is_waiting_for_line_direction():
				return "先选择施法方向，再选择目标格"
			return "选择合法目标，右键或 ESC 取消"
		InputState.ATTACK_TARGETING:
			return "悬停敌人查看预测，左键确认攻击"
		InputState.SWIFT_PHASE:
			return "仅可使用迅捷技能，或直接结束回合"
		_:
			return ""


func _show_enemy_info(unit: Unit) -> void:
	_inspected_unit = unit
	_combat_forecast = {}
	_emit_dashboard_state_changed()


func _show_unit_info(unit: Unit) -> void:
	if unit.faction == "enemy":
		_show_enemy_info(unit)
	else:
		_inspected_unit = null
		_emit_dashboard_state_changed()


func _complete_move_phase(moved: bool) -> void:
	if current_unit == null:
		return
	if not moved:
		_pre_move_position = current_unit.grid_position
		_move_committed = false
	selected_unit = current_unit
	_inspected_unit = null
	_clear_targeting_buffers()
	_move_range = {}
	_path_preview = []
	_attack_mode = ATTACK_MODE_BASIC
	_selected_skill_id = ""
	_skill_bar_expanded = false
	_combat_forecast = {}
	input_state = InputState.ACTION_PHASE
	_recalculate_hover_artifacts()
	_refresh_highlights()
	_emit_dashboard_state_changed()


func _undo_move() -> void:
	if current_unit == null:
		return
	var from_pos: Vector2i = current_unit.grid_position
	if from_pos != _pre_move_position:
		current_unit.position = grid.grid_to_world(_pre_move_position)
		grid.move_unit(current_unit, from_pos, _pre_move_position)
	else:
		current_unit.position = grid.grid_to_world(_pre_move_position)
	current_unit.restore_movement_resource()
	current_unit.refresh_status_icons()
	selected_unit = current_unit
	_clear_targeting_buffers()
	_selected_skill_id = ""
	_skill_bar_expanded = false
	_inspected_unit = null
	_combat_forecast = {}
	_move_committed = false
	input_state = InputState.MOVE_PHASE
	_refresh_move_range(current_unit)
	_recalculate_hover_artifacts()
	_show_move_highlights()
	_emit_dashboard_state_changed()


func _cancel_targeting() -> void:
	var origin_state: InputState = _targeting_origin_state
	var keep_skill_bar_open: bool = input_state == InputState.SKILL_TARGETING
	_clear_targeting_buffers()
	_selected_skill_id = ""
	_attack_mode = ATTACK_MODE_BASIC
	_combat_forecast = {}
	_skill_bar_expanded = keep_skill_bar_open
	_targeting_origin_state = InputState.IDLE
	if origin_state == InputState.MOVE_PHASE:
		input_state = InputState.MOVE_PHASE
		_refresh_move_range(current_unit)
	else:
		input_state = InputState.ACTION_PHASE
		_move_range = {}
	_recalculate_hover_artifacts()
	_refresh_highlights()
	_emit_dashboard_state_changed()


func _end_player_turn() -> void:
	if not _is_player_turn_active():
		return
	_clear_hover_state()
	_clear_highlights()
	_clear_dashboard_state()
	turn_manager.end_current_turn()


func _can_enter_attack_targeting() -> bool:
	if input_state != InputState.ACTION_PHASE:
		return false
	if current_unit == null:
		return false
	var validation: Dictionary = GameAction.can_use_normal_attack(current_unit)
	return bool(validation.get("ok", false))


func _get_attack_button_reason() -> String:
	if current_unit == null:
		return ""
	if input_state == InputState.MOVE_PHASE:
		return "当前处于移动阶段，请先完成移动"
	var validation: Dictionary = GameAction.can_use_normal_attack(current_unit)
	if bool(validation.get("ok", false)):
		return ""
	if not current_unit.has_basic_attack:
		return "该职业没有普通攻击"
	return "攻击机会已使用"


func _resolve_post_action_phase() -> void:
	if not _is_player_turn_active():
		return
	if current_unit.standard_used:
		if _has_available_swift_skill(current_unit):
			input_state = InputState.SWIFT_PHASE
			_clear_targeting_buffers()
			_move_range = {}
			_path_preview = []
			_attack_mode = ATTACK_MODE_BASIC
			_selected_skill_id = ""
			_skill_bar_expanded = true
			_emit_dashboard_state_changed()
		else:
			_end_player_turn()
	else:
		input_state = InputState.ACTION_PHASE
		_emit_dashboard_state_changed()


func _handle_post_skill_execution(previous_state: InputState,
		action: GameAction) -> void:
	var action_cost: String = str(action.data.get("action_cost", "standard"))
	var source_state: InputState = previous_state
	if previous_state == InputState.SKILL_TARGETING:
		source_state = _targeting_origin_state
	_targeting_origin_state = InputState.IDLE
	match action_cost:
		"move":
			_complete_move_phase(true)
		"standard":
			_restore_action_phase_state()
		# 自由动作（决心）与迅捷一样不占移动和标准动作，用完回到原来的阶段。
		"swift", "free":
			match source_state:
				InputState.MOVE_PHASE:
					input_state = InputState.MOVE_PHASE
					_skill_bar_expanded = false
					_refresh_move_range(current_unit)
					_recalculate_hover_artifacts()
					_show_move_highlights()
					_emit_dashboard_state_changed()
				InputState.SWIFT_PHASE:
					_restore_action_phase_state()
				_:
					input_state = InputState.ACTION_PHASE
					_skill_bar_expanded = false
					_clear_targeting_buffers()
					_recalculate_hover_artifacts()
					_refresh_highlights()
					_emit_dashboard_state_changed()
		_:
			_restore_action_phase_state()


## 这个单位此刻还有迅捷技能（或自由动作技能）可用吗（决定标准动作用完之后进迅捷阶段还是直接结束回合）。
##
## ★ 必须与 `_get_skill_entries` 看到**同一批槽**，否则会出现「进了迅捷阶段，可技能栏里
## 一个迅捷技能都没有」。2026-08-13 修：此前这里遍历的是 `unit.skill_ids` 原始 id，不走
## `Unit.get_visible_skill_id` 的槽位替换，于是剑圣印记满 3 时它仍然看到招架（swift、剑气
## 够、冷却好）判为「有迅捷可用」，而技能栏那一格已经换成拔刀（standard，攻击机会已用完）。
## 玩家因此被送进一个什么都点不出来的阶段。病根与招架架势那条同型：一个查询函数忘了套用
## 另一处已经做了的变换。
func _has_available_swift_skill(unit: Unit) -> bool:
	# 被动槽换出的技能（空想剑，迅捷）与技能栏一致地参与判定。
	var passive_swap: String = _passive_slot_skill_id(unit)
	if passive_swap != "" and _is_usable_swift_or_free(unit, _get_skill_data(passive_swap)):
		return true
	for slot_id: String in unit.skill_ids:
		var slot_data: Dictionary = _get_skill_data(slot_id)
		# 槽位提供者（拔刀）不独立占槽，口径同 _get_skill_entries。当前它是 standard、
		# 下面那道 action_cost 闸也会滤掉它；这一行是为了让两个函数的取槽规则逐条对齐，
		# 将来出现迅捷型 provider 时不必再想起还有这里。
		if bool(slot_data.get("slot_swap_provider", false)):
			continue
		var skill_id: String = unit.get_visible_skill_id(slot_id,
			str(slot_data.get("slot_swap_trigger", "")),
			str(slot_data.get("slot_swap_target", "")),
			_slot_swap_requires(slot_data))
		var skill_data: Dictionary = _get_skill_data(skill_id)
		# 自由动作（决心）同样可以在标准动作之后使用，算进来，免得回合被自动结束。
		if str(skill_data.get("action_cost", "")) not in ["swift", "free"]:
			continue
		if _get_phase_mismatch_reason(skill_data) != "":
			continue
		if not _is_supported_runtime_skill(skill_data):
			continue
		var validation: Dictionary = GameAction.validate_skill_usage(unit, skill_data)
		if bool(validation.get("ok", false)):
			return true
	return false


func _is_usable_swift_or_free(unit: Unit, skill_data: Dictionary) -> bool:
	if str(skill_data.get("action_cost", "")) not in ["swift", "free"]:
		return false
	if _get_phase_mismatch_reason(skill_data) != "" or not _is_supported_runtime_skill(skill_data):
		return false
	return bool(GameAction.validate_skill_usage(unit, skill_data).get("ok", false))


func _get_phase_mismatch_reason(skill_data: Dictionary) -> String:
	var action_cost: String = str(skill_data.get("action_cost", "standard"))
	if input_state == InputState.MOVE_PHASE and action_cost == "standard":
		return "当前处于移动阶段，请先完成移动"
	return ""


func _localize_skill_unavailable_reason(skill_data: Dictionary,
		validation: Dictionary) -> String:
	var reason: String = str(validation.get("reason", ""))
	var skill_id: String = str(skill_data.get("id", ""))
	if skill_id != "" and current_unit != null and current_unit.get_skill_cooldown(skill_id) > 0:
		return "冷却中 (%d 回合后恢复)" % current_unit.get_skill_cooldown(skill_id)
	match reason:
		"Movement already used":
			return "已失去移动机会"
		"Standard Action already used":
			return "攻击机会已使用"
		"Swift Action already used":
			return "迅捷机会已使用"
		"Must use before moving":
			return "需要在移动前使用"
		"Must use after moving":
			return "需要在移动后使用"
		"Must use before attacking":
			return "需要在攻击前使用"
		"Must use after attacking":
			return "需要在攻击后使用"
		_:
			return reason


func _build_attack_forecast_for_hover(grid_pos: Vector2i) -> Dictionary:
	if current_unit == null or input_state != InputState.ATTACK_TARGETING:
		return {}
	if grid_pos not in _attack_cells:
		return {}
	var target: Unit = grid.get_unit_at(grid_pos)
	if target == null or target.faction == current_unit.faction:
		return {}
	var action: GameAction = GameAction.make_attack(current_unit, target)
	var preview_data: Dictionary = _build_hostile_action_context(
		current_unit, target, action.data)
	var preview: Dictionary = DamageCalculator.preview_attack(
		current_unit, target, preview_data)
	var dmg: int = int(preview.get("damage", 0))
	var hit_pct: int = int(preview.get("hit_percent", 0))
	var crit_pct: int = int(preview.get("crit_percent", 0))
	var dtype: String = str(preview_data.get("damage_type", "physical"))
	return {
		"visible": true,
		"target_name": target.unit_name,
		"hit_percent": hit_pct,
		"crit_percent": crit_pct,
		"damage": dmg,
		"hit_count": int(preview.get("hit_count", 1)),
		"per_hit_damage": int(preview.get("per_hit_damage", preview.get("damage", 0))),
		"total_damage": int(preview.get("total_damage", preview.get("damage", 0))),
		"damage_type": dtype,
		"is_heal": bool(preview.get("is_heal", false)),
		"terrain_name": str(preview.get("terrain_name", "PLAIN")),
		"terrain_evade_bonus": int(preview.get("terrain_evade_bonus", 0)),
		"terrain_def_bonus": int(preview.get("terrain_def_bonus", 0)),
		"terrain_res_bonus": int(preview.get("terrain_res_bonus", 0)),
		# 新增：头顶数字 + FE 浮窗所需字段
		"targets": [{
			"world": target.get_combat_text_anchor_world(-30.0),
			"damage": dmg,
			"damage_type": dtype,
			"hit_percent": hit_pct,
			"crit_percent": crit_pct,
			"is_primary": true,
		}],
		"target_hp": target.stats.hp,
		"target_hp_max": target.stats.max_hp,
	}


## 技能瞄准 forecast：对 area 内每个敌方单位跑 preview_attack，按项⑤溅射规则汇总。
## 字段集与 _build_attack_forecast_for_hover 完全同名 → 现有 dashboard 渲染零改动吃下。
func _build_skill_forecast_for_hover(grid_pos: Vector2i) -> Dictionary:
	if current_unit == null or input_state != InputState.SKILL_TARGETING:
		return {}
	if _selected_skill_id == "" or _is_waiting_for_line_direction():
		return {}
	if grid_pos not in _attack_cells and grid_pos != _landing_anchor:
		return {}
	var skill_data: Dictionary = _get_skill_data(_selected_skill_id)
	if skill_data.is_empty():
		return {}
	# self / 支援（招架等）技能不做伤害 forecast。
	if _is_support_skill(skill_data) \
			or str(skill_data.get("range", {}).get("type", "")) == "self":
		return {}

	var area_direction: Vector2i = _get_skill_area_direction(
		current_unit.grid_position, grid_pos)
	var area_cells: Array[Vector2i] = _compute_skill_area_cells(
		current_unit, skill_data, grid_pos, area_direction)
	var target_units: Array[Unit] = _get_units_in_skill_area(
		current_unit, skill_data, area_cells)
	if target_units.is_empty():
		return {}

	var splash_pct: int = int(skill_data.get("splash_damage_pct", 100))
	# 用 _build_skill_action 构造 payload，保证 forecast 与执行字段一致。
	var action: GameAction = _build_skill_action(current_unit, grid_pos, null)
	if action == null:
		return {}
	var base_payload: Dictionary = action.data

	var total_damage: int = 0
	var hit_count: int = 0
	var primary_name: String = ""
	var primary_per_hit: int = 0
	var primary_hit_percent: int = 0
	var primary_crit_percent: int = 0
	var primary_terrain_name: String = "PLAIN"
	var primary_terrain_evade: int = 0
	var primary_terrain_def: int = 0
	var primary_terrain_res: int = 0
	var first_per_hit: int = 0
	var has_first: bool = false
	# 新增：每受影响目标独立条目（头顶数字 + FE 浮窗用）
	var targets_list: Array[Dictionary] = []
	var primary_target_unit: Unit = null

	for target_unit: Unit in target_units:
		var per_target: Dictionary = base_payload.duplicate(true)
		var is_primary_cell: bool = target_unit.grid_position == grid_pos
		if is_primary_cell:
			per_target["area_damage_multiplier"] = 1.0
		else:
			per_target["area_damage_multiplier"] = float(splash_pct) / 100.0
		var preview_data: Dictionary = _build_hostile_action_context(
			current_unit, target_unit, per_target)
		var preview: Dictionary = DamageCalculator.preview_attack(
			current_unit, target_unit, preview_data)
		var dmg: int = int(preview.get("damage", 0))
		total_damage += dmg
		hit_count += 1
		var t_hit: int = int(preview.get("hit_percent", 0))
		var t_crit: int = int(preview.get("crit_percent", 0))
		targets_list.append({
			"world": target_unit.get_combat_text_anchor_world(-30.0),
			"damage": dmg,
			"damage_type": str(preview_data.get("damage_type", "physical")),
			"hit_percent": t_hit,
			"crit_percent": t_crit,
			"is_primary": is_primary_cell,
		})
		if not has_first:
			has_first = true
			first_per_hit = dmg
			primary_name = target_unit.unit_name
			primary_per_hit = dmg
			primary_hit_percent = t_hit
			primary_crit_percent = t_crit
			primary_terrain_name = str(preview.get("terrain_name", "PLAIN"))
			primary_terrain_evade = int(preview.get("terrain_evade_bonus", 0))
			primary_terrain_def = int(preview.get("terrain_def_bonus", 0))
			primary_terrain_res = int(preview.get("terrain_res_bonus", 0))
		if is_primary_cell:
			# 主目标覆盖首项展示（命中/暴击/per_hit 以主目标为准）。
			primary_name = target_unit.unit_name
			primary_per_hit = dmg
			primary_hit_percent = t_hit
			primary_crit_percent = t_crit
			primary_terrain_name = str(preview.get("terrain_name", "PLAIN"))
			primary_terrain_evade = int(preview.get("terrain_evade_bonus", 0))
			primary_terrain_def = int(preview.get("terrain_def_bonus", 0))
			primary_terrain_res = int(preview.get("terrain_res_bonus", 0))
			primary_target_unit = target_unit

	if primary_per_hit == 0 and not has_first:
		primary_per_hit = first_per_hit

	return {
		"visible": true,
		"target_name": primary_name,
		"hit_percent": primary_hit_percent,
		"crit_percent": primary_crit_percent,
		"damage": total_damage,
		"hit_count": hit_count,
		"per_hit_damage": primary_per_hit,
		"total_damage": total_damage,
		"damage_type": str(base_payload.get("damage_type", "physical")),
		"is_heal": false,
		"terrain_name": primary_terrain_name,
		"terrain_evade_bonus": primary_terrain_evade,
		"terrain_def_bonus": primary_terrain_def,
		"terrain_res_bonus": primary_terrain_res,
		# 新增：头顶数字 + FE 浮窗所需字段
		"targets": targets_list,
		"target_hp": primary_target_unit.stats.hp if primary_target_unit != null else 0,
		"target_hp_max": primary_target_unit.stats.max_hp if primary_target_unit != null else 1,
	}

# ── Action execution ─────────────────────────────────

func _execute_move(unit: Unit, target: Vector2i) -> void:
	var move_check: Dictionary = GameAction.can_use_normal_move(unit)
	if not bool(move_check.get("ok", false)):
		print("[Action] Move blocked: %s" % str(move_check.get("reason", "")))
		return
	_pre_move_position = unit.grid_position
	_move_committed = false
	input_state = InputState.ANIMATING
	var from: Vector2i = unit.grid_position
	GameAction.consume_normal_move(unit)
	unit.refresh_status_icons()
	_path_preview = []
	_clear_highlights()
	_move_range = {}
	_emit_dashboard_state_changed()
	await unit.move_to(target, grid)
	if not battle_active or not is_instance_valid(unit) or turn_manager.current_unit != unit:
		return
	grid.move_unit(unit, from, target)
	selected_unit = current_unit
	_complete_move_phase(true)


func _execute_attack_from_input(action: GameAction) -> void:
	if input_state == InputState.ANIMATING:
		return
	var previous_state: InputState = input_state
	input_state = InputState.ANIMATING
	_clear_highlights()
	_clear_targeting_buffers()
	_combat_forecast = {}
	var executed: bool = await _execute_presented_attack(action)
	if is_instance_valid(current_unit) and current_unit.stats.is_alive() \
			and turn_manager.current_unit == current_unit:
		if executed:
			_restore_action_phase_state()
		else:
			input_state = previous_state
			_refresh_attack_cells()
			_recalculate_hover_artifacts()
			_show_attack_highlights()


func _execute_skill_from_input(action: GameAction) -> void:
	if input_state == InputState.ANIMATING:
		return
	var previous_state: InputState = input_state
	input_state = InputState.ANIMATING
	_clear_highlights()
	_clear_targeting_buffers()
	_combat_forecast = {}
	var executed: bool = await _execute_presented_skill(action)
	if is_instance_valid(current_unit) and current_unit.stats.is_alive() \
			and turn_manager.current_unit == current_unit:
		if executed:
			_handle_post_skill_execution(previous_state, action)
		else:
			input_state = previous_state
			_refresh_attack_cells()
			_recalculate_hover_artifacts()
			_show_attack_highlights()


## Wait only at the presentation boundary. The rules resolver below stays synchronous.
func _execute_presented_attack(action: GameAction) -> bool:
	var actor: Unit = action.actor
	var target: Unit = action.target_unit
	if not battle_active or not is_instance_valid(actor) or not is_instance_valid(target):
		return false
	if not bool(GameAction.can_use_normal_attack(actor).get("ok", false)):
		return false
	var delay: float = actor.begin_attack_visual(target.grid_position)
	if delay > 0.0:
		await _start_enemy_pacing(delay)
	if not battle_active or not is_instance_valid(actor) or not is_instance_valid(target):
		return false
	if turn_manager.current_unit != actor:
		return false
	var executed: bool = _execute_attack_action(action)
	if delay > 0.0 and battle_active:
		await _start_enemy_pacing(maxf(0.0, 1.0 - delay))
	return executed


func _execute_presented_skill(action: GameAction) -> bool:
	var actor: Unit = action.actor
	if not battle_active or not is_instance_valid(actor):
		return false
	var skill: Dictionary = _get_skill_data(str(action.data.get("skill_id", "")))
	var delay: float = 0.0
	if not _is_support_skill(skill) and actor.has_character_animation() \
			and bool(GameAction.validate_skill_usage(actor, skill).get("ok", false)):
		var target: Vector2i = action.target_pos
		# Cell/area casts face the selected cell, not each subsequently hit occupant.
		if _skill_target_mode(skill) == TARGET_MODE_UNIT and is_instance_valid(action.target_unit):
			target = action.target_unit.grid_position
		delay = actor.begin_attack_visual(target)
		await _start_enemy_pacing(delay)
	if not battle_active or not is_instance_valid(actor) or turn_manager.current_unit != actor:
		return false
	var executed: bool = _execute_skill_action(action)
	if delay > 0.0 and battle_active:
		await _start_enemy_pacing(maxf(0.0, 1.0 - delay))
	return executed


func _execute_attack_action(action: GameAction) -> bool:
	var attacker: Unit = action.actor
	var defender: Unit = action.target_unit
	if not _can_execute_hostile_action(attacker, defender):
		return false
	var attack_check: Dictionary = GameAction.can_use_normal_attack(attacker)
	if not bool(attack_check.get("ok", false)):
		print("[Action] Attack blocked: %s" % str(attack_check.get("reason", "")))
		return false

	GameAction.consume_normal_attack(attacker)
	_move_committed = true
	attacker.refresh_status_icons()
	_execute_hostile_action(attacker, defender, action.data)
	_run_pending_reactions()
	_emit_dashboard_state_changed()
	return true


func _execute_skill_action(action: GameAction) -> bool:
	var user: Unit = action.actor
	var data: Dictionary = action.data
	if user == null:
		return false
	var skill_id: String = str(data.get("skill_id", ""))
	if skill_id == "":
		return false

	var skill_data: Dictionary = _get_skill_data(skill_id)
	if skill_data.is_empty():
		return false
	var validation: Dictionary = GameAction.validate_skill_usage(user, skill_data)
	if not bool(validation.get("ok", false)):
		print("[Skill] %s blocked: %s" % [skill_id, str(validation.get("reason", ""))])
		return false

	var target_pos: Vector2i = action.target_pos
	if not grid.is_valid(target_pos):
		return false
	var area_direction: Vector2i = _deserialize_vector2i(
		data.get("target_direction", {}))
	var area_cells: Array[Vector2i] = _extract_cells_from_payload(
		data.get("affected_cells", []))
	if area_cells.is_empty():
		area_direction = _get_skill_area_direction(
			user.grid_position, target_pos)
		area_cells = _compute_skill_area_cells(
			user, skill_data, target_pos, area_direction)
	var target_units: Array[Unit] = _get_units_in_skill_area(
		user, skill_data, area_cells)
	if not _is_ground_target_skill(skill_data) and target_units.is_empty():
		return false
	# 「范围内至少有一名敌人才能使用」（拔刀、裂空、回天、霸天）：只数敌人，在扣消耗前拦截。
	var enemies_in_area: Array[Unit] = _get_enemies_in_cells(user, area_cells)
	if bool(skill_data.get("requires_enemy_in_area", false)) and enemies_in_area.is_empty():
		return false
	if str(skill_data.get("target_order", "")) == "near_to_far":
		_sort_units_near_to_far(user.grid_position, target_units)

	# 位移技能落点二次校验（双保险）：消耗资源前拦截无效落点 → 零消耗。
	if bool(skill_data.get("displacement", false)) \
			and not _is_displacement_landing_valid(user, target_pos):
		return false
	# 先选敌人再选落点（〔踏影〕）：落点必须是该敌人上下左右相邻、能站立且没被别人占的格，
	# 否则在扣消耗前拒绝。「目标在本轮尚未行动」在发动时判定（结算中目标倒下也不影响）。
	var landing_cell: Vector2i = LANDING_ANCHOR_NONE
	var target_pending_turn: bool = false
	if _skill_landing_mode(skill_data) == LANDING_MODE_ADJACENT:
		if not data.has("landing_cell") or target_units.is_empty():
			return false
		landing_cell = _deserialize_vector2i(data.get("landing_cell"))
		if landing_cell not in _get_adjacent_landing_cells(user, target_pos):
			return false
		target_pending_turn = turn_manager != null \
			and turn_manager.has_pending_turn(target_units[0])

	var action_cost: String = str(skill_data.get("action_cost", "standard"))
	var swift_limit: int = int(skill_data.get("swift_limit", 1))
	GameAction.consume_action_cost(user, action_cost, swift_limit)
	if action_cost in ["move", "standard", "swift"]:
		_move_committed = true

	# ── 剑圣资源消耗 ────────────────────────────────────
	# 剑气在施放时扣（心眼暴击的剑气时序不在本次修复范围内）。
	var qi_cost: int = int(skill_data.get("qi_cost", 0))
	if qi_cost > 0:
		user.spend_sword_qi(qi_cost, "skill_cost:" + skill_id)
	# 修复 P0-②：印记消耗推迟到伤害结算之后再执行（见下方 _spend_skill_marks）。
	# 否则拔刀在 spend_marks 之后才结算伤害，吃不到自己正在消耗的势(STR+2)印记加成
	# （实测非暴击对 DEF2 木桩 = 25 而非应有的 29，对 30 血脆敌非暴击打不死）。
	var mark_cost: int = int(skill_data.get("mark_cost", 0))

	var cooldown_turns: int = int(data.get("cooldown", 0))
	user.consume_skill(skill_id, cooldown_turns)
	user.refresh_status_icons()
	_action_dealt_damage = false
	# 直接位移到落点再出手（踏影 effect「直接位移至该格，并对目标造成物理伤害」）：
	# 不检查沿途、不视为移动，所以不走寻路与移动事件。
	if landing_cell != LANDING_ANCHOR_NONE:
		_apply_skill_displacement(user, landing_cell)
	var skill_name: String = str(data.get("skill_name", skill_id))
	# ★ 这里刻意**不早退**（2026-08-11 修）。原本辅助类技能（`power <= 0`）在这里
	# 直接 `return true`，于是下面的位移块**永远走不到**——`displacement: true` 且
	# `power <= 0` 的技能施放后单位站着不动，而且一声不吭。瞬身（无伤害的瞬移）
	# 正好是这个组合。改成 if / else 让两条路径汇到同一个收尾，扣印记与位移的
	# 逻辑也因此各只剩一份，不会再出现「改了一处漏了另一处」。
	#
	# ⚠ **位移必须留在伤害结算之后**，不能为了让辅助技能走到就把整块提前：
	# 一闪的途经伤害靠 `_get_displacement_path_cells(user.grid_position, target_pos)`
	# 算路径，先位移会让起点变成落点，路径整个算错。
	if _is_support_skill(skill_data):
		print("[Skill] %s uses %s (%d target(s))" % [
			user.unit_name,
			skill_name,
			target_units.size(),
		])
		_apply_support_skill(user, skill_data, target_units)
	else:
		var hostile_payload: Dictionary = data.duplicate(true)
		if target_units.is_empty():
			print("[Skill] %s uses %s on empty area %s" % [
				user.unit_name,
				skill_name,
				target_pos,
			])
		else:
			var splash_pct: int = int(skill_data.get("splash_damage_pct", 100))
			for target_unit: Unit in target_units:
				if not _can_execute_hostile_action(user, target_unit):
					continue
				print("[Skill] %s uses %s on %s" % [
					user.unit_name,
					skill_name,
					target_unit.unit_name,
				])
				# 主目标（落点格单位）吃满；其余溅射目标按 splash_damage_pct 衰减（JSON 驱动）。
				var per_target_payload: Dictionary = hostile_payload.duplicate(true)
				if target_unit.grid_position == target_pos:
					per_target_payload["area_damage_multiplier"] = 1.0
				else:
					per_target_payload["area_damage_multiplier"] = float(splash_pct) / 100.0
				_execute_hostile_action(user, target_unit, per_target_payload)

	# 伤害结算完成后才扣印记（修复 P0-②：使拔刀吃到自身消耗的势加成）。
	_spend_skill_marks(user, mark_cost)
	# 护盾（回天）：最大生命 × pct% × 发动时范围内的敌人数，向上取整 [推断：原文没写取整]，
	# 与现有护盾相加（R1.17）。
	var shield_gain: Variant = skill_data.get("shield_gain", null)
	if shield_gain is Dictionary:
		var shield_amount: int = ceili(float(user.stats.max_hp)
			* float((shield_gain as Dictionary).get("max_hp_pct_per_enemy", 0.0)) / 100.0
			* float(enemies_in_area.size()))
		if shield_amount > 0:
			user.gain_shield(shield_amount)
			print("[Shield] %s +%d shield from %s → %d" % [
				user.unit_name, shield_amount, skill_id, user.shield])
	# 「持有 N 层某状态时，消耗 N 层，结算后恢复 1 次标准动作」（空想剑）：不以命中为条件；
	# 恢复的标准动作以本回合已经消耗的为限（R3.2：标准行动点不超过容量）。
	var restore: Variant = skill_data.get("restore_standard_on_stacks", null)
	if restore is Dictionary:
		var restore_state: String = str((restore as Dictionary).get("state_id", ""))
		var restore_need: int = int((restore as Dictionary).get("stacks", 0))
		if restore_need > 0 and user.held_states.stacks(restore_state) >= restore_need:
			user.held_states.consume_stacks(restore_state, restore_need)
			if user.standard_used:
				user.restore_standard_resource()
			user.refresh_status_icons()
	# 「目标在本轮尚未行动时获得 N 点剑气」（设计库 kensei_huizhan）：不以命中为条件。
	var qi_not_acted: int = int(skill_data.get("qi_gain_if_target_not_acted", 0))
	if target_pending_turn and qi_not_acted > 0:
		user.gain_sword_qi(qi_not_acted, "target_not_acted:" + skill_id)
	# 「全部目标结算完毕后，再获得 N 点剑气」（设计库 kensei_liekong）：不以命中为条件。
	var qi_after_resolve: int = int(skill_data.get("qi_gain_after_resolve", 0))
	if qi_after_resolve > 0:
		user.gain_sword_qi(qi_after_resolve, "after_resolve:" + skill_id)
	# 「结算后随机获得一枚印记」（设计库 kensei_juhe）：不以命中或伤害为条件。
	for _i: int in range(int(skill_data.get("mark_gain_after_resolve", 0))):
		var resolved_mark: String = user.gain_random_mark()
		if resolved_mark != "":
			print("[SwordMark] %s gained mark 「%s」 after %s, total=%d" % [
				user.unit_name, resolved_mark, skill_id, user.get_mark_count()])
	# ── 位移技能（如一闪）：施放后落在所选目标格 ──
	if bool(skill_data.get("displacement", false)):
		_apply_skill_displacement(user, target_pos)
	# 满月：发动时持有纳刀（已在构建动作时锁定），全部直接伤害完成后移除纳刀。
	if bool(data.get("held_state_form_active", false)):
		var form: Dictionary = skill_data.get("held_state_form", {})
		if bool(form.get("remove_state_after_use", false)):
			user.held_states.remove(str(form.get("state_id", "")))
			user.refresh_status_icons()
	_apply_held_skill_triggers(user, skill_id)
	_consume_on_skill_damage_states(user, skill_id)
	_run_pending_reactions()
	_emit_dashboard_state_changed()
	return true


## 〔若离〕：自身造成技能伤害时消耗 1 层、获得剑气；每次使用技能最多消耗 1 层，不造成伤害的不消耗。
## 数值在状态定义的 engine_on_skill_damage 里。结算时点放在整个技能结算完之后（原文「造成技能伤害时」）：
## 现有技能没有在结算途中读剑气的条件，结果相同；以后出现这类条件时要改成在伤害段里结算。
func _consume_on_skill_damage_states(user: Unit, skill_id: String) -> void:
	if not _action_dealt_damage or user == null or not user.stats.is_alive():
		return
	for state_id: String in user.held_states.held_ids():
		var spec: Variant = (DataLoader.held_states.get(state_id, {}) as Dictionary).get(
			"engine_on_skill_damage", null)
		if not spec is Dictionary:
			continue
		if user.held_states.consume_stacks(state_id, int((spec as Dictionary).get("consume", 1))) <= 0:
			continue
		var qi: int = int((spec as Dictionary).get("qi_gain", 0))
		if qi > 0:
			user.gain_sword_qi(qi, "%s:%s" % [state_id, skill_id])
		user.refresh_status_icons()


## 攻击动作结束后的反应：〔见切〕——对自身进行过命中判定的敌方攻击动作结束后，若自身存活、
## 攻击者与自身上下左右相邻、剑气足够，消耗 1 层见切和剑气，对攻击者反击一次。
## 每个敌方攻击动作最多一次（同一动作里的多段、多个目标只登记一次）；反击不再引发反击。
func _run_pending_reactions() -> void:
	var pending: Array[Dictionary] = _pending_reactions.duplicate()
	_pending_reactions.clear()
	for item: Dictionary in pending:
		var attacker: Unit = item.get("attacker", null)
		var defender: Unit = item.get("defender", null)
		if attacker == null or defender == null:
			continue
		if not is_instance_valid(attacker) or not is_instance_valid(defender):
			continue
		_try_counter(defender, attacker)


func _try_counter(defender: Unit, attacker: Unit) -> void:
	if not defender.stats.is_alive() or not attacker.stats.is_alive():
		return
	for state_id: String in defender.held_states.held_ids():
		var spec_value: Variant = (DataLoader.held_states.get(state_id, {}) as Dictionary).get(
			"engine_counter", null)
		if not spec_value is Dictionary:
			continue
		var spec: Dictionary = spec_value
		if _manhattan(defender.grid_position, attacker.grid_position) != 1:
			return
		var qi_cost: int = int(spec.get("qi_cost", 0))
		if defender.sword_qi < qi_cost:
			return
		if defender.held_states.consume_stacks(state_id, 1) <= 0:
			return
		if qi_cost > 0:
			defender.spend_sword_qi(qi_cost, "counter:" + state_id)
		defender.refresh_status_icons()
		print("[Counter] %s 反击 %s（%s）" % [defender.unit_name, attacker.unit_name, state_id])
		_execute_hostile_action(defender, attacker, {
			"skill_id": "counter:" + state_id,
			"skill_name": "反击",
			"is_counter": true,
			"damage_type": _normalize_damage_type(spec.get("damage_type", "physical")),
			"skill_power": float(spec.get("power", 0)),
			"skill_multiplier": float(spec.get("coefficient", 1.0)),
			"attack_type": "melee",
			"qi_gain_on_hit": 0,
			"effects": [],
		})
		return


## 「持有即生效」的触发：单位技能栏里的技能可以声明 held_triggers，在单位使用某个身份的技能后
## 生效（R2.5：身份按基础技能算，所以写「招架」的也作用于见切、浮生若梦）。
## 目前只有满月：使用招架或其回忆技能时，若没有纳刀，获得纳刀和一枚当前未持有的印记；
## 已持有纳刀时不重复获得（「只有从没有纳刀变为持有纳刀时，才获得印记」）。
func _apply_held_skill_triggers(user: Unit, used_skill_id: String) -> void:
	if user == null or not user.stats.is_alive():
		return
	var identity: String = user.get_skill_identity(used_skill_id)
	for owned_id: String in user.skill_ids:
		var triggers: Variant = _get_skill_data(owned_id).get("held_triggers", [])
		if not triggers is Array:
			continue
		for trigger_value: Variant in (triggers as Array):
			if not trigger_value is Dictionary:
				continue
			var trigger: Dictionary = trigger_value
			if str(trigger.get("on_use_identity", "")) != identity:
				continue
			var state_id: String = str(trigger.get("gain_held_state", ""))
			if state_id == "" or user.held_states.has(state_id):
				continue
			user.apply_held_state(state_id, 1, {"kind": "permanent"})
			for _i: int in range(int(trigger.get("gain_random_marks", 0))):
				user.gain_random_mark()
			user.refresh_status_icons()
			print("[HeldTrigger] %s 使用 %s → %s 给予 %s，印记=%d" % [
				user.unit_name, used_skill_id, owned_id, state_id, user.get_mark_count()])


## 目标按与使用者的曼哈顿距离由近到远排序（裂空 rules：逐个结算，近的先结算）。
## 距离按单位的锚点格算；引擎目前只有单格单位，多格单位的口径（取最近占据格）未承载（Q7）。
func _sort_units_near_to_far(origin: Vector2i, target_units: Array[Unit]) -> void:
	target_units.sort_custom(func(a: Unit, b: Unit) -> bool:
		return _manhattan(origin, a.grid_position) < _manhattan(origin, b.grid_position))


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## 在伤害结算之后扣减技能的印记消耗（修复 P0-②；mark_cost<=0 时空操作）。
func _spend_skill_marks(user: Unit, mark_cost: int) -> void:
	if user == null or mark_cost <= 0:
		return
	user.spend_marks(mark_cost)
	user.refresh_status_icons()


## 位移技能落点：把 user 移动到 landing 格（落在所选目标格规则）。
## 目标格越界 / 不可通行 / 已被占用 → 不位移（安全跳过）。
func _apply_skill_displacement(user: Unit, landing: Vector2i) -> void:
	if user == null or not grid.is_valid(landing):
		return
	if landing == user.grid_position:
		return
	var cell: Cell = grid.get_cell(landing)
	if cell == null or not cell.is_passable() or cell.occupant != null:
		return
	var from: Vector2i = user.grid_position
	grid.move_unit(user, from, landing)
	user.position = grid.grid_to_world(landing)
	print("[Skill] %s 位移 %s → %s" % [user.unit_name, from, landing])


func _can_execute_hostile_action(attacker: Unit, defender: Unit) -> bool:
	if not attacker or not defender:
		return false
	if not attacker.stats.is_alive() or not defender.stats.is_alive():
		return false
	return true


func _execute_hostile_action(attacker: Unit, defender: Unit,
		data: Dictionary) -> void:
	attacker.show_attack_contact(defender.grid_position)
	var action_data: Dictionary = _build_hostile_action_context(attacker, defender, data)

	# ── 天赋：动作级事件「执行攻击动作时」（Wave 2）────────────────
	# 这里比「命中时」还早——在命中判定之前，与 A2 要开的真 on-hit 钩子不是同一处。
	# 该事件的效果不在此刻结算，只登记待办（见 _apply_talent_effect 的
	# offhand_followup 分支）：条件在动作开始时判定，伤害在主手那一下之后追加。
	var action_ctx: Dictionary = {
		"defender": defender, "pending_offhand": [],
		"contexts": [CONTEXT_ACTIVE_ATTACK],
	}
	_dispatch_talents(attacker, "执行攻击动作时", action_ctx)

	defender.handle_attacked()

	# 多段攻击（伤害条目 segments > 1，例如〔连斩〕）：每段独立判定命中、暴击与伤害，
	# 各自分发命中与造成伤害事件（R1.10）；任一段未命中或目标倒下即停（R1.11），
	# 已结算的段照常保留。动作级事件（上面的「执行攻击动作时」）与副手追加整次只结算一次。
	# 单段攻击不复制 action_data，与改动前完全相同。
	var segments: int = maxi(1, int(action_data.get("segments", 1)))
	var segment_data: Dictionary = action_data
	# 「暴击时」等事件写进 action_ctx 的增伤只属于那一段，下一段从动作开始时的值重新算。
	var action_more_damage: float = float(action_ctx.get("more_damage_multiplier", 1.0))
	for segment_index: int in range(segments):
		if segments > 1:
			segment_data = _build_segment_action_data(action_data, segment_index)
			action_ctx["more_damage_multiplier"] = action_more_damage
		var segment_result: DamageCalculator.AttackResult = _resolve_hostile_segment(
			attacker, defender, segment_data, data, action_ctx, segment_index)
		if not segment_result.hit or not defender.stats.is_alive():
			break

	_note_reaction(attacker, defender, data)

	# 主手全部副作用结算后，再按队列执行副手追加。
	# 递归追加进入同一队列，并受每次攻击动作的总次数护栏限制。
	# 反击是〔见切〕产生的追加攻击，原文没有允许它再产生追加攻击（R1.15），所以不执行副手追加；
	# 命中、暴击、造成伤害等事件照常分发（追加攻击正常产生自己的事件）。
	var queue: Array = [] if bool(data.get("is_counter", false)) \
		else (action_ctx["pending_offhand"] as Array).duplicate()
	var executed: int = 0
	while not queue.is_empty():
		if executed >= MAX_OFFHAND_FOLLOWUPS_PER_ACTION:
			push_warning("[Offhand] %s 一次攻击动作内的副手追加已达上限 %d 次，剩余 %d 次丢弃——检查递归追加的概率与衰减参数"
				% [attacker.unit_name, MAX_OFFHAND_FOLLOWUPS_PER_ACTION, queue.size()])
			break
		var followup: Variant = queue.pop_front()
		if not followup is Dictionary:
			continue
		executed += 1
		for spawned: Variant in _execute_offhand_followup(
				attacker, defender, segment_data, followup, action_ctx):
			queue.append(spawned)

	# 自动反击已整体移除（2026-07-11 用户裁决）：未来以天赋/敌方特性形式回归，
	# 伤害与特效将与天赋/特性深度绑定，不预设反击框架。


func _note_reaction(attacker: Unit, defender: Unit, data: Dictionary) -> void:
	if bool(data.get("is_counter", false)) or attacker.faction == defender.faction:
		return
	for item: Dictionary in _pending_reactions:
		if item.get("attacker") == attacker and item.get("defender") == defender:
			return
	_pending_reactions.append({"attacker": attacker, "defender": defender})


## 多段攻击第 segment_index 段（从 0 起）的动作数据。第 n 段（n 从 1 起）命中减 decay×(n−1)，
## 在未截断命中上扣除后再按通用上下限处理（连斩 rules）；其他效果给的必定命中只作用于第一段，
## 伤害条目自己声明的「必定命中」（entry_guaranteed_hit）每段都保留；
## 「第一段命中并造成伤害后」的印记（mark_gain_after_damage）只在第一段结算。
func _build_segment_action_data(action_data: Dictionary, segment_index: int) -> Dictionary:
	var segment_data: Dictionary = action_data.duplicate(true)
	if segment_index <= 0:
		return segment_data
	segment_data["segment_hit_penalty"] = \
		int(action_data.get("segment_hit_decay", 0)) * segment_index
	segment_data["guaranteed_hit"] = bool(action_data.get("entry_guaranteed_hit", false))
	segment_data["mark_gain_after_damage"] = 0
	# 调试确定性开关仍对每段生效（headless 用例需要逐段可控）。
	_apply_debug_determinism(segment_data)
	return segment_data


## 〔若即〕：原本会命中的可回避攻击改为回避，消耗 1 层并获得状态定义 engine_evade_conversion 写的状态。
## 自然未命中不消耗；必中攻击不受影响。「可回避」按引擎的命中判定口径：掷了命中（R1.2）的攻击都算，
## 范围攻击也一样 [推断，待用户确认：〔影〕rules 把「法术、范围、必中、Boss 重击」列为不可回避，
## 那条是〔影〕吸引攻击的口径，引擎里范围攻击照常可以被闪开]。每个伤害段分别判定。
## 调试「强制命中」开关会把所有攻击变成必中，此时若即不会触发。
func _apply_evade_conversion(defender: Unit, outcome: Dictionary, action_data: Dictionary) -> void:
	if not bool(outcome.get("hit", false)):
		return
	if bool(action_data.get("guaranteed_hit", false)):
		return
	for state_id: String in defender.held_states.held_ids():
		var spec: Variant = (DataLoader.held_states.get(state_id, {}) as Dictionary).get(
			"engine_evade_conversion", null)
		if not spec is Dictionary:
			continue
		if defender.held_states.consume_stacks(state_id, 1) <= 0:
			continue
		outcome["hit"] = false
		outcome["crit"] = false
		_grant_conversion_state(defender, spec as Dictionary)
		print("[Evade] %s 的 %s 把命中改为回避" % [defender.unit_name, state_id])
		return


func _grant_conversion_state(unit: Unit, spec: Dictionary) -> void:
	var gain_state: String = str(spec.get("gain_state", ""))
	if gain_state == "":
		return
	var duration: Variant = spec.get("gain_duration", {})
	unit.apply_held_state(gain_state, maxi(1, int(spec.get("gain_stacks", 1))),
		duration if duration is Dictionary else {})
	unit.refresh_status_icons()


## 一个直接伤害段的完整结算：掷命中与暴击 → 命中、暴击事件 → 防御侧反应 → 伤害 →
## 状态、资源、词条与 after-damage 事件。返回本段结果，调用方据此决定是否继续下一段。
func _resolve_hostile_segment(attacker: Unit, defender: Unit, action_data: Dictionary,
		data: Dictionary, action_ctx: Dictionary,
		segment_index: int) -> DamageCalculator.AttackResult:
	var damage_type: String = str(action_data.get("damage_type", "physical"))

	# 命中与暴击事件在伤害数值结算前分发，可修改本次伤害参数，
	# 但不得回溯改写已经掷出的 hit / crit。剑气回荡只强化随后的一次副手攻击。
	var outcome: Dictionary = DamageCalculator.roll_outcome(
		attacker, defender, action_data)
	_apply_evade_conversion(defender, outcome, action_data)
	action_ctx["source"] = SOURCE_MAIN_HAND
	_dispatch_on_hit_events(attacker, outcome, action_ctx)
	_merge_on_hit_modifiers(action_data, action_ctx)

	# 防御侧反应在伤害结算前写入减伤乘项，与攻击侧增伤共同进入 final_multiplier。
	var defense: Dictionary = _resolve_defense(
		attacker, defender, outcome, SOURCE_MAIN_HAND)
	_apply_defense_to_action(action_data, defense)

	action_data["precomputed_outcome"] = outcome

	# Main attack: calculate → popup → apply
	var result: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(
		attacker, defender, action_data)
	_record_parry_prevented(attacker, defender, action_data, result, defense)
	_log_attack(attacker, defender, result, "")
	var combat_text_anchor := defender.get_combat_text_anchor_world(-50.0)
	if result.hit:
		DamagePopup.spawn_at_anchor(popup_layer, combat_text_anchor,
			result.damage, damage_type, result.crit, segment_index)
		defender.take_damage(result.damage, damage_type)
		if result.damage > 0 and not bool(action_data.get("is_counter", false)):
			_action_dealt_damage = true
	else:
		DamagePopup.spawn_miss_at_anchor(popup_layer, combat_text_anchor, segment_index)

	if result.hit and defender.stats.is_alive():
		_apply_hostile_skill_effects(attacker, defender, data)

	# ── 剑圣资源：命中得气、击杀得气+减CD+得印记 ──────────
	_apply_sword_qi_on_hit(attacker, result, action_data)

	# ── 敌人词条：命中 / 击杀时机分发（纯加法，无词条 get_affixes() 空即 return）──
	if result.hit:
		_apply_affixes(attacker, "on_hit", {"defender": defender, "result": result})
	if result.defender_died:
		_apply_affixes(attacker, "on_kill", {"defender": defender, "result": result})

	# ── 天赋：after-damage 族三事件分发（Wave 1 · A1，零新钩子）──────────
	# 与上面的词条分发同一时点——都在 defender.take_damage() 之后，故三者都是
	# after-damage 语义（R1.4）。纯加法：单位无 talent_ids 时立即 return。
	# 三事件的判据差别（照设计库 trigger_event 定义）：
	#   命中后     = 该次命中的伤害结算完成后，按命中计一次，**实际伤害为 0 也触发**
	#   造成伤害时 = 实际造成了伤害（damage > 0）才触发
	#   击杀时     = 该次攻击导致目标死亡
	var talent_ctx: Dictionary = {
		"defender": defender, "result": result,
		"source": SOURCE_MAIN_HAND, "contexts": [CONTEXT_ACTIVE_ATTACK],
		# 主手的 after-damage 事件也要能登记副手追加：它们排在下面那个队列**之前**，
		# 登记进同一个数组就会被队列接手。少了这个键，挂在「命中后」的追加类效果
		# 会走进 _apply_talent_effect 的告警分支、白白丢掉。
		"pending_offhand": action_ctx["pending_offhand"],
		"action_ctx": action_ctx,
	}
	if result.hit:
		_dispatch_talents(attacker, "命中后", talent_ctx)
		if result.damage > 0:
			_dispatch_talents(attacker, "造成伤害时", talent_ctx)
	if result.defender_died:
		_dispatch_talents(attacker, "击杀时", talent_ctx)
	return result


func _is_waiting_for_line_direction() -> bool:
	if input_state != InputState.SKILL_TARGETING or _selected_skill_id == "":
		return false
	var skill_data: Dictionary = _get_skill_data(_selected_skill_id)
	var range_data: Dictionary = skill_data.get("range", {})
	return str(range_data.get("type", "")) == "line" \
		and _targeting_direction == Vector2i.ZERO


func _can_confirm_skill_target(grid_pos: Vector2i) -> bool:
	if current_unit == null or _selected_skill_id == "":
		return false
	if grid_pos not in _attack_cells:
		return false
	var skill_data: Dictionary = _get_skill_data(_selected_skill_id)
	# 位移技能（如一闪）：落点必须可落，否则不允许释放（点击无反应、不扣资源）。
	if bool(skill_data.get("displacement", false)):
		return _is_displacement_landing_valid(current_unit, grid_pos)
	if _is_ground_target_skill(skill_data):
		return true
	var target_unit: Unit = grid.get_unit_at(grid_pos)
	return _matches_target_relation(
		current_unit, target_unit, _get_skill_target_relation(skill_data))


func _get_units_in_skill_area(user: Unit, skill_data: Dictionary,
		area_cells: Array[Vector2i]) -> Array[Unit]:
	var relation: String = _get_area_effect_relation(skill_data)
	var units_by_id: Dictionary = {}
	for cell_pos: Vector2i in area_cells:
		var target_unit: Unit = grid.get_unit_at(cell_pos)
		if _matches_target_relation(user, target_unit, relation):
			units_by_id[target_unit.get_instance_id()] = target_unit
	var units_in_area: Array[Unit] = []
	for unit_value: Variant in units_by_id.values():
		if unit_value is Unit:
			units_in_area.append(unit_value)
	return units_in_area


## 这个技能要瞄准谁：自己 / 友军 / 敌军。
##
## 「自己」这一档从 `target_mode` 读（2026-08-12），不再由 `range.type=="self" and
## area.type=="single"` 反推——理由见 `_is_ground_target_skill` 的说明，两处是同一个病。
## 友军 / 敌军仍按 `_is_support_skill` 分（那是**效果**的性质，不是选择模型的事）。
## 范围内哪些单位受影响。以自身为目标的伤害技能（剑圣〔拔刀〕：自身中心菱形 1 格）选的是
## 自己、打的是周围的敌人；其余技能与选目标的关系相同。只影响范围结算，不改选目标的逻辑。
func _get_area_effect_relation(skill_data: Dictionary) -> String:
	if _skill_target_mode(skill_data) == TARGET_MODE_SELF and not _is_support_skill(skill_data):
		return "enemy"
	return _get_skill_target_relation(skill_data)


func _get_skill_target_relation(skill_data: Dictionary) -> String:
	if _skill_target_mode(skill_data) == TARGET_MODE_SELF:
		return "self"
	if _is_support_skill(skill_data):
		return "ally"
	return "enemy"


func _matches_target_relation(user: Unit, target_unit: Unit,
		relation: String) -> bool:
	if user == null or target_unit == null or not target_unit.stats.is_alive():
		return false
	match relation:
		"self":
			return target_unit == user
		"ally":
			return target_unit.faction == user.faction
		"enemy":
			return target_unit.faction != user.faction
		_:
			return false


func _is_support_skill(skill_data: Dictionary) -> bool:
	# 设计库伤害条目技能不写 power，有条目即为伤害技能。
	if not _select_damage_entry(skill_data).is_empty():
		return false
	return int(skill_data.get("power", 0)) <= 0


## 释放这个技能时，玩家能不能点一个**没有单位**的格子。
##
## ── 2026-08-12：从「反推 area」改成「读 target_mode」──────────────
##
## 旧实现是 `range.type != "self" and area.type != "single"`。**那是拿伤害波及的形状
## 去猜选择模型**，设计库 `app/models.py::TargetMode` 立字段时就把它判定失效了，逐字：
##
##   「引擎原先从 area 形状反推是否选地面（`_is_ground_target_skill`：area.type !=
##     "single" 即算选地面），于是斩击/居合被判为选单位、**拔刀被判为选地面**。而 R4.4
##     规定多格单位『其占据格逐格均为合法瞄准点』——斩击也要能选打哪一格，这个反推在
##     多格单位下直接失效。故把目标选择语义提升为独立字段。」
##
## 那之后设计库有了 `target_mode`，引擎侧却一直零承载，于是**拔刀在游戏里一直能点空地
## 释放**（它 `area=diamond/1` → 旧反推判它选地面），与设计库 `target_mode=单位` 矛盾。
## 本次把这一半接上：选择读 `target_mode`，`area` 只管伤害波及与派生分类，不再兼职。
##
## 映射：`格子` / `方向` → 可点空格；`单位` / `自身` → 必须点到符合关系的单位。
## 「方向」也归可点空格一侧——一闪要先点一个空格当落点，方向由 `_targeting_direction`
## 另行捕获（见 `_get_skill_area_direction`）。
func _is_ground_target_skill(skill_data: Dictionary) -> bool:
	return _skill_target_mode(skill_data) in [TARGET_MODE_CELL, TARGET_MODE_DIRECTION]


## 读技能的目标选择方式。缺字段时**响亮退回旧反推**——不静默：静默会让一个漏填
## `target_mode` 的新技能悄悄回到那个已判定失效的猜法上，而表现只是「这技能能点空地」，
## 与本次要修的 bug 一模一样，最难查。
func _skill_target_mode(skill_data: Dictionary) -> String:
	var mode: String = str(skill_data.get("target_mode", "")).strip_edges()
	if mode in SUPPORTED_TARGET_MODES:
		return mode
	if mode != "":
		push_warning("[Skill] %s 的 target_mode「%s」不在闭集 %s 内，退回旧的 area 反推"
			% [str(skill_data.get("id", "?")), mode, str(SUPPORTED_TARGET_MODES)])
	else:
		push_warning("[Skill] %s 缺 target_mode，退回旧的 area 反推（该反推已被设计库判定失效，请补字段）"
			% str(skill_data.get("id", "?")))
	return _legacy_target_mode_from_area(skill_data)


## 旧的 area 反推，**只在缺字段时兜底**，不是正常路径。保留它而不是直接报错，是为了让
## 一个漏填字段的技能仍能按老样子跑（退化而非崩掉），同时靠上面那条告警把问题喊出来。
func _legacy_target_mode_from_area(skill_data: Dictionary) -> String:
	var range_data: Dictionary = skill_data.get("range", {})
	var area_data: Dictionary = skill_data.get("area", {})
	if str(range_data.get("type", "")) == "self":
		return TARGET_MODE_SELF if str(area_data.get("type", "single")) == "single" \
			else TARGET_MODE_UNIT
	if str(area_data.get("type", "single")) != "single":
		return TARGET_MODE_CELL
	return TARGET_MODE_UNIT


func _apply_support_skill(user: Unit, skill_data: Dictionary,
		target_units: Array[Unit]) -> void:
	for target_unit: Unit in target_units:
		for effect_value: Variant in skill_data.get("effects", []):
			if not (effect_value is Dictionary):
				continue
			_apply_skill_effect_to_unit(
				user, target_unit, effect_value as Dictionary, false)


## 持有型状态效果的层数：stacks（缺省 1）；写了 stacks_from_qi 时 = base + 使用者剑气 ÷ qi_step（向下取整），
## 不超过 max（见切、若即：「层数为 1，使用时每有 30 点剑气再多 1 层，最大 3 层」）。
func _effect_stacks(user: Unit, effect_data: Dictionary) -> int:
	var spec: Variant = effect_data.get("stacks_from_qi", null)
	if not spec is Dictionary:
		return maxi(1, int(effect_data.get("stacks", 1)))
	var step: int = maxi(1, int((spec as Dictionary).get("qi_step", 1)))
	var stacks: int = int((spec as Dictionary).get("base", 1)) + int(user.sword_qi / step)
	return clampi(stacks, 1, maxi(1, int((spec as Dictionary).get("max", stacks))))


func _apply_hostile_skill_effects(user: Unit, target_unit: Unit,
		action_data: Dictionary) -> void:
	var effect_entries: Variant = action_data.get("effects", [])
	if not (effect_entries is Array):
		return
	for effect_value: Variant in effect_entries:
		if not (effect_value is Dictionary):
			continue
		_apply_skill_effect_to_unit(
			user, target_unit, effect_value as Dictionary, true)


func _apply_skill_effect_to_unit(user: Unit, target_unit: Unit,
		effect_data: Dictionary, is_hostile: bool) -> void:
	# 持有型状态（data/held_states）：持续时间与数值由技能写明（R3.4），原样传给 HeldStateSet。
	if effect_data.has("held_state_id"):
		if not _roll_effect_application(target_unit, effect_data, is_hostile):
			return
		var duration_value: Variant = effect_data.get("duration", {})
		var params_value: Variant = effect_data.get("params", {})
		target_unit.apply_held_state(str(effect_data["held_state_id"]),
			_effect_stacks(user, effect_data),
			duration_value if duration_value is Dictionary else {},
			params_value if params_value is Dictionary else {},
			user.unit_id)
		return
	var effect_type: String = str(
		effect_data.get("effect_id", effect_data.get("type", "")))
	var effect_value: int = int(effect_data.get("value", 0))
	match effect_type:
		"heal":
			if effect_value > 0:
				target_unit.heal(effect_value)
		"damage", "dot":
			if effect_value > 0:
				target_unit.take_damage(effect_value, "pure")
		_:
			# 〔剑痕〕：即将受到普通控制时，在抵抗判定前失去 1 层，并免疫本次效果。
			if is_hostile and _try_control_immunity(target_unit, effect_type):
				return
			if not _roll_effect_application(target_unit, effect_data, is_hostile):
				return
			# 〔若即〕：原本会成功施加的普通控制改为抵抗（先过正常抵抗，再消耗层数）。
			if is_hostile and _try_resist_control(target_unit, effect_type):
				return
			var buff: BuffEffect = _make_buff_effect_instance(user, effect_data)
			if buff != null:
				target_unit.add_buff(buff)


func _try_control_immunity(target_unit: Unit, buff_id: String) -> bool:
	if str((DataLoader.buffs.get(buff_id, {}) as Dictionary).get("effect_type", "")) != "control":
		return false
	for state_id: String in target_unit.held_states.held_ids():
		if not bool((DataLoader.held_states.get(state_id, {}) as Dictionary).get(
				"engine_control_immunity_per_stack", false)):
			continue
		if target_unit.held_states.consume_stacks(state_id, 1) <= 0:
			continue
		target_unit.refresh_status_icons()
		print("[Immune] %s 的 %s 免疫了 %s" % [target_unit.unit_name, state_id, buff_id])
		return true
	return false


func _try_resist_control(target_unit: Unit, buff_id: String) -> bool:
	if str((DataLoader.buffs.get(buff_id, {}) as Dictionary).get("effect_type", "")) != "control":
		return false
	for state_id: String in target_unit.held_states.held_ids():
		var spec: Variant = (DataLoader.held_states.get(state_id, {}) as Dictionary).get(
			"engine_evade_conversion", null)
		if not spec is Dictionary or not bool((spec as Dictionary).get("resists_control", false)):
			continue
		if target_unit.held_states.consume_stacks(state_id, 1) <= 0:
			continue
		_grant_conversion_state(target_unit, spec as Dictionary)
		print("[Resist] %s 的 %s 抵抗了 %s" % [target_unit.unit_name, state_id, buff_id])
		return true
	return false


func _roll_effect_application(target_unit: Unit, effect_data: Dictionary,
		is_hostile: bool) -> bool:
	var base_chance: float = float(effect_data.get("chance", 100))
	if base_chance <= 0.0:
		return false
	var actual_percent: float = base_chance
	if is_hostile:
		actual_percent *= target_unit.get_status_resist_multiplier()
	return randf() <= clampf(actual_percent / 100.0, 0.0, 1.0)


func _make_buff_effect_instance(user: Unit,
		effect_data: Dictionary) -> BuffEffect:
	var effect_id: String = str(
		effect_data.get("effect_id", effect_data.get("type", "")))
	var template_data: Dictionary = DataLoader.buffs.get(effect_id, {})
	if template_data.is_empty():
		return null
	var buff_payload: Dictionary = template_data.duplicate(true)
	if effect_data.has("duration"):
		var duration_value: int = int(effect_data.get("duration", buff_payload.get("duration", -1)))
		buff_payload["duration"] = duration_value
		buff_payload["max_duration"] = duration_value
	if effect_data.has("value"):
		buff_payload["value"] = float(effect_data.get("value", buff_payload.get("value", 0)))
	buff_payload["source_unit_id"] = user.unit_id
	return BuffEffect.from_dict(buff_payload)


func _get_skill_range_fill_color() -> Color:
	if _selected_skill_id == "":
		return HIGHLIGHT_ATTACK_RANGE_FILL
	var skill_data: Dictionary = _get_skill_data(_selected_skill_id)
	if _is_support_skill(skill_data):
		return HIGHLIGHT_SUPPORT_RANGE_FILL
	return HIGHLIGHT_ATTACK_RANGE_FILL


func _get_skill_range_border_color() -> Color:
	if _selected_skill_id == "":
		return HIGHLIGHT_ATTACK_RANGE_BORDER
	var skill_data: Dictionary = _get_skill_data(_selected_skill_id)
	if _is_support_skill(skill_data):
		return HIGHLIGHT_SUPPORT_RANGE_BORDER
	return HIGHLIGHT_ATTACK_RANGE_BORDER


func _get_skill_target_fill_color() -> Color:
	if _selected_skill_id == "":
		return HIGHLIGHT_ATTACK_TARGET_FILL
	var skill_data: Dictionary = _get_skill_data(_selected_skill_id)
	if _is_support_skill(skill_data):
		return HIGHLIGHT_SUPPORT_TARGET_FILL
	return HIGHLIGHT_ATTACK_TARGET_FILL


func _get_skill_target_border_color() -> Color:
	if _selected_skill_id == "":
		return HIGHLIGHT_ATTACK_TARGET_BORDER
	var skill_data: Dictionary = _get_skill_data(_selected_skill_id)
	if _is_support_skill(skill_data):
		return HIGHLIGHT_SUPPORT_TARGET_BORDER
	return HIGHLIGHT_ATTACK_TARGET_BORDER


func _refresh_attack_cells() -> void:
	_range_display_cells = []
	_attack_cells = []
	_area_preview_cells = []
	_direction_selector_cells = []
	if current_unit == null:
		return
	if _attack_mode == ATTACK_MODE_SKILL and _selected_skill_id != "":
		var skill_data: Dictionary = _get_skill_data(_selected_skill_id)
		var range_data: Dictionary = skill_data.get("range", {})
		if str(range_data.get("type", "")) == "line" \
				and _targeting_direction == Vector2i.ZERO:
			_direction_selector_cells = RangeCalculator.get_line_selector_cells(
				grid, current_unit.grid_position, range_data)
			return
		if _skill_landing_mode(skill_data) == LANDING_MODE_ADJACENT:
			if _landing_anchor == LANDING_ANCHOR_NONE:
				_range_display_cells = RangeCalculator.calculate_cells(
					grid, current_unit.grid_position, range_data)
				_attack_cells = _get_landing_target_cells(current_unit, skill_data)
			else:
				_attack_cells = _get_adjacent_landing_cells(current_unit, _landing_anchor)
			return
		var candidate_cells: Array[Vector2i] = RangeCalculator.calculate_cells(
			grid, current_unit.grid_position, range_data, _targeting_direction)
		_range_display_cells = candidate_cells
		_attack_cells = _filter_targetable_cells(candidate_cells, skill_data)
	else:
		var basic_pattern: Dictionary = {
			"type": "diamond",
			"min": current_unit.attack_min_range,
			"max": current_unit.attack_range,
		}
		var basic_cells: Array[Vector2i] = RangeCalculator.calculate_cells(
			grid, current_unit.grid_position, basic_pattern)
		_range_display_cells = basic_cells
		_attack_cells = _filter_enemy_target_cells(basic_cells)


func _filter_targetable_cells(candidate_cells: Array[Vector2i],
		skill_data: Dictionary) -> Array[Vector2i]:
	if current_unit == null:
		return []
	if _is_ground_target_skill(skill_data):
		return candidate_cells
	var filtered_cells: Array[Vector2i] = []
	var relation: String = _get_skill_target_relation(skill_data)
	for cell_pos: Vector2i in candidate_cells:
		var target_unit: Unit = grid.get_unit_at(cell_pos)
		if _matches_target_relation(current_unit, target_unit, relation):
			filtered_cells.append(cell_pos)
	return filtered_cells


func _filter_enemy_target_cells(candidate_cells: Array[Vector2i]) -> Array[Vector2i]:
	if current_unit == null:
		return []
	var filtered_cells: Array[Vector2i] = []
	for cell_pos: Vector2i in candidate_cells:
		var target_unit: Unit = grid.get_unit_at(cell_pos)
		if target_unit != null and target_unit.faction != current_unit.faction:
			filtered_cells.append(cell_pos)
	return filtered_cells


## 算受伤格时用哪个方向：玩家选的那个，还是「起点 → 目标」推出来的那个。
##
## ── 2026-08-12：判据从 `area.type == "line"` 改成「本次有没有捕获到方向」──
##
## 旧实现是 `area.type == "line" and _targeting_direction != ZERO`，即**再一次拿伤害
## 波及的形状去猜**（同 `_is_ground_target_skill` 那个已修的病）。现在只问一件事：
## **这次玩家到底选没选过方向**。选了就用它，没选就按起点→目标推。
##
## 语义上这才是对的：`_targeting_direction` 非零本身就表示「玩家做过一次方向选择」，
## 那个选择该不该被采用，与受伤格恰好是什么形状无关——形状由 `AreaCalculator` 自己
## 按 `area` 处理，它对非 line 形状本就忽略 direction 参数。
##
## 零行为变化的依据：方向捕获只在 `range.type == "line"` 时发生（见
## `_is_waiting_for_line_direction`），而现有 `area.type == "line"` 的两条技能
## （剑士 / 剑圣的一闪与 `archer_piercing_arrow`）恰好都是 `range.type == "line"`；
## 反过来 `range.type == "line"` 但 area 非 line 的 `knight_charge`，其 direction
## 交给 `AreaCalculator` 后按 `single` 处理、本就不参与受伤格计算。
##
## ⚠ **这不等于「格子 / 方向」已经变成声明式**：要不要定方向仍由 `range.type` 决定，
## 不由 `target_mode=方向` 声明。
##
## **而这是「已裁决现在不做」，不是待办**（2026-08-12）：真实设计内容里 `方向` ⟺
## `直线` 精确对应，改成声明式在所有真实数据上结果一样；唯一分歧点 `knight_charge`
## （range=line 却 target_mode=单位）自己就是引擎自有测试技能、没有权威定性，为一个
## 待重判的值改架构是本末倒置。**要翻过来的条件**：测试单位正式化、`knight_charge`
## 拿到真定性之后。在此之前别动。完整理由见 lane §2.2 注 10 第四条。
func _get_skill_area_direction(origin: Vector2i, target_pos: Vector2i) -> Vector2i:
	if _targeting_direction != Vector2i.ZERO:
		return _targeting_direction
	return RangeCalculator.direction_from_to(origin, target_pos)


## 位移技能（如一闪）的受伤格：从 origin 到 landing 沿笛卡尔直线的途经格。
## 不含起点；含中途格；含落点。一闪 range=line→方向为 cardinal，路径为直线段。
func _get_displacement_path_cells(origin: Vector2i, landing: Vector2i) -> Array[Vector2i]:
	var path_cells: Array[Vector2i] = []
	if origin == landing:
		return path_cells
	var delta: Vector2i = landing - origin
	var step: Vector2i = Vector2i(signi(delta.x), signi(delta.y))
	if step == Vector2i.ZERO:
		return path_cells
	var cursor: Vector2i = origin + step
	# 安全上界：以曼哈顿/切比雪夫距离为界，避免非共线导致死循环。
	var guard: int = absi(delta.x) + absi(delta.y) + 1
	while guard > 0:
		if grid != null and grid.is_valid(cursor):
			path_cells.append(cursor)
		if cursor == landing:
			break
		cursor += step
		guard -= 1
	return path_cells


## 统一计算技能受伤格：displacement 技能用位移路径替换 AreaCalculator，
## 其余按 area 形状（拔刀菱形/居合 single）。三处调用方共用此函数避免分叉。
func _compute_skill_area_cells(user: Unit, skill_data: Dictionary,
		target_pos: Vector2i, direction: Vector2i) -> Array[Vector2i]:
	if user != null and bool(skill_data.get("displacement", false)):
		return _get_displacement_path_cells(user.grid_position, target_pos)
	return AreaCalculator.calculate_cells(
		grid, target_pos, skill_data.get("area", {}), direction)


## displacement 技能落点有效性：复用 _apply_skill_displacement 的同条件。
func _is_displacement_landing_valid(user: Unit, landing: Vector2i) -> bool:
	if user == null or not grid.is_valid(landing):
		return false
	if landing == user.grid_position:
		return false
	var cell: Cell = grid.get_cell(landing)
	if cell == null or not cell.is_passable() or cell.occupant != null:
		return false
	return true


func _build_skill_action(user: Unit, target_pos: Vector2i,
		target: Unit, landing: Vector2i = LANDING_ANCHOR_NONE) -> GameAction:
	if user == null or _selected_skill_id == "":
		return null
	var skill_data: Dictionary = _get_skill_data(_selected_skill_id)
	if skill_data.is_empty():
		return null
	var area_data: Dictionary = skill_data.get("area", {})
	var area_type: String = str(area_data.get("type", "single"))
	var area_direction: Vector2i = _get_skill_area_direction(
		user.grid_position, target_pos)
	var affected_cells: Array[Vector2i] = _compute_skill_area_cells(
		user, skill_data, target_pos, area_direction)
	var basic_attack_profile: Dictionary = _get_unit_basic_attack_profile(user)
	var payload: Dictionary = {
		"skill_name": str(skill_data.get("name", _selected_skill_id)),
		"action_cost": str(skill_data.get("action_cost", "standard")),
		"timing_constraint": str(skill_data.get("timing_constraint", "any")),
		"swift_limit": int(skill_data.get("swift_limit", 1)),
		"cooldown": int(skill_data.get("cooldown", 0)),
		"damage_type": str(skill_data.get("damage_type", "physical")),
		"pure_atk_source": str(skill_data.get("pure_atk_source", "phys")),
		"attack_type": _derive_skill_attack_type(skill_data),
		"skill_multiplier": float(skill_data.get("power", 100)) / 100.0,
		"terrain_multiplier": 1.0,
		"skill_power": _legacy_skill_power(basic_attack_profile),
		"weapon_hit": int(basic_attack_profile.get("weapon_hit", 0))
			+ int(skill_data.get("hit_bonus", 0)),
		"weapon_crit": int(basic_attack_profile.get("weapon_crit", 0))
			+ int(skill_data.get("crit_bonus", 0)),
		"range_type": str(skill_data.get("range", {}).get("type", "diamond")),
		"area_type": area_type,
		"effect_timing": str(skill_data.get("effect_timing", "after_damage")),
		"effects": skill_data.get("effects", []).duplicate(true),
		"target_direction": _serialize_vector2i(area_direction),
		"affected_cells": _serialize_cells(affected_cells),
		# ── 剑圣专属字段（缺省安全，非剑圣技能此处为 0/false）──
		"skill_id": _selected_skill_id,
		"guaranteed_hit": bool(skill_data.get("guaranteed_hit", false)),
		"guaranteed_crit": bool(skill_data.get("guaranteed_crit", false)),
		"crit_damage_bonus": float(skill_data.get("crit_damage_bonus", 0.0)),
		"crit_damage_mult": float(skill_data.get("crit_damage_mult", 1.0)),
		"qi_gain_on_hit": int(skill_data.get("qi_gain_on_hit", 0)),
		"qi_gain_on_kill": int(skill_data.get("qi_gain_on_kill", 0)),
		"mark_gain": int(skill_data.get("mark_gain", 0)),
		"mark_gain_after_damage": int(skill_data.get("mark_gain_after_damage", 0)),
		"qi_gain_after_damage": int(skill_data.get("qi_gain_after_damage", 0)),
		"mark_fill_on_hit": bool(skill_data.get("mark_fill_on_hit", false)),
		"ki_on_kill_cd_reduction": int(skill_data.get("ki_on_kill_cd_reduction", 0)),
	}
	if landing != LANDING_ANCHOR_NONE:
		payload["landing_cell"] = _serialize_vector2i(landing)
	# 满月：发动时先锁定纳刀（rules）。持有时纳刀的总降对本技能无效，本技能再总增。
	var state_form: Dictionary = skill_data.get("held_state_form", {})
	if not state_form.is_empty():
		payload["skill_name"] = str(state_form.get("name_without_state", payload["skill_name"]))
	if not state_form.is_empty() and user.held_states.has(str(state_form.get("state_id", ""))):
		payload["held_state_form_active"] = true
		payload["skill_name"] = str(state_form.get("name_with_state", payload["skill_name"]))
		if bool(state_form.get("ignores_state_damage_modifier", false)):
			payload["ignored_attacker_states"] = [str(state_form.get("state_id", ""))]
		payload["damage_total_modifiers"] = [
			float(state_form.get("damage_total_modifier", 1.0))]
	# 伤害条目按发动时范围内的敌人数选择（霸天：2 名以上 / 只有 1 名）。
	var damage_entry: Dictionary = _select_damage_entry(skill_data,
		_get_enemies_in_cells(user, affected_cells).size())
	if not damage_entry.is_empty():
		_apply_damage_entry(payload, skill_data, damage_entry,
			int(basic_attack_profile.get("weapon_hit", 0)))
	return GameAction.make_skill(user, _selected_skill_id, target_pos, target, payload)


## R1.7 武器威力不进入伤害。设计库外的旧技能、普通攻击与副手追加尚无「技能威力」，
## 暂按等价桥接：技能威力 = 原武器威力，系数仍取原 power/100，数值与改动前一致。
## 这是保持现状的过渡换算，不是设计结论；对应技能导入设计库后改走伤害条目。
func _legacy_skill_power(basic_attack_profile: Dictionary) -> float:
	return float(basic_attack_profile.get("weapon_might", 0))


## 设计库伤害条目（damage_entries）中本次结算使用的一条。
## 技能写了 engine_entry_conditions（按 sort 对应条目，给出范围内敌人数的上下限）且调用方给了
## 敌人数时，取第一条满足条件的条目（霸天的 applies_when）；否则按 sort 取最小的一条。
func _select_damage_entry(skill_data: Dictionary, enemy_count: int = -1) -> Dictionary:
	var entries: Variant = skill_data.get("damage_entries", [])
	if not entries is Array:
		return {}
	var conditions: Variant = skill_data.get("engine_entry_conditions", [])
	if enemy_count >= 0 and conditions is Array and not (conditions as Array).is_empty():
		for condition_value: Variant in (conditions as Array):
			if not condition_value is Dictionary:
				continue
			var condition: Dictionary = condition_value
			if enemy_count < int(condition.get("enemies_min", 0)):
				continue
			if condition.has("enemies_max") and enemy_count > int(condition.get("enemies_max", 0)):
				continue
			for item: Variant in (entries as Array):
				if item is Dictionary and int((item as Dictionary).get("sort", -1)) \
						== int(condition.get("sort", -2)):
					return item
	var chosen: Dictionary = {}
	for item: Variant in (entries as Array):
		if not item is Dictionary:
			continue
		var entry: Dictionary = item
		if chosen.is_empty() or int(entry.get("sort", 0)) < int(chosen.get("sort", 0)):
			chosen = entry
	return chosen


## 条目的伤害类型：条目写了就用条目的，否则用技能的；返回运行时键，无法识别时为空串。
func _damage_entry_type(skill_data: Dictionary, entry: Dictionary) -> String:
	var entry_type: Variant = entry.get("damage_type", null)
	if entry_type != null and str(entry_type) != "":
		return _normalize_damage_type(entry_type)
	return _normalize_damage_type(skill_data.get("damage_type", ""))


## 把设计库伤害条目写入技能 payload（R1.1 / R1.7）。
## 条目枚举保留设计库中文原值（「必定命中」「不可暴击」「力量」「纯粹」等），便于重新导入。
## 技能威力只取条目 power，不加武器威力；命中与暴击仍以主手武器为底（R1.7）。
func _apply_damage_entry(payload: Dictionary, skill_data: Dictionary,
		entry: Dictionary, weapon_hit: int) -> void:
	payload["damage_type"] = _damage_entry_type(skill_data, entry)
	payload["skill_power"] = float(entry.get("power", 0))
	payload["skill_multiplier"] = float(entry.get("coefficient", 1.0))
	payload["weapon_hit"] = weapon_hit + int(entry.get("hit_bonus", 0))
	match str(entry.get("base_attribute", "默认")):
		"力量":
			payload["base_attribute"] = "STR"
		"魔力":
			payload["base_attribute"] = "MAG"
		_:
			payload.erase("base_attribute")
	# 命中、暴击方式与暴击倍率以条目为准，覆盖技能 JSON 里同名旧字段（如旧居合的必定暴击）。
	payload["guaranteed_hit"] = str(entry.get("hit_mode", "正常")) == "必定命中"
	# 条目自身的必定命中单独记下：多段攻击的后续段只去掉其他效果给的必定命中。
	payload["entry_guaranteed_hit"] = payload["guaranteed_hit"]
	var crit_mode: String = str(entry.get("crit_mode", "正常"))
	payload["guaranteed_crit"] = crit_mode == "必定暴击"
	payload["disable_crit"] = crit_mode == "不可暴击"
	payload["crit_damage_bonus"] = 0.0
	payload["crit_damage_mult"] = float(entry.get("crit_multiplier", 1.0))
	payload["segments"] = maxi(1, int(entry.get("segments", 1)))
	payload["segment_hit_decay"] = int(entry.get("segment_hit_decay", 0))


## 设计库伤害类型中文值 → 运行时键；已是运行时键时原样返回，无法识别返回空串。
func _normalize_damage_type(value: Variant) -> String:
	match str(value):
		"物理", "physical":
			return "physical"
		"魔法", "magical":
			return "magical"
		"纯粹", "pure":
			return "pure"
		"混合", "hybrid":
			return "hybrid"
	return ""


func _derive_skill_attack_type(skill_data: Dictionary) -> String:
	## R4.3 攻击方式轴：技能声明 attack_type 时用声明值；
	## 未声明时按同一规则派生（area ≠ single → area；射程 max > 1 → ranged；否则 melee），
	## 保证缺省值也符合锁定规则而非固定 melee。
	var declared: String = str(skill_data.get("attack_type", ""))
	if declared != "":
		return declared
	var area_type: String = str(skill_data.get("area", {}).get("type", "single"))
	if area_type != "single":
		return "area"
	var range_max: int = int(skill_data.get("range", {}).get("max", 1))
	if range_max > 1:
		return "ranged"
	return "melee"


func _serialize_cells(cells: Array[Vector2i]) -> Array[Dictionary]:
	var serialized_cells: Array[Dictionary] = []
	for cell_pos: Vector2i in cells:
		serialized_cells.append(_serialize_vector2i(cell_pos))
	return serialized_cells


func _serialize_vector2i(cell_pos: Vector2i) -> Dictionary:
	return {"x": cell_pos.x, "y": cell_pos.y}


func _deserialize_vector2i(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Dictionary:
		return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
	return Vector2i.ZERO


func _extract_cells_from_payload(value: Variant) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not (value is Array):
		return cells
	for cell_value: Variant in value:
		var cell_pos: Vector2i = _deserialize_vector2i(cell_value)
		if grid.is_valid(cell_pos):
			cells.append(cell_pos)
	return cells


func _get_skill_data(skill_id: String) -> Dictionary:
	return DataLoader.skills.get(skill_id, {})


func _is_supported_runtime_skill(skill_data: Dictionary) -> bool:
	if skill_data.is_empty():
		return false
	var action_cost: String = str(skill_data.get("action_cost", "standard"))
	# free 为 [预留] 类型（2026-07-11 用户裁决：零消耗，R3.3 将增补；当前无技能使用）
	if action_cost not in ["move", "standard", "swift", "free"]:
		return false
	var range_data: Dictionary = skill_data.get("range", {})
	if str(range_data.get("type", "")) not in [
		"diamond", "line", "cross", "square", "self",
	]:
		return false
	var area_data: Dictionary = skill_data.get("area", {})
	if str(area_data.get("type", "single")) not in [
		"single", "diamond", "line", "cross", "square",
	]:
		return false
	if _is_support_skill(skill_data):
		return true
	var damage_entry: Dictionary = _select_damage_entry(skill_data)
	if not damage_entry.is_empty():
		return _damage_entry_type(skill_data, damage_entry) != ""
	var damage_type: String = str(skill_data.get("damage_type", ""))
	if damage_type not in ["physical", "magical", "pure", "hybrid"]:
		return false
	return int(skill_data.get("power", 0)) > 0


func _is_adjacent(a: Unit, b: Unit) -> bool:
	var dist: int = absi(a.grid_position.x - b.grid_position.x) \
			  + absi(a.grid_position.y - b.grid_position.y)
	return dist <= 1


func _build_hostile_action_context(attacker: Unit, defender: Unit,
		base_data: Dictionary) -> Dictionary:
	var action_data: Dictionary = base_data.duplicate(true)
	var basic_attack_profile: Dictionary = _get_unit_basic_attack_profile(attacker)
	var terrain_context: Dictionary = _get_unit_terrain_context(defender)
	if not action_data.has("skill_power"):
		action_data["skill_power"] = _legacy_skill_power(basic_attack_profile)
	if not action_data.has("weapon_hit"):
		action_data["weapon_hit"] = int(basic_attack_profile.get("weapon_hit", 0))
	if not action_data.has("weapon_crit"):
		action_data["weapon_crit"] = int(basic_attack_profile.get("weapon_crit", 0))
	if str(action_data.get("damage_type", "")) == "":
		action_data["damage_type"] = str(basic_attack_profile.get("damage_type", "physical"))
	if str(action_data.get("attack_type", "")) == "":
		action_data["attack_type"] = str(basic_attack_profile.get("attack_type", "melee"))
	# 基础攻击（普攻，无 skill 的 qi 字段）按职业基础攻击产气量补默认值；
	# 技能动作已带 qi_gain_on_hit，不会被覆盖。
	if not action_data.has("qi_gain_on_hit"):
		action_data["qi_gain_on_hit"] = int(basic_attack_profile.get("basic_attack_qi_gain", 0))
	action_data["terrain_evade_bonus"] = int(terrain_context.get("terrain_evade_bonus", 0))
	action_data["terrain_def_bonus"] = int(terrain_context.get("terrain_def_bonus", 0))
	action_data["terrain_res_bonus"] = int(terrain_context.get("terrain_res_bonus", 0))
	action_data["defender_terrain_name"] = str(terrain_context.get("terrain_name", "PLAIN"))
	# ── 敌人词条 afs_bulwark（壁垒统御）：防御方己方减伤光环 → 防御乘区（真实生效 hook）。
	# forecast（preview）与执行（resolve）共用本上下文，保证预告==实际伤害。
	# 无光环时乘区==1.0 → 与 damage_calculator 默认一致（无词条零影响）。
	action_data["affix_defense_multiplier"] = _affix_bulwark_multiplier(defender)
	# 〔澄心〕：每层使自身技能伤害的威力 +N（威力加算，计入技能威力）。反击也是技能伤害。
	if str(action_data.get("skill_id", "")) != "":
		var power_bonus: float = _held_state_skill_power_bonus(attacker)
		if power_bonus != 0.0:
			action_data["skill_power"] = float(action_data.get("skill_power", 0.0)) + power_bonus
	# 攻击者持有的状态带来的总增总降（纳刀：自身造成的伤害总降 50%），满月这类声明无效的除外。
	var totals: Array = (action_data.get("damage_total_modifiers", []) as Array).duplicate()
	# 「自身在自身回合内使用技能造成的伤害」（架势）：攻击者正在自己的回合、这是技能动作、不是反击。
	var own_turn_skill: bool = attacker.is_taking_turn \
		and str(action_data.get("skill_id", "")) != "" \
		and not bool(action_data.get("is_counter", false))
	totals.append_array(_attacker_state_damage_modifiers(
		attacker, action_data.get("ignored_attacker_states", []), own_turn_skill))
	action_data["damage_total_modifiers"] = totals
	_apply_debug_determinism(action_data)
	return action_data


func _held_state_skill_power_bonus(attacker: Unit) -> float:
	var total: float = 0.0
	for state_id: String in attacker.held_states.held_ids():
		var per_stack: float = float((DataLoader.held_states.get(state_id, {}) as Dictionary).get(
			"engine_skill_power_per_stack", 0))
		total += per_stack * float(attacker.held_states.stacks(state_id))
	return total


## 攻击者持有状态的总增总降（R1.1 第二层，逐项相乘）：状态定义里的 engine_damage_total_modifier。
## ignored：本次攻击声明对其无效的状态 id。
func _attacker_state_damage_modifiers(attacker: Unit, ignored: Variant,
		own_turn_skill: bool = false) -> Array:
	var out: Array = []
	if attacker == null:
		return out
	for state_id: String in attacker.held_states.held_ids():
		if ignored is Array and (ignored as Array).has(state_id):
			continue
		var definition: Dictionary = DataLoader.held_states.get(state_id, {})
		if definition.has("engine_damage_total_modifier"):
			out.append(float(definition["engine_damage_total_modifier"]))
		# 架势：比例随给予它的技能变化，写在施加时的参数里（R3.4），只作用于自身回合内的技能伤害。
		var params: Dictionary = attacker.held_states.params(state_id)
		if own_turn_skill and params.has("damage_total_modifier_own_turn_skill"):
			out.append(float(params["damage_total_modifier_own_turn_skill"]))
	return out


## 调试确定性开关注入（默认关 → 原样返回，不影响正式战斗）。
## 开时：强制命中 + 暴击三态。复用 damage_calculator 现有 guaranteed_hit/
## guaranteed_crit/disable_crit 字段，与 headless 确定性一致。
func _apply_debug_determinism(action_data: Dictionary) -> void:
	if not debug_harness_active or not debug_deterministic:
		return
	action_data["guaranteed_hit"] = true
	match debug_crit_mode:
		CritMode.FORCE:
			# 伤害条目声明「不可暴击」的技能（disable_crit 已为 true）保持不可暴击。
			if not bool(action_data.get("disable_crit", false)):
				action_data["guaranteed_crit"] = true
		CritMode.DISABLE:
			action_data["guaranteed_crit"] = false
			action_data["disable_crit"] = true
		_:
			# RANDOM：不改写暴击字段，保留技能原有 guaranteed_crit（如居合）。
			pass


func _build_basic_attack_action_data(attacker: Unit, defender: Unit,
		extra_data: Dictionary = {}) -> Dictionary:
	var basic_attack_profile: Dictionary = _get_unit_basic_attack_profile(attacker)
	var action_data: Dictionary = {
		"damage_type": str(basic_attack_profile.get("damage_type", "physical")),
		"attack_type": str(basic_attack_profile.get("attack_type", "melee")),
		"skill_multiplier": 1.0,
		"terrain_multiplier": 1.0,
		"relic_multiplier": 1.0,
		"final_multiplier": 1.0,
		"skill_power": _legacy_skill_power(basic_attack_profile),
		"weapon_hit": int(basic_attack_profile.get("weapon_hit", 0)),
		"weapon_crit": int(basic_attack_profile.get("weapon_crit", 0)),
		"pure_atk_source": str(basic_attack_profile.get("pure_atk_source", "phys")),
	}
	for key_value: Variant in extra_data.keys():
		var key: String = str(key_value)
		action_data[key] = extra_data[key]
	return _build_hostile_action_context(attacker, defender, action_data)


func _get_unit_basic_attack_profile(unit: Unit) -> Dictionary:
	var source_data: Dictionary = _get_unit_source_data(unit)
	var weapon_data: Dictionary = _get_unit_weapon_data(source_data, unit)
	var range_data: Dictionary = source_data.get("basic_attack_range", {"min": 1, "max": 1})
	var attack_type: String = "melee" if int(range_data.get("max", 1)) <= 1 else "ranged"
	return {
		"weapon_might": int(weapon_data.get("weapon_might", 0)),
		"weapon_hit": int(weapon_data.get("weapon_hit", 0)),
		"weapon_crit": int(weapon_data.get("weapon_crit", 0)),
		"damage_type": str(source_data.get("damage_type", "physical")),
		"pure_atk_source": str(source_data.get("pure_atk_source", "phys")),
		"attack_type": attack_type,
		# 剑圣等职业：基础攻击（普攻）命中产气，数值从职业 JSON 读，非剑圣缺省 0
		"basic_attack_qi_gain": int(source_data.get("basic_attack_qi_gain", 0)),
		"basic_attack_range": {
			"min": maxi(1, int(range_data.get("min", 1))),
			"max": maxi(1, int(range_data.get("max", 1))),
		},
	}


func _get_unit_source_data(unit: Unit) -> Dictionary:
	if unit == null:
		return {}
	var class_data: Dictionary = DataLoader.classes.get(unit.unit_id, {})
	if not class_data.is_empty():
		return class_data
	return DataLoader.enemies.get(unit.unit_id, {})


## R1.7：武器参数唯一来源 = 所装备武器（data/weapons/，DataLoader.weapons）。
## 每单位恒持一件武器（class/enemy JSON 必须声明 weapon_id）；缺失时数据校验兜底：
## push_error 记录 + might/hit/crit 回退 0（不崩溃战斗，但日志会显眼暴露数据缺陷）。
func _get_unit_weapon_data(source_data: Dictionary, unit: Unit) -> Dictionary:
	var weapon_id: String = str(source_data.get("weapon_id", ""))
	if weapon_id == "":
		push_error("[Weapon] 单位 %s 缺少 weapon_id（每单位恒持一件武器，R1.7）" \
			% (unit.unit_id if unit != null else "?"))
		return {}
	var weapon_data: Dictionary = DataLoader.weapons.get(weapon_id, {})
	if weapon_data.is_empty():
		push_error("[Weapon] 单位 %s 的 weapon_id \"%s\" 未找到武器定义" % [
			(unit.unit_id if unit != null else "?"), weapon_id])
	return weapon_data


func _get_unit_terrain_context(unit: Unit) -> Dictionary:
	if unit == null or grid == null:
		return {
			"terrain_name": "PLAIN",
			"terrain_evade_bonus": 0,
			"terrain_def_bonus": 0,
			"terrain_res_bonus": 0,
		}
	var cell: Cell = grid.get_cell(unit.grid_position)
	if cell == null:
		return {
			"terrain_name": "PLAIN",
			"terrain_evade_bonus": 0,
			"terrain_def_bonus": 0,
			"terrain_res_bonus": 0,
		}
	var combat_modifiers: Dictionary = cell.get_combat_modifiers()
	return {
		"terrain_name": str(combat_modifiers.get("terrain_name", "PLAIN")),
		"terrain_evade_bonus": int(combat_modifiers.get("evade_bonus", 0)),
		"terrain_def_bonus": int(combat_modifiers.get("def_bonus", 0)),
		"terrain_res_bonus": int(combat_modifiers.get("res_bonus", 0)),
	}


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


# ── 剑圣资源：命中/击杀后的气与印记结算 ─────────────────

func _apply_sword_qi_on_hit(attacker: Unit,
		result: DamageCalculator.AttackResult,
		action_data: Dictionary) -> void:
	# 仅在命中时触发；普通攻击 action_data 无此字段，缺省为 0/false
	if not result.hit:
		return
	# 命中得气（如斩击 qi_gain_on_hit=1）
	var qi_on_hit: int = int(action_data.get("qi_gain_on_hit", 0))
	if qi_on_hit > 0:
		attacker.gain_sword_qi(qi_on_hit, "on_hit:" + str(action_data.get("skill_id", "")))
		print("[SwordQi] %s +%d qi on hit → %d" % [
			attacker.unit_name, qi_on_hit, attacker.sword_qi])
	# 命中后获得全部未持有的印记（设计库 kensei_kongxiangjian）。
	if bool(action_data.get("mark_fill_on_hit", false)):
		while attacker.gain_random_mark() != "":
			pass
	# 命中并造成伤害后得剑气（设计库 kensei_yijue：每段命中并造成伤害后 +10）。
	var qi_after_damage: int = int(action_data.get("qi_gain_after_damage", 0))
	if qi_after_damage > 0 and result.damage > 0:
		attacker.gain_sword_qi(qi_after_damage,
			"after_damage:" + str(action_data.get("skill_id", "")))
	# 命中后得印记（如居合 mark_gain=1，命中即结算）
	var mark_gain: int = int(action_data.get("mark_gain", 0))
	if mark_gain > 0:
		var gained_mark: String = attacker.gain_random_mark()
		if gained_mark != "":
			print("[SwordMark] %s gained mark 「%s」 on hit, total=%d" % [
				attacker.unit_name, gained_mark, attacker.get_mark_count()])
	# 造成伤害后得印记（设计库 kensei_zhanji：剑气在命中时、印记在伤害结算后；致命一段照常结算）。
	# 本函数在 take_damage 之后调用，所以本段伤害吃不到新印记的加成。伤害为 0 不算「造成伤害」[推断]。
	var mark_after_damage: int = int(action_data.get("mark_gain_after_damage", 0))
	if mark_after_damage > 0 and result.damage > 0:
		for _i: int in range(mark_after_damage):
			var damage_mark: String = attacker.gain_random_mark()
			if damage_mark != "":
				print("[SwordMark] %s gained mark 「%s」 after damage, total=%d" % [
					attacker.unit_name, damage_mark, attacker.get_mark_count()])
	# 击杀触发：得气 + 技能 CD 减少
	if not result.defender_died:
		return
	var qi_on_kill: int = int(action_data.get("qi_gain_on_kill", 0))
	if qi_on_kill > 0:
		attacker.gain_sword_qi(qi_on_kill, "on_kill:" + str(action_data.get("skill_id", "")))
		print("[SwordQi] %s +%d qi on kill → %d" % [
			attacker.unit_name, qi_on_kill, attacker.sword_qi])
	var cd_reduce: int = int(action_data.get("ki_on_kill_cd_reduction", 0))
	var origin_skill_id: String = str(action_data.get("skill_id", ""))
	if cd_reduce > 0 and origin_skill_id != "":
		var current_cd: int = attacker.get_skill_cooldown(origin_skill_id)
		var new_cd: int = maxi(0, current_cd - cd_reduce)
		if new_cd == 0:
			attacker.skill_cooldowns.erase(origin_skill_id)
		else:
			attacker.skill_cooldowns[origin_skill_id] = new_cd
		print("[SwordQi] %s %s CD %d→%d on kill" % [
			attacker.unit_name, origin_skill_id, current_cd, new_cd])


# ── 天赋时机分发器（Wave 1 · A1）────────────────────────
# 纯加法：单位 talent_ids 为空 → 立即 return，正式战斗零影响。
# 只分发在 TalentRegistry 里**注册成功**的天赋；被拒收的 id 即使写进 talent_ids
# 也不会触发，且拒收时已 push_warning、理由可从 rejection_reason() 查到
# （Wave 1 §2.3：unevaluable 必须响亮失败，不许静默当条件不成立）。


## 懒构造天赋注册器。放在这里而非 _ready，是为了让 headless 测试能在
## 场景实例化之后再注入数据；DataLoader 是 autoload，此处只读不写。
func _ensure_state_registry() -> RefCounted:
	if _state_registry == null:
		_state_registry = StateRegistryScript.new(DataLoader.states)
	return _state_registry


func _ensure_talent_registry() -> RefCounted:
	if _talent_registry == null:
		_talent_registry = TalentRegistryScript.new(
			DataLoader.talents, _ensure_state_registry())
	return _talent_registry


func _dispatch_talents(unit: Unit, event: String, ctx: Dictionary) -> void:
	if unit == null or unit.talent_ids.is_empty():
		return
	var registry: RefCounted = _ensure_talent_registry()
	for row: Dictionary in registry.talents_for_event(event):
		var entry: Dictionary = row["talent"]
		# ★ 条件读的是**触发行**而非整卡：附加行有自己的 requires_states。
		# 二天一流就是主行永久生效无条件、附加行要求〔双持〕——退回卡级会让它
		# 在没装副手武器时也追加伤害。
		var trigger: Dictionary = row["trigger"]
		var talent_id: String = str(entry.get("id", ""))
		if talent_id not in unit.talent_ids:
			continue
		# 四道行级把关，缺一不可（都读**触发行**而非整卡）：
		#   来源 —— 本次伤害由哪只手产生（`trigger_source`，空 = 不限）
		#   路径 —— 本次伤害走的哪条产生路径（`requires_contexts`）
		#   回合 —— 本次事件落在被作用者回合内还是回合外（`requires_turn_phase`）
		#   状态 —— `requires_states` 此刻成不成立
		if not _talent_source_matches(trigger, ctx):
			continue
		if not _talent_contexts_hold(trigger, ctx):
			continue
		if not _talent_turn_phase_holds(trigger, ctx):
			continue
		if not _talent_conditions_hold(unit, trigger):
			continue
		var effects: Variant = entry.get("engine_effects", [])
		if not effects is Array:
			push_warning("[Talent] %s 的 engine_effects 不是数组，跳过" % talent_id)
			continue
		# ★ 按**行**取效果，不是整卡的 engine_effects：剑气回荡是两行两效果
		# （主行让副手必暴 / 附加行给 10 点剑气），不过滤就会两行各执行全部效果。
		for item: Variant in registry.effects_for_row(entry, str(row["row"])):
			if item is Dictionary:
				_apply_talent_effect(unit, talent_id, item, ctx)
			else:
				push_warning("[Talent] %s 的 engine_effects 含非字典项，跳过该项" % talent_id)


## 触发来源匹配（Wave 3）。设计库 `trigger_source` 是「主手 / 副手」闭集，
## **空串 = 不限来源**——介错的击杀返气不该因为是副手补的那一刀就不给。
##
## 分发点没声明来源时（ctx 无 `source` 键），指定了来源的卡一律不触发。注册期
## 已经拦掉了「把来源挂在不带来源的事件上」这种卡，所以走到这里还失配，说明是
## 分发点漏传了 —— 宁可不触发，不可错误触发。
func _talent_source_matches(trigger_row: Dictionary, ctx: Dictionary) -> bool:
	var want: String = str(trigger_row.get("trigger_source", "")).strip_edges()
	if want == "":
		return true
	return want == str(ctx.get("source", ""))


## 产生路径匹配（Wave 3）：`requires_contexts` 里每个标签，本次分发都得带上。
##
## 如实记下当前的把关强度：引擎目前唯一的伤害产生路径就是主动攻击动作（自动反击
## 已于 2026-07-11 整体移除），所以 `active_attack` **此刻恒成立**，这个函数当前
## 返回不了 false。它不是装饰——注册期的闭集校验是真的（依赖未知标签的卡会被拒），
## 求值也真的在跑；但要等 Wave 4 的防御侧事件落地，它才会真正开始区分。
## 结构先立起来，是为了今天不吞掉条件文本里「发生在主动攻击动作中」那半句。
## 回合位置匹配（Wave 4）：`requires_turn_phase` 非空时，本次分发必须带上同一个值。
##
## 形状照 `_talent_source_matches`（单值 + 空串=不限），不照 `_talent_contexts_hold`
## （数组、逐个都要满足）——理由见 talent_registry 的 SUPPORTED_TURN_PHASES 注释。
##
## 分发点没声明回合位置时（ctx 无 `turn_phase` 键），指定了回合位置的卡一律不触发：
## 宁可不触发，不可错误触发。攻击链五事件就是这一类——它们发给攻击者，而攻击者
## 必然在自己回合内，「不处于自身回合内」这种要求挂上去本身就是建卡错误。
##
## ⚠ 如实记下当前的把关强度：引擎没有任何能让单位在自己回合内被攻击的路径，
## 所以走到这里的 `outside_own_turn` 恒成立，本函数在防御侧返回不了 false。
## 它在**攻击侧**倒是真的会返回 false（那些 ctx 根本不带 turn_phase 键），
## 所以这个函数不是死代码——但那条分支拦的是建卡错误，不是游戏机制。
func _talent_turn_phase_holds(trigger_row: Dictionary, ctx: Dictionary) -> bool:
	var want: String = str(trigger_row.get("requires_turn_phase", "")).strip_edges()
	if want == "":
		return true
	return want == str(ctx.get("turn_phase", ""))


## 本次事件落在 `unit` 自己的回合内还是回合外。
## `turn_manager.current_unit` 是当前正在行动的单位；被攻击者不是它就是回合外。
func _turn_phase_of(unit: Unit) -> String:
	if turn_manager != null and turn_manager.current_unit == unit:
		return TURN_PHASE_OWN
	return TURN_PHASE_OUTSIDE_OWN


func _talent_contexts_hold(trigger_row: Dictionary, ctx: Dictionary) -> bool:
	var required: Variant = trigger_row.get("requires_contexts", [])
	if not required is Array or (required as Array).is_empty():
		return true
	var actual: Variant = ctx.get("contexts", [])
	if not actual is Array:
		return false
	for item: Variant in (required as Array):
		if str(item) not in (actual as Array):
			return false
	return true


## 分发「命中时」/「暴击时」两个真 on-hit 事件（Wave 3 · A2）。
##
## ⚠ R1.4 逐字只把效果时机分成 on-hit 与 after-damage **两类**，规则层没有独立的
## 「暴击时」。所以这里把它实现成 on-hit 的**条件化分支**——命中就发「命中时」，
## 其中暴击的再发一次「暴击时」，同一时点、同一批次。不是并列的第三类时机。
func _dispatch_on_hit_events(attacker: Unit, outcome: Dictionary,
		ctx: Dictionary) -> void:
	if not bool(outcome.get("hit", false)):
		return
	# ★ 给 ctx 的是**副本**，不是 outcome 本身。Dictionary 是引用类型，而这同一个
	# outcome 随后会作为 precomputed_outcome 交给 resolve_attack —— 直接放进 ctx
	# 就等于把本次的命中/暴击结果开放给天赋改写，那正是 R1.2 / R1.3 禁止的回溯改判
	# （两条链的最终层修正必须在掷骰之前应用完）。注释里禁止是一回事，结构上做不到
	# 才是保障。天赋想读掷骰结果可以，改不动。
	ctx["outcome"] = outcome.duplicate(true)
	_dispatch_talents(attacker, "命中时", ctx)
	if bool(outcome.get("crit", false)):
		_dispatch_talents(attacker, "暴击时", ctx)


## 防御侧反应分发给被攻击者，时点在命中判定后、伤害数值结算前。
## 未命中时不分发事件也不消耗剑气。
## 返回 `{applied, multiplier, reduction_pct, via, prevented}`；实际减免量由
## `_record_parry_prevented` 在伤害结算后回填。
func _resolve_defense(attacker: Unit, defender: Unit, outcome: Dictionary,
		source: String) -> Dictionary:
	var defense: Dictionary = {
		"applied": false, "multiplier": 1.0, "reduction_pct": 0.0,
		"via": "", "prevented": 0,
	}
	if defender == null or not bool(outcome.get("hit", false)):
		return defense

	# ── 第一步：分发「受到攻击时」，让防御侧天赋登记意图 ──────────
	# 天赋在这里**只登记不结算**（同 offhand_followup 的做法）。真正的取舍在下面
	# 那个唯一的结算点做——不然「架势已经减过了就不该再减一次、也不该白扣剑气」
	# 这条没有地方判，两条入口会各减各的。
	var defense_ctx: Dictionary = {
		"attacker": attacker, "defender": defender,
		"source": source, "contexts": [CONTEXT_ACTIVE_ATTACK],
		"turn_phase": _turn_phase_of(defender),
		# 给副本，理由同 _dispatch_on_hit_events：不开放本次 hit/crit 给天赋改写。
		"outcome": outcome.duplicate(true),
		"pending_parry": [],
	}
	_dispatch_talents(defender, "受到攻击时", defense_ctx)

	var params: Dictionary = _parry_params()
	if params.is_empty():
		return defense

	# ── 第二步：架势先行（它是免费的）────────────────────────
	# ★ `randf()` 只在**确实挂着架势**时才掷。多掷一次会整体平移全局随机序列，
	# 让所有固定 seed 的用例漂移——这也是为什么这道 has_buff 守卫不能写成
	# 「先掷再看有没有架势」。
	if defender.has_buff(PARRY_STANCE_BUFF_ID):
		var chance_stat: String = str(params.get("chance_stat", ""))
		var chance: float = float(defender.get_effective_stat(chance_stat)) / 100.0
		if randf() < chance:
			_fill_parry_result(defense, defender, params, "stance:" + PARRY_STANCE_BUFF_ID)
			print("[Parry] %s 招架成功（%s=%d%%）→ 减伤 %.1f%%" % [
				defender.unit_name, chance_stat,
				defender.get_effective_stat(chance_stat), defense["reduction_pct"]])

	# ── 第三步：架势没生效时，才轮到付费入口（交刃）──────────
	# **减伤每次攻击至多结算一次。** 两条入口给的是同一份减伤（设计库交刃逐字：
	# 「按招架的减伤结算」），叠乘等于凭空双倍，而设计库两边都没写可叠加。
	# 顺序上让免费的先掷、付费的兜底，正合交刃「花剑气买必定」的定位：白掷中了
	# 就不用付钱。**这是一处实装判断**，设计库没有明文，已在交付回执里登记。
	if not bool(defense["applied"]):
		for intent: Variant in (defense_ctx["pending_parry"] as Array):
			if not intent is Dictionary:
				continue
			var wish: Dictionary = intent
			var qi_cost: int = int(wish.get("qi_cost", 0))
			# 剑气不够就跳过，且**不扣**——交刃 trigger_condition 逐字含「当前剑气 ≥ 10」。
			if defender.sword_qi < qi_cost:
				continue
			if qi_cost > 0:
				defender.spend_sword_qi(qi_cost, "talent:" + str(wish.get("talent_id", "")))
			_fill_parry_result(defense, defender, params,
				"talent:" + str(wish.get("talent_id", "")))
			print("[Parry] %s 「%s」→ 消耗 %d 剑气换必定减伤 %.1f%%（剩余 %d）" % [
				defender.unit_name, str(wish.get("talent_id", "")), qi_cost,
				defense["reduction_pct"], defender.sword_qi])
			break
	return defense


## 招架减伤的参数：`data/buffs/swordsman_parry_stance.json` 的 `parry` 段。
##
## **这是减伤幅度在引擎侧的唯一权威**，招架架势与交刃共读它。设计库招架 `effect`
## 的叙述文本「按 SPD% 概率减少 (40+DEX)% 的伤害」是设计权威，这一段是它的机器
## 可执行译文（同 `engine_effects` 的模式），所以代码里不写死这三个值。
func _parry_params() -> Dictionary:
	var buff: Variant = DataLoader.buffs.get(PARRY_STANCE_BUFF_ID, {})
	if not buff is Dictionary:
		push_warning("[Parry] %s 的 buff 数据形状不对，减伤放弃" % PARRY_STANCE_BUFF_ID)
		return {}
	var params: Variant = (buff as Dictionary).get("parry", {})
	if not params is Dictionary or (params as Dictionary).is_empty():
		push_warning("[Parry] %s 缺 parry 段（减伤参数），减伤放弃——数据没接上时必须响亮，不能静默当作不减伤"
			% PARRY_STANCE_BUFF_ID)
		return {}
	return params


## 按 `parry` 段算出本次的减伤幅度与乘项，就地填进 `defense`。
##
## 减伤是**乘项不是减项**：`(base_pct + stat 当前值)%` 的「减少伤害」= 乘以
## `1 − pct/100`，落在本引擎的 `final_multiplier`。
##
## ⚠ **命名偏离的方向是引擎这一侧，不是设计库。** 规则表 R1.1（状态=锁定）逐字把
## 这一层写作 `final_modifier`：
##   `final_damage = base_damage × skill_multiplier × terrain_modifier
##                   × crit_modifier × relic_modifier × final_modifier`
## 引擎对其中三层用了 `_multiplier`（`terrain_` / `relic_` / `final_`），只有
## `skill_multiplier` 与 R1.1 一致。所以交刃 rules 写 `final_modifier` **是对的**
## ——它引的是锁定规则的术语，不是抄了个引擎键名；舍身（`myrmidon_sheshen`）也在用
## 同一个词。要对齐就该改引擎去贴 R1.1，而不是改设计库。本波不做那个改名（纯机械、
## 跨多处、与本波无关），登记在此。
func _fill_parry_result(defense: Dictionary, defender: Unit,
		params: Dictionary, via: String) -> void:
	var base_pct: float = float(params.get("reduction_base_pct", 0.0))
	var stat_key: String = str(params.get("reduction_stat", ""))
	var stat_value: int = defender.get_effective_stat(stat_key) if stat_key != "" else 0
	var pct: float = base_pct + float(stat_value)
	# 上限不钳（问题①答 (c)）：照数值原样实装，越界由数值设计负责，引擎不擅自加
	# 规则——钳一个设计库没写的上限就是引擎替设计做决定。但要**让它看得见**：
	# 算到 100% 及以上时响亮告警，否则「DEX 到 60 就永久免疫」会静默生效到没人发现。
	# 与 MAX_OFFHAND_FOLLOWUPS_PER_ACTION 同源——护栏让错数据可见，不改变行为。
	if pct >= 100.0:
		push_warning("[Parry] %s 的招架减伤算到 %.1f%%（>=100%%，本次攻击伤害归零）——%s=%d 已使 (%s+%s) 越界，请检查数值设计"
			% [defender.unit_name, pct, stat_key, stat_value,
				str(base_pct), stat_key])
	defense["applied"] = true
	defense["reduction_pct"] = pct
	defense["multiplier"] = maxf(0.0, 1.0 - pct / 100.0)
	defense["via"] = via


## 把减伤乘项并进 `action_data`，供随后的 `resolve_attack` 读。
##
## **用乘不用赋值**——`final_multiplier` 里还住着副手追加的 50% 与 on-hit 钩子写下的
## 「更多伤害」，直接覆写会把它们抹掉。
func _apply_defense_to_action(action_data: Dictionary, defense: Dictionary) -> void:
	if not bool(defense.get("applied", false)):
		return
	var before: float = float(action_data.get("final_multiplier", 1.0))
	# 记下减伤**之前**的值，供 _record_parry_prevented 精确还原基准伤害。
	# 不用「事后除回去」：减伤 100% 时乘项是 0，除不回来，而那正是最该报准的一档。
	defense["multiplier_before"] = before
	action_data["final_multiplier"] = before * float(defense.get("multiplier", 1.0))


## 回填「本次减伤实际挡下了多少点伤害」（借力的蓄劲要读这个数）。
##
## ★ 为什么要再算一次而不是拿乘项反推：`resolve_attack` 的最终量向下取整（R1.8），
## 反推 `damage / multiplier` 会因取整误差得到一个不精确的数，而蓄劲存的是「被减免
## 的伤害」，那必须是精确值。这里用**同一个 `precomputed_outcome`** 再算一次不带减伤
## 的伤害，两次都不掷骰、不改状态，差值就是精确减免量。
##
## ⚠ 本波不实装借力，这个数当前无人读取——但接口按它的需要设计好（Wave 4 任务书
## §2 问题②答 (a)），免得借力落地时回头再改减伤实现。取的是**两个已取整最终量的
## 差**，即「实际少挨了多少点」；若将来裁定蓄劲要存取整前的量，改这里一处即可。
func _record_parry_prevented(attacker: Unit, defender: Unit,
		action_data: Dictionary, result: DamageCalculator.AttackResult,
		defense: Dictionary) -> void:
	if not bool(defense.get("applied", false)) or not result.hit:
		return
	if not defense.has("multiplier_before"):
		# 走到这里说明 _apply_defense_to_action 没跑过（减伤算出来了却没并进
		# action_data），那是接线错误，必须响亮，不能报一个错的 prevented 出去。
		push_warning("[Parry] defense 缺 multiplier_before，无法计算减免量——减伤可能没并进 action_data")
		return
	var baseline_data: Dictionary = action_data.duplicate(true)
	# 深拷贝会把 precomputed_outcome 一并带过来（它是 Dictionary，会被真正深拷贝
	# ——见 DamageCalculator.roll_outcome 的类型说明），所以这一次**不掷骰**：
	# 同一次命中/暴击判定，只是不乘减伤那一项。
	baseline_data["final_multiplier"] = float(defense["multiplier_before"])
	var baseline: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(
		attacker, defender, baseline_data)
	defense["prevented"] = maxi(0, baseline.damage - result.damage)


## 把 on-hit 钩子里天赋写下的伤害修正合进 `action_data`，供随后的 `resolve_attack` 读。
##
## 目前只有一类：R1.8 的「更多」修正（措辞「N% 更多 X」），各条独立连乘、落在伤害链
## 最外层，对应引擎的 `final_multiplier`。**用乘不用赋值**——副手追加的 50% 也住在
## `final_multiplier` 里，直接覆写会把它抹掉。
##
## ⚠ 这里只合**伤害链**修正。命中链与暴击链的任何层修正都不许经此写回：那两条链的
## 最终层修正必须在掷骰之前应用完（R1.2 第四层的 clamp(1,100)、R1.3 第四层的取
## 大于 0 都发生在掷骰前），掷完再改就是回溯改判。「无视闪避 / 无视暴击回避」这类
## 效果同理——它们的生效时点在 `roll_outcome` 内部（闪避与暴击回避被消耗的那一刻），
## 必须在进入掷骰前就备齐，绝不能走这个钩子。
func _merge_on_hit_modifiers(action_data: Dictionary, ctx: Dictionary) -> void:
	var more: float = float(ctx.get("more_damage_multiplier", 1.0))
	if more == 1.0:
		return
	action_data["final_multiplier"] = \
		float(action_data.get("final_multiplier", 1.0)) * more


## 运行期条件求值：`requires_states` 里每个状态**此刻**都必须成立，否则不触发。
##
## 这一步与注册期的闸门是两件事，缺一不可：
##   注册期（TalentRegistry）问的是「引擎有没有能力判定这个条件」——判不了的卡
##   （如依赖〔双持〕的 5 张）直接拒收，根本进不了池。
##   运行期（这里）问的是「此刻条件成立不成立」——判得了但当前不成立的，跳过不触发。
## 只做前者不做后者，`condition_model=states` 的卡会在条件不成立时照常触发，
## 那正是 talent_registry.gd 头部所说「比不触发危险得多」的情形。
##
## 即时求值、不缓存，照 State 定义的「每次结算重新计算、不在进入时做快照」。
func _talent_conditions_hold(unit: Unit, trigger_row: Dictionary) -> bool:
	var required: Variant = trigger_row.get("requires_states", [])
	if not required is Array or (required as Array).is_empty():
		return true
	var state_registry: RefCounted = _ensure_state_registry()
	for item: Variant in (required as Array):
		if not state_registry.is_in_state(unit, str(item)):
			return false
	return true


## 副手追加攻击（Wave 2）。设计库二天一流的两段逐字要求：
##   effect：「执行攻击动作时，追加一次由副手武器计算的50%物理伤害。 不触发武器特效。」
##   rules ：「副手的追加伤害单独结算命中与暴击（R1.2、R1.3）；计算时只取副手武器的
##           数据，不套用主手武器的属性与特效。」
##
## ★ 刻意**不复用** `_execute_hostile_action`，而是只做 resolve → popup → take_damage
## 三步。那个函数带着八类副作用（技能效果挂载 / 剑气 / 印记 / 击杀减 CD / 词条
## on_hit+on_kill / 天赋三事件），副手若复用会把它们全部重跑一遍——剑气翻倍、上状态
## 概率翻倍（`_roll_effect_application` 会二次掷骰）、天赋触发翻倍。副手是「同一次
## 攻击动作里的第二段伤害」，不是第二次攻击动作。
##
## `action_data` 也不继承主手的：新建一份最小字典，只放副手武器三参数 + 伤害倍率 +
## 地形修正（同一个目标、同一块地形，这三项该一致），这就是「只取副手武器的数据，
## 不套用主手属性与特效」。调试确定性开关照常注入，否则 headless 测试没法确定。
##
## 击杀归属：主手没杀、副手杀了 → 在这里补发 on_kill 词条与「击杀时」天赋，
## 否则那次击杀会被整个吞掉。
func _execute_offhand_followup(attacker: Unit, defender: Unit,
		main_action_data: Dictionary, followup: Dictionary,
		action_ctx: Dictionary) -> Array:
	# 返回本次追加**自己又登记出来的**后续追加（燕返的递归链），由调用方的队列接手。
	var spawned: Array = []
	if attacker == null or defender == null:
		return spawned
	# 主手已经把目标打死了就不再追加——「追加一次伤害」的对象已经不在了。
	if not defender.stats.is_alive():
		return spawned
	if not attacker.is_dual_wielding():
		# 正常情况下走不到：注册期要求〔双持〕、分发期又求值过一次。
		# 留守卫是因为这里离条件判定隔了整个主手结算，中途状态可能已变。
		# ★ 注意这道守卫会**掩护**分发期条件求值的错误：两处都对时它是冗余的，
		# 分发期若漏判，它会把后果吞掉、外部观测不到。所以行级条件求值的正确性
		# 必须由一条**绕开本守卫**的测试来钉（见 test_talent_carrier 的
		# 「行级条件真的被用了」一组），不能指望副手追加的用例。
		return spawned
	# ── AOE 语义（2026-08-09 用户裁决）：每个目标各追加一次，且**不吃溅射衰减** ──
	#
	# `_execute_hostile_action` 被技能的 per-target 循环调用，一个 AOE 技能会对每个
	# 目标各跑一次，所以副手也对每个目标各追加一次——「追加一次」按**目标**算，
	# 不按攻击动作算。
	#
	# 「不吃溅射衰减」是**有意的**，不是漏传参数：下面构造 data 时刻意不放
	# `area_damage_multiplier`。已知后果并已被接受——主手对溅射目标会衰减，副手不会，
	# 因此在 AOE 场景下**副手对非主目标的单次伤害会高于主手**。这是设计取向
	# （双刀在 AOE 下收益显著），不是数值 bug；要改回来就改这里并同步 KB 双持章节。
	#
	# 用户在裁决时看到的对照（一发拔刀打中 3 人）：
	#   主手 8 / 4 / 4（主目标满额，其余衰减）；副手 5 / 5 / 5，副手总伤害 15。
	# 副手武器取自 **装备池**（data/equipment/，设计库那 22 把剑）——主手与副手是
	# 同一个池，二天一流只是让剑圣多用一个槽装第二把剑，不是另一套武器数据。
	#
	# ⚠ 已知不一致（登记，本波不动）：**主手**目前不走这个池，而是
	# `_get_unit_weapon_data` 按 class/enemy 档案的 weapon_id 去 data/weapons/ 取
	# 那 13 条职业固定初始武器。R1.7 说「每个单位始终持有一件武器…开局为每个单位
	# 发放一件，不由职业预先绑定」，现状与之不符。把主手迁到装备池属装备系统建设，
	# 不在 Wave 2 范围。
	var offhand: Dictionary = DataLoader.equipment.get(attacker.offhand_weapon_id, {})
	if offhand.is_empty():
		push_warning("[Offhand] %s 的副手武器「%s」在 data/equipment/ 里找不到，追加取消"
			% [attacker.unit_name, attacker.offhand_weapon_id])
		return spawned
	if not offhand.has("weapon_might"):
		push_warning("[Offhand] %s 的副手装备「%s」没有 weapon_might（不是武器？），追加取消"
			% [attacker.unit_name, attacker.offhand_weapon_id])
		return spawned

	var damage_pct: float = float(followup.get("damage_pct", 0.0))
	if damage_pct <= 0.0:
		push_warning("[Offhand] %s 的 damage_pct 非正（%s），追加取消"
			% [str(followup.get("talent_id", "")), str(damage_pct)])
		return spawned

	# damage_type 与 damage_pct 出自设计库同一句 effect（「50%物理伤害」），两个值
	# 都该从 JSON 读——一个进 JSON 一个写死在代码里是口径不一致。
	var damage_type: String = str(followup.get("damage_type", ""))
	if damage_type == "":
		push_warning("[Offhand] %s 未声明 damage_type，追加取消"
			% str(followup.get("talent_id", "")))
		return spawned
	var data: Dictionary = {
		# 不继承主手的 damage_type（主手可能是魔法技能）。
		"damage_type": damage_type,
		# ★ damage_pct 作用在**最终伤害**上（2026-08-09 用户澄清，此前反复过两次，
		#   以此为准）：**计算过程的数值一律不变，只在最后乘 0.5 结算伤害**。
		#     对： (STR + might − DEF) × … × 50%
		#     错： STR + (might × 50%) − DEF      ← 别再改回这个
		#   所以威力原样传入、不打折；weapon_hit / weapon_crit 同样原样，
		#   副手照 R1.2/R1.3 用自己的原始值独立掷骰。折算见下面的 final_multiplier。
		#
		#   武器特效带来的属性加成是**另一回事**：它按二刀开刃的 effect_scale 折算后
		#   并入 base（与技能威力同层加算，等价），再随整体吃副手的 50%。
		#   R1.7：副手威力按 `_legacy_skill_power` 同一等价桥接填入 skill_power。
		"skill_power": float(offhand.get("weapon_might", 0))
			+ _offhand_effect_might_bonus(
				offhand, damage_type, _offhand_effect_scale(attacker)),
		"weapon_hit": int(offhand.get("weapon_hit", 0)),
		"weapon_crit": int(offhand.get("weapon_crit", 0)),
		# 地形三项跟随主手（同目标同地块）。
		"terrain_evade_bonus": int(main_action_data.get("terrain_evade_bonus", 0)),
		"terrain_def_bonus": int(main_action_data.get("terrain_def_bonus", 0)),
		"terrain_res_bonus": int(main_action_data.get("terrain_res_bonus", 0)),
		# 副手的 50% 折算落在**最外层乘区**：damage_calculator 里 final_multiplier
		# 在暴击倍率之后（`final_dmg *= relic_multiplier * final_multiplier`），
		# 正是「最后乘 0.5」该在的位置。用它而不是 skill_multiplier——后者在暴击
		# 之前，虽然乘法可交换、当前结果相同，但语义上「最终伤害的 50%」就是最外层。
		"final_multiplier": damage_pct / 100.0,
		"affix_defense_multiplier": float(
			main_action_data.get("affix_defense_multiplier", 1.0)),
		# 纳刀等「自身造成的伤害」总降也作用于副手追加 [推断]；技能自己的总增（满月）不带过来（R1.13）。
		"damage_total_modifiers": _attacker_state_damage_modifiers(attacker, []),
		# ★ 刻意不放 area_damage_multiplier：2026-08-09 用户裁决「副手不吃溅射衰减」。
		# resolve_attack 缺该键时默认 1.0，正是这里想要的。别"顺手补上"。
	}
	# 剑气回荡：主手暴击强化**随后那一次**副手追加——必定暴击 + 命中后返气。
	# effect 原文说的是「该次副手的追加伤害」——单数，所以标记**消费一次就清掉**；
	# 燕返递归出来的后续几次不继承它，各自独立掷骰（燕返 rules 逐字：「每一次追加的
	# 副手伤害都各自独立结算命中与暴击」）。
	# 注意顺序：必须写在 _apply_debug_determinism 之前，否则调试「不暴」态
	# （disable_crit）会被这里覆盖，headless 用例就失去确定性。
	var empower: Dictionary = {}
	var empower_raw: Variant = action_ctx.get("offhand_empower", null)
	if empower_raw is Dictionary:
		empower = empower_raw
		action_ctx.erase("offhand_empower")
		if bool(empower.get("guaranteed_crit", false)):
			data["guaranteed_crit"] = true
	_apply_debug_determinism(data)

	# 副手独立掷骰，并按自己的结果分发两个 on-hit 事件。
	# **绝不能复用主手的 outcome**：二天一流 rules 逐字要求「副手的追加伤害单独结算
	# 命中与暴击（R1.2、R1.3）」。掷骰时点也必须留在原来 resolve_attack 那一行的
	# 位置——主手全部副作用（含 _roll_effect_application 的 randf 与 gain_random_mark
	# 的 randi）都排在它之前，提前掷会打乱全局随机序列。
	var offhand_ctx: Dictionary = {
		"defender": defender,
		"source": SOURCE_OFFHAND,
		"contexts": [CONTEXT_ACTIVE_ATTACK],
		"pending_offhand": [],
		# 燕返的链序：本次是链上第几次追加，决定它下一次的概率衰减几档。
		"offhand_chain_index": int(followup.get("chain_index", 0)),
		# 本次副手伤害规格供递归追加沿用，不在递归效果中另存一份。
		"offhand_damage_pct": damage_pct,
		"offhand_damage_type": damage_type,
		# 指回本次攻击动作的 ctx。有些效果的标记必须落在动作级而不是这一击级
		# （empower_next_offhand 就是），写在本字典上会随函数返回丢掉。
		"action_ctx": action_ctx,
	}
	var outcome: Dictionary = DamageCalculator.roll_outcome(attacker, defender, data)
	_dispatch_on_hit_events(attacker, outcome, offhand_ctx)
	_merge_on_hit_modifiers(data, offhand_ctx)

	# 主手与副手是各自结算命中与暴击的两次伤害，因此分别分发防御侧事件。
	# 同一攻击动作中，交刃可能分别为两次伤害消耗剑气。
	var offhand_defense: Dictionary = _resolve_defense(
		attacker, defender, outcome, SOURCE_OFFHAND)
	_apply_defense_to_action(data, offhand_defense)

	data["precomputed_outcome"] = outcome

	var result: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(
		attacker, defender, data)
	_record_parry_prevented(attacker, defender, data, result, offhand_defense)
	_log_attack(attacker, defender, result, "副手")
	var combat_text_anchor := defender.get_combat_text_anchor_world(-50.0)
	if result.hit:
		# segment_index=1：与主手的飘字错开，否则同坐标同帧两个数字会叠在一起。
		DamagePopup.spawn_at_anchor(popup_layer, combat_text_anchor,
			result.damage, damage_type, result.crit, 1)
		defender.take_damage(result.damage, damage_type)
	else:
		DamagePopup.spawn_miss_at_anchor(popup_layer, combat_text_anchor, 1)

	# 被强化的副手追加只在实际命中后返气：必定暴击不保证命中，
	# 副手仍按自己的命中结果结算。
	var empower_qi: int = int(empower.get("qi_on_hit", 0))
	if result.hit and empower_qi > 0:
		attacker.gain_sword_qi(empower_qi, "talent:" + str(empower.get("talent_id", "")))
		print("[Talent] %s 「%s」→ 被强化的副手追加命中 → +%d 剑气 → %d" % [
			attacker.unit_name, str(empower.get("talent_id", "")),
			empower_qi, attacker.sword_qi])

	# 副手命中后分发 after-damage 三事件；击杀链在副手造成击杀时补发。
	# 副手属于同一次攻击动作，不再次分发动作级事件或重跑主手副作用。
	offhand_ctx["result"] = result
	if result.hit:
		_dispatch_talents(attacker, "命中后", offhand_ctx)
		if result.damage > 0:
			_dispatch_talents(attacker, "造成伤害时", offhand_ctx)
	# 主手未击杀而副手击杀 → 补发击杀链，否则这次击杀无人知晓。
	if result.defender_died:
		_apply_affixes(attacker, "on_kill", {"defender": defender, "result": result})
		_dispatch_talents(attacker, "击杀时", offhand_ctx)

	for item: Variant in (offhand_ctx["pending_offhand"] as Array):
		if item is Dictionary:
			spawned.append(item)
	return spawned


## 副手武器特效当前的生效比例。0 = 不生效（二天一流「不触发武器特效」的默认态）；
## 0.5 = 二刀开刃解锁后按 50% 生效。
##
## 常驻天赋不进事件桶，得由消费方主动查——而且**常驻不等于无条件**：二刀开刃自己
## 就要求〔双持〕，所以这里除了「持有这张卡」还要走一次和分发期同样的行级条件求值。
func _offhand_effect_scale(unit: Unit) -> float:
	if unit == null or unit.talent_ids.is_empty():
		return 0.0
	var registry: RefCounted = _ensure_talent_registry()
	var scale: float = 0.0
	for talent_id: String in unit.talent_ids:
		var entry: Dictionary = registry.passive_entry(talent_id)
		if entry.is_empty():
			continue
		if not _talent_conditions_hold(unit, entry["trigger"]):
			continue
		# 与分发期同样按行取效果（常驻行恒为 "main"）——一张常驻卡若把某条效果绑给了
		# 别的行，这里不该把它也算进来。
		for item: Variant in registry.effects_for_row(
				entry["talent"] as Dictionary, str(entry.get("row", "main"))):
			if not item is Dictionary:
				continue
			var effect: Dictionary = item
			if str(effect.get("type", "")) != "unlock_offhand_weapon_effect":
				continue
			# 多张卡都解锁时取最大比例，不叠乘——「解锁」是开关，倍率取最宽松的那个。
			scale = maxf(scale, float(effect.get("effect_scale", 0.0)) / 100.0)
	return scale


## 把副手武器的属性型特效折算成可并入 skill_power 的加值。
##
## 只支持 STR / MAG 两个键：伤害公式里它们与 skill_power 是同一层加算
## （R1.1：physical = STR + 技能威力 − DEF），所以把加成并进威力与加进属性等价。
## DEX 之类不支持——它会经 R1.2/R1.3 进命中与暴击链，并进 might 就错了，
## 遇到时告警并跳过该条，不静默当 0。
func _offhand_effect_might_bonus(offhand: Dictionary, damage_type: String,
		scale: float) -> float:
	if scale <= 0.0:
		return 0.0
	var effects: Variant = offhand.get("engine_effects", [])
	if not effects is Array:
		return 0.0
	var wanted: String = "STR" if damage_type == "physical" else "MAG"
	var bonus: float = 0.0
	for item: Variant in (effects as Array):
		if not item is Dictionary:
			continue
		var effect: Dictionary = item
		if str(effect.get("type", "")) != "stat_bonus":
			push_warning("[Offhand] 武器特效类型「%s」引擎未支持，跳过"
				% str(effect.get("type", "")))
			continue
		var stat: String = str(effect.get("stat", ""))
		if stat != "STR" and stat != "MAG":
			push_warning("[Offhand] 武器特效属性「%s」暂不支持（只支持 STR / MAG——"
				% stat + "它们与 skill_power 同层加算；DEX 等会进命中/暴击链，需另接）")
			continue
		if stat != wanted:
			continue    # 物理伤害只吃 STR、魔法只吃 MAG
		bonus += float(effect.get("amount", 0)) * scale
	return bonus


## 执行一条结构化天赋效果。未知类型在注册期就已被拒收，走到这里仍要兜底告警——
## 静默 default 分支正是路径 C 留档里点名的失效模式。
func _apply_talent_effect(unit: Unit, talent_id: String,
		effect: Dictionary, ctx: Dictionary) -> void:
	var effect_type: String = str(effect.get("type", ""))
	match effect_type:
		"gain_resource":
			var resource: String = str(effect.get("resource", ""))
			var amount: int = int(effect.get("amount", 0))
			match resource:
				"qi":
					if amount <= 0:
						# gain_resource 只表达获得；扣减要走 spend / lose，数据写错时响亮告警。
						push_warning("[Talent] %s 的 gain_resource qi 数量必须为正，实际 %d，已忽略"
							% [talent_id, amount])
						return
					unit.gain_sword_qi(amount, "talent:" + talent_id)
					print("[Talent] %s 「%s」→ +%d 剑气 → %d" % [
						unit.unit_name, talent_id, amount, unit.sword_qi])
				"mark":
					for _i: int in range(amount):
						var gained: String = unit.gain_random_mark()
						if gained == "":
							break
					print("[Talent] %s 「%s」→ +%d 印记 → %d" % [
						unit.unit_name, talent_id, amount, unit.get_mark_count()])
				_:
					push_warning("[Talent] %s 的 gain_resource 资源「%s」无执行分支"
						% [talent_id, resource])
		"offhand_followup":
			# 副手追加攻击。这里**只登记待办、不立即打**——事件是「执行攻击动作时」
			# （主手结算之前），而设计库 effect 说的是「追加一次」，追加必须发生在
			# 主手那一下之后。所以在动作开头判定条件、把待办塞进 ctx，由
			# _execute_hostile_action 末尾统一执行。
			if not ctx.has("pending_offhand"):
				push_warning("[Talent] %s 的 offhand_followup 在不支持追加的时机触发（%s）"
					% [talent_id, str(ctx.keys())])
				return
			(ctx["pending_offhand"] as Array).append({
				"talent_id": talent_id,
				"damage_pct": float(effect.get("damage_pct", 0.0)),
				"damage_type": str(effect.get("damage_type", "")),
				"chain_index": 0,
			})
		"empower_next_offhand":
			# 剑气回荡：强化**随后那一次**副手追加——让它必定暴击，并在它命中后
			# 额外返气。effect 逐字：「主手暴击时，该次副手的追加伤害必定暴击且
			# 额外获得 10 点剑气」——两件事都挂在同一次副手追加上，所以做成一条
			# 效果、一个标记，读完即清（「该次」是单数，燕返再产生的后续追加不继承）。
			#
			# ★ 这不是回溯改判：作用对象是**随后另一次攻击**，不是本次。本次的
			# hit / crit 已经掷完，任何回头改它的写法都违反 R1.2 / R1.3。
			# ★ 标记必须落在**本次攻击动作**的 ctx 上。消费点在
			# _execute_offhand_followup 开头，读的是 action_ctx；副手侧分发时传进来的
			# 是临时的 offhand_ctx，写在那儿会随函数返回丢掉——静默失效。
			var owner_ctx: Variant = ctx.get("action_ctx", null)
			var target_ctx: Dictionary = owner_ctx if owner_ctx is Dictionary else ctx
			target_ctx["offhand_empower"] = {
				"guaranteed_crit": bool(effect.get("guaranteed_crit", false)),
				"qi_on_hit": int(effect.get("qi_on_hit", 0)),
				"talent_id": talent_id,
			}
			print("[Talent] %s 「%s」→ 强化随后一次副手追加（必暴=%s，命中返气=%d）" % [
				unit.unit_name, talent_id,
				str(bool(effect.get("guaranteed_crit", false))),
				int(effect.get("qi_on_hit", 0))])
		"parry_damage_reduction":
			# 交刃登记一次付费的招架减伤意图。
			#
			# ★ 这里**只登记意图、不当场结算**，同 offhand_followup 的做法。理由是
			# 「减伤每次攻击至多结算一次」这条取舍需要同时看到架势与本卡两条入口，
			# 而分发期只看得到本卡；当场扣剑气就会出现「架势本来也成功了、剑气却
			# 已经白扣」。真正的结算与扣费在 _resolve_defense 里。
			#
			# ★ 减伤幅度**不由本卡声明**（注册期已拒收 reduction_base_pct /
			# reduction_stat）：设计库逐字「按招架的减伤结算」，幅度的权威在招架
			# 架势的 parry 段，两条入口共读一份。
			if not ctx.has("pending_parry"):
				push_warning("[Talent] %s 的 parry_damage_reduction 在不支持防御反应的时机触发（%s）"
					% [talent_id, str(ctx.keys())])
				return
			(ctx["pending_parry"] as Array).append({
				"talent_id": talent_id,
				"qi_cost": int(effect.get("qi_cost", 0)),
			})
		"more_damage_from_stat":
			# R1.8 的「更多」类修正：措辞「N% 更多 X」，各条独立连乘，落伤害链最外层。
			# ★ 它**不是**「暴击倍率 ×N」那一类（拔刀走的那条），两者落层不同。
			#
			# 中间量不取整（R1.8：只有最终伤害向下取整）——死线 pct_per_point=0.5、
			# DEX=7 时系数是 3.5%，不能先取整成 3 或 4。
			var stat: String = str(effect.get("stat", ""))
			var stat_value: int = unit.get_effective_stat(stat)
			var factor: float = 1.0 + float(stat_value) \
				* float(effect.get("pct_per_point", 0.0)) / 100.0
			ctx["more_damage_multiplier"] = \
				float(ctx.get("more_damage_multiplier", 1.0)) * factor
			print("[Talent] %s 「%s」→ %s=%d → ×%.4f 更多伤害" % [
				unit.unit_name, talent_id, stat, stat_value, factor])
		"offhand_recursive_followup":
			# 燕返：副手的追加伤害命中后，按概率再追加一次。
			# 概率 = chance_stat 的当前值%，每成功追加一次再乘一次衰减系数
			# （effect 原文：「每成功追加一次，下一次的概率为上一次的 80%」）。
			#
			# 注册期已要求这条效果显式声明 self_retriggerable=true——R1.10 默认禁止
			# 自触发，豁免句要求「效果描述显式声明可以反复追加」，燕返正是那一类。
			if not ctx.has("pending_offhand"):
				push_warning("[Talent] %s 的 offhand_recursive_followup 在不支持追加的时机触发（%s）"
					% [talent_id, str(ctx.keys())])
				return
			var chain_index: int = int(ctx.get("offhand_chain_index", 0))
			var decay: float = float(effect.get("chance_decay_pct", 0.0)) / 100.0
			var base_chance: float = float(unit.get_effective_stat(
				str(effect.get("chance_stat", "")))) / 100.0
			var chance: float = base_chance * pow(decay, float(chain_index))
			if randf() >= chance:
				return
			# ★ 追加的伤害规格**沿用触发本次判定的那一次副手追加**，不由本卡声明
			# （2026-08-10 用户裁决：「燕返的追加是基于二天一流的伤害再次进行计算」）。
			# 链的源头就是二天一流那一次，所以这样天然跟随——二天一流将来改了系数，
			# 燕返自动跟着变，不会像各存一份那样静默分叉。
			var inherit_pct: float = float(ctx.get("offhand_damage_pct", 0.0))
			var inherit_type: String = str(ctx.get("offhand_damage_type", ""))
			if inherit_pct <= 0.0 or inherit_type == "":
				push_warning("[Talent] %s 无法继承副手追加的伤害规格（pct=%s type=%s），本次递归取消"
					% [talent_id, str(inherit_pct), inherit_type])
				return
			(ctx["pending_offhand"] as Array).append({
				"talent_id": talent_id,
				"damage_pct": inherit_pct,
				"damage_type": inherit_type,
				"chain_index": chain_index + 1,
			})
			print("[Talent] %s 「%s」→ 第 %d 次递归追加命中（概率 %.1f%%）" % [
				unit.unit_name, talent_id, chain_index + 1, chance * 100.0])
		_:
			push_warning("[Talent] %s 的效果类型「%s」无执行分支" % [talent_id, effect_type])


# ── 敌人词条时机分发器（触发类词条）──────────────────────
# 纯加法：无词条单位 get_affixes() 为空 → 立即 return，正式战斗零影响。
# 数值类词条（stat_scale/stat_flat/stat_pct 常驻/afs_frenzy/af_heal_resist）
# 已在 unit.gd / damage_calculator.gd 处生效；本分发器负责状态型触发时机
# 与 v0 占位词条的显式提示（不静默）。

## 时机分发：遍历 unit 的词条，type==timing 者执行效果。
func _apply_affixes(unit: Unit, timing: String, context: Dictionary) -> void:
	if unit == null:
		return
	var affixes: Array[Dictionary] = unit.get_affixes()
	if affixes.is_empty():
		return
	for affix: Dictionary in affixes:
		if str(affix.get("type", "")) != timing:
			continue
		_execute_affix_effect(unit, affix, context)


## 单个词条效果执行。v0：占位词条走显式提示分支；已在别处生效的词条走 default（不重复执行）。
## 当前无占位型时机词条（原占位词条已随其依赖系统废弃移除），所有词条均走 default。
func _execute_affix_effect(unit: Unit, affix: Dictionary, _context: Dictionary) -> void:
	var affix_id: String = str(affix.get("id", ""))
	match affix_id:
		_:
			# 已实装词条在各自 hook 真实生效，分发器不重复执行：
			#   af_vanguard→unit SPD 首回合态（round_ended 清）/
			#   afs_bulwark→_build_hostile_action_context 防御乘区 / af_heal_resist→heal() /
			#   afs_frenzy→damage_calc 输出乘区 / stat_flat·stat_pct→get_effective_stat。
			pass


## afs_bulwark（壁垒统御）：防御方所属阵营存在存活的携该词条单位 → 返回减伤乘区，否则 1.0。
## 数据定义为「为己方全体提供减伤光环」（params 仅含 ally_damage_reduction_pct，无半径字段）
## → 采「己方全队生效」，忠于词条数据（不臆造半径常量）。收集防御方阵营单位后交纯函数结算。
func _affix_bulwark_multiplier(defender: Unit) -> float:
	if defender == null:
		return 1.0
	var allies: Array = []
	for u_variant: Variant in units:
		var u: Unit = u_variant as Unit
		if u != null and u.faction == defender.faction:
			allies.append(u)
	return _compute_bulwark_multiplier(allies)


## 纯函数（可单测）：给定一组己方单位，任一存活单位携 afs_bulwark → 返回 1 - pct/100（下限 0）。
## 无携带 → 1.0（零影响）。数值 pct 从 affix params.ally_damage_reduction_pct 读。
static func _compute_bulwark_multiplier(allies: Array) -> float:
	for ally_variant: Variant in allies:
		var ally: Unit = ally_variant as Unit
		if ally == null or ally.stats == null or not ally.stats.is_alive():
			continue
		for affix: Dictionary in ally.get_affixes():
			if str(affix.get("id", "")) != "afs_bulwark":
				continue
			var pct: float = float(affix.get("params", {}).get("ally_damage_reduction_pct", 0))
			return maxf(0.0, 1.0 - pct / 100.0)
	return 1.0


## 一次性提示单位携带的 v0 占位词条（挂载但效果待后续实装；非静默）。每单位仅扫描一次。
func _notify_affix_placeholders(unit: Unit) -> void:
	if unit == null:
		return
	var affixes: Array[Dictionary] = unit.get_affixes()
	if affixes.is_empty():
		return
	var uid: int = unit.get_instance_id()
	if bool(_affix_swept_units.get(uid, false)):
		return
	_affix_swept_units[uid] = true
	for affix: Dictionary in affixes:
		var affix_id: String = str(affix.get("id", ""))
		if affix_id in _AFFIX_V0_PLACEHOLDERS:
			_affix_placeholder_notice(affix_id, "v0 声明式占位，效果待后续时机 hook 实装")


## 占位提示去重打印（push_warning + print，一 affix 仅提示一次）。
func _affix_placeholder_notice(affix_id: String, reason: String) -> void:
	if bool(_affix_placeholder_seen.get(affix_id, false)):
		return
	_affix_placeholder_seen[affix_id] = true
	push_warning("[Affix][占位] %s 未实装：%s" % [affix_id, reason])
	print("[Affix][占位] %s 未实装：%s" % [affix_id, reason])


# ── 调试 harness 公开 API（测试场景调用，正式战斗不触达）────────────

## 一键软重置：复位所有单位（满血/资源/印记/buff/冷却/站位）+ 回合状态，
## 比 reload_current_scene 快（不重新加载场景/不重建节点）。
func debug_soft_reset() -> void:
	# 1) 清交互与高亮，回到 IDLE
	_clear_hover_state()
	_clear_highlights()
	_clear_dashboard_state()
	# 2) 逐单位复位
	for u in units:
		_debug_reset_unit(u)
	# 3) 重置回合队列并从头开始（玩家回合开始）
	if battle_active:
		turn_manager.stop()
		var typed_units: Array[Unit] = []
		for u in units:
			typed_units.append(u)
		turn_manager.add_units(typed_units)
		turn_manager.start()
	_emit_dashboard_state_changed()
	print("[Debug] soft reset done (%d units)" % units.size())


## 复位单个单位：HP 满 / 剑气回职业初始 / 清印记 / 清 buff / 清冷却 / 回初始站位。
func _debug_reset_unit(unit: Unit) -> void:
	if unit == null or unit.stats == null:
		return
	# HP 满
	unit.stats.hp = unit.stats.max_hp
	unit.shield = 0
	# 行动经济复位
	unit.reset_action_resources()
	# 清冷却
	unit.skill_cooldowns.clear()
	# 清 buff（逐个 remove_buff，触发 unapply 还原属性修正）
	var buff_snapshot: Array[BuffEffect] = unit.buffs.duplicate()
	for buff: BuffEffect in buff_snapshot:
		unit.remove_buff(buff)
	unit.held_states.clear()
	# 剑圣资源：剑气回职业初始值 + 清印记（非剑圣 _qi_max==0，set_sword_qi 安全空操作）
	if unit._qi_max > 0:
		unit.clear_marks()
		var initial_qi: int = _debug_get_initial_qi(unit)
		unit.set_sword_qi(initial_qi)
	# 回初始站位
	_debug_restore_spawn_position(unit)
	unit.modulate = Color.WHITE
	unit.refresh_status_icons()
	unit._update_health_bar()


## 从职业 JSON 的 sword_qi_config.qi_initial 读初始剑气（不硬编码）。
func _debug_get_initial_qi(unit: Unit) -> int:
	var source_data: Dictionary = _get_unit_source_data(unit)
	var cfg: Dictionary = source_data.get("sword_qi_config", {})
	return clampi(int(cfg.get("qi_initial", 0)), 0, unit._qi_max)


## 把单位移回 spawn 时记录的初始格（格子被占则跳过，避免覆盖）。
func _debug_restore_spawn_position(unit: Unit) -> void:
	var key: int = unit.get_instance_id()
	if not _debug_spawn_positions.has(key):
		return
	var spawn_pos: Vector2i = _debug_spawn_positions[key]
	if not grid.is_valid(spawn_pos):
		return
	var from: Vector2i = unit.grid_position
	if from == spawn_pos:
		return
	var dest_cell: Cell = grid.get_cell(spawn_pos)
	if dest_cell != null and dest_cell.occupant != null and dest_cell.occupant != unit:
		return
	grid.move_unit(unit, from, spawn_pos)
	unit.position = grid.grid_to_world(spawn_pos)


## 切换确定性开关（开/关），返回新状态。
func debug_toggle_deterministic() -> bool:
	debug_deterministic = not debug_deterministic
	return debug_deterministic


## 循环切换暴击三态（随机 → 必暴 → 不暴 → 随机），返回新态。
func debug_cycle_crit_mode() -> CritMode:
	debug_crit_mode = ((debug_crit_mode + 1) % 3) as CritMode
	return debug_crit_mode


## 循环切换木桩行为（不动 → 自动攻击 → 不动），返回新态。
func debug_cycle_dummy_behavior() -> DummyBehavior:
	debug_dummy_behavior = ((debug_dummy_behavior + 1) % 2) as DummyBehavior
	return debug_dummy_behavior


func debug_crit_mode_label() -> String:
	match debug_crit_mode:
		CritMode.FORCE:
			return "必暴"
		CritMode.DISABLE:
			return "不暴"
		_:
			return "随机"


func _debug_dummy_behavior_label() -> String:
	match debug_dummy_behavior:
		DummyBehavior.AUTO:
			return "自动攻击"
		_:
			return "不动"


## 汇总当前调试开关状态（供 overlay 显示）。
func debug_get_status() -> Dictionary:
	return {
		"deterministic": debug_deterministic,
		"crit_mode": debug_crit_mode_label(),
		"dummy_behavior": _debug_dummy_behavior_label(),
	}


## 当前应在 overlay 详细展示的单位（行动/选中/检视单位，缺省 null）。
func debug_get_focus_unit() -> Unit:
	if _inspected_unit != null and _inspected_unit.stats.is_alive():
		return _inspected_unit
	if selected_unit != null and selected_unit.stats.is_alive():
		return selected_unit
	if current_unit != null and current_unit.stats.is_alive():
		return current_unit
	return null
