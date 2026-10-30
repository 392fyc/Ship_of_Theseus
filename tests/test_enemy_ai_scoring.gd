extends SceneTree
## 敌人 AI 加权打分（用户 2026-10-30 按方案页推荐选定：KB 结构、击杀加分 10、射程内也比较移动、
## 站位首期不打分、〔影〕诱饵分 6）。
##
## 依据：KB 01-Game-Design/Core-Systems/enemy-and-ai.md「目标选择」；R1.18（嘲讽）。
## 覆盖：
##   ① 配置：data/ai/target_scoring.json 已加载。
##   ② 单目标得分：期望有效伤害、普通伤害击杀、只有暴击才击杀、护盾算进耐久、〔影〕诱饵分与击杀分。
##   ③ 选择：射程内已有目标时，仍会走一步去打得分更高的目标；同分时不移动；已移动过只比较原地。
##   ④ 预告：TacticalManager 交给 AI 的预告带暴击伤害，且不低于普通伤害。
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


# ── ④ 预告 ───────────────────────────────────────────

func _test_forecast(tm: Node, target: Unit, enemy: Unit) -> void:
	print("\n[④] 交给 AI 的预告")
	var p: Dictionary = tm._forecast_attack_for_ai(enemy, target)
	_check("预告带暴击伤害", p.has("crit_damage"))
	_check("暴击伤害不低于普通伤害",
		int(p.get("crit_damage", -1)) >= int(p.get("damage", 0)),
		"damage %s crit %s" % [str(p.get("damage")), str(p.get("crit_damage"))])
	var ctx: Dictionary = tm._build_hostile_action_context(enemy, target,
		GameAction.make_attack(enemy, target).data)
	var direct: Dictionary = DamageCalculator.preview_attack(enemy, target, ctx)
	_eq("与玩家悬停预告同一套上下文：伤害相同", int(p.get("damage", -1)), int(direct.get("damage", -2)))
	_eq("与玩家悬停预告同一套上下文：命中相同", int(p.get("hit_percent", -1)),
		int(direct.get("hit_percent", -2)))


# ── 工具 ─────────────────────────────────────────────

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
