class_name TurnOrderBar
extends PanelContainer
## Proposal B — Classic TRPG turn order display.
## Shows current turn queue with faction color indicators and initiative.

const PLAYER_COLOR := Color(0.27, 0.53, 0.87)
const ENEMY_COLOR  := Color(0.87, 0.27, 0.27)
const CURRENT_BG   := Color(1.0, 0.90, 0.40, 0.12)
const HEADER_COLOR := Color(0.65, 0.65, 0.75)
const NAME_COLOR   := Color.WHITE
const INIT_COLOR   := Color(0.55, 0.55, 0.60)

const BAR_WIDTH    := 180
const INDICATOR_SZ := 16
const ENTRY_SEP    := 2
const FONT_NAME    := 13
const FONT_INIT    := 11
const FONT_HEADER  := 14

var _vbox: VBoxContainer


func _ready() -> void:
	position = Vector2(1080.0, 10.0)
	custom_minimum_size = Vector2(float(BAR_WIDTH), 0.0)
	mouse_filter = MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.10, 0.85)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.06, 0.06, 0.08)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", style)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", ENTRY_SEP)
	add_child(_vbox)

	var header := Label.new()
	header.text = "Turn Order"
	header.add_theme_font_size_override("font_size", FONT_HEADER)
	header.add_theme_color_override("font_color", HEADER_COLOR)
	header.mouse_filter = MOUSE_FILTER_IGNORE
	_vbox.add_child(header)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	_vbox.add_child(sep)


func update_queue(display_queue: Array[Unit], current: Unit) -> void:
	_clear_entries()
	for unit in display_queue:
		_vbox.add_child(_create_entry(unit, unit == current))


func _clear_entries() -> void:
	for i in range(_vbox.get_child_count() - 1, 1, -1):
		var child := _vbox.get_child(i)
		_vbox.remove_child(child)
		child.queue_free()


func _create_entry(unit: Unit, is_current: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = CURRENT_BG if is_current else Color.TRANSPARENT
	ps.content_margin_left = 4.0
	ps.content_margin_right = 4.0
	ps.content_margin_top = 2.0
	ps.content_margin_bottom = 2.0
	panel.add_theme_stylebox_override("panel", ps)
	panel.mouse_filter = MOUSE_FILTER_IGNORE

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	# Faction color indicator (portrait placeholder)
	var indicator := ColorRect.new()
	indicator.custom_minimum_size = Vector2(float(INDICATOR_SZ), float(INDICATOR_SZ))
	indicator.color = PLAYER_COLOR if unit.faction == "player" else ENEMY_COLOR
	indicator.mouse_filter = MOUSE_FILTER_IGNORE
	hbox.add_child(indicator)

	var name_lbl := Label.new()
	name_lbl.text = unit.unit_name
	name_lbl.add_theme_font_size_override("font_size", FONT_NAME)
	name_lbl.add_theme_color_override("font_color", NAME_COLOR)
	name_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	name_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	hbox.add_child(name_lbl)

	var init_lbl := Label.new()
	init_lbl.text = "Init %d" % unit.stats.spd
	init_lbl.add_theme_font_size_override("font_size", FONT_INIT)
	init_lbl.add_theme_color_override("font_color", INIT_COLOR)
	init_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	init_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	hbox.add_child(init_lbl)

	return panel
