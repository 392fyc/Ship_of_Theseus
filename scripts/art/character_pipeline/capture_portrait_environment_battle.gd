extends "res://scripts/art/character_pipeline/capture_portrait_token_facing_align.gd"
## Same real battle capture, with a legal forest visit and return instead of repeated center attacks.

func _settled() -> void:
	while is_instance_valid(manager) and manager.get("input_state") == manager.InputState.ANIMATING:
		await create_timer(0.03).timeout
	await create_timer(0.15).timeout

func _move_input(actor: Unit, destination: Vector2i) -> void:
	_event("player_move_input", {"actor":actor.unit_id,"from":str(actor.grid_position),"to":str(destination)})
	manager.call("handle_pointer_click", _screen(destination))
	await _settled()
	if actor.grid_position != destination:
		push_error("Forest recording MOVE did not reach its legal destination: " + str(destination))
		quit(3)

func _attack_input(actor: Unit, target: Unit) -> void:
	# 剑士没有普通攻击（S2）：继承自 facing_align 录制脚本的 _begin_strike 会改用斩击。
	_begin_strike(manager, target.grid_position)
	if not target.grid_position in manager.get("_attack_cells"):
		push_error("Forest recording target is outside the real attack range")
		quit(3)
		return
	_event("player_attack_input", {"actor":actor.unit_id,"target":target.unit_id,"target_hp_before":target.stats.hp})
	manager.call("handle_pointer_hover", _screen(target.grid_position))
	_event("player_attack_hover_hold", {"actor":actor.unit_id,"target":target.unit_id})
	await create_timer(0.6).timeout
	manager.call("handle_pointer_click", _screen(target.grid_position))
	await _settled()

func _drive_player_ai() -> void:
	await create_timer(0.7).timeout
	var swordsman: Unit = manager.get("current_unit") as Unit
	var target: Unit = manager.get("grid").get_unit_at(Vector2i(4,4))
	await _move_input(swordsman, Vector2i(3,4))
	manager.call("handle_pointer_hover", _screen(target.grid_position))
	_event("ordinary_unit_hover", {"target":target.unit_id})
	await create_timer(0.6).timeout
	manager.call("handle_pointer_hover", _screen(Vector2i(0,3)))
	_event("ordinary_unit_hover_left", {})
	await create_timer(0.2).timeout
	await _attack_input(swordsman, target)
	manager.call("request_end_turn")
	await create_timer(0.1).timeout
	var kensei: Unit = manager.get("current_unit") as Unit
	if kensei == null or kensei.unit_id != "kensei":
		push_error("Expected the real kensei turn")
		quit(3)
		return
	await _move_input(kensei, Vector2i(0,6))
	_event("forest_standing", {"actor":kensei.unit_id,"grid":str(kensei.grid_position)})
	await create_timer(0.8).timeout
	manager.call("request_end_turn")
	while is_instance_valid(manager) and manager.get("current_unit") != swordsman:
		await create_timer(0.04).timeout
	await _settled()
	manager.call("request_end_move")
	await _attack_input(swordsman, target)
	manager.call("request_end_turn")
	await create_timer(0.1).timeout
	if manager.get("current_unit") != kensei:
		push_error("Expected the next real kensei turn")
		quit(3)
		return
	await _move_input(kensei, Vector2i(1,6))
	_event("forest_left", {"actor":kensei.unit_id,"grid":str(kensei.grid_position)})
	# Capture input only: leave the empty forest unobscured by hover UI.
	manager.call("handle_pointer_hover", _screen(Vector2i(2,2)))
	_event("forest_hover_cleared", {"hover_grid":"(2, 2)"})
	# End with a quiet, restored canopy and operable real action phase.

func _unit_state(unit: Unit, current: Unit) -> Dictionary:
	var result: Dictionary = super._unit_state(unit, current)
	if unit.unit_id == "myrmidon" and session.get("tree_presentation") != null:
		var selected: Array[Dictionary] = []
		for tree: Dictionary in session.get("tree_presentation").call("debug_snapshot"):
			if tree["cell"] == Vector2i(0,6) or not (tree["reveal_owners"] as Array).is_empty():
				selected.append(tree)
		result["tree_visibility"] = selected
		result["unit_hover_detail"] = session.call("get_unit_hover_detail_snapshot")
	return result
