extends SceneTree
## 回忆技能·居合组之一（gameplay-impl PR6f-1）：〔阴阳剑〕→〔太阳剑〕〔太阴剑〕。
##
## 依据：设计库 762393b 的 kensei_taiyangjian / kensei_taiyinjian，states kensei_taiyang / kensei_taiyin；
## R1.1、R1.2、R1.3、R1.8、R2.5、R3.2；KB 设计规则总表 S16（阴阳圆满的额外回合不加每关卡上限）。
## 覆盖：
##   ① 数据与挂载。
##   ② 交替槽：每场开始为太阳剑；用太阳剑后变太阴剑并得 1 层太阳；用太阴剑后变回太阳剑并得 1 层太阴；
##      太阴剑是迅捷，交替形态参与迅捷阶段判定。
##   ③ 太阳：每层暴击 +1；剑气每实际累计增加 30 点得 1 层；满层累计暂停。
##      太阴：每层闪避 +1；剑气每实际累计减少 30 点得 1 层（含空想把获得改为失去）。
##   ④ 回合结束：技能栏为太阴剑失去 1 层太阳，为太阳剑失去 1 层太阴。
##   ⑤ 阴阳调和：两者都为 N 层时，自身回合内剑气变动额外 ±N×5；技能消耗的额外部分计入消耗与可用性；
##      回合外、空想期间不生效；层数不等时不生效。
##   ⑥ 阴阳圆满：两者都满 5 层 → 都降为 1 层；本轮已行动或正在自身回合 → 当前回合结束后获得额外回合
##      （不计入状态持续时间）；本轮尚未行动 → 本场速度 +10%。
##
## 运行：
##   <Godot_console.exe> --headless --path <worktree> --script res://tests/test_kensei_memory_yinyang.gd

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []


func _initialize() -> void:
	print("=== test_kensei_memory_yinyang（回忆技能·阴阳剑）===")
	_run.call_deferred()


func _run() -> void:
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	scene.run_injected = true
	scene.injected_map_id = "test_arena"
	scene.injected_player_units = [{"class_id": "kensei", "pos": Vector2i(1, 1)}]
	scene.injected_enemy_units = [{"class_id": "test_lancer", "pos": Vector2i(2, 1)}]
	scene.debug_harness_enabled = false
	root.add_child(scene)
	await process_frame
	await process_frame

	var tm: Node = scene.get_node("TacticalManager")
	_check("tactical_manager 脚本已挂载", tm.get_script() != null
		and (tm.get_script() as Script).resource_path == "res://scripts/core/tactical_manager.gd")
	_check("turn_manager 脚本已挂载", tm.turn_manager != null
		and (tm.turn_manager.get_script() as Script).resource_path == "res://scripts/core/turn_manager.gd")
	if tm.turn_manager != null:
		tm.turn_manager.stop()
	var ks: Unit = null
	var enemy: Unit = null
	for u: Variant in tm.units:
		if u is Unit and (u as Unit).unit_id == "kensei":
			ks = u
		elif u is Unit and (u as Unit).faction == "enemy":
			enemy = u
	if ks == null or enemy == null:
		_check("场景含剑圣与敌人", false)
		_finish(scene)
		return
	enemy.stats.max_hp = 999
	enemy.stats.hp = 999
	enemy.stats.spd = 0
	enemy.stats.def_attr = 0
	enemy.stats.res = 0
	ks.stats.dex = 80
	tm.battle_active = true

	var dl: Node = root.get_node("/root/DataLoader")
	_test_data(dl)
	var r: Dictionary = ks.apply_memory("kensei_juhe_yinyang", dl.memories, dl.skills)
	_check("阴阳剑兑现成功", bool(r.get("ok", false)), str(r.get("reason", "")))
	_eq("居合原位换成太阳剑", ks.skill_ids.has("kensei_taiyangjian") and not ks.skill_ids.has("kensei_juhe"), true)
	_eq("太阴剑身份是居合（R2.5）", ks.get_skill_identity("kensei_taiyinjian"), "kensei_juhe")
	_test_alternation(tm, ks, enemy)
	_test_accumulation(tm, ks)
	_test_turn_end_decay(tm, ks)
	_test_harmony(tm, ks, enemy)
	_test_fulfilled(tm, ks)
	_finish(scene)


func _test_data(dl: Node) -> void:
	print("\n[①] 数据")
	var yang: Dictionary = dl.skills.get("kensei_taiyangjian", {})
	var yin: Dictionary = dl.skills.get("kensei_taiyinjian", {})
	_check("太阳剑、太阴剑已装载", not yang.is_empty() and not yin.is_empty())
	_eq("太阳剑：标准、60 剑气、射程 1–2", [str(yang.action_cost), int(yang.qi_cost), int(yang.range.min),
		int(yang.range.max)], ["standard", 60, 1, 2])
	_eq("太阳剑：威力 +5、系数 1.5", [int(yang.damage_entries[0].power), float(yang.damage_entries[0].coefficient)],
		[5, 1.5])
	_eq("太阴剑：迅捷、20 剑气、射程 2–4、魔法", [str(yin.action_cost), int(yin.qi_cost), int(yin.range.min),
		int(yin.range.max), str(yin.damage_type)], ["swift", 20, 2, 4, "magical"])
	_eq("太阴剑：以力量计算", str(yin.damage_entries[0].base_attribute), "力量")
	_eq("累计每 30 点 1 层", int((yang.qi_accumulators as Array)[0].per), 30)
	_eq("调和每层 5 点、圆满降为 1 层、速度 10%", [int(yang.qi_harmony.per_stack), int(yang.qi_harmony.fulfilled_keep),
		int(yang.qi_harmony.fulfilled_speed_pct)], [5, 1, 10])
	_eq("太阳每层暴击 +1、太阴每层闪避 +1", [int(dl.held_states["kensei_taiyang"].engine_crit_per_stack),
		int(dl.held_states["kensei_taiyin"].engine_avoid_per_stack)], [1, 1])


# ── ② 交替槽 ─────────────────────────────────────────

func _test_alternation(tm: Node, ks: Unit, enemy: Unit) -> void:
	print("\n[②] 交替槽")
	_reset(ks)
	_enter_action_phase(tm, ks)
	_eq("每场开始：居合槽是太阳剑", _slot(tm, "kensei_taiyangjian").get("skill_id"), "kensei_taiyangjian")
	ks.set_sword_qi(100)
	ks.is_taking_turn = false
	_cast(tm, ks, "kensei_taiyangjian", enemy.grid_position, enemy)
	_eq("用太阳剑后槽变为太阴剑", _slot(tm, "kensei_taiyangjian").get("skill_id"), "kensei_taiyinjian")
	_eq("得 1 层太阳", ks.held_states.stacks("kensei_taiyang"), 1)
	_eq("太阳剑消耗 60 剑气", ks.sword_qi, 40)
	_eq("消耗的 60 点也是实际减少：累计得 2 层太阴", ks.held_states.stacks("kensei_taiyin"), 2)
	# 太阴剑射程 2–4：把敌人移到距离 2。
	tm.grid.move_unit(enemy, Vector2i(2, 1), Vector2i(3, 1))
	enemy.grid_position = Vector2i(3, 1)
	ks.standard_used = true
	_check("标准动作后只剩太阴剑（迅捷）：仍有可用的迅捷技能", tm._has_available_swift_skill(ks))
	var hp_before: int = enemy.stats.hp
	_cast(tm, ks, "kensei_taiyinjian", enemy.grid_position, enemy)
	_check("太阴剑造成伤害", enemy.stats.hp < hp_before)
	_eq("用太阴剑后槽变回太阳剑", _slot(tm, "kensei_taiyangjian").get("skill_id"), "kensei_taiyangjian")
	_eq("太阴剑使用后得 1 层太阴（2 + 1；消耗的 20 点累计不到 30）", ks.held_states.stacks("kensei_taiyin"), 3)
	_eq("太阴剑消耗 20 剑气", ks.sword_qi, 20)
	_check("太阴剑消耗迅捷行动", ks.swift_used)
	# 新的一场战斗复位为太阳剑（start_battle 对每个单位调用这两步；这里不真的开战，免得敌人回合开始行动）。
	ks.set_slot_form("kensei_taiyangjian", "kensei_taiyinjian")
	ks.held_states.clear()
	ks.reset_battle_memory_state()
	_eq("新战斗开始：回到太阳剑", ks.resolve_slot_form("kensei_taiyangjian"), "kensei_taiyangjian")
	_eq("新战斗开始：太阳太阴为 0 层", [ks.held_states.stacks("kensei_taiyang"),
		ks.held_states.stacks("kensei_taiyin")], [0, 0])
	tm.grid.move_unit(enemy, Vector2i(3, 1), Vector2i(2, 1))
	enemy.grid_position = Vector2i(2, 1)
	_leave_action_phase(tm)


# ── ③ 累计 ───────────────────────────────────────────

func _test_accumulation(tm: Node, ks: Unit) -> void:
	print("\n[③] 太阳与太阴的累计")
	_reset(ks)
	ks.is_taking_turn = false
	ks.set_sword_qi(0)
	var avoid0: int = ks.get_avoid_value(0)
	ks.gain_sword_qi(29, "test")
	_eq("实际增加 29：还没到 30", ks.held_states.stacks("kensei_taiyang"), 0)
	ks.gain_sword_qi(1, "test")
	_eq("累计到 30：1 层太阳", ks.held_states.stacks("kensei_taiyang"), 1)
	# 暴击对比在同一剑气下做：基础心眼的剑气暴击会随剑气变化。
	var crit_with: int = ks.get_crit_value(0)
	ks.held_states.remove("kensei_taiyang")
	_eq("太阳每层暴击 +1（同一剑气下对比）", crit_with - ks.get_crit_value(0), 1)
	ks.held_states.apply("kensei_taiyang", 1, {"kind": "permanent"})
	ks.lose_sword_qi(30, "test")
	_eq("实际减少 30：1 层太阴", ks.held_states.stacks("kensei_taiyin"), 1)
	_eq("太阴每层闪避 +1", ks.get_avoid_value(0) - avoid0, 1)
	# 只计实际变化：剑气 100 时再获得不计。
	ks.set_sword_qi(100)
	ks.gain_sword_qi(30, "test")
	_eq("剑气已满时获得：没有实际增加，不计", ks.held_states.stacks("kensei_taiyang"), 1)
	# 满层暂停：太阳满 5 层后再增加不存进度。
	ks.held_states.apply("kensei_taiyang", 4, {"kind": "permanent"})
	ks.set_sword_qi(0)
	ks.gain_sword_qi(29, "test")
	_eq("太阳满 5 层：进度不保存", int(ks._qi_accumulation_progress.get("kensei_taiyang", 0)), 0)
	# 空想把获得改为失去：只计入太阴。
	_reset(ks)
	ks.held_states.apply("kensei_kongxiang", 1, {"kind": "until_this_turn_end"})
	ks.set_sword_qi(60)
	ks.gain_sword_qi(30, "test")
	_eq("空想里获得 30 被改为失去：太阴 1 层", ks.held_states.stacks("kensei_taiyin"), 1)
	_eq("空想里被改为失去的不计入太阳", ks.held_states.stacks("kensei_taiyang"), 0)
	ks.held_states.remove("kensei_kongxiang")


# ── ④ 回合结束衰减 ───────────────────────────────────

func _test_turn_end_decay(tm: Node, ks: Unit) -> void:
	print("\n[④] 回合结束衰减")
	_reset(ks)
	ks.held_states.apply("kensei_taiyang", 2, {"kind": "permanent"})
	ks.held_states.apply("kensei_taiyin", 2, {"kind": "permanent"})
	tm._apply_slot_form_turn_end(ks)
	_eq("技能栏为太阳剑：失去 1 层太阴", [ks.held_states.stacks("kensei_taiyang"),
		ks.held_states.stacks("kensei_taiyin")], [2, 1])
	ks.set_slot_form("kensei_taiyangjian", "kensei_taiyinjian")
	tm._apply_slot_form_turn_end(ks)
	_eq("技能栏为太阴剑：失去 1 层太阳", [ks.held_states.stacks("kensei_taiyang"),
		ks.held_states.stacks("kensei_taiyin")], [1, 1])
	ks.set_slot_form("kensei_taiyangjian", "kensei_taiyangjian")
	# 回合结束钩子确实调用。
	tm.turn_manager.current_unit = ks
	tm._on_turn_ended(ks)
	_eq("回合结束钩子：太阳剑槽 → 太阴 1 → 0", ks.held_states.stacks("kensei_taiyin"), 0)


# ── ⑤ 阴阳调和 ───────────────────────────────────────

func _test_harmony(tm: Node, ks: Unit, enemy: Unit) -> void:
	print("\n[⑤] 阴阳调和")
	_reset(ks)
	ks.held_states.apply("kensei_taiyang", 2, {"kind": "permanent"})
	ks.held_states.apply("kensei_taiyin", 2, {"kind": "permanent"})
	ks.is_taking_turn = true
	_eq("两者都是 2 层：额外 10", ks.get_harmony_extra(), 10)
	ks.set_sword_qi(0)
	ks.gain_sword_qi(10, "test")
	_eq("自身回合内获得 10：实际 +20", ks.sword_qi, 20)
	ks.lose_sword_qi(5, "test")
	_eq("自身回合内失去 5：实际 −15", ks.sword_qi, 5)
	ks.gain_sword_qi(10, "talent:test")
	_eq("天赋给的剑气不是技能效果：不调和（+10）", ks.sword_qi, 15)
	ks.set_sword_qi(5)
	# 上面那 10 点让太阳的累计到了 30、多得 1 层：恢复成两者各 2 层，接着测技能消耗。
	ks.held_states.clear()
	ks.reset_battle_memory_state()
	ks.held_states.apply("kensei_taiyang", 2, {"kind": "permanent"})
	ks.held_states.apply("kensei_taiyin", 2, {"kind": "permanent"})
	# 技能消耗：额外部分计入消耗，剑气足以支付时才能使用。
	_enter_action_phase(tm, ks)
	ks.is_taking_turn = true
	ks.set_sword_qi(65)
	_eq("太阳剑 60 + 调和 10 = 70：剑气 65 不可用", tm._build_skill_entry(ks, "kensei_taiyangjian").get("available"), false)
	_check("校验同样拒绝", not bool(GameAction.validate_skill_usage(ks, tm._get_skill_data("kensei_taiyangjian")).get("ok", true)))
	ks.set_sword_qi(70)
	_eq("剑气 70：可用", tm._build_skill_entry(ks, "kensei_taiyangjian").get("available"), true)
	_cast(tm, ks, "kensei_taiyangjian", enemy.grid_position, enemy)
	_eq("消耗 60 + 10 = 70", ks.sword_qi, 0)
	_leave_action_phase(tm)
	# 不生效的情形。
	_reset(ks)
	ks.held_states.apply("kensei_taiyang", 2, {"kind": "permanent"})
	ks.held_states.apply("kensei_taiyin", 2, {"kind": "permanent"})
	ks.is_taking_turn = false
	ks.set_sword_qi(0)
	ks.gain_sword_qi(10, "test")
	_eq("回合外：不调和", ks.sword_qi, 10)
	ks.is_taking_turn = true
	ks.held_states.apply("kensei_kongxiang", 1, {"kind": "until_this_turn_end"})
	_eq("空想期间：不调和", ks.get_harmony_extra(), 0)
	ks.held_states.remove("kensei_kongxiang")
	ks.held_states.consume_stacks("kensei_taiyin", 1)
	_eq("层数不等：不调和", ks.get_harmony_extra(), 0)
	ks.is_taking_turn = false


# ── ⑥ 阴阳圆满 ───────────────────────────────────────

func _test_fulfilled(tm: Node, ks: Unit) -> void:
	print("\n[⑥] 阴阳圆满")
	# 正在自身回合：额外回合。
	_reset(ks)
	ks.held_states.apply("kensei_taiyang", 5, {"kind": "permanent"})
	ks.held_states.apply("kensei_taiyin", 4, {"kind": "permanent"})
	tm.turn_manager._queue.clear()
	tm.turn_manager.current_unit = ks
	ks.is_taking_turn = false
	ks.set_sword_qi(0)
	ks.set_sword_qi(60)
	ks.lose_sword_qi(30, "test")
	_eq("太阴到 5：两者都降为 1 层", [ks.held_states.stacks("kensei_taiyang"),
		ks.held_states.stacks("kensei_taiyin")], [1, 1])
	_eq("正在自身回合：排入一个额外回合", tm.turn_manager._extra_turn_queue.size(), 1)
	_eq("额外回合不进按先攻排序的队列", tm.turn_manager._queue.size(), 0)
	_check("排队的额外回合不算「本轮尚未行动」", not tm.turn_manager.has_pending_turn(ks))
	# 队列重排（回合结束时任何单位的 buff 变化都会触发）不影响额外回合先进行。
	var other: Unit = null
	for u: Variant in tm.units:
		if u is Unit and (u as Unit).faction == "enemy":
			other = u
	tm.turn_manager._queue.append(other)
	other.stats.spd = 999
	tm.turn_manager.refresh_queue_order()
	_eq("速度不变", ks.battle_speed_pct, 0.0)
	# 额外回合开始：标记为额外回合，状态持续时间不计入。
	ks.held_states.apply("kensei_jiashi", 1, {"kind": "until_own_turn_start", "count": 2})
	tm.turn_manager.current_unit = null
	tm.turn_manager._advance()
	_check("额外回合先于队列里速度更快的单位开始", tm.turn_manager.current_unit == ks
		and tm.turn_manager.current_is_extra_turn)
	_eq("额外回合不计入持有型状态的持续时间（架势仍为 2）", ks.held_states.remaining("kensei_jiashi"), 2)
	# 额外回合也不推进普通 buff 的持续时间。
	var buff: BuffEffect = tm._make_buff_effect_instance(ks, {"effect_id": "defense_up", "duration": 3, "value": 1})
	ks.add_buff(buff)
	tm._on_turn_ended(ks)
	_eq("额外回合结束：普通 buff 持续时间不减（仍为 3）", buff.duration, 3)
	ks.process_turn_end_buffs(false)
	_eq("常规回合结束：普通 buff 持续时间减 1", buff.duration, 2)
	ks.remove_buff(buff)
	tm.turn_manager.stop()
	other.stats.spd = 0
	ks.held_states.remove("kensei_jiashi")

	# 在别的单位回合里达成：等那个回合结束后插入。
	_reset(ks)
	tm.turn_manager.current_unit = other
	ks.held_states.apply("kensei_taiyang", 5, {"kind": "permanent"})
	ks.held_states.apply("kensei_taiyin", 5, {"kind": "permanent"})
	ks.check_yin_yang_fulfilled()
	_eq("他人回合里达成（本轮已行动）：排入额外回合", tm.turn_manager._extra_turn_queue.size(), 1)
	_eq("他人回合仍在进行", tm.turn_manager.current_unit, other)
	tm.turn_manager.current_unit = null
	tm.turn_manager._advance()
	_check("那个回合结束后，额外回合开始", tm.turn_manager.current_unit == ks
		and tm.turn_manager.current_is_extra_turn)
	tm.turn_manager.stop()

	# 本轮尚未行动：本场速度 +10%，可多次获得。
	_reset(ks)
	var spd0: int = ks.get_effective_stat("SPD")
	tm.turn_manager._queue.clear()
	tm.turn_manager._queue.append(ks)
	tm.turn_manager.current_unit = null
	for _i: int in range(2):
		ks.held_states.apply("kensei_taiyang", 5, {"kind": "permanent"})
		ks.held_states.apply("kensei_taiyin", 5, {"kind": "permanent"})
		ks.check_yin_yang_fulfilled()
	_eq("本轮尚未行动两次圆满：速度 +20%", ks.battle_speed_pct, 20.0)
	_eq("速度按 R1.8 向下取整", ks.get_effective_stat("SPD"), floori(float(spd0) * 1.2 + 0.000001))
	_eq("没有排入额外回合", tm.turn_manager._extra_turn_queue.size(), 0)
	tm.turn_manager.stop()

	# 单位死亡移出回合管理时，排队的额外回合一并清掉（多个也一样）。
	tm.turn_manager.grant_extra_turn(ks)
	tm.turn_manager.grant_extra_turn(ks)
	tm.turn_manager.remove_unit(ks)
	_eq("移出时清掉全部排队的额外回合", tm.turn_manager._extra_turn_queue.size(), 0)


# ── 工具 ─────────────────────────────────────────────

func _reset(ks: Unit) -> void:
	ks.held_states.clear()
	ks.reset_battle_memory_state()
	ks.is_taking_turn = false
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()


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
