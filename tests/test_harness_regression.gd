extends SceneTree
## 测试场 harness 回归加固（2026-06-30，次要任务）
##   ① forecast 多目标边界：拔刀 AoE 汇总 hit_count/total/splash；0/1/3 目标 + 单体居合。
##   ② 调试控制台按钮状态：暴击三态 / 木桩三态 循环与回绕，按钮文案随状态同步。
##   ③ 木桩多轮 round_ended 防漂移：regen 多轮回满不漂移、revive 存活不重复生成、死亡原位复活。
##
## 经正式 TacticalScene 实例化；坑规避：断言放 _process 首帧；tm/scene 用 Object/鸭子访问。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false

const ST_SKILL_TARGETING: int = 3  # InputState.SKILL_TARGETING（IDLE0/选中1/ACTION_PHASE2/SKILL_TARGETING3）


func _initialize() -> void:
	print("=== test_harness_regression (forecast多目标 + 控制台按钮 + 木桩防漂移) ===")


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
	if tm.turn_manager != null:
		tm.turn_manager.stop()

	_test_forecast_multitarget(scene, tm)
	_test_console_button_state(scene, tm)
	_test_dummy_round_ended_drift(scene, tm)

	_finish(scene)


# ── ① forecast 多目标边界 ─────────────────────────────────

func _test_forecast_multitarget(scene: Node, tm: Object) -> void:
	print("\n[①] forecast 多目标边界（拔刀 AoE 汇总 / 0/1/3 目标）")
	var sword: Unit = _find(tm, "swordsman")
	if sword == null:
		_check("场景含剑圣", false)
		return
	# 簇：主(4,3) + 正交两枚(4,2)(4,4)，剑圣站(3,3)
	# 用 goblin_melee（无 dummy_mode）避免污染 ③ 的 regen/revive 计数。
	var main: Unit = tm.spawn_unit("goblin_melee", Vector2i(4, 3), "enemy")
	var nb1: Unit = tm.spawn_unit("goblin_melee", Vector2i(4, 2), "enemy")
	var nb2: Unit = tm.spawn_unit("goblin_melee", Vector2i(4, 4), "enemy")
	if main == null or nb1 == null or nb2 == null:
		_check("PACK 簇生成成功", false)
		return
	for d: Unit in [main, nb1, nb2]:
		d.stats.spd = 0
		d.stats.lck = 0
		d.stats.max_hp = 9999
		d.stats.hp = 9999
	_place_at(tm, sword, Vector2i(3, 3))
	# 满印记（势→拔刀吃 STR）+ 充足剑气
	sword.set_sword_qi(8)
	sword.clear_marks()
	sword.marks["心"] = true
	sword.marks["道"] = true
	sword.marks["势"] = true

	tm.current_unit = sword
	tm.input_state = ST_SKILL_TARGETING

	# (a) 拔刀命中 3 目标
	tm._selected_skill_id = "swordsman_badao"
	_set_attack_cells(tm, [Vector2i(4, 3)])
	var fc3: Dictionary = tm._build_skill_forecast_for_hover(Vector2i(4, 3))
	_check("拔刀 forecast 非空", not fc3.is_empty())
	_eq("拔刀 hit_count==3（主+2溅射）", int(fc3.get("hit_count", 0)), 3)
	var tlist: Array = fc3.get("targets", [])
	_eq("拔刀 targets 列表 3 条", tlist.size(), 3)
	# total == 各目标伤害之和
	var sum_t: int = 0
	var primary_dmg: int = 0
	var splash_dmg: int = -1
	var primary_count: int = 0
	for entry: Dictionary in tlist:
		sum_t += int(entry.get("damage", 0))
		if bool(entry.get("is_primary", false)):
			primary_dmg = int(entry.get("damage", 0))
			primary_count += 1
		else:
			splash_dmg = int(entry.get("damage", 0))
	_eq("拔刀 total_damage == 各目标之和", int(fc3.get("total_damage", -1)), sum_t)
	_eq("拔刀 恰一个主目标", primary_count, 1)
	_check("拔刀 溅射≈主目标 50%（误差≤1）",
		primary_dmg > 0 and splash_dmg > 0 and absi(splash_dmg * 2 - primary_dmg) <= 1)

	# (b) 单体居合 → hit_count==1，total==per_hit
	tm._selected_skill_id = "swordsman_juhe"
	_set_attack_cells(tm, [Vector2i(4, 3)])
	var fc1: Dictionary = tm._build_skill_forecast_for_hover(Vector2i(4, 3))
	_eq("居合 hit_count==1", int(fc1.get("hit_count", 0)), 1)
	_eq("居合 total==per_hit（单体）",
		int(fc1.get("total_damage", -1)), int(fc1.get("per_hit_damage", -2)))

	# (c) 区域无敌 → 返回空
	tm._selected_skill_id = "swordsman_badao"
	_set_attack_cells(tm, [Vector2i(7, 7)])
	var fc0: Dictionary = tm._build_skill_forecast_for_hover(Vector2i(7, 7))
	_check("拔刀 命中空地（区域无敌）→ forecast 为空", fc0.is_empty())

	# (d) 悬停格不在 _attack_cells → 空
	_set_attack_cells(tm, [Vector2i(4, 3)])
	var fc_out: Dictionary = tm._build_skill_forecast_for_hover(Vector2i(0, 0))
	_check("悬停格不在攻击范围 → forecast 为空", fc_out.is_empty())

	tm.input_state = 0  # 还原 IDLE
	tm.current_unit = null


# ── ② 控制台按钮状态 ─────────────────────────────────────

func _test_console_button_state(scene: Node, tm: Object) -> void:
	print("\n[②] 调试控制台按钮状态（暴击/木桩三态循环 + 按钮文案同步）")
	if scene._btn_crit == null or scene._btn_dummy == null or scene._btn_determinism == null:
		_check("控制台按钮已构建", false)
		return
	_check("控制台按钮已构建", true)

	# 暴击三态：随机→必暴→不暴→随机
	tm.debug_crit_mode = 0  # RANDOM
	_eq("暴击初态=随机", tm.debug_crit_mode_label(), "随机")
	tm.debug_cycle_crit_mode()
	_eq("暴击循环1=必暴", tm.debug_crit_mode_label(), "必暴")
	tm.debug_cycle_crit_mode()
	_eq("暴击循环2=不暴", tm.debug_crit_mode_label(), "不暴")
	tm.debug_cycle_crit_mode()
	_eq("暴击循环3回绕=随机", tm.debug_crit_mode_label(), "随机")

	# 木桩两态：不动→自动攻击→不动（只反击态已随自动反击移除，2026-07-11）
	tm.debug_dummy_behavior = 0  # IDLE
	_eq("木桩初态=不动", tm._debug_dummy_behavior_label(), "不动")
	tm.debug_cycle_dummy_behavior()
	_eq("木桩循环1=自动攻击", tm._debug_dummy_behavior_label(), "自动攻击")
	tm.debug_cycle_dummy_behavior()
	_eq("木桩循环2回绕=不动", tm._debug_dummy_behavior_label(), "不动")

	# 确定性开关 toggle
	tm.debug_deterministic = false
	tm.debug_toggle_deterministic()
	_check("确定性 toggle→开", tm.debug_deterministic)
	tm.debug_toggle_deterministic()
	_check("确定性 toggle→关", not tm.debug_deterministic)

	# 按钮文案随状态同步（_refresh_debug_overlay 镜像）
	tm.debug_crit_mode = 1   # 必暴
	tm.debug_dummy_behavior = 1  # 自动攻击（两态枚举 IDLE=0 / AUTO=1）
	tm.debug_deterministic = true
	scene._refresh_debug_overlay()
	_eq("暴击按钮文案同步", str(scene._btn_crit.text), "暴击态：必暴")
	_eq("木桩按钮文案同步", str(scene._btn_dummy.text), "木桩行为：自动攻击")
	_eq("确定性按钮文案同步", str(scene._btn_determinism.text), "确定性：开")
	# 还原默认
	tm.debug_crit_mode = 0
	tm.debug_dummy_behavior = 0
	tm.debug_deterministic = false


# ── ③ 木桩多轮 round_ended 防漂移 ─────────────────────────

func _test_dummy_round_ended_drift(scene: Node, tm: Object) -> void:
	print("\n[③] 木桩多轮 round_ended 防漂移（regen 回满不漂移 / revive 不重复+死亡复活）")
	var regen: Unit = _find(tm, "test_dummy_regen")
	var revive: Unit = _find(tm, "test_dummy_revive")
	if regen == null or revive == null:
		_check("场景含 regen + revive 木桩", false)
		return

	# regen：多轮损血→回合末回满，位置不漂移，单位数不增
	var regen_pos: Vector2i = regen.grid_position
	var ok_heal: bool = true
	var ok_pos: bool = true
	for round_i: int in range(5):
		regen.stats.hp = maxi(1, regen.stats.max_hp - 137)  # 模拟受击
		scene._process_test_dummies()
		if regen.stats.hp != regen.stats.max_hp:
			ok_heal = false
		if regen.grid_position != regen_pos:
			ok_pos = false
	_check("regen 5 轮均回满血（不漂移）", ok_heal)
	_check("regen 位置 5 轮不变", ok_pos)

	# revive 存活时多轮 → 不重复生成
	var revive_count_before: int = _count_alive(tm, "test_dummy_revive")
	for round_i: int in range(3):
		scene._process_test_dummies()
	var revive_count_after: int = _count_alive(tm, "test_dummy_revive")
	_eq("revive 存活时多轮不重复生成（存活数稳定）",
		revive_count_after, revive_count_before)

	# revive 死亡 → 回合末原位复活
	var revive_spawn: Vector2i = revive.grid_position
	var old_id: int = revive.get_instance_id()
	revive.stats.hp = 0  # 判死
	# 清原格占用（模拟死亡释放，让复活可落原位）
	var cell: Object = tm.grid.get_cell(revive_spawn)
	if cell != null and cell.occupant == revive:
		cell.occupant = null
	scene._process_test_dummies()
	var new_revive: Unit = _find_alive_at(tm, "test_dummy_revive", revive_spawn)
	_check("revive 死亡后回合末原位复活", new_revive != null)
	if new_revive != null:
		_check("复活的是新实例", new_revive.get_instance_id() != old_id)
		_check("复活实例存活", new_revive.stats.is_alive())
	_eq("复活后存活 revive 仅 1 个（无重复）",
		_count_alive(tm, "test_dummy_revive"), 1)


# ── 工具 ─────────────────────────────────────────────

func _check(name: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		_fails.append(name)
		print("  ✗ " + name)


func _eq(name: String, actual: Variant, expected: Variant) -> void:
	_check(name + ("  [期望 %s 实际 %s]" % [str(expected), str(actual)] if actual != expected else ""),
		actual == expected)


func _find(tm: Object, uid: String) -> Unit:
	for u: Unit in tm.units:
		if u.unit_id == uid:
			return u
	return null


func _count_alive(tm: Object, uid: String) -> int:
	var n: int = 0
	for u: Unit in tm.units:
		if u.unit_id == uid and u.stats.is_alive():
			n += 1
	return n


func _find_alive_at(tm: Object, uid: String, pos: Vector2i) -> Unit:
	for u: Unit in tm.units:
		if u.unit_id == uid and u.stats.is_alive() and u.grid_position == pos:
			return u
	return null


func _set_attack_cells(tm: Object, cells: Array) -> void:
	var typed: Array[Vector2i] = []
	for c: Vector2i in cells:
		typed.append(c)
	tm._attack_cells = typed


func _place_at(tm: Object, mover: Unit, dest: Vector2i) -> void:
	var old_cell: Object = tm.grid.get_cell(mover.grid_position)
	if old_cell != null and old_cell.occupant == mover:
		old_cell.occupant = null
	tm.grid.place_unit(mover, dest)


func _finish(scene: Node) -> void:
	if is_instance_valid(scene):
		scene.free()
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		for f: String in _fails:
			print("  ✗ " + f)
	else:
		print("OK")
	quit(0 if _fail == 0 else 1)
