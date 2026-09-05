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
			_eq("方槽中心不受名称影响", slot.get_global_rect().get_center().y, bar.get_global_rect().get_center().y)
			var name_label: Label = slot.get_node("NameLabel") as Label
			_eq("完整技能名", name_label.text, entries[index].name)
			var bottom_margin: float = (bar._panel.get_theme_stylebox(&"panel") as StyleBoxTexture).texture_margin_bottom
			_check("名称位于外框内部预留高度内", name_label.get_global_rect().end.y <= bar.get_global_rect().end.y - bottom_margin)
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
	states[1].cost_text = "自定费"
	states[1].qi_cost = 99
	states[2].cooldown = 2
	states[2].mark_cost = 1
	states[2].qi_cost = 20
	states[3].available = false
	states[3].reason = "测试夹具资源不足"
	states[4].action_cost = "swift"
	dashboard.update_state(_state(states, "fixture_1"))
	await _settle(dashboard)
	var passive: Button = bar._list.get_child(0)
	var selected: Button = bar._list.get_child(1)
	var cooling: Button = bar._list.get_child(2)
	var unavailable: Button = bar._list.get_child(3)
	_check("选中层直接绑定", selected.get_node("Content/SelectedOverlay").visible)
	_eq("cost_text优先", selected.get_node("Content/CostLabel").text, "自定费")
	_eq("费用按印记再剑气组合且不加单位", bar._build_cost_text(states[2], "standard"), "1+20")
	_eq("无职业费用时回退行动符号", bar._list.get_child(4).get_node("Content/CostLabel").text, "S")
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
	await _click((bar._list.get_child(1) as Button).get_global_rect().get_center())
	_eq("替换后仅新ID被激活", emitted, ["fixture_1", "fixture_replacement"])
	dashboard.update_state(_state(states).merged({"skills_visible": false}, true))
	_check("set_expanded关闭玩家技能栏", not bar.visible)
	dashboard.update_state(_state(states).merged({"mode": "enemy"}, true))
	_check("敌方状态隐藏技能栏", not bar.visible)
	dashboard.queue_free()
	await process_frame


func _exercise_real_input(key_index: int, keyboard: bool) -> Dictionary:
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var dashboard: BottomDashboard = scene._bottom_dashboard
	var manager: Object = scene.tactical_manager
	var unit: Unit = manager._get_dashboard_unit()
	manager.request_end_move()
	await _settle(dashboard)
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
