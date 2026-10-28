extends Node2D
## Persistent allegiance at the actual Unit foot; independent of HP label avoidance.
var allegiance: Color = Color("53c5cf")
var _active: bool = false
var compact_badge_layout: bool = false
# Legacy entry keeps its previous offset; portrait entry opts into the true cell origin.
var center_offset := Vector2(0, 4)

func _process(_delta: float) -> void:
	var unit: Node = get_parent()
	var manager: Node = unit.get_parent().get_parent()
	var active: bool = manager.selected_unit == unit or manager.current_unit == unit
	if active != _active:
		_active = active
		queue_redraw()

func _ellipse(rx: float, ry: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(41):
		var angle: float = TAU * float(index) / 40.0
		points.append(Vector2(cos(angle) * rx, sin(angle) * ry) + center_offset)
	return points

func _draw() -> void:
	if compact_badge_layout:
		draw_polyline(_ellipse(8.5, 3.8), Color("24332de6"), 2.0, true)
		draw_polyline(_ellipse(8.5, 3.8), allegiance, 1.2, true)
		if _active:
			draw_polyline(_ellipse(9.5, 4.4), Color("f2dd97"), 1.2, true)
		return
	var ring: PackedVector2Array = _ellipse(18.0, 8.0)
	draw_polyline(ring, Color("24332de6"), 4.5, true)
	draw_polyline(ring, allegiance, 2.2, true)
	if _active:
		draw_polyline(_ellipse(22.0, 10.0), Color("f2dd97"), 1.5, true)
