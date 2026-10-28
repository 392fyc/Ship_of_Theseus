extends "res://scripts/art/character_pipeline/capture_portrait_environment_battle.gd"
## Reuse the real player/AI sequence; add only UI observations to its existing trace.


func _unit_state(unit: Unit, current: Unit) -> Dictionary:
	var result: Dictionary = super._unit_state(unit, current)
	if unit.unit_id == "myrmidon":
		var turn_order: Control = session.get("battle").get("_turn_order_bar") as Control
		var description: Label = session.get("_description") as Label
		result["battle_ui"] = {
			"turn_order":turn_order.call("get_debug_snapshot"),
			"turn_order_rect":turn_order.get_global_rect(),
			"description_text":description.text,
			"description_rect":description.get_global_rect(),
			"header_clear":not description.get_global_rect().intersects(turn_order.get_global_rect())}
	return result
