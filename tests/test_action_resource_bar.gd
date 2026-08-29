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
	for resource_id: String in ["movement", "standard", "swift"]:
		var segment: Control = bar._segments[resource_id]
		_eq("%s 段尺寸" % resource_id, segment.custom_minimum_size, Vector2(76.0, 30.0))
	_eq("M 强调色", bar._segments["movement"].glyph.accent_color, Color("#6FAED1"))
	_eq("A 强调色", bar._segments["standard"].glyph.accent_color, Color("#D17A50"))
	_eq("S 强调色", bar._segments["swift"].glyph.accent_color, Color("#D5BC59"))
	_eq("可用文字", bar._segments["movement"].state_label.text, "可用")
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
