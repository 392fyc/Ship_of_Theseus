extends SceneTree

const THEME_PATH: String = "res://assets/ui/themes/hud_structure_prototype.tres"
const SKILL_SCENE_PATH: String = "res://scenes/tactical/hud/skill_slot_button.tscn"
const RESOURCE_SCENE_PATH: String = "res://scenes/tactical/hud/action_resource_strip.tscn"
const SKILL_TEXTURE_PATH: String = "res://assets/ui/skins/hud/skill_slot_surface_v1.png"
const RESOURCE_TEXTURE_PATH: String = "res://assets/ui/skins/hud/action_resource_strip_surface_v1.png"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_hud_surface_skinning ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	_check("HUD Theme 可加载", theme != null)
	if theme == null:
		_finish()
		return

	_check_surface(
		"技能槽中性表面",
		theme.get_stylebox(&"normal", &"SkillSlotButton"),
		SKILL_TEXTURE_PATH,
		Vector2i(64, 64)
	)
	_check_surface(
		"行动资源条中性表面",
		theme.get_stylebox(&"panel", &"ActionResourceStrip"),
		RESOURCE_TEXTURE_PATH,
		Vector2i(274, 40)
	)
	_check_skill_states_share_texture(theme)
	_check_runtime_layers_remain_declarative()
	_finish()


func _check_surface(label: String, style: StyleBox, expected_path: String,
		expected_size: Vector2i) -> void:
	var textured: StyleBoxTexture = style as StyleBoxTexture
	_check(label + "使用 StyleBoxTexture", textured != null)
	if textured == null:
		return
	_check(label + "纹理可加载", textured.texture != null)
	if textured.texture == null:
		return
	_eq(label + "使用独立正式候选", textured.texture.resource_path, expected_path)
	var image := textured.texture.get_image()
	_check(label + "图像数据可读取", image != null and not image.is_empty())
	if image == null or image.is_empty():
		return
	_eq(label + "使用目标导入尺寸", image.get_size(), expected_size)
	_check(label + "外部为真实透明", image.get_pixel(0, 0).a <= 0.04)
	_check(
		label + "中心内容区为真实透明",
		image.get_pixel(int(image.get_width() / 2), int(image.get_height() / 2)).a <= 0.04
	)
	_check(label + "声明九宫格边距", textured.texture_margin_left > 0.0
		and textured.texture_margin_top > 0.0
		and textured.texture_margin_right > 0.0
		and textured.texture_margin_bottom > 0.0)


func _check_skill_states_share_texture(theme: Theme) -> void:
	var paths: Array[String] = []
	for state: StringName in [&"normal", &"hover", &"pressed", &"disabled"]:
		var style: StyleBoxTexture = theme.get_stylebox(state, &"SkillSlotButton") as StyleBoxTexture
		_check("技能槽 %s 状态使用纹理表面" % state, style != null)
		if style != null and style.texture != null:
			paths.append(style.texture.resource_path)
	_eq("技能槽交互状态共用一张中性表面", paths, [SKILL_TEXTURE_PATH, SKILL_TEXTURE_PATH, SKILL_TEXTURE_PATH, SKILL_TEXTURE_PATH])


func _check_runtime_layers_remain_declarative() -> void:
	var skill_packed: PackedScene = load(SKILL_SCENE_PATH) as PackedScene
	var resource_packed: PackedScene = load(RESOURCE_SCENE_PATH) as PackedScene
	_check("技能槽场景可加载", skill_packed != null)
	_check("行动资源条场景可加载", resource_packed != null)
	if skill_packed == null or resource_packed == null:
		return

	var skill: Control = skill_packed.instantiate() as Control
	var resource: Control = resource_packed.instantiate() as Control
	_check("冷却暗层仍由场景声明", skill.get_node_or_null("Content/CooldownShade") != null)
	_check("冷却数字仍由场景声明", skill.get_node_or_null("Content/CooldownTurnsLabel") != null)
	_check("标准行动点容器仍由场景声明", resource.get_node_or_null("Margin/MainRow/StandardZone/StandardPips") != null)
	_check("迅捷行动点容器仍由场景声明", resource.get_node_or_null("Margin/MainRow/SwiftZone/SwiftPips") != null)
	skill.free()
	resource.free()


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
