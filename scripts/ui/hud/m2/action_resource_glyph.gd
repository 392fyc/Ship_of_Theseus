class_name HudM2ActionResourceGlyph
extends Control

enum Kind { FOOTPRINT, STANDARD, SWIFT }

@export var kind: Kind = Kind.FOOTPRINT
@export var spent: bool = false
@export var strip_sizing: bool = false

# 获批足迹 SVG 的实际贝塞尔边界，不包含透明视口。
const FOOTPRINT_BOUNDS := Rect2(1.1066090716773, 0.607695154587, 12.285695773735938, 15.392304845412582)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	theme_changed.connect(queue_redraw)


func configure(next_kind: Kind, is_spent: bool, use_strip_sizing: bool = false) -> void:
	kind = next_kind
	spent = is_spent
	strip_sizing = use_strip_sizing
	queue_redraw()


func get_path_bounds() -> Rect2:
	if kind == Kind.FOOTPRINT:
		var extent: Vector2 = FOOTPRINT_BOUNDS.size * (20.0 / FOOTPRINT_BOUNDS.size.y) if strip_sizing else FOOTPRINT_BOUNDS.size * (size.x / 16.0)
		return Rect2((size - extent) * 0.5, extent) if strip_sizing else Rect2(FOOTPRINT_BOUNDS.position * (size.x / 16.0), extent)
	if kind == Kind.SWIFT:
		var extent := Vector2(size.x, size.x * sqrt(3.0) * 0.5)
		return Rect2((size - extent) * 0.5, extent)
	var diameter: float = 20.0 if strip_sizing else minf(size.x, size.y)
	return Rect2((size - Vector2.ONE * diameter) * 0.5, Vector2.ONE * diameter)


func get_swift_points() -> PackedVector2Array:
	var bounds: Rect2 = get_path_bounds()
	return PackedVector2Array([Vector2(bounds.get_center().x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)])


func get_display_color() -> Color:
	if spent:
		return get_theme_color(&"spent", &"HudM2")
	match kind:
		Kind.STANDARD: return get_theme_color(&"standard", &"HudM2")
		Kind.SWIFT: return get_theme_color(&"swift", &"HudM2")
	return get_theme_color(&"movement", &"HudM2")


func _draw() -> void:
	var color: Color = get_display_color()
	var outline: Color = get_theme_color(&"spent_edge", &"HudM2") if spent else color
	if kind == Kind.STANDARD:
		var radius: float = get_path_bounds().size.x * 0.5 - 0.5
		draw_circle(size * 0.5, radius, color, true, -1.0, true)
		draw_circle(size * 0.5, radius, outline, false, 1.0, true)
	elif kind == Kind.SWIFT:
		_polygon(get_swift_points(), color, outline, 1.0)
	else:
		# 与获批 SVG 相同的双足曲线，按当前图形宽度缩放。
		for shift: Vector2 in [Vector2.ZERO, Vector2(8, 4)]:
			var curve := Curve2D.new()
			curve.add_point(Vector2(3, 1), Vector2.ZERO, Vector2(-3, 1))
			curve.add_point(Vector2(3, 8), Vector2(-2, -1), Vector2(2, 0))
			curve.add_point(Vector2(5, 3), Vector2(1, 2), Vector2(0, -2))
			curve.add_point(Vector2(3, 1), Vector2(1, -1))
			var sole: PackedVector2Array = curve.tessellate(6 if strip_sizing else 3, 0.5 if strip_sizing else 2.0)
			for index: int in sole.size():
				sole[index] = _footprint_point(sole[index] + shift)
			_polygon(sole, color, outline, 0.6)
			var heel := PackedVector2Array([Vector2(3, 9), Vector2(5, 9), Vector2(5, 12), Vector2(3, 12)])
			for index: int in heel.size():
				heel[index] = _footprint_point(heel[index] + shift)
			_polygon(heel, color, outline, 0.6)


func _footprint_point(point: Vector2) -> Vector2:
	if strip_sizing:
		return get_path_bounds().position + (point - FOOTPRINT_BOUNDS.position) * (20.0 / FOOTPRINT_BOUNDS.size.y)
	return point * (size.x / 16.0)


func _polygon(points: PackedVector2Array, color: Color, outline: Color, width: float) -> void:
	draw_colored_polygon(points, color)
	var border: PackedVector2Array = points.duplicate()
	border.append(points[0])
	draw_polyline(border, outline, width, true)
