extends SceneTree
## 回忆技能·拔刀组（gameplay-impl PR6c，差距清单 M11、M16、M17）：
## 〔鞘之内〕→〔满月〕；〔兵无常势〕→〔决心〕〔回天〕〔霸天〕。
##
## 依据：设计库 762393b 的 kensei_dashangduan / sanduanzhan / huitian / batian、states/kensei_nadao；
## R1.1（总增总降逐项相乘）、R1.17（护盾）、R2.5、R3.6。
## 覆盖：
##   ① 数据与挂载。
##   ② 满月：使用招架时得纳刀与一枚印记（已有纳刀不重复）；招架槽在 3 印记、20 剑气时换出本技能，
##      显示名随纳刀切换；纳刀让其他攻击总降 50%，对满月无效且满月再总增 30%；满月结算后移除纳刀。
##   ③ 兵无常势：招架槽按印记与剑气在决心 / 回天 / 霸天之间切换，各形态独立冷却（R3.6）。
##   ④ 决心：自由动作，消耗 1 印记，得 15 剑气。
##   ⑤ 回天：周围有敌人才可用；护盾 = ceil(最大生命 × 5% × 周围敌人数)。
##   ⑥ 护盾（R1.17）：先扣护盾；自身回合开始衰减并受 58% 上限约束。
##   ⑦ 霸天：按发动时范围内敌人数选伤害条目；对每名敌人结算；消耗 3 印记、20 剑气。
##
## 运行：
##   <Godot_console.exe> --headless --path <worktree> --script res://tests/test_kensei_memory_badao.gd

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []


func _initialize() -> void:
	print("=== test_kensei_memory_badao（回忆技能·拔刀组）===")
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
		{"class_id": "test_lancer", "pos": Vector2i(5, 6)},
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
	if swords.size() < 2 or enemies.size() < 3:
		_check("场景含两名剑圣与三名敌人", false)
		_finish(scene)
		return
	_check("剑圣单位脚本已挂载", (swords[0].get_script() as Script).resource_path
		== "res://scripts/units/unit.gd")
	for ks: Unit in swords:
		ks.stats.dex = 80
	swords.sort_custom(func(a: Unit, b: Unit) -> bool: return a.grid_position.x < b.grid_position.x)

	var dl: Node = root.get_node("/root/DataLoader")
	_test_data(dl)
	_test_mangetsu(tm, dl, swords[0], enemies[Vector2i(2, 1)])
	_test_forms(tm, dl, swords[1])
	_test_juexin(tm, swords[1])
	_test_huitian(tm, swords[1], enemies)
	_test_shield(tm, swords[1])
	_test_batian(tm, swords[1], enemies)
	_finish(scene)


# ── ① 数据 ───────────────────────────────────────────

func _test_data(dl: Node) -> void:
	print("\n[①] 数据")
	for id: String in ["kensei_dashangduan", "kensei_sanduanzhan", "kensei_huitian", "kensei_batian"]:
		var s: Dictionary = dl.skills.get(id, {})
		_check(id + " 已装载", not s.is_empty())
		_eq(id + " upgrade_of", str(s.get("upgrade_of", "")), "kensei_badao")
		_check(id + " 不独立占槽（slot_swap_provider）", bool(s.get("slot_swap_provider", false)))
		_check(id + " 自己声明了 slot_swap_requires", s.get("slot_swap_requires", null) is Dictionary)
	var m: Dictionary = dl.skills["kensei_dashangduan"]
	_eq("满月 名称", str(m.name), "满月")
	_eq("满月 显示名（无纳刀）", str(m.held_state_form.name_without_state), "拔刀")
	_eq("满月 总增 30%", float(m.held_state_form.damage_total_modifier), 1.3)
	_eq("满月 消耗 3 印记 20 剑气", [int(m.mark_cost), int(m.qi_cost)], [3, 20])
	_eq("纳刀 总降 50%", float((dl.held_states["kensei_nadao"] as Dictionary).get(
		"engine_damage_total_modifier", 0.0)), 0.5)
	var j: Dictionary = dl.skills["kensei_sanduanzhan"]
	_eq("决心 自由动作、冷却 2", [str(j.action_cost), int(j.cooldown)], ["free", 2])
	_eq("决心 消耗 1 印记、得 15 剑气", [int(j.mark_cost), int(j.qi_gain_after_resolve)], [1, 15])
	var h: Dictionary = dl.skills["kensei_huitian"]
	_eq("回天 迅捷、冷却 4", [str(h.action_cost), int(h.cooldown)], ["swift", 4])
	_eq("回天 消耗 2 印记 10 剑气", [int(h.mark_cost), int(h.qi_cost)], [2, 10])
	_eq("回天 每名敌人 5%", float(h.shield_gain.max_hp_pct_per_enemy), 5.0)
	var b: Dictionary = dl.skills["kensei_batian"]
	_eq("霸天 两条伤害条目", (b.damage_entries as Array).size(), 2)
	_eq("霸天 消耗 3 印记 20 剑气", [int(b.mark_cost), int(b.qi_cost)], [3, 20])
	var rule: Dictionary = (dl.rules as Dictionary).get("shield", {})
	_eq("R1.17 参数", [int(rule.get("decay_pct", 0)), int(rule.get("res_scale", 0)),
		int(rule.get("max_keep_pct", 0))], [50, 100, 58])


# ── ② 满月 ───────────────────────────────────────────

func _test_mangetsu(tm: Node, dl: Node, ks: Unit, enemy: Unit) -> void:
	print("\n[②] 满月")
	var r: Dictionary = ks.apply_memory("kensei_guzhuyizhi", dl.memories, dl.skills)
	_check("鞘之内兑现成功", bool(r.get("ok", false)), str(r.get("reason", "")))
	_check("拔刀换成满月", ks.skill_ids.has("kensei_dashangduan") and not ks.skill_ids.has("kensei_badao"))
	_eq("满月身份是拔刀（R2.5）", ks.get_skill_identity("kensei_dashangduan"), "kensei_badao")

	# 使用招架：没有纳刀 → 得纳刀 + 一枚印记。
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.clear_marks()
	ks.set_sword_qi(0)
	_enter_action_phase(tm, ks)
	_cast(tm, ks, "kensei_zhaojia", ks.grid_position, ks)
	_check("使用招架后获得纳刀", ks.held_states.has("kensei_nadao"))
	_eq("同时获得一枚印记", ks.get_mark_count(), 1)
	# 已持有纳刀：再用招架不重复得印记。
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	_cast(tm, ks, "kensei_zhaojia", ks.grid_position, ks)
	_eq("已有纳刀时不再得印记", ks.get_mark_count(), 1)
	# 其他技能不触发。
	ks.held_states.remove("kensei_nadao")
	ks.reset_action_resources()
	_cast(tm, ks, "kensei_zhanji", enemy.grid_position, enemy)
	_check("使用斩击不给纳刀", not ks.held_states.has("kensei_nadao"))

	# 招架槽：3 印记、20 剑气换成满月；显示名随纳刀。
	ks.marks = {"心": true, "道": true, "势": true}
	ks.set_sword_qi(20)
	ks.skill_cooldowns.clear()
	var slot: Dictionary = _zhaojia_slot(tm)
	_eq("3 印记、20 剑气时招架槽换成满月", slot.get("skill_id"), "kensei_dashangduan")
	_eq("没有纳刀时显示为拔刀", slot.get("name"), "拔刀")
	ks.apply_held_state("kensei_nadao", 1, {"kind": "permanent"})
	_eq("持有纳刀时显示为满月", _zhaojia_slot(tm).get("name"), "满月")
	ks.set_sword_qi(19)
	_eq("剑气 19 时恢复招架", _zhaojia_slot(tm).get("skill_id"), "kensei_zhaojia")
	ks.set_sword_qi(20)

	# 伤害修正：纳刀让其他攻击总降 50%；满月持纳刀时忽略纳刀并总增 30%。
	var zhanji_ctx: Dictionary = _hostile_context(tm, ks, "kensei_zhanji", enemy.grid_position, enemy)
	_eq("持纳刀时斩击总降 50%", zhanji_ctx.get("damage_total_modifiers"), [0.5])
	var mangetsu_ctx: Dictionary = _hostile_context(tm, ks, "kensei_dashangduan", ks.grid_position, enemy)
	_eq("持纳刀时满月：纳刀无效、总增 30%", mangetsu_ctx.get("damage_total_modifiers"), [1.3])
	var with_nadao: int = int(DamageCalculator.preview_attack(ks, enemy, mangetsu_ctx).get("damage", 0))
	ks.held_states.remove("kensei_nadao")
	var plain_ctx: Dictionary = _hostile_context(tm, ks, "kensei_dashangduan", ks.grid_position, enemy)
	_eq("没有纳刀时按拔刀结算（无修正）", plain_ctx.get("damage_total_modifiers"), [])
	var without_nadao: int = int(DamageCalculator.preview_attack(ks, enemy, plain_ctx).get("damage", 0))
	_check("满月比拔刀伤害高（×1.3）", with_nadao > without_nadao,
		"满月=%d 拔刀=%d" % [with_nadao, without_nadao])
	ks.apply_held_state("kensei_nadao", 1, {"kind": "permanent"})
	_eq("纳刀的总降也给副手追加用（攻击者状态修正）", tm._attacker_state_damage_modifiers(ks, []), [0.5])
	_eq("满月声明对纳刀无效时不计入", tm._attacker_state_damage_modifiers(ks, ["kensei_nadao"]), [])
	ks.held_states.remove("kensei_nadao")
	_check("满月伤害约为拔刀的 1.3 倍", absi(with_nadao - int(floor(without_nadao * 1.3))) <= 1,
		"满月=%d 拔刀=%d" % [with_nadao, without_nadao])

	# 满月结算后移除纳刀。
	ks.apply_held_state("kensei_nadao", 1, {"kind": "permanent"})
	ks.reset_action_resources()
	var hp_before: int = enemy.stats.hp
	_cast(tm, ks, "kensei_dashangduan", ks.grid_position, ks)
	_check("满月对范围内敌人造成伤害", enemy.stats.hp < hp_before)
	_check("满月结算后移除纳刀", not ks.held_states.has("kensei_nadao"))
	_eq("满月消耗 3 印记", ks.get_mark_count(), 0)
	_eq("满月消耗 20 剑气", ks.sword_qi, 0)
	_leave_action_phase(tm)


# ── ③ 兵无常势的槽位 ────────────────────────────────

func _test_forms(tm: Node, dl: Node, ks: Unit) -> void:
	print("\n[③] 兵无常势：招架槽的三种形态")
	var r: Dictionary = ks.apply_memory("kensei_huazhengweiling", dl.memories, dl.skills)
	_check("兵无常势兑现成功", bool(r.get("ok", false)), str(r.get("reason", "")))
	_check("拔刀换成决心", ks.skill_ids.has("kensei_sanduanzhan"))
	for form: String in ["kensei_sanduanzhan", "kensei_huitian", "kensei_batian"]:
		_eq(form + " 身份是拔刀（R2.5）", ks.get_skill_identity(form), "kensei_badao")
	_enter_action_phase(tm, ks)
	ks.skill_cooldowns.clear()
	var cases: Array = [
		[0, 50, "kensei_zhaojia", "0 印记 → 招架"],
		[1, 0, "kensei_sanduanzhan", "1 印记 → 决心"],
		[2, 9, "kensei_zhaojia", "2 印记、剑气 9 → 招架"],
		[2, 10, "kensei_huitian", "2 印记、剑气 10 → 回天"],
		[3, 19, "kensei_zhaojia", "3 印记、剑气 19 → 招架（不退到回天）"],
		[3, 20, "kensei_batian", "3 印记、剑气 20 → 霸天"],
	]
	for c: Array in cases:
		_set_marks(ks, int(c[0]))
		ks.set_sword_qi(int(c[1]))
		_eq(str(c[3]), _zhaojia_slot(tm).get("skill_id"), str(c[2]))
	# R3.6：对应形态冷却中时，招架保持可用；其他形态的冷却互不影响。
	ks.skill_cooldowns["kensei_batian"] = 2
	_eq("霸天冷却中 → 招架", _zhaojia_slot(tm).get("skill_id"), "kensei_zhaojia")
	_set_marks(ks, 2)
	ks.set_sword_qi(10)
	_eq("霸天冷却不影响回天", _zhaojia_slot(tm).get("skill_id"), "kensei_huitian")
	ks.skill_cooldowns.clear()
	_leave_action_phase(tm)


# ── ④ 决心 ───────────────────────────────────────────

func _test_juexin(tm: Node, ks: Unit) -> void:
	print("\n[④] 决心")
	_enter_action_phase(tm, ks)
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	_set_marks(ks, 1)
	ks.set_sword_qi(0)
	_eq("决心可用", tm._build_skill_entry(ks, "kensei_sanduanzhan").get("available"), true)
	_cast(tm, ks, "kensei_sanduanzhan", ks.grid_position, ks)
	_eq("消耗 1 印记", ks.get_mark_count(), 0)
	_eq("得 15 剑气", ks.sword_qi, 15)
	_check("自由动作：不消耗任何行动资源",
		not ks.standard_used and not ks.swift_used and not ks.movement_used)
	_eq("进入冷却 2", ks.get_skill_cooldown("kensei_sanduanzhan"), 2)

	# 回合流程：标准动作和迅捷动作都用完、只剩决心时，不自动结束回合，进入迅捷阶段。
	ks.skill_cooldowns.clear()
	_set_marks(ks, 1)
	ks.standard_used = true
	ks.swift_used = true
	tm.battle_active = true
	tm.input_state = 2  # ACTION_PHASE
	_check("只剩决心时仍有可用的非标准技能", tm._has_available_swift_skill(ks))
	tm._resolve_post_action_phase()
	_eq("标准动作后只剩决心：进入迅捷阶段而不是结束回合", tm.input_state, 5)  # SWIFT_PHASE
	_eq("回合没有结束", tm.turn_manager.current_unit, ks)
	# 移动阶段用决心：用完回到移动阶段。
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	tm.input_state = 1  # MOVE_PHASE
	tm.selected_unit = ks
	var act: Object = _build_action(tm, ks, "kensei_sanduanzhan")
	_check("决心动作可构建", act != null)
	if act != null:
		tm._handle_post_skill_execution(1, act)
	_eq("移动阶段使用决心后仍在移动阶段", tm.input_state, 1)
	_leave_action_phase(tm)


# ── ⑤ 回天 ───────────────────────────────────────────

func _test_huitian(tm: Node, ks: Unit, enemies: Dictionary) -> void:
	print("\n[⑤] 回天")
	_enter_action_phase(tm, ks)
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.shield = 0
	_set_marks(ks, 2)
	ks.set_sword_qi(10)
	_eq("周围 2 名敌人时可用", tm._build_skill_entry(ks, "kensei_huitian").get("available"), true)
	var expected: int = ceili(float(ks.stats.max_hp) * 5.0 / 100.0 * 2.0)
	_cast(tm, ks, "kensei_huitian", ks.grid_position, ks)
	_eq("护盾 = ceil(最大生命 × 5% × 2)", ks.shield, expected)
	_check("前提：护盾大于 0", ks.shield > 0)
	_eq("消耗 2 印记", ks.get_mark_count(), 0)
	_eq("消耗 10 剑气", ks.sword_qi, 0)
	_check("消耗迅捷行动", ks.swift_used)
	_eq("进入冷却 4", ks.get_skill_cooldown("kensei_huitian"), 4)
	# 与现有护盾相加。
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	_set_marks(ks, 2)
	ks.set_sword_qi(10)
	_cast(tm, ks, "kensei_huitian", ks.grid_position, ks)
	_eq("再用一次：护盾相加", ks.shield, expected * 2)

	# 周围没有敌人：不可用，执行也被拒绝且不扣消耗。
	var grid: Object = tm.grid
	var home: Vector2i = ks.grid_position
	var far: Vector2i = Vector2i(7, 0)
	grid.move_unit(ks, home, far)
	ks.grid_position = far
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	_set_marks(ks, 2)
	ks.set_sword_qi(10)
	var entry: Dictionary = tm._build_skill_entry(ks, "kensei_huitian")
	_eq("周围没有敌人 → 不可用", entry.get("available"), false)
	tm.current_unit = ks
	tm._selected_skill_id = "kensei_huitian"
	var act: Object = tm._build_skill_action(ks, ks.grid_position, ks)
	tm._selected_skill_id = ""
	_check("空场的回天动作可构建（拒绝发生在执行时）", act != null)
	if act != null:
		_eq("周围没有敌人时执行被拒绝", bool(tm._execute_skill_action(act)), false)
	_eq("被拒绝时不扣印记", ks.get_mark_count(), 2)
	_eq("被拒绝时不扣剑气", ks.sword_qi, 10)
	grid.move_unit(ks, far, home)
	ks.grid_position = home
	_leave_action_phase(tm)


# ── ⑥ 护盾 ───────────────────────────────────────────

func _test_shield(tm: Node, ks: Unit) -> void:
	print("\n[⑥] 护盾（R1.17）")
	ks.stats.hp = ks.stats.max_hp
	ks.shield = 5
	ks.take_damage(3, "physical")
	_eq("伤害先扣护盾：护盾 5 → 2", ks.shield, 2)
	_eq("护盾挡住时生命不变", ks.stats.hp, ks.stats.max_hp)
	ks.take_damage(4, "physical")
	_eq("超出的部分扣生命：护盾 0", ks.shield, 0)
	_eq("超出的 2 点扣生命", ks.stats.hp, ks.stats.max_hp - 2)
	ks.stats.hp = ks.stats.max_hp

	# 衰减：衰减量 = ceil(护盾 × 50% × 100 ÷ (100 + 魔抗))，衰减后最多留 58%。
	var res: int = ks.get_effective_stat("RES")
	var base_res: int = ks.stats.res
	ks.shield = 100
	var decay_100: int = ceili(100.0 * 0.5 * 100.0 / (100.0 + float(res)))
	var expected_100: int = mini(100 - decay_100, 58)
	ks.decay_shield()
	_eq("护盾 100 衰减后（魔抗 %d）" % res, ks.shield, expected_100)
	# 魔抗很高时衰减量很小，58% 上限生效。
	ks.stats.res = 400
	ks.shield = 100
	ks.decay_shield()
	_eq("魔抗 400：衰减量只有 10，但最多留 58", ks.shield, 58)
	# 58% 上限按向下取整：护盾 3、魔抗 400 → 衰减量 ceil(0.3)=1 → 剩 2；上限 floor(1.74)=1 → 1。
	# 若按四舍五入取上限会剩 2。
	ks.shield = 3
	ks.decay_shield()
	_eq("58% 上限向下取整：护盾 3 → 1", ks.shield, 1)
	ks.stats.res = base_res
	ks.shield = 0
	_eq("没有护盾时衰减为 0", ks.decay_shield(), 0)

	# 自身回合开始时衰减。
	ks.shield = 10
	var expected_10: int = mini(10 - ceili(10.0 * 0.5 * 100.0 / (100.0 + float(res))), 5)
	tm.battle_active = true
	tm.turn_manager.current_unit = ks
	tm._on_turn_started(ks)
	_eq("自身回合开始时护盾衰减", ks.shield, expected_10)
	ks.shield = 0
	_leave_action_phase(tm)


# ── ⑦ 霸天 ───────────────────────────────────────────

func _test_batian(tm: Node, ks: Unit, enemies: Dictionary) -> void:
	print("\n[⑦] 霸天")
	_enter_action_phase(tm, ks)
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	_set_marks(ks, 3)
	ks.set_sword_qi(20)
	var e1: Unit = enemies[Vector2i(6, 5)]
	var e2: Unit = enemies[Vector2i(5, 6)]
	var two: Dictionary = _payload(tm, ks, "kensei_batian")
	_eq("范围内 2 名敌人：威力 +1、系数 1.5", [float(two.get("skill_power", -1)),
		float(two.get("skill_multiplier", -1))], [1.0, 1.5])
	# 把一名敌人移出范围：只剩 1 名。
	var grid: Object = tm.grid
	grid.move_unit(e2, Vector2i(5, 6), Vector2i(5, 7))
	e2.grid_position = Vector2i(5, 7)
	var one: Dictionary = _payload(tm, ks, "kensei_batian")
	_eq("范围内只有 1 名敌人：威力 +4、系数 1.6", [float(one.get("skill_power", -1)),
		float(one.get("skill_multiplier", -1))], [4.0, 1.6])
	grid.move_unit(e2, Vector2i(5, 7), Vector2i(5, 6))
	e2.grid_position = Vector2i(5, 6)

	var hp1: int = e1.stats.hp
	var hp2: int = e2.stats.hp
	_cast(tm, ks, "kensei_batian", ks.grid_position, ks)
	_check("范围内第 1 名敌人受到伤害", e1.stats.hp < hp1)
	_check("范围内第 2 名敌人受到伤害", e2.stats.hp < hp2)
	_eq("消耗 3 印记", ks.get_mark_count(), 0)
	_eq("消耗 20 剑气", ks.sword_qi, 0)
	_check("消耗标准行动", ks.standard_used)
	_leave_action_phase(tm)


# ── 工具 ─────────────────────────────────────────────

func _zhaojia_slot(tm: Node) -> Dictionary:
	for entry: Dictionary in tm._get_skill_entries():
		if str(entry.get("slot_origin_id", "")) == "kensei_zhaojia":
			return entry
	return {}


func _set_marks(ks: Unit, count: int) -> void:
	var keys: Array[String] = ["心", "道", "势"]
	ks.clear_marks()
	for i: int in range(count):
		ks.marks[keys[i]] = true


func _build_action(tm: Node, ks: Unit, skill_id: String) -> Object:
	tm.current_unit = ks
	tm._selected_skill_id = skill_id
	var act: Object = tm._build_skill_action(ks, ks.grid_position, ks)
	tm._selected_skill_id = ""
	return act


func _payload(tm: Node, ks: Unit, skill_id: String) -> Dictionary:
	tm.current_unit = ks
	tm._selected_skill_id = skill_id
	var act: Object = tm._build_skill_action(ks, ks.grid_position, ks)
	tm._selected_skill_id = ""
	return act.data if act != null else {}


func _hostile_context(tm: Node, ks: Unit, skill_id: String, pos: Vector2i, target: Unit) -> Dictionary:
	tm.current_unit = ks
	tm._selected_skill_id = skill_id
	var act: Object = tm._build_skill_action(ks, pos, target)
	tm._selected_skill_id = ""
	if act == null:
		return {}
	return tm._build_hostile_action_context(ks, target, act.data)


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
