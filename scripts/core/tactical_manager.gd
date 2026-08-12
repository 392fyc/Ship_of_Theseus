class_name TacticalManager
extends Node

@onready var turn_manager: TurnManager = $TurnManager
@onready var terrain_layer: Node2D = $TerrainLayer
@onready var highlight_layer: Node2D = $HighlightLayer
@onready var popup_layer: Node2D = $PopupLayer

var grid: Grid = Grid.new()
var units: Array = []
var battle_active: bool = false
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
	grid.initialize(map_data)
	_render_terrain()
	battle_started.emit()


func start_battle() -> void:
	battle_active = true
	var typed_units: Array[Unit] = []
	for u in units:
		typed_units.append(u)
	turn_manager.add_units(typed_units)
	turn_manager.start()


func stop_battle() -> void:
	battle_active = false
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
	return {
		"visible": true,
		"mode": "enemy" if is_enemy_info else "player",
		"unit_name": info_unit.unit_name,
		"unit_label": info_unit.get_short_label(),
		"hp": info_unit.stats.hp,
		"hp_max": info_unit.stats.max_hp,
		"hp_ratio": float(info_unit.stats.hp) / maxf(1.0, float(info_unit.stats.max_hp)),
		"status_text": info_unit.get_action_status_summary(),
		"phase_text": _get_phase_text(),
		"show_actions": not is_enemy_info and _is_player_turn_active(),
		"buttons": _build_primary_button_state(),
		# B1：技能栏玩家回合常驻（去掉 _skill_bar_expanded 闸；施放后不再自动隐藏）。
		"skills_visible": not is_enemy_info and _is_player_turn_active(),
		"skills": _get_skill_entries(),
		"selected_skill_id": _selected_skill_id,
		"forecast": _combat_forecast.duplicate(true),
		"hint_text": _get_dashboard_hint_text(),
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
		"marks": info_unit.marks.duplicate() if info_unit._qi_max > 0 else {},
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


func request_end_turn() -> void:
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
				faction: String) -> Unit:
	var class_data: Dictionary = DataLoader.classes.get(class_id, {})
	if class_data.is_empty():
		class_data = DataLoader.enemies.get(class_id, {})
	if class_data.is_empty():
		push_error("[TacticalManager] Class/enemy not found: " + class_id)
		return null
	var unit_scene := preload("res://scenes/tactical/Unit.tscn")
	var unit: Unit = unit_scene.instantiate()
	unit.faction = faction
	add_child(unit)
	unit.setup(class_data)
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
	unit.process_turn_end_buffs()
	_deselect_unit()


func _on_round_ended() -> void:
	print("[TurnManager] === Round ended ===")
	# 敌人词条 af_vanguard（先手部署）：首回合（round 1）结束后关闭速度加成。
	# 无该词条单位 expire_vanguard() 为空操作 → 零影响。round 1 之后再触发亦幂等无害。
	for u_variant: Variant in units:
		var u: Unit = u_variant as Unit
		if u != null:
			u.expire_vanguard()


func _do_enemy_turn(unit: Unit) -> void:
	await get_tree().create_timer(0.3).timeout
	if not battle_active or turn_manager.current_unit != unit:
		return

	# ── 调试木桩行为开关：仅 AUTO 走正式敌方 AI；IDLE 不主动行动 ──
	# 门控：debug_harness_active=false（正式战斗）时跳过木桩逻辑，直接走敌方 AI。
	if debug_harness_active and debug_dummy_behavior != DummyBehavior.AUTO:
		print("[AI] %s: dummy behavior=%s (no proactive action)" % [
			unit.unit_name, _debug_dummy_behavior_label()])
		if battle_active and unit.stats.is_alive() \
				and turn_manager.current_unit == unit:
			turn_manager.end_current_turn()
		return

	var actions: Array[GameAction] = EnemyAI.decide_actions(unit, grid, units)

	if actions.is_empty():
		print("[AI] %s: no actions (idle)" % unit.unit_name)

	for action in actions:
		if not battle_active or turn_manager.current_unit != unit:
			break
		if not unit.stats.is_alive():
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
				await unit.move_to(action.target_pos, grid)
				grid.move_unit(unit, from, action.target_pos)
				await get_tree().create_timer(0.15).timeout
			GameAction.Type.ATTACK:
				print("[AI] %s: attack %s" % [
					unit.unit_name, action.target_unit.unit_name])
				_execute_attack_action(action)
			GameAction.Type.SKILL:
				var skill_name := str(action.data.get("skill_name", action.data.get("skill_id", "skill")))
				print("[AI] %s: skill %s" % [unit.unit_name, skill_name])
				_execute_skill_action(action)

	if battle_active and unit.stats.is_alive() \
			and turn_manager.current_unit == unit:
		turn_manager.end_current_turn()


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
		var area_direction: Vector2i = _get_skill_area_direction(
			current_unit.grid_position, _hover_cell, skill_data)
		_area_preview_cells = _compute_skill_area_cells(
			current_unit, skill_data, _hover_cell, area_direction)
		_combat_forecast = _build_skill_forecast_for_hover(_hover_cell)
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


func _build_skill_entry(unit: Unit, skill_id: String) -> Dictionary:
	var skill_data: Dictionary = _get_skill_data(skill_id)
	var cooldown_turns: int = unit.get_skill_cooldown(skill_id)
	var entry: Dictionary = {
		"skill_id": skill_id,
		"name": str(skill_data.get("name", skill_id)),
		"action_cost": str(skill_data.get("action_cost", "standard")),
		"timing_constraint": str(skill_data.get("timing_constraint", "any")),
		"swift_limit": int(skill_data.get("swift_limit", 1)),
		"cooldown": cooldown_turns,
		"cooldown_max": int(skill_data.get("cooldown", 0)),
		"description": str(skill_data.get("description", "")),
		"available": false,
		"reason": "",
		"selected": skill_id == _selected_skill_id,
		"qi_cost": int(skill_data.get("qi_cost", 0)),
		"mark_cost": int(skill_data.get("mark_cost", 0)),
		"requires_marks": int(skill_data.get("requires_marks", 0)),
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
	if qi_cost > 0 and unit.sword_qi < qi_cost:
		entry["reason"] = "剑气不足（需要 %d，当前 %d）" % [qi_cost, unit.sword_qi]
		return entry
	var requires_marks: int = int(skill_data.get("requires_marks", 0))
	if requires_marks > 0 and unit.get_mark_count() < requires_marks:
		entry["reason"] = "印记不足（需要 %d 个，当前 %d）" % [requires_marks, unit.get_mark_count()]
		return entry
	entry["available"] = true
	return entry


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
			str(slot_skill_data.get("slot_swap_target", "")))
		var entry: Dictionary = _build_skill_entry(unit, display_id)
		# 保留原始槽位 ID 以便取消时恢复（附加字段，UI 可忽略）
		entry["slot_origin_id"] = skill_id
		entries.append(entry)
	return entries


## 心眼被动条目：技能栏最左侧、不可点、无键位、无冷却（仅剑气类=剑圣）。
## 描述只放效果本体（名字由 UI 的悬停标题补「【心眼】（被动）」）。
func _build_passive_entry(unit: Unit) -> Dictionary:
	if unit._qi_max <= 0:
		return {}
	var desc: String = "每点剑气 +%d%% 暴击率；剑气达到 %d 时速度 +%d。" % [
		unit._xinyan_crit_per_qi, unit._xinyan_speed_threshold, unit._xinyan_speed_bonus]
	return {
		"skill_id": "swordsman_xinyan",
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
		"slot_origin_id": "swordsman_xinyan",
	}


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
		"swift":
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


func _has_available_swift_skill(unit: Unit) -> bool:
	for skill_id: String in unit.skill_ids:
		var skill_data: Dictionary = _get_skill_data(skill_id)
		if str(skill_data.get("action_cost", "")) != "swift":
			continue
		if _get_phase_mismatch_reason(skill_data) != "":
			continue
		if not _is_supported_runtime_skill(skill_data):
			continue
		var validation: Dictionary = GameAction.validate_skill_usage(unit, skill_data)
		if bool(validation.get("ok", false)):
			return true
	return false


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
			"world": grid.grid_to_world(target.grid_position),
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
	if grid_pos not in _attack_cells:
		return {}
	var skill_data: Dictionary = _get_skill_data(_selected_skill_id)
	if skill_data.is_empty():
		return {}
	# self / 支援（招架等）技能不做伤害 forecast。
	if _is_support_skill(skill_data) \
			or str(skill_data.get("range", {}).get("type", "")) == "self":
		return {}

	var area_direction: Vector2i = _get_skill_area_direction(
		current_unit.grid_position, grid_pos, skill_data)
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
			"world": grid.grid_to_world(target_unit.grid_position),
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
	await unit.move_to(target, grid)
	grid.move_unit(unit, from, target)
	selected_unit = current_unit
	_complete_move_phase(true)


func _execute_attack_from_input(action: GameAction) -> void:
	var previous_state: InputState = input_state
	input_state = InputState.ANIMATING
	_clear_highlights()
	_clear_targeting_buffers()
	_combat_forecast = {}
	var executed: bool = _execute_attack_action(action)
	if current_unit and current_unit.stats.is_alive() \
			and turn_manager.current_unit == current_unit:
		if executed:
			_restore_action_phase_state()
		else:
			input_state = previous_state
			_refresh_attack_cells()
			_recalculate_hover_artifacts()
			_show_attack_highlights()


func _execute_skill_from_input(action: GameAction) -> void:
	var previous_state: InputState = input_state
	input_state = InputState.ANIMATING
	_clear_highlights()
	_clear_targeting_buffers()
	_combat_forecast = {}
	var executed: bool = _execute_skill_action(action)
	if current_unit and current_unit.stats.is_alive() \
			and turn_manager.current_unit == current_unit:
		if executed:
			_handle_post_skill_execution(previous_state, action)
		else:
			input_state = previous_state
			_refresh_attack_cells()
			_recalculate_hover_artifacts()
			_show_attack_highlights()


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
			user.grid_position, target_pos, skill_data)
		area_cells = _compute_skill_area_cells(
			user, skill_data, target_pos, area_direction)
	var target_units: Array[Unit] = _get_units_in_skill_area(
		user, skill_data, area_cells)
	if not _is_ground_target_skill(skill_data) and target_units.is_empty():
		return false

	# 位移技能落点二次校验（双保险）：消耗资源前拦截无效落点 → 零消耗。
	if bool(skill_data.get("displacement", false)) \
			and not _is_displacement_landing_valid(user, target_pos):
		return false

	var action_cost: String = str(skill_data.get("action_cost", "standard"))
	var swift_limit: int = int(skill_data.get("swift_limit", 1))
	GameAction.consume_action_cost(user, action_cost, swift_limit)
	if action_cost in ["move", "standard", "swift"]:
		_move_committed = true

	# ── 剑圣资源消耗 ────────────────────────────────────
	# 剑气在施放时扣（心眼暴击的剑气时序不在本次修复范围内）。
	var qi_cost: int = int(skill_data.get("qi_cost", 0))
	if qi_cost > 0:
		user.set_sword_qi(user.sword_qi - qi_cost)
	# 修复 P0-②：印记消耗推迟到伤害结算之后再执行（见下方 _spend_skill_marks）。
	# 否则拔刀在 spend_marks 之后才结算伤害，吃不到自己正在消耗的势(STR+2)印记加成
	# （实测非暴击对 DEF2 木桩 = 25 而非应有的 29，对 30 血脆敌非暴击打不死）。
	var mark_cost: int = int(skill_data.get("mark_cost", 0))

	var cooldown_turns: int = int(data.get("cooldown", 0))
	user.consume_skill(skill_id, cooldown_turns)
	user.refresh_status_icons()
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
	# ── 位移技能（如一闪）：施放后落在所选目标格 ──
	if bool(skill_data.get("displacement", false)):
		_apply_skill_displacement(user, target_pos)
	return true


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
	var action_data: Dictionary = _build_hostile_action_context(attacker, defender, data)
	var damage_type: String = str(action_data.get("damage_type", "physical"))

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

	# ── A2（Wave 3）：先掷骰 → 发两个真 on-hit 事件 → 再算伤害 ──────────
	# 「命中时」/「暴击时」的时点在伤害数值结算**之前**（R1.4 的 on-hit），所以落在
	# 这里的天赋可以回过头改写本次伤害——死线的「该次暴击造成 (DEX/2)% 更多伤害」
	# 就是这么生效的。
	#
	# ★ `roll_outcome` 必须**恰好**在原来 `resolve_attack` 那一行的时点调用。全局
	# 随机流还有别的消费者（`_roll_effect_application` 的 randf、`gain_random_mark`
	# 的 randi 都排在本次 resolve 之后），把掷骰提前、或把主手与副手批量预掷，
	# 都会改变随机序列，让固定 seed 的用例漂移。
	#
	# ★ 钩子**不得回溯改判本次 hit / crit**，理由见 `_merge_on_hit_modifiers`。
	# 剑气回荡的「让副手那次必定暴击」作用对象是**随后另一次攻击**、不是本次，
	# 所以不构成回溯改判。
	var outcome: Dictionary = DamageCalculator.roll_outcome(
		attacker, defender, action_data)
	action_ctx["source"] = SOURCE_MAIN_HAND
	_dispatch_on_hit_events(attacker, outcome, action_ctx)
	_merge_on_hit_modifiers(action_data, action_ctx)

	# ── Wave 4：防御侧反应（受到攻击时 + 招架减伤）────────────────
	# 同一时点的另一半——攻击者的钩子写增伤，被攻击者的写减伤，两边都落
	# `final_multiplier` 且**相乘**，所以先后不影响结果。放在这里是取「离伤害数值
	# 结算最近」的位置，对应交刃 rules 的「伤害数值结算前介入」。
	var defense: Dictionary = _resolve_defense(
		attacker, defender, outcome, SOURCE_MAIN_HAND)
	_apply_defense_to_action(action_data, defense)

	action_data["precomputed_outcome"] = outcome

	# Main attack: calculate → popup → apply
	var result: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(
		attacker, defender, action_data)
	_record_parry_prevented(attacker, defender, action_data, result, defense)
	_log_attack(attacker, defender, result, "")
	if result.hit:
		DamagePopup.spawn(popup_layer, defender.position,
			result.damage, damage_type, result.crit)
		defender.take_damage(result.damage, damage_type)
	else:
		DamagePopup.spawn_miss(popup_layer, defender.position)

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

	# ── 副手追加攻击（Wave 2）：主手全部副作用结算完之后 ──────────
	# 放在最末尾是有意的——主手的 popup / 词条 / 天赋 / 剑气都已跑完，副手不打断
	# 也不穿插；主手是否击杀已判定，副手可用存活守卫天然处理「主手已杀就不追加」。
	# 燕返（Wave 3）会在自己命中后再登记新的追加，所以这里是**队列而不是递归**
	# ——用调用栈会越套越深。上限撞上时响亮告警：燕返的链长期望本就有限
	# （DEX% 起始、每成功一次 ×80% 衰减），真撞上说明参数填错了。
	var queue: Array = (action_ctx["pending_offhand"] as Array).duplicate()
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
				attacker, defender, action_data, followup, action_ctx):
			queue.append(spawned)

	# 自动反击已整体移除（2026-07-11 用户裁决）：未来以天赋/敌方特性形式回归，
	# 伤害与特效将与天赋/特性深度绑定，不预设反击框架。


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
	var relation: String = _get_skill_target_relation(skill_data)
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
			if not _roll_effect_application(target_unit, effect_data, is_hostile):
				return
			var buff: BuffEffect = _make_buff_effect_instance(user, effect_data)
			if buff != null:
				target_unit.add_buff(buff)


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


func _get_skill_area_direction(origin: Vector2i, target_pos: Vector2i,
		skill_data: Dictionary) -> Vector2i:
	var area_data: Dictionary = skill_data.get("area", {})
	if str(area_data.get("type", "")) == "line" \
			and _targeting_direction != Vector2i.ZERO:
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
		target: Unit) -> GameAction:
	if user == null or _selected_skill_id == "":
		return null
	var skill_data: Dictionary = _get_skill_data(_selected_skill_id)
	if skill_data.is_empty():
		return null
	var area_data: Dictionary = skill_data.get("area", {})
	var area_type: String = str(area_data.get("type", "single"))
	var area_direction: Vector2i = _get_skill_area_direction(
		user.grid_position, target_pos, skill_data)
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
		"weapon_might": int(basic_attack_profile.get("weapon_might", 0)),
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
		"ki_on_kill_cd_reduction": int(skill_data.get("ki_on_kill_cd_reduction", 0)),
	}
	return GameAction.make_skill(user, _selected_skill_id, target_pos, target, payload)


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
	if not action_data.has("weapon_might"):
		action_data["weapon_might"] = int(basic_attack_profile.get("weapon_might", 0))
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
	_apply_debug_determinism(action_data)
	return action_data


## 调试确定性开关注入（默认关 → 原样返回，不影响正式战斗）。
## 开时：强制命中 + 暴击三态。复用 damage_calculator 现有 guaranteed_hit/
## guaranteed_crit/disable_crit 字段，与 headless 确定性一致。
func _apply_debug_determinism(action_data: Dictionary) -> void:
	if not debug_harness_active or not debug_deterministic:
		return
	action_data["guaranteed_hit"] = true
	match debug_crit_mode:
		CritMode.FORCE:
			action_data["guaranteed_crit"] = true
			action_data["disable_crit"] = false
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
		"weapon_might": int(basic_attack_profile.get("weapon_might", 0)),
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
		attacker.set_sword_qi(attacker.sword_qi + qi_on_hit)
		print("[SwordQi] %s +%d qi on hit → %d" % [
			attacker.unit_name, qi_on_hit, attacker.sword_qi])
	# 命中后得印记（如居合 mark_gain=1，命中即结算）
	var mark_gain: int = int(action_data.get("mark_gain", 0))
	if mark_gain > 0:
		var gained_mark: String = attacker.gain_random_mark()
		if gained_mark != "":
			print("[SwordMark] %s gained mark 「%s」 on hit, total=%d" % [
				attacker.unit_name, gained_mark, attacker.get_mark_count()])
	# 击杀触发：得气 + 技能 CD 减少
	if not result.defender_died:
		return
	var qi_on_kill: int = int(action_data.get("qi_gain_on_kill", 0))
	if qi_on_kill > 0:
		attacker.set_sword_qi(attacker.sword_qi + qi_on_kill)
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


## 防御侧反应（Wave 4）：分发「受到攻击时」并结算招架减伤，返回本次的减伤结果。
##
## ★ **收件人是被攻击者**，不是攻击者。攻击链五事件全部发给攻击者，只有这一个反过来
## ——`_dispatch_talents` 的第一个参数写错就会变成「我打人时我自己的交刃触发」。
##
## 时点：命中判定之后、伤害数值结算之前。交刃 rules 逐字要求「在该次攻击判定命中后、
## 伤害数值结算前介入」，正是 Wave 3 攻击侧两阶段结构的镜像。
##
## **未命中就整个不发**：交刃 rules 逐字「攻击未命中则不触发、不消耗剑气」。把这条
## 落在最前面，剑气就不可能被白扣——不必依赖下游每个分支各自记得判一次。
##
## 返回 `{applied, multiplier, reduction_pct, via, prevented}`。`prevented`（实际减免
## 了多少伤害）要等伤害算完才知道，由 `_record_parry_prevented` 回填。
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
				defender.set_sword_qi(defender.sword_qi - qi_cost)
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
		#   所以 weapon_might 原样传入、不打折；weapon_hit / weapon_crit 同样原样，
		#   副手照 R1.2/R1.3 用自己的原始值独立掷骰。折算见下面的 final_multiplier。
		#
		#   武器特效带来的属性加成是**另一回事**：它按二刀开刃的 effect_scale 折算后
		#   并入 base（与 weapon_might 同层加算，等价），再随整体吃副手的 50%。
		"weapon_might": float(offhand.get("weapon_might", 0))
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

	# ── 副手自己掷骰、自己发两个 on-hit 事件（Wave 3）────────────
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
		# 本次追加的伤害规格。燕返再追加时**沿用它**而不是自带一份
		# （2026-08-10 用户裁决：基于二天一流的伤害再次计算）。
		"offhand_damage_pct": damage_pct,
		"offhand_damage_type": damage_type,
		# 指回本次攻击动作的 ctx。有些效果的标记必须落在动作级而不是这一击级
		# （empower_next_offhand 就是），写在本字典上会随函数返回丢掉。
		"action_ctx": action_ctx,
	}
	var outcome: Dictionary = DamageCalculator.roll_outcome(attacker, defender, data)
	_dispatch_on_hit_events(attacker, outcome, offhand_ctx)
	_merge_on_hit_modifiers(data, offhand_ctx)

	# ── Wave 4：副手这一击同样走防御侧反应 ────────────────────
	# **为什么副手也发**：副手追加是独立结算命中与暴击的一次伤害（二天一流 rules
	# 逐字），Wave 3 问题①已按这个理由裁定 on-hit 两事件主副手各发一次。防御侧是
	# 它的镜像，只发主手会在被双持者攻击时留一个**减伤打不到的洞**——那比多发一次
	# 更坏。代价是交刃在被双持者攻击时一次动作里可能扣两次剑气（每次伤害各一次），
	# 已在交付回执里登记为已知疑点。
	var offhand_defense: Dictionary = _resolve_defense(
		attacker, defender, outcome, SOURCE_OFFHAND)
	_apply_defense_to_action(data, offhand_defense)

	data["precomputed_outcome"] = outcome

	var result: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(
		attacker, defender, data)
	_record_parry_prevented(attacker, defender, data, result, offhand_defense)
	_log_attack(attacker, defender, result, "副手")
	if result.hit:
		# segment_index=1：与主手的飘字错开，否则同坐标同帧两个数字会叠在一起。
		DamagePopup.spawn(popup_layer, defender.position,
			result.damage, damage_type, result.crit, 1)
		defender.take_damage(result.damage, damage_type)
	else:
		DamagePopup.spawn_miss(popup_layer, defender.position, 1)

	# 被强化的那一次追加，命中后返气（剑气回荡）。
	# ★ 「命中才给」是引擎侧的实装判断，已回写进设计库 rules（2026-08-10）：
	# 用户改的卡面把两件事合并成一句「该次副手的追加伤害必定暴击且额外获得
	# 10 点剑气」，主语是那次追加，但没写命中与否。取「命中后结算」是因为
	# ① 改版前的卡面明确写着「命中后」，这次改的是「不依赖暴击」那一点；
	# ② 必定暴击并不保证命中——副手仍要照 R1.2 独立掷命中，miss 时暴击无意义。
	var empower_qi: int = int(empower.get("qi_on_hit", 0))
	if result.hit and empower_qi > 0:
		attacker.set_sword_qi(attacker.sword_qi + empower_qi)
		print("[Talent] %s 「%s」→ 被强化的副手追加命中 → +%d 剑气 → %d" % [
			attacker.unit_name, str(empower.get("talent_id", "")),
			empower_qi, attacker.sword_qi])

	# ── 副手的 after-damage 三事件（Wave 3 新增）──────────────
	# Wave 2 时这里**只**补发了「击杀时」，「命中后」/「造成伤害时」在副手命中时
	# 根本不发。燕返（命中后 / 副手）与剑气回荡的附加行（命中后 / 副手）都挂在这两个
	# 事件上，不补发它们就永远不触发——这是 trigger_source 接线之外，副手侧的另一半
	# 缺口。
	#
	# 补的只有**天赋事件**。主手那一套副作用（技能效果挂载 / 剑气 / 印记 / 击杀减 CD）
	# 仍然不重跑：副手是「同一次攻击动作里的第二段伤害」，不是第二次攻击动作
	# ——按 R1.10，挂在「执行攻击动作时」的效果一次攻击动作只触发一次，所以副手也
	# 不发那个事件（否则二天一流会自己再登记一次追加，成死循环）。
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


## 把副手武器的属性型特效折算成可并入 weapon_might 的加值。
##
## 只支持 STR / MAG 两个键：伤害公式里它们与 weapon_might 是同一层加算
## （R1.1：physical = STR + might − DEF），所以把加成并进 might 与加进属性等价。
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
				% stat + "它们与 weapon_might 同层加算；DEX 等会进命中/暴击链，需另接）")
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
					unit.set_sword_qi(unit.sword_qi + amount)
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
			# 交刃（Wave 4）：花剑气买一次必定的招架减伤。
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
	# 行动经济复位
	unit.reset_action_resources()
	# 清冷却
	unit.skill_cooldowns.clear()
	# 清 buff（逐个 remove_buff，触发 unapply 还原属性修正）
	var buff_snapshot: Array[BuffEffect] = unit.buffs.duplicate()
	for buff: BuffEffect in buff_snapshot:
		unit.remove_buff(buff)
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
