extends SceneTree
## 敌人 AI 加权打分（用户 2026-10-30 按方案页推荐选定：KB 结构、击杀加分 10、射程内也比较移动、
## 站位首期不打分、〔影〕诱饵分 6）。
##
## 依据：KB 01-Game-Design/Core-Systems/enemy-and-ai.md「目标选择」；R1.18（嘲讽）。
## 覆盖：
##   ① 配置：data/ai/target_scoring.json 已加载。
##   ② 单目标得分：期望有效伤害、普通伤害击杀、只有暴击才击杀、护盾算进耐久、〔影〕诱饵分与击杀分。
##   ③ 选择：射程内已有目标时，仍会走一步去打得分更高的目标；同分时不移动；已移动过只比较原地。
##   ③b 同分决胜：能击杀 → 移动少 → 目标生命低 → 目标格 y、x → 站位格。
##   ③c 嘲讽（R1.18）：站位按得分定下，再在射程内的嘲讽单位里按得分选。
##   ④ 预告：TacticalManager 交给 AI 的预告与实际结算一致（普通与暴击）。
##
## 运行：
##   <Godot_console.exe> --headless --path <worktree> --script res://tests/test_enemy_ai_scoring.gd

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []


func _initialize() -> void:
	print("=== test_enemy_ai_scoring（敌人 AI 加权打分）===")
	_run.call_deferred()


func _run() -> void:
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	scene.run_injected = true
	scene.injected_map_id = "test_arena"
	scene.injected_player_units = [
		{"class_id": "kensei", "pos": Vector2i(3, 3)},
		{"class_id": "kensei", "pos": Vector2i(5, 4)},
	]
	scene.injected_enemy_units = [
		{"class_id": "test_lancer", "pos": Vector2i(3, 4)},
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
	var near: Unit = null
	var far: Unit = null
	var enemy: Unit = null
	for u: Variant in tm.units:
		if not u is Unit:
			continue
		var unit: Unit = u
		if unit.faction == "enemy":
			enemy = unit
		elif unit.grid_position == Vector2i(3, 3):
			near = unit
		elif unit.grid_position == Vector2i(5, 4):
			far = unit
	if near == null or far == null or enemy == null:
		_check("场景含两名剑圣与一名敌人", false)
		_finish(scene)
		return

	var dl: Node = root.get_node("/root/DataLoader")
	var cfg: Dictionary = (dl.ai as Dictionary).get("target_scoring", {})
	_test_config(cfg)
	_test_score(near, enemy, cfg)
	_test_choice(tm, near, far, enemy, cfg)
	_test_tie_break(near, far, cfg)
	_test_taunt(tm, near, far, enemy)
	_test_forecast(tm, near, enemy)
	_finish(scene)


# ── ① 配置 ───────────────────────────────────────────

func _test_config(cfg: Dictionary) -> void:
	print("\n[①] 配置")
	_check("target_scoring 已加载", not cfg.is_empty())
	_eq("击杀加分 10（占位）", float(cfg.get("kill_bonus", 0)), 10.0)
	_eq("诱饵分 6（推断）", float(cfg.get("decoy_bonus", 0)), 6.0)
	_eq("决胜顺序", cfg.get("tie_break", []), ["kill", "move_cells", "target_hp", "cell_yx"])


# ── ② 单目标得分 ─────────────────────────────────────

func _test_score(target: Unit, enemy: Unit, cfg: Dictionary) -> void:
	print("\n[②] 单目标得分")
	var w: float = float(cfg.get("damage_weight", 1.0))
	var kb: float = float(cfg.get("kill_bonus", 0.0))
	var decoy: float = float(cfg.get("decoy_bonus", 0.0))
	target.shield = 0
	target.stats.hp = 6

	var s: Dictionary = EnemyAI.score_target(enemy, target, _stub(80, 0, 7, 7), cfg)
	_near("80% 命中、7 伤害打 6 生命：0.8×6 + 0.8×击杀分", float(s["score"]), 0.8 * 6.0 * w + 0.8 * kb)
	_check("能击杀", bool(s["kill"]))

	target.stats.hp = 30
	s = EnemyAI.score_target(enemy, target, _stub(45, 0, 8, 8), cfg)
	_near("打不死：只算期望伤害 0.45×8", float(s["score"]), 0.45 * 8.0 * w)
	_check("不能击杀", not bool(s["kill"]))

	target.stats.hp = 6
	s = EnemyAI.score_target(enemy, target, _stub(50, 20, 4, 8), cfg)
	_near("只有暴击才击杀：0.5×4 + 0.5×0.2×击杀分", float(s["score"]), 0.5 * 4.0 * w + 0.1 * kb)
	_check("暴击击杀也算能击杀", bool(s["kill"]))

	target.shield = 3
	s = EnemyAI.score_target(enemy, target, _stub(80, 0, 7, 7), cfg)
	_near("护盾 3 + 生命 6：打不死，有效伤害 7", float(s["score"]), 0.8 * 7.0 * w)
	_check("护盾挡住击杀", not bool(s["kill"]))
	target.shield = 0

	target.is_illusion = true
	target.stats.hp = 4
	s = EnemyAI.score_target(enemy, target, _stub(100, 0, 1, 1), cfg)
	_near("〔影〕剩 4：1 + 诱饵分", float(s["score"]), 1.0 * w + decoy)
	target.shield = 5
	target.stats.hp = 1
	s = EnemyAI.score_target(enemy, target, _stub(100, 0, 1, 1), cfg)
	_near("〔影〕剩 1：1 + 击杀分 + 诱饵分（不看护盾）", float(s["score"]), 1.0 * w + kb + decoy)
	target.is_illusion = false
	target.shield = 0
	target.stats.hp = target.stats.max_hp


# ── ③ 选择 ───────────────────────────────────────────

func _test_choice(tm: Node, near: Unit, far: Unit, enemy: Unit, cfg: Dictionary) -> void:
	print("\n[③] 选择位置与目标")
	enemy.stats.mov = 3
	enemy.attack_min_range = 1
	enemy.attack_range = 1
	enemy.movement_used = false
	near.stats.hp = 100
	far.stats.hp = 6
	# near 相邻（原地可打），far 要走一步；打 far 能击杀，得分更高。
	var stubs: Dictionary = {near: {"hit_percent": 80, "crit_percent": 0, "damage": 5},
		far: {"hit_percent": 80, "crit_percent": 0, "damage": 7}}
	var forecast: Callable = func(_a: Unit, t: Unit) -> Dictionary: return stubs[t]
	var acts: Array[GameAction] = EnemyAI.decide_actions(enemy, tm.grid, tm.units, forecast)
	_eq("射程内有目标仍比较移动：先移动再攻击", acts.size(), 2)
	if acts.size() == 2:
		_eq("走到 far 旁边移动最少的格子 (4,4)", acts[0].target_pos, Vector2i(4, 4))
		_eq("攻击能击杀的 far", acts[1].target_unit, far)

	# 同分：都打不死、期望伤害相同 → 移动最少（原地）优先。
	far.stats.hp = 100
	stubs[far] = stubs[near]
	acts = EnemyAI.decide_actions(enemy, tm.grid, tm.units, forecast)
	_eq("同分：不移动，只攻击", acts.size(), 1)
	if acts.size() == 1:
		_eq("同分：打原地够得着的 near", acts[0].target_unit, near)

	# 已经移动过：只比较原地。
	far.stats.hp = 6
	stubs[far] = {"hit_percent": 80, "crit_percent": 0, "damage": 7}
	enemy.movement_used = true
	acts = EnemyAI.decide_actions(enemy, tm.grid, tm.units, forecast)
	_eq("已移动过：原地攻击", acts.size(), 1)
	if acts.size() == 1:
		_eq("已移动过：只能打 near", acts[0].target_unit, near)
	enemy.movement_used = false
	near.stats.hp = near.stats.max_hp
	far.stats.hp = far.stats.max_hp


# ── ③b 同分决胜 ─────────────────────────────────────

func _test_tie_break(near: Unit, far: Unit, cfg: Dictionary) -> void:
	print("\n[③b] 同分决胜")
	var tie: Array = cfg.get("tie_break", [])
	near.stats.hp = 50
	far.stats.hp = 50
	# near 在 (3,3)，far 在 (5,4)：目标格 y 小的是 near。
	var a: Dictionary = _cand(Vector2i(4, 4), 2, far, true)
	var b: Dictionary = _cand(Vector2i(3, 4), 0, near, false)
	_check("能击杀优先于移动少", EnemyAI._better(a, b, tie) and not EnemyAI._better(b, a, tie))
	a = _cand(Vector2i(4, 4), 1, far, false)
	_check("移动少的优先", EnemyAI._better(b, a, tie) and not EnemyAI._better(a, b, tie))
	far.stats.hp = 20
	a = _cand(Vector2i(4, 4), 0, far, false)
	_check("目标剩余生命低的优先", EnemyAI._better(a, b, tie) and not EnemyAI._better(b, a, tie))
	far.stats.hp = 50
	_check("目标格先比 y：near (3,3) 优先于 far (5,4)",
		EnemyAI._better(b, a, tie) and not EnemyAI._better(a, b, tie))
	var c: Dictionary = _cand(Vector2i(2, 3), 0, near, false)
	_check("全部相同时比站位格", EnemyAI._better(c, b, tie) and not EnemyAI._better(b, c, tie))
	var hi: Dictionary = _cand(Vector2i(4, 4), 3, far, false)
	hi["score"] = 2.0
	_check("得分高先于一切决胜项", EnemyAI._better(hi, b, tie))
	near.stats.hp = near.stats.max_hp
	far.stats.hp = far.stats.max_hp


# ── ③c 嘲讽（R1.18） ─────────────────────────────────

func _test_taunt(tm: Node, near: Unit, far: Unit, enemy: Unit) -> void:
	print("\n[③c] 嘲讽（R1.18）")
	enemy.stats.mov = 3
	enemy.attack_min_range = 1
	enemy.attack_range = 1
	enemy.movement_used = false
	near.stats.hp = 100
	far.stats.hp = 6
	near.held_states.apply("taunt", 1, {"kind": "permanent"})
	_check("前提：near 有嘲讽、far 没有", near.has_taunt() and not far.has_taunt())
	var stubs: Dictionary = {near: {"hit_percent": 80, "crit_percent": 0, "damage": 5},
		far: {"hit_percent": 80, "crit_percent": 0, "damage": 7}}
	var forecast: Callable = func(_a: Unit, t: Unit) -> Dictionary: return stubs[t]
	# 得分选在 (4,4) 打 far；(4,4) 与 near (3,3) 不相邻，射程内没有嘲讽单位，沿用原选择。
	var acts: Array[GameAction] = EnemyAI.decide_actions(enemy, tm.grid, tm.units, forecast)
	_eq("站位射程内没有嘲讽单位：仍打得分最高的 far",
		acts.back().target_unit if not acts.is_empty() else null, far)

	# far 挪到 (4,4)：原地 (3,4) 同时够得着 near 与 far，得分选原地打 far，嘲讽改成 near。
	tm.grid.move_unit(far, Vector2i(5, 4), Vector2i(4, 4))
	far.grid_position = Vector2i(4, 4)
	acts = EnemyAI.decide_actions(enemy, tm.grid, tm.units, forecast)
	_eq("站位定在原地", acts.size(), 1)
	if acts.size() == 1:
		_eq("射程内有嘲讽单位：改打 near", acts[0].target_unit, near)

	# 两个嘲讽单位都在射程内：按得分挑能击杀的 far。
	far.held_states.apply("taunt", 1, {"kind": "permanent"})
	acts = EnemyAI.decide_actions(enemy, tm.grid, tm.units, forecast)
	_eq("多个嘲讽单位：原地攻击", acts.size(), 1)
	if acts.size() == 1:
		_eq("多个嘲讽单位：按得分选 far", acts[0].target_unit, far)

	near.held_states.remove("taunt")
	far.held_states.remove("taunt")
	tm.grid.move_unit(far, Vector2i(4, 4), Vector2i(5, 4))
	far.grid_position = Vector2i(5, 4)
	near.stats.hp = near.stats.max_hp
	far.stats.hp = far.stats.max_hp


# ── ④ 预告 ───────────────────────────────────────────

func _test_forecast(tm: Node, target: Unit, enemy: Unit) -> void:
	print("\n[④] 交给 AI 的预告")
	target.stats.def_attr = 0
	var p: Dictionary = tm._forecast_attack_for_ai(enemy, target)
	_check("预告带暴击伤害", p.has("crit_damage"))
	# 与实际结算对照：同一上下文指定命中并暴击 / 命中不暴击，resolve_attack 的伤害应等于预告。
	var ctx: Dictionary = tm._build_hostile_action_context(enemy, target,
		GameAction.make_attack(enemy, target).data)
	ctx["precomputed_outcome"] = {"hit": true, "crit": true}
	var crit_hit: int = DamageCalculator.resolve_attack(enemy, target, ctx).damage
	_check("暴击结算高于普通伤害（断言有意义）", crit_hit > int(p.get("damage", 0)),
		"crit %d normal %d" % [crit_hit, int(p.get("damage", 0))])
	_eq("预告暴击伤害 == 实际暴击结算", int(p.get("crit_damage", -1)), crit_hit)
	ctx["precomputed_outcome"] = {"hit": true, "crit": false}
	_eq("预告伤害 == 实际普通结算", int(p.get("damage", -1)),
		DamageCalculator.resolve_attack(enemy, target, ctx).damage)
	# 暴击之后还有乘区时，两边乘法顺序也一致。
	ctx["final_multiplier"] = 1.4
	ctx["precomputed_outcome"] = {"hit": true, "crit": true}
	_eq("带最终修正时预告暴击伤害 == 实际", int(DamageCalculator.preview_attack(
		enemy, target, ctx).get("crit_damage", -1)),
		DamageCalculator.resolve_attack(enemy, target, ctx).damage)


# ── 工具 ─────────────────────────────────────────────

func _cand(pos: Vector2i, move_cost: int, target: Unit, kill: bool) -> Dictionary:
	return {"pos": pos, "move_cost": move_cost, "target": target, "score": 1.0, "kill": kill}


func _stub(hit: int, crit: int, damage: int, crit_damage: int) -> Callable:
	return func(_a: Unit, _t: Unit) -> Dictionary:
		return {"hit_percent": hit, "crit_percent": crit, "damage": damage, "crit_damage": crit_damage}


func _finish(scene: Node) -> void:
	scene.queue_free()
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  ✗ " + f)
	quit(0 if _fail == 0 else 1)


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		_fails.append(name + ("  [" + detail + "]" if detail != "" else ""))
		print("  ✗ " + name + ("  [" + detail + "]" if detail != "" else ""))


func _eq(name: String, actual: Variant, expected: Variant) -> void:
	_check(name, actual == expected, "期望 %s 实际 %s" % [str(expected), str(actual)])


func _near(name: String, actual: float, expected: float) -> void:
	_check(name, absf(actual - expected) < 0.0001, "期望 %s 实际 %s" % [str(expected), str(actual)])
