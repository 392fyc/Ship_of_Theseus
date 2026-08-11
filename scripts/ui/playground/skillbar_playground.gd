extends Control
## 剑圣底部信息操作栏 Playground（v3 视觉稿落地，mock 数据）。
## 不改任何真机 .gd / .tscn / JSON；本场景独立，供人工 MCP 截图评审。
## 运行：F6（设为运行场景）或 res://scenes/dev/skillbar_playground.tscn 直接运行。
##
## 五区 L→R 硬序：① 个人信息 ② 资源栏(加宽) ③ 技能栏(居中:4主动+被动心眼)
##   ④ 物品 2×3(缩小) ⑤ 结束(红框)。每区一块 GothFrame。
##
## 切换键（详见 HUD 角标提示）：
##   ↑/↓     剑气档 0 / 4 / 7 / 10
##   ←/→     印记数 1 / 2 / 3（满 3 → 槽 3 招架变拔刀）
##   1       槽 4 居合 冷却态（演示遮罩 + 回合数）
##   2       槽 2 一闪 置灰态（演示去饱和 + 红角标）
##   3       槽 1 斩击 选中态（金加粗边 + 外发光，并显伤害预测器）
##   4       预测器三态循环（单段物理 / 多段 3×12 / 治疗 +16）
##   0       复位到默认代表态
##
## 复用 damage_popup.gd 配色（class_name DamagePopup，可直接引用）。

# 新组件用 preload 引用（headless --script 不刷新全局 class_name 缓存；
# class_name 仍在各自文件里声明，编辑器内/批 4 可全局引用）。
const GothFrameScript: GDScript = preload("res://scripts/ui/playground/goth_frame.gd")
const SwordQiBarScript: GDScript = preload("res://scripts/ui/sword_qi_bar.gd")

# ── 五区框尺寸（对齐 mockup SVG 坐标，整条高 ~118）──
const BAR_H: float = 118.0
const ZONE_GAP: float = 8.0
const INFO_W: float = 232.0
const RES_W: float = 216.0
const SKILL_W: float = 360.0
const ITEM_W: float = 166.0
const END_W: float = 84.0

const SLOT_SIZE: float = 56.0
const PASSIVE_SIZE: float = 48.0
const ITEM_SIZE: float = 38.0
const END_BTN_SIZE: float = 52.0
const MARK_SIZE: float = 24.0
const MARK_SIZE_FULL: float = 28.0

# ── 调色板（对齐 spec.md §4 / 现有常量）──
const C_GOLD: Color = Color(0.722, 0.580, 0.184, 1.0)        # #b8942f
const C_GOLD_BRIGHT: Color = Color(0.878, 0.749, 0.282, 1.0) # #e0bf48 亮金（选中/达标/总值）
const C_TEXT_MAIN: Color = Color(0.902, 0.859, 0.780, 1.0)   # #e6dbc7
const C_TEXT_SUB: Color = Color(0.549, 0.561, 0.600, 1.0)    # #8c8f99
const C_TEXT_DIM: Color = Color(0.361, 0.361, 0.400, 1.0)    # #5c5c66
const C_TEXT_MUTE: Color = Color(0.451, 0.459, 0.498, 1.0)   # #73757f
const C_STANDARD: Color = Color(0.980, 0.451, 0.059, 1.0)    # #fa730f 橙
const C_MOVE: Color = Color(0.231, 0.510, 0.961, 1.0)        # #3b82f5 蓝
const C_SWIFT: Color = Color(0.063, 0.722, 0.518, 1.0)       # #10b884 绿
const C_QI_LOW: Color = Color(0.373, 0.659, 0.847, 1.0)      # #5fa8d8 消耗角标淡蓝
const C_RED: Color = Color(0.878, 0.180, 0.180, 1.0)         # #e02e2e 危险/不足
const C_SELECTED: Color = Color(0.878, 0.749, 0.282, 1.0)    # #e0bf48 选中金
const C_SLOT_BG: Color = Color(0.067, 0.035, 0.102, 1.0)     # #11091a 槽底
const C_SLOT_BG_DISABLED: Color = Color(0.051, 0.039, 0.078, 1.0) # #0d0a14
const C_EDGE_DISABLED: Color = Color(0.275, 0.278, 0.302, 1.0)    # #46474d
const C_ICON_DISABLED: Color = Color(0.361, 0.361, 0.400, 1.0)   # #5c5c66
const C_OVERLAY: Color = Color(0.024, 0.035, 0.055, 0.66)    # rgba(6,9,14,.66)
const C_ITEM_EMPTY_EDGE: Color = Color(0.227, 0.212, 0.251, 1.0)  # #3a3640
const C_MARK_HELD_BG: Color = Color(0.102, 0.078, 0.063, 1.0)    # #1a1410
const C_MARK_HELD_BG_FULL: Color = Color(0.165, 0.125, 0.055, 1.0)# #2a200e
const C_MARK_EMPTY_BG: Color = Color(0.051, 0.039, 0.078, 1.0)   # #0d0a14

# ── mock 状态 ───────────────────────────────────────
var _qi_levels: Array[int] = [0, 4, 7, 10]
var _qi_index: int = 2          # 默认剑气 7（达标紫·代表态）
var _mark_count: int = 2        # 默认持有 2（心 + 道）
var _slot4_cooldown: int = 0    # 居合冷却回合（0 = 无）
var _slot2_disabled: bool = false
var _slot1_selected: bool = true # 默认槽1选中 → 显伤害预测器
var _forecast_mode: int = 0     # 0 单段物理 / 1 多段3×12 / 2 治疗

# ── 组件引用（用于切换时重建/刷新）──
var _slots_holder: HBoxContainer = null
var _marks_holder: HBoxContainer = null
var _qi_bar: Control = null   # SwordQiBar 实例（preload，避免 headless class_name 未注册）
var _qi_value_label: Label = null
var _forecaster: _ForecastPanel = null
var _target_marker: Control = null
var _hud_label: Label = null

const MARK_KEYS: Array[String] = ["心", "道", "势"]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_refresh_all()


func _build() -> void:
	# 背景（暗页底）
	var bg: ColorRect = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.027, 0.031, 0.063, 1.0)  # #070810
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# mock「目标」标记 + 浮其上方的伤害预测器（居屏中上区）
	_build_target_and_forecaster()

	# ── 布局重排（动态视口，禁硬编码 1280）──
	# 目标：[个人信息]···空隙···[资源][技能·屏幕正中][物品]···空隙···[结束]
	# 硬约束：技能框水平中线 = 视口水平中线；个人信息钉左下、结束钉右下。
	var vp: Vector2 = get_viewport_rect().size
	var margin: float = 12.0
	var bar_y: float = vp.y - BAR_H - margin

	# 中央簇：技能框严格居中 → 技能左缘 = 视口中线 - 技能半宽
	var skill_x: float = vp.x * 0.5 - SKILL_W * 0.5
	# 资源紧贴技能左侧（资源右缘 = 技能左缘 - ZONE_GAP）
	var res_x: float = skill_x - ZONE_GAP - RES_W
	# 物品紧贴技能右侧（物品左缘 = 技能右缘 + ZONE_GAP）
	var item_x: float = skill_x + SKILL_W + ZONE_GAP

	# 两端钉角：个人信息左下，结束右下（左右对称）
	var info_x: float = margin
	var end_x: float = vp.x - margin - END_W

	_add_zone(_build_info_zone(), info_x, bar_y, INFO_W)
	_add_zone(_build_resource_zone(), res_x, bar_y, RES_W)
	_add_zone(_build_skill_zone(), skill_x, bar_y, SKILL_W)
	_add_zone(_build_item_zone(), item_x, bar_y, ITEM_W)
	_add_zone(_build_end_zone(), end_x, bar_y, END_W)

	_build_hud()


## 把一个区内容（已含 GothFrame 背景）放到绝对位置，返回右缘 x。
func _add_zone(zone: Control, x: float, y: float, w: float) -> float:
	zone.position = Vector2(x, y)
	zone.size = Vector2(w, BAR_H)
	add_child(zone)
	return x + w


# ═══════════════════════════════════════════════════════════════
#  ① 个人信息区（简化 mock：头像框 + 名/Lv + HP 条 + 属性几项）
# ═══════════════════════════════════════════════════════════════

func _build_info_zone() -> Control:
	var root: Control = _make_framed_zone("normal")

	# 头像框
	var portrait: Control = _make_panel_box(Vector2(56.0, 74.0),
		Color(0.020, 0.027, 0.051, 1.0), C_GOLD, 1.4)
	portrait.position = Vector2(12.0, 12.0)
	root.add_child(portrait)
	var pl: Label = _make_label("武", 26, C_GOLD)
	pl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait.add_child(pl)

	# 名 / 等级
	_add_text(root, "武藏", 12, C_TEXT_MAIN, Vector2(78.0, 14.0))
	_add_text(root, "Lv.12 剑圣", 9, C_TEXT_SUB, Vector2(78.0, 32.0))

	# HP 条（简化）
	var hp_track: Control = _make_panel_box(Vector2(140.0, 11.0),
		Color(0.039, 0.047, 0.071, 1.0), Color(0.227, 0.188, 0.094, 0.8), 1.0)
	hp_track.position = Vector2(78.0, 48.0)
	root.add_child(hp_track)
	var hp_fill: ColorRect = ColorRect.new()
	hp_fill.color = Color(0.247, 0.682, 0.329, 1.0)  # #3fae54
	hp_fill.position = Vector2(1.0, 1.0)
	hp_fill.size = Vector2(98.0, 9.0)
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_track.add_child(hp_fill)
	var hp_lbl: Label = _make_label("HP 30/42", 8, C_TEXT_MAIN)
	hp_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_track.add_child(hp_lbl)

	# 属性几项（2 列 × 3 行 mock）
	var stats: Array = [
		["STR", "14", Vector2(78.0, 66.0)], ["DEX", "16", Vector2(140.0, 66.0)],
		["SPD", "15", Vector2(78.0, 80.0)], ["LCK", "9", Vector2(140.0, 80.0)],
		["DEF", "8", Vector2(190.0, 66.0)], ["MOV", "5", Vector2(190.0, 80.0)],
	]
	for s: Array in stats:
		_add_text(root, str(s[0]), 8, C_GOLD, s[2])
		_add_text(root, str(s[1]), 8, C_TEXT_MAIN, (s[2] as Vector2) + Vector2(26.0, 0.0))

	_add_zone_caption(root, "个人信息")
	return root


# ═══════════════════════════════════════════════════════════════
#  ② 资源栏（剑气 10 格条 + 印记 心/道/势）
# ═══════════════════════════════════════════════════════════════

func _build_resource_zone() -> Control:
	var root: Control = _make_framed_zone("normal")

	# 内容统一以「剑气条」宽度为列宽（182），在框内水平居中 → 各行同左缘对齐。
	var bar_w: float = SwordQiBarScript.BAR_W
	var col_x: float = (RES_W - bar_w) * 0.5  # 列左缘（居中）

	# 剑气标签（列左对齐） + 数值（列右对齐），同一行
	var qi_lbl: Label = _make_label("剑气", 11, C_GOLD)
	qi_lbl.position = Vector2(col_x, 18.0)
	qi_lbl.size = Vector2(bar_w * 0.5, 14.0)
	qi_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(qi_lbl)
	_qi_value_label = _make_label("7 / 10", 11, C_GOLD_BRIGHT)
	_qi_value_label.position = Vector2(col_x, 18.0)
	_qi_value_label.size = Vector2(bar_w, 14.0)
	_qi_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_qi_value_label)

	# 剑气分段条（与上行同左缘）
	_qi_bar = SwordQiBarScript.new()
	_qi_bar.position = Vector2(col_x, 34.0)
	_qi_bar.size = Vector2(bar_w, SwordQiBarScript.BAR_H + 14.0)
	_qi_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_qi_bar)

	# 速度+1 标注（达标态显示，刷新时控可见）
	# （并入 qi 数值色与阈值线，由 SwordQiBar 自绘；此处不重复，避免与条上箭头叠加）

	# 印记区（标题列左对齐 + 印记盒紧随其后，整行与上方同左缘）
	var mark_lbl: Label = _make_label("印记", 11, C_GOLD)
	mark_lbl.position = Vector2(col_x, 78.0)
	mark_lbl.size = Vector2(34.0, 14.0)
	mark_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(mark_lbl)
	_marks_holder = HBoxContainer.new()
	_marks_holder.position = Vector2(col_x + 36.0, 72.0)
	_marks_holder.add_theme_constant_override("separation", 6)
	_marks_holder.alignment = BoxContainer.ALIGNMENT_BEGIN
	_marks_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_marks_holder)

	_add_zone_caption(root, "资源栏（加宽）")
	return root


func _rebuild_marks() -> void:
	for child: Node in _marks_holder.get_children():
		child.queue_free()
	var full: bool = _mark_count >= 3
	for i: int in range(MARK_KEYS.size()):
		var held: bool = i < _mark_count
		var box: MarkBox = MarkBox.new()
		box.key_text = MARK_KEYS[i]
		box.held = held
		box.full_state = full
		_marks_holder.add_child(box)
	# 计数小字
	var cnt: Label = _make_label("%d/3" % _mark_count, 8, C_TEXT_MUTE)
	cnt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_marks_holder.add_child(cnt)


# ═══════════════════════════════════════════════════════════════
#  ③ 技能栏（4 主动 1-4 + 细分隔 + 被动心眼）
# ═══════════════════════════════════════════════════════════════

func _build_skill_zone() -> Control:
	var root: Control = _make_framed_zone("normal")

	# 用 CenterContainer 铺满「框内 - 底部标题条」区域 → 槽行水平 + 垂直居中
	var center: CenterContainer = _make_zone_center_area()
	root.add_child(center)

	_slots_holder = HBoxContainer.new()
	_slots_holder.alignment = BoxContainer.ALIGNMENT_CENTER
	_slots_holder.add_theme_constant_override("separation", 6)
	_slots_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_slots_holder)

	_add_zone_caption(root, "技能栏（居中）")
	return root


func _rebuild_slots() -> void:
	for child: Node in _slots_holder.get_children():
		child.queue_free()

	var full: bool = _mark_count >= 3

	# 槽 1 斩击（橙，0 气回 +1 气）
	var s1: SkillSlot = _make_slot("1", "斩击", C_STANDARD, "+1气", "attack")
	s1.selected = _slot1_selected
	_slots_holder.add_child(s1)

	# 槽 2 一闪（蓝，1 气，可置灰）
	var s2: SkillSlot = _make_slot("2", "一闪", C_MOVE, "1气", "dash")
	s2.disabled = _slot2_disabled
	_slots_holder.add_child(s2)

	# 槽 3 招架 ↔ 拔刀（slot swap）
	var s3: SkillSlot
	if full:
		s3 = _make_slot("3", "拔刀", C_STANDARD, "3印+2气", "iai")
		s3.swap_badge = true   # 左下金「换」角标
	else:
		s3 = _make_slot("3", "招架", C_SWIFT, "1气", "parry")
	_slots_holder.add_child(s3)

	# 槽 4 居合（橙，6 气，可冷却）
	var s4: SkillSlot = _make_slot("4", "居合", C_STANDARD, "6气", "iai")
	s4.cooldown = _slot4_cooldown
	_slots_holder.add_child(s4)

	# 细分隔（主动 | 被动）
	var divider: ColorRect = ColorRect.new()
	divider.custom_minimum_size = Vector2(1.0, SLOT_SIZE - 4.0)
	divider.color = Color(0.420, 0.353, 0.196, 0.5)  # #6b5a32(.5)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 用左右间隔模拟 mockup 的细线缝隙
	var div_holder: CenterContainer = CenterContainer.new()
	div_holder.custom_minimum_size = Vector2(8.0, SLOT_SIZE)
	div_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	div_holder.add_child(divider)
	_slots_holder.add_child(div_holder)

	# 被动 心眼（48px，「P」角标，无键位/不可点/无冷却）
	var passive: SkillSlot = SkillSlot.new()
	passive.is_passive = true
	passive.glyph_kind = "eye"
	passive.accent = C_GOLD
	passive.title = "心眼"
	passive.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slots_holder.add_child(passive)


func _make_slot(key: String, title: String, accent: Color, cost: String, glyph: String) -> SkillSlot:
	var slot: SkillSlot = SkillSlot.new()
	slot.key_text = key
	slot.title = title
	slot.accent = accent
	slot.cost_text = cost
	slot.glyph_kind = glyph
	return slot


# ═══════════════════════════════════════════════════════════════
#  ④ 物品 2×3（占位，无点击交互）
# ═══════════════════════════════════════════════════════════════

func _build_item_zone() -> Control:
	var root: Control = _make_framed_zone("normal")

	# 标题 + 网格整体在框内（除底部标题条）水平 + 垂直居中
	var center: CenterContainer = _make_zone_center_area()
	root.add_child(center)

	var col: VBoxContainer = VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)

	# 「道具」标题（居中）
	var title: Label = _make_label("道具", 9, C_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(title)

	# mock 占位：药剂x2 / 卷轴x1 / 空 / 净化x1 / 空 / 空
	var items: Array = [
		{"kind": "potion", "color": Color(0.180, 0.682, 0.337, 1.0), "count": "x2"},
		{"kind": "scroll", "color": C_GOLD, "count": "x1"},
		{"kind": "empty"},
		{"kind": "potion", "color": C_MOVE, "count": "x1"},  # 净化（蓝液）
		{"kind": "empty"},
		{"kind": "empty"},
	]
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(grid)
	for it: Dictionary in items:
		var cell: ItemSlot = ItemSlot.new()
		cell.kind = str(it.get("kind", "empty"))
		cell.icon_color = it.get("color", C_GOLD)
		cell.count_text = str(it.get("count", ""))
		grid.add_child(cell)

	_add_zone_caption(root, "物品 2×3（缩小）")
	return root


# ═══════════════════════════════════════════════════════════════
#  ⑤ 结束（红框）
# ═══════════════════════════════════════════════════════════════

func _build_end_zone() -> Control:
	var root: Control = _make_framed_zone("end")

	var btn: Control = _make_panel_box(Vector2(END_BTN_SIZE, END_BTN_SIZE),
		Color(0.141, 0.071, 0.075, 1.0), Color(C_RED, 0.42), 1.0)
	btn.position = Vector2((END_W - END_BTN_SIZE) * 0.5, 26.0)
	root.add_child(btn)
	var icon: ColorRect = ColorRect.new()
	icon.color = C_RED
	icon.size = Vector2(16.0, 16.0)
	icon.position = (Vector2(END_BTN_SIZE, END_BTN_SIZE) - icon.size) * 0.5
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(icon)

	_add_text_centered(root, "结束回合", 9, C_TEXT_MAIN, 88.0, END_W)
	_add_zone_caption(root, "结束（最右）")
	return root


# ═══════════════════════════════════════════════════════════════
#  目标标记 + 伤害预测器（浮于目标上方）
# ═══════════════════════════════════════════════════════════════

func _build_target_and_forecaster() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var target_center: Vector2 = Vector2(vp.x * 0.5, vp.y * 0.34)

	# mock 目标标记（菱形格 + 「敌」字）
	_target_marker = Control.new()
	_target_marker.size = Vector2(64.0, 64.0)
	_target_marker.position = target_center - _target_marker.size * 0.5
	_target_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_target_marker)
	var marker_box: Control = _make_panel_box(Vector2(56.0, 56.0),
		Color(0.110, 0.043, 0.047, 1.0), Color(C_RED, 0.6), 1.4)
	marker_box.position = Vector2(4.0, 4.0)
	_target_marker.add_child(marker_box)
	var ml: Label = _make_label("敌", 20, Color(0.949, 0.659, 0.659, 1.0))
	ml.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker_box.add_child(ml)
	var hint: Label = _make_label("mock 目标", 8, C_TEXT_SUB)
	hint.position = Vector2(0.0, 66.0)
	hint.size = Vector2(64.0, 12.0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_marker.add_child(hint)

	# 伤害预测器（浮于目标头顶上方，三角向下指向目标）
	_forecaster = _ForecastPanel.new()
	_forecaster.size = _ForecastPanel.PANEL_SIZE
	# 锚到目标头顶：x 居中目标、底部三角尖对准目标上缘
	_forecaster.position = Vector2(
		target_center.x - _ForecastPanel.PANEL_SIZE.x * 0.5,
		target_center.y - 32.0 - _ForecastPanel.PANEL_SIZE.y - _ForecastPanel.TRIANGLE_H)
	_forecaster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_forecaster)


# ═══════════════════════════════════════════════════════════════
#  HUD 提示 + 切换键
# ═══════════════════════════════════════════════════════════════

func _build_hud() -> void:
	_hud_label = Label.new()
	_hud_label.position = Vector2(16.0, 12.0)
	_hud_label.add_theme_font_size_override("font_size", 11)
	_hud_label.add_theme_color_override("font_color", C_TEXT_SUB)
	_hud_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
	_hud_label.add_theme_constant_override("outline_size", 2)
	add_child(_hud_label)


func _update_hud() -> void:
	var qi: int = _qi_levels[_qi_index]
	var fmodes: Array[String] = ["单段物理", "多段3×12", "治疗+16"]
	_hud_label.text = "剑圣底栏 Playground（mock）   切换键：↑/↓ 剑气[%d]  ←/→ 印记[%d]  1 居合冷却[%s]  2 一闪置灰[%s]  3 斩击选中[%s]  4 预测器[%s]  0 复位" % [
		qi, _mark_count,
		"开" if _slot4_cooldown > 0 else "关",
		"开" if _slot2_disabled else "关",
		"开" if _slot1_selected else "关",
		fmodes[_forecast_mode],
	]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = (event as InputEventKey).keycode
	match key:
		KEY_UP:
			_qi_index = (_qi_index + 1) % _qi_levels.size()
		KEY_DOWN:
			_qi_index = (_qi_index - 1 + _qi_levels.size()) % _qi_levels.size()
		KEY_RIGHT:
			_mark_count = clampi(_mark_count + 1, 1, 3)
		KEY_LEFT:
			_mark_count = clampi(_mark_count - 1, 1, 3)
		KEY_1:
			_slot4_cooldown = 0 if _slot4_cooldown > 0 else 3
		KEY_2:
			_slot2_disabled = not _slot2_disabled
		KEY_3:
			_slot1_selected = not _slot1_selected
		KEY_4:
			_forecast_mode = (_forecast_mode + 1) % 3
		KEY_0:
			_reset_mock()
		_:
			return
	_refresh_all()


func _reset_mock() -> void:
	_qi_index = 2
	_mark_count = 2
	_slot4_cooldown = 0
	_slot2_disabled = false
	_slot1_selected = true
	_forecast_mode = 0


func _refresh_all() -> void:
	var qi: int = _qi_levels[_qi_index]
	if _qi_bar != null:
		_qi_bar.sword_qi = qi
		_qi_bar.sword_qi_max = 10
		_qi_bar.threshold = 7
	if _qi_value_label != null:
		_qi_value_label.text = "%d / 10" % qi
		var reached: bool = qi >= 7
		_qi_value_label.add_theme_color_override("font_color",
			SwordQiBarScript.QI_HIGH_GLOW if reached else C_QI_LOW)
	if _marks_holder != null:
		_rebuild_marks()
	if _slots_holder != null:
		_rebuild_slots()
	if _forecaster != null:
		_forecaster.visible = _slot1_selected
		_forecaster.set_mode(_forecast_mode)
	if _hud_label != null:
		_update_hud()


# ═══════════════════════════════════════════════════════════════
#  小工具
# ═══════════════════════════════════════════════════════════════

func _make_framed_zone(variant: String) -> Control:
	var root: Control = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame: Control = GothFrameScript.new()  # GothFrame 实例
	frame.variant = variant
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(frame)
	return root


## 框内居中区：铺满 GothFrame 内部（除底部标题条），子节点自动水平+垂直居中。
## 顶部留 4px、底部让出 16px 标题条，左右各内缩 4px 不贴边。
func _make_zone_center_area() -> CenterContainer:
	var center: CenterContainer = CenterContainer.new()
	center.anchor_left = 0.0
	center.anchor_top = 0.0
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	center.offset_left = 4.0
	center.offset_top = 4.0
	center.offset_right = -4.0
	center.offset_bottom = -16.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return center


func _make_panel_box(box_size: Vector2, fill: Color, border: Color, border_w: float) -> Control:
	var box: ColorRect = ColorRect.new()
	box.color = fill
	box.size = box_size
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b: BorderDraw = BorderDraw.new()
	b.border_color = border
	b.border_width = border_w
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(b)
	return box


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _add_text(parent: Control, text: String, font_size: int, color: Color, pos: Vector2) -> void:
	var l: Label = _make_label(text, font_size, color)
	l.position = pos
	parent.add_child(l)


func _add_text_centered(parent: Control, text: String, font_size: int, color: Color, y: float, w: float) -> void:
	var l: Label = _make_label(text, font_size, color)
	l.position = Vector2(0.0, y)
	l.size = Vector2(w, 14.0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)


func _add_zone_caption(parent: Control, text: String) -> void:
	# 拉满区宽、底部居中（区宽未知 → 用 anchor 横向铺满，KEEP_SIZE 不改高）
	var l: Label = _make_label(text, 9, C_TEXT_MUTE)
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.offset_left = 0.0
	l.offset_right = 0.0
	l.offset_top = BAR_H - 16.0
	l.offset_bottom = BAR_H - 2.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)


# ═══════════════════════════════════════════════════════════════
#  内部类：简易 1px 边框绘制（叠在 ColorRect 上）
# ═══════════════════════════════════════════════════════════════

class BorderDraw extends Control:
	var border_color: Color = Color.WHITE
	var border_width: float = 1.0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), border_color, false, border_width)


# ═══════════════════════════════════════════════════════════════
#  内部类：技能槽（主动 56 / 被动 48），全状态自绘
#  互斥优先级：冷却中 > 不可用 > 选中 > 常态（对齐 spec.md §5）
# ═══════════════════════════════════════════════════════════════

class SkillSlot extends Control:
	var key_text: String = ""        # 左上键位角标（被动无）
	var title: String = ""
	var accent: Color = Color.WHITE  # 资源色（边框）
	var cost_text: String = ""       # 右下消耗角标
	var glyph_kind: String = "attack"
	var cooldown: int = 0
	var disabled: bool = false
	var selected: bool = false
	var swap_badge: bool = false     # 左下金「换」角标（拔刀态）
	var is_passive: bool = false

	const C_SLOT_BG: Color = Color(0.067, 0.035, 0.102, 1.0)
	const C_SLOT_BG_DISABLED: Color = Color(0.051, 0.039, 0.078, 1.0)
	const C_EDGE_DISABLED: Color = Color(0.275, 0.278, 0.302, 1.0)
	const C_ICON_DISABLED: Color = Color(0.361, 0.361, 0.400, 1.0)
	const C_OVERLAY: Color = Color(0.024, 0.035, 0.055, 0.66)
	const C_SELECTED: Color = Color(0.878, 0.749, 0.282, 1.0)
	const C_GOLD_BRIGHT: Color = Color(0.878, 0.749, 0.282, 1.0)
	const C_QI_LOW: Color = Color(0.373, 0.659, 0.847, 1.0)
	const C_RED: Color = Color(0.878, 0.180, 0.180, 1.0)
	const C_TEXT_MAIN: Color = Color(0.902, 0.859, 0.780, 1.0)
	const C_TEXT_SUB: Color = Color(0.549, 0.561, 0.600, 1.0)
	const C_STANDARD: Color = Color(0.980, 0.451, 0.059, 1.0)

	func _ready() -> void:
		var s: float = 48.0 if is_passive else 56.0
		# 主动槽底部留 14px 给标题行；被动同
		custom_minimum_size = Vector2(s, s + 14.0)

	func _draw() -> void:
		var s: float = 48.0 if is_passive else 56.0
		var slot: Rect2 = Rect2(0.0, 0.0, s, s)

		var state_cooldown: bool = cooldown > 0 and not is_passive
		var state_disabled: bool = disabled and not state_cooldown and not is_passive

		# 槽底
		var bg: Color = C_SLOT_BG_DISABLED if state_disabled else C_SLOT_BG
		draw_rect(slot, bg)

		# 边框（按状态）
		var edge: Color
		var edge_w: float = 1.0
		if state_disabled:
			edge = Color(C_EDGE_DISABLED, 0.5)
		elif selected and not is_passive:
			edge = C_SELECTED
			edge_w = 1.6
		else:
			edge = Color(accent, 0.55)
		draw_rect(slot, edge, false, edge_w)

		# 选中外发光（金描边外圈）
		if selected and not state_cooldown and not state_disabled and not is_passive:
			draw_rect(Rect2(-2.0, -2.0, s + 4.0, s + 4.0), Color(C_SELECTED, 0.35), false, 3.0)

		# 图标
		var icon_col: Color = accent
		if state_cooldown:
			icon_col = Color(0.478, 0.455, 0.408, 1.0)  # 转暗灰
		elif state_disabled:
			icon_col = C_ICON_DISABLED
		elif selected and not is_passive:
			icon_col = Color(1.0, 0.949, 0.812, 1.0)
		_draw_glyph(Vector2(s, s) * 0.5, icon_col)

		# 冷却遮罩 + 中心回合数
		if state_cooldown:
			draw_rect(slot, C_OVERLAY)
			var ctxt: String = str(cooldown)
			var fnt: Font = ThemeDB.fallback_font
			var fs: int = 20
			var tw: float = fnt.get_string_size(ctxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var tp: Vector2 = Vector2(s * 0.5 - tw * 0.5, s * 0.5 + 2.0)
			# 描边
			for off: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				draw_string(fnt, tp + off, ctxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.9))
			draw_string(fnt, tp, ctxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, accent)
			var rfnt: Font = ThemeDB.fallback_font
			var rw: float = rfnt.get_string_size("回合", HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			draw_string(rfnt, Vector2(s * 0.5 - rw * 0.5, s * 0.5 + 18.0), "回合", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_TEXT_MAIN)

		# 左上键位角标 / 被动「P」角标
		if is_passive:
			_draw_badge(Rect2(0.0, 0.0, 13.0, 11.0), Color(0.612, 0.514, 0.278, 0.5), "P", 8, C_TEXT_SUB)
		elif key_text != "":
			var key_edge: Color = Color(accent, 0.6)
			if state_disabled:
				key_edge = Color(C_EDGE_DISABLED, 0.5)
			var key_col: Color = C_TEXT_MAIN if not state_disabled else Color(0.361, 0.361, 0.400, 1.0)
			_draw_badge(Rect2(0.0, 0.0, 14.0, 13.0), key_edge, key_text, 9, key_col)

		# 右下消耗角标
		if cost_text != "" and not is_passive and not state_cooldown:
			var cost_col: Color = C_QI_LOW
			if state_disabled:
				cost_col = C_RED  # 缺口资源角标变红
			elif swap_badge:
				cost_col = C_GOLD_BRIGHT
			_draw_cost_badge(s, cost_text, cost_col)

		# 左下金「换」角标（拔刀态）
		if swap_badge and not state_cooldown and not state_disabled:
			_draw_badge(Rect2(0.0, s - 12.0, 14.0, 12.0), Color(C_GOLD_BRIGHT, 0.7), "换", 8, C_GOLD_BRIGHT)

		# 标题行
		var title_col: Color = C_TEXT_SUB
		if selected and not is_passive:
			title_col = C_GOLD_BRIGHT
		elif state_disabled or state_cooldown:
			title_col = Color(0.451, 0.459, 0.498, 1.0)
		elif title == "居合" or title == "拔刀":
			title_col = C_TEXT_MAIN
		_draw_title(s, title, title_col)

	func _draw_badge(r: Rect2, edge: Color, text: String, fs: int, text_col: Color) -> void:
		draw_rect(r, Color(0.039, 0.047, 0.090, 0.9))
		draw_rect(r, edge, false, 1.0)
		var fnt: Font = ThemeDB.fallback_font
		var tw: float = fnt.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(fnt, Vector2(r.position.x + (r.size.x - tw) * 0.5, r.position.y + r.size.y - 2.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_col)

	func _draw_cost_badge(s: float, text: String, col: Color) -> void:
		var fnt: Font = ThemeDB.fallback_font
		var fs: int = 8
		var tw: float = fnt.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var bw: float = tw + 6.0
		var r: Rect2 = Rect2(s - bw, s - 12.0, bw, 12.0)
		draw_rect(r, Color(0.039, 0.047, 0.090, 0.85))
		draw_string(fnt, Vector2(r.position.x + 3.0, r.position.y + 9.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	func _draw_title(s: float, text: String, col: Color) -> void:
		var fnt: Font = ThemeDB.fallback_font
		var fs: int = 9
		var tw: float = fnt.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(fnt, Vector2((s - tw) * 0.5, s + 11.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	func _draw_glyph(c: Vector2, col: Color) -> void:
		match glyph_kind:
			"dash":
				draw_line(c + Vector2(-13, 13), c + Vector2(13, -13), col, 2.4, true)
				var tip: Vector2 = c + Vector2(13, -13)
				draw_colored_polygon([tip, tip + Vector2(-6, 1), tip + Vector2(-1, 6)], col)
			"parry":
				# 盾形
				var pts: PackedVector2Array = PackedVector2Array([
					c + Vector2(0, -14), c + Vector2(12, -9), c + Vector2(12, 2),
					c + Vector2(0, 15), c + Vector2(-12, 2), c + Vector2(-12, -9)])
				for i: int in range(pts.size()):
					draw_line(pts[i], pts[(i + 1) % pts.size()], col, 1.8, true)
				draw_line(c + Vector2(-6, 1), c + Vector2(6, 1), col, 1.6, true)
			"iai":
				draw_line(c + Vector2(-15, 15), c + Vector2(15, -15), col, 2.8, true)
				draw_line(c + Vector2(-6, -9), c + Vector2(0, -15), col.lightened(0.3), 1.2, true)
				draw_line(c + Vector2(6, 9), c + Vector2(15, 0), col.lightened(0.3), 1.2, true)
			"eye":
				# 心眼：眼形
				_draw_eye(c, col)
			_:
				# attack：斜斩刃
				draw_line(c + Vector2(-12, 13), c + Vector2(14, -13), col.lightened(0.1), 2.4, true)
				draw_line(c + Vector2(-10, 15), c + Vector2(-4, 19), col.darkened(0.2), 2.0, true)

	func _draw_eye(c: Vector2, col: Color) -> void:
		# 椭圆轮廓（手绘点连线）
		var pts: PackedVector2Array = PackedVector2Array()
		var rx: float = 15.0
		var ry: float = 9.0
		var segs: int = 28
		for i: int in range(segs + 1):
			var a: float = float(i) / float(segs) * TAU
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		for i: int in range(pts.size() - 1):
			draw_line(pts[i], pts[i + 1], col, 1.6, true)
		draw_circle(c, 4.4, col)
		draw_circle(c + Vector2(-1.6, -1.6), 1.3, C_SLOT_BG)


# ═══════════════════════════════════════════════════════════════
#  内部类：印记方块（心/道/势 24×24，满 3 态 28 高加粗）
# ═══════════════════════════════════════════════════════════════

class MarkBox extends Control:
	var key_text: String = "心"
	var held: bool = false
	var full_state: bool = false

	const C_HELD_BG: Color = Color(0.102, 0.078, 0.063, 1.0)
	const C_HELD_BG_FULL: Color = Color(0.165, 0.125, 0.055, 1.0)
	const C_EMPTY_BG: Color = Color(0.051, 0.039, 0.078, 1.0)
	const C_GOLD_BRIGHT: Color = Color(0.878, 0.749, 0.282, 1.0)
	const C_TEXT_DIM: Color = Color(0.361, 0.361, 0.400, 1.0)
	const C_TEXT_BRIGHT: Color = Color(1.0, 0.949, 0.812, 1.0)

	func _ready() -> void:
		var w: float = 24.0
		var h: float = 28.0 if (full_state and held) else 24.0
		custom_minimum_size = Vector2(w, h)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var w: float = 24.0
		var h: float = 28.0 if (full_state and held) else 24.0
		var r: Rect2 = Rect2(0.0, 0.0, w, h)
		var bg: Color
		var edge: Color
		var txt_col: Color
		var edge_w: float
		if held:
			bg = C_HELD_BG_FULL if full_state else C_HELD_BG
			edge = C_GOLD_BRIGHT
			txt_col = C_TEXT_BRIGHT if full_state else C_GOLD_BRIGHT
			edge_w = 1.6 if full_state else 1.2
		else:
			bg = C_EMPTY_BG
			edge = C_TEXT_DIM
			txt_col = C_TEXT_DIM
			edge_w = 1.2
		draw_rect(r, bg)
		draw_rect(r, edge, false, edge_w)
		var fnt: Font = ThemeDB.fallback_font
		var fs: int = 13
		var tw: float = fnt.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(fnt, Vector2((w - tw) * 0.5, h * 0.5 + 5.0), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, txt_col)


# ═══════════════════════════════════════════════════════════════
#  内部类：物品格（38×38 占位，无交互）
# ═══════════════════════════════════════════════════════════════

class ItemSlot extends Control:
	var kind: String = "empty"          # potion / scroll / empty
	var icon_color: Color = Color.WHITE
	var count_text: String = ""

	const SIZE: float = 38.0
	const C_FILLED_BG: Color = Color(0.082, 0.067, 0.047, 1.0)   # #15110c
	const C_FILLED_EDGE: Color = Color(0.863, 0.780, 0.678, 0.42)# #dcc7ad(.42)
	const C_EMPTY_BG: Color = Color(0.047, 0.039, 0.071, 1.0)    # #0c0a12
	const C_EMPTY_EDGE: Color = Color(0.227, 0.212, 0.251, 0.7)  # #3a3640(.7)
	const C_TEXT_MAIN: Color = Color(0.902, 0.859, 0.780, 1.0)

	func _ready() -> void:
		custom_minimum_size = Vector2(SIZE, SIZE)

	func _draw() -> void:
		var r: Rect2 = Rect2(0.0, 0.0, SIZE, SIZE)
		if kind == "empty":
			draw_rect(r, C_EMPTY_BG)
			_draw_dashed_border(r, C_EMPTY_EDGE)
			draw_circle(Vector2(SIZE * 0.5, SIZE * 0.5), 2.0, Color(0.227, 0.212, 0.251, 1.0))
			return
		draw_rect(r, C_FILLED_BG)
		draw_rect(r, C_FILLED_EDGE, false, 1.0)
		match kind:
			"potion":
				# 瓶身 + 液体
				var bottle: Rect2 = Rect2(13.0, 9.0, 12.0, 16.0)
				draw_rect(bottle, Color(0.863, 0.780, 0.678, 0.9), false, 1.4)
				draw_rect(Rect2(15.0, 16.0, 8.0, 7.0), icon_color)
			"scroll":
				var scroll: Rect2 = Rect2(12.0, 10.0, 14.0, 17.0)
				draw_rect(scroll, Color(0.847, 0.765, 0.612, 0.9), false, 1.3)
				for ly: float in [15.0, 19.0, 23.0]:
					var lw: float = 8.0 if ly < 23.0 else 5.0
					draw_line(Vector2(15.0, ly), Vector2(15.0 + lw, ly), Color(0.722, 0.604, 0.392, 1.0), 1.0)
		# 右下数量角标
		if count_text != "":
			var br: Rect2 = Rect2(SIZE - 14.0, SIZE - 11.0, 13.0, 11.0)
			draw_rect(br, Color(0.039, 0.047, 0.090, 0.85))
			var fnt: Font = ThemeDB.fallback_font
			var fs: int = 7
			var tw: float = fnt.get_string_size(count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(fnt, Vector2(br.position.x + (br.size.x - tw) * 0.5, br.position.y + 8.0), count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_TEXT_MAIN)

	func _draw_dashed_border(r: Rect2, col: Color) -> void:
		var dash: float = 3.0
		var gap: float = 3.0
		# 顶 / 底
		for edge_y: float in [r.position.y, r.position.y + r.size.y - 1.0]:
			var xx: float = r.position.x
			while xx < r.position.x + r.size.x:
				draw_line(Vector2(xx, edge_y), Vector2(minf(xx + dash, r.position.x + r.size.x), edge_y), col, 1.0)
				xx += dash + gap
		# 左 / 右
		for edge_x: float in [r.position.x, r.position.x + r.size.x - 1.0]:
			var yy: float = r.position.y
			while yy < r.position.y + r.size.y:
				draw_line(Vector2(edge_x, yy), Vector2(edge_x, minf(yy + dash, r.position.y + r.size.y)), col, 1.0)
				yy += dash + gap


# ═══════════════════════════════════════════════════════════════
#  内部类：伤害预测器（暗黑哥特框 + 向下三角，浮于目标上方）
#  三态：单段「物理 · 24」/ 多段「物理 3 × 12（36）」/ 治疗「治疗 · +16」
# ═══════════════════════════════════════════════════════════════

## ⚠ 名字里的下划线前缀不是风格偏好，是**防再次撞车**。
##
## 本类原名 `DamageForecaster`，与 `scripts/ui/damage_forecaster.gd` 顶部的全局
## `class_name DamageForecaster` 同名 —— 内部类名 hides a global script class，
## 整个 playground 脚本 **parse 失败**。它从 `15aebaa`（那次把预测浮窗抽成全局类、
## 同时也改了本文件，但漏删这个内部类）起就坏着，两个月无人发现：唯一会碰它的
## `tests/test_skillbar_playground_load.gd` 当时只检查 `load()` 与 `instantiate()`
## 的返回非 null，而**场景在附着脚本 parse 失败时照样实例化得出来**（脚本变成
## null、节点还在），于是它照常打印 OK 并退出 0。
##
## 保留这份与全局类近乎重复的实现是**有意的**：收敛两份实现要先逐字比对确认没有
## playground 专属差异，那是一次行为等价性判断，而 playground 是 `scenes/dev/` 下的
## 开发期原型、不在出货路径上，为它冒行为改变的风险收益不对等。要收敛该另开一件事，
## 不混进「修假绿测试」这次改动里。
class _ForecastPanel extends Control:
	const PANEL_SIZE: Vector2 = Vector2(180.0, 78.0)
	const TRIANGLE_H: float = 8.0

	# 复用 damage_popup.gd 配色（DamagePopup.COLOR_*，非 autoload，可直接引用）
	var _type_color: Color = DamagePopup.COLOR_PHYS
	var _type_name: String = "物理"
	var _hit_count: int = 1
	var _per_hit: int = 24
	var _hit_percent: int = 92
	var _crit_percent: int = 35
	var _is_heal: bool = false
	var _heal_amount: int = 16

	# 框色（对齐 spec.md §3 / mockup 预测器）
	const FRAME_OUTER: Color = Color(0.031, 0.039, 0.071, 1.0)
	const FRAME_INNER: Color = Color(0.055, 0.063, 0.098, 1.0)
	const EDGE_HI: Color = Color(0.612, 0.514, 0.278, 0.55)
	const EDGE_LO: Color = Color(0.227, 0.188, 0.094, 0.9)
	const C_GOLD: Color = Color(0.722, 0.580, 0.184, 1.0)
	const C_GOLD_BRIGHT: Color = Color(0.878, 0.749, 0.282, 1.0)
	const C_TEXT_SUB: Color = Color(0.549, 0.561, 0.600, 1.0)
	const C_TEXT_DIM: Color = Color(0.361, 0.361, 0.400, 1.0)
	const C_CRIT: Color = Color(0.980, 0.451, 0.059, 1.0)  # 暴击橙 #fa730f

	func set_mode(mode: int) -> void:
		match mode:
			1:
				# 多段物理 3 × 12（36）
				_is_heal = false
				_type_color = DamagePopup.COLOR_PHYS
				_type_name = "物理"
				_hit_count = 3
				_per_hit = 12
				_hit_percent = 92
				_crit_percent = 35
			2:
				# 治疗 +16
				_is_heal = true
				_type_color = DamagePopup.COLOR_HEAL
				_type_name = "治疗"
				_heal_amount = 16
			_:
				# 单段物理 24
				_is_heal = false
				_type_color = DamagePopup.COLOR_PHYS
				_type_name = "物理"
				_hit_count = 1
				_per_hit = 24
				_hit_percent = 92
				_crit_percent = 35
		queue_redraw()

	func _draw() -> void:
		var w: float = PANEL_SIZE.x
		var h: float = PANEL_SIZE.y
		# 外缘 + 内壁
		draw_rect(Rect2(0.0, 0.0, w, h), FRAME_OUTER)
		draw_rect(Rect2(2.0, 2.0, w - 4.0, h - 4.0), FRAME_INNER)
		# 双色描边
		draw_line(Vector2(6.0, 2.5), Vector2(w, 2.5), EDGE_HI, 1.0)
		draw_line(Vector2(2.5, 6.0), Vector2(2.5, h), EDGE_HI, 1.0)
		draw_line(Vector2(0.0, h - 2.5), Vector2(w - 6.0, h - 2.5), EDGE_LO, 1.0)
		draw_line(Vector2(w - 2.5, 6.0), Vector2(w - 2.5, h), EDGE_LO, 1.0)
		# 向下指向三角（底边中点）
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
			draw_arc(Vector2(20.0, 36.0), 5.0, 0.0, TAU, 16, Color(0.5, 0.5, 0.5, 1.0), 1.0, true)

		# 数值行
		if _is_heal:
			draw_string(fnt, Vector2(32.0, 40.0), "%s · +%d" % [_type_name, _heal_amount], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _type_color)
			# 治疗无命中/暴击行
			draw_string(fnt, Vector2(12.0, 62.0), "必定生效", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_TEXT_SUB)
			return

		if _hit_count <= 1:
			# 单段：直接显数值
			draw_string(fnt, Vector2(32.0, 40.0), "%s · %d" % [_type_name, _per_hit], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _type_color)
		else:
			# 多段：物理 3 × 12（36）— x/y 类型色、× 灰、总值金
			var x_pos: float = 32.0
			x_pos = _draw_run(fnt, x_pos, 40.0, _type_name + " ", 13, _type_color)
			x_pos = _draw_run(fnt, x_pos, 40.0, str(_hit_count), 13, _type_color)
			x_pos = _draw_run(fnt, x_pos + 3.0, 40.0, "×", 12, C_TEXT_SUB)
			x_pos = _draw_run(fnt, x_pos + 3.0, 40.0, str(_per_hit), 13, _type_color)
			x_pos = _draw_run(fnt, x_pos + 4.0, 40.0, "(%d)" % (_hit_count * _per_hit), 12, C_GOLD_BRIGHT)

		# 命中 / 暴击行
		draw_string(fnt, Vector2(12.0, 62.0), "命中 %d%%" % _hit_percent, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_TEXT_SUB)
		draw_string(fnt, Vector2(96.0, 62.0), "暴击 %d%%" % _crit_percent, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_CRIT)

	## 画一段文本并返回下一段起始 x（用于多段拼色）。
	func _draw_run(fnt: Font, x: float, y: float, text: String, fs: int, col: Color) -> float:
		draw_string(fnt, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		return x + fnt.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
