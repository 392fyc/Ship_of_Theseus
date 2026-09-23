class_name HudM2SkillShelf
extends "res://scripts/ui/hud/skill_shelf.gd"

const M2SlotScene: PackedScene = preload("res://scenes/tactical/hud/m2/skill_slot_button.tscn")
var _layout_skill_count: int = 0
var _inspection_obstacles: Array[Rect2] = []
@export var shortcut_input_enabled: bool = true


func set_layout_skill_count(count: int) -> void:
	_layout_skill_count = count if count >= 0 and count <= 7 else 0
	if is_node_ready() and _has_pending_skills:
		_reconcile_slots(_pending_skills)


func set_shortcut_input_enabled(enabled: bool) -> void:
	shortcut_input_enabled = enabled


func set_inspection_obstacles(rectangles: Array[Rect2]) -> void:
	_inspection_obstacles = rectangles.duplicate()
	if is_node_ready():
		for slot: Control in get_skill_slots():
			slot.set_inspection_obstacles(_inspection_obstacles)


func apply_skills(skills: Array[RefCounted]) -> void:
	_pending_skills = skills.duplicate()
	_has_pending_skills = true
	if is_node_ready():
		_reconcile_slots(_pending_skills)


func _build_slots(skills: Array[RefCounted]) -> void:
	_reconcile_slots(skills)


func _reconcile_slots(skills: Array[RefCounted]) -> void:
	if skills.size() > 7:
		return
	var count: int = skills.size()
	var slot_extent: float = 56.0 if count == 7 else 64.0
	while _slots.get_child_count() > count:
		var obsolete: Node = _slots.get_child(_slots.get_child_count() - 1)
		_slots.remove_child(obsolete)
		obsolete.queue_free()
	for index: int in count:
		var view: RefCounted = skills[index]
		var slot: Button
		if index < _slots.get_child_count():
			slot = _slots.get_child(index) as Button
		else:
			slot = M2SlotScene.instantiate() as Button
			slot.theme = null
			slot.skill_activated.connect(_on_skill_activated)
			_slots.add_child(slot)
		slot.custom_minimum_size = Vector2(slot_extent, slot_extent)
		# 说明卡位于技能架上方的行动条之外，保留 8px 间隔。
		slot.inspection_clearance = (size.y - slot_extent) * 0.5 + 54.0
		slot.set_inspection_obstacles(_inspection_obstacles)
		slot.call("apply_view", view)


func _unhandled_key_input(event: InputEvent) -> void:
	if not shortcut_input_enabled or not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	var key: InputEventKey = event as InputEventKey
	if key.alt_pressed or key.ctrl_pressed or key.meta_pressed:
		return
	var key_text: String = OS.get_keycode_string(key.keycode)
	for index: int in _pending_skills.size():
		var view: RefCounted = _pending_skills[index]
		if view.active_capable and view.hotkey_text == key_text and index < _slots.get_child_count():
			_slots.get_child(index).call("activate_shortcut")
			get_viewport().set_input_as_handled()
			return
