extends SceneTree

const ActionResourceBarScript: GDScript = preload("res://scripts/ui/action_resource_bar.gd")

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_action_resource_bar ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	_test_resource_order_state_and_stable_instances()
	_test_visual_contract_and_missing_data_visibility()
	_finish()


func _test_resource_order_state_and_stable_instances() -> void:
	var bar: PanelContainer = ActionResourceBarScript.new()
	root.add_child(bar)
	bar.update_resources({
		"movement_used": false,
		"standard_used": true,
		"swift_used": false,
	})
	_eq("资源顺序固定", bar._segments.keys(), ["movement", "standard", "swift"])
	var original_ids: Array[int] = []
	for resource_id: String in ["movement", "standard", "swift"]:
		original_ids.append((bar._segments[resource_id] as Object).get_instance_id())
	_check("M 可用", not bar._segments["movement"].spent)
	_check("A 已用", bar._segments["standard"].spent)
	_check("S 可用", not bar._segments["swift"].spent)
	_eq("M 标题", bar._segments["movement"].title_label.text, "M 移动")
	_eq("A 状态文字", bar._segments["standard"].state_label.text, "已用")
	_check("已用态有斜向缺口", bar._segments["standard"].glyph.spent)
	bar.update_resources({"movement_used": true, "standard_used": false, "swift_used": true})
	var updated_ids: Array[int] = []
	for resource_id: String in ["movement", "standard", "swift"]:
		updated_ids.append((bar._segments[resource_id] as Object).get_instance_id())
	_eq("重复更新不会重建段", updated_ids, original_ids)
	_check("第二次状态精确", bar._segments["movement"].spent and not bar._segments["standard"].spent and bar._segments["swift"].spent)
	bar.free()


func _test_visual_contract_and_missing_data_visibility() -> void:
	var bar: PanelContainer = ActionResourceBarScript.new()
	root.add_child(bar)
	var resource_entries: Array[Dictionary] = [
		{"id": "movement", "spent": false},
		{"id": "standard", "spent": false},
		{"id": "swift", "spent": false},
	]
	bar.set_resources(resource_entries)
	_check("有完整数据时显示", bar.visible)
	_eq("外壳底色", (bar.get_theme_stylebox("panel") as StyleBoxFlat).bg_color, Color("#0A0B12F5"))
	_eq("外壳边框", (bar.get_theme_stylebox("panel") as StyleBoxFlat).border_color, Color("#8F743D"))
	var outer_margin: MarginContainer = bar.get_child(0) as MarginContainer
	_check("外壳包含边距容器", outer_margin != null)
	if outer_margin != null:
		_eq("外壳左边距", outer_margin.get_theme_constant("margin_left"), 6)
		_eq("外壳右边距", outer_margin.get_theme_constant("margin_right"), 6)
		_eq("外壳上边距", outer_margin.get_theme_constant("margin_top"), 4)
		_eq("外壳下边距", outer_margin.get_theme_constant("margin_bottom"), 4)
		var row: HBoxContainer = outer_margin.get_child(0) as HBoxContainer
		_check("边距容器包含资源行", row != null)
		if row != null:
			_eq("资源段间距", row.get_theme_constant("separation"), 4)
	for resource_id: String in ["movement", "standard", "swift"]:
		var segment: Control = bar._segments[resource_id]
		_eq("%s 段尺寸" % resource_id, segment.custom_minimum_size, Vector2(76.0, 30.0))
	_eq("M 强调色", bar._segments["movement"].glyph.accent_color, Color("#6FAED1"))
	_eq("A 强调色", bar._segments["standard"].glyph.accent_color, Color("#D17A50"))
	_eq("S 强调色", bar._segments["swift"].glyph.accent_color, Color("#D5BC59"))
	_eq("可用文字", bar._segments["movement"].state_label.text, "可用")
	for resource_id: String in ["movement", "standard", "swift"]:
		var available_segment: PanelContainer = bar._segments[resource_id]
		var available_style: StyleBoxFlat = available_segment.get_theme_stylebox("panel") as StyleBoxFlat
		_eq("%s 可用背景" % resource_id, available_style.bg_color, Color("#121722"))
		_eq("%s 可用边框" % resource_id, available_style.border_color, available_segment.glyph.accent_color)
		_eq("%s 可用标题颜色" % resource_id, available_segment.title_label.get_theme_color("font_color"), Color("#E5DBCB"))
		_eq("%s 可用状态颜色" % resource_id, available_segment.state_label.get_theme_color("font_color"), available_segment.glyph.accent_color)
	bar.update_resources({"movement_used": true, "standard_used": true, "swift_used": true})
	for resource_id: String in ["movement", "standard", "swift"]:
		var spent_segment: PanelContainer = bar._segments[resource_id]
		var spent_style: StyleBoxFlat = spent_segment.get_theme_stylebox("panel") as StyleBoxFlat
		_eq("%s 已用背景" % resource_id, spent_style.bg_color, Color("#23232A"))
		_eq("%s 已用边框" % resource_id, spent_style.border_color, Color("#6C6872"))
		_eq("%s 已用标题颜色" % resource_id, spent_segment.title_label.get_theme_color("font_color"), Color("#6C6872"))
		_eq("%s 已用状态颜色" % resource_id, spent_segment.state_label.get_theme_color("font_color"), Color("#6C6872"))
	bar.clear_resources()
	_check("清除数据后隐藏", not bar.visible)
	var incomplete_entries: Array[Dictionary] = [{"id": "movement", "spent": false}]
	bar.set_resources(incomplete_entries)
	_check("数据缺失时隐藏", not bar.visible)
	_check("组件不持有 Unit", not ("Unit" in bar.get_script().source_code))
	bar.free()


func _finish() -> void:
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for failure: String in _fails:
			print("  ✗ " + failure)
	else:
		print("OK")
	quit(0 if _fail == 0 else 1)


func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		_fails.append(name + ("  [" + detail + "]" if detail != "" else ""))
		print("  ✗ " + name + ("  [" + detail + "]" if detail != "" else ""))


func _eq(name: String, actual: Variant, expected: Variant) -> void:
	_check(name, actual == expected, "期望 %s 实际 %s" % [str(expected), str(actual)])
