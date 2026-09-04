extends Control

const EquipmentScene: PackedScene = preload(
	"res://scenes/tactical/hud/equipment_hud_panel.tscn")
const RelicScene: PackedScene = preload(
	"res://scenes/tactical/hud/relic_grid.tscn")
const EndTurnScene: PackedScene = preload(
	"res://scenes/tactical/hud/end_turn_control.tscn")
const SlotViewData := preload("res://scripts/ui/hud/slot_view_data.gd")
const PotionViewData := preload("res://scripts/ui/hud/potion_view_data.gd")
const EndTurnViewData := preload("res://scripts/ui/hud/end_turn_view_data.gd")

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
	_build_empty_state($SafeArea/Layout/Content/States/EmptyState/Components)
	_build_occupied_state($SafeArea/Layout/Content/States/OccupiedState/Components)
	_build_disabled_state($SafeArea/Layout/Content/States/DisabledState/Components)


func _build_empty_state(parent: HBoxContainer) -> void:
	_add_equipment(parent, _make_slot("weapon"), _make_slot("armor"),
		_make_potion())
	_add_relic_grid(parent, [])
	_add_end_control(parent, EndTurnViewData.ACTION_END_TURN, true, "结束回合")


func _build_occupied_state(parent: HBoxContainer) -> void:
	_add_equipment(parent,
		_make_slot("weapon", true, true, "mock-only：武器", Color(0.55, 0.24, 0.18)),
		_make_slot("armor", true, true, "mock-only：防具", Color(0.22, 0.38, 0.48)),
		_make_potion(true, "mock-only：全职业血瓶", Color(0.58, 0.12, 0.16)))
	var relic_views: Array[RefCounted] = []
	for index: int in 3:
		relic_views.append(_make_slot("visual_relic_%d" % index, true, true,
			"mock-only：遗物 %d" % (index + 1),
			Color(0.44 + index * 0.06, 0.28, 0.12 + index * 0.05)))
	_add_relic_grid(parent, relic_views)
	_add_end_control(parent, EndTurnViewData.ACTION_END_MOVE, true, "结束移动")


func _build_disabled_state(parent: HBoxContainer) -> void:
	_add_equipment(parent,
		_make_slot("weapon", true, false, "mock-only：武器不可用", Color(0.28, 0.28, 0.3)),
		_make_slot("armor", true, false, "mock-only：防具不可用", Color(0.25, 0.3, 0.32)),
		_make_potion(false, "mock-only：血瓶不可用", Color(0.32, 0.18, 0.2)))
	var relic_views: Array[RefCounted] = []
	for index: int in 8:
		relic_views.append(_make_slot("visual_relic_%d" % index, false, false))
	_add_relic_grid(parent, relic_views)
	_add_end_control(parent, EndTurnViewData.ACTION_END_TURN, false, "当前不可结束")


func _add_equipment(parent: HBoxContainer, weapon_view: RefCounted,
		armor_view: RefCounted, potion_view: RefCounted) -> void:
	var equipment: Control = EquipmentScene.instantiate() as Control
	equipment.name = "EquipmentHudPanel"
	equipment.call("apply_view", weapon_view, armor_view, potion_view)
	parent.add_child(equipment)


func _add_relic_grid(parent: HBoxContainer, slot_views: Array[RefCounted]) -> void:
	var relic_grid: Control = RelicScene.instantiate() as Control
	relic_grid.name = "RelicGrid"
	relic_grid.call("apply_slots", slot_views)
	parent.add_child(relic_grid)


func _add_end_control(parent: HBoxContainer, action_kind: StringName,
		enabled: bool, tooltip_text: String) -> void:
	var end_control: Control = EndTurnScene.instantiate() as Control
	end_control.name = "EndTurnControl"
	var view: RefCounted = EndTurnViewData.new()
	view.set("action_kind", action_kind)
	view.set("enabled", enabled)
	view.set("tooltip_text", tooltip_text)
	end_control.call("apply_view", view)
	parent.add_child(end_control)


func _make_slot(slot_id: String, occupied: bool = false, enabled: bool = true,
		tooltip_text: String = "", icon_color: Color = Color.TRANSPARENT) -> RefCounted:
	var view: RefCounted = SlotViewData.new()
	view.set("slot_id", slot_id)
	view.set("content_id", "mock_%s" % slot_id if occupied else "")
	view.set("occupied", occupied)
	view.set("enabled", enabled)
	view.set("tooltip_text", tooltip_text)
	if occupied:
		view.set("icon_texture", _make_mock_texture(icon_color))
	return view


func _make_potion(enabled: bool = true, tooltip_text: String = "",
		icon_color: Color = Color.TRANSPARENT) -> RefCounted:
	var view: RefCounted = PotionViewData.new()
	view.set("content_id", "mock_shared_potion" if tooltip_text != "" else "")
	view.set("enabled", enabled)
	view.set("tooltip_text", tooltip_text)
	if icon_color != Color.TRANSPARENT:
		view.set("icon_texture", _make_mock_texture(icon_color))
	return view


func _make_mock_texture(color: Color) -> Texture2D:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(color)
	for coordinate: int in 8:
		image.set_pixel(coordinate, coordinate, color.lightened(0.28))
		image.set_pixel(7 - coordinate, coordinate, color.darkened(0.28))
	return ImageTexture.create_from_image(image)
