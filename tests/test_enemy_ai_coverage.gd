extends SceneTree
## AI 技能覆盖（用户 2026-10-31「补，然后重跑」：模拟里 AI 用不出位移、召唤与自由动作的自身强化）。
## 覆盖：
##   ① 当前槽位：AI 取的技能与技能栏一致（〔兵无常势〕持有 1 枚印记时招架槽是〔三段斩〕，
##      它是以自身为目标的自由动作，分类为 self；与召唤物换位的〔颠倒〕不返回）。
##   ② 位移技能〔一闪〕：穿过敌人落到它身后，再在落点出手，总分高于「移动 + 出手」时选用；执行后站在落点。
##   ③ 先选敌人再选落点〔回斩〕：落到敌人相邻空格，再在落点出手；执行后站在落点。
##   ④ 召唤〔临摹〕：放在挨着敌人的空格；执行后〔影〕在场。
##   ⑤ 资源预算：主动作先留剑气与印记；迅捷行动点每回合一次，招架与临摹不会同回合都排上。
##   ⑥ 三段斩排进计划并执行；只与普通移动打平的位移方案不用；计划后已不在当前槽位上的技能跳过。
##
## 运行：
##   <Godot_console.exe> --headless --path <worktree> --script res://tests/test_enemy_ai_coverage.gd

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []


func _initialize() -> void:
	print("=== test_enemy_ai_coverage（AI 技能覆盖）===")
	_run.call_deferred()


func _run() -> void:
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	scene.run_injected = true
	scene.injected_map_id = "test_arena"
	scene.injected_player_units = [
		{"class_id": "kensei", "pos": Vector2i(0, 0)},
		{"class_id": "kensei", "pos": Vector2i(0, 7), "memories": ["kensei_tuodaoji"]},
		{"class_id": "kensei", "pos": Vector2i(7, 7), "memories": ["kensei_juhe_xushi"]},
		{"class_id": "kensei", "pos": Vector2i(7, 0), "memories": ["kensei_huazhengweiling"]},
	]
	scene.injected_enemy_units = [{"class_id": "goblin_melee", "pos": Vector2i(4, 4)}]
	scene.debug_harness_enabled = false
	root.add_child(scene)
	await process_frame
	await process_frame

	var tm: Node = scene.get_node("TacticalManager")
	_check("tactical_manager 脚本已挂载", tm.get_script() != null
		and (tm.get_script() as Script).resource_path == "res://scripts/core/tactical_manager.gd")
	if tm.turn_manager != null:
		tm.turn_manager.stop()
	var by_pos: Dictionary = {}
	var enemy: Unit = null
	for u: Variant in tm.units:
		var unit: Unit = u
		if unit.faction == "enemy":
			enemy = unit
			unit.stats.max_hp = 999
			unit.stats.hp = 999
		else:
			by_pos[unit.grid_position] = unit
			unit.stats.dex = 300
	var k_base: Unit = by_pos.get(Vector2i(0, 0))
	var k_tuo: Unit = by_pos.get(Vector2i(0, 7))
	var k_xushi: Unit = by_pos.get(Vector2i(7, 7))
	var k_hua: Unit = by_pos.get(Vector2i(7, 0))
	if enemy == null or k_base == null or k_tuo == null or k_xushi == null or k_hua == null:
		_check("场景含四名剑圣与一名敌人", false)
		_finish(scene)
		return

	_test_slots(tm, k_hua, k_xushi)
	await _test_yishan(tm, k_base, enemy)
	await _test_huizhan(tm, k_tuo, enemy)
	await _test_summon(tm, k_xushi, enemy)
	_test_budget()
	_test_tie_and_stale(tm, k_base, enemy)
	_finish(scene)


# ── ① 当前槽位 ───────────────────────────────────────

func _test_slots(tm: Node, k_hua: Unit, k_xushi: Unit) -> void:
	print("\n[①] 当前槽位")
	k_hua.clear_marks()
	k_hua.gain_random_mark()
	_reset(k_hua)
	var ids: Array[String] = tm._ai_current_skill_ids(k_hua)
	_check("兵无常势持有 1 枚印记：招架槽是三段斩", ids.has("kensei_sanduanzhan") and not ids.has("kensei_zhaojia"),
		str(ids))
	var kinds: Dictionary = {}
	for s: Dictionary in tm._ai_support_skills(k_hua):
		kinds[s["skill_id"]] = [s["kind"], s["action_cost"]]
	_eq("三段斩是自由动作的自身强化", kinds.get("kensei_sanduanzhan"), ["self", "free"])
	# 三段斩可用就用：排进计划并执行，消耗 1 枚印记、获得 15 剑气。
	k_hua.set_sword_qi(0)
	var acts: Array[GameAction] = _decide(tm, k_hua)
	var sdz: GameAction = null
	for a: GameAction in acts:
		if a.type == GameAction.Type.SKILL and str(a.data.get("skill_id", "")) == "kensei_sanduanzhan":
			sdz = a
	_check("三段斩排进计划", sdz != null, _describe(acts))
	if sdz != null:
		var cast: GameAction = tm._rebuild_ai_skill_action(k_hua, sdz)
		_check("三段斩执行成功", cast != null and bool(tm._execute_skill_action(cast)))
		_check("消耗印记、获得剑气", k_hua.get_mark_count() == 0 and k_hua.sword_qi > 0,
			"印记 %d 剑气 %d" % [k_hua.get_mark_count(), k_hua.sword_qi])
	k_hua.clear_marks()
	k_hua.set_sword_qi(0)


# ── ② 一闪 ───────────────────────────────────────────

func _test_yishan(tm: Node, ks: Unit, enemy: Unit) -> void:
	print("\n[②] 一闪：穿过敌人再出手")
	_place(tm, ks, Vector2i(1, 3))
	_place(tm, enemy, Vector2i(3, 3))
	_reset(ks)
	var acts: Array[GameAction] = _decide(tm, ks)
	var first: GameAction = acts[0] if not acts.is_empty() else null
	_check("先用一闪", first != null and first.type == GameAction.Type.SKILL
		and str(first.data.get("skill_id", "")) == "kensei_yishan", _describe(acts))
	_check("落到敌人身后 (4,3)", first != null and first.target_pos == Vector2i(4, 3))
	_check("落点上接着出手", acts.size() >= 2 and acts.back().type != GameAction.Type.MOVE)
	if first != null and str(first.data.get("skill_id", "")) == "kensei_yishan":
		var hp: int = enemy.stats.hp
		var cast: GameAction = tm._rebuild_ai_skill_action(ks, first)
		_check("一闪执行成功", cast != null and bool(tm._execute_skill_action(cast)))
		await process_frame
		_eq("站在落点", ks.grid_position, Vector2i(4, 3))
		_check("途经的敌人受伤", enemy.stats.hp < hp, "%d → %d" % [hp, enemy.stats.hp])
		_check("落点上的出手执行成功", _execute(tm, ks, acts.back()))
	_place(tm, ks, Vector2i(0, 0))
	enemy.stats.hp = enemy.stats.max_hp


# ── ③ 回斩 ───────────────────────────────────────────

func _test_huizhan(tm: Node, ks: Unit, enemy: Unit) -> void:
	print("\n[③] 回斩：落到敌人相邻格再出手")
	_place(tm, ks, Vector2i(1, 4))
	_place(tm, enemy, Vector2i(4, 4))
	_reset(ks)
	var acts: Array[GameAction] = _decide(tm, ks)
	var first: GameAction = acts[0] if not acts.is_empty() else null
	_check("先用回斩", first != null and first.type == GameAction.Type.SKILL
		and str(first.data.get("skill_id", "")) == "kensei_huizhan", _describe(acts))
	if first != null and str(first.data.get("skill_id", "")) == "kensei_huizhan":
		var landing: Vector2i = tm._deserialize_vector2i(first.data.get("ai_landing", {}))
		_check("目标是敌人、落点与它相邻", first.target_unit == enemy
			and absi(landing.x - 4) + absi(landing.y - 4) == 1, str(landing))
		_check("落点上接着出手", acts.size() >= 2 and acts.back().type != GameAction.Type.MOVE)
		var cast: GameAction = tm._rebuild_ai_skill_action(ks, first)
		_check("回斩执行成功", cast != null and bool(tm._execute_skill_action(cast)))
		await process_frame
		_eq("站在落点", ks.grid_position, landing)
		_check("落点上的出手执行成功", _execute(tm, ks, acts.back()))
	_place(tm, ks, Vector2i(0, 7))
	enemy.stats.hp = enemy.stats.max_hp


# ── ④ 召唤 ───────────────────────────────────────────

func _test_summon(tm: Node, ks: Unit, enemy: Unit) -> void:
	print("\n[④] 临摹：召唤到挨着敌人的空格")
	_place(tm, ks, Vector2i(2, 4))
	_place(tm, enemy, Vector2i(4, 4))
	_reset(ks)
	ks.set_sword_qi(100)
	ks.skill_cooldowns["kensei_zhaojia"] = 2
	ks.movement_used = true
	var acts: Array[GameAction] = _decide(tm, ks)
	var summon: GameAction = null
	for a: GameAction in acts:
		if a.type == GameAction.Type.SKILL and str(a.data.get("skill_id", "")) == "kensei_linmo":
			summon = a
	_check("放临摹", summon != null, _describe(acts))
	if summon != null:
		var d: int = absi(summon.target_pos.x - 4) + absi(summon.target_pos.y - 4)
		_eq("落在挨着敌人的空格", d, 1)
		var cast: GameAction = tm._rebuild_ai_skill_action(ks, summon)
		_check("临摹执行成功", cast != null and bool(tm._execute_skill_action(cast)))
		_check("〔影〕在场", not tm._get_illusions_of(ks).is_empty())
		_check("〔影〕在场时临摹槽是颠倒", tm._ai_current_skill_ids(ks).has("kensei_diandao"))
		var has_swap: bool = false
		for s: Dictionary in tm._ai_support_skills(ks):
			if s["skill_id"] == "kensei_diandao":
				has_swap = true
		_check("颠倒不在功能技能里", not has_swap)
	# ⑤ 迅捷行动点每回合一次：招架与临摹都能用时只排一个。
	print("\n[⑤] 迅捷行动点")
	for ying: Unit in tm._get_illusions_of(ks):
		ying.vanish_illusion()
	_reset(ks)
	ks.set_sword_qi(100)
	ks.movement_used = true
	acts = _decide(tm, ks)
	var swift: int = 0
	for a: GameAction in acts:
		if a.type == GameAction.Type.SKILL and ["kensei_zhaojia", "kensei_linmo"].has(str(a.data.get("skill_id", ""))):
			swift += 1
	_eq("招架与临摹只排一个", swift, 1)


func _test_budget() -> void:
	print("\n[⑤b] 资源预算")
	var b: Dictionary = {"qi": 70, "marks": 1, "swift": 1}
	EnemyAI._spend_budget(b, {"qi": 20, "marks": 0, "uses_swift": false})
	_check("主动作留出 20 剑气后，60 剑气的临摹放不下", not EnemyAI._fits_budget(b, {"qi": 60, "uses_swift": true}))
	_check("允许透支时不看剑气", EnemyAI._fits_budget(b, {"qi": 60, "qi_overdraft": true, "uses_swift": true}))
	_check("印记门槛", not EnemyAI._fits_budget(b, {"marks_needed": 2}))
	EnemyAI._spend_budget(b, {"uses_swift": true})
	_check("迅捷行动点用完", not EnemyAI._fits_budget(b, {"uses_swift": true}))


# ── ⑥ 打平不用位移、过期技能跳过 ─────────────────────

func _test_tie_and_stale(tm: Node, ks: Unit, enemy: Unit) -> void:
	print("
[⑥] 打平不用位移；已不在槽位上的技能跳过")
	# 一闪往下落到 (1,5) 与敌人 (2,5) 相邻，途经没有敌人：与普通移动后出手同分，不用一闪。
	_place(tm, ks, Vector2i(1, 3))
	_place(tm, enemy, Vector2i(2, 5))
	_reset(ks)
	var acts: Array[GameAction] = _decide(tm, ks)
	var used_yishan: bool = false
	for a: GameAction in acts:
		if a.type == GameAction.Type.SKILL and str(a.data.get("skill_id", "")) == "kensei_yishan":
			used_yishan = true
	_check("位移方案只是打平：不用一闪", not used_yishan and not acts.is_empty(), _describe(acts))
	# 计划时招架槽是招架；之后有了 3 枚印记与 20 剑气，招架槽换成拔刀，原计划的招架跳过。
	_reset(ks)
	ks.clear_marks()
	ks.set_sword_qi(0)
	var parry: GameAction = GameAction.make_skill(ks, "kensei_zhaojia", ks.grid_position, ks)
	for i: int in range(3):
		ks.gain_random_mark()
	ks.set_sword_qi(30)
	_check("前提：招架槽已换成拔刀", not tm._ai_current_skill_ids(ks).has("kensei_zhaojia"))
	_check("已不在槽位上的招架跳过", tm._rebuild_ai_skill_action(ks, parry) == null)
	ks.clear_marks()
	ks.set_sword_qi(0)
	_place(tm, ks, Vector2i(0, 0))


# ── 工具 ─────────────────────────────────────────────

func _execute(tm: Node, unit: Unit, act: GameAction) -> bool:
	if act.type == GameAction.Type.ATTACK:
		return bool(tm._execute_attack_action(act))
	var cast: GameAction = tm._rebuild_ai_skill_action(unit, act)
	return cast != null and bool(tm._execute_skill_action(cast))


func _decide(tm: Node, unit: Unit) -> Array[GameAction]:
	return EnemyAI.decide_actions(unit, tm.grid, tm.units,
		Callable(tm, "_forecast_attack_for_ai"), tm)


func _reset(unit: Unit) -> void:
	unit.reset_action_resources()
	unit.movement_used = false
	unit.skill_cooldowns.clear()


func _describe(acts: Array[GameAction]) -> String:
	var parts: PackedStringArray = []
	for a: GameAction in acts:
		parts.append("%d:%s@%s" % [a.type, str(a.data.get("skill_id", "")), str(a.target_pos)])
	return ", ".join(parts)


func _place(tm: Node, unit: Unit, pos: Vector2i) -> void:
	if unit.grid_position == pos:
		return
	tm.grid.move_unit(unit, unit.grid_position, pos)
	unit.grid_position = pos
	unit.position = tm.grid.grid_to_world(pos)


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
