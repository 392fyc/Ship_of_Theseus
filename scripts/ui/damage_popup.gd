class_name DamagePopup
extends RefCounted
## Proposal B+ — FF14 风格伤害飘字。
## 类型前缀 = 自绘矢量形状（剑/菱/星/十字，占位字形，真图标交 Mercury 美术），
## 数字相对小，先在头顶停留可读片刻再升起淡出；多段同目标命中向右上叠加。
## 形状无字体依赖（_draw 自绘），不会出现豆腐方框。
##
## 用法：
##   DamagePopup.spawn(popup_layer, world_pos, 100, "physical", false)
##   DamagePopup.spawn(layer, pos, 80, "magical", true, 1)  # segment_index=1 → 向右上叠
##   DamagePopup.spawn_miss(layer, pos)
##   DamagePopup.spawn_heal(layer, pos, 40)

# ── 伤害类型配色（对齐 ADR-004 四类型）──
const COLOR_PHYS   := Color.WHITE
const COLOR_MAGIC  := Color(0.67, 0.53, 1.0)       # #AA88FF
const COLOR_PURE   := Color(1.0, 0.84, 0.0)        # #FFD700
const COLOR_HYBRID := Color(1.0, 0.55, 0.0)        # #FF8C00
const COLOR_MISS   := Color(0.60, 0.60, 0.60)
const COLOR_HEAL   := Color(0.30, 0.90, 0.30)

# ── 字号（数字保持小；暴击仅 +3 略大，非跳变）──
const NORMAL_SIZE := 16
const CRIT_SIZE   := 19    # 普通 16 + 3（用户拍板）
const MISS_SIZE   := 14

# ── 自绘字形 ──
const GLYPH_SIZE   := 12.0   # 形状外接正方形边长
const GLYPH_GAP    := 4.0    # 形状与数字间距

# ── 多段叠加（同一目标连续命中）──
const SEGMENT_DX   := 14.0   # 每后一段向右
const SEGMENT_DY   := 20.0   # ……并向上

# ── 动画 ──
const RISE_DIST := 46.0
const HOLD_TIME := 0.5       # 头顶停留可读
const RISE_TIME := 0.9       # 升起 + 淡出


# ── 纯函数 helper（headless 可断言）：组装 文本/形状/颜色/字号 ──
# 返回 {text, shape, color, size}；shape ∈ {sword, diamond, star, hybrid, heal, none}。
static func compose(amount: int, damage_type: String, is_crit: bool) -> Dictionary:
	var sz: int = CRIT_SIZE if is_crit else NORMAL_SIZE
	var txt := "%d" % amount         # FF14 式：伤害不带负号，类型由形状+颜色传达
	if is_crit:
		txt += "！"                   # 暴击后缀（替换旧 CRIT!）
	return {
		"text": txt,
		"shape": _type_shape(damage_type),
		"color": _type_color(damage_type),
		"size": sz,
	}


static func spawn(parent: Node, world_pos: Vector2,
		amount: int, damage_type: String, is_crit: bool,
		segment_index: int = 0) -> void:
	var parts := compose(amount, damage_type, is_crit)
	_create(parent, world_pos, parts.text, parts.shape, parts.color, parts.size, segment_index)


static func spawn_miss(parent: Node, world_pos: Vector2,
		segment_index: int = 0) -> void:
	_create(parent, world_pos, "MISS", "none", COLOR_MISS, MISS_SIZE, segment_index)


static func spawn_heal(parent: Node, world_pos: Vector2, amount: int,
		segment_index: int = 0) -> void:
	_create(parent, world_pos, "+%d" % amount, "heal", COLOR_HEAL, NORMAL_SIZE, segment_index)


static func _create(parent: Node, world_pos: Vector2,
		text: String, shape: String, color: Color, font_size: int,
		segment_index: int) -> void:
	var has_glyph := shape != "none"
	# 估算宽度，让 [字形 间距 数字] 整组横向居中于单位头顶。
	var num_w := float(text.length()) * float(font_size) * 0.62
	var glyph_w := (GLYPH_SIZE + GLYPH_GAP) if has_glyph else 0.0
	var total_w := glyph_w + num_w
	var seg := Vector2(SEGMENT_DX, -SEGMENT_DY) * float(segment_index)
	var origin := Vector2(world_pos.x - total_w * 0.5, world_pos.y - 50.0) + seg

	var nodes: Array[Control] = []

	if has_glyph:
		var glyph := _Glyph.new()
		glyph.shape = shape
		glyph.color = color
		glyph.custom_minimum_size = Vector2(GLYPH_SIZE, GLYPH_SIZE)
		glyph.size = Vector2(GLYPH_SIZE, GLYPH_SIZE)
		glyph.position = origin + Vector2(0.0, float(font_size) * 0.5 - GLYPH_SIZE * 0.5)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(glyph)
		nodes.append(glyph)

	var text_x := origin.x + glyph_w

	var shadow := _make_label(text, font_size, Color(0.0, 0.0, 0.0, 0.70),
		Vector2(text_x + 2.0, origin.y + 2.0))
	parent.add_child(shadow)
	nodes.append(shadow)

	var label := _make_label(text, font_size, color, Vector2(text_x, origin.y))
	parent.add_child(label)
	nodes.append(label)

	for node in nodes:
		_animate(parent, node)


static func _animate(parent: Node, node: Control) -> void:
	var start_y: float = node.position.y
	var tw := parent.create_tween()
	tw.tween_interval(HOLD_TIME)                                    # 先停留
	tw.tween_property(node, "position:y", start_y - RISE_DIST, RISE_TIME) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)     # 再升起
	tw.parallel().tween_property(node, "modulate:a", 0.0, RISE_TIME) \
		.set_ease(Tween.EASE_IN)                                   # 同步淡出
	tw.chain().tween_callback(node.queue_free)


static func _make_label(text: String, font_size: int,
		color: Color, pos: Vector2) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.size = Vector2(float(text.length()) * float(font_size) + 24.0, float(font_size) + 10.0)
	lbl.position = pos
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


static func _type_color(damage_type: String) -> Color:
	match damage_type:
		"physical": return COLOR_PHYS
		"magical":  return COLOR_MAGIC
		"pure":     return COLOR_PURE
		"hybrid":   return COLOR_HYBRID
		"heal":     return COLOR_HEAL
	return COLOR_PHYS


static func _type_shape(damage_type: String) -> String:
	match damage_type:
		"physical":     return "sword"
		"magical":      return "diamond"
		"pure":         return "star"
		"hybrid":       return "hybrid"
		"heal":         return "heal"
		"miss", "none": return "none"
	return "sword"


# ── 自绘字形节点（占位矢量形状，无字体依赖）──
class _Glyph extends Control:
	var shape: String = "sword"
	var color: Color = Color.WHITE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		match shape:
			"sword":
				# 斜向刀身 + 短护手
				draw_line(Vector2(w * 0.15, h * 0.85), Vector2(w * 0.85, h * 0.15), color, 2.0, true)
				draw_line(Vector2(w * 0.18, h * 0.50), Vector2(w * 0.50, h * 0.82), color, 2.0, true)
			"diamond":
				draw_colored_polygon(_diamond(w, h), color)
			"star":
				draw_colored_polygon(_star(Vector2(w * 0.5, h * 0.5), w * 0.48, w * 0.20), color)
			"hybrid":
				# 实心菱形 + 斜切线（物理+魔法）
				draw_colored_polygon(_diamond(w, h), color)
				draw_line(Vector2(w * 0.12, h * 0.88), Vector2(w * 0.88, h * 0.12),
					Color(0.0, 0.0, 0.0, 0.55), 1.5, true)
			"heal":
				# 十字
				draw_line(Vector2(w * 0.5, h * 0.15), Vector2(w * 0.5, h * 0.85), color, 2.5, true)
				draw_line(Vector2(w * 0.15, h * 0.5), Vector2(w * 0.85, h * 0.5), color, 2.5, true)

	func _diamond(w: float, h: float) -> PackedVector2Array:
		return PackedVector2Array([
			Vector2(w * 0.5, h * 0.08), Vector2(w * 0.92, h * 0.5),
			Vector2(w * 0.5, h * 0.92), Vector2(w * 0.08, h * 0.5)])

	func _star(center: Vector2, outer: float, inner: float) -> PackedVector2Array:
		# 四角星（✦）：8 顶点交替外/内半径，起于正上方
		var pts := PackedVector2Array()
		for i in 8:
			var ang := -PI * 0.5 + float(i) * PI * 0.25
			var r := outer if (i % 2 == 0) else inner
			pts.append(center + Vector2(cos(ang), sin(ang)) * r)
		return pts
