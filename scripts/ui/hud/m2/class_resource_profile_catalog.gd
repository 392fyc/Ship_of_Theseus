class_name HudM2ClassResourceProfileCatalog
extends RefCounted

const SOURCE_PATH := "res://assets/ui/catalogs/hud_m2_class_resource_profiles.json"
var _profiles: Dictionary = {}


func _init() -> void:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
	if source is Dictionary and source.get("profiles") is Dictionary:
		_profiles = source["profiles"]


func profile_for(class_id: StringName) -> Dictionary:
	var profile: Variant = _profiles.get(str(class_id))
	return profile.duplicate(true) if profile is Dictionary else {}
