extends Control
## Dashboard Playground — Variant A: 星轨法阵 (Astral Grimoire)
## 暗紫 + 金色法阵纹饰，环形 HP/EX 围绕头像，菱形指令阵，刻印石板列表。
## F6 运行此场景查看效果。


# ═══════════════════════════════════════════════════════════════
#  Inner Class: 星盘环 — custom _draw() for circular HP/EX arcs
# ═══════════════════════════════════════════════════════════════

class AstrolabeRing extends Control:
	var hp_ratio: float = 0.71
	var ex_ratio: float = 0.45
	var ring_radius: float = 85.0
	var hp_ring_w: float = 11.0
	var ex_ring_w: float = 8.0
	var ring_gap: float = 3.0

	const ARC_HP: Color = Color(0.85, 0.25, 0.30, 1.0)
	const ARC_EX: Color = Color(0.60, 0.25, 0.90, 0.90)
	const ARC_TRACK: Color = Color(0.12, 0.08, 0.18, 0.45)
	const ARC_TICK: Color = Color(0.83, 0.69, 0.22, 0.12)

	func _draw() -> void:
		var c: Vector2 = size / 2.0
		var r_hp: float = ring_radius
		var r_ex: float = ring_radius - hp_ring_w - ring_gap
		var segs: int = 64
		var start_a: float = -PI / 2.0

		# HP outer ring: track + fill
		draw_arc(c, r_hp, 0.0, TAU, segs, ARC_TRACK, hp_ring_w, true)
		if hp_ratio > 0.001:
			draw_arc(c, r_hp, start_a, start_a + hp_ratio * TAU, segs, ARC_HP, hp_ring_w, true)

		# EX inner ring: track + fill
		draw_arc(c, r_ex, 0.0, TAU, segs, ARC_TRACK, ex_ring_w, true)
		if ex_ratio > 0.001:
			draw_arc(c, r_ex, start_a, start_a + ex_ratio * TAU, segs, ARC_EX, ex_ring_w, true)

		# Decorative tick marks (12 positions)
		var tick_base: float = r_hp + hp_ring_w * 0.5 + 3.0
		for i: int in range(12):
			var angle: float = float(i) * TAU / 12.0
			var d: Vector2 = Vector2(cos(angle), sin(angle))
			draw_line(c + d * tick_base, c + d * (tick_base + 4.0), ARC_TICK, 1.0, true)


# ═══════════════════════════════════════════════════════════════
#  Color Palette
# ═══════════════════════════════════════════════════════════════

const BG_DARK: Color = Color(0.04, 0.02, 0.06, 1.0)
const PANEL_BG: Color = Color(0.09, 0.06, 0.14, 0.88)
const PANEL_BORDER: Color = Color(0.83, 0.69, 0.22, 0.22)
const GOLD: Color = Color(0.83, 0.69, 0.22, 1.0)
const GOLD_DIM: Color = Color(0.83, 0.69, 0.22, 0.35)
const GOLD_GLOW: Color = Color(0.83, 0.69, 0.22, 0.10)
const PURPLE_GLOW: Color = Color(0.58, 0.20, 0.92, 0.15)
const AVATAR_BG: Color = Color(0.03, 0.02, 0.05, 1.0)
const AVATAR_BORDER: Color = Color(0.83, 0.69, 0.22, 0.80)
const BTN_BG: Color = Color(0.08, 0.05, 0.12, 1.0)
const BTN_BORDER: Color = Color(0.83, 0.69, 0.22, 0.50)
const BTN_SEL_BORDER: Color = Color(0.83, 0.69, 0.22, 1.0)
const BTN_SEL_GLOW: Color = Color(0.83, 0.69, 0.22, 0.30)
const BTN_DIS_BG: Color = Color(0.05, 0.03, 0.07, 1.0)
const BTN_DIS_BORDER: Color = Color(0.20, 0.16, 0.24, 0.30)
const TEXT_MAIN: Color = Color(0.88, 0.85, 0.78, 1.0)
const TEXT_MUTED: Color = Color(0.50, 0.46, 0.55, 1.0)
const TEXT_DISABLED: Color = Color(0.30, 0.26, 0.34, 1.0)
const COST_S: Color = Color(0.98, 0.45, 0.09, 1.0)
const COST_M: Color = Color(0.23, 0.70, 0.96, 1.0)
const COST_A: Color = Color(0.83, 0.69, 0.22, 1.0)
const COST_SWIFT: Color = Color(0.06, 0.73, 0.51, 1.0)
const CD_COLOR: Color = Color(0.60, 0.15, 0.12, 1.0)
const CHIP_AVAIL_BG: Color = Color(0.06, 0.10, 0.14, 0.90)
const CHIP_AVAIL_BD: Color = Color(0.30, 0.55, 0.75, 0.60)
const CHIP_SPENT_BG: Color = Color(0.10, 0.05, 0.06, 0.90)
const CHIP_SPENT_BD: Color = Color(0.55, 0.25, 0.20, 0.50)
const CARD_BG: Color = Color(0.07, 0.05, 0.11, 0.95)
const ICON_BG: Color = Color(0.10, 0.07, 0.16, 1.0)
const SEP_COLOR: Color = Color(0.83, 0.69, 0.22, 0.20)

# ═══════════════════════════════════════════════════════════════
#  Layout Constants (compact scale)
# ═══════════════════════════════════════════════════════════════

const RING_RADIUS: float = 85.0
const RING_AREA: float = 224.0
const AVATAR_SZ: float = 62.0
const DIAMOND_SZ: float = 42.0
const DIAMOND_GAP: float = 6.0
const CARD_H: float = 54.0
const CARD_GAP: int = 5
const CARD_ICON_SZ: float = 28.0
const RUNE_W: float = 330.0

# ═══════════════════════════════════════════════════════════════
#  Mock Data
# ═══════════════════════════════════════════════════════════════

const MOCK_SKILLS: Array = [
	{"name": "净世火焰", "icon": "☀", "cost_type": "S", "cost": 1,
		"cd": 0, "cd_max": 0, "desc": "召唤圣火，对单体造成高额魔法伤害。"},
	{"name": "治愈光环", "icon": "✚", "cost_type": "S", "cost": 1,
		"cd": 2, "cd_max": 3, "desc": "恢复周围一格内友军 20 HP。"},
	{"name": "疾风残影", "icon": "≈", "cost_type": "M", "cost": 1,
		"cd": 0, "cd_max": 0, "desc": "本回合移动力 +3，无视控制区。"},
	{"name": "绝对神盾", "icon": "♦", "cost_type": "A", "cost": 1,
		"cd": 0, "cd_max": 0, "desc": "放弃攻击，使下一次受到的伤害变为 0。"},
]

const CMD_DEFS: Array = [
	{"icon": "⚔", "label": "攻击", "disabled": false, "selected": false},
	{"icon": "✺", "label": "技能", "disabled": false, "selected": true},
	{"icon": "⚗", "label": "道具", "disabled": true, "selected": false},
	{"icon": "◎", "label": "结束", "disabled": false, "selected": false},
]

const ORBIT_CHIPS: Array = [
	{"icon": "→", "label": "移动", "angle_deg": -135.0, "spent": false, "key": "move"},
	{"icon": "✕", "label": "攻击", "angle_deg": -55.0, "spent": true, "key": "attack"},
	{"icon": "↯", "label": "迅捷", "angle_deg": 50.0, "spent": false, "key": "swift"},
]


# ═══════════════════════════════════════════════════════════════
#  Setup
# ═══════════════════════════════════════════════════════════════

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg: ColorRect = ColorRect.new()
	bg.color = BG_DARK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title: Label = Label.new()
	title.text = "❖ ASTRAL GRIMOIRE INTERFACE ❖"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", GOLD)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.position.y = 6.0
	add_child(title)

	_build_ui()


func _build_ui() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var vp_w: float = maxf(vp.x, 800.0)
	var vp_h: float = maxf(vp.y, 500.0)

	# Explicit centering: compute total width, center on viewport
	var gap: float = 8.0
	var grid_w: float = DIAMOND_SZ * 2.0 + DIAMOND_GAP
	var total_w: float = RING_AREA + gap + grid_w + gap + RUNE_W
	var start_x: float = (vp_w - total_w) / 2.0
	var bottom_ref: float = vp_h - 14.0

	# Astrolabe: centered in its slot
	var astro_cx: float = start_x + RING_AREA / 2.0
	var astro_cy: float = bottom_ref - RING_AREA / 2.0 - 18.0
	_build_astrolabe(Vector2(astro_cx, astro_cy))

	# Command grid: centered in its slot, vertically aligned with ring
	var cmd_cx: float = start_x + RING_AREA + gap + grid_w / 2.0
	_build_command_grid(Vector2(cmd_cx, astro_cy + 6.0))

	# Rune panel: right slot, extends upward
	var rune_x: float = start_x + RING_AREA + gap + grid_w + gap
	var rune_h: float = minf(vp_h * 0.40, 300.0)
	var rune_y: float = bottom_ref - rune_h
	_build_rune_panel(Vector2(rune_x, rune_y), Vector2(RUNE_W, rune_h))


# ═══════════════════════════════════════════════════════════════
#  Section 1: 星盘法阵 — Astrolabe with HP/EX Rings
# ═══════════════════════════════════════════════════════════════

func _build_astrolabe(center: Vector2) -> void:
	var half: float = RING_AREA / 2.0
	var area: Control = Control.new()
	area.position = center - Vector2(half, half)
	area.size = Vector2(RING_AREA, RING_AREA)
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(area)

	# Arc ring drawer
	var ring: AstrolabeRing = AstrolabeRing.new()
	ring.ring_radius = RING_RADIUS
	ring.hp_ratio = 32.0 / 45.0
	ring.ex_ratio = 45.0 / 100.0
	ring.size = area.size
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(ring)

	# Avatar center
	var av_offset: float = (RING_AREA - AVATAR_SZ) / 2.0
	var avatar: PanelContainer = PanelContainer.new()
	avatar.position = Vector2(av_offset, av_offset)
	avatar.size = Vector2(AVATAR_SZ, AVATAR_SZ)
	avatar.add_theme_stylebox_override("panel", _make_avatar_style())
	area.add_child(avatar)

	var av_col: VBoxContainer = VBoxContainer.new()
	av_col.alignment = BoxContainer.ALIGNMENT_CENTER
	av_col.add_theme_constant_override("separation", 0)
	avatar.add_child(av_col)

	var av_icon: Label = Label.new()
	av_icon.text = "艾"
	av_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av_icon.add_theme_font_size_override("font_size", 18)
	av_icon.add_theme_color_override("font_color", GOLD)
	av_col.add_child(av_icon)

	var av_lv: Label = Label.new()
	av_lv.text = "LV.8"
	av_lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av_lv.add_theme_font_size_override("font_size", 7)
	av_lv.add_theme_color_override("font_color", TEXT_MUTED)
	av_col.add_child(av_lv)

	var av_class: Label = Label.new()
	av_class.text = "◇ 圣骑 ◇"
	av_class.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av_class.add_theme_font_size_override("font_size", 6)
	av_class.add_theme_color_override("font_color", GOLD_DIM)
	av_col.add_child(av_class)

	# Orbit action-resource chips
	var ac: Vector2 = Vector2(half, half)
	for chip: Variant in ORBIT_CHIPS:
		var d: Dictionary = chip as Dictionary
		var angle_r: float = deg_to_rad(float(d.get("angle_deg", 0.0)))
		_build_orbit_chip(area, ac, angle_r,
			str(d.get("icon", "")), str(d.get("label", "")),
			_cost_color(str(d.get("key", ""))), bool(d.get("spent", false)))

	# HP / EX labels below ring
	var bottom_y: float = RING_AREA + 2.0

	var hp_lbl: Label = Label.new()
	hp_lbl.text = "HP 32/45"
	hp_lbl.position = Vector2(16.0, bottom_y)
	hp_lbl.add_theme_font_size_override("font_size", 9)
	hp_lbl.add_theme_color_override("font_color", Color(0.85, 0.25, 0.30, 0.85))
	area.add_child(hp_lbl)

	var ex_lbl: Label = Label.new()
	ex_lbl.text = "EX 45/100"
	ex_lbl.position = Vector2(RING_AREA - 76.0, bottom_y)
	ex_lbl.add_theme_font_size_override("font_size", 9)
	ex_lbl.add_theme_color_override("font_color", Color(0.60, 0.25, 0.90, 0.85))
	area.add_child(ex_lbl)


func _build_orbit_chip(parent: Control, center: Vector2, angle: float,
		icon_t: String, label_t: String, accent: Color, spent: bool) -> void:
	var dist: float = RING_RADIUS + 22.0
	var cw: float = 36.0
	var ch: float = 26.0
	var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * dist \
		- Vector2(cw / 2.0, ch / 2.0)

	var chip: PanelContainer = PanelContainer.new()
	chip.position = pos
	chip.size = Vector2(cw, ch)
	chip.add_theme_stylebox_override("panel", _make_chip_style(spent))
	parent.add_child(chip)

	var col: VBoxContainer = VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	chip.add_child(col)

	var ic: Label = Label.new()
	ic.text = icon_t
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ic.add_theme_font_size_override("font_size", 9)
	ic.add_theme_color_override("font_color",
		accent.darkened(0.40) if spent else accent)
	col.add_child(ic)

	var nl: Label = Label.new()
	nl.text = label_t
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.add_theme_font_size_override("font_size", 6)
	nl.add_theme_color_override("font_color",
		TEXT_DISABLED if spent else TEXT_MAIN)
	col.add_child(nl)


# ═══════════════════════════════════════════════════════════════
#  Section 2: 战术水晶阵 — 2×2 Diamond Command Grid
# ═══════════════════════════════════════════════════════════════

func _build_command_grid(center: Vector2) -> void:
	var half: float = (DIAMOND_SZ + DIAMOND_GAP) / 2.0
	var offsets: Array = [
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(-half, half), Vector2(half, half),
	]
	for i: int in range(CMD_DEFS.size()):
		var d: Dictionary = CMD_DEFS[i] as Dictionary
		_build_diamond_btn(center + (offsets[i] as Vector2), d)


func _build_diamond_btn(ctr: Vector2, d: Dictionary) -> void:
	var is_dis: bool = bool(d.get("disabled", false))
	var is_sel: bool = bool(d.get("selected", false))
	var s: float = DIAMOND_SZ

	# Wrapper (absolute, unrotated)
	var wrap: Control = Control.new()
	wrap.position = ctr - Vector2(s / 2.0, s / 2.0)
	wrap.size = Vector2(s, s)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)

	# Diamond bg (rotated 45 deg)
	var ds: float = s * 0.72
	var diamond: PanelContainer = PanelContainer.new()
	diamond.size = Vector2(ds, ds)
	diamond.position = (wrap.size - diamond.size) / 2.0
	diamond.pivot_offset = Vector2(ds / 2.0, ds / 2.0)
	diamond.rotation = PI / 4.0
	if is_dis:
		diamond.add_theme_stylebox_override("panel", _make_dia_disabled())
	elif is_sel:
		diamond.add_theme_stylebox_override("panel", _make_dia_selected())
	else:
		diamond.add_theme_stylebox_override("panel", _make_dia_normal())
	wrap.add_child(diamond)

	# Text overlay (not rotated)
	var tcol: VBoxContainer = VBoxContainer.new()
	tcol.position = Vector2.ZERO
	tcol.size = wrap.size
	tcol.alignment = BoxContainer.ALIGNMENT_CENTER
	tcol.add_theme_constant_override("separation", 0)
	tcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(tcol)

	var ic_color: Color = TEXT_DISABLED if is_dis else (GOLD if is_sel else TEXT_MAIN)
	var tx_color: Color = TEXT_DISABLED if is_dis else (GOLD if is_sel else TEXT_MUTED)

	var ic_lbl: Label = Label.new()
	ic_lbl.text = str(d.get("icon", ""))
	ic_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ic_lbl.add_theme_font_size_override("font_size", 13)
	ic_lbl.add_theme_color_override("font_color", ic_color)
	if is_sel:
		ic_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		ic_lbl.add_theme_constant_override("outline_size", 2)
	tcol.add_child(ic_lbl)

	var nm_lbl: Label = Label.new()
	nm_lbl.text = str(d.get("label", ""))
	nm_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm_lbl.add_theme_font_size_override("font_size", 8)
	nm_lbl.add_theme_color_override("font_color", tx_color)
	tcol.add_child(nm_lbl)


# ═══════════════════════════════════════════════════════════════
#  Section 3: 刻印石板阵列 — Rune Panel with Skill Tablets
# ═══════════════════════════════════════════════════════════════

func _build_rune_panel(pos: Vector2, sz: Vector2) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.position = pos
	panel.size = sz
	panel.add_theme_stylebox_override("panel", _make_rune_panel_style())
	add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 5)
	margin.add_child(col)

	# ── Header ──
	var hdr: HBoxContainer = HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 6)
	col.add_child(hdr)

	var hdr_circle: PanelContainer = PanelContainer.new()
	hdr_circle.custom_minimum_size = Vector2(26.0, 26.0)
	hdr_circle.add_theme_stylebox_override("panel",
		_make_circle_style(ICON_BG, GOLD_DIM, 13))
	hdr.add_child(hdr_circle)

	var hdr_cc: CenterContainer = CenterContainer.new()
	hdr_circle.add_child(hdr_cc)

	var hdr_ic: Label = Label.new()
	hdr_ic.text = "☆"
	hdr_ic.add_theme_font_size_override("font_size", 11)
	hdr_ic.add_theme_color_override("font_color", GOLD)
	hdr_cc.add_child(hdr_ic)

	var hdr_txt: VBoxContainer = VBoxContainer.new()
	hdr_txt.add_theme_constant_override("separation", 0)
	hdr.add_child(hdr_txt)

	var hdr_title: Label = Label.new()
	hdr_title.text = "技能 刻印"
	hdr_title.add_theme_font_size_override("font_size", 11)
	hdr_title.add_theme_color_override("font_color", GOLD)
	hdr_txt.add_child(hdr_title)

	var hdr_sub: Label = Label.new()
	hdr_sub.text = "Channel your will"
	hdr_sub.add_theme_font_size_override("font_size", 8)
	hdr_sub.add_theme_color_override("font_color", TEXT_MUTED)
	hdr_txt.add_child(hdr_sub)

	# ── Separator ──
	var sep: ColorRect = ColorRect.new()
	sep.custom_minimum_size = Vector2(0.0, 1.0)
	sep.color = SEP_COLOR
	col.add_child(sep)

	# ── Scroll area ──
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	col.add_child(scroll)

	var vsb: VScrollBar = scroll.get_v_scroll_bar()
	vsb.modulate = Color(0.0, 0.0, 0.0, 0.0)

	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", CARD_GAP)
	scroll.add_child(list)

	for i: int in range(MOCK_SKILLS.size()):
		_build_rune_card(list, MOCK_SKILLS[i] as Dictionary)


func _build_rune_card(parent: VBoxContainer, sd: Dictionary) -> void:
	var cost_type: String = str(sd.get("cost_type", "S"))
	var accent: Color = _badge_color(cost_type)
	var cd: int = int(sd.get("cd", 0))
	var cd_max: int = int(sd.get("cd_max", 0))
	var on_cd: bool = cd > 0

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(0.0, CARD_H)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",
		_make_card_cd() if on_cd else _make_card_style(accent))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(card)

	# Hover: slide right + brighten
	card.mouse_entered.connect(func() -> void:
		var tw: Tween = card.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "position:x", 10.0, 0.18)
		tw.parallel().tween_property(card, "modulate", Color(1.2, 1.2, 1.2, 1.0), 0.18)
	)
	card.mouse_exited.connect(func() -> void:
		var tw: Tween = card.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "position:x", 0.0, 0.18)
		tw.parallel().tween_property(card, "modulate", Color.WHITE, 0.18)
	)

	var cm: MarginContainer = MarginContainer.new()
	cm.add_theme_constant_override("margin_left", 8)
	cm.add_theme_constant_override("margin_right", 8)
	cm.add_theme_constant_override("margin_top", 5)
	cm.add_theme_constant_override("margin_bottom", 5)
	card.add_child(cm)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	cm.add_child(row)

	# Circle icon
	var ic_bg: PanelContainer = PanelContainer.new()
	ic_bg.custom_minimum_size = Vector2(CARD_ICON_SZ, CARD_ICON_SZ)
	ic_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ic_border: Color = accent.darkened(0.30) if on_cd else accent * Color(1, 1, 1, 0.40)
	ic_bg.add_theme_stylebox_override("panel",
		_make_circle_style(ICON_BG, ic_border, int(CARD_ICON_SZ / 2.0)))
	row.add_child(ic_bg)

	var ic_cc: CenterContainer = CenterContainer.new()
	ic_bg.add_child(ic_cc)

	var ic_lbl: Label = Label.new()
	ic_lbl.text = str(sd.get("icon", "✦"))
	ic_lbl.add_theme_font_size_override("font_size", 11)
	ic_lbl.add_theme_color_override("font_color",
		TEXT_DISABLED if on_cd else TEXT_MAIN)
	ic_cc.add_child(ic_lbl)

	# Info column
	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 1)
	row.add_child(info)

	var nm: Label = Label.new()
	nm.text = str(sd.get("name", ""))
	nm.add_theme_font_size_override("font_size", 10)
	nm.add_theme_color_override("font_color",
		TEXT_DISABLED if on_cd else TEXT_MAIN)
	info.add_child(nm)

	var desc: Label = Label.new()
	desc.text = str(sd.get("desc", ""))
	desc.add_theme_font_size_override("font_size", 8)
	desc.add_theme_color_override("font_color", TEXT_MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.add_child(desc)

	# Badges column
	var badges: VBoxContainer = VBoxContainer.new()
	badges.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badges.add_theme_constant_override("separation", 2)
	row.add_child(badges)

	if on_cd:
		var cd_badge: PanelContainer = PanelContainer.new()
		cd_badge.custom_minimum_size = Vector2(44.0, 14.0)
		cd_badge.add_theme_stylebox_override("panel", _make_badge_style(CD_COLOR))
		badges.add_child(cd_badge)
		var cd_cc: CenterContainer = CenterContainer.new()
		cd_badge.add_child(cd_cc)
		var cd_lbl: Label = Label.new()
		cd_lbl.text = "CD: %d/%d" % [cd, cd_max]
		cd_lbl.add_theme_font_size_override("font_size", 7)
		cd_lbl.add_theme_color_override("font_color", TEXT_MAIN)
		cd_cc.add_child(cd_lbl)

	var cost_bg: PanelContainer = PanelContainer.new()
	cost_bg.custom_minimum_size = Vector2(44.0, 14.0)
	cost_bg.add_theme_stylebox_override("panel",
		_make_badge_style(accent.darkened(0.60) if on_cd else accent.darkened(0.40)))
	badges.add_child(cost_bg)

	var cost_cc: CenterContainer = CenterContainer.new()
	cost_bg.add_child(cost_cc)

	var cost_lbl: Label = Label.new()
	cost_lbl.text = "%s ×%d" % [cost_type, int(sd.get("cost", 1))]
	cost_lbl.add_theme_font_size_override("font_size", 7)
	cost_lbl.add_theme_color_override("font_color",
		TEXT_DISABLED if on_cd else accent)
	cost_cc.add_child(cost_lbl)


# ═══════════════════════════════════════════════════════════════
#  Color Helpers
# ═══════════════════════════════════════════════════════════════

func _cost_color(key: String) -> Color:
	match key:
		"move": return COST_M
		"attack": return COST_A
		"swift": return COST_SWIFT
		_: return COST_S


func _badge_color(t: String) -> Color:
	match t:
		"S": return COST_S
		"M": return COST_M
		"A": return COST_A
		_: return COST_SWIFT


# ═══════════════════════════════════════════════════════════════
#  StyleBox Factories
# ═══════════════════════════════════════════════════════════════

func _make_avatar_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = AVATAR_BG
	s.border_color = AVATAR_BORDER
	s.set_border_width_all(2)
	s.set_corner_radius_all(int(AVATAR_SZ / 2.0))
	s.shadow_color = PURPLE_GLOW
	s.shadow_size = 10
	return s


func _make_chip_style(spent: bool) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = CHIP_SPENT_BG if spent else CHIP_AVAIL_BG
	s.border_color = CHIP_SPENT_BD if spent else CHIP_AVAIL_BD
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	return s


func _make_dia_normal() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = BTN_BG
	s.border_color = BTN_BORDER
	s.set_border_width_all(2)
	s.set_corner_radius_all(3)
	s.shadow_color = GOLD_GLOW
	s.shadow_size = 3
	return s


func _make_dia_selected() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = BTN_BG.lightened(0.08)
	s.border_color = BTN_SEL_BORDER
	s.set_border_width_all(2)
	s.set_corner_radius_all(3)
	s.shadow_color = BTN_SEL_GLOW
	s.shadow_size = 8
	return s


func _make_dia_disabled() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = BTN_DIS_BG
	s.border_color = BTN_DIS_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	return s


func _make_rune_panel_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = PANEL_BG
	s.border_color = PANEL_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(5)
	s.shadow_color = PURPLE_GLOW
	s.shadow_size = 12
	return s


func _make_card_style(accent: Color) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = CARD_BG
	s.border_color = accent * Color(1, 1, 1, 0.35)
	s.set_border_width_all(1)
	s.border_width_left = 3
	s.set_corner_radius_all(3)
	s.shadow_color = Color(0.0, 0.0, 0.0, 0.18)
	s.shadow_size = 2
	return s


func _make_card_cd() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.03, 0.07, 0.85)
	s.border_color = Color(0.20, 0.16, 0.24, 0.25)
	s.set_border_width_all(1)
	s.border_width_left = 3
	s.set_corner_radius_all(3)
	return s


func _make_circle_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	return s


func _make_badge_style(bg: Color) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(3)
	s.content_margin_left = 3.0
	s.content_margin_right = 3.0
	s.content_margin_top = 1.0
	s.content_margin_bottom = 1.0
	return s
