extends StyleBox

## 一个样式资源拥有连续外轮廓和共享隔边。内容锚点仍由场景定义。
@export var material_texture: Texture2D:
	set(value):
		material_texture = value
		emit_changed()
@export var background_color: Color = Color("#191C20"):
	set(value):
		background_color = value
		emit_changed()
@export var border_color: Color = Color("#51534E"):
	set(value):
		border_color = value
		emit_changed()
@export var border_width: float = 2.0:
	set(value):
		border_width = value
		emit_changed()
@export var raised: bool = true:
	set(value):
		raised = value
		emit_changed()
@export var layout: Resource
@export var has_resources: bool = false


static func frame_rect(has_actions: bool, resource_layout: Resource = null, resources: bool = false) -> Rect2:
	if resources and resource_layout != null:
		return resource_layout.frame_rect(has_actions)
	return Rect2(32, 550, 1216, 154) if has_actions else Rect2(32, 596, 1216, 108)


static func outline_points(has_actions: bool, resource_layout: Resource = null, resources: bool = false) -> PackedVector2Array:
	if resources and resource_layout != null:
		return resource_layout.outline_points(has_actions)
	# 获批共享外轮廓；绘制与输入命中沿用同一几何。
	var curve := Curve2D.new()
	curve.add_point(Vector2(38, 596))
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
	curve.add_point(Vector2(32, 602), Vector2.ZERO, Vector2(0, -4))
	curve.add_point(Vector2(38, 596), Vector2(-4, 0))
	return curve.tessellate(5, 1.0)


static func window_rects(has_actions: bool, _resource_layout: Resource = null, _resources: bool = false) -> Array[Rect2]:
	# FE-FRAME-R1 开口。单条共边及两肩均由整块材质承担。
	var windows: Array[Rect2] = [Rect2(35, 599, 226.4, 102), Rect2(262.6, 599, 134.8, 102),
		Rect2(398.6, 599, 482.8, 102), Rect2(882.6, 599, 284.8, 102), Rect2(1168.6, 599, 76.4, 102)]
	if has_actions:
		windows.append_array([Rect2(506, 553, 88.4, 45), Rect2(595.6, 553, 88.8, 45), Rect2(685.6, 553, 88.4, 45)])
	return windows


static func scanline_rects(outline: PackedVector2Array, clip: Rect2) -> Array[Rect2]:
	var rectangles: Array[Rect2] = []
	for y: int in range(int(clip.position.y), int(clip.end.y)):
		var crossings: Array[float] = []
		var scan_y: float = float(y) + 0.5
		for index: int in outline.size() - 1:
			var a: Vector2 = outline[index]
			var b: Vector2 = outline[index + 1]
			if (a.y <= scan_y and b.y > scan_y) or (b.y <= scan_y and a.y > scan_y):
				crossings.append(a.x + (scan_y - a.y) * (b.x - a.x) / (b.y - a.y))
		crossings.sort()
		for index: int in range(0, crossings.size() - 1, 2):
			var band: Rect2 = Rect2(crossings[index], y, crossings[index + 1] - crossings[index], 1).intersection(clip)
			if band.has_area():
				rectangles.append(band)
	return rectangles


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if material_texture != null:
		material_texture.draw_rect(to_canvas_item, rect, false)
		return
	var source: Rect2 = frame_rect(raised, layout, has_resources)
	var factor: Vector2 = rect.size / source.size
	var points: PackedVector2Array = outline_points(raised, layout, has_resources)
	points.resize(points.size() - 1)
	for index: int in points.size():
		points[index] = rect.position + (points[index] - source.position) * factor
	# 先绘制完整框面，再填充圆角开口；T形接点和两肩没有叠加描边。
	RenderingServer.canvas_item_add_polygon(to_canvas_item, points, PackedColorArray([border_color]))
	var surface := StyleBoxFlat.new()
	surface.bg_color = background_color
	surface.set_corner_radius_all(3)
	surface.corner_detail = 12
	for window: Rect2 in window_rects(raised, layout, has_resources):
		var opening: Rect2 = window.grow(-(maxf(border_width, 0.0) - 2.0) * 0.5)
		var target := Rect2(rect.position + (opening.position - source.position) * factor, opening.size * factor)
		surface.draw(to_canvas_item, target)
	if has_resources and layout != null:
		var resource_window: PackedVector2Array = layout.resource_window_points()
		resource_window.resize(resource_window.size() - 1)
		for index: int in resource_window.size():
			resource_window[index] = rect.position + (resource_window[index] - source.position) * factor
		RenderingServer.canvas_item_add_polygon(to_canvas_item, resource_window, PackedColorArray([background_color]))
