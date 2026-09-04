extends Control

const LOGICAL_SIZE: Vector2 = Vector2(1280.0, 720.0)
const KENSEI_PROFILE_PATH: String = "res://data/visual_profiles/kensei_map_token.json"

const CharacterViewData := preload("res://scripts/ui/hud/character_hud_view_data.gd")
const ValueMeterViewData := preload("res://scripts/ui/hud/value_meter_view_data.gd")
const SkillViewData := preload("res://scripts/ui/hud/skill_slot_view_data.gd")
const ActionViewData := preload("res://scripts/ui/hud/action_resource_view_data.gd")
const SlotViewData := preload("res://scripts/ui/hud/slot_view_data.gd")
const PotionViewData := preload("res://scripts/ui/hud/potion_view_data.gd")
const EndViewData := preload("res://scripts/ui/hud/end_turn_view_data.gd")

var _skill_count: int = 5
var _output_size: Vector2i = Vector2i(1280, 720)
var _output_scale: float = 1.0

@onready var _design_root: Control = %DesignRoot
@onready var _board: Control = %DiamondBoardStress
@onready var _token: Sprite2D = %KenseiScaleAnchor
@onready var _composition: Control = %BottomHudComposition


func _ready() -> void:
	_configure_token()
	_apply_output_geometry()
	_apply_mock_views()


func configure(skill_count: int, output_size: Vector2i) -> void:
	_skill_count = skill_count
	_output_size = output_size
	custom_minimum_size = Vector2(output_size)
	size = Vector2(output_size)
	if is_node_ready():
		_apply_output_geometry()
		_apply_mock_views()


func get_output_scale() -> float:
	return _output_scale


func get_skill_count() -> int:
	return _skill_count


func _apply_output_geometry() -> void:
	_output_scale = minf(float(_output_size.x) / LOGICAL_SIZE.x,
		float(_output_size.y) / LOGICAL_SIZE.y)
	_design_root.scale = Vector2(_output_scale, _output_scale)


func _configure_token() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(KENSEI_PROFILE_PATH))
	if not (parsed is Dictionary):
		push_error("[HudBottomCompositionGallery] Invalid kensei visual profile")
		return
	if not bool(_token.call("configure", parsed as Dictionary)):
		push_error("[HudBottomCompositionGallery] Kensei scale anchor rejected profile")
		return
	_token.call("set_visual_state", &"SE", false)
	_token.position = _board.call("get_tile_center", 10, 10)


func _apply_mock_views() -> void:
	_composition.call("apply_character", _make_character_view())
	_composition.call("apply_skills", _make_skill_views(_skill_count))
	_composition.call("apply_action_resources", _make_action_view())
	_composition.call("apply_equipment", _make_slot_view("weapon"),
		_make_slot_view("armor"), _make_potion_view())
	var empty_relics: Array[RefCounted] = []
	_composition.call("apply_relics", empty_relics)
	_composition.call("apply_end_action", _make_end_view())


func _make_character_view() -> RefCounted:
	var view: RefCounted = CharacterViewData.new()
	view.set("profession_name", "剑圣")
	view.set("player_name", "fyc")
	view.set("level", 12)
	view.set("experience", _make_meter(125, 500))
	view.set("hp", _make_meter(78, 120))
	view.set("shield", _make_meter(14, 40))
	view.set("portrait_fallback_text", "剑")
	return view


func _make_meter(current_value: int, maximum_value: int) -> RefCounted:
	var view: RefCounted = ValueMeterViewData.new()
	view.set("current_value", current_value)
	view.set("maximum_value", maximum_value)
	return view


func _make_skill_views(count: int) -> Array[RefCounted]:
	var views: Array[RefCounted] = []
	for index: int in count:
		var view: RefCounted = SkillViewData.new()
		view.set("skill_id", "mock_skill_%d" % (index + 1))
		view.set("hotkey_text", str(index + 1))
		view.set("enabled", true)
		view.set("selected", index == 0)
		view.set("cooldown_turns", 2 if index == maxi(count - 2, 0) else 0)
		view.set("charges", 2)
		view.set("show_charges", index == count - 1)
		view.set("passive", index == count - 1)
		view.set("active_capable", true)
		view.set("tooltip_text", "mock-only skill %d" % (index + 1))
		views.append(view)
	return views


func _make_action_view() -> RefCounted:
	var view: RefCounted = ActionViewData.new()
	view.set("movement_remaining", 6)
	view.set("movement_available", true)
	view.set("standard_capacity", 1)
	view.set("standard_remaining", 1)
	view.set("swift_capacity", 1)
	view.set("swift_remaining", 1)
	return view


func _make_slot_view(slot_id: String) -> RefCounted:
	var view: RefCounted = SlotViewData.new()
	view.set("slot_id", slot_id)
	view.set("content_id", "")
	view.set("occupied", false)
	view.set("enabled", true)
	view.set("tooltip_text", "mock-only empty %s" % slot_id)
	return view


func _make_potion_view() -> RefCounted:
	var view: RefCounted = PotionViewData.new()
	view.set("content_id", "mock_shared_potion")
	view.set("enabled", true)
	view.set("tooltip_text", "mock-only universal potion")
	return view


func _make_end_view() -> RefCounted:
	var view: RefCounted = EndViewData.new()
	view.set("action_kind", &"end_turn")
	view.set("visible", true)
	view.set("enabled", true)
	view.set("tooltip_text", "结束本回合")
	return view
