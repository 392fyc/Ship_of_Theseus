class_name HudActionResourceGlyph
extends Control

enum Kind {
	FOOTPRINT,
	STANDARD,
	SWIFT,
}

const SPENT_COLOR: Color = Color("#70747C")
const FOOTPRINT_COLOR: Color = Color("#D1AB57")
const STANDARD_COLOR: Color = Color("#4FC76B")
const SWIFT_COLOR: Color = Color("#F09C33")
const SPENT_OUTLINE_COLOR: Color = Color("#CDD2DA")
const FOOTPRINT_OUTLINE_COLOR: Color = Color("#EAD7A9")
const STANDARD_OUTLINE_COLOR: Color = Color("#A3E9AC")
const SWIFT_OUTLINE_COLOR: Color = Color("#FFD293")
const OUTLINE_WIDTH: float = 1.0
const SWIFT_SIDE_LENGTH: float = 14.0

@export var kind: Kind = Kind.FOOTPRINT
@export var spent: bool = false

var _display_color: Color = FOOTPRINT_COLOR
var _outline_color: Color = FOOTPRINT_OUTLINE_COLOR


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
		_outline_color = SPENT_OUTLINE_COLOR
		return
	match kind:
		Kind.STANDARD:
			_display_color = STANDARD_COLOR
			_outline_color = STANDARD_OUTLINE_COLOR
		Kind.SWIFT:
			_display_color = SWIFT_COLOR
			_outline_color = SWIFT_OUTLINE_COLOR
		_:
			_display_color = FOOTPRINT_COLOR
			_outline_color = FOOTPRINT_OUTLINE_COLOR


func _draw() -> void:
	match kind:
		Kind.STANDARD:
			_draw_standard()
		Kind.SWIFT:
			_draw_swift()
		_:
			_draw_footprint()


func _draw_standard() -> void:
	_draw_circle_with_outline(size * 0.5, minf(size.x, size.y) * 0.31)


func _draw_swift() -> void:
	var center: Vector2 = size * 0.5
	var half_side: float = SWIFT_SIDE_LENGTH * 0.5
	var half_height: float = SWIFT_SIDE_LENGTH * sqrt(3.0) * 0.25
	_draw_polygon_with_outline(PackedVector2Array([
		center + Vector2(0.0, -half_height),
		center + Vector2(-half_side, half_height),
		center + Vector2(half_side, half_height),
	]))


func _draw_footprint() -> void:
	# 单只脚向上：脚跟、前脚掌和大小递减的脚趾分层，避免缩小后像瓶子。
	var offset_x: float = (size.x - 18.0) * 0.5
	var offset_y: float = (size.y - 24.0) * 0.5
	_draw_polygon_with_outline(PackedVector2Array([
		Vector2(offset_x + 6.0, offset_y + 15.0),
		Vector2(offset_x + 11.0, offset_y + 15.0),
		Vector2(offset_x + 13.0, offset_y + 11.0),
		Vector2(offset_x + 12.5, offset_y + 7.5),
		Vector2(offset_x + 10.8, offset_y + 6.4),
		Vector2(offset_x + 7.5, offset_y + 7.0),
		Vector2(offset_x + 5.5, offset_y + 10.0),
		Vector2(offset_x + 5.6, offset_y + 12.8),
	]))
	_draw_polygon_with_outline(PackedVector2Array([
		Vector2(offset_x + 6.6, offset_y + 16.0),
		Vector2(offset_x + 10.8, offset_y + 16.0),
		Vector2(offset_x + 11.4, offset_y + 18.6),
		Vector2(offset_x + 10.3, offset_y + 22.0),
		Vector2(offset_x + 7.0, offset_y + 22.0),
		Vector2(offset_x + 6.0, offset_y + 18.8),
	]))
	_draw_circle_with_outline(Vector2(offset_x + 11.7, offset_y + 3.1), 2.1)
	_draw_circle_with_outline(Vector2(offset_x + 8.5, offset_y + 3.0), 1.55)
	_draw_circle_with_outline(Vector2(offset_x + 6.0, offset_y + 3.7), 1.2)
	_draw_circle_with_outline(Vector2(offset_x + 4.2, offset_y + 4.8), 0.9)


func _draw_polygon_with_outline(points: PackedVector2Array) -> void:
	draw_colored_polygon(points, _display_color)
	var outline_points: PackedVector2Array = points.duplicate()
	outline_points.append(points[0])
	draw_polyline(outline_points, _outline_color, OUTLINE_WIDTH, true)


func _draw_circle_with_outline(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, _display_color, true, -1.0, true)
	draw_circle(center, radius, _outline_color, false, OUTLINE_WIDTH, true)
