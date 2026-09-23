class_name HudM2SwordResourcePanel
extends Control

## 中性剑体、沿刃裁切的能量层、流线和数字分别绘制，保留定版透明图层。
var _view: HudM2SwordResourceViewData
var _geometry: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_changed.connect(queue_redraw)


func apply_view(view: HudM2SwordResourceViewData, geometry: Dictionary) -> void:
	_view = view
	_geometry = geometry
	queue_redraw()


func _draw() -> void:
	if _view == null or _view.qi == null or _geometry.is_empty():
		return
	var base: Texture2D = get_theme_icon(&"sword_base", &"HudM2FrozenResource")
	var high: bool = _view.band == &"high"
	var energy: Texture2D = get_theme_icon(&"sword_energy_high" if high else &"sword_energy_low", &"HudM2FrozenResource")
	var flow: Texture2D = get_theme_icon(&"sword_flow_high" if high else &"sword_flow_low", &"HudM2FrozenResource")
	draw_texture_rect(base, _geometry["base"], false)
	var ratio: float = clampf(_view.qi.ratio, 0.0, 1.0)
	if ratio > 0.0:
		var energy_rect: Rect2 = _geometry["energy"]
		var cropped: Rect2 = Rect2(energy_rect.position, Vector2(energy_rect.size.x * ratio, energy_rect.size.y))
		var source: Rect2 = Rect2(Vector2.ZERO, Vector2(energy.get_width() * ratio, energy.get_height()))
		draw_texture_rect_region(energy, cropped, source)
		# Penpot 的流线是独立于裁切板的悬浮图层，保留完整剑刃上的定版形态。
		draw_texture_rect(flow, _geometry["flow"], false)
	var number: String = str(_view.qi.current_value)
	var number_rect: Rect2 = _geometry["number"]
	var font: Font = get_theme_font(&"number", &"HudM2FrozenResource")
	var font_size: int = get_theme_font_size(&"number", &"HudM2FrozenResource")
	var color: Color = get_theme_color(&"number", &"HudM2FrozenResource")
	var width: float = font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline: Vector2 = Vector2(number_rect.position.x + (number_rect.size.x - width) * 0.5, number_rect.position.y + number_rect.size.y * 0.76)
	draw_string(font, baseline, number, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
