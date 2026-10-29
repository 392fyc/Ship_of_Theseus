extends SceneTree
## 回忆技能·一闪组（gameplay-impl PR6b，差距清单 M14）：〔如影随形〕→〔踏影〕。
##
## 依据：设计库 762393b 的 kensei_huizhan；R2.5。
## 覆盖：
##   ① 数据：技能镜像设计库，upgrade_of 指向一闪；脚本挂载。
##   ② 兑现：真实数据下回忆可兑现，一闪原位换成踏影，技能身份仍是一闪（R2.5）。
##   ③ 选目标：射程内有合法落点的敌人才可选；四周被占满的敌人不可选；落点是目标上下左右的空格。
##   ④ 执行：直接位移到落点（可越过目标，不检查沿途）、不触发移动事件，再对目标造成伤害；
##      目标本轮尚未行动时 +20 剑气，已行动则不给；消耗移动机会；落点不合法时拒绝且不扣消耗。
##   ⑤ 可用性：射程内没有可落脚的敌人时不可用。
##   ⑥ 输入路径：点敌人 → 落点高亮 → 点落点，走真实点击流程完成施放。
##
## 运行：
##   <Godot_console.exe> --headless --path <worktree> --script res://tests/test_kensei_memory_yishan.gd

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []


func _initialize() -> void:
	print("=== test_kensei_memory_yishan（回忆技能·一闪组）===")
	_run.call_deferred()


func _run() -> void:
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	scene.run_injected = true
	scene.injected_map_id = "test_arena"
	scene.injected_player_units = [{"class_id": "kensei", "pos": Vector2i(2, 3)}]
	# (5,3)：距离 3，四周都空。(2,0)：距离 3，左 (1,0)、右 (3,0)、下 (2,1) 都有敌人，上方出界 → 没有落点。
	scene.injected_enemy_units = [
		{"class_id": "test_lancer", "pos": Vector2i(5, 3)},
		{"class_id": "test_lancer", "pos": Vector2i(2, 0)},
		{"class_id": "test_lancer", "pos": Vector2i(1, 0)},
		{"class_id": "test_lancer", "pos": Vector2i(3, 0)},
		{"class_id": "test_lancer", "pos": Vector2i(2, 1)},
	]
	scene.debug_harness_enabled = false
	root.add_child(scene)
	await process_frame
	await process_frame

	var tm: Node = scene.get_node("TacticalManager")
	_check("tactical_manager 脚本已挂载", tm.get_script() != null)
	_eq("tactical_manager 挂的是 tactical_manager.gd",
		(tm.get_script() as Script).resource_path, "res://scripts/core/tactical_manager.gd")
	_check("turn_manager 脚本已挂载", tm.turn_manager != null and tm.turn_manager.get_script() != null
		and (tm.turn_manager.get_script() as Script).resource_path == "res://scripts/core/turn_manager.gd")
	if tm.turn_manager != null:
		tm.turn_manager.stop()
	var ks: Unit = null
	var enemies: Dictionary = {}
	for u: Variant in tm.units:
		if not u is Unit:
			continue
		var unit: Unit = u
		if unit.unit_id == "kensei":
			ks = unit
		elif unit.faction == "enemy":
			enemies[unit.grid_position] = unit
			unit.stats.max_hp = 999
			unit.stats.hp = 999
			unit.stats.spd = 0
			unit.stats.def_attr = 0
	if ks == null or enemies.size() < 5:
		_check("场景含剑圣与五名敌人", false)
		_finish(scene)
		return
	ks.stats.dex = 80

	var dl: Node = root.get_node("/root/DataLoader")
	_test_data(dl)
	_test_apply(dl, ks)
	_test_targeting(tm, ks, enemies)
	_test_execute(tm, ks, enemies[Vector2i(5, 3)])
	_test_availability(tm, ks)
	await _test_input_flow(tm, ks, enemies[Vector2i(5, 3)])
	_finish(scene)


# ── ① 数据 ───────────────────────────────────────────

func _test_data(dl: Node) -> void:
	print("\n[①] 数据")
	var s: Dictionary = dl.skills.get("kensei_huizhan", {})
	_check("踏影已装载", not s.is_empty())
	_eq("踏影 upgrade_of", str(s.get("upgrade_of", "")), "kensei_yishan")
	_eq("踏影 名称", str(s.get("name", "")), "踏影")
	_eq("踏影 目标方式 单位", str(s.get("target_mode", "")), "单位")
	_eq("踏影 射程 菱形 1–4", [str(s.range.type), int(s.range.min), int(s.range.max)], ["diamond", 1, 4])
	_eq("踏影 冷却 2、移动", [int(s.cooldown), str(s.action_cost)], [2, "move"])
	var e: Dictionary = (s.get("damage_entries", []) as Array)[0]
	_eq("踏影 威力 +1、系数 0.5", [int(e.get("power", 0)), float(e.get("coefficient", 0.0))], [1, 0.5])
	_eq("踏影 落点方式", str(s.get("landing_mode", "")), "adjacent_to_target")
	_eq("踏影 目标本轮未行动 +20 剑气", int(s.get("qi_gain_if_target_not_acted", 0)), 20)
	_check("踏影 不走一闪的沿途位移口径", not bool(s.get("displacement", false)))


# ── ② 兑现 ───────────────────────────────────────────

func _test_apply(dl: Node, ks: Unit) -> void:
	print("\n[②] 兑现（真实数据）")
	var index: int = ks.skill_ids.find("kensei_yishan")
	var r: Dictionary = ks.apply_memory("kensei_tuodaoji", dl.memories, dl.skills)
	_check("如影随形兑现成功", bool(r.get("ok", false)), str(r.get("reason", "")))
	_eq("一闪原位换成踏影", ks.skill_ids[index] if index >= 0 else "", "kensei_huizhan")
	_eq("踏影的技能身份是一闪（R2.5）", ks.get_skill_identity("kensei_huizhan"), "kensei_yishan")


# ── ③ 选目标 ─────────────────────────────────────────

func _test_targeting(tm: Node, ks: Unit, enemies: Dictionary) -> void:
	print("\n[③] 选目标")
	var skill: Dictionary = tm._get_skill_data("kensei_huizhan")
	var targets: Array[Vector2i] = tm._get_landing_target_cells(ks, skill)
	_check("四周空的敌人可选", Vector2i(5, 3) in targets)
	_check("四周被占满的敌人不可选", not Vector2i(2, 0) in targets)
	_check("至少有一面空着的敌人可选", Vector2i(2, 1) in targets)
	var landings: Array[Vector2i] = tm._get_adjacent_landing_cells(ks, Vector2i(5, 3))
	landings.sort()
	_eq("落点是目标上下左右的四个空格", landings,
		[Vector2i(4, 3), Vector2i(5, 2), Vector2i(5, 4), Vector2i(6, 3)])
	var boxed: Array[Vector2i] = tm._get_adjacent_landing_cells(ks, Vector2i(2, 0))
	_eq("被占满的敌人没有落点", boxed.size(), 0)


# ── ④ 执行 ───────────────────────────────────────────

func _test_execute(tm: Node, ks: Unit, target: Unit) -> void:
	print("\n[④] 执行")
	var home: Vector2i = ks.grid_position
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.set_sword_qi(0)
	_enter_action_phase(tm, ks)
	# 不合法的落点（不与目标相邻）：拒绝，不扣消耗，不移动。
	var bad: Object = _build(tm, ks, target, Vector2i(7, 3))
	_check("非相邻落点的动作可构建（拒绝发生在执行时）", bad != null)
	if bad != null:
		_eq("非相邻落点被拒绝", bool(tm._execute_skill_action(bad)), false)
	_eq("被拒绝时不移动", ks.grid_position, home)
	_check("被拒绝时不消耗移动机会", not ks.movement_used)
	_eq("被拒绝时没有进入冷却", ks.get_skill_cooldown("kensei_huizhan"), 0)
	# 没带落点的动作也拒绝。
	tm._selected_skill_id = "kensei_huizhan"
	var no_landing: Object = tm._build_skill_action(ks, target.grid_position, target)
	tm._selected_skill_id = ""
	if no_landing != null:
		_eq("没有落点的动作被拒绝", bool(tm._execute_skill_action(no_landing)), false)

	# 目标本轮尚未行动：把它放进本轮待行动队列。
	tm.turn_manager._queue.clear()
	tm.turn_manager._queue.append(target)
	var moved_events: Array[int] = []
	var on_moved: Callable = func(_from: Vector2i, _to: Vector2i) -> void: moved_events.append(1)
	ks.moved.connect(on_moved)
	var damaged_at: Array[Vector2i] = []
	var on_damage: Callable = func(_amount: int, _type: String) -> void:
		damaged_at.append(ks.grid_position)
	target.damage_taken.connect(on_damage)
	var act: Object = _build(tm, ks, target, Vector2i(6, 3))
	_check("踏影 动作可构建", act != null)
	if act != null:
		_check("踏影 执行成功", bool(tm._execute_skill_action(act)))
	ks.moved.disconnect(on_moved)
	target.damage_taken.disconnect(on_damage)
	_eq("越过目标落到另一侧（不检查沿途）", ks.grid_position, Vector2i(6, 3))
	_eq("旧格已空出", tm.grid.get_unit_at(home), null)
	_eq("新格的占据者是剑圣", tm.grid.get_unit_at(Vector2i(6, 3)), ks)
	_eq("先位移后伤害：受伤时剑圣已在落点", damaged_at, [Vector2i(6, 3)])
	_eq("不视为移动：没有发出移动事件", moved_events.size(), 0)
	_check("目标受到伤害", target.stats.hp < 999, "hp=%d" % target.stats.hp)
	_eq("目标本轮尚未行动 → +20 剑气", ks.sword_qi, 20)
	_eq("进入冷却 2", ks.get_skill_cooldown("kensei_huizhan"), 2)
	_check("消耗移动机会", ks.movement_used)
	_check("不消耗标准行动", not ks.standard_used)

	# 目标本轮已经行动过：不给剑气。落点选在已站着的格（目标左侧，原地出手）。
	tm.turn_manager._queue.clear()
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.set_sword_qi(0)
	var hp_before: int = target.stats.hp
	var stay: Object = _build(tm, ks, target, Vector2i(6, 3))
	if stay != null:
		_check("已站在目标旁边时可原地出手", bool(tm._execute_skill_action(stay)))
	_eq("原地出手不移动", ks.grid_position, Vector2i(6, 3))
	_check("原地出手仍造成伤害", target.stats.hp < hp_before)
	_eq("目标本轮已行动 → 不给剑气", ks.sword_qi, 0)

	# 被其他单位占据的落点：拒绝。
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	var occupied: Object = _build(tm, ks, target, Vector2i(4, 3))
	var blocker: Unit = null
	for u: Variant in tm.units:
		if u is Unit and (u as Unit).faction == "enemy" and (u as Unit).grid_position == Vector2i(2, 1):
			blocker = u
	# 把 (2,1) 的敌人搬到 (4,3)，让这个落点被占。
	if blocker != null:
		tm.grid.move_unit(blocker, Vector2i(2, 1), Vector2i(4, 3))
		blocker.grid_position = Vector2i(4, 3)
	if occupied != null:
		_eq("被占据的落点被拒绝", bool(tm._execute_skill_action(occupied)), false)
	_eq("被拒绝时不移动", ks.grid_position, Vector2i(6, 3))
	if blocker != null:
		tm.grid.move_unit(blocker, Vector2i(4, 3), Vector2i(2, 1))
		blocker.grid_position = Vector2i(2, 1)
	# 回原位，供后面用。
	tm.grid.move_unit(ks, ks.grid_position, home)
	ks.grid_position = home
	_leave_action_phase(tm)


# ── ⑤ 可用性 ─────────────────────────────────────────

func _test_availability(tm: Node, ks: Unit) -> void:
	print("\n[⑤] 可用性")
	var home: Vector2i = ks.grid_position
	var far: Vector2i = Vector2i(7, 7)  # 离所有敌人都超过 4 格
	tm.grid.move_unit(ks, home, far)
	ks.grid_position = far
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	_enter_action_phase(tm, ks)
	var entry: Dictionary = tm._build_skill_entry(ks, "kensei_huizhan")
	_eq("射程内没有可落脚的敌人 → 不可用", entry.get("available"), false)
	_eq("不可用原因", entry.get("reason"), "射程内没有可落脚的敌人")
	tm.grid.move_unit(ks, far, home)
	ks.grid_position = home
	_eq("回到敌人附近 → 可用", tm._build_skill_entry(ks, "kensei_huizhan").get("available"), true)
	_leave_action_phase(tm)


# ── ⑥ 输入路径 ───────────────────────────────────────

func _test_input_flow(tm: Node, ks: Unit, target: Unit) -> void:
	print("\n[⑥] 输入路径：点敌人 → 点落点")
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.set_sword_qi(0)
	tm.turn_manager._queue.clear()
	_enter_action_phase(tm, ks)
	tm.battle_active = true
	tm.request_skill_selection("kensei_huizhan")
	_eq("进入选目标", tm.input_state, 3)  # SKILL_TARGETING
	_check("第一段：可点的格是敌人", target.grid_position in tm._attack_cells
		and not Vector2i(2, 0) in tm._attack_cells)
	tm._handle_click(target.grid_position)
	_eq("点敌人后记下它", tm._landing_anchor, target.grid_position)
	var landing_cells: Array[Vector2i] = tm._attack_cells.duplicate()
	landing_cells.sort()
	_eq("第二段：可点的格是它四周的空格", landing_cells,
		[Vector2i(4, 3), Vector2i(5, 2), Vector2i(5, 4), Vector2i(6, 3)])
	tm._has_hover_cell = true
	tm._hover_cell = Vector2i(5, 2)
	tm._recalculate_hover_artifacts()
	_eq("悬停落点时范围预览落在敌人身上", tm._area_preview_cells, [target.grid_position])
	_check("悬停落点时有伤害预告", not (tm._combat_forecast as Dictionary).is_empty())
	var hp_before: int = target.stats.hp
	tm._handle_click(Vector2i(5, 2))
	await create_timer(2.0).timeout
	_eq("点落点后剑圣位移到 (5,2)", ks.grid_position, Vector2i(5, 2))
	_check("目标受到伤害", target.stats.hp < hp_before)
	_eq("施放后清空已选敌人", tm._landing_anchor, Vector2i(-1, -1))
	_leave_action_phase(tm)


func _build(tm: Node, ks: Unit, target: Unit, landing: Vector2i) -> Object:
	tm.current_unit = ks
	tm._selected_skill_id = "kensei_huizhan"
	var act: Object = tm._build_skill_action(ks, target.grid_position, target, landing)
	tm._selected_skill_id = ""
	return act


func _enter_action_phase(tm: Node, u: Unit) -> void:
	tm.current_unit = u
	tm.selected_unit = u
	tm.turn_manager.current_unit = u
	tm.input_state = 2  # ACTION_PHASE


func _leave_action_phase(tm: Node) -> void:
	tm.turn_manager.current_unit = null
	tm.current_unit = null
	tm.input_state = 0


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
