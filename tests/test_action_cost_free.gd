extends SceneTree
## action_cost "free" 预留类型 —— 2026-07-11 漂移修复 FIX-7
##
## 用户裁决：free = 不消耗任何行动资源、无资源门槛（R3.3 将增补该枚举值），
## 代码先行预留，当前无技能使用。
## 覆盖：校验放行（含资源全耗尽时仍可用）、消耗为零、未知值仍 fail-closed 拒绝、
##       运行时白名单接受 free。
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/test_action_cost_free.gd  （退出码 0=全过）

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_action_cost_free (free 预留类型) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	var dl: Object = load("res://scripts/data/data_loader.gd").new()
	dl.load_all()
	var class_data: Dictionary = dl.classes.get("soldier", {})
	_check("soldier class_data 可加载", not class_data.is_empty())
	if class_data.is_empty():
		_finish()
		return
	var u: Unit = _make_unit(class_data)

	# 1. 校验放行（资源全满时）
	u.reset_action_resources()
	_check("free 校验放行（资源全满）",
		bool(GameAction.validate_action_cost(u, "free").get("ok", false)))

	# 2. 零消耗
	GameAction.consume_action_cost(u, "free")
	_eq("free 消耗后 movement_used 仍 false", u.movement_used, false)
	_eq("free 消耗后 standard_used 仍 false", u.standard_used, false)
	_eq("free 消耗后 swift_used 仍 false", u.swift_used, false)
	_eq("free 消耗后 reaction_available 仍 true", u.reaction_available, true)

	# 3. 资源全耗尽后 free 仍可用（不吃任何资源门槛）
	u.consume_movement_resource()
	u.consume_standard_resource()
	u.consume_swift_resource()
	u.consume_reaction_resource()
	_check("free 校验放行（资源全耗尽）",
		bool(GameAction.validate_action_cost(u, "free").get("ok", false)))

	# 4. 未知值仍 fail-closed
	_check("未知 action_cost 仍被拒绝",
		not bool(GameAction.validate_action_cost(u, "bogus").get("ok", false)))

	_finish()


func _make_unit(class_data: Dictionary) -> Unit:
	var u: Unit = load("res://scenes/tactical/Unit.tscn").instantiate()
	root.add_child(u)
	u.setup(class_data)
	return u


# ── 断言工具 ─────────────────────────────────────────
func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  OK  " + name)
	else:
		_fail += 1
		var msg: String = name + ("  [" + detail + "]" if detail != "" else "")
		_fails.append(msg)
		print("  XX  " + msg)


func _eq(name: String, actual: Variant, expected: Variant) -> void:
	_check(name, actual == expected, "期望 %s 实际 %s" % [str(expected), str(actual)])


func _finish() -> void:
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  XX " + f)
	quit(0 if _fail == 0 else 1)
