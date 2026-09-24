class_name HudM2SlotViewData
extends "res://scripts/ui/hud/slot_view_data.gd"

var locked: bool = false
var empty_kind: StringName = &""


func can_request() -> bool:
	return enabled and not locked and not slot_id.is_empty()
