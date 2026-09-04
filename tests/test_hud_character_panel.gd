extends SceneTree

const VIEW_DATA_PATH: String = "res://scripts/ui/hud/character_hud_view_data.gd"
const SCENE_PATH: String = "res://scenes/tactical/hud/character_hud_panel.tscn"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_hud_character_panel ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var view_script: GDScript = load(VIEW_DATA_PATH) as GDScript
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_check("有类型角色栏显示数据脚本存在", view_script != null)
	_check("角色栏场景存在", packed != null)
	if view_script == null or packed == null:
		_finish()
		return

	_test_view_data_isolation(view_script)
	await _test_declared_layout_and_binding(view_script, packed)
	_finish()


func _test_view_data_isolation(view_script: GDScript) -> void:
	var view: RefCounted = view_script.new()
	var property_names: Array[String] = []
	for property: Dictionary in view.get_property_list():
		property_names.append(str(property["name"]).to_lower())
	for forbidden: String in ["unit", "run_state", "game_action"]:
		_check("角色栏显示数据不持有 %s" % forbidden,
			property_names.all(func(name: String) -> bool: return forbidden not in name))
	for expected: String in ["profession_name", "player_name", "level", "experience",
			"hp", "shield", "portrait_texture", "portrait_fallback_text"]:
		_check("角色栏显示数据声明 %s" % expected, expected in property_names)


func _test_declared_layout_and_binding(view_script: GDScript, packed: PackedScene) -> void:
	var panel: Control = packed.instantiate() as Control
	_check("角色栏根节点可实例化", panel != null)
	if panel == null:
		return
	var required_paths: Array[String] = [
		"Margin/ContentRow/PortraitFrame/PortraitContent",
		"Margin/ContentRow/PortraitFrame/PortraitFallback",
		"Margin/ContentRow/InfoColumn/IdentityLabel",
		"Margin/ContentRow/InfoColumn/LevelExperienceRow/LevelLabel",
		"Margin/ContentRow/InfoColumn/LevelExperienceRow/ExperienceMeter",
		"Margin/ContentRow/InfoColumn/SurvivalFrame/SurvivalColumn/HpMeter",
		"Margin/ContentRow/InfoColumn/SurvivalFrame/SurvivalColumn/ShieldMeter",
	]
	for path: String in required_paths:
		_check("静态节点由 tscn 声明：%s" % path, panel.get_node_or_null(path) != null)
	_check("角色栏场景序列化声明式组件树", packed.get_state().get_node_count() >= 12)

	root.add_child(panel)
	await process_frame
	await process_frame
	_eq("角色栏固定宽度", panel.size.x, 226.0)
	_eq("角色栏固定高度", panel.size.y, 108.0)
	var portrait_frame: Control = panel.get_node("Margin/ContentRow/PortraitFrame") as Control
	var info_column: Control = panel.get_node("Margin/ContentRow/InfoColumn") as Control
	_eq("头像区宽度为 72", portrait_frame.size.x, 72.0)
	_eq("信息列宽度为 124", info_column.size.x, 124.0)
	_eq("头像区在外围绘制边缘内保持安全位置",
		_relative_rect(portrait_frame, panel), Rect2(12, 13, 72, 82))
	_eq("信息列在外围绘制边缘内保持安全位置",
		_relative_rect(info_column, panel), Rect2(90, 13, 124, 82))
	_check("头像区四周至少保留 10 像素边界净距",
		_has_minimum_edge_clearance(portrait_frame, panel, 10.0))
	_check("信息列四周至少保留 10 像素边界净距",
		_has_minimum_edge_clearance(info_column, panel, 10.0))
	_eq("头像区与信息列横向间距为 6",
		info_column.global_position.x - (portrait_frame.global_position.x + portrait_frame.size.x),
		6.0)
	_check("头像区与信息列互不重叠",
		not _relative_rect(portrait_frame, panel).intersects(_relative_rect(info_column, panel)))

	var identity: Label = panel.get_node("Margin/ContentRow/InfoColumn/IdentityLabel") as Label
	var level_row: Control = panel.get_node("Margin/ContentRow/InfoColumn/LevelExperienceRow") as Control
	var survival: Control = panel.get_node("Margin/ContentRow/InfoColumn/SurvivalFrame") as Control
	_eq("名称组随身份文字放大为 20 高", identity.size.y, 20.0)
	_eq("等级经验组随文字放大为 22 高", level_row.size.y, 22.0)
	_eq("HP 护盾组随两条数值条放大为 32 高", survival.size.y, 32.0)
	_eq("名称组到等级经验组间距统一为 4", level_row.position.y - (identity.position.y + identity.size.y), 4.0)
	_eq("等级经验组到 HP 护盾组间距统一为 4", survival.position.y - (level_row.position.y + level_row.size.y), 4.0)
	_eq("信息列上边距为 13", identity.global_position.y - panel.global_position.y, 13.0)
	_eq("信息列下边距为 13",
		panel.size.y - ((survival.global_position.y - panel.global_position.y) + survival.size.y), 13.0)

	var view: RefCounted = view_script.new()
	view.set("profession_name", "剑圣")
	view.set("player_name", "fyc")
	view.set("portrait_fallback_text", "剑")
	view.set("level", 12)
	var experience: RefCounted = view.get("experience") as RefCounted
	experience.set("current_value", 125)
	experience.set("maximum_value", 500)
	var hp: RefCounted = view.get("hp") as RefCounted
	hp.set("current_value", 78)
	hp.set("maximum_value", 120)
	var shield: RefCounted = view.get("shield") as RefCounted
	shield.set("current_value", 0)
	shield.set("maximum_value", 40)
	panel.call("apply_view", view)

	_eq("职业名在玩家名之前", identity.text, "剑圣 · fyc")
	_eq("完整名称写入 tooltip", identity.tooltip_text, "剑圣 · fyc")
	_check("名称保持单行裁切", identity.clip_text
		and identity.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS)
	var level_label: Label = panel.get_node("Margin/ContentRow/InfoColumn/LevelExperienceRow/LevelLabel") as Label
	var experience_meter: Control = panel.get_node(
		"Margin/ContentRow/InfoColumn/LevelExperienceRow/ExperienceMeter") as Control
	_eq("等级文字绑定", level_label.text, "Lv. 12")
	_eq("等级字段为放大文字分配 40 像素宽度", level_label.size.x, 40.0)
	_eq("经验字段在固定信息列中重分配为 80 像素宽度", experience_meter.size.x, 80.0)
	var exp_label: Label = panel.get_node("Margin/ContentRow/InfoColumn/LevelExperienceRow/ExperienceMeter/ValueLabel") as Label
	var hp_label: Label = panel.get_node("Margin/ContentRow/InfoColumn/SurvivalFrame/SurvivalColumn/HpMeter/ValueLabel") as Label
	var shield_label: Label = panel.get_node("Margin/ContentRow/InfoColumn/SurvivalFrame/SurvivalColumn/ShieldMeter/ValueLabel") as Label
	_eq("经验数值绑定", exp_label.text, "125/500")
	_eq("HP 数值绑定", hp_label.text, "78/120")
	_eq("零护盾仍显示明确数值", shield_label.text, "0/40")
	_eq("职业与名称使用 14px", identity.get_theme_font_size(&"font_size"), 14)
	_eq("等级使用 12px", level_label.get_theme_font_size(&"font_size"), 12)
	_eq("经验使用 11px 常规数值", exp_label.get_theme_font_size(&"font_size"), 11)
	_eq("HP 使用 11px 常规数值", hp_label.get_theme_font_size(&"font_size"), 11)
	_eq("护盾使用 11px 常规数值", shield_label.get_theme_font_size(&"font_size"), 11)
	var exp_track: ProgressBar = panel.get_node(
		"Margin/ContentRow/InfoColumn/LevelExperienceRow/ExperienceMeter/Track") as ProgressBar
	_eq("经验轨道随字段放大为 12 高", exp_track.size.y, 12.0)
	_eq("经验轨道在 22 像素字段中垂直居中", exp_track.position.y, 5.0)
	var hp_meter: Control = panel.get_node(
		"Margin/ContentRow/InfoColumn/SurvivalFrame/SurvivalColumn/HpMeter") as Control
	var shield_meter: Control = panel.get_node(
		"Margin/ContentRow/InfoColumn/SurvivalFrame/SurvivalColumn/ShieldMeter") as Control
	_eq("HP 数值条承载高度放大为 13", hp_meter.size.y, 13.0)
	_eq("护盾数值条承载高度放大为 13", shield_meter.size.y, 13.0)

	var portrait: TextureRect = panel.get_node("Margin/ContentRow/PortraitFrame/PortraitContent") as TextureRect
	var fallback: Label = panel.get_node("Margin/ContentRow/PortraitFrame/PortraitFallback") as Label
	_check("无头像时显示显式 fallback", portrait.texture == null and fallback.visible
		and fallback.text == "剑")
	var generated_texture := GradientTexture2D.new()
	view.set("portrait_texture", generated_texture)
	panel.call("apply_view", view)
	_check("有头像时隐藏 fallback", portrait.texture == generated_texture and not fallback.visible)

	var long_name: String = "流浪剑术宗师长职业名 · 玩家自定义超长名称用于验证截断"
	view.set("profession_name", "流浪剑术宗师长职业名")
	view.set("player_name", "玩家自定义超长名称用于验证截断")
	hp.set("current_value", 999999)
	hp.set("maximum_value", 999999)
	panel.call("apply_view", view)
	await process_frame
	_eq("长名称完整值保留在 tooltip", identity.tooltip_text, long_name)
	_eq("超大 HP 数值更新", hp_label.text, "999999/999999")
	_eq("超大 HP 数值回退为 9px", hp_label.get_theme_font_size(&"font_size"), 9)
	_eq("极大数值状态仍保持角色栏固定宽度", panel.size.x, 226.0)
	_check("角色栏所有可视组件保留在固定边界内", _descendants_within(panel, panel))

	panel.queue_free()
	await process_frame


func _descendants_within(node: Node, boundary: Control) -> bool:
	for child: Node in node.get_children():
		var control: Control = child as Control
		if control != null and control.visible:
			var relative: Vector2 = control.global_position - boundary.global_position
			if relative.x < -0.01 or relative.y < -0.01 \
					or relative.x + control.size.x > boundary.size.x + 0.01 \
					or relative.y + control.size.y > boundary.size.y + 0.01:
				return false
		if not _descendants_within(child, boundary):
			return false
	return true


func _relative_rect(control: Control, boundary: Control) -> Rect2:
	return Rect2(control.global_position - boundary.global_position, control.size)


func _has_minimum_edge_clearance(control: Control, boundary: Control,
		minimum: float) -> bool:
	var rect: Rect2 = _relative_rect(control, boundary)
	return rect.position.x >= minimum \
		and rect.position.y >= minimum \
		and boundary.size.x - rect.end.x >= minimum \
		and boundary.size.y - rect.end.y >= minimum


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
