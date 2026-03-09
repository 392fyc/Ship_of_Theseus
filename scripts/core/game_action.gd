class_name GameAction
extends RefCounted

enum Type { MOVE, ATTACK, SKILL, USE_SWIFT, END_TURN }

var type: GameAction.Type
var actor: Unit
var target_pos: Vector2i
var target_unit: Unit
var data: Dictionary = {}


static func make_move(unit: Unit, to: Vector2i) -> GameAction:
	var a := GameAction.new()
	a.type = Type.MOVE
	a.actor = unit
	a.target_pos = to
	return a


static func make_attack(attacker: Unit, target: Unit,
		skill_id: String = "",
		damage_type: String = "physical",
		pure_atk_source: String = "phys") -> GameAction:
	var a := GameAction.new()
	a.type = Type.ATTACK
	a.actor = attacker
	a.target_unit = target
	a.data = {
		"attacker_id": attacker.unit_id,
		"target_id": target.unit_id,
		"skill_id": skill_id,
		"damage_type": damage_type,
		"pure_atk_source": pure_atk_source,
		"skill_multiplier": 1.0,
		"terrain_multiplier": 1.0,
		"allow_counter": true,
		"allow_pursuit": true,
	}
	return a


static func make_skill(user: Unit, skill_id: String,
		skill_target_pos: Vector2i = Vector2i.ZERO,
		target: Unit = null,
		payload: Dictionary = {}) -> GameAction:
	var a := GameAction.new()
	a.type = Type.SKILL
	a.actor = user
	a.target_pos = skill_target_pos
	a.target_unit = target
	a.data = payload.duplicate(true)
	a.data["skill_id"] = skill_id
	return a


static func make_use_swift(user: Unit, skill_id: String = "",
		payload: Dictionary = {}) -> GameAction:
	var a := GameAction.new()
	a.type = Type.USE_SWIFT
	a.actor = user
	a.data = payload.duplicate(true)
	if skill_id != "":
		a.data["skill_id"] = skill_id
	return a


static func make_end_turn(unit: Unit) -> GameAction:
	var a := GameAction.new()
	a.type = Type.END_TURN
	a.actor = unit
	return a
