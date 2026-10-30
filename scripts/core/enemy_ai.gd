class_name EnemyAI
extends RefCounted
## 敌人 AI：比较所有可达位置上的普通攻击与攻击技能，选得分最高的位置、攻击与目标；
## 打不到任何人时走向最近的玩家单位。
## 单体得分 = 命中率 × 有效伤害 × damage_weight + 击杀概率 × kill_bonus，〔影〕再加 decoy_bonus。
## 范围技能（AOE）得分 = 范围内每个目标的命中率 × 有效伤害 × damage_weight 之和，不加击杀分
## 与诱饵分（用户 2026-10-31「只比总期望伤害」）。单体与 AOE 的得分直接比较（用户「比得分」）。
## 权重与同分决胜顺序在 data/ai/target_scoring.json；命中、暴击与伤害取伤害预告的同一套公式。
## All decisions are returned as GameAction arrays for TacticalManager to execute,
## keeping the pattern compatible with multiplayer broadcast.

const CONFIG_ID := "target_scoring"
## 浮点得分相差不到它时算同分，交给决胜顺序。
const SCORE_EPSILON := 0.000001


## `forecast`：`func(attacker: Unit, target: Unit) -> Dictionary`，返回
## DamageCalculator.preview_attack 的结果。TacticalManager 传入玩家悬停预告用的同一个上下文；
## 不传时退回不带上下文的 preview_attack（只在测试里出现）。
## `planner`：提供攻击技能查询的对象（TacticalManager），需有 `_ai_attack_skill_ids(unit)`、
## `_ai_skill_casts(unit, skill_id, origin)` 与 `_ai_forecast_skill(attacker, target, skill_id)`。
## 不传时只比较普通攻击。
static func decide_actions(unit: Unit, grid: Grid,
		all_units: Array, forecast: Callable = Callable(),
		planner: Object = null) -> Array[GameAction]:
	var actions: Array[GameAction] = []
	var atk_min_range: int = unit.attack_min_range
	var atk_range: int = unit.attack_range

	var targets: Array[Unit] = []
	for u in all_units:
		if u.faction != unit.faction and u.stats.is_alive():
			targets.append(u)

	if targets.is_empty():
		return actions

	var cfg: Dictionary = _config()
	# 预告只读防守方所在格的地形，与攻击者站在哪里无关，所以每个目标只算一次。
	var scored: Dictionary = {}
	for target in targets:
		scored[target] = score_target(unit, target, forecast, cfg)

	# 1. 候选站位：原地，加上本回合还能移动时的全部可达空格。
	var move_range: Dictionary = {unit.grid_position: unit.stats.mov}
	if bool(GameAction.can_use_normal_move(unit).get("ok", false)):
		move_range = Pathfinding.get_move_range(
			grid, unit.grid_position, unit.stats.mov, unit.faction)

	# 本回合能用的攻击技能；每个技能对每个目标的打分各算一次（预告与站位无关）。
	var skill_ids: Array[String] = []
	if planner != null:
		skill_ids = planner._ai_attack_skill_ids(unit)
	var skill_scored: Dictionary = {}

	# 2. 比较每个站位上的每种出手，选得分最高的一组。同分时普攻在前，技能按技能组顺序。
	var tie_break: Array = cfg.get("tie_break", [])
	var best: Dictionary = {}
	for move_pos: Vector2i in move_range:
		var cell := grid.get_cell(move_pos)
		if cell.occupant != null and cell.occupant != unit:
			continue
		var move_cost: int = unit.stats.mov - int(move_range[move_pos])
		for target in targets:
			if not unit.has_basic_attack:
				break
			if not _in_range(move_pos, target, atk_min_range, atk_range):
				continue
			var cand: Dictionary = _candidate(move_pos, move_cost, target, scored[target])
			if best.is_empty() or _better(cand, best, tie_break):
				best = cand
		for skill_id: String in skill_ids:
			for cast: Dictionary in planner._ai_skill_casts(unit, skill_id, move_pos):
				var cand: Dictionary = _skill_candidate(unit, planner, skill_id, cast,
					move_pos, move_cost, skill_scored, cfg)
				if best.is_empty() or _better(cand, best, tie_break):
					best = cand

	if not best.is_empty():
		# R1.18：位置与攻击按得分定下后，再在该位置的合法嘲讽目标里按得分选目标。
		# 以格子或方向为目标的技能不受嘲讽影响。
		var skill_id: String = str(best.get("skill_id", ""))
		var taunting: Dictionary = {}
		if skill_id == "":
			taunting = _pick_taunting_target(best, targets, scored,
				atk_min_range, atk_range, tie_break)
		elif best.get("target") != null:
			taunting = _pick_taunting_cast(unit, planner, best, skill_scored, cfg, tie_break)
		if not taunting.is_empty():
			best = taunting

	# 3. 功能技能（增益、减益、治疗；用户 2026-10-31「可用就用」）：按技能组顺序，
	#    第一个有合法施放方式的标准动作技能取代攻击；迅捷技能在最终站位上另外各用一次。
	var supports: Array = []
	if planner != null:
		supports = planner._ai_support_skills(unit)
	var preferred: Unit = best.get("target") if not best.is_empty() else null
	var free_cells: Dictionary = {}
	for move_pos: Vector2i in move_range:
		var cell := grid.get_cell(move_pos)
		if cell.occupant == null or cell.occupant == unit:
			free_cells[move_pos] = unit.stats.mov - int(move_range[move_pos])
	var main_plan: Dictionary = {}
	for support: Dictionary in supports:
		if str(support["action_cost"]) != "standard":
			continue
		main_plan = _plan_support(unit, planner, support, free_cells, preferred, scored)
		if not main_plan.is_empty():
			break

	var final_pos: Vector2i = unit.grid_position
	var main_action: GameAction = null
	if not main_plan.is_empty():
		final_pos = main_plan["pos"]
		main_action = GameAction.make_skill(unit, main_plan["skill_id"],
			main_plan["target_pos"], main_plan.get("target"))
	elif not best.is_empty():
		final_pos = best["pos"]
		var attack_skill: String = str(best.get("skill_id", ""))
		if attack_skill == "":
			main_action = GameAction.make_attack(unit, best["target"])
		else:
			main_action = GameAction.make_skill(unit, attack_skill, best["target_pos"], best.get("target"))

	# 迅捷技能：已有主动作时只在它的站位施放；没有主动作时，第一个能用的迅捷技能决定站位。
	var swift_actions: Array[GameAction] = []
	var pos_fixed: bool = main_action != null
	for support: Dictionary in supports:
		if str(support["action_cost"]) != "swift":
			continue
		var cells: Dictionary = {final_pos: free_cells.get(final_pos, 0)} if pos_fixed else free_cells
		var plan: Dictionary = _plan_support(unit, planner, support, cells, preferred, scored)
		if plan.is_empty():
			continue
		final_pos = plan["pos"]
		pos_fixed = true
		swift_actions.append(GameAction.make_skill(unit, plan["skill_id"],
			plan["target_pos"], plan.get("target")))

	if main_action == null and swift_actions.is_empty():
		# 4. 什么都做不了：没有普攻的单位（牧师）靠近友军待命（用户 2026-10-31）；
		#    其余单位走向最近的玩家单位。
		if not unit.has_basic_attack:
			final_pos = _standby_cell(unit, all_units, targets, free_cells)
		else:
			var nearest: Unit = _find_nearest(unit.grid_position, targets)
			if nearest:
				final_pos = _closest_reachable_to(move_range, nearest.grid_position, unit, grid)

	if final_pos != unit.grid_position:
		actions.append(GameAction.make_move(unit, final_pos))
	actions.append_array(swift_actions)
	if main_action != null:
		actions.append(main_action)
	return actions


## 一个目标的得分。返回 `{"score": float, "kill": bool}`，`kill` 指这一击有机会击杀。
static func score_target(unit: Unit, target: Unit, forecast: Callable,
		cfg: Dictionary) -> Dictionary:
	var preview: Dictionary = forecast.call(unit, target) if forecast.is_valid() \
		else DamageCalculator.preview_attack(unit, target, {})
	var hit_rate: float = float(preview.get("hit_percent", 0)) / 100.0
	var crit_rate: float = float(preview.get("crit_percent", 0)) / 100.0
	var damage: int = int(preview.get("damage", 0))
	var crit_damage: int = int(preview.get("crit_damage", damage))
	# 护盾先于生命吸收伤害；〔影〕每包固定扣生命，不看护盾。
	var durability: int = target.stats.hp
	if not target.is_illusion:
		durability += target.shield
	# 击杀概率：普通伤害够击杀时等于命中率；只有暴击才够时为命中率 × 暴击率。
	var kill_p: float = 0.0
	if damage >= durability:
		kill_p = hit_rate
	elif crit_damage >= durability:
		kill_p = hit_rate * crit_rate
	# 有效伤害：超出目标剩余耐久的部分不计。
	var score: float = hit_rate * float(mini(damage, durability)) \
		* float(cfg.get("damage_weight", 1.0))
	score += kill_p * float(cfg.get("kill_bonus", 0.0))
	if target.is_illusion:
		score += float(cfg.get("decoy_bonus", 0.0))
	return {"score": score, "kill": kill_p > 0.0,
		"expected": hit_rate * float(mini(damage, durability)) * float(cfg.get("damage_weight", 1.0))}


## 一次技能施放的候选。单体技能按单体得分；AOE 按范围内期望伤害之和，不加击杀分与诱饵分。
## 站在目标格上的单位按主目标预告，其余按溅射预告（与执行时的 area_damage_multiplier 一致）。
## `cache`：「技能 id」或「技能 id#splash」→ {目标: score_target 的结果}，每种情况只预告一次。
static func _skill_candidate(unit: Unit, planner: Object, skill_id: String, cast: Dictionary,
		pos: Vector2i, move_cost: int, cache: Dictionary, cfg: Dictionary) -> Dictionary:
	var target_unit: Unit = cast.get("target_unit")
	var cand: Dictionary = {}
	if bool(cast.get("single", false)):
		cand = _candidate(pos, move_cost, target_unit,
			_cached_skill_score(unit, planner, skill_id, target_unit, true, cache, cfg))
	else:
		var total: float = 0.0
		for hit_unit: Unit in cast.get("hit_units", []):
			var primary: bool = hit_unit.grid_position == cast.get("target_pos")
			total += float(_cached_skill_score(unit, planner, skill_id, hit_unit, primary,
				cache, cfg).get("expected", 0.0))
		cand = {"pos": pos, "move_cost": move_cost, "target": target_unit,
			"score": total, "kill": false}
	cand["skill_id"] = skill_id
	cand["target_pos"] = cast.get("target_pos")
	return cand


static func _cached_skill_score(unit: Unit, planner: Object, skill_id: String, target: Unit,
		primary: bool, cache: Dictionary, cfg: Dictionary) -> Dictionary:
	var key: String = skill_id if primary else skill_id + "#splash"
	if not cache.has(key):
		cache[key] = {}
	var by_target: Dictionary = cache[key]
	if not by_target.has(target):
		var forecast: Callable = func(attacker: Unit, t: Unit) -> Dictionary:
			return planner._ai_forecast_skill(attacker, t, skill_id, primary)
		by_target[target] = score_target(unit, target, forecast, cfg)
	return by_target[target]


# ── Helpers ──────────────────────────────────────────

static func _config() -> Dictionary:
	# 静态函数拿不到 autoload 标识符，从场景树取 DataLoader。
	var cfg: Dictionary = {}
	var tree := Engine.get_main_loop() as SceneTree
	var data_loader: Node = tree.root.get_node_or_null("DataLoader") if tree != null else null
	if data_loader != null and data_loader.get("ai") is Dictionary:
		cfg = (data_loader.get("ai") as Dictionary).get(CONFIG_ID, {})
	if cfg.is_empty():
		push_warning("[EnemyAI] 缺 data/ai/target_scoring.json，只按期望伤害选目标")
	return cfg


static func _in_range(pos: Vector2i, target: Unit,
		atk_min_range: int, atk_range: int) -> bool:
	var dist: int = _manhattan(pos, target.grid_position)
	return dist >= atk_min_range and dist <= atk_range


static func _candidate(pos: Vector2i, move_cost: int, target: Unit,
		target_score: Dictionary) -> Dictionary:
	return {
		"pos": pos,
		"move_cost": move_cost,
		"target": target,
		"score": float(target_score.get("score", 0.0)),
		"kill": bool(target_score.get("kill", false)),
	}


## `a` 是否优于 `b`：得分高者优先；同分时按 `tie_break` 依次比较，
## 最后比站位坐标（先 y 后 x），保证结果确定、不掷骰。
static func _better(a: Dictionary, b: Dictionary, tie_break: Array) -> bool:
	var diff: float = float(a["score"]) - float(b["score"])
	if absf(diff) > SCORE_EPSILON:
		return diff > 0.0
	# 以格子或方向为目标的技能没有目标单位：跳过「目标生命」，「目标格」比较选中的格子。
	var ta: Unit = a.get("target")
	var tb: Unit = b.get("target")
	for key: Variant in tie_break:
		match str(key):
			"kill":
				if a["kill"] != b["kill"]:
					return bool(a["kill"])
			"move_cells":
				if a["move_cost"] != b["move_cost"]:
					return int(a["move_cost"]) < int(b["move_cost"])
			"target_hp":
				if ta != null and tb != null and ta.stats.hp != tb.stats.hp:
					return ta.stats.hp < tb.stats.hp
			"cell_yx":
				var cmp: int = _compare_yx(_target_cell(a), _target_cell(b))
				if cmp != 0:
					return cmp < 0
	return _compare_yx(a["pos"], b["pos"]) < 0


static func _target_cell(cand: Dictionary) -> Vector2i:
	var target: Unit = cand.get("target")
	if target != null:
		return target.grid_position
	return cand.get("target_pos", cand["pos"])


static func _compare_yx(a: Vector2i, b: Vector2i) -> int:
	if a.y != b.y:
		return -1 if a.y < b.y else 1
	if a.x != b.x:
		return -1 if a.x < b.x else 1
	return 0


## R1.18：站位已定（`chosen` 的 pos），在那里射程内的嘲讽单位中按原优先级（得分与决胜顺序）选。
## 没有带嘲讽的合法目标时返回空字典，沿用原选择。
static func _pick_taunting_target(chosen: Dictionary, targets: Array[Unit],
		scored: Dictionary, atk_min_range: int, atk_range: int,
		tie_break: Array) -> Dictionary:
	var best: Dictionary = {}
	var pos: Vector2i = chosen["pos"]
	for target in targets:
		if not target.has_taunt() or not _in_range(pos, target, atk_min_range, atk_range):
			continue
		var cand: Dictionary = _candidate(pos, int(chosen["move_cost"]), target, scored[target])
		if best.is_empty() or _better(cand, best, tie_break):
			best = cand
	return best


## 一个功能技能在 `cells`（站位 → 移动消耗）里最好的施放方式；没有合法施放方式时返回空字典。
## 按 `support.kind` 比较（用户 2026-10-31）：
##   debuff：优先能打到这个敌人攻击时会选的目标 `preferred`，其次按范围内目标的攻击得分之和；
##           选单位的减益在站位定下后优先嘲讽单位（R1.18）。
##   heal：只在有人缺血时用，按实际补回的生命之和比较。
##   buff：选单位的单体增益给生命比例最低的友军；范围或自身增益按「还没有这些状态」的友军人数比较，
##         人数为 0 时不用。
## 同分时移动少的优先，再比站位格与目标格（先 y 后 x）。
static func _plan_support(unit: Unit, planner: Object, support: Dictionary, cells: Dictionary,
		preferred: Unit, scored: Dictionary) -> Dictionary:
	var skill_id: String = support["skill_id"]
	var kind: String = support["kind"]
	var best: Dictionary = {}
	var best_key: Array = []
	for pos: Vector2i in cells:
		for cast: Dictionary in planner._ai_skill_casts(unit, skill_id, pos):
			var key: Array = _support_key(kind, support, cast, preferred, scored)
			if key.is_empty():
				continue
			key.append(-int(cells[pos]))
			if best.is_empty() or _key_better(key, best_key, pos, best["pos"],
					cast["target_pos"], best["target_pos"]):
				best = {"pos": pos, "skill_id": skill_id, "target_pos": cast["target_pos"],
					"target": cast.get("target_unit")}
				best_key = key
	if kind == "debuff" and not best.is_empty() and best.get("target") != null:
		var taunt_best: Dictionary = {}
		var taunt_key: Array = []
		for cast: Dictionary in planner._ai_skill_casts(unit, skill_id, best["pos"]):
			var target_unit: Unit = cast.get("target_unit")
			if target_unit == null or not target_unit.has_taunt():
				continue
			var key: Array = _support_key(kind, support, cast, preferred, scored)
			if key.is_empty():
				continue
			if taunt_best.is_empty() or _key_better(key, taunt_key, best["pos"], best["pos"],
					cast["target_pos"], taunt_best["target_pos"]):
				taunt_best = {"pos": best["pos"], "skill_id": skill_id,
					"target_pos": cast["target_pos"], "target": target_unit}
				taunt_key = key
		if not taunt_best.is_empty():
			best = taunt_best
	return best


## 一次功能技能施放的比较键（越大越好）；不值得施放时返回空数组。
static func _support_key(kind: String, support: Dictionary, cast: Dictionary,
		preferred: Unit, scored: Dictionary) -> Array:
	var hit_units: Array = cast.get("hit_units", [])
	if hit_units.is_empty():
		return []
	match kind:
		"debuff":
			var total: float = 0.0
			for hit_unit: Unit in hit_units:
				total += float((scored.get(hit_unit, {}) as Dictionary).get("score", 0.0))
			return [1 if hit_units.has(preferred) else 0, total]
		"heal":
			var healed: int = 0
			for hit_unit: Unit in hit_units:
				healed += mini(hit_unit.preview_heal(int(support["heal"])),
					hit_unit.stats.max_hp - hit_unit.stats.hp)
			return [healed] if healed > 0 else []
		_:
			var target_unit: Unit = cast.get("target_unit")
			if bool(cast.get("single", false)) and target_unit != null \
					and not bool(cast.get("self", false)):
				# 单体友方增益：给生命比例最低的友军（用户 2026-10-31 护盾术）。
				return [-float(target_unit.stats.hp) / maxf(1.0, float(target_unit.stats.max_hp))]
			var lacking: int = 0
			for hit_unit: Unit in hit_units:
				if _lacks_any(hit_unit, support["effect_ids"]):
					lacking += 1
			return [lacking] if lacking > 0 else []


static func _lacks_any(target: Unit, effect_ids: Array) -> bool:
	for effect_id: Variant in effect_ids:
		var id: String = str(effect_id)
		if id == "shield":
			if target.shield <= 0:
				return true
		elif id.begins_with("held:"):
			if not target.held_states.has(id.trim_prefix("held:")):
				return true
		elif target.get_buff(id) == null:
			return true
	return false


## 键逐项比较，大者优先；全部相同时移动少的已在键末尾，再比站位格与目标格（先 y 后 x）。
static func _key_better(a: Array, b: Array, pos_a: Vector2i, pos_b: Vector2i,
		cell_a: Vector2i, cell_b: Vector2i) -> bool:
	for i: int in range(mini(a.size(), b.size())):
		if absf(float(a[i]) - float(b[i])) > SCORE_EPSILON:
			return float(a[i]) > float(b[i])
	var cmp: int = _compare_yx(pos_a, pos_b)
	if cmp != 0:
		return cmp < 0
	return _compare_yx(cell_a, cell_b) < 0


## 没有普攻、也没有可用技能的单位（牧师）靠近友军待命（用户 2026-10-31）：
## 走到离最近友军最近的格子；相同时离最近玩家单位远的优先，再比移动少、格子先 y 后 x。
static func _standby_cell(unit: Unit, all_units: Array, targets: Array[Unit],
		cells: Dictionary) -> Vector2i:
	var allies: Array[Unit] = []
	for u in all_units:
		if u != unit and u.faction == unit.faction and u.stats.is_alive() and not u.is_illusion:
			allies.append(u)
	if allies.is_empty():
		return unit.grid_position
	var best_pos: Vector2i = unit.grid_position
	var best_key: Array = []
	for pos: Vector2i in cells:
		var ally_dist: int = _manhattan(pos, _find_nearest(pos, allies).grid_position)
		var enemy_dist: int = 0
		var nearest_enemy: Unit = _find_nearest(pos, targets)
		if nearest_enemy != null:
			enemy_dist = _manhattan(pos, nearest_enemy.grid_position)
		var key: Array = [-ally_dist, enemy_dist, -int(cells[pos])]
		if best_key.is_empty() or _key_better(key, best_key, pos, best_pos, pos, best_pos):
			best_pos = pos
			best_key = key
	return best_pos


## R1.18 的技能版：站位与技能已定，在该站位上这个技能的施放方式里，只看选中嘲讽单位的那些，
## 按同一套打分选。没有时返回空字典。
static func _pick_taunting_cast(unit: Unit, planner: Object, chosen: Dictionary,
		cache: Dictionary, cfg: Dictionary, tie_break: Array) -> Dictionary:
	var best: Dictionary = {}
	var skill_id: String = chosen["skill_id"]
	for cast: Dictionary in planner._ai_skill_casts(unit, skill_id, chosen["pos"]):
		var target_unit: Unit = cast.get("target_unit")
		if target_unit == null or not target_unit.has_taunt():
			continue
		var cand: Dictionary = _skill_candidate(unit, planner, skill_id, cast,
			chosen["pos"], int(chosen["move_cost"]), cache, cfg)
		if best.is_empty() or _better(cand, best, tie_break):
			best = cand
	return best


static func _find_nearest(origin: Vector2i,
		targets: Array[Unit]) -> Unit:
	var best: Unit = null
	var best_dist: int = 99999
	for target in targets:
		var dist: int = _manhattan(origin, target.grid_position)
		if dist < best_dist:
			best_dist = dist
			best = target
	return best


static func _closest_reachable_to(move_range: Dictionary,
		goal: Vector2i, unit: Unit, grid: Grid) -> Vector2i:
	var best_pos: Vector2i = unit.grid_position
	var best_dist: int = _manhattan(unit.grid_position, goal)
	for pos: Vector2i in move_range:
		var cell := grid.get_cell(pos)
		if cell.occupant != null and cell.occupant != unit:
			continue
		var dist: int = _manhattan(pos, goal)
		if dist < best_dist:
			best_dist = dist
			best_pos = pos
	return best_pos


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
