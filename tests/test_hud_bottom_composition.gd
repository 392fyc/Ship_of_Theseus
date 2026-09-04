extends SceneTree

const SCENE_PATH: String = "res://scenes/tactical/hud/bottom_hud_composition.tscn"
const CharacterViewData := preload("res://scripts/ui/hud/character_hud_view_data.gd")
const ValueMeterViewData := preload("res://scripts/ui/hud/value_meter_view_data.gd")
const SkillViewData := preload("res://scripts/ui/hud/skill_slot_view_data.gd")
const ActionViewData := preload("res://scripts/ui/hud/action_resource_view_data.gd")
const SlotViewData := preload("res://scripts/ui/hud/slot_view_data.gd")
const PotionViewData := preload("res://scripts/ui/hud/potion_view_data.gd")
const EndViewData := preload("res://scripts/ui/hud/end_turn_view_data.gd")
const RunStateScript := preload("res://scripts/roguelite/run_state.gd")

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_hud_bottom_composition ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_check("底部 HUD 组合场景存在", packed != null)
	if packed == null:
		_finish()
		return
	var composition: Control = packed.instantiate() as Control
	_check("底部 HUD 组合根可实例化", composition != null)
	if composition == null:
		_finish()
		return
	root.add_child(composition)
	await process_frame
	await process_frame
	_test_fixed_geometry(composition)
	_test_runtime_binding(composition)
	_test_signal_forwarding(composition)
	composition.queue_free()
	await process_frame
	_finish()


func _test_fixed_geometry(composition: Control) -> void:
	_eq("组合使用唯一 1280×720 逻辑画布", composition.size, Vector2(1280, 720))
	var row: HBoxContainer = composition.get_node_or_null("BottomRow") as HBoxContainer
	var strip: Control = composition.get_node_or_null("ActionResourceStrip") as Control
	_check("底栏与行动资源条由 tscn 声明", row != null and strip != null)
	if row == null or strip == null:
		return
	_eq("五区底栏位置固定", row.position, Vector2(32, 596))
	_eq("五区底栏尺寸固定", row.size, Vector2(1216, 108))
	_eq("五区间距固定为 8", row.get_theme_constant("separation"), 8)
	var expected_names: Array[String] = [
		"CharacterHudPanel", "EquipmentHudPanel", "SkillShelf", "RelicGrid", "EndTurnControl",
	]
	var expected_sizes: Array[Vector2] = [
		Vector2(226, 108), Vector2(128, 108), Vector2(476, 108),
		Vector2(278, 108), Vector2(76, 108),
	]
	var expected_x: Array[float] = [32.0, 266.0, 402.0, 886.0, 1172.0]
	_eq("五区数量固定为 5", row.get_child_count(), 5)
	for index: int in mini(row.get_child_count(), expected_names.size()):
		var component: Control = row.get_child(index) as Control
		_eq("五区 %d 顺序" % (index + 1), component.name, StringName(expected_names[index]))
		_eq("五区 %d 尺寸" % (index + 1), component.size, expected_sizes[index])
		_eq("五区 %d 全局横坐标" % (index + 1),
			component.global_position.x - composition.global_position.x, expected_x[index])
	_eq("五区底边距为 16", composition.size.y - (row.position.y + row.size.y), 16.0)
	_eq("行动资源条位置固定", strip.position, Vector2(503, 550))
	_eq("行动资源条尺寸固定", strip.size, Vector2(274, 40))
	_eq("行动资源条与技能栏中心同为 640", strip.position.x + strip.size.x * 0.5, 640.0)
	_eq("行动资源条底边与底栏顶边相隔 6", row.position.y - (strip.position.y + strip.size.y), 6.0)
	for forbidden: String in ["ProfessionResource", "ItemPanel", "AttackButton", "MoveButton"]:
		_check("组合不创建 %s" % forbidden,
			composition.find_child("*%s*" % forbidden, true, false) == null)
	var equipment: Control = row.get_node("EquipmentHudPanel") as Control
	var relics: Control = row.get_node("RelicGrid") as Control
	var potion: Control = equipment.get_node("PotionButton") as Control
	_check("血瓶仍在装备栏内部右上并避开外围边框",
		potion.position.x >= equipment.size.x * 0.5
		and potion.position.y < equipment.size.y * 0.5
		and potion.position.x >= 10.0
		and potion.position.y >= 10.0
		and equipment.size.x - (potion.position.x + potion.size.x) >= 10.0)
	_eq("遗物仍只有 8 个视觉槽壳", relics.get_node("VisualGrid").get_child_count(), 8)
	_eq("玩法遗物容量仍为 6", RunStateScript.RELIC_SLOT_MAX, 6)


func _test_runtime_binding(composition: Control) -> void:
	var character: RefCounted = CharacterViewData.new()
	character.set("profession_name", "剑圣")
	character.set("player_name", "fyc")
	character.set("level", 12)
	character.set("experience", _meter(125, 500))
	character.set("hp", _meter(78, 120))
	character.set("shield", _meter(14, 40))
	character.set("portrait_fallback_text", "剑")
	composition.call("apply_character", character)

	var skills: Array[RefCounted] = []
	for index: int in 5:
		var skill: RefCounted = SkillViewData.new()
		skill.set("skill_id", "mock_skill_%d" % (index + 1))
		skill.set("hotkey_text", str(index + 1))
		skill.set("enabled", true)
		skill.set("active_capable", true)
		skill.set("cooldown_turns", 2 if index == 4 else 0)
		skills.append(skill)
	composition.call("apply_skills", skills)

	var action: RefCounted = ActionViewData.new()
	action.set("movement_remaining", 6)
	action.set("movement_available", true)
	action.set("standard_capacity", 1)
	action.set("standard_remaining", 1)
	action.set("swift_capacity", 1)
	action.set("swift_remaining", 1)
	composition.call("apply_action_resources", action)

	var weapon: RefCounted = _slot("weapon", true, "mock-only weapon")
	var armor: RefCounted = _slot("armor", false, "mock-only empty armor")
	var potion: RefCounted = PotionViewData.new()
	potion.set("content_id", "mock_shared_potion")
	potion.set("tooltip_text", "mock-only potion")
	composition.call("apply_equipment", weapon, armor, potion)
	var empty_relics: Array[RefCounted] = []
	composition.call("apply_relics", empty_relics)

	var end_view: RefCounted = EndViewData.new()
	end_view.set("action_kind", &"end_turn")
	end_view.set("visible", true)
	end_view.set("enabled", true)
	end_view.set("tooltip_text", "结束本回合")
	composition.call("apply_end_action", end_view)

	var character_panel: Control = composition.get_node("BottomRow/CharacterHudPanel") as Control
	var identity: Label = character_panel.get_node(
		"Margin/ContentRow/InfoColumn/IdentityLabel") as Label
	var level: Label = character_panel.get_node(
		"Margin/ContentRow/InfoColumn/LevelExperienceRow/LevelLabel") as Label
	var hp_value: Label = character_panel.get_node(
		"Margin/ContentRow/InfoColumn/SurvivalFrame/SurvivalColumn/HpMeter/ValueLabel") as Label
	_eq("职业与玩家名是运行时文字", identity.text, "剑圣 · fyc")
	_eq("等级是运行时文字", level.text, "Lv. 12")
	_eq("HP 是运行时数值", hp_value.text, "78/120")

	var shelf: Control = composition.get_node("BottomRow/SkillShelf") as Control
	var slot_nodes: Array = shelf.call("get_skill_slots") as Array
	_eq("组合只显示实际 5 个技能", slot_nodes.size(), 5)
	if slot_nodes.size() == 5:
		_eq("技能快捷键是运行时文字",
			(slot_nodes[0] as Control).get_node("Content/HotkeyBadge/HotkeyText").text, "1")
		_eq("冷却是运行时数字",
			(slot_nodes[4] as Control).get_node("Content/CooldownTurnsLabel").text, "2")
		for index: int in slot_nodes.size():
			_eq("技能 %d 不烘焙内容图标" % (index + 1),
				(slot_nodes[index] as Control).get_node("Content/IconRect").texture, null)
	var movement: Label = composition.get_node(
		"ActionResourceStrip/Margin/MainRow/MovementZone/MovementCluster/MovementValue") as Label
	_eq("移动力是运行时数值", movement.text, "6")


func _test_signal_forwarding(composition: Control) -> void:
	var skills_received: Array[String] = []
	var slots_received: Array[Array] = []
	var potions_received: Array[bool] = []
	var turns_received: Array[bool] = []
	var moves_received: Array[bool] = []
	composition.connect("skill_activated",
		func(skill_id: String) -> void: skills_received.append(skill_id))
	composition.connect("slot_requested",
		func(slot_id: String, content_id: String) -> void:
			slots_received.append([slot_id, content_id]))
	composition.connect("potion_requested", func() -> void: potions_received.append(true))
	composition.connect("end_turn_requested", func() -> void: turns_received.append(true))
	composition.connect("end_move_requested", func() -> void: moves_received.append(true))

	var shelf: Control = composition.get_node("BottomRow/SkillShelf") as Control
	var slots: Array = shelf.call("get_skill_slots") as Array
	if not slots.is_empty():
		(slots[0] as Button).pressed.emit()
	(composition.get_node("BottomRow/EquipmentHudPanel/WeaponSlot") as Button).pressed.emit()
	(composition.get_node("BottomRow/EquipmentHudPanel/PotionButton") as Button).pressed.emit()
	(composition.get_node("BottomRow/EndTurnControl/EndTurnButton") as Button).pressed.emit()
	_eq("技能激活信号由组合转发", skills_received, ["mock_skill_1"])
	_eq("通用槽请求由组合转发", slots_received, [["weapon", "mock_weapon"]])
	_eq("血瓶请求由组合转发", potions_received, [true])
	_eq("结束回合请求由组合转发", turns_received, [true])
	_eq("结束回合不会误发结束移动", moves_received, [])

	var end_view: RefCounted = EndViewData.new()
	end_view.set("action_kind", &"end_move")
	composition.call("apply_end_action", end_view)
	(composition.get_node("BottomRow/EndTurnControl/EndTurnButton") as Button).pressed.emit()
	_eq("结束移动请求由组合转发", moves_received, [true])


func _meter(current_value: int, maximum_value: int) -> RefCounted:
	var view: RefCounted = ValueMeterViewData.new()
	view.set("current_value", current_value)
	view.set("maximum_value", maximum_value)
	return view


func _slot(slot_id: String, occupied: bool, tooltip: String) -> RefCounted:
	var view: RefCounted = SlotViewData.new()
	view.set("slot_id", slot_id)
	view.set("content_id", "mock_%s" % slot_id if occupied else "")
	view.set("occupied", occupied)
	view.set("enabled", true)
	view.set("tooltip_text", tooltip)
	return view


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
