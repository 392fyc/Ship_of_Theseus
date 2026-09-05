class_name SkillBar
extends Control

signal skill_selected(skill_id: String)

const SkillShelfScene: PackedScene = preload("res://scenes/tactical/hud/skill_shelf.tscn")
const ProductionSlotScene: PackedScene = preload("res://scenes/tactical/production/skill_slot.tscn")
const SkillViewData := preload("res://scripts/ui/hud/skill_slot_view_data.gd")
const SHELF_SIZE := Vector2(476.0, 108.0)
const SLOT_GAP: int = 8
const COST_COLORS: Dictionary = {
	"move": Color(0.231, 0.510, 0.961, 1.0),
	"standard": Color(0.980, 0.451, 0.059, 1.0),
	"swift": Color(0.063, 0.722, 0.518, 1.0),
}
const COST_SYMBOLS: Dictionary = {"move": "M", "standard": "A", "swift": "S"}

var _panel: Control = null
var _list: HBoxContainer = null
var _empty_label: Label = null
var _expanded: bool = false
var _current_entries: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_panel = SkillShelfScene.instantiate() as Control
	add_child(_panel)
	_list = _panel.get_node("SlotsCenter/Slots") as HBoxContainer
	_empty_label = Label.new()
	_empty_label.text = "当前没有可展示的技能。"
	_empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.add_theme_font_size_override("font_size", 12)
	_panel.add_child(_empty_label)
	_empty_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_refresh_size()


func update_entries(entries: Array[Dictionary], selected_skill_id: String) -> void:
	_current_entries = entries.duplicate(true)
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_empty_label.visible = _current_entries.is_empty()
	_list.visible = not _current_entries.is_empty()
	var active_index: int = 0
	var extent: float = 56.0 if _current_entries.size() >= 7 else 64.0
	for entry: Dictionary in _current_entries:
		var is_passive: bool = bool(entry.get("is_passive", false))
		var view: RefCounted = SkillViewData.new()
		view.skill_id = str(entry.get("skill_id", ""))
		view.passive = is_passive
		view.active_capable = not is_passive
		view.enabled = bool(entry.get("available", false))
		view.selected = view.skill_id == selected_skill_id and view.skill_id != "" and not is_passive
		view.cooldown_turns = maxi(int(entry.get("cooldown", 0)), 0)
		view.tooltip_text = _compose_tooltip(entry, view.enabled, is_passive)
		if not is_passive:
			if active_index < 4:
				view.hotkey_text = str(active_index + 1)
			active_index += 1
		var action_cost: String = str(entry.get("action_cost", "standard"))
		var slot: Button = ProductionSlotScene.instantiate() as Button
		slot.custom_minimum_size = Vector2(extent, extent)
		slot.call("configure_entry", entry, view, _build_cost_text(entry, action_cost), _get_cost_color(action_cost))
		slot.skill_activated.connect(_on_slot_pressed)
		_list.add_child(slot)
	_refresh_size()


## 保持公开入口：只控制玩家行动阶段的技能栏可见性。
func set_expanded(expanded: bool) -> void:
	_expanded = expanded
	visible = expanded


func _refresh_size() -> void:
	var width: float = SHELF_SIZE.x
	if _current_entries.size() > 7:
		width = 56.0 * _current_entries.size() + SLOT_GAP * (_current_entries.size() - 1) + 36.0
	custom_minimum_size = Vector2(width, SHELF_SIZE.y)
	size = custom_minimum_size
	_panel.custom_minimum_size = custom_minimum_size
	_panel.size = custom_minimum_size


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


func _build_cost_text(entry: Dictionary, action_cost: String) -> String:
	if entry.has("cost_text"):
		return str(entry["cost_text"])
	var qi_cost: int = int(entry.get("qi_cost", 0))
	var mark_cost: int = int(entry.get("mark_cost", 0))
	var parts: PackedStringArray = []
	if mark_cost > 0:
		parts.append(str(mark_cost))
	if qi_cost > 0:
		parts.append(str(qi_cost))
	if not parts.is_empty():
		return "+".join(parts)
	return str(COST_SYMBOLS.get(action_cost, ""))


func _get_cost_color(action_cost: String) -> Color:
	if COST_COLORS.has(action_cost):
		return COST_COLORS[action_cost]
	return Color(0.80, 0.66, 0.34, 1.0)


func _on_slot_pressed(skill_id: String) -> void:
	skill_selected.emit(skill_id)
