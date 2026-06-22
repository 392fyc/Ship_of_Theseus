extends SceneTree
## 调试 harness 自检（headless 烟雾测试）
##
## 目的：确认 TacticalScene 调试 harness 能 headless 实例化、软重置不崩、
## 确定性开关与暴击/木桩态切换 API 可用。与剑圣回归套件互补（后者测逻辑断言）。
##
## 坑规避（--script 三大坑）：
##   - 断言放 _process 首帧（不在构造期）
##   - 不在主循环顶层引用会触发早期类缓存编译失败的全局 class_name
##   - 经 TacticalScene.tscn.instantiate 走正式 spawn 路径（内部用 Unit.tscn）
##
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/test_harness_load.gd
## 退出码 0=全过，1=有失败。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_harness_load (调试 harness 自检) ===")


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
		_finish()
		return

	# 调试 API 存在性
	_check("debug_soft_reset 方法存在", tm.has_method("debug_soft_reset"))
	_check("debug_toggle_deterministic 方法存在", tm.has_method("debug_toggle_deterministic"))
	_check("debug_cycle_crit_mode 方法存在", tm.has_method("debug_cycle_crit_mode"))
	_check("debug_cycle_dummy_behavior 方法存在", tm.has_method("debug_cycle_dummy_behavior"))
	_check("debug_get_status 方法存在", tm.has_method("debug_get_status"))

	# 软重置：先扰动单位状态，再 reset 应复位
	var sword: Unit = _find_swordsman(tm)
	if sword != null:
		sword.stats.hp = 1
		sword.set_sword_qi(5)
		sword.marks["心"] = true
		sword.skill_cooldowns["swordsman_juhe"] = 3
		sword.standard_used = true

	tm.debug_soft_reset()
	_check("软重置后不崩（场景仍有效）", is_instance_valid(scene))

	if sword != null and is_instance_valid(sword):
		_eq("软重置 → HP 回满", sword.stats.hp, sword.stats.max_hp)
		_eq("软重置 → 剑气回初始0", sword.sword_qi, 0)
		_eq("软重置 → 印记清空", sword.get_mark_count(), 0)
		_eq("软重置 → 冷却清空", sword.skill_cooldowns.size(), 0)
		_check("软重置 → standard_used 复位", not sword.standard_used)

	# 确定性开关：toggle 翻转
	var det1: bool = tm.debug_toggle_deterministic()
	_check("确定性开关 → 开", det1)
	var det2: bool = tm.debug_toggle_deterministic()
	_check("确定性开关 → 关", not det2)

	# 暴击态循环：随机(0)→必暴(1)→不暴(2)→随机(0)
	# CritMode 枚举序号（RANDOM=0, FORCE=1, DISABLE=2），用整数比对避免引枚举
	tm.debug_crit_mode = 0
	_eq("暴击态 cycle 1 → 必暴(1)", int(tm.debug_cycle_crit_mode()), 1)
	_eq("暴击态 cycle 2 → 不暴(2)", int(tm.debug_cycle_crit_mode()), 2)
	_eq("暴击态 cycle 3 → 随机(0)", int(tm.debug_cycle_crit_mode()), 0)

	# 木桩行为循环：不动(0)→只反击(1)→自动(2)→不动(0)
	tm.debug_dummy_behavior = 0
	_eq("木桩 cycle 1 → 只反击(1)", int(tm.debug_cycle_dummy_behavior()), 1)
	_eq("木桩 cycle 2 → 自动(2)", int(tm.debug_cycle_dummy_behavior()), 2)
	_eq("木桩 cycle 3 → 不动(0)", int(tm.debug_cycle_dummy_behavior()), 0)

	# 状态汇总字典字段
	var status: Dictionary = tm.debug_get_status()
	_check("debug_get_status 含 deterministic", status.has("deterministic"))
	_check("debug_get_status 含 crit_mode", status.has("crit_mode"))
	_check("debug_get_status 含 dummy_behavior", status.has("dummy_behavior"))

	# 确定性注入：开 + 必暴 → action_data 带 guaranteed_hit/guaranteed_crit
	tm.debug_deterministic = true
	tm.debug_crit_mode = 1
	var ctx_force: Dictionary = {}
	if sword != null:
		var enemy: Unit = _find_enemy(tm)
		if enemy != null:
			ctx_force = tm._build_hostile_action_context(sword, enemy, {})
	_check("确定性开 → 强制命中注入", bool(ctx_force.get("guaranteed_hit", false)))
	_check("必暴态 → guaranteed_crit 注入", bool(ctx_force.get("guaranteed_crit", false)))

	# 不暴态 → disable_crit 注入
	tm.debug_crit_mode = 2
	var ctx_disable: Dictionary = {}
	if sword != null:
		var enemy2: Unit = _find_enemy(tm)
		if enemy2 != null:
			ctx_disable = tm._build_hostile_action_context(sword, enemy2, {})
	_check("不暴态 → disable_crit 注入", bool(ctx_disable.get("disable_crit", false)))

	# 关闭确定性 → 不再注入
	tm.debug_deterministic = false
	var ctx_off: Dictionary = {}
	if sword != null:
		var enemy3: Unit = _find_enemy(tm)
		if enemy3 != null:
			ctx_off = tm._build_hostile_action_context(sword, enemy3, {})
	_check("确定性关 → 不注入 guaranteed_hit",
		not bool(ctx_off.get("guaranteed_hit", false)))

	scene.free()
	_finish()


func _finish() -> void:
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
