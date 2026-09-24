extends Control

const FrameStyle := preload("res://scripts/ui/hud/m2/shared_frame_style.gd")


func _ready() -> void:
	theme_changed.connect(queue_redraw)


func has_action_region() -> bool:
	var strip: Control = get_parent().get_node("ActionResourceStrip") as Control
	return strip.visible


func get_frame_style() -> StyleBox:
	return get_theme_stylebox(get_frame_style_name(), &"HudM2SharedFrame")


func get_frame_style_name() -> StringName:
	return &"panel" if has_action_region() else &"collapsed"


func _draw() -> void:
	draw_style_box(get_frame_style(), FrameStyle.frame_rect(has_action_region()))


func _has_point(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point, FrameStyle.outline_points(has_action_region()))


func get_input_blocking_rects() -> Array[Rect2]:
	var rectangles: Array[Rect2] = []
	var transform: Transform2D = get_global_transform()
	for rectangle: Rect2 in get_logical_blocking_rects():
		rectangles.append(transform * rectangle)
	return rectangles


func get_logical_blocking_rects() -> Array[Rect2]:
	var rectangles: Array[Rect2] = [Rect2(32, 596, 1216, 108)]
	# 按一逻辑像素横带覆盖圆滑连接处；空白顶角继续向战场透传。
	var outline: PackedVector2Array = FrameStyle.outline_points(has_action_region())
	var top: int = int(FrameStyle.frame_rect(has_action_region()).position.y)
	rectangles.append_array(FrameStyle.scanline_rects(outline, Rect2(32, top, 1216, 596 - top)))
	return rectangles
