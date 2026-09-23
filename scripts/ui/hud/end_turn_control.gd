class_name HudEndTurnControl
extends Control

signal end_turn_requested
signal end_move_requested

const EndTurnViewDataScript := preload("res://scripts/ui/hud/end_turn_view_data.gd")

@onready var end_turn_button: Button = $EndTurnButton

var _view: RefCounted = EndTurnViewDataScript.new()


func _ready() -> void:
	end_turn_button.pressed.connect(_on_button_pressed)
	_apply_view_to_nodes()


func apply_view(view: RefCounted) -> void:
	_view.action_kind = view.action_kind
	_view.visible = view.visible
	_view.enabled = view.enabled
	_view.tooltip_text = view.tooltip_text
	if is_node_ready():
		_apply_view_to_nodes()


func _apply_view_to_nodes() -> void:
	visible = _view.visible
	end_turn_button.tooltip_text = _view.tooltip_text
	end_turn_button.call("set_interaction_enabled",
		_view.enabled and _view.is_valid_action_kind())


func _on_button_pressed() -> void:
	if not visible or end_turn_button.disabled or not _view.is_valid_action_kind():
		return
	if _view.action_kind == EndTurnViewDataScript.ACTION_END_TURN:
		end_turn_requested.emit()
	elif _view.action_kind == EndTurnViewDataScript.ACTION_END_MOVE:
		end_move_requested.emit()
