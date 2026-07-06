extends Control
## Dashboard Playground — Variant C: 逐步设计
## Step 1: 角色信息面板 (头像 / 名称 / 职业 / HP+护盾 / XP / 属性)
## F6 运行此场景查看效果。


# ═══════════════════════════════════════════════════════════════
#  Inner Class: HP/护盾复合血条 — custom _draw()
# ═══════════════════════════════════════════════════════════════

class HPShieldBar extends Control:
	## Draws combined HP (left→right, gradient) + Shield (right→left, blue).
	var hp: int = 32
	var hp_max: int = 45
	var shield: int = 15

	const BAR_BG_C: Color = Color(0.04, 0.05, 0.10, 1.0)
	const BORDER_NORMAL: Color = Color(0.40, 0.35, 0.22, 0.55)
	const BORDER_SHIELD: Color = Color(0.40, 0.65, 0.85, 0.65)
	const SHIELD_FILL_C: Color = Color(0.36, 0.63, 0.92, 0.32)
	const SHIELD_GLOSS_C: Color = Color(0.82, 0.92, 1.00, 0.14)
	const SHIELD_EDGE_C: Color = Color(0.72, 0.88, 1.00, 0.28)
	const HP_STOPS: Array = [
		Color(0.80, 0.15, 0.15),   # 0%
		Color(0.85, 0.40, 0.15),   # 20%
		Color(0.85, 0.65, 0.15),   # 40%
		Color(0.80, 0.80, 0.20),   # 60%
		Color(0.50, 0.80, 0.30),   # 80%
		Color(0.25, 0.75, 0.40),   # 100%
	]

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		var hp_ratio: float = clampf(float(hp) / maxf(float(hp_max), 1.0), 0.0, 1.0)
		var shield_ratio: float = clampf(float(shield) / maxf(float(hp_max), 1.0), 0.0, 1.0)

		# Background
		draw_rect(Rect2(0.0, 0.0, w, h), BAR_BG_C)

		# HP fill: left → right, gradient color based on ratio
		if hp_ratio > 0.001:
			draw_rect(Rect2(1.0, 1.0, (w - 2.0) * hp_ratio, h - 2.0), _hp_gradient(hp_ratio))

		# Shield fill: right → left, transparent blue
		if shield_ratio > 0.001:
			var sw: float = (w - 2.0) * shield_ratio
			var sx: float = w - 1.0 - sw
			var inner_h: float = h - 2.0
			draw_rect(Rect2(sx, 1.0, sw, inner_h), SHIELD_FILL_C)
			draw_rect(Rect2(sx + 1.0, 1.0, maxf(sw - 2.0, 0.0), maxf(inner_h * 0.45, 1.0)), SHIELD_GLOSS_C)
			draw_line(Vector2(sx, 1.0), Vector2(sx, h - 1.0), SHIELD_EDGE_C, 1.0, true)
			draw_line(Vector2(sx + 1.0, 1.0), Vector2(w - 1.0, 1.0), SHIELD_EDGE_C, 1.0, true)

		# Border: light blue if shielded, else muted gold
		var bc: Color = BORDER_SHIELD if shield > 0 else BORDER_NORMAL
		draw_rect(Rect2(0.0, 0.0, w, h), bc, false, 1.0)

	func _hp_gradient(ratio: float) -> Color:
		var idx: float = clampf(ratio, 0.0, 1.0) * 5.0
		var i: int = mini(int(idx), 4)
		var t: float = idx - float(i)
		return (HP_STOPS[i] as Color).lerp(HP_STOPS[i + 1] as Color, t)


# ═══════════════════════════════════════════════════════════════
#  Inner Class: XP 经验槽 — custom _draw()
# ═══════════════════════════════════════════════════════════════

class XPBar extends Control:
	## Flat purple XP bar with centered text.
	var xp: int = 45
	var xp_max: int = 100

	const XP_BG_C: Color = Color(0.10, 0.07, 0.20, 1.0)
	const XP_FILL_C: Color = Color(0.40, 0.28, 0.70, 1.0)
	const XP_BORDER_C: Color = Color(0.48, 0.34, 0.72, 0.50)

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		var ratio: float = clampf(float(xp) / maxf(float(xp_max), 1.0), 0.0, 1.0)

		draw_rect(Rect2(0.0, 0.0, w, h), XP_BG_C)
		if ratio > 0.001:
			draw_rect(Rect2(1.0, 1.0, (w - 2.0) * ratio, h - 2.0), XP_FILL_C)
		draw_rect(Rect2(0.0, 0.0, w, h), XP_BORDER_C, false, 1.0)


class ActionGlyph extends Control:
	## Transparent custom glyphs for action buttons.
	var glyph_kind: String = ""
	var accent_color: Color = Color(1.0, 1.0, 1.0, 1.0)

	func _draw() -> void:
		match glyph_kind:
			"attack":
				_draw_attack_glyph()
			"skill":
				_draw_skill_glyph()
			"item":
				_draw_item_glyph()

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
		draw_colored_polygon([
			blade_a1,
			blade_a1 + Vector2(2.0, -1.0),
			blade_a1 + Vector2(1.0, 2.0)
		], steel)
		draw_colored_polygon([
			blade_b1,
			blade_b1 + Vector2(-2.0, -1.0),
			blade_b1 + Vector2(-1.0, 2.0)
		], steel)

	func _draw_skill_glyph() -> void:
		var left_top: Vector2 = Vector2(10.0, 9.0)
		var right_top: Vector2 = Vector2(20.0, 7.0)
		var bottom: Vector2 = Vector2(15.0, 18.0)
		_draw_diamond(left_top, 4.0, accent_color, true)
		_draw_diamond(right_top, 4.0, accent_color, false)
		_draw_diamond(bottom, 4.5, accent_color, true)
		draw_line(left_top, right_top, accent_color * Color(1.0, 1.0, 1.0, 0.25), 1.0, true)
		draw_line(left_top, bottom, accent_color * Color(1.0, 1.0, 1.0, 0.25), 1.0, true)
		draw_line(right_top, bottom, accent_color * Color(1.0, 1.0, 1.0, 0.25), 1.0, true)

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


var _action_shell: PanelContainer = null
var _popup_panel: PanelContainer = null
var _popup_title_label: Label = null
var _popup_sub_label: Label = null
var _popup_list: VBoxContainer = null
var _popup_mode: String = ""


# ═══════════════════════════════════════════════════════════════
#  Color Palette — Dark Fantasy (BG3 Hybrid)
# ═══════════════════════════════════════════════════════════════

const BG_SCENE: Color = Color(0.05, 0.05, 0.07, 1.0)
const PANEL_BG: Color = Color(0.04, 0.05, 0.10, 0.95)
const PANEL_BORDER: Color = Color(0.60, 0.50, 0.28, 0.50)
const PORTRAIT_BG: Color = Color(0.02, 0.03, 0.07, 1.0)
const PORTRAIT_BORDER: Color = Color(0.72, 0.58, 0.28, 1.0)
const GOLD: Color = Color(0.72, 0.58, 0.28, 1.0)
const TEXT_MAIN: Color = Color(0.90, 0.86, 0.78, 1.0)
const TEXT_MUTED: Color = Color(0.55, 0.56, 0.60, 1.0)
const STAT_ABBR: Color = Color(0.68, 0.56, 0.30, 1.0)
const HP_LABEL_C: Color = Color(0.50, 0.78, 0.55, 1.0)
const SHIELD_LABEL_C: Color = Color(0.50, 0.72, 0.90, 1.0)
const POPUP_PANEL_BG: Color = Color(0.09, 0.06, 0.14, 0.88)
const POPUP_PANEL_BORDER: Color = Color(0.83, 0.69, 0.22, 0.22)
const POPUP_CARD_BG: Color = Color(0.07, 0.05, 0.11, 0.95)
const POPUP_ICON_BG: Color = Color(0.10, 0.07, 0.16, 1.0)
const POPUP_SEP: Color = Color(0.83, 0.69, 0.22, 0.20)
const POPUP_GLOW: Color = Color(0.58, 0.20, 0.92, 0.15)

# ═══════════════════════════════════════════════════════════════
#  Layout Constants
# ═══════════════════════════════════════════════════════════════

const PORTRAIT_W: float = 78.0
const PORTRAIT_H: float = 104.0
const XP_BAR_H: float = 16.0
const XP_BAR_W: float = 82.0
const HP_BAR_W: float = 181.0
const HP_BAR_H: float = 12.0
const STAT_CELL_W: float = 44.0
const STAT_CELL_H: float = 16.0
const STAT_GRID_SEP: int = 1
const STATS_SECTION_SEP: int = 3
const RELIC_PANEL_W: float = 96.0
const RELIC_ICON_SIZE: float = 28.0
const RELIC_GRID_GAP: int = 8
const ACTION_BTN_SIZE: float = 52.0
const ACTION_BAR_GAP: int = 6
const ACTION_DIVIDER_H: float = 28.0
const POPUP_W: float = 330.0
const POPUP_H: float = 284.0
const POPUP_CARD_H: float = 54.0
const POPUP_CARD_GAP: int = 5
const PANEL_PAD: int = 8

# ═══════════════════════════════════════════════════════════════
#  Mock Data
# ═══════════════════════════════════════════════════════════════

const MOCK_CHAR: Dictionary = {
	"name": "艾琳娜",
	"level": 8,
	"class": "圣骑士",
	"hp": 45,
	"hp_max": 45,
	"shield": 30,
	"xp": 45,
	"xp_max": 100,
}

const MOCK_STATS: Array = [
	["STR", 18], ["MAG", 12], ["DEX", 15], ["SPE", 13],
	["DEF", 14], ["RES", 10], ["LCK", 8], ["MOV", 5],
]

const ACTION_BUTTONS: Array = [
	{"kind": "attack", "label": "攻击", "accent": Color(0.86, 0.80, 0.74, 1.0), "fill": Color(0.16, 0.11, 0.08, 1.0)},
	{"kind": "skill", "label": "技能", "accent": Color(0.86, 0.86, 0.94, 1.0), "fill": Color(0.10, 0.11, 0.16, 1.0), "icon_frame": true},
	{"kind": "item", "label": "道具", "accent": Color(0.86, 0.78, 0.68, 1.0), "fill": Color(0.13, 0.10, 0.08, 1.0), "icon_frame": true},
	{"icon": "", "label": "结束", "accent": Color(0.90, 0.18, 0.18, 1.0), "fill": Color(0.14, 0.07, 0.08, 1.0), "end_square": true},
]

const MOCK_SKILL_POPUP: Array = [
	{"title": "净世火焰", "subtitle": "召唤圣火，对单体造成高额魔法伤害。", "icon": "☆", "accent": Color(0.98, 0.45, 0.09, 1.0), "badge": "S ×1"},
	{"title": "治愈光环", "subtitle": "恢复周围一格内友军 20 HP。", "icon": "✚", "accent": Color(0.98, 0.45, 0.09, 1.0), "badge": "S ×1"},
	{"title": "疾风残影", "subtitle": "本回合移动力 +3。", "icon": "✦", "accent": Color(0.23, 0.70, 0.96, 1.0), "badge": "M ×1"},
	{"title": "绝对神盾", "subtitle": "放弃攻击，使下一次受到的伤害变为 0。", "icon": "♦", "accent": Color(0.72, 0.58, 0.28, 1.0), "badge": "A ×1"},
	{"title": "神圣连斩", "subtitle": "对目标进行两次连续打击。", "icon": "⚔", "accent": Color(0.98, 0.45, 0.09, 1.0), "badge": "S ×2"},
]

const MOCK_ITEM_POPUP: Array = [
	{"title": "治疗药剂", "subtitle": "恢复 25 点生命值。", "icon": "⚗", "accent": Color(0.18, 0.68, 0.34, 1.0), "badge": "×3"},
	{"title": "魔力药剂", "subtitle": "恢复 15 点法力值。", "icon": "⚗", "accent": Color(0.34, 0.56, 0.90, 1.0), "badge": "×2"},
	{"title": "抗毒药", "subtitle": "解除中毒并提供 2 回合抗性。", "icon": "⚗", "accent": Color(0.56, 0.80, 0.34, 1.0), "badge": "×1"},
	{"title": "战术札记", "subtitle": "阅读后获得临时命中加成。", "icon": "▤", "accent": Color(0.70, 0.60, 0.42, 1.0), "badge": "×1"},
	{"title": "封印卷轴", "subtitle": "对单体施加沉默效果。", "icon": "▤", "accent": Color(0.70, 0.48, 0.86, 1.0), "badge": "×2"},
]


# ═══════════════════════════════════════════════════════════════
#  Setup
# ═══════════════════════════════════════════════════════════════

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Scene background
	var bg: ColorRect = ColorRect.new()
	bg.color = BG_SCENE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_build_character_info()
	_build_action_bar()


# ═══════════════════════════════════════════════════════════════
#  Character Info Panel
# ═══════════════════════════════════════════════════════════════

func _build_character_info() -> void:
	var vp: Vector2 = get_viewport_rect().size

	# Outer panel
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PANEL_PAD)
	margin.add_theme_constant_override("margin_right", PANEL_PAD)
	margin.add_theme_constant_override("margin_top", PANEL_PAD)
	margin.add_theme_constant_override("margin_bottom", PANEL_PAD)
	panel.add_child(margin)

	var main_row: HBoxContainer = HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 8)
	margin.add_child(main_row)

	# ── Left column: Portrait + XP ──
	var left_col: VBoxContainer = VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 3)
	left_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	main_row.add_child(left_col)

	_build_portrait(left_col)

	# ── Right column: Name / Class / HP / Stats ──
	var right_col: VBoxContainer = VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 4)
	right_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	main_row.add_child(right_col)

	_build_name_plate(right_col)
	_build_hp_area(right_col)
	_build_stats_area(right_col)

	# Position: flush to the bottom-left, preserving size and proportions.
	await panel.resized
	panel.position = Vector2(
		12.0,
		vp.y - panel.size.y - 14.0)

	_build_relic_panel(panel)


# ═══════════════════════════════════════════════════════════════
#  Sub-builders
# ═══════════════════════════════════════════════════════════════

func _build_portrait(parent: VBoxContainer) -> void:
	var frame: PanelContainer = PanelContainer.new()
	frame.custom_minimum_size = Vector2(PORTRAIT_W, PORTRAIT_H)
	frame.add_theme_stylebox_override("panel", _make_portrait_style())
	parent.add_child(frame)

	var center: CenterContainer = CenterContainer.new()
	frame.add_child(center)

	var icon: Label = Label.new()
	icon.text = "艾"
	icon.add_theme_font_size_override("font_size", 30)
	icon.add_theme_color_override("font_color", GOLD)
	icon.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	icon.add_theme_constant_override("outline_size", 2)
	center.add_child(icon)


func _build_xp_bar(parent: Control) -> void:
	# Container for bar + overlaid label
	var area: Control = Control.new()
	area.custom_minimum_size = Vector2(XP_BAR_W, XP_BAR_H)
	parent.add_child(area)

	var bar: XPBar = XPBar.new()
	bar.xp = int(MOCK_CHAR.get("xp", 0))
	bar.xp_max = int(MOCK_CHAR.get("xp_max", 100))
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	area.add_child(bar)

	var lbl: Label = Label.new()
	lbl.text = "XP %d" % int(MOCK_CHAR.get("xp", 0))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.80, 0.95, 0.90))
	area.add_child(lbl)


func _build_name_plate(parent: VBoxContainer) -> void:
	var name_lbl: Label = Label.new()
	name_lbl.text = str(MOCK_CHAR.get("name", ""))
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", TEXT_MAIN)
	parent.add_child(name_lbl)

	var class_row: HBoxContainer = HBoxContainer.new()
	class_row.add_theme_constant_override("separation", 6)
	parent.add_child(class_row)

	var lv_lbl: Label = Label.new()
	lv_lbl.text = "Lv.%d" % int(MOCK_CHAR.get("level", 1))
	lv_lbl.add_theme_font_size_override("font_size", 10)
	lv_lbl.add_theme_color_override("font_color", TEXT_MUTED)
	class_row.add_child(lv_lbl)

	var cls_lbl: Label = Label.new()
	cls_lbl.text = str(MOCK_CHAR.get("class", ""))
	cls_lbl.add_theme_font_size_override("font_size", 10)
	cls_lbl.add_theme_color_override("font_color", TEXT_MUTED)
	class_row.add_child(cls_lbl)

	var xp_gap: Control = Control.new()
	xp_gap.custom_minimum_size = Vector2(8.0, 0.0)
	class_row.add_child(xp_gap)

	_build_xp_bar(class_row)


func _build_hp_area(parent: VBoxContainer) -> void:
	var hp: int = int(MOCK_CHAR.get("hp", 0))
	var hp_max: int = int(MOCK_CHAR.get("hp_max", 1))
	var shield: int = int(MOCK_CHAR.get("shield", 0))

	# Value labels row
	var label_row: HBoxContainer = HBoxContainer.new()
	parent.add_child(label_row)

	var hp_lbl: Label = Label.new()
	hp_lbl.text = "HP %d/%d" % [hp, hp_max]
	hp_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_lbl.add_theme_font_size_override("font_size", 9)
	hp_lbl.add_theme_color_override("font_color", HP_LABEL_C)
	label_row.add_child(hp_lbl)

	if shield > 0:
		var shield_lbl: Label = Label.new()
		shield_lbl.text = "护盾 %d" % shield
		shield_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		shield_lbl.add_theme_font_size_override("font_size", 9)
		shield_lbl.add_theme_color_override("font_color", SHIELD_LABEL_C)
		label_row.add_child(shield_lbl)

	# Bar
	var bar: HPShieldBar = HPShieldBar.new()
	bar.hp = hp
	bar.hp_max = hp_max
	bar.shield = shield
	bar.custom_minimum_size = Vector2(HP_BAR_W, HP_BAR_H)
	parent.add_child(bar)


func _build_stats_area(parent: VBoxContainer) -> void:
	var stats_row: HBoxContainer = HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", STATS_SECTION_SEP)
	parent.add_child(stats_row)

	# Grid 1: STR MAG / DEX SPE  (indices 0-3)
	var grid1: GridContainer = GridContainer.new()
	grid1.columns = 2
	grid1.add_theme_constant_override("h_separation", STAT_GRID_SEP)
	grid1.add_theme_constant_override("v_separation", 1)
	stats_row.add_child(grid1)

	for i: int in range(0, 4):
		_build_stat_cell(grid1, MOCK_STATS[i])

	# Small divider
	var div: ColorRect = ColorRect.new()
	div.custom_minimum_size = Vector2(1.0, 0.0)
	div.size_flags_vertical = Control.SIZE_EXPAND_FILL
	div.color = Color(0.40, 0.35, 0.22, 0.30)
	stats_row.add_child(div)

	# Grid 2: DEF RES / LCK MOV  (indices 4-7)
	var grid2: GridContainer = GridContainer.new()
	grid2.columns = 2
	grid2.add_theme_constant_override("h_separation", STAT_GRID_SEP)
	grid2.add_theme_constant_override("v_separation", 1)
	stats_row.add_child(grid2)

	for i: int in range(4, 8):
		_build_stat_cell(grid2, MOCK_STATS[i])


func _build_stat_cell(parent: GridContainer, stat: Array) -> void:
	var cell: HBoxContainer = HBoxContainer.new()
	cell.custom_minimum_size = Vector2(STAT_CELL_W, STAT_CELL_H)
	cell.add_theme_constant_override("separation", 2)
	parent.add_child(cell)

	var abbr: Label = Label.new()
	abbr.text = str(stat[0])
	abbr.add_theme_font_size_override("font_size", 9)
	abbr.add_theme_color_override("font_color", STAT_ABBR)
	cell.add_child(abbr)

	var val_lbl: Label = Label.new()
	val_lbl.text = str(stat[1])
	val_lbl.add_theme_font_size_override("font_size", 9)
	val_lbl.add_theme_color_override("font_color", TEXT_MAIN)
	cell.add_child(val_lbl)


func _build_relic_panel(anchor_panel: PanelContainer) -> void:
	var relic_panel: PanelContainer = PanelContainer.new()
	relic_panel.add_theme_stylebox_override("panel", _make_panel_style())
	relic_panel.size = Vector2(RELIC_PANEL_W, anchor_panel.size.y)
	relic_panel.position = Vector2(anchor_panel.position.x + anchor_panel.size.x - 1.0, anchor_panel.position.y)
	add_child(relic_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	relic_panel.add_child(margin)

	var center: CenterContainer = CenterContainer.new()
	margin.add_child(center)

	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", RELIC_GRID_GAP)
	grid.add_theme_constant_override("v_separation", RELIC_GRID_GAP)
	center.add_child(grid)

	for i: int in range(6):
		var slot: PanelContainer = PanelContainer.new()
		slot.custom_minimum_size = Vector2(RELIC_ICON_SIZE, RELIC_ICON_SIZE)
		slot.add_theme_stylebox_override("panel", _make_relic_slot_style())
		grid.add_child(slot)

		var slot_center: CenterContainer = CenterContainer.new()
		slot.add_child(slot_center)

		var glyph: Label = Label.new()
		glyph.text = "◌"
		glyph.add_theme_font_size_override("font_size", 12)
		glyph.add_theme_color_override("font_color", TEXT_MUTED)
		slot_center.add_child(glyph)


func _build_action_bar() -> void:
	var vp: Vector2 = get_viewport_rect().size

	var shell: PanelContainer = PanelContainer.new()
	shell.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(shell)
	_action_shell = shell

	var shell_margin: MarginContainer = MarginContainer.new()
	shell_margin.add_theme_constant_override("margin_left", 8)
	shell_margin.add_theme_constant_override("margin_right", 8)
	shell_margin.add_theme_constant_override("margin_top", 8)
	shell_margin.add_theme_constant_override("margin_bottom", 8)
	shell.add_child(shell_margin)

	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override("separation", ACTION_BAR_GAP)
	shell_margin.add_child(bar)

	for i: int in range(ACTION_BUTTONS.size()):
		if i == 3:
			var divider_wrap: CenterContainer = CenterContainer.new()
			divider_wrap.custom_minimum_size = Vector2(4.0, ACTION_BTN_SIZE)
			bar.add_child(divider_wrap)

			var divider: ColorRect = ColorRect.new()
			divider.custom_minimum_size = Vector2(1.0, ACTION_DIVIDER_H)
			divider.color = Color(0.56, 0.48, 0.28, 0.45)
			divider_wrap.add_child(divider)

		var data: Dictionary = ACTION_BUTTONS[i] as Dictionary
		var btn: PanelContainer = PanelContainer.new()
		btn.custom_minimum_size = Vector2(ACTION_BTN_SIZE, ACTION_BTN_SIZE)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.add_theme_stylebox_override("panel", _make_action_button_style(
			data.get("fill", Color(0.08, 0.09, 0.12, 1.0)),
			data.get("accent", TEXT_MAIN)))
		bar.add_child(btn)

		var btn_margin: MarginContainer = MarginContainer.new()
		btn_margin.add_theme_constant_override("margin_left", 4)
		btn_margin.add_theme_constant_override("margin_right", 4)
		btn_margin.add_theme_constant_override("margin_top", 4)
		btn_margin.add_theme_constant_override("margin_bottom", 4)
		btn.add_child(btn_margin)

		var content: VBoxContainer = VBoxContainer.new()
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_theme_constant_override("separation", 2)
		btn_margin.add_child(content)

		var icon_holder: CenterContainer = CenterContainer.new()
		icon_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_child(icon_holder)

		if bool(data.get("end_square", false)):
			var square: PanelContainer = PanelContainer.new()
			square.custom_minimum_size = Vector2(15.0, 15.0)
			square.add_theme_stylebox_override("panel", _make_end_square_style())
			icon_holder.add_child(square)
		else:
			var icon_parent: Control = icon_holder
			if bool(data.get("icon_frame", false)):
				var icon_frame: PanelContainer = PanelContainer.new()
				icon_frame.custom_minimum_size = Vector2(28.0, 28.0)
				icon_frame.add_theme_stylebox_override("panel", _make_action_icon_frame_style(
					data.get("accent", TEXT_MAIN)))
				icon_holder.add_child(icon_frame)
				var icon_frame_center: CenterContainer = CenterContainer.new()
				icon_frame.add_child(icon_frame_center)
				icon_parent = icon_frame_center

			var glyph: ActionGlyph = ActionGlyph.new()
			glyph.glyph_kind = str(data.get("kind", ""))
			glyph.accent_color = data.get("accent", TEXT_MAIN)
			glyph.custom_minimum_size = Vector2(30.0, 24.0)
			icon_parent.add_child(glyph)

		var name_lbl: Label = Label.new()
		name_lbl.text = str(data.get("label", ""))
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 8)
		name_lbl.add_theme_color_override("font_color", TEXT_MUTED)
		content.add_child(name_lbl)

		var kind: String = str(data.get("kind", ""))
		if kind == "skill" or kind == "item":
			var popup_kind: String = kind
			btn.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton:
					var mb: InputEventMouseButton = event as InputEventMouseButton
					if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
						_toggle_action_popup(popup_kind)
			)

	await shell.resized
	shell.position = Vector2(
		vp.x - shell.size.x - 14.0,
		vp.y - shell.size.y - 14.0)
	_build_action_popup()


func _build_action_popup() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.visible = false
	panel.size = Vector2(POPUP_W, POPUP_H)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _make_popup_panel_style())
	add_child(panel)
	_popup_panel = panel

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

	var hdr: HBoxContainer = HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 6)
	col.add_child(hdr)

	var hdr_circle: PanelContainer = PanelContainer.new()
	hdr_circle.custom_minimum_size = Vector2(26.0, 26.0)
	hdr_circle.add_theme_stylebox_override("panel", _make_popup_circle_style())
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
	_popup_title_label = hdr_title

	var hdr_sub: Label = Label.new()
	hdr_sub.text = "Channel your will"
	hdr_sub.add_theme_font_size_override("font_size", 8)
	hdr_sub.add_theme_color_override("font_color", TEXT_MUTED)
	hdr_txt.add_child(hdr_sub)
	_popup_sub_label = hdr_sub

	var sep: ColorRect = ColorRect.new()
	sep.custom_minimum_size = Vector2(0.0, 1.0)
	sep.color = POPUP_SEP
	col.add_child(sep)

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
	list.size_flags_stretch_ratio = 1.0
	list.add_theme_constant_override("separation", POPUP_CARD_GAP)
	scroll.add_child(list)
	_popup_list = list


func _toggle_action_popup(mode: String) -> void:
	if _popup_panel == null or _action_shell == null:
		return

	if _popup_panel.visible and _popup_mode == mode:
		_popup_panel.visible = false
		_popup_mode = ""
		return

	_popup_mode = mode
	_rebuild_action_popup(mode)
	var vp: Vector2 = get_viewport_rect().size
	var popup_x: float = clampf(
		_action_shell.position.x - 96.0,
		12.0,
		vp.x - _popup_panel.size.x - 12.0
	)
	_popup_panel.position = Vector2(
		popup_x,
		_action_shell.position.y - _popup_panel.size.y - 8.0)
	_popup_panel.visible = true


func _rebuild_action_popup(mode: String) -> void:
	if _popup_list == null or _popup_title_label == null or _popup_sub_label == null:
		return

	for child: Node in _popup_list.get_children():
		child.queue_free()

	var entries: Array = []
	if mode == "skill":
		_popup_title_label.text = "技能 刻印"
		_popup_sub_label.text = "Channel your will"
		entries = MOCK_SKILL_POPUP
	else:
		_popup_title_label.text = "道具 陈列"
		_popup_sub_label.text = "Arrange your tools"
		entries = MOCK_ITEM_POPUP

	for entry: Variant in entries:
		_build_action_popup_card(_popup_list, entry as Dictionary)


func _build_action_popup_card(parent: VBoxContainer, data: Dictionary) -> void:
	var accent: Color = data.get("accent", GOLD)

	var card: PanelContainer = PanelContainer.new()
	# Enforce consistent card width: popup width minus margins (10+10) minus scroll padding
	var card_width: float = POPUP_W - 20.0 - 4.0
	card.custom_minimum_size = Vector2(card_width, POPUP_CARD_H)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.add_theme_stylebox_override("panel", _make_popup_card_style(accent))
	parent.add_child(card)

	var cm: MarginContainer = MarginContainer.new()
	cm.add_theme_constant_override("margin_left", 8)
	cm.add_theme_constant_override("margin_right", 8)
	cm.add_theme_constant_override("margin_top", 5)
	cm.add_theme_constant_override("margin_bottom", 5)
	card.add_child(cm)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	cm.add_child(row)

	var ic_bg: PanelContainer = PanelContainer.new()
	ic_bg.custom_minimum_size = Vector2(32.0, 32.0)
	ic_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic_bg.add_theme_stylebox_override("panel", _make_popup_icon_square_style(accent))
	row.add_child(ic_bg)

	var ic_cc: CenterContainer = CenterContainer.new()
	ic_bg.add_child(ic_cc)

	var ic_lbl: Label = Label.new()
	ic_lbl.text = str(data.get("icon", "✦"))
	ic_lbl.add_theme_font_size_override("font_size", 12)
	ic_lbl.add_theme_color_override("font_color", TEXT_MAIN)
	ic_cc.add_child(ic_lbl)

	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 1)
	row.add_child(info)

	var title_lbl: Label = Label.new()
	title_lbl.text = str(data.get("title", ""))
	title_lbl.add_theme_font_size_override("font_size", 10)
	title_lbl.add_theme_color_override("font_color", TEXT_MAIN)
	info.add_child(title_lbl)

	var sub_lbl: Label = Label.new()
	sub_lbl.text = str(data.get("subtitle", ""))
	sub_lbl.add_theme_font_size_override("font_size", 8)
	sub_lbl.add_theme_color_override("font_color", TEXT_MUTED)
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.add_child(sub_lbl)

	var badge_lbl: Label = Label.new()
	badge_lbl.text = str(data.get("badge", ""))
	badge_lbl.add_theme_font_size_override("font_size", 7)
	badge_lbl.add_theme_color_override("font_color", accent)
	badge_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(badge_lbl)


# ═══════════════════════════════════════════════════════════════
#  StyleBox Factories
# ═══════════════════════════════════════════════════════════════

func _make_panel_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = PANEL_BG
	s.border_color = PANEL_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.shadow_color = Color(0.0, 0.0, 0.0, 0.30)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0.0, 3.0)
	return s


func _make_portrait_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = PORTRAIT_BG
	s.border_color = PORTRAIT_BORDER
	s.set_border_width_all(2)
	s.set_corner_radius_all(3)
	s.shadow_color = Color(0.72, 0.58, 0.28, 0.10)
	s.shadow_size = 6
	return s


func _make_relic_slot_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.04, 0.08, 1.0)
	s.border_color = Color(0.56, 0.48, 0.28, 0.45)
	s.set_border_width_all(1)
	s.set_corner_radius_all(int(RELIC_ICON_SIZE / 2.0))
	s.shadow_color = Color(0.0, 0.0, 0.0, 0.18)
	s.shadow_size = 3
	return s


func _make_action_button_style(fill_color: Color, accent_color: Color) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = fill_color
	s.border_color = accent_color * Color(1.0, 1.0, 1.0, 0.26)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.shadow_color = Color(0.0, 0.0, 0.0, 0.22)
	s.shadow_size = 5
	s.shadow_offset = Vector2(0.0, 2.0)
	return s


func _make_action_icon_frame_style(accent_color: Color) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	s.border_color = accent_color * Color(1.0, 1.0, 1.0, 0.42)
	s.set_border_width_all(1)
	s.set_corner_radius_all(5)
	s.shadow_color = accent_color * Color(1.0, 1.0, 1.0, 0.06)
	s.shadow_size = 2
	return s


func _make_popup_panel_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = POPUP_PANEL_BG
	s.border_color = POPUP_PANEL_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(5)
	s.shadow_color = POPUP_GLOW
	s.shadow_size = 12
	return s


func _make_popup_card_style(accent: Color) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = POPUP_CARD_BG
	s.border_color = accent * Color(1.0, 1.0, 1.0, 0.35)
	s.set_border_width_all(1)
	s.border_width_left = 3
	s.set_corner_radius_all(3)
	s.shadow_color = Color(0.0, 0.0, 0.0, 0.18)
	s.shadow_size = 2
	return s


func _make_popup_circle_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = POPUP_ICON_BG
	s.border_color = GOLD * Color(1.0, 1.0, 1.0, 0.35)
	s.set_border_width_all(1)
	s.set_corner_radius_all(13)
	return s


func _make_popup_icon_square_style(accent: Color) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = POPUP_ICON_BG
	s.border_color = accent * Color(1.0, 1.0, 1.0, 0.45)
	s.set_border_width_all(1)
	# Rounded square: ~25% of the 32px icon size for a visible rounded-square look
	s.set_corner_radius_all(8)
	s.shadow_color = accent * Color(1.0, 1.0, 1.0, 0.08)
	s.shadow_size = 2
	return s


func _make_end_square_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = Color(0.88, 0.16, 0.18, 1.0)
	s.border_color = Color(1.0, 0.72, 0.72, 0.35)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.shadow_color = Color(0.88, 0.16, 0.18, 0.16)
	s.shadow_size = 3
	return s
