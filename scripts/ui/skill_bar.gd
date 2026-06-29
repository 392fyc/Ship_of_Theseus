class_name SkillBar
extends Control

signal skill_selected(skill_id: String)

# ── v3：横排方形技能槽（屏幕底部居中常驻）──────────────────────
# 由旧「竖排弹窗卡片」重写为「横排 56px 方槽平铺」，参考 playground 槽位风格：
#   键位角标(左上) / 资源消耗(右下) / 冷却中心遮罩+回合数 / 选中金边外发光 / 不可用置灰。
# 公开 API 不变：class_name SkillBar + signal skill_selected + update_entries / set_expanded。
# 可见性不再依赖 set_expanded（B1 常驻）；set_expanded 仅作内部状态钩子保留。

const SLOT_SIZE: float = 56.0
const SLOT_LABEL_H: float = 14.0           # 槽下标题行高
const SLOT_GAP: int = 6                     # 槽间距
const ROW_PAD: int = 6                      # 容器内边距

const PANEL_BG: Color = Color(0.07, 0.05, 0.11, 0.92)
const PANEL_BORDER: Color = Color(0.30, 0.25, 0.18, 0.60)
const PANEL_GLOW: Color = Color(0.0, 0.0, 0.0, 0.30)

const C_TEXT_MAIN: Color = Color(0.90, 0.86, 0.78, 1.0)
const C_TEXT_SUB: Color = Color(0.55, 0.56, 0.60, 1.0)
const C_TEXT_DIM: Color = Color(0.36, 0.36, 0.40, 1.0)
const C_GOLD_BRIGHT: Color = Color(0.878, 0.749, 0.282, 1.0)
const C_RED: Color = Color(0.878, 0.180, 0.180, 1.0)

const COST_COLORS: Dictionary = {
	"move": Color(0.231, 0.510, 0.961, 1.0),
	"standard": Color(0.980, 0.451, 0.059, 1.0),
	"swift": Color(0.063, 0.722, 0.518, 1.0),
}

const COST_SYMBOLS: Dictionary = {
	"move": "M",
	"standard": "A",
	"swift": "S",
}

var _panel: PanelContainer = null
var _list: HBoxContainer = null
var _empty_label: Label = null
var _expanded: bool = false
var _current_entries: Array[Dictionary] = []


## v3 横排方形技能槽（自绘全状态）。
## 互斥优先级：冷却中 > 不可用 > 选中 > 常态（对齐 spec.md §5）。
class SkillSlot extends Control:
	signal pressed(skill_id: String)

	var skill_id: String = ""
	var key_text: String = ""        # 左上键位角标
	var title: String = ""
	var accent: Color = Color.WHITE  # 资源色（边框）
	var cost_text: String = ""       # 右下消耗角标
	var cooldown: int = 0
	var cooldown_max: int = 0
	var disabled: bool = false
	var selected: bool = false
	var is_passive: bool = false

	const C_SLOT_BG: Color = Color(0.067, 0.035, 0.102, 1.0)
	const C_SLOT_BG_DISABLED: Color = Color(0.051, 0.039, 0.078, 1.0)
	const C_EDGE_DISABLED: Color = Color(0.275, 0.278, 0.302, 1.0)
	const C_ICON_DISABLED: Color = Color(0.361, 0.361, 0.400, 1.0)
	const C_OVERLAY: Color = Color(0.024, 0.035, 0.055, 0.66)
	const C_SELECTED: Color = Color(0.878, 0.749, 0.282, 1.0)
	const C_QI_LOW: Color = Color(0.373, 0.659, 0.847, 1.0)
	const C_RED: Color = Color(0.878, 0.180, 0.180, 1.0)
	const C_TEXT_MAIN: Color = Color(0.902, 0.859, 0.780, 1.0)
	const C_TEXT_SUB: Color = Color(0.549, 0.561, 0.600, 1.0)

	func _ready() -> void:
		custom_minimum_size = Vector2(56.0, 56.0 + 14.0)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _gui_input(event: InputEvent) -> void:
		if disabled or cooldown > 0 or skill_id == "" or is_passive:
			return
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				pressed.emit(skill_id)

	## 自定义悬停卡片：限宽换行（避免文本横向铺满屏幕）。
	func _make_custom_tooltip(for_text: String) -> Object:
		var panel: PanelContainer = PanelContainer.new()
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0.07, 0.05, 0.11, 0.97)
		sb.border_color = Color(0.45, 0.38, 0.22, 0.70)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 9.0
		sb.content_margin_right = 9.0
		sb.content_margin_top = 7.0
		sb.content_margin_bottom = 7.0
		panel.add_theme_stylebox_override("panel", sb)
		var lbl: Label = Label.new()
		lbl.text = for_text
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size = Vector2(248.0, 0.0)
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.90, 0.86, 0.78, 1.0))
		panel.add_child(lbl)
		return panel

	func _draw() -> void:
		var s: float = 56.0
		var slot: Rect2 = Rect2(0.0, 0.0, s, s)

		var state_cooldown: bool = cooldown > 0
		var state_disabled: bool = disabled and not state_cooldown

		# 槽底
		var bg: Color = C_SLOT_BG_DISABLED if state_disabled else C_SLOT_BG
		draw_rect(slot, bg)

		# 边框（按状态）
		var edge: Color
		var edge_w: float = 1.0
		if state_disabled:
			edge = Color(C_EDGE_DISABLED, 0.5)
		elif selected:
			edge = C_SELECTED
			edge_w = 1.6
		else:
			edge = Color(accent, 0.55)
		draw_rect(slot, edge, false, edge_w)

		# 选中外发光（金描边外圈）
		if selected and not state_cooldown and not state_disabled:
			draw_rect(Rect2(-2.0, -2.0, s + 4.0, s + 4.0), Color(C_SELECTED, 0.35), false, 3.0)

		# 图标（占位字符：取 title 首字）
		var icon_col: Color = accent
		if state_cooldown:
			icon_col = Color(0.478, 0.455, 0.408, 1.0)
		elif state_disabled:
			icon_col = C_ICON_DISABLED
		elif selected:
			icon_col = Color(1.0, 0.949, 0.812, 1.0)
		_draw_icon(Vector2(s, s) * 0.5, icon_col)

		# 冷却：径向转圈（剩余比例暗扇区，自正上方顺时针）+ 中心数字（去「回合」字样）
		if state_cooldown:
			draw_rect(slot, Color(0.024, 0.035, 0.055, 0.45))
			var cd_center: Vector2 = Vector2(s * 0.5, s * 0.5)
			var cd_radius: float = s * 0.5 - 1.0
			var cd_frac: float = clampf(float(cooldown) / maxf(float(cooldown_max), 1.0), 0.0, 1.0)
			if cd_frac > 0.0:
				var fan: PackedVector2Array = PackedVector2Array([cd_center])
				var seg: int = maxi(2, int(ceil(cd_frac * 40.0)))
				for k: int in range(seg + 1):
					var a: float = -PI * 0.5 + TAU * cd_frac * (float(k) / float(seg))
					fan.append(cd_center + Vector2(cos(a), sin(a)) * cd_radius)
				draw_colored_polygon(fan, Color(0.016, 0.024, 0.043, 0.82))
			draw_arc(cd_center, cd_radius, 0.0, TAU, 32, Color(accent, 0.5), 1.0, true)
			var ctxt: String = str(cooldown)
			var fnt: Font = ThemeDB.fallback_font
			var fs: int = 22
			var tw: float = fnt.get_string_size(ctxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var tp: Vector2 = Vector2(s * 0.5 - tw * 0.5, s * 0.5 + float(fs) * 0.36)
			for off: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				draw_string(fnt, tp + off, ctxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.9))
			draw_string(fnt, tp, ctxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.95, 0.85, 1.0))

		# 左上键位角标
		if key_text != "":
			var key_edge: Color = Color(accent, 0.6)
			if state_disabled:
				key_edge = Color(C_EDGE_DISABLED, 0.5)
			var key_col: Color = C_TEXT_MAIN if not state_disabled else Color(0.361, 0.361, 0.400, 1.0)
			_draw_badge(Rect2(0.0, 0.0, 14.0, 13.0), key_edge, key_text, 9, key_col)

		# 右下消耗角标
		if cost_text != "" and not state_cooldown:
			var cost_col: Color = C_QI_LOW
			if state_disabled:
				cost_col = C_RED
			_draw_cost_badge(s, cost_text, cost_col)

		# 标题行
		var title_col: Color = C_TEXT_SUB
		if selected:
			title_col = C_SELECTED
		elif state_disabled or state_cooldown:
			title_col = Color(0.451, 0.459, 0.498, 1.0)
		_draw_title(s, title, title_col)

	func _draw_icon(c: Vector2, col: Color) -> void:
		# 占位图标：title 首字符（缺真图标，见 receipt 人工核验清单）
		var ch: String = title.left(1) if title != "" else "技"
		var fnt: Font = ThemeDB.fallback_font
		var fs: int = 18
		var tw: float = fnt.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(fnt, Vector2(c.x - tw * 0.5, c.y + 6.0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

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


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# B1 常驻：可见性不再依赖 set_expanded，默认隐藏（无条目时），有条目时显示。
	visible = false
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	_build_ui()


func update_entries(entries: Array[Dictionary], selected_skill_id: String) -> void:
	_current_entries = entries.duplicate(true)
	for child: Node in _list.get_children():
		if child == _empty_label:
			continue
		child.queue_free()

	if _current_entries.is_empty():
		_empty_label.visible = true
		_refresh_size()
		return

	_empty_label.visible = false
	# 键位 1-4 仅分配给「主动」技能（被动如心眼不占键位）。
	var active_idx: int = 0
	for i: int in range(_current_entries.size()):
		var entry: Dictionary = _current_entries[i]
		if not bool(entry.get("is_passive", false)):
			if active_idx < 4 and not entry.has("hotkey"):
				entry["hotkey"] = str(active_idx + 1)
			active_idx += 1
		_list.add_child(_build_skill_slot(entry, selected_skill_id, i))
	_refresh_size()


## set_expanded：B1 后语义改为「玩家行动阶段可见」开关——bottom_dashboard 在
## 玩家回合传 true、敌方/非行动态传 false（与 show_skills 一致），实现常驻可见。
## 公开 API 签名保持不变。
func set_expanded(expanded: bool) -> void:
	_expanded = expanded
	visible = expanded


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", ROW_PAD)
	margin.add_theme_constant_override("margin_right", ROW_PAD)
	margin.add_theme_constant_override("margin_top", ROW_PAD)
	margin.add_theme_constant_override("margin_bottom", ROW_PAD)
	_panel.add_child(margin)

	# 横排技能槽（居中对齐）
	_list = HBoxContainer.new()
	_list.alignment = BoxContainer.ALIGNMENT_CENTER
	_list.add_theme_constant_override("separation", SLOT_GAP)
	margin.add_child(_list)

	_empty_label = Label.new()
	_empty_label.visible = false
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.custom_minimum_size = Vector2(SLOT_SIZE * 2.0, SLOT_SIZE)
	_empty_label.text = "当前没有可展示的技能。"
	_empty_label.add_theme_font_size_override("font_size", 10)
	_empty_label.add_theme_color_override("font_color", C_TEXT_DIM)
	_list.add_child(_empty_label)


func _build_skill_slot(entry: Dictionary, selected_skill_id: String, _index: int) -> Control:
	var skill_id: String = str(entry.get("skill_id", ""))
	var skill_name: String = str(entry.get("name", skill_id))
	var action_cost: String = str(entry.get("action_cost", "standard"))
	var cooldown_turns: int = int(entry.get("cooldown", 0))
	var available: bool = bool(entry.get("available", false))
	var is_passive: bool = bool(entry.get("is_passive", false))
	# 键位角标：主动技能由 update_entries 注入 1-4；被动显 "P" 标记。
	var hotkey: String = str(entry.get("hotkey", "")) if entry.has("hotkey") else ""
	if is_passive:
		hotkey = "P"
	var cost_text: String = _build_cost_text(entry, action_cost)
	var accent: Color = _get_cost_color(action_cost)

	var slot: SkillSlot = SkillSlot.new()
	slot.skill_id = skill_id
	slot.key_text = hotkey
	slot.title = skill_name
	slot.accent = accent
	slot.cost_text = cost_text
	slot.cooldown = cooldown_turns
	slot.cooldown_max = int(entry.get("cooldown_max", cooldown_turns))
	slot.is_passive = is_passive
	slot.disabled = (not available or skill_id == "") and not is_passive
	slot.selected = skill_id == selected_skill_id and skill_id != "" and not is_passive
	slot.tooltip_text = _compose_tooltip(entry, available, is_passive)
	slot.pressed.connect(_on_slot_pressed)
	return slot


## 悬停介绍：无论技能是否可用都显示「技能名 + 描述」；不可用时附原因。
func _compose_tooltip(entry: Dictionary, available: bool, is_passive: bool) -> String:
	var parts: PackedStringArray = []
	var nm: String = str(entry.get("name", ""))
	if nm != "":
		parts.append("【%s】%s" % [nm, "（被动）" if is_passive else ""])
	var desc: String = str(entry.get("description", ""))
	if desc != "":
		parts.append(desc)
	if not is_passive and not available:
		var reason: String = str(entry.get("reason", ""))
		if reason != "":
			parts.append("✗ " + reason)
	return "\n".join(parts)


func _refresh_size() -> void:
	# 让面板贴合内容（横排槽数 × 槽宽）；外层定位由 bottom_dashboard 居中处理。
	var slot_count: int = maxi(_current_entries.size(), 1)
	var inner_w: float = float(slot_count) * SLOT_SIZE + float(slot_count - 1) * float(SLOT_GAP)
	var w: float = inner_w + float(ROW_PAD) * 2.0
	var h: float = SLOT_SIZE + SLOT_LABEL_H + float(ROW_PAD) * 2.0
	custom_minimum_size = Vector2(w, h)
	size = Vector2(w, h)


## 右下消耗角标文本：优先剑气/印记消耗（从 state 读，不硬编码数值），
## 都为 0 时回退动作资源符号（A/M/S）。
func _build_cost_text(entry: Dictionary, action_cost: String) -> String:
	if entry.has("cost_text"):
		return str(entry["cost_text"])
	var qi_cost: int = int(entry.get("qi_cost", 0))
	var mark_cost: int = int(entry.get("mark_cost", 0))
	var parts: PackedStringArray = []
	if mark_cost > 0:
		parts.append("%d印" % mark_cost)
	if qi_cost > 0:
		parts.append("%d气" % qi_cost)
	if not parts.is_empty():
		return "+".join(parts)
	return str(COST_SYMBOLS.get(action_cost, ""))


func _get_cost_color(action_cost: String) -> Color:
	if COST_COLORS.has(action_cost):
		return COST_COLORS[action_cost]
	return Color(0.80, 0.66, 0.34, 1.0)


func _make_panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.shadow_color = PANEL_GLOW
	style.shadow_size = 8
	return style


func _on_slot_pressed(skill_id: String) -> void:
	skill_selected.emit(skill_id)
