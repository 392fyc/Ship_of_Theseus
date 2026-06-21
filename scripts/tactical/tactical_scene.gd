extends Node2D
## TacticalScene controller: spawns units, starts battle, handles victory/defeat.

@onready var tactical_manager: TacticalManager = $TacticalManager
@onready var result_overlay: ColorRect = $UILayer/ResultOverlay
@onready var result_label: Label = $UILayer/ResultLabel
@onready var return_button: Button = $UILayer/ReturnButton

var _turn_order_bar: TurnOrderBar = null
var _bottom_dashboard: BottomDashboard = null
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


func _ready() -> void:
	_setup_camera()
	tactical_manager.initialize_battle("forest_01")

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


func _setup_camera() -> void:
	_camera = Camera2D.new()
	_camera.enabled = true
	_camera.position = Vector2(0.0, 0.0)
	add_child(_camera)


func _should_ignore_board_pointer() -> bool:
	var hovered_control: Control = get_viewport().gui_get_hovered_control()
	return hovered_control != null
