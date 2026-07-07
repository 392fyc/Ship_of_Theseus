class_name SwordQiBar
extends Control
## 剑气分段条（v3，10 格；剑气 0-100 标度，按 sword_qi_max 比例填格）：空格始终可见细边 + 颜色突变 + 阈值线。
## 全自绘 _draw，参照 bottom_dashboard.gd 内部类 HPShieldBar / XPBar。
##
## 规则（对齐 spec.md §8.1 / mockup §四）：
##   - 10 格，每格内宽 15.2px、步进 18.2px，条宽 182px、高 16px。
##   - 空格始终画：底 #0a1019 + 1px 细边（未达标 #314257 / 达标 #5b3f7a）。
##   - 填充整条切色：未达阈值 淡蓝 #5fa8d8（槽底 #0c1320）；达阈值 紫 #a855f7（当前最高格亮紫 #c98bff，槽底 #100a1c，槽缘紫）。
##   - 阈值线固定第 7 格右缘 x≈126.4：未达标 灰虚线 + 「阈值7」；达标 金实线 1.4px + 上指箭头 + 「速度+1」。
##
## 用法：
##   var bar := SwordQiBar.new()
##   bar.sword_qi = 7
##   bar.sword_qi_max = 100
##   bar.threshold = 70

const BAR_W: float = 182.0
const BAR_H: float = 16.0
const CELLS: int = 10
const CELL_INNER_W: float = 15.2
const CELL_STEP: float = 18.2
const CELL_PAD: float = 2.0      # 条内壁到首格左缘
const CELL_INNER_H: float = 12.0
const THRESHOLD_X: float = 126.4 # 第 7 格右缘

# ── 调色板（对齐 spec.md §4 新增剑气色）──
const QI_LOW: Color = Color(0.373, 0.659, 0.847, 1.0)        # #5fa8d8 <7 淡蓝
const QI_HIGH: Color = Color(0.659, 0.333, 0.969, 1.0)       # #a855f7 ≥7 紫
const QI_HIGH_GLOW: Color = Color(0.788, 0.545, 1.0, 1.0)    # #c98bff 当前最高/满 亮紫
const TRACK_LOW: Color = Color(0.047, 0.075, 0.125, 1.0)     # #0c1320 槽底（未达标）
const TRACK_HIGH: Color = Color(0.063, 0.039, 0.110, 1.0)    # #100a1c 槽底（达标）
const TRACK_EDGE_HIGH: Color = Color(0.659, 0.333, 0.969, 0.55)  # 槽缘紫(.55)
const CELL_EMPTY_BG: Color = Color(0.039, 0.063, 0.098, 1.0) # #0a1019 空格底
const CELL_EDGE_LOW: Color = Color(0.192, 0.259, 0.341, 1.0) # #314257 空格边（未达标）
const CELL_EDGE_HIGH: Color = Color(0.357, 0.247, 0.478, 1.0)# #5b3f7a 空格边（达标·偏紫）

const THRESH_DASH: Color = Color(0.275, 0.278, 0.302, 1.0)   # #46474d 灰虚线（未达标）
const THRESH_GOLD: Color = Color(0.878, 0.749, 0.282, 1.0)   # #e0bf48 金实线（达标）

var sword_qi: int = 0:
	set(value):
		sword_qi = value
		queue_redraw()
var sword_qi_max: int = 100:
	set(value):
		sword_qi_max = maxi(value, 1)
		queue_redraw()
var threshold: int = 70:
	set(value):
		threshold = value
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(BAR_W, BAR_H + 14.0)  # 留出阈值线箭头 + 标注空间


func _draw() -> void:
	var reached: bool = sword_qi >= threshold
	# 条顶留 8px（给上指箭头），条画在 y_top
	var y_top: float = 8.0
	var bar_rect: Rect2 = Rect2(0.0, y_top, BAR_W, BAR_H)

	# 槽底 + 槽缘（达标态切暗紫底 + 紫缘）
	if reached:
		draw_rect(bar_rect, TRACK_HIGH)
		draw_rect(bar_rect, TRACK_EDGE_HIGH, false, 1.0)
	else:
		draw_rect(bar_rect, TRACK_LOW)
		draw_rect(bar_rect, Color(CELL_EDGE_LOW, 0.7), false, 1.0)

	# floori（非 roundi）：每 sword_qi_max/CELLS 点满 1 格，与心眼 floor(剑气/10) 语义一致；
	# 避免 [65,69] 舍入填满 7 格却未达 70 阈值线的观感错位（格满才算达标）。
	var filled: int = clampi(floori(float(sword_qi) / float(sword_qi_max) * float(CELLS)), 0, CELLS)
	var fill_col: Color = QI_HIGH if reached else QI_LOW
	var empty_edge: Color = CELL_EDGE_HIGH if reached else CELL_EDGE_LOW

	for i: int in range(CELLS):
		var cx: float = CELL_PAD + float(i) * CELL_STEP
		var cell: Rect2 = Rect2(cx, y_top + 2.0, CELL_INNER_W, CELL_INNER_H)
		if i < filled:
			# 填充格：达标态当前最高格（i == filled-1）或满槽用亮紫
			var col: Color = fill_col
			if reached and (i == filled - 1 or filled >= CELLS):
				col = QI_HIGH_GLOW
			draw_rect(cell, col)
		else:
			# 空格：始终画底 + 1px 可见细边
			draw_rect(cell, CELL_EMPTY_BG)
			draw_rect(cell, empty_edge, false, 1.0)

	_draw_threshold_line(reached, y_top)


## 阈值线（固定第 7 格右缘 x≈126.4，与当前值无关）。
func _draw_threshold_line(reached: bool, y_top: float) -> void:
	var x: float = THRESHOLD_X
	var top_y: float = y_top - 6.0
	var bot_y: float = y_top + BAR_H + 4.0
	if reached:
		# 达标：金实线 1.4px + 上指箭头三角
		draw_line(Vector2(x, top_y), Vector2(x, y_top + BAR_H), THRESH_GOLD, 1.4)
		var arrow: PackedVector2Array = PackedVector2Array([
			Vector2(x, top_y - 1.0),
			Vector2(x - 4.0, top_y + 4.0),
			Vector2(x + 4.0, top_y + 4.0),
		])
		draw_colored_polygon(arrow, THRESH_GOLD)
	else:
		# 未达标：灰虚线（手绘短段模拟 dash）
		var seg: float = 2.0
		var yy: float = top_y
		while yy < y_top + BAR_H:
			draw_line(Vector2(x, yy), Vector2(x, minf(yy + seg, y_top + BAR_H)), THRESH_DASH, 1.0)
			yy += seg * 2.0
