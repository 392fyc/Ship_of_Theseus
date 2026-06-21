class_name DamageCalculator
extends RefCounted
## ADR-005: FE-style additive base damage + multiplicative outer layers.
## Block removed from base resolution flow.
## Hit/Crit derived from DEX/SPD/LCK instead of independent attributes.


class AttackResult:
	var hit: bool = false
	var crit: bool = false
	var damage: int = 0
	var defender_died: bool = false
	var attacker_died: bool = false


static func resolve_attack(attacker: Unit, defender: Unit,
		action_data: Dictionary = {}) -> AttackResult:
	var result: AttackResult = AttackResult.new()

	var damage_type: String = action_data.get("damage_type", "physical")
	var skill_multiplier: float = action_data.get("skill_multiplier", 1.0)
	var terrain_multiplier: float = action_data.get("terrain_multiplier", 1.0)
	var relic_multiplier: float = action_data.get("relic_multiplier", 1.0)
	var final_multiplier: float = action_data.get("final_multiplier", 1.0)
	var pure_atk_source: String = action_data.get("pure_atk_source", "phys")

	var weapon_might: int = action_data.get("weapon_might", 0)
	var weapon_hit: int = action_data.get("weapon_hit", 0)
	var weapon_crit: int = action_data.get("weapon_crit", 0)
	var terrain_evade_bonus: int = action_data.get("terrain_evade_bonus", 0)
	var terrain_def_bonus: int = action_data.get("terrain_def_bonus", 0)
	var terrain_res_bonus: int = action_data.get("terrain_res_bonus", 0)

	# ── Step 1: Hit determination ───────────────────────
	# Hit = weapon_hit + DEX×2 + LCK×0.5
	# Avoid = SPD×2 + LCK×0.5 + terrain_evade
	# guaranteed_hit（居合）：绕过命中判定，直接命中。
	var guaranteed_hit: bool = bool(action_data.get("guaranteed_hit", false))
	if guaranteed_hit:
		result.hit = true
	else:
		var hit_value: int = attacker.get_hit_value(weapon_hit)
		var avoid_value: int = defender.get_avoid_value(terrain_evade_bonus)
		var hit_rate: float = clampf((hit_value - avoid_value) / 100.0, 0.01, 1.0)
		if randf() > hit_rate:
			return result  # miss → hit=false
		result.hit = true

	# ── Step 2: Crit determination ──────────────────────
	# Crit = weapon_crit + DEX/2 + crit_bonus;  Dodge = LCK
	# guaranteed_crit（居合）：跳过随机判定直接暴击（pure伤害仍受限）。
	var is_pure: bool = (damage_type == "pure")
	var allow_crit: bool = true
	if is_pure and not action_data.get("enable_pure_crit", false):
		allow_crit = false
	if allow_crit:
		var guaranteed_crit: bool = bool(action_data.get("guaranteed_crit", false))
		if guaranteed_crit:
			result.crit = true
		else:
			var crit_value: int = attacker.get_crit_value(weapon_crit)
			var dodge_value: int = defender.get_crit_avoid_value()
			var crit_rate: float = maxf(0.0, (crit_value - dodge_value) / 100.0)
			if randf() < crit_rate:
				result.crit = true

	# ── Step 3: Base damage (additive, FE-style) ────────
	var base_damage: float = _calc_base_damage(
		attacker, defender, damage_type,
		weapon_might, pure_atk_source, terrain_def_bonus, terrain_res_bonus)

	# ── Step 4: Apply multiplicative layers ─────────────
	var final_dmg: float = base_damage * skill_multiplier * terrain_multiplier

	if result.crit:
		var crit_mult: float = 1.5
		if not is_pure:
			# crit_damage_bonus：拔刀额外暴击倍率（叠加到 1.5x 基础上）
			crit_mult += float(action_data.get("crit_damage_bonus", 0.0))
		final_dmg *= crit_mult

	final_dmg *= relic_multiplier * final_multiplier

	# ── Step 5: Calculate final damage (caller applies) ─
	result.damage = maxi(0, roundi(final_dmg))
	result.defender_died = defender.stats.hp <= result.damage

	return result


static func preview_attack(attacker: Unit, defender: Unit,
		action_data: Dictionary = {}) -> Dictionary:
	var damage_type: String = action_data.get("damage_type", "physical")
	var skill_multiplier: float = action_data.get("skill_multiplier", 1.0)
	var terrain_multiplier: float = action_data.get("terrain_multiplier", 1.0)
	var relic_multiplier: float = action_data.get("relic_multiplier", 1.0)
	var final_multiplier: float = action_data.get("final_multiplier", 1.0)
	var pure_atk_source: String = action_data.get("pure_atk_source", "phys")
	var weapon_might: int = action_data.get("weapon_might", 0)
	var weapon_hit: int = action_data.get("weapon_hit", 0)
	var weapon_crit: int = action_data.get("weapon_crit", 0)
	var terrain_evade_bonus: int = action_data.get("terrain_evade_bonus", 0)
	var terrain_def_bonus: int = action_data.get("terrain_def_bonus", 0)
	var terrain_res_bonus: int = action_data.get("terrain_res_bonus", 0)

	var guaranteed_hit: bool = bool(action_data.get("guaranteed_hit", false))
	var hit_rate: float = 1.0
	if not guaranteed_hit:
		var hit_value: int = attacker.get_hit_value(weapon_hit)
		var avoid_value: int = defender.get_avoid_value(terrain_evade_bonus)
		hit_rate = clampf((hit_value - avoid_value) / 100.0, 0.01, 1.0)

	var crit_rate: float = 0.0
	var is_pure: bool = (damage_type == "pure")
	if not (is_pure and not action_data.get("enable_pure_crit", false)):
		var guaranteed_crit: bool = bool(action_data.get("guaranteed_crit", false))
		if guaranteed_crit:
			crit_rate = 1.0
		else:
			var crit_value: int = attacker.get_crit_value(weapon_crit)
			var dodge_value: int = defender.get_crit_avoid_value()
			crit_rate = maxf(0.0, (crit_value - dodge_value) / 100.0)

	var base_damage: float = _calc_base_damage(
		attacker, defender, damage_type, weapon_might, pure_atk_source,
		terrain_def_bonus, terrain_res_bonus)
	var final_damage: float = base_damage * skill_multiplier * terrain_multiplier
	final_damage *= relic_multiplier * final_multiplier

	var dmg_int: int = maxi(0, roundi(final_damage))
	return {
		"hit_percent": clampi(roundi(hit_rate * 100.0), 0, 100),
		"crit_percent": clampi(roundi(crit_rate * 100.0), 0, 100),
		"damage": dmg_int,
		"counter_expected": bool(action_data.get("allow_counter", true)),
		"terrain_name": str(action_data.get("defender_terrain_name", "PLAIN")),
		"terrain_evade_bonus": terrain_evade_bonus,
		"terrain_def_bonus": terrain_def_bonus,
		"terrain_res_bonus": terrain_res_bonus,
		"hit_count": 1,
		"per_hit_damage": dmg_int,
		"total_damage": dmg_int,
		"damage_type": damage_type,
		"is_heal": false,
	}


static func _calc_base_damage(attacker: Unit, defender: Unit,
		damage_type: String,
		weapon_might: int, pure_atk_source: String,
		terrain_def_bonus: int, terrain_res_bonus: int) -> float:
	## ADR-005 §4.2: Additive base damage formula.
	## physical:  max(1, STR + weapon_might - DEF)
	## magical:   max(1, MAG + tome_might  - RES)
	## pure:      [source] + weapon_might  (ignores defense)
	## hybrid:    max(1, (STR+MAG) + hybrid_might - min(DEF,RES))  ⚠️ TBD (ADR-006)
	var base: float = 0.0
	var defender_def: int = defender.get_effective_stat("DEF") + terrain_def_bonus
	var defender_res: int = defender.get_effective_stat("RES") + terrain_res_bonus
	match damage_type:
		"physical":
			base = float(attacker.get_effective_stat("STR") + weapon_might \
				 - defender_def)
		"magical", "holy":
			base = float(attacker.get_effective_stat("MAG") + weapon_might \
				 - defender_res)
		"pure":
			var raw: float = 0.0
			match pure_atk_source:
				"phys":
					raw = float(attacker.get_effective_stat("STR"))
				"mag":
					raw = float(attacker.get_effective_stat("MAG"))
				"sum":
					raw = float(
						attacker.get_effective_stat("STR") + attacker.get_effective_stat("MAG"))
			base = raw + float(weapon_might)
			return base  # pure ignores defense, no max(1) floor needed
		"hybrid":
			# ⚠️ TBD — placeholder per ADR-005 §4.2. Awaiting ADR-006.
			var both_atk: float = float(
				attacker.get_effective_stat("STR") + attacker.get_effective_stat("MAG"))
			var weaker_def: float = float(mini(defender_def, defender_res))
			base = both_atk + float(weapon_might) - weaker_def
	return maxf(1.0, base)
