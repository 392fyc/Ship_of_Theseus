extends SceneTree
## 剑圣 QA 实装回归（项①②③⑤）
##
## 覆盖：
##   ① 一闪路径 AoE：起点→落点沿途敌受伤；剑圣位移到落点
##   ② 一闪落点拒绝：无效落点 _can_confirm_skill_target=false + 零消耗
##   ⑤ 拔刀溅射：主目标满、邻格溅射≈50%（splash_damage_pct JSON 驱动）
##   ③ 技能 forecast：SKILL_TARGETING 下 _build_skill_forecast_for_hover 非空、
##      damage==preview 直算；多目标 area → hit_count>1 且 total==主满+溅射50%
##
## 坑规避：断言放 _process 首帧；经 TacticalScene.tscn.instantiate 走正式 spawn；
## 顶层不引用重 class_name（用整数枚举 input_state）。
##
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/test_swordsman_qa_impl.gd

const INPUT_SKILL_TARGETING: int = 3  # InputState.SKILL_TARGETING
const INPUT_ACTION_PHASE: int = 2     # InputState.ACTION_PHASE

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_swordsman_qa_impl (一闪路径/落点/拔刀溅射/forecast) ===")


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
	var sword: Unit = _find_swordsman(tm)
	if sword == null:
		_check("场景中存在剑圣单位", false)
		_finish(scene)
		return
	_check("场景中存在剑圣单位", true)

	_test_yishan_path_aoe(tm, sword)
	_test_yishan_landing_reject(tm, sword)
	_test_badao_splash(tm, sword)
	_test_skill_forecast(tm, sword)

	_finish(scene)


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


# ── ① 一闪路径 AoE ─────────────────────────────────────
# 剑圣(0,y)、中途敌(1,y)、落点空(2,y)共线 → 放一闪落(2,y)
#   → 中途敌(1,y)受伤、剑圣位移到(2,y)。
func _test_yishan_path_aoe(tm: Object, sword: Unit) -> void:
	print("\n[①] 一闪路径 AoE：起点→落点沿途敌受伤 + 位移到落点")
	# 清空棋盘占用并手工布阵于共线三格。
	_clear_all_occupancy(tm)
	var y: int = 0
	var origin: Vector2i = Vector2i(0, y)
	var mid: Vector2i = Vector2i(1, y)
	var landing: Vector2i = Vector2i(2, y)
	if not (tm.grid.is_valid(origin) and tm.grid.is_valid(mid) and tm.grid.is_valid(landing)):
		_check("共线三格有效", false)
		return
	# 路径格须可通行、落点空。
	if not _cells_passable(tm, [origin, mid, landing]):
		_check("共线三格可通行", false)
		return

	var mid_enemy: Unit = _find_enemy(tm)
	if mid_enemy == null:
		_check("存在敌方单位(一闪)", false)
		return
	# 木桩化中途敌：必命中、不死。
	# 注意：spd=0 且无地形/直接闪避修正 → 回避=0（R1.2：avoid = SPD×2 + 地形闪避 + 直接闪避修正），
	# 一闪(非必中)命中率钳到 100%，确定性命中。
	# LCK 只进 R1.3 暴击回避与 R1.5 减益抵抗，不参与命中与闪避（R1.2/R2.1）；
	# "受伤(HP下降)"断言与暴击无关，无需抑制暴击。
	mid_enemy.stats.spd = 0
	mid_enemy.stats.lck = 0
	mid_enemy.stats.max_hp = 9999
	mid_enemy.stats.hp = 9999
	mid_enemy.stats.def_attr = 0

	_force_place(tm, sword, origin)
	_force_place(tm, mid_enemy, mid)
	# 确保落点空
	var landing_cell: Object = tm.grid.get_cell(landing)
	_check("落点(2,y)为空", landing_cell != null and landing_cell.occupant == null)

	# 路径方向为 +x（cardinal），_targeting_direction 设为 (1,0)
	tm.input_state = INPUT_ACTION_PHASE
	tm._targeting_direction = Vector2i(1, 0)
	tm._selected_skill_id = "swordsman_yishan"
	sword.standard_used = false
	sword.movement_used = false
	sword.swift_used = false
	sword.skill_cooldowns.clear()
	sword.set_sword_qi(10)
	sword.clear_marks()

	var action: Object = tm._build_skill_action(sword, landing, null)
	_check("一闪 action 构造成功", action != null)
	if action == null:
		return
	# affected_cells 应含中途格(1,y)，不含起点(0,y)
	var cells: Array = tm._extract_cells_from_payload(action.data.get("affected_cells", []))
	_check("一闪 affected_cells 含中途格(1,y)", mid in cells)
	_check("一闪 affected_cells 不含起点(0,y)", not (origin in cells))
	_check("一闪 affected_cells 含落点(2,y)", landing in cells)

	var hp_before: int = mid_enemy.stats.hp
	var ok: bool = tm._execute_skill_action(action)
	_check("一闪 _execute_skill_action 返回 true", ok)
	_check("中途敌(1,y)受伤(HP下降)", mid_enemy.stats.hp < hp_before)
	_eq("剑圣位移到落点(2,y)", sword.grid_position, landing)


# ── ② 一闪落点拒绝 ─────────────────────────────────────
# 落点被占 → _can_confirm_skill_target=false；强行 _execute → 零消耗。
func _test_yishan_landing_reject(tm: Object, sword: Unit) -> void:
	print("\n[②] 一闪落点拒绝：无效落点不允许释放 + 零消耗")
	_clear_all_occupancy(tm)
	var y: int = 0
	var origin: Vector2i = Vector2i(0, y)
	var occupied: Vector2i = Vector2i(1, y)
	if not (tm.grid.is_valid(origin) and tm.grid.is_valid(occupied)):
		_check("拒绝测试格有效", false)
		return

	var blocker: Unit = _find_enemy(tm)
	if blocker == null:
		_check("存在敌方单位(拒绝)", false)
		return
	_force_place(tm, sword, origin)
	_force_place(tm, blocker, occupied)

	tm.current_unit = sword
	tm.input_state = INPUT_SKILL_TARGETING
	tm._selected_skill_id = "swordsman_yishan"
	tm._targeting_direction = Vector2i(1, 0)
	var reject_cells: Array[Vector2i] = [occupied]  # 把被占格纳入可点候选
	tm._attack_cells = reject_cells

	var can_confirm: bool = tm._can_confirm_skill_target(occupied)
	_check("落点被占 → _can_confirm_skill_target==false", not can_confirm)

	# 强行 _execute：备资源，记录前值，断言零消耗。
	sword.standard_used = false
	sword.movement_used = false
	sword.swift_used = false
	sword.skill_cooldowns.clear()
	sword.set_sword_qi(5)
	sword.clear_marks()
	var qi_before: int = sword.sword_qi
	var standard_before: bool = sword.standard_used
	var move_before: bool = sword.movement_used

	var action: Object = tm._build_skill_action(sword, occupied, blocker)
	if action == null:
		_check("拒绝: action 构造（应仍能构造，执行期拒绝）", false)
		return
	var ok: bool = tm._execute_skill_action(action)
	_check("无效落点 _execute_skill_action 返回 false", not ok)
	_eq("拒绝后 剑气未扣（仍为5）", sword.sword_qi, qi_before)
	_eq("拒绝后 standard_used 未变", sword.standard_used, standard_before)
	_eq("拒绝后 movement_used 未变", sword.movement_used, move_before)
	_check("拒绝后 一闪无冷却写入", not sword.skill_cooldowns.has("swordsman_yishan"))


# ── ⑤ 拔刀溅射 50% ─────────────────────────────────────
# 主目标(满)+邻格溅射目标 → 邻格受伤≈主目标的50%。
func _test_badao_splash(tm: Object, sword: Unit) -> void:
	print("\n[⑤] 拔刀溅射：邻格目标受伤≈主目标 50%（splash_damage_pct）")
	_clear_all_occupancy(tm)
	var origin: Vector2i = Vector2i(0, 0)
	var main_pos: Vector2i = Vector2i(1, 0)   # 落点=主目标
	var splash_pos: Vector2i = Vector2i(2, 0) # 主目标邻格（拔刀 diamond1 覆盖）
	if not _cells_valid(tm, [origin, main_pos, splash_pos]):
		_check("拔刀测试格有效", false)
		return

	var main_enemy: Unit = _find_enemy(tm)
	var splash_enemy: Unit = _find_enemy_other(tm, main_enemy)
	if main_enemy == null or splash_enemy == null:
		_check("存在两个敌方单位(拔刀)", false)
		return
	for e: Unit in [main_enemy, splash_enemy]:
		e.stats.spd = 0
		e.stats.lck = 0     # 木桩化；命中由上一行 spd=0 → 回避=0 保证，LCK 不进闪避(R1.2/R2.1)
		e.stats.dex = 0
		e.stats.max_hp = 9999
		e.stats.hp = 9999
		e.stats.def_attr = 0
		e.stats.res = 0
		e.crit_avoid_bonus = 999  # 压死暴击随机 → 执行路径确定性（仅本测试）

	_force_place(tm, sword, origin)
	_force_place(tm, main_enemy, main_pos)
	_force_place(tm, splash_enemy, splash_pos)

	tm.input_state = INPUT_ACTION_PHASE
	tm._selected_skill_id = "swordsman_badao"
	tm._targeting_direction = Vector2i.ZERO
	sword.standard_used = false
	sword.movement_used = false
	sword.swift_used = false
	sword.skill_cooldowns.clear()
	sword.set_sword_qi(20)
	# 拔刀 requires_marks=3 + mark_cost=3：给满 3 印记
	sword.clear_marks()
	sword.marks["心"] = true
	sword.marks["道"] = true
	sword.marks["势"] = true

	# 先用 preview_attack 做确定性比值断言（无随机暴击）：溅射==主目标 50%。
	var action: Object = tm._build_skill_action(sword, main_pos, main_enemy)
	_check("拔刀 action 构造成功", action != null)
	if action == null:
		return
	var main_payload: Dictionary = action.data.duplicate(true)
	main_payload["area_damage_multiplier"] = 1.0
	var splash_payload: Dictionary = action.data.duplicate(true)
	splash_payload["area_damage_multiplier"] = 0.5
	var main_pdata: Dictionary = tm._build_hostile_action_context(sword, main_enemy, main_payload)
	var splash_pdata: Dictionary = tm._build_hostile_action_context(sword, splash_enemy, splash_payload)
	var main_preview: int = int(
		DamageCalculator.preview_attack(sword, main_enemy, main_pdata).get("damage", 0))
	var splash_preview: int = int(
		DamageCalculator.preview_attack(sword, splash_enemy, splash_pdata).get("damage", 0))
	var expected_splash: int = int(round(float(main_preview) * 0.5))
	_check("preview 主目标伤害>0", main_preview > 0)
	_check("preview 溅射==主目标 50%（确定性比值）",
		absi(splash_preview - expected_splash) <= 1,
		"main=%d splash=%d expect=%d" % [main_preview, splash_preview, expected_splash])

	# 再跑真实执行：主目标与溅射目标 HP 均下降（命中），主目标降幅>溅射降幅。
	var main_before: int = main_enemy.stats.hp
	var splash_before: int = splash_enemy.stats.hp
	var ok: bool = tm._execute_skill_action(action)
	_check("拔刀 _execute_skill_action 返回 true", ok)
	var main_dmg: int = main_before - main_enemy.stats.hp
	var splash_dmg: int = splash_before - splash_enemy.stats.hp
	_check("主目标受伤>0", main_dmg > 0)
	_check("溅射目标受伤>0", splash_dmg > 0)
	_check("主目标降幅>=溅射降幅", main_dmg >= splash_dmg,
		"main=%d splash=%d" % [main_dmg, splash_dmg])


# ── ③ 技能 forecast ────────────────────────────────────
func _test_skill_forecast(tm: Object, sword: Unit) -> void:
	print("\n[③] 技能 forecast：居合单体 + 拔刀多目标汇总")
	# 单体（居合）forecast：damage==preview 直算
	_clear_all_occupancy(tm)
	var origin: Vector2i = Vector2i(0, 0)
	var target_pos: Vector2i = Vector2i(1, 0)
	if not _cells_valid(tm, [origin, target_pos]):
		_check("forecast 单体格有效", false)
		return
	var enemy: Unit = _find_enemy(tm)
	if enemy == null:
		_check("存在敌方(forecast单体)", false)
		return
	enemy.stats.spd = 0
	enemy.stats.lck = 0
	enemy.stats.max_hp = 9999
	enemy.stats.hp = 9999
	enemy.stats.def_attr = 0
	_force_place(tm, sword, origin)
	_force_place(tm, enemy, target_pos)

	tm.current_unit = sword
	tm.input_state = INPUT_SKILL_TARGETING
	tm._selected_skill_id = "swordsman_juhe"
	tm._targeting_direction = Vector2i.ZERO
	var juhe_cells: Array[Vector2i] = [target_pos]
	tm._attack_cells = juhe_cells

	var fc: Dictionary = tm._build_skill_forecast_for_hover(target_pos)
	_check("居合 forecast 非空", not fc.is_empty())
	_check("居合 forecast visible", bool(fc.get("visible", false)))
	_eq("居合 forecast hit_count==1", int(fc.get("hit_count", 0)), 1)
	# damage 应等于 preview 直算（居合必暴但 forecast 不计暴击 → 用 preview）
	var action: Object = tm._build_skill_action(sword, target_pos, enemy)
	var pdata: Dictionary = tm._build_hostile_action_context(sword, enemy, action.data)
	var preview: Dictionary = DamageCalculator.preview_attack(sword, enemy, pdata)
	_eq("居合 forecast damage==preview 直算",
		int(fc.get("damage", -1)), int(preview.get("damage", -2)))
	_eq("居合 forecast total_damage==damage",
		int(fc.get("total_damage", -1)), int(fc.get("damage", -2)))

	# 多目标（拔刀）forecast：hit_count>1，total==主满+溅射50%
	_clear_all_occupancy(tm)
	var main_pos: Vector2i = Vector2i(1, 0)
	var splash_pos: Vector2i = Vector2i(2, 0)
	if not _cells_valid(tm, [origin, main_pos, splash_pos]):
		_check("forecast 多目标格有效", false)
		return
	var main_e: Unit = _find_enemy(tm)
	var splash_e: Unit = _find_enemy_other(tm, main_e)
	if main_e == null or splash_e == null:
		_check("存在两个敌方(forecast多目标)", false)
		return
	for e2: Unit in [main_e, splash_e]:
		e2.stats.spd = 0
		e2.stats.lck = 0  # forecast 走 preview(确定性)，此处仅保持一致（回避=0 来自上一行 spd=0）
		e2.stats.max_hp = 9999
		e2.stats.hp = 9999
		e2.stats.def_attr = 0
		e2.stats.res = 0
	_force_place(tm, sword, origin)
	_force_place(tm, main_e, main_pos)
	_force_place(tm, splash_e, splash_pos)

	tm.current_unit = sword
	tm.input_state = INPUT_SKILL_TARGETING
	tm._selected_skill_id = "swordsman_badao"
	tm._targeting_direction = Vector2i.ZERO
	var badao_cells: Array[Vector2i] = [main_pos]
	tm._attack_cells = badao_cells

	var fc2: Dictionary = tm._build_skill_forecast_for_hover(main_pos)
	_check("拔刀 forecast 非空", not fc2.is_empty())
	_check("拔刀 forecast hit_count>1", int(fc2.get("hit_count", 0)) > 1)

	# 手算期望：主目标满 preview + 溅射目标 50% preview
	var act2: Object = tm._build_skill_action(sword, main_pos, main_e)
	var main_payload: Dictionary = act2.data.duplicate(true)
	main_payload["area_damage_multiplier"] = 1.0
	var splash_payload: Dictionary = act2.data.duplicate(true)
	splash_payload["area_damage_multiplier"] = 0.5
	var main_pdata: Dictionary = tm._build_hostile_action_context(sword, main_e, main_payload)
	var splash_pdata: Dictionary = tm._build_hostile_action_context(sword, splash_e, splash_payload)
	var main_dmg: int = int(DamageCalculator.preview_attack(sword, main_e, main_pdata).get("damage", 0))
	var splash_dmg: int = int(DamageCalculator.preview_attack(sword, splash_e, splash_pdata).get("damage", 0))
	var expect_total: int = main_dmg + splash_dmg
	_eq("拔刀 forecast total_damage==主满+溅射50%",
		int(fc2.get("total_damage", -1)), expect_total)
	_eq("拔刀 forecast damage==total_damage",
		int(fc2.get("damage", -1)), int(fc2.get("total_damage", -2)))


# ── 工具 ─────────────────────────────────────────────

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


func _find_swordsman(tm: Object) -> Unit:
	for u: Unit in tm.units:
		if u.unit_id == "swordsman":
			return u
	return null


func _find_enemy(tm: Object) -> Unit:
	for u: Unit in tm.units:
		if u.faction == "enemy" and u.stats.is_alive():
			return u
	return null


func _find_enemy_other(tm: Object, exclude: Unit) -> Unit:
	for u: Unit in tm.units:
		if u.faction == "enemy" and u.stats.is_alive() and u != exclude:
			return u
	return null


func _cells_valid(tm: Object, cells: Array) -> bool:
	for c: Vector2i in cells:
		if not tm.grid.is_valid(c):
			return false
	return true


func _cells_passable(tm: Object, cells: Array) -> bool:
	for c: Vector2i in cells:
		var cell: Object = tm.grid.get_cell(c)
		if cell == null or not cell.is_passable():
			return false
	return true


## 清空全棋盘占用（把所有单位从 grid 占用解绑，便于手工布阵）。
func _clear_all_occupancy(tm: Object) -> void:
	for u: Unit in tm.units:
		var cell: Object = tm.grid.get_cell(u.grid_position)
		if cell != null and cell.occupant == u:
			cell.occupant = null


## 强制把 unit 放到 pos（先清原占用，再 place_unit 更新占用+grid_position）。
func _force_place(tm: Object, unit: Unit, pos: Vector2i) -> void:
	var old_cell: Object = tm.grid.get_cell(unit.grid_position)
	if old_cell != null and old_cell.occupant == unit:
		old_cell.occupant = null
	tm.grid.place_unit(unit, pos)
	unit.position = tm.grid.grid_to_world(pos)
