extends SceneTree

const THEME_PATH: String = "res://assets/ui/themes/hud_structure_prototype.tres"
const CHARACTER_SCENE_PATH: String = "res://scenes/tactical/hud/character_hud_panel.tscn"
const VIEW_DATA_PATH: String = "res://scripts/ui/hud/character_hud_view_data.gd"
const CHARACTER_TEXTURE_PATH: String = "res://assets/ui/skins/hud/character_panel_surface_v1.png"
const PORTRAIT_TEXTURE_PATH: String = "res://assets/ui/skins/hud/portrait_frame_surface_v1.png"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_hud_character_surface_skinning ===")


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
		"角色栏中性外壳",
		theme.get_stylebox(&"panel", &"CharacterHudPanel"),
		CHARACTER_TEXTURE_PATH,
		Vector2i(226, 108)
	)
	_check_surface(
		"头像框中性外壳",
		theme.get_stylebox(&"panel", &"HudPortraitFrame"),
		PORTRAIT_TEXTURE_PATH,
		Vector2i(72, 82)
	)
	_check_meter_styles_remain_runtime(theme)
	await _check_runtime_layers_remain_declarative()
	_finish()


func _check_surface(label: String, style: StyleBox, expected_path: String,
		expected_size: Vector2i) -> void:
	var file_exists: bool = FileAccess.file_exists(expected_path)
	_check(label + "最终 PNG 存在", file_exists)
	var textured: StyleBoxTexture = style as StyleBoxTexture
	_check(label + "使用 StyleBoxTexture", textured != null)
	if not file_exists or textured == null:
		return
	_check(label + "纹理可加载", textured.texture != null)
	if textured.texture == null:
		return
	_eq(label + "只引用自己的正式候选", textured.texture.resource_path, expected_path)
	var image: Image = textured.texture.get_image()
	_check(label + "图像数据可读取", image != null and not image.is_empty())
	if image == null or image.is_empty():
		return
	_eq(label + "使用目标导入尺寸", image.get_size(), expected_size)
	_check(label + "一像素外缘为真实透明", _outer_edge_is_transparent(image))
	_check(label + "中心内容区为真实透明",
		image.get_pixel(int(image.get_width() / 2), int(image.get_height() / 2)).a <= 0.04)
	_check(label + "边框仍含有可见材质", _has_visible_frame(image))
	_check(label + "声明九宫格边距", textured.texture_margin_left > 0.0
		and textured.texture_margin_top > 0.0
		and textured.texture_margin_right > 0.0
		and textured.texture_margin_bottom > 0.0)


func _outer_edge_is_transparent(image: Image) -> bool:
	for x: int in image.get_width():
		if image.get_pixel(x, 0).a > 0.04 \
				or image.get_pixel(x, image.get_height() - 1).a > 0.04:
			return false
	for y: int in image.get_height():
		if image.get_pixel(0, y).a > 0.04 \
				or image.get_pixel(image.get_width() - 1, y).a > 0.04:
			return false
	return true


func _has_visible_frame(image: Image) -> bool:
	for y: int in range(1, image.get_height() - 1):
		for x: int in range(1, image.get_width() - 1):
			if image.get_pixel(x, y).a >= 0.5:
				return true
	return false


func _check_meter_styles_remain_runtime(theme: Theme) -> void:
	for meter_type: StringName in [&"HudExperienceMeter", &"HudHpMeter", &"HudShieldMeter"]:
		_check("%s 轨道背景仍由 Theme 绘制" % meter_type,
			theme.get_stylebox(&"background", meter_type) is StyleBoxFlat)
		_check("%s 动态填充仍由 Theme 绘制" % meter_type,
			theme.get_stylebox(&"fill", meter_type) is StyleBoxFlat)


func _check_runtime_layers_remain_declarative() -> void:
	var packed: PackedScene = load(CHARACTER_SCENE_PATH) as PackedScene
	var view_script: GDScript = load(VIEW_DATA_PATH) as GDScript
	_check("角色栏场景可加载", packed != null)
	_check("角色栏显示数据可加载", view_script != null)
	if packed == null or view_script == null:
		return

	var panel: Control = packed.instantiate() as Control
	var identity: Label = panel.get_node_or_null(
		"Margin/ContentRow/InfoColumn/IdentityLabel") as Label
	var level_label: Label = panel.get_node_or_null(
		"Margin/ContentRow/InfoColumn/LevelExperienceRow/LevelLabel") as Label
	var portrait: TextureRect = panel.get_node_or_null(
		"Margin/ContentRow/PortraitFrame/PortraitContent") as TextureRect
	var fallback: Label = panel.get_node_or_null(
		"Margin/ContentRow/PortraitFrame/PortraitFallback") as Label
	var experience_track: ProgressBar = panel.get_node_or_null(
		"Margin/ContentRow/InfoColumn/LevelExperienceRow/ExperienceMeter/Track") as ProgressBar
	var hp_track: ProgressBar = panel.get_node_or_null(
		"Margin/ContentRow/InfoColumn/SurvivalFrame/SurvivalColumn/HpMeter/Track") as ProgressBar
	var shield_track: ProgressBar = panel.get_node_or_null(
		"Margin/ContentRow/InfoColumn/SurvivalFrame/SurvivalColumn/ShieldMeter/Track") as ProgressBar
	var experience_label: Label = panel.get_node_or_null(
		"Margin/ContentRow/InfoColumn/LevelExperienceRow/ExperienceMeter/ValueLabel") as Label
	var hp_label: Label = panel.get_node_or_null(
		"Margin/ContentRow/InfoColumn/SurvivalFrame/SurvivalColumn/HpMeter/ValueLabel") as Label
	var shield_label: Label = panel.get_node_or_null(
		"Margin/ContentRow/InfoColumn/SurvivalFrame/SurvivalColumn/ShieldMeter/ValueLabel") as Label

	_check("职业和玩家名仍由动态 Label 承担", identity != null)
	_check("等级仍由动态 Label 承担", level_label != null)
	_check("经验、HP、护盾仍是三个独立 ProgressBar",
		experience_track != null and hp_track != null and shield_track != null)
	_check("三个数值仍由独立 Label 承担",
		experience_label != null and hp_label != null and shield_label != null)
	_check("头像内容仍保留 TextureRect 接口", portrait != null)
	_check("头像 fallback 仍是独立 Label", fallback != null)
	if identity == null or level_label == null or portrait == null or fallback == null \
			or experience_track == null or hp_track == null or shield_track == null \
			or experience_label == null or hp_label == null or shield_label == null:
		panel.free()
		return

	root.add_child(panel)
	await process_frame
	await process_frame
	var view: RefCounted = view_script.new()
	view.set("profession_name", "剑圣")
	view.set("player_name", "fyc")
	view.set("level", 12)
	view.set("portrait_fallback_text", "剑")
	var experience: RefCounted = view.get("experience") as RefCounted
	experience.set("current_value", 125)
	experience.set("maximum_value", 500)
	var hp: RefCounted = view.get("hp") as RefCounted
	hp.set("current_value", 78)
	hp.set("maximum_value", 120)
	var shield: RefCounted = view.get("shield") as RefCounted
	shield.set("current_value", 14)
	shield.set("maximum_value", 40)
	panel.call("apply_view", view)

	_eq("图片接入不会替代职业和玩家名", identity.text, "剑圣 · fyc")
	_eq("图片接入不会替代等级", level_label.text, "Lv. 12")
	_eq("图片接入不会替代经验数值", experience_label.text, "125/500")
	_eq("图片接入不会替代 HP 数值", hp_label.text, "78/120")
	_eq("图片接入不会替代护盾数值", shield_label.text, "14/40")
	_eq("经验填充仍响应运行时比例", experience_track.value, 0.25)
	_eq("HP 填充仍响应运行时比例", hp_track.value, 0.65)
	_eq("护盾填充仍响应运行时比例", shield_track.value, 0.35)
	_check("缺少头像时 fallback 由显示数据提供",
		portrait.texture == null and fallback.visible and fallback.text == "剑")
	var runtime_portrait := GradientTexture2D.new()
	view.set("portrait_texture", runtime_portrait)
	panel.call("apply_view", view)
	_check("运行时头像纹理仍可替换且隐藏 fallback",
		portrait.texture == runtime_portrait and not fallback.visible)

	panel.queue_free()
	await process_frame


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
