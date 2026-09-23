class_name HudEndTurnViewData
extends RefCounted

const ACTION_END_TURN: StringName = &"end_turn"
const ACTION_END_MOVE: StringName = &"end_move"

var action_kind: StringName = ACTION_END_TURN
var visible: bool = true
var enabled: bool = true
var tooltip_text: String = ""


func is_valid_action_kind() -> bool:
	return action_kind == ACTION_END_TURN or action_kind == ACTION_END_MOVE
