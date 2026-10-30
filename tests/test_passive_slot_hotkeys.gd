extends SceneTree
## 通过真实战斗按键验证技能顺序、被动转主动、恢复与图标辨识。

const Adapter := preload("res://scripts/ui/hud/m2/dashboard_view_adapter.gd")
const Hotkeys := preload("res://scripts/ui/skill_hotkeys.gd")
const LegacyBar := preload("res://scripts/ui/skill_bar.gd")
const EXPECTED: Array[String] = ["kensei_zhanji", "kensei_yishan", "kensei_zhaojia", "kensei_juhe"]

var _passed: int = 0
var _failed: int = 0
var _scene: Node
var _manager: Node
var _unit: Unit
var _base_passive_icon: Texture2D


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
	_check("冷却不令编号漂移", unavailable[0].hotkey_text == "1" and unavailable[4].hotkey_text == "5")
	await _key(KEY_1)
	_check("不可用技能不触发且不跳到下一技能", str(_manager._selected_skill_id).is_empty())
	_unit.skill_cooldowns.clear()
	# 主动槽换形态仍继承原编号；仅改变测试载荷，不修改技能或玩法数据。
	var state: Dictionary = _manager.get_dashboard_data()
	state["skills"][2]["skill_id"] = "fixture_active_slot_form"
	var views: Array = Adapter.new().build(state)["skills"]
	_check("主动槽替换形态保留三号键", views[2].skill_id == "fixture_active_slot_form" and views[2].hotkey_text == "3")
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
	var expected: Array[String] = EXPECTED.duplicate()
	if swapped:
		expected.insert(3, "kensei_kongxiangjian")
	_check(label + "当前主动技能均有数字键", numbered.size() == expected.size())
	_check(label + "心眼在招架与居合之间", views[2].skill_id == "kensei_zhaojia" and views[4].skill_id == "kensei_juhe")
	_check(label + "当前形态决定数字键", views[3].hotkey_text == ("4" if swapped else ""))
	_check(label + "保留鼠标激活能力", views[3].active_capable == swapped)
	var legacy := LegacyBar.new()
	root.add_child(legacy)
	var entries: Array[Dictionary] = []
	entries.assign(state["skills"])
	legacy.update_entries(entries, "", _unit.passive_skill_id)
	var slots: Array = _scene._bottom_dashboard.get_composition().get_node("BottomRow/SkillShelf").get_skill_slots()
	_check(label + "M2当前形态的数字角标", slots[3].get_node("Content/HotkeyBadge").visible == swapped)
	var icon: TextureRect = slots[3].get_node("Content/IconRect")
	_check(label + "M2被动槽显示实际图标", icon.visible and icon.texture != null)
	if _base_passive_icon == null and not swapped:
		_base_passive_icon = icon.texture
	elif swapped:
		_check(label + "主动替换图标区别于被动", icon.texture != null and icon.texture != _base_passive_icon)
		_check(label + "空想剑不复用斩击图标", icon.texture != slots[0].get_node("Content/IconRect").texture)
	else:
		_check(label + "升级被动恢复原心眼图标", icon.texture != null and icon.texture == _base_passive_icon)
	for index: int in range(expected.size()):
		var slot_index: int = index if swapped or index < 3 else index + 1
		_check(label + "编号" + str(index + 1), numbered[index]["skill_id"] == expected[index] and views[slot_index].hotkey_text == str(index + 1))
		_check(label + "M2角标" + str(index + 1), slots[slot_index].get_node("Content/HotkeyBadge/HotkeyText").text == str(index + 1))
		_check(label + "旧技能栏角标" + str(index + 1), legacy._list.get_child(slot_index + 1).key_text == str(index + 1))
	_check(label + "旧技能栏按当前形态编号", legacy._list.get_child(4).key_text == ("4" if swapped else "P"))
	_check(label + "视图未改写源载荷", state == before)
	legacy.free()
	for index: int in range(expected.size()):
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
			_check(label + "实际按键" + str(index + 1), _manager._selected_skill_id == expected[index] and _manager.input_state == _manager.InputState.SKILL_TARGETING)
			_manager.request_cancel_action()
			_check(label + "可以取消" + str(index + 1), str(_manager._selected_skill_id).is_empty())


func _test_mouse_replacement() -> void:
	_prepare()
	await process_frame
	var slots: Array = _scene._bottom_dashboard.get_composition().get_node("BottomRow/SkillShelf").get_skill_slots()
	var slot: Control = slots[3]
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
