class_name HudSkillShelf
extends Panel

signal skill_activated(skill_id: String)

const SkillSlotScene: PackedScene = preload("res://scenes/tactical/hud/skill_slot_button.tscn")

var _pending_skills: Array[RefCounted] = []
var _has_pending_skills: bool = false

@onready var _slots: HBoxContainer = %Slots


func _ready() -> void:
	if _has_pending_skills:
		_build_slots(_pending_skills)


func apply_skills(skills: Array[RefCounted]) -> void:
	_pending_skills = skills.duplicate()
	_has_pending_skills = true
	if is_node_ready():
		_build_slots(_pending_skills)


func get_skill_slots() -> Array:
	if not is_node_ready():
		return []
	return _slots.get_children()


func _build_slots(skills: Array[RefCounted]) -> void:
	_clear_slots()
	if skills.size() < 5 or skills.size() > 7:
		return
	var slot_extent: float = 56.0 if skills.size() == 7 else 64.0
	for view: RefCounted in skills:
		var slot: Button = SkillSlotScene.instantiate() as Button
		slot.custom_minimum_size = Vector2(slot_extent, slot_extent)
		slot.skill_activated.connect(_on_skill_activated)
		slot.call("apply_view", view)
		_slots.add_child(slot)


func _clear_slots() -> void:
	for child: Node in _slots.get_children():
		_slots.remove_child(child)
		child.queue_free()


func _on_skill_activated(skill_id: String) -> void:
	skill_activated.emit(skill_id)
