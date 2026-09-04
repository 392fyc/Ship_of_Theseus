extends SceneTree

const SCENE_PATH: String = "res://scenes/dev/hud_bottom_dynamic_states_gallery.tscn"
const BASE_GALLERY_PATH: String = "res://scenes/dev/hud_bottom_composition_gallery.tscn"
const STATE_READY: StringName = &"capacity_1_ready_zero_shield"
const STATE_EARLY_LOCK: StringName = &"capacity_2_early_move_lock_long_values"
const STATE_EXHAUSTED: StringName = &"capacity_3_move_exhausted"
const EXPECTED_STATES: Array[StringName] = [STATE_READY, STATE_EARLY_LOCK, STATE_EXHAUSTED]

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_hud_bottom_dynamic_states_gallery ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_check("动态状态画廊存在", packed != null)
	if packed == null:
		_finish()
		return
	var gallery: Control = packed.instantiate() as Control
	_check("动态状态画廊可实例化", gallery != null)
	if gallery == null:
		_finish()
		return
	_check("画廊提供状态接口", gallery.has_method("configure_state")
		and gallery.has_method("get_state_id") and gallery.has_method("get_state_ids"))
	_eq("画廊只声明三个现行状态", gallery.call("get_state_ids"), EXPECTED_STATES)
	gallery.call("configure_state", STATE_READY)
	root.add_child(gallery)
	await process_frame
	await process_frame
	_test_unique_ghv4_reuse(gallery)
	await _test_ready_state(gallery)
	await _test_early_lock_state(gallery)
	await _test_exhausted_state(gallery)
	gallery.queue_free()
	await process_frame
	_finish()


func _test_unique_ghv4_reuse(gallery: Control) -> void:
	_eq("动态画廊根固定为 1280×720", gallery.size, Vector2(1280, 720))
	_eq("动态画廊只有一个 GHV-4 子画廊", gallery.get_child_count(), 1)
	var base: Control = gallery.get_node_or_null("BaseGallery") as Control
	_check("唯一子节点来自现有 GHV-4 画廊", base != null
		and base.scene_file_path == BASE_GALLERY_PATH)
	_eq("动态状态复用五技能默认配置", base.call("get_skill_count"), 5)
	_check("动态画廊不复制棋盘", gallery.get_node_or_null("DiamondBoardStress") == null)
	_check("动态画廊不复制棋子", gallery.get_node_or_null("KenseiScaleAnchor") == null)


func _test_ready_state(gallery: Control) -> void:
	gallery.call("configure_state", STATE_READY)
	await process_frame
	await process_frame
	_eq("容量 1 状态 ID", gallery.call("get_state_id"), STATE_READY)
	var composition: Control = _composition(gallery)
	_check("容量 1 状态复用完整组合", composition != null)
	if composition == null:
		return
	var character: Control = composition.get_node("BottomRow/CharacterHudPanel") as Control
	_eq("容量 1 角色名", _identity(character).text, "剑圣 · fyc")
	_eq("容量 1 等级", _level(character).text, "Lv. 12")
	_eq("容量 1 经验", _meter_label(character, "ExperienceMeter").text, "125/500")
	_eq("容量 1 HP", _meter_label(character, "HpMeter").text, "78/120")
	_eq("零护盾明确显示", _meter_label(character, "ShieldMeter").text, "0/40")
	_eq("普通数值使用 11px", _meter_label(character, "HpMeter").get_theme_font_size(&"font_size"), 11)
	_assert_action_state(composition, "容量 1", "6", false, [false], [false])
	var slots: Array = _skill_slots(composition)
	_eq("容量 1 固定使用五个技能", slots.size(), 5)
	_assert_hotkeys(slots)
	if slots.size() == 5:
		_check("容量 1 没有冷却对照色块", _icon(slots[0]).texture == null)
		_check("容量 1 没有次数", not _charge(slots[1]).visible and _charge(slots[1]).text == "")
	_assert_non_skill_content_empty(composition)


func _test_early_lock_state(gallery: Control) -> void:
	gallery.call("configure_state", STATE_EARLY_LOCK)
	await process_frame
	await process_frame
	_eq("容量 2 状态 ID", gallery.call("get_state_id"), STATE_EARLY_LOCK)
	var composition: Control = _composition(gallery)
	if composition == null:
		_check("容量 2 状态复用完整组合", false)
		return
	var character: Control = composition.get_node("BottomRow/CharacterHudPanel") as Control
	var full_identity: String = "流浪剑术宗师长职业名 · 玩家自定义超长名称用于验证截断"
	var identity: Label = _identity(character)
	_eq("长职业与玩家名来自运行时", identity.text, full_identity)
	_eq("长名称 tooltip 保留完整文字", identity.tooltip_text, full_identity)
	_check("长名称触发单行省略条件", identity.clip_text
		and identity.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS
		and _rendered_text_width(identity) > identity.size.x)
	_eq("极长经验文字", _meter_label(character, "ExperienceMeter").text, "999999/999999")
	_eq("极长 HP 文字", _meter_label(character, "HpMeter").text, "999999/999999")
	_eq("极长 SH 文字", _meter_label(character, "ShieldMeter").text, "999999/999999")
	_eq("极长数值回退为 9px", _meter_label(character, "HpMeter").get_theme_font_size(&"font_size"), 9)
	_assert_action_state(composition, "容量 2", "7", true,
		[false, true], [true, true])
	var slots: Array = _skill_slots(composition)
	_eq("容量 2 固定使用五个技能", slots.size(), 5)
	_assert_hotkeys(slots)
	if slots.size() == 5:
		var icon: TextureRect = _icon(slots[0])
		var shade: Panel = (slots[0] as Control).get_node("Content/CooldownShade") as Panel
		var cooldown: Label = (slots[0] as Control).get_node(
			"Content/CooldownTurnsLabel") as Label
		_check("冷却对照只使用运行时纹理", icon.texture != null
			and icon.texture.resource_path == "")
		_eq("冷却数字为剩余回合", cooldown.text, "2")
		_check("冷却数字与暗层可见", cooldown.visible and shade.visible)
		var shade_style: StyleBoxFlat = shade.get_theme_stylebox(&"panel") as StyleBoxFlat
		_check("冷却暗层 alpha 为 0.5", shade_style != null
			and is_equal_approx(shade_style.bg_color.a, 0.5))
		_check("内容层位于冷却暗层下方", _icon(slots[0]).get_index() < shade.get_index())
		_eq("次数按运行时显示", _charge(slots[1]).text, "3")
		_check("次数层可见", _charge(slots[1]).visible)
		_eq("可主动触发被动保留快捷键", _hotkey(slots[2]).text, "Q")
	_assert_only_cooldown_mock_texture(slots)
	_assert_non_skill_content_empty(composition)


func _test_exhausted_state(gallery: Control) -> void:
	gallery.call("configure_state", STATE_EXHAUSTED)
	await process_frame
	await process_frame
	_eq("容量 3 状态 ID", gallery.call("get_state_id"), STATE_EXHAUSTED)
	var composition: Control = _composition(gallery)
	if composition == null:
		_check("容量 3 状态复用完整组合", false)
		return
	var character: Control = composition.get_node("BottomRow/CharacterHudPanel") as Control
	_eq("短名称恢复", _identity(character).text, "剑士 · 归航者")
	_eq("短 HP 恢复", _meter_label(character, "HpMeter").text, "34/100")
	_eq("长值后恢复 11px", _meter_label(character, "HpMeter").get_theme_font_size(&"font_size"), 11)
	_assert_action_state(composition, "容量 3", "0", true,
		[false, false, true], [false, true, true])
	var slots: Array = _skill_slots(composition)
	_eq("容量 3 固定使用五个技能", slots.size(), 5)
	_assert_hotkeys(slots)
	if slots.size() == 5:
		var shade: Control = (slots[0] as Control).get_node("Content/CooldownShade") as Control
		var cooldown: Label = (slots[0] as Control).get_node(
			"Content/CooldownTurnsLabel") as Label
		_check("冷却归零后对照色块仍存在", _icon(slots[0]).texture != null
			and _icon(slots[0]).texture.resource_path == "")
		_check("冷却归零后暗层和数字隐藏", not shade.visible
			and not cooldown.visible and cooldown.text == "")
		_check("次数状态清除", not _charge(slots[1]).visible
			and _charge(slots[1]).text == "")
	_assert_only_cooldown_mock_texture(slots)
	_assert_non_skill_content_empty(composition)


func _assert_action_state(composition: Control, label: String, movement_text: String,
		movement_spent: bool, standard_spent: Array, swift_spent: Array) -> void:
	var strip: Control = composition.get_node("ActionResourceStrip") as Control
	var standard: Array = strip.call("get_standard_pips") as Array
	var swift: Array = strip.call("get_swift_pips") as Array
	_eq("%s 标准行动只显示实际容量" % label, standard.size(), standard_spent.size())
	_eq("%s 迅捷行动只显示实际容量" % label, swift.size(), swift_spent.size())
	_eq("%s 标准行动消耗状态" % label, _spent_states(standard), standard_spent)
	_eq("%s 迅捷行动消耗状态" % label, _spent_states(swift), swift_spent)
	var footprint: Control = strip.get_node(
		"Margin/MainRow/MovementZone/MovementCluster/FootprintGlyph") as Control
	var movement: Label = strip.get_node(
		"Margin/MainRow/MovementZone/MovementCluster/MovementValue") as Label
	_eq("%s 移动剩余值" % label, movement.text, movement_text)
	_eq("%s 移动灰化状态" % label, bool(footprint.get("spent")), movement_spent)
	_eq("%s 足迹与数值使用同一状态色" % label,
		movement.modulate, footprint.call("get_display_color"))


func _assert_hotkeys(slots: Array) -> void:
	if slots.size() != 5:
		return
	var expected: Array[String] = ["1", "2", "Q", "E", "R"]
	for index: int in expected.size():
		var hotkey: Label = _hotkey(slots[index])
		_eq("快捷键 %d 运行时文字" % (index + 1), hotkey.text, expected[index])
		_check("快捷键 %d 居中" % (index + 1),
			hotkey.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER
			and hotkey.vertical_alignment == VERTICAL_ALIGNMENT_CENTER)


func _assert_only_cooldown_mock_texture(slots: Array) -> void:
	for index: int in slots.size():
		var texture: Texture2D = _icon(slots[index]).texture
		if index == 0:
			_check("冷却对照槽有且仅有运行时纹理", texture != null
				and texture.resource_path == "")
		else:
			_eq("技能槽 %d 内容纹理为空" % (index + 1), texture, null)


func _assert_non_skill_content_empty(composition: Control) -> void:
	var equipment: Control = composition.get_node("BottomRow/EquipmentHudPanel") as Control
	for path: String in ["WeaponSlot/Content/IconRect", "ArmorSlot/Content/IconRect",
			"PotionButton/Content/IconRect"]:
		_eq("装备与血瓶内容纹理为空：%s" % path,
			(equipment.get_node(path) as TextureRect).texture, null)
	var relics: Control = composition.get_node("BottomRow/RelicGrid") as Control
	for slot: Node in relics.get_node("VisualGrid").get_children():
		_eq("遗物内容纹理为空：%s" % slot.name,
			(slot.get_node("Content/IconRect") as TextureRect).texture, null)


func _composition(gallery: Control) -> Control:
	return gallery.get_node_or_null(
		"BaseGallery/DesignRoot/BottomHudComposition") as Control


func _identity(character: Control) -> Label:
	return character.get_node("Margin/ContentRow/InfoColumn/IdentityLabel") as Label


func _level(character: Control) -> Label:
	return character.get_node(
		"Margin/ContentRow/InfoColumn/LevelExperienceRow/LevelLabel") as Label


func _meter_label(character: Control, meter_name: String) -> Label:
	var base: String = "Margin/ContentRow/InfoColumn/"
	if meter_name == "ExperienceMeter":
		return character.get_node(
			base + "LevelExperienceRow/ExperienceMeter/ValueLabel") as Label
	return character.get_node(base + "SurvivalFrame/SurvivalColumn/%s/ValueLabel" % meter_name) as Label


func _skill_slots(composition: Control) -> Array:
	var shelf: Control = composition.get_node("BottomRow/SkillShelf") as Control
	return shelf.call("get_skill_slots") as Array


func _icon(slot: Variant) -> TextureRect:
	return (slot as Control).get_node("Content/IconRect") as TextureRect


func _hotkey(slot: Variant) -> Label:
	return (slot as Control).get_node("Content/HotkeyBadge/HotkeyText") as Label


func _charge(slot: Variant) -> Label:
	return (slot as Control).get_node("Content/ChargeText") as Label


func _spent_states(nodes: Array) -> Array:
	var states: Array[bool] = []
	for node: Control in nodes:
		states.append(bool(node.get("spent")))
	return states


func _rendered_text_width(label: Label) -> float:
	var font: Font = label.get_theme_font(&"font")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		label.get_theme_font_size(&"font_size")).x


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
