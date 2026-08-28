extends SceneTree
## 真实 TacticalScene 的地图棋子接入回归。
##
## 运行：<Godot_console.exe> --headless --path <project-root> \
##   --script res://tests/test_tactical_map_token_integration.gd

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_tactical_map_token_integration ===")


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
	scene.injected_map_id = "forest_01"
	scene.injected_player_units = [
		{"class_id": "kensei", "pos": Vector2i(0, 2), "facing": &"NW"},
	]
	scene.injected_enemy_units = [
		{"class_id": "goblin_melee", "pos": Vector2i(6, 3)},
	]
	root.add_child(scene)

	var tm: Object = scene.tactical_manager
	var unit_layer := tm.get_node_or_null("UnitLayer") as Node2D
	var popup_layer := tm.get_node_or_null("PopupLayer") as Node2D
	_check("UnitLayer 存在且启用纵向排序",
		unit_layer != null and unit_layer.y_sort_enabled)
	_check("PopupLayer 位于单位层之上",
		popup_layer != null and unit_layer != null
		and popup_layer.z_index > unit_layer.z_index)

	var kensei: Unit = null
	var enemy: Unit = null
	for unit: Unit in tm.units:
		_check("所有单位都由 UnitLayer 承载", unit.get_parent() == unit_layer)
		if unit.faction == "player":
			kensei = unit
		else:
			enemy = unit

	_check("剑圣与未绑定正式棋子的敌人均已生成", kensei != null and enemy != null)
	if kensei != null:
		_check("剑圣启用正式棋子显示", kensei.has_runtime_map_token())
		_check("显式 NW 初始朝向生效", kensei.get_facing() == &"NW")
		_check("剑圣根位置来自 grid_to_world",
			kensei.position.is_equal_approx(tm.grid.grid_to_world(kensei.grid_position)))
	if enemy != null:
		_check("未绑定敌人保留占位显示", not enemy.has_runtime_map_token())
		_check("敌人根位置来自 grid_to_world",
			enemy.position.is_equal_approx(tm.grid.grid_to_world(enemy.grid_position)))

	# 缺省参数必须保留既有三参数调用接口。
	var legacy_unit: Unit = tm.spawn_unit("goblin_melee", Vector2i(3, 5), "enemy")
	_check("旧三参数 spawn_unit 仍可用", legacy_unit != null)
	if legacy_unit != null:
		_check("旧接口生成单位也进入 UnitLayer", legacy_unit.get_parent() == unit_layer)

	if kensei != null and enemy != null:
		tm.current_unit = kensei
		tm.input_state = 4 # InputState.ATTACK_TARGETING
		var attack_cells: Array[Vector2i] = [enemy.grid_position]
		tm._attack_cells = attack_cells
		var forecast: Dictionary = tm._build_attack_forecast_for_hover(enemy.grid_position)
		var targets: Array = forecast.get("targets", [])
		_check("普攻预估返回一个目标", targets.size() == 1)
		if targets.size() == 1:
			var target_data := targets[0] as Dictionary
			var actual_world: Vector2 = target_data["world"]
			_check("预估 world 使用最终锚点", actual_world.is_equal_approx(
				enemy.get_combat_text_anchor_world(-30.0)))

	scene.free()
	_finish()


func _finish() -> void:
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		for item: String in _fails:
			print("  ✗ ", item)
		quit(1)
	else:
		print("ALL PASS")
		quit(0)


func _check(desc: String, cond: bool) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		_fails.append(desc)
		print("  ✗ FAIL: ", desc)
