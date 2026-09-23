class_name RelicGrid
extends Panel

const SlotViewData := preload("res://scripts/ui/hud/slot_view_data.gd")
const _VISUAL_SLOT_COUNT: int = 8

var _slot_views: Array[RefCounted] = []

@onready var _visual_grid: GridContainer = %VisualGrid


func _ready() -> void:
	_apply_slots_to_nodes()


func apply_slots(slot_views: Array[RefCounted]) -> void:
	_slot_views.clear()
	for index: int in mini(slot_views.size(), _VISUAL_SLOT_COUNT):
		_slot_views.append(slot_views[index])
	if is_node_ready():
		_apply_slots_to_nodes()


func _apply_slots_to_nodes() -> void:
	var slots: Array[Node] = _visual_grid.get_children()
	for index: int in slots.size():
		var view: SlotViewData = _view_for_slot(index)
		slots[index].call("apply_view", view)


func _view_for_slot(index: int) -> SlotViewData:
	if index < _slot_views.size() and _slot_views[index] is SlotViewData:
		return _slot_views[index] as SlotViewData
	return SlotViewData.new()
