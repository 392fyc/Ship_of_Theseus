extends SceneTree

## RESOURCE-INTEGRATION-R1 T3 原生验收捕获。
## 正式截图只读取 TacticalScene 自身的 _bottom_dashboard；展示边界在正式场景释放后单独运行。

const RuntimeDashboard := preload("res://scripts/ui/hud/m2/runtime_dashboard.gd")
const LegacyDashboard := preload("res://scripts/ui/bottom_dashboard.gd")
const CAPTURE_FLAG := "--capture-hud-m2-resource-integration"
const POST_COMMIT_FLAG := "--post-commit"
const MAIN_SCENE_FALLBACK := "res://scenes/tactical/TacticalScene.tscn"
const SOURCE_CANDIDATE_PATH := "res://.omc/ui-m2/resource-integration-r1/source-candidate.json"
const EVIDENCE_ROOT := "res://dev_doc/ui-art-research/hud-m2-resource-integration/evidence"
const DEFAULT_THEME_PATH := "res://assets/ui/themes/hud_m2.tres"
const SOURCE_MANIFEST_PATH := "res://assets/ui/skins/hud_m2_resource_r1/source-manifest.json"
const SELECTED_OPTION := "A"
const MAX_STABLE_FRAMES := 90
const HOVER_POINTS := {
	"portrait": Vector2(48, 54), "identity": Vector2(150, 23),
	"level": Vector2(110, 45), "experience": Vector2(180, 45),
	"hp": Vector2(170, 72), "shield": Vector2(170, 86),
	"top_left_margin": Vector2(2, 2), "bottom_right_margin": Vector2(224, 106),
	"portrait_identity_gap": Vector2(87, 54)
}

var _passed: int = 0
var _failed: int = 0
var _captures: Array[Dictionary] = []
var _run_failures: Array[String] = []
var _candidate: Dictionary = {}
var _candidate_manifest_sha256: String = ""
var _head_at_start: String = ""
var _head_at_end: String = ""
var _post_commit: bool = false
var _output_res_path: String = ""
var _output_abs_path: String = ""
var _source_manifest: Dictionary = {}
var _scene_path: String = ""


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if not CAPTURE_FLAG in arguments:
		print("HUD_M2_RESOURCE_INTEGRATION_CAPTURE_SKIPPED_NO_FLAG")
		quit(0)
		return
	if DisplayServer.get_name() == "headless":
		push_error("HUD_M2_RESOURCE_INTEGRATION_CAPTURE_REQUIRES_NATIVE_DISPLAY")
		quit(2)
		return
	_post_commit = POST_COMMIT_FLAG in arguments
	_run.call_deferred()


func _run() -> void:
	print("=== capture_hud_m2_resource_integration ===")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	_output_res_path = EVIDENCE_ROOT.path_join("post-commit") if _post_commit else EVIDENCE_ROOT
	_output_abs_path = ProjectSettings.globalize_path(_output_res_path)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(_output_abs_path)
	if directory_error != OK:
		_fail_run("不能创建原生证据目录：%s" % error_string(directory_error))
		_finish()
		return
	if FileAccess.file_exists(_output_abs_path.path_join("native-capture.json")):
		push_error("目标 native-capture.json 已存在；为保护既有证据，本次未覆盖")
		quit(4)
		return
	_head_at_start = _read_git_head()
	_scene_path = str(ProjectSettings.get_setting("application/run/main_scene", MAIN_SCENE_FALLBACK))
	_source_manifest = _read_json_resource(SOURCE_MANIFEST_PATH)
	if not _load_and_validate_candidate():
		_finish()
		return
	await _capture_real_matrix()
	await _capture_boundary_matrix()
	_head_at_end = _read_git_head()
	if _head_at_end.is_empty():
		_fail_run("捕获结束时不能读取 git HEAD")
	if not _post_commit and _head_at_end != _head_at_start:
		_fail_run("捕获期间 HEAD 发生变化")
	_validate_candidate_files("capture_end")
	_finish()


func _load_and_validate_candidate() -> bool:
	var absolute_path: String = ProjectSettings.globalize_path(SOURCE_CANDIDATE_PATH)
	if not FileAccess.file_exists(absolute_path):
		_fail_run("缺少 Main 冻结的源码候选：.omc/ui-m2/resource-integration-r1/source-candidate.json")
		return false
	_candidate = _read_json_resource(SOURCE_CANDIDATE_PATH)
	if _candidate.is_empty():
		_fail_run("源码候选不是有效 JSON 对象")
		return false
	_candidate_manifest_sha256 = FileAccess.get_sha256(absolute_path)
	if not _candidate.has("candidate_sha256") or not _candidate.has("head") or not _candidate.has("files"):
		_fail_run("源码候选缺少 candidate_sha256、head 或 files")
		return false
	if not (_candidate["files"] is Array) or (_candidate["files"] as Array).is_empty():
		_fail_run("源码候选 files 必须是非空数组")
		return false
	var computed_candidate_sha256: String = _compute_candidate_sha256(_candidate)
	if computed_candidate_sha256 != str(_candidate.get("candidate_sha256", "")).to_lower():
		_fail_run("源码候选 candidate_sha256 与规范化清单内容不一致")
		return false
	if _post_commit:
		if _head_at_start.is_empty():
			_fail_run("post-commit 捕获不能实时读取 git HEAD")
	else:
		if str(_candidate.get("head", "")) != _head_at_start:
			_fail_run("源码候选 HEAD 与当前 HEAD 不一致")
	_validate_candidate_files("capture_start")
	return _run_failures.is_empty()


func _validate_candidate_files(stage: String) -> void:
	for item_value: Variant in _candidate.get("files", []):
		if not (item_value is Dictionary):
			_fail_run("%s：候选 files 存在非对象项" % stage)
			continue
		var item: Dictionary = item_value
		var relative_path: String = str(item.get("path", ""))
		var expected_sha256: String = str(item.get("sha256", "")).to_lower()
		if relative_path.is_empty() or expected_sha256.is_empty():
			_fail_run("%s：候选文件项缺少 path 或 sha256" % stage)
			continue
		var absolute_path: String = ProjectSettings.globalize_path("res://" + relative_path)
		if not FileAccess.file_exists(absolute_path):
			_fail_run("%s：候选文件不存在：%s" % [stage, relative_path])
			continue
		var actual_sha256: String = FileAccess.get_sha256(absolute_path).to_lower()
		if actual_sha256 != expected_sha256:
			_fail_run("%s：候选文件内容变化：%s" % [stage, relative_path])


func _capture_real_matrix() -> void:
	root.size = Vector2i(1280, 720)
	var packed: PackedScene = load(_scene_path) as PackedScene
	if packed == null:
		_fail_run("不能读取正式主场景：%s" % _scene_path)
		return
	var default_scene: Node = packed.instantiate()
	if default_scene == null:
		_fail_run("不能实例化正式主场景")
		return
	# 三张默认主图保持 application/run/main_scene 的原始配置，不设置任何注入字段。
	root.add_child(default_scene)
	await _settle()
	var default_dashboard: Control = default_scene.get("_bottom_dashboard") as Control
	if not _validate_formal_host(default_scene, default_dashboard):
		default_scene.queue_free()
		await process_frame
		return
	var default_manager: Object = default_scene.get("tactical_manager")
	var default_start_config: Dictionary = {
		"source": "application/run/main_scene", "run_injected": false,
		"configuration": "scene_defaults_unchanged",
	}
	_move_pointer(Vector2(640, 280))
	await process_frame
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		root.size = size
		await _settle()
		await _capture_case(default_scene, default_dashboard, {
			"case_id": "R-NORMAL-%dx%d" % [size.x, size.y],
			"file_name": "real-player-normal-%dx%d" % [size.x, size.y],
			"data_kind": "real_tactical_manager",
			"payload": default_manager.call("get_dashboard_data"),
			"startup_configuration": default_start_config,
			"actions": [{"event": "mouse_motion", "viewport_position": [640, 280], "purpose": "move_to_neutral_board"}],
			"expect": {"viewport_size": size, "mode": "player", "show_actions": true, "skills_min": 1},
		})
	default_scene.queue_free()
	await _settle()
	root.size = Vector2i(1280, 720)
	var scene: Node = packed.instantiate()
	if scene == null:
		_fail_run("不能实例化正式注入交互场景")
		return
	# 其余交互矩阵使用公开注入配置；单位仍由正式 spawn 路径创建。
	scene.set("run_injected", true)
	scene.set("debug_harness_enabled", false)
	scene.set("injected_map_id", "forest_01")
	scene.set("injected_player_units", [{"class_id": "kensei", "pos": Vector2i(1, 2), "level": 1}])
	scene.set("injected_enemy_units", [
		{"class_id": "goblin_melee", "pos": Vector2i(3, 2)},
		{"class_id": "kensei", "pos": Vector2i(4, 2), "level": 1},
	])
	root.add_child(scene)
	await _settle()
	var dashboard: Control = scene.get("_bottom_dashboard") as Control
	if not _validate_formal_host(scene, dashboard):
		scene.queue_free()
		await process_frame
		return
	var manager: Object = scene.get("tactical_manager")
	var start_config: Dictionary = {
		"source": "application/run/main_scene", "run_injected": true,
		"map_id": "forest_01", "player_classes": ["kensei"],
		"enemy_classes": ["goblin_melee", "kensei"],
		"enemy_kensei_reason": "有资源但无玩家操作的正式敌方检视证据",
	}
	var composition: Control = dashboard.call("get_composition") as Control
	var character: Control = composition.get_node("BottomRow/CharacterHudPanel") as Control
	var character_card: Control = character.call("get_inspection_panel") as Control
	var hover_actions: Array[Dictionary] = []
	for point_name: String in HOVER_POINTS:
		var screen_point: Vector2 = character.get_global_transform_with_canvas() * (HOVER_POINTS[point_name] as Vector2)
		_move_pointer(screen_point)
		await _settle()
		hover_actions.append({"event": "mouse_motion", "target": point_name, "viewport_position": _vec(screen_point), "card_visible": character_card.is_visible_in_tree()})
	await _capture_case(scene, dashboard, {
		"case_id": "R-CHARACTER-HOVER", "file_name": "real-character-full-hover-1280",
		"data_kind": "real_tactical_manager", "payload": manager.call("get_dashboard_data"),
		"startup_configuration": start_config, "actions": hover_actions,
		"expect": {"mode": "player", "character_card_visible": true, "character_attribute_count": 8, "resource_visible": true},
	})
	var bridge_actions: Array[Dictionary] = []
	var character_origin: Vector2 = character.get_global_transform_with_canvas() * Vector2.ZERO
	for logical_y: int in [600, 594, 580, 560, 542, 534, 528, 524, 510]:
		var point: Vector2 = Vector2(character_origin.x + 108.0, logical_y)
		_move_pointer(point)
		await _settle()
		bridge_actions.append({"event": "mouse_motion", "viewport_position": _vec(point), "card_visible": character_card.is_visible_in_tree()})
	_move_pointer(character_card.get_global_rect().get_center())
	await _settle()
	bridge_actions.append({"event": "mouse_motion", "target": "character_card", "viewport_position": _vec(character_card.get_global_rect().get_center()), "card_visible": character_card.is_visible_in_tree()})
	await _capture_case(scene, dashboard, {
		"case_id": "R-CHARACTER-CARD-BRIDGE", "file_name": "real-character-card-pointer-inside-1280",
		"data_kind": "real_tactical_manager", "payload": manager.call("get_dashboard_data"),
		"startup_configuration": start_config, "actions": bridge_actions,
		"expect": {"mode": "player", "character_card_visible": true, "resource_visible": true},
	})
	var state_before_character_card_click: Dictionary = manager.call("get_dashboard_data")
	var input_before_character_card_click: Variant = manager.get("input_state")
	await _click(character_card.get_global_rect().get_center())
	var character_card_click_safe: bool = manager.call("get_dashboard_data") == state_before_character_card_click and manager.get("input_state") == input_before_character_card_click
	_move_pointer(Vector2(900, 300))
	await _settle()
	var character_closed_after_leave: bool = not character_card.is_visible_in_tree()
	_move_pointer(character.get_global_rect().get_center())
	await _settle()
	await _click(character.get_global_rect().get_center())
	_move_pointer(Vector2(900, 300))
	await _settle()
	await _capture_case(scene, dashboard, {
		"case_id": "R-CHARACTER-CLICK-LEAVE", "file_name": "real-character-click-leave-1280",
		"data_kind": "real_tactical_manager", "payload": manager.call("get_dashboard_data"),
		"startup_configuration": start_config,
		"actions": [{"event": "left_click", "target": "character_card"}, {"event": "mouse_motion", "target": "neutral_board"}, {"event": "left_click", "target": "character_panel"}, {"event": "mouse_motion", "target": "neutral_board"}],
		"observations": {"first_leave_closed": character_closed_after_leave, "card_click_state_unchanged": character_card_click_safe, "character_panel_has_focus_after_click_and_leave": character.call("get_inspection_control").has_focus()},
		"expect": {"mode": "player", "character_card_visible": false, "resource_visible": true, "character_click_safe": character_card_click_safe and not character.call("get_inspection_control").has_focus()},
	})
	var longest_passive: Control = _find_longest_pure_passive(composition)
	if longest_passive == null:
		_fail_run("正式载荷中没有可观察的纯被动技能")
	else:
		_move_pointer(longest_passive.get_global_rect().get_center())
		await _settle()
		var passive_card: Control = longest_passive.call("get_inspection_panel") as Control
		await _capture_case(scene, dashboard, {
			"case_id": "R-LONGEST-PURE-PASSIVE", "file_name": "real-longest-pure-passive-1280",
			"data_kind": "real_tactical_manager", "payload": manager.call("get_dashboard_data"),
			"startup_configuration": start_config,
			"actions": [{"event": "mouse_motion", "target": "longest_real_pure_passive", "viewport_position": _vec(longest_passive.get_global_rect().get_center())}],
			"observations": {"skill_id": str(longest_passive.get("_view").skill_id), "inspection_text": longest_passive.call("get_inspection_text")},
			"expect": {"mode": "player", "passive_card_visible": true, "resource_visible": true},
		})
		var selected_before: String = str(manager.call("get_selected_skill_id"))
		_move_pointer(passive_card.get_global_rect().get_center())
		await _settle()
		await _click(passive_card.get_global_rect().get_center())
		var selected_after: String = str(manager.call("get_selected_skill_id"))
		await _capture_case(scene, dashboard, {
			"case_id": "R-PASSIVE-CARD-POINTER", "file_name": "real-passive-card-pointer-inside-1280",
			"data_kind": "real_tactical_manager", "payload": manager.call("get_dashboard_data"),
			"startup_configuration": start_config,
			"actions": [{"event": "mouse_motion", "target": "pure_passive_card"}, {"event": "left_click", "target": "pure_passive_card"}],
			"observations": {"selected_before": selected_before, "selected_after": selected_after},
			"expect": {"mode": "player", "passive_card_visible": true, "selection_unchanged": selected_before == selected_after, "resource_visible": true},
		})
		_move_pointer(Vector2(900, 300))
		root.gui_release_focus()
		await _settle()
	var all_units: Array = manager.get("units") as Array
	var enemies: Array = all_units.filter(func(unit: Object) -> bool: return str(unit.get("faction")) == "enemy")
	var goblin: Object = _find_unit(enemies, "goblin_melee")
	var enemy_kensei: Object = _find_unit(enemies, "kensei")
	if goblin == null or enemy_kensei == null:
		_fail_run("正式注入配置未生成 goblin_melee 与 kensei 敌人")
	else:
		await _click(_unit_screen(scene, goblin))
		await _capture_case(scene, dashboard, {
			"case_id": "R-ENEMY-NO-RESOURCE", "file_name": "real-enemy-no-resource-1280",
			"data_kind": "real_tactical_manager", "payload": manager.call("get_dashboard_data"),
			"startup_configuration": start_config,
			"actions": [{"event": "left_click", "target": "goblin_melee", "viewport_position": _vec(_unit_screen(scene, goblin))}],
			"expect": {"mode": "enemy", "show_actions": false, "resource_visible": false},
		})
		await _key(KEY_ESCAPE)
		await _click(_unit_screen(scene, enemy_kensei))
		await _capture_case(scene, dashboard, {
			"case_id": "R-ENEMY-RESOURCE-RESTRICTED", "file_name": "real-enemy-resource-no-actions-1280",
			"data_kind": "real_tactical_manager", "payload": manager.call("get_dashboard_data"),
			"startup_configuration": start_config,
			"actions": [{"event": "key", "key": "Escape", "purpose": "return_player"}, {"event": "left_click", "target": "enemy_kensei", "viewport_position": _vec(_unit_screen(scene, enemy_kensei))}],
			"expect": {"mode": "enemy", "show_actions": false, "resource_visible": true},
		})
		await _key(KEY_ESCAPE)
		await _capture_case(scene, dashboard, {
			"case_id": "R-RETURN-PLAYER", "file_name": "real-return-player-1280",
			"data_kind": "real_tactical_manager", "payload": manager.call("get_dashboard_data"),
			"startup_configuration": start_config, "actions": [{"event": "key", "key": "Escape", "purpose": "return_player"}],
			"expect": {"mode": "player", "resource_visible": true, "show_actions": true},
		})
	var resource_host: Control = composition.call("get_class_resource_host") as Control
	var state_before_resource_click: Dictionary = manager.call("get_dashboard_data")
	var input_state_before_resource_click: Variant = manager.get("input_state")
	await _click(resource_host.get_global_rect().get_center())
	var hovered_resource: Control = root.gui_get_hovered_control()
	var state_after_resource_click: Dictionary = manager.call("get_dashboard_data")
	await _capture_case(scene, dashboard, {
		"case_id": "R-RESOURCE-INPUT", "file_name": "real-resource-input-blocking-1280",
		"data_kind": "real_tactical_manager", "payload": state_after_resource_click,
		"startup_configuration": start_config,
		"actions": [{"event": "left_click", "target": "class_resource_host", "viewport_position": _vec(resource_host.get_global_rect().get_center()), "hovered_control": _control_identity(hovered_resource), "gui_handled_observation": "TacticalScene reports board pointer ignored at this position"}],
		"observations": {"input_state_before": str(input_state_before_resource_click), "input_state_after": str(manager.get("input_state")), "payload_unchanged": state_before_resource_click == state_after_resource_click, "board_pointer_ignored": bool(scene.call("_should_ignore_board_pointer"))},
		"expect": {"mode": "player", "resource_visible": true, "resource_click_safe": state_before_resource_click == state_after_resource_click and manager.get("input_state") == input_state_before_resource_click and bool(scene.call("_should_ignore_board_pointer"))},
	})
	_move_pointer(Vector2(640, 280))
	await _settle()
	var default_theme: Theme = composition.call("get_skin_theme") as Theme
	await _capture_case(scene, dashboard, {
		"case_id": "R-SKIN-DEFAULT", "file_name": "real-skin-default-1280",
		"data_kind": "real_tactical_manager", "payload": manager.call("get_dashboard_data"),
		"startup_configuration": start_config, "actions": [{"operation": "read_current_theme", "resource_path": default_theme.resource_path}],
		"expect": {"mode": "player", "resource_visible": true},
	})
	var alternate_theme: Theme = _make_alternate_theme(default_theme)
	composition.call("set_skin_theme", alternate_theme)
	await _settle()
	await _capture_case(scene, dashboard, {
		"case_id": "R-SKIN-ALTERNATE", "file_name": "real-skin-alternate-1280",
		"data_kind": "real_tactical_manager", "payload": manager.call("get_dashboard_data"),
		"startup_configuration": start_config, "actions": [{"operation": "set_skin_theme", "theme": alternate_theme.resource_name}],
		"expect": {"mode": "player", "resource_visible": true, "theme_identity": alternate_theme.resource_name},
	})
	composition.call("set_skin_theme", default_theme)
	await _settle()
	await _capture_case(scene, dashboard, {
		"case_id": "R-SKIN-RESTORED", "file_name": "real-skin-restored-1280",
		"data_kind": "real_tactical_manager", "payload": manager.call("get_dashboard_data"),
		"startup_configuration": start_config, "actions": [{"operation": "set_skin_theme", "theme": "default_theme_object"}],
		"expect": {"mode": "player", "resource_visible": true, "theme_identity": default_theme.resource_path},
	})
	var default_capture: Dictionary = _find_capture("R-SKIN-DEFAULT")
	var restored_capture: Dictionary = _find_capture("R-SKIN-RESTORED")
	if not default_capture.is_empty() and not restored_capture.is_empty():
		var default_crop_sha: String = str(default_capture.get("connection_crop", {}).get("sha256", ""))
		var restored_crop_sha: String = str(restored_capture.get("connection_crop", {}).get("sha256", ""))
		_append_post_capture_check(restored_capture, "恢复后静态HUD连接区域与默认主题像素一致", not default_crop_sha.is_empty() and default_crop_sha == restored_crop_sha, "%s vs %s" % [default_crop_sha, restored_crop_sha])
	scene.queue_free()
	await _settle()


func _capture_boundary_matrix() -> void:
	root.size = Vector2i(1280, 720)
	var dashboard: Control = RuntimeDashboard.new()
	root.add_child(dashboard)
	await _settle()
	var cases: Array[Dictionary] = []
	for item: Dictionary in [
		{"ids": ["B01"], "name": "boundary-kensei-qi-0-of-100", "state": _fixture_state("kensei", 0, 100), "expect": {"resource_visible": true, "qi_text": "0/100", "fill_width": 0.0}},
		{"ids": ["B02"], "name": "boundary-kensei-qi-1-of-100", "state": _fixture_state("kensei", 1, 100), "expect": {"resource_visible": true, "qi_text": "1/100", "fill_width": 2.1}},
		{"ids": ["B03"], "name": "boundary-kensei-qi-full", "state": _fixture_state("kensei", 100, 100), "expect": {"resource_visible": true, "qi_text": "100/100", "fill_width": 210.0}},
		{"ids": ["B04"], "name": "boundary-kensei-threshold-equal", "state": _fixture_state("kensei", 50, 100), "expect": {"resource_visible": true, "qi_text": "50/100", "fill_width": 105.0, "qi_band": "low"}},
		{"ids": ["B05"], "name": "boundary-kensei-threshold-above", "state": _fixture_state("kensei", 51, 100), "expect": {"resource_visible": true, "qi_text": "51/100", "fill_width": 107.1, "qi_band": "high"}},
		{"ids": ["B06"], "name": "boundary-kensei-dynamic-before", "state": _fixture_state("kensei", 65, 100), "expect": {"resource_visible": true, "qi_text": "65/100", "fill_width": 136.5, "qi_band": "high"}},
		{"ids": ["B07"], "name": "boundary-kensei-dynamic-max", "state": _fixture_state("kensei", 65, 130), "expect": {"resource_visible": true, "qi_text": "65/130", "fill_width": 105.0, "qi_band": "low"}},
		{"ids": ["B08"], "name": "boundary-kensei-dynamic-above", "state": _fixture_state("kensei", 66, 130), "expect": {"resource_visible": true, "qi_text": "66/130", "fill_width": 106.61538, "qi_band": "high"}},
		{"ids": ["B09"], "name": "boundary-myrmidon-qi-only", "state": _fixture_state("myrmidon", 65, 100, {"心": true, "道": true, "势": true}), "expect": {"resource_visible": true, "marks_visible": false, "qi_text": "65/100"}},
		{"ids": ["B10"], "name": "boundary-kensei-marks-0", "state": _fixture_state("kensei", 65, 100, {}), "expect": {"resource_visible": true, "marks": ["", "", ""]}},
		{"ids": ["B11"], "name": "boundary-kensei-marks-1", "state": _fixture_state("kensei", 65, 100, {"势": true}), "expect": {"resource_visible": true, "marks": ["势", "", ""]}},
		{"ids": ["B12"], "name": "boundary-kensei-marks-2", "state": _fixture_state("kensei", 65, 100, {"心": true, "势": true}), "expect": {"resource_visible": true, "marks": ["心", "势", ""]}},
		{"ids": ["B13"], "name": "boundary-kensei-marks-3", "state": _fixture_state("kensei", 65, 100, {"心": true, "道": true, "势": true}), "expect": {"resource_visible": true, "marks": ["心", "道", "势"]}},
		{"ids": ["B14"], "name": "boundary-no-resource", "state": _fixture_state("goblin_melee", -1, 0), "expect": {"resource_visible": false, "skills": 4}},
	]:
		cases.append(item)
	var zero_skills: Dictionary = _fixture_state("kensei", 65, 100)
	zero_skills["skills"] = []
	cases.append({"ids": ["B15"], "name": "boundary-skills-0", "state": zero_skills, "expect": {"resource_visible": true, "skills": 0}})
	var seven_skills: Dictionary = _fixture_state("kensei", 65, 100)
	seven_skills["skills"] = _fixture_skills(7)
	cases.append({"ids": ["B16"], "name": "boundary-skills-7", "state": seven_skills, "expect": {"resource_visible": true, "skills": 7, "first_pure_passive": true}})
	var capacity_three: Dictionary = _fixture_state("kensei", 65, 100)
	capacity_three["action_resources"] = {"movement_remaining": 0, "movement_available": false, "standard_capacity": 3, "standard_remaining": 1, "swift_capacity": 3, "swift_remaining": 0}
	cases.append({"ids": ["B17"], "name": "boundary-action-capacity-3", "state": capacity_three, "expect": {"resource_visible": true, "standard_pips": 3, "swift_pips": 3, "movement_available": false}})
	for combination: Dictionary in [
		{"ids": ["B18"], "name": "boundary-resources-actions", "resources": true, "actions": true, "frame_style": "panel_resources"},
		{"ids": ["B19"], "name": "boundary-resources-no-actions", "resources": true, "actions": false, "frame_style": "collapsed_resources"},
		{"ids": ["B20"], "name": "boundary-actions-no-resources", "resources": false, "actions": true, "frame_style": "panel"},
		{"ids": ["B21"], "name": "boundary-no-resources-no-actions", "resources": false, "actions": false, "frame_style": "collapsed"},
	]:
		var state: Dictionary = _fixture_state("kensei", 65, 100) if bool(combination["resources"]) else _fixture_state("goblin_melee", -1, 0)
		state["show_actions"] = bool(combination["actions"])
		combination["state"] = state
		combination["expect"] = {"resource_visible": bool(combination["resources"]), "show_actions": bool(combination["actions"]), "frame_style": combination["frame_style"]}
		cases.append(combination)
	for config: Dictionary in cases:
		var state: Dictionary = config["state"]
		dashboard.call("update_state", state)
		_move_pointer(Vector2(640, 280))
		await _settle()
		await _capture_case(dashboard, dashboard, {
			"case_id": "+".join(PackedStringArray(config["ids"])), "case_ids": config["ids"],
			"file_name": config["name"], "data_kind": "display_boundary_fixture",
			"payload": state, "fixture_override": _json_safe(state),
			"actions": [{"operation": "runtime_dashboard.update_state", "data_kind": "display_boundary_fixture"}],
			"expect": config["expect"],
		})
	dashboard.queue_free()
	await _settle()


func _capture_case(owner: Node, dashboard: Control, config: Dictionary) -> void:
	var case_id: String = str(config.get("case_id", "unnamed"))
	var file_name: String = str(config.get("file_name", case_id.to_lower()))
	var record: Dictionary = {
		"case_id": case_id,
		"case_ids": config.get("case_ids", [case_id]),
		"data_kind": config.get("data_kind", "unknown"),
		"result": "fail",
		"selected_option": SELECTED_OPTION,
		"scene_path": _scene_path if config.get("data_kind") == "real_tactical_manager" else "res://scripts/ui/hud/m2/runtime_dashboard.gd",
		"candidate_manifest_path": SOURCE_CANDIDATE_PATH.trim_prefix("res://"),
		"candidate_manifest_sha256": _candidate_manifest_sha256,
		"candidate_sha256": str(_candidate.get("candidate_sha256", "")),
		"candidate_head": str(_candidate.get("head", "")),
		"head_at_capture": _read_git_head(),
		"capture_script_sha256": FileAccess.get_sha256(ProjectSettings.globalize_path("res://tests/capture_hud_m2_resource_integration.gd")),
		"viewport": _viewport_record(dashboard),
		"host_identity": _host_identity(owner, dashboard),
		"startup_configuration": config.get("startup_configuration", {}),
		"actions": config.get("actions", []),
		"raw_payload": _json_safe(config.get("payload", {})),
		"raw_payload_sha256": _variant_sha256(config.get("payload", {})),
		"fixture_override": config.get("fixture_override", null),
		"observations": config.get("observations", {}),
		"preconditions": ["layout signature stable for two complete frames", "candidate files match frozen byte SHA256"],
		"assertions": [],
	}
	var stability: Dictionary = await _wait_for_stable_capture(dashboard, config.get("payload", {}))
	if not bool(stability.get("ready", false)):
		_record_case_check(record, "连续两帧布局稳定", false, str(stability.get("reason", "timeout")))
		record["stability"] = stability
		_captures.append(record)
		_failed += 1
		return
	var image: Image = stability["image"] as Image
	record["stability"] = {"complete_frames": 2, "frame_index": stability.get("frame_index", -1), "signature": stability.get("signature", "")}
	record["node_rects"] = _node_rects(dashboard, owner)
	_apply_case_assertions(record, dashboard, config.get("payload", {}), config.get("expect", {}), image)
	var output_abs: String = _output_abs_path.path_join(file_name + ".png")
	var save_error: Error = OK
	if FileAccess.file_exists(output_abs):
		save_error = ERR_ALREADY_EXISTS
	else:
		save_error = image.save_png(output_abs)
	_record_case_check(record, "完整 viewport PNG 保存成功且未覆盖既有证据", save_error == OK, error_string(save_error))
	if save_error == OK:
		record["png"] = {"path": _output_res_path.trim_prefix("res://").path_join(file_name + ".png"), "width": image.get_width(), "height": image.get_height(), "sha256": FileAccess.get_sha256(output_abs), "complete_frames": 2}
		var crop: Dictionary = _save_connection_crop(image, dashboard, file_name)
		if not crop.is_empty():
			record["connection_crop"] = crop
			_record_case_check(record, "连接局部来自同一原生Image且未覆盖既有证据", str(crop.get("result", "")) == "pass", str(crop.get("error", "pass")))
	var all_passed: bool = true
	for assertion_value: Variant in record["assertions"]:
		if not bool((assertion_value as Dictionary).get("passed", false)):
			all_passed = false
			break
	record["result"] = "pass" if all_passed else "fail"
	if all_passed:
		_passed += 1
	else:
		_failed += 1
	_captures.append(record)
	print("CAPTURE %s result=%s size=%dx%d" % [case_id, record["result"], image.get_width(), image.get_height()])


func _wait_for_stable_capture(dashboard: Control, payload: Variant) -> Dictionary:
	var previous_signature: String = ""
	var stable_frames: int = 0
	for frame_index: int in MAX_STABLE_FRAMES:
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var signature: String = _stable_signature(dashboard, payload, image)
		if not signature.is_empty() and signature == previous_signature:
			stable_frames += 1
		else:
			stable_frames = 1 if not signature.is_empty() else 0
		previous_signature = signature
		if stable_frames >= 2:
			return {"ready": true, "image": image, "frame_index": frame_index, "signature": signature}
	return {"ready": false, "reason": "连续两帧稳定超时", "last_signature": previous_signature}


func _stable_signature(dashboard: Control, payload: Variant, image: Image) -> String:
	if image == null or image.get_size() != root.size or dashboard == null or not is_instance_valid(dashboard):
		return ""
	var composition: Control = dashboard.call("get_composition") as Control
	if composition == null or not composition.is_node_ready():
		return ""
	var signature_data: Dictionary = {
		"image_size": _vec(image.get_size()),
		"dashboard_id": dashboard.get_instance_id(),
		"composition_id": composition.get_instance_id(),
		"payload": _json_safe(payload),
		"rects": _node_rects(dashboard),
	}
	return _variant_sha256(signature_data)


func _apply_case_assertions(record: Dictionary, dashboard: Control, payload: Dictionary, expect: Dictionary, image: Image) -> void:
	var composition: Control = dashboard.call("get_composition") as Control
	var host: Control = composition.call("get_class_resource_host") as Control
	var resource_renderer: Control = host.call("get_renderer") as Control if host.visible else null
	var skills: Array = composition.get_node("BottomRow/SkillShelf").call("get_skill_slots") as Array
	var action_strip: Control = composition.get_node("ActionResourceStrip") as Control
	_record_case_check(record, "PNG物理尺寸等于真实viewport", image.get_size() == root.size, "%s vs %s" % [image.get_size(), root.size])
	_record_case_check(record, "viewport原生图像含可见内容", image.get_used_rect().has_area(), str(image.get_used_rect()))
	_record_case_check(record, "M2五区数量为5", composition.get_node("BottomRow").get_child_count() == 5, "child_count=%d" % composition.get_node("BottomRow").get_child_count())
	if expect.has("viewport_size"):
		_record_case_check(record, "原生物理分辨率精确", image.get_size() == expect["viewport_size"], str(image.get_size()))
	if expect.has("mode"):
		_record_case_check(record, "显示模式符合前提", str(payload.get("mode", "")) == str(expect["mode"]), str(payload.get("mode", "")))
	if expect.has("show_actions"):
		_record_case_check(record, "行动显示符合前提", bool(payload.get("show_actions", false)) == bool(expect["show_actions"]) and action_strip.visible == bool(expect["show_actions"]), "payload=%s node=%s" % [payload.get("show_actions"), action_strip.visible])
	if expect.has("resource_visible"):
		_record_case_check(record, "职业资源宿主可见性符合前提", host.visible == bool(expect["resource_visible"]), str(host.visible))
	if expect.has("skills"):
		_record_case_check(record, "技能槽数量精确", skills.size() == int(expect["skills"]), str(skills.size()))
	if expect.has("skills_min"):
		_record_case_check(record, "正式技能槽非空", skills.size() >= int(expect["skills_min"]), str(skills.size()))
	if expect.has("character_card_visible"):
		var character_card: Control = composition.get_node("BottomRow/CharacterHudPanel").call("get_inspection_panel") as Control
		_record_case_check(record, "人物检视卡可见性符合前提", character_card.is_visible_in_tree() == bool(expect["character_card_visible"]), str(character_card.is_visible_in_tree()))
	if expect.has("character_attribute_count"):
		var card: Control = composition.get_node("BottomRow/CharacterHudPanel").call("get_inspection_panel") as Control
		_record_case_check(record, "人物检视卡包含八项属性", card.get_node("AttributeRows").get_child_count() == int(expect["character_attribute_count"]), str(card.get_node("AttributeRows").get_child_count()))
	if expect.has("passive_card_visible"):
		var visible_passive: bool = false
		for slot_value: Variant in skills:
			var slot: Control = slot_value as Control
			if slot.get("_view") != null and slot.get("_view").is_pure_passive() and slot.call("is_inspection_visible"):
				visible_passive = true
		_record_case_check(record, "纯被动说明卡可见性符合前提", visible_passive == bool(expect["passive_card_visible"]), str(visible_passive))
	if expect.has("selection_unchanged"):
		_record_case_check(record, "纯被动卡点击未改变正式选择", bool(expect["selection_unchanged"]), str(expect["selection_unchanged"]))
	if resource_renderer != null:
		if expect.has("qi_text"):
			_record_case_check(record, "剑气文本精确", resource_renderer.get_node("QiValue").text == str(expect["qi_text"]), resource_renderer.get_node("QiValue").text)
		if expect.has("fill_width"):
			_record_case_check(record, "剑气连续填充宽度精确", is_equal_approx(resource_renderer.get_node("QiFill").size.x, float(expect["fill_width"])), str(resource_renderer.get_node("QiFill").size.x))
		if expect.has("marks_visible"):
			_record_case_check(record, "印记区适用性由职业决定", bool(resource_renderer.get("_view").marks_visible) == bool(expect["marks_visible"]), str(resource_renderer.get("_view").marks_visible))
		if expect.has("marks"):
			var actual_marks: Array[String] = []
			for index: int in 3:
				actual_marks.append(str(resource_renderer.get_node("Mark%d" % index).text))
			_record_case_check(record, "普通印记按心道势压紧且空槽在右", actual_marks == expect["marks"], str(actual_marks))
	if expect.has("qi_band"):
		_record_case_check(record, "剑气阈值分档精确", str(payload.get("class_resource_display", {}).get("qi_band", "")) == str(expect["qi_band"]), str(payload.get("class_resource_display", {}).get("qi_band", "")))
	if expect.has("first_pure_passive"):
		var first_passive: bool = not skills.is_empty() and (skills[0] as Control).get("_view").is_pure_passive()
		_record_case_check(record, "七技能首项为带长说明纯被动", first_passive and str((skills[0] as Control).call("get_inspection_text")).contains("最长说明末行"), str(first_passive))
	if expect.has("standard_pips"):
		_record_case_check(record, "标准行动容量为3", (action_strip.call("get_standard_pips") as Array).size() == int(expect["standard_pips"]), str((action_strip.call("get_standard_pips") as Array).size()))
	if expect.has("swift_pips"):
		var swift_pips: Array = action_strip.call("get_swift_pips") as Array
		var equilateral: bool = swift_pips.size() == int(expect["swift_pips"])
		var swift_triangles: Array[Dictionary] = []
		for pip_value: Variant in swift_pips:
			var pip: Control = pip_value as Control
			var points: PackedVector2Array = pip.call("get_swift_points") as PackedVector2Array
			var sides: Array[float] = []
			var area: float = 0.0
			if points.size() == 3:
				sides = [points[0].distance_to(points[1]), points[1].distance_to(points[2]), points[2].distance_to(points[0])]
				area = absf((points[1] - points[0]).cross(points[2] - points[0])) * 0.5
				equilateral = equilateral and absf(sides[0] - sides[1]) <= 0.02 and absf(sides[1] - sides[2]) <= 0.02 and area > 0.01
			else:
				equilateral = false
			swift_triangles.append({"node_path": str(pip.get_path()), "points": _json_safe(points), "side_lengths": sides, "area": area})
		var observations: Dictionary = record.get("observations", {}) as Dictionary
		observations["swift_triangles"] = swift_triangles
		record["observations"] = observations
		_record_case_check(record, "迅捷行动容量为3且实际绘制三角三边相等、面积非零", equilateral, JSON.stringify(_json_safe(swift_triangles)))
	if expect.has("frame_style"):
		var shared: Control = composition.call("get_shared_frame") as Control
		var expected_style: StyleBox = composition.call("get_skin_theme").get_stylebox(StringName(str(expect["frame_style"])), &"HudM2SharedFrame")
		_record_case_check(record, "共享单外框状态精确", shared.call("get_frame_style") == expected_style, str(expect["frame_style"]))
	if expect.has("theme_identity"):
		var theme: Theme = composition.call("get_skin_theme") as Theme
		var identity_matches: bool = theme.resource_name == str(expect["theme_identity"]) or theme.resource_path == str(expect["theme_identity"])
		_record_case_check(record, "当前Theme身份符合捕获步骤", identity_matches, "%s|%s" % [theme.resource_name, theme.resource_path])
	if expect.has("resource_click_safe"):
		_record_case_check(record, "资源实体点击被正式输入边界接收且状态不变", bool(expect["resource_click_safe"]), str(expect["resource_click_safe"]))
	if expect.has("character_click_safe"):
		_record_case_check(record, "人物卡内点击未泄漏且人物栏点击未锁定检视", bool(expect["character_click_safe"]), str(expect["character_click_safe"]))
	_record_case_check(record, "遗物区保留8个实际槽位", composition.get_node("BottomRow/RelicGrid/VisualGrid").get_child_count() == 8, str(composition.get_node("BottomRow/RelicGrid/VisualGrid").get_child_count()))


func _record_case_check(record: Dictionary, label: String, passed: bool, observation: String) -> void:
	(record["assertions"] as Array).append({"label": label, "passed": passed, "observation": observation})


func _append_post_capture_check(record: Dictionary, label: String, passed: bool, observation: String) -> void:
	var was_passed: bool = str(record.get("result", "")) == "pass"
	_record_case_check(record, label, passed, observation)
	if was_passed and not passed:
		record["result"] = "fail"
		_passed -= 1
		_failed += 1


func _find_capture(case_id: String) -> Dictionary:
	for capture: Dictionary in _captures:
		if str(capture.get("case_id", "")) == case_id:
			return capture
	return {}


func _validate_formal_host(scene: Node, dashboard: Control) -> bool:
	var counts: Dictionary = {"m2": 0, "legacy": 0}
	_count_dashboards(scene, counts)
	var valid: bool = dashboard is RuntimeDashboard and dashboard.get_parent() == scene.get_node("UILayer") and int(counts["m2"]) == 1 and int(counts["legacy"]) == 0
	if not valid:
		_fail_run("正式场景没有唯一 M2 宿主，或仍存在旧 BottomDashboard：%s" % str(counts))
	return valid


func _count_dashboards(node: Node, counts: Dictionary) -> void:
	if node is RuntimeDashboard:
		counts["m2"] = int(counts["m2"]) + 1
	if node is LegacyDashboard:
		counts["legacy"] = int(counts["legacy"]) + 1
	for child: Node in node.get_children():
		_count_dashboards(child, counts)


func _host_identity(owner: Node, dashboard: Control) -> Dictionary:
	var counts: Dictionary = {"m2": 0, "legacy": 0}
	_count_dashboards(owner, counts)
	var composition: Control = dashboard.call("get_composition") as Control
	var host: Control = composition.call("get_class_resource_host") as Control
	return {
		"scene_instance_id": owner.get_instance_id(), "dashboard_instance_id": dashboard.get_instance_id(),
		"dashboard_node_path": str(dashboard.get_path()), "dashboard_script_path": str(dashboard.get_script().resource_path),
		"composition_instance_id": composition.get_instance_id(), "resource_host_instance_id": host.get_instance_id(),
		"m2_host_count": counts["m2"], "legacy_host_count": counts["legacy"],
	}


func _node_rects(dashboard: Control, owner: Node = null) -> Dictionary:
	var composition: Control = dashboard.call("get_composition") as Control
	var character: Control = composition.get_node("BottomRow/CharacterHudPanel") as Control
	var equipment: Control = composition.get_node("BottomRow/EquipmentHudPanel") as Control
	var skills: Control = composition.get_node("BottomRow/SkillShelf") as Control
	var relics: Control = composition.get_node("BottomRow/RelicGrid") as Control
	var end_turn: Control = composition.get_node("BottomRow/EndTurnControl") as Control
	var action: Control = composition.get_node("ActionResourceStrip") as Control
	var host: Control = composition.call("get_class_resource_host") as Control
	var character_card: Control = character.call("get_inspection_panel") as Control
	var visible_skill_cards: Array = []
	for slot_value: Variant in skills.call("get_skill_slots"):
		var slot: Control = slot_value as Control
		if slot.call("is_inspection_visible"):
			visible_skill_cards.append({"skill_id": str(slot.get("_view").skill_id), "rect": _rect(slot.call("get_inspection_panel").get_global_rect())})
	var result: Dictionary = {
		"viewport": _rect(root.get_visible_rect()), "composition": _rect(composition.get_global_rect()),
		"character": _rect(character.get_global_rect()), "equipment": _rect(equipment.get_global_rect()),
		"skills": _rect(skills.get_global_rect()), "relics": _rect(relics.get_global_rect()),
		"end_turn": _rect(end_turn.get_global_rect()), "action": _rect(action.get_global_rect()) if action.visible else null,
		"class_resource": _rect(host.get_global_rect()) if host.visible else null,
		"character_card": _rect(character_card.get_global_rect()) if character_card.is_visible_in_tree() else null,
		"skill_cards": visible_skill_cards,
		"input_blocking_rects": (dashboard.call("get_input_blocking_rects") as Array).map(func(value: Variant) -> Variant: return _rect(value as Rect2)),
	}
	if owner != null and owner != dashboard:
		var forecaster: Control = owner.get("_damage_forecaster") as Control
		if forecaster != null:
			result["damage_forecaster"] = _rect(Rect2(forecaster.position, forecaster.call("get_visual_size"))) if forecaster.is_visible_in_tree() else null
			result["damage_forecaster_instance_id"] = forecaster.get_instance_id()
	return result


func _viewport_record(dashboard: Control) -> Dictionary:
	var composition: Control = dashboard.call("get_composition") as Control
	var transform: Transform2D = composition.get_global_transform_with_canvas()
	return {
		"physical_size": _vec(root.get_texture().get_size()), "visible_rect": _rect(root.get_visible_rect()),
		"content_scale_mode": root.content_scale_mode, "content_scale_size": _vec(root.content_scale_size),
		"logical_canvas": [1280, 720], "composition_scale": _vec(composition.scale),
		"logical_to_viewport_transform": [transform.x.x, transform.x.y, transform.y.x, transform.y.y, transform.origin.x, transform.origin.y],
		"display_server": DisplayServer.get_name(),
	}


func _save_connection_crop(image: Image, dashboard: Control, file_name: String) -> Dictionary:
	var composition: Control = dashboard.call("get_composition") as Control
	var logical_crop := Rect2(Vector2(26, 534), Vector2(1228, 176))
	var transform: Transform2D = composition.get_global_transform_with_canvas()
	var top_left: Vector2 = transform * logical_crop.position
	var bottom_right: Vector2 = transform * logical_crop.end
	var crop_rect := Rect2i(Vector2i(floor(top_left.x), floor(top_left.y)), Vector2i(ceil(bottom_right.x - top_left.x), ceil(bottom_right.y - top_left.y)))
	crop_rect = crop_rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if not crop_rect.has_area():
		return {}
	var crop_image: Image = image.get_region(crop_rect)
	var crop_name: String = file_name + "-connections.png"
	var crop_abs: String = _output_abs_path.path_join(crop_name)
	var error: Error = ERR_ALREADY_EXISTS if FileAccess.file_exists(crop_abs) else crop_image.save_png(crop_abs)
	if error != OK:
		return {"result": "fail", "error": error_string(error), "crop_rect_physical": _recti(crop_rect)}
	return {
		"result": "pass", "path": _output_res_path.trim_prefix("res://").path_join(crop_name),
		"sha256": FileAccess.get_sha256(crop_abs), "parent_png_sha256": FileAccess.get_sha256(_output_abs_path.path_join(file_name + ".png")),
		"crop_rect_physical": _recti(crop_rect), "logical_source_rect": _rect(logical_crop),
		"coverage": {"resource_right_shoulder": true, "action_shoulders": true, "shared_separators_x": [262, 398, 882, 1168]},
	}


func _fixture_state(class_id: String, current: int, maximum: int, marks: Dictionary = {}) -> Dictionary:
	return {
		"visible": true, "mode": "player", "show_actions": true, "skills_visible": true,
		"unit_name": "展示边界夹具", "unit_label": "界", "level": 1,
		"hp": 7, "max_hp": 10, "skills": _fixture_skills(4),
		"action_resources": {"movement_remaining": 4, "movement_available": true, "standard_capacity": 1, "standard_remaining": 1, "swift_capacity": 1, "swift_remaining": 1},
		"buttons": {"end_turn_visible": true, "end_turn_disabled": false},
		"sword_qi": current, "sword_qi_max": maximum, "marks": marks.duplicate(true),
		"class_resource_display": {"class_id": class_id, "mark_capacity": 3, "qi_threshold_ratio": 0.5, "qi_band": &"low" if maximum <= 0 or current * 2 <= maximum else &"high"},
	}


func _fixture_skills(count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in count:
		result.append({
			"skill_id": "display_boundary_%d" % index,
			"name": "展示边界技能%d" % (index + 1),
			"description": "显示边界说明第一行\n第二行\n第三行\n第四行\n第五行\n第六行\n最长说明末行" if index == 0 else "显示边界说明",
			"is_passive": index == 0, "active_capable": index != 0,
			"available": true, "selected": false, "cooldown": 0,
			"action_cost": "swift" if index % 2 == 0 else "standard",
			"resource_cost_display": {"amount": index + 1, "resource_name": "显示边界资源"},
		})
	return result


func _find_longest_pure_passive(composition: Control) -> Control:
	var result: Control = null
	var longest: int = -1
	for slot_value: Variant in composition.get_node("BottomRow/SkillShelf").call("get_skill_slots"):
		var slot: Control = slot_value as Control
		var view: Variant = slot.get("_view")
		if view != null and view.is_pure_passive():
			var length: int = str(slot.call("get_inspection_text")).length()
			if length > longest:
				longest = length
				result = slot
	return result


func _find_unit(units: Array, unit_id: String) -> Object:
	for unit_value: Variant in units:
		var unit: Object = unit_value as Object
		if str(unit.get("unit_id")) == unit_id:
			return unit
	return null


func _unit_screen(scene: Node, unit: Object) -> Vector2:
	return scene.get_viewport().get_canvas_transform() * scene.get("tactical_manager").get("grid").call("grid_to_world", unit.get("grid_position"))


func _make_alternate_theme(source: Theme) -> Theme:
	var result: Theme = source.duplicate(true) as Theme
	result.resource_name = "T3 alternate cyan verification theme"
	for key: StringName in [&"text", &"muted", &"edge", &"spent_edge", &"end_disabled"]:
		result.set_color(key, &"HudM2", Color("#B5DDEA") if key != &"edge" else Color("#528CCF"))
	for item: StringName in result.get_stylebox_list(&"HudM2SharedFrame"):
		var original: StyleBox = result.get_stylebox(item, &"HudM2SharedFrame")
		var changed: StyleBox = original.duplicate(true) as StyleBox
		changed.set("material_texture", null)
		changed.set("background_color", Color("#102C39"))
		changed.set("border_color", Color("#74DFEC"))
		result.set_stylebox(item, &"HudM2SharedFrame", changed)
	return result


func _move_pointer(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	root.push_input(event, true)


func _click(position: Vector2) -> void:
	_move_pointer(position)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


func _key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


func _settle() -> void:
	await process_frame
	await process_frame


func _read_git_head() -> String:
	var output: Array = []
	var exit_code: int = OS.execute("git", PackedStringArray(["rev-parse", "HEAD"]), output, true)
	if exit_code != 0 or output.is_empty():
		return ""
	return str(output[0]).strip_edges()


func _read_json_resource(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _compute_candidate_sha256(source: Dictionary) -> String:
	var digest_payload: Dictionary = {
		"schema": source.get("schema", ""), "task_id": source.get("task_id", ""),
		"head": source.get("head", ""), "files": source.get("files", []),
		"selected_option": source.get("selected_option", ""),
	}
	return _variant_sha256(digest_payload)


func _variant_sha256(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(_json_safe(value), "", true).to_utf8_buffer())
	return context.finish().hex_encode()


func _json_safe(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array = value.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		for key: Variant in keys:
			result[str(key)] = _json_safe(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_json_safe(item))
		return result
	if value is Vector2 or value is Vector2i:
		return _vec(value)
	if value is Rect2:
		return _rect(value)
	if value is Rect2i:
		return _recti(value)
	if value is StringName:
		return str(value)
	if value is Object:
		return {"instance_id": value.get_instance_id(), "class": value.get_class()}
	return value


func _vec(value: Variant) -> Array:
	return [value.x, value.y]


func _rect(value: Rect2) -> Array:
	return [value.position.x, value.position.y, value.size.x, value.size.y]


func _recti(value: Rect2i) -> Array:
	return [value.position.x, value.position.y, value.size.x, value.size.y]


func _control_identity(control: Control) -> Variant:
	if control == null:
		return null
	return {"instance_id": control.get_instance_id(), "node_path": str(control.get_path()), "class": control.get_class()}


func _fail_run(message: String) -> void:
	_run_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _head_at_end.is_empty():
		_head_at_end = _read_git_head()
	var case_passed: int = 0
	var case_failed: int = 0
	for capture: Dictionary in _captures:
		if str(capture.get("result", "")) == "pass":
			case_passed += 1
		else:
			case_failed += 1
	var engine_arguments: Array = Array(OS.get_cmdline_args())
	var user_arguments: Array = Array(OS.get_cmdline_user_args())
	var result: Dictionary = {
		"task_id": "RESOURCE-INTEGRATION-R1-T3-native-capture",
		"status": "pass" if case_failed == 0 and _run_failures.is_empty() and case_passed > 0 else "fail",
		"case_count": _captures.size(), "passed": case_passed, "failed": case_failed,
		"run_failure_count": _run_failures.size(),
		"run_failures": _run_failures, "captures": _captures,
		"post_commit": _post_commit, "selected_option": SELECTED_OPTION,
		"engine_version": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"command_arguments": engine_arguments + ["--"] + user_arguments,
		"command_user_arguments": user_arguments,
		"scene_path": _scene_path, "data_kinds": ["real_tactical_manager", "display_boundary_fixture"],
		"head_at_start": _head_at_start, "head_at_end": _head_at_end,
		"candidate_manifest_path": SOURCE_CANDIDATE_PATH.trim_prefix("res://"),
		"candidate_manifest_sha256": _candidate_manifest_sha256,
		"candidate_sha256": str(_candidate.get("candidate_sha256", "")),
		"candidate_head": str(_candidate.get("head", "")),
		"capture_script_sha256": FileAccess.get_sha256(ProjectSettings.globalize_path("res://tests/capture_hud_m2_resource_integration.gd")),
		"selection_source": _json_safe(_source_manifest.get("approval", {})),
		"source_manifest_path": SOURCE_MANIFEST_PATH.trim_prefix("res://"),
		"source_manifest_sha256": FileAccess.get_sha256(ProjectSettings.globalize_path(SOURCE_MANIFEST_PATH)) if FileAccess.file_exists(ProjectSettings.globalize_path(SOURCE_MANIFEST_PATH)) else "",
		"limitations": ["重复印记、获取顺序、离形重复与纳刀印没有运行实体来源，不列为已支持能力", "正式缺失的头像、姓名、经验、护盾和药剂来源保持产品现有缺值表现"],
	}
	var receipt_path: String = _output_abs_path.path_join("native-capture.json")
	var file: FileAccess = FileAccess.open(receipt_path, FileAccess.WRITE)
	if file == null:
		push_error("不能写入 native-capture.json")
		quit(3)
		return
	file.store_string(JSON.stringify(_json_safe(result), "\t", false) + "\n")
	file.close()
	print("HUD_M2_RESOURCE_INTEGRATION_NATIVE_RESULT passed=%d failed=%d cases=%d run_failures=%d receipt=%s" % [case_passed, case_failed, _captures.size(), _run_failures.size(), _output_res_path.path_join("native-capture.json")])
	quit(0 if result["status"] == "pass" else 1)
