extends Control

const CharacterHudPanelScene: PackedScene = preload(
	"res://scenes/tactical/hud/character_hud_panel.tscn")
const CharacterViewData := preload("res://scripts/ui/hud/character_hud_view_data.gd")
const MeterViewData := preload("res://scripts/ui/hud/value_meter_view_data.gd")

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
	_add_state_panel($SafeArea/Layout/Content/CharacterColumn/NormalState,
		_make_view("剑圣", "fyc", 12, 450, 1000, 34, 100, 12, 40))
	_add_state_panel($SafeArea/Layout/Content/CharacterColumn/LongNameState,
		_make_view("流浪剑术宗师", "极长的玩家自定义名称", 99,
			9999, 10000, 999, 1200, 345, 500))
	_add_state_panel($SafeArea/Layout/Content/CharacterColumn/ZeroShieldState,
		_make_view("剑士", "fyc", 5, 0, 100, 70, 100, 0, 100))
	_add_state_panel($SafeArea/Layout/Content/CharacterColumn/FullValuesState,
		_make_view("剑圣", "满值测试", 20, 1000, 1000, 100, 100, 50, 50))
	_add_state_panel($SafeArea/Layout/Content/CharacterColumn/LargeValuesState,
		_make_view("剑圣", "fyc", 999,
			999999, 999999, 999999, 999999, 999999, 999999))


func _add_state_panel(parent: VBoxContainer, view: RefCounted) -> void:
	var panel: Control = CharacterHudPanelScene.instantiate() as Control
	panel.name = "CharacterHudPanel"
	panel.call("apply_view", view)
	parent.add_child(panel)


func _make_view(profession_name: String, player_name: String, level: int,
		experience_current: int, experience_maximum: int,
		hp_current: int, hp_maximum: int,
		shield_current: int, shield_maximum: int) -> RefCounted:
	var view: RefCounted = CharacterViewData.new()
	view.set("profession_name", profession_name)
	view.set("player_name", player_name)
	view.set("level", level)
	view.set("portrait_fallback_text", profession_name.left(1))
	view.set("experience", _make_meter(experience_current, experience_maximum))
	view.set("hp", _make_meter(hp_current, hp_maximum))
	view.set("shield", _make_meter(shield_current, shield_maximum))
	return view


func _make_meter(current_value: int, maximum_value: int) -> RefCounted:
	var meter: RefCounted = MeterViewData.new()
	meter.set("current_value", current_value)
	meter.set("maximum_value", maximum_value)
	return meter
