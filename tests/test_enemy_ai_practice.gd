extends SceneTree
## 测试场景的「敌人 AI 对练」与魔法普攻（用户 2026-10-31：「修」「放个测试场景，控制一下伤害互相打不死」
## 「测试场景之前应该存在一个，把场景什么的填入即可」）。
## 覆盖：
##   ① 对练开关：默认场景阵容不变；打开后 6 种普通哥布林与配置的玩家单位在场，所有单位最大生命为配置值，
##      敌人自动行动；每轮结束回满，不复活木桩。
##   ② 魔法普攻：普攻为魔法的单位（哥布林法师、萨满）普攻按魔法伤害结算，物理的仍是物理；
##      预告与实际结算用同一个伤害类型。
##
## 运行：
##   <Godot_console.exe> --headless --path <worktree> --script res://tests/test_enemy_ai_practice.gd

const GOBLINS: Array[String] = ["goblin_archer", "goblin_brave", "goblin_mage",
	"goblin_melee", "goblin_priest", "goblin_shaman"]

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []


func _initialize() -> void:
	print("=== test_enemy_ai_practice（敌人 AI 对练与魔法普攻）===")
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load("res://scenes/tactical/TacticalScene.tscn")
	# 默认阵容不变（对练关闭）。
	# enemy_ai_practice 是静态变量：在实例上读写即读写全场景共享的开关。
	var plain: Node = packed.instantiate()
	_check("前提：对练默认关闭", not bool(plain.get("enemy_ai_practice")))
	root.add_child(plain)
	await process_frame
	await process_frame
	var plain_ids: Array[String] = []
	for u: Variant in plain.tactical_manager.units:
		plain_ids.append((u as Unit).unit_id)
	_check("对练关闭：默认阵容不变（有 test_lancer、没有哥布林）",
		plain_ids.has("test_lancer") and not plain_ids.has("goblin_melee"))
	plain.queue_free()
	await process_frame

	var scene: Node = packed.instantiate()
	scene.set("enemy_ai_practice", true)
	_check("测试场景脚本已挂载", scene.get_script() != null
		and (scene.get_script() as Script).resource_path == "res://scripts/tactical/tactical_scene.gd")
	root.add_child(scene)
	await process_frame
	await process_frame

	var tm: Node = scene.get("tactical_manager")
	if tm == null:
		_check("测试场景建好了战斗", false)
		_finish(scene)
		return
	if tm.turn_manager != null:
		tm.turn_manager.stop()
	var cfg: Dictionary = (root.get_node("/root/DataLoader").ai as Dictionary).get("enemy_ai_practice", {})
	var hp: int = int(cfg.get("unit_hp", 0))
	_check("前提：配置的生命值大于 0", hp > 0)
	_eq("敌人自动行动（木桩行为：自动）", int(tm.debug_dummy_behavior), int(tm.DummyBehavior.AUTO))

	# ① 场上单位
	var enemy_ids: Array[String] = []
	var players: Array[Unit] = []
	var by_id: Dictionary = {}
	for u: Variant in tm.units:
		if not u is Unit:
			continue
		var unit: Unit = u
		if unit.faction == "enemy":
			enemy_ids.append(unit.unit_id)
			by_id[unit.unit_id] = unit
		else:
			players.append(unit)
	enemy_ids.sort()
	_eq("6 种普通哥布林都在场", enemy_ids, GOBLINS)
	_eq("玩家单位数", players.size(), (cfg.get("player_units", []) as Array).size())
	var all_hp: bool = true
	for u: Variant in tm.units:
		var unit: Unit = u
		if unit.stats.max_hp != hp or unit.stats.hp != hp:
			all_hp = false
	_check("所有单位最大生命与当前生命都是 %d" % hp, all_hp)
	# 每轮结束回满。
	var target: Unit = players[0]
	target.take_damage(300, "pure")
	var mage: Unit = by_id.get("goblin_mage")
	mage.take_damage(100, "pure")
	_check("前提：受了伤", target.stats.hp < hp and mage.stats.hp < hp)
	tm.turn_manager.round_ended.emit()
	_check("每轮结束回满", target.stats.hp == hp and mage.stats.hp == hp)
	var revived: bool = false
	for u: Variant in tm.units:
		if (u as Unit).unit_id == "test_dummy_revive":
			revived = true
	_check("对练阵容不复活木桩", not revived)

	# ② 魔法普攻
	for id: String in ["goblin_mage", "goblin_shaman", "goblin_melee"]:
		var attacker: Unit = by_id.get(id)
		var expected: String = str((root.get_node("/root/DataLoader").enemies as Dictionary)
			.get(id, {}).get("damage_type", ""))
		var ctx: Dictionary = tm._build_hostile_action_context(attacker, target,
			GameAction.make_attack(attacker, target).data)
		_eq("%s 普攻按数据的伤害类型结算" % id, str(ctx.get("damage_type", "")), expected)
		_eq("%s 普攻预告与结算同一伤害类型" % id,
			str(tm._forecast_attack_for_ai(attacker, target).get("damage_type", "")), expected)
	_check("前提：法师数据是魔法", str((root.get_node("/root/DataLoader").enemies as Dictionary)
		.get("goblin_mage", {}).get("damage_type", "")) == "magical")
	_finish(scene)


func _finish(scene: Node) -> void:
	scene.set("enemy_ai_practice", false)
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  ✗ " + f)
	scene.queue_free()
	await process_frame
	quit(1 if _fail > 0 else 0)


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		var line: String = name + ("  [" + detail + "]" if detail != "" else "")
		_fails.append(line)
		print("  ✗ " + line)


func _eq(name: String, actual: Variant, expected: Variant) -> void:
	_check(name, actual == expected, "期望 %s 实际 %s" % [str(expected), str(actual)])
