class_name HudM2ActionResourceStrip
extends Panel

const ActionResourceViewData := preload("res://scripts/ui/hud/action_resource_view_data.gd")
const ActionResourceGlyph := preload("res://scripts/ui/hud/m2/action_resource_glyph.gd")

var _view: ActionResourceViewData = null
@onready var _footprint_glyph: ActionResourceGlyph = %FootprintGlyph
@onready var _movement_value: Label = %MovementValue
@onready var _standard_pips: HBoxContainer = %StandardPips
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
	_footprint_glyph.configure(ActionResourceGlyph.Kind.FOOTPRINT, not _view.movement_available, true)
	_movement_value.text = str(_view.movement_remaining)
	_refresh_skin()
	_rebuild_pips(_standard_pips, ActionResourceGlyph.Kind.STANDARD, _view.standard_capacity, _view.standard_remaining)
	_rebuild_pips(_swift_pips, ActionResourceGlyph.Kind.SWIFT, _view.swift_capacity, _view.swift_remaining)


func _rebuild_pips(container: HBoxContainer, glyph_kind: ActionResourceGlyph.Kind, capacity: int, remaining: int) -> void:
	for child: Node in container.get_children():
		child.free()
	for index: int in capacity:
		var glyph := ActionResourceGlyph.new()
		glyph.name = "%sPip%d" % ["Standard" if glyph_kind == ActionResourceGlyph.Kind.STANDARD else "Swift", index + 1]
		glyph.custom_minimum_size = Vector2(24.0, 24.0)
		glyph.configure(glyph_kind, index >= remaining, true)
		container.add_child(glyph)
	var row_width: float = capacity * 24.0 + (capacity - 1) * 5.0
	container.size = Vector2(row_width, 24.0)
	container.position = (container.get_parent_control().size - container.size) * 0.5


func _refresh_skin() -> void:
	if not is_node_ready() or _view == null:
		return
	_movement_value.add_theme_color_override(&"font_color", get_theme_color(&"text" if _view.movement_available else &"spent_edge", &"HudM2"))
	_layout_movement()


func _layout_movement() -> void:
	var text_width: float = ceilf(_movement_value.get_theme_font(&"font").get_string_size(_movement_value.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _movement_value.get_theme_font_size(&"font_size")).x)
	var text_height: float = _movement_value.get_minimum_size().y
	var foot: Rect2 = _footprint_glyph.get_path_bounds()
	var center: Vector2 = _footprint_glyph.get_parent_control().size * 0.5
	var left: float = center.x - (foot.size.x + 7.0 + text_width) * 0.5
	_footprint_glyph.position = Vector2(left - foot.position.x, center.y - 12.0)
	_movement_value.size = Vector2(text_width, text_height)
	_movement_value.position = Vector2(left + foot.size.x + 7.0, center.y - text_height * 0.5)
