extends Node2D
## TacticalScene controller: spawns units, starts battle, handles victory/defeat.

@onready var tactical_manager: TacticalManager = $TacticalManager
@onready var result_overlay: ColorRect = $UILayer/ResultOverlay
@onready var result_label: Label = $UILayer/ResultLabel
@onready var return_button: Button = $UILayer/ReturnButton

# 伤害预测浮窗脚本用 preload 引用（headless --script 不刷新全局 class_name 缓存；
# class_name DamageForecaster 仍在文件内声明，编辑器/真机可全局引用）。
const DamageForecasterScript: GDScript = preload("res://scripts/ui/damage_forecaster.gd")

var _turn_order_bar: TurnOrderBar = null
var _bottom_dashboard: BottomDashboard = null
# 伤害预测浮窗（v3）：浮于悬停目标格上方，独立 CanvasLayer 宿主（屏幕空间）。
var _forecaster_layer: CanvasLayer = null
var _damage_forecaster: Control = null
# 浮窗锚到目标格上方的纵向间距（格中心上方留出 ~半格 + 浮窗高 + 三角）。
const FORECASTER_ANCHOR_OFFSET_Y: float = 36.0
var _camera: Camera2D = null
var _is_panning: bool = false
var _pan_button: int = -1
var _left_pan_candidate: bool = false
var _right_pan_candidate: bool = false
var _left_press_position: Vector2 = Vector2.ZERO
var _right_press_position: Vector2 = Vector2.ZERO
const PAN_DRAG_THRESHOLD: float = 8.0

signal battle_ended(result: String)

# ── Spawn configuration ──────────────────────────────

const PLAYER_UNITS: Array[Dictionary] = [
	# 测试场景：仅剑圣，便于专注验证剑气/印记/技能手感
	{"class_id": "swordsman", "pos": Vector2i(1, 2)},
]

const ENEMY_UNITS: Array[Dictionary] = [
	{"class_id": "goblin_melee",  "pos": Vector2i(6, 3)},
	{"class_id": "goblin_archer", "pos": Vector2i(6, 5)},
]

var _battle_over: bool = false
var _turn_order_scene: PackedScene = preload("res://scenes/tactical/TurnOrderBar.tscn")
var _bottom_dashboard_scene: PackedScene = preload("res://scenes/tactical/bottom_dashboard.tscn")

# ── 调试 harness（默认开启于测试场景；纯加法、不影响正式战斗逻辑）──────
## 是否启用调试 harness（快捷键 + overlay）。本测试场景默认 true；
## 正式战斗场景若复用此脚本，可在实例化后置 false 关闭。
@export var debug_harness_enabled: bool = true
var _debug_overlay: CanvasLayer = null
var _debug_status_label: Label = null
var _debug_state_label: Label = null
# 调试快捷键 InputMap 动作名（物理键码避让 1-4/鼠标中键）。
const DEBUG_ACTIONS: Dictionary = {
	"debug_soft_reset":   KEY_R,
	"debug_determinism":  KEY_F,
	"debug_crit_cycle":   KEY_C,
	"debug_dummy_cycle":  KEY_B,
}


func _ready() -> void:
	for slot_index: int in range(1, 5):
		var action_name: String = "skill_slot_%d" % slot_index
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
			var ev: InputEventKey = InputEventKey.new()
			ev.physical_keycode = KEY_1 + (slot_index - 1)
			InputMap.action_add_event(action_name, ev)
	if debug_harness_enabled:
		_register_debug_actions()
		tactical_manager.debug_harness_active = true
	_setup_camera()
	tactical_manager.initialize_battle("test_arena")

	for cfg: Dictionary in PLAYER_UNITS:
		var pos: Vector2i = cfg["pos"]
		tactical_manager.spawn_unit(cfg["class_id"], pos, "player")

	for cfg: Dictionary in ENEMY_UNITS:
		var pos: Vector2i = cfg["pos"]
		tactical_manager.spawn_unit(cfg["class_id"], pos, "enemy")

	print("[TacticalScene] Units spawned: %d" % tactical_manager.units.size())

	tactical_manager.unit_killed.connect(_on_unit_killed)

	_turn_order_bar = _turn_order_scene.instantiate()
	$UILayer.add_child(_turn_order_bar)
	_bottom_dashboard = _bottom_dashboard_scene.instantiate()
	$UILayer.add_child(_bottom_dashboard)
	_build_damage_forecaster()
	tactical_manager.turn_manager.queue_changed.connect(_refresh_turn_order)
	tactical_manager.turn_manager.turn_started.connect(_on_turn_changed)
	tactical_manager.turn_manager.turn_ended.connect(_on_turn_changed)
	tactical_manager.dashboard_state_changed.connect(_refresh_dashboard)
	_bottom_dashboard.attack_requested.connect(_on_attack_requested)
	_bottom_dashboard.skill_toggle_requested.connect(_on_skill_toggle_requested)
	_bottom_dashboard.skill_selected.connect(_on_skill_selected)
	_bottom_dashboard.end_turn_requested.connect(_on_end_turn_requested)
	_bottom_dashboard.end_move_requested.connect(_on_end_move_requested)
	_bottom_dashboard.cancel_requested.connect(_on_cancel_requested)
	return_button.pressed.connect(_on_return_pressed)

	result_overlay.visible = false
	result_label.visible = false
	return_button.visible = false

	_refresh_dashboard()
	tactical_manager.start_battle()

	if debug_harness_enabled:
		_build_debug_overlay()
		_refresh_debug_overlay()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		match mouse_event.button_index:
			MOUSE_BUTTON_LEFT:
				if _should_ignore_board_pointer():
					return
				if mouse_event.pressed:
					_left_pan_candidate = true
					_left_press_position = mouse_event.position
					get_viewport().set_input_as_handled()
				else:
					if _left_pan_candidate and not (_is_panning and _pan_button == MOUSE_BUTTON_LEFT):
						tactical_manager.handle_pointer_click(mouse_event.position)
						get_viewport().set_input_as_handled()
					_left_pan_candidate = false
					if _pan_button == MOUSE_BUTTON_LEFT:
						_is_panning = false
						_pan_button = -1
			MOUSE_BUTTON_MIDDLE:
				_is_panning = mouse_event.pressed
				_pan_button = MOUSE_BUTTON_MIDDLE if mouse_event.pressed else -1
			MOUSE_BUTTON_RIGHT:
				if mouse_event.pressed:
					_right_pan_candidate = true
					_right_press_position = mouse_event.position
					_is_panning = false
				else:
					if _right_pan_candidate and not (_is_panning and _pan_button == MOUSE_BUTTON_RIGHT):
						tactical_manager.request_cancel_action()
					_right_pan_candidate = false
					if _pan_button == MOUSE_BUTTON_RIGHT:
						_is_panning = false
						_pan_button = -1
	elif event is InputEventMouseMotion:
		var motion_event: InputEventMouseMotion = event
		if _left_pan_candidate \
				and motion_event.position.distance_to(_left_press_position) > PAN_DRAG_THRESHOLD:
			_is_panning = true
			_pan_button = MOUSE_BUTTON_LEFT
		if _right_pan_candidate \
				and motion_event.position.distance_to(_right_press_position) > PAN_DRAG_THRESHOLD:
			_is_panning = true
			_pan_button = MOUSE_BUTTON_RIGHT
		if _camera != null and _is_panning:
			_camera.position -= motion_event.relative
			get_viewport().set_input_as_handled()
		elif not _should_ignore_board_pointer():
			tactical_manager.handle_pointer_hover(motion_event.position)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE and not mouse_event.pressed:
			_is_panning = false
			_pan_button = -1
	if debug_harness_enabled and _handle_debug_input(event):
		get_viewport().set_input_as_handled()
		return
	for slot_index: int in range(1, 5):
		if event.is_action_pressed("skill_slot_%d" % slot_index):
			_try_trigger_skill_slot(slot_index)
			get_viewport().set_input_as_handled()
			return


# ── Victory / Defeat ─────────────────────────────────

func _on_turn_changed(_unit: Unit) -> void:
	_refresh_turn_order()
	_refresh_dashboard()


func _refresh_turn_order() -> void:
	if _turn_order_bar == null:
		return
	var queue := tactical_manager.turn_manager.get_display_queue()
	_turn_order_bar.update_queue(queue,
		tactical_manager.turn_manager.current_unit)


func _refresh_dashboard() -> void:
	if _bottom_dashboard == null:
		return
	_bottom_dashboard.update_state(tactical_manager.get_dashboard_data())
	_update_damage_forecaster()


# ── 伤害预测浮窗（浮于悬停目标格上方）─────────────────────
# 宿主独立 CanvasLayer（屏幕空间），仅瞄准态 + forecast.visible 时显示；
# 位置 = 悬停格世界坐标 → 经相机 canvas 变换转屏幕坐标。

func _build_damage_forecaster() -> void:
	_forecaster_layer = CanvasLayer.new()
	# 在 UILayer 之上，确保浮窗压住战场但不挡底栏交互（浮窗自身 mouse ignore）。
	_forecaster_layer.layer = 6
	add_child(_forecaster_layer)
	_damage_forecaster = DamageForecasterScript.new()
	_damage_forecaster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_forecaster.visible = false
	_forecaster_layer.add_child(_damage_forecaster)


func _update_damage_forecaster() -> void:
	if _damage_forecaster == null:
		return
	var data: Dictionary = tactical_manager.get_dashboard_data()
	var forecast: Dictionary = data.get("forecast", {})
	var show: bool = tactical_manager.is_targeting_active() \
		and bool(forecast.get("visible", false))
	if not show:
		_damage_forecaster.visible = false
		return
	var hover: Dictionary = tactical_manager.get_hover_world_pos()
	if not bool(hover.get("has", false)):
		_damage_forecaster.visible = false
		return

	_damage_forecaster.set_forecast(forecast)
	var world: Vector2 = hover.get("world", Vector2.ZERO)
	var screen: Vector2 = _world_to_screen(world)
	# 锚到目标格上方：x 居中浮窗、底部三角尖对准格中心上方。
	var panel_size: Vector2 = DamageForecasterScript.PANEL_SIZE
	var pos: Vector2 = Vector2(
		screen.x - panel_size.x * 0.5,
		screen.y - FORECASTER_ANCHOR_OFFSET_Y - panel_size.y - DamageForecasterScript.TRIANGLE_H)
	# 夹在视口内，避免出界（顶端/左右）。
	var vp: Vector2 = get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, 4.0, maxf(4.0, vp.x - panel_size.x - 4.0))
	pos.y = maxf(4.0, pos.y)
	_damage_forecaster.position = pos
	_damage_forecaster.visible = true


## 世界坐标 → 屏幕坐标（经视口 canvas 变换，含相机平移/缩放）。
func _world_to_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos


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
	return_button.visible = true

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


func _on_return_pressed() -> void:
	get_tree().reload_current_scene()


func _on_skill_selected(skill_id: String) -> void:
	tactical_manager.request_skill_selection(skill_id)


func _on_attack_requested() -> void:
	tactical_manager.request_attack_targeting()


func _on_skill_toggle_requested() -> void:
	tactical_manager.request_toggle_skill_bar()


func _on_end_turn_requested() -> void:
	tactical_manager.request_end_turn()


func _on_end_move_requested() -> void:
	tactical_manager.request_end_move()


func _on_cancel_requested() -> void:
	tactical_manager.request_cancel_action()


func _try_trigger_skill_slot(slot_index: int) -> void:
	var data: Dictionary = tactical_manager.get_dashboard_data()
	if not bool(data.get("visible", false)):
		return
	if str(data.get("mode", "player")) != "player":
		return
	if not bool(data.get("show_actions", false)):
		return
	var entries: Array = data.get("skills", [])
	var idx: int = slot_index - 1
	if idx < 0 or idx >= entries.size():
		return
	var entry: Dictionary = entries[idx]
	if not bool(entry.get("available", false)):
		return
	_on_skill_selected(str(entry.get("skill_id", "")))


func _setup_camera() -> void:
	_camera = Camera2D.new()
	_camera.enabled = true
	_camera.position = Vector2(0.0, 0.0)
	add_child(_camera)


func _should_ignore_board_pointer() -> bool:
	var hovered_control: Control = get_viewport().gui_get_hovered_control()
	return hovered_control != null


# ── 调试 harness ─────────────────────────────────────
# 纯加法调试增项：键盘驱动，默认仅在 debug_harness_enabled 下生效。
# 键位避让 1-4(skill_slot) / 鼠标中键(平移)：
#   R=软重置  F=确定性开关  C=暴击态循环  B=木桩行为循环

const DEBUG_OVERLAY_LAYER: int = 50
const DEBUG_PANEL_POS: Vector2 = Vector2(12.0, 12.0)
const DEBUG_PANEL_MIN_SIZE: Vector2 = Vector2(232.0, 0.0)
const DEBUG_FONT_SIZE: int = 12
const DEBUG_HELP_TEXT: String = "[调试 Harness]  R 软重置  F 确定性  C 暴击态  B 木桩行为｜技能 1-4 选中后点目标格执行"


func _register_debug_actions() -> void:
	for action_value: Variant in DEBUG_ACTIONS.keys():
		var action_name: String = str(action_value)
		if InputMap.has_action(action_name):
			continue
		InputMap.add_action(action_name)
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = int(DEBUG_ACTIONS[action_name])
		InputMap.action_add_event(action_name, ev)


func _handle_debug_input(event: InputEvent) -> bool:
	if _battle_over:
		return false
	if event.is_action_pressed("debug_soft_reset"):
		tactical_manager.debug_soft_reset()
		_refresh_debug_overlay()
		return true
	if event.is_action_pressed("debug_determinism"):
		var on: bool = tactical_manager.debug_toggle_deterministic()
		print("[Debug] deterministic = %s" % str(on))
		_refresh_debug_overlay()
		return true
	if event.is_action_pressed("debug_crit_cycle"):
		tactical_manager.debug_cycle_crit_mode()
		print("[Debug] crit mode = %s" % tactical_manager.debug_crit_mode_label())
		_refresh_debug_overlay()
		return true
	if event.is_action_pressed("debug_dummy_cycle"):
		tactical_manager.debug_cycle_dummy_behavior()
		print("[Debug] dummy behavior = %s" % tactical_manager.debug_get_status().get("dummy_behavior", ""))
		_refresh_debug_overlay()
		return true
	return false


func _build_debug_overlay() -> void:
	if _debug_overlay != null:
		return
	_debug_overlay = CanvasLayer.new()
	_debug_overlay.layer = DEBUG_OVERLAY_LAYER
	add_child(_debug_overlay)

	var panel: PanelContainer = PanelContainer.new()
	panel.position = DEBUG_PANEL_POS
	panel.custom_minimum_size = DEBUG_PANEL_MIN_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.08, 0.82)
	bg.set_content_margin_all(8.0)
	bg.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", bg)
	_debug_overlay.add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	var help: Label = _make_debug_label(DEBUG_HELP_TEXT, Color(1.0, 0.92, 0.45))
	vbox.add_child(help)

	_debug_state_label = _make_debug_label("", Color(0.62, 0.92, 1.0))
	vbox.add_child(_debug_state_label)

	_debug_status_label = _make_debug_label("", Color(0.82, 0.86, 0.92))
	vbox.add_child(_debug_status_label)


func _make_debug_label(text: String, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", DEBUG_FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _process(_delta: float) -> void:
	if debug_harness_enabled and _debug_overlay != null and not _battle_over:
		_refresh_debug_overlay()


func _refresh_debug_overlay() -> void:
	if _debug_state_label == null or _debug_status_label == null:
		return
	var status: Dictionary = tactical_manager.debug_get_status()
	var det_text: String = "开" if bool(status.get("deterministic", false)) else "关"
	_debug_state_label.text = "确定性: %s   暴击: %s   木桩: %s" % [
		det_text,
		str(status.get("crit_mode", "随机")),
		str(status.get("dummy_behavior", "不动")),
	]
	_debug_status_label.text = _build_debug_unit_status()


func _build_debug_unit_status() -> String:
	var unit: Unit = tactical_manager.debug_get_focus_unit()
	if unit == null:
		return "(无聚焦单位)"
	var lines: PackedStringArray = []
	lines.append("%s  HP %d/%d" % [unit.unit_name, unit.stats.hp, unit.stats.max_hp])
	if unit._qi_max > 0:
		lines.append("剑气 %d/%d   印记 %s" % [
			unit.sword_qi, unit._qi_max, _format_marks(unit)])
	lines.append("Buff: " + _format_buffs(unit))
	lines.append("冷却: " + _format_cooldowns(unit))
	return "\n".join(lines)


func _format_marks(unit: Unit) -> String:
	var held: PackedStringArray = []
	for mark_key: String in ["心", "道", "势"]:
		if bool(unit.marks.get(mark_key, false)):
			held.append(mark_key)
	if held.is_empty():
		return "无"
	return "".join(held)


func _format_buffs(unit: Unit) -> String:
	if unit.buffs.is_empty():
		return "无"
	var parts: PackedStringArray = []
	for buff: BuffEffect in unit.buffs:
		if buff.duration > 0:
			parts.append("%s(%d)" % [buff.buff_id, buff.duration])
		else:
			parts.append(buff.buff_id)
	return ", ".join(parts)


func _format_cooldowns(unit: Unit) -> String:
	if unit.skill_cooldowns.is_empty():
		return "无"
	var parts: PackedStringArray = []
	for skill_id_value: Variant in unit.skill_cooldowns.keys():
		var skill_id: String = str(skill_id_value)
		var skill_name: String = _skill_display_name(skill_id)
		parts.append("%s:%d" % [skill_name, int(unit.skill_cooldowns[skill_id])])
	return ", ".join(parts)


## 把裸 skill_id 映射为技能中文名（从技能数据读 name，不硬编码）。
func _skill_display_name(skill_id: String) -> String:
	var skill_data: Dictionary = tactical_manager._get_skill_data(skill_id)
	return str(skill_data.get("name", skill_id))
