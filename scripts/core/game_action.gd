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


static func can_use_normal_move(unit: Unit) -> Dictionary:
	if unit == null:
		return {"ok": false, "reason": "No acting unit"}
	if unit.movement_used:
		return {"ok": false, "reason": "Movement already used"}
	return {"ok": true, "reason": ""}


static func can_use_normal_attack(unit: Unit) -> Dictionary:
	if unit == null:
		return {"ok": false, "reason": "No acting unit"}
	if unit.standard_used:
		return {"ok": false, "reason": "Standard Action already used"}
	return {"ok": true, "reason": ""}


static func validate_skill_usage(unit: Unit, skill_data: Dictionary,
		reaction_trigger_met: bool = false) -> Dictionary:
	if unit == null:
		return {"ok": false, "reason": "No acting unit"}
	if skill_data.is_empty():
		return {"ok": false, "reason": "Skill data missing"}

	var skill_id: String = str(skill_data.get("id", ""))
	if skill_id != "" and not unit.is_skill_available(skill_id):
		return {
			"ok": false,
			"reason": "Cooldown: %d turn(s)" % unit.get_skill_cooldown(skill_id),
		}

	# ── 资源门槛（修复 P0-①）──────────────────────────────
	# 此前执行路径不校验资源 → 居合可无视剑气门槛刷冷却。数据驱动：仅当技能 JSON
	# 声明 qi_cost / requires_marks / mark_cost 时生效（sword_qi、get_mark_count 在
	# Unit 基类恒存在且默认 0，非剑圣技能不声明这些字段 → 门槛不触发，符合资源每职业独立）。
	var qi_cost: int = int(skill_data.get("qi_cost", 0))
	if qi_cost > 0 and unit.sword_qi < qi_cost:
		return {"ok": false, "reason": "剑气不足：需 %d / 现 %d" % [qi_cost, unit.sword_qi]}
	var marks_needed: int = maxi(
		int(skill_data.get("requires_marks", 0)), int(skill_data.get("mark_cost", 0)))
	if marks_needed > 0 and unit.get_mark_count() < marks_needed:
		return {"ok": false,
			"reason": "印记不足：需 %d / 现 %d" % [marks_needed, unit.get_mark_count()]}

	var action_cost: String = str(skill_data.get("action_cost", "standard"))
	var swift_limit: int = int(skill_data.get("swift_limit", 1))
	var action_cost_result: Dictionary = validate_action_cost(
		unit, action_cost, reaction_trigger_met, swift_limit)
	if not bool(action_cost_result.get("ok", false)):
		return action_cost_result

	var timing_constraint: String = str(
		skill_data.get("timing_constraint", "any"))
	return validate_timing_constraint(unit, timing_constraint)


static func validate_action_cost(unit: Unit, action_cost: String,
		reaction_trigger_met: bool = false,
		swift_limit: int = 1) -> Dictionary:
	if unit == null:
		return {"ok": false, "reason": "No acting unit"}

	match action_cost:
		"move":
			if unit.movement_used:
				return {"ok": false, "reason": "Movement already used"}
		"standard":
			if unit.standard_used:
				return {"ok": false, "reason": "Standard Action already used"}
		"swift":
			if not unit.can_use_swift_skill(swift_limit):
				return {"ok": false, "reason": "Swift Action already used"}
		"reaction":
			if not unit.reaction_available:
				return {"ok": false, "reason": "Reaction already used"}
			if not reaction_trigger_met:
				return {"ok": false, "reason": "Reaction trigger not met"}
		"free":
			# [预留] 2026-07-11 用户裁决：free = 不消耗任何行动资源、无资源门槛
			# （R3.3 将增补该枚举值）；当前无技能使用。
			pass
		_:
			return {"ok": false, "reason": "Unknown action_cost: %s" % action_cost}

	return {"ok": true, "reason": ""}


static func validate_timing_constraint(unit: Unit,
		timing_constraint: String) -> Dictionary:
	if unit == null:
		return {"ok": false, "reason": "No acting unit"}

	match timing_constraint:
		"any":
			pass
		"before_move":
			if unit.movement_used:
				return {"ok": false, "reason": "Must use before moving"}
		"after_move":
			if not unit.movement_used:
				return {"ok": false, "reason": "Must use after moving"}
		"before_attack":
			if unit.standard_used:
				return {"ok": false, "reason": "Must use before attacking"}
		"after_attack":
			if not unit.standard_used:
				return {"ok": false, "reason": "Must use after attacking"}
		_:
			return {
				"ok": false,
				"reason": "Unknown timing_constraint: %s" % timing_constraint,
			}

	return {"ok": true, "reason": ""}


static func consume_action_cost(unit: Unit, action_cost: String,
		swift_limit: int = 1) -> void:
	if unit == null:
		return

	match action_cost:
		"move":
			unit.consume_movement_resource()
		"standard":
			unit.consume_standard_resource()
			unit.consume_movement_resource()
		"swift":
			if swift_limit != -1:
				unit.consume_swift_resource()
		"reaction":
			unit.consume_reaction_resource()
		"free":
			# [预留] free 零消耗（2026-07-11 用户裁决，R3.3 将增补；当前无技能使用）
			pass


static func consume_normal_move(unit: Unit) -> void:
	if unit == null:
		return
	unit.consume_movement_resource()


static func consume_normal_attack(unit: Unit) -> void:
	if unit == null:
		return
	unit.consume_standard_resource()
	unit.consume_movement_resource()
