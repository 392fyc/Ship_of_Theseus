extends "res://tests/claude_review/capture_terrain_readability_r7.gd"
## R9 保留 R7 静态采集，并在同一进程另存凹槽像素与四状态遮挡读回。

const R9_ENTRY_SCRIPT := "res://tests/claude_review/capture_terrain_readability_r9.gd"
const R9_SOURCE_PATHS: PackedStringArray = [
	R9_ENTRY_SCRIPT,
	"res://tests/claude_review/validate_terrain_pillar_r9.py",
	"res://tests/claude_review/test_terrain_pillar_r9.py",
	"res://dev_doc/ui-art-research/terrain-readability/pillar-r9-task.md",
]
const R9_CAPTURE_SCRIPT_CHAIN: PackedStringArray = [
	R9_ENTRY_SCRIPT,
	"res://tests/claude_review/capture_terrain_readability_r7.gd",
	"res://tests/claude_review/capture_terrain_readability_r6.gd",
	"res://tests/claude_review/capture_terrain_readability_v6_atlas.gd",
	"res://tests/claude_review/capture_terrain_readability_v6_regions_semantic_sidecar.gd",
	"res://tests/claude_review/capture_terrain_readability_v6_regions.gd",
	"res://tests/claude_review/capture_terrain_readability_v6.gd",
	"res://tests/claude_review/capture_terrain_readability.gd",
]
const R9_O1_SCHEMA := "terrain-pillar-occlusion/1"
const R9_UNIT_CELL := Vector2i(0, 3)
const R9_ATTACKER_CELL := Vector2i(0, 2)
const R9_PILLAR_ID := "pillar@1.00,4.00"
const DamagePopupScript: GDScript = preload("res://scripts/ui/damage_popup.gd")

var _r9_defer_close := false
var _r9_o1_extra_viewports: Array[SubViewport] = []
var _r9_o1_extra_sessions: Array[Node2D] = []


func _capture_case(map_size: int, resolution: Vector2i, source_map: Dictionary,
		profile: Dictionary) -> bool:
	_r9_defer_close = true
	var captured: bool = await super._capture_case(map_size, resolution, source_map, profile)
	if not captured:
		_r9_defer_close = false
		_close_sessions_and_passes()
		return false
	var o1: Dictionary = await _capture_r9_o1(resolution)
	var o1_path := _active_case_directory.path_join("r9-o1.json")
	if not _write_json(o1_path, o1):
		_abort("R9 O1 readback record could not be written")
	_r9_defer_close = false
	_close_sessions_and_passes()
	return not _failed


func _close_sessions_and_passes() -> void:
	if _r9_defer_close:
		return
	for viewport: SubViewport in _r9_o1_extra_viewports:
		if is_instance_valid(viewport):
			viewport.queue_free()
	_r9_o1_extra_viewports.clear()
	_r9_o1_extra_sessions.clear()
	super._close_sessions_and_passes()


func _semantic_draw_leaf_input(canvas: CanvasItem, relative_path: String) -> Dictionary:
	var record: Dictionary = super._semantic_draw_leaf_input(canvas, relative_path)
	if canvas is Line2D and str(canvas.name).begins_with("R9Groove"):
		if canvas.has_meta("r9_groove_index") and canvas.has_meta("r9_groove_u"):
			record["r9_groove_index"] = int(canvas.get_meta("r9_groove_index"))
			record["r9_groove_u"] = float(canvas.get_meta("r9_groove_u"))
		else:
			_abort("R9 groove Line2D is missing its source-authored index/u metadata")
	return record


func _build_manifest_skeleton(map_data: Dictionary, resolution: Vector2i,
		case_name: String) -> Dictionary:
	var manifest: Dictionary = super._build_manifest_skeleton(map_data, resolution, case_name)
	var config: Dictionary = manifest.get("capture_config", {}).duplicate(true)
	config["capture_entry_script"] = R9_ENTRY_SCRIPT
	config["capture_script_inheritance"] = R9_CAPTURE_SCRIPT_CHAIN.duplicate()
	config["r9_supplemental_capture"] = "separate pixel samples and O1 four-state group; not appended to frozen image list"
	manifest["capture_config"] = config
	return manifest


func _path_hashes(paths: PackedStringArray) -> Dictionary:
	var extended: PackedStringArray = paths.duplicate()
	for path: String in R9_SOURCE_PATHS:
		if path not in extended:
			extended.append(path)
	return super._path_hashes(extended)


func _candidate_record() -> Dictionary:
	var candidate: Dictionary = super._candidate_record()
	var hashes: Dictionary = candidate.get("source_sha256", {}).duplicate(true)
	for path: String in R9_SOURCE_PATHS:
		var relative: String = path.trim_prefix("res://")
		var absolute: String = ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(absolute):
			_abort("R9 source file is missing: " + relative)
			continue
		hashes[relative] = FileAccess.get_sha256(absolute)
	candidate["capture_entry_script"] = R9_ENTRY_SCRIPT
	candidate["capture_script_inheritance"] = R9_CAPTURE_SCRIPT_CHAIN.duplicate()
	candidate["source_sha256"] = hashes
	candidate["candidate_digest_sha256"] = _sha256_text(JSON.stringify(hashes))
	return candidate


func _capture_r9_o1(resolution: Vector2i) -> Dictionary:
	var manifest_path: String = _active_case_directory.path_join("capture-manifest.json")
	var sidecar_path: String = _active_case_directory.path_join(SEMANTIC_SIDECAR_MANIFEST)
	var capture: Dictionary = _read_json_dictionary(manifest_path)
	var sidecar_sha: String = FileAccess.get_sha256(sidecar_path) if FileAccess.file_exists(sidecar_path) else ""
	var manifest_sha: String = FileAccess.get_sha256(manifest_path) if FileAccess.file_exists(manifest_path) else ""
	var candidate: Dictionary = capture.get("candidate", {})
	var record := {
		"schema_version": R9_O1_SCHEMA,
		"capture_manifest_sha256": manifest_sha,
		"semantic_sidecar_sha256": sidecar_sha,
		"candidate_digest_sha256": str(candidate.get("candidate_digest_sha256", "")),
		"callback": "RenderingServer.frame_post_draw",
		"same_frame": false,
		"frame_id": -1,
		"image_size": [resolution.x, resolution.y],
		"window_size": [root.size.x, root.size.y],
		"pillar_stable_id": R9_PILLAR_ID,
		"unit_cell": [R9_UNIT_CELL.x, R9_UNIT_CELL.y],
		"hover_cell": [R9_UNIT_CELL.x, R9_UNIT_CELL.y],
		"attacker_cell": [R9_ATTACKER_CELL.x, R9_ATTACKER_CELL.y],
		"forecast_path": "TacticalManager._select_unit -> request_end_move -> request_attack_targeting -> handle_pointer_hover -> _update_hover/_recalculate_hover_artifacts -> TacticalScene._update_damage_forecaster",
		"pillar_alpha_input": "actual pillar CanvasItem.modulate.a after TerrainBattleSession._update_board_visibility_context and CourtyardBoardView._process",
		"body_rect": [],
		"overlays": {},
		"states": {},
		"setup_status": "NOT_TESTED",
		"setup_reason": "O1 setup has not completed",
	}
	if manifest_sha.is_empty() or sidecar_sha.is_empty() or candidate.is_empty():
		record["setup_reason"] = "static capture manifest or semantic sidecar is missing"
		return record
	if resolution != Vector2i(1280, 720):
		record["setup_reason"] = "O1 visual capture requires the formal native 1280x720 case"
		return record
	if not is_instance_valid(_main_session) or not is_instance_valid(_reconstruction_session) \
			or not is_instance_valid(_main_manager) or not is_instance_valid(_main_board):
		record["setup_reason"] = "frozen R7 formal source sessions are unavailable after static readback"
		return record
	var map_data: Dictionary = (_main_session.get("_configured_map") as Dictionary).duplicate(true)
	var clone_c: Dictionary = await _r9_make_o1_session("r9_o1_C", map_data, resolution)
	var clone_d: Dictionary = await _r9_make_o1_session("r9_o1_D", map_data, resolution)
	if not bool(clone_c.get("ok", false)) or not bool(clone_d.get("ok", false)):
		record["setup_reason"] = "formal C/D comparison sessions could not be configured: %s; %s" % [
			str(clone_c.get("reason", "")), str(clone_d.get("reason", ""))]
		return record
	var sessions: Dictionary = {
		"A": {"session": _main_session, "manager": _main_manager,
			"board": _main_board, "battle": _main_battle, "viewport": root,
			"pillar_visible": true, "unit_visible": true},
		"B": {"session": _reconstruction_session,
			"manager": _reconstruction_session.get("manager") as Node,
			"board": _reconstruction_session.get("board_view") as Node2D,
			"battle": _reconstruction_session.get("battle") as Node2D,
			"viewport": _reconstruction_viewport, "pillar_visible": false, "unit_visible": true},
		"C": {"session": clone_c["session"], "manager": clone_c["manager"],
			"board": clone_c["board"], "viewport": clone_c["viewport"],
			"pillar_visible": true, "unit_visible": false},
		"D": {"session": clone_d["session"], "manager": clone_d["manager"],
			"board": clone_d["board"], "viewport": clone_d["viewport"],
			"pillar_visible": false, "unit_visible": false},
	}
	for role: String in ["A", "B", "C", "D"]:
		var state: Dictionary = sessions[role]
		if not await _r9_prepare_o1_state(role, state):
			record["setup_reason"] = "formal O1 state %s could not place the actual target/attacker or activate the official forecast path" % role
			return record
	var transforms: Dictionary = {}
	for role: String in ["A", "B", "C", "D"]:
		var viewport: Viewport = sessions[role]["viewport"] as Viewport
		transforms[role] = {
			"canvas": _transform_array(viewport.get_canvas_transform()),
			"final": _transform_array(viewport.get_final_transform()),
		}
	var reference: Dictionary = transforms["A"]
	for role: String in ["B", "C", "D"]:
		if not _numeric_arrays_equal(transforms[role]["canvas"], reference["canvas"], 0.001) \
				or not _numeric_arrays_equal(transforms[role]["final"], reference["final"], 0.001):
			record["setup_reason"] = "O1 formal viewports do not share main canvas/final transforms: %s=%s, A=%s" % [role, transforms[role], reference]
			return record
	var a_units := _r9_units_for_state(sessions["A"])
	if not bool(a_units.get("ok", false)):
		record["setup_reason"] = str(a_units.get("reason", "actual Unit source missing"))
		return record
	var states: Dictionary = {}
	var image_by_role: Dictionary = {}
	await RenderingServer.frame_post_draw
	# 这次 post-draw 回调内连续读状态和四个 viewport，中间不 await。
	# alpha、真实矩形和像素因此属于同一帧；同步计数围住完整读回。
	var draw_before: int = Engine.get_frames_drawn()
	var process_before: int = Engine.get_process_frames()
	var frame_id: int = draw_before
	var body_rect: Array = []
	var overlays: Dictionary = {}
	var alpha_by_role: Dictionary = {}
	for role: String in ["A", "B", "C", "D"]:
		var state: Dictionary = sessions[role]
		var viewport: Viewport = state["viewport"] as Viewport
		var state_units := _r9_units_for_state(state)
		if not bool(state_units.get("ok", false)):
			record["setup_reason"] = str(state_units.get("reason", "actual source Units missing after draw"))
			return record
		var unit: Unit = state_units["target"] as Unit
		var manager: Node = state["manager"] as Node
		var grid: Object = manager.get("grid") as Object
		var pillar: Node2D = state.get("pillar_node") as Node2D
		if not is_instance_valid(pillar):
			record["setup_reason"] = "O1 %s actual pillar draw node is missing after setup" % role
			return record
		var actual_body_rect: Array = _r9_rect_pixels(viewport, unit.get_overhead_body_rect_screen())
		var actual_hover: Vector2i = manager.get("_hover_cell")
		var has_hover: bool = bool(manager.get("_has_hover_cell"))
		var actual_unit_cell: Vector2i = unit.grid_position
		var image: Image = viewport.get_texture().get_image()
		if image == null or image.is_empty() or image.get_size() != resolution:
			record["setup_reason"] = "O1 %s viewport produced an empty or incorrectly sized image" % role
			return record
		image.convert(Image.FORMAT_RGBA8)
		var image_name: String = "r9-o1-%s.png" % role
		var image_path: String = _active_case_directory.path_join(image_name)
		if image.save_png(image_path) != OK:
			record["setup_reason"] = "O1 %s PNG could not be saved" % role
			return record
		var raw: PackedByteArray = FileAccess.get_file_as_bytes(image_path)
		var viewport_record: Dictionary = _viewport_record(viewport, image)
		var state_record := {
			"role": role,
			"window_id": DisplayServer.MAIN_WINDOW_ID,
			"window_name": "MAIN_WINDOW_ID",
			"window_size": [root.size.x, root.size.y],
			"viewport_name": str(viewport.name),
			"viewport_instance_id": viewport.get_instance_id(),
			"image_size": [image.get_width(), image.get_height()],
			"callback": "RenderingServer.frame_post_draw",
			"frame_id": frame_id,
			"frames_drawn_before": draw_before,
			"frames_drawn_after": -1,
			"process_frames_before": process_before,
			"process_frames_after": -1,
			"same_frame": true,
			"pillar_visible": bool(state["pillar_visible"]),
			"unit_visible": bool(state["unit_visible"]),
			"requested_unit_cell": [R9_UNIT_CELL.x, R9_UNIT_CELL.y],
			"requested_hover_cell": [R9_UNIT_CELL.x, R9_UNIT_CELL.y],
			"unit_cell": [actual_unit_cell.x, actual_unit_cell.y],
			"hover_cell": [actual_hover.x, actual_hover.y],
			"has_hover_cell": has_hover,
			"target_unit_id": unit.unit_id,
			"body_rect": actual_body_rect,
			"pillar_alpha": pillar.modulate.a,
			"viewport": viewport_record,
			"image": {"path": image_name, "sha256": _sha256_bytes(raw), "bytes": raw.size(),
				"image_size": [image.get_width(), image.get_height()], "mime_type": "image/png"},
		}
		states[role] = state_record
		image_by_role[role] = image
		alpha_by_role[role] = pillar.modulate.a
		if role == "A":
			body_rect = actual_body_rect
			overlays = _r9_overlay_records(state["battle"] as Node2D, unit, viewport, manager)
	var draw_after: int = Engine.get_frames_drawn()
	var process_after: int = Engine.get_process_frames()
	var same_frame: bool = draw_before == frame_id and frame_id == draw_after \
		and process_before == process_after
	for role: String in states:
		var state_record: Dictionary = states[role]
		state_record["frames_drawn_after"] = draw_after
		state_record["process_frames_after"] = process_after
		state_record["same_frame"] = same_frame
		states[role] = state_record
	record["frame_id"] = frame_id
	record["frames_drawn_before"] = draw_before
	record["frames_drawn_after"] = draw_after
	record["process_frames_before"] = process_before
	record["process_frames_after"] = process_after
	record["same_frame"] = same_frame
	record["states"] = states
	record["body_rect"] = body_rect
	record["body_rect_source"] = "actual target Unit.get_overhead_body_rect_screen transformed by root final_transform into native main-image pixels"
	record["overlays"] = overlays
	record["pillar_alpha"] = alpha_by_role.get("A", -1.0)
	record["pillar_alpha_by_state"] = alpha_by_role
	record["pillar_canvas_layer"] = _r9_canvas_layer(_r9_find_pillar(_main_board, _main_manager.get("grid") as Object))
	record["pillar_canvas_layer_source"] = "actual nearest CanvasLayer ancestor; world draw order is layer 0"
	record["setup_status"] = "PASS" if same_frame and image_by_role.size() == 4 else "NOT_TESTED"
	record["setup_reason"] = "" if same_frame else "O1 four-state image readback crossed a draw/process frame boundary"
	return record


func _r9_make_o1_session(role: String, map_data: Dictionary,
		resolution: Vector2i) -> Dictionary:
	var viewport := _new_viewport(role, resolution, false)
	root.add_child(viewport)
	_r9_o1_extra_viewports.append(viewport)
	var configured: Dictionary = _configure_session(map_data)
	if not bool(configured.get("ok", false)):
		return {"ok": false, "reason": str(configured.get("reason", "configure_map failed"))}
	var session := configured["session"] as Node2D
	_r9_o1_extra_sessions.append(session)
	await _wait_for_session(session, viewport)
	if _failed:
		return {"ok": false, "reason": "formal session failed while loading"}
	await _frames(2)
	var manager := session.get("manager") as Node
	var board := session.get("board_view") as Node2D
	var battle := session.get("battle") as Node2D
	if manager == null or board == null or battle == null:
		return {"ok": false, "reason": "formal session lacks manager, board, or TacticalScene"}
	return {"ok": true, "session": session, "manager": manager,
		"board": board, "battle": battle, "viewport": viewport}


func _r9_prepare_o1_state(role: String, state: Dictionary) -> bool:
	var session: Node2D = state.get("session") as Node2D
	var manager: Node = state.get("manager") as Node
	var board: Node2D = state.get("board") as Node2D
	var battle: Node2D = state.get("battle") as Node2D if state.has("battle") else session.get("battle") as Node2D
	if not is_instance_valid(session) or not is_instance_valid(manager) or not is_instance_valid(board) or not is_instance_valid(battle):
		return false
	var grid: Object = manager.get("grid") as Object
	if grid == null or not bool(grid.call("is_valid", R9_UNIT_CELL)) \
			or not bool(grid.call("is_valid", R9_ATTACKER_CELL)):
		return false
	var pillar: Node2D = _r9_find_pillar(board, grid)
	if not is_instance_valid(pillar):
		return false
	state["pillar_node"] = pillar
	var unit_rows: Dictionary = _r9_place_o1_units(manager, grid)
	if not bool(unit_rows.get("ok", false)):
		return false
	var target: Unit = unit_rows["target"] as Unit
	var attacker: Unit = unit_rows["attacker"] as Unit
	if bool(state.get("pillar_visible", true)):
		pillar.show()
	else:
		pillar.hide()
		var props: Array = board.get("_props") as Array
		for index: int in range(props.size() - 1, -1, -1):
			var spec: Variant = props[index]
			if spec is Dictionary and (spec as Dictionary).get("node") == pillar:
				props.remove_at(index)
		board.set("_props", props)
	if bool(state.get("unit_visible", true)):
		target.show()
	else:
		target.hide()
	manager.call("_select_unit", attacker)
	manager.call("request_end_move")
	manager.call("request_attack_targeting")
	var viewport: Viewport = state["viewport"] as Viewport
	var hover_world: Vector2 = grid.call("grid_to_world", R9_UNIT_CELL)
	var hover_screen: Vector2 = viewport.get_canvas_transform() * hover_world
	manager.call("handle_pointer_hover", hover_screen)
	if battle.has_method("_update_damage_forecaster"):
		battle.call("_update_damage_forecaster")
	if session.has_method("_update_board_visibility_context"):
		session.call("_update_board_visibility_context", R9_UNIT_CELL)
	board.call("_process", 0.25)
	var layout: Variant = battle.get("_unit_overhead_layout")
	if is_instance_valid(layout) and layout.has_method("sync_units"):
		layout.call("sync_units", manager.get("units"))
		layout.call("refresh_layout")
	if not bool(state.get("unit_visible", true)):
		target.hide()
	var forecast: Dictionary = manager.get("_combat_forecast") as Dictionary
	# --script 在 autoload 注册前编译；从运行中的 manager 读取枚举，避免提前解析全局类。
	var manager_script: Script = manager.get_script() as Script
	if manager_script == null:
		push_error("[R9 O1] formal manager has no script for InputState lookup")
		return false
	var input_states: Dictionary = manager_script.get_script_constant_map().get("InputState", {}) as Dictionary
	if not input_states.has("ATTACK_TARGETING"):
		push_error("[R9 O1] formal manager script has no InputState.ATTACK_TARGETING")
		return false
	var attack_state: bool = manager.get("input_state") == input_states["ATTACK_TARGETING"]
	var targets_value: Variant = forecast.get("targets", [])
	var has_forecast_targets: bool = targets_value is Array and not (targets_value as Array).is_empty()
	return target.grid_position == R9_UNIT_CELL and attacker.grid_position == R9_ATTACKER_CELL \
		and bool(manager.get("_has_hover_cell")) \
		and manager.get("_hover_cell") == R9_UNIT_CELL \
		and attack_state and bool(forecast.get("visible", false)) \
		and has_forecast_targets


func _r9_place_o1_units(manager: Node, grid: Object) -> Dictionary:
	var units: Array = manager.get("units") as Array
	var players: Array[Unit] = []
	var enemies: Array[Unit] = []
	for value: Variant in units:
		if value is Unit and is_instance_valid(value):
			var unit := value as Unit
			if unit.faction == "player":
				players.append(unit)
			else:
				enemies.append(unit)
	if players.is_empty() or enemies.is_empty():
		return {"ok": false, "reason": "formal map has no player/enemy pair"}
	enemies.sort_custom(func(a: Unit, b: Unit) -> bool: return a.unit_id < b.unit_id)
	var active_value: Variant = manager.get("current_unit")
	if not active_value is Unit or (active_value as Unit).faction != "player":
		return {"ok": false, "reason": "formal TacticalManager has no active player Unit for its official attack path"}
	var attacker: Unit = active_value as Unit
	if attacker not in players:
		return {"ok": false, "reason": "formal active player Unit is not present in the source unit inventory"}
	var target: Unit = enemies[0]
	var original_positions: Dictionary = {}
	for value: Variant in units:
		if value is Unit and is_instance_valid(value):
			var unit := value as Unit
			original_positions[unit.get_instance_id()] = unit.grid_position
			grid.call("remove_unit", unit)
	var used: Dictionary = {}
	used["%d,%d" % [R9_ATTACKER_CELL.x, R9_ATTACKER_CELL.y]] = attacker
	used["%d,%d" % [R9_UNIT_CELL.x, R9_UNIT_CELL.y]] = target
	for value: Variant in units:
		if not value is Unit or not is_instance_valid(value):
			continue
		var unit := value as Unit
		if unit == attacker or unit == target:
			continue
		var original: Vector2i = original_positions[unit.get_instance_id()]
		var key: String = "%d,%d" % [original.x, original.y]
		if grid.call("is_valid", original) and not used.has(key):
			used[key] = unit
		else:
			var replacement: Vector2i = _r9_first_free_cell(grid, used)
			if replacement.x < 0:
				return {"ok": false, "reason": "no free formal grid cell for remaining source units"}
			key = "%d,%d" % [replacement.x, replacement.y]
			used[key] = unit
	var placements: Array[Dictionary] = []
	placements.append({"unit": attacker, "cell": R9_ATTACKER_CELL})
	placements.append({"unit": target, "cell": R9_UNIT_CELL})
	for value: Variant in units:
		if not value is Unit or not is_instance_valid(value):
			continue
		var unit := value as Unit
		if unit == attacker or unit == target:
			continue
		var assigned: Vector2i = original_positions[unit.get_instance_id()]
		if not grid.call("is_valid", assigned) \
				or assigned == R9_ATTACKER_CELL or assigned == R9_UNIT_CELL:
			assigned = _r9_assigned_cell(used, unit)
		placements.append({"unit": unit, "cell": assigned})
	for placement: Dictionary in placements:
		var unit: Unit = placement["unit"] as Unit
		var cell: Vector2i = placement["cell"]
		grid.call("place_unit", unit, cell)
		unit.position = grid.call("grid_to_world", cell)
	return {"ok": true, "attacker": attacker, "target": target}


func _r9_first_free_cell(grid: Object, used: Dictionary) -> Vector2i:
	for y: int in range(int(grid.get("height")) - 1, -1, -1):
		for x: int in range(int(grid.get("width")) - 1, -1, -1):
			var key: String = "%d,%d" % [x, y]
			if not used.has(key):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _r9_assigned_cell(used: Dictionary, unit: Unit) -> Vector2i:
	for key_value: Variant in used.keys():
		if used[key_value] == unit:
			var parts := str(key_value).split(",")
			return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i(-1, -1)


func _r9_find_pillar(board: Node2D, grid: Object) -> Node2D:
	var props: Array = board.get("_props") as Array
	for value: Variant in props:
		if not value is Dictionary:
			continue
		var spec: Dictionary = value
		var node := spec.get("node") as Node2D
		if not is_instance_valid(node) or not node.visible:
			continue
		if _classify_prop(node) != "pillar":
			continue
		var logical: Vector2 = _r9_logical_position(grid, node.global_position)
		if logical.distance_to(Vector2(1.0, 4.0)) <= 0.02:
			return node
	return null


func _r9_logical_position(grid: Object, world: Vector2) -> Vector2:
	var origin: Vector2 = grid.call("grid_to_world", Vector2i.ZERO)
	var delta: Vector2 = world - origin
	return Vector2(snappedf((delta.x / 32.0 + delta.y / 16.0) * 0.5, 0.01),
		snappedf((delta.y / 16.0 - delta.x / 32.0) * 0.5, 0.01))


func _r9_units_for_state(state: Dictionary) -> Dictionary:
	var manager: Node = state.get("manager") as Node
	if not is_instance_valid(manager):
		return {"ok": false, "reason": "formal TacticalManager missing"}
	var units: Array = manager.get("units") as Array
	var target: Unit = null
	var attacker: Unit = null
	for value: Variant in units:
		if not value is Unit or not is_instance_valid(value):
			continue
		var unit := value as Unit
		if unit.grid_position == R9_UNIT_CELL and unit.faction != "player":
			target = unit
		elif unit.grid_position == R9_ATTACKER_CELL and unit.faction == "player":
			attacker = unit
	return {"ok": is_instance_valid(target) and is_instance_valid(attacker),
		"target": target, "attacker": attacker,
		"reason": "actual target/player Units at approved O1 coordinates are missing"}


func _r9_overlay_records(battle: Node2D, target: Unit, viewport: Viewport,
		manager: Node) -> Dictionary:
	if not is_instance_valid(battle) or not is_instance_valid(target) or not is_instance_valid(manager):
		return {}
	var id: int = target.get_instance_id()
	var name_node: Node = battle.find_child("Name_%d" % id, true, false)
	var hp_node: Node = battle.find_child("HP_%d" % id, true, false)
	var forecast_node: Node = battle.find_child("Forecast_%d" % id, true, false)
	var damage_control: Variant = battle.get("_damage_forecaster")
	var name_record: Dictionary = _r9_control_record(name_node, viewport)
	var hp_record: Dictionary = _r9_control_record(hp_node, viewport)
	var overhead_forecast: Dictionary = _r9_control_record(forecast_node, viewport)
	var damage_record: Dictionary = _r9_control_record(damage_control as Node, viewport)
	var official_forecast: Dictionary = manager.get("_combat_forecast") as Dictionary
	if is_instance_valid(damage_control) and damage_control.has_method("get_value_line_text"):
		damage_record["text"] = str(damage_control.call("get_value_line_text"))
		damage_record["forecast_control"] = "TacticalScene._damage_forecaster"
		var forecast_text: String = str(overhead_forecast.get("text", ""))
		var expected_overhead_text: String = ""
		if not official_forecast.is_empty():
			var expected_value: Dictionary = DamagePopupScript.compose(
				int(official_forecast.get("damage", 0)),
				str(official_forecast.get("damage_type", "physical")), false)
			expected_overhead_text = str(expected_value.get("text", ""))
		damage_record["unit_overhead_forecast_text"] = forecast_text
		damage_record["expected_unit_overhead_forecast_text"] = expected_overhead_text
		damage_record["official_forecast"] = official_forecast.duplicate(true)
		damage_record["has_matching_official_value"] = not damage_record["text"].is_empty() \
			and not expected_overhead_text.is_empty() and forecast_text == expected_overhead_text
	return {"name": name_record, "hp": hp_record, "forecast": damage_record,
		"unit_overhead_forecast": overhead_forecast}


func _r9_control_record(node: Node, viewport: Viewport) -> Dictionary:
	if not is_instance_valid(node) or not node is Control:
		return {"visible": false, "text_complete": false,
			"reason": "actual production Control node is missing"}
	var control := node as Control
	var rect: Rect2 = control.get_global_rect()
	var layer: int = 0
	var cursor: Node = control
	while cursor != null:
		if cursor is CanvasLayer:
			layer = (cursor as CanvasLayer).layer
			break
		cursor = cursor.get_parent()
	var text: String = str(control.text) if control is Label else ""
	if control.has_method("get_value_line_text"):
		text = str(control.call("get_value_line_text"))
	var text_complete: bool = false
	if control is Label:
		var label := control as Label
		text_complete = label.get_line_count() > 0 \
			and label.get_visible_line_count() >= label.get_line_count() \
			and control.size.x + 0.5 >= control.get_combined_minimum_size().x
	elif control.has_method("get_value_line_text"):
		var text_width: float = ThemeDB.fallback_font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		text_complete = control.size.x >= 44.0 + text_width
	return {"node_path": str(control.get_path()), "node_class": control.get_class(),
		"text": text, "visible": control.is_visible_in_tree(),
		"rect": _r9_rect_pixels(viewport, rect), "canvas_layer": layer,
		"text_complete": text_complete, "control_size": [control.size.x, control.size.y],
		"canvas_layer_source": "actual CanvasLayer ancestor; world fallback layer 0"}


func _r9_rect_pixels(viewport: Viewport, rect: Rect2) -> Array:
	var transform: Transform2D = viewport.get_final_transform()
	var points: Array[Vector2] = [transform * rect.position,
		transform * Vector2(rect.end.x, rect.position.y),
		transform * rect.end, transform * Vector2(rect.position.x, rect.end.y)]
	var minimum: Vector2 = points[0]
	var maximum: Vector2 = points[0]
	for point: Vector2 in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	return [minimum.x, minimum.y, maximum.x - minimum.x, maximum.y - minimum.y]


func _r9_canvas_layer(item: CanvasItem) -> int:
	if not is_instance_valid(item):
		return -2147483648
	var cursor: Node = item
	while cursor != null:
		if cursor is CanvasLayer:
			return (cursor as CanvasLayer).layer
		cursor = cursor.get_parent()
	return 0


func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()
