class_name HudM2SkillIconCatalog
extends RefCounted

const CATALOG_PATH := "res://assets/ui/catalogs/hud_m2_skill_icons.json"

var _paths: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_paths = parsed


func resolve(skill_id: StringName) -> Texture2D:
	var path: Variant = _paths.get(str(skill_id))
	if not path is String or str(path).is_empty():
		return null
	var resource: Resource = load(str(path))
	return resource as Texture2D


func resolve_entries(entries: Array) -> Dictionary:
	var textures: Dictionary = {}
	for source: Variant in entries:
		if not source is Dictionary:
			continue
		var skill_id := StringName(str(source.get("skill_id", "")))
		var texture := resolve(skill_id)
		if texture != null:
			textures[str(skill_id)] = texture
	return textures
