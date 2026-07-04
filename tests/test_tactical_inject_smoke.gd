extends SceneTree
## TacticalScene 注入模式烟雾测试 —— 2026-07-04（任务 #6）
##
## 目的：headless 实例化 TacticalScene.tscn，走 run_injected 注入分支（宿主 RunScene 的
## 装配→注入路径），验证：
##   - 注入清单按 spawn 数正确落地（玩家 + 敌人）。
##   - 敌人词条经 apply_affixes 注入（has_affix 为真，玩家不注入）。
##   - stat_scale 体现在 max_hp（缩放敌 == round(参照敌 max_hp × scale)）。
##   - 全程不崩、非注入路径不受影响（debug_harness_enabled=false）。
##
## 坑规避（--script 三大坑）：断言放 _process 首帧；不引全局 class_name；经
## TacticalScene.tscn.instantiate 走正式 spawn 路径（内部用 Unit.tscn）；
## 注入字段在 add_child（触发 _ready）前设置。
##
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/test_tactical_inject_smoke.gd
## 退出码 0=全过，1=有失败。

const INJECT_MAP: String = "forest_01"
const INJECT_SCALE: float = 1.35

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_tactical_inject_smoke (TacticalScene 注入模式) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	var scene: Node = load("res://scenes/tactical/TacticalScene.tscn").instantiate()
	# 注入字段必须在 add_child（触发 _ready）前设置。
	scene.run_injected = true
	scene.debug_harness_enabled = false
	scene.injected_map_id = INJECT_MAP
	scene.injected_player_units = [
		{"class_id": "swordsman", "pos": Vector2i(0, 2), "level": 1},
	]
	# 缩放敌（含基础词条 + 特殊词条 + 数值增强）与 参照敌（无词条、scale=1.0）同 class。
	scene.injected_enemy_units = [
		{
			"class_id": "goblin_melee",
			"pos": Vector2i(6, 3),
			"affixes": ["af_counter_boost"],
			"special_affix": "afs_bulwark",
			"stat_scale": INJECT_SCALE,
		},
		{
			"class_id": "goblin_melee",
			"pos": Vector2i(6, 4),
		},
	]
	root.add_child(scene)

	var tm: Object = scene.tactical_manager
	_check("场景实例化成功", scene != null)
	_check("tactical_manager 存在", tm != null)
	if tm == null:
		scene.free()
		_finish()
		return

	# spawn 数：1 玩家 + 2 敌人 = 3
	_eq("注入 spawn 单位总数 == 3", tm.units.size(), 3)

	var players: Array = []
	var enemies: Array = []
	for u in tm.units:
		if u.faction == "player":
			players.append(u)
		else:
			enemies.append(u)
	_eq("玩家单位 spawn 1 个", players.size(), 1)
	_eq("敌人单位 spawn 2 个", enemies.size(), 2)
	if players.size() >= 1:
		_check("玩家单位为 swordsman", str(players[0].unit_id) == "swordsman",
			"unit_id=%s" % str(players[0].unit_id))
		_check("玩家不注入词条（has_affix 为假）",
			not players[0].has_affix("af_counter_boost"))

	# 区分 缩放敌 vs 参照敌：缩放敌带 afs_bulwark 特殊词条。
	var scaled: Unit = null
	var reference: Unit = null
	for u: Unit in enemies:
		if u.has_affix("afs_bulwark"):
			scaled = u
		else:
			reference = u

	_check("缩放敌（含 afs_bulwark）存在", scaled != null)
	_check("参照敌（无词条）存在", reference != null)

	if scaled != null:
		_check("缩放敌 has_affix(af_counter_boost) 为真（基础词条注入）",
			scaled.has_affix("af_counter_boost"))
		_check("缩放敌 has_affix(afs_bulwark) 为真（特殊词条注入）",
			scaled.has_affix("afs_bulwark"))
	if reference != null:
		_check("参照敌 has_affix(af_counter_boost) 为假（scale=1.0 未注入词条）",
			not reference.has_affix("af_counter_boost"))

	if scaled != null and reference != null:
		var expected_hp: int = roundi(float(reference.stats.max_hp) * INJECT_SCALE)
		_eq("缩放敌 max_hp == round(参照敌 max_hp × %.2f)" % INJECT_SCALE,
			scaled.stats.max_hp, expected_hp)
		_check("缩放敌 max_hp > 参照敌 max_hp（数值增强生效）",
			scaled.stats.max_hp > reference.stats.max_hp,
			"缩放 %d 参照 %d" % [scaled.stats.max_hp, reference.stats.max_hp])
		_check("缩放敌 hp==max_hp（注入后回满）",
			scaled.stats.hp == scaled.stats.max_hp,
			"hp=%d max=%d" % [scaled.stats.hp, scaled.stats.max_hp])

	_check("注入流程未崩（场景仍有效）", is_instance_valid(scene))

	scene.free()
	_finish()


func _finish() -> void:
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  XX " + f)
	else:
		print("OK：全部断言通过")
	quit(0 if _fail == 0 else 1)


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  OK  " + name)
	else:
		_fail += 1
		_fails.append(name + ("  [" + detail + "]" if detail != "" else ""))
		print("  XX  " + name + ("  [" + detail + "]" if detail != "" else ""))


func _eq(name: String, actual: Variant, expected: Variant) -> void:
	_check(name, actual == expected, "期望 %s 实际 %s" % [str(expected), str(actual)])
