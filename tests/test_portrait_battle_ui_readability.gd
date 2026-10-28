extends "res://tests/test_portrait_token_battle.gd"
## Real entry regression for clipped header and action-resource refresh timing.


func _run() -> void:
	root.size = Vector2i(1280, 720)
	seed(20261027)
	session = load("res://scenes/tactical/character_pipeline/portrait_token_battle.tscn").instantiate()
	root.add_child(session)
	await wait(0.2)
	var battle: Node = session.battle
	var manager: Node = session.manager
	var actor: Unit = manager.current_unit
	var turn_order: Control = battle.get("_turn_order_bar") as Control
	var description: Label = session.get("_description") as Label
	check("header stays clear of turn order at the actual fixed viewport",
		not description.get_global_rect().intersects(turn_order.get_global_rect()))
	check("header uses the current skill input instead of the removed attack button",
		description.text.contains("选择技能") and not description.text.contains("攻击按钮"))
	var regular_text: String = description.text
	description.text = "很长的操作说明".repeat(60)
	await wait(0.05)
	check("long localized header is clipped to one line before the turn panel",
		description.clip_text and description.max_lines_visible == 1
		and not description.get_global_rect().intersects(turn_order.get_global_rect()))
	description.text = regular_text
	check("current actor initially displays available movement and standard action",
		_row(turn_order, actor).get("resource_texts", []).has("移动可用")
		and _row(turn_order, actor).get("resource_texts", []).has("标准可用"))
	_check_waiting(turn_order)
	click(manager, Vector2i(3, 4))
	await _settle(manager)
	check("real movement refreshes the current row without ending the turn",
		actor.grid_position == Vector2i(3, 4) and actor == manager.current_unit
		and _row(turn_order, actor).get("resource_texts", []).has("移动已用"))
	var target: Unit = manager.grid.get_unit_at(Vector2i(4, 4))
	_begin_strike(manager)
	manager.handle_pointer_hover(root.get_canvas_transform() * manager.grid.grid_to_world(target.grid_position))
	await wait(0.1)
	click(manager, target.grid_position)
	await _settle(manager)
	check("real skill settlement refreshes standard resource without ending the turn",
		actor.standard_used and actor == manager.current_unit
		and _row(turn_order, actor).get("resource_texts", []).has("标准已用"))
	manager.request_end_turn()
	await wait(0.1)
	check("next actor is current and previous actor has left this round's remaining queue",
		manager.current_unit != actor and _row(turn_order, actor).is_empty()
		and bool(_row(turn_order, manager.current_unit).get("current", false)))
	check("completed count follows the remaining queue",
		turn_order.call("get_debug_snapshot")["completed_text"] == "存活单位已行动 1 人")
	manager.request_end_turn()
	var enemy_move_observed: bool = false
	var enemy_attack_observed: bool = false
	var enemy_resources_current: bool = true
	for _index: int in 220:
		var active: Unit = manager.current_unit
		if active != null and active.faction == "enemy":
			var displayed: Array = _row(turn_order, active).get("resource_texts", [])
			if active.movement_used:
				enemy_move_observed = true
				enemy_resources_current = enemy_resources_current and displayed.has("移动已用")
			if active.standard_used:
				enemy_attack_observed = true
				enemy_resources_current = enemy_resources_current and displayed.has("标准已用")
		if manager.current_unit != null and manager.turn_manager.get_round_number() >= 2:
			break
		await wait(0.03)
	await wait(0.05)
	check("real enemy movement and attack expose consumed resources during their turn",
		enemy_move_observed and enemy_attack_observed and enemy_resources_current)
	var round_actor: Unit = manager.current_unit
	check("real enemy turns complete and next round begins",
		round_actor != null and manager.turn_manager.get_round_number() >= 2)
	_check_waiting(turn_order)
	check("next round's current actor displays its reset resources",
		_row(turn_order, round_actor).get("resource_texts", []).has("移动可用")
		and _row(turn_order, round_actor).get("resource_texts", []).has("标准可用"))
	session.queue_free()
	await wait(0.1)
	print("PORTRAIT_UI_READABILITY_RESULT=", JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)


func _row(turn_order: Control, unit: Unit) -> Dictionary:
	for row: Dictionary in turn_order.call("get_debug_snapshot")["units"]:
		if row["instance_id"] == unit.get_instance_id():
			return row
	return {}


func _check_waiting(turn_order: Control) -> void:
	for row: Dictionary in turn_order.call("get_debug_snapshot")["units"]:
		if not row["current"]:
			check("waiting unit never exposes previous-turn resource flags",
				row["waiting_text"] == "等待行动" and row["resource_texts"].is_empty())


func _settle(manager: Node) -> void:
	for _index: int in 100:
		if manager.input_state != manager.InputState.ANIMATING:
			break
		await wait(0.03)
	await wait(0.1)
