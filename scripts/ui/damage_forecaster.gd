class_name DamageForecaster
extends Control
## 伤害预测浮窗（v3）：暗黑哥特框 + 向下指向三角，浮于目标格上方。
## 提取自 scripts/ui/playground/skillbar_playground.gd 的内部类 DamageForecaster
## （内部类无法跨脚本复用 → 独立成 class_name 文件；playground 原型内部类保持不动）。
##
## 数据驱动：set_forecast(forecast) 读 forecast 字典（与 tactical_manager
##   _build_*_forecast_for_hover 出的字段同名）：
##   visible / target_name / hit_percent / crit_percent / damage /
##   hit_count / per_hit_damage / total_damage / damage_type / is_heal
##
## 类型徽标配色复用 DamagePopup.COLOR_*（与飘字颜色记忆一致：
##   物理白 / 魔法紫 / 纯金 / 混合橙 / 治疗绿）。
##
## 渲染对齐 spec.md §9.1：
##   - 单段（hit_count<=1）：「类型 · 数值」
##   - 多段（hit_count>1）：「类型 x × y（总值）」=hit_count×per_hit_damage（总=total_damage）
##   - 治疗（is_heal）：「治疗 · +N」无命中/暴击行
##   - 下方 命中%（灰）/ 暴击%（橙）；命中 0% 或不可用数值置灰

const PANEL_SIZE: Vector2 = Vector2(180.0, 78.0)
const TRIANGLE_H: float = 8.0

# ── 框色（对齐 spec.md §3 / mockup 预测器）──
const FRAME_OUTER: Color = Color(0.031, 0.039, 0.071, 1.0)
const FRAME_INNER: Color = Color(0.055, 0.063, 0.098, 1.0)
const EDGE_HI: Color = Color(0.612, 0.514, 0.278, 0.55)
const EDGE_LO: Color = Color(0.227, 0.188, 0.094, 0.9)
const C_GOLD: Color = Color(0.722, 0.580, 0.184, 1.0)
const C_GOLD_BRIGHT: Color = Color(0.878, 0.749, 0.282, 1.0)
const C_TEXT_SUB: Color = Color(0.549, 0.561, 0.600, 1.0)
const C_TEXT_DIM: Color = Color(0.361, 0.361, 0.400, 1.0)   # 置灰（不可用 / 命中0%）
const C_CRIT: Color = Color(0.980, 0.451, 0.059, 1.0)        # 暴击橙 #fa730f

# ── 当前 forecast 字段（由 set_forecast 填充）──
var _type_color: Color = DamagePopup.COLOR_PHYS
var _type_name: String = "物理"
var _hit_count: int = 1
var _per_hit: int = 24
var _total: int = 24
var _hit_percent: int = 92
var _crit_percent: int = 35
var _is_heal: bool = false
var _heal_amount: int = 16


func _ready() -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE


## 从 forecast 字典刷新展示内容。空字典 / visible=false 由调用方控可见性，
## 这里仅解析数值字段并 queue_redraw。
func set_forecast(forecast: Dictionary) -> void:
	var damage_type: String = str(forecast.get("damage_type", "physical"))
	_type_color = _color_for_type(damage_type)
	_type_name = _name_for_type(damage_type)
	_is_heal = bool(forecast.get("is_heal", false))
	_hit_count = maxi(int(forecast.get("hit_count", 1)), 1)
	_per_hit = int(forecast.get("per_hit_damage", forecast.get("damage", 0)))
	_total = int(forecast.get("total_damage", forecast.get("damage", _per_hit * _hit_count)))
	_hit_percent = int(forecast.get("hit_percent", 0))
	_crit_percent = int(forecast.get("crit_percent", 0))
	if _is_heal:
		_type_color = DamagePopup.COLOR_HEAL
		_type_name = "治疗"
		_heal_amount = int(forecast.get("damage", forecast.get("total_damage", 0)))
	queue_redraw()


## damage_type → 徽标配色（复用 DamagePopup 配色常量，与飘字一致）。
func _color_for_type(damage_type: String) -> Color:
	match damage_type:
		"physical": return DamagePopup.COLOR_PHYS
		"magical":  return DamagePopup.COLOR_MAGIC
		"pure":     return DamagePopup.COLOR_PURE
		"hybrid":   return DamagePopup.COLOR_HYBRID
		"holy":     return DamagePopup.COLOR_HEAL
	return DamagePopup.COLOR_PHYS


## 数值行文本（与 _draw 的分支拼装一致；渲染不可 headless 测，文本可测）。
##   治疗：「治疗 · +N」 / 单段：「类型 · 数值」 / 多段：「类型 x × y（总值）」。
func get_value_line_text() -> String:
	if _is_heal:
		return "%s · +%d" % [_type_name, _heal_amount]
	if _hit_count <= 1:
		return "%s · %d" % [_type_name, _per_hit]
	return "%s %d × %d (%d)" % [_type_name, _hit_count, _per_hit, _total]


func _name_for_type(damage_type: String) -> String:
	match damage_type:
		"physical": return "物理"
		"magical":  return "魔法"
		"pure":     return "纯粹"
		"hybrid":   return "混合"
		"holy":     return "神圣"
	return "物理"


func _draw() -> void:
	var w: float = PANEL_SIZE.x
	var h: float = PANEL_SIZE.y
	# 外缘 + 内壁
	draw_rect(Rect2(0.0, 0.0, w, h), FRAME_OUTER)
	draw_rect(Rect2(2.0, 2.0, w - 4.0, h - 4.0), FRAME_INNER)
	# 双色描边（受光 顶+左 / 背光 底+右）
	draw_line(Vector2(6.0, 2.5), Vector2(w, 2.5), EDGE_HI, 1.0)
	draw_line(Vector2(2.5, 6.0), Vector2(2.5, h), EDGE_HI, 1.0)
	draw_line(Vector2(0.0, h - 2.5), Vector2(w - 6.0, h - 2.5), EDGE_LO, 1.0)
	draw_line(Vector2(w - 2.5, 6.0), Vector2(w - 2.5, h), EDGE_LO, 1.0)
	# 向下指向三角（底边中点，对准目标）
	var tx: float = w * 0.5
	var tri: PackedVector2Array = PackedVector2Array([
		Vector2(tx - 6.0, h - 1.0),
		Vector2(tx + 6.0, h - 1.0),
		Vector2(tx, h - 1.0 + TRIANGLE_H),
	])
	draw_colored_polygon(tri, FRAME_INNER)
	draw_line(tri[0], tri[2], EDGE_LO, 1.0)
	draw_line(tri[1], tri[2], EDGE_LO, 1.0)

	var fnt: Font = ThemeDB.fallback_font
	# 标题
	var title: String = "效果预测" if _is_heal else "伤害预测"
	draw_string(fnt, Vector2(12.0, 20.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_GOLD)
	# 类型徽标（小圆点）
	draw_circle(Vector2(20.0, 36.0), 5.0, _type_color)
	if _type_color == DamagePopup.COLOR_PHYS:
		# 物理白点描灰圈，避免与暗底糊在一起
		draw_arc(Vector2(20.0, 36.0), 5.0, 0.0, TAU, 16, Color(0.5, 0.5, 0.5, 1.0), 1.0, true)

	# 数值行
	if _is_heal:
		draw_string(fnt, Vector2(32.0, 40.0), "%s · +%d" % [_type_name, _heal_amount], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _type_color)
		# 治疗无命中/暴击行
		draw_string(fnt, Vector2(12.0, 62.0), "必定生效", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_TEXT_SUB)
		return

	# 命中 0% 或总伤为 0（不可用）→ 数值置灰
	var unavailable: bool = _hit_percent <= 0 or (_per_hit <= 0 and _total <= 0)
	var value_col: Color = C_TEXT_DIM if unavailable else _type_color

	if _hit_count <= 1:
		# 单段：直接显「类型 · 数值」
		draw_string(fnt, Vector2(32.0, 40.0), "%s · %d" % [_type_name, _per_hit], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, value_col)
	else:
		# 多段：类型 x × y（总值）— x/y 类型色、× 灰、总值金
		var sep_col: Color = C_TEXT_DIM if unavailable else C_TEXT_SUB
		var total_col: Color = C_TEXT_DIM if unavailable else C_GOLD_BRIGHT
		var x_pos: float = 32.0
		x_pos = _draw_run(fnt, x_pos, 40.0, _type_name + " ", 13, value_col)
		x_pos = _draw_run(fnt, x_pos, 40.0, str(_hit_count), 13, value_col)
		x_pos = _draw_run(fnt, x_pos + 3.0, 40.0, "×", 12, sep_col)
		x_pos = _draw_run(fnt, x_pos + 3.0, 40.0, str(_per_hit), 13, value_col)
		x_pos = _draw_run(fnt, x_pos + 4.0, 40.0, "(%d)" % _total, 12, total_col)

	# 命中 / 暴击行（命中灰 / 暴击橙；不可用整体偏暗）
	var hit_col: Color = C_TEXT_DIM if unavailable else C_TEXT_SUB
	var crit_col: Color = C_TEXT_DIM if unavailable else C_CRIT
	draw_string(fnt, Vector2(12.0, 62.0), "命中 %d%%" % _hit_percent, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, hit_col)
	draw_string(fnt, Vector2(96.0, 62.0), "暴击 %d%%" % _crit_percent, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, crit_col)


## 画一段文本并返回下一段起始 x（用于多段拼色）。
func _draw_run(fnt: Font, x: float, y: float, text: String, fs: int, col: Color) -> float:
	draw_string(fnt, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	return x + fnt.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
