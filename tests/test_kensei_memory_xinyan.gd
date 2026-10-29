extends SceneTree
## 回忆技能·心眼组（gameplay-impl PR6e，差距清单 M18、M19）：
## 〔心无旁骛〕→〔心眼·澄〕；〔大梦将醒〕→〔心眼·梦〕与〔空想剑〕。
##
## 依据：设计库 762393b 的 kensei_xinyan_cheng / xinyan_che / kongxiangjian，
## states kensei_chengxin / kongxiang / jianhen；R1.1、R1.2、R2.5、R3.2；KB 天赋设计要点 §12。
## 覆盖：
##   ① 数据与挂载。
##   ② PR5 前置条件 1：心眼升级后，基础心眼的剑气暴击、剑气不足加速度、印记百分比属性全部失效；
##      被动条目的名字与说明取升级技能。
##   ③ 心眼·澄：回合结束剑气 ≥ 15 → 消耗 15 得 1 层澄心，否则失去 1 层；上限 3；澄心每层技能威力 +2。
##   ④ 心眼·梦：回合开始剑气为上限才进入空想；空想期间获得改失去、可透支剑气、实际损失每 25 点
##      得 1 层剑痕（满 5 层不存进度）、结束时清空剩余剑气（不计剑痕）。
##   ⑤ 剑痕：每层闪避 +3；即将受到普通控制时失去 1 层并免疫。
##   ⑥ 空想剑：只在空想期间可用，被动槽换成它；命中后补齐印记；5 层剑痕时消耗并恢复 1 次标准动作；
##      空想期间只剩空想剑时，标准动作之后不自动结束回合。
##
## 运行：
##   <Godot_console.exe> --headless --path <worktree> --script res://tests/test_kensei_memory_xinyan.gd

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []


func _initialize() -> void:
	print("=== test_kensei_memory_xinyan（回忆技能·心眼组）===")
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
	tm.battle_active = true

	var dl: Node = root.get_node("/root/DataLoader")
	_test_data(dl)
	_test_base_xinyan_off(tm, dl, swords[0])
	_test_cheng(tm, swords[0], enemies[Vector2i(2, 1)])
	_test_meng(tm, dl, swords[1])
	_test_scars(tm, swords[1], enemies[Vector2i(6, 5)])
	await _test_kongxiangjian(tm, swords[1], enemies[Vector2i(6, 5)])
	_finish(scene)


# ── ① 数据 ───────────────────────────────────────────

func _test_data(dl: Node) -> void:
	print("\n[①] 数据")
	for id: String in ["kensei_xinyan_cheng", "kensei_xinyan_che", "kensei_kongxiangjian"]:
		var s: Dictionary = dl.skills.get(id, {})
		_check(id + " 已装载", not s.is_empty())
		_eq(id + " upgrade_of", str(s.get("upgrade_of", "")), "kensei_xinyan")
	var k: Dictionary = dl.skills["kensei_kongxiangjian"]
	_eq("空想剑 射程 菱形 1–3、迅捷、冷却 1", [str(k.range.type), int(k.range.min), int(k.range.max),
		str(k.action_cost), int(k.cooldown)], ["diamond", 1, 3, "swift", 1])
	var e: Dictionary = (k.damage_entries as Array)[0]
	_eq("空想剑 纯粹、以力量计算、不可暴击", [str(e.damage_type), str(e.base_attribute), str(e.crit_mode)],
		["纯粹", "力量", "不可暴击"])
	_eq("澄 回合结束消耗 15 剑气", int(dl.skills["kensei_xinyan_cheng"].passive_turn_end.qi_cost), 15)
	_eq("澄心 每层威力 +2", int(dl.held_states["kensei_chengxin"].engine_skill_power_per_stack), 2)
	_eq("空想 每 25 点损失 1 层剑痕", int(dl.held_states["kensei_kongxiang"].engine_qi_loss_scar.qi_per_stack), 25)
	_eq("剑痕 每层闪避 +3", int(dl.held_states["kensei_jianhen"].engine_avoid_per_stack), 3)


# ── ② 基础心眼失效 ───────────────────────────────────

func _test_base_xinyan_off(tm: Node, dl: Node, ks: Unit) -> void:
	print("\n[②] 心眼升级后基础心眼的加成失效（PR5 前置条件 1）")
	ks.set_sword_qi(60)
	ks.marks = {"心": true, "道": false, "势": false}
	var base_dex: int = ks.stats.dex
	_check("前提：基础心眼生效", ks.has_base_xinyan())
	_eq("前提：剑气 60 → 暴击 +3", ks.crit_bonus, 3)
	_eq("前提：〔心〕印记让技巧 +10%", ks.get_effective_stat("DEX"), floori(base_dex * 1.1 + 0.000001))
	ks.set_sword_qi(0)
	var spd_with_deficit: int = ks.get_effective_stat("SPD")
	ks.set_sword_qi(100)
	_eq("前提：剑气 0 比剑气满时速度高 2", spd_with_deficit - ks.get_effective_stat("SPD"), 2)

	var r: Dictionary = ks.apply_memory("kensei_xinwupangwu", dl.memories, dl.skills)
	_check("心无旁骛兑现成功", bool(r.get("ok", false)), str(r.get("reason", "")))
	_eq("被动换成心眼·澄", ks.passive_skill_id, "kensei_xinyan_cheng")
	_check("基础心眼不再生效", not ks.has_base_xinyan())
	ks.set_sword_qi(60)
	_eq("剑气暴击加成失效", ks.crit_bonus, 0)
	_eq("〔心〕印记不再加技巧", ks.get_effective_stat("DEX"), base_dex)
	ks.set_sword_qi(0)
	var spd0: int = ks.get_effective_stat("SPD")
	ks.set_sword_qi(100)
	_eq("剑气不足加速度失效", spd0, ks.get_effective_stat("SPD"))
	ks.clear_marks()
	ks.set_sword_qi(0)
	_enter_action_phase(tm, ks)
	var entry: Dictionary = tm._build_passive_entry(ks)
	_eq("被动条目名取升级技能", entry.get("name"), "心眼·澄")
	_check("被动条目说明取升级技能", str(entry.get("description", "")).contains("澄心"))
	_leave_action_phase(tm)


# ── ③ 心眼·澄 ────────────────────────────────────────

func _test_cheng(tm: Node, ks: Unit, enemy: Unit) -> void:
	print("\n[③] 心眼·澄")
	ks.set_sword_qi(20)
	tm._apply_passive_turn_end(ks)
	_eq("剑气 20：消耗 15 → 5", ks.sword_qi, 5)
	_eq("得 1 层澄心", ks.held_states.stacks("kensei_chengxin"), 1)
	tm._apply_passive_turn_end(ks)
	_eq("剑气 5：不消耗", ks.sword_qi, 5)
	_eq("剑气不足失去 1 层澄心", ks.held_states.stacks("kensei_chengxin"), 0)
	for _i: int in range(4):
		ks.set_sword_qi(15)
		tm._apply_passive_turn_end(ks)
	_eq("澄心最多 3 层", ks.held_states.stacks("kensei_chengxin"), 3)
	# 每层技能威力 +2：斩击威力 +1 → +7。
	var ctx: Dictionary = _context(tm, ks, "kensei_zhanji", enemy)
	_eq("3 层澄心：斩击威力 1 + 6 = 7", float(ctx.get("skill_power", -1)), 7.0)
	var basic_with: float = float(tm._build_hostile_action_context(ks, enemy, {}).get("skill_power", 0.0))
	var saved_stacks: int = ks.held_states.stacks("kensei_chengxin")
	ks.held_states.remove("kensei_chengxin")
	var basic_without: float = float(tm._build_hostile_action_context(ks, enemy, {}).get("skill_power", 0.0))
	ks.held_states.apply("kensei_chengxin", saved_stacks, {"kind": "permanent"})
	_eq("非技能动作：有没有澄心威力都一样", basic_with, basic_without)
	# 回合结束钩子确实调用。
	ks.held_states.remove("kensei_chengxin")
	ks.set_sword_qi(15)
	tm.turn_manager.current_unit = ks
	tm._on_turn_ended(ks)
	_eq("回合结束时结算：澄心 1 层", ks.held_states.stacks("kensei_chengxin"), 1)
	_eq("回合结束时结算：剑气 15 → 0", ks.sword_qi, 0)


# ── ④ 心眼·梦与空想 ──────────────────────────────────

func _test_meng(tm: Node, dl: Node, ks: Unit) -> void:
	print("\n[④] 心眼·梦与空想")
	var r: Dictionary = ks.apply_memory("kensei_xinyanche", dl.memories, dl.skills)
	_check("大梦将醒兑现成功", bool(r.get("ok", false)), str(r.get("reason", "")))
	_eq("被动换成心眼·梦", ks.passive_skill_id, "kensei_xinyan_che")
	_eq("空想剑身份是心眼（R2.5）", ks.get_skill_identity("kensei_kongxiangjian"), "kensei_xinyan")

	ks.set_sword_qi(99)
	tm._apply_passive_turn_start(ks)
	_check("剑气 99：不进入空想", not ks.held_states.has("kensei_kongxiang"))
	ks.set_sword_qi(100)
	_start_own_turn(tm, ks)
	_check("剑气 100：回合开始进入空想", ks.held_states.has("kensei_kongxiang"))

	# 获得改失去，不产生获得事件。
	var kinds: Array[String] = []
	var on_qi: Callable = func(_u: Unit, kind: String, _req: int, _act: int, _src: String) -> void:
		kinds.append(kind)
	ks.sword_qi_changed.connect(on_qi)
	var actual: int = ks.gain_sword_qi(25, "test")
	ks.sword_qi_changed.disconnect(on_qi)
	_eq("获得 25 改为失去 25：100 → 75", ks.sword_qi, 75)
	_eq("返回实际变化 −25", actual, -25)
	_eq("事件是失去，不是获得", kinds, ["lose"])
	_eq("实际损失 25 → 1 层剑痕", ks.held_states.stacks("kensei_jianhen"), 1)

	# 透支：剑气不足也能发动，发动后剑气降至 0；实际损失计入进度。
	_enter_action_phase(tm, ks)
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.set_sword_qi(30)
	_check("空想期间允许透支", ks.allows_qi_overdraft())
	_eq("居合（60 剑气）在剑气 30 时可用", tm._build_skill_entry(ks, "kensei_juhe").get("available"), true)
	_check("校验也放行", bool(GameAction.validate_skill_usage(ks, tm._get_skill_data("kensei_juhe")).get("ok", false)))
	_cast(tm, ks, "kensei_juhe", Vector2i(6, 5), tm.grid.get_unit_at(Vector2i(6, 5)))
	_eq("透支发动后剑气降至 0", ks.sword_qi, 0)
	_check("剑气降至 0 不提前结束空想", ks.held_states.has("kensei_kongxiang"))
	_eq("实际损失 30（累计 30）→ 第 2 层剑痕，余 5 点进度", ks.held_states.stacks("kensei_jianhen"), 2)
	_eq("进度 5", ks._qi_loss_scar_progress, 5)
	# 剑气为 0 时的反转没有实际损失，不计入。
	ks.gain_sword_qi(30, "test")
	_eq("剑气 0 时获得被反转：没有实际损失，进度不变", ks._qi_loss_scar_progress, 5)
	_leave_action_phase(tm)

	# 结束：清空剩余剑气，不计入剑痕；进度清空。
	ks._qi_loss_scar_progress = 20
	ks.set_sword_qi(40)
	var scars: int = ks.held_states.stacks("kensei_jianhen")
	tm.turn_manager.current_unit = ks
	tm._on_turn_ended(ks)
	_eq("空想结束：剩余剑气清空", ks.sword_qi, 0)
	_eq("清空的剑气不计入剑痕", ks.held_states.stacks("kensei_jianhen"), scars)
	_eq("不足一档的进度清空", ks._qi_loss_scar_progress, 0)
	_check("空想到本回合结束为止", not ks.held_states.has("kensei_kongxiang"))
	# 空想外获得剑气照常。
	ks.gain_sword_qi(10, "test")
	_eq("空想结束后获得剑气照常", ks.sword_qi, 10)
	# 上一次空想的残留进度（例如战斗在回合中途结束）不带进新的空想。
	ks._qi_loss_scar_progress = 20
	ks.set_sword_qi(100)
	_start_own_turn(tm, ks)
	_eq("进入空想时进度从零开始", ks._qi_loss_scar_progress, 0)
	tm.turn_manager.current_unit = ks
	tm._on_turn_ended(ks)
	# 剑痕满 5 层时不保存多出的进度。
	ks.held_states.apply("kensei_jianhen", 5, {"kind": "permanent"})
	ks.set_sword_qi(100)
	_start_own_turn(tm, ks)
	ks.lose_sword_qi(40, "test")
	_eq("剑痕满层：仍是 5", ks.held_states.stacks("kensei_jianhen"), 5)
	_eq("剑痕满层：进度不保存", ks._qi_loss_scar_progress, 0)
	tm.turn_manager.current_unit = ks
	tm._on_turn_ended(ks)


# ── ⑤ 剑痕 ───────────────────────────────────────────

func _test_scars(tm: Node, ks: Unit, enemy: Unit) -> void:
	print("\n[⑤] 剑痕")
	ks.held_states.remove("kensei_jianhen")
	var avoid0: int = ks.get_avoid_value(0)
	ks.held_states.apply("kensei_jianhen", 2, {"kind": "permanent"})
	_eq("2 层剑痕：闪避 +6", ks.get_avoid_value(0) - avoid0, 6)
	ks.stats.lck = 0
	tm._apply_skill_effect_to_unit(enemy, ks, {"effect_id": "stun", "chance": 100, "duration": 1}, true)
	_check("眩晕被免疫", ks.get_buff("stun") == null)
	_eq("免疫消耗 1 层剑痕", ks.held_states.stacks("kensei_jianhen"), 1)
	# 免疫在抵抗判定之前：施加率 0（本来必定施加失败）的控制也先消耗 1 层。
	ks.held_states.apply("kensei_jianhen", 1, {"kind": "permanent"})
	tm._apply_skill_effect_to_unit(enemy, ks, {"effect_id": "stun", "chance": 0, "duration": 1}, true)
	_eq("抵抗判定之前就消耗剑痕（施加率 0 的控制也耗 1 层）", ks.held_states.stacks("kensei_jianhen"), 1)
	tm._apply_skill_effect_to_unit(enemy, ks, {"effect_id": "defense_down", "chance": 100, "duration": 1, "value": -1}, true)
	_eq("非控制效果不消耗剑痕", ks.held_states.stacks("kensei_jianhen"), 1)
	var dd: Variant = ks.get_buff("defense_down")
	if dd != null:
		ks.remove_buff(dd)


# ── ⑥ 空想剑 ─────────────────────────────────────────

func _test_kongxiangjian(tm: Node, ks: Unit, enemy: Unit) -> void:
	print("\n[⑥] 空想剑")
	ks.held_states.remove("kensei_jianhen")
	ks.held_states.remove("kensei_kongxiang")
	_enter_action_phase(tm, ks)
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	var data: Dictionary = tm._get_skill_data("kensei_kongxiangjian")
	_check("没有空想时不可用", not bool(GameAction.validate_skill_usage(ks, data).get("ok", true)))
	_eq("没有空想时被动槽是心眼·梦", tm._build_passive_entry(ks).get("name"), "心眼·梦")

	ks.set_sword_qi(100)
	_start_own_turn(tm, ks)
	_enter_action_phase(tm, ks)
	var slot: Dictionary = tm._build_passive_entry(ks)
	_eq("空想期间被动槽换成空想剑", slot.get("skill_id"), "kensei_kongxiangjian")
	_eq("空想剑可用", slot.get("available"), true)
	_check("空想剑不是被动条目（可以点）", not bool(slot.get("is_passive", false)))

	# 命中后补齐全部印记；纯粹伤害无视防御：给敌人很高的防御，伤害仍是「力量 + 威力 1」。
	ks.clear_marks()
	ks.marks["心"] = true
	enemy.stats.def_attr = 500
	var expected_damage: int = ks.get_effective_stat("STR") + 1
	var hp_before: int = enemy.stats.hp
	_cast(tm, ks, "kensei_kongxiangjian", enemy.grid_position, enemy)
	_eq("纯粹伤害无视防御：伤害 = 力量 + 1", hp_before - enemy.stats.hp, expected_damage)
	enemy.stats.def_attr = 0
	_eq("命中后补齐全部印记", ks.get_mark_count(), 3)
	_check("消耗迅捷行动", ks.swift_used)

	# 5 层剑痕：消耗 5 层，结算后恢复 1 次标准动作（以已消耗的为限）。
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.standard_used = true
	ks.held_states.apply("kensei_jianhen", 5, {"kind": "permanent"})
	_cast(tm, ks, "kensei_kongxiangjian", enemy.grid_position, enemy)
	_eq("5 层剑痕被消耗", ks.held_states.stacks("kensei_jianhen"), 0)
	_check("恢复 1 次标准动作", not ks.standard_used)
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.held_states.apply("kensei_jianhen", 5, {"kind": "permanent"})
	_cast(tm, ks, "kensei_kongxiangjian", enemy.grid_position, enemy)
	_eq("标准动作没用过：仍消耗 5 层剑痕", ks.held_states.stacks("kensei_jianhen"), 0)
	_check("标准动作没用过：不多给（仍未用）", not ks.standard_used)
	# 未命中也照样消耗与恢复（不以命中为条件）。
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.standard_used = true
	ks.held_states.apply("kensei_jianhen", 5, {"kind": "permanent"})
	var saved_dex: int = ks.stats.dex
	ks.stats.dex = 0
	enemy.stats.spd = 500
	hp_before = enemy.stats.hp
	_cast(tm, ks, "kensei_kongxiangjian", enemy.grid_position, enemy)
	_eq("前提：本次未命中", enemy.stats.hp, hp_before)
	_eq("未命中也消耗 5 层剑痕", ks.held_states.stacks("kensei_jianhen"), 0)
	_check("未命中也恢复标准动作", not ks.standard_used)
	ks.stats.dex = saved_dex
	enemy.stats.spd = 0

	# 标准与迅捷都用完、只剩空想剑也用过——迅捷还剩时不结束回合。
	ks.reset_action_resources()
	ks.skill_cooldowns.clear()
	ks.standard_used = true
	_check("只剩空想剑可用：仍有可用的迅捷技能", tm._has_available_swift_skill(ks))
	tm.input_state = 2
	tm._resolve_post_action_phase()
	_eq("标准动作后进入迅捷阶段", tm.input_state, 5)
	_leave_action_phase(tm)
	tm.turn_manager.current_unit = ks
	tm._on_turn_ended(ks)
	_check("回合结束后空想结束", not ks.held_states.has("kensei_kongxiang"))
	await process_frame


# ── 工具 ─────────────────────────────────────────────

func _start_own_turn(tm: Node, ks: Unit) -> void:
	tm.turn_manager.current_unit = ks
	tm._on_turn_started(ks)


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
