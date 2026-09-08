extends SceneTree

## FE-IMPORT-R1 定向接口测试。fixture_* 仅为显示接口夹具，不代表玩法数据。
const RuntimeDashboard := preload("res://scripts/ui/hud/m2/runtime_dashboard.gd")
const ViewAdapter := preload("res://scripts/ui/hud/m2/dashboard_view_adapter.gd")
const CompositionScene := preload("res://scenes/tactical/hud/m2/bottom_hud_composition.tscn")
const DEFAULT_THEME_PATH := "res://assets/ui/themes/hud_m2.tres"
const TEXTURE_MARKER := Color("#20DCE8")
const FLAT_MARKER := Color("#528CCF")
const SHARED_MARKER := Color("#74DFEC")

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	if not "--skin-end-icon-only" in OS.get_cmdline_user_args():
		await _test_composition()
		await _test_parent_theme_and_standalone()
		await _test_runtime()
	await _test_end_icon_switch()
	print("HUD_M2_SKIN_THEME_RESULT passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


static func make_alternate_theme() -> Theme:
	var source: Theme = load(DEFAULT_THEME_PATH)
	var result: Theme = source.duplicate(true) as Theme
	result.resource_name = "SKIN-R1 程序化验证主题"
	# 保留内容边距及语义色；不透明贴图中心也不得遮住内容图像。
	for type_name: StringName in result.get_stylebox_type_list():
		if not str(type_name).begins_with("HudM2") and type_name != &"HudPortraitFrame":
			continue
		if type_name in [&"HudM2HpFill", &"HudM2ShieldFill", &"HudM2ExperienceFill"]:
			continue
		for item: StringName in result.get_stylebox_list(type_name):
			var original: StyleBox = result.get_stylebox(item, type_name)
			var changed: StyleBox = original.duplicate(true) as StyleBox
			if changed is StyleBoxFlat:
				var flat: StyleBoxFlat = changed as StyleBoxFlat
				flat.bg_color = Color(0.035, 0.11, 0.17, flat.bg_color.a)
				flat.border_color = Color(FLAT_MARKER, flat.border_color.a)
			elif changed is StyleBoxTexture:
				(changed as StyleBoxTexture).modulate_color = Color(0.4, 0.85, 1.0, 1.0)
			elif type_name == &"HudM2SharedFrame":
				changed.set("material_texture", null)
				changed.set("background_color", Color("#102C39"))
				changed.set("border_color", SHARED_MARKER)
			result.set_stylebox(item, type_name, changed)
	var pixels: Image = Image.create(12, 12, false, Image.FORMAT_RGBA8)
	pixels.fill(Color("#0D2533"))
	for y: int in 12:
		for x: int in 12:
			if x < 3 or x >= 9 or y < 3 or y >= 9:
				pixels.set_pixel(x, y, TEXTURE_MARKER)
	var texture_frame := StyleBoxTexture.new()
	texture_frame.texture = ImageTexture.create_from_image(pixels)
	var original_frame: StyleBox = source.get_stylebox(&"panel", &"HudM2SlotFrame")
	for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		texture_frame.set_texture_margin(side, 3.0)
		texture_frame.set_content_margin(side, original_frame.get_content_margin(side))
	result.set_stylebox(&"panel", &"HudM2SlotFrame", texture_frame)
	result.set_stylebox(&"panel", &"HudM2EmptySlotFrame", texture_frame)
	result.set_stylebox(&"panel", &"HudM2RelicFrame", texture_frame)
	for key: StringName in [&"text", &"muted", &"edge", &"spent_edge", &"end_disabled"]:
		result.set_color(key, &"HudM2", Color("#B5DDEA") if key != &"edge" else FLAT_MARKER)
	for role: StringName in [&"HudM2Text", &"HudM2NumericLabel", &"HudM2IdentityLabel", &"HudM2AttributeKey"]:
		result.set_color(&"font_color", role, Color("#B5DDEA"))
	return result


static func fixture_state(count: int = 5) -> Dictionary:
	var entries: Array[Dictionary] = []
	for index: int in count:
		entries.append({
			"skill_id": "fixture_skin_%d" % index, "name": "接口夹具 %d" % index,
			"description": "仅用于换肤与数量边界验证，不代表真实战斗。",
			"is_passive": index == 0, "active_capable": index != 0,
			"available": true, "selected": index == 1, "cooldown": 0,
			"action_cost": "swift" if index % 2 == 0 else "standard",
			"resource_cost_display": {"amount": 999, "resource_name": "任意职业资源"},
		})
	return {
		"visible": true, "mode": "player", "show_actions": true, "skills_visible": true,
		"unit_name": "界面验证夹具", "unit_label": "测", "skills": entries,
		"action_resources": {"movement_remaining": 4, "movement_available": false,
			"standard_capacity": 2, "standard_remaining": 1, "swift_capacity": 3, "swift_remaining": 1},
		"buttons": {"end_turn_visible": true, "end_turn_disabled": false},
		"sword_qi": 65, "sword_qi_max": 100, "marks": {"心": true},
		"class_resource_display": {"class_id": "kensei", "mark_capacity": 3, "qi_threshold_ratio": 0.5, "qi_band": &"high"},
	}


func _apply_fixture(composition: Control, state: Dictionary) -> void:
	var views: Dictionary = ViewAdapter.new().build(state)
	var skills: Array[RefCounted] = []
	skills.assign(views["skills"])
	composition.apply_character(views["character"])
	composition.apply_skills(skills)
	composition.apply_equipment(views["weapon"], views["armor"], views["potion"])
	composition.apply_relics(views["relics"])
	composition.apply_action_resources(views["action_resources"])
	composition.apply_end_action(views["end_action"])
	composition.apply_class_resources(views["class_resources"])


func _test_composition() -> void:
	var composition: Control = CompositionScene.instantiate() as Control
	root.add_child(composition)
	await _settle()
	if not _skin_api_ready(composition):
		composition.queue_free()
		await _settle()
		return
	_apply_fixture(composition, fixture_state())
	await _settle()
	var original: Theme = composition.get_skin_theme()
	var alternate: Theme = make_alternate_theme()
	var slots: Array = composition.get_node("BottomRow/SkillShelf").get_skill_slots()
	var passive: Control = slots[0] as Control
	var active: Control = slots[1] as Control
	var pip: Control = composition.get_node("ActionResourceStrip").get_standard_pips()[0] as Control
	var pip_color: Color = pip.get_display_color()
	var spent_pip: Control = composition.get_node("ActionResourceStrip").get_standard_pips()[1] as Control
	var spent_color: Color = spent_pip.get_display_color()
	var original_rect: Rect2 = active.get_global_rect()
	var original_icon_rect: Rect2 = active.get_node("Content/IconRect").get_rect()
	var requests: Array[String] = []
	composition.skill_activated.connect(func(id: String) -> void: requests.append(id))
	passive.grab_focus()
	await _settle()
	composition.set_skin_theme(alternate)
	await _settle()
	_check("组合接受同一个Theme资源", composition.get_skin_theme() == alternate)
	_check("换肤保留技能实例和焦点", composition.get_node("BottomRow/SkillShelf").get_skill_slots() == slots and passive.has_focus())
	_check("换肤保留行动点实例", composition.get_node("ActionResourceStrip").get_standard_pips()[0] == pip)
	_check("换肤保留行动与耗尽灰色语义", pip.get_display_color() == pip_color and spent_pip.get_display_color() == spent_color and spent_pip.spent)
	_check("换肤保留被动检视可见状态", passive.is_inspection_visible())
	var resource_host: Control = composition.get_class_resource_host()
	var resource_panel: Control = resource_host.get_renderer()
	_check("换肤同步资源材质与连续数值", resource_host.visible and resource_panel.get_theme_stylebox(&"mark_slot", &"HudM2ClassResource") == alternate.get_stylebox(&"mark_slot", &"HudM2ClassResource") and is_equal_approx(resource_panel.get_node("QiFill").size.x, 136.5))
	_check("换肤不改变技能与图像内容边距", active.get_global_rect() == original_rect and active.get_node("Content/IconRect").get_rect() == original_icon_rect)
	_check_theme_consumption(composition, alternate, "组合贴图主题")
	_check("普通槽实际解析StyleBoxTexture", active.get_node("Content/ActiveFrame").get_theme_stylebox(&"panel") is StyleBoxTexture)
	_check("默认普通槽消费获批Penpot纹理", original.get_stylebox(&"panel", &"HudM2SlotFrame") is StyleBoxTexture and (original.get_stylebox(&"panel", &"HudM2SlotFrame") as StyleBoxTexture).texture.resource_path == "res://assets/ui/skins/hud_m2_fe/slot-active.png")
	for role: StringName in [&"HudM2HpFill", &"HudM2ShieldFill"]:
		_check("换肤保留" + str(role) + "语义色", (alternate.get_stylebox(&"panel", role) as StyleBoxFlat).bg_color == (original.get_stylebox(&"panel", role) as StyleBoxFlat).bg_color)
	_check("三位数费用保持且说明保留任意资源名", active.get_node("Content/ResourceCostBadge/ResourceCostText").text == "999" and active.tooltip_text.contains("任意职业资源：999"))
	_check("选中状态保留", active.get_node("Content/SelectedOverlay").visible)
	for item: String in ["HotkeyBadge", "ActionBadge", "ResourceCostBadge", "SelectedOverlay", "CooldownShade", "UnavailableShade"]:
		_check("纯被动不显示主动语义：" + item, not passive.get_node("Content/" + item).visible)
	await _click(passive.get_global_rect().get_center())
	await _key(KEY_SPACE)
	passive.activate_shortcut()
	_check("纯被动拒绝鼠标键盘与快捷激活", requests.is_empty())
	await _click(active.get_global_rect().get_center())
	_check("换肤后信号仍单次转发", requests == ["fixture_skin_1"])
	root.gui_release_focus()
	_move_pointer(Vector2(640, 320))
	for count: int in range(8):
		_apply_fixture(composition, fixture_state(count))
		await _settle()
		var current: Array = composition.get_node("BottomRow/SkillShelf").get_skill_slots()
		_check("动态%d技能数量" % count, current.size() == count)
		for index: int in current.size():
			var slot: Control = current[index] as Control
			_check("动态%d技能%d继承替换主题" % [count, index], slot.get_node("Content/ActiveFrame").get_theme_stylebox(&"panel") == alternate.get_stylebox(&"panel", &"HudM2SlotFrame"))
			_check("动态%d技能%d保留内容边距" % [count, index], slot.get_node("Content/IconRect").get_rect() == Rect2(Vector2(6, 6), slot.size - Vector2(12, 12)))
			if index > 0:
				var amount: Label = slot.get_node("Content/ResourceCostBadge/ResourceCostText") as Label
				_check("动态%d技能三位费用可容纳" % count, amount.text == "999" and amount.get_theme_font(&"font").get_string_size(amount.text, HORIZONTAL_ALIGNMENT_LEFT, -1, amount.get_theme_font_size(&"font_size")).x <= amount.size.x)
			if index > 0 and index % 2 == 0:
				var glyph: Control = slot.get_node("Content/ActionBadge/ActionGlyph") as Control
				_check("迅捷图形保持等边三角外接尺寸", is_equal_approx(glyph.size.y, glyph.size.x * sqrt(3.0) / 2.0))
	for capacity: int in [1, 3, 2]:
		var state: Dictionary = fixture_state(7)
		state["action_resources"]["standard_capacity"] = capacity
		state["action_resources"]["standard_remaining"] = 0
		_apply_fixture(composition, state)
		await _settle()
		var pips: Array = composition.get_node("ActionResourceStrip").get_standard_pips()
		_check("动态行动点容量%d" % capacity, pips.size() == capacity)
		for glyph: Control in pips:
			_check("动态行动点继承当前主题且保留耗尽语义", glyph.spent and glyph.get_theme_color(&"edge", &"HudM2") == alternate.get_color(&"edge", &"HudM2"))
	composition.set_skin_theme(null)
	await _settle()
	_check("组合null恢复默认", composition.get_skin_theme() == original)
	_check("资源恢复默认材质且宿主不重建", composition.get_class_resource_host() == resource_host and resource_host.get_renderer() == resource_panel and resource_panel.get_theme_stylebox(&"mark_slot", &"HudM2ClassResource") == original.get_stylebox(&"mark_slot", &"HudM2ClassResource"))
	_check_theme_consumption(composition, original, "组合切回默认")
	composition.queue_free()
	await _settle()


func _test_parent_theme_and_standalone() -> void:
	var parent := Control.new()
	parent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.theme = make_alternate_theme()
	root.add_child(parent)
	for scene_name: String in ["character_hud_panel", "equipment_hud_panel", "skill_shelf", "relic_grid", "end_turn_control", "action_resource_strip", "skill_slot_button"]:
		var scene: PackedScene = load("res://scenes/tactical/hud/m2/" + scene_name + ".tscn") as PackedScene
		var inherited: Control = scene.instantiate() as Control
		# 独立场景保留默认Theme；调用方按Godot原生语义清根Theme以选择继承。
		inherited.theme = null
		parent.add_child(inherited)
		await _settle()
		var role: StringName = &"HudM2SlotFrame"
		_check(scene_name + "独立装入父节点继承Theme", inherited.get_theme_stylebox(&"panel", role) == parent.theme.get_stylebox(&"panel", role))
		inherited.queue_free()
		await _settle()
		var standalone: Control = scene.instantiate() as Control
		root.add_child(standalone)
		await _settle()
		_check(scene_name + "独立组件仍有默认样式", standalone.get_theme_stylebox(&"panel", role) == (load(DEFAULT_THEME_PATH) as Theme).get_stylebox(&"panel", role))
		standalone.queue_free()
		await _settle()
	parent.queue_free()
	await _settle()


func _test_end_icon_switch() -> void:
	var dashboard: Control = RuntimeDashboard.new()
	dashboard.update_state(fixture_state())
	root.add_child(dashboard)
	await _settle()
	var composition: Control = dashboard.get_composition()
	var button: Button = composition.get_node("BottomRow/EndTurnControl/EndTurnButton") as Button
	var emblem: TextureRect = button.get_node("HourglassEmblem") as TextureRect
	var default_theme: Theme = load(DEFAULT_THEME_PATH)
	# 默认主题允许使用原生绘制且不声明icon；记住进入切换序列前的真实显示资源。
	var default_icon: Texture2D = emblem.texture
	var theme_a: Theme = default_theme.duplicate(true) as Theme
	var theme_b: Theme = default_theme.duplicate(true) as Theme
	# 仅验证不同纹理资源的消费；不作为美术资产或真实战斗内容。
	var icon_a := GradientTexture2D.new()
	var icon_b := GradientTexture2D.new()
	theme_a.set_icon(&"end_emblem", &"HudM2", icon_a)
	theme_b.set_icon(&"end_emblem", &"HudM2", icon_b)
	button.grab_focus()
	for sample: Dictionary in [
		{"skin": null, "icon": default_icon, "step": "默认"},
		{"skin": theme_a, "icon": icon_a, "step": "图标A"},
		{"skin": theme_b, "icon": icon_b, "step": "图标B"},
		{"skin": null, "icon": default_icon, "step": "恢复默认"},
	]:
		dashboard.set_skin_theme(sample["skin"] as Theme)
		await _settle()
		_check("结束图标" + str(sample["step"]) + "实际TextureRect消费", emblem.texture == sample["icon"])
		_check("结束图标" + str(sample["step"]) + "保留按钮与焦点", composition.get_node("BottomRow/EndTurnControl/EndTurnButton") == button and button.has_focus())
	dashboard.queue_free()
	await _settle()


func _test_runtime() -> void:
	var environment: Dictionary = await _make_runtime()
	var scene: Node = environment["scene"]
	var dashboard: Control = environment["dashboard"]
	var manager: Object = environment["manager"]
	if not _skin_api_ready(dashboard):
		scene.queue_free()
		await _settle()
		return
	var composition: Control = dashboard.get_composition()
	var state: Dictionary = dashboard.get_last_state()
	var alternate: Theme = make_alternate_theme()
	var slots: Array = composition.get_node("BottomRow/SkillShelf").get_skill_slots()
	var character: Control = composition.get_node("BottomRow/CharacterHudPanel") as Control
	_move_pointer(character.get_inspection_control().get_global_rect().get_center())
	await _settle()
	var character_card: Control = character.get_inspection_panel()
	_check("真实人物全栏悬停显示信息卡", character_card.visible)
	dashboard.set_skin_theme(alternate)
	await _settle()
	_check("runtime入口传到原组合", dashboard.get_skin_theme() == alternate and dashboard.get_composition() == composition and composition.get_skin_theme() == alternate)
	_check("runtime换肤保留载荷与槽实例", dashboard.get_last_state() == state and composition.get_node("BottomRow/SkillShelf").get_skill_slots() == slots)
	_check("runtime换肤不打断人物悬浮", character_card.visible)
	_check_theme_consumption(composition, alternate, "真实宿主贴图主题")
	for output_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		root.size = output_size
		_move_pointer(Vector2(640, 320))
		root.gui_release_focus()
		await _settle()
		_check("%s固定五区与行动几何" % output_size, _geometry_ready(composition))
		var factor: float = float(output_size.x) / 1280.0
		for point: Vector2 in [Vector2(640, 320), Vector2(490, 558), Vector2(790, 558), Vector2(20, 650)]:
			_move_pointer(point * factor)
			await _settle()
			_check("%s战场空白%s输入透传" % [output_size, point], not _point_blocked(dashboard, point * factor) and root.gui_get_hovered_control() == null)
		for point: Vector2 in [Vector2(262, 650), Vector2(398, 650), Vector2(882, 650), Vector2(1168, 650), Vector2(510, 593), Vector2(770, 593)]:
			_move_pointer(point * factor)
			await _settle()
			_check("%s共享分隔及连接区域%s阻挡" % [output_size, point], _point_blocked(dashboard, point * factor) and root.gui_get_hovered_control() != null)
	root.size = Vector2i(1280, 720)
	await _settle()
	root.gui_release_focus()
	_move_pointer(Vector2(640, 320))
	# 通过真实结束入口进入主动技能阶段，避免用移动阶段的不可用技能作输入夹具。
	var end_button: Button = composition.get_node("BottomRow/EndTurnControl/EndTurnButton") as Button
	var end_signals: Array[String] = []
	dashboard.end_move_requested.connect(func() -> void: end_signals.append("move"))
	var phase_before: Variant = manager.input_state
	await _click(end_button.get_global_rect().get_center())
	_check("runtime换肤后结束移动单次转发至管理器", end_signals == ["move"] and manager.input_state != phase_before)
	state = dashboard.get_last_state()
	var active_index: int = -1
	var real_entries: Array = state.get("skills", []) as Array
	for index: int in real_entries.size():
		var entry: Dictionary = real_entries[index] as Dictionary
		if bool(entry.get("available", false)) and bool(entry.get("active_capable", not bool(entry.get("is_passive", false)))):
			active_index = index
			break
	_check("真实载荷提供可激活技能", active_index >= 0)
	if active_index >= 0:
		await _click((slots[active_index] as Control).get_global_rect().get_center())
		_check("runtime换肤后真实鼠标选择转发", manager.get_selected_skill_id() == str(real_entries[active_index]["skill_id"]))
		manager.request_cancel_action()
		await _settle()
	dashboard.set_skin_theme(null)
	await _settle()
	_check("runtime null恢复默认Theme", dashboard.get_skin_theme() == load(DEFAULT_THEME_PATH))
	_check_theme_consumption(composition, dashboard.get_skin_theme(), "真实宿主切回")
	var enemies: Array = manager.units.filter(func(unit: Object) -> bool: return unit.faction == "enemy")
	if not enemies.is_empty():
		var enemy: Object = enemies[0]
		var enemy_screen: Vector2 = manager.get_viewport().get_canvas_transform() * manager.grid.grid_to_world(enemy.grid_position)
		await _click(enemy_screen)
		await _settle()
		_check("真实敌方收起行动条并保留五区", not composition.get_node("ActionResourceStrip").visible and _geometry_ready(composition))
		_check("收起共享肩部后原连接区域透传", not _point_blocked(dashboard, Vector2(510, 593)))
		_move_pointer(Vector2(510, 593))
		await _settle()
		_check("收起共享肩部后实际鼠标透传", root.gui_get_hovered_control() == null)
	dashboard.update_state({"visible": false})
	await _settle()
	_check("隐藏宿主不残留共享框阻挡", dashboard.get_input_blocking_rects().is_empty())
	scene.queue_free()
	await _settle()


func _check_theme_consumption(composition: Control, skin: Theme, label: String) -> void:
	var paths: Array[String] = [
		"BottomRow/CharacterHudPanel/PortraitFrame",
		"BottomRow/CharacterHudPanel/InspectionPanel/InspectionFrame",
		"BottomRow/EquipmentHudPanel/WeaponSlot/Content/Frame",
		"BottomRow/EquipmentHudPanel/PotionButton/Content/Frame",
		"BottomRow/EndTurnControl/EndTurnButton/DiamondFrame/Surface",
	]
	for path: String in paths:
		var node: Control = composition.get_node_or_null(path) as Control
		_check(label + "节点存在：" + path, node != null)
		if node == null:
			continue
		_check(label + "实际样式：" + path, not node.theme_type_variation.is_empty() and node.get_theme_stylebox(&"panel") == skin.get_stylebox(&"panel", node.theme_type_variation))
	for slot: Control in composition.get_node("BottomRow/SkillShelf").get_skill_slots():
		for path: String in ["Content/ActiveFrame", "Content/PassiveFrame/Contour", "InspectionPanel/Frame"]:
			var panel: Control = slot.get_node(path) as Control
			_check(label + "技能表面：" + path, panel.get_theme_stylebox(&"panel") == skin.get_stylebox(&"panel", panel.theme_type_variation))
		if slot.get_node("Content/ResourceCostBadge").visible:
			var cost_label: Label = slot.get_node("Content/ResourceCostBadge/ResourceCostText") as Label
			_check(label + "技能费用文字刷新", cost_label.get_theme_color(&"font_color") == skin.get_color(&"spent_edge" if slot.disabled else &"text", &"HudM2"))
	var end_label: Label = composition.get_node("BottomRow/EndTurnControl/EndLabel") as Label
	var end_button: Button = composition.get_node("BottomRow/EndTurnControl/EndTurnButton") as Button
	_check(label + "结束文字刷新", end_label.get_theme_color(&"font_color") == skin.get_color(&"end_disabled" if end_button.disabled else &"muted", &"HudM2"))
	var relics: Node = composition.get_node("BottomRow/RelicGrid/VisualGrid")
	for relic: Node in relics.get_children():
		var frame: Control = relic.get_node("Content/Frame") as Control
		_check(label + "遗物实际样式", frame.get_theme_stylebox(&"panel") == skin.get_stylebox(&"panel", frame.theme_type_variation))
	var shared: Control = composition.get_node_or_null("SharedFrame") as Control
	_check(label + "共享框存在", shared != null)
	if shared != null:
		var item: StringName = &"panel" if composition.get_node("ActionResourceStrip").visible else &"collapsed"
		if composition.get_class_resource_host().visible:
			item = &"panel_resources" if composition.get_node("ActionResourceStrip").visible else &"collapsed_resources"
		_check(label + "共享框实际绘制样式", shared.get_frame_style() == skin.get_stylebox(item, &"HudM2SharedFrame"))
	var amount: Label = composition.get_node("ActionResourceStrip/MovementZone/MovementValue") as Label
	var color_key: StringName = &"spent_edge" if composition.get_node("ActionResourceStrip/MovementZone/FootprintGlyph").spent else &"text"
	var expected_color: Color = skin.get_color(color_key, &"HudM2")
	var actual_color: Color = amount.get_theme_color(&"font_color")
	if actual_color != expected_color:
		print("SKIN_COLOR_TRACE %s key=%s expected=%s actual=%s override=%s strip_resolved=%s" % [label, color_key, expected_color, actual_color, amount.has_theme_color_override(&"font_color"), composition.get_node("ActionResourceStrip").get_theme_color(color_key, &"HudM2")])
	_check(label + "行动数字缓存刷新", actual_color == expected_color)


func _geometry_ready(composition: Control) -> bool:
	var factor: float = float(root.size.x) / 1280.0
	var row: Node = composition.get_node("BottomRow")
	var positions: Array[float] = [32.0, 266.0, 402.0, 886.0, 1172.0]
	var widths: Array[float] = [226.0, 128.0, 476.0, 278.0, 76.0]
	if row.get_child_count() != 5:
		return false
	for index: int in 5:
		var zone: Control = row.get_child(index) as Control
		if not zone.get_global_rect().is_equal_approx(Rect2(Vector2(positions[index], 596) * factor, Vector2(widths[index], 108) * factor)):
			return false
	var strip: Control = composition.get_node("ActionResourceStrip") as Control
	return strip.get_global_rect().is_equal_approx(Rect2(Vector2(503, 550) * factor, Vector2(274, 40) * factor))


func _skin_api_ready(control: Control) -> bool:
	var present: bool = control.has_method("set_skin_theme") and control.has_method("get_skin_theme")
	_check("换肤公开接口存在：" + str(control.name), present)
	return present


func _point_blocked(dashboard: Control, point: Vector2) -> bool:
	for rectangle: Rect2 in dashboard.get_input_blocking_rects():
		if rectangle.has_point(point):
			return true
	return false


func _make_runtime() -> Dictionary:
	# 与现有真实捕获相同的 TacticalScene 装配；不导入 gallery 或 p3-fixtures。
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await _settle()
	var manager: Object = scene.tactical_manager
	var dashboard: Control = scene.get("_bottom_dashboard") as Control
	_check("换肤运行环境读取正式M2实例", dashboard is RuntimeDashboard)
	await _settle()
	return {"scene": scene, "manager": manager, "dashboard": dashboard}


func _real_skill_icons() -> Dictionary:
	return {
		"swordsman_xinyan": load("res://assets/prototype/hud_m2/skill-xinyan.png"),
		"swordsman_zhanji": load("res://assets/prototype/hud_m2/skill-zhanji.png"),
		"swordsman_yishan": load("res://assets/prototype/hud_m2/skill-yishan.png"),
		"swordsman_zhaojia": load("res://assets/prototype/hud_m2/skill-zhaojia.png"),
		"swordsman_juhe": load("res://assets/prototype/hud_m2/skill-juhe.png"),
	}


func _settle() -> void:
	await process_frame
	await process_frame


func _move_pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event, true)


func _click(point: Vector2) -> void:
	_move_pointer(point)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
	await _settle()


func _key(code: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)
	await _settle()


func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + label)
