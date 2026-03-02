extends Node2D
## Terrain & Highlight Color Scheme Playground
## F6 运行此场景可直接看到 3 套配色方案（A / B / C）横向排列。
## 选定后记录方案名，将色值常量迁移到正式渲染系统。

# ── Cell size（与 cell.gd 保持一致）──
const CELL_SIZE := 64

# ── Terrain indices（镜像 Cell.Terrain enum，见 scripts/core/cell.gd）──
const T_PLAIN := 0
const T_FOREST := 1
const T_MOUNTAIN := 2
const T_PEAK := 3
const T_WALL := 4
const T_SHALLOW_WATER := 5
const T_DEEP_WATER := 6
const T_LAVA := 7
const T_SWAMP := 8

const TERRAIN_ORDER := [
	T_PLAIN, T_FOREST, T_MOUNTAIN,
	T_PEAK, T_WALL, T_SHALLOW_WATER,
	T_DEEP_WATER, T_LAVA, T_SWAMP,
]

const TERRAIN_LABELS := {
	T_PLAIN: "Plain",
	T_FOREST: "Forest",
	T_MOUNTAIN: "Mountain",
	T_PEAK: "Peak",
	T_WALL: "Wall",
	T_SHALLOW_WATER: "Shallow",
	T_DEEP_WATER: "Deep Water",
	T_LAVA: "Lava",
	T_SWAMP: "Swamp",
}

# ══════════════════════════════════════════════════════════════════
#  方案A — 深色低饱和 (Dark / Low Saturation)
#  整体偏暗、低饱和，战术沉稳风格
# ══════════════════════════════════════════════════════════════════
const SCHEME_A_TERRAIN := {
	T_PLAIN:         Color(0.24, 0.36, 0.24),   # #3D5C3D 暗草绿
	T_FOREST:        Color(0.16, 0.29, 0.16),   # #2A4A2A 深林绿
	T_MOUNTAIN:      Color(0.35, 0.29, 0.23),   # #5A4A3A 暗棕
	T_PEAK:          Color(0.42, 0.42, 0.44),   # #6A6A70 冷灰
	T_WALL:          Color(0.29, 0.29, 0.33),   # #4A4A55 板岩灰
	T_SHALLOW_WATER: Color(0.23, 0.35, 0.42),   # #3A5A6A 暗青
	T_DEEP_WATER:    Color(0.10, 0.16, 0.29),   # #1A2A4A 深海蓝
	T_LAVA:          Color(0.35, 0.16, 0.10),   # #5A2A1A 暗烬红
	T_SWAMP:         Color(0.23, 0.23, 0.13),   # #3A3A20 暗橄榄
}
const SCHEME_A_MOVE   := Color(0.16, 0.31, 0.71, 0.40)   # 沉稳蓝
const SCHEME_A_ATTACK := Color(0.71, 0.16, 0.16, 0.40)   # 暗红
const SCHEME_A_HOVER  := Color(0.71, 0.67, 0.16, 0.40)   # 暗金

# ══════════════════════════════════════════════════════════════════
#  方案B — GBA FE 经典明亮 (Classic Bright)
#  模拟 GBA 火焰纹章经典地图配色，鲜明易读
# ══════════════════════════════════════════════════════════════════
const SCHEME_B_TERRAIN := {
	T_PLAIN:         Color(0.44, 0.78, 0.28),   # #70C848 明草绿
	T_FOREST:        Color(0.22, 0.53, 0.29),   # #38884A 常绿
	T_MOUNTAIN:      Color(0.78, 0.66, 0.41),   # #C8A868 沙棕
	T_PEAK:          Color(0.69, 0.69, 0.72),   # #B0B0B8 亮石
	T_WALL:          Color(0.53, 0.53, 0.60),   # #888898 石灰
	T_SHALLOW_WATER: Color(0.35, 0.69, 0.85),   # #58B0D8 亮水蓝
	T_DEEP_WATER:    Color(0.19, 0.38, 0.63),   # #3060A0 海蓝
	T_LAVA:          Color(0.88, 0.41, 0.19),   # #E06830 亮橙红
	T_SWAMP:         Color(0.41, 0.47, 0.22),   # #687838 泥绿
}
const SCHEME_B_MOVE   := Color(0.24, 0.47, 1.00, 0.35)   # 天蓝
const SCHEME_B_ATTACK := Color(1.00, 0.24, 0.24, 0.35)   # 亮红
const SCHEME_B_HOVER  := Color(1.00, 0.94, 0.24, 0.35)   # 亮黄

# ══════════════════════════════════════════════════════════════════
#  方案C — 高对比度 / 色盲友好 (High Contrast / Colorblind-friendly)
#  蓝-橙轴为主，品红替代纯红，避免红绿混淆
# ══════════════════════════════════════════════════════════════════
const SCHEME_C_TERRAIN := {
	T_PLAIN:         Color(0.72, 0.85, 0.19),   # #B8D830 黄绿
	T_FOREST:        Color(0.00, 0.53, 0.50),   # #008880 青绿
	T_MOUNTAIN:      Color(0.85, 0.56, 0.19),   # #D89030 暖橙
	T_PEAK:          Color(0.88, 0.88, 0.88),   # #E0E0E0 近白
	T_WALL:          Color(0.31, 0.31, 0.35),   # #505058 暗灰
	T_SHALLOW_WATER: Color(0.25, 0.75, 0.88),   # #40C0E0 亮青
	T_DEEP_WATER:    Color(0.13, 0.31, 0.63),   # #2050A0 强蓝
	T_LAVA:          Color(0.82, 0.19, 0.50),   # #D03080 品红
	T_SWAMP:         Color(0.50, 0.41, 0.28),   # #806848 暖棕
}
const SCHEME_C_MOVE   := Color(0.00, 0.71, 1.00, 0.45)   # 明青
const SCHEME_C_ATTACK := Color(1.00, 0.00, 0.63, 0.45)   # 品红
const SCHEME_C_HOVER  := Color(1.00, 1.00, 0.00, 0.45)   # 纯黄

# ── Layout constants ──
const BLOCK := 2                               # 每种地形占 2×2 格
const SCHEME_GAP := 64                         # 方案间距（px）
const SCHEME_W := 6 * CELL_SIZE                # 单方案宽 384px
const TITLE_H := 36                            # 标题区高度
const HL_GAP := 16                             # 地形网格→高亮区间距
const HL_SUBTITLE_H := 24                      # 高亮小标题高度
const BG_COLOR := Color(0.11, 0.11, 0.13)      # 深色背景

const HIGHLIGHT_NAMES := ["移动范围", "攻击范围", "悬停"]
const HIGHLIGHT_BG := [T_PLAIN, T_FOREST, T_MOUNTAIN]

var _schemes: Array[Dictionary] = []


func _ready() -> void:
	_schemes = [
		{
			"name": "方案A — 深色低饱和",
			"terrain": SCHEME_A_TERRAIN,
			"highlights": [SCHEME_A_MOVE, SCHEME_A_ATTACK, SCHEME_A_HOVER],
		},
		{
			"name": "方案B — GBA经典明亮",
			"terrain": SCHEME_B_TERRAIN,
			"highlights": [SCHEME_B_MOVE, SCHEME_B_ATTACK, SCHEME_B_HOVER],
		},
		{
			"name": "方案C — 高对比度",
			"terrain": SCHEME_C_TERRAIN,
			"highlights": [SCHEME_C_MOVE, SCHEME_C_ATTACK, SCHEME_C_HOVER],
		},
	]


func _draw() -> void:
	draw_rect(Rect2(-20.0, -20.0, 1320.0, 760.0), BG_COLOR)

	var font: Font = ThemeDB.fallback_font

	for i in range(_schemes.size()):
		var ox: float = float(i) * float(SCHEME_W + SCHEME_GAP)
		_draw_scheme(ox, 16.0, _schemes[i], font)


func _draw_scheme(ox: float, oy: float, scheme: Dictionary, font: Font) -> void:
	# ── 方案标题 ──
	_draw_text(font, Vector2(ox, oy + 20.0), scheme["name"] as String, 20, Color.WHITE)

	var grid_y: float = oy + float(TITLE_H)
	var terrain_colors: Dictionary = scheme["terrain"] as Dictionary

	# ── 地形网格 3×3 blocks of 2×2 cells = 6×6 grid ──
	for idx in range(TERRAIN_ORDER.size()):
		var bcol: int = idx % 3
		var brow: int = idx / 3
		var bx: float = ox + float(bcol * BLOCK * CELL_SIZE)
		var by: float = grid_y + float(brow * BLOCK * CELL_SIZE)
		var t_key: int = TERRAIN_ORDER[idx] as int
		var t_color: Color = terrain_colors[t_key] as Color

		_draw_cell_block(bx, by, t_color, Color(0.0, 0.0, 0.0, 0.0))
		_draw_block_label(font, bx, by, TERRAIN_LABELS[t_key] as String)

	# ── 高亮叠加演示 ──
	var hl_y: float = grid_y + 6.0 * float(CELL_SIZE) + float(HL_GAP)
	_draw_text(font, Vector2(ox, hl_y + 12.0), "▼ 高亮叠加演示", 13, Color(0.65, 0.65, 0.75))

	hl_y += float(HL_SUBTITLE_H)
	var hl_colors: Array = scheme["highlights"] as Array

	for hi in range(3):
		var hx: float = ox + float(hi * BLOCK * CELL_SIZE)
		var bg_key: int = HIGHLIGHT_BG[hi] as int
		var base_color: Color = terrain_colors[bg_key] as Color
		var hl_color: Color = hl_colors[hi] as Color

		_draw_cell_block(hx, hl_y, base_color, hl_color)
		_draw_block_label(font, hx, hl_y, HIGHLIGHT_NAMES[hi] as String)


func _draw_cell_block(bx: float, by: float, base: Color, overlay: Color) -> void:
	for dy in range(BLOCK):
		for dx in range(BLOCK):
			var rect := Rect2(
				bx + float(dx * CELL_SIZE),
				by + float(dy * CELL_SIZE),
				float(CELL_SIZE), float(CELL_SIZE)
			)
			draw_rect(rect, base)
			if overlay.a > 0.0:
				draw_rect(rect, overlay)
			draw_rect(rect, Color(0.0, 0.0, 0.0, 0.18), false, 1.0)


func _draw_block_label(font: Font, bx: float, by: float, text: String) -> void:
	var sz: int = 13
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var lx: float = bx + (float(BLOCK * CELL_SIZE) - tw) * 0.5
	var ly: float = by + float(BLOCK * CELL_SIZE) * 0.5 + float(sz) * 0.35
	_draw_text(font, Vector2(lx, ly), text, sz, Color(1.0, 1.0, 1.0, 0.92))


func _draw_text(font: Font, pos: Vector2, text: String, size: int, color: Color) -> void:
	draw_string(font, pos + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.0, 0.0, 0.0, 0.6))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
