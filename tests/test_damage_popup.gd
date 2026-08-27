extends SceneTree
## DamagePopup 纯函数回归（compose / 形状映射 / 颜色 / 字号 / 暴击后缀）
##
## 覆盖：FF14 飘字的可断言数据层 —— 类型前缀形状、配色、数字基准小、暴击仅 +3 略大 + ！后缀。
## 视觉（自绘形状渲染 / 头顶停留 / 升起淡出 / 多段右上偏移）= 编辑器人眼核验，headless 测不了渲染。
##
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/test_damage_popup.gd
## 退出码 0 = 全过。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_damage_popup (FF14 飘字 compose 纯函数) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	# 字号基准：数字相对小，暴击仅 +3（用户拍板）
	_check("普通字号=16", DamagePopup.NORMAL_SIZE == 16)
	_check("暴击字号=19", DamagePopup.CRIT_SIZE == 19)
	_check("暴击比普通大 3", DamagePopup.CRIT_SIZE - DamagePopup.NORMAL_SIZE == 3)
	_check("MISS 字号=14", DamagePopup.MISS_SIZE == 14)

	# 物理 → 剑形 + 白
	var p: Dictionary = DamagePopup.compose(100, "physical", false)
	_check("物理 text=100（FF14 式无负号）", p.text == "100")
	_check("物理 shape=sword", p.shape == "sword")
	_check("物理 color=白", p.color == DamagePopup.COLOR_PHYS)
	_check("物理 size=16", p.size == 16)

	# 魔法 → 菱形 + 紫
	var m: Dictionary = DamagePopup.compose(80, "magical", false)
	_check("魔法 shape=diamond", m.shape == "diamond")
	_check("魔法 color=紫", m.color == DamagePopup.COLOR_MAGIC)

	# 纯粹 → 星 + 金
	var u: Dictionary = DamagePopup.compose(50, "pure", false)
	_check("纯粹 shape=star", u.shape == "star")
	_check("纯粹 color=金", u.color == DamagePopup.COLOR_PURE)

	# 混合 → hybrid + 橙
	var h: Dictionary = DamagePopup.compose(60, "hybrid", false)
	_check("混合 shape=hybrid", h.shape == "hybrid")
	_check("混合 color=橙", h.color == DamagePopup.COLOR_HYBRID)

	# 暴击 → 数字 19 + ！后缀，不再用 CRIT!
	var c: Dictionary = DamagePopup.compose(300, "physical", true)
	_check("暴击 text=300！", c.text == "300！")
	_check("暴击不含旧 CRIT 文案", not ("CRIT" in c.text))
	_check("暴击 size=19", c.size == 19)
	_check("暴击 size > 普通 size", c.size > DamagePopup.NORMAL_SIZE)

	# 未知类型 → 回退 sword/白（不崩）
	var x: Dictionary = DamagePopup.compose(10, "???", false)
	_check("未知类型回退 shape=sword", x.shape == "sword")
	_check("未知类型回退 color=白", x.color == DamagePopup.COLOR_PHYS)

	# 形状映射：治疗 / 未命中
	_check("治疗 shape=heal", DamagePopup._type_shape("heal") == "heal")
	_check("miss → none（无字形）", DamagePopup._type_shape("miss") == "none")
	_check("治疗配色=绿", DamagePopup._type_color("heal") == DamagePopup.COLOR_HEAL)

	# 已经由 Unit 计算完成的最终锚点不得再次叠加旧版 -50 像素偏移。
	var parent := Node2D.new()
	root.add_child(parent)
	var anchor := Vector2(120, 80)
	var legacy_origin := DamagePopup._compute_origin(
		anchor, "12", "sword", 16, 0, true)
	var final_origin := DamagePopup._compute_origin(
		anchor, "12", "sword", 16, 0, false)
	_check("旧 API 保留向上 50 像素", is_equal_approx(legacy_origin.y, anchor.y - 50.0))
	_check("最终锚点 API 不再减 50", is_equal_approx(final_origin.y, anchor.y))
	parent.free()

	_finish()


func _finish() -> void:
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		for f in _fails:
			print("  ✗ ", f)
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
