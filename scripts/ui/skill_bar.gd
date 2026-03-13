class_name SkillBar
extends Control

signal skill_selected(skill_id: String)

const PANEL_SIZE: Vector2 = Vector2(330.0, 284.0)
const PANEL_BG: Color = Color(0.09, 0.06, 0.14, 0.88)
const PANEL_BORDER: Color = Color(0.83, 0.69, 0.22, 0.22)
const PANEL_GLOW: Color = Color(0.58, 0.20, 0.92, 0.15)
const PANEL_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.30)
const TEXT_MAIN: Color = Color(0.90, 0.86, 0.78, 1.0)
const TEXT_SUB: Color = Color(0.55, 0.56, 0.60, 1.0)
const TEXT_MUTE: Color = Color(0.45, 0.46, 0.50, 1.0)
const TEXT_DIM: Color = Color(0.36, 0.36, 0.40, 1.0)
const GOLD: Color = Color(0.72, 0.58, 0.28, 1.0)
const CARD_BG: Color = Color(0.07, 0.05, 0.11, 0.95)
const CARD_BG_HOVER: Color = Color(0.10, 0.08, 0.14, 0.95)
const CARD_BG_SELECTED: Color = Color(0.14, 0.10, 0.09, 0.95)
const CARD_BG_DISABLED: Color = Color(0.05, 0.04, 0.08, 0.90)
const CARD_BORDER: Color = Color(0.30, 0.25, 0.18, 0.70)
const CARD_BORDER_SELECTED: Color = Color(0.72, 0.58, 0.28, 0.92)
const CARD_HEIGHT: float = 54.0
const MAX_VISIBLE_ENTRIES: int = 4
const POPUP_OFFSET_Y: float = 10.0
const ANIM_SHOW_TIME: float = 0.15
const ANIM_HIDE_TIME: float = 0.12
const OVERLAY_COLOR: Color = Color(0.02, 0.03, 0.06, 0.66)
const POPUP_ICON_BG: Color = Color(0.10, 0.07, 0.16, 1.0)
const POPUP_SEP: Color = Color(0.83, 0.69, 0.22, 0.20)
const POPUP_CARD_GAP: int = 5

const COST_COLORS: Dictionary = {
	"move": Color(0.23, 0.51, 0.96, 1.0),
	"standard": Color(0.98, 0.45, 0.10, 1.0),
	"swift": Color(0.06, 0.72, 0.51, 1.0),
}

const COST_SYMBOLS: Dictionary = {
	"move": "M",
	"standard": "A",
	"swift": "S",
}

const COST_BADGES: Dictionary = {
	"move": "移动",
	"standard": "标准",
	"swift": "迅捷",
}

var _panel: PanelContainer = null
var _title_label: Label = null
var _subtitle_label: Label = null
var _scroll: ScrollContainer = null
var _list: VBoxContainer = null
var _empty_label: Label = null
var _expanded: bool = false
var _anim_tween: Tween = null
var _current_entries: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	size = PANEL_SIZE
	custom_minimum_size = PANEL_SIZE
	_build_ui()


func update_entries(entries: Array[Dictionary], selected_skill_id: String) -> void:
	_current_entries = entries.duplicate(true)
	for child: Node in _list.get_children():
		if child == _empty_label:
			continue
		child.queue_free()

	if _current_entries.is_empty():
		_empty_label.visible = true
		_empty_label.text = "当前没有可展示的技能。"
		return

	_empty_label.visible = false
	for entry: Dictionary in _current_entries:
		_list.add_child(_build_skill_card(entry, selected_skill_id))


func set_expanded(expanded: bool) -> void:
	if _expanded == expanded and visible == expanded:
		return
	_expanded = expanded
	if _anim_tween != null:
		_anim_tween.kill()

	if expanded:
		visible = true
		modulate = Color(1.0, 1.0, 1.0, 0.0)
		_panel.position.y = POPUP_OFFSET_Y
		_anim_tween = create_tween()
		_anim_tween.set_trans(Tween.TRANS_QUAD)
		_anim_tween.set_ease(Tween.EASE_OUT)
		_anim_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), ANIM_SHOW_TIME)
		_anim_tween.parallel().tween_property(_panel, "position:y", 0.0, ANIM_SHOW_TIME)
		return

	_anim_tween = create_tween()
	_anim_tween.set_trans(Tween.TRANS_QUAD)
	_anim_tween.set_ease(Tween.EASE_IN)
	_anim_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 0.0), ANIM_HIDE_TIME)
	_anim_tween.parallel().tween_property(_panel, "position:y", POPUP_OFFSET_Y, ANIM_HIDE_TIME)
	_anim_tween.finished.connect(_on_hide_finished, CONNECT_ONE_SHOT)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	_panel.add_child(margin)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)

	# Header: circle icon + title/subtitle
	var header_row: HBoxContainer = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	header_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.add_child(header_row)

	var circle_bg: PanelContainer = PanelContainer.new()
	circle_bg.custom_minimum_size = Vector2(26.0, 26.0)
	circle_bg.add_theme_stylebox_override("panel", _make_circle_style())
	header_row.add_child(circle_bg)

	var circle_label: Label = Label.new()
	circle_label.text = "★"
	circle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	circle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	circle_label.add_theme_font_size_override("font_size", 12)
	circle_label.add_theme_color_override("font_color", GOLD)
	circle_bg.add_child(circle_label)

	var title_col: VBoxContainer = VBoxContainer.new()
	title_col.add_theme_constant_override("separation", 1)
	header_row.add_child(title_col)

	_title_label = Label.new()
	_title_label.text = "技能刻印"
	_title_label.add_theme_font_size_override("font_size", 11)
	_title_label.add_theme_color_override("font_color", GOLD)
	title_col.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.text = "选择一个可用技能并进入目标确认。"
	_subtitle_label.add_theme_font_size_override("font_size", 8)
	_subtitle_label.add_theme_color_override("font_color", TEXT_SUB)
	title_col.add_child(_subtitle_label)

	var divider: ColorRect = ColorRect.new()
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	divider.color = POPUP_SEP
	column.add_child(divider)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", POPUP_CARD_GAP)
	_scroll.add_child(_list)

	_empty_label = Label.new()
	_empty_label.visible = false
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.custom_minimum_size = Vector2(PANEL_SIZE.x - 40.0, CARD_HEIGHT * 2.0)
	_empty_label.text = "当前没有可展示的技能。"
	_empty_label.add_theme_font_size_override("font_size", 10)
	_empty_label.add_theme_color_override("font_color", TEXT_MUTE)
	_list.add_child(_empty_label)

	_scroll.get_v_scroll_bar().modulate = Color(1.0, 1.0, 1.0, 0.0)


func _build_skill_card(entry: Dictionary, selected_skill_id: String) -> Control:
	var skill_id: String = str(entry.get("skill_id", ""))
	var skill_name: String = str(entry.get("name", skill_id))
	var action_cost: String = str(entry.get("action_cost", "standard"))
	var timing_constraint: String = str(entry.get("timing_constraint", "any"))
	var cooldown_turns: int = int(entry.get("cooldown", 0))
	var available: bool = bool(entry.get("available", false))
	var reason: String = str(entry.get("reason", ""))
	var badge_text: String = str(entry.get("badge_text", COST_BADGES.get(action_cost, "战技")))
	var icon_text: String = str(entry.get("icon_text", COST_SYMBOLS.get(action_cost, "技")))
	var is_selected: bool = skill_id == selected_skill_id
	var accent: Color = _get_cost_color(action_cost)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(0.0, CARD_HEIGHT)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_card_style(accent, is_selected, available))

	var click_target: Button = Button.new()
	click_target.flat = true
	click_target.focus_mode = Control.FOCUS_NONE
	click_target.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	click_target.disabled = not available or skill_id == ""
	click_target.tooltip_text = reason
	click_target.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	click_target.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	click_target.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	click_target.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	click_target.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	card.add_child(click_target)
	if not click_target.disabled:
		click_target.pressed.connect(_on_card_pressed.bind(skill_id))

	var inner_margin: MarginContainer = MarginContainer.new()
	inner_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner_margin.add_theme_constant_override("margin_left", 8)
	inner_margin.add_theme_constant_override("margin_right", 8)
	inner_margin.add_theme_constant_override("margin_top", 5)
	inner_margin.add_theme_constant_override("margin_bottom", 5)
	card.add_child(inner_margin)

	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	inner_margin.add_child(row)

	var icon_slot: PanelContainer = PanelContainer.new()
	icon_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_slot.custom_minimum_size = Vector2(28.0, 28.0)
	icon_slot.add_theme_stylebox_override("panel", _make_icon_slot_style(accent, available))
	row.add_child(icon_slot)

	var icon_label: Label = Label.new()
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_label.text = icon_text
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 13)
	icon_label.add_theme_color_override("font_color", TEXT_MAIN if available else TEXT_DIM)
	icon_slot.add_child(icon_label)

	var text_column: VBoxContainer = VBoxContainer.new()
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 1)
	row.add_child(text_column)

	var title_label: Label = Label.new()
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.text = skill_name
	title_label.add_theme_font_size_override("font_size", 11)
	title_label.add_theme_color_override("font_color", TEXT_MAIN if available else TEXT_MUTE)
	text_column.add_child(title_label)

	var detail_label: Label = Label.new()
	detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_label.text = _build_detail_text(action_cost, timing_constraint, cooldown_turns, available, reason)
	detail_label.add_theme_font_size_override("font_size", 8)
	detail_label.add_theme_color_override("font_color", TEXT_SUB if available else TEXT_MUTE)
	text_column.add_child(detail_label)

	var badge_label: Label = Label.new()
	badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_label.text = badge_text
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_label.add_theme_font_size_override("font_size", 7)
	badge_label.add_theme_color_override("font_color", accent if available else TEXT_DIM)
	row.add_child(badge_label)

	if cooldown_turns > 0:
		var overlay: ColorRect = ColorRect.new()
		overlay.color = OVERLAY_COLOR
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.add_child(overlay)

		var cooldown_box: CenterContainer = CenterContainer.new()
		cooldown_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.add_child(cooldown_box)

		var cooldown_column: VBoxContainer = VBoxContainer.new()
		cooldown_column.alignment = BoxContainer.ALIGNMENT_CENTER
		cooldown_column.add_theme_constant_override("separation", -3)
		cooldown_box.add_child(cooldown_column)

		var cooldown_label: Label = Label.new()
		cooldown_label.text = str(cooldown_turns)
		cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cooldown_label.add_theme_font_size_override("font_size", 18)
		cooldown_label.add_theme_color_override("font_color", accent)
		cooldown_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.04, 0.92))
		cooldown_label.add_theme_constant_override("outline_size", 3)
		cooldown_column.add_child(cooldown_label)

		var turn_label: Label = Label.new()
		turn_label.text = "回合"
		turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		turn_label.add_theme_font_size_override("font_size", 8)
		turn_label.add_theme_color_override("font_color", TEXT_MAIN)
		cooldown_column.add_child(turn_label)

	return card


func _build_detail_text(
	action_cost: String,
	timing_constraint: String,
	cooldown_turns: int,
	available: bool,
	reason: String
) -> String:
	if cooldown_turns > 0:
		return "冷却中 · 剩余 %d 回合" % cooldown_turns
	if not available and reason != "":
		return reason
	return "%s · %s" % [_localize_cost(action_cost), _localize_timing(timing_constraint)]


func _localize_cost(action_cost: String) -> String:
	match action_cost:
		"move":
			return "移动资源"
		"swift":
			return "迅捷资源"
		_:
			return "标准资源"


func _localize_timing(timing_constraint: String) -> String:
	match timing_constraint:
		"move_phase":
			return "移动阶段"
		"action_phase":
			return "行动阶段"
		"swift_phase":
			return "迅捷阶段"
		_:
			return "任意时机"


func _get_cost_color(action_cost: String) -> Color:
	if COST_COLORS.has(action_cost):
		return COST_COLORS[action_cost]
	return Color(0.80, 0.66, 0.34, 1.0)


func _make_panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.shadow_color = PANEL_GLOW
	style.shadow_size = 12
	return style


func _make_circle_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = POPUP_ICON_BG
	style.border_color = GOLD * Color(1.0, 1.0, 1.0, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(13)
	return style


func _make_card_style(accent: Color, selected: bool, available: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = CARD_BG
	if not available:
		style.bg_color = CARD_BG_DISABLED
	elif selected:
		style.bg_color = CARD_BG_SELECTED
	style.border_color = CARD_BORDER_SELECTED if selected else accent * Color(1.0, 1.0, 1.0, 0.35)
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.set_corner_radius_all(3)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.18)
	style.shadow_size = 2
	return style


func _make_icon_slot_style(accent: Color, available: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = POPUP_ICON_BG if available else Color(0.06, 0.05, 0.09, 1.0)
	style.border_color = accent * Color(1.0, 1.0, 1.0, 0.35) if available else Color(0.28, 0.28, 0.30, 0.50)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	return style


func _on_card_pressed(skill_id: String) -> void:
	skill_selected.emit(skill_id)


func _on_hide_finished() -> void:
	if not _expanded:
		visible = false
