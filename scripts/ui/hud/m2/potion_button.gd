class_name HudM2PotionButton
extends "res://scripts/ui/hud/potion_button.gd"

@onready var _unavailable_shade: Control = %UnavailableShade
@onready var _hover_overlay: Control = %HoverOverlay
@onready var _pressed_shade: Control = %PressedShade


func _ready() -> void:
	super._ready()
	mouse_entered.connect(func() -> void: _hover_overlay.visible = not disabled)
	mouse_exited.connect(func() -> void: _hover_overlay.hide(); _pressed_shade.hide())
	button_down.connect(func() -> void: _pressed_shade.visible = not disabled)
	button_up.connect(_pressed_shade.hide)
	if _view == null:
		disabled = true
		_unavailable_shade.show()


func _apply_view_to_nodes() -> void:
	if _view == null:
		_view = PotionViewData.new()
	super._apply_view_to_nodes()
	disabled = not _view.enabled or _view.content_id.is_empty()
	_unavailable_shade.visible = disabled
	_hover_overlay.visible = not disabled and is_hovered()
	_pressed_shade.hide()


func _on_pressed() -> void:
	if is_visible_in_tree() and not disabled and _view != null and _view.enabled and not _view.content_id.is_empty():
		potion_requested.emit()
