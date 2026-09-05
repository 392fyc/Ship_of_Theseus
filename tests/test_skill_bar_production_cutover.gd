extends SceneTree
## 数量夹具只验证布局；真实技能输入另行加载 TacticalScene。

const SLOT_PATH := "res://scenes/tactical/production/skill_slot.tscn"
const SHELF_PATH := "res://scenes/tactical/hud/skill_shelf.tscn"
var _passed: int = 0
var _failed: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== test_skill_bar_production_cutover ===")
	await _test_facade()
	await _test_generic_resource_cost_source()
	for key_index: int in range(1, 5):
		var keyboard: Dictionary = await _exercise_real_input(key_index, true)
		var mouse: Dictionary = await _exercise_real_input(key_index, false)
		_eq("真实键%d与鼠标得到相同行为" % key_index, keyboard, mouse)
	print("--- 结果：%d 过 / %d 失败 ---" % [_passed, _failed.size()])
	for failure: String in _failed:
		print("  ✗ " + failure)
	quit(0 if _failed.is_empty() else 1)


func _test_facade() -> void:
	var dashboard: BottomDashboard = (load("res://scenes/tactical/bottom_dashboard.tscn") as PackedScene).instantiate()
	dashboard.size = Vector2(1280.0, 720.0)
	root.add_child(dashboard)
	var bar: SkillBar = dashboard._skill_bar
	_eq("正式技能架来自冻结场景", bar._panel.scene_file_path, SHELF_PATH)
	_eq("场景布局接入点", bar._list, bar._panel.get_node("SlotsCenter/Slots"))
	_check("保留公开输入和显示入口", bar.has_signal("skill_selected") and bar.has_method("update_entries") and bar.has_method("set_expanded"))
	var emitted: Array[String] = []
	dashboard.skill_selected.connect(func(skill_id: String) -> void: emitted.append(skill_id))
	for count: int in [0, 1, 4, 5, 6, 7, 8, 1, 0, 5]:
		var entries: Array[Dictionary] = _quantity_fixture(count)
		if count > 1:
			entries[1].resource_cost_display = {"amount": 20, "resource_name": "测试资源"}
		var original: Array[Dictionary] = entries.duplicate(true)
		dashboard.update_state(_state(entries))
		await _settle(dashboard)
		_eq("%d条输入不被改写" % count, entries, original)
		_eq("%d条无残留或假槽" % count, bar._list.get_child_count(), count)
		var expected_width: float = 476.0 if count <= 7 else 56.0 * count + 8.0 * (count - 1) + 36.0
		_eq("%d条门面尺寸" % count, bar.size, Vector2(expected_width, 108.0))
		_eq("%d条技能架尺寸" % count, bar._panel.size, bar.size)
		_eq("%d条空提示" % count, bar._empty_label.visible, count == 0)
		_eq("%d条横向间距" % count, bar._list.get_theme_constant(&"separation"), 8)
		var extent: float = 56.0 if count >= 7 else 64.0
		for index: int in count:
			var slot: Button = bar._list.get_child(index) as Button
			_eq("%d条槽%d继承正式场景" % [count, index], slot.scene_file_path, SLOT_PATH)
			_eq("方槽精确尺寸", slot.size, Vector2(extent, extent))
			if index == 1 and count in [5, 7]:
				_assert_badges(slot, "A", "20")
				_assert_badge_layout(slot)
			_eq("方槽中心不受名称影响", slot.get_global_rect().get_center().y, bar.get_global_rect().get_center().y)
			var expected_key: String = str(index) if index > 0 and index <= 4 else ""
			_eq("仅前四非被动显示真实快捷键", (slot.get_node("Content/HotkeyBadge/HotkeyText") as Label).text, expected_key)
		_eq("行动资源条尺寸保持", dashboard._action_resource_strip.size, Vector2(274.0, 40.0))
		_eq("行动资源条与技能架净距", bar.position.y - dashboard._action_resource_strip.position.y - 40.0, 6.0)
		_eq("行动资源条与技能架中线", dashboard._action_resource_strip.get_global_rect().get_center().x, bar.get_global_rect().get_center().x)
		var expected_top: float = dashboard.size.y
		for panel: Control in [dashboard._info_panel, dashboard._relic_panel, dashboard._action_shell, bar, dashboard._action_resource_strip]:
			if panel.visible:
				expected_top = minf(expected_top, panel.position.y)
		_eq("浮窗避让顶边包含当前技能架和资源条", dashboard.get_content_top_y(), expected_top)

	var states: Array[Dictionary] = _quantity_fixture(5)
	states[0].available = false
	states[0].resource_cost_display = {"amount": 20, "resource_name": "测试资源"}
	states[1].cost_text = "自定费"
	states[1].resource_cost_display = {"amount": 99, "resource_name": "测试资源"}
	states[2].cooldown = 2
	states[2].resource_cost_display = {"amount": 20, "resource_name": "测试资源"}
	states[3].available = false
	states[3].qi_cost = 321
	states[3].resource_cost_display = {}
	states[3].mark_cost = 3
	states[3].reason = "测试夹具资源不足"
	states[4].action_cost = "swift"
	states[4].resource_cost_display = {"amount": 10, "resource_name": "测试资源"}
	dashboard.update_state(_state(states, "fixture_1"))
	await _settle(dashboard)
	var passive: Button = bar._list.get_child(0)
	var selected: Button = bar._list.get_child(1)
	var cooling: Button = bar._list.get_child(2)
	var unavailable: Button = bar._list.get_child(3)
	_check("选中层直接绑定", selected.get_node("Content/SelectedOverlay").visible)
	_assert_badges(selected, "A", "99")
	_assert_badges(cooling, "A", "20", false)
	_assert_badges(unavailable, "A", "")
	_assert_badges(bar._list.get_child(4), "S", "10")
	_assert_badges(passive, "", "")
	_check("冷却行动角标位于暗层之后", cooling.get_node("Content/ActionTypeLabel").get_index() > cooling.get_node("Content/CooldownShade").get_index())
	_eq("首字占位", selected.get_node("Content/IconPlaceholder").text, states[1].name.left(1))
	_eq("冷却剩余回合", cooling.get_node("Content/CooldownTurnsLabel").text, "2")
	_check("冷却显示原暗层且禁用", cooling.disabled and cooling.get_node("Content/CooldownShade").visible)
	_check("纯被动禁用输入", passive.disabled)
	_eq("纯被动不因不能激活而灰化", passive.get_node("Content/IconPlaceholder").get_theme_color(&"font_color"), bar._get_cost_color("standard"))
	_eq("纯被动禁用皮肤保持正常内容", passive.get_theme_stylebox(&"disabled"), passive.get_theme_stylebox(&"normal"))
	_check("没有虚构次数", not passive.get_node("Content/ChargeText").visible)
	_check("被动说明保留", "（被动）" in passive.tooltip_text)
	_check("不可用原因保留", "测试夹具资源不足" in unavailable.tooltip_text)
	var tooltip: Control = unavailable.call("_make_custom_tooltip", unavailable.tooltip_text) as Control
	var tooltip_label: Label = tooltip.get_child(0) as Label
	_eq("tooltip内容宽度", tooltip_label.custom_minimum_size.x, 248.0)
	_eq("tooltip自动换行", tooltip_label.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
	_eq("tooltip内容完整", tooltip_label.text, unavailable.tooltip_text)
	tooltip.free()
	await _click(selected.get_global_rect().get_center())
	_eq("真实GUI点击穿过按钮到门面", emitted, ["fixture_1"])
	for blocked: Button in [passive, cooling, unavailable]:
		await _click(blocked.get_global_rect().get_center())
	_eq("纯被动冷却和不足不会误触发", emitted, ["fixture_1"])
	states[1].skill_id = "fixture_replacement"
	states[2].cooldown = 0
	dashboard.update_state(_state(states))
	await _settle(dashboard)
	_eq("同一位置的ID被替换", bar._list.get_child(1).get("_view").skill_id, "fixture_replacement")
	_check("选中不残留", not bar._list.get_child(1).get_node("Content/SelectedOverlay").visible)
	_check("冷却不残留", not bar._list.get_child(2).get_node("Content/CooldownShade").visible)
	_assert_badges(bar._list.get_child(2), "A", "20")
	await _click((bar._list.get_child(1) as Button).get_global_rect().get_center())
	_eq("替换后仅新ID被激活", emitted, ["fixture_1", "fixture_replacement"])
	for action_type: String in ["", "free", "unmapped"]:
		states[1].action_cost = action_type
		states[1].resource_cost_display = {"amount": 10, "resource_name": "测试资源"}
		dashboard.update_state(_state(states))
		await _settle(dashboard)
		_assert_badges(bar._list.get_child(1), "", "10")
	states[1].erase("action_cost")
	states[1].resource_cost_display = {}
	dashboard.update_state(_state(states))
	await _settle(dashboard)
	_assert_badges(bar._list.get_child(1), "", "")

	dashboard.update_state(_state(states).merged({"skills_visible": false}, true))
	_check("set_expanded关闭玩家技能栏", not bar.visible)
	dashboard.update_state(_state(states).merged({"mode": "enemy"}, true))
	_check("敌方状态隐藏技能栏", not bar.visible)
	dashboard.queue_free()
	await process_frame


func _test_generic_resource_cost_source() -> void:
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var dashboard: BottomDashboard = scene._bottom_dashboard
	var manager: Object = scene.tactical_manager
	var unit: Unit = manager._get_dashboard_unit()
	manager.request_end_move()
	await _settle(dashboard)
	var data_loader: Object = root.get_node("DataLoader")
	var fixture_id: String = "hud_generic_resource_display_fixture"
	var had_fixture: bool = data_loader.skills.has(fixture_id)
	var saved_fixture: Variant = data_loader.skills.get(fixture_id)
	# 只替换本进程测试缓存；不新增职业配置，也不执行虚构资源扣费。
	var template: Dictionary = manager._get_skill_data("swordsman_zhanji").duplicate(true)
	template.id = fixture_id
	template.name = "通用资源显示夹具"
	template.description = "仅验证显示元数据，不定义其他职业的可用性或扣费规则。"
	var json_source: Dictionary = JSON.parse_string('{"amount":12,"resource_name":"法力"}') as Dictionary
	_eq("JSON整数文本实际解析为float", typeof(json_source.amount), TYPE_FLOAT)
	var cases: Array[Dictionary] = [
		{"label": "非剑气整数", "display": {"amount": 7, "resource_name": " 法力 "}, "qi_cost": 0, "expected": {"amount": 7, "resource_name": "法力"}},
		{"label": "显式元数据覆盖剑气", "display": {"amount": 8, "resource_name": "斗志"}, "expected": {"amount": 8, "resource_name": "斗志"}},
		{"label": "整数值float", "display": {"amount": 9.0, "resource_name": "法力"}, "expected": {"amount": 9, "resource_name": "法力"}},
		{"label": "JSON整数来源", "display": json_source, "expected": {"amount": 12, "resource_name": "法力"}},
		{"label": "三位费用64槽", "display": {"amount": 999, "resource_name": "法力"}, "qi_cost": 0, "slot_count": 1, "expected": {"amount": 999, "resource_name": "法力"}},
		{"label": "三位费用56槽", "display": {"amount": 999, "resource_name": "法力"}, "qi_cost": 0, "slot_count": 7, "expected": {"amount": 999, "resource_name": "法力"}},
		{"label": "显式空对象", "display": {}},
		{"label": "零", "display": {"amount": 0, "resource_name": "法力"}},
		{"label": "负数", "display": {"amount": -1, "resource_name": "法力"}},
		{"label": "字符串数值", "display": {"amount": "7", "resource_name": "法力"}},
		{"label": "布尔数值", "display": {"amount": true, "resource_name": "法力"}},
		{"label": "小数", "display": {"amount": 7.5, "resource_name": "法力"}},
		{"label": "正无穷", "display": {"amount": INF, "resource_name": "法力"}},
		{"label": "负无穷", "display": {"amount": -INF, "resource_name": "法力"}},
		{"label": "非数", "display": {"amount": NAN, "resource_name": "法力"}},
		{"label": "超int范围", "display": {"amount": 9223372036854775808.0, "resource_name": "法力"}},
		{"label": "缺少数值", "display": {"resource_name": "法力"}},
		{"label": "缺少名称", "display": {"amount": 7}},
		{"label": "空名称", "display": {"amount": 7, "resource_name": "  "}},
		{"label": "数字名称", "display": {"amount": 7, "resource_name": 12}},
		{"label": "null名称", "display": {"amount": 7, "resource_name": null}},
		{"label": "null元数据", "display": null},
		{"label": "数组元数据", "display": [{"amount": 7, "resource_name": "法力"}]},
		{"label": "缺省才适配剑气", "absent": true, "qi_cost": 20, "mark_cost": 3, "expected": {"amount": 20, "resource_name": "剑气"}},
		{"label": "纯印记不构造费用", "absent": true, "qi_cost": 0, "mark_cost": 3},
		{"label": "缺省零剑气", "absent": true, "qi_cost": 0},
	]
	var unit_resources_before: Array = [unit.standard_remaining, unit.swift_remaining, unit.sword_qi, unit.get_mark_count()]
	for test_case: Dictionary in cases:
		var label: String = test_case.label
		var skill_data: Dictionary = template.duplicate(true)
		skill_data.qi_cost = test_case.get("qi_cost", 60)
		skill_data.mark_cost = test_case.get("mark_cost", 0)
		skill_data.requires_marks = skill_data.mark_cost
		skill_data.cost_text = "旧费用文本"
		# 对照只去掉显示元数据，证明通用显示接口没有改变现有可用性判定。
		data_loader.skills[fixture_id] = skill_data.duplicate(true)
		var control_entry: Dictionary = manager._build_skill_entry(unit, fixture_id)
		if not test_case.get("absent", false):
			skill_data.resource_cost_display = test_case.get("display")
		var source_before: PackedByteArray = var_to_bytes(skill_data)
		data_loader.skills[fixture_id] = skill_data
		var entry: Dictionary = manager._build_skill_entry(unit, fixture_id)
		var expected: Dictionary = test_case.get("expected", {})
		_eq(label + "经过真实entry归一", entry.resource_cost_display, expected)
		if not expected.is_empty():
			_eq(label + "输出amount归一为int", typeof(entry.resource_cost_display.amount), TYPE_INT)
		_eq(label + "不改源技能数据", var_to_bytes(skill_data), source_before)
		_eq(label + "可用性与原因不受显示元数据影响", [entry.available, entry.reason], [control_entry.available, control_entry.reason])
		var entry_before: PackedByteArray = var_to_bytes(entry)
		var entries: Array[Dictionary] = [entry]
		if test_case.get("slot_count", 1) == 7:
			entries.append_array(_quantity_fixture(6))
		dashboard.update_state(_state(entries))
		await _settle(dashboard)
		var slot: Button = dashboard._skill_bar._list.get_child(0)
		_assert_badges(slot, "A", str(expected.amount) if not expected.is_empty() else "")
		if test_case.has("slot_count"):
			var extent: float = 56.0 if test_case.slot_count == 7 else 64.0
			_eq(label + "真实方槽尺寸", slot.size, Vector2(extent, extent))
			_assert_badge_layout(slot)
			_eq(label + "原费用缩放保持1", slot.get_node("Content/CostLabel").scale, Vector2.ONE)
		_eq(label + "HUD不改输入entry", var_to_bytes(entry), entry_before)
		_check(label + "tooltip保留名称与描述", entry.name in slot.tooltip_text and entry.description in slot.tooltip_text)
		if entry.reason != "":
			_check(label + "tooltip保留不可用原因", entry.reason in slot.tooltip_text)
		if expected.is_empty():
			_check(label + "tooltip不伪造资源费用", not "消耗：" in slot.tooltip_text)
		else:
			_check(label + "资源名只进入费用说明", "消耗：%d %s" % [expected.amount, expected.resource_name] in slot.tooltip_text)
	_eq("构建entry与HUD不会消费任何资源", [unit.standard_remaining, unit.swift_remaining, unit.sword_qi, unit.get_mark_count()], unit_resources_before)
	_eq("真实被动entry显式提供空显示数据", manager._build_passive_entry(unit).resource_cost_display, {})
	if had_fixture:
		data_loader.skills[fixture_id] = saved_fixture
	else:
		data_loader.skills.erase(fixture_id)
	scene.queue_free()
	await process_frame

func _assert_badges(slot: Button, action_text: String, resource_text: String, resource_visible: bool = true) -> void:
	var action_label: Label = slot.get_node("Content/ActionTypeLabel") as Label
	var cost_label: Label = slot.get_node("Content/CostLabel") as Label
	_eq("左下行动类型", action_label.text, action_text)
	_eq("右下只显示职业资源数字", cost_label.text, resource_text)
	_eq("行动类型可见性", action_label.visible, action_text != "")
	_eq("职业资源可见性", cost_label.visible, resource_visible and resource_text != "")


func _assert_badge_layout(slot: Button) -> void:
	var action_rect: Rect2 = (slot.get_node("Content/ActionTypeLabel") as Control).get_rect()
	var resource_rect: Rect2 = (slot.get_node("Content/CostLabel") as Control).get_rect()
	var slot_rect := Rect2(Vector2.ZERO, slot.size)
	_check("两角标矩形不交叠", not action_rect.intersects(resource_rect))
	_check("两角标完整位于方槽内", slot_rect.encloses(action_rect) and slot_rect.encloses(resource_rect))
	_check("行动类型位于左下半区", action_rect.end.x <= slot.size.x / 2.0 and action_rect.position.y >= slot.size.y / 2.0)
	_check("职业资源位于右下半区", resource_rect.position.x >= slot.size.x / 2.0 and resource_rect.position.y >= slot.size.y / 2.0)

func _exercise_real_input(key_index: int, keyboard: bool) -> Dictionary:
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var dashboard: BottomDashboard = scene._bottom_dashboard
	var manager: Object = scene.tactical_manager
	var unit: Unit = manager._get_dashboard_unit()
	manager.request_end_move()
	await _settle(dashboard)
	if keyboard and key_index == 1:
		var expected_badges: Dictionary = {
			"swordsman_xinyan": ["", ""], "swordsman_zhanji": ["A", ""],
			"swordsman_yishan": ["M", "10"], "swordsman_zhaojia": ["S", "10"],
			"swordsman_juhe": ["A", "60"],
		}
		for real_slot: Button in dashboard._skill_bar._list.get_children():
			var skill_id: String = real_slot.get("_view").skill_id
			_check("真实技能角标存在已核实期望", expected_badges.has(skill_id))
			if expected_badges.has(skill_id):
				_assert_badges(real_slot, expected_badges[skill_id][0], expected_badges[skill_id][1])
	var entries: Array = manager.get_dashboard_data().skills
	var active: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if not entry.get("is_passive", false):
			active.append(entry)
	_check("真实场景存在键%d对应技能" % key_index, active.size() >= key_index)
	if active.size() < key_index:
		scene.queue_free()
		await process_frame
		return {}
	var target: Dictionary = active[key_index - 1]
	_check("真实行动阶段至少存在可用技能", active.any(func(entry: Dictionary) -> bool: return entry.available))
	var standard_before: int = unit.standard_remaining
	var swift_before: int = unit.swift_remaining
	var slot: Button = null
	for candidate: Button in dashboard._skill_bar._list.get_children():
		if candidate.get("_view").skill_id == target.skill_id:
			slot = candidate
	_eq("真实技能键位标识", slot.get_node("Content/HotkeyBadge/HotkeyText").text, str(key_index))
	var emitted: Array[String] = []
	dashboard.skill_selected.connect(func(skill_id: String) -> void: emitted.append(skill_id))
	if keyboard:
		var press := InputEventKey.new()
		press.physical_keycode = KEY_1 + key_index - 1
		press.keycode = press.physical_keycode
		press.pressed = true
		root.push_input(press, true)
		var release: InputEventKey = press.duplicate()
		release.pressed = false
		root.push_input(release, true)
		await process_frame
	else:
		await _click(slot.get_global_rect().get_center())
		_eq("真实鼠标是否发出技能ID", emitted, [str(target.skill_id)] if target.available else [])
	var result: Dictionary = {
		"skill_id": target.skill_id, "available": target.available,
		"selected": manager._selected_skill_id, "phase": manager.input_state,
		"standard": unit.standard_remaining, "swift": unit.swift_remaining,
		"cooldowns": unit.skill_cooldowns.duplicate(true),
	}
	if not target.available:
		_eq("不可用真实技能保持未选中", manager._selected_skill_id, "")
	else:
		var skill_data: Dictionary = manager._get_skill_data(target.skill_id)
		if str(skill_data.get("range", {}).get("type", "")) == "self":
			_check("可用自身技能真实执行并消费行动", unit.standard_remaining < standard_before or unit.swift_remaining < swift_before)
		else:
			_eq("可用真实技能进入正确目标选择", manager._selected_skill_id, target.skill_id)
	scene.queue_free()
	await process_frame
	return result


func _quantity_fixture(count: int) -> Array[Dictionary]:
	var names: Array[String] = ["心眼", "斩击", "居合", "招架", "绝影", "破阵", "回风", "流光"]
	var result: Array[Dictionary] = []
	for index: int in count:
		result.append({"skill_id": "fixture_%d" % index, "name": names[index],
			"description": "明确标注的数量与状态测试夹具，不是角色技能配置。",
			"available": true, "is_passive": index == 0, "cooldown": 0,
			"action_cost": "standard", "hotkey": "Q"})
	return result


func _state(entries: Array[Dictionary], selected: String = "") -> Dictionary:
	return {"visible": true, "mode": "player", "show_actions": true, "skills_visible": true,
		"skills": entries, "selected_skill_id": selected,
		"action_resources": {"movement_remaining": 4, "movement_available": true,
			"standard_capacity": 1, "standard_remaining": 1, "swift_capacity": 1, "swift_remaining": 1}}


func _settle(dashboard: BottomDashboard) -> void:
	if dashboard._visibility_tween != null and dashboard._visibility_tween.is_running():
		await dashboard._visibility_tween.finished
	await process_frame
	await process_frame
	await process_frame


func _click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	var press := InputEventMouseButton.new()
	press.position = point
	press.global_position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	var release: InputEventMouseButton = press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await process_frame


func _check(label: String, valid: bool) -> void:
	if valid:
		_passed += 1
	else:
		_failed.append(label)


func _eq(label: String, actual: Variant, expected: Variant) -> void:
	_check(label + "：实际%s，期望%s" % [str(actual), str(expected)], actual == expected)
