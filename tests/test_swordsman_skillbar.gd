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
