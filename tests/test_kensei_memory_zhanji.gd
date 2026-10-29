extends SceneTree
## 回忆技能·斩击组（gameplay-impl PR6a，差距清单 M12、M13）：〔化剑为气〕→〔裂空〕、〔疾风骤雨〕→〔连斩〕。
##
## 依据：设计库 762393b 的 kensei_liekong / kensei_yijue；R1.9、R1.10、R1.11、R2.5。
## 覆盖：
##   ① 数据：两条技能镜像设计库，upgrade_of 指向斩击；脚本挂载。
##   ② 兑现：真实数据下两张回忆都能兑现，斩击原位换成升级技能，技能身份仍是斩击（R2.5）。
##   ③ 裂空：前方直线 3 格内没有敌人时不可用、执行被拒且不扣消耗；直线内每名敌人各结算一次，
##      直线外不受影响；每命中一名 +10 剑气，结算完再 +5；使用后得一枚印记；目标由近到远排序。
##   ④ 连斩：三段全中 → 每段 +10 剑气、只得一枚印记；目标倒下即停；后续段命中逐段降低 15 点，
##      其他效果给的必定命中只作用于第一段；未命中即停。
##
## 运行：
##   <Godot_console.exe> --headless --path <worktree> --script res://tests/test_kensei_memory_zhanji.gd

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []


func _initialize() -> void:
	print("=== test_kensei_memory_zhanji（回忆技能·斩击组）===")
	_run.call_deferred()


func _run() -> void:
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	scene.run_injected = true
	scene.injected_map_id = "test_arena"
	scene.injected_player_units = [
		{"class_id": "kensei", "pos": Vector2i(2, 3)},
		{"class_id": "kensei", "pos": Vector2i(2, 6)},
	]
	# 裂空的直线（向右）：(3,3) 距离 1、(5,3) 距离 3 在范围内，(6,3) 距离 4 在外；(2,4) 在下方。
	# 连斩：(3,6)、(1,6) 与第二名剑圣相邻。
	scene.injected_enemy_units = [
		{"class_id": "test_lancer", "pos": Vector2i(3, 3)},
		{"class_id": "test_lancer", "pos": Vector2i(5, 3)},
		{"class_id": "test_lancer", "pos": Vector2i(6, 3)},
		{"class_id": "test_lancer", "pos": Vector2i(2, 4)},
		{"class_id": "test_lancer", "pos": Vector2i(3, 6)},
		{"class_id": "test_lancer", "pos": Vector2i(1, 6)},
	]
	scene.debug_harness_enabled = false
	root.add_child(scene)
	await process_frame
	await process_frame

	var tm: Node = scene.get_node("TacticalManager")
	_check("tactical_manager 脚本已挂载", tm.get_script() != null)
	_eq("tactical_manager 挂的是 tactical_manager.gd",
		(tm.get_script() as Script).resource_path, "res://scripts/core/tactical_manager.gd")
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
	if swords.size() < 2 or enemies.size() < 6:
		_check("场景含两名剑圣与六名敌人", false)
		_finish(scene)
		return
	_check("剑圣单位脚本已挂载", swords[0].get_script() != null
		and (swords[0].get_script() as Script).resource_path == "res://scripts/units/unit.gd")
	for ks: Unit in swords:
		ks.stats.dex = 80  # 命中 ≥ 160，对 0 速度敌人三段都是 100%

	var dl: Node = root.get_node("/root/DataLoader")
	_test_data(dl)
	_test_apply(dl, swords)
	_test_liekong(tm, swords[0], enemies)
	_test_yijue(tm, swords[1], enemies)
	_test_segment_rules(tm, swords[1], enemies[Vector2i(3, 6)])
	_finish(scene)


# ── ① 数据 ───────────────────────────────────────────

func _test_data(dl: Node) -> void:
	print("\n[①] 数据")
	var liekong: Dictionary = dl.skills.get("kensei_liekong", {})
	var yijue: Dictionary = dl.skills.get("kensei_yijue", {})
	_check("裂空已装载", not liekong.is_empty())
	_check("连斩已装载", not yijue.is_empty())
	_eq("裂空 upgrade_of", str(liekong.get("upgrade_of", "")), "kensei_zhanji")
	_eq("连斩 upgrade_of", str(yijue.get("upgrade_of", "")), "kensei_zhanji")
	_eq("裂空名称", str(liekong.get("name", "")), "裂空")
	_eq("连斩名称", str(yijue.get("name", "")), "连斩")
	var le: Dictionary = (liekong.get("damage_entries", []) as Array)[0]
	_eq("裂空 威力 +1", int(le.get("power", 0)), 1)
	_eq("裂空 系数 0.9", float(le.get("coefficient", 0.0)), 0.9)
	_eq("裂空 目标方式 格子", str(liekong.get("target_mode", "")), "格子")
	_eq("裂空 射程 直线 1–1", [str(liekong.range.type), int(liekong.range.min), int(liekong.range.max)],
		["line", 1, 1])
	_eq("裂空 范围 直线（所选格后再 2 格，共 3 格）", [str(liekong.area.type), int(liekong.area.size)],
		["line", 2])
	_eq("裂空 冷却 0、标准", [int(liekong.cooldown), str(liekong.action_cost)], [0, "standard"])
	_eq("裂空 每命中 +10 剑气", int(liekong.get("qi_gain_on_hit", 0)), 10)
	_eq("裂空 结算后 +5 剑气", int(liekong.get("qi_gain_after_resolve", 0)), 5)
	_eq("裂空 使用后得一枚印记", int(liekong.get("mark_gain_after_resolve", 0)), 1)
	var ye: Dictionary = (yijue.get("damage_entries", []) as Array)[0]
	_eq("连斩 威力 +1、系数 0.4", [int(ye.get("power", 0)), float(ye.get("coefficient", 0.0))], [1, 0.4])
	_eq("连斩 最多 3 段、每段命中 −15", [int(ye.get("segments", 0)), int(ye.get("segment_hit_decay", 0))],
		[3, 15])
	_eq("连斩 射程 菱形 1–1", [str(yijue.range.type), int(yijue.range.min), int(yijue.range.max)],
		["diamond", 1, 1])
	_eq("连斩 冷却 0、标准", [int(yijue.cooldown), str(yijue.action_cost)], [0, "standard"])
	_eq("连斩 每段造成伤害 +10 剑气", int(yijue.get("qi_gain_after_damage", 0)), 10)
	_eq("连斩 命中时不另给剑气", int(yijue.get("qi_gain_on_hit", 0)), 0)
	_eq("连斩 第一段造成伤害后得印记", int(yijue.get("mark_gain_after_damage", 0)), 1)


# ── ② 兑现 ───────────────────────────────────────────

func _test_apply(dl: Node, swords: Array[Unit]) -> void:
	print("\n[②] 兑现（真实数据）")
	var pairs: Array = [
		[swords[0], "kensei_huajianweiqi", "kensei_liekong"],
		[swords[1], "kensei_yiguzuoqi", "kensei_yijue"],
	]
	for p: Array in pairs:
		var u: Unit = p[0]
		var index: int = u.skill_ids.find("kensei_zhanji")
		var r: Dictionary = u.apply_memory(str(p[1]), dl.memories, dl.skills)
		_check("%s 兑现成功" % p[1], bool(r.get("ok", false)), str(r.get("reason", "")))
		_eq("%s：斩击原位换成 %s" % [p[1], p[2]], u.skill_ids[index] if index >= 0 else "", str(p[2]))
		_eq("%s 的技能身份是斩击（R2.5）" % p[2], u.get_skill_identity(str(p[2])), "kensei_zhanji")
	var again: Dictionary = swords[0].apply_memory("kensei_yiguzuoqi", dl.memories, dl.skills)
	_check("同一技能一局只升级一次：第二张斩击回忆被拒", not bool(again.get("ok", true)))
	_check("被拒后仍是裂空", swords[0].skill_ids.has("kensei_liekong")
		and not swords[0].skill_ids.has("kensei_yijue"))


# ── ③ 裂空 ───────────────────────────────────────────

func _test_liekong(tm: Node, ks: Unit, enemies: Dictionary) -> void:
	print("\n[③] 裂空")
	var grid: Object = tm.grid
	var home: Vector2i = ks.grid_position
	# 先移到角落：四个方向的直线 3 格内都没有敌人。
	var corner: Vector2i = Vector2i(0, 0)
	grid.move_unit(ks, home, corner)
	ks.grid_position = corner
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.clear_marks()
	ks.set_sword_qi(0)
	_enter_action_phase(tm, ks)
	var far_entry: Dictionary = tm._build_skill_entry(ks, "kensei_liekong")
	_eq("直线内没有敌人 → 不可用", far_entry.get("available"), false)
	_eq("不可用原因", far_entry.get("reason"), "范围内没有敌人")
	tm._selected_skill_id = "kensei_liekong"
	var empty_act: Object = tm._build_skill_action(ks, Vector2i(1, 0), null)
	_check("空直线的动作仍可构建（拒绝发生在执行时）", empty_act != null)
	if empty_act != null:
		_eq("直线内没有敌人时执行被拒绝", bool(tm._execute_skill_action(empty_act)), false)
	tm._selected_skill_id = ""
	_check("被拒绝时不消耗标准行动", not ks.standard_used)
	_eq("被拒绝时不得印记", ks.get_mark_count(), 0)
	_eq("被拒绝时不得剑气", ks.sword_qi, 0)

	grid.move_unit(ks, corner, home)
	ks.grid_position = home
	var near: Unit = enemies[Vector2i(3, 3)]
	var far: Unit = enemies[Vector2i(5, 3)]
	var outside: Unit = enemies[Vector2i(6, 3)]
	var below: Unit = enemies[Vector2i(2, 4)]
	_eq("右侧直线内有敌人 → 可用", tm._build_skill_entry(ks, "kensei_liekong").get("available"), true)

	# 由近到远：传入远、近的顺序，排序后近的在前。
	var order: Array[Unit] = [far, near]
	tm._sort_units_near_to_far(ks.grid_position, order)
	_check("目标按距离由近到远排序", order[0] == near and order[1] == far)

	# 真实施放路径里的结算顺序：记录每名敌人受到伤害的先后。
	var hit_order: Array[String] = []
	var on_near: Callable = func(_amount: int, _type: String) -> void: hit_order.append("near")
	var on_far: Callable = func(_amount: int, _type: String) -> void: hit_order.append("far")
	near.damage_taken.connect(on_near)
	far.damage_taken.connect(on_far)
	var qi_sources: Array[String] = []
	var on_qi: Callable = func(_u: Unit, kind: String, _req: int, actual: int, source: String) -> void:
		if kind == "gain" and actual > 0:
			qi_sources.append(source)
	ks.sword_qi_changed.connect(on_qi)
	_cast(tm, ks, "kensei_liekong", Vector2i(3, 3), null)
	ks.sword_qi_changed.disconnect(on_qi)
	near.damage_taken.disconnect(on_near)
	far.damage_taken.disconnect(on_far)
	_eq("施放时由近到远结算", hit_order, ["near", "far"])
	_check("距离 1 的敌人受到伤害", near.stats.hp < 999, "hp=%d" % near.stats.hp)
	_check("距离 3 的敌人受到伤害", far.stats.hp < 999, "hp=%d" % far.stats.hp)
	_eq("距离 4 的敌人不受影响", outside.stats.hp, 999)
	_eq("下方的敌人不受影响", below.stats.hp, 999)
	_eq("两名命中 +10×2，结算后 +5：0 → 25", ks.sword_qi, 25)
	_eq("剑气获得顺序：每命中一次，最后才是结算后", qi_sources,
		["on_hit:kensei_liekong", "on_hit:kensei_liekong", "after_resolve:kensei_liekong"])
	_eq("使用后得一枚印记", ks.get_mark_count(), 1)
	_check("消耗标准行动", ks.standard_used)
	_leave_action_phase(tm)


# ── ④ 连斩 ───────────────────────────────────────────

func _test_yijue(tm: Node, ks: Unit, enemies: Dictionary) -> void:
	print("\n[④] 连斩")
	var target: Unit = enemies[Vector2i(3, 6)]
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.clear_marks()
	ks.set_sword_qi(0)
	_enter_action_phase(tm, ks)
	_eq("连斩可用（多段已承载）", tm._build_skill_entry(ks, "kensei_yijue").get("available"), true)
	var damage_events: Array[int] = []
	var on_damage: Callable = func(amount: int, _damage_type: String) -> void:
		damage_events.append(amount)
	target.damage_taken.connect(on_damage)
	_cast(tm, ks, "kensei_yijue", target.grid_position, target)
	target.damage_taken.disconnect(on_damage)
	_eq("三段各造成一次伤害", damage_events.size(), 3)
	_check("目标受到伤害", target.stats.hp < 999, "hp=%d" % target.stats.hp)
	_eq("三段全中、每段造成伤害 +10：0 → 30", ks.sword_qi, 30)
	_eq("印记只在第一段得一枚", ks.get_mark_count(), 1)
	_check("整次只消耗一次标准行动", ks.standard_used)

	# 目标倒下即停：第一段就打死，后面不再结算。
	var weak: Unit = enemies[Vector2i(1, 6)]
	weak.stats.hp = 1
	ks.reset_action_resources()
	ks.clear_marks()
	ks.set_sword_qi(0)
	_cast(tm, ks, "kensei_yijue", weak.grid_position, weak)
	_check("第一段击倒目标", not weak.stats.is_alive())
	_eq("目标倒下后停止：只有第一段的 +10", ks.sword_qi, 10)
	_eq("致命一段照常得印记（R1.11）", ks.get_mark_count(), 1)
	_leave_action_phase(tm)


func _test_segment_rules(tm: Node, ks: Unit, enemy: Unit) -> void:
	print("\n[④'] 段命中规则")
	var base: Dictionary = {
		"guaranteed_hit": true, "segment_hit_decay": 15,
		"mark_gain": 1, "mark_gain_after_damage": 1,
	}
	var s0: Dictionary = tm._build_segment_action_data(base, 0)
	var s1: Dictionary = tm._build_segment_action_data(base, 1)
	var s2: Dictionary = tm._build_segment_action_data(base, 2)
	_eq("第一段不降命中", int(s0.get("segment_hit_penalty", 0)), 0)
	_eq("第二段命中 −15", int(s1.get("segment_hit_penalty", 0)), 15)
	_eq("第三段命中 −30", int(s2.get("segment_hit_penalty", 0)), 30)
	_check("其他效果给的必定命中只作用于第一段", bool(s0.get("guaranteed_hit", false))
		and not bool(s1.get("guaranteed_hit", true)) and not bool(s2.get("guaranteed_hit", true)))
	_check("「第一段造成伤害后」的印记只在第一段", int(s0.get("mark_gain_after_damage", 0)) == 1
		and int(s1.get("mark_gain_after_damage", 1)) == 0 and int(s2.get("mark_gain_after_damage", 1)) == 0)
	_eq("命中即得的印记不受段数限制（原文没有只在第一段）", int(s2.get("mark_gain", 0)), 1)
	var own: Dictionary = base.duplicate()
	own["entry_guaranteed_hit"] = true
	_check("伤害条目自己声明的必定命中每段都保留",
		bool(tm._build_segment_action_data(own, 2).get("guaranteed_hit", false)))

	# 命中降低进入掷骰：命中 − 闪避恰为 100 时，无降低必中；降低 99 后只剩 1%。
	ks.stats.dex = 50
	enemy.stats.spd = 0
	var weapon_hit: int = 100 - ks.get_hit_value(0) + enemy.get_avoid_value(0)
	seed(20261029)
	var hits_plain: int = 0
	var hits_penalty: int = 0
	for _i: int in range(200):
		if bool(DamageCalculator.roll_outcome(ks, enemy, {"weapon_hit": weapon_hit, "disable_crit": true}).get("hit")):
			hits_plain += 1
		if bool(DamageCalculator.roll_outcome(ks, enemy,
				{"weapon_hit": weapon_hit, "disable_crit": true, "segment_hit_penalty": 99}).get("hit")):
			hits_penalty += 1
	_eq("无降低：200 次全中", hits_plain, 200)
	_check("降低 99 点后命中率只剩下限 1%", hits_penalty <= 10, "hits=%d" % hits_penalty)
	# 口径「先从未截断命中里扣，再按上下限」：命中 − 闪避为 150 时降低 15 仍是 135 → 100%。
	# 若先截断到 100 再扣，就只剩 85%，200 次里几乎必有未中。
	var hits_untruncated: int = 0
	for _i: int in range(200):
		if bool(DamageCalculator.roll_outcome(ks, enemy,
				{"weapon_hit": weapon_hit + 50, "disable_crit": true, "segment_hit_penalty": 15}).get("hit")):
			hits_untruncated += 1
	_eq("命中 − 闪避 150、降低 15：仍 200 次全中（先扣后截断）", hits_untruncated, 200)

	# 未命中即停：在测试进程里把连斩的段命中降低改成 1000（只剩 1% 下限），第二段几乎必然未中。
	var dl: Node = root.get_node("/root/DataLoader")
	var original: Dictionary = (dl.skills["kensei_yijue"] as Dictionary).duplicate(true)
	var steep: Dictionary = original.duplicate(true)
	(steep["damage_entries"] as Array)[0]["segment_hit_decay"] = 1000
	dl.skills["kensei_yijue"] = steep
	ks.stats.dex = 80
	enemy.stats.hp = 999
	ks.reset_action_resources()
	ks.clear_marks()
	ks.set_sword_qi(0)
	_enter_action_phase(tm, ks)
	seed(7)
	# 数本次动作产生的飘字：每个结算过的段各出一个（命中数字或 MISS），每个飘字是
	# 文字与阴影两个 Label（命中的另有一个形状图标，不是 Label）。
	# 第一段命中、第二段未中后停下 → 2 个飘字；若未中后继续掷第三段 → 3 个。
	var labels_before: int = _count_labels(tm.popup_layer)
	_cast(tm, ks, "kensei_yijue", enemy.grid_position, enemy)
	_eq("第二段未命中即停：只结算了两段（命中 + MISS 两个飘字）",
		(_count_labels(tm.popup_layer) - labels_before) / 2, 2)
	_eq("第二段未命中即停：只有第一段的 +10", ks.sword_qi, 10)
	dl.skills["kensei_yijue"] = original
	_leave_action_phase(tm)


func _count_labels(layer: Node) -> int:
	var count: int = 0
	for child: Node in layer.get_children():
		if child is Label:
			count += 1
	return count


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
