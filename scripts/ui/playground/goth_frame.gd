class_name GothFrame
extends Control
## 暗黑哥特区域框（Diablo IV 风格，四层叠绘 + 双色描边 + 四角角饰）。
## 全自绘 _draw（StyleBox 单色做不出「顶左受光亮 / 底右背光暗」双色描边）。
## 复用范式参照 bottom_dashboard.gd 内部类 HPShieldBar / XPBar。
##
## 用法：
##   var f := GothFrame.new()
##   f.variant = "normal"          # 或 "end"（红框危险变体）
##   f.custom_minimum_size = Vector2(216, 118)
##
## variant：
##   "normal" — 金属/石质双色描边（常规区）
##   "end"    — 红描边 + 红角饰（结束/危险区）

# ── 四层叠加结构调色板（对齐 spec.md §3.1 / mockup CSS 变量）──
const FRAME_OUTER: Color = Color(0.031, 0.039, 0.071, 1.0)       # #080a12 外缘最暗
const FRAME_INNER_TOP: Color = Color(0.078, 0.086, 0.129, 1.0)   # #141621 内壁渐变 上
const FRAME_INNER_MID: Color = Color(0.055, 0.063, 0.098, 1.0)   # #0e1019 内壁渐变 中
const FRAME_INNER_BOT: Color = Color(0.039, 0.047, 0.078, 1.0)   # #0a0c14 内壁渐变 下
const FRAME_NOISE: Color = Color(0.102, 0.114, 0.165, 1.0)       # #1a1d2a 噪点
const FRAME_NOISE_ALT: Color = Color(0.055, 0.063, 0.094, 1.0)   # #0e1018 噪点（暗档）

# 常规区双色描边
const EDGE_HI: Color = Color(0.612, 0.514, 0.278, 0.55)          # #9c8347(.55) 受光（顶+左）
const EDGE_LO: Color = Color(0.227, 0.188, 0.094, 0.9)           # #3a3018(.9) 背光（底+右）
const CORNER_TL: Color = Color(0.722, 0.580, 0.184, 0.7)         # #b8942f 左上（最亮）
const CORNER_TR_BL: Color = Color(0.478, 0.392, 0.157, 0.6)      # #7a6428 右上 / 左下
const CORNER_BR: Color = Color(0.290, 0.235, 0.094, 0.6)         # #4a3c18 右下（最暗）

# 结束区红变体
const END_OUTER: Color = Color(0.039, 0.024, 0.031, 1.0)         # #0a0608 外缘（偏红黑）
const END_INNER: Color = Color(0.071, 0.039, 0.047, 1.0)         # #120a0c 内壁
const END_EDGE_HI: Color = Color(0.878, 0.180, 0.180, 0.45)      # #e02e2e(.45) 红受光
const END_EDGE_LO: Color = Color(0.290, 0.078, 0.086, 0.9)       # #4a1416(.9) 红背光
const END_CORNER_HI: Color = Color(0.878, 0.180, 0.180, 0.6)     # #e02e2e 红角饰
const END_CORNER_LO: Color = Color(0.290, 0.078, 0.086, 0.7)     # #4a1416

const RADIUS: float = 4.0
const OUTER_INSET: float = 2.0   # 外缘比内壁大 ~2px → 内壁内缩 2px 制造凹陷
const CORNER_SIZE: float = 5.0   # 四角角饰 5×5
const NOISE_PERIOD: float = 6.0  # 噪点 6px 周期

var variant: String = "normal":
	set(value):
		variant = value
		queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var is_end: bool = variant == "end"

	# ① 外缘（最暗矩形，铺满整框，制造凹陷感）
	draw_rect(Rect2(0.0, 0.0, w, h), END_OUTER if is_end else FRAME_OUTER)

	# 内壁矩形（内缩 OUTER_INSET，露出外缘边形成嵌入感）
	var ix: float = OUTER_INSET
	var iy: float = OUTER_INSET
	var iw: float = w - OUTER_INSET * 2.0
	var ih: float = h - OUTER_INSET * 2.0
	if iw <= 0.0 or ih <= 0.0:
		return
	var inner: Rect2 = Rect2(ix, iy, iw, ih)

	# ② 内壁竖直渐变（上→中→下，模拟自上而下受光）
	_draw_vertical_gradient(inner, is_end)

	# ③ 噪点纹理（稀疏点阵，石质颗粒；像素风克制密度低）
	_draw_noise(inner)

	# ④ 双色描边（受光顶+左 / 背光底+右）
	_draw_dual_border(inner, is_end)

	# ⑤ 四角金属角饰（按受光方向递暗）
	_draw_corner_studs(inner, is_end)


## ② 内壁竖直渐变：用横向条带逐行插值 上→中→下 三段色。
func _draw_vertical_gradient(r: Rect2, is_end: bool) -> void:
	if is_end:
		# 结束区内壁单色（偏红黑），避免与红描边争视觉
		draw_rect(r, END_INNER)
		return
	var bands: int = 24
	var band_h: float = r.size.y / float(bands)
	for i: int in range(bands):
		var t: float = float(i) / float(maxi(bands - 1, 1))
		var col: Color
		if t < 0.5:
			col = FRAME_INNER_TOP.lerp(FRAME_INNER_MID, t * 2.0)
		else:
			col = FRAME_INNER_MID.lerp(FRAME_INNER_BOT, (t - 0.5) * 2.0)
		var y: float = r.position.y + float(i) * band_h
		# 末段补足像素避免接缝
		var bh: float = band_h + 1.0
		draw_rect(Rect2(r.position.x, y, r.size.x, bh), col)


## ③ 噪点：6px 周期内点 3 个稀疏像素点（透明度 .35–.5），密度低不糊。
func _draw_noise(r: Rect2) -> void:
	var cols: int = int(r.size.x / NOISE_PERIOD)
	var rows: int = int(r.size.y / NOISE_PERIOD)
	for cx: int in range(cols):
		for cy: int in range(rows):
			var ox: float = r.position.x + float(cx) * NOISE_PERIOD
			var oy: float = r.position.y + float(cy) * NOISE_PERIOD
			# 每周期固定 3 点（对齐 mockup pattern：(0,0).5 / (3,2).35 / (1,4)alt.4）
			draw_rect(Rect2(ox + 0.0, oy + 0.0, 1.0, 1.0), Color(FRAME_NOISE, 0.5))
			draw_rect(Rect2(ox + 3.0, oy + 2.0, 1.0, 1.0), Color(FRAME_NOISE, 0.35))
			draw_rect(Rect2(ox + 1.0, oy + 4.0, 1.0, 1.0), Color(FRAME_NOISE_ALT, 0.4))


## ④ 双色描边：受光边（顶 + 左）画亮金，背光边（底 + 右）画深褐金。
func _draw_dual_border(r: Rect2, is_end: bool) -> void:
	var hi: Color = END_EDGE_HI if is_end else EDGE_HI
	var lo: Color = END_EDGE_LO if is_end else EDGE_LO
	var x0: float = r.position.x
	var y0: float = r.position.y
	var x1: float = r.position.x + r.size.x
	var y1: float = r.position.y + r.size.y
	# 受光：顶边（含圆角偏移）+ 左边
	draw_line(Vector2(x0 + RADIUS, y0 + 0.5), Vector2(x1, y0 + 0.5), hi, 1.0)
	draw_line(Vector2(x0 + 0.5, y0 + RADIUS), Vector2(x0 + 0.5, y1), hi, 1.0)
	# 背光：底边 + 右边
	draw_line(Vector2(x0, y1 - 0.5), Vector2(x1 - RADIUS, y1 - 0.5), lo, 1.0)
	draw_line(Vector2(x1 - 0.5, y0 + RADIUS), Vector2(x1 - 0.5, y1), lo, 1.0)


## ⑤ 四角 5×5 角饰：左上最亮 → 右上/左下 → 右下最暗（按受光方向递暗）。
func _draw_corner_studs(r: Rect2, is_end: bool) -> void:
	var s: float = CORNER_SIZE
	var x0: float = r.position.x + 1.0
	var y0: float = r.position.y + 1.0
	var x1: float = r.position.x + r.size.x - 1.0 - s
	var y1: float = r.position.y + r.size.y - 1.0 - s
	if is_end:
		draw_rect(Rect2(x0, y0, s, s), END_CORNER_HI)
		draw_rect(Rect2(x1, y1, s, s), END_CORNER_LO)
	else:
		draw_rect(Rect2(x0, y0, s, s), CORNER_TL)        # 左上 最亮
		draw_rect(Rect2(x1, y0, s, s), CORNER_TR_BL)     # 右上
		draw_rect(Rect2(x0, y1, s, s), CORNER_TR_BL)     # 左下
		draw_rect(Rect2(x1, y1, s, s), CORNER_BR)        # 右下 最暗
