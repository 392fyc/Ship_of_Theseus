extends SceneTree

const SCENE_PATH: String = "res://scenes/dev/hud_utility_vertical_slice_gallery.tscn"
const THEME_PATH: String = "res://assets/ui/themes/hud_structure_prototype.tres"
const STATE_ROOT: String = "SafeArea/Layout/Content/States"
const STATE_NAMES: Array[String] = ["EmptyState", "OccupiedState", "DisabledState"]

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_hud_utility_vertical_slice_gallery ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_check("实用 HUD 纵向切片画廊存在", packed != null)
	if packed == null:
		_finish()
		return

	var gallery: Control = packed.instantiate() as Control
	_check("实用 HUD 画廊根节点可实例化", gallery != null)
	if gallery == null:
		_finish()
		return
	root.add_child(gallery)
	gallery.call("set_reference_size", Vector2i(1280, 720))
	await process_frame
	await process_frame

	var safe_area: Control = gallery.get_node("SafeArea") as Control
	_check("画廊安全画布存在", safe_area != null)
	_eq("画廊记录 1280×720 参考尺寸", gallery.call("get_reference_size"), Vector2i(1280, 720))
	for state_name: String in STATE_NAMES:
		_test_state_geometry(gallery, safe_area, state_name)
	_test_runtime_states(gallery)
	_test_no_baked_component_text(gallery)
	_test_gate3_surface_reuse()

	gallery.queue_free()
	await process_frame
	_finish()


func _test_state_geometry(gallery: Control, safe_area: Control, state_name: String) -> void:
	var state_path := "%s/%s/Components" % [STATE_ROOT, state_name]
	var equipment: Control = gallery.get_node_or_null(state_path + "/EquipmentHudPanel") as Control
	var relic: Control = gallery.get_node_or_null(state_path + "/RelicGrid") as Control
	var end_control: Control = gallery.get_node_or_null(state_path + "/EndTurnControl") as Control
	_check("%s 装备栏存在" % state_name, equipment != null)
	_check("%s 遗物栏存在" % state_name, relic != null)
	_check("%s 结束区存在" % state_name, end_control != null)
	if equipment == null or relic == null or end_control == null:
		return
	_eq("%s 装备栏固定尺寸" % state_name, equipment.size, Vector2(128, 108))
	_eq("%s 遗物栏固定尺寸" % state_name, relic.size, Vector2(278, 108))
	_eq("%s 结束区固定尺寸" % state_name, end_control.size, Vector2(76, 108))
	for component: Control in [equipment, relic, end_control]:
		_check("%s 组件位于安全画布内" % state_name,
			_contains_rect(safe_area.get_global_rect(), component.get_global_rect()))


func _test_runtime_states(gallery: Control) -> void:
	var empty_equipment: Control = gallery.get_node(
		STATE_ROOT + "/EmptyState/Components/EquipmentHudPanel") as Control
	var empty_weapon: Button = empty_equipment.get_node("WeaponSlot") as Button
	var empty_relic: Control = gallery.get_node(
		STATE_ROOT + "/EmptyState/Components/RelicGrid") as Control
	_check("空装备槽保留空态覆盖层", empty_weapon.get_node("Content/StateOverlay").visible)
	_check("空遗物末槽保留空态覆盖层",
		(empty_relic.get_node("VisualGrid/RelicSlot8") as Button).get_node("Content/StateOverlay").visible)

	var occupied_equipment: Control = gallery.get_node(
		STATE_ROOT + "/OccupiedState/Components/EquipmentHudPanel") as Control
	var occupied_weapon: Button = occupied_equipment.get_node("WeaponSlot") as Button
	var occupied_armor: Button = occupied_equipment.get_node("ArmorSlot") as Button
	var occupied_potion: Button = occupied_equipment.get_node("PotionButton") as Button
	_check("mock 武器槽进入占用态", not occupied_weapon.get_node("Content/StateOverlay").visible)
	_check("mock 防具槽进入占用态", not occupied_armor.get_node("Content/StateOverlay").visible)
	_eq("mock 血瓶接口有明确提示", occupied_potion.tooltip_text, "mock-only：全职业血瓶")
	var occupied_relic: Control = gallery.get_node(
		STATE_ROOT + "/OccupiedState/Components/RelicGrid") as Control
	_check("局部 mock 遗物进入占用态",
		not (occupied_relic.get_node("VisualGrid/RelicSlot1") as Button)
			.get_node("Content/StateOverlay").visible)
	_check("未注入的遗物视觉槽仍为空",
		(occupied_relic.get_node("VisualGrid/RelicSlot8") as Button)
			.get_node("Content/StateOverlay").visible)

	var disabled_equipment: Control = gallery.get_node(
		STATE_ROOT + "/DisabledState/Components/EquipmentHudPanel") as Control
	_check("禁用武器槽不可交互", (disabled_equipment.get_node("WeaponSlot") as Button).disabled)
	_check("禁用防具槽不可交互", (disabled_equipment.get_node("ArmorSlot") as Button).disabled)
	_check("禁用血瓶不可交互", (disabled_equipment.get_node("PotionButton") as Button).disabled)
	var disabled_end: Control = gallery.get_node(
		STATE_ROOT + "/DisabledState/Components/EndTurnControl") as Control
	var disabled_end_button: Button = disabled_end.get_node("EndTurnButton") as Button
	_check("禁用结束按钮不可交互", disabled_end_button.disabled)
	_check("禁用结束按钮整体灰化", disabled_end_button.modulate != Color.WHITE)


func _test_no_baked_component_text(gallery: Control) -> void:
	for state_name: String in STATE_NAMES:
		var components: Control = gallery.get_node(
			"%s/%s/Components" % [STATE_ROOT, state_name]) as Control
		for node: Node in components.find_children("*", "Button", true, false):
			_check("%s 的正式按钮不含审核文字" % state_name, (node as Button).text == "")


func _test_gate3_surface_reuse() -> void:
	var theme: Theme = load(THEME_PATH) as Theme
	_check("Gate 3 可读取 HUD Theme", theme != null)
	if theme == null:
		return
	var shared_panel: StyleBox = theme.get_stylebox(&"panel", &"CharacterHudPanel")
	_check("装备栏安全复用已验收角色栏中性外壳",
		theme.get_stylebox(&"panel", &"HudEquipmentPanel") == shared_panel)
	_check("遗物栏安全复用已验收角色栏中性外壳",
		theme.get_stylebox(&"panel", &"HudRelicPanel") == shared_panel)
	var shared_slot: StyleBox = theme.get_stylebox(&"normal", &"SkillSlotButton")
	_check("52×52 通用槽安全复用已验收中性槽壳",
		theme.get_stylebox(&"normal", &"HudSlotButton52") == shared_slot)
	_check("44×44 通用槽安全复用已验收中性槽壳",
		theme.get_stylebox(&"normal", &"HudSlotButton44") == shared_slot)
	_check("32×32 血瓶壳使用独立可替换 Theme 表面",
		theme.get_stylebox(&"normal", &"HudPotionButton32") is StyleBoxTexture)


func _contains_rect(outer: Rect2, inner: Rect2) -> bool:
	return inner.position.x >= outer.position.x - 0.01 \
		and inner.position.y >= outer.position.y - 0.01 \
		and inner.end.x <= outer.end.x + 0.01 \
		and inner.end.y <= outer.end.y + 0.01


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
