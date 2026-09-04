extends Control

const OUTPUT_SIZE: Vector2i = Vector2i(1280, 720)
const STATE_READY: StringName = &"capacity_1_ready_zero_shield"
const STATE_EARLY_LOCK: StringName = &"capacity_2_early_move_lock_long_values"
const STATE_EXHAUSTED: StringName = &"capacity_3_move_exhausted"
const STATE_IDS: Array[StringName] = [STATE_READY, STATE_EARLY_LOCK, STATE_EXHAUSTED]
const MOCK_COOLDOWN_COLOR: Color = Color(0.18, 0.64, 0.92, 1.0)

const CharacterViewData := preload("res://scripts/ui/hud/character_hud_view_data.gd")
const ValueMeterViewData := preload("res://scripts/ui/hud/value_meter_view_data.gd")
const SkillViewData := preload("res://scripts/ui/hud/skill_slot_view_data.gd")
const ActionViewData := preload("res://scripts/ui/hud/action_resource_view_data.gd")
const SlotViewData := preload("res://scripts/ui/hud/slot_view_data.gd")
const PotionViewData := preload("res://scripts/ui/hud/potion_view_data.gd")
const EndViewData := preload("res://scripts/ui/hud/end_turn_view_data.gd")

var _state_id: StringName = STATE_READY

@onready var _base_gallery: Control = %BaseGallery
@onready var _composition: Control = _base_gallery.get_node(
	"DesignRoot/BottomHudComposition") as Control


func _ready() -> void:
	_base_gallery.call("configure", 5, OUTPUT_SIZE)
	_apply_state()


func configure_state(state_id: StringName) -> void:
	if state_id not in STATE_IDS:
		push_error("[HudBottomDynamicStatesGallery] Unknown state: %s" % state_id)
		return
	_state_id = state_id
	if is_node_ready():
		_apply_state()


func get_state_id() -> StringName:
	return _state_id


func get_state_ids() -> Array[StringName]:
	return STATE_IDS.duplicate()


func _apply_state() -> void:
	match _state_id:
		STATE_EARLY_LOCK:
			_apply_early_lock_state()
		STATE_EXHAUSTED:
			_apply_exhausted_state()
		_:
			_apply_ready_state()
	_apply_empty_utility_content()


func _apply_ready_state() -> void:
	_composition.call("apply_character", _make_character(
		"剑圣", "fyc", 12, 125, 500, 78, 120, 0, 40, "剑"))
	_composition.call("apply_action_resources", _make_action(6, true, 1, 1, 1, 1))
	_composition.call("apply_skills", _make_skills(false, 0, false))


func _apply_early_lock_state() -> void:
	_composition.call("apply_character", _make_character(
		"流浪剑术宗师长职业名", "玩家自定义超长名称用于验证截断", 999,
		999999, 999999, 999999, 999999, 999999, 999999, "流"))
	_composition.call("apply_action_resources", _make_action(7, false, 2, 1, 2, 0))
	_composition.call("apply_skills", _make_skills(true, 2, true))


func _apply_exhausted_state() -> void:
	_composition.call("apply_character", _make_character(
		"剑士", "归航者", 20, 450, 1000, 34, 100, 12, 40, "剑"))
	_composition.call("apply_action_resources", _make_action(0, false, 3, 2, 3, 1))
	_composition.call("apply_skills", _make_skills(true, 0, false))


func _apply_empty_utility_content() -> void:
	_composition.call("apply_equipment", _make_slot("weapon"), _make_slot("armor"),
		_make_potion())
	var empty_relics: Array[RefCounted] = []
	_composition.call("apply_relics", empty_relics)
	_composition.call("apply_end_action", _make_end_view())


func _make_character(profession_name: String, player_name: String, level: int,
		experience_current: int, experience_maximum: int,
		hp_current: int, hp_maximum: int,
		shield_current: int, shield_maximum: int,
		portrait_fallback_text: String) -> RefCounted:
	var view: RefCounted = CharacterViewData.new()
	view.set("profession_name", profession_name)
	view.set("player_name", player_name)
	view.set("level", level)
	view.set("experience", _make_meter(experience_current, experience_maximum))
	view.set("hp", _make_meter(hp_current, hp_maximum))
	view.set("shield", _make_meter(shield_current, shield_maximum))
	view.set("portrait_fallback_text", portrait_fallback_text)
	return view


func _make_meter(current_value: int, maximum_value: int) -> RefCounted:
	var view: RefCounted = ValueMeterViewData.new()
	view.set("current_value", current_value)
	view.set("maximum_value", maximum_value)
	return view


func _make_action(movement_remaining: int, movement_available: bool,
		standard_capacity: int, standard_remaining: int,
		swift_capacity: int, swift_remaining: int) -> RefCounted:
	var view: RefCounted = ActionViewData.new()
	view.set("movement_remaining", movement_remaining)
	view.set("movement_available", movement_available)
	view.set("standard_capacity", standard_capacity)
	view.set("standard_remaining", standard_remaining)
	view.set("swift_capacity", swift_capacity)
	view.set("swift_remaining", swift_remaining)
	return view


func _make_skills(include_cooldown_reference: bool, cooldown_turns: int,
		show_charges: bool) -> Array[RefCounted]:
	var hotkeys: Array[String] = ["1", "2", "Q", "E", "R"]
	var views: Array[RefCounted] = []
	for index: int in hotkeys.size():
		var view: RefCounted = SkillViewData.new()
		view.set("skill_id", "mock_dynamic_skill_%d" % (index + 1))
		view.set("hotkey_text", hotkeys[index])
		view.set("enabled", true)
		view.set("selected", index == 3)
		view.set("cooldown_turns", cooldown_turns if index == 0 else 0)
		view.set("charges", 3 if index == 1 else 0)
		view.set("show_charges", show_charges and index == 1)
		view.set("passive", index == 2)
		view.set("active_capable", true)
		view.set("tooltip_text", "mock-only skill %d" % (index + 1))
		if include_cooldown_reference and index == 0:
			view.set("icon_texture", _make_cooldown_reference_texture())
			view.set("tooltip_text", "mock-only：冷却透明度验证色块，不是技能图标")
		views.append(view)
	return views


func _make_cooldown_reference_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([MOCK_COOLDOWN_COLOR, MOCK_COOLDOWN_COLOR])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	var texture := GradientTexture2D.new()
	texture.width = 64
	texture.height = 64
	texture.gradient = gradient
	return texture


func _make_slot(slot_id: String) -> RefCounted:
	var view: RefCounted = SlotViewData.new()
	view.set("slot_id", slot_id)
	view.set("content_id", "")
	view.set("occupied", false)
	view.set("enabled", true)
	view.set("tooltip_text", "mock-only empty %s" % slot_id)
	return view


func _make_potion() -> RefCounted:
	var view: RefCounted = PotionViewData.new()
	view.set("content_id", "")
	view.set("enabled", true)
	view.set("tooltip_text", "mock-only empty universal potion content")
	return view


func _make_end_view() -> RefCounted:
	var view: RefCounted = EndViewData.new()
	view.set("action_kind", &"end_turn")
	view.set("visible", true)
	view.set("enabled", true)
	view.set("tooltip_text", "结束本回合")
	return view
