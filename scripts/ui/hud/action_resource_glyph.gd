class_name HudActionResourceGlyph
extends Control

enum Kind {
	FOOTPRINT,
	STANDARD,
	SWIFT,
}

const SPENT_COLOR: Color = Color(0.34, 0.35, 0.38, 1.0)
const FOOTPRINT_COLOR: Color = Color(0.82, 0.67, 0.34, 1.0)
const STANDARD_COLOR: Color = Color(0.31, 0.78, 0.42, 1.0)
const SWIFT_COLOR: Color = Color(0.94, 0.61, 0.2, 1.0)

@export var kind: Kind = Kind.FOOTPRINT
@export var spent: bool = false

var _display_color: Color = FOOTPRINT_COLOR


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_color()


func configure(next_kind: Kind, is_spent: bool) -> void:
	kind = next_kind
	spent = is_spent
	_refresh_color()
	queue_redraw()


func get_display_color() -> Color:
	return _display_color


func _refresh_color() -> void:
	if spent:
		_display_color = SPENT_COLOR
		return
	match kind:
		Kind.STANDARD:
			_display_color = STANDARD_COLOR
		Kind.SWIFT:
			_display_color = SWIFT_COLOR
		_:
			_display_color = FOOTPRINT_COLOR


func _draw() -> void:
	match kind:
		Kind.STANDARD:
			_draw_standard()
		Kind.SWIFT:
			_draw_swift()
		_:
			_draw_footprint()


func _draw_standard() -> void:
	draw_circle(size * 0.5, minf(size.x, size.y) * 0.31, _display_color)


func _draw_swift() -> void:
	var center_x: float = size.x * 0.5
	var top: float = size.y * 0.18
	var bottom: float = size.y * 0.82
	draw_colored_polygon(PackedVector2Array([
		Vector2(center_x, top),
		Vector2(size.x * 0.18, bottom),
		Vector2(size.x * 0.82, bottom),
	]), _display_color)


func _draw_footprint() -> void:
	# 单只脚向上：脚跟、前脚掌和大小递减的脚趾分层，避免缩小后像瓶子。
	var offset_x: float = (size.x - 18.0) * 0.5
	var offset_y: float = (size.y - 24.0) * 0.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(offset_x + 6.0, offset_y + 15.0),
		Vector2(offset_x + 11.0, offset_y + 15.0),
		Vector2(offset_x + 13.0, offset_y + 11.0),
		Vector2(offset_x + 12.5, offset_y + 7.5),
		Vector2(offset_x + 10.8, offset_y + 6.4),
		Vector2(offset_x + 7.5, offset_y + 7.0),
		Vector2(offset_x + 5.5, offset_y + 10.0),
		Vector2(offset_x + 5.6, offset_y + 12.8),
	]), _display_color)
	draw_colored_polygon(PackedVector2Array([
		Vector2(offset_x + 6.6, offset_y + 16.0),
		Vector2(offset_x + 10.8, offset_y + 16.0),
		Vector2(offset_x + 11.4, offset_y + 18.6),
		Vector2(offset_x + 10.3, offset_y + 22.0),
		Vector2(offset_x + 7.0, offset_y + 22.0),
		Vector2(offset_x + 6.0, offset_y + 18.8),
	]), _display_color)
	draw_circle(Vector2(offset_x + 11.7, offset_y + 3.1), 2.1, _display_color)
	draw_circle(Vector2(offset_x + 8.5, offset_y + 3.0), 1.55, _display_color)
	draw_circle(Vector2(offset_x + 6.0, offset_y + 3.7), 1.2, _display_color)
	draw_circle(Vector2(offset_x + 4.2, offset_y + 4.8), 0.9, _display_color)
