class_name HudM2SkillIconCatalog
extends RefCounted

const CATALOG_PATH := "res://assets/ui/catalogs/hud_m2_skill_icons.json"

var _paths: Dictionary = {}
var _class_paths: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_paths = parsed
		var overrides: Variant = parsed.get("_class_overrides", {})
		if overrides is Dictionary:
			_class_paths = overrides


func resolve(skill_id: StringName, class_id: StringName = &"") -> Texture2D:
	var default_path: Variant = _paths.get(str(skill_id))
	var class_catalog: Variant = _class_paths.get(str(class_id), {})
	if class_catalog is Dictionary:
		var override_path: Variant = class_catalog.get(str(skill_id))
		var override_texture: Texture2D = _load_texture(override_path)
		if override_texture != null:
			return override_texture
	return _load_texture(default_path)


func _load_texture(path: Variant) -> Texture2D:
	if not path is String or str(path).is_empty() or not ResourceLoader.exists(str(path)):
		return null
	var resource: Resource = load(str(path))
	return resource as Texture2D


func resolve_entries(entries: Array, class_id: StringName = &"") -> Dictionary:
	var textures: Dictionary = {}
	for source: Variant in entries:
		if not source is Dictionary:
			continue
		var skill_id := StringName(str(source.get("skill_id", "")))
		var texture := resolve(skill_id, class_id)
		if texture != null:
			textures[str(skill_id)] = texture
	return textures
