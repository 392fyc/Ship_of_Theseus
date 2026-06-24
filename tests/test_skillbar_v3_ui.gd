extends SceneTree
## 技能栏 v3 批4 局部 UI 回归（逻辑层可测部分）。
##
## 覆盖：
##   ① BottomDashboard.update_state 带 sword_qi/marks/sword_qi_config
##      → SwordQiBar 实例 sword_qi/sword_qi_max/threshold 正确绑定。
##   ② DamageForecaster.set_forecast 后 get_value_line_text 按 hit_count/is_heal
##      分支正确拼装（单段 / 多段 / 治疗）。
##   ③ 公开 API 红线自检：BottomDashboard 6 信号 + update_state；
##      DamageForecaster set_forecast。
##
## 渲染（分段条颜色/阈值线/印记满态/浮窗位置）headless 测不了 → 见 receipt 人工核验清单。
##
## 坑规避：preload 引用（不依赖全局 class_name 缓存）；断言放 _process 首帧。
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/test_skillbar_v3_ui.gd

# 注意：不直接 preload sword_qi_bar.gd（bottom_dashboard 已 preload 它，
# 测试再 preload 会与全局 class_name 注册双重加载冲突：Class "X" hides a global class）。
# damage_forecaster.gd 仅 tactical_scene 加载、本测试不加载该场景 → 单一加载路径，可 preload。
const BottomDashboardScript: GDScript = preload("res://scripts/ui/bottom_dashboard.gd")
const DamageForecasterScript: GDScript = preload("res://scripts/ui/damage_forecaster.gd")

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_skillbar_v3_ui (技能栏 v3 批4 UI 回归) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	_test_dashboard_sword_qi_binding()
	_test_forecaster_branches()
	_test_public_api()
	_finish()


# ── ① 资源条绑定 ─────────────────────────────────────
func _test_dashboard_sword_qi_binding() -> void:
	var dash: Control = BottomDashboardScript.new()
	root.add_child(dash)

	# 剑圣态：sword_qi=8 / max=10 / threshold=7（达标）+ 印记满 3
	dash.update_state({
		"visible": true,
		"show_actions": false,
		"unit_name": "剑圣",
		"hp": 30, "hp_max": 42,
		"sword_qi": 8, "sword_qi_max": 10,
		"sword_qi_config": {"speed_threshold": 7},
		"marks": {"心": true, "道": true, "势": true},
	})
	var bar: Control = dash._sword_qi_bar
	_check("SwordQiBar 实例存在", bar != null)
	if bar != null:
		_eq("SwordQiBar.sword_qi == 8", bar.sword_qi, 8)
		_eq("SwordQiBar.sword_qi_max == 10", bar.sword_qi_max, 10)
		_eq("SwordQiBar.threshold == 7（自 state.sword_qi_config）", bar.threshold, 7)
	_check("剑气区可见（剑圣单位）", dash._sword_qi_row.visible)
	# 印记满 3 → 各方块 held + full_state
	var block_xin: Control = dash._mark_blocks.get("心", null)
	_check("印记『心』方块存在", block_xin != null)
	if block_xin != null:
		_check("印记『心』held", block_xin.held)
		_check("印记满3 → full_state", block_xin.full_state)

	# 阈值缺省回退：state 不带 sword_qi_config → 回退 7
	dash.update_state({
		"visible": true, "show_actions": false, "unit_name": "剑圣",
		"hp": 30, "hp_max": 42,
		"sword_qi": 3, "sword_qi_max": 10,
		"marks": {"心": false, "道": false, "势": false},
	})
	if bar != null:
		_eq("缺省 threshold 回退 7", bar.threshold, 7)
		_eq("SwordQiBar.sword_qi == 3（未达标）", bar.sword_qi, 3)
	var block_xin2: Control = dash._mark_blocks.get("心", null)
	if block_xin2 != null:
		_check("无印记 → 『心』not held", not block_xin2.held)
		_check("无印记 → not full_state", not block_xin2.full_state)

	# 非剑圣（sword_qi=-1）→ 整区隐藏
	dash.update_state({
		"visible": true, "show_actions": false, "unit_name": "弓箭手",
		"hp": 20, "hp_max": 20,
		"sword_qi": -1, "sword_qi_max": 0,
	})
	_check("非剑圣单位 → 剑气区隐藏", not dash._sword_qi_row.visible)

	dash.free()


# ── ② 伤害预测器分支 ─────────────────────────────────
func _test_forecaster_branches() -> void:
	var fc: Control = DamageForecasterScript.new()

	# 单段物理：hit_count=1 → 「物理 · 24」
	fc.set_forecast({
		"visible": true, "damage_type": "physical", "is_heal": false,
		"hit_count": 1, "per_hit_damage": 24, "total_damage": 24, "damage": 24,
		"hit_percent": 92, "crit_percent": 35,
	})
	_eq("单段 → 物理 · 24", fc.get_value_line_text(), "物理 · 24")

	# 多段：hit_count=3 per_hit=12 total=36 → 「物理 3 × 12 (36)」
	fc.set_forecast({
		"visible": true, "damage_type": "physical", "is_heal": false,
		"hit_count": 3, "per_hit_damage": 12, "total_damage": 36, "damage": 36,
		"hit_percent": 92, "crit_percent": 35,
	})
	_eq("多段 → 物理 3 × 12 (36)", fc.get_value_line_text(), "物理 3 × 12 (36)")

	# 治疗：is_heal → 「治疗 · +16」无命中暴击
	fc.set_forecast({
		"visible": true, "damage_type": "holy", "is_heal": true,
		"hit_count": 1, "damage": 16, "total_damage": 16,
	})
	_eq("治疗 → 治疗 · +16", fc.get_value_line_text(), "治疗 · +16")

	# 魔法单段：类型名映射
	fc.set_forecast({
		"visible": true, "damage_type": "magical", "is_heal": false,
		"hit_count": 1, "per_hit_damage": 18, "total_damage": 18, "damage": 18,
		"hit_percent": 80, "crit_percent": 10,
	})
	_eq("魔法单段 → 魔法 · 18", fc.get_value_line_text(), "魔法 · 18")

	fc.free()


# ── ③ 公开 API 红线自检 ──────────────────────────────
func _test_public_api() -> void:
	var dash: Control = BottomDashboardScript.new()
	for sig: String in [
		"attack_requested", "skill_toggle_requested", "skill_selected",
		"end_turn_requested", "end_move_requested", "cancel_requested",
	]:
		_check("BottomDashboard 信号 %s 存在" % sig, dash.has_signal(sig))
	_check("BottomDashboard.update_state 存在", dash.has_method("update_state"))
	dash.free()

	var fc: Control = DamageForecasterScript.new()
	_check("DamageForecaster.set_forecast 存在", fc.has_method("set_forecast"))
	fc.free()


func _finish() -> void:
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  ✗ " + f)
	else:
		print("OK")
	quit(0 if _fail == 0 else 1)


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
