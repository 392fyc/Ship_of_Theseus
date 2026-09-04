class_name HudBottomComposition
extends Control

signal skill_activated(skill_id: String)
signal slot_requested(slot_id: String, content_id: String)
signal potion_requested
signal end_turn_requested
signal end_move_requested

@onready var _character_panel: Control = %CharacterHudPanel
@onready var _equipment_panel: Control = %EquipmentHudPanel
@onready var _skill_shelf: Control = %SkillShelf
@onready var _relic_grid: Control = %RelicGrid
@onready var _end_turn_control: Control = %EndTurnControl
@onready var _action_resource_strip: Control = %ActionResourceStrip


func _ready() -> void:
	_skill_shelf.connect("skill_activated", _on_skill_activated)
	_end_turn_control.connect("end_turn_requested", _on_end_turn_requested)
	_end_turn_control.connect("end_move_requested", _on_end_move_requested)
	var weapon_slot: Button = _equipment_panel.get_node("WeaponSlot") as Button
	var armor_slot: Button = _equipment_panel.get_node("ArmorSlot") as Button
	var potion_button: Button = _equipment_panel.get_node("PotionButton") as Button
	weapon_slot.connect("slot_requested", _on_slot_requested)
	armor_slot.connect("slot_requested", _on_slot_requested)
	potion_button.connect("potion_requested", _on_potion_requested)
	for slot: Node in _relic_grid.get_node("VisualGrid").get_children():
		slot.connect("slot_requested", _on_slot_requested)


func apply_character(view: RefCounted) -> void:
	_character_panel.call("apply_view", view)


func apply_equipment(weapon_view: RefCounted, armor_view: RefCounted,
		potion_view: RefCounted) -> void:
	_equipment_panel.call("apply_view", weapon_view, armor_view, potion_view)


func apply_skills(skills: Array[RefCounted]) -> void:
	_skill_shelf.call("apply_skills", skills)


func apply_relics(relics: Array[RefCounted]) -> void:
	_relic_grid.call("apply_slots", relics)


func apply_action_resources(view: RefCounted) -> void:
	_action_resource_strip.call("apply_view", view)


func apply_end_action(view: RefCounted) -> void:
	_end_turn_control.call("apply_view", view)


func _on_skill_activated(skill_id: String) -> void:
	skill_activated.emit(skill_id)


func _on_slot_requested(slot_id: String, content_id: String) -> void:
	slot_requested.emit(slot_id, content_id)


func _on_potion_requested() -> void:
	potion_requested.emit()


func _on_end_turn_requested() -> void:
	end_turn_requested.emit()


func _on_end_move_requested() -> void:
	end_move_requested.emit()
