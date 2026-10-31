extends SceneTree

const Adapter := preload("res://scripts/ui/hud/m2/dashboard_view_adapter.gd")

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_manager_payload()
	_test_missing_and_action_states()
	_test_skill_semantics()
	await _test_m2_composition_receives_views()
	print("HUD_M2_DASHBOARD_VIEW_ADAPTER_RESULT passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_manager_payload() -> void:
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var manager: Object = scene.tactical_manager
	_check("真实 TacticalManager 可用", manager != null)
	if manager == null:
		scene.free()
		return
	var state: Dictionary = manager.get_dashboard_data()
	var before: Dictionary = state.duplicate(true)
	var result: Dictionary = Adapter.new().build(state)
	var character: RefCounted = result["character"]
	var unit: Node = manager._get_dashboard_unit()
	var resource: RefCounted = result["class_resources"]
	_check("真实manager职业身份进入显示元数据", state["class_resource_display"]["class_id"] == unit.unit_id)
	_check("真实资源按有效运行上限显隐", resource.visible == (unit._qi_max > 0))
	if resource.visible:
		_check("精确当前数值和动态上限来自manager", resource.body.qi.current_value == state["sword_qi"] and resource.body.qi.maximum_value == state["sword_qi_max"])
		_check("适用关系与容量分离", resource.body.marks_visible == (unit.unit_id == "kensei"))
	_check("真实载荷生成可见人物对象", result["visible"] and character != null)
	_check("真实人物身份不伪造玩家名", character.profession_name == str(state.get("unit_name", "")) and character.player_name.is_empty())
	_check("剑圣头像读取已选定的生成素材", character.portrait_texture is AtlasTexture and (character.portrait_texture as AtlasTexture).region == Rect2(320, 100, 660, 735) and (character.portrait_texture as AtlasTexture).atlas.resource_path == "res://assets/ui/portraits/kensei_hud_portrait_generated.png")
	_check("真实 HP 进入仪表", character.hp != null and character.hp.current_value == state["hp"] and character.hp.maximum_value == state["hp_max"])
	for mapping: Dictionary in [
		{"out": "STR", "in": "str"}, {"out": "MAG", "in": "mag"}, {"out": "DEX", "in": "dex"}, {"out": "SPE", "in": "spd"},
		{"out": "DEF", "in": "def"}, {"out": "RES", "in": "res"}, {"out": "LCK", "in": "lck"}, {"out": "MOV", "in": "mov"},
	]:
		var source_key: String = mapping["in"]
		var attribute: Dictionary = character.attribute_descriptions[mapping["out"]]
		_check("真实属性 %s 与增量" % mapping["out"], attribute["value"] == state["stats"][source_key] and attribute["delta"] == state["stats_delta"].get(source_key, 0))
	_check("转换不修改真实输入", state == before)
	scene.free()


func _test_missing_and_action_states() -> void:
	var adapter := Adapter.new()
	var guidance_source: Dictionary = _state_with_actions({})
	guidance_source["phase_text"] = "移动阶段"
	guidance_source["hint_text"] = "选择移动格"
	guidance_source["feedback_text"] = "超出攻击范围"
	var guidance: Dictionary = adapter.build(guidance_source)["guidance"]
	_check("阶段、操作提示和拒绝原因经适配器保留",
		guidance == {"phase_text": "移动阶段", "hint_text": "选择移动格", "feedback_text": "超出攻击范围"})
	var missing: Dictionary = adapter.build({"visible": true, "hp": 0, "hp_max": 0, "stats": {"str": 0}, "stats_delta": {"str": 0}})
	var character: RefCounted = missing["character"]
	_check("零值不是缺值", character.hp != null and character.hp.current_value == 0 and character.hp.maximum_value == 0 and character.attribute_value_text("STR") == "0")
	_check("缺失等级经验护盾和头像明确不可用", not character.has_level and character.experience == null and character.shield == null and character.portrait_texture == null)
	_check("缺失属性显示横线", character.attribute_value_text("MAG") == "—")
	var myrmidon: RefCounted = adapter.build({"visible": true, "unit_name": "剑士", "class_resource_display": {"class_id": "myrmidon"}})["character"]
	_check("剑士头像读取独立生成素材", myrmidon.portrait_texture is AtlasTexture and (myrmidon.portrait_texture as AtlasTexture).region == Rect2(320, 100, 660, 735) and (myrmidon.portrait_texture as AtlasTexture).atlas.resource_path == "res://assets/ui/portraits/myrmidon_hud_portrait_generated.png")
	var other_class: RefCounted = adapter.build({"visible": true, "unit_name": "法师", "class_resource_display": {"class_id": "mage"}})["character"]
	_check("其他职业不会误用剑士或剑圣头像", other_class.portrait_texture == null)
	_check("装备与遗物保持预留空槽", _is_reserved_slot(missing["weapon"]) and _is_reserved_slot(missing["armor"]) and missing["relics"].size() == 8 and missing["relics"].all(_is_reserved_slot))
	_check("药剂缺来源状态保持", missing["potion"].content_id.is_empty() and not missing["potion"].enabled and missing["potion"].tooltip_text == "暂无药剂信息")
	var valid: Dictionary = adapter.build(_state_with_actions({
		"movement_remaining": 0, "movement_available": false, "standard_capacity": 2, "standard_remaining": 0, "swift_capacity": 3, "swift_remaining": 2,
	}))
	_check("有效行动载荷保留零与容量", valid["action_resources_valid"] and valid["action_resources"].movement_remaining == 0 and valid["action_resources"].standard_capacity == 2 and valid["action_resources"].swift_remaining == 2)
	_check("结束移动优先结束回合", valid["end_action"].visible and valid["end_action"].action_kind == &"end_move")
	var invalid_state: Dictionary = _state_with_actions({"movement_remaining": 2, "movement_available": true, "standard_capacity": 0, "standard_remaining": 0, "swift_capacity": 1, "swift_remaining": 1})
	var invalid: Dictionary = adapter.build(invalid_state)
	_check("非法行动载荷隐藏行动条", not invalid["action_resources_valid"] and invalid["action_resources"] == null)
	var enemy: Dictionary = adapter.build(_state_with_actions({"movement_remaining": 2, "movement_available": true, "standard_capacity": 1, "standard_remaining": 1, "swift_capacity": 1, "swift_remaining": 1}, "enemy"))
	_check("敌方不显示行动条和结束动作", not enemy["action_resources_valid"] and not enemy["end_action"].visible)
	var no_action_state: Dictionary = _state_with_actions({"movement_remaining": 2, "movement_available": true, "standard_capacity": 1, "standard_remaining": 1, "swift_capacity": 1, "swift_remaining": 1})
	no_action_state["show_actions"] = false
	var no_action: Dictionary = adapter.build(no_action_state)
	_check("无行动态不显示行动条或结束动作", not no_action["action_resources_valid"] and not no_action["end_action"].visible)


func _test_skill_semantics() -> void:
	var self_cast_state: Dictionary = _state_with_actions({"movement_remaining": 1, "movement_available": true, "standard_capacity": 1, "standard_remaining": 1, "swift_capacity": 1, "swift_remaining": 1})
	self_cast_state["skills"] = [{"skill_id": "self_cast", "name": "自我强化", "available": true,
		"action_cost": "swift", "activation_hint": "点选即施放"}]
	var self_cast_view: RefCounted = Adapter.new().build(self_cast_state)["skills"][0]
	_check("自身技能激活方式进入技能说明", self_cast_view.tooltip_text.contains("操作：点选即施放"))
	var state: Dictionary = _state_with_actions({"movement_remaining": 1, "movement_available": true, "standard_capacity": 1, "standard_remaining": 1, "swift_capacity": 1, "swift_remaining": 1})
	state["skills"] = [
		{"skill_id": "passive", "name": "纯被动", "is_passive": true, "available": true, "action_cost": "swift", "description": "被动说明", "resource_cost_display": {"amount": 9, "resource_name": "错误来源"}, "qi_cost": 99},
		{"skill_id": "hybrid", "name": "A 不可用", "is_passive": true, "active_capable": true, "available": false, "action_cost": "move", "reason": "资源不足", "description": "混合说明", "resource_cost_display": {"amount": 12, "resource_name": "法力"}},
		{"skill_id": "unavailable", "name": "B 冷却", "available": false, "action_cost": "standard", "reason": "冷却中 (2 回合后恢复)", "cooldown": 2, "resource_cost_display": {"amount": 7, "resource_name": "斗志"}},
		{"skill_id": "third", "name": "招架", "available": true, "action_cost": "swift", "description": "迅捷·持续到下个自身回合开始；期间额外闪避 +N。持有 3 枚印记且剑气不少于 20 点时，本槽变为〔拔刀〕。"},
		{"skill_id": "fourth", "name": "拔刀", "available": false, "action_cost": "standard", "reason": "印记不足（需要 3 个，当前 2 个）", "description": "消耗 3 枚印记和 20 点剑气。", "resource_cost_display": {"amount": 20, "resource_name": "剑气"}},
		{"skill_id": "qi_unavailable", "name": "拔刀", "available": false, "action_cost": "standard", "reason": "剑气不足（需要 20，当前 15）", "description": "消耗 3 枚印记和 20 点剑气。", "resource_cost_display": {"amount": 20, "resource_name": "剑气"}},
	]
	var icons: Dictionary = {"hybrid": GradientTexture2D.new()}
	var views: Array = Adapter.new().build(state, icons)["skills"]
	_check("技能保持真实顺序", views.map(func(view: RefCounted) -> String: return view.skill_id) == ["passive", "hybrid", "unavailable", "third", "fourth", "qi_unavailable"])
	_check("纯被动无键位动作费用", views[0].passive and not views[0].active_capable and views[0].hotkey_text.is_empty() and views[0].resource_cost_display.is_empty())
	_check("纯被动说明不写行动消耗", not views[0].tooltip_text.contains("消耗："))
	_check("显式可主动被动保留行动与调用方图标", views[1].passive and views[1].active_capable and views[1].hotkey_text == "1" and views[1].icon_texture == icons["hybrid"])
	_check("A 不可用不激活且保留原因和移动行动费用", not views[1].can_activate() and views[1].tooltip_text.contains("资源不足") and views[1].tooltip_text.contains("消耗：移动行动"))
	_check("冷却技能保留冷却数与不可用原因", views[2].cooldown_turns == 2 and views[2].tooltip_text.contains("冷却中 (2 回合后恢复)"))
	_check("标准技能标出标准行动并保留职业资源名", views[2].tooltip_text.contains("消耗：标准行动") and views[2].resource_cost_display == {"amount": 7, "resource_name": "斗志"})
	_check("招架迅捷前缀不重复且效果和拔刀门槛仍在", views[3].tooltip_text.contains("消耗：迅捷行动") and not views[3].tooltip_text.contains("迅捷·") and views[3].tooltip_text.contains("额外闪避 +N") and views[3].tooltip_text.contains("持有 3 枚印记且剑气不少于 20 点"))
	_check("拔刀保留标准行动、印记与剑气费用及原因", views[4].tooltip_text.contains("消耗：标准行动") and views[4].tooltip_text.contains("消耗 3 枚印记和 20 点剑气") and views[4].tooltip_text.contains("印记不足") and views[4].resource_cost_display == {"amount": 20, "resource_name": "剑气"})
	_check("剑气不足原因与拔刀的职业费用仍在说明卡数据中", views[5].tooltip_text.contains("剑气不足（需要 20，当前 15）") and views[5].tooltip_text.contains("消耗 3 枚印记和 20 点剑气") and views[5].resource_cost_display == {"amount": 20, "resource_name": "剑气"})
	_check("不可用技能仍保留原快捷键顺序", views[1].hotkey_text == "1" and views[2].hotkey_text == "2" and views[3].hotkey_text == "3")
	_check("前四项主动能力按真实顺序分配一至四", views[1].hotkey_text == "1" and views[2].hotkey_text == "2" and views[3].hotkey_text == "3" and views[4].hotkey_text == "4")
	state["skills"][1]["available"] = true
	var changed_views: Array = Adapter.new().build(state)["skills"]
	_check("可用状态改变不令后续编号漂移", changed_views[1].hotkey_text == "1" and changed_views[2].hotkey_text == "2" and changed_views[3].hotkey_text == "3" and changed_views[4].hotkey_text == "4")
	_check("费用只读通用显示元数据", views[0].resource_cost_display.is_empty() and views[1].resource_cost_display == {"amount": 12, "resource_name": "法力"} and views[2].resource_cost_display == {"amount": 7, "resource_name": "斗志"})
	state["mode"] = "enemy"
	var enemy_views: Array = Adapter.new().build(state)["skills"]
	_check("敌方技能没有可触发键位", enemy_views.all(func(view: RefCounted) -> bool: return view.hotkey_text.is_empty() and not view.can_activate()))
	for example: Dictionary in [
		{"action": "move", "reason": "已失去移动机会", "expected": "移动行动已用"},
		{"action": "standard", "reason": "攻击机会已使用", "expected": "标准行动已用"},
		{"action": "swift", "reason": "迅捷机会已使用", "expected": "迅捷行动已用"},
	]:
		var spent_state: Dictionary = _state_with_actions({})
		spent_state["skills"] = [{"skill_id": "spent", "name": "已用技能", "available": false,
			"action_cost": example["action"], "reason": example["reason"]}]
		var spent_view: RefCounted = Adapter.new().build(spent_state)["skills"][0]
		_check("%s原因沿用行动名称且保持不可用" % example["action"],
			spent_view.tooltip_text.ends_with(example["expected"]) and not spent_view.can_activate())


func _test_m2_composition_receives_views() -> void:
	var composition: Control = (load("res://scenes/tactical/hud/m2/bottom_hud_composition.tscn") as PackedScene).instantiate()
	root.add_child(composition)
	await process_frame
	var composition_state: Dictionary = _state_with_actions({"movement_remaining": 1, "movement_available": true, "standard_capacity": 1, "standard_remaining": 1, "swift_capacity": 1, "swift_remaining": 1})
	composition_state["phase_text"] = "移动阶段"
	composition_state["hint_text"] = "选择移动格"
	var views: Dictionary = Adapter.new().build(composition_state)
	composition.apply_character(views["character"])
	composition.apply_class_resources(views["class_resources"])
	composition.apply_skills(views["skills"])
	composition.apply_action_resources(views["action_resources"])
	composition.apply_equipment(views["weapon"], views["armor"], views["potion"])
	composition.apply_relics(views["relics"])
	composition.apply_end_action(views["end_action"])
	composition.apply_action_guidance(views["guidance"])
	await process_frame
	var guidance_panel: Control = composition.get_node("ActionGuidance") as Control
	var phase_label: Label = guidance_panel.get_node("GuidanceLines/PhaseText") as Label
	var operation_label: Label = guidance_panel.get_node("GuidanceLines/OperationText") as Label
	_check("M2组合分两行显示阶段和常态操作提示",
		guidance_panel.visible and phase_label.text == "移动阶段" and operation_label.text == "选择移动格")
	composition_state["feedback_text"] = "目标超出范围；已取消选择"
	var rejected_guidance: Dictionary = Adapter.new().build(composition_state)["guidance"]
	composition.apply_action_guidance(rejected_guidance)
	_check("M2组合显示拒绝原因、取消状态和重选提示",
		phase_label.text == "移动阶段" and operation_label.text == "拒绝：目标超出范围；已取消选择")
	_check("提示面板和文字忽略鼠标输入",
		guidance_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and guidance_panel.get_node("GuidanceLines").mouse_filter == Control.MOUSE_FILTER_IGNORE
		and phase_label.mouse_filter == Control.MOUSE_FILTER_IGNORE
		and operation_label.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("全部显示对象和行动提示可被现有 M2 组合接收", true)
	var equipment: Control = composition.get_node("BottomRow/EquipmentHudPanel") as Control
	for path: String in ["WeaponSlot", "ArmorSlot"]:
		var slot: Button = equipment.get_node(path) as Button
		_check(path + " 实际控件无内容或类型轮廓", slot.disabled and not slot.find_child("IconRect", true, false).visible and not slot.find_child("EmptyGlyph", true, false).visible and not slot.find_child("LockGlyph", true, false).visible)
	composition.free()


func _is_reserved_slot(view: RefCounted) -> bool:
	return not view.slot_id.is_empty() and view.content_id.is_empty() and view.icon_texture == null and view.empty_kind == &"" and not view.occupied and not view.enabled and not view.locked and not view.can_request()


func _state_with_actions(resources: Dictionary, mode: String = "player") -> Dictionary:
	return {"visible": true, "mode": mode, "unit_name": "测试职业", "hp": 10, "hp_max": 20, "stats": {}, "stats_delta": {}, "show_actions": true, "skills_visible": true, "action_resources": resources, "buttons": {"end_move_visible": true, "end_move_disabled": false, "end_turn_visible": true, "end_turn_disabled": false}}


func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + label)
