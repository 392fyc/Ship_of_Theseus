class_name BottomDashboard
extends Control

signal attack_requested
signal skill_toggle_requested
signal skill_selected(skill_id: String)
signal end_turn_requested
signal end_move_requested
@warning_ignore("unused_signal")
signal cancel_requested


class ActionGlyph extends Control:
	var glyph_kind: String = "attack"
	var accent_color: Color = Color(1.0, 1.0, 1.0, 1.0)

	func _ready() -> void:
		custom_minimum_size = Vector2(30.0, 24.0)

	func _draw() -> void:
		match glyph_kind:
			"skill":
				_draw_skill_glyph()
			"item":
				_draw_item_glyph()
			_:
				_draw_attack_glyph()

	func _draw_attack_glyph() -> void:
		var c: Vector2 = size * 0.5
		var blade_a0: Vector2 = c + Vector2(-9.0, 8.0)
		var blade_a1: Vector2 = c + Vector2(7.0, -8.0)
		var blade_b0: Vector2 = c + Vector2(9.0, 8.0)
		var blade_b1: Vector2 = c + Vector2(-7.0, -8.0)
		var steel: Color = accent_color.lightened(0.18)
		var guard: Color = accent_color.darkened(0.15)

		draw_line(blade_a0, blade_a1, steel, 2.0, true)
		draw_line(blade_b0, blade_b1, steel, 2.0, true)
		draw_line(c + Vector2(-5.0, 4.0), c + Vector2(-1.0, 8.0), guard, 2.0, true)
		draw_line(c + Vector2(5.0, 4.0), c + Vector2(1.0, 8.0), guard, 2.0, true)
		draw_line(c + Vector2(-1.0, 8.0), c + Vector2(-3.0, 11.0), guard, 2.0, true)
		draw_line(c + Vector2(1.0, 8.0), c + Vector2(3.0, 11.0), guard, 2.0, true)
		draw_colored_polygon([blade_a1, blade_a1 + Vector2(2.0, -1.0), blade_a1 + Vector2(1.0, 2.0)], steel)
		draw_colored_polygon([blade_b1, blade_b1 + Vector2(-2.0, -1.0), blade_b1 + Vector2(-1.0, 2.0)], steel)

	func _draw_skill_glyph() -> void:
		var left_top: Vector2 = Vector2(10.0, 9.0)
		var right_top: Vector2 = Vector2(20.0, 7.0)
		var bottom: Vector2 = Vector2(15.0, 18.0)
		_draw_diamond(left_top, 4.0, accent_color, true)
		_draw_diamond(right_top, 4.0, accent_color, false)
		_draw_diamond(bottom, 4.5, accent_color, true)
		var line_color: Color = accent_color * Color(1.0, 1.0, 1.0, 0.25)
		draw_line(left_top, right_top, line_color, 1.0, true)
		draw_line(left_top, bottom, line_color, 1.0, true)
		draw_line(right_top, bottom, line_color, 1.0, true)

	func _draw_item_glyph() -> void:
		var book_edge: Color = accent_color.darkened(0.20)
		var book_fill: Color = Color(0.34, 0.27, 0.20, 1.0)
		var potion_edge: Color = Color(0.74, 0.70, 0.64, 0.95)
		var potion_glass: Color = Color(0.84, 0.88, 0.92, 0.12)
		var potion_fill: Color = Color(0.18, 0.68, 0.34, 0.82)

		for i: int in range(3):
			var y: float = 6.0 + float(i) * 4.0
			var rect: Rect2 = Rect2(15.0, y, 10.0, 4.0)
			draw_rect(rect, book_fill)
			draw_rect(rect, book_edge, false, 1.0)
			draw_line(Vector2(rect.position.x + 2.0, rect.position.y), Vector2(rect.end.x - 2.0, rect.position.y), accent_color * Color(1.0, 1.0, 1.0, 0.18), 1.0, true)

		var bottle: Rect2 = Rect2(4.0, 8.0, 10.0, 12.0)
		var neck: Rect2 = Rect2(7.0, 5.0, 4.0, 4.0)
		draw_rect(bottle, potion_glass)
		draw_rect(bottle, potion_edge, false, 1.0)
		draw_rect(neck, potion_glass)
		draw_rect(neck, potion_edge, false, 1.0)
		draw_rect(Rect2(5.0, 13.0, 8.0, 6.0), potion_fill)
		draw_line(Vector2(5.5, 12.0), Vector2(12.5, 12.0), Color(0.82, 1.0, 0.82, 0.55), 1.0, true)
		draw_line(Vector2(6.0, 9.0), Vector2(8.5, 7.0), Color(1.0, 1.0, 1.0, 0.25), 1.0, true)

	func _draw_diamond(center: Vector2, radius: float, color: Color, filled: bool) -> void:
		var pts: PackedVector2Array = PackedVector2Array([
			center + Vector2(0.0, -radius),
			center + Vector2(radius, 0.0),
			center + Vector2(0.0, radius),
			center + Vector2(-radius, 0.0),
		])
		if filled:
			draw_colored_polygon(pts, color)
		else:
			for i: int in range(pts.size()):
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[(i + 1) % pts.size()]
				draw_line(a, b, color, 1.0, true)


class HPGradientBar extends Control:
	var hp: int = 0
	var hp_max: int = 1

	const BAR_BG: Color = Color(0.04, 0.05, 0.10, 1.0)
	const BORDER_NORMAL: Color = Color(0.40, 0.35, 0.22, 0.55)
	const HP_STOPS: Array = [
		Color(0.80, 0.15, 0.15),
		Color(0.85, 0.40, 0.15),
		Color(0.85, 0.65, 0.15),
		Color(0.80, 0.80, 0.20),
		Color(0.50, 0.80, 0.30),
		Color(0.25, 0.75, 0.40),
	]

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		var hp_ratio: float = clampf(float(hp) / maxf(float(hp_max), 1.0), 0.0, 1.0)
		draw_rect(Rect2(0.0, 0.0, w, h), BAR_BG)
		if hp_ratio > 0.001:
			draw_rect(Rect2(1.0, 1.0, (w - 2.0) * hp_ratio, h - 2.0), _hp_gradient(hp_ratio))
		draw_rect(Rect2(0.0, 0.0, w, h), BORDER_NORMAL, false, 1.0)

	func _hp_gradient(ratio: float) -> Color:
		var idx: float = clampf(ratio, 0.0, 1.0) * 5.0
		var i: int = mini(int(idx), 4)
		var t: float = idx - float(i)
		return (HP_STOPS[i] as Color).lerp(HP_STOPS[i + 1] as Color, t)


const PORTRAIT_W: float = 78.0
const PORTRAIT_H: float = 104.0
const RELIC_PANEL_W: float = 96.0
const ACTION_BTN_SIZE: float = 52.0
const ACTION_BAR_GAP: int = 6
const ACTION_DIVIDER_H: float = 28.0
const HP_BAR_W: float = 181.0
const HP_BAR_H: float = 12.0
const FORECAST_PANEL_SIZE: Vector2 = Vector2(220.0, 80.0)
const ITEM_POPUP_SIZE: Vector2 = Vector2(330.0, 284.0)
const PANEL_MARGIN: float = 12.0
const PANEL_PAD: int = 8
const POPUP_GAP_Y: float = 8.0
const FORECAST_GAP_Y: float = 8.0
const SHOW_ANIM_TIME: float = 0.25
const HIDE_ANIM_TIME: float = 0.20
const DASH_OFFSET_Y: float = 24.0

const COLOR_PANEL_BG: Color = Color(0.04, 0.05, 0.10, 0.95)
const COLOR_PANEL_BG_ALT: Color = Color(0.06, 0.06, 0.12, 0.96)
const COLOR_PANEL_BORDER: Color = Color(0.60, 0.50, 0.28, 0.50)
const COLOR_PANEL_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.30)
const COLOR_GOLD: Color = Color(0.72, 0.58, 0.28, 1.0)
const COLOR_TEXT_MAIN: Color = Color(0.90, 0.86, 0.78, 1.0)
const COLOR_TEXT_SUB: Color = Color(0.55, 0.56, 0.60, 1.0)
const COLOR_TEXT_MUTE: Color = Color(0.45, 0.46, 0.50, 1.0)
const COLOR_HP_LABEL: Color = Color(0.50, 0.78, 0.55, 1.0)
const COLOR_HP_BG: Color = Color(0.04, 0.05, 0.10, 1.0)
const COLOR_HINT_BG: Color = Color(0.06, 0.06, 0.12, 0.90)
const COLOR_HINT_BORDER: Color = Color(0.40, 0.35, 0.22, 0.55)
const COLOR_FORECAST_BG: Color = Color(0.06, 0.06, 0.12, 0.94)
const COLOR_FORECAST_BORDER: Color = Color(0.72, 0.58, 0.28, 0.70)
const COLOR_PORTRAIT_BG: Color = Color(0.02, 0.03, 0.07, 1.0)
const COLOR_PORTRAIT_BORDER: Color = Color(0.72, 0.58, 0.28, 1.0)
const COLOR_POPUP_BG: Color = Color(0.09, 0.06, 0.14, 0.88)
const COLOR_POPUP_BORDER: Color = Color(0.83, 0.69, 0.22, 0.22)
const COLOR_POPUP_GLOW: Color = Color(0.58, 0.20, 0.92, 0.15)
const COLOR_POPUP_CARD_BG: Color = Color(0.07, 0.05, 0.11, 0.95)
const COLOR_POPUP_ICON_BG: Color = Color(0.10, 0.07, 0.16, 1.0)
const COLOR_POPUP_SEP: Color = Color(0.83, 0.69, 0.22, 0.20)
const COLOR_STAT_ABBR: Color = Color(0.68, 0.56, 0.30, 1.0)

const BUTTON_META: Dictionary = {
	"attack": {"title": "攻击", "fill": Color(0.16, 0.11, 0.08, 1.0), "accent": Color(0.86, 0.80, 0.74, 1.0), "glyph": "attack", "icon_frame": false},
	"skill": {"title": "技能", "fill": Color(0.10, 0.11, 0.16, 1.0), "accent": Color(0.86, 0.86, 0.94, 1.0), "glyph": "skill", "icon_frame": true},
	"item": {"title": "道具", "fill": Color(0.13, 0.10, 0.08, 1.0), "accent": Color(0.86, 0.78, 0.68, 1.0), "glyph": "item", "icon_frame": true},
	"end": {"title": "结束", "fill": Color(0.14, 0.07, 0.08, 1.0), "accent": Color(0.90, 0.18, 0.18, 1.0), "glyph": "end", "icon_frame": false},
}

const ITEM_PLACEHOLDERS := [
	{"name": "治疗药剂", "detail": "恢复少量生命值", "badge": "x02"},
	{"name": "战术卷轴", "detail": "暂未开放的功能占位", "badge": "x01"},
	{"name": "净化瓶", "detail": "移除一个负面状态", "badge": "x00"},
	{"name": "爆裂瓶", "detail": "范围道具接口保留中", "badge": "x00"},
	{"name": "备用口粮", "detail": "演示滚动区域占位", "badge": "x03"},
]

var _panel_offset_internal: float = DASH_OFFSET_Y
var _panel_offset_y: float:
	get:
		return _panel_offset_internal
	set(value):
		_panel_offset_internal = value
		if is_node_ready():
			_layout_dashboard()

var _visibility_tween: Tween = null
var _item_popup_tween: Tween = null
var _current_state: Dictionary = {}
var _item_popup_open: bool = false

var _info_panel: PanelContainer = null
var _avatar_panel: PanelContainer = null
var _avatar_label: Label = null
var _name_label: Label = null
var _unit_label_label: Label = null
var _phase_tag_panel: PanelContainer = null
var _phase_tag: Label = null
var _hp_label: Label = null
var _hp_bar: HPGradientBar = null
var _status_row: HBoxContainer = null
var _hint_panel: PanelContainer = null
var _hint_label: Label = null

var _relic_panel: PanelContainer = null
var _forecast_panel: PanelContainer = null
var _forecast_title: Label = null
var _forecast_body: Label = null

var _action_shell: PanelContainer = null
var _attack_button: Button = null
var _skill_button: Button = null
var _item_button: Button = null
var _end_button: Button = null
var _end_divider: ColorRect = null
var _button_nodes: Dictionary = {}

var _skill_bar: SkillBar = null
var _item_popup: Control = null
var _item_popup_panel: PanelContainer = null
var _item_popup_list: VBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	_build_ui()
	_layout_dashboard()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_layout_dashboard()


func update_state(state: Dictionary) -> void:
	_current_state = state.duplicate(true)
	var should_show: bool = bool(state.get("visible", false))
	_set_dashboard_visible(should_show)
	if not should_show:
		_skill_bar.set_expanded(false)
		_set_item_popup_visible(false)
		return

	var is_enemy_mode: bool = str(state.get("mode", "player")) == "enemy"
	var unit_name: String = str(state.get("unit_name", "未命名单位"))
	var unit_label: String = str(state.get("unit_label", ""))
	var hp_value: int = int(state.get("hp", 0))
	var hp_max: int = max(int(state.get("hp_max", 0)), 1)
	var hp_ratio: float = clampf(float(state.get("hp_ratio", 0.0)), 0.0, 1.0)
	var phase_text: String = str(state.get("phase_text", ""))
	var hint_text: String = str(state.get("hint_text", ""))
	var show_actions: bool = bool(state.get("show_actions", false)) and not is_enemy_mode
	var show_skills: bool = bool(state.get("skills_visible", false)) and show_actions

	_name_label.text = unit_name
	_unit_label_label.text = unit_label
	_phase_tag.text = phase_text
	_phase_tag_panel.visible = phase_text != ""
	_avatar_label.text = _build_avatar_text(unit_name, unit_label)
	_hp_label.text = "HP %d/%d" % [hp_value, hp_max]
	_hp_bar.hp = hp_value
	_hp_bar.hp_max = hp_max
	_hp_bar.queue_redraw()

	_hint_label.text = hint_text
	_hint_panel.visible = hint_text != ""
	_rebuild_status_row(str(state.get("status_text", "")))

	_action_shell.visible = show_actions
	if not show_actions:
		_skill_bar.set_expanded(false)
		_set_item_popup_visible(false)

	_update_buttons(_extract_button_state(state.get("buttons", {})), show_skills)
	_skill_bar.update_entries(_extract_skill_entries(state.get("skills", [])), str(state.get("selected_skill_id", "")))
	_skill_bar.set_expanded(show_skills)
	if show_skills and _item_popup_open:
		_set_item_popup_visible(false)

	_update_forecast(state.get("forecast", {}), is_enemy_mode)
	_layout_dashboard()


func _build_ui() -> void:
	_info_panel = _build_info_panel()
	add_child(_info_panel)

	_relic_panel = _build_relic_panel()
	add_child(_relic_panel)

	_forecast_panel = _build_forecast_panel()
	add_child(_forecast_panel)

	_action_shell = _build_action_shell()
	add_child(_action_shell)

	_skill_bar = SkillBar.new()
	_skill_bar.skill_selected.connect(_on_skill_selected)
	add_child(_skill_bar)

	_item_popup = _build_item_popup()
	add_child(_item_popup)


func _build_info_panel() -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_shell_style(COLOR_PANEL_BG, COLOR_PANEL_BORDER))

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PANEL_PAD)
	margin.add_theme_constant_override("margin_right", PANEL_PAD)
	margin.add_theme_constant_override("margin_top", PANEL_PAD)
	margin.add_theme_constant_override("margin_bottom", PANEL_PAD)
	panel.add_child(margin)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	var left_col: VBoxContainer = VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 3)
	left_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(left_col)

	_avatar_panel = PanelContainer.new()
	_avatar_panel.custom_minimum_size = Vector2(PORTRAIT_W, PORTRAIT_H)
	_avatar_panel.add_theme_stylebox_override("panel", _make_avatar_style())
	left_col.add_child(_avatar_panel)

	var avatar_center: CenterContainer = CenterContainer.new()
	_avatar_panel.add_child(avatar_center)

	_avatar_label = Label.new()
	_avatar_label.text = "?"
	_avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avatar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avatar_label.add_theme_font_size_override("font_size", 30)
	_avatar_label.add_theme_color_override("font_color", COLOR_GOLD)
	_avatar_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.50))
	_avatar_label.add_theme_constant_override("outline_size", 2)
	avatar_center.add_child(_avatar_label)

	var info_column: VBoxContainer = VBoxContainer.new()
	info_column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info_column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	info_column.custom_minimum_size.x = HP_BAR_W
	info_column.add_theme_constant_override("separation", 4)
	row.add_child(info_column)

	_name_label = Label.new()
	_name_label.text = "角色"
	_name_label.add_theme_font_size_override("font_size", 13)
	_name_label.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	info_column.add_child(_name_label)

	var subtitle_row: HBoxContainer = HBoxContainer.new()
	subtitle_row.add_theme_constant_override("separation", 6)
	info_column.add_child(subtitle_row)

	_unit_label_label = Label.new()
	_unit_label_label.text = "职业"
	_unit_label_label.add_theme_font_size_override("font_size", 10)
	_unit_label_label.add_theme_color_override("font_color", COLOR_TEXT_SUB)
	subtitle_row.add_child(_unit_label_label)

	_phase_tag_panel = PanelContainer.new()
	_phase_tag_panel.visible = false
	_phase_tag_panel.add_theme_stylebox_override("panel", _make_tag_style())
	subtitle_row.add_child(_phase_tag_panel)

	_phase_tag = Label.new()
	_phase_tag.text = ""
	_phase_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_phase_tag.add_theme_font_size_override("font_size", 9)
	_phase_tag.add_theme_color_override("font_color", COLOR_GOLD)
	_phase_tag_panel.add_child(_phase_tag)

	_hp_label = Label.new()
	_hp_label.text = "HP 0/0"
	_hp_label.add_theme_font_size_override("font_size", 9)
	_hp_label.add_theme_color_override("font_color", COLOR_HP_LABEL)
	info_column.add_child(_hp_label)

	_hp_bar = HPGradientBar.new()
	_hp_bar.custom_minimum_size = Vector2(HP_BAR_W, HP_BAR_H)
	info_column.add_child(_hp_bar)

	_status_row = HBoxContainer.new()
	_status_row.add_theme_constant_override("separation", 4)
	info_column.add_child(_status_row)

	_hint_panel = PanelContainer.new()
	_hint_panel.visible = false
	_hint_panel.add_theme_stylebox_override("panel", _make_hint_style())
	info_column.add_child(_hint_panel)

	var hint_margin: MarginContainer = MarginContainer.new()
	hint_margin.add_theme_constant_override("margin_left", 4)
	hint_margin.add_theme_constant_override("margin_right", 4)
	hint_margin.add_theme_constant_override("margin_top", 3)
	hint_margin.add_theme_constant_override("margin_bottom", 3)
	_hint_panel.add_child(hint_margin)

	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.add_theme_font_size_override("font_size", 8)
	_hint_label.add_theme_color_override("font_color", COLOR_TEXT_SUB)
	hint_margin.add_child(_hint_label)

	return panel


func _build_relic_panel() -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_shell_style(COLOR_PANEL_BG, COLOR_PANEL_BORDER))

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var center: CenterContainer = CenterContainer.new()
	margin.add_child(center)

	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	center.add_child(grid)

	for index: int in range(6):
		var slot: PanelContainer = PanelContainer.new()
		slot.custom_minimum_size = Vector2(28.0, 28.0)
		slot.add_theme_stylebox_override("panel", _make_relic_slot_style())
		grid.add_child(slot)

		var slot_center: CenterContainer = CenterContainer.new()
		slot.add_child(slot_center)

		var mark: Label = Label.new()
		mark.text = "◌"
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mark.add_theme_font_size_override("font_size", 12)
		mark.add_theme_color_override("font_color", COLOR_TEXT_SUB)
		slot_center.add_child(mark)

	return panel


func _build_forecast_panel() -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.visible = false
	panel.custom_minimum_size = FORECAST_PANEL_SIZE
	panel.size = FORECAST_PANEL_SIZE
	panel.add_theme_stylebox_override("panel", _make_forecast_style())

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 7)
	panel.add_child(margin)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)

	_forecast_title = Label.new()
	_forecast_title.text = "战斗预测"
	_forecast_title.add_theme_font_size_override("font_size", 11)
	_forecast_title.add_theme_color_override("font_color", COLOR_GOLD)
	column.add_child(_forecast_title)

	_forecast_body = Label.new()
	_forecast_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_forecast_body.add_theme_font_size_override("font_size", 9)
	_forecast_body.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	column.add_child(_forecast_body)

	return panel


func _build_action_shell() -> PanelContainer:
	var shell: PanelContainer = PanelContainer.new()
	shell.add_theme_stylebox_override("panel", _make_shell_style(COLOR_PANEL_BG, COLOR_PANEL_BORDER))

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PANEL_PAD)
	margin.add_theme_constant_override("margin_right", PANEL_PAD)
	margin.add_theme_constant_override("margin_top", PANEL_PAD)
	margin.add_theme_constant_override("margin_bottom", PANEL_PAD)
	shell.add_child(margin)

	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", ACTION_BAR_GAP)
	margin.add_child(row)

	_attack_button = _build_action_button("attack")
	_skill_button = _build_action_button("skill")
	_skill_button.toggle_mode = true
	_item_button = _build_action_button("item")
	_item_button.toggle_mode = true
	_end_button = _build_action_button("end")

	row.add_child(_attack_button)
	row.add_child(_skill_button)
	row.add_child(_item_button)

	var divider_holder: CenterContainer = CenterContainer.new()
	divider_holder.custom_minimum_size = Vector2(4.0, ACTION_BTN_SIZE)
	row.add_child(divider_holder)

	_end_divider = ColorRect.new()
	_end_divider.custom_minimum_size = Vector2(1.0, ACTION_DIVIDER_H)
	_end_divider.color = Color(0.56, 0.48, 0.28, 0.45)
	divider_holder.add_child(_end_divider)

	row.add_child(_end_button)

	_button_nodes["attack"] = _attack_button
	_button_nodes["skill"] = _skill_button
	_button_nodes["item"] = _item_button
	_button_nodes["end"] = _end_button

	_attack_button.pressed.connect(_on_attack_pressed)
	_skill_button.pressed.connect(_on_skill_button_pressed)
	_item_button.pressed.connect(_on_item_button_pressed)
	_end_button.pressed.connect(_on_end_button_pressed)

	return shell


func _build_action_button(key: String) -> Button:
	var meta: Dictionary = BUTTON_META[key]
	var accent: Color = meta["accent"]
	var fill: Color = meta["fill"]
	var button: Button = Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(ACTION_BTN_SIZE, ACTION_BTN_SIZE)
	button.text = ""
	button.clip_contents = false
	button.add_theme_stylebox_override("normal", _make_action_button_style(fill, accent, "normal"))
	button.add_theme_stylebox_override("hover", _make_action_button_style(fill, accent, "hover"))
	button.add_theme_stylebox_override("pressed", _make_action_button_style(fill, accent, "pressed"))
	button.add_theme_stylebox_override("disabled", _make_action_button_style(fill, accent, "disabled"))

	var inner_margin: MarginContainer = MarginContainer.new()
	inner_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner_margin.add_theme_constant_override("margin_left", 4)
	inner_margin.add_theme_constant_override("margin_right", 4)
	inner_margin.add_theme_constant_override("margin_top", 4)
	inner_margin.add_theme_constant_override("margin_bottom", 4)
	button.add_child(inner_margin)

	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
	inner_margin.add_child(column)

	var icon_holder: CenterContainer = CenterContainer.new()
	icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(icon_holder)

	if key == "end":
		var end_icon: PanelContainer = PanelContainer.new()
		end_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		end_icon.custom_minimum_size = Vector2(15.0, 15.0)
		end_icon.add_theme_stylebox_override("panel", _make_end_icon_style())
		icon_holder.add_child(end_icon)
	else:
		var icon_parent: Control = icon_holder
		if bool(meta.get("icon_frame", false)):
			var icon_frame: PanelContainer = PanelContainer.new()
			icon_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon_frame.custom_minimum_size = Vector2(28.0, 28.0)
			icon_frame.add_theme_stylebox_override("panel", _make_action_icon_frame_style(accent))
			icon_holder.add_child(icon_frame)
			var icon_frame_center: CenterContainer = CenterContainer.new()
			icon_frame.add_child(icon_frame_center)
			icon_parent = icon_frame_center

		var glyph: ActionGlyph = ActionGlyph.new()
		glyph.glyph_kind = str(meta["glyph"])
		glyph.accent_color = accent
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_parent.add_child(glyph)

	var label: Label = Label.new()
	label.text = str(meta["title"])
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", COLOR_TEXT_SUB)
	column.add_child(label)

	return button


func _build_item_popup() -> Control:
	var popup_root: Control = Control.new()
	popup_root.visible = false
	popup_root.modulate = Color(1.0, 1.0, 1.0, 0.0)
	popup_root.size = ITEM_POPUP_SIZE
	popup_root.custom_minimum_size = ITEM_POPUP_SIZE

	_item_popup_panel = PanelContainer.new()
	_item_popup_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_item_popup_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_item_popup_panel.add_theme_stylebox_override("panel", _make_popup_panel_style())
	popup_root.add_child(_item_popup_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_item_popup_panel.add_child(margin)

	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)

	var hdr: HBoxContainer = HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 6)
	column.add_child(hdr)

	var hdr_circle: PanelContainer = PanelContainer.new()
	hdr_circle.custom_minimum_size = Vector2(26.0, 26.0)
	hdr_circle.add_theme_stylebox_override("panel", _make_popup_circle_style())
	hdr.add_child(hdr_circle)

	var hdr_cc: CenterContainer = CenterContainer.new()
	hdr_circle.add_child(hdr_cc)

	var hdr_ic: Label = Label.new()
	hdr_ic.text = "⚗"
	hdr_ic.add_theme_font_size_override("font_size", 11)
	hdr_ic.add_theme_color_override("font_color", COLOR_GOLD)
	hdr_cc.add_child(hdr_ic)

	var hdr_txt: VBoxContainer = VBoxContainer.new()
	hdr_txt.add_theme_constant_override("separation", 0)
	hdr.add_child(hdr_txt)

	var title_label: Label = Label.new()
	title_label.text = "道具 陈列"
	title_label.add_theme_font_size_override("font_size", 11)
	title_label.add_theme_color_override("font_color", COLOR_GOLD)
	hdr_txt.add_child(title_label)

	var subtitle_label: Label = Label.new()
	subtitle_label.text = "Arrange your tools"
	subtitle_label.add_theme_font_size_override("font_size", 8)
	subtitle_label.add_theme_color_override("font_color", COLOR_TEXT_SUB)
	hdr_txt.add_child(subtitle_label)

	var divider: ColorRect = ColorRect.new()
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	divider.color = COLOR_POPUP_SEP
	column.add_child(divider)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	_item_popup_list = VBoxContainer.new()
	_item_popup_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_popup_list.add_theme_constant_override("separation", 5)
	scroll.add_child(_item_popup_list)

	scroll.get_v_scroll_bar().modulate = Color(0.0, 0.0, 0.0, 0.0)
	_rebuild_item_popup_entries()
	return popup_root


func _rebuild_item_popup_entries() -> void:
	for child: Node in _item_popup_list.get_children():
		child.queue_free()

	for item_data: Dictionary in ITEM_PLACEHOLDERS:
		_item_popup_list.add_child(_build_item_card(item_data))


func _build_item_card(item_data: Dictionary) -> PanelContainer:
	var accent: Color = Color(0.18, 0.68, 0.34, 1.0)
	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(0.0, 54.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _make_popup_card_style(accent))

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	card.add_child(margin)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	var icon_slot: PanelContainer = PanelContainer.new()
	icon_slot.custom_minimum_size = Vector2(28.0, 28.0)
	icon_slot.add_theme_stylebox_override("panel", _make_popup_icon_square_style(accent))
	row.add_child(icon_slot)

	var ic_cc: CenterContainer = CenterContainer.new()
	icon_slot.add_child(ic_cc)

	var icon_label: Label = Label.new()
	icon_label.text = "⚗"
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 12)
	icon_label.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	ic_cc.add_child(icon_label)

	var text_column: VBoxContainer = VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 1)
	row.add_child(text_column)

	var title_label: Label = Label.new()
	title_label.text = str(item_data.get("name", "道具"))
	title_label.add_theme_font_size_override("font_size", 10)
	title_label.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	text_column.add_child(title_label)

	var detail_label: Label = Label.new()
	detail_label.text = str(item_data.get("detail", ""))
	detail_label.add_theme_font_size_override("font_size", 8)
	detail_label.add_theme_color_override("font_color", COLOR_TEXT_SUB)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	text_column.add_child(detail_label)

	var badge_label: Label = Label.new()
	badge_label.text = str(item_data.get("badge", ""))
	badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_label.add_theme_font_size_override("font_size", 7)
	badge_label.add_theme_color_override("font_color", accent)
	row.add_child(badge_label)

	return card


func _extract_button_state(buttons_variant: Variant) -> Dictionary:
	if buttons_variant is Dictionary:
		return buttons_variant
	return {}


func _extract_skill_entries(entries_variant: Variant) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not (entries_variant is Array):
		return entries
	for entry_value: Variant in entries_variant:
		if entry_value is Dictionary:
			entries.append(entry_value)
	return entries


func _rebuild_status_row(status_text: String) -> void:
	for child: Node in _status_row.get_children():
		child.queue_free()

	if status_text == "":
		return

	for token: String in status_text.split(" ", false):
		if token == "":
			continue
		_status_row.add_child(_build_status_chip(token))


func _build_status_chip(token: String) -> PanelContainer:
	var chip: PanelContainer = PanelContainer.new()
	var state_key: String = token.left(1)
	var enabled: bool = token.contains("✓")
	chip.add_theme_stylebox_override("panel", _make_status_chip_style(enabled))

	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	chip.add_child(row)

	var dot: Label = Label.new()
	dot.text = "●"
	dot.add_theme_font_size_override("font_size", 8)
	dot.add_theme_color_override("font_color", Color(0.84, 0.96, 0.90, 1.0) if enabled else Color(0.98, 0.84, 0.84, 1.0))
	row.add_child(dot)

	var name_label: Label = Label.new()
	name_label.text = _localize_status_token(state_key)
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", COLOR_TEXT_MAIN)
	row.add_child(name_label)

	return chip


func _localize_status_token(token: String) -> String:
	match token:
		"M":
			return "移动"
		"A":
			return "攻击"
		"S":
			return "迅捷"
		_:
			return token


func _build_avatar_text(unit_name: String, unit_label: String) -> String:
	if unit_name != "":
		return unit_name.left(1)
	if unit_label != "":
		return unit_label.left(1)
	return "?"


func _update_buttons(buttons: Dictionary, show_skills: bool) -> void:
	var attack_visible: bool = bool(buttons.get("attack_visible", true))
	var skill_visible: bool = bool(buttons.get("skill_visible", true))
	var item_visible: bool = bool(buttons.get("item_visible", true))
	var end_turn_visible: bool = bool(buttons.get("end_turn_visible", false))
	var end_move_visible: bool = bool(buttons.get("end_move_visible", false))

	_attack_button.visible = attack_visible
	_skill_button.visible = skill_visible
	_item_button.visible = item_visible
	_end_button.visible = end_turn_visible or end_move_visible
	_end_divider.visible = _end_button.visible

	_attack_button.disabled = bool(buttons.get("attack_disabled", false))
	_skill_button.disabled = bool(buttons.get("skill_disabled", false))
	_item_button.disabled = false
	_end_button.disabled = _get_end_button_disabled(buttons)

	_attack_button.tooltip_text = str(buttons.get("attack_reason", ""))
	_skill_button.tooltip_text = str(buttons.get("skill_reason", ""))
	_item_button.tooltip_text = str(buttons.get("item_reason", ""))
	_end_button.tooltip_text = _get_end_button_tooltip(buttons)

	_skill_button.set_pressed_no_signal(show_skills)
	_item_button.set_pressed_no_signal(_item_popup_open)


func _get_end_button_disabled(buttons: Dictionary) -> bool:
	var end_move_visible: bool = bool(buttons.get("end_move_visible", false))
	if end_move_visible:
		return bool(buttons.get("end_move_disabled", false))
	return bool(buttons.get("end_turn_disabled", false))


func _get_end_button_tooltip(buttons: Dictionary) -> String:
	var end_move_visible: bool = bool(buttons.get("end_move_visible", false))
	if end_move_visible:
		return str(buttons.get("end_move_reason", ""))
	return str(buttons.get("end_turn_reason", ""))


func _update_forecast(forecast_variant: Variant, is_enemy_mode: bool) -> void:
	if is_enemy_mode or not (forecast_variant is Dictionary):
		_forecast_panel.visible = false
		return

	var forecast: Dictionary = forecast_variant
	if not bool(forecast.get("visible", false)):
		_forecast_panel.visible = false
		return

	_forecast_panel.visible = true
	_forecast_body.text = "%s\n命中 %d%%  暴击 %d%%\n预计伤害 %d  预计反击 %s" % [
		str(forecast.get("target_name", "")),
		int(forecast.get("hit_percent", 0)),
		int(forecast.get("crit_percent", 0)),
		int(forecast.get("damage", 0)),
		"是" if bool(forecast.get("counter_expected", false)) else "否",
	]


func _layout_dashboard() -> void:
	if not is_node_ready():
		return
	if _info_panel == null or _relic_panel == null or _action_shell == null or _skill_bar == null or _item_popup == null or _forecast_panel == null:
		return

	var vp_h: float = size.y
	var vp_w: float = size.x
	var offset_y: float = _panel_offset_internal

	# Force panels to content size (not stretched)
	var info_sz: Vector2 = _info_panel.get_combined_minimum_size()
	_info_panel.size = info_sz
	var action_sz: Vector2 = _action_shell.get_combined_minimum_size()
	_action_shell.size = action_sz

	# Info panel: bottom-left
	var info_pos: Vector2 = Vector2(PANEL_MARGIN, vp_h - info_sz.y - PANEL_MARGIN + offset_y)
	_info_panel.position = info_pos

	# Relic panel: adjacent right of info, same height
	_relic_panel.custom_minimum_size = Vector2(RELIC_PANEL_W, info_sz.y)
	_relic_panel.size = Vector2(RELIC_PANEL_W, info_sz.y)
	_relic_panel.position = Vector2(info_pos.x + info_sz.x - 1.0, info_pos.y)

	# Action shell: bottom-right
	var action_pos: Vector2 = Vector2(vp_w - action_sz.x - PANEL_MARGIN, vp_h - action_sz.y - PANEL_MARGIN + offset_y)
	_action_shell.position = action_pos

	# Forecast: above the relic/info area
	_forecast_panel.position = Vector2(
		maxf(PANEL_MARGIN, _relic_panel.position.x + RELIC_PANEL_W - FORECAST_PANEL_SIZE.x),
		info_pos.y - FORECAST_PANEL_SIZE.y - FORECAST_GAP_Y)

	# Skill popup: above action shell, shifted left
	var skill_sz: Vector2 = _skill_bar.get_combined_minimum_size()
	_skill_bar.size = skill_sz
	var popup_x: float = clampf(action_pos.x - 96.0, PANEL_MARGIN, vp_w - skill_sz.x - PANEL_MARGIN)
	var popup_y: float = action_pos.y - skill_sz.y - POPUP_GAP_Y
	_skill_bar.position = Vector2(popup_x, popup_y)

	# Item popup: above action shell
	_item_popup.position = Vector2(
		clampf(action_pos.x - 96.0, PANEL_MARGIN, vp_w - ITEM_POPUP_SIZE.x - PANEL_MARGIN),
		action_pos.y - ITEM_POPUP_SIZE.y - POPUP_GAP_Y)


func _set_dashboard_visible(should_show: bool) -> void:
	if _visibility_tween != null:
		_visibility_tween.kill()

	if should_show:
		visible = true
		if modulate.a < 0.01:
			modulate = Color(1.0, 1.0, 1.0, 0.0)
			_panel_offset_y = DASH_OFFSET_Y
		_visibility_tween = create_tween()
		_visibility_tween.set_trans(Tween.TRANS_QUAD)
		_visibility_tween.set_ease(Tween.EASE_OUT)
		_visibility_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), SHOW_ANIM_TIME)
		_visibility_tween.parallel().tween_property(self, "_panel_offset_y", 0.0, SHOW_ANIM_TIME)
		return

	_visibility_tween = create_tween()
	_visibility_tween.set_trans(Tween.TRANS_QUAD)
	_visibility_tween.set_ease(Tween.EASE_IN)
	_visibility_tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 0.0), HIDE_ANIM_TIME)
	_visibility_tween.parallel().tween_property(self, "_panel_offset_y", DASH_OFFSET_Y, HIDE_ANIM_TIME)
	_visibility_tween.finished.connect(_on_hide_finished, CONNECT_ONE_SHOT)


func _set_item_popup_visible(visible_state: bool) -> void:
	_item_popup_open = visible_state
	_item_button.set_pressed_no_signal(visible_state)
	if _item_popup_tween != null:
		_item_popup_tween.kill()

	if visible_state:
		_item_popup.visible = true
		_item_popup.modulate = Color(1.0, 1.0, 1.0, 0.0)
		_item_popup_panel.position.y = 10.0
		_item_popup_tween = create_tween()
		_item_popup_tween.set_trans(Tween.TRANS_QUAD)
		_item_popup_tween.set_ease(Tween.EASE_OUT)
		_item_popup_tween.tween_property(_item_popup, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15)
		_item_popup_tween.parallel().tween_property(_item_popup_panel, "position:y", 0.0, 0.15)
		return

	_item_popup_tween = create_tween()
	_item_popup_tween.set_trans(Tween.TRANS_QUAD)
	_item_popup_tween.set_ease(Tween.EASE_IN)
	_item_popup_tween.tween_property(_item_popup, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.12)
	_item_popup_tween.parallel().tween_property(_item_popup_panel, "position:y", 10.0, 0.12)
	_item_popup_tween.finished.connect(_on_item_popup_hidden, CONNECT_ONE_SHOT)


func _on_attack_pressed() -> void:
	if _item_popup_open:
		_set_item_popup_visible(false)
	attack_requested.emit()


func _on_skill_button_pressed() -> void:
	if _item_popup_open:
		_set_item_popup_visible(false)
	skill_toggle_requested.emit()


func _on_item_button_pressed() -> void:
	if bool(_current_state.get("skills_visible", false)):
		skill_toggle_requested.emit()
	_skill_button.set_pressed_no_signal(false)
	_skill_bar.set_expanded(false)
	_set_item_popup_visible(not _item_popup_open)


func _on_end_button_pressed() -> void:
	if _item_popup_open:
		_set_item_popup_visible(false)
	var buttons: Dictionary = _extract_button_state(_current_state.get("buttons", {}))
	if bool(buttons.get("end_move_visible", false)) and not bool(buttons.get("end_move_disabled", false)):
		end_move_requested.emit()
		return
	if not bool(buttons.get("end_turn_disabled", false)):
		end_turn_requested.emit()


func _on_skill_selected(skill_id: String) -> void:
	skill_selected.emit(skill_id)


func _on_hide_finished() -> void:
	if modulate.a <= 0.01:
		visible = false


func _on_item_popup_hidden() -> void:
	if not _item_popup_open:
		_item_popup.visible = false


func _make_shell_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.shadow_color = COLOR_PANEL_SHADOW
	style.shadow_size = 8
	style.shadow_offset = Vector2(0.0, 3.0)
	return style


func _make_avatar_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_PORTRAIT_BG
	style.border_color = COLOR_PORTRAIT_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	style.shadow_color = Color(0.72, 0.58, 0.28, 0.10)
	style.shadow_size = 6
	return style


func _make_tag_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.10, 0.08, 0.96)
	style.border_color = Color(0.60, 0.50, 0.28, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style


func _make_hint_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_HINT_BG
	style.border_color = COLOR_HINT_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style


func _make_status_chip_style(enabled: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.22, 0.15, 0.92) if enabled else Color(0.24, 0.12, 0.12, 0.92)
	style.border_color = Color(0.30, 0.60, 0.40, 0.80) if enabled else Color(0.60, 0.28, 0.28, 0.80)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style


func _make_relic_slot_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.08, 1.0)
	style.border_color = Color(0.56, 0.48, 0.28, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.18)
	style.shadow_size = 3
	return style


func _make_forecast_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_FORECAST_BG
	style.border_color = COLOR_FORECAST_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.shadow_color = COLOR_PANEL_SHADOW
	style.shadow_size = 8
	style.shadow_offset = Vector2(0.0, 3.0)
	return style


func _make_action_button_style(fill: Color, accent: Color, state: String) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = accent * Color(1.0, 1.0, 1.0, 0.26)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.22)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0.0, 2.0)
	match state:
		"hover":
			style.bg_color = fill.lightened(0.12)
			style.border_color = accent * Color(1.0, 1.0, 1.0, 0.50)
		"pressed":
			style.bg_color = fill.darkened(0.12)
			style.border_color = accent * Color(1.0, 1.0, 1.0, 0.42)
			style.shadow_size = 3
			style.shadow_offset = Vector2(0.0, 1.0)
		"disabled":
			style.bg_color = fill.darkened(0.28)
			style.border_color = Color(0.24, 0.24, 0.26, 0.50)
			style.shadow_size = 0
	return style


func _make_action_icon_frame_style(accent_color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_color = accent_color * Color(1.0, 1.0, 1.0, 0.42)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.shadow_color = accent_color * Color(1.0, 1.0, 1.0, 0.06)
	style.shadow_size = 2
	return style


func _make_end_icon_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.88, 0.16, 0.18, 1.0)
	style.border_color = Color(1.0, 0.72, 0.72, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0.88, 0.16, 0.18, 0.16)
	style.shadow_size = 3
	return style


func _make_popup_panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_POPUP_BG
	style.border_color = COLOR_POPUP_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.shadow_color = COLOR_POPUP_GLOW
	style.shadow_size = 12
	return style


func _make_popup_circle_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_POPUP_ICON_BG
	style.border_color = COLOR_GOLD * Color(1.0, 1.0, 1.0, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(13)
	return style


func _make_popup_card_style(accent: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_POPUP_CARD_BG
	style.border_color = accent * Color(1.0, 1.0, 1.0, 0.35)
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.set_corner_radius_all(3)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.18)
	style.shadow_size = 2
	return style


func _make_popup_icon_square_style(accent: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_POPUP_ICON_BG
	style.border_color = accent * Color(1.0, 1.0, 1.0, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	return style
