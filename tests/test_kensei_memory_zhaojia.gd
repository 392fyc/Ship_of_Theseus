extends SceneTree
## 回忆技能·招架组（gameplay-impl PR6d，差距清单 M15）：〔刹那之隙〕→〔见切〕、〔若即若离〕→〔浮生若梦〕。
##
## 依据：设计库 762393b 的 kensei_jieli / kensei_qiefan，states kensei_jiashi / jianqie_stance / ruoji / ruoli；
## R1.1（总增总降）、R1.2（其他闪避加减）、R1.18（嘲讽）、R2.5、R3.4；用户裁决 Q3、Q5。
## 覆盖：
##   ① 数据与挂载；升级技能保留招架槽换出拔刀的字段。
##   ② 兑现与槽位：招架原位换成升级技能，3 印记、20 剑气时这一格仍换出拔刀（R2.5）。
##   ③ 见切：架势（自身回合内技能伤害总降 20%、额外闪避 = 技巧 50%、嘲讽）、见切层数按剑气、再次获得设为本次层数。
##   ④ 反击：敌方攻击动作结束后、相邻、剑气 ≥ 10 → 耗 1 层与 10 剑气反击一次；层数用完见切结束、架势照常；
##      不相邻、剑气不足、没有层数都不反击；反击不吃架势总降。
##   ⑤ 嘲讽（R1.18）：敌人站位定下后，在合法目标里优先选带嘲讽的单位，多个时按原优先级（得分）。
##   ⑥ 浮生若梦：架势总降 25%；若即把原本会命中的攻击（含范围攻击）改为回避并给若离、必中攻击不受影响、
##      普通控制改为抵抗；若离在造成技能伤害时耗 1 层得 15 剑气，不造成伤害的技能不耗。
##   ⑥b 若即对带控制的范围攻击（端到端）：回避只耗 1 层，附带的眩晕落空；没有若即时同一技能命中并眩晕。
##
## 运行：
##   <Godot_console.exe> --headless --path <worktree> --script res://tests/test_kensei_memory_zhaojia.gd

const SplashFixture := preload("res://tests/fixtures/splash_area_skill.gd")

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []


func _initialize() -> void:
	print("=== test_kensei_memory_zhaojia（回忆技能·招架组）===")
	_run.call_deferred()


func _run() -> void:
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	scene.run_injected = true
	scene.injected_map_id = "test_arena"
	scene.injected_player_units = [
		{"class_id": "kensei", "pos": Vector2i(1, 1)},
		{"class_id": "kensei", "pos": Vector2i(5, 5)},
	]
	scene.injected_enemy_units = [
		{"class_id": "test_lancer", "pos": Vector2i(2, 1)},
		{"class_id": "test_lancer", "pos": Vector2i(6, 5)},
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
	var swords: Array[Unit] = []
	var enemies: Dictionary = {}
	for u: Variant in tm.units:
		if not u is Unit:
			continue
		var unit: Unit = u
		if unit.unit_id == "kensei":
			swords.append(unit)
		elif unit.faction == "enemy":
			enemies[unit.grid_position] = unit
			unit.stats.max_hp = 999
			unit.stats.hp = 999
			unit.stats.spd = 0
			unit.stats.def_attr = 0
	if swords.size() < 2 or enemies.size() < 2:
		_check("场景含两名剑圣与两名敌人", false)
		_finish(scene)
		return
	swords.sort_custom(func(a: Unit, b: Unit) -> bool: return a.grid_position.x < b.grid_position.x)
	for ks: Unit in swords:
		ks.stats.dex = 80
		ks.stats.max_hp = 999
		ks.stats.hp = 999

	var dl: Node = root.get_node("/root/DataLoader")
	_test_data(dl)
	_test_apply_and_slot(tm, dl, swords)
	_test_jieli(tm, swords[0], enemies[Vector2i(2, 1)])
	_test_counter(tm, swords[0], enemies[Vector2i(2, 1)])
	_test_taunt(swords)
	_test_qiefan(tm, swords[1], enemies[Vector2i(6, 5)])
	_finish(scene)


# ── ① 数据 ───────────────────────────────────────────

func _test_data(dl: Node) -> void:
	print("\n[①] 数据")
	for id: String in ["kensei_jieli", "kensei_qiefan"]:
		var s: Dictionary = dl.skills.get(id, {})
		_check(id + " 已装载", not s.is_empty())
		_eq(id + " upgrade_of", str(s.get("upgrade_of", "")), "kensei_zhaojia")
		_eq(id + " 迅捷", str(s.get("action_cost", "")), "swift")
		_eq(id + " 保留招架槽换出拔刀", [str(s.get("slot_swap_trigger", "")), str(s.get("slot_swap_target", ""))],
			["marks_and_qi", "kensei_badao"])
	_eq("见切 冷却 2", int(dl.skills["kensei_jieli"].cooldown), 2)
	_eq("浮生若梦 冷却 3", int(dl.skills["kensei_qiefan"].cooldown), 3)
	var counter: Dictionary = (dl.held_states["kensei_jianqie_stance"] as Dictionary).get("engine_counter", {})
	_eq("反击：10 剑气、威力 +1、系数 1.0", [int(counter.get("qi_cost", 0)), int(counter.get("power", 0)),
		float(counter.get("coefficient", 0.0))], [10, 1, 1.0])
	var ruoli: Dictionary = (dl.held_states["kensei_ruoli"] as Dictionary).get("engine_on_skill_damage", {})
	_eq("若离：耗 1 层得 15 剑气", [int(ruoli.get("consume", 0)), int(ruoli.get("qi_gain", 0))], [1, 15])
	var ruoji: Dictionary = (dl.held_states["kensei_ruoji"] as Dictionary).get("engine_evade_conversion", {})
	_eq("若即：转出若离", str(ruoji.get("gain_state", "")), "kensei_ruoli")


# ── ② 兑现与槽位 ─────────────────────────────────────

func _test_apply_and_slot(tm: Node, dl: Node, swords: Array[Unit]) -> void:
	print("\n[②] 兑现与招架槽")
	var pairs: Array = [[swords[0], "kensei_houfazhiren", "kensei_jieli"],
		[swords[1], "kensei_shihuo", "kensei_qiefan"]]
	for p: Array in pairs:
		var u: Unit = p[0]
		var index: int = u.skill_ids.find("kensei_zhaojia")
		var r: Dictionary = u.apply_memory(str(p[1]), dl.memories, dl.skills)
		_check("%s 兑现成功" % p[1], bool(r.get("ok", false)), str(r.get("reason", "")))
		_eq("招架原位换成 %s" % p[2], u.skill_ids[index] if index >= 0 else "", str(p[2]))
		_eq("%s 的身份是招架（R2.5）" % p[2], u.get_skill_identity(str(p[2])), "kensei_zhaojia")
	var ks: Unit = swords[0]
	_enter_action_phase(tm, ks)
	ks.skill_cooldowns.clear()
	ks.marks = {"心": true, "道": true, "势": true}
	ks.set_sword_qi(20)
	_eq("3 印记、20 剑气：见切那一格换出拔刀", _slot(tm, "kensei_jieli").get("skill_id"), "kensei_badao")
	ks.set_sword_qi(0)
	_eq("条件不成立时是见切", _slot(tm, "kensei_jieli").get("skill_id"), "kensei_jieli")
	ks.clear_marks()
	_leave_action_phase(tm)


# ── ③ 见切 ───────────────────────────────────────────

func _test_jieli(tm: Node, ks: Unit, enemy: Unit) -> void:
	print("\n[③] 见切：架势与层数")
	_enter_action_phase(tm, ks)
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.set_sword_qi(65)
	var avoid_before: int = ks.get_avoid_value(0)
	_cast(tm, ks, "kensei_jieli", ks.grid_position, ks)
	_check("获得架势", ks.held_states.has("kensei_jiashi"))
	_eq("剑气 65：见切 1 + 2 = 3 层", ks.held_states.stacks("kensei_jianqie_stance"), 3)
	_eq("架势与见切持续到其后第 2 个自身回合开始", [ks.held_states.remaining("kensei_jiashi"),
		ks.held_states.remaining("kensei_jianqie_stance")], [2, 2])
	_check("架势期间有嘲讽", ks.has_taunt())
	_eq("额外闪避 = 技巧 × 50%", ks.get_avoid_value(0) - avoid_before,
		floori(float(ks.get_effective_stat("DEX")) * 0.5))
	_check("消耗迅捷行动", ks.swift_used)
	# 再次获得：层数设为本次层数（Q3），不相加。
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.set_sword_qi(30)
	_cast(tm, ks, "kensei_jieli", ks.grid_position, ks)
	_eq("剑气 30 再用：层数设为 2（不是 3 + 2）", ks.held_states.stacks("kensei_jianqie_stance"), 2)
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.set_sword_qi(0)
	_cast(tm, ks, "kensei_jieli", ks.grid_position, ks)
	_eq("剑气 0：1 层", ks.held_states.stacks("kensei_jianqie_stance"), 1)

	# 架势：只作用于自身回合内的技能伤害。
	ks.is_taking_turn = true
	_eq("自身回合内的技能：总降 20%", _context(tm, ks, "kensei_zhanji", enemy).get("damage_total_modifiers"), [0.8])
	ks.is_taking_turn = false
	_eq("不在自身回合：不降", _context(tm, ks, "kensei_zhanji", enemy).get("damage_total_modifiers"), [])
	ks.is_taking_turn = true
	var counter_ctx: Dictionary = tm._build_hostile_action_context(ks, enemy,
		{"skill_id": "counter:kensei_jianqie_stance", "is_counter": true})
	_eq("反击不吃架势总降", counter_ctx.get("damage_total_modifiers"), [])
	ks.is_taking_turn = false
	_leave_action_phase(tm)


# ── ④ 反击 ───────────────────────────────────────────

func _test_counter(tm: Node, ks: Unit, enemy: Unit) -> void:
	print("\n[④] 见切：反击")
	ks.held_states.apply("kensei_jianqie_stance", 1, {"kind": "until_own_turn_start", "count": 2})
	_eq("前提：见切 1 层", ks.held_states.stacks("kensei_jianqie_stance"), 1)
	ks.set_sword_qi(25)
	enemy.reset_action_resources()
	var hp_before: int = enemy.stats.hp
	var counters: Array[String] = []
	var on_damage: Callable = func(_amount: int, _type: String) -> void: counters.append("hit")
	enemy.damage_taken.connect(on_damage)
	_check("敌人普通攻击执行成功", bool(tm._execute_attack_action(GameAction.make_attack(enemy, ks))))
	enemy.damage_taken.disconnect(on_damage)
	_eq("反击一次：消耗 10 剑气", ks.sword_qi, 15)
	_eq("层数用完：见切结束", ks.held_states.has("kensei_jianqie_stance"), false)
	_check("架势照常持续", ks.held_states.has("kensei_jiashi"))
	_check("反击对攻击者造成伤害", enemy.stats.hp < hp_before, "hp=%d" % enemy.stats.hp)
	_eq("每个敌方攻击动作最多反击一次", counters.size(), 1)

	# 没有层数：不反击。
	enemy.reset_action_resources()
	hp_before = enemy.stats.hp
	tm._execute_attack_action(GameAction.make_attack(enemy, ks))
	_eq("没有见切层数：不反击（剑气不变）", ks.sword_qi, 15)
	_eq("没有见切层数：攻击者不受伤", enemy.stats.hp, hp_before)

	# 剑气不足：不反击，层数保留。
	ks.held_states.apply("kensei_jianqie_stance", 1, {"kind": "until_own_turn_start", "count": 2})
	ks.set_sword_qi(9)
	enemy.reset_action_resources()
	hp_before = enemy.stats.hp
	tm._execute_attack_action(GameAction.make_attack(enemy, ks))
	_eq("剑气 9：不反击，层数保留", ks.held_states.stacks("kensei_jianqie_stance"), 1)
	_eq("剑气 9：攻击者不受伤", enemy.stats.hp, hp_before)

	# 同一动作里重复登记（多段、多目标）：层数与剑气都充足，也只反击一次。
	ks.held_states.apply("kensei_jianqie_stance", 3, {"kind": "until_own_turn_start", "count": 2})
	ks.set_sword_qi(50)
	tm._note_reaction(enemy, ks, {})
	tm._note_reaction(enemy, ks, {})
	tm._note_reaction(enemy, ks, {"is_counter": true})
	tm._run_pending_reactions()
	_eq("重复登记只反击一次：层数 3 → 2", ks.held_states.stacks("kensei_jianqie_stance"), 2)
	_eq("重复登记只反击一次：剑气 50 → 40", ks.sword_qi, 40)
	ks.held_states.remove("kensei_jianqie_stance")
	ks.held_states.apply("kensei_jianqie_stance", 1, {"kind": "until_own_turn_start", "count": 2})

	# M1：反击不带出副手追加（R1.15）。双持剑圣（二天一流 + 副手）反击时只造成一次伤害。
	ks.talent_ids = ["kensei_ertianyiliu"]
	ks.equip_offhand("eq_wpn_regal_blade")
	tm._talent_registry = null
	ks.set_sword_qi(50)
	var hits: Array[int] = []
	var on_hit: Callable = func(amount: int, _type: String) -> void: hits.append(amount)
	enemy.damage_taken.connect(on_hit)
	tm._try_counter(ks, enemy)
	enemy.damage_taken.disconnect(on_hit)
	_eq("双持反击：只有反击这一下，没有副手追加", hits.size(), 1)
	ks.talent_ids = []
	ks.unequip_offhand()
	tm._talent_registry = null
	ks.held_states.apply("kensei_jianqie_stance", 1, {"kind": "until_own_turn_start", "count": 2})

	# 不相邻：登记反应后不反击。
	ks.set_sword_qi(50)
	tm._pending_reactions.append({"attacker": enemy, "defender": ks})
	var home: Vector2i = enemy.grid_position
	tm.grid.move_unit(enemy, home, Vector2i(4, 1))
	enemy.grid_position = Vector2i(4, 1)
	tm._run_pending_reactions()
	_eq("不相邻：不反击，层数保留", ks.held_states.stacks("kensei_jianqie_stance"), 1)
	_eq("不相邻：剑气不变", ks.sword_qi, 50)
	tm.grid.move_unit(enemy, Vector2i(4, 1), home)
	enemy.grid_position = home
	ks.held_states.remove("kensei_jianqie_stance")


# ── ⑤ 嘲讽 ───────────────────────────────────────────

func _test_taunt(swords: Array[Unit]) -> void:
	print("\n[⑤] 嘲讽（R1.18）")
	var a: Unit = swords[0]  # (1,1)，有架势（嘲讽）
	var b: Unit = swords[1]  # (5,5)
	_check("前提：a 有嘲讽、b 没有", a.has_taunt() and not b.has_taunt())
	a.stats.hp = 900
	b.stats.hp = 100
	var targets: Array[Unit] = [a, b]
	# 原逻辑（得分）选 b；站位定下后，射程内有嘲讽单位时改选 a，站位不变。
	var scored: Dictionary = {a: {"score": 1.0, "kill": false}, b: {"score": 50.0, "kill": true}}
	var tie: Array = ["kill", "move_cells", "target_hp", "cell_yx"]
	var at_33: Dictionary = {"pos": Vector2i(3, 3), "move_cost": 2, "target": b,
		"score": 50.0, "kill": true}  # 到 a、b 都是 4 格
	var picked: Dictionary = EnemyAI._pick_taunting_target(at_33, targets, scored, 1, 4, tie)
	_eq("站位射程内有嘲讽单位：改选它", picked.get("target"), a)
	_eq("改选目标不改站位", picked.get("pos"), Vector2i(3, 3))
	var at_54: Dictionary = {"pos": Vector2i(5, 4), "move_cost": 0, "target": b,
		"score": 50.0, "kill": true}
	_check("站位射程内没有嘲讽单位：沿用原选择",
		EnemyAI._pick_taunting_target(at_54, targets, scored, 1, 1, tie).is_empty())
	a.stats.hp = 999
	b.stats.hp = 999


# ── ⑥ 浮生若梦 ───────────────────────────────────────

func _test_qiefan(tm: Node, ks: Unit, enemy: Unit) -> void:
	print("\n[⑥] 浮生若梦：架势、若即、若离")
	_enter_action_phase(tm, ks)
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.set_sword_qi(30)
	_cast(tm, ks, "kensei_qiefan", ks.grid_position, ks)
	_check("获得架势", ks.held_states.has("kensei_jiashi"))
	_eq("剑气 30：若即 2 层", ks.held_states.stacks("kensei_ruoji"), 2)
	_check("浮生若梦的架势没有嘲讽", not ks.has_taunt())
	ks.is_taking_turn = true
	_eq("自身回合内的技能：总降 25%", _context(tm, ks, "kensei_zhanji", enemy).get("damage_total_modifiers"), [0.75])
	ks.is_taking_turn = false
	_leave_action_phase(tm)

	# 若即：原本会命中的攻击改为回避。
	enemy.stats.dex = 300
	var hp_before: int = ks.stats.hp
	enemy.reset_action_resources()
	tm._execute_attack_action(GameAction.make_attack(enemy, ks))
	_eq("原本会命中的攻击改为回避：不受伤", ks.stats.hp, hp_before)
	_eq("消耗 1 层若即", ks.held_states.stacks("kensei_ruoji"), 1)
	_eq("获得 1 层若离", ks.held_states.stacks("kensei_ruoli"), 1)
	_eq("若离持续到下个自身回合结束", ks.held_states.remaining("kensei_ruoli"), 1)
	# 必中攻击不受影响（不耗层数）。
	var sure: Dictionary = {"hit": true, "crit": false}
	tm._apply_evade_conversion(ks, sure, {"guaranteed_hit": true})
	_check("必中攻击：仍然命中，不耗层数", bool(sure.hit) and ks.held_states.stacks("kensei_ruoji") == 1)
	var natural: Dictionary = {"hit": false, "crit": false}
	tm._apply_evade_conversion(ks, natural, {})
	_eq("自然未命中：不耗层数", ks.held_states.stacks("kensei_ruoji"), 1)
	# 范围攻击同样受影响（用户 2026-10-30「伤害也有效」）。
	var area: Dictionary = {"hit": true, "crit": false}
	tm._apply_evade_conversion(ks, area, {"attack_type": "area"})
	_check("范围攻击：改为回避", not bool(area.hit))
	_eq("范围攻击：消耗最后 1 层若即", ks.held_states.stacks("kensei_ruoji"), 0)
	_eq("范围攻击：给若离", ks.held_states.stacks("kensei_ruoli"), 2)

	# 普通控制改为抵抗。
	ks.held_states.apply("kensei_ruoji", 1, {"kind": "permanent"})
	ks.stats.lck = 0
	tm._apply_skill_effect_to_unit(enemy, ks, {"effect_id": "stun", "chance": 100, "duration": 1}, true)
	_check("眩晕被抵抗", ks.get_buff("stun") == null)
	_eq("抵抗消耗最后 1 层若即", ks.held_states.stacks("kensei_ruoji"), 0)
	_eq("抵抗也给若离", ks.held_states.stacks("kensei_ruoli"), 3)
	# 没有若即时照常命中。
	enemy.reset_action_resources()
	hp_before = ks.stats.hp
	tm._execute_attack_action(GameAction.make_attack(enemy, ks))
	_check("没有若即：攻击照常命中", ks.stats.hp < hp_before)
	_test_ruoji_area_control(tm, ks, enemy)
	enemy.stats.dex = 0

	# 若离：造成技能伤害时耗 1 层、得 15 剑气；每次技能最多 1 层。
	_enter_action_phase(tm, ks)
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.set_sword_qi(0)
	ks.clear_marks()
	enemy.stats.hp = 999
	_cast(tm, ks, "kensei_yijue", enemy.grid_position, enemy)
	_eq("连斩三段各 +10 = 30，若离 +15 = 45", ks.sword_qi, 45)
	_eq("三段伤害也只耗 1 层若离（每次技能最多 1 层）：3 → 2", ks.held_states.stacks("kensei_ruoli"), 2)
	# 不造成伤害的技能不耗。
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	_cast(tm, ks, "kensei_qiefan", ks.grid_position, ks)
	_eq("浮生若梦不造成伤害：不耗若离", ks.held_states.stacks("kensei_ruoli"), 2)
	_leave_action_phase(tm)


## 若即对带控制的范围攻击（端到端）：敌人用范围技能走真实施放路径。原本会命中时改为回避，
## 只耗 1 层；附带的眩晕随之落空，不再触发「控制改为抵抗」去多耗一层（设计库 kensei_ruoji rules）。
## 对照组：没有若即时同一技能命中并眩晕，证明夹具确实会施加控制。
func _test_ruoji_area_control(tm: Node, ks: Unit, enemy: Unit) -> void:
	print("\n[⑥b] 若即：带控制的范围攻击（端到端）")
	var dl: Node = root.get_node("/root/DataLoader")
	var skill_id: String = SplashFixture.install(dl)
	# 夹具是剑圣技能的副本：去掉剑气与印记门槛，换上一个必定施加的眩晕，让敌人能用。
	var fixture: Dictionary = dl.skills[skill_id]
	fixture["qi_cost"] = 0
	fixture["mark_cost"] = 0
	fixture["requires_marks"] = 0
	fixture["effects"] = [{"effect_id": "stun", "chance": 100, "duration": 1}]
	_check("前提：眩晕是控制类", str((dl.buffs.get("stun", {}) as Dictionary).get("effect_type", "")) == "control")
	ks.stats.lck = 0
	# 抵抗倍率为 1 时眩晕必定施加：否则「回避后仍施加效果」的错误可能因施加自然失败而漏过。
	_check("前提：抵抗倍率为 1", is_equal_approx(ks.get_status_resist_multiplier(), 1.0))
	_clear_stun(ks)
	var hp_entry: int = ks.stats.hp
	ks.held_states.apply("kensei_ruoji", 2, {"kind": "permanent"})
	# 若离最多 3 层，先清空才看得出这次只加了 1 层；结束时恢复，后面的若离用例接着用。
	var ruoli_before: int = ks.held_states.stacks("kensei_ruoli")
	var ruoli_remaining: int = ks.held_states.remaining("kensei_ruoli")
	ks.held_states.remove("kensei_ruoli")
	var hp_before: int = ks.stats.hp
	enemy.reset_action_resources()
	var act: GameAction = _enemy_skill_action(tm, enemy, skill_id, ks)
	_check("前提：载荷是范围攻击", act != null and str(act.data.get("attack_type", "")) == "area")
	var effects: Array = act.data.get("effects", []) if act != null else []
	_check("前提：载荷带眩晕", effects.size() == 1
		and str((effects[0] as Dictionary).get("effect_id", "")) == "stun")
	_check("范围技能执行成功", act != null and bool(tm._execute_skill_action(act)))
	_eq("改为回避：不受伤", ks.stats.hp, hp_before)
	_check("附带的眩晕落空", ks.get_buff("stun") == null)
	_eq("只耗 1 层若即：2 → 1", ks.held_states.stacks("kensei_ruoji"), 1)
	_eq("若离只加 1 层", ks.held_states.stacks("kensei_ruoli"), 1)

	# 对照组：没有若即时同一技能命中并眩晕。
	ks.held_states.remove("kensei_ruoji")
	enemy.reset_action_resources()
	enemy.skill_cooldowns.clear()
	act = _enemy_skill_action(tm, enemy, skill_id, ks)
	_check("对照：范围技能执行成功", act != null and bool(tm._execute_skill_action(act)))
	_check("对照：命中受伤", ks.stats.hp < hp_before)
	_check("对照：被眩晕", ks.get_buff("stun") != null)
	_clear_stun(ks)
	# 按进入前的状态复原：生命、若离层数与持续时间（若离由若即按 gain_duration 给出）。
	ks.stats.hp = hp_entry
	ks.held_states.remove("kensei_ruoli")
	var gain_duration: Dictionary = ((dl.held_states["kensei_ruoji"] as Dictionary)
		["engine_evade_conversion"] as Dictionary).get("gain_duration", {})
	ks.held_states.apply("kensei_ruoli", ruoli_before, gain_duration)
	_eq("复原：若离层数与持续时间", [ks.held_states.stacks("kensei_ruoli"),
		ks.held_states.remaining("kensei_ruoli")], [ruoli_before, ruoli_remaining])
	dl.skills.erase(skill_id)


## 走真实施放路径构建敌人的技能动作：载荷由 _build_skill_action 按技能数据填写。
func _enemy_skill_action(tm: Node, enemy: Unit, skill_id: String, target: Unit) -> GameAction:
	tm.current_unit = enemy
	tm._selected_skill_id = skill_id
	var act: GameAction = tm._build_skill_action(enemy, target.grid_position, target)
	tm._selected_skill_id = ""
	tm.current_unit = null
	return act


func _clear_stun(u: Unit) -> void:
	var stun: BuffEffect = u.get_buff("stun")
	if stun != null:
		u.remove_buff(stun)


# ── 工具 ─────────────────────────────────────────────

func _slot(tm: Node, origin_id: String) -> Dictionary:
	for entry: Dictionary in tm._get_skill_entries():
		if str(entry.get("slot_origin_id", "")) == origin_id:
			return entry
	return {}


func _context(tm: Node, ks: Unit, skill_id: String, target: Unit) -> Dictionary:
	tm.current_unit = ks
	tm._selected_skill_id = skill_id
	var act: Object = tm._build_skill_action(ks, target.grid_position, target)
	tm._selected_skill_id = ""
	return {} if act == null else tm._build_hostile_action_context(ks, target, act.data)


func _enter_action_phase(tm: Node, u: Unit) -> void:
	tm.current_unit = u
	tm.selected_unit = u
	tm.turn_manager.current_unit = u
	tm.input_state = 2  # ACTION_PHASE


func _leave_action_phase(tm: Node) -> void:
	tm.turn_manager.current_unit = null
	tm.current_unit = null
	tm.input_state = 0


func _cast(tm: Node, u: Unit, skill_id: String, pos: Vector2i, target: Unit) -> void:
	tm.current_unit = u
	tm._selected_skill_id = skill_id
	var act: Object = tm._build_skill_action(u, pos, target)
	_check(skill_id + " 动作可构建", act != null)
	if act != null:
		_check(skill_id + " 执行成功", bool(tm._execute_skill_action(act)))
	tm._selected_skill_id = ""


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
