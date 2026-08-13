extends SceneTree
## 技能栏修复回归（2026-06-29 用户眼验反馈）：
##   ① 心眼被动条目（最左、is_passive、不可点、available、有描述；非剑圣无此条目）
##   ② slot_swap 数据契约（拔刀=slot_swap_provider、招架→拔刀）
##   ③ 技能条目携带 description + cooldown_max（悬停介绍 + 径向冷却所需）
##   ④ _get_skill_entries 构成：心眼最左 + 印记未满时无独立拔刀槽（拔刀不常驻第5技能）
##   ⑤ SkillBar._compose_tooltip：可用/不可用/被动 都给「技能名+描述」
## 视觉（径向转圈冷却 / 心眼 P 角标 / 悬停弹窗 / 浮窗底部避让）= 编辑器人眼核验。
##
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/test_swordsman_skillbar.gd ；退出码 0 = 全过。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_swordsman_skillbar (技能栏修复回归) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	var scene: Node = load("res://scenes/tactical/TacticalScene.tscn").instantiate()
	root.add_child(scene)
	var tm: Object = scene.tactical_manager
	var sword: Unit = _find_kensei(tm)
	_check("场景存在剑圣", sword != null)
	if sword == null:
		_finish(scene)
		return

	# ① 心眼被动条目（building block，不依赖回合态）
	var passive: Dictionary = tm._build_passive_entry(sword)
	_check("心眼条目非空（剑圣 _qi_max>0）", not passive.is_empty())
	_eq("心眼 is_passive=true", bool(passive.get("is_passive", false)), true)
	_eq("心眼 name=心眼", str(passive.get("name", "")), "心眼")
	_eq("心眼 skill_id=swordsman_xinyan", str(passive.get("skill_id", "")), "swordsman_xinyan")
	_eq("心眼 available=true（被动恒亮）", bool(passive.get("available", false)), true)
	_check("心眼 description 非空", str(passive.get("description", "")) != "")
	var enemy: Unit = _find_enemy(tm)
	if enemy != null:
		_check("非剑圣单位 _build_passive_entry 为空", tm._build_passive_entry(enemy).is_empty())

	# ② slot_swap 数据契约
	_eq("拔刀 slot_swap_provider=true",
		bool(tm._get_skill_data("swordsman_badao").get("slot_swap_provider", false)), true)
	_eq("招架 slot_swap_target=拔刀",
		str(tm._get_skill_data("swordsman_zhaojia").get("slot_swap_target", "")), "swordsman_badao")

	# ③ 条目携带 description + cooldown_max（居合 cd3 / 斩击 cd0）
	var juhe_entry: Dictionary = tm._build_skill_entry(sword, "swordsman_juhe")
	_check("居合条目含 description", str(juhe_entry.get("description", "")) != "")
	_eq("居合 cooldown_max=3", int(juhe_entry.get("cooldown_max", -1)), 3)
	_eq("斩击 cooldown_max=0", int(tm._build_skill_entry(sword, "swordsman_zhanji").get("cooldown_max", -1)), 0)

	# ④ _get_skill_entries 构成（需剑圣为行动单位；印记未满）
	sword.clear_marks()
	var entries: Array = tm._get_skill_entries()
	if entries.size() > 0:
		_eq("首条目=心眼被动（最左）", bool(entries[0].get("is_passive", false)), true)
		var ids: Array = []
		for e: Dictionary in entries:
			ids.append(str(e.get("skill_id", "")))
		_check("含斩击槽", "swordsman_zhanji" in ids)
		_check("含招架槽（印记未满）", "swordsman_zhaojia" in ids)
		_check("含居合槽", "swordsman_juhe" in ids)
		_check("无独立拔刀槽（印记未满，不常驻第5技能）", not ("swordsman_badao" in ids))
	else:
		print("  · 注：当前非剑圣行动态，_get_skill_entries 空，跳过构成断言（building block 已覆盖逻辑）")

	# ⑤ SkillBar._compose_tooltip：可用/不可用/被动 都给介绍
	var bar: Variant = SkillBar.new()
	var tip_ok: String = bar._compose_tooltip(
		{"name": "斩击", "description": "距1，100%物理。"}, true, false)
	_check("可用技能 tooltip 含技能名", "斩击" in tip_ok)
	_check("可用技能 tooltip 含描述", "物理" in tip_ok)
	var tip_no: String = bar._compose_tooltip(
		{"name": "拔刀", "description": "满3印记触发。", "reason": "印记不足"}, false, false)
	_check("不可用技能 tooltip 仍含描述", "满3印记触发" in tip_no)
	_check("不可用技能 tooltip 含原因", "印记不足" in tip_no)
	var tip_p: String = bar._compose_tooltip(
		{"name": "心眼", "description": "每点剑气+1%暴击。"}, true, true)
	_check("被动 tooltip 标注（被动）", "（被动）" in tip_p)
	bar.free()

	# ⑥ forecast 数据契约：targets / target_hp 字段（counter_* 已随自动反击移除）
	_test_forecast_data_contract(tm, sword)

	# ⑦ 迅捷可用性判定必须走槽位替换（2026-08-13 修）
	_test_swift_availability_respects_slot_swap(tm, sword)

	# ⑧ 心眼被动说明文字与实际口径一致（2026-08-13 修）
	_test_passive_description_matches_behavior(tm, sword)

	_finish(scene)


# ── ⑥ forecast 数据契约 ─────────────────────────────────
# 验证 _build_attack_forecast_for_hover 和 _build_skill_forecast_for_hover
# 都输出 targets/target_hp/target_hp_max 字段（counter_* 已随自动反击移除，2026-07-11）。
# AoE 场景（拔刀：主目标 + 溅射目标）验证 targets.size() > 1。
func _test_forecast_data_contract(tm: Object, sword: Unit) -> void:
	print("\n[⑥] forecast 数据契约：targets/target_hp")

	# --- 单体攻击 forecast（ATTACK_TARGETING 态）---
	_clear_all_occupancy(tm)
	var origin: Vector2i = Vector2i(0, 0)
	var atk_pos: Vector2i = Vector2i(1, 0)
	var enemy_a: Unit = _find_enemy(tm)
	if enemy_a == null:
		_check("存在敌方单位（攻击forecast）", false)
		return
	enemy_a.stats.max_hp = 100
	enemy_a.stats.hp = 80
	enemy_a.stats.spd = 0
	enemy_a.stats.lck = 0
	enemy_a.stats.def_attr = 0
	_force_place(tm, sword, origin)
	_force_place(tm, enemy_a, atk_pos)
	sword.standard_used = false
	sword.movement_used = false
	sword.swift_used = false

	tm.current_unit = sword
	tm.input_state = 4  # InputState.ATTACK_TARGETING
	var atk_cells: Array[Vector2i] = [atk_pos]
	tm._attack_cells = atk_cells

	var fc_atk: Dictionary = tm._build_attack_forecast_for_hover(atk_pos)
	_check("攻击 forecast 非空", not fc_atk.is_empty())
	if not fc_atk.is_empty():
		_check("攻击 forecast 含 targets 字段", fc_atk.has("targets"))
		var atk_targets: Array = fc_atk.get("targets", [])
		_check("攻击 targets.size()==1", atk_targets.size() == 1)
		if atk_targets.size() > 0:
			var t0: Dictionary = atk_targets[0]
			_check("攻击 targets[0] 含 world", t0.has("world"))
			_check("攻击 targets[0] 含 damage", t0.has("damage"))
			_check("攻击 targets[0] 含 damage_type", t0.has("damage_type"))
			_check("攻击 targets[0] 含 is_primary", t0.has("is_primary"))
			_check("攻击 targets[0].is_primary==true", bool(t0.get("is_primary", false)))
		_check("攻击 forecast 含 target_hp", fc_atk.has("target_hp"))
		_check("攻击 forecast 含 target_hp_max", fc_atk.has("target_hp_max"))
		_eq("攻击 target_hp==80", int(fc_atk.get("target_hp", -1)), 80)
		_eq("攻击 target_hp_max==100", int(fc_atk.get("target_hp_max", -1)), 100)
		_check("攻击 forecast 无 counter_damage（自动反击已移除）",
			not fc_atk.has("counter_damage"))

	# --- AoE 技能 forecast（拔刀：主目标 + 溅射目标）---
	_clear_all_occupancy(tm)
	var main_pos: Vector2i = Vector2i(1, 0)
	var splash_pos: Vector2i = Vector2i(2, 0)
	var main_e: Unit = _find_enemy(tm)
	var splash_e: Unit = _find_enemy_other(tm, main_e)
	if main_e == null or splash_e == null:
		_check("存在两个敌方单位（AoE forecast）", false)
		return
	for e: Unit in [main_e, splash_e]:
		e.stats.spd = 0
		e.stats.lck = 0
		e.stats.max_hp = 9999
		e.stats.hp = 9999
		e.stats.def_attr = 0
		e.stats.res = 0
	_force_place(tm, sword, origin)
	_force_place(tm, main_e, main_pos)
	_force_place(tm, splash_e, splash_pos)

	tm.current_unit = sword
	tm.input_state = 3  # InputState.SKILL_TARGETING
	tm._selected_skill_id = "swordsman_badao"
	tm._targeting_direction = Vector2i.ZERO
	sword.standard_used = false
	sword.movement_used = false
	sword.swift_used = false
	sword.skill_cooldowns.clear()
	sword.set_sword_qi(9)
	sword.clear_marks()
	sword.marks["心"] = true
	sword.marks["道"] = true
	sword.marks["势"] = true
	var badao_cells: Array[Vector2i] = [main_pos]
	tm._attack_cells = badao_cells

	var fc_aoe: Dictionary = tm._build_skill_forecast_for_hover(main_pos)
	_check("AoE 技能 forecast 非空", not fc_aoe.is_empty())
	if not fc_aoe.is_empty():
		_check("AoE forecast 含 targets 字段", fc_aoe.has("targets"))
		var aoe_targets: Array = fc_aoe.get("targets", [])
		_check("AoE targets.size() > 1（含溅射）", aoe_targets.size() > 1)
		var has_primary: bool = false
		for t: Variant in aoe_targets:
			if t is Dictionary:
				_check("AoE targets 每项含 world", (t as Dictionary).has("world"))
				_check("AoE targets 每项含 damage", (t as Dictionary).has("damage"))
				_check("AoE targets 每项含 is_primary", (t as Dictionary).has("is_primary"))
				if bool((t as Dictionary).get("is_primary", false)):
					has_primary = true
		_check("AoE targets 含 is_primary==true 的主目标", has_primary)
		_check("AoE forecast 含 target_hp", fc_aoe.has("target_hp"))
		_check("AoE forecast 含 target_hp_max", fc_aoe.has("target_hp_max"))
		_check("AoE forecast 无 counter_damage（自动反击已移除）",
			not fc_aoe.has("counter_damage"))


# ── ⑦ 迅捷可用性判定必须走槽位替换 ─────────────────────
# `_resolve_post_action_phase` 用 `_has_available_swift_skill` 决定标准动作用完之后
# 是进迅捷阶段还是直接结束回合。它必须与 `_get_skill_entries` 看到同一批槽 ——
# 剑圣印记满 3 时招架槽已经换成拔刀（standard），此时不应再判「有迅捷可用」，
# 否则玩家被送进一个一个技能都点不出来的阶段。
#
# 第三条断言（剑士对照）是这组的关键：它把「修复靠槽位替换」与「修复靠 is_marks_full
# 一刀切」区分开 —— 剑士没有拔刀、满印也不替换，所以它必须仍然判为有迅捷可用。
func _test_swift_availability_respects_slot_swap(tm: Object, sword: Unit) -> void:
	print("\n[⑦] 迅捷可用性判定走槽位替换（满印时招架槽已是拔刀）")
	var zhaojia: Dictionary = tm._get_skill_data("swordsman_zhaojia")
	var trig: String = str(zhaojia.get("slot_swap_trigger", ""))
	var tgt: String = str(zhaojia.get("slot_swap_target", ""))

	sword.set_sword_qi(50)      # 招架 qi_cost=10，够用
	sword.skill_cooldowns.clear()
	sword.swift_used = false
	sword.clear_marks()
	_check("前提：剑圣 skill_ids 含拔刀（替换目标确实在表内）",
		sword.skill_ids.has("swordsman_badao"))
	_check("印记未满 → 判为有迅捷可用（招架在槽上）",
		tm._has_available_swift_skill(sword))

	sword.marks["心"] = true
	sword.marks["道"] = true
	sword.marks["势"] = true
	_check("前提：印记确实满了", sword.is_marks_full())
	_eq("前提：招架槽此刻显示的是拔刀",
		sword.get_visible_skill_id("swordsman_zhaojia", trig, tgt), "swordsman_badao")
	_check("印记满 → 判为无迅捷可用（招架槽已变拔刀，standard）",
		not tm._has_available_swift_skill(sword))

	# 剑士对照：拔刀不在其 skill_ids 内 → 满印也不替换 → 招架仍在槽上 → 仍有迅捷可用。
	var dl: Object = load("res://scripts/data/data_loader.gd").new()
	dl.load_all()
	var mm_class: Dictionary = dl.classes.get("myrmidon", {})
	_check("myrmidon 职业数据存在", not mm_class.is_empty())
	if not mm_class.is_empty():
		var mm: Unit = load("res://scenes/tactical/Unit.tscn").instantiate()
		root.add_child(mm)
		mm.setup(mm_class)
		mm.set_sword_qi(50)
		mm.skill_cooldowns.clear()
		mm.swift_used = false
		mm.marks["心"] = true
		mm.marks["道"] = true
		mm.marks["势"] = true
		_check("前提：剑士 skill_ids 不含拔刀", not mm.skill_ids.has("swordsman_badao"))
		_check("前提：剑士印记同样能满", mm.is_marks_full())
		_check("剑士印记满 → 仍判为有迅捷可用（槽位不替换，招架还在）",
			tm._has_available_swift_skill(mm))
		mm.free()
	dl.free()

	sword.clear_marks()


# ── ⑧ 心眼被动说明文字与实际口径一致 ───────────────────
# 说明文字是玩家据以做剑气经营决策的唯一信息源，写错的代价不是「文案不好看」，
# 而是把决策带向反方向。2026-08-13 修前它写的是「每点剑气 +2% 暴击率；剑气达到 50
# 时速度 +2」，三处都不对（倍率错 10 倍 / 分档方向反了 / 缺印记加成整句）。
func _test_passive_description_matches_behavior(tm: Object, sword: Unit) -> void:
	print("\n[⑧] 心眼被动说明文字 vs 实际口径")
	var desc: String = str(tm._build_passive_entry(sword).get("description", ""))
	_check("说明非空", desc != "")
	# ① 暴击：每 qi_per_crit_pct 点剑气 +crit_per_qi 点（不是每 1 点 +N%）。
	_check("含「每 %d 点剑气」" % sword._xinyan_qi_per_crit_pct,
		("每 %d 点剑气" % sword._xinyan_qi_per_crit_pct) in desc, desc)
	_check("含「暴击 +%d」" % sword._xinyan_crit_per_qi,
		("暴击 +%d" % sword._xinyan_crit_per_qi) in desc, desc)
	_check("不再出现旧文案的「每点剑气」", not ("每点剑气" in desc), desc)
	_check("不再把暴击说成百分比（无「暴击率」字样）", not ("暴击率" in desc), desc)
	# ② 分档方向：≤ 阈值给低气段属性，> 阈值给高气段属性。方向反了是修复前的主要错误。
	var threshold_qi: int = sword._qi_max * sword._xinyan_qi_ratio_threshold_pct / 100
	_check("含「不高于 %d」（低气段判据）" % threshold_qi,
		("不高于 %d" % threshold_qi) in desc, desc)
	_check("含「高于 %d」（高气段判据）" % threshold_qi,
		("高于 %d" % threshold_qi) in desc, desc)
	_check("低气段给的是速度（SPD）", "速度 +%d" % sword._xinyan_low_qi_stat_bonus in desc, desc)
	_check("高气段给的是技巧（DEX）", "技巧 +%d" % sword._xinyan_high_qi_stat_bonus in desc, desc)
	# 方向断言：「不高于 N」必须排在「速度」之前、「高于 N」排在「技巧」之前。
	# 只查两个词都在场是抓不到方向写反的 —— 反着写这两个词照样都在。
	_check("方向正确：低气段那句在前、给速度",
		desc.find("不高于 %d 时 速度" % threshold_qi) >= 0
		or desc.find("不高于 %d 时 %s" % [threshold_qi, "速度"]) >= 0, desc)
	# ③ 印记持有加成整句（剑圣 _mark_max>0）。
	if sword._mark_max > 0:
		_check("含印记持有加成：心 → 技巧", ("心 → 技巧 +%d" % sword._mark_dex_bonus) in desc, desc)
		_check("含印记持有加成：道 → 速度", ("道 → 速度 +%d" % sword._mark_spd_bonus) in desc, desc)
		_check("含印记持有加成：势 → 力量", ("势 → 力量 +%d" % sword._mark_str_bonus) in desc, desc)


func _find_enemy_other(tm: Object, exclude: Unit) -> Unit:
	for u: Unit in tm.units:
		if u.faction == "enemy" and u.stats.is_alive() and u != exclude:
			return u
	return null


func _clear_all_occupancy(tm: Object) -> void:
	for u: Unit in tm.units:
		var cell: Object = tm.grid.get_cell(u.grid_position)
		if cell != null and cell.occupant == u:
			cell.occupant = null


func _force_place(tm: Object, unit: Unit, pos: Vector2i) -> void:
	var old_cell: Object = tm.grid.get_cell(unit.grid_position)
	if old_cell != null and old_cell.occupant == unit:
		old_cell.occupant = null
	tm.grid.place_unit(unit, pos)
	unit.position = tm.grid.grid_to_world(pos)


func _finish(scene: Node) -> void:
	if is_instance_valid(scene):
		scene.free()
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  ✗ " + f)
	else:
		print("OK")
	quit(0 if _fail == 0 else 1)


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		_fails.append(name + ("  [" + detail + "]" if detail != "" else ""))
		print("  ✗ " + name + ("  [" + detail + "]" if detail != "" else ""))


func _eq(name: String, actual: Variant, expected: Variant) -> void:
	_check(name, actual == expected, "期望 %s 实际 %s" % [str(expected), str(actual)])


func _find_kensei(tm: Object) -> Unit:
	for u: Unit in tm.units:
		if u.unit_id == "kensei":
			return u
	return null


func _find_enemy(tm: Object) -> Unit:
	for u: Unit in tm.units:
		if u.faction == "enemy" and u.stats.is_alive():
			return u
	return null
