class_name HudM2ActionResourceStrip
extends Panel

const ActionResourceViewData := preload("res://scripts/ui/hud/action_resource_view_data.gd")
const ActionResourceGlyph := preload("res://scripts/ui/hud/m2/action_resource_glyph.gd")

const PIP_SIZE: float = 16.0
const PIP_SEPARATION: float = 2.0

var _view: ActionResourceViewData = null
@onready var _footprint_glyph: ActionResourceGlyph = %FootprintGlyph
@onready var _movement_value: Label = %MovementValue
@onready var _movement_state: Label = %MovementState
@onready var _standard_state: Label = %StandardState
@onready var _standard_pips: HBoxContainer = %StandardPips
@onready var _swift_state: Label = %SwiftState
@onready var _swift_pips: HBoxContainer = %SwiftPips


func _ready() -> void:
	# Control 先发出 theme_changed，再清理查询缓存；延后读取才能取得新颜色。
	theme_changed.connect(_refresh_skin, CONNECT_DEFERRED)
	if _view != null:
		_apply_view_to_nodes()


func apply_view(view: ActionResourceViewData) -> void:
	_view = view
	_view.normalize()
	if is_node_ready():
		_apply_view_to_nodes()


func get_standard_pips() -> Array[Node]:
	return _standard_pips.get_children()


func get_swift_pips() -> Array[Node]:
	return _swift_pips.get_children()


func _apply_view_to_nodes() -> void:
	_view.normalize()
	_footprint_glyph.visible = true
	_footprint_glyph.configure(ActionResourceGlyph.Kind.FOOTPRINT, not _view.movement_available)
	_movement_value.text = "移动力 %d" % _view.movement_remaining
	_movement_state.text = "移动可用" if _view.movement_available else "移动已用"
	_standard_state.text = "可用" if _view.standard_remaining > 0 else "已用"
	_swift_state.text = "可用" if _view.swift_remaining > 0 else "已用"
	_refresh_skin()
	_rebuild_pips(_standard_pips, ActionResourceGlyph.Kind.STANDARD, _view.standard_capacity, _view.standard_remaining)
	_rebuild_pips(_swift_pips, ActionResourceGlyph.Kind.SWIFT, _view.swift_capacity, _view.swift_remaining)
	_layout_status(_standard_state, _standard_pips)
	_layout_status(_swift_state, _swift_pips)


func _rebuild_pips(container: HBoxContainer, glyph_kind: ActionResourceGlyph.Kind, capacity: int, remaining: int) -> void:
	for child: Node in container.get_children():
		child.free()
	for index: int in capacity:
		var glyph := ActionResourceGlyph.new()
		glyph.name = "%sPip%d" % ["Standard" if glyph_kind == ActionResourceGlyph.Kind.STANDARD else "Swift", index + 1]
		glyph.custom_minimum_size = Vector2.ONE * PIP_SIZE
		glyph.configure(glyph_kind, index >= remaining)
		container.add_child(glyph)
	var row_width: float = capacity * PIP_SIZE + (capacity - 1) * PIP_SEPARATION
	container.size = Vector2(row_width, PIP_SIZE)
	container.position = Vector2(container.get_parent_control().size.x - 4.0 - row_width, 25.0)


func _layout_status(label: Label, pips: HBoxContainer) -> void:
	var pips_left: float = pips.position.x
	label.position = Vector2(5.0, 26.0)
	label.size = Vector2(maxf(pips_left - label.position.x - 4.0, 0.0), 13.0)


func _refresh_skin() -> void:
	if not is_node_ready() or _view == null:
		return
	_movement_value.add_theme_color_override(&"font_color", get_theme_color(&"text", &"HudM2"))
	_movement_state.add_theme_color_override(&"font_color", get_theme_color(&"text" if _view.movement_available else &"spent_edge", &"HudM2"))
	_standard_state.add_theme_color_override(&"font_color", get_theme_color(&"text" if _view.standard_remaining > 0 else &"spent_edge", &"HudM2"))
	_swift_state.add_theme_color_override(&"font_color", get_theme_color(&"text" if _view.swift_remaining > 0 else &"spent_edge", &"HudM2"))
	_layout_movement()


func _layout_movement() -> void:
	var text_width: float = ceilf(_movement_value.get_theme_font(&"font").get_string_size(_movement_value.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _movement_value.get_theme_font_size(&"font_size")).x)
	var line_height: float = maxf(_movement_value.get_minimum_size().y, 13.0)
	var zone_size: Vector2 = _footprint_glyph.get_parent_control().size
	var group_width: float = PIP_SIZE + 4.0 + text_width
	var left: float = (zone_size.x - group_width) * 0.5
	_footprint_glyph.size = Vector2.ONE * PIP_SIZE
	_footprint_glyph.position = Vector2(left, 4.0)
	_movement_value.size = Vector2(text_width, line_height)
	_movement_value.position = Vector2(left + PIP_SIZE + 4.0, 4.0)
	_movement_state.position = Vector2(0.0, 25.0)
	_movement_state.size = Vector2(zone_size.x, 13.0)
