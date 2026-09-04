class_name HudSlotButton
extends Button

signal slot_requested(slot_id: String, content_id: String)

const SlotViewData := preload("res://scripts/ui/hud/slot_view_data.gd")

var _view: SlotViewData = null

@onready var _icon_rect: TextureRect = %IconRect
@onready var _state_overlay: Control = %StateOverlay
@onready var _focus_overlay: Control = %FocusOverlay


func _ready() -> void:
	pressed.connect(_on_pressed)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	if _view != null:
		_apply_view_to_nodes()


func apply_view(view: SlotViewData) -> void:
	_view = view
	if is_node_ready():
		_apply_view_to_nodes()


func _apply_view_to_nodes() -> void:
	_icon_rect.texture = _view.icon_texture
	_state_overlay.visible = not _view.occupied
	tooltip_text = _view.tooltip_text
	disabled = not _view.enabled


func _on_pressed() -> void:
	if _view != null and not disabled:
		slot_requested.emit(_view.slot_id, _view.content_id)


func _on_focus_entered() -> void:
	_focus_overlay.visible = true


func _on_focus_exited() -> void:
	_focus_overlay.visible = false
