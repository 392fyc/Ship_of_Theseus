extends Node2D
## Battle UI Playground — 3 Proposals (A / B / C)
## F6 运行此场景，横向对比 3 套 Battle UI 风格。
## 所有数据为 mock，不依赖 TacticalManager / DataLoader。

# ══════════════════════════════════════════════════════════════════
#  LAYOUT
# ══════════════════════════════════════════════════════════════════
const PANEL_W := 320
const PANEL_H := 480
const PANEL_GAP := 24
const MARGIN := 24
const INNER_PAD := 14
const CONTENT_W := 292            # PANEL_W - INNER_PAD * 2

const BG_COLOR := Color(0.10, 0.10, 0.12)
const PANEL_BG_A := Color(0.15, 0.15, 0.17)
const PANEL_BG_B := Color(0.14, 0.14, 0.18)
const PANEL_BG_C := Color(0.13, 0.14, 0.17)

# Y-offsets within each panel (relative to panel top)
const TITLE_Y := 22
const HP_SECTION_Y := 42
const HP_BAR_START_Y := 62
const HP_BAR_SPACING := 36
const POPUP_SECTION_Y := 176
const POPUP_AREA_Y := 196
const POPUP_AREA_H := 88
const TURN_SECTION_Y := 294
const TURN_START_Y := 314
const TURN_ENTRY_H := 24

# ══════════════════════════════════════════════════════════════════
#  DAMAGE TYPE COLORS
# ══════════════════════════════════════════════════════════════════
const DMG_PHYS   := Color.WHITE
const DMG_MAGIC  := Color(0.67, 0.53, 1.0)       # #AA88FF
const DMG_PURE   := Color(1.0, 0.84, 0.0)        # #FFD700
const DMG_HYBRID := Color(1.0, 0.55, 0.0)        # #FF8C00

const DMG_COLORS := {
	"phys": DMG_PHYS, "magic": DMG_MAGIC,
	"pure": DMG_PURE, "hybrid": DMG_HYBRID,
}

# Team colors for TurnOrderBar
const PLAYER_CLR := Color(0.27, 0.53, 0.87)      # blue
const ENEMY_CLR  := Color(0.87, 0.27, 0.27)      # red

# ══════════════════════════════════════════════════════════════════
#  MOCK DATA (static — no game system imports)
# ══════════════════════════════════════════════════════════════════
const HP_STATES: Array[Dictionary] = [
	{"label": "Full",     "current": 85, "max_hp": 100},
	{"label": "Low",      "current": 42, "max_hp": 100},
	{"label": "Critical", "current": 12, "max_hp": 100},
]

const MOCK_TURNS: Array[Dictionary] = [
	{"name": "Knight",   "init": 18, "is_player": true},
	{"name": "Archer",   "init": 16, "is_player": true},
	{"name": "Goblin A", "init": 15, "is_player": false},
	{"name": "Mage",     "init": 13, "is_player": true},
	{"name": "Goblin B", "init": 11, "is_player": false},
	{"name": "Orc Chief","init":  9, "is_player": false},
]

const POPUP_SEQ: Array[Dictionary] = [
	{"text": "-24", "type": "phys",   "crit": false},
	{"text": "-38", "type": "magic",  "crit": false},
	{"text": "-99", "type": "pure",   "crit": true},
	{"text": "-15", "type": "hybrid", "crit": false},
	{"text": "-56", "type": "phys",   "crit": true},
]

# ══════════════════════════════════════════════════════════════════
#  PROPOSAL A — Flat / Minimal
#  Thin bars, small clean text, no decorative frames.
# ══════════════════════════════════════════════════════════════════
const A_BAR_H := 5
const A_HP_FULL  := Color(0.30, 0.75, 0.30)      # calm green
const A_HP_LOW   := Color(0.75, 0.68, 0.20)      # muted yellow
const A_HP_CRIT  := Color(0.80, 0.22, 0.22)      # warning red
const A_BAR_BG   := Color(0.25, 0.25, 0.27)
const A_LABEL_SZ := 11
const A_POP_SZ   := 14
const A_POP_CRIT := 19

# ══════════════════════════════════════════════════════════════════
#  PROPOSAL B — Classic TRPG
#  Thicker bars, HP number overlay, portrait icon on TurnOrderBar.
# ══════════════════════════════════════════════════════════════════
const B_BAR_H := 12
const B_HP_FULL  := Color(0.24, 0.68, 0.24)
const B_HP_LOW   := Color(0.82, 0.55, 0.15)
const B_HP_CRIT  := Color(0.82, 0.18, 0.18)
const B_BAR_BG   := Color(0.15, 0.15, 0.18)
const B_BORDER   := Color(0.06, 0.06, 0.08)
const B_BORDER_W := 2.0
const B_LABEL_SZ := 13
const B_POP_SZ   := 18
const B_POP_CRIT := 24
const B_PORT_R   := 10.0                         # portrait circle radius

# ══════════════════════════════════════════════════════════════════
#  PROPOSAL C — Stylized
#  Gradient fills, glow, rounded frames, scale-punch popup.
# ══════════════════════════════════════════════════════════════════
const C_BAR_H := 16
const C_HP_FULL  := Color(0.35, 0.85, 0.35)
const C_HP_LOW   := Color(0.90, 0.73, 0.22)
const C_HP_CRIT  := Color(0.90, 0.22, 0.28)
const C_BAR_BG   := Color(0.20, 0.20, 0.24)
const C_FRAME    := Color(0.45, 0.45, 0.55)
const C_FRAME_W  := 2.0
const C_GLOW_SP  := 4.0                          # glow spread pixels
const C_GLOW_A   := 0.20                         # glow alpha
const C_LABEL_SZ := 13
const C_POP_SZ   := 20
const C_POP_CRIT := 28
const C_CARD_BG  := Color(0.20, 0.20, 0.26)
const C_CARD_BD  := Color(0.35, 0.35, 0.45)

# ── internal ──
var _font: Font
var _popup_idx: int = 0


func _ready() -> void:
	_font = ThemeDB.fallback_font

	var timer := Timer.new()
	timer.wait_time = 2.0
	timer.timeout.connect(_on_popup_tick)
	add_child(timer)
	timer.start()

	_on_popup_tick()


# ══════════════════════════════════════════════════════════════════
#  MAIN DRAW
# ══════════════════════════════════════════════════════════════════
func _draw() -> void:
	var tw := float(MARGIN * 2 + PANEL_W * 3 + PANEL_GAP * 2)
	var th := float(MARGIN * 2 + PANEL_H)
	draw_rect(Rect2(-16.0, -16.0, tw + 32.0, th + 32.0), BG_COLOR)

	for i in range(3):
		var px := float(MARGIN + i * (PANEL_W + PANEL_GAP))
		var py := float(MARGIN)
		var bg: Color = [PANEL_BG_A, PANEL_BG_B, PANEL_BG_C][i]
		draw_rect(Rect2(px, py, float(PANEL_W), float(PANEL_H)), bg)
		match i:
			0: _draw_a(px, py)
			1: _draw_b(px, py)
			2: _draw_c(px, py)


# ══════════════════════════════════════════════════════════════════
#  PROPOSAL A — Flat / Minimal
# ══════════════════════════════════════════════════════════════════
func _draw_a(px: float, py: float) -> void:
	var cx := px + float(INNER_PAD)

	_txt_s(Vector2(cx, py + float(TITLE_Y)), "Proposal A \u2014 Flat/Minimal", 16, Color.WHITE)
	_txt_s(Vector2(cx, py + float(HP_SECTION_Y)), "HP Bar", 11, Color(0.55, 0.55, 0.65))

	for i in range(HP_STATES.size()):
		var st: Dictionary = HP_STATES[i]
		var by := py + float(HP_BAR_START_Y + i * HP_BAR_SPACING)
		var ratio := float(st["current"]) / float(st["max_hp"])
		var col := _hp_col(ratio, A_HP_FULL, A_HP_LOW, A_HP_CRIT)

		_txt(Vector2(cx, by + 10.0),
			"%s  %d/%d" % [st["label"], st["current"], st["max_hp"]],
			A_LABEL_SZ, Color(0.70, 0.70, 0.70))
		var bar_y := by + 16.0
		draw_rect(Rect2(cx, bar_y, float(CONTENT_W), float(A_BAR_H)), A_BAR_BG)
		draw_rect(Rect2(cx, bar_y, float(CONTENT_W) * ratio, float(A_BAR_H)), col)

	_txt_s(Vector2(cx, py + float(POPUP_SECTION_Y)), "Damage Popup", 11, Color(0.55, 0.55, 0.65))
	_draw_popup_area(cx, py + float(POPUP_AREA_Y), Color(0.18, 0.18, 0.20), Color(0.28, 0.28, 0.30))

	_txt_s(Vector2(cx, py + float(TURN_SECTION_Y)), "Turn Order", 11, Color(0.55, 0.55, 0.65))
	_draw_turn_a(cx, py + float(TURN_START_Y))


func _draw_turn_a(cx: float, sy: float) -> void:
	for i in range(MOCK_TURNS.size()):
		var u: Dictionary = MOCK_TURNS[i]
		var ey := sy + float(i * TURN_ENTRY_H)
		var tc := PLAYER_CLR if (u["is_player"] as bool) else ENEMY_CLR
		draw_rect(Rect2(cx, ey + 4.0, 10.0, 10.0), tc)
		_txt(Vector2(cx + 16.0, ey + 14.0),
			"%d. %s  Init %d" % [i + 1, u["name"], u["init"]],
			A_LABEL_SZ, Color(0.78, 0.78, 0.78))


# ══════════════════════════════════════════════════════════════════
#  PROPOSAL B — Classic TRPG
# ══════════════════════════════════════════════════════════════════
func _draw_b(px: float, py: float) -> void:
	var cx := px + float(INNER_PAD)

	_txt_s(Vector2(cx, py + float(TITLE_Y)), "Proposal B \u2014 Classic TRPG", 16, Color.WHITE)
	_txt_s(Vector2(cx, py + float(HP_SECTION_Y)), "HP Bar", 11, Color(0.55, 0.55, 0.65))

	for i in range(HP_STATES.size()):
		var st: Dictionary = HP_STATES[i]
		var by := py + float(HP_BAR_START_Y + i * HP_BAR_SPACING)
		var ratio := float(st["current"]) / float(st["max_hp"])
		var col := _hp_col(ratio, B_HP_FULL, B_HP_LOW, B_HP_CRIT)

		_txt(Vector2(cx, by + 10.0), st["label"] as String, B_LABEL_SZ, Color(0.70, 0.70, 0.70))
		var bar_y := by + 16.0

		# border → bg → fill
		draw_rect(Rect2(cx - B_BORDER_W, bar_y - B_BORDER_W,
			float(CONTENT_W) + B_BORDER_W * 2.0, float(B_BAR_H) + B_BORDER_W * 2.0), B_BORDER)
		draw_rect(Rect2(cx, bar_y, float(CONTENT_W), float(B_BAR_H)), B_BAR_BG)
		draw_rect(Rect2(cx, bar_y, float(CONTENT_W) * ratio, float(B_BAR_H)), col)

		# HP overlay centered
		var hp_str := "%d / %d" % [st["current"], st["max_hp"]]
		var tsz := _font.get_string_size(hp_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		_txt_s(Vector2(cx + (float(CONTENT_W) - tsz) * 0.5,
			bar_y + float(B_BAR_H) * 0.5 + 4.0), hp_str, 11, Color.WHITE)

	_txt_s(Vector2(cx, py + float(POPUP_SECTION_Y)), "Damage Popup", 11, Color(0.55, 0.55, 0.65))
	_draw_popup_area(cx, py + float(POPUP_AREA_Y), Color(0.16, 0.16, 0.20), Color(0.08, 0.08, 0.10))

	_txt_s(Vector2(cx, py + float(TURN_SECTION_Y)), "Turn Order", 11, Color(0.55, 0.55, 0.65))
	_draw_turn_b(cx, py + float(TURN_START_Y))


func _draw_turn_b(cx: float, sy: float) -> void:
	for i in range(MOCK_TURNS.size()):
		var u: Dictionary = MOCK_TURNS[i]
		var ey := sy + float(i * TURN_ENTRY_H)
		var tc := PLAYER_CLR if (u["is_player"] as bool) else ENEMY_CLR

		var cc := Vector2(cx + B_PORT_R, ey + float(TURN_ENTRY_H) * 0.5)
		draw_circle(cc, B_PORT_R, tc)
		draw_arc(cc, B_PORT_R, 0.0, TAU, 24, Color(0.06, 0.06, 0.08), 1.5)

		_txt(Vector2(cx + B_PORT_R * 2.0 + 8.0, ey + 16.0),
			u["name"] as String, B_LABEL_SZ, Color.WHITE)

		var init_str := "Init %d" % u["init"]
		var iw := _font.get_string_size(init_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		_txt(Vector2(cx + float(CONTENT_W) - iw, ey + 16.0),
			init_str, 11, Color(0.55, 0.55, 0.60))


# ══════════════════════════════════════════════════════════════════
#  PROPOSAL C — Stylized
# ══════════════════════════════════════════════════════════════════
func _draw_c(px: float, py: float) -> void:
	var cx := px + float(INNER_PAD)

	_txt_s(Vector2(cx, py + float(TITLE_Y)), "Proposal C \u2014 Stylized", 16, Color.WHITE)
	# accent underline
	draw_rect(Rect2(cx, py + float(TITLE_Y) + 4.0, 170.0, 2.0), C_FRAME)
	_txt_s(Vector2(cx, py + float(HP_SECTION_Y)), "HP Bar", 11, Color(0.55, 0.55, 0.65))

	for i in range(HP_STATES.size()):
		var st: Dictionary = HP_STATES[i]
		var by := py + float(HP_BAR_START_Y + i * HP_BAR_SPACING)
		var ratio := float(st["current"]) / float(st["max_hp"])
		var col := _hp_col(ratio, C_HP_FULL, C_HP_LOW, C_HP_CRIT)

		_txt(Vector2(cx, by + 10.0), st["label"] as String, C_LABEL_SZ, Color(0.70, 0.70, 0.70))
		var bar_y := by + 16.0
		var fill_w := float(CONTENT_W) * ratio

		# glow
		var glow := Color(col.r, col.g, col.b, C_GLOW_A)
		draw_rect(Rect2(cx - C_GLOW_SP, bar_y - C_GLOW_SP,
			fill_w + C_GLOW_SP * 2.0, float(C_BAR_H) + C_GLOW_SP * 2.0), glow)
		# bg → fill → highlight top half → frame
		draw_rect(Rect2(cx, bar_y, float(CONTENT_W), float(C_BAR_H)), C_BAR_BG)
		draw_rect(Rect2(cx, bar_y, fill_w, float(C_BAR_H)), col)
		draw_rect(Rect2(cx, bar_y, fill_w, float(C_BAR_H) * 0.5),
			Color(1.0, 1.0, 1.0, 0.15))
		draw_rect(Rect2(cx, bar_y, float(CONTENT_W), float(C_BAR_H)), C_FRAME, false, C_FRAME_W)

		# HP right-aligned
		var hp_str := "%d / %d" % [st["current"], st["max_hp"]]
		var tw := _font.get_string_size(hp_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_txt_s(Vector2(cx + float(CONTENT_W) - tw,
			bar_y + float(C_BAR_H) * 0.5 + 4.0), hp_str, 12, Color.WHITE)

	_txt_s(Vector2(cx, py + float(POPUP_SECTION_Y)), "Damage Popup", 11, Color(0.55, 0.55, 0.65))
	_draw_popup_area(cx, py + float(POPUP_AREA_Y), Color(0.15, 0.15, 0.19), C_CARD_BD)

	_txt_s(Vector2(cx, py + float(TURN_SECTION_Y)), "Turn Order", 11, Color(0.55, 0.55, 0.65))
	_draw_turn_c(cx, py + float(TURN_START_Y))


func _draw_turn_c(cx: float, sy: float) -> void:
	for i in range(MOCK_TURNS.size()):
		var u: Dictionary = MOCK_TURNS[i]
		var ey := sy + float(i * TURN_ENTRY_H)
		var tc := PLAYER_CLR if (u["is_player"] as bool) else ENEMY_CLR

		# card bg + left accent strip + border
		draw_rect(Rect2(cx, ey, float(CONTENT_W), float(TURN_ENTRY_H) - 2.0), C_CARD_BG)
		draw_rect(Rect2(cx, ey, 4.0, float(TURN_ENTRY_H) - 2.0), tc)
		draw_rect(Rect2(cx, ey, float(CONTENT_W), float(TURN_ENTRY_H) - 2.0), C_CARD_BD, false, 1.0)

		_txt(Vector2(cx + 12.0, ey + 15.0), u["name"] as String, C_LABEL_SZ, Color.WHITE)

		# initiative badge
		var init_str := "%d" % u["init"]
		var iw := _font.get_string_size(init_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var bx := cx + float(CONTENT_W) - iw - 16.0
		draw_rect(Rect2(bx - 4.0, ey + 3.0, iw + 8.0, float(TURN_ENTRY_H) - 8.0),
			Color(0.25, 0.25, 0.35))
		_txt(Vector2(bx, ey + 15.0), init_str, 13, Color(0.90, 0.85, 0.50))


# ══════════════════════════════════════════════════════════════════
#  POPUP ANIMATION (auto-loop every 2 s)
# ══════════════════════════════════════════════════════════════════
func _on_popup_tick() -> void:
	var d: Dictionary = POPUP_SEQ[_popup_idx]
	_popup_idx = (_popup_idx + 1) % POPUP_SEQ.size()

	var dmg_text: String = d["text"] as String
	var dmg_type: String = d["type"] as String
	var is_crit: bool    = d["crit"] as bool
	var color: Color     = DMG_COLORS[dmg_type] as Color
	if is_crit:
		dmg_text += " CRIT!"

	for i in range(3):
		var px := float(MARGIN + i * (PANEL_W + PANEL_GAP)) + float(INNER_PAD)
		var center_x := px + float(CONTENT_W) * 0.5
		var base_y   := float(MARGIN) + float(POPUP_AREA_Y) + float(POPUP_AREA_H) - 24.0
		match i:
			0: _popup_a(center_x, base_y, dmg_text, color, is_crit)
			1: _popup_b(center_x, base_y, dmg_text, color, is_crit)
			2: _popup_c(center_x, base_y, dmg_text, color, is_crit)


func _popup_a(cx: float, by: float, text: String, color: Color, is_crit: bool) -> void:
	var lbl := _make_label(text, A_POP_CRIT if is_crit else A_POP_SZ, color, cx)
	lbl.position.y = by
	add_child(lbl)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", by - 55.0, 1.2) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.2) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.chain().tween_callback(lbl.queue_free)


func _popup_b(cx: float, by: float, text: String, color: Color, is_crit: bool) -> void:
	var sz: int = B_POP_CRIT if is_crit else B_POP_SZ

	# shadow
	var shd := _make_label(text, sz, Color(0.0, 0.0, 0.0, 0.70), cx)
	shd.position = Vector2(shd.position.x + 2.0, by + 2.0)
	add_child(shd)
	# main
	var lbl := _make_label(text, sz, color, cx)
	lbl.position.y = by
	add_child(lbl)

	for n: Label in [shd, lbl]:
		var off := 2.0 if n == shd else 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(n, "position:y", by - 60.0 + off, 1.4) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(n, "modulate:a", 0.0, 1.4) \
			.set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(n.queue_free)


func _popup_c(cx: float, by: float, text: String, color: Color, is_crit: bool) -> void:
	var sz: int = C_POP_CRIT if is_crit else C_POP_SZ
	var lbl := _make_label(text, sz, color, cx)
	lbl.position.y = by
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.90))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.pivot_offset = Vector2(lbl.size.x * 0.5, lbl.size.y * 0.5)
	lbl.scale = Vector2(1.5, 1.5) if is_crit else Vector2(1.2, 1.2)
	add_child(lbl)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(lbl, "scale", Vector2.ONE, 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(lbl, "position:y", by - 55.0, 1.5) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.5) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.chain().tween_callback(lbl.queue_free)


# ══════════════════════════════════════════════════════════════════
#  DRAWING HELPERS
# ══════════════════════════════════════════════════════════════════
func _hp_col(ratio: float, full: Color, low: Color, crit: Color) -> Color:
	if ratio > 0.6:
		return full
	if ratio > 0.3:
		return low
	return crit


func _draw_popup_area(cx: float, ay: float, bg: Color, bd: Color) -> void:
	draw_rect(Rect2(cx, ay, float(CONTENT_W), float(POPUP_AREA_H)), bg)
	draw_rect(Rect2(cx, ay, float(CONTENT_W), float(POPUP_AREA_H)), bd, false, 1.0)


func _make_label(text: String, font_size: int, color: Color, center_x: float) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size = Vector2(120.0, 40.0)
	lbl.position = Vector2(center_x - 60.0, 0.0)
	return lbl


func _txt_s(pos: Vector2, text: String, sz: int, col: Color) -> void:
	draw_string(_font, pos + Vector2(1.0, 1.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0.0, 0.0, 0.0, 0.55))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _txt(pos: Vector2, text: String, sz: int, col: Color) -> void:
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
