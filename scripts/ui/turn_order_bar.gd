class_name TurnOrderBar
extends PanelContainer
## Present TurnManager's current-and-remaining queue without predicting future resources.

const PLAYER_COLOR := Color("69a7dc")
const ENEMY_COLOR := Color("e48b70")
const TEXT_COLOR := Color("e0d7c5")
const MUTED_COLOR := Color("aaa596")
const USED_COLOR := Color("8d8982")
const BAR_WIDTH := 180

var _entries: VBoxContainer
var _round_label: Label
var _completed_label: Label
var _rows: Array[Dictionary] = []


func _ready() -> void:
	position = Vector2(1080.0, 10.0)
	custom_minimum_size = Vector2(float(BAR_WIDTH), 0.0)
	mouse_filter = MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("19191ded")
	style.set_border_width_all(1)
	style.border_color = Color("766344")
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", style)
	var content := VBoxContainer.new()
	content.mouse_filter = MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 5)
	add_child(content)
	content.add_child(_label("行动顺序", 14, Color("ddc99d")))
	_round_label = _label("", 11, MUTED_COLOR)
	content.add_child(_round_label)
	_entries = VBoxContainer.new()
	_entries.mouse_filter = MOUSE_FILTER_IGNORE
	_entries.add_theme_constant_override("separation", 3)
	content.add_child(_entries)
	_completed_label = _label("", 11, MUTED_COLOR)
	content.add_child(_completed_label)


func update_queue(display_queue: Array[Unit], current: Unit,
		round_number: int = 0, alive_count: int = 0) -> void:
	for child: Node in _entries.get_children():
		_entries.remove_child(child)
		child.queue_free()
	_rows.clear()
	_round_label.text = "第 %d 回合 · 剩余 %d 人" % [round_number, display_queue.size()]
	_completed_label.text = "存活单位已行动 %d 人" % maxi(0, alive_count - display_queue.size())
	for index: int in display_queue.size():
		var unit: Unit = display_queue[index]
		_entries.add_child(_create_entry(unit, unit == current, index + 1))
	reset_size()


func _create_entry(unit: Unit, is_current: bool, order: int) -> PanelContainer:
	var faction: Color = PLAYER_COLOR if unit.faction == "player" else ENEMY_COLOR
	var panel := PanelContainer.new()
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("c2a96b20") if is_current else Color("10111460")
	style.border_width_left = 2
	style.border_color = faction if is_current else faction.darkened(0.45)
	style.content_margin_left = 5.0
	style.content_margin_right = 4.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	panel.add_theme_stylebox_override("panel", style)
	var lines := VBoxContainer.new()
	lines.mouse_filter = MOUSE_FILTER_IGNORE
	lines.add_theme_constant_override("separation", 3)
	panel.add_child(lines)
	var heading := HBoxContainer.new()
	heading.mouse_filter = MOUSE_FILTER_IGNORE
	heading.add_theme_constant_override("separation", 5)
	lines.add_child(heading)
	var ordinal: Label = _label(str(order), 12, faction)
	ordinal.custom_minimum_size.x = 12.0
	heading.add_child(ordinal)
	var unit_name_label: Label = _label(unit.unit_name, 13, TEXT_COLOR)
	unit_name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	heading.add_child(unit_name_label)
	if is_current:
		heading.add_child(_label("当前", 11, Color("e4c785")))
	var speed: Label = _label("速度 %d" % unit.get_effective_stat("SPD"), 10, MUTED_COLOR)
	heading.add_child(speed)
	var resource_labels: Array[Label] = []
	var waiting_label: Label = null
	if is_current:
		var resources := HBoxContainer.new()
		resources.mouse_filter = MOUSE_FILTER_IGNORE
		resources.add_theme_constant_override("separation", 5)
		lines.add_child(resources)
		var names: Array[String] = ["移动", "标准", "迅捷"]
		var consumed: Array[bool] = [unit.movement_used, unit.standard_used, unit.swift_used]
		for index: int in names.size():
			var text: String = names[index] + ("已用" if consumed[index] else "可用")
			var resource: Label = _label(text, 10, USED_COLOR if consumed[index] else TEXT_COLOR)
			resources.add_child(resource)
			resource_labels.append(resource)
	else:
		# Waiting units retain previous-turn flags until their own turn begins.
		waiting_label = _label("等待行动", 11, MUTED_COLOR)
		lines.add_child(waiting_label)
	_rows.append({"instance_id":unit.get_instance_id(), "unit_id":unit.unit_id,
		"current":is_current, "panel":panel, "resources":resource_labels, "waiting":waiting_label})
	return panel


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text_value
	result.mouse_filter = MOUSE_FILTER_IGNORE
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result


## Read actual displayed labels for captures and state-transition tests.
func get_debug_snapshot() -> Dictionary:
	var rows: Array[Dictionary] = []
	for row: Dictionary in _rows:
		var resources: Array[String] = []
		for label: Label in row["resources"]:
			resources.append(label.text)
		var waiting: Label = row["waiting"] as Label
		rows.append({"instance_id":row["instance_id"], "unit_id":row["unit_id"],
			"current":row["current"], "resource_texts":resources,
			"waiting_text":waiting.text if waiting != null else "",
			"rect":(row["panel"] as Control).get_global_rect()})
	return {"round_text":_round_label.text, "completed_text":_completed_label.text, "units":rows}
