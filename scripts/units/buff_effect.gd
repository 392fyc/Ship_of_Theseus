class_name BuffEffect
extends Resource

var buff_id: String = ""
var display_name: String = ""
var icon: String = ""

var duration: int = -1
var max_duration: int = -1

var effect_type: String = "special"
var stat_key: String = ""
var value: float = 0.0
var is_percentage: bool = false

var trigger: String = "permanent"
var source_unit_id: String = ""

var stackable: bool = false
var max_stacks: int = 1
var refresh_on_reapply: bool = false


func tick(target_unit: Unit) -> Dictionary:
	var result: Dictionary = {
		"skip_turn": false,
	}
	if target_unit == null:
		return result

	match effect_type:
		"dot":
			var amount: int = maxi(0, roundi(value))
			if amount > 0:
				var damage_type: String = "pure" if buff_id == "poison" else "magical"
				target_unit.take_damage(amount, damage_type)
		"hot":
			var heal_amount: int = maxi(0, roundi(value))
			if heal_amount > 0:
				target_unit.heal(heal_amount)
		"control":
			if buff_id == "stun" or buff_id == "freeze":
				result["skip_turn"] = true
	return result


func apply(_target_unit: Unit) -> void:
	pass


func unapply(_target_unit: Unit) -> void:
	pass


func to_dict() -> Dictionary:
	return {
		"buff_id": buff_id,
		"display_name": display_name,
		"icon": icon,
		"duration": duration,
		"max_duration": max_duration,
		"effect_type": effect_type,
		"stat_key": stat_key,
		"value": value,
		"is_percentage": is_percentage,
		"trigger": trigger,
		"source_unit_id": source_unit_id,
		"stackable": stackable,
		"max_stacks": max_stacks,
		"refresh_on_reapply": refresh_on_reapply,
	}


static func from_dict(data: Dictionary) -> BuffEffect:
	var buff: BuffEffect = BuffEffect.new()
	buff.buff_id = str(data.get("buff_id", data.get("id", "")))
	buff.display_name = str(data.get("display_name", buff.buff_id))
	buff.icon = str(data.get("icon", ""))
	buff.duration = int(data.get("duration", -1))
	buff.max_duration = int(data.get("max_duration", buff.duration))
	buff.effect_type = str(data.get("effect_type", "special"))
	buff.stat_key = str(data.get("stat_key", ""))
	buff.value = float(data.get("value", 0.0))
	buff.is_percentage = bool(data.get("is_percentage", false))
	buff.trigger = str(data.get("trigger", "permanent"))
	buff.source_unit_id = str(data.get("source_unit_id", ""))
	buff.stackable = bool(data.get("stackable", false))
	buff.max_stacks = int(data.get("max_stacks", 1))
	buff.refresh_on_reapply = bool(data.get("refresh_on_reapply", false))
	return buff


func is_debuff() -> bool:
	match effect_type:
		"dot", "control":
			return true
		"hot", "shield":
			return false
		"stat_mod":
			return value < 0.0
	return value < 0.0
