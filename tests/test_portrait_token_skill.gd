extends SceneTree
## One real existing skill through the same targeting/input path; no stat/resource patching.
var checks: int = 0
var failures: Array[String] = []
var damage_events: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, value: bool) -> void:
	checks += 1
	print("[", "PASS" if value else "FAIL", "] ", label)
	if not value:
		failures.append(label)

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _damage(_amount: int, _type: String) -> void:
	damage_events += 1

func _run() -> void:
	root.size = Vector2i(1280, 720)
	seed(20261027)
	var session: Node = load("res://scenes/tactical/character_pipeline/portrait_token_battle.tscn").instantiate()
	root.add_child(session)
	await wait(0.2)
	var manager: Node = session.manager
	var actor: Unit = manager.current_unit
	var target: Unit = manager.grid.get_unit_at(Vector2i(4, 4))
	manager.handle_pointer_click(root.get_canvas_transform() * manager.grid.grid_to_world(Vector2i(3, 4)))
	await wait(0.35)
	var hp_before: int = target.stats.hp
	var qi_before: int = actor.sword_qi
	target.damage_taken.connect(_damage)
	manager.request_skill_selection("kensei_zhanji")
	check("existing 斩击 enters real skill targeting", manager.input_state == manager.InputState.SKILL_TARGETING)
	var point: Vector2 = root.get_canvas_transform() * manager.grid.grid_to_world(target.grid_position)
	manager.handle_pointer_click(point)
	manager.request_skill_selection("kensei_zhanji")
	manager.handle_pointer_click(point)
	manager.request_end_turn()
	await wait(0.15)
	check("skill windup has real melee and leaves HP/resource untouched", actor.character_animation.action == "melee" and target.stats.hp == hp_before and not actor.standard_used)
	check("repeat skill input and End Turn stay locked", manager.current_unit == actor and manager.input_state == manager.InputState.ANIMATING)
	await wait(0.35)
	check("skill impact changes HP exactly once", damage_events == 1 and target.stats.hp < hp_before and actor.standard_used)
	var loader: Node = root.get_node("DataLoader")
	var skill: Dictionary = loader.skills["kensei_zhanji"]
	check("real skill gain occurs once", actor.sword_qi == qi_before + int(skill["qi_gain_on_hit"]))
	print("SKILL_STATE=", JSON.stringify({"hp_before": hp_before, "hp_after": target.stats.hp,
		"qi_before": qi_before, "qi_after": actor.sword_qi, "damage_events": damage_events,
		"standard_used": actor.standard_used, "animation_frame": actor.character_animation.frame_coords.x}))
	await wait(0.6)
	check("skill recovers idle and normal operations", actor.character_animation.action == "idle" and manager.input_state != manager.InputState.ANIMATING)
	manager.request_end_turn()
	await wait(0.05)
	check("next unit turn remains operable", manager.current_unit != actor and manager.battle_active)
	manager.stop_battle()
	session.queue_free()
	await process_frame
	print("CHARACTER_SKILL_RESULT=", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
