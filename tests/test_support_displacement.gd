extends SceneTree
## 辅助类位移技能（`power <= 0` + `displacement: true`）必须真的位移。
##
## 起因：Mercury 2026-08-11 在跨组收件箱报的静默失效——`_execute_skill_action` 里
## `_is_support_skill()`（判据 `power <= 0`）命中后直接 `return true` 早退，而位移块在
## 那之后，于是这类技能施放后**单位站着不动、且不报错**。瞬身（无伤害的瞬移）正好是
## 这个组合，照原状实装会得到一个「用了没反应」的技能。
##
## 这一组锁三件事：
##   A. 辅助类位移技能确实会位移（修复本身）
##   B. 有伤害的位移技能仍然位移（一闪，回归）
##   C. ★ 位移仍发生在伤害结算**之后** —— 一闪的途经伤害用
##      `_get_displacement_path_cells(user.grid_position, target_pos)` 算路径，
##      若为了让辅助技能走到而把位移整块提前，起点会变成落点、路径全错。
##      这条是修复时最容易踩的坑，必须有断言压着。
##
## 运行：
##   <Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##     --script res://tests/test_support_displacement.gd
## 退出码 0=全过，1=有失败。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_support_displacement (辅助类位移技能不再静默失效) ===")


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
	tm.debug_harness_active = true
	tm.debug_deterministic = true
	tm.debug_crit_mode = 2

	var user: Unit = null
	for u: Unit in tm.units:
		if u.faction == "player" and u.unit_id == "kensei":
			user = u
			break
	if user == null:
		_check("场景中找到剑圣", false)
		scene.free()
		quit(1)
		return
	_check("场景中找到剑圣", true)

	_test_support_displacement(tm, user)
	_test_hostile_displacement_still_works(tm, user)
	_test_displacement_after_damage(tm, user)

	scene.free()
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  ✗ " + f)
	quit(0 if _fail == 0 else 1)


## A. power<=0 + displacement=true → 必须真的移动（本次修复的正题）。
func _test_support_displacement(tm: Object, user: Unit) -> void:
	print("\n[A] 辅助类位移技能（power<=0 + displacement）")
	var origin: Vector2i = _find_free_cell(tm, user)
	if origin == Vector2i(-999, -999):
		_check("找到可用起点", false)
		return
	_move_to(tm, user, origin)

	var landing: Vector2i = _find_landing(tm, origin, 2)
	if landing == Vector2i(-999, -999):
		_check("找到可用落点", false)
		return

	# power=0 → 走 _is_support_skill 分支；displacement=true → 应当位移。
	var skill: Dictionary = {
		"id": "test_blink", "name": "测试·瞬移", "power": 0,
		"range": {"type": "diamond", "min": 1, "max": 5},
		# ⚠ area 刻意**不用 single**：`_execute_skill_action` 有一道
		# 「非选地面技能（area.type==single）且目标格无单位 → return false」的静默拦截
		# （:1530），而位移落点又要求无占据者——两条对 area=single 的位移技能互斥。
		# 那是与本修复无关的**另一个**障碍（瞬身真正的拦路虎），已在跨组收件箱登记；
		# 本组只锁「power<=0 也要位移」，故用能跑通的配置。
		"area": {"type": "diamond", "size": 1},
		"displacement": true, "effects": [],
	}
	if not _register_skill(skill):
		_check("注入测试技能到 autoload DataLoader", false)
		return
	user.reset_action_resources()
	var before: Vector2i = user.grid_position
	tm._execute_skill_action(_make_action(user, skill, landing))
	_check("power=0 的位移技能确实移动了（修复前会站着不动且不报错）",
		user.grid_position != before,
		"施放前 %s 施放后 %s" % [str(before), str(user.grid_position)])
	_eq("落点正是所选目标格", user.grid_position, landing)


## B. 有伤害的位移技能（一闪）仍然位移 —— 防止修复把原路径改坏。
func _test_hostile_displacement_still_works(tm: Object, user: Unit) -> void:
	print("\n[B] 有伤害的位移技能仍然位移（回归）")
	var origin: Vector2i = _find_free_cell(tm, user)
	if origin == Vector2i(-999, -999):
		_check("找到可用起点", false)
		return
	_move_to(tm, user, origin)
	var landing: Vector2i = _find_landing(tm, origin, 2)
	if landing == Vector2i(-999, -999):
		_check("找到可用落点", false)
		return

	var skill: Dictionary = {
		"id": "test_dash", "name": "测试·突进", "power": 50,
		"damage_type": "physical",
		"range": {"type": "line", "min": 1, "max": 4},
		"area": {"type": "line", "size": 1},
		"displacement": true, "effects": [],
	}
	if not _register_skill(skill):
		_check("注入测试技能到 autoload DataLoader", false)
		return
	user.reset_action_resources()
	var before: Vector2i = user.grid_position
	tm._execute_skill_action(_make_action(user, skill, landing))
	_check("power>0 的位移技能仍然移动", user.grid_position != before,
		"施放前 %s 施放后 %s" % [str(before), str(user.grid_position)])


## C. ★ 位移必须仍在伤害结算之后。
##
## 判据不看时序看**受伤格**：途经格由 `_get_displacement_path_cells(起点, 落点)` 算，
## 若位移被提前，起点会变成落点、路径退化成空，途中的敌人就一个都打不到。
## 所以「途中敌人掉了血」这一条，等价于「算路径时用的还是起点」。
func _test_displacement_after_damage(tm: Object, user: Unit) -> void:
	print("\n[C] 位移仍发生在伤害结算之后（途经格用起点算）")
	var victim: Unit = null
	for u: Unit in tm.units:
		if u.faction == "enemy" and u.stats.is_alive():
			victim = u
			break
	if victim == null:
		_check("找到一名敌人当途经目标", false)
		return
	_check("找到一名敌人当途经目标", true)

	# 自己摆局面，不指望敌人原地周围恰好有空格：找一条连续三格，
	# 施法者站左、敌人站中、落点在右。
	var start: Vector2i = Vector2i(-999, -999)
	for y: int in range(1, 12):
		for x: int in range(1, 12):
			var a: Vector2i = Vector2i(x, y)
			var three_free: bool = _cell_free(tm, a) \
				and _cell_free(tm, a + Vector2i(1, 0)) \
				and _cell_free(tm, a + Vector2i(2, 0))
			if three_free:
				start = a
				break
		if start != Vector2i(-999, -999):
			break
	if start == Vector2i(-999, -999):
		_check("摆出「敌人在途中」的局面", false, "找不到连续三格空地")
		return
	_move_to(tm, user, start)
	_move_to(tm, victim, start + Vector2i(1, 0))
	var landing: Vector2i = start + Vector2i(2, 0)
	_check("摆出「敌人在途中」的局面", true)

	victim.stats.max_hp = 9999
	victim.stats.hp = 9999
	victim.stats.def_attr = 0
	var skill: Dictionary = {
		"id": "test_dash2", "name": "测试·穿击", "power": 50,
		"damage_type": "physical",
		"range": {"type": "line", "min": 1, "max": 4},
		"area": {"type": "line", "size": 1},
		"displacement": true, "effects": [],
	}
	if not _register_skill(skill):
		_check("注入测试技能到 autoload DataLoader", false)
		return
	user.reset_action_resources()
	tm._execute_skill_action(_make_action(user, skill, landing))
	_check("途中的敌人确实掉了血（说明路径是用【起点】算的，位移没被提前）",
		victim.stats.hp < 9999,
		"敌人 HP 仍是 %d；若位移被提前，起点=落点会让途经格算成空" % victim.stats.hp)
	_eq("施法者最终落在目标格", user.grid_position, landing)


# ── 夹具 ───────────────────────────────────────────

## 技能数据必须进 **autoload** 的 DataLoader —— `_get_skill_data` 读的是它，
## 直接把字典塞进 action.data 不管用。`DataLoader` 这个标识符在 --script 主循环下
## 编译期解析不到，走 get_node。
func _register_skill(skill: Dictionary) -> bool:
	var dl: Node = root.get_node_or_null("/root/DataLoader")
	if dl == null:
		return false
	dl.skills[str(skill.get("id", ""))] = skill.duplicate(true)
	return true


func _make_action(user: Unit, skill: Dictionary, target: Vector2i) -> GameAction:
	var a: GameAction = GameAction.new()
	a.actor = user
	a.target_pos = target
	a.data = {"skill_id": str(skill.get("id", "")),
		"skill_name": str(skill.get("name", ""))}
	return a


func _cell_free(tm: Object, pos: Vector2i) -> bool:
	var cell: Variant = tm.grid.get_cell(pos)
	if cell == null:
		return false
	return cell.is_passable() and cell.occupant == null


func _find_free_cell(tm: Object, user: Unit) -> Vector2i:
	for y: int in range(2, 10):
		for x: int in range(2, 10):
			var p: Vector2i = Vector2i(x, y)
			if _cell_free(tm, p) and _cell_free(tm, p + Vector2i(2, 0)):
				return p
	return Vector2i(-999, -999)


func _find_landing(tm: Object, origin: Vector2i, dist: int) -> Vector2i:
	var p: Vector2i = origin + Vector2i(dist, 0)
	return p if _cell_free(tm, p) else Vector2i(-999, -999)


func _move_to(tm: Object, user: Unit, pos: Vector2i) -> void:
	var from: Vector2i = user.grid_position
	tm.grid.move_unit(user, from, pos)
	user.position = tm.grid.grid_to_world(pos)


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
