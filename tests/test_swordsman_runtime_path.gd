extends SceneTree
## 剑圣运行时路径诊断（issue1 CD / issue2 剑气）
##
## 目的：经验性驱动完整运行时链路，区分逻辑bug vs 显示/认知bug：
##   - spawn 出来的剑圣 _qi_max 是否 >0（资源初始化）
##   - 斩击经 _build_skill_action→_execute_skill_action→_execute_hostile_action 命中后 sword_qi +1
##   - 一闪施放后 skill_cooldowns 写入 cd=3，reset_turn_state() 逐回合 -1 直到移除
##   - 居合击杀（可选）返气 + cd-1
##
## 坑规避：断言放 _process 首帧；经 TacticalScene.tscn.instantiate 走正式 spawn；
## 不在主循环顶层引用会触发早期类缓存编译失败的 class_name（用整数枚举）。
##
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/test_swordsman_runtime_path.gd

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_swordsman_runtime_path (运行时路径诊断) ===")


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

	# ── 0. spawn-init：运行期 _qi_max 是否 >0 ──
	_eq("spawn 剑圣 _qi_max>0（资源已初始化）", sword._qi_max, 100)
	_eq("spawn 剑圣 sword_qi 初始==0", sword.sword_qi, 0)

	_test_zhanji_qi_runtime(tm, sword)
	_test_yishan_cooldown_runtime(tm, sword)
	_test_juhe_kill_optional(tm, sword)

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


# ── (a) 斩击产气：完整运行时链路 ─────────────────────────

func _test_zhanji_qi_runtime(tm: Object, sword: Unit) -> void:
	print("\n[a] 斩击 _build_skill_action→_execute_skill_action 命中 → +1 剑气")
	var enemy: Unit = _find_enemy(tm)
	if enemy == null:
		_check("存在敌方单位", false)
		return
	# 木桩化：必命中、不死
	enemy.stats.spd = 0
	enemy.stats.lck = 0
	enemy.stats.max_hp = 9999
	enemy.stats.hp = 9999
	enemy.stats.def_attr = 9999  # 高防→伤害压到下限（R1.1 加法层 max(0, ·)），9999 HP 确保不死

	# 把剑圣移到敌人相邻格（斩击 range diamond1-1）
	_place_adjacent(tm, sword, enemy)

	# 进入行动阶段，复位行动经济/资源
	tm.input_state = 2  # ACTION_PHASE
	sword.standard_used = false
	sword.movement_used = false
	sword.swift_used = false
	sword.skill_cooldowns.clear()
	sword.set_sword_qi(0)
	sword.clear_marks()

	# 经正式构造路径：设 _selected_skill_id → _build_skill_action → _execute_skill_action
	tm._selected_skill_id = "swordsman_zhanji"
	var action: Object = tm._build_skill_action(sword, enemy.grid_position, enemy)
	_check("斩击 action 构造成功", action != null)
	if action == null:
		return
	var qi_before: int = sword.sword_qi
	var ok: bool = tm._execute_skill_action(action)
	_check("斩击 _execute_skill_action 返回 true", ok)
	_eq("斩击命中 → sword_qi +10（运行时真实链路）", sword.sword_qi, qi_before + 10)
	# 剑圣=转职后职业 → 斩击命中随机获得一枚未持印记（mark_gain=1）
	_eq("斩击命中 → 得1印记（剑圣转职后，mark_gain=1）", sword.get_mark_count(), 1)


# ── (b) 一闪冷却：施放写 cd=3，reset_turn_state 逐回合 -1 ─────

func _test_yishan_cooldown_runtime(tm: Object, sword: Unit) -> void:
	print("\n[b] 一闪施放 → cd=3；reset_turn_state() 逐回合递减")
	tm.input_state = 2  # ACTION_PHASE（move 技能也须非 IDLE）
	sword.standard_used = false
	sword.movement_used = false
	sword.swift_used = false
	sword.skill_cooldowns.clear()
	sword.set_sword_qi(50)  # 一闪 qi_cost=10
	sword.clear_marks()

	# 一闪 displacement=true，落点须为空格；选剑圣的一个空邻格作落点
	var landing: Vector2i = _find_empty_neighbor(tm, sword.grid_position)
	if landing == Vector2i(-1, -1):
		_check("找到一闪空落点", false)
		return

	tm._selected_skill_id = "swordsman_yishan"
	var action: Object = tm._build_skill_action(sword, landing, null)
	_check("一闪 action 构造成功", action != null)
	if action == null:
		return
	_eq("一闪 payload.cooldown==3（来自 JSON）", int(action.data.get("cooldown", -1)), 3)

	var ok: bool = tm._execute_skill_action(action)
	_check("一闪 _execute_skill_action 返回 true", ok)
	# 施放后 consume_skill 写入冷却
	_eq("施放后 skill_cooldowns['swordsman_yishan']==3",
		sword.get_skill_cooldown("swordsman_yishan"), 3)
	_check("施放后 一闪不可用(cd>0)", not sword.is_skill_available("swordsman_yishan"))

	# 回合开始 reset_turn_state() → _tick_skill_cooldowns() -1
	sword.reset_turn_state()
	_eq("reset 1次 → cd 3→2", sword.get_skill_cooldown("swordsman_yishan"), 2)
	sword.reset_turn_state()
	_eq("reset 2次 → cd 2→1", sword.get_skill_cooldown("swordsman_yishan"), 1)
	sword.reset_turn_state()
	_eq("reset 3次 → cd 1→0(移除)", sword.get_skill_cooldown("swordsman_yishan"), 0)
	_check("reset 3次后 一闪可用", sword.is_skill_available("swordsman_yishan"))
	_check("cd 归零后从 skill_cooldowns 移除",
		not sword.skill_cooldowns.has("swordsman_yishan"))


# ── (c) 居合击杀（可选）：返气 + cd-1 ───────────────────────

func _test_juhe_kill_optional(tm: Object, sword: Unit) -> void:
	print("\n[c] 居合击杀 → qi_gain_on_kill + ki_on_kill_cd_reduction（运行时）")
	var enemy: Unit = _find_enemy(tm)
	if enemy == null:
		_check("存在敌方单位(居合)", false)
		return
	# 让敌人极脆，居合 power300 必杀
	enemy.stats.spd = 0
	enemy.stats.lck = 0
	enemy.stats.def_attr = 0
	enemy.stats.res = 0
	enemy.stats.max_hp = 1
	enemy.stats.hp = 1

	_place_adjacent(tm, sword, enemy)
	tm.input_state = 2
	sword.standard_used = false
	sword.movement_used = false
	sword.swift_used = false
	sword.skill_cooldowns.clear()  # 不可预置 cd：execute 会先验证 is_skill_available 而拒绝
	sword.set_sword_qi(60)  # 居合 qi_cost=60
	sword.clear_marks()

	tm._selected_skill_id = "swordsman_juhe"
	var action: Object = tm._build_skill_action(sword, enemy.grid_position, enemy)
	if action == null:
		_check("居合 action 构造成功", false)
		return
	# 施放扣60气 → 0；击杀返30气；施放时 consume_skill 用 payload.cooldown=3(JSON)写入，
	# 再经击杀 ki_on_kill_cd_reduction -1 → 2。
	var ok: bool = tm._execute_skill_action(action)
	_check("居合 _execute_skill_action 返回 true", ok)
	_check("居合击杀 → 敌人死亡", not enemy.stats.is_alive())
	# 扣60返30 → 净 30 气
	_eq("居合: 施放扣60气 + 击杀返30气 → sword_qi==30", sword.sword_qi, 30)
	_eq("居合: 得1印记(mark_gain)", sword.get_mark_count(), 1)
	# 施放写 cd=3(JSON)，击杀 -1 → 2
	_eq("居合: cd 写3 → 击杀-1 → 2", sword.get_skill_cooldown("swordsman_juhe"), 2)


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


func _find_empty_neighbor(tm: Object, origin: Vector2i) -> Vector2i:
	for nb: Vector2i in tm.grid.get_neighbors(origin):
		var c: Object = tm.grid.get_cell(nb)
		if c != null and c.is_passable() and c.occupant == null:
			return nb
	return Vector2i(-1, -1)


## 把 mover 放到 target 的一个空邻格（更新 grid 占用 + grid_position）。
func _place_adjacent(tm: Object, mover: Unit, target: Unit) -> void:
	var dest: Vector2i = _find_empty_neighbor(tm, target.grid_position)
	if dest == Vector2i(-1, -1):
		return
	# 清原格占用
	var old_cell: Object = tm.grid.get_cell(mover.grid_position)
	if old_cell != null and old_cell.occupant == mover:
		old_cell.occupant = null
	tm.grid.place_unit(mover, dest)
