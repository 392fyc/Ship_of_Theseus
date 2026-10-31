extends SceneTree
## UI-07：真实战斗输入状态、拒绝原因和取消恢复，不改目标合法性。
var passed: int = 0
var failed: int = 0
var scene: Node
var manager: Node
var actor: Unit

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	scene = load("res://scenes/tactical/TacticalScene.tscn").instantiate()
	scene.run_injected = true
	scene.injected_map_id = "test_arena"
	scene.injected_player_units = [{"class_id": "myrmidon", "pos": Vector2i(3, 3)}]
	scene.injected_enemy_units = [{"class_id": "test_lancer", "pos": Vector2i(5, 3)}]
	scene.debug_harness_enabled = false
	root.add_child(scene)
	await process_frame
	await process_frame
	manager = scene.get_node("TacticalManager")
	manager.turn_manager.stop()
	for unit: Unit in manager.units:
		if unit.faction == "player":
			actor = unit
	_check("剑士存在", actor != null)
	if actor == null:
		quit(1)
		return
	_prepare()
	_check("无普攻角色不提示可攻击", not str(manager.get_dashboard_data()["hint_text"]).contains("攻击"))
	var entry: Dictionary = manager._build_skill_entry(actor, "myrmidon_zhaojia")
	_check("自身技能明示直接施放", entry.get("activation_hint") == "点选即施放")
	manager.request_skill_selection("myrmidon_zhanji")
	manager._handle_click(Vector2i(3, 4))
	_expect_rejected("空格缺目标", "没有目标单位", manager.InputState.ACTION_PHASE)
	manager.request_skill_selection("myrmidon_zhanji")
	_check("重选清除旧错误", _feedback().is_empty())
	manager._handle_click(Vector2i(7, 3))
	_expect_rejected("超射程", "超出当前技能范围", manager.InputState.ACTION_PHASE)
	manager.request_cancel_action()
	_check("手动取消不保留错误", _feedback().is_empty())
	_prepare()
	manager.input_state = manager.InputState.MOVE_PHASE
	manager.request_skill_selection("myrmidon_yishan")
	_check("一闪先选方向", str(manager.get_dashboard_data()["hint_text"]).contains("1 选方向"))
	manager._handle_click(Vector2i(4, 4))
	_expect_rejected("非方向格", "高亮方向格", manager.InputState.MOVE_PHASE)
	manager.request_skill_selection("myrmidon_yishan")
	manager._handle_click(Vector2i(4, 3))
	_check("一闪第二步选落点", str(manager.get_dashboard_data()["hint_text"]).contains("2 选择"))
	_check("合法空落点仍可确认", manager._can_confirm_skill_target(Vector2i(4, 3)))
	manager._handle_click(Vector2i(5, 3))
	_expect_rejected("占据落点", "已被单位占据", manager.InputState.MOVE_PHASE)
	var cell: Cell = manager.grid.get_cell(Vector2i(4, 3))
	var original_terrain: int = cell.terrain
	cell.terrain = Cell.Terrain.WALL
	manager.request_skill_selection("myrmidon_yishan")
	manager._handle_click(Vector2i(4, 3))
	manager._handle_click(Vector2i(4, 3))
	_expect_rejected("不可站立落点", "无法站立", manager.InputState.MOVE_PHASE)
	cell.terrain = original_terrain
	manager.request_skill_selection("myrmidon_yishan")
	manager._handle_click(Vector2i(4, 3))
	manager._handle_click(Vector2i(4, 3))
	await _settled()
	_check("空落点实际执行", actor.grid_position == Vector2i(4, 3) and actor.movement_used)
	_check("执行后旧错误消失", _feedback().is_empty())
	_prepare()
	manager.request_skill_selection("myrmidon_zhaojia")
	_check("自身技能不进入选目标", manager.input_state != manager.InputState.SKILL_TARGETING)
	await _settled()
	_check("自身技能一次点选消耗迅捷", actor.swift_used)
	scene.queue_free()
	await process_frame
	print("UI07_ACTION_GUIDANCE_RESULT passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _prepare() -> void:
	actor.reset_action_resources()
	actor.skill_cooldowns.clear()
	manager.battle_active = true
	manager.current_unit = actor
	manager.selected_unit = actor
	manager.turn_manager.current_unit = actor
	manager.input_state = manager.InputState.ACTION_PHASE
	manager._selected_skill_id = ""
	manager._clear_targeting_buffers()
	manager._move_committed = true

func _feedback() -> String:
	return str(manager.get_dashboard_data().get("feedback_text", ""))

func _expect_rejected(label: String, reason: String, origin: int) -> void:
	_check(label + "解释原因", _feedback().contains(reason))
	_check(label + "返回来源阶段", manager.input_state == origin and manager.get_selected_skill_id().is_empty())
	_check(label + "不扣行动", not actor.standard_used and not actor.movement_used and not actor.swift_used)

func _settled() -> void:
	var deadline: int = Time.get_ticks_msec() + 120000
	while manager.input_state == manager.InputState.ANIMATING and Time.get_ticks_msec() < deadline:
		await process_frame
	_check("动作在截止前完成", manager.input_state != manager.InputState.ANIMATING)

func _check(label: String, ok: bool) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("UI07_FAILED " + label)
