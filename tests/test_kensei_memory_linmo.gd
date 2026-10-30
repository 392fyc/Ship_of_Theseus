extends SceneTree
## 回忆技能·居合组之二（gameplay-impl PR6f-2，差距清单 M20）：〔虚实相生〕→〔临摹〕〔颠倒〕与〔影〕。
##
## 依据：设计库 762393b 的 kensei_linmo / kensei_diandao（〔影〕的规则写在临摹的 rules 里）；
## R1.1、R1.10、R2.5；用户裁决 Q6（敌人只会普通攻击时，先按「普通攻击可选影」实装）。
## 覆盖：
##   ① 数据与挂载；召唤物不在职业与敌人表里。
##   ② 临摹：只能选可通行的空格，否则不可选、执行被拒且不扣消耗；召唤影（属于自身一方、不进回合顺序）；
##      槽位换成颠倒；消耗 60 剑气、迅捷、冷却 4。
##   ③ 影：敌人可以选它为目标且必定命中；每个伤害包计 1 次、生命不减，4 次后消失，槽位换回临摹；
##      召唤后的第 3 个主人自身回合结束时消失（召唤所在的回合不计）；友方效果不选影。
##   ④ 颠倒：与影换位；没有影时被拒。
##   ⑤ 照做：斩击后影在自己的位置再打一遍，伤害约为一半，不计主人的澄心威力，不给剑气与印记；
##      非斩击系、拔刀系的技能不照做；影的射程内没有敌人时不照做；以自身为中心的范围以影为中心。
##   ⑥ 胜负：只剩影时判定全灭。
##
## 运行：
##   <Godot_console.exe> --headless --path <worktree> --script res://tests/test_kensei_memory_linmo.gd

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []


func _initialize() -> void:
	print("=== test_kensei_memory_linmo（回忆技能·虚实相生）===")
	_run.call_deferred()


func _run() -> void:
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	scene.run_injected = true
	scene.injected_map_id = "test_arena"
	scene.injected_player_units = [{"class_id": "kensei", "pos": Vector2i(2, 2)}]
	# E1 与剑圣相邻；E2 在 (3,4)，与将要召唤的影 (2,4) 相邻、离剑圣 3 格。
	scene.injected_enemy_units = [
		{"class_id": "test_lancer", "pos": Vector2i(3, 2)},
		{"class_id": "test_lancer", "pos": Vector2i(3, 4)},
	]
	scene.debug_harness_enabled = false
	root.add_child(scene)
	await process_frame
	await process_frame

	var tm: Node = scene.get_node("TacticalManager")
	_check("tactical_manager 脚本已挂载", tm.get_script() != null
		and (tm.get_script() as Script).resource_path == "res://scripts/core/tactical_manager.gd")
	_check("tactical_scene 脚本已挂载", scene.get_script() != null
		and (scene.get_script() as Script).resource_path == "res://scripts/tactical/tactical_scene.gd")
	if tm.turn_manager != null:
		tm.turn_manager.stop()
	var ks: Unit = null
	var e1: Unit = null
	var e2: Unit = null
	for u: Variant in tm.units:
		if not u is Unit:
			continue
		var unit: Unit = u
		if unit.unit_id == "kensei":
			ks = unit
		elif unit.grid_position == Vector2i(3, 2):
			e1 = unit
		elif unit.grid_position == Vector2i(3, 4):
			e2 = unit
	if ks == null or e1 == null or e2 == null:
		_check("场景含剑圣与两名敌人", false)
		_finish(scene)
		return
	for e: Unit in [e1, e2]:
		e.stats.max_hp = 999
		e.stats.hp = 999
		e.stats.spd = 0
		e.stats.def_attr = 0
	ks.stats.dex = 80
	tm.battle_active = true

	var dl: Node = root.get_node("/root/DataLoader")
	_test_data(dl)
	var r: Dictionary = ks.apply_memory("kensei_juhe_xushi", dl.memories, dl.skills)
	_check("虚实相生兑现成功", bool(r.get("ok", false)), str(r.get("reason", "")))
	_check("居合原位换成临摹", ks.skill_ids.has("kensei_linmo") and not ks.skill_ids.has("kensei_juhe"))
	_eq("颠倒身份是居合（R2.5）", ks.get_skill_identity("kensei_diandao"), "kensei_juhe")
	var ying: Unit = _test_linmo(tm, ks)
	if ying == null:
		_finish(scene)
		return
	_test_ying_rules(tm, ks, ying, e2)
	_test_diandao(tm, ks)
	_test_mimic(tm, ks, e1, e2)
	_test_lifetime(tm, ks)
	_test_hits_vanish(tm, ks, e2)
	_test_battle_end(tm, scene, ks)
	_finish(scene)


func _test_data(dl: Node) -> void:
	print("\n[①] 数据")
	var linmo: Dictionary = dl.skills.get("kensei_linmo", {})
	var diandao: Dictionary = dl.skills.get("kensei_diandao", {})
	_check("临摹、颠倒已装载", not linmo.is_empty() and not diandao.is_empty())
	_eq("临摹：迅捷、60 剑气、冷却 4、射程 1–3", [str(linmo.action_cost), int(linmo.qi_cost), int(linmo.cooldown),
		int(linmo.range.min), int(linmo.range.max)], ["swift", 60, 4, 1, 3])
	_eq("颠倒：迅捷、冷却 1", [str(diandao.action_cost), int(diandao.cooldown)], ["swift", 1])
	_eq("照做：斩击系、拔刀系，50%", [linmo.mimic.identities, int(linmo.mimic.damage_pct)],
		[["kensei_zhanji", "kensei_badao"], 50])
	var ying: Dictionary = dl.summons.get("kensei_ying", {})
	_eq("影：生命 4、每包扣 1、第 3 个主人回合",
		[int(ying.base_stats.HP), int(ying.illusion.damage_per_hit), int(ying.illusion.owner_turns)], [4, 1, 3])
	_check("影不在职业表、也不在敌人表", not dl.classes.has("kensei_ying") and not dl.enemies.has("kensei_ying"))


# ── ② 临摹 ───────────────────────────────────────────

func _test_linmo(tm: Node, ks: Unit) -> Unit:
	print("\n[②] 临摹")
	_enter_action_phase(tm, ks)
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.set_sword_qi(100)
	ks.is_taking_turn = true
	tm.request_skill_selection("kensei_linmo")
	_check("可选格不含有单位的格（剑圣自己、E1）", not Vector2i(3, 2) in tm._attack_cells)
	_check("可选格含空格 (2,4)", Vector2i(2, 4) in tm._attack_cells)
	tm._cancel_targeting()
	_enter_action_phase(tm, ks)
	# 被占的格：执行被拒、不扣消耗。
	var bad: Object = _build(tm, ks, "kensei_linmo", Vector2i(3, 2), null)
	_check("有单位的格的动作可构建（拒绝发生在执行时）", bad != null)
	if bad != null:
		_eq("有单位的格：执行被拒", bool(tm._execute_skill_action(bad)), false)
	_eq("被拒时不扣剑气", ks.sword_qi, 100)
	_check("被拒时不耗迅捷", not ks.swift_used)

	var act: Object = _build(tm, ks, "kensei_linmo", Vector2i(2, 4), null)
	_check("临摹动作可构建", act != null)
	if act != null:
		_check("临摹执行成功", bool(tm._execute_skill_action(act)))
	var ying: Unit = tm.grid.get_unit_at(Vector2i(2, 4))
	_check("在 (2,4) 召唤了影", ying != null and ying.is_illusion)
	if ying == null:
		return null
	_check("影的脚本已挂载", ying.get_script() != null
		and (ying.get_script() as Script).resource_path == "res://scripts/units/unit.gd")
	_eq("影属于剑圣一方", ying.faction, ks.faction)
	_eq("影的主人是剑圣", ying.illusion_owner, ks)
	_check("影不进回合顺序", not tm.turn_manager._all_units.has(ying))
	_eq("消耗 60 剑气", ks.sword_qi, 40)
	_check("消耗迅捷行动", ks.swift_used)
	_eq("进入冷却 4", ks.get_skill_cooldown("kensei_linmo"), 4)
	_eq("影在场：临摹槽换成颠倒", _slot(tm, "kensei_linmo").get("skill_id"), "kensei_diandao")
	ks.is_taking_turn = false
	_leave_action_phase(tm)
	return ying


# ── ③ 影的规则 ───────────────────────────────────────

func _test_ying_rules(tm: Node, ks: Unit, ying: Unit, e2: Unit) -> void:
	print("\n[③] 影：被选为目标、必定命中、友方效果不选它")
	var actions: Array = EnemyAI.decide_actions(e2, tm.grid, tm.units)
	var attacks_ying: bool = false
	for a: Variant in actions:
		if a is GameAction and (a as GameAction).target_unit == ying:
			attacks_ying = true
	_check("敌人（Q6：普通攻击）可以选影为目标", attacks_ying)
	var ctx: Dictionary = tm._build_hostile_action_context(e2, ying, {})
	_check("敌人对影的攻击必定命中", bool(ctx.get("guaranteed_hit", false)))
	_check("友方关系不包括影", not tm._matches_target_relation(ks, ying, "ally"))
	_check("敌方关系包括影（敌人可以打它）", tm._matches_target_relation(e2, ying, "enemy"))
	_eq("影的生命 4（= 能承受的次数）", ying.stats.hp, 4)
	var preview: Dictionary = DamageCalculator.preview_attack(e2, ying, ctx)
	_eq("预告对影显示每包 1 点", int(preview.get("damage", 0)), 1)
	ying.take_damage(50, "physical")
	_eq("一个伤害包只扣 1 点生命：还剩 3", ying.stats.hp, 3)
	ying.stats.hp = 4


# ── ④ 颠倒 ───────────────────────────────────────────

func _test_diandao(tm: Node, ks: Unit) -> void:
	print("\n[④] 颠倒")
	_enter_action_phase(tm, ks)
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	var ying: Unit = tm.grid.get_unit_at(Vector2i(2, 4))
	var act: Object = _build(tm, ks, "kensei_diandao", ks.grid_position, ks)
	_check("颠倒执行成功", act != null and bool(tm._execute_skill_action(act)))
	_eq("剑圣换到影的位置", ks.grid_position, Vector2i(2, 4))
	_eq("影换到剑圣的位置", ying.grid_position, Vector2i(2, 2))
	_eq("格子占据者随之交换", [tm.grid.get_unit_at(Vector2i(2, 4)), tm.grid.get_unit_at(Vector2i(2, 2))], [ks, ying])
	# 换回去，供后面使用。
	ks.skill_cooldowns.clear()
	ks.reset_action_resources()
	var back: Object = _build(tm, ks, "kensei_diandao", ks.grid_position, ks)
	if back != null:
		tm._execute_skill_action(back)
	_eq("再用一次换回", ks.grid_position, Vector2i(2, 2))
	_leave_action_phase(tm)


# ── ⑤ 照做 ───────────────────────────────────────────

func _test_mimic(tm: Node, ks: Unit, e1: Unit, e2: Unit) -> void:
	print("\n[⑤] 照做")
	tm.debug_harness_active = true
	tm.debug_deterministic = true
	tm.debug_crit_mode = 2  # DISABLE：去掉暴击浮动
	_enter_action_phase(tm, ks)
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.clear_marks()
	ks.set_sword_qi(0)
	ks.held_states.apply("kensei_chengxin", 3, {"kind": "permanent"})
	# 对照：没有澄心时斩击打 E2 的伤害。
	ks.held_states.remove("kensei_chengxin")
	var base_ctx: Dictionary = _context(tm, ks, "kensei_zhanji", e2)
	var full: int = int(DamageCalculator.preview_attack(ks, e2, base_ctx).get("damage", 0))
	ks.held_states.apply("kensei_chengxin", 3, {"kind": "permanent"})
	var e1_before: int = e1.stats.hp
	var e2_before: int = e2.stats.hp
	_cast(tm, ks, "kensei_zhanji", e1.grid_position, e1)
	_check("斩击打中 E1", e1.stats.hp < e1_before)
	var mimic_damage: int = e2_before - e2.stats.hp
	_check("影照做：打到影射程内的 E2", mimic_damage > 0, "dmg=%d" % mimic_damage)
	_check("照做伤害约为不含澄心的斩击的一半", absi(mimic_damage - int(full * 0.5)) <= 1,
		"照做=%d 斩击=%d" % [mimic_damage, full])
	_eq("照做不给剑气：只有斩击自己的 25", ks.sword_qi, 25)
	_eq("照做不给印记：只有斩击自己的 1 枚", ks.get_mark_count(), 1)
	ks.held_states.remove("kensei_chengxin")

	# 非斩击系、拔刀系：不照做。
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.set_sword_qi(100)
	e2_before = e2.stats.hp
	_cast(tm, ks, "kensei_zhaojia", ks.grid_position, ks)
	_eq("招架（不是斩击系、拔刀系）：不照做", e2.stats.hp, e2_before)

	# 影的射程内没有敌人：不照做。
	tm.grid.move_unit(e2, Vector2i(3, 4), Vector2i(7, 7))
	e2.grid_position = Vector2i(7, 7)
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	e2_before = e2.stats.hp
	_cast(tm, ks, "kensei_zhanji", e1.grid_position, e1)
	_eq("影的射程内没有敌人：不照做", e2.stats.hp, e2_before)

	# 以自身为中心的范围（拔刀）：以影为中心再打一圈。
	tm.grid.move_unit(e2, Vector2i(7, 7), Vector2i(2, 5))
	e2.grid_position = Vector2i(2, 5)
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.marks = {"心": true, "道": true, "势": true}
	ks.set_sword_qi(100)
	e2_before = e2.stats.hp
	# 拔刀结算后才扣 3 枚印记；照做要按扣之前的印记算属性（〔势〕力量 +10%）。把力量调高让差别看得出。
	var saved_str: int = ks.stats.str_attr
	ks.stats.str_attr = 60
	var badao_ctx: Dictionary = _context(tm, ks, "kensei_badao", e2)
	var with_marks: int = int(DamageCalculator.preview_attack(ks, e2, badao_ctx).get("damage", 0))
	ks.clear_marks()
	var without_marks: int = int(DamageCalculator.preview_attack(ks, e2, badao_ctx).get("damage", 0))
	ks.marks = {"心": true, "道": true, "势": true}
	_check("前提：有无印记的伤害差得出来", with_marks - without_marks >= 4,
		"有=%d 无=%d" % [with_marks, without_marks])
	_cast(tm, ks, "kensei_badao", ks.grid_position, ks)
	var badao_mimic: int = e2_before - e2.stats.hp
	_check("拔刀：以影为中心打到影身边的 E2", badao_mimic > 0)
	_check("拔刀照做按扣印记之前的属性计算（约为有印记时的一半）",
		absi(badao_mimic - int(with_marks * 0.5)) <= 1,
		"照做=%d 有印记一半=%d 无印记一半=%d" % [badao_mimic, int(with_marks * 0.5), int(without_marks * 0.5)])
	_eq("照做之后印记仍是扣完的状态", ks.get_mark_count(), 0)
	ks.stats.str_attr = saved_str
	tm.grid.move_unit(e2, Vector2i(2, 5), Vector2i(3, 4))
	e2.grid_position = Vector2i(3, 4)

	# 方向攻击（裂空）：从影的位置朝同一方向打。剑圣在 (2,2) 向右打到 E1；影在 (2,4) 向右打到 (3,4) 的 E2。
	var dl: Node = root.get_node("/root/DataLoader")
	var r: Dictionary = ks.apply_memory("kensei_huajianweiqi", dl.memories, dl.skills)
	_check("化剑为气兑现成功（斩击 → 裂空）", bool(r.get("ok", false)), str(r.get("reason", "")))
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	e2_before = e2.stats.hp
	_cast(tm, ks, "kensei_liekong", Vector2i(3, 2), null)
	_check("裂空：影从自己的位置朝同一方向照做，打到 E2", e2.stats.hp < e2_before)
	tm.debug_harness_active = false
	tm.debug_deterministic = false
	_leave_action_phase(tm)


# ── ⑥ 寿命 ───────────────────────────────────────────

func _test_lifetime(tm: Node, ks: Unit) -> void:
	print("\n[⑥] 影的寿命：召唤后的第 3 个主人回合结束")
	var ying: Unit = tm.grid.get_unit_at(Vector2i(2, 4))
	# 召唤所在的回合不计：第 1 次回合结束不减，之后 3 次。
	tm.turn_manager.current_unit = ks
	tm._on_turn_ended(ks)
	_check("召唤所在的回合结束：影仍在", is_instance_valid(ying) and ying.stats.is_alive())
	tm._on_turn_ended(ks)
	tm._on_turn_ended(ks)
	_check("第 2 个主人回合结束：影仍在", is_instance_valid(ying) and ying.stats.is_alive())
	tm._on_turn_ended(ks)
	_check("第 3 个主人回合结束：影消失", not tm.units.has(ying))
	_eq("影消失后槽位换回临摹（槽位记录）", ks.resolve_slot_form("kensei_linmo"), "kensei_linmo")
	_enter_action_phase(tm, ks)
	_eq("影消失后槽位换回临摹（技能栏）", _slot(tm, "kensei_linmo").get("skill_id"), "kensei_linmo")
	_leave_action_phase(tm)
	_check("影消失后格子空出", tm.grid.get_unit_at(Vector2i(2, 4)) == null)


# ── ⑦ 4 个伤害包 ─────────────────────────────────────

func _test_hits_vanish(tm: Node, ks: Unit, e2: Unit) -> void:
	print("\n[⑦] 4 个伤害包后消失")
	_enter_action_phase(tm, ks)
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.set_sword_qi(100)
	var act: Object = _build(tm, ks, "kensei_linmo", Vector2i(2, 4), null)
	if act != null:
		tm._execute_skill_action(act)
	var ying: Unit = tm.grid.get_unit_at(Vector2i(2, 4))
	_check("再次召唤影", ying != null and ying.is_illusion)
	_leave_action_phase(tm)
	if ying == null:
		return
	e2.stats.dex = 0
	ying.stats.spd = 999
	for i: int in range(3):
		e2.reset_action_resources()
		tm._execute_attack_action(GameAction.make_attack(e2, ying))
	_check("3 次后仍在（敌人攻击必定命中，闪避再高也计数）", is_instance_valid(ying) and ying.stats.is_alive())
	_eq("3 次后生命剩 1", ying.stats.hp, 1)
	e2.reset_action_resources()
	tm._execute_attack_action(GameAction.make_attack(e2, ying))
	_check("第 4 次后消失", not tm.units.has(ying))
	_eq("槽位换回临摹（槽位记录）", ks.resolve_slot_form("kensei_linmo"), "kensei_linmo")
	_enter_action_phase(tm, ks)
	_eq("槽位换回临摹（技能栏）", _slot(tm, "kensei_linmo").get("skill_id"), "kensei_linmo")
	_leave_action_phase(tm)


# ── ⑧ 胜负 ───────────────────────────────────────────

func _test_battle_end(tm: Node, scene: Node, ks: Unit) -> void:
	print("\n[⑧] 只剩影时判定全灭")
	_enter_action_phase(tm, ks)
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.set_sword_qi(100)
	var act: Object = _build(tm, ks, "kensei_linmo", Vector2i(2, 4), null)
	if act != null:
		tm._execute_skill_action(act)
	_leave_action_phase(tm)
	_check("前提：影在场", tm.grid.get_unit_at(Vector2i(2, 4)) != null)
	var ying: Unit = tm.grid.get_unit_at(Vector2i(2, 4))
	ks.take_damage(99999, "pure")
	_check("剑圣死亡时影随之消失", not tm.units.has(ying) and tm.grid.get_unit_at(Vector2i(2, 4)) == null)
	_check("剑圣倒下：判定战斗结束", bool(scene._battle_over))
	_eq("判定为全灭", str(scene.result_label.text), "DEFEAT")


# ── 工具 ─────────────────────────────────────────────

func _build(tm: Node, ks: Unit, skill_id: String, pos: Vector2i, target: Unit) -> Object:
	tm.current_unit = ks
	tm._selected_skill_id = skill_id
	var act: Object = tm._build_skill_action(ks, pos, target)
	tm._selected_skill_id = ""
	return act


func _context(tm: Node, ks: Unit, skill_id: String, target: Unit) -> Dictionary:
	var act: Object = _build(tm, ks, skill_id, target.grid_position, target)
	return {} if act == null else tm._build_hostile_action_context(ks, target, act.data)


func _slot(tm: Node, origin_id: String) -> Dictionary:
	for entry: Dictionary in tm._get_skill_entries():
		if str(entry.get("slot_origin_id", "")) == origin_id:
			return entry
	return {}


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
