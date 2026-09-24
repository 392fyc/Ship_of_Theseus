class_name HudPotionButton
extends Button

signal potion_requested

const PotionViewData := preload("res://scripts/ui/hud/potion_view_data.gd")

var _view: PotionViewData = null

@onready var _icon_rect: TextureRect = %IconRect
@onready var _focus_overlay: Control = %FocusOverlay


func _ready() -> void:
	pressed.connect(_on_pressed)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	if _view != null:
		_apply_view_to_nodes()


func apply_view(view: PotionViewData) -> void:
	_view = view
	if is_node_ready():
		_apply_view_to_nodes()


func _apply_view_to_nodes() -> void:
	_icon_rect.texture = _view.icon_texture
	tooltip_text = _view.tooltip_text
	disabled = not _view.enabled


func _on_pressed() -> void:
	if _view != null and not disabled:
		potion_requested.emit()


func _on_focus_entered() -> void:
	_focus_overlay.visible = true


func _on_focus_exited() -> void:
	_focus_overlay.visible = false
