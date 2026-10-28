extends SceneTree
## Real TacticalScene coverage for projected facing, token footing, ring centers,
## stationary attack recovery, canceled movement, and an existing ground-target skill.
const ENTRY_SCENE: String = "res://scenes/tactical/character_pipeline/portrait_token_battle.tscn"
const DIRECTION_CASES: Array[Dictionary] = [
	{"name": "NE", "delta": Vector2i(0, -1)},
	{"name": "NW", "delta": Vector2i(-1, 0)},
	{"name": "SW", "delta": Vector2i(0, 1)},
	{"name": "SE", "delta": Vector2i(1, 0)},
]
const HERO_IDS: Array[String] = ["myrmidon", "kensei"]
const EXPECTED_FRAME_CELL_BY_HERO: Dictionary = {
	"myrmidon": {
		"NE": Vector2i(0, 0), "NW": Vector2i(1, 0),
		"SW": Vector2i(0, 1), "SE": Vector2i(1, 1),
	},
	"kensei": {
		"NE": Vector2i(0, 0), "NW": Vector2i(1, 0),
		"SW": Vector2i(2, 0), "SE": Vector2i(3, 0),
	},
}

var checks: int = 0
var failures: Array[String] = []
var output: String = ""
var impact_samples: Array[Dictionary] = []

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output = argument.trim_prefix("--out=")
	if not output.is_empty():
		if not output.is_absolute_path():
			push_error("Facing alignment evidence requires an absolute --out path")
			quit(2)
			return
		DirAccess.make_dir_recursive_absolute(output)
	_run.call_deferred()

func check(label: String, value: bool) -> void:
	checks += 1
	print("[", "PASS" if value else "FAIL", "] ", label)
	if not value:
		failures.append(label)

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _spawn(class_id: String, position: Vector2i) -> Dictionary:
	return {"class_id": class_id, "position": [position.x, position.y]}

func _replace_layout_units(session: Node, players: Array[Dictionary], enemies: Array[Dictionary]) -> void:
	var layout_id: String = str(session.get("layout_id"))
	var layouts: Dictionary = session.get("layouts")
	var layout: Dictionary = (layouts[layout_id] as Dictionary).duplicate(true)
	layout["player_units"] = players
	layout["enemy_units"] = enemies
	layouts[layout_id] = layout
	session.set("layouts", layouts)
	await session.call("select_layout", layout_id)
	await wait(0.05)

func _screen(cell: Vector2i, manager: Node) -> Vector2:
	return root.get_canvas_transform() * manager.get("grid").grid_to_world(cell)

func _unit_screen_center(unit: Unit, manager: Node) -> Vector2:
	return root.get_canvas_transform() * manager.get("grid").grid_to_world(unit.grid_position)

func _foot_screen(unit: Unit) -> Vector2:
	var view: Node = unit.character_animation
	return root.get_canvas_transform() * (view.call("foot_support_world_position") as Vector2)

func _ring_centers_screen(unit: Unit) -> Array[Vector2]:
	var centers: Array[Vector2] = []
	for child: Node in unit.get_children():
		if child.name != "PersistentFactionRing" or not child.is_visible_in_tree():
			continue
		var offset: Vector2 = child.get("center_offset")
		centers.append(root.get_canvas_transform() * child.to_global(offset))
	return centers

func _portrait_token_style_for(session: Node, hero_id: String) -> Dictionary:
	var visuals_value: Variant = session.get("_character_visuals")
	if not visuals_value is Dictionary:
		return {}
	var style_value: Variant = (visuals_value as Dictionary).get(hero_id, {})
	return style_value if style_value is Dictionary else {}

func _read_style_cell(style: Dictionary, direction: String) -> Vector2i:
	var cells_value: Variant = style.get("cell_by_direction", {})
	if not cells_value is Dictionary:
		return Vector2i(-1, -1)
	var cells: Dictionary = cells_value
	var cell_value: Variant = cells.get(direction, cells.get(StringName(direction), null))
	if cell_value is Vector2i:
		return cell_value
	if cell_value is Array and (cell_value as Array).size() == 2:
		return Vector2i(int((cell_value as Array)[0]), int((cell_value as Array)[1]))
	if cell_value is Dictionary:
		var point: Dictionary = cell_value
		return Vector2i(int(point.get("x", -1)), int(point.get("y", -1)))
	return Vector2i(-1, -1)

func _expected_frame_cell(hero_id: String, direction: String) -> Vector2i:
	var hero_value: Variant = EXPECTED_FRAME_CELL_BY_HERO.get(hero_id, {})
	if not hero_value is Dictionary:
		return Vector2i(-1, -1)
	var cell_value: Variant = (hero_value as Dictionary).get(direction, Vector2i(-1, -1))
	return cell_value if cell_value is Vector2i else Vector2i(-1, -1)

func _check_bound_hero_style(label: String, session: Node, actor: Unit,
		hero_id: String, direction: String) -> Vector2i:
	var style: Dictionary = _portrait_token_style_for(session, hero_id)
	var expected_cell: Vector2i = _expected_frame_cell(hero_id, direction)
	var style_cell: Vector2i = _read_style_cell(style, direction)
	check(label + " entry binds the hero-specific source style", not style.is_empty())
	check(label + " entry style maps " + direction + " to the expected source cell",
		style_cell == expected_cell)
	var expected_asset_path: String = str(style.get("texture_path", ""))
	var has_loaded_token: bool = actor.has_character_animation() \
		and actor.character_animation.texture != null
	check(label + " real actor loads the asset bound by the entry",
		has_loaded_token and not expected_asset_path.is_empty()
		and actor.character_animation.texture.resource_path == expected_asset_path)
	if has_loaded_token:
		var resolved_cells_value: Variant = actor.character_animation.get("_cell_by_direction")
		var resolved_cell: Vector2i = _read_resolved_cell(resolved_cells_value, direction)
		check(label + " real actor resolves the entry-bound frame cell", resolved_cell == style_cell)
	if hero_id == "myrmidon":
		var kensei_style: Dictionary = _portrait_token_style_for(session, "kensei")
		check(label + " sworder uses an asset distinct from the kensei original",
			not expected_asset_path.is_empty()
			and expected_asset_path != str(kensei_style.get("texture_path", "")))
	return expected_cell

func _read_resolved_cell(value: Variant, direction: String) -> Vector2i:
	if not value is Dictionary:
		return Vector2i(-1, -1)
	var cells: Dictionary = value
	var cell_value: Variant = cells.get(StringName(direction), cells.get(direction, null))
	return cell_value if cell_value is Vector2i else Vector2i(-1, -1)

func _capture_impact_sample(manager: Node, actor: Unit, target_cell: Vector2i,
		case_name: String, screenshot_name: String) -> void:
	var transform: Transform2D = root.get_canvas_transform()
	var target_center: Vector2 = transform * manager.get("grid").grid_to_world(target_cell)
	var actor_center: Vector2 = _unit_screen_center(actor, manager)
	var target_vector: Vector2 = transform.basis_xform(
		manager.get("grid").grid_to_world(target_cell) - manager.get("grid").grid_to_world(actor.grid_position))
	var foot_world: Vector2 = actor.character_animation.call("foot_support_world_position") as Vector2
	var foot_screen: Vector2 = transform * foot_world
	var rings: Array[Dictionary] = []
	for ring_center: Vector2 in _ring_centers_screen(actor):
		rings.append({"screen_center": [ring_center.x, ring_center.y],
		"grid_center_error_px": ring_center.distance_to(actor_center)})
	var frame: Vector2i = actor.character_animation.frame_coords
	var sample: Dictionary = {
		"direction_case": case_name,
		"unit_class_id": actor.unit_id,
		"screenshot": screenshot_name if DisplayServer.get_name() != "headless" else "",
		"target_cell": str(target_cell),
		"target_center_screen": [target_center.x, target_center.y],
		"target_projected_vector_screen": [target_vector.x, target_vector.y],
		"actor_grid_center_screen": [actor_center.x, actor_center.y],
		"facing": str(actor.get_facing()),
		"frame": [frame.x, frame.y],
		"texture_path": actor.character_animation.texture.resource_path,
		"frame_grid": [
			(actor.character_animation.get("_frame_grid") as Vector2i).x,
			(actor.character_animation.get("_frame_grid") as Vector2i).y,
		],
		"foot_world": [foot_world.x, foot_world.y],
		"foot_screen": [foot_screen.x, foot_screen.y],
		"foot_grid_center_error_px": foot_screen.distance_to(actor_center),
		"all_visible_ring_centers": rings,
	}
	if not output.is_empty() and DisplayServer.get_name() == "headless":
		check(actor.unit_id + " " + case_name + " screenshot requires a native display", false)
	if DisplayServer.get_name() != "headless" and not output.is_empty():
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		sample["screenshot_size"] = [image.get_width(), image.get_height()]
		check(actor.unit_id + " " + case_name + " screenshot keeps native 1280x720 size",
			image.get_size() == Vector2i(1280, 720))
		var error: Error = image.save_png(output.path_join(screenshot_name))
		sample["screenshot_saved"] = error == OK
		check(actor.unit_id + " " + case_name + " native screenshot is saved", error == OK)
	impact_samples.append(sample)

func _check_grounding(label: String, manager: Node) -> void:
	for unit: Unit in manager.get("units"):
		if not is_instance_valid(unit) or not unit.has_character_animation():
			continue
		var grid_center: Vector2 = _unit_screen_center(unit, manager)
		var foot: Vector2 = _foot_screen(unit)
		check(label + " " + unit.unit_id + " foot aligns with grid center", foot.distance_to(grid_center) <= 0.75)
		var ring_centers: Array[Vector2] = _ring_centers_screen(unit)
		check(label + " " + unit.unit_id + " has visible persistent ring", not ring_centers.is_empty())
		for ring_center: Vector2 in ring_centers:
			check(label + " " + unit.unit_id + " ring center aligns with grid center", ring_center.distance_to(grid_center) <= 0.75)

func _assert_attack_projection(label: String, manager: Node, actor: Unit, target: Unit,
		direction: StringName, expected_cell: Vector2i, anchor_before: Vector2) -> void:
	var projected: Vector2 = root.get_canvas_transform().basis_xform(
		manager.get("grid").grid_to_world(target.grid_position)
		- manager.get("grid").grid_to_world(actor.grid_position))
	check(label + " target has a nonzero screen projection", projected.length() > 1.0)
	check(label + " facing follows projected target vector", actor.get_facing() == direction)
	check(label + " uses expected character-specific source frame cell",
		actor.character_animation.frame_coords == expected_cell)
	check(label + " token stays anchored during melee", actor.character_animation.position == Vector2.ZERO)
	check(label + " Unit remains at its grid endpoint", actor.global_position == anchor_before)
	var foot_error: float = _foot_screen(actor).distance_to(_unit_screen_center(actor, manager))
	check(label + " foot support error is within subpixel tolerance", foot_error <= 0.75)
	for ring_center: Vector2 in _ring_centers_screen(actor):
		check(label + " actor ring center shares the grid anchor",
			ring_center.distance_to(_unit_screen_center(actor, manager)) <= 0.75)

func _run_direction_case(session: Node, case: Dictionary, hero_id: String) -> void:
	var origin: Vector2i = Vector2i(3, 3)
	var target_cell: Vector2i = origin + (case["delta"] as Vector2i)
	var players: Array[Dictionary] = [_spawn(hero_id, origin)]
	var enemies: Array[Dictionary] = [_spawn("test_lancer", target_cell)]
	await _replace_layout_units(session, players, enemies)
	var manager: Node = session.get("manager")
	var actor: Unit = manager.get("current_unit") as Unit
	var target: Unit = manager.get("grid").get_unit_at(target_cell) as Unit
	var direction: StringName = StringName(str(case["name"]))
	var label: String = hero_id + " real " + str(direction)
	check(label + " fixture begins on the live player's turn",
		actor != null and actor.faction == "player" and manager.get("input_state") == manager.InputState.MOVE_PHASE)
	if actor == null or target == null or actor.faction != "player":
		return
	check(label + " fixture selected the requested real class", actor.unit_id == hero_id)
	var expected_cell: Vector2i = _check_bound_hero_style(label, session, actor, hero_id, str(direction))
	var anchor_before: Vector2 = actor.global_position
	var contact_before: int = actor.character_animation.get("contact_count")
	manager.call("request_end_move")
	_begin_strike(manager)
	manager.call("handle_pointer_click", _screen(target_cell, manager))
	check(label + " real attack enters presentation lock", manager.get("input_state") == manager.InputState.ANIMATING)
	_assert_attack_projection(label + " windup", manager, actor, target, direction, expected_cell, anchor_before)
	await wait(0.48)
	check(label + " real impact emits one contact", actor.character_animation.get("contact_count") == contact_before + 1)
	var screenshot_name: String = "impact_%s_%s.png" % [hero_id, str(direction).to_lower()]
	await _capture_impact_sample(manager, actor, target_cell, str(direction), screenshot_name)
	_assert_attack_projection(label + " impact", manager, actor, target, direction, expected_cell, anchor_before)
	await wait(0.62)
	check(label + " action recovers to idle", actor.character_animation.get("action") == "idle")
	_assert_attack_projection(label + " recovery", manager, actor, target, direction, expected_cell, anchor_before)
	_check_grounding(label + " recovery", manager)

func _run_canceled_move_case(session: Node, hero_id: String) -> void:
	var origin: Vector2i = Vector2i(3, 3)
	var target_cell: Vector2i = Vector2i(4, 3)
	var players: Array[Dictionary] = [_spawn(hero_id, origin)]
	var enemies: Array[Dictionary] = [_spawn("test_lancer", target_cell)]
	await _replace_layout_units(session, players, enemies)
	var manager: Node = session.get("manager")
	var actor: Unit = manager.get("current_unit") as Unit
	var target: Unit = manager.get("grid").get_unit_at(target_cell) as Unit
	if actor == null or target == null or actor.faction != "player":
		check("canceled movement fixture reaches player turn", false)
		return
	check("canceled movement fixture selects " + hero_id, actor.unit_id == hero_id)
	var expected_se_cell: Vector2i = _check_bound_hero_style(
		"canceled " + hero_id, session, actor, hero_id, "SE")
	var original_position: Vector2 = actor.global_position
	var destination: Vector2i = Vector2i(-1, -1)
	for cell_value: Variant in manager.get("_move_range").keys():
		var candidate: Vector2i = cell_value as Vector2i
		if candidate != target_cell and manager.get("grid").get_unit_at(candidate) == null:
			destination = candidate
			break
	check("canceled movement fixture has a legal move", destination != Vector2i(-1, -1))
	if destination == Vector2i(-1, -1):
		return
	manager.call("handle_pointer_click", _screen(destination, manager))
	await wait(0.35)
	check("real move reaches a distinct grid endpoint", actor.grid_position == destination)
	manager.call("request_cancel_action")
	await wait(0.05)
	check("cancel restores prior grid cell and world endpoint",
		actor.grid_position == origin and actor.global_position == original_position)
	check("cancel restores token sprite origin", actor.character_animation.position == Vector2.ZERO)
	check("cancel restores foot support to origin grid center",
		_foot_screen(actor).distance_to(_unit_screen_center(actor, manager)) <= 0.75)
	for ring_center: Vector2 in _ring_centers_screen(actor):
		check("cancel restores ring center to origin grid center",
			ring_center.distance_to(_unit_screen_center(actor, manager)) <= 0.75)
	await _capture_impact_sample(manager, actor, origin, "canceled_move_restored",
		"canceled_move_restored_%s.png" % hero_id)
	manager.call("request_end_move")
	_begin_strike(manager)
	manager.call("handle_pointer_click", _screen(target_cell, manager))
	check("attack after canceled move is a real presentation", manager.get("input_state") == manager.InputState.ANIMATING)
	_assert_attack_projection("canceled " + hero_id + " windup", manager, actor, target,
		&"SE", expected_se_cell, original_position)
	await wait(1.12)
	check("attack after canceled move recovers at the original endpoint",
		manager.get("input_state") != manager.InputState.ANIMATING
		and actor.character_animation.get("action") == "idle"
		and actor.grid_position == origin and actor.global_position == original_position)
	_assert_attack_projection("canceled " + hero_id + " recovery", manager, actor, target,
		&"SE", expected_se_cell, original_position)

func _run_ground_skill_case(session: Node) -> void:
	var origin: Vector2i = Vector2i(3, 3)
	var target_cell: Vector2i = Vector2i(4, 4)
	var players: Array[Dictionary] = [_spawn("mage", origin)]
	var enemies: Array[Dictionary] = [
		_spawn("test_lancer", Vector2i(3, 4)),
		_spawn("test_lancer", Vector2i(5, 4)),
	]
	await _replace_layout_units(session, players, enemies)
	var manager: Node = session.get("manager")
	var actor: Unit = manager.get("current_unit") as Unit
	check("ground-target skill fixture begins on live mage turn",
		actor != null and actor.faction == "player" and manager.get("input_state") == manager.InputState.MOVE_PHASE)
	if actor == null or actor.faction != "player":
		return
	var target_a: Unit = manager.get("grid").get_unit_at(Vector2i(3, 4)) as Unit
	var target_b: Unit = manager.get("grid").get_unit_at(Vector2i(5, 4)) as Unit
	check("empty-cell AOE fixture has two legal enemy targets", target_a != null and target_b != null)
	if target_a == null or target_b == null:
		return
	var contact_before: int = actor.character_animation.get("contact_count")
	manager.call("request_end_move")
	manager.call("request_skill_selection", "mage_fireball")
	check("existing mage_fireball enters real cell targeting",
		manager.get("grid").get_unit_at(target_cell) == null
		and manager.get("input_state") == manager.InputState.SKILL_TARGETING
		and target_cell in manager.get("_attack_cells"))
	manager.call("handle_pointer_click", _screen(target_cell, manager))
	check("existing target-cell skill enters real presentation lock",
		manager.get("input_state") == manager.InputState.ANIMATING)
	var cast_facing: StringName = actor.get_facing()
	check("empty target cell binds cast direction and original-token frame",
		cast_facing in [&"SW", &"SE"]
		and actor.character_animation.frame_coords.x == (2 if cast_facing == &"SW" else 3)
		and actor.character_animation.frame_coords.y == 0)
	var target_a_vector: Vector2 = manager.get("grid").grid_to_world(target_a.grid_position) \
		- manager.get("grid").grid_to_world(actor.grid_position)
	var target_b_vector: Vector2 = manager.get("grid").grid_to_world(target_b.grid_position) \
		- manager.get("grid").grid_to_world(actor.grid_position)
	var target_a_facing: StringName = actor.character_animation.call("direction_for_screen_vector",
		root.get_canvas_transform().basis_xform(target_a_vector))
	var target_b_facing: StringName = actor.character_animation.call("direction_for_screen_vector",
		root.get_canvas_transform().basis_xform(target_b_vector))
	check("AOE occupants lie in different projected facings",
		target_a_facing != target_b_facing
		and (target_a_facing != cast_facing or target_b_facing != cast_facing))
	await wait(0.48)
	check("empty-cell AOE hits two real units", target_a.stats.hp < target_a.stats.max_hp and target_b.stats.hp < target_b.stats.max_hp)
	check("multi-target impact keeps the selected-cell facing",
		actor.character_animation.get("contact_count") == contact_before + 2
		and actor.get_facing() == cast_facing
		and actor.character_animation.frame_coords.x == (2 if cast_facing == &"SW" else 3))
	await _capture_impact_sample(manager, actor, target_cell, "mage_fireball_empty_cell", "impact_mage_fireball_empty_cell.png")
	await wait(0.62)
	check("cell skill recovers to idle with foot and ring on grid center",
		actor.character_animation.get("action") == "idle"
		and _foot_screen(actor).distance_to(_unit_screen_center(actor, manager)) <= 0.75)
	_check_grounding("mage skill recovery", manager)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	seed(20261027)
	var session: Node = load(ENTRY_SCENE).instantiate()
	root.add_child(session)
	await wait(0.2)
	var hero_styles: Dictionary = {}
	for hero_id: String in HERO_IDS:
		var hero_style: Dictionary = _portrait_token_style_for(session, hero_id)
		hero_styles[hero_id] = {
			"texture_path": str(hero_style.get("texture_path", "")),
			"frame_grid": hero_style.get("frame_grid", []),
			"cell_by_direction": hero_style.get("cell_by_direction", {}),
		}
	check("fixture source is the real portrait-token TacticalScene entry",
		session.get("manager") != null and session.get("manager").get("units").size() == 4)
	var initial_actor: Unit = session.manager.current_unit
	for sample: Dictionary in [
		{"delta": Vector2i(2, -1), "expected": &"SE"},
		{"delta": Vector2i(-1, -2), "expected": &"NE"},
		{"delta": Vector2i(-2, 1), "expected": &"NW"},
		{"delta": Vector2i(1, 2), "expected": &"SW"},
	]:
		check("non-adjacent projected target " + str(sample.delta), initial_actor._character_direction(initial_actor.grid_position + sample.delta) == sample.expected)
	initial_actor.set_facing(&"NW")
	check("zero target distance preserves existing facing", initial_actor._character_direction(initial_actor.grid_position) == &"NW")
	initial_actor.begin_attack_visual(initial_actor.grid_position + Vector2i(0, -1))
	initial_actor.set_facing(&"SW")
	check("unrelated facing refresh cannot override bound attack", initial_actor.get_facing() == &"NE")
	initial_actor.cancel_movement()
	for hero_id: String in HERO_IDS:
		for case: Dictionary in DIRECTION_CASES:
			await _run_direction_case(session, case, hero_id)
	for hero_id: String in HERO_IDS:
		await _run_canceled_move_case(session, hero_id)
	await _run_ground_skill_case(session)
	if session.get("manager") != null:
		session.get("manager").call("stop_battle")
	session.queue_free()
	await process_frame
	if not output.is_empty():
		var evidence_file: FileAccess = FileAccess.open(output.path_join("impact-coordinates.json"), FileAccess.WRITE)
		evidence_file.store_string(JSON.stringify({"source": ENTRY_SCENE,
			"viewport": [1280, 720], "bound_hero_styles": hero_styles,
			"impact_samples": impact_samples}, "\t") + "\n")
	print("PORTRAIT_TOKEN_FACING_ALIGN_RESULT=", JSON.stringify({"checks": checks, "failures": failures}))
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
