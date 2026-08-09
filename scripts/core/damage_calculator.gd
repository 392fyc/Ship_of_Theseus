class_name DamageCalculator
extends RefCounted
## ADR-005: FE-style additive base damage + multiplicative outer layers.
## Block removed from base resolution flow.
## Hit/Avoid derived from DEX/SPD (LCK removed, R1.2); Crit derived from DEX/LCK
## (LCK still gates crit avoid).


class AttackResult:
	var hit: bool = false
	var crit: bool = false
	var damage: int = 0
	var defender_died: bool = false
	var attacker_died: bool = false


## 只掷命中与暴击、不算伤害，返回 `{"hit": bool, "crit": bool}`。
##
## 为什么要把掷骰单独抽出来（Wave 3 · A2）：设计库的「命中时」/「暴击时」两个
## trigger_event 是**伤害数值结算之前**的时点，落在这个时点的天赋可以回过头改写
## 本次伤害（死线的「该次暴击造成 (DEX/2)% 更多伤害」就是这种），所以调用方必须
## 能先拿到掷骰结果、把事件分发完、再让伤害算出来。
##
## ★ 返回 Dictionary 而不是自定义类，是有原因的：`action_data` 会被 `duplicate(true)`
## 深拷贝多次（`_build_hostile_action_context`、范围技能的 per-target 复制、预告路径），
## 而 **Object 在 `duplicate(true)` 下是共享引用、不会被复制**。用类承载掷骰结果，
## 一发范围技能的每个目标就会共用同一次命中/暴击判定——直接违反 R1.10「计次按被
## 作用的目标单位分别进行」。Dictionary 会被真正深拷贝，没有这个陷阱。
##
## ★ 拆分前后 **randf() 的调用次数与顺序完全一致**，这是回归零变化的前提：
##   未命中 → 掷 1 次（命中判定后立即返回，暴击那次永不发生）
##   命中   → 掷 2 次（先命中、后暴击），顺序不可倒置
##   guaranteed_hit / guaranteed_crit / 纯粹伤害 / disable_crit → 跳过对应那次掷骰
## 三条别动的细节：① 命中失败必须立即 return；② `crit_rate <= 0` 时**照样掷**
## （不加短路，否则高 LCK 目标上的掷骰次数会变）；③ 比较运算符原样保留——命中是
## `randf() > hit_rate` 判未中、暴击是 `randf() < crit_rate` 判暴击，改成 >= / <=
## 会在边界值上翻结果。另外本函数用的是全局 `randf()`，别换成新建的
## RandomNumberGenerator 实例，那是另一条随机流。
static func roll_outcome(attacker: Unit, defender: Unit,
		action_data: Dictionary = {}) -> Dictionary:
	var outcome: Dictionary = {"hit": false, "crit": false}
	var damage_type: String = action_data.get("damage_type", "physical")
	var weapon_hit: int = action_data.get("weapon_hit", 0)
	var weapon_crit: int = action_data.get("weapon_crit", 0)
	var terrain_evade_bonus: int = action_data.get("terrain_evade_bonus", 0)

	# ── Step 1: Hit determination ───────────────────────
	# Hit = weapon_hit + DEX×2
	# Avoid = SPD×2 + terrain_evade
	# guaranteed_hit（居合）：绕过命中判定，直接命中。
	var guaranteed_hit: bool = bool(action_data.get("guaranteed_hit", false))
	if guaranteed_hit:
		outcome["hit"] = true
	else:
		var hit_value: int = attacker.get_hit_value(weapon_hit)
		var avoid_value: int = defender.get_avoid_value(terrain_evade_bonus)
		var hit_rate: float = clampf((hit_value - avoid_value) / 100.0, 0.01, 1.0)
		if randf() > hit_rate:
			return outcome  # miss → hit=false，暴击不掷
		outcome["hit"] = true

	# ── Step 2: Crit determination ──────────────────────
	# Crit = weapon_crit + DEX/2 + crit_bonus;  Dodge = LCK
	# guaranteed_crit（居合）：跳过随机判定直接暴击；纯粹伤害不参与暴击判定（R1.3），
	# guaranteed_crit 对其无效。
	var allow_crit: bool = (damage_type != "pure")
	# disable_crit（调试确定性开关「不暴」态）：纯加法分支，默认 false 不影响正式战斗。
	if bool(action_data.get("disable_crit", false)):
		allow_crit = false
	if allow_crit:
		var guaranteed_crit: bool = bool(action_data.get("guaranteed_crit", false))
		if guaranteed_crit:
			outcome["crit"] = true
		else:
			var crit_value: int = attacker.get_crit_value(weapon_crit)
			var dodge_value: int = defender.get_crit_avoid_value()
			var crit_rate: float = maxf(0.0, (crit_value - dodge_value) / 100.0)
			if randf() < crit_rate:
				outcome["crit"] = true
	return outcome


static func resolve_attack(attacker: Unit, defender: Unit,
		action_data: Dictionary = {}) -> AttackResult:
	var result: AttackResult = AttackResult.new()

	var damage_type: String = action_data.get("damage_type", "physical")
	var skill_multiplier: float = action_data.get("skill_multiplier", 1.0)
	var terrain_multiplier: float = action_data.get("terrain_multiplier", 1.0)
	var relic_multiplier: float = action_data.get("relic_multiplier", 1.0)
	var final_multiplier: float = action_data.get("final_multiplier", 1.0)
	var pure_atk_source: String = action_data.get("pure_atk_source", "phys")

	# R1.8「中间量不取整」：weapon_might 用 float 承接，因为它可能是被修正过的
	# 中间量（例：副手追加取 might×50%，5×0.5=2.5）。提前截成 int 等于在中间层
	# floor 一次，与 R1.8「clamp 与 floor 在最外层生效」冲突。主手传整数时行为不变。
	var weapon_might: float = float(action_data.get("weapon_might", 0))
	var terrain_def_bonus: int = action_data.get("terrain_def_bonus", 0)
	var terrain_res_bonus: int = action_data.get("terrain_res_bonus", 0)

	# ── Step 1+2: 命中与暴击 ────────────────────────────
	# 掷骰逻辑统一在 roll_outcome()，那里有随机序列一致性的完整说明。
	#
	# `precomputed_outcome`：调用方**已经**掷过骰了。Wave 3 起主手与副手都走这条路
	# ——必须先拿到 hit / crit，才能分发「命中时」/「暴击时」，让落在那个时点的
	# 天赋回过头改写本次伤害。这里就不再重掷，否则一次攻击会掷两轮。
	#
	# ★ 这个键**只能在调用点现场注入**，绝不能放进会被 per-target 深拷贝的上游字典
	# （技能 payload、`_build_hostile_action_context` 的输入、`_apply_debug_determinism`）
	# ——那样一发范围技能的每个目标会共用同一次命中/暴击判定，违反 R1.10「计次按被
	# 作用的目标单位分别进行」。
	var precomputed: Variant = action_data.get("precomputed_outcome", null)
	var outcome: Dictionary = precomputed if precomputed is Dictionary \
		else roll_outcome(attacker, defender, action_data)
	result.hit = bool(outcome.get("hit", false))
	result.crit = bool(outcome.get("crit", false))
	if not result.hit:
		return result  # miss → damage 保持 0

	# 纯粹伤害不参与暴击判定（R1.1 与 R1.3 各自逐字重申过一次），这是无条件的。
	# roll_outcome 已经守住了；这里再守一次，防的是**外部传进来的**
	# precomputed_outcome——它可能是手工构造的，绕过了上面那道。disable_crit 同理。
	if damage_type == "pure" or bool(action_data.get("disable_crit", false)):
		result.crit = false

	# ── Step 3: Base damage (additive, FE-style) ────────
	var base_damage: float = _calc_base_damage(
		attacker, defender, damage_type,
		weapon_might, pure_atk_source, terrain_def_bonus, terrain_res_bonus)

	# ── Step 4: Apply multiplicative layers ─────────────
	var final_dmg: float = base_damage * skill_multiplier * terrain_multiplier

	if result.crit:
		# R1.3 暴击倍率 = (1.5 + Σ 加算 crit_damage_bonus) × Π 乘算 crit_damage_mult，
		# 加算先于乘算。crit_damage_mult 默认 1.0 → 无乘算修正时与引入本通道前完全一致。
		# 例：拔刀「暴击倍率 ×1.2」是乘算 → 1.5 × 1.2 = 1.8（2026-08-03 用户裁决 F [已定]）。
		var crit_mult: float = (1.5 + float(action_data.get("crit_damage_bonus", 0.0))) \
			* float(action_data.get("crit_damage_mult", 1.0))
		final_dmg *= crit_mult

	final_dmg *= relic_multiplier * final_multiplier

	# ── 敌人词条输出乘区（具名，独立于 relic/final）─────
	# 无词条攻击方 affix_multiplier==1.0 → 伤害与引入词条前完全一致（回归零变化）。
	final_dmg *= _affix_attack_multiplier(attacker)

	# ── 区域溅射衰减（如拔刀 splash_damage_pct）──────────
	# area_damage_multiplier 默认 1.0（向后兼容），溅射目标由调用方设为 0.5 等。
	final_dmg *= float(action_data.get("area_damage_multiplier", 1.0))

	# ── 敌人词条 afs_bulwark 防御乘区（己方减伤光环）─────────
	# 由 tactical_manager._build_hostile_action_context 注入；默认 1.0（无光环 → 零影响）。
	final_dmg *= float(action_data.get("affix_defense_multiplier", 1.0))

	# ── Step 5: Calculate final damage (caller applies) ─
	# R1.8：中间量不取整，最终量向下取整；下限 0 在最外层生效。
	result.damage = maxi(0, floori(final_dmg))
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
	var weapon_might: float = float(action_data.get("weapon_might", 0))
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
	var crit_blocked: bool = is_pure or bool(action_data.get("disable_crit", false))
	if not crit_blocked:
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
	# 敌人词条输出乘区（与 resolve_attack 一致，保证 forecast == 实际伤害）。
	final_damage *= _affix_attack_multiplier(attacker)
	# 区域溅射衰减（与 resolve_attack 一致，保证 forecast == 实际伤害）。
	final_damage *= float(action_data.get("area_damage_multiplier", 1.0))
	# afs_bulwark 防御乘区（与 resolve_attack 一致，保证 forecast == 实际伤害）。
	final_damage *= float(action_data.get("affix_defense_multiplier", 1.0))

	# R1.8：与 resolve_attack 一致向下取整，保证 forecast == 实际伤害。
	var dmg_int: int = maxi(0, floori(final_damage))
	return {
		"hit_percent": clampi(roundi(hit_rate * 100.0), 0, 100),
		"crit_percent": clampi(roundi(crit_rate * 100.0), 0, 100),
		"damage": dmg_int,
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
		weapon_might: float, pure_atk_source: String,
		terrain_def_bonus: int, terrain_res_bonus: int) -> float:
	## R1.1（伤害链）: Additive base damage formula.
	## physical:  max(0, STR + weapon_might - DEF)
	## magical:   max(0, MAG + weapon_might - RES)
	## pure:      [source] + weapon_might  (ignores defense)
	## hybrid:    ( max(0, STR + weapon_might - DEF) + max(0, MAG + weapon_might - RES) ) / 2
	##            物理与魔法各按 R1.1 各算一次（各自带自己的地板），再取算术平均。
	##            2026-08-03 用户裁决 A [已定]，取代旧的 min(DEF,RES) 占位写法。
	var base: float = 0.0
	var defender_def: int = defender.get_effective_stat("DEF") + terrain_def_bonus
	var defender_res: int = defender.get_effective_stat("RES") + terrain_res_bonus
	match damage_type:
		"physical":
			base = float(attacker.get_effective_stat("STR") + weapon_might \
				 - defender_def)
		"magical":
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
			return base  # pure ignores defense
		"hybrid":
			# 裁决 A（2026-08-03 [已定]）：物理与魔法各按 R1.1 各算一次（各自带自己的
			# max(0,·) 地板），再取算术平均。
			# ⚠️ 这不等于「一次性减去平均防御」——只要有一侧被地板截断，两种写法结果就不同，
			# 所以必须在分支内先各自取地板再平均，不能落到函数末尾那个统一地板
			# （那条路径是「先平均再取地板」，与裁决不符）。
			var phys_part: float = maxf(0.0, float(
				attacker.get_effective_stat("STR") + weapon_might - defender_def))
			var mag_part: float = maxf(0.0, float(
				attacker.get_effective_stat("MAG") + weapon_might - defender_res))
			return (phys_part + mag_part) / 2.0
	return maxf(0.0, base)


## 敌人词条输出乘区：攻击方 stat_scale 增强（affix_damage_mult）× 条件触发词条。
## 无词条攻击方 affix_damage_mult==1.0 且 _affixes 空 → 返回 1.0（回归零变化）。
## v0 条件触发示范：afs_frenzy（低血增伤）——攻击方 hp/max_hp < 阈值时额外增伤。
static func _affix_attack_multiplier(attacker: Unit) -> float:
	if attacker == null:
		return 1.0
	var mult: float = attacker.affix_damage_mult
	for affix: Dictionary in attacker.get_affixes():
		if str(affix.get("id", "")) != "afs_frenzy":
			continue
		var params: Dictionary = affix.get("params", {})
		var threshold_pct: float = float(params.get("low_hp_threshold_pct", 0))
		var bonus_pct: float = float(params.get("damage_bonus_pct", 0))
		if attacker.stats != null and attacker.stats.max_hp > 0:
			var hp_ratio_pct: float = float(attacker.stats.hp) \
				/ float(attacker.stats.max_hp) * 100.0
			if hp_ratio_pct < threshold_pct:
				mult *= (1.0 + bonus_pct / 100.0)
	return mult
