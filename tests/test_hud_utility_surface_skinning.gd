extends SceneTree

const THEME_PATH: String = "res://assets/ui/themes/hud_structure_prototype.tres"
const POTION_SCENE_PATH: String = "res://scenes/tactical/hud/potion_button.tscn"
const END_BUTTON_SCENE_PATH: String = "res://scenes/tactical/hud/end_turn_button.tscn"
const POTION_ASSET_PATH: String = "res://assets/ui/skins/hud/potion_button_shell_v1.png"
const DIAMOND_ASSET_PATH: String = "res://assets/ui/skins/hud/end_action_diamond_frame_v1.png"
const HOURGLASS_ASSET_PATH: String = "res://assets/ui/skins/hud/end_action_hourglass_emblem_v1.png"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_hud_utility_surface_skinning ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	_check("HUD Theme 可加载", theme != null)
	if theme != null:
		_test_potion_surface(theme)
	_test_end_action_layers()
	_finish()


func _test_potion_surface(theme: Theme) -> void:
	_check("血瓶按钮外壳最终 PNG 存在", FileAccess.file_exists(POTION_ASSET_PATH))
	var normal: StyleBox = theme.get_stylebox(&"normal", &"HudPotionButton32")
	_check("血瓶按钮外壳使用 StyleBoxTexture", normal is StyleBoxTexture)
	if normal is StyleBoxTexture:
		var textured := normal as StyleBoxTexture
		_check("血瓶按钮只引用自己的正式候选", textured.texture != null
			and textured.texture.resource_path == POTION_ASSET_PATH)
		_eq("血瓶外壳九宫格左边距", textured.texture_margin_left, 5.0)
		_eq("血瓶外壳九宫格上边距", textured.texture_margin_top, 5.0)
	_test_image(POTION_ASSET_PATH, Vector2i(32, 32), true, "血瓶按钮外壳")

	var packed: PackedScene = load(POTION_SCENE_PATH) as PackedScene
	_check("血瓶按钮场景可加载", packed != null)
	if packed != null:
		var button: Button = packed.instantiate() as Button
		_check("血瓶运行时图标接口保持独立", button.get_node_or_null("Content/IconRect") is TextureRect)
		_check("血瓶按钮不含固定文字", button.text == "")
		button.free()


func _test_end_action_layers() -> void:
	_check("结束菱形框最终 PNG 存在", FileAccess.file_exists(DIAMOND_ASSET_PATH))
	_check("沙漏图形最终 PNG 存在", FileAccess.file_exists(HOURGLASS_ASSET_PATH))
	_test_image(DIAMOND_ASSET_PATH, Vector2i(44, 44), true, "结束菱形框")
	_test_image(HOURGLASS_ASSET_PATH, Vector2i(18, 24), false, "沙漏图形")

	var packed: PackedScene = load(END_BUTTON_SCENE_PATH) as PackedScene
	_check("结束按钮场景可加载", packed != null)
	if packed == null:
		return
	var button: Button = packed.instantiate() as Button
	var diamond: TextureRect = button.get_node_or_null("DiamondFrame") as TextureRect
	var hourglass: TextureRect = button.get_node_or_null("HourglassEmblem") as TextureRect
	_check("菱形框由独立 TextureRect 消费", diamond != null)
	_check("沙漏由独立 TextureRect 消费", hourglass != null)
	if diamond != null:
		_eq("菱形框保持 44×44", diamond.size, Vector2(44, 44))
		_check("菱形框只引用自己的正式候选", diamond.texture != null
			and diamond.texture.resource_path == DIAMOND_ASSET_PATH)
	if hourglass != null:
		_eq("沙漏保持 18×24", hourglass.size, Vector2(18, 24))
		_check("沙漏只引用自己的正式候选", hourglass.texture != null
			and hourglass.texture.resource_path == HOURGLASS_ASSET_PATH)
	if diamond != null and hourglass != null:
		var left_gap: float = hourglass.position.x - diamond.position.x
		var top_gap: float = hourglass.position.y - diamond.position.y
		var right_gap: float = (diamond.position.x + diamond.size.x) \
			- (hourglass.position.x + hourglass.size.x)
		var bottom_gap: float = (diamond.position.y + diamond.size.y) \
			- (hourglass.position.y + hourglass.size.y)
		_check("沙漏与菱形四边至少保留 5px",
			minf(minf(left_gap, right_gap), minf(top_gap, bottom_gap)) >= 5.0)
	_eq("结束按钮点击区保持 52×52", button.size, Vector2(52, 52))
	_check("结束按钮不含 END 文字", button.text == "")
	button.call("set_interaction_enabled", true)
	button.call("_on_mouse_entered")
	var hover_modulate: Color = button.modulate
	button.call("_on_button_down")
	_check("结束按钮按下反馈由父 Button 调制", button.modulate != hover_modulate)
	button.call("set_interaction_enabled", false)
	var disabled_modulate: Color = button.modulate
	button.call("_on_mouse_entered")
	_check("禁用结束按钮不进入悬停态", button.modulate == disabled_modulate)
	button.free()


func _test_image(path: String, expected_size: Vector2i, center_transparent: bool,
		label: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	_check("%s 图像数据可读取" % label, image != null and not image.is_empty())
	if image == null or image.is_empty():
		return
	_eq("%s 使用目标尺寸" % label, image.get_size(), expected_size)
	_check("%s 完整一像素外缘透明" % label, _outer_border_is_transparent(image))
	if center_transparent:
		_check("%s 中心内容区透明" % label,
			image.get_pixel(image.get_width() / 2, image.get_height() / 2).a <= 0.02)
	_check("%s 仍包含可见材质" % label, _has_visible_pixel(image))


func _outer_border_is_transparent(image: Image) -> bool:
	for x: int in image.get_width():
		if image.get_pixel(x, 0).a > 0.02 or image.get_pixel(x, image.get_height() - 1).a > 0.02:
			return false
	for y: int in image.get_height():
		if image.get_pixel(0, y).a > 0.02 or image.get_pixel(image.get_width() - 1, y).a > 0.02:
			return false
	return true


func _has_visible_pixel(image: Image) -> bool:
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a >= 0.25:
				return true
	return false


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
