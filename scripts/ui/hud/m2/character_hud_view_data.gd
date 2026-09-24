class_name HudM2CharacterViewData
extends "res://scripts/ui/hud/character_hud_view_data.gd"

## 只承载调用方已经提供的显示事实。空值不表示真实的零值。
var has_level: bool = false
## 键为属性标识；值可为整数，或 {"value": 整数, "delta": 整数}。
var attribute_descriptions: Dictionary = {}
const ATTRIBUTE_KEYS: Array[String] = ["STR", "MAG", "DEX", "SPE", "DEF", "RES", "LCK", "MOV"]


func _init() -> void:
	experience = null
	hp = null
	shield = null


func identity_text() -> String:
	var parts: PackedStringArray = []
	if not profession_name.strip_edges().is_empty():
		parts.append(profession_name.strip_edges())
	if not player_name.strip_edges().is_empty():
		parts.append(player_name.strip_edges())
	return " · ".join(parts) if not parts.is_empty() else "身份未提供"


func inspection_text() -> String:
	var lines: PackedStringArray = [identity_text()]
	for key: String in ATTRIBUTE_KEYS:
		lines.append("%s  %s" % [key, attribute_value_text(key)])
	return "\n".join(lines)


func attribute_value_text(key: String) -> String:
	var source: Variant = attribute_descriptions.get(key)
	var value: Variant = source.get("value") if source is Dictionary else source
	if not _is_integer(value):
		return "—"
	var result: String = str(int(value))
	var delta: Variant = source.get("delta") if source is Dictionary else null
	if _is_integer(delta) and int(delta) != 0:
		result += " (%+d)" % int(delta)
	return result


func _is_integer(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var numeric: float = float(value)
	return is_finite(numeric) and numeric == floor(numeric) and absf(numeric) < 9223372036854775808.0
