extends SceneTree
## 剑圣基础组（gameplay-impl PR4：D1 剑圣半边、D2、D4、D6、D7、M3、M5、M7、M8、M9/R3.6、S2 剑圣线）。
##
## 依据：设计库 762393b 的 kensei_zhanji / yishan / zhaojia / juhe / xinyan / badao；
## R1.2（其他闪避加减）、R1.8（先固定点数后百分比、最后向下取整）、R1.11、R3.4、R3.6。
## 覆盖：
##   ① 数据：技能栏换成 kensei_*、伤害只读 damage_entries、拔刀以自身为中心。
##   ② S2：剑圣没有普通攻击。
##   ③ 心眼：暴击与速度新口径；印记各提升 10%，按 R1.8 合并后向下取整。
##   ④ 招架：额外闪避 = 当前技巧，随技巧即时变化；必定命中不受影响；到下个自身回合开始结束。
##   ⑤ 同槽（R3.6）：3 印记且剑气 ≥ 20 → 拔刀；条件不成立立即恢复；拔刀冷却中保持招架。
##   ⑥ 拔刀：周围没有敌人不可用且不扣消耗；对范围内每名敌人结算、不伤自己；印记结算后才扣。
##   ⑦ 斩击：命中得 25 剑气，造成伤害后得印记（伤害为 0 不得）；居合：结算后得印记。
##
## 运行：
##   <Godot_console.exe> --headless --path <worktree> --script res://tests/test_kensei_base.gd

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []


func _initialize() -> void:
	print("=== test_kensei_base (剑圣基础组) ===")
	_run.call_deferred()


func _run() -> void:
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	scene.run_injected = true
	scene.injected_map_id = "test_arena"
	scene.injected_player_units = [{"class_id": "kensei", "pos": Vector2i(3, 3)}]
	scene.injected_enemy_units = [
		{"class_id": "test_lancer", "pos": Vector2i(4, 3)},
		{"class_id": "test_lancer", "pos": Vector2i(3, 4)},
	]
	scene.debug_harness_enabled = false
	root.add_child(scene)
	await process_frame
	await process_frame

	var tm: Node = scene.get_node("TacticalManager")
	_check("tactical_manager 脚本已挂载", tm.get_script() != null)
	_eq("tactical_manager 挂的是 tactical_manager.gd",
		(tm.get_script() as Script).resource_path, "res://scripts/core/tactical_manager.gd")
	var ks: Unit = null
	var enemies: Array[Unit] = []
	for u: Variant in tm.units:
		if u is Unit and (u as Unit).unit_id == "kensei":
			ks = u
		elif u is Unit and (u as Unit).faction == "enemy":
			enemies.append(u)
	if ks == null or enemies.size() < 2:
		_check("场景含剑圣与两名敌人", false)
		_finish(scene)
		return
	_check("剑圣单位脚本已挂载", ks.get_script() != null
		and (ks.get_script() as Script).resource_path == "res://scripts/units/unit.gd")
	if tm.turn_manager != null:
		tm.turn_manager.stop()
	for e: Unit in enemies:
		e.stats.max_hp = 999
		e.stats.hp = 999

	_test_data()
	_test_no_basic_attack(tm, ks)
	_test_xinyan(tm, ks)
	_test_zhaojia(tm, ks, enemies[0])
	_test_slot_swap(tm, ks)
	_test_badao(tm, ks, enemies)
	_test_marks_timing(tm, ks, enemies[0])
	_finish(scene)


# ── ① 数据 ───────────────────────────────────────────

func _test_data() -> void:
	print("\n[①] 数据")
	var dl: Node = root.get_node("/root/DataLoader")
	var cls: Dictionary = dl.classes.get("kensei", {})
	_eq("剑圣技能栏", cls.get("skill_ids"),
		["kensei_zhanji", "kensei_yishan", "kensei_zhaojia", "kensei_juhe", "kensei_badao"])
	_eq("剑圣没有普通攻击", cls.get("basic_attack"), false)
	_check("去掉普攻得气字段", not cls.has("basic_attack_qi_gain"))
	_eq("心眼被动 id", cls.get("passive_skill_id"), "kensei_xinyan")
	var cfg: Dictionary = cls.get("sword_qi_config", {})
	_eq("心眼暴击：每 20 点剑气 +1",
		[int(cfg.get("qi_per_crit_pct", 0)), int(cfg.get("crit_per_qi", 0))], [20, 1])
	_eq("心眼速度：每少 40 点 +1",
		[int(cfg.get("qi_deficit_per_step", 0)), cfg.get("deficit_stat_key"),
			int(cfg.get("deficit_stat_bonus", 0))], [40, "SPD", 1])
	_eq("印记提升各 10%",
		[int(cfg.get("mark_dex_pct", 0)), int(cfg.get("mark_spd_pct", 0)), int(cfg.get("mark_str_pct", 0))],
		[10, 10, 10])
	_eq("印记不再给固定点数",
		[int(cfg.get("mark_dex_bonus", -1)), int(cfg.get("mark_spd_bonus", -1)), int(cfg.get("mark_str_bonus", -1))],
		[0, 0, 0])

	var expect: Dictionary = {
		"kensei_zhanji": [1, 1.0, "正常", 1.0, 0],
		"kensei_yishan": [1, 0.5, "正常", 1.0, 3],
		"kensei_juhe": [8, 1.6, "必定命中", 1.0, 0],
		"kensei_badao": [1, 1.5, "正常", 1.2, 0],
	}
	for sid: String in expect.keys():
		var sk: Dictionary = dl.skills.get(sid, {})
		_check(sid + " 已装载", not sk.is_empty())
		var entries: Array = sk.get("damage_entries", [])
		_eq(sid + " 一条伤害条目", entries.size(), 1)
		var want: Array = expect[sid]
		if entries.size() == 1:
			var e: Dictionary = entries[0]
			_eq(sid + " 威力", float(e.get("power", -1)), float(want[0]))
			_eq(sid + " 系数", float(e.get("coefficient", -1)), float(want[1]))
			_eq(sid + " 命中方式", e.get("hit_mode"), want[2])
			_eq(sid + " 暴击倍率", float(e.get("crit_multiplier", -1)), float(want[3]))
			_eq(sid + " 暴击方式正常", e.get("crit_mode"), "正常")
		_eq(sid + " 冷却", int(sk.get("cooldown", -1)), int(want[4]))
		_check(sid + " 不写 power", not sk.has("power"))
	var badao: Dictionary = dl.skills.get("kensei_badao", {})
	_eq("拔刀以自身为目标", badao.get("target_mode"), "自身")
	var area: Dictionary = badao.get("area", {})
	_eq("拔刀范围自身菱形 1 格", [area.get("type"), int(area.get("size", -1))], ["diamond", 1])
	_eq("拔刀消耗 3 印记 + 20 剑气",
		[int(badao.get("mark_cost", 0)), int(badao.get("requires_marks", 0)), int(badao.get("qi_cost", 0))], [3, 3, 20])
	_check("拔刀去掉溅射衰减与命中加成",
		not badao.has("splash_damage_pct") and int(badao.get("hit_bonus", 0)) == 0)
	_check("拔刀要求范围内有敌人", bool(badao.get("requires_enemy_in_area", false)))
	var juhe: Dictionary = dl.skills.get("kensei_juhe", {})
	_eq("居合消耗 60 剑气、结算后得 1 印记",
		[int(juhe.get("qi_cost", 0)), int(juhe.get("mark_gain_after_resolve", 0)), int(juhe.get("mark_gain", 0))], [60, 1, 0])
	_eq("一闪不耗剑气", int(dl.skills.get("kensei_yishan", {}).get("qi_cost", -1)), 0)
	var zj: Dictionary = dl.skills.get("kensei_zhaojia", {})
	_eq("招架冷却 2、迅捷、不耗剑气",
		[int(zj.get("cooldown", -1)), zj.get("action_cost"), int(zj.get("qi_cost", -1))], [2, "swift", 0])
	var req: Dictionary = zj.get("slot_swap_requires", {})
	_eq("招架替换门槛（JSON 数字按整数比）",
		[int(req.get("marks", -1)), int(req.get("qi", -1))], [3, 20])


# ── ② S2 ─────────────────────────────────────────────

func _test_no_basic_attack(tm: Node, ks: Unit) -> void:
	print("\n[②] 剑圣没有普通攻击")
	ks.reset_action_resources()
	_check("has_basic_attack = false", not ks.has_basic_attack)
	_eq("普攻判定拒绝", GameAction.can_use_normal_attack(ks).get("ok"), false)
	tm.current_unit = ks
	tm.input_state = 2
	_eq("攻击按钮提示", tm._get_attack_button_reason(), "该职业没有普通攻击")
	tm.current_unit = null


# ── ③ 心眼 ───────────────────────────────────────────

func _test_xinyan(tm: Node, ks: Unit) -> void:
	print("\n[③] 心眼与印记")
	ks.clear_marks()
	var spd_base: int = ks.stats.spd
	for c: Array in [[0, 0, 2], [20, 1, 2], [21, 1, 1], [60, 3, 1], [61, 3, 0], [100, 5, 0]]:
		ks.set_sword_qi(int(c[0]))
		_eq("剑气 %d：暴击 +%d" % [c[0], c[1]], ks.crit_bonus, int(c[1]))
		_eq("剑气 %d：速度 +%d" % [c[0], c[2]], ks.get_effective_stat("SPD") - spd_base, int(c[2]))

	# 印记提升 10%（R1.8：先固定点数后百分比，最后向下取整）。剑气 100 → 心眼不给速度。
	ks.set_sword_qi(100)
	ks.stats.dex = 10
	ks.stats.spd = 9
	ks.stats.str_attr = 25
	ks.marks = {"心": true, "道": false, "势": false}
	_eq("〔心〕技巧 10 → 11", ks.get_effective_stat("DEX"), 11)
	ks.marks = {"心": false, "道": true, "势": false}
	_eq("〔道〕速度 9 → 9.9 向下取整 9", ks.get_effective_stat("SPD"), 9)
	ks.set_sword_qi(0)
	_eq("〔道〕+ 心眼速度 +2：(9 + 2) × 1.1 = 12.1 → 12（固定点数先加）", ks.get_effective_stat("SPD"), 12)
	ks.marks = {"心": false, "道": false, "势": true}
	_eq("〔势〕力量 25 → 27.5 向下取整 27", ks.get_effective_stat("STR"), 27)
	ks.marks = {"心": false, "道": false, "势": false}
	_eq("无印记时力量不变", ks.get_effective_stat("STR"), 25)
	var entry: Dictionary = tm._build_passive_entry(ks)
	_eq("被动条目 id", entry.get("skill_id"), "kensei_xinyan")
	_check("被动说明写印记百分比", str(entry.get("description", "")).contains("+10%"),
		str(entry.get("description", "")))
	ks.clear_marks()
	ks.set_sword_qi(0)


# ── ④ 招架 ───────────────────────────────────────────

func _test_zhaojia(tm: Node, ks: Unit, enemy: Unit) -> void:
	print("\n[④] 招架：额外闪避 = 当前技巧")
	ks.held_states.clear()
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.clear_marks()
	ks.set_sword_qi(0)
	ks.stats.dex = 12
	var avoid0: int = ks.get_avoid_value(0)
	_cast(tm, ks, "kensei_zhaojia", ks.grid_position, ks)
	_check("施放后持有招架状态", ks.held_states.has("kensei_zhaojia"))
	_check("消耗迅捷、不消耗标准", ks.swift_used and not ks.standard_used)
	_eq("额外闪避 +技巧 12", ks.get_avoid_value(0) - avoid0, 12)
	ks.stats.dex = 20
	_eq("技巧变为 20 → 额外闪避即时变为 +20", ks.get_avoid_value(0) - avoid0, 20)
	# 必定命中不受影响：闪避再高也命中。
	ks.stats.dex = 200
	var forced: Dictionary = DamageCalculator.roll_outcome(enemy, ks, {"guaranteed_hit": true})
	_eq("必定命中的攻击照样命中", bool(forced.get("hit", false)), true)
	ks.stats.dex = 12
	tm.battle_active = true
	tm._on_turn_ended(ks)
	_check("施放回合结束后仍持有", ks.held_states.has("kensei_zhaojia"))
	tm.turn_manager.current_unit = ks
	tm._on_turn_started(ks)
	tm.battle_active = false
	tm.turn_manager.current_unit = null
	_check("下个自身回合开始时结束", not ks.held_states.has("kensei_zhaojia"))
	_eq("结束后闪避回到原值", ks.get_avoid_value(0), avoid0)


# ── ⑤ 同槽 R3.6 ──────────────────────────────────────

func _test_slot_swap(tm: Node, ks: Unit) -> void:
	print("\n[⑤] 招架 ⇄ 拔刀（R3.6）")
	var dl: Node = root.get_node("/root/DataLoader")
	var zj: Dictionary = dl.skills["kensei_zhaojia"]
	var trig: String = str(zj.get("slot_swap_trigger", ""))
	var tgt: String = str(zj.get("slot_swap_target", ""))
	var req: Dictionary = zj.get("slot_swap_requires", {})
	ks.skill_cooldowns.clear()
	ks.marks = {"心": true, "道": true, "势": true}
	ks.set_sword_qi(19)
	_eq("3 印记、剑气 19 → 仍是招架", ks.get_visible_skill_id("kensei_zhaojia", trig, tgt, req), "kensei_zhaojia")
	ks.set_sword_qi(20)
	_eq("3 印记、剑气 20 → 拔刀", ks.get_visible_skill_id("kensei_zhaojia", trig, tgt, req), "kensei_badao")
	ks.marks = {"心": true, "道": true, "势": false}
	_eq("2 印记、剑气 20 → 立即恢复招架", ks.get_visible_skill_id("kensei_zhaojia", trig, tgt, req), "kensei_zhaojia")
	ks.marks = {"心": true, "道": true, "势": true}
	ks.consume_skill("kensei_badao", 2)
	_eq("拔刀冷却中 → 保持招架（R3.6）", ks.get_visible_skill_id("kensei_zhaojia", trig, tgt, req), "kensei_zhaojia")
	ks.skill_cooldowns.clear()
	_eq("拔刀冷却结束且条件仍成立 → 立即替换", ks.get_visible_skill_id("kensei_zhaojia", trig, tgt, req), "kensei_badao")
	_eq("缺门槛声明时不替换", ks.get_visible_skill_id("kensei_zhaojia", trig, tgt, {}), "kensei_zhaojia")

	# 技能栏：拔刀不单独占槽，出现在招架槽里。技能栏按「剑圣回合的行动阶段」构建。
	_enter_action_phase(tm, ks)
	var ids: Array[String] = []
	for e: Dictionary in tm._get_skill_entries():
		ids.append(str(e.get("skill_id", "")))
	_check("技能栏招架槽显示拔刀", ids.has("kensei_badao") and not ids.has("kensei_zhaojia"), str(ids))
	_eq("技能栏一共 5 项（心眼 + 4 槽；拔刀不单独占槽）", ids.size(), 5)
	ks.clear_marks()
	ks.set_sword_qi(0)
	_leave_action_phase(tm)


# ── ⑥ 拔刀 ───────────────────────────────────────────

func _test_badao(tm: Node, ks: Unit, enemies: Array[Unit]) -> void:
	print("\n[⑥] 拔刀")
	var grid: Object = tm.grid
	var home: Vector2i = ks.grid_position
	# 先移到周围没有敌人的格子。
	var away: Vector2i = Vector2i(0, 0)
	grid.move_unit(ks, home, away)
	ks.grid_position = away
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.marks = {"心": true, "道": true, "势": true}
	ks.set_sword_qi(50)
	_enter_action_phase(tm, ks)
	var entry_far: Dictionary = tm._build_skill_entry(ks, "kensei_badao")
	_eq("周围没有敌人 → 不可用", entry_far.get("available"), false)
	_eq("不可用原因", entry_far.get("reason"), "范围内没有敌人")
	tm.current_unit = ks
	tm._selected_skill_id = "kensei_badao"
	var empty_act: Object = tm._build_skill_action(ks, ks.grid_position, ks)
	if empty_act != null:
		_eq("周围没有敌人时执行被拒绝", bool(tm._execute_skill_action(empty_act)), false)
	_eq("被拒绝时不扣剑气", ks.sword_qi, 50)
	_eq("被拒绝时不扣印记", ks.get_mark_count(), 3)
	_check("被拒绝时不消耗标准行动", not ks.standard_used)
	tm._selected_skill_id = ""

	# 回到两名敌人相邻的格子。
	grid.move_unit(ks, away, home)
	ks.grid_position = home
	ks.stats.dex = 60
	for e: Unit in enemies:
		e.stats.spd = 0
		e.stats.hp = 999
	var hp_self: int = ks.stats.hp
	_eq("周围有敌人 → 可用", tm._build_skill_entry(ks, "kensei_badao").get("available"), true)
	_cast(tm, ks, "kensei_badao", ks.grid_position, ks)
	for i: int in range(enemies.size()):
		_check("范围内第 %d 名敌人受到伤害" % (i + 1), enemies[i].stats.hp < 999,
			"hp=%d" % enemies[i].stats.hp)
	_eq("不伤自己", ks.stats.hp, hp_self)
	_eq("消耗 20 剑气：50 → 30", ks.sword_qi, 30)
	_eq("消耗 3 印记", ks.get_mark_count(), 0)
	_check("消耗标准行动", ks.standard_used)
	_leave_action_phase(tm)


# ── ⑦ 印记时机 ───────────────────────────────────────

func _test_marks_timing(tm: Node, ks: Unit, enemy: Unit) -> void:
	print("\n[⑦] 斩击与居合的印记时机")
	ks.stats.dex = 60
	enemy.stats.spd = 0
	enemy.stats.def_attr = 0
	enemy.stats.hp = 999
	ks.clear_marks()
	ks.set_sword_qi(0)
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	_cast(tm, ks, "kensei_zhanji", enemy.grid_position, enemy)
	_check("斩击命中造成伤害", enemy.stats.hp < 999)
	_eq("斩击命中得 25 剑气", ks.sword_qi, 25)
	_eq("斩击造成伤害后得 1 枚印记", ks.get_mark_count(), 1)

	# 命中但伤害为 0：剑气照得，印记不得。
	enemy.stats.def_attr = 999
	ks.clear_marks()
	ks.set_sword_qi(0)
	ks.reset_action_resources()
	var hp_before: int = enemy.stats.hp
	_cast(tm, ks, "kensei_zhanji", enemy.grid_position, enemy)
	_eq("前提：本次伤害为 0", enemy.stats.hp, hp_before)
	_eq("伤害为 0 仍在命中时得剑气", ks.sword_qi, 25)
	_eq("伤害为 0 不得印记", ks.get_mark_count(), 0)
	enemy.stats.def_attr = 0

	# 居合：必定命中、消耗 60、结算后得印记。
	ks.clear_marks()
	ks.set_sword_qi(70)
	ks.reset_action_resources()
	ks.stats.dex = 0
	enemy.stats.spd = 200
	hp_before = enemy.stats.hp
	_cast(tm, ks, "kensei_juhe", enemy.grid_position, enemy)
	_check("居合必定命中（闪避再高也命中）", enemy.stats.hp < hp_before)
	_eq("居合消耗 60 剑气：70 → 10", ks.sword_qi, 10)
	_eq("居合结算后得 1 枚印记", ks.get_mark_count(), 1)


## 让战术管理器处于「剑圣回合的行动阶段」：技能栏与条目可用性都按当前操作单位和阶段判定。
func _enter_action_phase(tm: Node, u: Unit) -> void:
	tm.current_unit = u
	tm.selected_unit = u
	tm.turn_manager.current_unit = u
	tm.input_state = 2  # ACTION_PHASE


func _leave_action_phase(tm: Node) -> void:
	tm.turn_manager.current_unit = null
	tm.current_unit = null
	tm.input_state = 0


## 走真实施放路径：构建 → 执行。
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
