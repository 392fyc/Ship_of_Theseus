extends Control
## DoorSelect v0 门选择 UI（功能原型，先功能后美化）。
##
## 真源：runloop-reward-map-proposal.md §7（Hades 门模式，2-3 扇门，奖励前置预告）
##       + v0-implementation-plan.md §1。
##
## 职责：为一组门（DoorOption 数组）各建一个按钮，显示：
##   - reward_type（文字 + emoji 图标占位，美术图标后续替换）
##   - elite_room（精英房 → 骷髅标 💀）
##   - preview.special_affix（有则显示词条名，从 DataLoader.affixes 查 name）
## 点击某扇门 → emit door_chosen(index)，由宿主 RunScene 接管流转。
##
## 设计约束：纯 UI（不持有 run 状态、不结算）；信号 past-tense；数值不硬编码业务逻辑
## （图标 emoji 与文案为占位表现层，非游戏数值）。

## past-tense：玩家已选定某扇门（index 为门组内下标）。
signal door_chosen(index: int)

# [占位] reward_type → 显示文案 + emoji 图标占位。表现层占位，美术图标后续替换。
const REWARD_LABELS: Dictionary = {
	"gold": "💰 金币",
	"exp": "⭐ 经验",
	"equipment": "🗡 装备",
	"relic": "💎 遗物",
	"event": "❓ 事件",
	"boss": "☠ Boss",
}

const DOOR_BUTTON_MIN_SIZE: Vector2 = Vector2(190.0, 128.0)
const TITLE_FONT_SIZE: int = 28
const DOOR_FONT_SIZE: int = 18


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


## 用一组门填充选择界面（重建全部子节点，可多次调用）。
func populate(doors: Array) -> void:
	for child: Node in get_children():
		child.queue_free()

	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06, 0.86)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	var title: Label = Label.new()
	title.text = "选择下一扇门"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)

	for i: int in range(doors.size()):
		if not (doors[i] is Dictionary):
			continue
		row.add_child(_build_door_button(i, doors[i]))


## 组装单扇门按钮：文案含奖励类型 + 精英标 + 特殊词条预告。
func _build_door_button(index: int, door: Dictionary) -> Button:
	var reward_type: String = str(door.get("reward_type", ""))
	var lines: Array[String] = []
	lines.append("门 %d" % (index + 1))
	lines.append(str(REWARD_LABELS.get(reward_type, reward_type)))
	if bool(door.get("elite_room", false)):
		lines.append("💀 精英房")

	var preview_v: Variant = door.get("preview")
	var preview: Dictionary = preview_v if preview_v is Dictionary else {}
	var special_affix_v: Variant = preview.get("special_affix", null)
	if special_affix_v != null and str(special_affix_v) != "":
		lines.append("词条：" + _affix_name(str(special_affix_v)))

	# 事件门：显示事件占位提示（v0 事件流程为后续任务，本层仅预告）
	if reward_type == "event":
		var event_id_v: Variant = door.get("event_id", null)
		if event_id_v != null and str(event_id_v) != "":
			lines.append("(%s)" % str(event_id_v))

	var btn: Button = Button.new()
	btn.text = "\n".join(lines)
	btn.add_theme_font_size_override("font_size", DOOR_FONT_SIZE)
	btn.custom_minimum_size = DOOR_BUTTON_MIN_SIZE
	btn.clip_text = true
	btn.pressed.connect(_on_door_button_pressed.bind(index))
	return btn


func _on_door_button_pressed(index: int) -> void:
	door_chosen.emit(index)


## 词条 id → 中文名（从 DataLoader.affixes 读 name，查不到回退 id）。
func _affix_name(affix_id: String) -> String:
	var affix: Dictionary = DataLoader.affixes.get(affix_id, {})
	return str(affix.get("name", affix_id))
