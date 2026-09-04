class_name HudValueMeter
extends Control

const ValueMeterViewData := preload("res://scripts/ui/hud/value_meter_view_data.gd")
const LONG_VALUE_CHARACTER_COUNT: int = 13
const LONG_VALUE_FONT_SIZE: int = 9

@export var track_theme_type: StringName = &"HudHpMeter"
@export_range(1.0, 32.0, 1.0) var track_height: float = 13.0

var _view: ValueMeterViewData = null

@onready var _track: ProgressBar = %Track
@onready var _value_label: Label = %ValueLabel


func _ready() -> void:
	_track.theme_type_variation = track_theme_type
	_apply_track_geometry()
	if _view != null:
		_apply_view_to_nodes()


func apply_view(view: ValueMeterViewData) -> void:
	_view = view
	if is_node_ready():
		_apply_view_to_nodes()


func _apply_view_to_nodes() -> void:
	_track.value = _view.ratio
	var display_text: String = _view.display_text
	_value_label.text = display_text
	if display_text.length() >= LONG_VALUE_CHARACTER_COUNT:
		_value_label.add_theme_font_size_override(&"font_size", LONG_VALUE_FONT_SIZE)
	else:
		_value_label.remove_theme_font_size_override(&"font_size")


func _apply_track_geometry() -> void:
	_track.anchor_top = 0.5
	_track.anchor_bottom = 0.5
	_track.offset_top = -track_height * 0.5
	_track.offset_bottom = track_height * 0.5
