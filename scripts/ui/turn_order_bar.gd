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
const STATUS_COLOR := Color(0.72, 0.72, 0.78)

const BAR_WIDTH    := 180
const PORTRAIT_SZ  := 24
const ENTRY_SEP    := 2
const FONT_NAME    := 13
const FONT_INIT    := 11
const FONT_HEADER  := 14
const FONT_STATUS  := 10

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

	var portrait := PanelContainer.new()
	var portrait_style := StyleBoxFlat.new()
	portrait_style.bg_color = PLAYER_COLOR if unit.faction == "player" else ENEMY_COLOR
	portrait_style.corner_radius_top_left = 3
	portrait_style.corner_radius_top_right = 3
	portrait_style.corner_radius_bottom_left = 3
	portrait_style.corner_radius_bottom_right = 3
	portrait_style.content_margin_left = 0.0
	portrait_style.content_margin_right = 0.0
	portrait_style.content_margin_top = 0.0
	portrait_style.content_margin_bottom = 0.0
	portrait.add_theme_stylebox_override("panel", portrait_style)
	portrait.custom_minimum_size = Vector2(float(PORTRAIT_SZ), float(PORTRAIT_SZ))
	portrait.mouse_filter = MOUSE_FILTER_IGNORE
	hbox.add_child(portrait)

	var portrait_label := Label.new()
	portrait_label.text = unit.get_short_label()
	portrait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_label.size = Vector2(float(PORTRAIT_SZ), float(PORTRAIT_SZ))
	portrait_label.add_theme_font_size_override("font_size", FONT_NAME)
	portrait_label.add_theme_color_override("font_color", Color.WHITE)
	portrait_label.add_theme_color_override("font_outline_color", Color.BLACK)
	portrait_label.add_theme_constant_override("outline_size", 2)
	portrait_label.mouse_filter = MOUSE_FILTER_IGNORE
	portrait.add_child(portrait_label)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = SIZE_EXPAND_FILL
	text_box.mouse_filter = MOUSE_FILTER_IGNORE
	hbox.add_child(text_box)

	var name_lbl := Label.new()
	name_lbl.text = unit.unit_name
	name_lbl.add_theme_font_size_override("font_size", FONT_NAME)
	name_lbl.add_theme_color_override("font_color", NAME_COLOR)
	name_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	name_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	text_box.add_child(name_lbl)

	var status_lbl := Label.new()
	status_lbl.text = unit.get_action_status_summary()
	status_lbl.add_theme_font_size_override("font_size", FONT_STATUS)
	status_lbl.add_theme_color_override("font_color", STATUS_COLOR)
	status_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	text_box.add_child(status_lbl)

	var init_lbl := Label.new()
	init_lbl.text = "Init %d" % unit.stats.spd
	init_lbl.add_theme_font_size_override("font_size", FONT_INIT)
	init_lbl.add_theme_color_override("font_color", INIT_COLOR)
	init_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	init_lbl.mouse_filter = MOUSE_FILTER_IGNORE
	hbox.add_child(init_lbl)

	return panel
