extends Control

const CANDIDATE_FONT: FontFile = preload(
	"res://assets/fonts/ibm_plex_mono/IBMPlexMono-SemiBold.ttf")
const PREVIEW_STATE: StringName = &"capacity_2_early_move_lock_long_values"

@onready var _base_gallery: Control = $BaseGallery

var _value_labels: Array[Label] = []


func _ready() -> void:
	_base_gallery.call("configure_state", PREVIEW_STATE)
	_value_labels = _resolve_value_labels()
	for label: Label in _value_labels:
		label.add_theme_font_override(&"font", CANDIDATE_FONT)


func get_value_labels() -> Array[Label]:
	return _value_labels.duplicate()


func get_candidate_font() -> FontFile:
	return CANDIDATE_FONT


func _resolve_value_labels() -> Array[Label]:
	var character: Control = _base_gallery.get_node(
		"BaseGallery/DesignRoot/BottomHudComposition/BottomRow/CharacterHudPanel") as Control
	var info_base: String = "Margin/ContentRow/InfoColumn/"
	return [
		character.get_node(
			info_base + "LevelExperienceRow/ExperienceMeter/ValueLabel") as Label,
		character.get_node(
			info_base + "SurvivalFrame/SurvivalColumn/HpMeter/ValueLabel") as Label,
		character.get_node(
			info_base + "SurvivalFrame/SurvivalColumn/ShieldMeter/ValueLabel") as Label,
	]
