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
# 头顶数字节点池（浮于各受影响目标头顶，持续显示至瞄准结束）。
var _forecast_head_nodes: Array[Node] = []
# 浮窗锚到目标格上方的纵向间距（格中心上方留出 ~半格 + 浮窗高 + 三角）。
const FORECASTER_ANCHOR_OFFSET_Y: float = 36.0
# 浮窗在头顶数字上方的额外净空（浮窗底边不压头顶数字）。
const FORECASTER_HEAD_CLEARANCE: float = 28.0
var _camera: Camera2D = null
var _is_panning: bool = false
var _pan_button: int = -1
var _left_pan_candidate: bool = false
var _right_pan_candidate: bool = false
var _left_press_position: Vector2 = Vector2.ZERO
var _right_press_position: Vector2 = Vector2.ZERO
const PAN_DRAG_THRESHOLD: float = 8.0

signal battle_ended(result: String)

# ── run-loop 注入模式（纯加法门控；run_injected=false 时行为完全不变）──────
## 由 RunScene 宿主在实例化后（add_child 前）置 true：跳过 PLAYER_UNITS/ENEMY_UNITS
## 硬编码清单，改用下方注入字段 spawn，并为敌人注入词条（玩家不注入）。
## 注入模式下 ReturnButton 不 reload，改由宿主经 battle_ended 信号接管流转。
@export var run_injected: bool = false
var injected_map_id: String = ""
## 元素 Dictionary：{ class_id:String, pos:Vector2i, level?:int }
var injected_player_units: Array = []
## 元素 Dictionary：{ class_id:String, pos:Vector2i, affixes?:Array, special_affix?, stat_scale?:float }
var injected_enemy_units: Array = []

# ── Spawn configuration ──────────────────────────────

const PLAYER_UNITS: Array[Dictionary] = [
	# 测试场景：仅剑圣，便于专注验证剑气/印记/技能手感
	{"class_id": "kensei", "pos": Vector2i(1, 2), "facing": &"SE"},
]

# ── 敌人列表（木桩场景 B=不动 与 受击场景 B=自动攻击 共用，可增删）──
# 先配火纹三系：枪兵(近战物理) / 弓箭手(远程物理) / 法师(魔法近远)。
# 数值见 data/enemies/test_*.json（测试占位，可调）。受击场景按 B 切到「自动攻击」即由 EnemyAI 驱动逼近+攻击。
const ENEMY_UNITS: Array[Dictionary] = [
	{"class_id": "test_lancer",        "pos": Vector2i(5, 2)},  # 枪兵 近战物理(距1)
	{"class_id": "test_archer",        "pos": Vector2i(6, 4)},  # 弓箭手 远程物理(距2-3)
	{"class_id": "test_mage",          "pos": Vector2i(6, 1)},  # 法师 魔法(距1-2)
	{"class_id": "test_dummy_regen",   "pos": Vector2i(5, 5)},  # 不灭木桩 回合末回满血
	{"class_id": "test_dummy_revive",  "pos": Vector2i(2, 5)},  # 复活木桩 死亡后回合末复活
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
# 控制台面板及按钮引用（·键切换显隐，按钮替代原 R/F/C/B 快捷键）。
var _debug_console_panel: PanelContainer = null
var _btn_soft_reset: Button = null
var _btn_determinism: Button = null
var _btn_crit: Button = null
var _btn_dummy: Button = null
# 调试快捷键：仅·键（KEY_QUOTELEFT）切换控制台显隐（避让 1-4/鼠标中键）。
const DEBUG_ACTIONS: Dictionary = {
	"debug_console_toggle": KEY_QUOTELEFT,
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
		tactical_manager.turn_manager.round_ended.connect(_process_test_dummies)
	_setup_camera()
	if run_injected:
		_spawn_injected_units()
	else:
		tactical_manager.initialize_battle("test_arena")

		for cfg: Dictionary in PLAYER_UNITS:
			var pos: Vector2i = cfg["pos"]
			var facing := StringName(str(cfg.get("facing", "SE")))
			tactical_manager.spawn_unit(
				str(cfg.get("class_id", "")), pos, "player", facing)

		for cfg: Dictionary in ENEMY_UNITS:
			var pos: Vector2i = cfg["pos"]
			var facing := StringName(str(cfg.get("facing", "SE")))
			tactical_manager.spawn_unit(
				str(cfg.get("class_id", "")), pos, "enemy", facing)

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


## 注入模式 spawn（仅 run_injected 时调用）：读注入清单走正式 spawn_unit 路径；
## 敌人 spawn 后调 apply_affixes 注入词条与数值增强（玩家不注入词条）。纯加法。
func _spawn_injected_units() -> void:
	tactical_manager.initialize_battle(injected_map_id)
	for cfg_v: Variant in injected_player_units:
		if not (cfg_v is Dictionary):
			continue
		var cfg: Dictionary = cfg_v
		var pos: Vector2i = cfg.get("pos", Vector2i.ZERO)
		var facing := StringName(str(cfg.get("facing", "SE")))
		var player_unit: Unit = tactical_manager.spawn_unit(
			str(cfg.get("class_id", "")), pos, "player", facing)
		# HP 跨关继承（磨损模型 #8）：注入项带 hp 时按磨损/战死规则落地不满血入场。
		# 无 hp 字段（首关或满血）→ 缺省满血，不改动。玩家不涉词条注入。
		if player_unit != null and cfg.has("hp"):
			_apply_injected_hp(player_unit, int(cfg.get("hp", 0)))
	for cfg_v: Variant in injected_enemy_units:
		if not (cfg_v is Dictionary):
			continue
		var cfg: Dictionary = cfg_v
		var pos: Vector2i = cfg.get("pos", Vector2i.ZERO)
		var facing := StringName(str(cfg.get("facing", "SE")))
		var enemy_unit: Unit = tactical_manager.spawn_unit(
			str(cfg.get("class_id", "")), pos, "enemy", facing)
		if enemy_unit == null:
			continue
		var affixes_v: Variant = cfg.get("affixes", [])
		var affixes: Array = affixes_v if affixes_v is Array else []
		var special_affix: Variant = cfg.get("special_affix", null)
		var stat_scale: float = float(cfg.get("stat_scale", 1.0))
		enemy_unit.apply_affixes(affixes, special_affix, stat_scale, DataLoader.affixes)


## 应用注入的继承 HP（磨损模型 #8）。规则：
##   inj_hp <= 0        → hp=1 入场（[占位] v0 无永久死亡，战死角色以 1 血复出）。
##   0 < inj_hp < max_hp → hp=inj_hp（不满血入场，体现磨损）。
##   inj_hp >= max_hp   → 不改动（维持 spawn 后满血）。
## 直接写 stats.hp 并刷新血条，不经 take_damage（避免触发受击飘字/死亡链）。
func _apply_injected_hp(unit: Unit, inj_hp: int) -> void:
	if unit.stats == null:
		return
	var max_hp: int = unit.stats.max_hp
	if inj_hp <= 0:
		unit.stats.hp = 1
	elif inj_hp < max_hp:
		unit.stats.hp = inj_hp
	else:
		return
	unit._update_health_bar()


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


## 清除所有头顶数字节点（瞄准结束或重新计算时调用）。
func _clear_forecast_head_nodes() -> void:
	for n: Node in _forecast_head_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_forecast_head_nodes.clear()


## 为每个受影响目标在其头顶显示「类型字形 + 伤害数字」预览节点。
## 复用 DamagePopup.compose + _Glyph 样式，与造成伤害飘字视觉一致。
func _spawn_forecast_head_nodes(targets: Array) -> void:
	for t: Variant in targets:
		if not (t is Dictionary):
			continue
		var target_dict: Dictionary = t
		var world: Vector2 = target_dict.get("world", Vector2.ZERO)
		var dmg: int = int(target_dict.get("damage", 0))
		var dtype: String = str(target_dict.get("damage_type", "physical"))
		var parts: Dictionary = DamagePopup.compose(dmg, dtype, false)
		var screen: Vector2 = _world_to_screen(world)
		# world 已是 Unit 提供的最终锚点，不再叠加旧版纵向偏移。
		var base_pos: Vector2 = screen

		# 字形节点
		var shape: String = str(parts.get("shape", "sword"))
		if shape != "none":
			var glyph: Control = DamagePopup._Glyph.new()
			glyph.shape = shape
			glyph.color = parts.get("color", Color.WHITE)
			glyph.custom_minimum_size = Vector2(DamagePopup.GLYPH_SIZE, DamagePopup.GLYPH_SIZE)
			glyph.size = Vector2(DamagePopup.GLYPH_SIZE, DamagePopup.GLYPH_SIZE)
			glyph.position = base_pos + Vector2(-DamagePopup.GLYPH_SIZE - DamagePopup.GLYPH_GAP, -DamagePopup.GLYPH_SIZE * 0.5)
			glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_forecaster_layer.add_child(glyph)
			_forecast_head_nodes.append(glyph)

		# 数字标签
		var txt: String = str(parts.get("text", str(dmg)))
		var fs: int = int(parts.get("size", DamagePopup.NORMAL_SIZE))
		var col: Color = parts.get("color", Color.WHITE)
		var lbl: Label = Label.new()
		lbl.text = txt
		lbl.add_theme_font_size_override("font_size", fs)
		lbl.add_theme_color_override("font_color", col)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.size = Vector2(float(txt.length()) * float(fs) + 24.0, float(fs) + 10.0)
		lbl.position = base_pos + Vector2(-lbl.size.x * 0.5, -lbl.size.y * 0.5)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_forecaster_layer.add_child(lbl)
		_forecast_head_nodes.append(lbl)


func _update_damage_forecaster() -> void:
	if _damage_forecaster == null:
		return
	var data: Dictionary = tactical_manager.get_dashboard_data()
	var forecast: Dictionary = data.get("forecast", {})
	var show: bool = tactical_manager.is_targeting_active() \
		and bool(forecast.get("visible", false))
	if not show:
		_damage_forecaster.visible = false
		_clear_forecast_head_nodes()
		return
	var hover: Dictionary = tactical_manager.get_hover_world_pos()
	if not bool(hover.get("has", false)):
		_damage_forecaster.visible = false
		_clear_forecast_head_nodes()
		return

	# 更新头顶数字（先清再建）
	_clear_forecast_head_nodes()
	var targets: Array = forecast.get("targets", [])
	if not targets.is_empty():
		_spawn_forecast_head_nodes(targets)

	_damage_forecaster.set_forecast(forecast)
	var world: Vector2 = hover.get("world", Vector2.ZERO)
	var screen: Vector2 = _world_to_screen(world)
	# 锚到目标格上方：x 居中浮窗、底部三角尖对准格中心上方（额外加头顶数字净空）。
	var panel_size: Vector2 = DamageForecasterScript.PANEL_SIZE
	var pos: Vector2 = Vector2(
		screen.x - panel_size.x * 0.5,
		screen.y - FORECASTER_ANCHOR_OFFSET_Y - FORECASTER_HEAD_CLEARANCE - panel_size.y - DamageForecasterScript.TRIANGLE_H)
	# 夹在视口内，避免出界（顶端/左右）。
	var vp: Vector2 = get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, 4.0, maxf(4.0, vp.x - panel_size.x - 4.0))
	# 底部避让：浮窗底边不得压到底栏内容区（人物属性栏等）。目标在棋盘下方时上移。
	if _bottom_dashboard != null and _bottom_dashboard.has_method("get_content_top_y"):
		var dash_top: float = _bottom_dashboard.get_content_top_y()
		if dash_top > 0.0:
			pos.y = minf(pos.y, dash_top - panel_size.y - 6.0)
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
	if run_injected:
		# 注入模式：宿主(RunScene)经 battle_ended 信号接管流转，不自行 reload。
		return
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
	# 键 1-4 仅对应「主动」技能（跳过心眼等被动条目），与技能栏键位角标 1-4 一致。
	var active: Array = []
	for e: Dictionary in entries:
		if not bool(e.get("is_passive", false)):
			active.append(e)
	var idx: int = slot_index - 1
	if idx < 0 or idx >= active.size():
		return
	var entry: Dictionary = active[idx]
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
# 纯加法调试增项：·键（`）呼出按钮控制台，默认仅在 debug_harness_enabled 下生效。
# 键位避让 1-4(skill_slot) / 鼠标中键(平移)：
#   ·键=开关控制台面板（按钮操控 软重置/确定性/暴击态/木桩行为）

const DEBUG_OVERLAY_LAYER: int = 50
const DEBUG_PANEL_POS: Vector2 = Vector2(12.0, 12.0)
const DEBUG_PANEL_MIN_SIZE: Vector2 = Vector2(240.0, 0.0)
const DEBUG_FONT_SIZE: int = 12
const DEBUG_HELP_TEXT: String = "[调试 Harness]  ·键 关闭控制台｜技能 1-4 选中后点目标格执行"
const DEBUG_HINT_TEXT: String = "·键 调试控制台"


func _register_debug_actions() -> void:
	for action_name: String in DEBUG_ACTIONS.keys():
		if InputMap.has_action(action_name):
			continue
		InputMap.add_action(action_name)
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = int(DEBUG_ACTIONS[action_name])
		InputMap.action_add_event(action_name, ev)


func _handle_debug_input(event: InputEvent) -> bool:
	if event.is_action_pressed("debug_console_toggle"):
		if _debug_console_panel != null:
			_debug_console_panel.visible = not _debug_console_panel.visible
			if _debug_console_panel.visible:
				_refresh_debug_overlay()
		return true
	return false


func _build_debug_overlay() -> void:
	if _debug_overlay != null:
		return
	_debug_overlay = CanvasLayer.new()
	_debug_overlay.layer = DEBUG_OVERLAY_LAYER
	add_child(_debug_overlay)

	# 持久提示标签（始终可见，告知·键可开控制台）
	var hint: Label = _make_debug_label(DEBUG_HINT_TEXT, Color(0.9, 0.85, 0.4))
	hint.position = DEBUG_PANEL_POS
	_debug_overlay.add_child(hint)

	# 控制台主面板（默认隐藏；·键切换显隐；MOUSE_FILTER_STOP 让按钮可点）
	_debug_console_panel = PanelContainer.new()
	_debug_console_panel.position = DEBUG_PANEL_POS + Vector2(0.0, 18.0)
	_debug_console_panel.custom_minimum_size = DEBUG_PANEL_MIN_SIZE
	_debug_console_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_debug_console_panel.visible = false
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	bg.set_content_margin_all(8.0)
	bg.set_corner_radius_all(4)
	_debug_console_panel.add_theme_stylebox_override("panel", bg)
	_debug_overlay.add_child(_debug_console_panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	_debug_console_panel.add_child(vbox)

	var title: Label = _make_debug_label(DEBUG_HELP_TEXT, Color(1.0, 0.92, 0.45))
	vbox.add_child(title)

	_debug_state_label = _make_debug_label("", Color(0.62, 0.92, 1.0))
	vbox.add_child(_debug_state_label)

	_btn_soft_reset = _make_debug_button("软重置")
	_btn_soft_reset.pressed.connect(_on_debug_btn_soft_reset)
	vbox.add_child(_btn_soft_reset)

	_btn_determinism = _make_debug_button("确定性：关")
	_btn_determinism.pressed.connect(_on_debug_btn_determinism)
	vbox.add_child(_btn_determinism)

	_btn_crit = _make_debug_button("暴击态：随机")
	_btn_crit.pressed.connect(_on_debug_btn_crit)
	vbox.add_child(_btn_crit)

	_btn_dummy = _make_debug_button("木桩行为：不动")
	_btn_dummy.pressed.connect(_on_debug_btn_dummy)
	vbox.add_child(_btn_dummy)

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


func _make_debug_button(label_text: String) -> Button:
	var btn: Button = Button.new()
	btn.text = label_text
	btn.add_theme_font_size_override("font_size", DEBUG_FONT_SIZE)
	btn.custom_minimum_size = Vector2(DEBUG_PANEL_MIN_SIZE.x - 16.0, 22.0)
	return btn


func _process(_delta: float) -> void:
	if debug_harness_enabled and _debug_overlay != null and not _battle_over:
		_refresh_debug_overlay()


func _refresh_debug_overlay() -> void:
	if _debug_state_label == null or _debug_status_label == null:
		return
	var status: Dictionary = tactical_manager.debug_get_status()
	var det_text: String = "开" if bool(status.get("deterministic", false)) else "关"
	var crit_text: String = str(status.get("crit_mode", "随机"))
	var dummy_text: String = str(status.get("dummy_behavior", "不动"))
	_debug_state_label.text = "确定性: %s   暴击: %s   木桩: %s" % [
		det_text, crit_text, dummy_text,
	]
	_debug_status_label.text = _build_debug_unit_status()
	# 同步按钮文案
	if _btn_determinism != null:
		_btn_determinism.text = "确定性：" + det_text
	if _btn_crit != null:
		_btn_crit.text = "暴击态：" + crit_text
	if _btn_dummy != null:
		_btn_dummy.text = "木桩行为：" + dummy_text


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


# ── 调试控制台按钮回调 ────────────────────────────────

func _on_debug_btn_soft_reset() -> void:
	tactical_manager.debug_soft_reset()
	_refresh_debug_overlay()


func _on_debug_btn_determinism() -> void:
	var on: bool = tactical_manager.debug_toggle_deterministic()
	print("[Debug] deterministic = %s" % str(on))
	_refresh_debug_overlay()


func _on_debug_btn_crit() -> void:
	tactical_manager.debug_cycle_crit_mode()
	print("[Debug] crit mode = %s" % tactical_manager.debug_crit_mode_label())
	_refresh_debug_overlay()


func _on_debug_btn_dummy() -> void:
	tactical_manager.debug_cycle_dummy_behavior()
	print("[Debug] dummy behavior = %s" % tactical_manager.debug_get_status().get("dummy_behavior", ""))
	_refresh_debug_overlay()


## 回合末木桩钩子：regen 木桩 HP 回满，revive 木桩从原位复活。
## 连 tactical_manager.turn_manager.round_ended 信号；
## 仅在 debug_harness_enabled=true 且战斗未结束时有效。
func _process_test_dummies() -> void:
	if not debug_harness_enabled or _battle_over:
		return
	if tactical_manager == null:
		return
	var turn_mgr: TurnManager = tactical_manager.turn_manager
	if turn_mgr == null:
		return

	# 再生：遍历存活单位，regen 木桩 HP 回满（由 DataLoader 读 dummy_mode，不硬编码）
	for u: Unit in tactical_manager.units:
		if not u.stats.is_alive():
			continue
		var edata: Dictionary = DataLoader.enemies.get(u.unit_id, {})
		if str(edata.get("dummy_mode", "")) == "regen":
			var heal_amount: int = u.stats.max_hp - u.stats.hp
			if heal_amount > 0:
				u.heal(heal_amount)
				print("[TestDummy] %s (regen) 回血 %d，HP 回满 %d/%d" % [
					u.unit_name, heal_amount, u.stats.hp, u.stats.max_hp])

	# 复活：遍历 ENEMY_UNITS 中 revive 木桩配置，无存活实例时于原位重生
	for cfg: Dictionary in ENEMY_UNITS:
		var class_id: String = str(cfg.get("class_id", ""))
		var edata: Dictionary = DataLoader.enemies.get(class_id, {})
		if str(edata.get("dummy_mode", "")) != "revive":
			continue
		# 检查是否有存活实例
		var alive: bool = false
		for u: Unit in tactical_manager.units:
			if u.unit_id == class_id and u.stats.is_alive():
				alive = true
				break
		if alive:
			continue
		var spawn_pos: Vector2i = cfg.get("pos", Vector2i.ZERO)
		var facing := StringName(str(cfg.get("facing", "SE")))
		var new_unit: Unit = tactical_manager.spawn_unit(
			class_id, spawn_pos, "enemy", facing)
		if new_unit == null:
			continue
		var typed_units: Array[Unit] = [new_unit]
		turn_mgr.add_units(typed_units)
		print("[TestDummy] %s (revive) 复活于 %s" % [class_id, str(spawn_pos)])
