extends SceneTree
## #98：通过真实战斗场景的按键入口验证被动槽替换前、期间、结束后的编号与鼠标选择。

const Adapter := preload("res://scripts/ui/hud/m2/dashboard_view_adapter.gd")
const Hotkeys := preload("res://scripts/ui/skill_hotkeys.gd")
const LegacyBar := preload("res://scripts/ui/skill_bar.gd")
const EXPECTED: Array[String] = ["kensei_zhanji", "kensei_yishan", "kensei_zhaojia", "kensei_juhe"]

var _passed: int = 0
var _failed: int = 0
var _scene: Node
var _manager: Node
var _unit: Unit


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_scene = load("res://scenes/tactical/TacticalScene.tscn").instantiate()
	_scene.run_injected = true
	_scene.injected_map_id = "test_arena"
	_scene.injected_player_units = [{"class_id": "kensei", "pos": Vector2i(3, 3)}]
	_scene.injected_enemy_units = [{"class_id": "test_lancer", "pos": Vector2i(5, 3)}]
	_scene.debug_harness_enabled = false
	root.add_child(_scene)
	await process_frame
	await process_frame
	_manager = _scene.get_node("TacticalManager")
	_manager.turn_manager.stop()
	for value: Unit in _manager.units:
		if value.faction == "player":
			_unit = value
	_check("取得真实剑圣", _unit != null)
	if _unit == null:
		quit(1)
		return
	_prepare()
	await _test_state("普通", false)
	_prepare()
	var applied: Dictionary = _manager.request_apply_memory(_unit, "kensei_xinyanche")
	_check("通过运行时兑现大梦将醒", bool(applied.get("ok", false)))
	_unit.set_sword_qi(_unit._qi_max)
	_manager._apply_passive_turn_start(_unit)
	_check("触发空想", _unit.held_states.has("kensei_kongxiang"))
	await _test_state("空想期间", true)
	await _test_mouse_replacement()
	_prepare()
	_unit.skill_cooldowns["kensei_zhanji"] = 1
	_scene._refresh_dashboard()
	var unavailable: Array = Adapter.new().build(_manager.get_dashboard_data())["skills"]
	_check("冷却不令编号漂移", unavailable[1].hotkey_text == "1" and unavailable[4].hotkey_text == "4")
	await _key(KEY_1)
	_check("不可用技能不触发且不跳到下一技能", str(_manager._selected_skill_id).is_empty())
	_unit.skill_cooldowns.clear()
	# 主动槽换形态仍继承原编号；仅改变测试载荷，不修改技能或玩法数据。
	var state: Dictionary = _manager.get_dashboard_data()
	state["skills"][3]["skill_id"] = "fixture_active_slot_form"
	var views: Array = Adapter.new().build(state)["skills"]
	_check("主动槽替换形态保留三号键", views[3].skill_id == "fixture_active_slot_form" and views[3].hotkey_text == "3")
	_manager._on_turn_ended(_unit)
	_check("回合结束退出空想", not _unit.held_states.has("kensei_kongxiang"))
	await _test_state("空想结束", false)
	_scene.queue_free()
	await process_frame
	print("PASSIVE_SLOT_HOTKEYS_RESULT passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _prepare() -> void:
	_unit.reset_action_resources()
	_unit.skill_cooldowns.clear()
	_unit.set_sword_qi(_unit._qi_max)
	_manager.battle_active = true
	_manager.current_unit = _unit
	_manager.selected_unit = _unit
	_manager.turn_manager.current_unit = _unit
	_manager.input_state = _manager.InputState.ACTION_PHASE
	_manager._selected_skill_id = ""
	_scene._refresh_dashboard()


func _test_state(label: String, swapped: bool) -> void:
	_prepare()
	var state: Dictionary = _manager.get_dashboard_data()
	var before: Dictionary = state.duplicate(true)
	_check(label + "载荷提供实际被动身份", state.get("passive_skill_id") == _unit.passive_skill_id)
	var views: Array = Adapter.new().build(state)["skills"]
	var numbered: Array[Dictionary] = Hotkeys.numbered_entries(state["skills"], state["passive_skill_id"])
	_check(label + "恰有四个数字键", numbered.size() == 4)
	_check(label + "被动槽不显示数字", views[0].hotkey_text.is_empty())
	_check(label + "保留鼠标激活能力", views[0].active_capable == swapped)
	var legacy := LegacyBar.new()
	root.add_child(legacy)
	var entries: Array[Dictionary] = []
	entries.assign(state["skills"])
	legacy.update_entries(entries, "", _unit.passive_skill_id)
	var slots: Array = _scene._bottom_dashboard.get_composition().get_node("BottomRow/SkillShelf").get_skill_slots()
	_check(label + "M2被动槽不显示数字角标", not slots[0].get_node("Content/HotkeyBadge").visible)
	for index: int in range(4):
		_check(label + "编号" + str(index + 1), numbered[index]["skill_id"] == EXPECTED[index] and views[index + 1].hotkey_text == str(index + 1))
		_check(label + "M2角标" + str(index + 1), slots[index + 1].get_node("Content/HotkeyBadge/HotkeyText").text == str(index + 1))
		_check(label + "旧技能栏角标" + str(index + 1), legacy._list.get_child(index + 2).key_text == str(index + 1))
	_check(label + "旧被动槽不冒充数字键", legacy._list.get_child(1).key_text == ("" if swapped else "P"))
	_check(label + "视图未改写源载荷", state == before)
	legacy.free()
	for index: int in range(4):
		_prepare()
		await _key(KEY_1 + index)
		if index == 2:
			# 招架是自身技能，原操作会直接施放；其他三项进入选目标。
			var deadline: int = Time.get_ticks_msec() + 120000
			while _manager.input_state == _manager.InputState.ANIMATING and Time.get_ticks_msec() < deadline:
				await process_frame
			_check(label + "三号键使用招架", _unit.swift_used and int(_unit.skill_cooldowns.get("kensei_zhaojia", 0)) > 0)
			_check(label + "招架完成", _manager.input_state != _manager.InputState.ANIMATING)
		else:
			_check(label + "实际按键" + str(index + 1), _manager._selected_skill_id == EXPECTED[index] and _manager.input_state == _manager.InputState.SKILL_TARGETING)
			_manager.request_cancel_action()
			_check(label + "可以取消" + str(index + 1), str(_manager._selected_skill_id).is_empty())


func _test_mouse_replacement() -> void:
	_prepare()
	await process_frame
	var slots: Array = _scene._bottom_dashboard.get_composition().get_node("BottomRow/SkillShelf").get_skill_slots()
	var slot: Control = slots[0]
	_check("空想剑仍为可点击条目", slot.get("_view").skill_id == "kensei_kongxiangjian" and not slot.disabled)
	var point: Vector2 = slot.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = down
		root.push_input(event, true)
	await process_frame
	_check("鼠标点击进入空想剑选目标", _manager._selected_skill_id == "kensei_kongxiangjian" and _manager.input_state == _manager.InputState.SKILL_TARGETING)
	_manager.request_cancel_action()
	_check("空想剑可以取消", str(_manager._selected_skill_id).is_empty())
	root.gui_release_focus()


func _key(code: int) -> void:
	root.gui_release_focus()
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		root.push_input(event, true)
	await process_frame


func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + label)
