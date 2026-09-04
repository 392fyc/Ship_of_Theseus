extends Control

const SkillSlotScene: PackedScene = preload("res://scenes/tactical/hud/skill_slot_button.tscn")
const SkillSlotViewData := preload("res://scripts/ui/hud/skill_slot_view_data.gd")
const ActionResourceScene: PackedScene = preload("res://scenes/tactical/hud/action_resource_strip.tscn")
const ActionResourceViewData := preload("res://scripts/ui/hud/action_resource_view_data.gd")

var _built: bool = false
var _reference_size: Vector2i = Vector2i(1280, 720)


func _ready() -> void:
	_build_once()
	set_reference_size(_reference_size)


func set_reference_size(reference_size: Vector2i) -> void:
	_reference_size = reference_size
	custom_minimum_size = Vector2(reference_size)
	size = Vector2(reference_size)


func get_reference_size() -> Vector2i:
	return _reference_size


func _build_once() -> void:
	if _built:
		return
	_built = true
	_populate_skill_board($SafeArea/Layout/Content/SkillColumn/SkillCount5/Slots,
		5, Vector2(64.0, 64.0))
	_populate_skill_board($SafeArea/Layout/Content/SkillColumn/SkillCount6/Slots,
		6, Vector2(64.0, 64.0))
	_populate_skill_board($SafeArea/Layout/Content/SkillColumn/SkillCount7/Slots,
		7, Vector2(56.0, 56.0))
	_populate_resource_board(%ActionCapacity1, 6, true, 1, 1, 1, 1)
	_populate_resource_board(%ActionCapacity2, 6, true, 2, 1, 2, 1)
	_populate_resource_board(%ActionCapacity3, 6, true, 3, 2, 3, 0)
	_populate_resource_board(%ActionMovementDisabled, 8, false, 1, 1, 1, 1)


func _populate_skill_board(slots: HBoxContainer, count: int,
		slot_size: Vector2) -> void:
	for index: int in count:
		var slot: Button = SkillSlotScene.instantiate() as Button
		slot.name = "SkillSlot%d" % (index + 1)
		slot.custom_minimum_size = slot_size
		var view: SkillSlotViewData = SkillSlotViewData.new()
		view.skill_id = "gallery_skill_%d_%d" % [count, index + 1]
		view.hotkey_text = str(index + 1)
		view.enabled = true
		view.selected = index == 0
		view.cooldown_turns = 2 if index == count - 2 else 0
		view.charges = 2
		view.show_charges = index == count - 1
		view.passive = index == count - 1
		view.active_capable = true
		slot.call("apply_view", view)
		slots.add_child(slot)


func _populate_resource_board(board: VBoxContainer, movement: int,
		movement_available: bool, standard_capacity: int, standard_remaining: int,
		swift_capacity: int, swift_remaining: int) -> void:
	var strip: Control = ActionResourceScene.instantiate() as Control
	strip.name = "ActionResourceStrip"
	var view: ActionResourceViewData = ActionResourceViewData.new()
	view.movement_remaining = movement
	view.movement_available = movement_available
	view.standard_capacity = standard_capacity
	view.standard_remaining = standard_remaining
	view.swift_capacity = swift_capacity
	view.swift_remaining = swift_remaining
	strip.call("apply_view", view)
	board.add_child(strip)
