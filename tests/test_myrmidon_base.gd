extends SceneTree
## 剑士基础组（gameplay-impl PR3：D1 剑士半边、D2–D5、D7、D8、M5 剑士招架、M8 剑士心眼、S2 剑士线）。
##
## 依据：设计库 762393b 的 myrmidon_zhanji / yishan / zhaojia / juhe / xinyan；R1.1、R1.7、R3.4。
## 覆盖：
##   ① 数据：职业技能栏换成 myrmidon_*、伤害只读 damage_entries、数值与设计库一致。
##   ② S2：剑士没有普通攻击（三条入口共用的判定）、敌人仍有。
##   ③ 心眼：每 20 剑气暴击 +1；剑气每比 100 少 40 点速度 +1；不再有技巧分档。
##   ④ 招架：迅捷施放 → 防御与魔防 +(1 + 剑气÷25)，随剑气即时变化；到下个自身回合开始结束。
##   ⑤ 居合 / 斩击 / 一闪 走真实施放路径：消耗与得气、必定命中、无印记。
##
## 运行：
##   <Godot_console.exe> --headless --path <worktree> --script res://tests/test_myrmidon_base.gd

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []


func _initialize() -> void:
	print("=== test_myrmidon_base (剑士基础组) ===")
	_run.call_deferred()


func _run() -> void:
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	scene.run_injected = true
	scene.injected_map_id = "test_arena"
	scene.injected_player_units = [{"class_id": "myrmidon", "pos": Vector2i(1, 2)}]
	scene.injected_enemy_units = [{"class_id": "test_lancer", "pos": Vector2i(2, 2)}]
	scene.debug_harness_enabled = false
	root.add_child(scene)
	await process_frame
	await process_frame

	var tm: Node = scene.get_node("TacticalManager")
	_check("tactical_manager 脚本已挂载", tm.get_script() != null)
	_eq("tactical_manager 挂的是 tactical_manager.gd",
		(tm.get_script() as Script).resource_path, "res://scripts/core/tactical_manager.gd")
	var sword: Unit = null
	var enemy: Unit = null
	for u: Variant in tm.units:
		if u is Unit and (u as Unit).unit_id == "myrmidon":
			sword = u
		elif u is Unit and (u as Unit).faction == "enemy":
			enemy = u
	if sword == null or enemy == null:
		_check("场景含剑士与敌人", false)
		_finish(scene)
		return
	_check("剑士单位脚本已挂载", sword.get_script() != null
		and (sword.get_script() as Script).resource_path == "res://scripts/units/unit.gd")
	if tm.turn_manager != null:
		tm.turn_manager.stop()

	_test_data()
	_test_no_basic_attack(tm, sword, enemy)
	_test_xinyan(tm, sword)
	_test_zhaojia(tm, sword)
	_test_attacks(tm, sword, enemy)
	_finish(scene)


# ── ① 数据 ───────────────────────────────────────────

func _test_data() -> void:
	print("\n[①] 数据")
	var dl: Node = root.get_node("/root/DataLoader")
	var cls: Dictionary = dl.classes.get("myrmidon", {})
	_eq("剑士技能栏", cls.get("skill_ids"),
		["myrmidon_zhanji", "myrmidon_yishan", "myrmidon_zhaojia", "myrmidon_juhe"])
	_eq("剑士没有普通攻击", cls.get("basic_attack"), false)
	_check("去掉普攻得气字段", not cls.has("basic_attack_qi_gain"))
	_eq("心眼被动 id", cls.get("passive_skill_id"), "myrmidon_xinyan")
	var cfg: Dictionary = cls.get("sword_qi_config", {})
	# JSON 数字读进来是 float，按整数比较。
	_eq("心眼暴击：每 20 点剑气 +1",
		[int(cfg.get("qi_per_crit_pct", 0)), int(cfg.get("crit_per_qi", 0))], [20, 1])
	_eq("心眼速度：每少 40 点 +1",
		[int(cfg.get("qi_deficit_per_step", 0)), cfg.get("deficit_stat_key"),
			int(cfg.get("deficit_stat_bonus", 0))], [40, "SPD", 1])

	# 与设计库 762393b 的伤害条目逐项对照（关键数值抄错会直接改变战斗）。
	var expect: Dictionary = {
		"myrmidon_zhanji": {"power": 1, "coefficient": 1.0, "hit_mode": "正常", "cd": 0},
		"myrmidon_yishan": {"power": 1, "coefficient": 0.5, "hit_mode": "正常", "cd": 3},
		"myrmidon_juhe": {"power": 8, "coefficient": 1.6, "hit_mode": "必定命中", "cd": 0},
	}
	for sid: String in expect.keys():
		var sk: Dictionary = dl.skills.get(sid, {})
		_check(sid + " 已装载", not sk.is_empty())
		var entries: Array = sk.get("damage_entries", [])
		_eq(sid + " 一条伤害条目", entries.size(), 1)
		if entries.size() == 1:
			var e: Dictionary = entries[0]
			var want: Dictionary = expect[sid]
			_eq(sid + " 威力", float(e.get("power", -1)), float(want["power"]))
			_eq(sid + " 系数", float(e.get("coefficient", -1)), float(want["coefficient"]))
			_eq(sid + " 命中方式", e.get("hit_mode"), want["hit_mode"])
			_eq(sid + " 暴击方式（正常，居合不再必定暴击）", e.get("crit_mode"), "正常")
		_eq(sid + " 冷却", int(sk.get("cooldown", -1)), int(expect[sid]["cd"]))
		_check(sid + " 不写 power（R1.7：不加武器威力的旧百分比）", not sk.has("power"))
		_eq(sid + " 不得印记（剑士没有印记）", int(sk.get("mark_gain", 0)), 0)
	var yishan: Dictionary = dl.skills.get("myrmidon_yishan", {})
	_eq("一闪不耗剑气", int(yishan.get("qi_cost", -1)), 0)
	_eq("一闪消耗移动机会", yishan.get("action_cost"), "move")
	var juhe: Dictionary = dl.skills.get("myrmidon_juhe", {})
	_eq("居合消耗 60 剑气", int(juhe.get("qi_cost", -1)), 60)
	_eq("居合击杀不返气", int(juhe.get("qi_gain_on_kill", -1)), 0)
	_check("居合击杀不减冷却", not juhe.has("ki_on_kill_cd_reduction"))
	var zhaojia: Dictionary = dl.skills.get("myrmidon_zhaojia", {})
	_eq("招架冷却 2", int(zhaojia.get("cooldown", -1)), 2)
	_eq("招架是迅捷", zhaojia.get("action_cost"), "swift")
	_eq("招架不耗剑气", int(zhaojia.get("qi_cost", -1)), 0)
	_check("招架不再挂旧的概率减伤 buff", str(zhaojia.get("effects", [])).find("swordsman_parry_stance") < 0)
	_check("剑士招架没有拔刀槽替换", not zhaojia.has("slot_swap_target"))
	_eq("斩击命中得 25 剑气", int(dl.skills.get("myrmidon_zhanji", {}).get("qi_gain_on_hit", -1)), 25)
	_check("剑圣仍用 swordsman_*（剑圣 PR 再改）",
		(dl.classes.get("kensei", {}).get("skill_ids", []) as Array).has("swordsman_zhanji"))


# ── ② S2 ─────────────────────────────────────────────

func _test_no_basic_attack(tm: Node, sword: Unit, enemy: Unit) -> void:
	print("\n[②] 剑士没有普通攻击")
	sword.reset_action_resources()
	_check("单位字段 has_basic_attack = false", not sword.has_basic_attack)
	var check: Dictionary = GameAction.can_use_normal_attack(sword)
	_eq("普攻判定拒绝（界面、点敌、执行三条入口共用）", check.get("ok"), false)
	_eq("拒绝原因", check.get("reason"), "No basic attack")
	tm.current_unit = sword
	tm.input_state = 2  # ACTION_PHASE
	_check("不能进入普攻瞄准", not tm._can_enter_attack_targeting())
	_eq("攻击按钮提示", tm._get_attack_button_reason(), "该职业没有普通攻击")
	_check("敌人仍有普通攻击", enemy.has_basic_attack
		and bool(GameAction.can_use_normal_attack(enemy).get("ok", false)))
	tm.current_unit = null


# ── ③ 心眼 ───────────────────────────────────────────

func _test_xinyan(tm: Node, u: Unit) -> void:
	print("\n[③] 心眼")
	var spd_base: int = u.stats.spd
	var dex_base: int = u.stats.dex
	var cases: Array = [[0, 0, 2], [19, 0, 2], [20, 1, 2], [21, 1, 1], [59, 2, 1], [60, 3, 1],
		[61, 3, 0], [99, 4, 0], [100, 5, 0]]
	for c: Array in cases:
		u.set_sword_qi(int(c[0]))
		_eq("剑气 %d：暴击 +%d" % [c[0], c[1]], u.crit_bonus, int(c[1]))
		_eq("剑气 %d：速度 +%d" % [c[0], c[2]], u.get_effective_stat("SPD") - spd_base, int(c[2]))
		_eq("剑气 %d：技巧不加" % c[0], u.get_effective_stat("DEX") - dex_base, 0)
	var entry: Dictionary = tm._build_passive_entry(u)
	_eq("被动条目 id", entry.get("skill_id"), "myrmidon_xinyan")
	_check("被动说明写新口径", str(entry.get("description", "")).contains("每比 100 点少 40 点"),
		str(entry.get("description", "")))
	_check("被动说明不提印记", not str(entry.get("description", "")).contains("印记"))
	u.set_sword_qi(0)


# ── ④ 招架 ───────────────────────────────────────────

func _test_zhaojia(tm: Node, u: Unit) -> void:
	print("\n[④] 招架")
	u.held_states.clear()
	u.reset_action_resources()
	u.skill_cooldowns.clear()
	u.set_sword_qi(0)
	var def0: int = u.get_effective_stat("DEF")
	var res0: int = u.get_effective_stat("RES")
	_cast(tm, u, "myrmidon_zhaojia", u.grid_position, u)
	_check("施放后持有招架状态", u.held_states.has("myrmidon_zhaojia"))
	_check("消耗迅捷行动", u.swift_used)
	_check("不消耗标准行动", not u.standard_used)
	_eq("进入冷却 2", u.get_skill_cooldown("myrmidon_zhaojia"), 2)
	_eq("剑气 0：防御 +1", u.get_effective_stat("DEF") - def0, 1)
	_eq("剑气 0：魔防 +1", u.get_effective_stat("RES") - res0, 1)
	for c: Array in [[24, 1], [25, 2], [50, 3], [99, 4], [100, 5]]:
		u.set_sword_qi(int(c[0]))
		_eq("剑气 %d：防御 +%d（即时变化）" % [c[0], c[1]],
			u.get_effective_stat("DEF") - def0, int(c[1]))
	_eq("剑气 100：魔防 +5", u.get_effective_stat("RES") - res0, 5)
	_eq("速度不受招架影响", u.held_states.params("myrmidon_zhaojia").get("qi_scaled_stat_bonus", {}).get("stats"),
		["DEF", "RES"])
	# 走真实回合钩子：施放所在回合结束 → 敌方回合期间仍在 → 下个自身回合开始时结束。
	tm.battle_active = true
	tm._on_turn_ended(u)
	_check("施放所在回合结束后仍持有（覆盖敌方回合）", u.held_states.has("myrmidon_zhaojia"))
	_eq("施放回合结束后防御仍 +5（直到下个自身回合开始）", u.get_effective_stat("DEF") - def0, 5)
	tm.turn_manager.current_unit = u
	tm._on_turn_started(u)
	tm.battle_active = false
	tm.turn_manager.current_unit = null
	_check("下个自身回合开始时结束", not u.held_states.has("myrmidon_zhaojia"))
	_eq("结束后防御回到原值", u.get_effective_stat("DEF") - def0, 0)
	u.set_sword_qi(0)


# ── ⑤ 攻击技能 ───────────────────────────────────────

func _test_attacks(tm: Node, u: Unit, enemy: Unit) -> void:
	print("\n[⑤] 攻击技能")
	enemy.stats.max_hp = 999
	enemy.stats.hp = 999

	# 斩击：伤害参数来自条目（技能威力 1，系数 1.0，不加武器威力）。
	tm._selected_skill_id = "myrmidon_zhanji"
	var act: Object = tm._build_skill_action(u, enemy.grid_position, enemy)
	_check("斩击动作可构建", act != null)
	if act != null:
		_eq("斩击 skill_power = 1", act.data.get("skill_power"), 1.0)
		_eq("斩击系数 1.0", act.data.get("skill_multiplier"), 1.0)
		_eq("斩击命中得气 25", int(act.data.get("qi_gain_on_hit", 0)), 25)
		_eq("斩击不得印记", int(act.data.get("mark_gain", 0)), 0)

	# 斩击实际施放：命中率拉满（技巧高、目标速度 0），命中后剑气 +25、没有印记。
	var dex_saved: int = u.stats.dex
	var spd_saved: int = enemy.stats.spd
	u.stats.dex = 60
	enemy.stats.spd = 0
	u.reset_action_resources()
	u.skill_cooldowns.clear()
	u.set_sword_qi(0)
	var zhanji_hp: int = enemy.stats.hp
	_cast(tm, u, "myrmidon_zhanji", enemy.grid_position, enemy)
	_check("斩击命中造成伤害", enemy.stats.hp < zhanji_hp)
	_eq("斩击命中后剑气 0 → 25", u.sword_qi, 25)
	_eq("斩击后仍没有印记", u.get_mark_count(), 0)
	_check("斩击消耗标准行动", u.standard_used)
	u.stats.dex = dex_saved
	enemy.stats.spd = spd_saved

	# 居合：消耗 60 剑气、必定命中、正常暴击（不再必定暴击）。
	u.reset_action_resources()
	u.skill_cooldowns.clear()
	u.set_sword_qi(70)
	tm._selected_skill_id = "myrmidon_juhe"
	var juhe: Object = tm._build_skill_action(u, enemy.grid_position, enemy)
	_check("居合动作可构建", juhe != null)
	if juhe != null:
		_eq("居合 skill_power = 8", juhe.data.get("skill_power"), 8.0)
		_eq("居合系数 1.6", juhe.data.get("skill_multiplier"), 1.6)
		_eq("居合必定命中", juhe.data.get("guaranteed_hit"), true)
		_eq("居合不必定暴击", juhe.data.get("guaranteed_crit", false), false)
	var hp_before: int = enemy.stats.hp
	_cast(tm, u, "myrmidon_juhe", enemy.grid_position, enemy)
	_eq("居合消耗 60 剑气：70 → 10", u.sword_qi, 10)
	_check("居合必定命中造成伤害", enemy.stats.hp < hp_before,
		"hp %d → %d" % [hp_before, enemy.stats.hp])
	_eq("居合冷却 0：可再次使用", u.get_skill_cooldown("myrmidon_juhe"), 0)
	_eq("剑士没有印记", u.get_mark_count(), 0)

	# 剑气不足 60 时不可施放。
	u.reset_action_resources()
	u.set_sword_qi(59)
	tm._selected_skill_id = "myrmidon_juhe"
	var juhe_data: Dictionary = tm._get_skill_data("myrmidon_juhe")
	_eq("剑气 59 时居合不可用", bool(GameAction.validate_skill_usage(u, juhe_data).get("ok", true)), false)

	# 一闪：不耗剑气。
	u.reset_action_resources()
	u.set_sword_qi(30)
	_eq("一闪可用（不需要剑气）",
		bool(GameAction.validate_skill_usage(u, tm._get_skill_data("myrmidon_yishan")).get("ok", false)), true)
	tm._selected_skill_id = "myrmidon_yishan"
	var dir_cell: Vector2i = u.grid_position + Vector2i(0, 1)
	var yishan: Object = tm._build_skill_action(u, dir_cell, null)
	if yishan != null:
		_eq("一闪 payload 不扣剑气", int(yishan.data.get("qi_cost", 0)), 0)
		_eq("一闪 skill_power = 1", yishan.data.get("skill_power"), 1.0)
		_eq("一闪系数 0.5", yishan.data.get("skill_multiplier"), 0.5)
	else:
		_check("一闪动作可构建", false)
	tm._selected_skill_id = ""


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
