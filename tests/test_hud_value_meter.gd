extends SceneTree

const VIEW_DATA_PATH: String = "res://scripts/ui/hud/value_meter_view_data.gd"
const SCENE_PATH: String = "res://scenes/tactical/hud/value_meter.tscn"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_hud_value_meter ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var view_script: GDScript = load(VIEW_DATA_PATH) as GDScript
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_check("有类型数值条显示数据脚本存在", view_script != null)
	_check("数值条场景存在", packed != null)
	if view_script == null or packed == null:
		_finish()
		return

	_test_ratio_and_text_contract(view_script)
	await _test_declared_scene_and_binding(view_script, packed)
	_finish()


func _test_ratio_and_text_contract(view_script: GDScript) -> void:
	var view: RefCounted = view_script.new()
	view.set("current_value", 25)
	view.set("maximum_value", 100)
	_eq("部分值比例由输入产生", view.get("ratio"), 0.25)
	_eq("数值文字由输入产生", view.get("display_text"), "25/100")

	view.set("current_value", 125)
	_eq("超过上限的比例限制为一", view.get("ratio"), 1.0)
	_eq("超过上限仍保留真实输入文字", view.get("display_text"), "125/100")

	view.set("current_value", -8)
	_eq("负当前值比例限制为零", view.get("ratio"), 0.0)
	view.set("current_value", 20)
	view.set("maximum_value", 0)
	_eq("最大值为零时比例安全归零", view.get("ratio"), 0.0)
	_eq("非法最大值按零显示", view.get("display_text"), "20/0")
	view.set("maximum_value", -9)
	_eq("负最大值比例安全归零", view.get("ratio"), 0.0)
	_eq("负最大值不会进入显示", view.get("display_text"), "20/0")

	var property_names: Array[String] = []
	for property: Dictionary in view.get_property_list():
		property_names.append(str(property["name"]).to_lower())
	for forbidden: String in ["unit", "run_state", "game_action"]:
		_check("数值条显示数据不持有 %s" % forbidden,
			property_names.all(func(name: String) -> bool: return forbidden not in name))


func _test_declared_scene_and_binding(view_script: GDScript, packed: PackedScene) -> void:
	var meter: Control = packed.instantiate() as Control
	_check("数值条根节点可实例化", meter != null)
	if meter == null:
		return
	_check("轨道与文字层由 tscn 声明",
		meter.get_node_or_null("Track") is ProgressBar
		and meter.get_node_or_null("ValueLabel") is Label)
	_check("数值条场景序列化完整静态树", packed.get_state().get_node_count() == 3)

	root.add_child(meter)
	await process_frame
	await process_frame
	var track: ProgressBar = meter.get_node("Track") as ProgressBar
	var value_label: Label = meter.get_node("ValueLabel") as Label
	_eq("轨道使用标准化比例上限", track.max_value, 1.0)
	_check("轨道不显示内建百分比", not track.show_percentage)
	_eq("数值文字右对齐", value_label.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT)
	_eq("数值文字垂直居中", value_label.vertical_alignment, VERTICAL_ALIGNMENT_CENTER)
	_check("数值文字启用单行裁切", value_label.clip_text)

	var view: RefCounted = view_script.new()
	view.set("current_value", 75)
	view.set("maximum_value", 100)
	meter.call("apply_view", view)
	_eq("部分值绑定到轨道", track.value, 0.75)
	_eq("部分值绑定到运行时文字", value_label.text, "75/100")
	_eq("普通数值使用 11px 字号", value_label.get_theme_font_size(&"font_size"), 11)
	_check("普通数值不保留局部字号覆盖",
		not value_label.has_theme_font_size_override(&"font_size"))

	view.set("current_value", 100)
	meter.call("apply_view", view)
	_eq("满值填满轨道", track.value, 1.0)
	view.set("current_value", 170)
	meter.call("apply_view", view)
	_eq("超上限值不会越过轨道", track.value, 1.0)
	_eq("超上限文字不被伪造", value_label.text, "170/100")
	view.set("current_value", 44)
	view.set("maximum_value", 0)
	meter.call("apply_view", view)
	_eq("非法最大值清空轨道", track.value, 0.0)
	_eq("非法最大值仍提供明确数值", value_label.text, "44/0")
	view.set("current_value", 999999)
	view.set("maximum_value", 999999)
	meter.call("apply_view", view)
	_eq("超长数值文字来自运行时输入", value_label.text, "999999/999999")
	_eq("十三字符数值局部降为 9px", value_label.get_theme_font_size(&"font_size"), 9)
	_check("十三字符数值使用局部字号覆盖",
		value_label.has_theme_font_size_override(&"font_size"))
	meter.custom_minimum_size = Vector2(82, 22)
	meter.size = Vector2(82, 22)
	await process_frame
	_eq("经验数值条语境宽度为 82", meter.size.x, 82.0)
	_eq("经验数值标签扣除右侧安全距后有 79 像素可用宽度", value_label.size.x, 79.0)
	_check("十三字符 9px 数值含描边后适配经验数值标签宽度",
		_rendered_text_width_with_outline(value_label) <= value_label.size.x + 0.01,
		"rendered=%s available=%s" % [
			str(_rendered_text_width_with_outline(value_label)), str(value_label.size.x)])
	_check("超长数值层保持在组件边界内", value_label.position.x >= 0.0
		and value_label.position.y >= 0.0
		and value_label.position.x + value_label.size.x <= meter.size.x + 0.01
		and value_label.position.y + value_label.size.y <= meter.size.y + 0.01,
		"meter pos=%s size=%s; label pos=%s size=%s" % [
			str(meter.position), str(meter.size), str(value_label.position), str(value_label.size)])
	meter.custom_minimum_size = Vector2(120, 13)
	meter.size = Vector2(120, 13)
	await process_frame
	_eq("HP 与护盾数值条语境宽度为 120", meter.size.x, 120.0)
	_eq("HP 与护盾数值标签扣除右侧安全距后有 117 像素可用宽度",
		value_label.size.x, 117.0)
	_check("十三字符 9px 数值含描边后适配 HP 与护盾数值标签宽度",
		_rendered_text_width_with_outline(value_label) <= value_label.size.x + 0.01,
		"rendered=%s available=%s" % [
			str(_rendered_text_width_with_outline(value_label)), str(value_label.size.x)])
	view.set("current_value", 44)
	view.set("maximum_value", 100)
	meter.call("apply_view", view)
	_eq("恢复短值后回到 11px 字号", value_label.get_theme_font_size(&"font_size"), 11)
	_check("恢复短值后移除局部字号覆盖",
		not value_label.has_theme_font_size_override(&"font_size"))

	meter.queue_free()
	await process_frame


func _rendered_text_width_with_outline(label: Label) -> float:
	var font: Font = label.get_theme_font(&"font")
	var glyph_width: float = font.get_string_size(label.text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		label.get_theme_font_size(&"font_size")).x
	return glyph_width + float(label.get_theme_constant(&"outline_size") * 2)


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
		return
	_fail += 1
	_fails.append(name + ("  [" + detail + "]" if detail != "" else ""))
	print("  ✗ " + name + ("  [" + detail + "]" if detail != "" else ""))


func _eq(name: String, actual: Variant, expected: Variant) -> void:
	_check(name, actual == expected, "期望 %s 实际 %s" % [str(expected), str(actual)])
