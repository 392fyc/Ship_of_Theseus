class_name SkillBar
extends Control

signal skill_selected(skill_id: String)

# --- Color Palette ---
const PANEL_BG: Color = Color(0.05, 0.08, 0.14, 0.98)
const PANEL_BORDER: Color = Color(0.72, 0.62, 0.38, 0.85)
const CARD_BG: Color = Color(0.08, 0.12, 0.20, 1.0)
const CARD_BG_DISABLED: Color = Color(0.06, 0.08, 0.13, 1.0)
const CARD_BG_SELECTED: Color = Color(0.12, 0.17, 0.28, 1.0)
const CARD_BORDER: Color = Color(0.26, 0.32, 0.44, 1.0)
const CARD_BORDER_SELECTED: Color = Color(0.82, 0.71, 0.43, 1.0)
const TEXT_MAIN: Color = Color(0.96, 0.93, 0.86, 1.0)
const TEXT_MUTED: Color = Color(0.62, 0.67, 0.76, 1.0)
const TEXT_DISABLED: Color = Color(0.40, 0.44, 0.52, 1.0)
const COOLDOWN_MASK: Color = Color(0.0, 0.0, 0.0, 0.70)

# --- Layout ---
const CARD_MIN_HEIGHT: float = 62.0
const CARD_MIN_WIDTH: float = 248.0
const ACCENT_LINE_WIDTH: float = 3.0
const BADGE_SIZE: Vector2 = Vector2(30.0, 26.0)

const COST_COLORS: Dictionary = {
	"move": Color("3b82f6"),
	"standard": Color("f97316"),
	"swift": Color("10b981"),
	"reaction": Color(0.52, 0.52, 0.52, 1.0),
}

const COST_SYMBOLS: Dictionary = {
	"move": "靴",
	"standard": "剑",
	"swift": "◆",
	"reaction": "被",
}

var _panel: PanelContainer = null
var _header_label: Label = null
var _header_hint: Label = null
var _scroll: ScrollContainer = null
var _row: VBoxContainer = null
var _anim_tween: Tween = null
var _is_expanded: bool = false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(280.0, 256.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	modulate.a = 0.0
	_build_ui()
	_panel.position.y = 6.0


func update_entries(entries: Array[Dictionary], selected_skill_id: String) -> void:
	for child: Node in _row.get_children():
		child.queue_free()

	for entry: Dictionary in entries:
		_row.add_child(_build_skill_card(entry, selected_skill_id))

	_header_label.text = "技能序列"
	_header_hint.text = ""
	_header_hint.visible = false


func set_expanded(expanded: bool) -> void:
	if _is_expanded == expanded:
		if not expanded:
			visible = false
		return

	_is_expanded = expanded
	if _anim_tween != null and _anim_tween.is_running():
		_anim_tween.kill()

	if expanded:
		visible = true
		_anim_tween = create_tween().set_parallel(true)
		_anim_tween.tween_property(self, "modulate:a", 1.0, 0.15) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		_anim_tween.tween_property(_panel, "position:y", 0.0, 0.15) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	else:
		_anim_tween = create_tween().set_parallel(true)
		_anim_tween.tween_property(self, "modulate:a", 0.0, 0.12) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		_anim_tween.tween_property(_panel, "position:y", 6.0, 0.12) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		_anim_tween.finished.connect(func() -> void:
			visible = false
		)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_panel.add_child(margin)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	var header_row: HBoxContainer = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	column.add_child(header_row)

	_header_label = Label.new()
	_header_label.add_theme_font_size_override("font_size", 12)
	_header_label.add_theme_color_override("font_color", TEXT_MAIN)
	header_row.add_child(_header_label)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)

	_header_hint = Label.new()
	_header_hint.add_theme_font_size_override("font_size", 10)
	_header_hint.add_theme_color_override("font_color", TEXT_MUTED)
	header_row.add_child(_header_hint)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.custom_minimum_size = Vector2(0.0, 214.0)
	column.add_child(_scroll)

	_row = VBoxContainer.new()
	_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_theme_constant_override("separation", 8)
	_scroll.add_child(_row)


func _build_skill_card(entry: Dictionary, selected_skill_id: String) -> Control:
	var skill_id: String = str(entry.get("skill_id", ""))
	var skill_name: String = str(entry.get("name", skill_id))
	var action_cost: String = str(entry.get("action_cost", "standard"))
	var cooldown_turns: int = int(entry.get("cooldown", 0))
	var available: bool = bool(entry.get("available", false))
	var is_selected: bool = skill_id == selected_skill_id

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_MIN_WIDTH, CARD_MIN_HEIGHT)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.tooltip_text = ""
	card.add_theme_stylebox_override("panel", _make_card_style(action_cost, is_selected, available))

	# Left accent line (replaces top bar)
	var accent_line: ColorRect = ColorRect.new()
	accent_line.color = COST_COLORS.get(action_cost, Color(0.6, 0.6, 0.6, 1.0))
	if not available and cooldown_turns <= 0:
		accent_line.color = accent_line.color.darkened(0.50)
	accent_line.anchor_bottom = 1.0
	accent_line.offset_left = 0.0
	accent_line.offset_top = 6.0
	accent_line.offset_right = ACCENT_LINE_WIDTH
	accent_line.offset_bottom = -6.0
	accent_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(accent_line)

	var button: Button = Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.anchor_right = 1.0
	button.anchor_bottom = 1.0
	button.offset_left = 0.0
	button.offset_top = 0.0
	button.offset_right = 0.0
	button.offset_bottom = 0.0
	button.disabled = not available
	button.tooltip_text = ""
	button.pressed.connect(_on_skill_pressed.bind(skill_id))
	card.add_child(button)

	var margin: MarginContainer = MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	button.add_child(margin)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)

	var top_row: HBoxContainer = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	column.add_child(top_row)

	var title: Label = Label.new()
	title.text = skill_name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.max_lines_visible = 1
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", TEXT_MAIN if available else TEXT_DISABLED)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(title)

	top_row.add_child(_create_badge(action_cost))

	var detail_label: Label = Label.new()
	detail_label.text = "%s  ·  %s" % [
		_get_timing_label(str(entry.get("timing_constraint", "any"))),
		_get_state_label(action_cost, available, cooldown_turns),
	]
	detail_label.clip_text = true
	detail_label.max_lines_visible = 1
	detail_label.add_theme_font_size_override("font_size", 10)
	detail_label.add_theme_color_override("font_color", _get_state_label_color(available, cooldown_turns))
	detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(detail_label)

	# Cooldown overlay
	if cooldown_turns > 0:
		var mask: ColorRect = ColorRect.new()
		mask.color = COOLDOWN_MASK
		mask.anchor_right = 1.0
		mask.anchor_bottom = 1.0
		mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(mask)

		var cd_column: VBoxContainer = VBoxContainer.new()
		cd_column.anchor_right = 1.0
		cd_column.anchor_bottom = 1.0
		cd_column.alignment = BoxContainer.ALIGNMENT_CENTER
		cd_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(cd_column)

		var cd_label: Label = Label.new()
		cd_label.text = str(cooldown_turns)
		cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd_label.add_theme_font_size_override("font_size", 26)
		cd_label.add_theme_color_override("font_color", TEXT_MAIN)
		var cost_color: Color = COST_COLORS.get(action_cost, Color(0.6, 0.6, 0.6, 1.0))
		cd_label.add_theme_color_override("font_outline_color", cost_color.darkened(0.40))
		cd_label.add_theme_constant_override("outline_size", 4)
		cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd_column.add_child(cd_label)

		var cd_hint: Label = Label.new()
		cd_hint.text = "回合"
		cd_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd_hint.add_theme_font_size_override("font_size", 9)
		cd_hint.add_theme_color_override("font_color", TEXT_MUTED)
		cd_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd_column.add_child(cd_hint)

	return card


func _create_badge(action_cost: String) -> PanelContainer:
	var badge: PanelContainer = PanelContainer.new()
	badge.custom_minimum_size = BADGE_SIZE
	badge.add_theme_stylebox_override("panel", _make_badge_style(action_cost))

	var badge_margin: MarginContainer = MarginContainer.new()
	badge_margin.add_theme_constant_override("margin_left", 6)
	badge_margin.add_theme_constant_override("margin_right", 6)
	badge_margin.add_theme_constant_override("margin_top", 3)
	badge_margin.add_theme_constant_override("margin_bottom", 3)
	badge.add_child(badge_margin)

	var badge_label: Label = Label.new()
	badge_label.text = str(COST_SYMBOLS.get(action_cost, "?"))
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_label.add_theme_font_size_override("font_size", 12)
	badge_label.add_theme_color_override("font_color", COST_COLORS.get(action_cost, Color.WHITE))
	badge_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.50))
	badge_label.add_theme_constant_override("outline_size", 1)
	badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_margin.add_child(badge_label)

	return badge


func _make_panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.25)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0.0, 3.0)
	return style


func _make_card_style(action_cost: String, is_selected: bool, available: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = CARD_BG_SELECTED if is_selected else (CARD_BG if available else CARD_BG_DISABLED)
	style.border_color = CARD_BORDER_SELECTED if is_selected else CARD_BORDER
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	var cost_color: Color = COST_COLORS.get(action_cost, Color(0.4, 0.4, 0.4, 1.0))
	if is_selected:
		style.shadow_color = _with_alpha(cost_color.darkened(0.40), 0.30)
		style.shadow_size = 10
		style.shadow_offset = Vector2(0.0, 4.0)
	elif available:
		style.shadow_color = _with_alpha(cost_color.darkened(0.65), 0.15)
		style.shadow_size = 6
		style.shadow_offset = Vector2(0.0, 3.0)
	return style


func _make_badge_style(action_cost: String) -> StyleBoxFlat:
	var cost_color: Color = COST_COLORS.get(action_cost, Color(0.55, 0.55, 0.55, 1.0))
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.14, 1.0)
	style.border_color = cost_color.darkened(0.15)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = _with_alpha(cost_color.darkened(0.50), 0.20)
	style.shadow_size = 3
	style.shadow_offset = Vector2(0.0, 1.0)
	return style


func _get_timing_label(timing_constraint: String) -> String:
	match timing_constraint:
		"before_move":
			return "移动前使用"
		"after_move":
			return "移动后使用"
		"before_attack":
			return "攻击前使用"
		"after_attack":
			return "攻击后使用"
		_:
			return "任意时机"


func _get_state_label(action_cost: String, available: bool, cooldown_turns: int) -> String:
	if cooldown_turns > 0:
		return "冷却中"
	if not available:
		return "不可用"
	match action_cost:
		"move":
			return "移动动作"
		"standard":
			return "标准动作"
		"swift":
			return "迅捷动作"
		"reaction":
			return "被动参考"
		_:
			return "技能"


func _get_state_label_color(available: bool, cooldown_turns: int) -> Color:
	if cooldown_turns > 0:
		return Color(0.92, 0.65, 0.38, 1.0)
	if not available:
		return TEXT_DISABLED
	return TEXT_MUTED


func _with_alpha(color_value: Color, alpha: float) -> Color:
	return Color(color_value.r, color_value.g, color_value.b, alpha)


func _on_skill_pressed(skill_id: String) -> void:
	skill_selected.emit(skill_id)
