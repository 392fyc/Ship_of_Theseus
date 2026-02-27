class_name DamageCalculator
extends RefCounted


class AttackResult:
	var hit: bool = false
	var blocked: bool = false
	var crit: bool = false
	var damage: int = 0
	var defender_died: bool = false
	var attacker_died: bool = false


static func resolve_attack(attacker: Unit, defender: Unit,
		action_data: Dictionary = {}) -> AttackResult:
	var result := AttackResult.new()

	var damage_type: String = action_data.get("damage_type", "physical")
	var skill_multiplier: float = action_data.get("skill_multiplier", 1.0)
	var terrain_multiplier: float = action_data.get("terrain_multiplier", 1.0)
	var pure_atk_source: String = action_data.get("pure_atk_source", "phys")

	# M5: weapon_power 暂无武器系统，默认 1.0
	var weapon_power: float = action_data.get("weapon_power", 1.0)
	var phys_power: float = weapon_power
	var mag_power: float = action_data.get("mag_power", 1.0)
	var armor_resist: float = action_data.get("armor_resist", 1.0)
	var magic_resist: float = action_data.get("magic_resist", 1.0)

	# ── 步骤 1：命中判定 ──────────────────────────────
	var hit_rate := clampf(
		(attacker.stats.hit - defender.stats.evade) / 100.0,
		0.2, 1.0)
	if randf() > hit_rate:
		return result  # miss → hit=false

	result.hit = true

	# ── 步骤 2：格挡判定（pure 跳过）─────────────────
	var is_pure := (damage_type == "pure")
	if not is_pure and defender.stats.block > 0:
		if randf() < defender.stats.block / 100.0:
			result.blocked = true

	# ── 步骤 3：暴击判定（格挡成功时跳过）────────────
	if not result.blocked:
		var allow_crit := true
		if is_pure and not action_data.get("enable_pure_crit", false):
			allow_crit = false
		if allow_crit:
			var crit_rate := maxf(0.0,
				(attacker.stats.crit - defender.stats.crit_evade) / 100.0)
			if randf() < crit_rate:
				result.crit = true

	# ── 步骤 4-5：计算并应用最终伤害 ─────────────────
	var base_damage := _calc_base_damage(
		attacker, defender, damage_type,
		phys_power, mag_power, armor_resist, magic_resist,
		weapon_power, pure_atk_source)

	var final_dmg: float = base_damage * skill_multiplier * terrain_multiplier

	if result.crit:
		var crit_mult := 1.5
		if not is_pure:
			crit_mult += action_data.get("crit_damage_bonus", 0.0)
		final_dmg *= crit_mult

	if result.blocked:
		final_dmg *= 0.3

	result.damage = maxi(0, roundi(final_dmg))
	defender.take_damage(result.damage, damage_type)
	result.defender_died = not defender.stats.is_alive()

	# ── 步骤 6-7：附加效果（M5 留空）─────────────────
	pass

	return result


static func _calc_base_damage(attacker: Unit, defender: Unit,
		damage_type: String,
		phys_power: float, mag_power: float,
		armor_resist: float, magic_resist: float,
		weapon_power: float, pure_atk_source: String) -> float:
	var base: float = 0.0
	match damage_type:
		"physical":
			base = attacker.stats.phys_atk * phys_power \
				 - defender.stats.physical_defense * armor_resist
		"magical":
			base = attacker.stats.mag_atk * mag_power \
				 - defender.stats.magical_defense * magic_resist
		"pure":
			var raw: float = 0.0
			match pure_atk_source:
				"phys":
					raw = attacker.stats.phys_atk
				"mag":
					raw = attacker.stats.mag_atk
				"sum":
					raw = attacker.stats.phys_atk + attacker.stats.mag_atk
			base = raw * weapon_power
		"hybrid":
			var hybrid_power := (phys_power + mag_power) / 2.0
			var both_atk: float = attacker.stats.phys_atk + attacker.stats.mag_atk
			var both_def: float = minf(
				defender.stats.physical_defense * armor_resist,
				defender.stats.magical_defense * magic_resist)
			base = both_atk * hybrid_power - both_def
	return maxf(0.0, base)
