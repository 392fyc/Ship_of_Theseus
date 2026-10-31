extends SceneTree
## 普通敌人的增益、减益与友军技能（用户 2026-10-31 逐项收束）：
##   功能技能可用就用；减益给攻击时会选的目标；治疗只在有人缺血时用、给实际补回最多的；
##   护盾给生命比例最低的友军；牧师没有普攻，没事可做时靠近友军待命。
##
## 依据：KB 01-Game-Design/Core-Systems/enemy-and-ai.md「用户裁决：普通敌人的技能组与技能使用」；
## R1.2（命中加减）、R1.17（护盾相加）、R1.18（嘲讽）。
## 覆盖：
##   ① 查询：功能技能的分类（减益 / 治疗 / 增益）与行动消耗；诅咒的目标关系是敌方。
##   ② 诅咒：可用就用、不再攻击；目标是攻击时会选的那个；命中 −20；进入冷却后改回攻击；
##      够不着时走过去放；站位定下后优先嘲讽单位（R1.18）。
##   ③ 牧师：给缺血最多的友军治疗、护盾给生命比例最低的友军（迅捷先放）；
##      没人缺血且护盾冷却中时不攻击，靠近友军待命。
##   ④ 执行：护盾术与治疗按技能 id 在移动后重建并结算。
##
## 运行：
##   <Godot_console.exe> --headless --path <worktree> --script res://tests/test_enemy_ai_support.gd

const CURSE := "goblin_curse"
const HEAL := "goblin_priest_heal"
const SHIELD := "goblin_priest_shield"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []


func _initialize() -> void:
	print("=== test_enemy_ai_support（增益、减益与友军技能）===")
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
		{"class_id": "goblin_shaman", "pos": Vector2i(4, 1)},
		{"class_id": "goblin_priest", "pos": Vector2i(5, 5)},
		{"class_id": "goblin_melee", "pos": Vector2i(5, 4)},
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
	var shaman: Unit = null
	var priest: Unit = null
	var melee: Unit = null
	for u: Variant in tm.units:
		if not u is Unit:
			continue
		var unit: Unit = u
		match unit.unit_id:
			"goblin_shaman":
				shaman = unit
			"goblin_priest":
				priest = unit
			"goblin_melee":
				melee = unit
			_:
				players[unit.grid_position] = unit
				unit.stats.max_hp = 999
				unit.stats.hp = 999
				unit.stats.lck = 0
	var a: Unit = players.get(Vector2i(1, 1))
	var b: Unit = players.get(Vector2i(2, 1))
	var c: Unit = players.get(Vector2i(6, 6))
	if a == null or b == null or c == null or shaman == null or priest == null or melee == null:
		_check("场景含三名剑圣、萨满、牧师与战士", false)
		_finish(scene)
		return
	shaman.stats.dex = 300

	_test_queries(tm, shaman, priest)
	_test_curse(tm, a, b, shaman)
	_test_priest(tm, c, priest, melee, shaman)
	_finish(scene)


# ── ① 查询 ───────────────────────────────────────────

func _test_queries(tm: Node, shaman: Unit, priest: Unit) -> void:
	print("\n[①] 查询")
	shaman.reset_action_resources()
	priest.reset_action_resources()
	var curse: Array = tm._ai_support_skills(shaman)
	_check("萨满：诅咒是标准动作的减益", curse.size() == 1 and curse[0]["skill_id"] == CURSE
		and curse[0]["kind"] == "debuff" and curse[0]["action_cost"] == "standard")
	_eq("诅咒作用于敌方", tm._get_skill_target_relation(tm._get_skill_data(CURSE)), "enemy")
	_eq("萨满的攻击技能里没有诅咒", tm._ai_attack_skill_ids(shaman), [])
	var support: Array = tm._ai_support_skills(priest)
	_check("牧师：治疗（标准，20）与护盾术（迅捷增益）", support.size() == 2
		and support[0]["skill_id"] == HEAL and support[0]["kind"] == "heal" and int(support[0]["heal"]) == 20
		and support[1]["skill_id"] == SHIELD and support[1]["kind"] == "buff"
		and support[1]["action_cost"] == "swift" and (support[1]["effect_ids"] as Array).has("shield"))
	_check("牧师没有普攻", not priest.has_basic_attack)


# ── ② 诅咒 ───────────────────────────────────────────

func _test_curse(tm: Node, a: Unit, b: Unit, shaman: Unit) -> void:
	print("\n[②] 诅咒")
	shaman.reset_action_resources()
	shaman.movement_used = true
	# 萨满在 (4,1)：普攻（1–2 格）只够得着 B，所以攻击时会选 B；诅咒（1–3 格）够得着 A 与 B。
	shaman.skill_cooldowns[CURSE] = 4
	var acts: Array[GameAction] = _decide(tm, shaman)
	_check("前提：诅咒冷却中时普攻打 B", acts.size() == 1
		and acts[0].type == GameAction.Type.ATTACK and acts[0].target_unit == b)
	shaman.skill_cooldowns.clear()
	acts = _decide(tm, shaman)
	_check("可用就用：放诅咒、这回合不攻击", acts.size() == 1 and acts[0].type == GameAction.Type.SKILL
		and str(acts[0].data.get("skill_id", "")) == CURSE)
	_check("诅咒给攻击时会选的 B", acts.size() == 1 and acts[0].target_unit == b)

	# 执行：命中 −20，持续到 B 的下一个自身回合结束；萨满进入冷却后改回攻击。
	var hit_before: int = b.get_hit_value(90)
	var cast: GameAction = tm._rebuild_ai_skill_action(shaman, acts[0])
	_check("诅咒执行成功", cast != null and bool(tm._execute_skill_action(cast)))
	_eq("B 的命中 −20（R1.2 命中加减）", b.get_hit_value(90), hit_before - 20)
	b.process_turn_end_buffs()
	_eq("B 的自身回合结束后诅咒消失", b.get_hit_value(90), hit_before)
	shaman.reset_action_resources()
	shaman.movement_used = true
	acts = _decide(tm, shaman)
	_check("诅咒冷却中：改回普攻", acts.size() == 1 and acts[0].type == GameAction.Type.ATTACK)
	shaman.skill_cooldowns.clear()

	# R1.18：站位定下后，诅咒在合法目标里优先嘲讽单位。A 不在普攻射程内，攻击仍选 B。
	a.held_states.apply("taunt", 1, {"kind": "permanent"})
	acts = _decide(tm, shaman)
	_check("诅咒改给嘲讽的 A", acts.size() == 1 and str(acts[0].data.get("skill_id", "")) == CURSE
		and acts[0].target_unit == a)
	a.held_states.remove("taunt")

	# 够不着时走过去放：萨满在 (7,1)，A、B 都在 3 格外。
	_place(tm, shaman, Vector2i(7, 1))
	shaman.reset_action_resources()
	acts = _decide(tm, shaman)
	_check("先移动再放诅咒", acts.size() == 2 and acts[0].type == GameAction.Type.MOVE
		and acts[1].type == GameAction.Type.SKILL and str(acts[1].data.get("skill_id", "")) == CURSE)
	_place(tm, shaman, Vector2i(4, 1))


# ── ③ 牧师 ───────────────────────────────────────────

func _test_priest(tm: Node, c: Unit, priest: Unit, melee: Unit, shaman: Unit) -> void:
	print("
[③] 牧师")
	# 牧师 (5,5)、战士 (5,4) 相邻，萨满挪到 (5,3)：治疗（0–1 格）只够得着战士与自己，
	# 护盾术（1–2 格）够得着战士与萨满。
	_place(tm, shaman, Vector2i(5, 3))
	# 战士缺 30，牧师自己缺 5：治疗补回 20 对 5，给战士。
	# 生命比例：萨满 5/最大 远低于战士，护盾给萨满。
	melee.stats.hp = melee.stats.max_hp - 30
	priest.stats.hp = priest.stats.max_hp - 5
	shaman.stats.hp = 5
	_check("前提：萨满的生命比例低于战士",
		float(shaman.stats.hp) / shaman.stats.max_hp < float(melee.stats.hp) / melee.stats.max_hp)
	priest.reset_action_resources()
	priest.movement_used = true
	var acts: Array[GameAction] = _decide(tm, priest)
	var heal_act: GameAction = _find_skill(acts, HEAL)
	var shield_act: GameAction = _find_skill(acts, SHIELD)
	_check("治疗给补回最多的战士", heal_act != null and heal_act.target_unit == melee)
	_check("护盾给生命比例最低的萨满", shield_act != null and shield_act.target_unit == shaman)
	_check("迅捷的护盾术排在治疗前", acts.find(shield_act) < acts.find(heal_act))
	_check("牧师不攻击", not acts.any(func(x: GameAction) -> bool: return x.type == GameAction.Type.ATTACK))

	# 执行：护盾与治疗。
	var shield_before: int = shaman.shield
	var hp_before: int = melee.stats.hp
	if shield_act != null and heal_act != null:
		var s_cast: GameAction = tm._rebuild_ai_skill_action(priest, shield_act)
		_check("护盾术执行成功", s_cast != null and bool(tm._execute_skill_action(s_cast)))
		_eq("萨满护盾 +15（R1.17 相加）", shaman.shield, shield_before + 15)
		var h_cast: GameAction = tm._rebuild_ai_skill_action(priest, heal_act)
		_check("治疗执行成功", h_cast != null and bool(tm._execute_skill_action(h_cast)))
		_eq("战士恢复 20", melee.stats.hp, hp_before + 20)
	shaman.shield = 0
	shaman.stats.hp = shaman.stats.max_hp

	# 能移动时：治疗要走到战士旁边，护盾术在同一格施放（迅捷技能只在主动作的站位）。
	melee.stats.hp = melee.stats.max_hp - 30
	priest.stats.hp = priest.stats.max_hp
	_place(tm, priest, Vector2i(7, 4))
	priest.reset_action_resources()
	priest.skill_cooldowns.clear()
	acts = _decide(tm, priest)
	heal_act = _find_skill(acts, HEAL)
	shield_act = _find_skill(acts, SHIELD)
	var moved: bool = acts.size() == 3 and acts[0].type == GameAction.Type.MOVE
	_check("先移动、再放护盾术、再治疗", moved and acts[1] == shield_act and acts[2] == heal_act)
	if moved and heal_act != null and shield_act != null:
		var pos: Vector2i = acts[0].target_pos
		_check("护盾术与治疗都能在移动后的同一格施放",
			_castable(tm, priest, SHIELD, pos, shield_act) and _castable(tm, priest, HEAL, pos, heal_act))

	# 没人缺血时只有迅捷的护盾术可用：由它决定站位。
	melee.stats.hp = melee.stats.max_hp
	_place(tm, priest, Vector2i(7, 7))
	priest.reset_action_resources()
	priest.skill_cooldowns.clear()
	acts = _decide(tm, priest)
	shield_act = _find_skill(acts, SHIELD)
	moved = acts.size() == 2 and acts[0].type == GameAction.Type.MOVE and acts[1] == shield_act
	_check("没有主动作：移动到能放护盾术的位置再放", moved)
	if moved:
		_check("护盾术在移动后的格子能施放", _castable(tm, priest, SHIELD, acts[0].target_pos, shield_act))

	# 没人缺血、护盾冷却中：不攻击（C 在 2 格内也不打），靠近友军待命。
	_place(tm, shaman, Vector2i(4, 1))
	melee.shield = 0
	# 牧师 (7,5) 移动力 3：能走到挨着战士 (5,4) 的 (6,4) 或 (5,5)。C 挪到 (5,7)，
	# 两格离 C 分别是 4 与 2，所以「离玩家远」选 (6,4)。
	_place(tm, priest, Vector2i(7, 5))
	_place(tm, c, Vector2i(5, 7))
	priest.reset_action_resources()
	priest.skill_cooldowns[SHIELD] = 4
	acts = _decide(tm, priest)
	_check("没事可做：不攻击、不放技能", not acts.any(func(x: GameAction) -> bool:
		return x.type != GameAction.Type.MOVE))
	var dest: Vector2i = acts[0].target_pos if acts.size() == 1 else priest.grid_position
	var allies: Array[Unit] = [melee, shaman]
	var players: Array[Unit] = [c]
	for u: Variant in tm.units:
		if u is Unit and (u as Unit).faction != priest.faction and not players.has(u):
			players.append(u)
	var before: int = _nearest_dist(priest.grid_position, allies)
	var after: int = _nearest_dist(dest, allies)
	_check("靠近友军待命", acts.size() == 1 and after < before,
		"离最近友军 %d → %d" % [before, after])
	_check("待命的位置挨着友军", after == 1, "距离 %d" % after)
	# 同样挨着友军的格子里，选离玩家单位最远的。
	var reach: Dictionary = Pathfinding.get_move_range(tm.grid, priest.grid_position,
		priest.stats.mov, priest.faction)
	var farthest: int = -1
	var tied: int = 0
	for cell_pos: Vector2i in reach:
		var occ: Unit = tm.grid.get_unit_at(cell_pos)
		if occ != null and occ != priest:
			continue
		if _nearest_dist(cell_pos, allies) != after:
			continue
		tied += 1
		farthest = maxi(farthest, _nearest_dist(cell_pos, players))
	_check("前提：有多个同样挨着友军的格子", tied >= 2, "%d 个" % tied)
	_eq("其中离玩家单位最远", _nearest_dist(dest, players), farthest)
	_eq("待命选 (6,4)", dest, Vector2i(6, 4))
	_place(tm, c, Vector2i(6, 6))


func _castable(tm: Node, unit: Unit, skill_id: String, pos: Vector2i, act: GameAction) -> bool:
	for cast: Dictionary in tm._ai_skill_casts(unit, skill_id, pos):
		if cast["target_pos"] == act.target_pos and cast["target_unit"] == act.target_unit:
			return true
	return false


func _nearest_dist(pos: Vector2i, units: Array[Unit]) -> int:
	var best: int = 99999
	for u: Unit in units:
		best = mini(best, _dist(pos, u.grid_position))
	return best


# ── 工具 ─────────────────────────────────────────────

func _decide(tm: Node, unit: Unit) -> Array[GameAction]:
	return EnemyAI.decide_actions(unit, tm.grid, tm.units,
		Callable(tm, "_forecast_attack_for_ai"), tm)


func _find_skill(acts: Array[GameAction], skill_id: String) -> GameAction:
	for act: GameAction in acts:
		if act.type == GameAction.Type.SKILL and str(act.data.get("skill_id", "")) == skill_id:
			return act
	return null


func _dist(p: Vector2i, q: Vector2i) -> int:
	return absi(p.x - q.x) + absi(p.y - q.y)


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
