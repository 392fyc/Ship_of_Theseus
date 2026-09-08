class_name HudM2EndTurnControl
extends "res://scripts/ui/hud/end_turn_control.gd"

@onready var _end_label: Label = %EndLabel


func _ready() -> void:
	super._ready()
	theme_changed.connect(_refresh_skin, CONNECT_DEFERRED)
	_refresh_skin()


func _apply_view_to_nodes() -> void:
	super._apply_view_to_nodes()
	match _view.action_kind:
		EndTurnViewDataScript.ACTION_END_TURN: _end_label.text = "结束回合"
		EndTurnViewDataScript.ACTION_END_MOVE: _end_label.text = "结束移动"
		_: _end_label.text = ""
	_refresh_skin()


func _refresh_skin() -> void:
	if is_node_ready():
		_end_label.add_theme_color_override(&"font_color", get_theme_color(&"end_disabled" if end_turn_button.disabled else &"muted", &"HudM2"))


func _on_button_pressed() -> void:
	if is_visible_in_tree():
		super._on_button_pressed()
