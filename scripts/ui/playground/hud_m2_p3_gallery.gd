extends Control

const LOGICAL_SIZE := Vector2(1280, 720)
const FIXTURE_PATH := "res://assets/prototype/hud_m2/p3-fixtures.json"
const CharacterViewData := preload("res://scripts/ui/hud/m2/character_hud_view_data.gd")
const MeterViewData := preload("res://scripts/ui/hud/value_meter_view_data.gd")
const SkillViewData := preload("res://scripts/ui/hud/m2/skill_slot_view_data.gd")
const ActionViewData := preload("res://scripts/ui/hud/action_resource_view_data.gd")
const SlotViewData := preload("res://scripts/ui/hud/m2/slot_view_data.gd")
const PotionViewData := preload("res://scripts/ui/hud/potion_view_data.gd")
const EndViewData := preload("res://scripts/ui/hud/end_turn_view_data.gd")

var _skill_count: int = 5
var _output_size := Vector2i(1280, 720)
var _state: String = "normal"
var _fixtures: Dictionary = {}

@onready var _design_root: Control = %DesignRoot
@onready var _composition: Control = %BottomHudComposition
@onready var _board: Control = %Board


func _ready() -> void:
	_fixtures = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH)) as Dictionary
	_board.draw.connect(_draw_board)
	_board.queue_redraw()
	_apply_configuration()


func configure(skill_count: int, output_size: Vector2i, state: String = "normal") -> void:
	_skill_count = clampi(skill_count, 5, 7)
	_output_size = output_size
	_state = state
	custom_minimum_size = Vector2(output_size)
	size = Vector2(output_size)
	if is_node_ready():
		_apply_configuration()


func get_output_scale() -> float:
	return minf(float(_output_size.x) / LOGICAL_SIZE.x, float(_output_size.y) / LOGICAL_SIZE.y)


func get_skill_count() -> int:
	return _skill_count


func get_state() -> String:
	return _state


func get_skill_slots() -> Array:
	return _composition.get_node("BottomRow/SkillShelf").call("get_skill_slots") as Array


func get_character_panel() -> Control:
	return _composition.get_node("BottomRow/CharacterHudPanel") as Control


func _apply_configuration() -> void:
	_design_root.scale = Vector2.ONE * get_output_scale()
	_composition.call("apply_character", _make_character_view())
	_composition.call("apply_skills", _make_skill_views())
	_composition.call("apply_action_resources", _make_action_view())
	_composition.call("apply_equipment", _make_slot_view("weapon"), _make_slot_view("armor"), _make_potion_view())
	_composition.call("apply_relics", _make_relic_views())
	var end_view := EndViewData.new()
	var end_source: Dictionary = (_fixtures["end_action"] as Dictionary).duplicate(true)
	end_source.merge(_utility_overrides().get("end_action", {}) as Dictionary, true)
	end_view.action_kind = StringName(str(end_source["action_kind"]))
	end_view.visible = bool(end_source["visible"])
	end_view.enabled = bool(end_source["enabled"])
	end_view.tooltip_text = str(end_source["tooltip_text"])
	_composition.call("apply_end_action", end_view)
	var portrait_button: Button = get_character_panel().call("get_inspection_control") as Button
	portrait_button.release_focus()
	if _state in ["focus", "missing", "mixed"]:
		portrait_button.grab_focus.call_deferred()
	elif _state == "passive_focus":
		_focus_pure_passive.call_deferred()
	elif _state == "utility_focus":
		_composition.get_node("BottomRow/EquipmentHudPanel/WeaponSlot").grab_focus.call_deferred()


func _focus_pure_passive() -> void:
	for slot: Control in get_skill_slots():
		var passive_frame: Control = slot.find_child("PassiveFrame", true, false) as Control
		if passive_frame != null and passive_frame.visible:
			slot.grab_focus()
			return


func _make_character_view() -> RefCounted:
	var source: Dictionary = (_fixtures["character"] as Dictionary).duplicate(true)
	source.merge((_fixtures["character_overrides"] as Dictionary).get(_state, {}) as Dictionary, true)
	var view := CharacterViewData.new()
	view.profession_name = str(source["profession_name"])
	view.player_name = str(source["player_name"])
	view.has_level = source["level"] != null
	if view.has_level:
		view.level = int(source["level"])
	view.experience = _make_meter(source.get("experience"))
	view.hp = _make_meter(source.get("hp"))
	view.shield = _make_meter(source.get("shield"))
	view.attribute_descriptions = source["attributes"] as Dictionary
	var portrait_path: String = str(source.get("portrait_path", ""))
	if not portrait_path.is_empty():
		var region: Array = source["portrait_crop"] as Array
		var texture := AtlasTexture.new()
		texture.atlas = load(portrait_path) as Texture2D
		texture.region = Rect2(float(region[0]), float(region[1]), float(region[2]), float(region[3]))
		texture.filter_clip = true
		view.portrait_texture = texture
	return view


func _make_meter(source: Variant) -> MeterViewData:
	if not source is Dictionary:
		return null
	var meter := MeterViewData.new()
	meter.current_value = int(source["current"])
	meter.maximum_value = int(source["maximum"])
	return meter


func _make_skill_views() -> Array[RefCounted]:
	var views: Array[RefCounted] = []
	var overrides: Dictionary = (_fixtures["skill_overrides"] as Dictionary).get(_state, {}) as Dictionary
	for index: int in _skill_count:
		var source: Dictionary = (_fixtures["skills"][index] as Dictionary).duplicate(true)
		source.merge(overrides.get(str(index), {}) as Dictionary, true)
		var view := SkillViewData.new()
		view.skill_id = str(source["skill_id"])
		view.icon_texture = load(str(source["icon"])) as Texture2D
		view.hotkey_text = str(index + 1)
		view.enabled = bool(source.get("enabled", true))
		view.selected = bool(source.get("selected", false))
		view.cooldown_turns = int(source.get("cooldown_turns", 0))
		view.passive = bool(source.get("passive", false))
		view.active_capable = bool(source.get("active_capable", true))
		view.action_type = StringName(str(source["action_type"]))
		view.resource_cost_display = source.get("resource_cost_display", {}) as Dictionary
		view.tooltip_text = str(source.get("tooltip_text", source["name"]))
		views.append(view)
	return views


func _make_action_view() -> RefCounted:
	var source: Dictionary = (_fixtures["action_resources"] as Dictionary).duplicate(true)
	source.merge((_fixtures["action_overrides"] as Dictionary).get(_state, {}) as Dictionary, true)
	var view := ActionViewData.new()
	for key: Variant in source:
		view.set(str(key), source[key])
	return view


func _make_slot_view(slot_id: String) -> RefCounted:
	var source: Dictionary = (_fixtures["equipment"][slot_id] as Dictionary).duplicate(true)
	var overrides: Dictionary = _utility_overrides().get("equipment", {}) as Dictionary
	source.merge(overrides.get(slot_id, {}) as Dictionary, true)
	source["slot_id"] = slot_id
	return _slot_from_source(source)


func _slot_from_source(source: Dictionary) -> RefCounted:
	var view := SlotViewData.new()
	view.slot_id = str(source["slot_id"])
	view.content_id = str(source.get("content_id", ""))
	view.occupied = bool(source.get("occupied", not view.content_id.is_empty()))
	view.locked = bool(source.get("locked", false))
	view.enabled = bool(source.get("enabled", true))
	view.empty_kind = StringName(str(source.get("empty_kind", "")))
	if view.occupied:
		view.icon_texture = load(str(source["icon"])) as Texture2D
	return view


func _make_relic_views() -> Array[RefCounted]:
	var views: Array[RefCounted] = []
	var sources: Array = _fixtures["relics"] as Array
	var overrides: Dictionary = _utility_overrides().get("relics", {}) as Dictionary
	for index: int in sources.size():
		var source: Dictionary = (sources[index] as Dictionary).duplicate(true)
		source.merge(overrides.get(str(index), {}) as Dictionary, true)
		views.append(_slot_from_source(source))
	return views


func _utility_overrides() -> Dictionary:
	return (_fixtures["utility_overrides"] as Dictionary).get(_state, {}) as Dictionary


func _make_potion_view() -> RefCounted:
	var source: Dictionary = (_fixtures["equipment"]["potion"] as Dictionary).duplicate(true)
	source.merge((_utility_overrides().get("equipment", {}) as Dictionary).get("potion", {}) as Dictionary, true)
	var view := PotionViewData.new()
	view.content_id = str(source["content_id"])
	view.enabled = bool(source.get("enabled", true))
	if _state != "missing":
		view.icon_texture = load(str(source["icon"])) as Texture2D
	return view


func _draw_board() -> void:
	_board.draw_colored_polygon(PackedVector2Array([
		Vector2(640, 0), Vector2(1280, 320), Vector2(640, 640), Vector2(0, 320)]), Color("1b1c27"))
	var grid_color := Color("45404d")
	grid_color.a = 0.36
	for index: int in 21:
		var start_a := Vector2(640 + index * 32, index * 16)
		var start_b := Vector2(640 - index * 32, index * 16)
		_board.draw_line(start_a, start_a + Vector2(-640, 320), grid_color, 0.65, true)
		_board.draw_line(start_b, start_b + Vector2(640, 320), grid_color, 0.65, true)
