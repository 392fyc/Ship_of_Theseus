extends SceneTree
## 木桩再生/复活钩子 headless 回归测试
##
## 目的：验证 _process_test_dummies 钩子逻辑正确：
##   ① regen 木桩：扣血后触发 round_ended → HP 回满
##   ② revive 木桩：致死后触发 round_ended → units 中重新出现存活实例
##
## 坑规避（--script 三大坑）：
##   - 断言放 _process 首帧（不在构造期）
##   - 不在主循环顶层引用会触发早期类缓存编译失败的全局 class_name
##   - 经 TacticalScene.tscn.instantiate 走正式 spawn 路径（内部用 Unit.tscn）
##
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/test_harness_dummies.gd
## 退出码 0=全过，1=有失败。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_harness_dummies (木桩再生/复活) ===")


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

	_check("场景实例化成功", scene != null)
	_check("tactical_manager 存在", tm != null)
	if tm == null:
		_finish(scene)
		return

	# 前提：5 个敌人均已 spawn（含两木桩）
	var enemy_count: int = 0
	for u in tm.units:
		if u.faction == "enemy":
			enemy_count += 1
	_eq("敌人总数为 5（含两木桩）", enemy_count, 5)

	# 找到两个木桩单位
	var regen_unit: Unit = _find_by_id(tm, "test_dummy_regen")
	var revive_unit: Unit = _find_by_id(tm, "test_dummy_revive")
	_check("不灭木桩 (regen) 已 spawn", regen_unit != null)
	_check("复活木桩 (revive) 已 spawn", revive_unit != null)

	if regen_unit == null or revive_unit == null:
		_finish(scene)
		return

	# ─── ① 再生测试：扣血后触发 round_ended → HP 回满 ───────────────────
	print("\n[①] 再生测试")
	var regen_max_hp: int = regen_unit.stats.max_hp
	_eq("不灭木桩 max_hp = 999", regen_max_hp, 999)

	# 直接设置 HP（跳过 take_damage 动画，只测再生逻辑）
	regen_unit.stats.hp = regen_max_hp - 200
	_check("再生木桩扣血后 hp < max_hp", regen_unit.stats.hp < regen_max_hp)

	# 触发 round_ended → _process_test_dummies 执行再生
	tm.turn_manager.round_ended.emit()

	_eq("再生木桩 round_ended 后 hp 回满", regen_unit.stats.hp, regen_max_hp)

	# ─── ② 复活测试：致死后触发 round_ended → units 中重新出现存活实例 ──
	print("\n[②] 复活测试")
	var revive_id: String = revive_unit.unit_id
	var revive_max_hp: int = revive_unit.stats.max_hp
	_eq("复活木桩 max_hp = 30", revive_max_hp, 30)

	# 通过 take_damage 走完整死亡路径（unit_died → _on_unit_died → 从 units/grid 移除）
	# _on_death 会启动死亡动画协程（headless 下动画协程挂起但不影响逻辑）
	revive_unit.take_damage(revive_max_hp + 999)

	# 验证复活木桩已从 units 移除
	var found_after_kill: bool = false
	for u in tm.units:
		if u.unit_id == revive_id:
			found_after_kill = true
			break
	_check("复活木桩死亡后从 units 移除", not found_after_kill)

	# 验证格子占位已释放（spawn 前提）
	# （不直接检查 cell，信任 _on_unit_died 调了 grid.remove_unit）

	# 触发 round_ended → _process_test_dummies 执行复活
	tm.turn_manager.round_ended.emit()

	# 验证复活木桩重新出现在 units 中（新实例）
	var revived_unit: Unit = _find_by_id(tm, revive_id)
	_check("复活木桩 round_ended 后重新出现在 units 中", revived_unit != null)
	if revived_unit != null:
		_check("复活后单位存活（hp > 0）", revived_unit.stats.is_alive())
		_eq("复活后 hp = max_hp", revived_unit.stats.hp, revive_max_hp)

	# 总单位数：剑圣 1 + 枪兵/弓/法 3 + 再生 1 + 复活（新实例）1 = 6
	var total_after_revive: int = tm.units.size()
	_eq("复活后总单位数恢复 6", total_after_revive, 6)

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


func _find_by_id(tm: Object, uid: String) -> Unit:
	for u: Unit in tm.units:
		if u.unit_id == uid and u.stats.is_alive():
			return u
	return null
