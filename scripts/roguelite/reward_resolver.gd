class_name RewardResolver
extends RefCounted
## run-loop v0 奖励结算器（无内部状态，操作传入的 RunState）。
##
## 注：state 参数静态类型用 Object（非 RunState class_name），以便 headless
## --script 依赖编译期（全局 class 缓存未建）也能解析；成员按动态访问。
## RELIC_SLOT_MAX 经 preload 的脚本常量取，避免引用未注册的 class_name。
##
## 真源：KB run-loop.md:74-79 结算顺序 + :165 Boss 固定包 + :181 天赋点来自升级；
##       runloop-reward-map-proposal.md §6/§7；v0-implementation-plan.md。
##
## 结算顺序（每关战斗胜利后，由 RunManager 编排调用）：
##   1) settle_fixed —— 固定 Gold + EXP（每图固定数额，EXP 可能触发升级 → 天赋点）
##   2) settle_door_reward —— 门奖励（每角色独立），或 Boss 关用 settle_boss_package
##
## 设计约束：
##   - 纯数据账本操作，绝不实例化 Unit、不调 UnitStats.level_up。
##   - 所有数值一律从 act_config（progression / door_rewards / boss.reward /
##     door_gen.fixed_reward_per_stage）读取，不硬编码业务数值。
##   - 天赋点只来自升级（每次升级 +talent_point_per_level），非掉落。
##   - Gold 共享账本；EXP 每角色独立。

const RunStateScript: GDScript = preload("res://scripts/roguelite/run_state.gd")


## 1) 固定结算：每图固定 Gold + EXP（v0 幕倍率 x1.0 [占位]）。
## gold += fixed.gold（共享账本）；每角色 exp += fixed.exp 并检查升级。
## 返回 { "gold": int, "exp_each": int, "levelups": Array }。
func settle_fixed(state: Object, act_config: Dictionary) -> Dictionary:
	var fixed: Dictionary = _fixed_reward(act_config)
	var gold_add: int = int(fixed.get("gold", 0))
	var exp_add: int = int(fixed.get("exp", 0))
	# v0 幕倍率 x1.0 [占位]：act 越深倍率越高，后置。
	state.gold += gold_add
	var levelups: Array = _grant_exp_all(state, exp_add, act_config)
	return {
		"gold": gold_add,
		"exp_each": exp_add,
		"levelups": levelups,
	}


## 2) 门奖励结算（每角色独立发放）。reward_type ∈ gold|exp|equipment|relic|event。
## event 不发放（事件流程另处理）。elite_room 提升装备品质（读 elite 权重表）。
## 返回 { "reward_type", "elite_room", "gold": int, "exp_each": int,
##        "levelups": Array, "drops": Array }。
func settle_door_reward(state: Object, reward_type: String, elite_room: bool,
		data_pools: Dictionary, rng: RandomNumberGenerator,
		act_config: Dictionary) -> Dictionary:
	var door_rewards: Dictionary = _door_rewards(act_config)
	var summary: Dictionary = {
		"reward_type": reward_type,
		"elite_room": elite_room,
		"gold": 0,
		"exp_each": 0,
		"levelups": [],
		"drops": [],
	}

	match reward_type:
		"gold":
			var g: int = int(door_rewards.get("gold", 0))
			state.gold += g  # 共享账本
			summary["gold"] = g
		"exp":
			var e: int = int(door_rewards.get("exp", 0))
			summary["exp_each"] = e
			summary["levelups"] = _grant_exp_all(state, e, act_config)
		"equipment":
			var weights: Dictionary = _equipment_weights(door_rewards, elite_room)
			var per_drop: int = int(door_rewards.get("relic_per_drop", 1))  # 复用每次掉落个数
			summary["drops"] = _grant_equipment_all(state, data_pools, weights, "", rng, per_drop)
		"relic":
			var per_drop2: int = int(door_rewards.get("relic_per_drop", 1))
			summary["drops"] = _grant_relic_all(state, data_pools, {}, "", rng, per_drop2)
		"event":
			pass  # 事件不在此结算
		_:
			pass
	return summary


## Boss 固定包：Gold + EXP + Equipment + 特殊 Relic（数额/品质从 boss.reward 读）。
## boss_reward = act_config.boss.reward = { "fixed": {gold,exp}, "package": [RewardDrop...] }。
## 返回 { "gold", "exp_each", "levelups", "drops", "package_kinds" }。
func settle_boss_package(state: Object, boss_reward: Dictionary,
		data_pools: Dictionary, rng: RandomNumberGenerator,
		act_config: Dictionary) -> Dictionary:
	var fixed: Dictionary = {}
	if boss_reward.get("fixed") is Dictionary:
		fixed = boss_reward.get("fixed")
	var gold_add: int = int(fixed.get("gold", 0))
	var exp_add: int = int(fixed.get("exp", 0))
	state.gold += gold_add
	var levelups: Array = _grant_exp_all(state, exp_add, act_config)

	var drops: Array = []
	var package_kinds: Array[String] = []
	if boss_reward.get("package") is Array:
		for drop_v: Variant in (boss_reward.get("package") as Array):
			if not (drop_v is Dictionary):
				continue
			var drop: Dictionary = drop_v
			var kind: String = str(drop.get("kind", ""))
			var rarity_hint: String = str(drop.get("rarity", "")) if drop.get("rarity") != null else ""
			package_kinds.append(kind)
			match kind:
				"equipment":
					var eq_drops: Array = _grant_equipment_all(
						state, data_pools, {}, rarity_hint, rng, 1)
					for ed: Variant in eq_drops:
						drops.append(ed)
				"relic":
					var rl_drops: Array = _grant_relic_all(
						state, data_pools, {}, rarity_hint, rng, 1)
					for rd: Variant in rl_drops:
						drops.append(rd)
				_:
					pass  # gold/exp 由 fixed 处理，package 内的标记项跳过
	return {
		"gold": gold_add,
		"exp_each": exp_add,
		"levelups": levelups,
		"drops": drops,
		"package_kinds": package_kinds,
	}


# ── 内部：经验 / 升级 ─────────────────────────────────

## 给每个角色加经验并检查升级，返回 [{char_index, class_id, levels:[...]}]。
func _grant_exp_all(state: Object, exp_add: int, act_config: Dictionary) -> Array:
	var out: Array = []
	for i: int in range(state.party.size()):
		var member: Dictionary = state.party[i]
		member["exp"] = int(member.get("exp", 0)) + exp_add
		var levels: Array = _check_level_up(state, member, act_config)
		if not levels.is_empty():
			out.append({
				"char_index": i,
				"class_id": str(member.get("class_id", "")),
				"levels": levels,
			})
	return out


## 循环检查单角色升级：exp >= 阈值 → 扣阈值、level++、talent_points += 每级点数
## （同步累加角色与 state 顶层合计）。返回本次升级记录数组。
func _check_level_up(state: Object, member: Dictionary, act_config: Dictionary) -> Array:
	var tp_per_level: int = _talent_point_per_level(act_config)
	var levels: Array = []
	var guard: int = 0
	while true:
		var level: int = int(member.get("level", 1))
		var threshold: int = _exp_threshold(level, act_config)
		if threshold <= 0:
			break  # 阈值非法防死循环
		if int(member.get("exp", 0)) < threshold:
			break
		member["exp"] = int(member.get("exp", 0)) - threshold
		member["level"] = level + 1
		member["talent_points"] = int(member.get("talent_points", 0)) + tp_per_level
		state.talent_points += tp_per_level
		levels.append({
			"level": level + 1,
			"talent_points_gained": tp_per_level,
		})
		guard += 1
		if guard > 999:
			break  # 极端容错
	return levels


## 升级阈值公式 [占位]：threshold(level) = round(base * pow(growth, level-1))。
## growth=1.0 → 平坦（每级恒 base）。全部从 progression 读，不硬编码。
func _exp_threshold(level: int, act_config: Dictionary) -> int:
	var prog: Dictionary = _progression(act_config)
	var base: int = int(prog.get("exp_threshold_base", 100))
	var growth: float = float(prog.get("exp_threshold_growth", 1.0))
	var lv: int = level if level >= 1 else 1
	return int(round(float(base) * pow(growth, float(lv - 1))))


# ── 内部：装备 / 遗物掉落 ─────────────────────────────

## 每角色抽 per_drop 件装备，v0 先入 convoy.equipment。
## 返回 [{char_index, class_id, kind:"equipment", item, rarity}]。
func _grant_equipment_all(state: Object, data_pools: Dictionary,
		weights: Dictionary, forced_rarity: String,
		rng: RandomNumberGenerator, per_drop: int) -> Array:
	var pool: Dictionary = data_pools.get("equipment") if data_pools.get("equipment") is Dictionary else {}
	var out: Array = []
	var convoy_eq: Array = state.convoy.get("equipment", [])
	for i: int in range(state.party.size()):
		var member: Dictionary = state.party[i]
		for _n: int in range(max(1, per_drop)):
			var picked: Dictionary = _pick_by_rarity(pool, weights, forced_rarity, rng)
			var item: String = str(picked.get("id", ""))
			if item == "":
				continue
			convoy_eq.append(item)  # v0 先放运输队
			out.append({
				"char_index": i,
				"class_id": str(member.get("class_id", "")),
				"kind": "equipment",
				"item": item,
				"rarity": str(picked.get("rarity", "")),
			})
	state.convoy["equipment"] = convoy_eq
	return out


## 每角色抽 per_drop 个遗物：角色槽未满入角色，满则溢出 convoy.relics。
## 返回 [{char_index, class_id, kind:"relic", item, rarity, to_convoy:bool}]。
func _grant_relic_all(state: Object, data_pools: Dictionary,
		weights: Dictionary, forced_rarity: String,
		rng: RandomNumberGenerator, per_drop: int) -> Array:
	var pool: Dictionary = data_pools.get("relics") if data_pools.get("relics") is Dictionary else {}
	var out: Array = []
	var convoy_relics: Array = state.convoy.get("relics", [])
	for i: int in range(state.party.size()):
		var member: Dictionary = state.party[i]
		var member_relics: Array = member.get("relics", [])
		for _n: int in range(max(1, per_drop)):
			var picked: Dictionary = _pick_by_rarity(pool, weights, forced_rarity, rng)
			var item: String = str(picked.get("id", ""))
			if item == "":
				continue
			var to_convoy: bool = member_relics.size() >= RunStateScript.RELIC_SLOT_MAX
			if to_convoy:
				convoy_relics.append(item)
			else:
				member_relics.append(item)
			out.append({
				"char_index": i,
				"class_id": str(member.get("class_id", "")),
				"kind": "relic",
				"item": item,
				"rarity": str(picked.get("rarity", "")),
				"to_convoy": to_convoy,
			})
		member["relics"] = member_relics
	state.convoy["relics"] = convoy_relics
	return out


## 按品质加权从池（id→data 字典）抽一件。
##   forced_rarity != "" → 优先该品质，无此品质则回退全池。
##   否则按 weights 权重抽品质（只在池内存在的品质里抽），weights 空则均匀全池。
## 返回被抽中的条目字典（含 id/rarity），空池返回 {}。
func _pick_by_rarity(pool: Dictionary, weights: Dictionary,
		forced_rarity: String, rng: RandomNumberGenerator) -> Dictionary:
	if pool.is_empty():
		return {}
	# 按 rarity 分桶
	var buckets: Dictionary = {}  # rarity -> Array[String] of ids
	for id_v: Variant in pool.keys():
		var entry_v: Variant = pool[id_v]
		if not (entry_v is Dictionary):
			continue
		var rarity: String = str((entry_v as Dictionary).get("rarity", ""))
		if not buckets.has(rarity):
			buckets[rarity] = []
		(buckets[rarity] as Array).append(str(id_v))

	var target_rarity: String = ""
	if forced_rarity != "" and buckets.has(forced_rarity) \
			and not (buckets[forced_rarity] as Array).is_empty():
		target_rarity = forced_rarity
	elif forced_rarity == "" and not weights.is_empty():
		target_rarity = _weighted_rarity(buckets, weights, rng)

	var candidates: Array = []
	if target_rarity != "" and buckets.has(target_rarity):
		candidates = buckets[target_rarity]
	else:
		# 回退：全池均匀
		for k: Variant in pool.keys():
			candidates.append(str(k))

	if candidates.is_empty():
		return {}
	var chosen_id: String = str(candidates[rng.randi_range(0, candidates.size() - 1)])
	var chosen_v: Variant = pool.get(chosen_id)
	return chosen_v if chosen_v is Dictionary else { "id": chosen_id, "rarity": "" }


## 在池内存在的品质里按 weights 加权抽一个品质键，抽不到返回 ""。
func _weighted_rarity(buckets: Dictionary, weights: Dictionary,
		rng: RandomNumberGenerator) -> String:
	var total: float = 0.0
	var avail: Dictionary = {}  # rarity -> weight，仅池内有货的品质
	for rarity_v: Variant in weights.keys():
		var rarity: String = str(rarity_v)
		if rarity.begins_with("_"):
			continue
		if buckets.has(rarity) and not (buckets[rarity] as Array).is_empty():
			var w: float = float(weights[rarity_v])
			if w > 0.0:
				avail[rarity] = w
				total += w
	if total <= 0.0:
		return ""
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for rarity_v2: Variant in avail.keys():
		acc += float(avail[rarity_v2])
		if roll < acc:
			return str(rarity_v2)
	return str(avail.keys()[avail.size() - 1])


# ── 内部：配置读取（全部从 act_config，缺省兜底，不硬编码业务值） ──

func _fixed_reward(act_config: Dictionary) -> Dictionary:
	var dg_v: Variant = act_config.get("door_gen")
	if dg_v is Dictionary:
		var fr_v: Variant = (dg_v as Dictionary).get("fixed_reward_per_stage")
		if fr_v is Dictionary:
			return fr_v
	return {}


func _door_rewards(act_config: Dictionary) -> Dictionary:
	var dr_v: Variant = act_config.get("door_rewards")
	return dr_v if dr_v is Dictionary else {}


func _progression(act_config: Dictionary) -> Dictionary:
	var p_v: Variant = act_config.get("progression")
	return p_v if p_v is Dictionary else {}


func _talent_point_per_level(act_config: Dictionary) -> int:
	return int(_progression(act_config).get("talent_point_per_level", 1))


func _equipment_weights(door_rewards: Dictionary, elite_room: bool) -> Dictionary:
	var key: String = "elite_equipment_rarity_weights" if elite_room else "equipment_rarity_weights"
	var w_v: Variant = door_rewards.get(key)
	return w_v if w_v is Dictionary else {}
