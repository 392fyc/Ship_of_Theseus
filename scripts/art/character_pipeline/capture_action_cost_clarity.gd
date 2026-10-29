extends "res://scripts/art/character_pipeline/capture_portrait_token_facing_align.gd"
## UI-06: real entry, real HUD input and action execution. Resource boundary setup is explicit.

var capture_case: String = "normal"
var flow_complete: bool = false
var checks: Array[Dictionary] = []
var fixture_changes: Array[Dictionary] = []


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
		elif argument.begins_with("--frames="):
			total_frames = int(argument.trim_prefix("--frames="))
		elif argument.begins_with("--case="):
			capture_case = argument.trim_prefix("--case=")
	if output.is_empty() or not output.is_absolute_path() or total_frames < 360 \
			or total_frames > 1200 or capture_case not in ["normal", "threshold"] \
			or DisplayServer.get_name() == "headless":
		push_error("UI-06 capture requires a display, absolute output, valid case and 360-1200 frames")
		quit(2)
		return
	frames_dir = output.path_join("frames")
	DirAccess.make_dir_recursive_absolute(frames_dir)
	root.size = Vector2i(WIDTH, HEIGHT)
	seed(20261027)
	_start.call_deferred()


func _dashboard() -> Control:
	return session.get("battle").get("_bottom_dashboard") as Control


func _slot(skill_id: String) -> Control:
	var slots: Array = _dashboard().get_composition().get_node("BottomRow/SkillShelf").get_skill_slots()
	for slot: Control in slots:
		if str(slot.get("_view").skill_id) == skill_id:
			return slot
	return null


func _check(name: String, ok: bool) -> void:
	checks.append({"name": name, "ok": ok, "frame": frame_index})
	if not ok:
		push_error("UI06_CHECK_FAILED: " + name)
		quit(3)


func _move_pointer(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	Input.parse_input_event(motion)


func _hover_skill(skill_id: String, marker: String) -> void:
	var slot: Control = _slot(skill_id)
	_check(marker + "_slot_exists", slot != null)
	if slot == null:
		return
	_move_pointer(slot.get_global_rect().get_center())
	for _frame: int in range(4):
		await process_frame
	_check(marker + "_card_visible", slot.is_inspection_visible())
	_event(marker, {"skill": skill_id, "card": slot.get_inspection_text(),
		"disabled": slot.disabled, "hud": _dashboard().get_last_state()})
	await create_timer(1.6).timeout


func _click_skill(skill_id: String) -> void:
	var slot: Control = _slot(skill_id)
	_check(skill_id + "_clickable", slot != null and not slot.disabled)
	if slot == null or slot.disabled:
		return
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = slot.get_global_rect().get_center()
		Input.parse_input_event(click)
		await process_frame
	await _settled_ui06()


func _settled_ui06() -> void:
	# Software rendering with PNG capture runs slower than the fixed simulation clock.
	var deadline: int = Time.get_ticks_msec() + 120000
	while manager.get("input_state") == manager.InputState.ANIMATING \
			and frame_index < total_frames - 1 and Time.get_ticks_msec() < deadline:
		await process_frame
	_check("animation_finished", manager.get("input_state") != manager.InputState.ANIMATING)
	await create_timer(0.2).timeout


func _walk_to(unit: Unit, destination: Vector2i) -> void:
	_move_pointer(_screen(destination))
	manager.call("handle_pointer_click", _screen(destination))
	await _settled_ui06()
	_check("move_reached_" + str(destination), unit.grid_position == destination)


func _drive_player_ai() -> void:
	await create_timer(0.8).timeout
	if capture_case == "threshold":
		await _threshold_sequence()
	else:
		await _normal_sequence()
	flow_complete = true
	_move_pointer(Vector2(30, 180))
	_event("sequence_complete", {"case": capture_case})


func _normal_sequence() -> void:
	var actor: Unit = manager.get("current_unit") as Unit
	_check("normal_starts_with_myrmidon", actor.unit_id == "myrmidon")
	_event("opening", {"hud": _dashboard().get_last_state()})
	await _hover_skill("myrmidon_yishan", "move_available")
	await _walk_to(actor, Vector2i(3, 4))
	_check("movement_spent", actor.movement_used)
	await _hover_skill("myrmidon_yishan", "move_spent")
	_check("move_spent_reason_visible", _slot("myrmidon_yishan").get_inspection_text().contains("移动行动已用"))
	await _hover_skill("myrmidon_juhe", "qi_insufficient")
	_check("qi_insufficient_reason_visible", _slot("myrmidon_juhe").get_inspection_text().contains("剑气不足"))
	await _hover_skill("myrmidon_zhanji", "standard_cost")
	await _click_skill("myrmidon_zhanji")
	var target: Unit = manager.get("grid").get_unit_at(Vector2i(4, 4))
	_check("strike_target_present", target != null)
	if target == null:
		return
	_move_pointer(_screen(target.grid_position))
	manager.call("handle_pointer_hover", _screen(target.grid_position))
	_event("strike_targeting", {})
	await create_timer(1.0).timeout
	manager.call("handle_pointer_click", _screen(target.grid_position))
	await _settled_ui06()
	_check("standard_spent", actor.standard_used)
	await _hover_skill("myrmidon_zhanji", "standard_spent")
	_check("standard_spent_reason_visible", _slot("myrmidon_zhanji").get_inspection_text().contains("标准行动已用"))
	manager.call("request_end_turn")
	await create_timer(0.3).timeout
	var kensei: Unit = manager.get("current_unit") as Unit
	_check("normal_kensei_turn", kensei.unit_id == "kensei")
	await _hover_skill("kensei_zhaojia", "mark_requirement")
	# Show swift consumption on the next actor, still in the movement phase.
	await _click_skill("kensei_zhaojia")
	_check("swift_spent", kensei.swift_used)
	await _hover_skill("kensei_zhaojia", "swift_spent")
	manager.call("request_end_turn")
	await create_timer(3.0).timeout


func _set_boundary_resources(unit: Unit, mark_count: int, qi: int, marker: String) -> void:
	var index: int = 0
	for key: String in unit.marks:
		unit.marks[key] = index < mark_count
		index += 1
	unit.set_sword_qi(qi)
	fixture_changes.append({"frame": frame_index, "unit": unit.unit_id,
		"purpose": "resource threshold test setup", "marks": mark_count, "qi": qi})
	manager.call("_emit_dashboard_state_changed")
	await process_frame
	_event(marker, {"marks": unit.get_mark_count(), "qi": unit.sword_qi})


func _threshold_sequence() -> void:
	manager.call("request_end_turn")
	await create_timer(0.3).timeout
	var actor: Unit = manager.get("current_unit") as Unit
	_check("threshold_kensei_turn", actor.unit_id == "kensei")
	await _walk_to(actor, Vector2i(4, 5))
	var guard: Dictionary = manager.call("_get_skill_data", "kensei_zhaojia")
	var requirement: Dictionary = guard.get("slot_swap_requires", {})
	var need_marks: int = int(requirement.get("marks", 0))
	var need_qi: int = int(requirement.get("qi", 0))
	_check("threshold_data_present", need_marks > 0 and need_qi > 0)
	await _set_boundary_resources(actor, need_marks - 1, need_qi, "marks_below_threshold")
	_check("low_marks_keeps_guard", _slot("kensei_zhaojia") != null and _slot("kensei_badao") == null)
	await _hover_skill("kensei_zhaojia", "marks_below_card")
	await _set_boundary_resources(actor, need_marks, need_qi - 1, "qi_below_threshold")
	_check("low_qi_keeps_guard", _slot("kensei_zhaojia") != null and _slot("kensei_badao") == null)
	await _hover_skill("kensei_zhaojia", "qi_below_card")
	await _set_boundary_resources(actor, need_marks, need_qi, "threshold_met")
	_check("threshold_swaps_to_badao", _slot("kensei_badao") != null)
	await _hover_skill("kensei_badao", "badao_cost")
	await _click_skill("kensei_badao")
	_check("badao_consumed_standard", actor.standard_used)
	_check("badao_consumed_marks", actor.get_mark_count() == 0)
	_check("badao_consumed_qi", actor.sword_qi == 0)
	_event("badao_resolved", {"marks": actor.get_mark_count(), "qi": actor.sword_qi})
	await _hover_skill("kensei_zhaojia", "guard_restored")


func _capture() -> void:
	if busy:
		return
	busy = true
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image.get_size() != Vector2i(WIDTH, HEIGHT) \
			or image.save_png(frames_dir.path_join("frame_%05d.png" % frame_index)) != OK:
		push_error("UI-06 capture frame failed")
		quit(2)
		return
	var units: Array[Dictionary] = []
	var current: Unit = manager.get("current_unit") as Unit
	for unit: Unit in manager.get("units"):
		if is_instance_valid(unit):
			units.append(_unit_state(unit, current))
	states.append({"frame": frame_index, "input_state": manager.get("input_state"), "units": units})
	frame_index += 1
	if frame_index >= total_frames:
		var report: Dictionary = {"case": capture_case, "fps": FPS, "frames": frame_index,
			"size": [WIDTH, HEIGHT], "flow_complete": flow_complete, "checks": checks,
			"fixture_resource_changes": fixture_changes, "events": events, "states": states,
			"camera_zoom": session.get("camera").zoom, "rendering": "real PortraitTokenBattle / Compatibility"}
		var file := FileAccess.open(output.path_join("action-cost-trace.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report) + "\n")
		manager.call("stop_battle")
		session.queue_free()
		await process_frame
		quit(0 if flow_complete else 3)
		return
	busy = false
