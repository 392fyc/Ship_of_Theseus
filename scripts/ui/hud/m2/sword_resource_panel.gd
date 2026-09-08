class_name HudM2SwordResourcePanel
extends Control

var _view: HudM2SwordResourceViewData
var _geometry: Dictionary = {}
var _labels: Dictionary = {}
var _mark_labels: Array[Label] = []
var _fill: ColorRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key: String in ["qi_label", "qi_value", "mark_label"]:
		var label := Label.new()
		label.name = key.to_pascal_case()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.theme_type_variation = &"HudM2NumericLabel" if key == "qi_value" else &"HudM2Text"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if key == "qi_value" else HORIZONTAL_ALIGNMENT_LEFT
		add_child(label)
		_labels[key] = label
	_fill = ColorRect.new()
	_fill.name = "QiFill"
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)
	# 刻度与阈值在连续填充之后绘制。
	var overlay := Control.new()
	overlay.name = "TrackOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	overlay.draw.connect(_draw_track_overlay.bind(overlay))
	theme_changed.connect(_refresh)
	_refresh()


func apply_view(view: HudM2SwordResourceViewData, geometry: Dictionary) -> void:
	_view = view
	_geometry = geometry
	if is_node_ready():
		_refresh()


func _local(key: String) -> Rect2:
	var rect: Rect2 = _geometry[key]
	return Rect2(rect.position - (_geometry["bounds"] as Rect2).position, rect.size)


func _refresh() -> void:
	if not is_node_ready() or _view == null or _geometry.is_empty():
		return
	for key: String in _labels:
		var label: Label = _labels[key]
		var rect: Rect2 = _local(key)
		label.position = rect.position
		label.size = rect.size
		label.visible = rect.has_area()
		label.add_theme_font_size_override(&"font_size", get_theme_font_size(StringName(key), &"HudM2ClassResource"))
		label.add_theme_color_override(&"font_color", get_theme_color(&"mark_label" if key == "mark_label" else &"text", &"HudM2ClassResource"))
	(_labels["qi_label"] as Label).text = "剑气"
	(_labels["qi_value"] as Label).text = _view.qi.display_text
	(_labels["mark_label"] as Label).text = "剑意印记"
	var fill_rect: Rect2 = _local("qi_fill")
	_fill.position = fill_rect.position
	_fill.size = Vector2(fill_rect.size.x * _view.qi.ratio, fill_rect.size.y)
	_fill.color = _band_color()
	var slots: Array = _geometry["mark_slots"]
	var count: int = mini(_view.mark_capacity, slots.size()) if _view.marks_visible else 0
	while _mark_labels.size() > count:
		var obsolete: Label = _mark_labels.pop_back()
		remove_child(obsolete)
		obsolete.queue_free()
	while _mark_labels.size() < count:
		var label := Label.new()
		label.name = "Mark%d" % _mark_labels.size()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.theme_type_variation = &"HudM2Text"
		add_child(label)
		_mark_labels.append(label)
	for index: int in count:
		var rect: Rect2 = slots[index]
		var label: Label = _mark_labels[index]
		label.position = rect.position - (_geometry["bounds"] as Rect2).position
		label.size = rect.size
		label.text = str(_view.marks[index]["display_text"]) if index < _view.marks.size() else ""
		label.add_theme_font_size_override(&"font_size", get_theme_font_size(&"mark", &"HudM2ClassResource"))
		label.add_theme_color_override(&"font_color", get_theme_color(&"mark_text", &"HudM2ClassResource"))
	queue_redraw()
	$TrackOverlay.queue_redraw()


func _band_color() -> Color:
	return get_theme_color(&"qi_high" if _view.band == &"high" else &"qi_low", &"HudM2ClassResource")


func _draw() -> void:
	if _view == null or _geometry.is_empty():
		return
	draw_rect(_local("qi_track"), get_theme_color(&"track", &"HudM2ClassResource"))
	draw_rect(_local("qi_track"), get_theme_color(&"track_edge", &"HudM2ClassResource"), false, 1.0)
	if _view.marks_visible:
		var divider_rect: Rect2 = _local("divider")
		draw_line(divider_rect.position, divider_rect.end, get_theme_color(&"divider", &"HudM2ClassResource"), 1.2)
		for index: int in _mark_labels.size():
			var rect: Rect2 = _mark_labels[index].get_rect()
			draw_style_box(get_theme_stylebox(&"mark_slot", &"HudM2ClassResource"), rect)
			if index < _view.marks.size():
				draw_rect(rect.grow(-2), get_theme_color(&"mark_fill", &"HudM2ClassResource"))
				draw_rect(rect.grow(-0.5), get_theme_color(&"mark_edge", &"HudM2ClassResource"), false, 1.0)


func _draw_track_overlay(overlay: Control) -> void:
	if _view == null or _geometry.is_empty():
		return
	var rect: Rect2 = _local("qi_fill")
	for index: int in range(1, 10):
		var x: float = rect.position.x + rect.size.x * float(index) / 10.0
		overlay.draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), get_theme_color(&"tick", &"HudM2ClassResource"), 0.7)
	if _view.threshold_ratio >= 0.0:
		var x: float = rect.position.x + rect.size.x * _view.threshold_ratio
		overlay.draw_line(Vector2(x, rect.position.y - 3), Vector2(x, rect.end.y + 2), get_theme_color(&"threshold", &"HudM2ClassResource"), 1.0)
