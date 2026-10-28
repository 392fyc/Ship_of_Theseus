extends SceneTree
## Reproduces real held-hover popup/card overlap; never moves unit cards to clear HUD.
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void:
	root.size = Vector2i(1280,720)
	_run.call_deferred()
func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("[PASS] " if ok else "[FAIL] ",label)
func _run() -> void:
	var session: Node = load("res://scenes/tactical/character_pipeline/portrait_token_battle.tscn").instantiate()
	root.add_child(session)
	for i: int in 8:
		await process_frame
	var manager: Node = session.get("manager")
	var grid: Grid = manager.get("grid")
	manager.call("handle_pointer_click",root.get_canvas_transform()*grid.grid_to_world(Vector2i(3,4)))
	var elapsed: float = 0.0
	while manager.get("input_state") == manager.InputState.ANIMATING and elapsed < 8:
		await create_timer(0.03).timeout
		elapsed += 0.03
	for i: int in 8:
		await process_frame
	var overhead: Node = session.get("battle").get("_unit_overhead_layout")
	var before: Dictionary = {}
	for row: Dictionary in overhead.call("get_debug_snapshot")["units"]:
		before[row["instance_id"]] = row["group_rect"]
	_begin_strike(manager)
	manager.call("handle_pointer_hover",root.get_canvas_transform()*grid.grid_to_world(Vector2i(4,4)))
	var immediate: Dictionary = session.call("get_forecast_placement_snapshot")
	_check(not immediate.is_empty() and bool(immediate.get("placement_clear", false)),"first synchronous hover is already placed before any draw")
	_check(not session.get("battle").get("_damage_forecaster").get("target_pointer_visible"),"displaced popup hides its misleading decorative pointer")
	var stable: bool = true
	var clear: bool = true
	var visible: bool = true
	var same_size: bool = true
	for i: int in 60:
		await process_frame
		# Parent entry runs after the real TacticalScene HUD pass.
		var placement: Dictionary = session.call("get_forecast_placement_snapshot")
		if placement.is_empty():
			clear = false
			continue
		var rect: Rect2 = placement["actual_rect"]
		clear = clear and bool(placement["placement_clear"])
		clear = clear and (placement["bounds"] as Rect2).encloses(rect)
		for obstacle: Rect2 in placement["obstacles"]:
			clear = clear and not rect.intersects(obstacle)
		visible = visible and bool(session.get("battle").get("_damage_forecaster").visible)
		same_size = same_size and rect.size == Vector2(180,111)
		for row: Dictionary in overhead.call("get_debug_snapshot")["units"]:
			stable = stable and row["group_rect"] == before[row["instance_id"]]
	_check(clear,"60 real held-hover frames keep popup clear of cards, bodies and reserved HUD")
	_check(stable,"stationary owned group rectangles do not reflow for popup")
	_check(visible and same_size,"original forecast remains visible with its 180x111 visual size")
	_check(grid.get_unit_at(Vector2i(4,4)).stats.hp == 26,"hover never settles damage")
	manager.call("request_cancel_action")
	for i: int in 4:
		await process_frame
	_check(not session.get("battle").get("_damage_forecaster").visible,"cancel hides popup normally")
	manager.call("stop_battle")
	session.queue_free()
	await process_frame
	print("FORECAST_LAYOUT_RESULT=",JSON.stringify({"checks":checks,"failures":failures}))
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
