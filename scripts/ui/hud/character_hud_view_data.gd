class_name HudCharacterViewData
extends RefCounted

const ValueMeterViewData := preload("res://scripts/ui/hud/value_meter_view_data.gd")

var profession_name: String = ""
var player_name: String = ""
var level: int = 0
var experience: ValueMeterViewData = ValueMeterViewData.new()
var hp: ValueMeterViewData = ValueMeterViewData.new()
var shield: ValueMeterViewData = ValueMeterViewData.new()
var portrait_texture: Texture2D = null
var portrait_fallback_text: String = ""
