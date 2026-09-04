extends SceneTree

const FONT_PATH: String = "res://assets/fonts/ibm_plex_mono/IBMPlexMono-SemiBold.ttf"
const THEME_PATH: String = "res://assets/ui/themes/hud_structure_prototype.tres"
const METER_SCENE_PATH: String = "res://scenes/tactical/hud/value_meter.tscn"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_hud_numeric_font_theme_integration ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var candidate: FontFile = load(FONT_PATH) as FontFile
	var theme: Theme = load(THEME_PATH) as Theme
	var packed: PackedScene = load(METER_SCENE_PATH) as PackedScene
	_check("候选字体可加载", candidate != null)
	_check("开发 HUD 主题可加载", theme != null)
	_check("数值条场景可加载", packed != null)
	if candidate == null or theme == null or packed == null:
		_finish()
		return

	_check("主题为数值标签声明专用字体", theme.has_font(&"font", &"HudMeterValueLabel"))
	_check("数值标签专用字体是已审查候选",
		theme.get_font(&"font", &"HudMeterValueLabel") == candidate)
	_check("身份标签没有继承数值专用字体",
		not theme.has_font(&"font", &"HudIdentityLabel"))
	_check("等级标签没有继承数值专用字体",
		not theme.has_font(&"font", &"HudLevelLabel"))

	var meter: Control = packed.instantiate() as Control
	root.add_child(meter)
	await process_frame
	await process_frame
	var value_label: Label = meter.get_node("ValueLabel") as Label
	_check("数值标签不持有局部字体覆盖", not value_label.has_theme_font_override(&"font"))
	_check("数值标签从主题取得候选字体", value_label.get_theme_font(&"font") == candidate)
	_eq("主题默认字号统一提升为 11px", value_label.get_theme_font_size(&"font_size"), 11)
	_eq("数值标签保持 1px 描边", value_label.get_theme_constant(&"outline_size"), 1)

	var view_script: GDScript = load("res://scripts/ui/hud/value_meter_view_data.gd") as GDScript
	var view: RefCounted = view_script.new()
	view.set("current_value", 999999)
	view.set("maximum_value", 999999)
	meter.call("apply_view", view)
	_eq("十三字符数值降为 9px", value_label.get_theme_font_size(&"font_size"), 9)
	_check("长值只覆盖字号，不覆盖字体",
		value_label.has_theme_font_size_override(&"font_size")
		and not value_label.has_theme_font_override(&"font"))
	var rendered_width: float = candidate.get_string_size(value_label.text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		value_label.get_theme_font_size(&"font_size")).x + 2.0
	_check("十三字符数值含描边的实际渲染宽度不超过标签可用宽度",
		rendered_width <= value_label.size.x + 0.01,
		"rendered=%s available=%s" % [str(rendered_width), str(value_label.size.x)])
	view.set("current_value", 34)
	view.set("maximum_value", 100)
	meter.call("apply_view", view)
	_eq("短值恢复为 11px", value_label.get_theme_font_size(&"font_size"), 11)
	_check("短值恢复后移除局部字号覆盖",
		not value_label.has_theme_font_size_override(&"font_size"))

	meter.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
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
