class_name TacticalManager
extends Node

@onready var turn_manager: TurnManager = $TurnManager
@onready var terrain_layer: Node2D = $TerrainLayer
@onready var highlight_layer: Node2D = $HighlightLayer
@onready var popup_layer: Node2D = $PopupLayer

var grid: Grid = Grid.new()
var units: Array = []
var battle_active: bool = false

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
enum DummyBehavior { IDLE, COUNTER_ONLY, AUTO }
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

	# ── 调试木桩行为开关：仅 AUTO 走正式敌方 AI；IDLE / COUNTER_ONLY 不主动行动 ──
	# （反击仍由 _execute_hostile_action 的现有机制处理，不受此开关影响。）
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
	var counter: bool = _can_counterattack(preview_data, target, current_unit)
	# 反击预算（目标→我方方向逆向计算）
	var counter_dmg: int = 0
	var counter_hit: int = 0
	var counter_crit: int = 0
	if counter:
		var c_action: GameAction = GameAction.make_attack(target, current_unit)
		var c_ctx: Dictionary = _build_hostile_action_context(target, current_unit, c_action.data)
		var c_prev: Dictionary = DamageCalculator.preview_attack(target, current_unit, c_ctx)
		counter_dmg = int(c_prev.get("damage", 0))
		counter_hit = int(c_prev.get("hit_percent", 0))
		counter_crit = int(c_prev.get("crit_percent", 0))
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
		"counter_expected": counter,
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
		"counter_damage": counter_dmg,
		"counter_hit_percent": counter_hit,
		"counter_crit_percent": counter_crit,
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
	var primary_counter: bool = false
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
			primary_counter = _can_counterattack(preview_data, target_unit, current_unit)
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
			primary_counter = _can_counterattack(preview_data, target_unit, current_unit)
			primary_terrain_name = str(preview.get("terrain_name", "PLAIN"))
			primary_terrain_evade = int(preview.get("terrain_evade_bonus", 0))
			primary_terrain_def = int(preview.get("terrain_def_bonus", 0))
			primary_terrain_res = int(preview.get("terrain_res_bonus", 0))
			primary_target_unit = target_unit

	if primary_per_hit == 0 and not has_first:
		primary_per_hit = first_per_hit

	# 反击预算（主目标→我方方向逆向计算）
	var counter_dmg: int = 0
	var counter_hit: int = 0
	var counter_crit: int = 0
	if primary_counter and primary_target_unit != null:
		var c_action: GameAction = GameAction.make_attack(primary_target_unit, current_unit)
		var c_ctx: Dictionary = _build_hostile_action_context(
			primary_target_unit, current_unit, c_action.data)
		var c_prev: Dictionary = DamageCalculator.preview_attack(
			primary_target_unit, current_unit, c_ctx)
		counter_dmg = int(c_prev.get("damage", 0))
		counter_hit = int(c_prev.get("hit_percent", 0))
		counter_crit = int(c_prev.get("crit_percent", 0))

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
		"counter_expected": primary_counter,
		"terrain_name": primary_terrain_name,
		"terrain_evade_bonus": primary_terrain_evade,
		"terrain_def_bonus": primary_terrain_def,
		"terrain_res_bonus": primary_terrain_res,
		# 新增：头顶数字 + FE 浮窗所需字段
		"targets": targets_list,
		"target_hp": primary_target_unit.stats.hp if primary_target_unit != null else 0,
		"target_hp_max": primary_target_unit.stats.max_hp if primary_target_unit != null else 1,
		"counter_damage": counter_dmg,
		"counter_hit_percent": counter_hit,
		"counter_crit_percent": counter_crit,
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
	if _is_support_skill(skill_data):
		print("[Skill] %s uses %s (%d target(s))" % [
			user.unit_name,
			skill_name,
			target_units.size(),
		])
		_apply_support_skill(user, skill_data, target_units)
		_spend_skill_marks(user, mark_cost)
		return true

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
	var defender_disabled_before_attack: bool = defender.has_buff("stun") \
		or defender.has_buff("freeze")
	defender.handle_attacked()

	# Main attack: calculate → popup → apply
	var result: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(
		attacker, defender, action_data)
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

	if result.defender_died:
		return

	# Counter-attack
	if _can_counterattack(action_data, defender, attacker, defender_disabled_before_attack):
		var counter_data: Dictionary = _build_basic_attack_action_data(defender, attacker, {
			"allow_counter": false,
		})
		# ── 敌人词条 af_counter_boost：反击伤害提升（真实生效 hook）──
		# 无该词条时乘区==1.0 → 反击伤害与引入前一致。
		var counter_boost: float = _affix_counter_multiplier(defender)
		if counter_boost != 1.0:
			counter_data["final_multiplier"] = \
				float(counter_data.get("final_multiplier", 1.0)) * counter_boost
			_apply_affixes(defender, "on_counter", {"target": attacker})
		var counter_result: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(
			defender, attacker, counter_data)
		_log_attack(defender, attacker, counter_result, "Counterattack")
		if counter_result.hit:
			var counter_damage_type: String = str(counter_data.get("damage_type", "physical"))
			DamagePopup.spawn(popup_layer, attacker.position,
				counter_result.damage, counter_damage_type, counter_result.crit)
			attacker.take_damage(counter_result.damage, counter_damage_type)
		else:
			DamagePopup.spawn_miss(popup_layer, attacker.position)
		if counter_result.defender_died:
			result.attacker_died = true
			return


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


func _get_skill_target_relation(skill_data: Dictionary) -> String:
	var range_data: Dictionary = skill_data.get("range", {})
	var area_data: Dictionary = skill_data.get("area", {})
	if str(range_data.get("type", "")) == "self" \
			and str(area_data.get("type", "single")) == "single":
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


func _is_ground_target_skill(skill_data: Dictionary) -> bool:
	var range_data: Dictionary = skill_data.get("range", {})
	if str(range_data.get("type", "")) == "self":
		return false
	var area_data: Dictionary = skill_data.get("area", {})
	return str(area_data.get("type", "single")) != "single"


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
	var is_area_skill: bool = area_type != "single"
	var basic_attack_profile: Dictionary = _get_unit_basic_attack_profile(user)
	var payload: Dictionary = {
		"skill_name": str(skill_data.get("name", _selected_skill_id)),
		"action_cost": str(skill_data.get("action_cost", "standard")),
		"timing_constraint": str(skill_data.get("timing_constraint", "any")),
		"swift_limit": int(skill_data.get("swift_limit", 1)),
		"cooldown": int(skill_data.get("cooldown", 0)),
		"damage_type": str(skill_data.get("damage_type", "physical")),
		"attack_type": str(skill_data.get("attack_type", "melee")),
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
		"allow_counter": not is_area_skill,
		# ── 剑圣专属字段（缺省安全，非剑圣技能此处为 0/false）──
		"skill_id": _selected_skill_id,
		"guaranteed_hit": bool(skill_data.get("guaranteed_hit", false)),
		"guaranteed_crit": bool(skill_data.get("guaranteed_crit", false)),
		"crit_damage_bonus": float(skill_data.get("crit_damage_bonus", 0.0)),
		"qi_gain_on_hit": int(skill_data.get("qi_gain_on_hit", 0)),
		"qi_gain_on_kill": int(skill_data.get("qi_gain_on_kill", 0)),
		"mark_gain": int(skill_data.get("mark_gain", 0)),
		"ki_on_kill_cd_reduction": int(skill_data.get("ki_on_kill_cd_reduction", 0)),
	}
	return GameAction.make_skill(user, _selected_skill_id, target_pos, target, payload)


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
	if action_cost not in ["move", "standard", "swift"]:
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
	if damage_type not in ["physical", "magical", "pure", "hybrid", "holy"]:
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
	# 基础攻击（普攻/反击，无 skill 的 qi 字段）按职业基础攻击产气量补默认值；
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
		"allow_counter": true,
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
		# 剑圣等职业：基础攻击（普攻/反击）命中产气，数值从职业 JSON 读，非剑圣缺省 0
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


## R1.8：武器参数唯一来源 = 所装备武器（data/weapons/，DataLoader.weapons）。
## 每单位恒持一件武器（class/enemy JSON 必须声明 weapon_id）；缺失时数据校验兜底：
## push_error 记录 + might/hit/crit 回退 0（不崩溃战斗，但日志会显眼暴露数据缺陷）。
func _get_unit_weapon_data(source_data: Dictionary, unit: Unit) -> Dictionary:
	var weapon_id: String = str(source_data.get("weapon_id", ""))
	if weapon_id == "":
		push_error("[Weapon] 单位 %s 缺少 weapon_id（每单位恒持一件武器，R1.8）" \
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


func _can_counterattack(action_data: Dictionary, defender: Unit, attacker: Unit,
		defender_disabled: bool = false) -> bool:
	if not bool(action_data.get("allow_counter", true)):
		return false
	if str(action_data.get("attack_type", "melee")) == "area":
		return false
	if defender == null or attacker == null:
		return false
	if not defender.stats.is_alive():
		return false
	if defender_disabled:
		return false
	if defender.has_buff("stun") or defender.has_buff("freeze"):
		return false
	return _is_within_basic_attack_range(defender, attacker.grid_position)


func _is_within_basic_attack_range(unit: Unit, target_pos: Vector2i) -> bool:
	var basic_attack_profile: Dictionary = _get_unit_basic_attack_profile(unit)
	var range_data: Dictionary = basic_attack_profile.get("basic_attack_range", {})
	var min_range: int = maxi(1, int(range_data.get("min", 1)))
	var max_range: int = maxi(min_range, int(range_data.get("max", min_range)))
	var distance: int = absi(unit.grid_position.x - target_pos.x) \
		+ absi(unit.grid_position.y - target_pos.y)
	return distance >= min_range and distance <= max_range


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


# ── 敌人词条时机分发器（触发类词条）──────────────────────
# 纯加法：无词条单位 get_affixes() 为空 → 立即 return，正式战斗零影响。
# 数值类词条（stat_scale/stat_flat/stat_pct 常驻/afs_frenzy/af_heal_resist/af_counter_boost）
# 已在 unit.gd / damage_calculator.gd / 反击 hook 处生效；本分发器负责状态型触发时机
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
			#   afs_frenzy→damage_calc 输出乘区 / af_counter_boost→反击乘区 / stat_flat·stat_pct→get_effective_stat。
			pass


## af_counter_boost（反击强化）：返回反击伤害乘区。无该词条 → 1.0。
func _affix_counter_multiplier(unit: Unit) -> float:
	if unit == null:
		return 1.0
	var mult: float = 1.0
	for affix: Dictionary in unit.get_affixes():
		if str(affix.get("id", "")) != "af_counter_boost":
			continue
		var params: Dictionary = affix.get("params", {})
		mult *= (1.0 + float(params.get("damage_pct", 0)) / 100.0)
	return mult


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


## 循环切换木桩行为（不动 → 只反击 → 自动攻击 → 不动），返回新态。
func debug_cycle_dummy_behavior() -> DummyBehavior:
	debug_dummy_behavior = ((debug_dummy_behavior + 1) % 3) as DummyBehavior
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
		DummyBehavior.COUNTER_ONLY:
			return "只反击"
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
