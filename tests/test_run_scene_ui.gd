extends SceneTree
## RunScene UI 面板构建回归测试 —— 覆盖 headless 逻辑测试的盲区（真 UI 节点构建）。
##
## 背景：门循环逻辑测试（test_run_scene_flow 等）用 RunManager 直接驱动，不实例化真 UI，
## 因此 RunScene 的面板构建路径从未被 headless 覆盖。曾潜伏一个 bug：
##   _build_center_panel 把 VBox 挂在 CenterContainer 下，而 _show_prep/事件/结算面板
##   用 get_node("VBox")（找 panel 直接子节点）→ 返回 null → add_child on null 崩溃。
## 修复：CenterContainer 命名 "Center"，面板函数经 get_node("Center/VBox") 访问。
## 本测试直接验证 _build_center_panel 的 VBox 可经该路径访问并 add_child（不触发 _ready/战斗）。
##
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/test_run_scene_ui.gd
## 退出码 0=全过，1=有失败。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_run_scene_ui (RunScene UI 面板构建回归) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	# instantiate 不 add_child → 不触发 _ready(start_run/战斗)；_build_center_panel 是纯 UI 构建，可直接调。
	var rs: Node = load("res://scenes/roguelite/RunScene.tscn").instantiate()
	_check("RunScene 实例化成功", rs != null)

	var panel: Control = rs._build_center_panel()
	_check("_build_center_panel 返回非 null", panel != null)

	# 修复点：VBox 在 CenterContainer("Center") 下，须经 "Center/VBox" 访问（旧 "VBox" 返回 null）。
	var vbox_node: Node = panel.get_node_or_null("Center/VBox")
	_check("面板含 Center/VBox 节点（旧 get_node(\"VBox\") 曾返回 null）", vbox_node != null)
	_check("Center/VBox 是 VBoxContainer", vbox_node is VBoxContainer)
	# 负向对照：旧的直接子路径 "VBox" 不存在（确认 VBox 确实在 Center 下、不在 panel 直层）。
	_check("panel 直接子 \"VBox\" 不存在（VBox 在 Center 下）",
		panel.get_node_or_null("VBox") == null)

	# 复现修复前的崩溃点：面板函数会 vbox.add_child(...)，vbox 为 null 时崩。
	if vbox_node is VBoxContainer:
		var lbl: Label = Label.new()
		(vbox_node as VBoxContainer).add_child(lbl)
		_check("Center/VBox.add_child 成功（修复前此处 add_child on null 崩溃）",
			lbl.get_parent() == vbox_node)

	panel.free()
	rs.free()

	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  ✗ " + f)
	else:
		print("OK：全部断言通过")
	quit(0 if _fail == 0 else 1)


func _check(name: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		_fails.append(name)
		print("  ✗ " + name)
