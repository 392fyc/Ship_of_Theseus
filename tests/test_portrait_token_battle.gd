extends SceneTree
## Focused real-entry tests: animation timing/input lock and restart/stop safety.
var checks: int = 0
var failures: Array[String] = []
var session: Node

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, value: bool) -> void:
	checks += 1
	print("[", "PASS" if value else "FAIL", "] ", label)
	if not value:
		failures.append(label)

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func click(manager: Node, cell: Vector2i) -> void:
	manager.handle_pointer_click(root.get_canvas_transform() * manager.grid.grid_to_world(cell))

func _run() -> void:
	root.size = Vector2i(1280, 720)
	seed(20261027)
	session = load("res://scenes/tactical/character_pipeline/portrait_token_battle.tscn").instantiate()
	root.add_child(session)
	await wait(0.2)
	var manager: Node = session.manager
	var actor: Unit = manager.current_unit
	check("real TacticalScene contains four original static-token production Units", manager.units.size() == 4 and actor.has_character_animation())
	var expected_cells: Dictionary = {&"NE": Vector2i(0, 0), &"NW": Vector2i(1, 0), &"SW": Vector2i(0, 1), &"SE": Vector2i(1, 1)}
	for direction: StringName in expected_cells:
		actor.set_facing(direction)
		actor.character_animation.play("idle", direction)
		check("original static token direction " + str(direction), actor.character_animation.frame_coords == expected_cells[direction] and actor.character_animation.position == Vector2.ZERO)
	actor.set_facing(&"SE")
	var target: Unit = manager.grid.get_unit_at(Vector2i(4, 4))
	var before: int = target.stats.hp
	click(manager, Vector2i(3, 4))
	check("real move starts presentation movement state", actor.character_animation.action == "walk")
	await wait(0.35)
	check("real move updates Grid and returns idle", actor.grid_position == Vector2i(3, 4) and actor.character_animation.action == "idle")
	check("+grid-x faces screen SE using original static direction column", actor.get_facing() == &"SE" and actor.character_animation.frame_coords == Vector2i(1, 1))
	_begin_strike(manager)
	click(manager, target.grid_position)
	click(manager, target.grid_position)
	manager.request_end_turn()
	manager.request_cancel_action()
	await wait(0.15)
	check("windup keeps original HP and has not consumed standard action", target.stats.hp == before and not actor.standard_used)
	check("duplicate attack, cancel and End Turn cannot escape animation lock", manager.current_unit == actor and manager.input_state == manager.InputState.ANIMATING)
	await wait(0.35)
	check("impact applies real HP change and standard action", target.stats.hp < before and actor.standard_used)
	check("impact emits one real contact effect", actor.character_animation.action == "melee" and actor.character_animation.contact_count == 1)
	await wait(0.6)
	check("recovery returns idle and unlocks input", actor.character_animation.action == "idle" and manager.input_state != manager.InputState.ANIMATING)
	# Use the real restart route. No HP/resources are patched by the fixture.
	await session.select_layout("portrait_courtyard")
	await wait(0.1)
	manager = session.manager
	actor = manager.current_unit
	click(manager, Vector2i(3, 4))
	manager.stop_battle()
	await wait(0.1)
	check("stop cancels movement wait and pacing timer", actor._movement_tween == null and manager._enemy_pacing_timer == null)
	await session.select_layout("portrait_courtyard")
	await wait(0.1)
	manager = session.manager
	actor = manager.current_unit
	click(manager, Vector2i(3, 4))
	await wait(0.3)
	target = manager.grid.get_unit_at(Vector2i(4, 4))
	_begin_strike(manager)
	click(manager, target.grid_position)
	await wait(0.08)
	check("windup owns an active pacing timer before stop", manager._enemy_pacing_timer != null)
	manager.stop_battle()
	await wait(0.03)
	check("stop during windup cancels active pacing timer and resets token", manager._enemy_pacing_timer == null and actor.character_animation.action == "idle")
	await session.select_layout("portrait_courtyard")
	await wait(0.1)
	manager = session.manager
	actor = manager.current_unit
	click(manager, Vector2i(3, 4))
	await wait(0.3)
	target = manager.grid.get_unit_at(Vector2i(4, 4))
	_begin_strike(manager)
	click(manager, target.grid_position)
	await wait(0.08)
	var weak: WeakRef = weakref(manager)
	await session.select_layout("portrait_courtyard")
	await wait(0.2)
	check("restart during windup frees old manager without hanging", weak.get_ref() == null and session.manager.battle_active)
	session.queue_free()
	await wait(0.1)
	print("CHARACTER_BATTLE_RESULT=", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

## 剑士线没有普通攻击（gameplay-impl PR3，用户 2026-10-28 裁决 S2）。对没有普攻的单位改用其
## 技能栏第一格（剑士为斩击）：技能走同一条真实出手、动画锁与接触表现路径
## （_execute_presented_skill → begin_attack_visual），本测试要验的东西不变。
func _begin_strike(manager: Node) -> void:
	var actor: Unit = manager.current_unit
	if actor != null and not actor.has_basic_attack and not actor.skill_ids.is_empty():
		manager.request_skill_selection(actor.skill_ids[0])
	else:
		manager.request_attack_targeting()
