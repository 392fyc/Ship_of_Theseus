class_name HudM2ClassResourceLayout
extends Resource

## 获批画布的显示数据；不包含职业规则或资源容量。
@export var selected_option: StringName = &"A"
@export var bounds: Rect2
@export var qi_label: Rect2
@export var qi_value: Rect2
@export var qi_track: Rect2
@export var qi_fill: Rect2
@export var divider: Rect2
@export var mark_label: Rect2
@export var mark_slots: Array[Rect2] = []


func geometry(_has_actions: bool, has_marks: bool) -> Dictionary:
	return {"bounds": bounds, "qi_label": qi_label, "qi_value": qi_value,
		"qi_track": qi_track, "qi_fill": qi_fill, "divider": divider if has_marks else Rect2(),
		"mark_label": mark_label if has_marks else Rect2(), "mark_slots": mark_slots.duplicate() if has_marks else []}


func frame_rect(_has_actions: bool) -> Rect2:
	return Rect2(32, 540, 1216, 164)


func outline_points(has_actions: bool) -> PackedVector2Array:
	var curve := Curve2D.new()
	curve.add_point(Vector2(38, 540))
	curve.add_point(Vector2(380, 540), Vector2.ZERO, Vector2(4, 0))
	curve.add_point(Vector2(386, 546), Vector2(0, -4))
	curve.add_point(Vector2(386, 585), Vector2.ZERO, Vector2(0, 6))
	curve.add_point(Vector2(398, 596), Vector2(-7, 0))
	if has_actions:
		curve.add_point(Vector2(492, 596), Vector2.ZERO, Vector2(6, 0))
		curve.add_point(Vector2(503, 585), Vector2(0, 6))
		curve.add_point(Vector2(503, 557), Vector2.ZERO, Vector2(0, -14.0 / 3.0))
		curve.add_point(Vector2(510, 550), Vector2(-14.0 / 3.0, 0))
		curve.add_point(Vector2(770, 550), Vector2.ZERO, Vector2(14.0 / 3.0, 0))
		curve.add_point(Vector2(777, 557), Vector2(0, -14.0 / 3.0))
		curve.add_point(Vector2(777, 585), Vector2.ZERO, Vector2(0, 6))
		curve.add_point(Vector2(788, 596), Vector2(-6, 0))
	curve.add_point(Vector2(1242, 596), Vector2.ZERO, Vector2(4, 0))
	curve.add_point(Vector2(1248, 602), Vector2(0, -4))
	curve.add_point(Vector2(1248, 698), Vector2.ZERO, Vector2(0, 4))
	curve.add_point(Vector2(1242, 704), Vector2(4, 0))
	curve.add_point(Vector2(38, 704), Vector2.ZERO, Vector2(-4, 0))
	curve.add_point(Vector2(32, 698), Vector2(0, 4))
	curve.add_point(Vector2(32, 546), Vector2.ZERO, Vector2(0, -4))
	curve.add_point(Vector2(38, 540), Vector2(-4, 0))
	return curve.tessellate(5, 1.0)


func resource_window_points() -> PackedVector2Array:
	var curve := Curve2D.new()
	curve.add_point(Vector2(38, 543))
	curve.add_point(Vector2(380, 543), Vector2.ZERO, Vector2(2, 0))
	curve.add_point(Vector2(383, 546), Vector2(0, -2))
	curve.add_point(Vector2(383, 585), Vector2.ZERO, Vector2(0, 6))
	curve.add_point(Vector2(394, 597.8), Vector2(-6, -1.8))
	curve.add_point(Vector2(35, 597.8))
	curve.add_point(Vector2(35, 546), Vector2.ZERO, Vector2(0, -2))
	curve.add_point(Vector2(38, 543), Vector2(-2, 0))
	return curve.tessellate(5, 1.0)
