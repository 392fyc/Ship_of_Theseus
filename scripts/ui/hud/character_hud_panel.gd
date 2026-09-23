class_name CharacterHudPanel
extends PanelContainer

const CharacterViewData := preload("res://scripts/ui/hud/character_hud_view_data.gd")

var _view: CharacterViewData = null

@onready var _portrait_content: TextureRect = %PortraitContent
@onready var _portrait_fallback: Label = %PortraitFallback
@onready var _identity_label: Label = %IdentityLabel
@onready var _level_label: Label = %LevelLabel
@onready var _experience_meter: Control = %ExperienceMeter
@onready var _hp_meter: Control = %HpMeter
@onready var _shield_meter: Control = %ShieldMeter


func _ready() -> void:
	if _view != null:
		_apply_view_to_nodes()


func apply_view(view: CharacterViewData) -> void:
	_view = view
	if is_node_ready():
		_apply_view_to_nodes()


func _apply_view_to_nodes() -> void:
	var identity_parts: PackedStringArray = []
	if _view.profession_name != "":
		identity_parts.append(_view.profession_name)
	if _view.player_name != "":
		identity_parts.append(_view.player_name)
	var identity_text: String = " · ".join(identity_parts)
	_identity_label.text = identity_text
	_identity_label.tooltip_text = identity_text
	_level_label.text = "Lv. %d" % maxi(_view.level, 0)
	_experience_meter.call("apply_view", _view.experience)
	_hp_meter.call("apply_view", _view.hp)
	_shield_meter.call("apply_view", _view.shield)
	_portrait_content.texture = _view.portrait_texture
	_portrait_fallback.text = _view.portrait_fallback_text
	_portrait_fallback.visible = _view.portrait_texture == null
