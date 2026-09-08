class_name HudM2ClassResourceHost
extends Control

const SwordScene := preload("res://scenes/tactical/hud/m2/sword_resource_panel.tscn")
const FrameStyle := preload("res://scripts/ui/hud/m2/shared_frame_style.gd")
var _view: HudM2ClassResourceViewData
var _layout: HudM2ClassResourceLayout
var _has_actions: bool = false
var _renderer_key: StringName = &""
var _renderer: Control


func apply_view(view: HudM2ClassResourceViewData) -> void:
	_view = view
	visible = view != null and view.visible and view.body != null and view.renderer_key == &"sword"
	if not visible:
		return
	if _renderer_key != view.renderer_key:
		if _renderer != null:
			remove_child(_renderer)
			_renderer.queue_free()
		_renderer = SwordScene.instantiate()
		_renderer_key = view.renderer_key
		add_child(_renderer)
	_refresh_layout()


func set_layout(layout: HudM2ClassResourceLayout, has_actions: bool) -> void:
	_layout = layout
	_has_actions = has_actions
	_refresh_layout()


func get_renderer() -> Control:
	return _renderer


func _refresh_layout() -> void:
	if _layout == null:
		return
	position = _layout.bounds.position
	size = _layout.bounds.size
	if _renderer != null and _view != null and visible:
		_renderer.size = size
		_renderer.apply_view(_view.body, _layout.geometry(_has_actions, _view.body.marks_visible))


func _has_point(point: Vector2) -> bool:
	return _layout != null and Rect2(Vector2.ZERO, size).has_point(point) and Geometry2D.is_point_in_polygon(point + position, _layout.outline_points(_has_actions))


func get_input_blocking_rects() -> Array[Rect2]:
	var rectangles: Array[Rect2] = []
	if not is_visible_in_tree() or _layout == null:
		return rectangles
	# 资源主体和右肩的可命中面与共享框使用同一轮廓。
	var transform: Transform2D = get_global_transform()
	for rectangle: Rect2 in FrameStyle.scanline_rects(_layout.outline_points(_has_actions), _layout.bounds):
		rectangles.append(transform * Rect2(rectangle.position - _layout.bounds.position, rectangle.size))
	return rectangles
