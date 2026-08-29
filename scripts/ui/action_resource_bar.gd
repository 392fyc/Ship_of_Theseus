class_name ActionResourceBar
extends PanelContainer

const RESOURCE_DEFINITIONS: Array[Dictionary] = [
	{"id": "movement", "flag": "movement_used", "title": "M 移动", "accent": Color("#6FAED1")},
	{"id": "standard", "flag": "standard_used", "title": "A 行动", "accent": Color("#D17A50")},
	{"id": "swift", "flag": "swift_used", "title": "S 迅捷", "accent": Color("#D5BC59")},
]

const SHELL_BACKGROUND: Color = Color("#0A0B12F5")
const SHELL_BORDER: Color = Color("#8F743D")
const TEXT_AVAILABLE: Color = Color("#E5DBCB")
const TEXT_SPENT: Color = Color("#6C6872")
const SEGMENT_SIZE: Vector2 = Vector2(76.0, 30.0)

var _segments: Dictionary = {}
var _row: HBoxContainer = null


func _ready() -> void:
	_build_segments()
	visible = false


func update_resources(resources: Dictionary) -> void:
	if not _has_all_resource_flags(resources):
		clear_resources()
		return
	_build_segments()
	for definition: Dictionary in RESOURCE_DEFINITIONS:
		var resource_id: String = str(definition["id"])
		var flag: String = str(definition["flag"])
		(_segments[resource_id] as ResourceSegment).set_spent(bool(resources.get(flag, false)))
	visible = true


func clear_resources() -> void:
	visible = false


func _has_all_resource_flags(resources: Dictionary) -> bool:
	for definition: Dictionary in RESOURCE_DEFINITIONS:
		if not resources.has(str(definition["flag"])):
			return false
	return true


func _build_segments() -> void:
	if not _segments.is_empty():
		return
	custom_minimum_size = Vector2(248.0, 38.0)
	add_theme_stylebox_override("panel", _make_shell_style())

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	add_child(margin)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 4)
	margin.add_child(_row)
	for definition: Dictionary in RESOURCE_DEFINITIONS:
		var resource_id: String = str(definition["id"])
		var segment: ResourceSegment = ResourceSegment.new(definition)
		_segments[resource_id] = segment
		_row.add_child(segment)


func _make_shell_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = SHELL_BACKGROUND
	style.border_color = SHELL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	return style


class ResourceGlyph extends Control:
	var accent_color: Color
	var spent: bool = false

	func _init(accent: Color) -> void:
		accent_color = accent
		custom_minimum_size = Vector2(14.0, 18.0)

	func set_spent(value: bool) -> void:
		spent = value
		queue_redraw()

	func _draw() -> void:
		var center: Vector2 = size * 0.5
		var radius: float = 6.0
		var glyph_color: Color = TEXT_SPENT if spent else accent_color
		var points: PackedVector2Array = PackedVector2Array([
			center + Vector2(0.0, -radius),
			center + Vector2(radius, 0.0),
			center + Vector2(0.0, radius),
			center + Vector2(-radius, 0.0),
		])
		draw_colored_polygon(points, glyph_color)
		if spent:
			draw_line(center + Vector2(-5.0, 4.0), center + Vector2(5.0, -4.0), Color("#0A0B12"), 2.0, true)


class ResourceSegment extends PanelContainer:
	var spent: bool = false
	var glyph: ResourceGlyph
	var title_label: Label
	var state_label: Label
	var _accent_color: Color

	func _init(definition: Dictionary) -> void:
		_accent_color = definition["accent"] as Color
		custom_minimum_size = SEGMENT_SIZE
		_build_content(str(definition["title"]))
		set_spent(false)

	func set_spent(value: bool) -> void:
		spent = value
		glyph.set_spent(value)
		title_label.add_theme_color_override("font_color", TEXT_SPENT if value else TEXT_AVAILABLE)
		state_label.text = "已用" if value else "可用"
		state_label.add_theme_color_override("font_color", TEXT_SPENT if value else _accent_color)
		add_theme_stylebox_override("panel", _make_style(value))

	func _build_content(title: String) -> void:
		var margin: MarginContainer = MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 4)
		margin.add_theme_constant_override("margin_right", 4)
		margin.add_theme_constant_override("margin_top", 3)
		margin.add_theme_constant_override("margin_bottom", 3)
		add_child(margin)

		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		margin.add_child(row)

		glyph = ResourceGlyph.new(_accent_color)
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(glyph)

		var text_column: VBoxContainer = VBoxContainer.new()
		text_column.add_theme_constant_override("separation", -2)
		text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text_column)

		title_label = Label.new()
		title_label.text = title
		title_label.add_theme_font_size_override("font_size", 10)
		text_column.add_child(title_label)

		state_label = Label.new()
		state_label.add_theme_font_size_override("font_size", 8)
		text_column.add_child(state_label)

	func _make_style(is_spent: bool) -> StyleBoxFlat:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color("#23232A") if is_spent else Color("#121722")
		style.border_color = TEXT_SPENT if is_spent else _accent_color
		style.set_border_width_all(1)
		style.set_corner_radius_all(2)
		return style
