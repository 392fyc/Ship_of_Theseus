extends Control
## Dashboard Playground — Variant B: Modern Refined
## 精致圆角，柔和琥珀调，简洁字体，现代优雅战棋风格。
## F6 运行此场景查看效果。

# ═══════════════════════════════════════════════════════════════
#  Color Palette — Modern Refined: softer gradients, amber warmth
# ═══════════════════════════════════════════════════════════════
const BG_SCENE: Color = Color(0.09, 0.09, 0.12, 1.0)
const BAR_BG: Color = Color(0.06, 0.07, 0.12, 0.92)
const BAR_BORDER: Color = Color(0.55, 0.50, 0.38, 0.60)
const CARD_BG: Color = Color(0.09, 0.11, 0.18, 1.0)
const PORTRAIT_BG: Color = Color(0.07, 0.09, 0.15, 1.0)
const PORTRAIT_BORDER: Color = Color(0.60, 0.52, 0.32, 0.90)
const PORTRAIT_GLOW: Color = Color(0.60, 0.52, 0.32, 0.08)
const BTN_BG: Color = Color(0.10, 0.13, 0.20, 1.0)
const BTN_BORDER: Color = Color(0.40, 0.44, 0.52, 0.50)
const BTN_BG_HOVER: Color = Color(0.14, 0.18, 0.28, 1.0)
const BTN_ACCENT_TOP: Color = Color(0.60, 0.52, 0.32, 0.50)
const BTN_BG_DISABLED: Color = Color(0.06, 0.07, 0.11, 1.0)
const BTN_BORDER_DISABLED: Color = Color(0.20, 0.22, 0.28, 0.40)
const TEXT_MAIN: Color = Color(0.92, 0.90, 0.85, 1.0)
const TEXT_MUTED: Color = Color(0.58, 0.60, 0.68, 1.0)
const TEXT_DISABLED: Color = Color(0.35, 0.38, 0.44, 1.0)
const ACCENT: Color = Color(0.85, 0.72, 0.40, 1.0)
const HP_FILL: Color = Color(0.24, 0.72, 0.54, 1.0)
const HP_BG: Color = Color(0.08, 0.12, 0.16, 1.0)
const EXP_FILL: Color = Color(0.45, 0.58, 0.90, 1.0)
const EXP_BG: Color = Color(0.08, 0.12, 0.16, 1.0)
const CHIP_AVAIL_BG: Color = Color(0.08, 0.16, 0.14, 1.0)
const CHIP_AVAIL_BORDER: Color = Color(0.22, 0.62, 0.46, 0.80)
const CHIP_SPENT_BG: Color = Color(0.16, 0.08, 0.10, 1.0)
const CHIP_SPENT_BORDER: Color = Color(0.65, 0.30, 0.28, 0.80)

# ═══════════════════════════════════════════════════════════════
#  Layout
# ═══════════════════════════════════════════════════════════════
const BAR_HEIGHT: float = 110.0
const BAR_MARGIN_H: float = 32.0
const BAR_MARGIN_BOTTOM: float = 18.0
const PORTRAIT_SIZE: float = 72.0
const BTN_SIZE: float = 68.0
const BTN_GAP: int = 10
const BAR_CORNER: int = 12
const BTN_CORNER: int = 10

const BTN_DEFS: Array = [
	{"icon": "⚔", "label": "攻击", "key": "attack", "disabled": false},
	{"icon": "★", "label": "技能", "key": "skill", "disabled": false},
	{"icon": "◈", "label": "道具", "key": "item", "disabled": true},
	{"icon": "⏹", "label": "结束", "key": "end_turn", "disabled": false},
]

const CHIP_DEFS: Array = [
	{"icon": "靴", "label": "移动", "spent": false},
	{"icon": "⚔", "label": "攻击", "spent": true},
	{"icon": "◆", "label": "迅捷", "spent": false},
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg: ColorRect = ColorRect.new()
	bg.color = BG_SCENE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title: Label = Label.new()
	title.text = "Variant B — Modern Refined"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", ACCENT)
	title.position = Vector2(BAR_MARGIN_H, 12.0)
	add_child(title)

	_build_bar()


func _build_bar() -> void:
	var bar_width: float = 960.0
	var bar_x: float = maxf((size.x - bar_width) * 0.5, BAR_MARGIN_H)
	var bar_y: float = size.y - BAR_HEIGHT - BAR_MARGIN_BOTTOM

	var shell: PanelContainer = PanelContainer.new()
	shell.position = Vector2(bar_x, bar_y)
	shell.size = Vector2(bar_width, BAR_HEIGHT)
	shell.add_theme_stylebox_override("panel", _make_shell_style())
	add_child(shell)

	var outer_margin: MarginContainer = MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 14)
	outer_margin.add_theme_constant_override("margin_right", 14)
	outer_margin.add_theme_constant_override("margin_top", 10)
	outer_margin.add_theme_constant_override("margin_bottom", 10)
	shell.add_child(outer_margin)

	var main_row: HBoxContainer = HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 16)
	outer_margin.add_child(main_row)

	_build_portrait_area(main_row)
	_build_divider(main_row)
	_build_button_area(main_row)
	_build_divider(main_row)
	_build_status_area(main_row)


func _build_divider(parent: HBoxContainer) -> void:
	var div: ColorRect = ColorRect.new()
	div.custom_minimum_size = Vector2(1.0, 0.0)
	div.size_flags_vertical = Control.SIZE_EXPAND_FILL
	div.color = BAR_BORDER
	parent.add_child(div)


func _build_portrait_area(parent: HBoxContainer) -> void:
	var area: HBoxContainer = HBoxContainer.new()
	area.add_theme_constant_override("separation", 10)
	area.custom_minimum_size = Vector2(280.0, 0.0)
	parent.add_child(area)

	# Portrait — rounded frame with soft glow
	var portrait: PanelContainer = PanelContainer.new()
	portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.add_theme_stylebox_override("panel", _make_portrait_style())
	area.add_child(portrait)

	var portrait_center: CenterContainer = CenterContainer.new()
	portrait.add_child(portrait_center)

	var portrait_label: Label = Label.new()
	portrait_label.text = "剑"
	portrait_label.add_theme_font_size_override("font_size", 28)
	portrait_label.add_theme_color_override("font_color", TEXT_MAIN)
	portrait_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.40))
	portrait_label.add_theme_constant_override("outline_size", 2)
	portrait_center.add_child(portrait_label)

	var info_col: VBoxContainer = VBoxContainer.new()
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_col.add_theme_constant_override("separation", 2)
	area.add_child(info_col)

	var name_label: Label = Label.new()
	name_label.text = "艾琳娜"
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", TEXT_MAIN)
	info_col.add_child(name_label)

	var class_label: Label = Label.new()
	class_label.text = "圣骑士  Lv.8"
	class_label.add_theme_font_size_override("font_size", 10)
	class_label.add_theme_color_override("font_color", TEXT_MUTED)
	info_col.add_child(class_label)

	# HP
	var hp_row: HBoxContainer = HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 6)
	info_col.add_child(hp_row)

	var hp_label: Label = Label.new()
	hp_label.text = "HP"
	hp_label.custom_minimum_size = Vector2(20.0, 0.0)
	hp_label.add_theme_font_size_override("font_size", 9)
	hp_label.add_theme_color_override("font_color", HP_FILL)
	hp_row.add_child(hp_label)

	var hp_bar: ProgressBar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(90.0, 8.0)
	hp_bar.max_value = 45.0
	hp_bar.value = 32.0
	hp_bar.show_percentage = false
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.add_theme_stylebox_override("background", _make_bar_bg())
	hp_bar.add_theme_stylebox_override("fill", _make_bar_fill(HP_FILL))
	hp_row.add_child(hp_bar)

	var hp_num: Label = Label.new()
	hp_num.text = "32/45"
	hp_num.add_theme_font_size_override("font_size", 9)
	hp_num.add_theme_color_override("font_color", TEXT_MAIN)
	hp_row.add_child(hp_num)

	# EXP
	var exp_row: HBoxContainer = HBoxContainer.new()
	exp_row.add_theme_constant_override("separation", 6)
	info_col.add_child(exp_row)

	var exp_label: Label = Label.new()
	exp_label.text = "EX"
	exp_label.custom_minimum_size = Vector2(20.0, 0.0)
	exp_label.add_theme_font_size_override("font_size", 9)
	exp_label.add_theme_color_override("font_color", EXP_FILL)
	exp_row.add_child(exp_label)

	var exp_bar: ProgressBar = ProgressBar.new()
	exp_bar.custom_minimum_size = Vector2(90.0, 8.0)
	exp_bar.max_value = 100.0
	exp_bar.value = 45.0
	exp_bar.show_percentage = false
	exp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exp_bar.add_theme_stylebox_override("background", _make_bar_bg())
	exp_bar.add_theme_stylebox_override("fill", _make_bar_fill(EXP_FILL))
	exp_row.add_child(exp_bar)

	var exp_num: Label = Label.new()
	exp_num.text = "45/100"
	exp_num.add_theme_font_size_override("font_size", 9)
	exp_num.add_theme_color_override("font_color", TEXT_MAIN)
	exp_row.add_child(exp_num)


func _build_button_area(parent: HBoxContainer) -> void:
	var btn_col: VBoxContainer = VBoxContainer.new()
	btn_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_col.add_theme_constant_override("separation", 4)
	parent.add_child(btn_col)

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", BTN_GAP)
	btn_col.add_child(btn_row)

	for def: Variant in BTN_DEFS:
		var d: Dictionary = def as Dictionary
		var is_disabled: bool = bool(d.get("disabled", false))

		var btn_panel: PanelContainer = PanelContainer.new()
		btn_panel.custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
		btn_panel.add_theme_stylebox_override("panel",
			_make_btn_style_disabled() if is_disabled else _make_btn_style())
		btn_row.add_child(btn_panel)

		var inner_col: VBoxContainer = VBoxContainer.new()
		inner_col.alignment = BoxContainer.ALIGNMENT_CENTER
		inner_col.add_theme_constant_override("separation", 1)
		btn_panel.add_child(inner_col)

		# Top accent line for enabled buttons
		if not is_disabled:
			var accent_line: ColorRect = ColorRect.new()
			accent_line.custom_minimum_size = Vector2(0.0, 2.0)
			accent_line.color = BTN_ACCENT_TOP
			inner_col.add_child(accent_line)

		var icon_lbl: Label = Label.new()
		icon_lbl.text = str(d.get("icon", "?"))
		icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_lbl.add_theme_font_size_override("font_size", 20)
		icon_lbl.add_theme_color_override("font_color",
			TEXT_DISABLED if is_disabled else TEXT_MAIN)
		inner_col.add_child(icon_lbl)

		var txt_lbl: Label = Label.new()
		txt_lbl.text = str(d.get("label", ""))
		txt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		txt_lbl.add_theme_font_size_override("font_size", 10)
		txt_lbl.add_theme_color_override("font_color",
			TEXT_DISABLED if is_disabled else TEXT_MUTED)
		inner_col.add_child(txt_lbl)


func _build_status_area(parent: HBoxContainer) -> void:
	var area: VBoxContainer = VBoxContainer.new()
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	area.add_theme_constant_override("separation", 8)
	parent.add_child(area)

	# Status chips
	var chip_flow: HFlowContainer = HFlowContainer.new()
	chip_flow.add_theme_constant_override("h_separation", 6)
	chip_flow.add_theme_constant_override("v_separation", 4)
	area.add_child(chip_flow)

	for def: Variant in CHIP_DEFS:
		var d: Dictionary = def as Dictionary
		var spent: bool = bool(d.get("spent", false))
		var chip: PanelContainer = PanelContainer.new()
		chip.custom_minimum_size = Vector2(62.0, 20.0)
		chip.add_theme_stylebox_override("panel", _make_chip_style(
			CHIP_SPENT_BG if spent else CHIP_AVAIL_BG,
			CHIP_SPENT_BORDER if spent else CHIP_AVAIL_BORDER))
		chip_flow.add_child(chip)

		var chip_center: CenterContainer = CenterContainer.new()
		chip.add_child(chip_center)

		var chip_label: Label = Label.new()
		chip_label.text = "%s %s" % [str(d.get("icon", "")), str(d.get("label", ""))]
		chip_label.add_theme_font_size_override("font_size", 9)
		chip_label.add_theme_color_override("font_color",
			TEXT_DISABLED if spent else TEXT_MAIN)
		chip_center.add_child(chip_label)

	# Conditional buttons row
	var extra_row: HBoxContainer = HBoxContainer.new()
	extra_row.add_theme_constant_override("separation", 8)
	area.add_child(extra_row)

	for pair: Array in [["▶", "结束移动"], ["✕", "取消"]]:
		var btn: PanelContainer = PanelContainer.new()
		btn.custom_minimum_size = Vector2(76.0, 26.0)
		btn.add_theme_stylebox_override("panel", _make_extra_btn_style())
		extra_row.add_child(btn)

		var center: CenterContainer = CenterContainer.new()
		btn.add_child(center)

		var lbl: Label = Label.new()
		lbl.text = "%s %s" % [pair[0], pair[1]]
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", TEXT_MUTED)
		center.add_child(lbl)


# ═══════════════════════════════════════════════════════════════
#  StyleBox Factories
# ═══════════════════════════════════════════════════════════════

func _make_shell_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = BAR_BG
	s.border_color = BAR_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(BAR_CORNER)
	s.shadow_color = Color(0.0, 0.0, 0.0, 0.50)
	s.shadow_size = 18
	s.shadow_offset = Vector2(0.0, 6.0)
	return s


func _make_portrait_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = PORTRAIT_BG
	s.border_color = PORTRAIT_BORDER
	s.set_border_width_all(2)
	s.set_corner_radius_all(10)
	s.shadow_color = PORTRAIT_GLOW
	s.shadow_size = 8
	s.shadow_offset = Vector2(0.0, 2.0)
	return s


func _make_btn_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = BTN_BG
	s.border_color = BTN_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(BTN_CORNER)
	s.shadow_color = Color(0.0, 0.0, 0.0, 0.30)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0.0, 2.0)
	s.content_margin_top = 6.0
	s.content_margin_bottom = 6.0
	return s


func _make_btn_style_disabled() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = BTN_BG_DISABLED
	s.border_color = BTN_BORDER_DISABLED
	s.set_border_width_all(1)
	s.set_corner_radius_all(BTN_CORNER)
	s.content_margin_top = 6.0
	s.content_margin_bottom = 6.0
	return s


func _make_extra_btn_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.10, 0.16, 1.0)
	s.border_color = Color(0.30, 0.34, 0.42, 0.50)
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	return s


func _make_chip_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg_color
	s.border_color = border_color
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	return s


func _make_bar_bg() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = HP_BG
	s.border_color = Color(0.18, 0.22, 0.30, 0.60)
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	return s


func _make_bar_fill(fill_color: Color) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = fill_color
	s.set_corner_radius_all(2)
	return s
