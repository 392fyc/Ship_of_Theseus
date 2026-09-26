class_name HudM2EndTurnButton
extends Button

@onready var _unavailable_shade: Control = %UnavailableShade
@onready var _hover_overlay: Control = %HoverOverlay
@onready var _pressed_shade: Control = %PressedShade
@onready var _focus_overlay: Control = %FocusOverlay


func _ready() -> void:
	mouse_entered.connect(func() -> void: _hover_overlay.visible = not disabled)
	mouse_exited.connect(func() -> void: _hover_overlay.hide(); _pressed_shade.hide())
	button_down.connect(func() -> void: _pressed_shade.visible = not disabled)
	button_up.connect(_pressed_shade.hide)
	focus_entered.connect(func() -> void: _focus_overlay.show())
	focus_exited.connect(_focus_overlay.hide)
	_unavailable_shade.visible = disabled
	%HourglassEmblem.draw.connect(_draw_hourglass)
	theme_changed.connect(_refresh_skin, CONNECT_DEFERRED)
	_refresh_skin()


func set_interaction_enabled(value: bool) -> void:
	disabled = not value
	if is_node_ready():
		_unavailable_shade.visible = disabled
		_hover_overlay.visible = not disabled and is_hovered()
		_pressed_shade.hide()


func _refresh_skin() -> void:
	if not is_node_ready():
		return
	%HourglassEmblem.texture = get_theme_icon(&"end_emblem", &"HudM2") if has_theme_icon(&"end_emblem", &"HudM2") else null
	%HourglassEmblem.queue_redraw()


func _draw_hourglass() -> void:
	if %HourglassEmblem.texture != null:
		return
	var color: Color = get_theme_color(&"end_emblem", &"HudM2")
	# 上下两半围绕 (9, 12) 镜像，保持沙漏和三角形等宽等高。
	var points := PackedVector2Array([
		Vector2(2, 2), Vector2(16, 2), Vector2(16, 5),
		Vector2(10, 11), Vector2(10, 13), Vector2(16, 19),
		Vector2(16, 22), Vector2(2, 22), Vector2(2, 19),
		Vector2(8, 13), Vector2(8, 11), Vector2(2, 5), Vector2(2, 2),
	])
	%HourglassEmblem.draw_polyline(points, color, 1.4, true)
