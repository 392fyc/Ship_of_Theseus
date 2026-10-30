extends SceneTree
## 批量模拟用的开关 TacticalManager.ai_controls_players（tools/sim/battle_sim.gd）。
## 覆盖：
##   ① 默认 false：玩家单位的回合等待输入，AI 不替它行动。
##   ② 打开后：玩家单位由 EnemyAI 行动，ai_action_started 对玩家单位发出；一场战斗能自己打完。
##
## 运行：
##   <Godot_console.exe> --headless --path <worktree> --script res://tests/test_ai_controls_players.gd

const MAX_FRAMES := 20000

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _player_actions: int = 0
var _result: String = ""


func _initialize() -> void:
	print("=== test_ai_controls_players（玩家方也由 AI 行动）===")
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load("res://scenes/tactical/TacticalScene.tscn")
	Engine.time_scale = 100.0

	# ① 默认关闭：轮到玩家单位时停在等待输入。
	var plain: Node = _make(packed)
	var plain_tm: Node = plain.get_node("TacticalManager")
	_check("默认关闭", not bool(plain_tm.get("ai_controls_players")))
	plain_tm.ai_action_started.connect(_count_player_action)
	root.add_child(plain)
	var reached_player: bool = false
	for i: int in range(120):
		await process_frame
		if plain_tm.current_unit != null and plain_tm.current_unit.faction == "player":
			reached_player = true
	# 轮到玩家后再等一段：若 AI 误替玩家行动，演出等待结束后就会发出动作信号。
	for i: int in range(60):
		await process_frame
	_check("前提：轮到过玩家单位", reached_player)
	_eq("关闭时 AI 不替玩家单位行动", _player_actions, 0)
	plain_tm.stop_battle()
	plain.queue_free()
	await process_frame

	# ② 打开：一场战斗自己打完。
	_player_actions = 0
	var scene: Node = _make(packed)
	var tm: Node = scene.get_node("TacticalManager")
	tm.ai_controls_players = true
	tm.ai_action_started.connect(_count_player_action)
	scene.battle_ended.connect(func(r: String) -> void: _result = r)
	root.add_child(scene)
	var frames: int = 0
	while _result == "" and frames < MAX_FRAMES:
		await process_frame
		frames += 1
	_check("玩家单位由 AI 行动", _player_actions > 0, "玩家动作 %d" % _player_actions)
	_check("战斗自己打完", _result != "", "帧数 %d" % frames)
	tm.stop_battle()
	Engine.time_scale = 1.0
	_finish(scene)


func _make(packed: PackedScene) -> Node:
	var scene: Node = packed.instantiate()
	scene.run_injected = true
	scene.debug_harness_enabled = false
	scene.injected_map_id = "test_arena"
	# 一名敌人：敌人先手时，它的回合在 ① 的 120 帧内就会走完（演出等待按 time_scale 加速），之后轮到玩家。
	scene.injected_player_units = [{"class_id": "kensei", "pos": Vector2i(1, 3)},
		{"class_id": "myrmidon", "pos": Vector2i(1, 4)}]
	scene.injected_enemy_units = [{"class_id": "goblin_melee", "pos": Vector2i(6, 3)}]
	return scene


func _count_player_action(unit: Unit, _action: GameAction) -> void:
	if unit.faction == "player":
		_player_actions += 1


func _finish(scene: Node) -> void:
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
