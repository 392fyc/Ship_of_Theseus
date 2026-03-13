class_name BottomDashboard
extends Control

signal attack_requested
signal skill_toggle_requested
signal skill_selected(skill_id: String)
signal end_turn_requested
signal end_move_requested
signal cancel_requested

# --- Layout Constants ---
const PANEL_WIDTH_MAX: float = 1060.0
const PANEL_HEIGHT_COLLAPSED: float = 192.0
const PANEL_MARGIN: float = 14.0
const PANEL_LIFT: float = 60.0
const CARD_GAP: int = 12
const REFERENCE_VIEWPORT_WIDTH: float = 1600.0
const REFERENCE_VIEWPORT_HEIGHT: float = 900.0
const BASE_UI_SCALE: float = 0.86
const MIN_UI_SCALE: float = 0.68
const MAX_UI_SCALE: float = 0.92
const MAX_HEIGHT_RATIO: float = 0.34
const BUTTON_MIN_HEIGHT: float = 40.0
const AVATAR_SIZE: float = 72.0
const OUTER_MARGIN: int = 12
const SHELL_CORNER: int = 20
const CARD_CORNER: int = 14

# --- Color Palette: BG3 frosted-dark + FFT gold filigree ---
const COLOR_SHELL_BG: Color = Color(0.05, 0.07, 0.13, 0.95)
const COLOR_SHELL_BORDER: Color = Color(0.72, 0.62, 0.38, 0.85)
const COLOR_SHELL_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.65)
const COLOR_CARD_BG: Color = Color(0.07, 0.10, 0.17, 0.96)
const COLOR_CARD_BORDER: Color = Color(0.24, 0.29, 0.40, 0.80)
const COLOR_CARD_INSET: Color = Color(0.05, 0.07, 0.12, 0.96)
const COLOR_TEXT_MAIN: Color = Color(0.96, 0.93, 0.86, 1.0)
const COLOR_TEXT_MUTED: Color = Color(0.62, 0.67, 0.76, 1.0)
const COLOR_TEXT_DISABLED: Color = Color(0.40, 0.44, 0.52, 1.0)
const COLOR_HP_BG: Color = Color(0.08, 0.10, 0.16, 1.0)
const COLOR_HP_FILL: Color = Color(0.28, 0.72, 0.52, 1.0)
const COLOR_HINT_BG: Color = Color(0.06, 0.09, 0.15, 0.98)
const COLOR_HINT_BORDER: Color = Color(0.20, 0.26, 0.36, 1.0)
const COLOR_DIVIDER: Color = Color(0.18, 0.22, 0.32, 1.0)
const COLOR_FORECAST_BG: Color = Color(0.07, 0.09, 0.15, 0.98)
const COLOR_FORECAST_BORDER: Color = Color(0.82, 0.62, 0.30, 0.90)
const COLOR_AVATAR_BG: Color = Color(0.06, 0.09, 0.16, 1.0)
const COLOR_AVATAR_BORDER: Color = Color(0.72, 0.62, 0.38, 1.0)
const COLOR_AVATAR_RING: Color = Color(0.20, 0.54, 0.86, 0.28)
const COLOR_CHIP_AVAIL_BG: Color = Color(0.06, 0.15, 0.10, 1.0)
const COLOR_CHIP_AVAIL_BORDER: Color = Color(0.22, 0.65, 0.42, 1.0)
const COLOR_CHIP_SPENT_BG: Color = Color(0.17, 0.07, 0.08, 1.0)
const COLOR_CHIP_SPENT_BORDER: Color = Color(0.72, 0.32, 0.28, 1.0)

const BUTTON_ACCENTS: Dictionary = {
	"attack": Color(0.85, 0.42, 0.25, 1.0),
	"skill": Color(0.28, 0.58, 0.92, 1.0),
	"item": Color(0.65, 0.52, 0.30, 1.0),
	"end_turn": Color(0.84, 0.71, 0.40, 1.0),
	"end_move": Color(0.22, 0.72, 0.65, 1.0),
	"cancel": Color(0.52, 0.57, 0.66, 1.0),
}

const CHIP_CONFIG: Dictionary = {
	"M": {"icon": "靴", "label": "移动"},
	"A": {"icon": "⚔", "label": "攻击"},
	"S": {"icon": "◆", "label": "迅捷"},
}

var _panel: PanelContainer = null
var _frame: HBoxContainer = null
var _info_card: PanelContainer = null
var _command_card: PanelContainer = null
var _skill_card: PanelContainer = null
var _phase_tag_panel: PanelContainer = null
var _phase_tag_label: Label = null
var _enemy_tag_panel: PanelContainer = null
var _enemy_tag_label: Label = null
var _avatar_panel: PanelContainer = null
var _avatar_ring: PanelContainer = null
var _avatar_label: Label = null
var _name_label: Label = null
var _subtitle_label: Label = null
var _hp_bar: ProgressBar = null
var _hp_label: Label = null
var _status_flow: HFlowContainer = null
var _hint_panel: PanelContainer = null
var _hint_label: Label = null
var _title_label: Label = null
var _subtitle_hint_label: Label = null
var _forecast_panel: PanelContainer = null
var _forecast_title: Label = null
var _forecast_body: Label = null
var _button_column: VBoxContainer = null
var _skill_bar: SkillBar = null
var _attack_button: Button = null
var _skill_button: Button = null
var _item_button: Button = null
var _end_turn_button: Button = null
var _end_move_button: Button = null
var _cancel_button: Button = null
var _slide_tween: Tween = null
var _visible_state: bool = false
var _panel_height: float = PANEL_HEIGHT_COLLAPSED
var _ui_scale: float = 1.0

var _skill_bar_scene: PackedScene = preload("res://scenes/tactical/skill_bar.tscn")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_layout_dashboard(true)
	_panel.visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_dashboard(true)


func update_state(state: Dictionary) -> void:
	var should_show: bool = bool(state.get("visible", false))
	var is_enemy_mode: bool = str(state.get("mode", "player")) == "enemy"
	var show_actions: bool = bool(state.get("show_actions", false)) and not is_enemy_mode
	var show_skills: bool = bool(state.get("skills_visible", false)) and show_actions
	_update_panel_height()
	_set_dashboard_visible(should_show)
	if not should_show:
		_skill_bar.set_expanded(false)
		return

	var phase_text: String = str(state.get("phase_text", ""))
	var unit_name: String = str(state.get("unit_name", ""))
	var unit_label: String = str(state.get("unit_label", ""))

	_name_label.text = unit_name
	_subtitle_label.text = "战术编号  %s" % unit_label
	_avatar_label.text = _get_avatar_text(unit_name)
	_phase_tag_label.text = phase_text
	_enemy_tag_label.text = "敌方只读"
	_phase_tag_panel.visible = not is_enemy_mode
	_enemy_tag_panel.visible = is_enemy_mode
	_apply_phase_tag_style(phase_text)

	var hp_value: int = int(state.get("hp", 0))
	var hp_max: int = max(1, int(state.get("hp_max", 1)))
	_hp_bar.max_value = float(hp_max)
	_hp_bar.value = float(hp_value)
	_hp_label.text = "生命值  %d / %d" % [hp_value, hp_max]
	_update_status_chips(str(state.get("status_text", "")))

	_hint_label.text = ""
	_hint_panel.visible = false
	_title_label.text = "敌军档案" if is_enemy_mode else "战术指令"
	_subtitle_hint_label.text = ""
	_subtitle_hint_label.visible = false

	var buttons: Dictionary = state.get("buttons", {})
	_apply_button_state(_attack_button, "攻击", "attack",
		bool(buttons.get("attack_visible", true)),
		bool(buttons.get("attack_disabled", true)),
		str(buttons.get("attack_reason", "")))
	_apply_button_state(_skill_button,
		"技能%s" % (" ▲" if show_skills else " ▼"),
		"skill",
		bool(buttons.get("skill_visible", true)),
		bool(buttons.get("skill_disabled", false)),
		str(buttons.get("skill_reason", "")))
	_apply_button_state(_item_button, "道具", "item",
		bool(buttons.get("item_visible", true)),
		bool(buttons.get("item_disabled", true)),
		str(buttons.get("item_reason", "")))
	_apply_button_state(_end_turn_button, "结束回合", "end_turn",
		bool(buttons.get("end_turn_visible", true)),
		bool(buttons.get("end_turn_disabled", false)),
		str(buttons.get("end_turn_reason", "")))
	_apply_button_state(_end_move_button, "结束移动", "end_move",
		bool(buttons.get("end_move_visible", false)),
		bool(buttons.get("end_move_disabled", false)),
		str(buttons.get("end_move_reason", "")))
	_apply_button_state(_cancel_button, "取消", "cancel",
		bool(buttons.get("cancel_visible", false)),
		bool(buttons.get("cancel_disabled", false)),
		str(buttons.get("cancel_reason", "")))

	var entries: Array[Dictionary] = []
	for entry_value: Variant in state.get("skills", []):
		if entry_value is Dictionary:
			entries.append(entry_value)
	_skill_bar.update_entries(entries, str(state.get("selected_skill_id", "")))
	_skill_bar.set_expanded(show_skills)

	_button_column.visible = show_actions
	_update_forecast(state.get("forecast", {}), is_enemy_mode)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH_MAX, PANEL_HEIGHT_COLLAPSED)
	_panel.size = Vector2(PANEL_WIDTH_MAX, PANEL_HEIGHT_COLLAPSED)
	_panel.add_theme_stylebox_override("panel", _make_shell_style())
	add_child(_panel)

	var outer_margin: MarginContainer = MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", OUTER_MARGIN)
	outer_margin.add_theme_constant_override("margin_right", OUTER_MARGIN)
	outer_margin.add_theme_constant_override("margin_top", OUTER_MARGIN)
	outer_margin.add_theme_constant_override("margin_bottom", OUTER_MARGIN)
	_panel.add_child(outer_margin)

	_frame = HBoxContainer.new()
	_frame.add_theme_constant_override("separation", CARD_GAP)
	outer_margin.add_child(_frame)

	_build_info_card()
	_build_command_card()
	_build_skill_card()


func _build_info_card() -> void:
	_info_card = PanelContainer.new()
	_info_card.custom_minimum_size = Vector2(0.0, 0.0)
	_info_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_card.size_flags_stretch_ratio = 1.2
	_info_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info_card.add_theme_stylebox_override("panel", _make_card_style(COLOR_CARD_BG, COLOR_CARD_BORDER))
	_frame.add_child(_info_card)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_info_card.add_child(margin)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	# Phase / Enemy tag row
	var tag_row: HBoxContainer = HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 8)
	column.add_child(tag_row)

	_phase_tag_panel = _create_tag_panel(Vector2(80.0, 26.0))
	_phase_tag_label = _create_tag_label(11)
	_phase_tag_panel.add_child(_wrap_tag_label(_phase_tag_label))
	tag_row.add_child(_phase_tag_panel)

	_enemy_tag_panel = _create_tag_panel(Vector2(80.0, 26.0))
	_enemy_tag_label = _create_tag_label(11)
	_enemy_tag_panel.add_child(_wrap_tag_label(_enemy_tag_label))
	tag_row.add_child(_enemy_tag_panel)

	var spacer_tag: Control = Control.new()
	spacer_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag_row.add_child(spacer_tag)

	# Identity row: avatar + name column
	var identity_row: HBoxContainer = HBoxContainer.new()
	identity_row.add_theme_constant_override("separation", 12)
	column.add_child(identity_row)

	# Avatar: outer ring (PanelContainer) + inner panel
	_avatar_ring = PanelContainer.new()
	_avatar_ring.custom_minimum_size = Vector2(AVATAR_SIZE + 6.0, AVATAR_SIZE + 6.0)
	_avatar_ring.add_theme_stylebox_override("panel", _make_avatar_ring_style())
	identity_row.add_child(_avatar_ring)

	_avatar_panel = PanelContainer.new()
	_avatar_panel.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	_avatar_panel.add_theme_stylebox_override("panel", _make_avatar_inner_style())
	_avatar_ring.add_child(_avatar_panel)

	var avatar_center: CenterContainer = CenterContainer.new()
	avatar_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	avatar_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar_panel.add_child(avatar_center)

	_avatar_label = Label.new()
	_avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avatar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avatar_label.add_theme_font_size_override("font_size", 28)
	_avatar_label.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	_avatar_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.60))
	_avatar_label.add_theme_constant_override("outline_size", 3)
	_avatar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_center.add_child(_avatar_label)

	# Name + subtitle + HP
	var identity_column: VBoxContainer = VBoxContainer.new()
	identity_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_column.add_theme_constant_override("separation", 3)
	identity_row.add_child(identity_column)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 20)
	_name_label.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	_name_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.35))
	_name_label.add_theme_constant_override("outline_size", 1)
	identity_column.add_child(_name_label)

	_subtitle_label = Label.new()
	_subtitle_label.add_theme_font_size_override("font_size", 10)
	_subtitle_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	identity_column.add_child(_subtitle_label)

	var hp_panel: PanelContainer = PanelContainer.new()
	hp_panel.add_theme_stylebox_override("panel", _make_card_style(COLOR_CARD_INSET, COLOR_DIVIDER, 10))
	identity_column.add_child(hp_panel)

	var hp_margin: MarginContainer = MarginContainer.new()
	hp_margin.add_theme_constant_override("margin_left", 8)
	hp_margin.add_theme_constant_override("margin_right", 8)
	hp_margin.add_theme_constant_override("margin_top", 5)
	hp_margin.add_theme_constant_override("margin_bottom", 5)
	hp_panel.add_child(hp_margin)

	var hp_column: VBoxContainer = VBoxContainer.new()
	hp_column.add_theme_constant_override("separation", 4)
	hp_margin.add_child(hp_column)

	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 11)
	_hp_label.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	hp_column.add_child(_hp_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(0.0, 10.0)
	_hp_bar.show_percentage = false
	_hp_bar.add_theme_stylebox_override("background", _make_progress_bg())
	_hp_bar.add_theme_stylebox_override("fill", _make_progress_fill())
	hp_column.add_child(_hp_bar)

	# Action status chips
	var status_row: HBoxContainer = HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 6)
	column.add_child(status_row)

	var status_title: Label = Label.new()
	status_title.text = "行动状态"
	status_title.add_theme_font_size_override("font_size", 10)
	status_title.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	status_row.add_child(status_title)

	_status_flow = HFlowContainer.new()
	_status_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_flow.add_theme_constant_override("h_separation", 6)
	_status_flow.add_theme_constant_override("v_separation", 4)
	status_row.add_child(_status_flow)

	# Hint panel
	_hint_panel = PanelContainer.new()
	_hint_panel.add_theme_stylebox_override("panel", _make_card_style(COLOR_HINT_BG, COLOR_HINT_BORDER, 10))
	column.add_child(_hint_panel)

	var hint_margin: MarginContainer = MarginContainer.new()
	hint_margin.add_theme_constant_override("margin_left", 8)
	hint_margin.add_theme_constant_override("margin_right", 8)
	hint_margin.add_theme_constant_override("margin_top", 5)
	hint_margin.add_theme_constant_override("margin_bottom", 5)
	_hint_panel.add_child(hint_margin)

	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.add_theme_font_size_override("font_size", 10)
	_hint_label.max_lines_visible = 2
	_hint_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	hint_margin.add_child(_hint_label)


func _build_command_card() -> void:
	_command_card = PanelContainer.new()
	_command_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_command_card.size_flags_stretch_ratio = 0.8
	_command_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_command_card.add_theme_stylebox_override("panel", _make_card_style(COLOR_CARD_BG, COLOR_CARD_BORDER))
	_frame.add_child(_command_card)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_command_card.add_child(margin)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)

	var header_row: HBoxContainer = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 10)
	column.add_child(header_row)

	var title_column: VBoxContainer = VBoxContainer.new()
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_column.add_theme_constant_override("separation", 3)
	header_row.add_child(title_column)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 15)
	_title_label.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	_title_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.30))
	_title_label.add_theme_constant_override("outline_size", 1)
	title_column.add_child(_title_label)

	_subtitle_hint_label = Label.new()
	_subtitle_hint_label.add_theme_font_size_override("font_size", 10)
	_subtitle_hint_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	title_column.add_child(_subtitle_hint_label)

	# Forecast panel — strong amber double-border for visual separation
	_forecast_panel = PanelContainer.new()
	_forecast_panel.custom_minimum_size = Vector2(236.0, 64.0)
	_forecast_panel.add_theme_stylebox_override("panel", _make_forecast_style())
	header_row.add_child(_forecast_panel)

	var forecast_margin: MarginContainer = MarginContainer.new()
	forecast_margin.add_theme_constant_override("margin_left", 10)
	forecast_margin.add_theme_constant_override("margin_right", 10)
	forecast_margin.add_theme_constant_override("margin_top", 8)
	forecast_margin.add_theme_constant_override("margin_bottom", 8)
	_forecast_panel.add_child(forecast_margin)

	var forecast_column: VBoxContainer = VBoxContainer.new()
	forecast_column.add_theme_constant_override("separation", 3)
	forecast_margin.add_child(forecast_column)

	_forecast_title = Label.new()
	_forecast_title.add_theme_font_size_override("font_size", 12)
	_forecast_title.add_theme_color_override("font_color", Color(0.92, 0.74, 0.40, 1.0))
	_forecast_title.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.40))
	_forecast_title.add_theme_constant_override("outline_size", 1)
	forecast_column.add_child(_forecast_title)

	_forecast_body = Label.new()
	_forecast_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_forecast_body.add_theme_font_size_override("font_size", 11)
	_forecast_body.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	forecast_column.add_child(_forecast_body)

	_button_column = VBoxContainer.new()
	_button_column.add_theme_constant_override("separation", 5)
	_button_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_button_column)

	_attack_button = _make_button("攻击", Vector2(0.0, BUTTON_MIN_HEIGHT), _on_attack_pressed)
	_skill_button = _make_button("技能", Vector2(0.0, BUTTON_MIN_HEIGHT), _on_skill_toggle_pressed)
	_item_button = _make_button("道具", Vector2(0.0, BUTTON_MIN_HEIGHT))
	_end_turn_button = _make_button("结束回合", Vector2(0.0, BUTTON_MIN_HEIGHT), _on_end_turn_pressed)
	_end_move_button = _make_button("结束移动", Vector2(0.0, BUTTON_MIN_HEIGHT), _on_end_move_pressed)
	_cancel_button = _make_button("取消", Vector2(0.0, BUTTON_MIN_HEIGHT), _on_cancel_pressed)

	for button: Button in [
		_attack_button, _skill_button, _item_button,
		_end_turn_button, _end_move_button, _cancel_button,
	]:
		_button_column.add_child(button)

func _build_skill_card() -> void:
	_skill_card = PanelContainer.new()
	_skill_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_card.size_flags_stretch_ratio = 1.0
	_skill_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_skill_card.add_theme_stylebox_override("panel", _make_card_style(COLOR_CARD_BG, COLOR_CARD_BORDER))
	_frame.add_child(_skill_card)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_skill_card.add_child(margin)

	_skill_bar = _skill_bar_scene.instantiate() as SkillBar
	_skill_bar.skill_selected.connect(_on_skill_selected)
	margin.add_child(_skill_bar)


func _make_button(text: String, minimum_size: Vector2,
		callback: Callable = Callable()) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.flat = false
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = minimum_size
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_constant_override("outline_size", 1)
	button.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.60))
	if callback != null and not callback.is_null():
		button.pressed.connect(callback)
	return button


func _apply_button_state(button: Button, text: String, accent_key: String,
		visible_state: bool, disabled: bool, _tooltip: String) -> void:
	button.text = text
	button.visible = visible_state
	button.disabled = disabled
	button.tooltip_text = ""

	var accent: Color = BUTTON_ACCENTS.get(accent_key, Color(0.55, 0.55, 0.55, 1.0))

	if disabled:
		var dis_bg: Color = Color(0.06, 0.08, 0.13, 1.0)
		var dis_border: Color = Color(0.20, 0.23, 0.30, 1.0)
		var dis_style: StyleBoxFlat = _make_button_style(dis_bg, dis_border, accent, 0.0)
		button.add_theme_stylebox_override("normal", dis_style)
		button.add_theme_stylebox_override("hover", dis_style)
		button.add_theme_stylebox_override("pressed", dis_style)
		button.add_theme_stylebox_override("disabled", dis_style)
		button.add_theme_color_override("font_color", COLOR_TEXT_DISABLED)
		button.add_theme_color_override("font_hover_color", COLOR_TEXT_DISABLED)
		button.add_theme_color_override("font_pressed_color", COLOR_TEXT_DISABLED)
		button.add_theme_color_override("font_disabled_color", COLOR_TEXT_DISABLED)
		return

	var bg: Color = Color(0.10, 0.13, 0.22, 1.0)
	var border: Color = accent.lerp(COLOR_SHELL_BORDER, 0.25).darkened(0.10)
	var normal_style: StyleBoxFlat = _make_button_style(bg, border, accent, 0.20)
	var hover_style: StyleBoxFlat = _make_button_style(
		bg.lightened(0.10), border.lightened(0.15), accent, 0.45)
	var pressed_style: StyleBoxFlat = _make_button_style(
		bg.darkened(0.08), border, accent, 0.15)
	pressed_style.shadow_offset = Vector2(0.0, 1.0)
	pressed_style.shadow_size = 3
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("disabled", normal_style)
	button.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.92, 1.0))
	button.add_theme_color_override("font_pressed_color", COLOR_TEXT_MAIN)
	button.add_theme_color_override("font_disabled_color", COLOR_TEXT_MAIN)


func _update_status_chips(status_text: String) -> void:
	for child: Node in _status_flow.get_children():
		child.queue_free()

	var parts: PackedStringArray = status_text.split(" ", false)
	for part: String in parts:
		if part.length() < 2:
			continue
		var resource_key: String = part.left(1)
		var spent: bool = part.ends_with("×")
		var config: Dictionary = CHIP_CONFIG.get(resource_key, {})
		var icon_text: String = str(config.get("icon", "?"))
		var label_text: String = str(config.get("label", resource_key))

		var chip_bg: Color = COLOR_CHIP_SPENT_BG if spent else COLOR_CHIP_AVAIL_BG
		var chip_border: Color = COLOR_CHIP_SPENT_BORDER if spent else COLOR_CHIP_AVAIL_BORDER

		var chip: PanelContainer = PanelContainer.new()
		chip.custom_minimum_size = Vector2(66.0, 24.0)
		chip.add_theme_stylebox_override("panel", _make_chip_style(chip_bg, chip_border))
		_status_flow.add_child(chip)

		var chip_margin: MarginContainer = MarginContainer.new()
		chip_margin.add_theme_constant_override("margin_left", 7)
		chip_margin.add_theme_constant_override("margin_right", 7)
		chip_margin.add_theme_constant_override("margin_top", 3)
		chip_margin.add_theme_constant_override("margin_bottom", 3)
		chip.add_child(chip_margin)

		var chip_row: HBoxContainer = HBoxContainer.new()
		chip_row.add_theme_constant_override("separation", 4)
		chip_margin.add_child(chip_row)

		var icon_label: Label = Label.new()
		icon_label.text = icon_text
		icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon_label.add_theme_font_size_override("font_size", 11)
		icon_label.add_theme_color_override("font_color", chip_border.lightened(0.25))
		icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip_row.add_child(icon_label)

		var name_label: Label = Label.new()
		name_label.text = label_text
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 10)
		name_label.add_theme_color_override("font_color",
			COLOR_TEXT_DISABLED if spent else COLOR_TEXT_MAIN)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip_row.add_child(name_label)


func _update_forecast(forecast: Dictionary, is_enemy_mode: bool) -> void:
	if is_enemy_mode:
		_forecast_title.text = ""
		_forecast_body.text = ""
		_forecast_panel.visible = false
		return

	var visible_state: bool = bool(forecast.get("visible", false))
	if not visible_state:
		_forecast_title.text = ""
		_forecast_body.text = ""
		_forecast_panel.visible = false
		return

	_forecast_panel.visible = true
	_forecast_title.text = "战斗预测"
	_forecast_body.text = "%s\n命中 %d%%  暴击 %d%%\n预计伤害 %d  预计反击 %s" % [
		str(forecast.get("target_name", "")),
		int(forecast.get("hit_percent", 0)),
		int(forecast.get("crit_percent", 0)),
		int(forecast.get("damage", 0)),
		"是" if bool(forecast.get("counter_expected", false)) else "否",
	]


func _set_dashboard_visible(should_show: bool) -> void:
	if _visible_state == should_show:
		return
	_visible_state = should_show
	if _slide_tween != null and _slide_tween.is_running():
		_slide_tween.kill()
	_panel.visible = true

	var scaled_height: float = _panel_height * _ui_scale
	var scaled_margin: float = PANEL_MARGIN * _ui_scale
	var shown_y: float = size.y - scaled_height - scaled_margin - PANEL_LIFT * _ui_scale
	var hidden_y: float = size.y + 18.0 * _ui_scale
	var target_y: float = shown_y if should_show else hidden_y
	var duration: float = 0.25 if should_show else 0.20
	var ease_type: Tween.EaseType = Tween.EASE_OUT if should_show else Tween.EASE_IN
	_slide_tween = create_tween().set_parallel(true)
	_slide_tween.tween_property(_panel, "position:y", target_y, duration) \
		.set_ease(ease_type).set_trans(Tween.TRANS_QUAD)
	_slide_tween.tween_property(_panel, "modulate:a", 1.0 if should_show else 0.0, duration) \
		.set_ease(ease_type).set_trans(Tween.TRANS_QUAD)
	if not should_show:
		_slide_tween.finished.connect(func() -> void:
			_panel.visible = false
		)


func _layout_dashboard(immediate: bool) -> void:
	if _panel == null:
		return
	_ui_scale = _compute_ui_scale()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH_MAX, _panel_height)
	_panel.size = Vector2(PANEL_WIDTH_MAX, _panel_height)
	_panel.scale = Vector2(_ui_scale, _ui_scale)
	var scaled_width: float = PANEL_WIDTH_MAX * _ui_scale
	var scaled_height: float = _panel_height * _ui_scale
	var scaled_margin: float = PANEL_MARGIN * _ui_scale
	_panel.position.x = (size.x - scaled_width) * 0.5
	var target_y: float = size.y - scaled_height - scaled_margin - PANEL_LIFT * _ui_scale
	if not _visible_state:
		target_y = size.y + 18.0 * _ui_scale
	if immediate:
		_panel.position.y = target_y
		_panel.modulate.a = 1.0 if _visible_state else 0.0


func _update_panel_height() -> void:
	if is_equal_approx(_panel_height, PANEL_HEIGHT_COLLAPSED):
		return
	_panel_height = PANEL_HEIGHT_COLLAPSED
	_layout_dashboard(true)


func _compute_ui_scale() -> float:
	if size.x <= 0.0 or size.y <= 0.0:
		return 1.0

	var width_budget: float = maxf(320.0, size.x - PANEL_MARGIN * 2.0)
	var width_fit_scale: float = width_budget / PANEL_WIDTH_MAX
	var height_budget: float = maxf(140.0, size.y * MAX_HEIGHT_RATIO)
	var height_fit_scale: float = height_budget / PANEL_HEIGHT_COLLAPSED
	var viewport_scale: float = minf(
		size.x / REFERENCE_VIEWPORT_WIDTH,
		size.y / REFERENCE_VIEWPORT_HEIGHT)
	var target_scale: float = BASE_UI_SCALE * clampf(viewport_scale, 0.90, 1.08)
	var fit_scale: float = minf(width_fit_scale, height_fit_scale)
	return clampf(minf(fit_scale, target_scale), MIN_UI_SCALE, MAX_UI_SCALE)


func _create_tag_panel(minimum_size: Vector2) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = minimum_size
	return panel


func _create_tag_label(font_size: int) -> Label:
	var label: Label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	return label


func _wrap_tag_label(label: Label) -> MarginContainer:
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	margin.add_child(label)
	return margin


func _apply_phase_tag_style(phase_text: String) -> void:
	var bg_color: Color = Color(0.12, 0.15, 0.24, 1.0)
	var border_color: Color = Color(0.35, 0.45, 0.68, 1.0)
	match phase_text:
		"移动阶段":
			bg_color = Color(0.07, 0.15, 0.26, 1.0)
			border_color = Color(0.23, 0.52, 0.88, 1.0)
		"行动阶段":
			bg_color = Color(0.18, 0.12, 0.06, 1.0)
			border_color = Color(0.92, 0.55, 0.22, 1.0)
		"技能瞄准":
			bg_color = Color(0.08, 0.17, 0.18, 1.0)
			border_color = Color(0.20, 0.70, 0.72, 1.0)
		"攻击瞄准":
			bg_color = Color(0.21, 0.10, 0.08, 1.0)
			border_color = Color(0.86, 0.36, 0.24, 1.0)
		"迅捷阶段":
			bg_color = Color(0.06, 0.16, 0.12, 1.0)
			border_color = Color(0.16, 0.72, 0.52, 1.0)
		"执行中":
			bg_color = Color(0.12, 0.13, 0.16, 1.0)
			border_color = Color(0.55, 0.58, 0.64, 1.0)
	_phase_tag_panel.add_theme_stylebox_override("panel", _make_chip_style(bg_color, border_color, 13))
	_enemy_tag_panel.add_theme_stylebox_override("panel", _make_chip_style(
		Color(0.17, 0.08, 0.09, 1.0), Color(0.76, 0.32, 0.28, 1.0), 13))


func _get_avatar_text(unit_name: String) -> String:
	if unit_name == "":
		return "?"
	return unit_name.left(1)


func _make_shell_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_SHELL_BG
	style.border_color = COLOR_SHELL_BORDER
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = SHELL_CORNER
	style.corner_radius_top_right = SHELL_CORNER
	style.corner_radius_bottom_left = SHELL_CORNER
	style.corner_radius_bottom_right = SHELL_CORNER
	style.shadow_color = COLOR_SHELL_SHADOW
	style.shadow_size = 24
	style.shadow_offset = Vector2(0.0, 8.0)
	style.expand_margin_left = 1.0
	style.expand_margin_right = 1.0
	style.expand_margin_top = 1.0
	style.expand_margin_bottom = 1.0
	return style


func _make_card_style(bg_color: Color, border_color: Color,
		corner_radius: int = CARD_CORNER) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.corner_radius_bottom_right = corner_radius
	return style


func _make_chip_style(bg_color: Color, border_color: Color,
		corner_radius: int = 12) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.corner_radius_bottom_right = corner_radius
	return style


func _make_avatar_ring_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_AVATAR_RING
	style.border_color = Color(0.20, 0.48, 0.80, 0.35)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 24
	style.corner_radius_top_right = 24
	style.corner_radius_bottom_left = 24
	style.corner_radius_bottom_right = 24
	style.content_margin_left = 3.0
	style.content_margin_right = 3.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style


func _make_avatar_inner_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_AVATAR_BG
	style.border_color = COLOR_AVATAR_BORDER
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 20
	style.corner_radius_top_right = 20
	style.corner_radius_bottom_left = 20
	style.corner_radius_bottom_right = 20
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.40)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0.0, 4.0)
	return style


func _make_forecast_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_FORECAST_BG
	style.border_color = COLOR_FORECAST_BORDER
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.shadow_color = Color(0.82, 0.62, 0.30, 0.12)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0.0, 2.0)
	return style


func _make_progress_bg() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_HP_BG
	style.border_color = Color(0.24, 0.28, 0.36, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


func _make_progress_fill() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_HP_FILL
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style


func _make_button_style(bg_color: Color, border_color: Color,
		accent_color: Color, accent_alpha: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color.lerp(accent_color, 0.30)
	style.border_width_left = 3
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.shadow_color = _with_alpha(accent_color.darkened(0.55), accent_alpha)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0.0, 4.0)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _with_alpha(color_value: Color, alpha: float) -> Color:
	return Color(color_value.r, color_value.g, color_value.b, alpha)


func _on_attack_pressed() -> void:
	attack_requested.emit()


func _on_skill_toggle_pressed() -> void:
	skill_toggle_requested.emit()


func _on_skill_selected(skill_id: String) -> void:
	skill_selected.emit(skill_id)


func _on_end_turn_pressed() -> void:
	end_turn_requested.emit()


func _on_end_move_pressed() -> void:
	end_move_requested.emit()


func _on_cancel_pressed() -> void:
	cancel_requested.emit()
