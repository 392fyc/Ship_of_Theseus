class_name HudEndTurnButton
extends Button

const IDLE_MODULATE: Color = Color.WHITE
const HOVER_MODULATE: Color = Color(1.12, 1.06, 0.88, 1.0)
const PRESSED_MODULATE: Color = Color(0.74, 0.7, 0.78, 1.0)
const DISABLED_MODULATE: Color = Color(0.46, 0.46, 0.5, 0.68)


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)


func set_interaction_enabled(value: bool) -> void:
	disabled = not value
	modulate = IDLE_MODULATE if value else DISABLED_MODULATE


func _on_mouse_entered() -> void:
	if not disabled:
		modulate = HOVER_MODULATE


func _on_mouse_exited() -> void:
	if not disabled:
		modulate = IDLE_MODULATE


func _on_button_down() -> void:
	if not disabled:
		modulate = PRESSED_MODULATE


func _on_button_up() -> void:
	if not disabled:
		modulate = HOVER_MODULATE
