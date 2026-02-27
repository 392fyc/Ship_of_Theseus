class_name GameAction
extends RefCounted

enum Type { MOVE, ATTACK, USE_SWIFT, END_TURN }

var type: GameAction.Type
var actor: Unit
var target_pos: Vector2i
var target_unit: Unit

static func make_move(actor: Unit, to: Vector2i) -> GameAction:
	var a := GameAction.new()
	a.type = Type.MOVE
	a.actor = actor
	a.target_pos = to
	return a

static func make_end_turn(actor: Unit) -> GameAction:
	var a := GameAction.new()
	a.type = Type.END_TURN
	a.actor = actor
	return a
