class_name HudM2ClassResourceHost
extends Control

## 职业资源通用宿主。新增职业可注册自己的 renderer，布局与皮肤不进入数据适配器。
const SwordScene: PackedScene = preload("res://scenes/tactical/hud/m2/sword_resource_panel.tscn")

var _view: HudM2ClassResourceViewData
var _layout: HudM2ClassResourceLayout
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
		_renderer = SwordScene.instantiate() as Control
		_renderer_key = view.renderer_key
		add_child(_renderer)
	_refresh_layout()


func set_layout(layout: HudM2ClassResourceLayout) -> void:
	_layout = layout
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
		_renderer.apply_view(_view.body, _layout.geometry())


func get_input_blocking_rects() -> Array[Rect2]:
	if is_visible_in_tree():
		return [get_global_rect()]
	return []
