extends SceneTree
## 普通敌人使用攻击技能（用户 2026-10-31 逐项收束）：
##   单个攻击技能只决定打谁、站哪打；AOE 只比总期望伤害；两种攻击都够得着时比得分。
##
## 依据：KB 01-Game-Design/Core-Systems/enemy-and-ai.md「现行实现」；R1.18（嘲讽）。
## 覆盖：
##   ① 查询：能用的攻击技能（冷却中的不算）；施放方式与 AOE 范围内的目标。
##   ② 两种攻击：近战与投掷都够得着时选得分高的近战；只有投掷够得着时投掷。
##   ③ AOE：范围内两人时法球的总期望伤害高于单体普攻；只有一人时普攻得分更高。
##   ④ 嘲讽（R1.18）：选单位的技能改打嘲讽单位；以格子为目标的技能不受影响。
##   ④b 移动后重建：先移动再放的技能按新位置重建，受影响单位与决策时相同；没移动时跳过。
##   ⑤ 执行：按技能 id 构建动作并结算，命中范围内的两人，进入冷却。
##
## 运行：
##   <Godot_console.exe> --headless --path <worktree> --script res://tests/test_enemy_ai_skills.gd

const THROW := "goblin_brave_throw"
const BURST := "goblin_mage_burst"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []


func _initialize() -> void:
	print("=== test_enemy_ai_skills（普通敌人使用攻击技能）===")
	_run.call_deferred()


func _run() -> void:
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	scene.run_injected = true
	scene.injected_map_id = "test_arena"
	scene.injected_player_units = [
		{"class_id": "kensei", "pos": Vector2i(1, 1)},
		{"class_id": "kensei", "pos": Vector2i(2, 1)},
		{"class_id": "kensei", "pos": Vector2i(6, 6)},
	]
	scene.injected_enemy_units = [
		{"class_id": "goblin_brave", "pos": Vector2i(6, 3)},
		{"class_id": "goblin_mage", "pos": Vector2i(4, 6)},
	]
	scene.debug_harness_enabled = false
	root.add_child(scene)
	await process_frame
	await process_frame

	var tm: Node = scene.get_node("TacticalManager")
	_check("tactical_manager 脚本已挂载", tm.get_script() != null
		and (tm.get_script() as Script).resource_path == "res://scripts/core/tactical_manager.gd")
	if tm.turn_manager != null:
		tm.turn_manager.stop()
	var players: Dictionary = {}
	var brave: Unit = null
	var mage: Unit = null
	for u: Variant in tm.units:
		if not u is Unit:
			continue
		var unit: Unit = u
		if unit.unit_id == "goblin_brave":
			brave = unit
		elif unit.unit_id == "goblin_mage":
			mage = unit
		elif unit.faction != "enemy":
			players[unit.grid_position] = unit
			unit.stats.max_hp = 999
			unit.stats.hp = 999
	var a: Unit = players.get(Vector2i(1, 1))
	var b: Unit = players.get(Vector2i(2, 1))
	var c: Unit = players.get(Vector2i(6, 6))
	if a == null or b == null or c == null or brave == null or mage == null:
		_check("场景含三名剑圣、勇士与法师", false)
		_finish(scene)
		return
	for e: Unit in [brave, mage]:
		e.stats.dex = 300
		e.stats.max_hp = 999
		e.stats.hp = 999

	_test_queries(tm, a, b, mage)
	_test_two_attacks(tm, a, b, brave)
	_test_aoe(tm, a, b, c, mage)
	_test_taunt(tm, a, b, c, brave, mage)
	_test_move_rebuild(tm, mage)
	_test_execute(tm, a, b, mage)
	_finish(scene)


# ── ① 查询 ───────────────────────────────────────────

func _test_queries(tm: Node, a: Unit, b: Unit, mage: Unit) -> void:
	print("\n[①] 查询")
	mage.reset_action_resources()
	_eq("法师能用的攻击技能", tm._ai_attack_skill_ids(mage), [BURST])
	mage.skill_cooldowns[BURST] = 2
	_eq("冷却中：不算能用", tm._ai_attack_skill_ids(mage), [])
	mage.skill_cooldowns.clear()
	# 法球射程 1–2、菱形半径 2：站在 (4,1) 选 (2,1)，范围内有 A 与 B。
	var found: bool = false
	for cast: Dictionary in tm._ai_skill_casts(mage, BURST, Vector2i(4, 1)):
		if cast["target_pos"] == Vector2i(2, 1):
			var hit: Array = cast["hit_units"]
			found = hit.size() == 2 and hit.has(a) and hit.has(b) and not bool(cast["single"])
	_check("站 (4,1) 选 (2,1)：范围内是 A 与 B", found)


# ── ② 两种攻击 ───────────────────────────────────────

func _test_two_attacks(tm: Node, a: Unit, b: Unit, brave: Unit) -> void:
	print("\n[②] 两种攻击")
	# 勇士站 (1,2)、不能再移动：近战够得着 A，投掷（2–3 格）够得着 B。普攻威力 100 高于投掷 90。
	_place(tm, brave, Vector2i(1, 2))
	brave.reset_action_resources()
	brave.movement_used = true
	var acts: Array[GameAction] = _decide(tm, brave)
	_check("近战与投掷都够得着：用近战打 A", acts.size() == 1
		and acts[0].type == GameAction.Type.ATTACK and acts[0].target_unit == a)
	# 站 (1,3)：A 距 2、B 距 3，近战够不着，只能投掷。
	_place(tm, brave, Vector2i(1, 3))
	acts = _decide(tm, brave)
	_check("只有投掷够得着：投掷", acts.size() == 1
		and acts[0].type == GameAction.Type.SKILL and str(acts[0].data.get("skill_id", "")) == THROW)
	# 同分（两人满血、同样的命中与伤害）按目标格先 y 后 x：A (1,1) 在 B (2,1) 前。
	_check("投掷目标按决胜顺序是 A", acts.size() == 1 and acts[0].target_unit == a)
	_place(tm, brave, Vector2i(6, 3))


# ── ③ AOE ───────────────────────────────────────────

func _test_aoe(tm: Node, a: Unit, b: Unit, c: Unit, mage: Unit) -> void:
	print("\n[③] AOE")
	var cfg: Dictionary = EnemyAI._config()
	_place(tm, mage, Vector2i(4, 1))
	mage.reset_action_resources()
	mage.movement_used = true
	var acts: Array[GameAction] = _decide(tm, mage)
	_check("范围内两人：用法球", acts.size() == 1 and acts[0].type == GameAction.Type.SKILL
		and str(acts[0].data.get("skill_id", "")) == BURST)
	# 得分 = 两人各自期望伤害之和，不加击杀分。
	var cast: Dictionary = {"target_pos": Vector2i(2, 1), "target_unit": null,
		"hit_units": [a, b], "single": false}
	var cand: Dictionary = EnemyAI._skill_candidate(mage, tm, BURST, cast, Vector2i(4, 1), 0, {}, cfg)
	# B 站在目标格上按主目标算，A 按溅射算。
	var fa: Callable = func(x: Unit, t: Unit) -> Dictionary: return tm._ai_forecast_skill(x, t, BURST)
	var fs: Callable = func(x: Unit, t: Unit) -> Dictionary: return tm._ai_forecast_skill(x, t, BURST, false)
	var expected: float = float(EnemyAI.score_target(mage, a, fs, cfg)["expected"]) \
		+ float(EnemyAI.score_target(mage, b, fa, cfg)["expected"])
	_check("AOE 得分 = 期望伤害之和", is_equal_approx(float(cand["score"]), expected) and expected > 0.0,
		"score %s expected %s" % [str(cand["score"]), str(expected)])
	_check("AOE 不计击杀", not bool(cand["kill"]))
	# B 一击可杀时：单体打分会加击杀分，AOE 仍只算期望伤害。
	b.stats.hp = 1
	var b_single: Dictionary = EnemyAI.score_target(mage, b, fa, cfg)
	_check("前提：B 的单体得分含击杀分", bool(b_single["kill"])
		and float(b_single["score"]) > float(b_single["expected"]) + 0.01)
	cand = EnemyAI._skill_candidate(mage, tm, BURST, cast, Vector2i(4, 1), 0, {}, cfg)
	var low_expected: float = float(EnemyAI.score_target(mage, a, fs, cfg)["expected"]) \
		+ float(b_single["expected"])
	_check("可击杀目标在范围内：AOE 仍不加击杀分", is_equal_approx(float(cand["score"]), low_expected),
		"score %s expected %s" % [str(cand["score"]), str(low_expected)])
	b.stats.hp = b.stats.max_hp
	# 只有 A 够得着时：普攻（单体，可加击杀分）与法球（只计期望伤害）直接比得分，选高的。
	_place(tm, b, Vector2i(6, 4))
	_place(tm, mage, Vector2i(3, 1))
	var basic_score: float = float(EnemyAI.score_target(mage, a,
		Callable(tm, "_forecast_attack_for_ai"), cfg)["score"])
	var burst_score: float = float(EnemyAI.score_target(mage, a, fa, cfg)["expected"])
	_check("前提：两种出手得分不同", absf(basic_score - burst_score) > 0.01,
		"普攻 %s 法球 %s" % [str(basic_score), str(burst_score)])
	acts = _decide(tm, mage)
	var want_burst: bool = burst_score > basic_score
	_check("只有一人：选得分高的那种（普攻 %.2f / 法球 %.2f）" % [basic_score, burst_score],
		acts.size() == 1 and (acts[0].type == GameAction.Type.SKILL) == want_burst)
	_place(tm, b, Vector2i(2, 1))
	_place(tm, mage, Vector2i(4, 6))


# ── ④ 嘲讽 ───────────────────────────────────────────

func _test_taunt(tm: Node, a: Unit, b: Unit, c: Unit, brave: Unit, mage: Unit) -> void:
	print("\n[④] 嘲讽（R1.18）")
	_place(tm, brave, Vector2i(1, 3))
	brave.reset_action_resources()
	brave.movement_used = true
	b.held_states.apply("taunt", 1, {"kind": "permanent"})
	_check("前提：B 有嘲讽", b.has_taunt())
	var acts: Array[GameAction] = _decide(tm, brave)
	_check("选单位的投掷改打嘲讽的 B", acts.size() == 1
		and acts[0].type == GameAction.Type.SKILL and acts[0].target_unit == b)
	b.held_states.remove("taunt")
	_place(tm, brave, Vector2i(6, 3))
	# 法球以格子为目标：带嘲讽的 C 在某些法球范围里，但打 A、B 的范围得分更高，照样打 A、B。
	_place(tm, c, Vector2i(6, 2))
	c.held_states.apply("taunt", 1, {"kind": "permanent"})
	_place(tm, mage, Vector2i(4, 1))
	mage.reset_action_resources()
	mage.movement_used = true
	var c_reachable: bool = false
	for cast: Dictionary in tm._ai_skill_casts(mage, BURST, Vector2i(4, 1)):
		if (cast["hit_units"] as Array).has(c):
			c_reachable = true
	_check("前提：有法球范围能打到嘲讽的 C", c_reachable)
	acts = _decide(tm, mage)
	var hit: Array = []
	if acts.size() == 1 and str(acts[0].data.get("skill_id", "")) == BURST:
		for cast: Dictionary in tm._ai_skill_casts(mage, BURST, Vector2i(4, 1)):
			if cast["target_pos"] == acts[0].target_pos:
				hit = cast["hit_units"]
	_check("格子目标的法球不受嘲讽影响：打 A、B", hit.size() == 2 and hit.has(a) and hit.has(b))
	c.held_states.remove("taunt")
	_place(tm, c, Vector2i(6, 6))


# ── ④b 移动后重建 ───────────────────────────────────

func _test_move_rebuild(tm: Node, mage: Unit) -> void:
	print("\n[④b] 移动后按新位置重建技能")
	_place(tm, mage, Vector2i(6, 1))
	mage.reset_action_resources()
	mage.skill_cooldowns.clear()
	var acts: Array[GameAction] = _decide(tm, mage)
	_check("要先移动再放法球", acts.size() == 2 and acts[0].type == GameAction.Type.MOVE
		and acts[1].type == GameAction.Type.SKILL)
	if acts.size() != 2:
		_place(tm, mage, Vector2i(4, 1))
		return
	var skill_act: GameAction = acts[1]
	# 没移动就重建：目标格不是这个位置上的合法施放方式，跳过。
	_check("没移动时不重建", tm._rebuild_ai_skill_action(mage, skill_act) == null)
	var decided: Array = []
	for cast: Dictionary in tm._ai_skill_casts(mage, BURST, acts[0].target_pos):
		if cast["target_pos"] == skill_act.target_pos:
			decided = cast["hit_units"]
	GameAction.consume_normal_move(mage)
	_place(tm, mage, acts[0].target_pos)
	tm._targeting_direction = Vector2i(1, 0)
	var rebuilt: GameAction = tm._rebuild_ai_skill_action(mage, skill_act)
	_check("移动后重建成功，残留方向已清零",
		rebuilt != null and tm._targeting_direction == Vector2i.ZERO)
	if rebuilt != null:
		var cells: Array[Vector2i] = tm._extract_cells_from_payload(
			rebuilt.data.get("affected_cells", []))
		var affected: Array = tm._get_units_in_skill_area(mage, tm._get_skill_data(BURST), cells)
		_check("重建后的受影响单位与决策时相同", not decided.is_empty()
			and affected.size() == decided.size()
			and decided.all(func(u: Unit) -> bool: return affected.has(u)),
			"决策 %d 人 重建 %d 人" % [decided.size(), affected.size()])
	_place(tm, mage, Vector2i(4, 1))


# ── ⑤ 执行 ───────────────────────────────────────────

func _test_execute(tm: Node, a: Unit, b: Unit, mage: Unit) -> void:
	print("\n[⑤] 执行")
	mage.reset_action_resources()
	mage.skill_cooldowns.clear()
	var hp_a: int = a.stats.hp
	var hp_b: int = b.stats.hp
	# 与 _do_enemy_turn 的技能分支相同：按技能 id 与当时的位置构建，再结算。
	tm._targeting_direction = Vector2i.ZERO
	var cast: GameAction = tm._build_skill_action(mage, Vector2i(2, 1), null,
		tm.LANDING_ANCHOR_NONE, BURST)
	_check("按技能 id 构建动作", cast != null and str(cast.data.get("skill_id", "")) == BURST
		and str(cast.data.get("attack_type", "")) == "area")
	_check("法球执行成功", cast != null and bool(tm._execute_skill_action(cast)))
	_check("A 与 B 都受伤", a.stats.hp < hp_a and b.stats.hp < hp_b,
		"A %d→%d B %d→%d" % [hp_a, a.stats.hp, hp_b, b.stats.hp])
	_check("法球进入冷却", not mage.is_skill_available(BURST))
	mage.reset_action_resources()
	_eq("冷却中 AI 不再选它", tm._ai_attack_skill_ids(mage), [])


# ── 工具 ─────────────────────────────────────────────

func _decide(tm: Node, unit: Unit) -> Array[GameAction]:
	return EnemyAI.decide_actions(unit, tm.grid, tm.units,
		Callable(tm, "_forecast_attack_for_ai"), tm)


func _place(tm: Node, unit: Unit, pos: Vector2i) -> void:
	if unit.grid_position == pos:
		return
	tm.grid.move_unit(unit, unit.grid_position, pos)
	unit.grid_position = pos


func _finish(scene: Node) -> void:
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  ✗ " + f)
	scene.queue_free()
	await process_frame
	quit(1 if _fail > 0 else 0)


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		var line: String = name + ("  [" + detail + "]" if detail != "" else "")
		_fails.append(line)
		print("  ✗ " + line)


func _eq(name: String, actual: Variant, expected: Variant) -> void:
	_check(name, actual == expected, "期望 %s 实际 %s" % [str(expected), str(actual)])
