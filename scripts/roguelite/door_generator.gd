class_name DoorGenerator
extends RefCounted
## run-loop v0 门生成器（纯逻辑，无场景依赖）。
##
## 真源：dev_doc/runloop-design/runloop-reward-map-proposal.md §6 数据结构
##       + v0-implementation-plan.md。
## 起点内核移植自 tests/exp_door_generation.gd（加权轮盘 + 不放回 + 保底），
## 但已按 2026-07-03 用户裁决改写：
##   - 商店退出门池（改固定插入，与本生成器无关）→ 彻底删除 shop 相关逻辑。
##   - 遗物保底从「按选中计数」改为「按出现计数」[已定]：只看 relic 门是否出现在
##     门组，与玩家是否选它无关。
##   - 门数下限 2（按配置走，不硬编码）。
##
## 设计约束：无内部可变状态。relic_drought 由调用方持有，作为 ctx 传入、
## 作为 relic_drought_after 传出，便于固定种子单测。
##
## 所有数值一律从 door_gen（act1_config.json 的 door_gen 子字典）读取，
## 不在代码中硬编码。JSON 读取使用 int()/str()/float() 显式转型 + 缺省值。


## 生成一组门。
##   door_gen = act1_config.json 的 door_gen 子字典
##             （door_count / type_weights / elite_room_weight / constraints /
##              pity / battle_pools / map_pool / event_pool）。
##   ctx      = { "last_choice_type": String, "relic_drought": int }
##             （last_choice_type 为上一关推进选择的 reward_type，首关传 ""）。
##   waves    = DataLoader.waves 字典（查 elite 波次的 special_affix 用）。
##   rng      = 外部注入的 RandomNumberGenerator（固定种子可测）。
## 返回 { "doors": Array[Dictionary], "relic_drought_after": int,
##        "_fallback_count": int }。
##   （"_fallback_count" 为下划线前缀调试/观测字段，供单测统计池耗尽回退次数，
##     非核心契约；正常五类配置下恒为 0。）
func generate_group(door_gen: Dictionary, ctx: Dictionary,
		waves: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	# ── 读配置（全部从 door_gen 取，缺省值兜底，不硬编码业务数值） ──
	var dc_min: int = 2
	var dc_max: int = 3
	var dc_v: Variant = door_gen.get("door_count")
	if dc_v is Dictionary:
		dc_min = int((dc_v as Dictionary).get("min", 2))
		dc_max = int((dc_v as Dictionary).get("max", 3))
	if dc_max < dc_min:
		dc_max = dc_min
	var door_count: int = rng.randi_range(dc_min, dc_max)

	var type_weights: Dictionary = {}
	var tw_v: Variant = door_gen.get("type_weights")
	if tw_v is Dictionary:
		for key_v: Variant in (tw_v as Dictionary).keys():
			var key: String = str(key_v)
			if key.begins_with("_"):
				continue  # 跳过 "_" 前缀注释键
			type_weights[key] = float((tw_v as Dictionary)[key_v])

	var elite_room_weight: float = float(door_gen.get("elite_room_weight", 0))

	var distinct: bool = true  # [提案] 同组门类型互不相同，做成开关，读配置默认 true
	var cons_v: Variant = door_gen.get("constraints")
	if cons_v is Dictionary:
		distinct = bool((cons_v as Dictionary).get("same_offer_types_distinct", true))

	var pity_stages: int = 0
	var pity_v: Variant = door_gen.get("pity")
	if pity_v is Dictionary:
		pity_stages = int((pity_v as Dictionary).get("relic_drought_stages", 0))

	var map_pool: Array[String] = _string_array(door_gen.get("map_pool"))
	var event_pool: Array[String] = _string_array(door_gen.get("event_pool"))
	var normal_pool: Array[String] = []
	var elite_pool: Array[String] = []
	var bp_v: Variant = door_gen.get("battle_pools")
	if bp_v is Dictionary:
		normal_pool = _string_array((bp_v as Dictionary).get("normal"))
		elite_pool = _string_array((bp_v as Dictionary).get("elite"))

	# ── 读 ctx ──
	var last_choice_type: String = str(ctx.get("last_choice_type", ""))
	var relic_drought: int = int(ctx.get("relic_drought", 0))
	# 事件不连续硬约束【生成侧排除】：上一关选事件 → 本组不含 event
	var exclude_event: bool = last_choice_type == "event"
	# 遗物保底触发：连续 pity_stages 关未出现 relic → 本组首门强制 relic
	var force_relic: bool = pity_stages > 0 and relic_drought >= pity_stages

	# ── 抽 door_count 个 reward_type（五类，权重 type_weights） ──
	var reward_types: Array[String] = []
	var avail: Dictionary = _candidate_pool(type_weights, exclude_event)
	var fallback_count: int = 0

	if force_relic and door_count >= 1 and type_weights.has("relic"):
		reward_types.append("relic")  # 首个强制 relic
		if distinct:
			avail.erase("relic")

	while reward_types.size() < door_count:
		if avail.is_empty():
			# 池耗尽回退：放宽 distinct 重取（保留 exclude_event 排除）。
			# 正常五类配置（≥4 类可用，门数 ≤3）下不应触发。
			fallback_count += 1
			avail = _candidate_pool(type_weights, exclude_event)
			if avail.is_empty():
				break  # 极端容错：无任何可用类型，直接停止填充
		var picked: String = _weighted_pick(avail, rng)
		reward_types.append(picked)
		if distinct:
			avail.erase(picked)

	# ── 逐门装配 DoorOption ──
	var doors: Array[Dictionary] = []
	var relic_appeared: bool = false
	for reward_type: String in reward_types:
		if reward_type == "relic":
			relic_appeared = true
		doors.append(_assemble_door(
			reward_type, elite_room_weight,
			map_pool, event_pool, normal_pool, elite_pool, waves, rng))

	# ── 保底按出现计数【已定】 ──
	# 只要门组里「出现」了 relic 门（无论玩家是否会选它）→ drought 归零；
	# 否则 drought + 1。这是「按出现」与旧「按选中」的核心区别：
	# 绝不改成「玩家选中 relic 才重置」。
	var relic_drought_after: int = 0 if relic_appeared else relic_drought + 1

	return {
		"doors": doors,
		"relic_drought_after": relic_drought_after,
		"_fallback_count": fallback_count,
	}


## 组装单扇门的 DoorOption 字典。
func _assemble_door(reward_type: String, elite_room_weight: float,
		map_pool: Array[String], event_pool: Array[String],
		normal_pool: Array[String], elite_pool: Array[String],
		waves: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var elite_room: bool = false
	var battle: Variant = null
	var event_id: Variant = null
	var special_affix: Variant = null

	if reward_type == "event":
		# 事件门：无战斗、无精英房，从 event_pool 均匀抽一个。
		event_id = _uniform_pick(event_pool, rng)
	else:
		# gold/exp/equipment/relic：伴随一场战斗，胜利后给该类奖励。
		elite_room = rng.randf() * 100.0 < elite_room_weight
		var map_id: Variant = _uniform_pick(map_pool, rng)
		var pool: Array[String] = elite_pool if elite_room else normal_pool
		var enemy_config: Variant = _uniform_pick(pool, rng)
		battle = {
			"map_id": str(map_id) if map_id != null else "",
			"enemy_config": str(enemy_config) if enemy_config != null else "",
		}
		# 精英门 special_affix：进房前可见，查该波次里 elite_chief 的 special_affix。
		if elite_room and enemy_config != null:
			special_affix = _lookup_special_affix(str(enemy_config), waves)

	return {
		"reward_type": reward_type,
		"elite_room": elite_room,
		"battle": battle,
		"event_id": event_id,
		"preview": {
			"icon": reward_type,
			"rarity_hint": null,
			"special_affix": special_affix,
		},
	}


## 构造候选类型池（复制权重字典，去掉排除项）。
## 防御性去掉 "shop"：商店已退出门池，即便配置误留 shop 权重也绝不产出。
func _candidate_pool(type_weights: Dictionary, exclude_event: bool) -> Dictionary:
	var pool: Dictionary = type_weights.duplicate()
	pool.erase("shop")
	if exclude_event:
		pool.erase("event")
	return pool


## 查波次里 tier=="elite_chief" 的敌人的 special_affix。
## 查不到波次 / 无 elite_chief / 无 special_affix → 返回 null（不崩）。
func _lookup_special_affix(wave_id: String, waves: Dictionary) -> Variant:
	if not waves.has(wave_id):
		return null
	var wave_v: Variant = waves[wave_id]
	if not (wave_v is Dictionary):
		return null
	var enemies_v: Variant = (wave_v as Dictionary).get("enemies")
	if not (enemies_v is Array):
		return null
	for enemy_v: Variant in (enemies_v as Array):
		if not (enemy_v is Dictionary):
			continue
		if str((enemy_v as Dictionary).get("tier", "")) == "elite_chief":
			var sa: String = str((enemy_v as Dictionary).get("special_affix", ""))
			return sa if sa != "" else null
	return null


## 加权轮盘选择，返回类型键。
func _weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total: float = 0.0
	for k: Variant in weights.keys():
		total += float(weights[k])
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for k: Variant in weights.keys():
		acc += float(weights[k])
		if roll < acc:
			return str(k)
	return str(weights.keys()[weights.size() - 1])


## 从数组均匀抽一个，空数组返回 null。
func _uniform_pick(arr: Array[String], rng: RandomNumberGenerator) -> Variant:
	if arr.is_empty():
		return null
	return arr[rng.randi_range(0, arr.size() - 1)]


## Variant → Array[String]（逐项 str() 转型），非数组返回空数组。
func _string_array(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if v is Array:
		for item: Variant in (v as Array):
			out.append(str(item))
	return out
