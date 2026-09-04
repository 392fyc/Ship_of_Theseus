class_name EquipmentHudPanel
extends Panel

const SlotViewData := preload("res://scripts/ui/hud/slot_view_data.gd")
const PotionViewData := preload("res://scripts/ui/hud/potion_view_data.gd")

var _weapon_view: SlotViewData = null
var _armor_view: SlotViewData = null
var _potion_view: PotionViewData = null

@onready var _weapon_slot: Button = %WeaponSlot
@onready var _armor_slot: Button = %ArmorSlot
@onready var _potion_button: Button = %PotionButton


func _ready() -> void:
	if _weapon_view != null and _armor_view != null and _potion_view != null:
		_apply_view_to_nodes()


func apply_view(weapon_view: SlotViewData, armor_view: SlotViewData,
		potion_view: PotionViewData) -> void:
	_weapon_view = weapon_view
	_armor_view = armor_view
	_potion_view = potion_view
	if is_node_ready():
		_apply_view_to_nodes()


func _apply_view_to_nodes() -> void:
	_weapon_slot.call("apply_view", _weapon_view)
	_armor_slot.call("apply_view", _armor_view)
	_potion_button.call("apply_view", _potion_view)
