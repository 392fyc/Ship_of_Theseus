extends SceneTree
## 批量战斗模拟（用户 2026-10-31：用引擎无界面批量跑「剑圣、剑士对哥布林」的完整战斗，双方都由 AI 行动；
## 重点看 AI 是否合理、技能机制是否符合预期、有没有自叠加或矛盾、资源循环怎么构成；数值只作参考）。
##
## 每个阵容 × 每种回忆配置（不兑现 + 每张回忆单独兑现）× 每个随机种子跑一场。输出：
##   - battles.jsonl：每场一行。结果、回合数、种子、回忆是否真的兑现，以及每个单位的伤害、承伤、
##     成功执行的动作与技能次数、剑气按来源的增减与被上限截掉的量、持有状态顶到上限的回合数、额外回合数。
##   - actions.jsonl：每个 AI 动作一行。回合、行动单位、动作、目标与目标剩余生命、是否成功、
##     这个动作期间造成的伤害与剑气变动次数。用来判断 AI 是否合理。
##   - events.jsonl：异常事件。越界检查（生命、护盾、剑气、印记、持有状态层数、冷却；多数值在写入时已被
##     截断，所以另记「截断」与「重复触发」）、同一动作里同一来源的剑气变动超过阈值、单回合动作过多、
##     额外回合连锁、回合结束时普攻射程内有敌人却没有出手。
##   - 标准输出里的 [SIM] battle_begin / battle_end 标记，供 analyze.py 把 Godot 自身的报错归到具体战斗。
## 同一种子与配置可以复现同一场战斗。
##
## 运行（Godot 4.6 控制台版）：
##   <Godot> --headless --path <worktree> --script res://tools/sim/battle_sim.gd -- --out=<输出目录> [--seeds=N] [--only=<阵容 id>] [--memory=<回忆 id 或 base>]

const SCENE_PATH := "res://scenes/tactical/TacticalScene.tscn"
const SCENARIOS_PATH := "res://tools/sim/scenarios.json"
## 一场战斗的安全上限（帧数）。正常战斗远低于它；到了就记为超时并强制结束。
const MAX_FRAMES_PER_BATTLE := 200000

var _cfg: Dictionary = {}
var _out_dir: String = ""
var _battles: FileAccess
var _actions_file: FileAccess
var _events: FileAccess
var _data_loader: Node
# 运行时加载：SceneTree 脚本编译时 DataLoader 等自动加载还不存在，不能 preload 场景。
var _scene_packed: PackedScene

# 当前战斗的状态
var _battle_id: String = ""
var _tm: Node = null
var _scene: Node = null
var _result: String = ""
var _round: int = 1
var _stats: Dictionary = {}            # unit key → 统计
var _turn_actions: Dictionary = {}     # unit key → 本回合成功执行的动作数（不含移动）
var _turn_flagged: Dictionary = {}     # unit key → 本回合已记过「动作过多」
var _turn_controlled: Dictionary = {}
var _extra_turns_round: Dictionary = {}  # unit key → 本轮额外回合数
var _action: Dictionary = {}           # 正在执行的 AI 动作（窗口）；空表示不在动作中
var _status_damage: int = 0            # 不在任何动作窗口里结算的伤害（持续伤害等）


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_data_loader = root.get_node("/root/DataLoader")
	_scene_packed = load(SCENE_PATH)
	var args: Dictionary = _parse_args(OS.get_cmdline_user_args())
	_out_dir = str(args.get("out", ""))
	if _out_dir == "":
		push_error("[SIM] 缺少 --out=<输出目录>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_cfg = JSON.parse_string(FileAccess.get_file_as_string(SCENARIOS_PATH))
	var seeds: int = int(args.get("seeds", _cfg.get("seeds", 5)))
	var only: String = str(args.get("only", ""))
	var only_memory: String = str(args.get("memory", ""))
	_battles = FileAccess.open(_out_dir.path_join("battles.jsonl"), FileAccess.WRITE)
	_actions_file = FileAccess.open(_out_dir.path_join("actions.jsonl"), FileAccess.WRITE)
	_events = FileAccess.open(_out_dir.path_join("events.jsonl"), FileAccess.WRITE)
	Engine.time_scale = float(_cfg.get("time_scale", 1.0))

	var memory_configs: Array[String] = [""]
	for memory_id: Variant in _sorted_keys(_data_loader.get("memories")):
		var memory: Dictionary = (_data_loader.get("memories") as Dictionary)[memory_id]
		if str(memory.get("class_id", "")) == str(_cfg.get("memory_class", "")):
			memory_configs.append(str(memory_id))

	var count: int = 0
	for lineup_v: Variant in _cfg.get("lineups", []):
		var lineup: Dictionary = lineup_v
		if only != "" and str(lineup.get("id", "")) != only:
			continue
		for memory_id: String in memory_configs:
			if only_memory != "" and (memory_id if memory_id != "" else "base") != only_memory:
				continue
			for s: int in range(seeds):
				await _run_battle(lineup, memory_id, s + 1)
				count += 1
	_battles.close()
	_actions_file.close()
	_events.close()
	print("[SIM] done battles=%d out=%s" % [count, _out_dir])
	quit(0)


func _run_battle(lineup: Dictionary, memory_id: String, seed_value: int) -> void:
	_battle_id = "%s|%s|%d" % [str(lineup.get("id", "")), memory_id if memory_id != "" else "base", seed_value]
	_result = ""
	_round = 1
	_stats = {}
	_turn_actions = {}
	_turn_flagged = {}
	_turn_controlled = {}
	_extra_turns_round = {}
	_action = {}
	_status_damage = 0
	seed(seed_value)
	print("[SIM] battle_begin %s" % _battle_id)

	_scene = _scene_packed.instantiate()
	_scene.run_injected = true
	_scene.debug_harness_enabled = false
	_scene.injected_map_id = str(_cfg.get("map_id", "test_arena"))
	var players: Array = []
	var memory_unit_id: String = ""
	for p_v: Variant in _cfg.get("players", []):
		var p: Dictionary = p_v
		var entry: Dictionary = {"class_id": str(p.get("class_id", "")), "pos": _vec(p.get("position", [0, 0]))}
		if bool(p.get("memory_target", false)) and memory_id != "":
			entry["memories"] = [memory_id]
			memory_unit_id = str(p.get("class_id", ""))
		players.append(entry)
	var enemies: Array = []
	for e_v: Variant in lineup.get("enemies", []):
		var e: Dictionary = e_v
		enemies.append({"class_id": str(e.get("class_id", "")), "pos": _vec(e.get("position", [0, 0]))})
	_scene.injected_player_units = players
	_scene.injected_enemy_units = enemies
	_tm = _scene.get_node("TacticalManager")
	_tm.ai_controls_players = true
	_tm.ai_action_started.connect(_on_ai_action_started)
	_tm.ai_action_finished.connect(_on_ai_action_finished)
	# 场景 _ready 会同步开战，回合信号要在加入场景树之前连上（单位要等生成后才能连，
	# 所以第一个回合开始时被动技能造成的剑气变动收不到）。
	var turn_manager: Node = _tm.get_node("TurnManager")
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.turn_ended.connect(_on_turn_ended)
	turn_manager.round_ended.connect(_on_round_ended)
	_scene.battle_ended.connect(func(result: String) -> void: _result = result)
	root.add_child(_scene)
	_watch_new_units()
	var memory_applied: bool = memory_id == "" or _memory_applied(memory_unit_id, memory_id)
	if not memory_applied:
		_event("memory_not_applied", null, "回忆 %s 没有兑现" % memory_id)

	var frames: int = 0
	var max_rounds: int = int(_cfg.get("max_rounds", 30))
	while _result == "":
		await process_frame
		frames += 1
		if _round > max_rounds:
			_result = "stalemate"
		elif frames > MAX_FRAMES_PER_BATTLE:
			_result = "timeout"
			_event("timeout", null, "超过 %d 帧仍未结束" % MAX_FRAMES_PER_BATTLE)
	_check_invariants("battle_end")
	_write_battle(lineup, memory_id, seed_value, memory_applied, mini(_round, max_rounds))
	print("[SIM] battle_end %s result=%s rounds=%d" % [_battle_id, _result, mini(_round, max_rounds)])
	_tm.stop_battle()
	_scene.queue_free()
	await process_frame
	await process_frame


func _memory_applied(unit_id: String, memory_id: String) -> bool:
	var memory: Dictionary = (_data_loader.get("memories") as Dictionary).get(memory_id, {})
	var upgrade: String = str(memory.get("upgrade_skill_id", ""))
	for u: Variant in _tm.units:
		var unit: Unit = u
		if unit.unit_id == unit_id:
			return unit.skill_ids.has(upgrade) or unit.passive_skill_id == upgrade
	return false


# ── 记录 ─────────────────────────────────────────────

## 新出现的单位（开战时生成的、战斗中召唤的〔影〕等）开始统计。每个动作结束后都扫一遍。
func _watch_new_units() -> void:
	for u: Variant in _tm.units:
		_watch_unit(u as Unit)


func _watch_unit(unit: Unit) -> void:
	var key: String = _key(unit)
	if _stats.has(key):
		return
	_stats[key] = {"unit_id": unit.unit_id, "faction": unit.faction, "illusion": unit.is_illusion,
		"damage_dealt": 0, "damage_taken": 0, "counter_damage_dealt": 0, "actions": {},
		"failed_actions": {}, "qi": {}, "qi_capped": {}, "held_at_cap": {}, "died_round": 0,
		"turns": 0, "extra_turns": 0, "idle_turns": 0, "suspicious_idle": 0}
	unit.damage_taken.connect(_on_damage.bind(unit))
	unit.sword_qi_changed.connect(_on_qi)
	unit.unit_died.connect(func() -> void: (_stats[key] as Dictionary)["died_round"] = _round)


## 伤害归属：动作进行中，打到对方阵营的记给行动单位；打到行动单位一方的是反击，记给这次动作的
## 目标（反击来自被打的一方）。不在动作里的伤害（持续伤害等）只记承伤。〔影〕照做的伤害算主人的。
## 伤害量是 damage_taken 的原始数值，含被护盾吸收和打死后溢出的部分。
func _on_damage(amount: int, _damage_type: String, victim: Unit) -> void:
	(_stats[_key(victim)] as Dictionary)["damage_taken"] += amount
	if _action.is_empty():
		_status_damage += amount
		return
	var victims: Dictionary = _action["victims"]
	victims[_key(victim)] = true
	if victim.faction != str(_action["actor_faction"]):
		(_stats[str(_action["actor_key"])] as Dictionary)["damage_dealt"] += amount
		_action["damage"] = int(_action["damage"]) + amount
	else:
		var target_key: String = str(_action["target_key"])
		if target_key != "" and _stats.has(target_key):
			(_stats[target_key] as Dictionary)["counter_damage_dealt"] += amount
		_action["counter_damage"] = int(_action["counter_damage"]) + amount


func _on_qi(unit: Unit, kind: String, requested: int, actual: int, source: String) -> void:
	var st: Dictionary = _stats[_key(unit)]
	var tag: String = "%s:%s" % [kind, source if source != "" else "?"]
	if actual != 0:
		st["qi"][tag] = int((st["qi"] as Dictionary).get(tag, 0)) + actual
	# 获得被上限截掉的部分（自叠加或溢出常常表现为反复撞到上限）。
	if kind == "gain" and requested > actual and actual >= 0:
		st["qi_capped"][tag] = int((st["qi_capped"] as Dictionary).get(tag, 0)) + requested - actual
	if not _action.is_empty():
		var counts: Dictionary = _action["qi_events"]
		var k: String = "%s %s" % [unit.unit_id, tag]
		counts[k] = int(counts.get(k, 0)) + 1


func _on_ai_action_started(unit: Unit, action: GameAction) -> void:
	_watch_unit(unit)
	var label: String = "move"
	match action.type:
		GameAction.Type.ATTACK:
			label = "attack"
		GameAction.Type.SKILL:
			label = "skill:" + str(action.data.get("skill_id", ""))
	# 单位可能在动作中被打死并释放，所以先把要用的信息存成字符串。
	var target: Unit = action.target_unit if is_instance_valid(action.target_unit) else null
	if target != null:
		_watch_unit(target)
	_action = {"actor_key": _key(unit), "actor_id": unit.unit_id, "actor_faction": unit.faction,
		"label": label,
		"target_key": _key(target) if target != null else "",
		"target_id": target.unit_id if target != null else "",
		"target_hp": target.stats.hp if target != null else -1,
		"target_illusion": target.is_illusion if target != null else false,
		"target_pos": [action.target_pos.x, action.target_pos.y],
		"damage": 0, "counter_damage": 0, "qi_events": {}, "victims": {}}


func _on_ai_action_finished(_unit: Unit, _action_obj: GameAction, executed: bool) -> void:
	if _action.is_empty():
		return
	var key: String = str(_action["actor_key"])
	var label: String = _action["label"]
	var st: Dictionary = _stats[key]
	var bucket: String = "actions" if executed else "failed_actions"
	st[bucket][label] = int((st[bucket] as Dictionary).get(label, 0)) + 1
	if executed and label != "move":
		_turn_actions[key] = int(_turn_actions.get(key, 0)) + 1
		if int(_turn_actions[key]) > int(_cfg.get("max_actions_per_turn", 8)) and not _turn_flagged.has(key):
			_turn_flagged[key] = true
			_event_id("too_many_actions", str(_action["actor_id"]), "单回合超过 %d 个动作（%s）" % [
				int(_cfg.get("max_actions_per_turn", 8)), label])
	# 同一动作里同一来源的剑气变动次数超过阈值：可能是自己触发自己（R1.9 / R1.10）。
	# 范围技能每命中一个目标可以各触发一次，所以阈值至少取本次受伤的单位数。
	var threshold: int = maxi(int(_cfg.get("repeat_trigger_threshold", 3)),
		(_action["victims"] as Dictionary).size())
	for k: String in _action["qi_events"]:
		if int(_action["qi_events"][k]) > threshold:
			_event_id("repeat_trigger", str(_action["actor_id"]),
				"%s 期间 %s 触发 %d 次" % [label, k, int(_action["qi_events"][k])])
	var rec: Dictionary = {"battle": _battle_id, "round": _round, "actor": _action["actor_id"],
		"faction": _action["actor_faction"], "action": label, "executed": executed,
		"target": _action["target_id"],
		"target_hp": _action["target_hp"], "target_illusion": _action["target_illusion"],
		"target_pos": _action["target_pos"], "damage": _action["damage"],
		"counter_damage": _action["counter_damage"], "qi_events": _action["qi_events"]}
	_actions_file.store_line(JSON.stringify(rec))
	_action = {}
	_watch_new_units()


func _on_turn_started(unit: Unit) -> void:
	var key: String = _key(unit)
	_watch_unit(unit)
	_action = {}
	_turn_actions[key] = 0
	_turn_flagged.erase(key)
	# 被眩晕、冰冻等控制的回合不算「可出手却没出手」。
	_turn_controlled[key] = unit.get_buff("stun") != null or unit.get_buff("freeze") != null
	if bool(_tm.turn_manager.current_is_extra_turn):
		(_stats[key] as Dictionary)["extra_turns"] += 1
		_extra_turns_round[key] = int(_extra_turns_round.get(key, 0)) + 1
		var limit: int = int(_cfg.get("max_extra_turns_per_round", 2))
		if int(_extra_turns_round[key]) > limit:
			_event("extra_turn_chain", unit, "同一轮第 %d 个额外回合" % int(_extra_turns_round[key]))


## 回合结束的观测推迟到同一帧末尾，在引擎自己的回合结束处理（被动、状态递减等）之后。
## 空闲判定在回合结束信号里同步做：下一个回合（可能是同一单位的额外回合）会立刻开始并清零计数。
## 顶到上限与越界检查推迟到同一帧末尾，在引擎的回合结束处理（被动、状态递减等）之后。
func _on_turn_ended(unit: Unit) -> void:
	var key: String = _key(unit)
	if not _stats.has(key):
		return
	var st: Dictionary = _stats[key]
	st["turns"] += 1
	if int(_turn_actions.get(key, 0)) == 0:
		st["idle_turns"] += 1
		if not bool(_turn_controlled.get(key, false)) and unit.stats.is_alive() \
				and unit.has_basic_attack and _enemy_in_basic_range(unit):
			st["suspicious_idle"] += 1
			_event("idle_with_target", unit, "回合结束时普攻射程内有敌人，却没有出手")
	_after_turn_end.call_deferred(unit, key)


func _after_turn_end(unit: Variant, key: String) -> void:
	if not _stats.has(key) or not is_instance_valid(unit):
		return
	var st: Dictionary = _stats[key]
	# 持有状态顶到上限的回合：叠加被截断时这里会反复出现。
	var held_defs: Dictionary = _data_loader.get("held_states")
	# 只看上限大于 1 的状态：上限为 1 的状态只要持有就算「顶到上限」，没有参考价值。
	for state_id: String in (unit as Unit).held_states.held_ids():
		var cap: int = _held_cap(held_defs, state_id)
		if cap > 1 and (unit as Unit).held_states.stacks(state_id) >= cap:
			st["held_at_cap"][state_id] = int((st["held_at_cap"] as Dictionary).get(state_id, 0)) + 1
	_check_invariants("turn_end")


func _on_round_ended() -> void:
	_round += 1
	_extra_turns_round = {}
	_check_invariants("round_end")


## 回合结束时普攻射程内（与敌人 AI 相同的曼哈顿距离）是否有非幻象敌人。
func _enemy_in_basic_range(unit: Unit) -> bool:
	for u: Variant in _tm.units:
		var other: Unit = u
		if other.faction == unit.faction or not other.stats.is_alive() or other.is_illusion:
			continue
		var d: int = absi(other.grid_position.x - unit.grid_position.x) \
			+ absi(other.grid_position.y - unit.grid_position.y)
		if d >= unit.attack_min_range and d <= unit.attack_range:
			return true
	return false


## 与引擎一致：持有状态没写 max_stacks 时上限按 1（HeldStateSet）。
func _held_cap(held_defs: Dictionary, state_id: String) -> int:
	return maxi(1, int((held_defs.get(state_id, {}) as Dictionary).get("max_stacks", 1)))


## 越界检查。剑气、印记、持有状态层数、不可叠加状态在写入时就被截断，这几项多半查不出问题，
## 叠加与溢出靠 qi_capped、held_at_cap 与 repeat_trigger 观察。
func _check_invariants(when: String) -> void:
	var held_defs: Dictionary = _data_loader.get("held_states")
	var buff_defs: Dictionary = _data_loader.get("buffs")
	for u: Variant in _tm.units:
		var unit: Unit = u
		if not unit.stats.is_alive():
			continue
		if unit.stats.hp < 0 or unit.stats.hp > unit.stats.max_hp:
			_event("hp_out_of_range", unit, "%s：生命 %d / %d" % [when, unit.stats.hp, unit.stats.max_hp])
		if unit.shield < 0:
			_event("shield_negative", unit, "%s：护盾 %d" % [when, unit.shield])
		if unit._qi_max > 0 and (unit.sword_qi < 0 or unit.sword_qi > unit._qi_max):
			_event("qi_out_of_range", unit, "%s：剑气 %d / %d" % [when, unit.sword_qi, unit._qi_max])
		if unit._mark_max > 0 and unit.get_mark_count() > unit._mark_max:
			_event("marks_out_of_range", unit, "%s：印记 %d / %d" % [when, unit.get_mark_count(), unit._mark_max])
		for state_id: String in unit.held_states.held_ids():
			var cap: int = _held_cap(held_defs, state_id)
			var n: int = unit.held_states.stacks(state_id)
			if n < 0 or n > cap:
				_event("held_stacks_out_of_range", unit, "%s：%s %d 层（上限 %d）" % [when, state_id, n, cap])
		for skill_id: Variant in unit.skill_cooldowns:
			if int(unit.skill_cooldowns[skill_id]) < 0:
				_event("cooldown_negative", unit, "%s：%s 冷却 %d" % [when, str(skill_id), int(unit.skill_cooldowns[skill_id])])
		var seen: Dictionary = {}
		for buff: Variant in unit.buffs:
			var buff_id: String = str((buff as BuffEffect).buff_id)
			seen[buff_id] = int(seen.get(buff_id, 0)) + 1
		for buff_id: String in seen:
			var stackable: bool = bool((buff_defs.get(buff_id, {}) as Dictionary).get("stackable", false))
			if not stackable and int(seen[buff_id]) > 1:
				_event("buff_duplicated", unit, "%s：不可叠加的 %s 有 %d 个" % [when, buff_id, int(seen[buff_id])])


func _event(kind: String, unit: Variant, detail: String) -> void:
	var unit_id: String = ""
	if is_instance_valid(unit) and unit is Unit:
		unit_id = (unit as Unit).unit_id
	_event_id(kind, unit_id, detail)


func _event_id(kind: String, unit_id: String, detail: String) -> void:
	var rec: Dictionary = {"battle": _battle_id, "round": _round, "kind": kind, "detail": detail}
	if unit_id != "":
		rec["unit"] = unit_id
	_events.store_line(JSON.stringify(rec))


func _write_battle(lineup: Dictionary, memory_id: String, seed_value: int,
		memory_applied: bool, rounds: int) -> void:
	var rec: Dictionary = {"battle": _battle_id, "lineup": str(lineup.get("id", "")),
		"memory": memory_id if memory_id != "" else "base", "memory_applied": memory_applied,
		"seed": seed_value, "result": _result, "rounds": rounds,
		"status_damage": _status_damage, "units": _stats.values()}
	_battles.store_line(JSON.stringify(rec))
	_battles.flush()
	_actions_file.flush()
	_events.flush()


# ── 工具 ─────────────────────────────────────────────

func _key(unit: Unit) -> String:
	return "%s#%d" % [unit.unit_id, unit.get_instance_id()]


func _vec(v: Variant) -> Vector2i:
	var a: Array = v if v is Array else [0, 0]
	return Vector2i(int(a[0]), int(a[1]))


func _sorted_keys(d: Variant) -> Array:
	var keys: Array = (d as Dictionary).keys() if d is Dictionary else []
	keys.sort()
	return keys


func _parse_args(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for a: String in args:
		if a.begins_with("--") and a.contains("="):
			var parts: PackedStringArray = a.substr(2).split("=", true, 1)
			out[parts[0]] = parts[1]
	return out
