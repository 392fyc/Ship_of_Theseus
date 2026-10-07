extends "res://tests/claude_review/capture_cr10_windows_weights.gd"
## CR-06 同帧遮挡采集。复用冻结的 courtyard→TacticalScene 相邻敌人夹具与字体设置。
## 不移动系统鼠标；所有悬停输入都通过 root.push_input。窗口由 runner 放到屏幕外并设为 no_focus。
## 原图案例：每档采集相邻单位预测隐藏、预测显示、镜头平移/缩放后重新显示，共 9 张原生整屏。
## Windows 原图入口：pwsh -NoProfile -File tests/claude_review/run_cr06_windows_overhead.ps1
##   -GodotPath <Godot 4.6.3 console executable> -ExpectedCommit <full SHA> -OutputDirectory <new external batch directory>。
## headless API 检查：Godot --headless --path . --script res://tests/claude_review/capture_cr06_overhead.gd -- --headless-check --weight=Medium。

const CR06_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const MEDIUM_FONT_PATH := "res://assets/fonts/noto_sans_cjk_sc/NotoSansCJKsc-Medium-subset.otf"
const BOLD_FONT_PATH := "res://assets/fonts/noto_sans_cjk_sc/NotoSansCJKsc-Bold-subset.otf"
const TITLE_FONT_PATH := "res://assets/ui/themes/hud_m2_title_font.tres"
const OVERHEAD_NODE_PATH := "UILayer/UnitOverheadLayout"
const CAPTURE_SCHEMA := "cr06-overhead/2"

var _headless_check: bool = false
var _actor: Node2D
var _layout: Node
var _camera: Camera2D
var _requested_pointer: Vector2 = Vector2.ZERO
var _requested_window_size: Vector2i = Vector2i.ZERO
var _previous_visible_units: Dictionary = {}
var _camera_before_change: Dictionary = {}


func _run() -> void:
	var has_output: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
			has_output = true
		elif argument == "--headless-check":
			_headless_check = true
		elif argument.begins_with("--weight="):
			_body_weight = argument.trim_prefix("--weight=")
	if _headless_check:
		await _run_headless_check()
		return
	if OS.get_name() != "Windows" or DisplayServer.get_name() != "Windows":
		_abort("本采集必须使用 Windows 显示服务")
		return
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_abort("本采集必须使用 Compatibility")
		return
	if not bool(ProjectSettings.get_setting("display/window/size/no_focus", false)):
		_abort("启动配置必须预先设置 no_focus")
		return
	if _body_weight != "Medium":
		_abort("只采集正式 Medium 正文字重与 Bold 标题")
		return
	if not has_output or not _validate_output_directory():
		return
	print("CR06_WINDOWS_PROCESS_ID ", OS.get_process_id())
	root.unfocusable = true
	root.borderless = true
	root.position = Vector2i(-12000, -12000)
	for dimensions: Vector2i in CR06_SIZES:
		_requested_window_size = dimensions
		root.size = dimensions
		await _frames(8)
		if not await _create_session():
			return
		if not _set_comparison_weight():
			_abort("正式 Medium 字体链无法设置")
			return
		await _frames(4)
		if not _bind_overhead_api():
			return
		if not _validate_adjoining_fixture():
			return
		_previous_visible_units.clear()
		_manager.request_end_move()
		await _frames(8)
		_move_pointer(Vector2(20, 100))
		await _frames(4)
		await _capture_overhead("adjacent-forecast-hidden", false, false)
		if _failed:
			return
		if not await _show_target_forecast():
			return
		await _capture_overhead("adjacent-forecast-visible", true, false)
		if _failed:
			return
		if not await _hide_target_forecast():
			return
		_camera_before_change = _camera_record()
		# 只改变测试中的 Camera2D，不动场景和玩法数据；随后重算目标的内部视口位置。
		_camera.position += Vector2(84.0, -42.0)
		_camera.zoom *= 1.12
		_camera.force_update_scroll()
		await _frames(4)
		_move_pointer(_target_screen_position())
		await _frames(3)
		_manager.request_skill_selection("swordsman_zhanji")
		await _frames(12)
		await _capture_overhead("camera-pan-zoom-forecast-reshown", true, true)
		if _failed:
			return
		_session.request_return()
		await _frames(3)
	quit(1 if _failed else 0)


func _run_headless_check() -> void:
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_abort("headless API check expects Compatibility")
		return
	root.size = Vector2i(1280, 720)
	if not await _create_session():
		return
	if not _bind_overhead_api() or not _validate_adjoining_fixture():
		return
	if not _set_comparison_weight():
		_abort("正式 Medium 字体链无法设置")
		return
	await _frames(3)
	_layout.call("refresh_layout")
	var snapshot: Dictionary = _layout.call("get_debug_snapshot")
	var units_value: Variant = snapshot.get("units", [])
	if not (units_value is Array):
		_abort("headless API 快照 units 不是 Array")
		return
	var units: Array = units_value
	if units.size() < 2:
		_abort("headless API 检查未取得至少两个实际单位布局")
		return
	for item_variant: Variant in units:
		if not (item_variant is Dictionary):
			_abort("headless API 快照单位项不是 Dictionary")
			return
		var item: Dictionary = item_variant
		for key: String in ["body_rect", "name_rect", "health_bar_rect", "hp_text_rect", "forecast_rect"]:
			if _rect_to_array(item.get(key)).size() != 4:
				_abort("headless API 未返回可序列化的实际 Rect2：" + key)
				return
	print("CR06_OVERHEAD_HEADLESS_CHECK " + JSON.stringify({
		"pass": true,
		"scene": "res://scenes/tactical/TacticalScene.tscn",
		"layout_node": str(_layout.get_path()),
		"snapshot_units": units.size(),
		"fixture": _fixture,
		"input_origin": "not used; headless API/scene parse only",
	}))
	quit(0)


func _validate_output_directory() -> bool:
	var project: String = ProjectSettings.globalize_path("res://").simplify_path().replace("\\", "/").to_lower().trim_suffix("/")
	var output: String = _output.simplify_path().replace("\\", "/").to_lower().trim_suffix("/")
	if not _output.is_absolute_path() or output == project or output.begins_with(project + "/"):
		_abort("需要仓库外绝对输出目录")
		return false
	if not DirAccess.dir_exists_absolute(_output):
		_abort("runner 必须先创建仓外批次目录")
		return false
	if not DirAccess.get_files_at(_output).is_empty():
		_abort("输出目录必须为空；请使用新批次目录并保留旧证据")
		return false
	return true


func _bind_overhead_api() -> bool:
	_layout = _scene.get_node_or_null(OVERHEAD_NODE_PATH)
	_camera = _scene.get("_camera") as Camera2D
	if _layout == null or not _layout.has_method("refresh_layout") or not _layout.has_method("get_debug_snapshot"):
		_abort("正式 TacticalScene 缺少 UnitOverheadLayout 调试快照接口")
		return false
	if _camera == null:
		_abort("正式 TacticalScene 未创建 Camera2D")
		return false
	return true


func _validate_adjoining_fixture() -> bool:
	if _manager == null or _manager.units.size() < 2 or _target == null:
		_abort("正式 courtyard 相邻单位夹具未创建")
		return false
	_actor = _manager.units[0] as Node2D
	if _actor == null or not _manager.grid.get_neighbors(_actor.grid_position).has(_target.grid_position):
		_abort("冻结夹具没有保留合法相邻敌人出生点")
		return false
	if bool(_fixture.get("terrain_modified", true)) or bool(_fixture.get("gameplay_values_modified", true)):
		_abort("相邻单位夹具不得修改地形或玩法数值")
	return true


func _show_target_forecast() -> bool:
	_manager.request_skill_selection("swordsman_zhanji")
	_move_pointer(_target_screen_position())
	await _frames(12)
	var data: Dictionary = _manager.get_dashboard_data()
	var forecast: Dictionary = data.get("forecast", {})
	var panel: Control = _scene.get("_damage_forecaster") as Control
	if not _manager.is_targeting_active() or not bool(forecast.get("visible", false)) \
			or forecast.get("targets", []).is_empty() or panel == null or not panel.is_visible_in_tree():
		_abort("目标悬停后没有实际显示伤害预测")
		return false
	return true


func _hide_target_forecast() -> bool:
	_manager.request_skill_selection("swordsman_zhanji")
	await _frames(5)
	var panel: Control = _scene.get("_damage_forecaster") as Control
	var forecast: Dictionary = _manager.get_dashboard_data().get("forecast", {})
	if _manager.is_targeting_active() or bool(forecast.get("visible", false)) or (panel != null and panel.is_visible_in_tree()):
		_abort("取消瞄准后预测仍然可见")
		return false
	return true


func _target_screen_position() -> Vector2:
	return _target.get_global_transform_with_canvas().origin


func _move_pointer(point: Vector2) -> void:
	_requested_pointer = point
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)


func _capture_overhead(group: String, expect_forecast: bool, require_camera_move: bool) -> void:
	_layout.call("refresh_layout")
	await RenderingServer.frame_post_draw
	var frame: int = Engine.get_process_frames()
	var texture: ViewportTexture = root.get_texture()
	if texture == null:
		_abort("无法读取根 Window 的 ViewportTexture")
		return
	var image: Image = texture.get_image()
	if image == null:
		_abort("无法从根 ViewportTexture 读取原始 Image")
		return
	var forecast: Dictionary = _manager.get_dashboard_data().get("forecast", {})
	var panel: Control = _scene.get("_damage_forecaster") as Control
	var panel_visible: bool = panel != null and panel.is_visible_in_tree()
	var hovered: Dictionary = _manager.get_hover_world_pos()
	var hover_cell: Array = []
	if bool(hovered.get("has", false)):
		var world: Vector2 = hovered.get("world", Vector2.ZERO)
		var cell: Vector2i = _manager.grid.world_to_grid(world)
		hover_cell = [cell.x, cell.y]
	var snapshot: Dictionary = _layout.call("get_debug_snapshot")
	var unit_rows: Array[Dictionary] = _normalise_units(snapshot.get("units", []))
	var actual_pointer: Vector2 = root.get_mouse_position()
	var size_matches: bool = image != null and image.get_size() == _requested_window_size \
		and root.size == _requested_window_size \
		and frame == Engine.get_process_frames()
	var forecast_values: Dictionary = _forecast_record(forecast)
	var state: Dictionary = {
		"schema": CAPTURE_SCHEMA,
		"capture_group": group,
		"image_file": "%s-%dx%d.png" % [group, root.size.x, root.size.y],
		"body_weight": "Medium",
		"title_weight": "Bold",
		"font_sources": _font_sources_record(),
		"input_origin": "Viewport.push_input only; operating-system mouse untouched",
		"map_source": EXAMPLES,
		"example": "courtyard",
		"map_size": [10, 10],
		"runtime_scene": _scene.scene_file_path,
		"fixture": _fixture,
		"actor": _unit_identity(_actor),
		"actor_cell": [_actor.grid_position.x, _actor.grid_position.y],
		"selected_skill": str(_manager.get("_selected_skill_id")),
		"forecast_visible": panel_visible,
		"forecast_panel_rect": _rect_to_array(panel.get_global_rect()) if panel != null else [0, 0, 0, 0],
		"forecast_values": forecast_values,
		"target": _unit_identity(_target),
		"target_cell": [_target.grid_position.x, _target.grid_position.y],
		"hover_present": bool(hovered.get("has", false)),
		"hover_cell": hover_cell,
		"hover_world": _vector2_to_array(hovered.get("world", Vector2.ZERO)),
		"requested_viewport_mouse": _vector2_to_array(_requested_pointer),
		"actual_viewport_mouse": _vector2_to_array(actual_pointer),
		"window_size": [root.size.x, root.size.y],
		"requested_window_size": [_requested_window_size.x, _requested_window_size.y],
		"viewport_size": _vector2_to_array(root.get_visible_rect().size),
		"layout_snapshot_viewport_size": _vector2_to_array(snapshot.get("viewport_size", Vector2.ZERO)),
		"texture_size": [texture.get_width(), texture.get_height()],
		"image_size": [image.get_width(), image.get_height()],
		"camera": _camera_record(),
		"camera_before_pan_zoom": _camera_before_change,
		"layout_units": unit_rows,
		"frame_binding": {"phase": "frame_post_draw", "start": frame, "end": Engine.get_process_frames()},
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"display_server": DisplayServer.get_name(),
		"window_unfocusable": root.unfocusable,
		"window_no_focus_setting": bool(ProjectSettings.get_setting("display/window/size/no_focus", false)),
		"window_position": [root.position.x, root.position.y],
	}
	if _failed:
		return
	if not size_matches:
		_abort("原图不是当前请求的 Window 尺寸，或原图与状态不是同一 frame_post_draw")
		return
	if panel_visible != expect_forecast or bool(forecast.get("visible", false)) != expect_forecast:
		_abort("实际预测可见状态与采集案例不符：" + group)
		return
	if not _validate_unit_rows(unit_rows, expect_forecast, group):
		return
	if require_camera_move and not _validate_repositioned_labels(unit_rows):
		return
	var basename: String = "%s-%dx%d" % [group, root.size.x, root.size.y]
	var png_path: String = _output.path_join(basename + ".png")
	if image.save_png(png_path) != OK:
		_abort("无法保存原始整屏 PNG")
		return
	state["image_sha256"] = FileAccess.get_sha256(png_path)
	var state_path: String = _output.path_join(basename + ".json")
	var file := FileAccess.open(state_path, FileAccess.WRITE)
	if file == null:
		_abort("无法保存同帧状态")
		return
	file.store_string(JSON.stringify(state, "  "))
	file.close()
	var record: Dictionary = CaptureMetadata.capture_record(root, image, png_path, {
		"capture_group": group,
		"capture_schema": CAPTURE_SCHEMA,
		"frame_binding": state["frame_binding"],
		"body_weight": "Medium",
		"title_weight": "Bold",
	})
	record["state_file"] = state_path.get_file()
	record["state_sha256"] = FileAccess.get_sha256(state_path)
	record["state_frame"] = frame
	record["fixture"] = _fixture
	_records.append(record)
	if not CaptureMetadata.write_manifest(root, _output.path_join("capture-metadata.json"), _records, {
		"script": "res://tests/claude_review/capture_cr06_overhead.gd",
		"capture_schema": CAPTURE_SCHEMA,
		"map_source": EXAMPLES,
		"map_example": "courtyard",
		"map_size": [10, 10],
		"body_weight": "Medium",
		"title_weight": "Bold",
		"input_origin": "Viewport.push_input only; no operating-system mouse calls",
		"engine": Engine.get_version_info(),
		"os": OS.get_name(),
		"display_server": DisplayServer.get_name(),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"audio_driver": AudioServer.get_driver_name(),
	}):
		_abort("无法保存原图与同帧状态清单")
		return
	print("CR06_WINDOWS_CAPTURE " + JSON.stringify({
		"file": basename + ".png",
		"sha256": record["sha256"],
		"state_file": record["state_file"],
		"state_sha256": record["state_sha256"],
		"frame": frame,
		"forecast_visible": panel_visible,
		"units": unit_rows.size(),
	}))


func _validate_unit_rows(rows: Array[Dictionary], expect_forecast: bool, group: String) -> bool:
	if rows.size() < 2:
		_abort("实际 Overhead 快照没有相邻单位：" + group)
		return false
	var target_row: Dictionary = {}
	var visible_forecasts: int = 0
	for row: Dictionary in rows:
		for key: String in ["body_rect", "name_rect", "health_bar_rect", "hp_text_rect", "forecast_rect"]:
			var rect: Array = row.get(key, [])
			if rect.size() != 4:
				_abort("实例节点矩形缺失：%s / %s" % [str(row.get("unit_id", "")), key])
				return false
		for key: String in ["body_rect", "name_rect", "health_bar_rect", "hp_text_rect"]:
			if not _rect_has_area(row.get(key, [])):
				_abort("单位身体、名牌或生命显示未提供实际矩形：%s / %s" % [str(row.get("unit_id", "")), key])
				return false
		if bool(row.get("forecast_visible", false)):
			visible_forecasts += 1
		if int(row.get("instance_id", -1)) == _target.get_instance_id():
			target_row = row
	if target_row.is_empty():
		# Older compatible snapshots may not yet include instance_id; match the unique enemy fixture.
		for row: Dictionary in rows:
			if str(row.get("faction", "")) == "enemy" and row.get("grid_position", []) == [_target.grid_position.x, _target.grid_position.y]:
				target_row = row
				break
	if target_row.is_empty():
		_abort("快照中找不到相邻测试敌人")
		return false
	if expect_forecast:
		if visible_forecasts < 1 or not bool(target_row.get("forecast_visible", false)) \
				or str(target_row.get("forecast_text", "")).is_empty() \
				or str(target_row.get("forecast_glyph_shape", "")).is_empty() \
				or not _rect_has_area(target_row.get("forecast_rect", [])):
			_abort("显示案例未采集到目标单位实际预测节点与矩形：" + group)
			return false
	else:
		if visible_forecasts != 0:
			_abort("隐藏案例仍有单位预测节点可见：" + group)
		for row: Dictionary in rows:
			if not str(row.get("forecast_text", "")).is_empty() or not str(row.get("forecast_glyph_shape", "")).is_empty():
				_abort("隐藏案例仍保留预测标签内容：" + group)
				return false
	if group == "adjacent-forecast-visible":
		_previous_visible_units = _index_units(rows)
	return true


func _validate_repositioned_labels(rows: Array[Dictionary]) -> bool:
	var camera_after: Dictionary = _camera_record()
	if camera_after.get("transform") == _camera_before_change.get("transform") \
			or camera_after.get("zoom") == _camera_before_change.get("zoom"):
		_abort("镜头平移/缩放没有形成可核验的 Camera2D 变化")
		return false
	var actor_key: String = "instance:%d" % _actor.get_instance_id()
	var target_key: String = "instance:%d" % _target.get_instance_id()
	var required_ids: Dictionary = {actor_key: true, target_key: true}
	var matched: int = 0
	for row: Dictionary in rows:
		var key: String = _unit_key(row)
		if not required_ids.has(key):
			continue
		if not _previous_visible_units.has(key):
			continue
		var previous: Dictionary = _previous_visible_units[key]
		if row.get("body_rect") == previous.get("body_rect"):
			_abort("镜头移动后单位身体矩形仍停在旧坐标：" + key)
			return false
		if row.get("name_rect") == previous.get("name_rect") \
				or row.get("health_bar_rect") == previous.get("health_bar_rect") \
				or row.get("hp_text_rect") == previous.get("hp_text_rect"):
			_abort("镜头移动后单位头顶标签有矩形滞留旧坐标：" + key)
			return false
		if key == target_key \
				and row.get("forecast_rect") == previous.get("forecast_rect"):
			_abort("镜头移动后目标预测数字矩形仍停在旧坐标")
			return false
		matched += 1
	if matched != required_ids.size():
		_abort("平移/缩放前后未能匹配至少两个单位实例")
		return false
	return true


func _index_units(rows: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for row: Dictionary in rows:
		result[_unit_key(row)] = row.duplicate(true)
	return result


func _unit_key(row: Dictionary) -> String:
	if row.has("instance_id"):
		return "instance:%d" % int(row["instance_id"])
	return "%s|%s|%s" % [str(row.get("unit_id", "")), str(row.get("faction", "")), str(row.get("grid_position", []))]


func _normalise_units(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (value is Array):
		return result
	for entry_variant: Variant in value:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		var row: Dictionary = {}
		for key: String in ["unit_id", "unit_name", "faction", "hp_text", "forecast_text", "forecast_glyph_shape", "forecast_visible", "instance_id", "overhead_group_name"]:
			if entry.has(key):
				row[key] = entry[key]
		for key: String in ["body_rect", "name_rect", "health_bar_rect", "hp_text_rect", "forecast_rect", "group_rect"]:
			row[key] = _rect_to_array(entry.get(key))
		var grid_value: Variant = entry.get("grid_position", Vector2i(-1, -1))
		if grid_value is Vector2i:
			var grid: Vector2i = grid_value
			row["grid_position"] = [grid.x, grid.y]
		elif grid_value is Vector2:
			var grid_float: Vector2 = grid_value
			row["grid_position"] = [int(grid_float.x), int(grid_float.y)]
		elif grid_value is Array:
			row["grid_position"] = grid_value.duplicate()
		else:
			row["grid_position"] = []
		result.append(row)
	return result


func _rect_to_array(value: Variant) -> Array:
	if value is Rect2:
		var rect: Rect2 = value
		return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	if value is Rect2i:
		var rect_i: Rect2i = value
		return [rect_i.position.x, rect_i.position.y, rect_i.size.x, rect_i.size.y]
	if value is Array and value.size() == 4:
		return value.duplicate()
	if value is PackedFloat32Array and value.size() == 4:
		return Array(value)
	if value is PackedFloat64Array and value.size() == 4:
		return Array(value)
	if value is Dictionary and value.has("position") and value.has("size"):
		var position: Array = _vector2_to_array(value["position"])
		var size: Array = _vector2_to_array(value["size"])
		if position.size() == 2 and size.size() == 2:
			return [position[0], position[1], size[0], size[1]]
	return []


func _rect_has_area(value: Variant) -> bool:
	var rect: Array = _rect_to_array(value)
	return rect.size() == 4 and float(rect[2]) > 0.0 and float(rect[3]) > 0.0


func _forecast_record(forecast: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in ["visible", "target_name", "target_hp", "target_hp_max", "damage_type", "is_heal", "hit_count", "per_hit_damage", "total_damage", "damage", "hit_percent", "crit_percent", "terrain_name", "terrain_evade_bonus", "terrain_def_bonus", "terrain_res_bonus"]:
		if forecast.has(key):
			result[key] = forecast[key]
	var targets: Array = []
	for target_variant: Variant in forecast.get("targets", []):
		if not (target_variant is Dictionary):
			continue
		var target: Dictionary = target_variant
		var world: Vector2 = target.get("world", Vector2.ZERO)
		targets.append({
			"world": _vector2_to_array(world),
			"damage": int(target.get("damage", 0)),
			"damage_type": str(target.get("damage_type", "")),
			"hit_percent": int(target.get("hit_percent", 0)),
			"crit_percent": int(target.get("crit_percent", 0)),
			"is_primary": bool(target.get("is_primary", false)),
		})
	result["targets"] = targets
	return result


func _unit_identity(unit: Node) -> Dictionary:
	return {
		"instance_id": unit.get_instance_id(),
		"unit_id": str(unit.get("unit_id")),
		"unit_name": str(unit.get("unit_name")),
		"faction": str(unit.get("faction")),
		"hp": int(unit.get("stats").get("hp")),
		"hp_max": int(unit.get("stats").get("max_hp")),
	}


func _font_sources_record() -> Dictionary:
	var theme: Theme = load("res://assets/ui/themes/hud_m2.tres") as Theme
	var body_record: Dictionary = _font_record(theme.default_font, {})
	var title_font: Font = load(TITLE_FONT_PATH) as Font
	var title_record: Dictionary = _font_record(title_font, {})
	var expected_medium: String = FileAccess.get_sha256(MEDIUM_FONT_PATH)
	var expected_bold: String = FileAccess.get_sha256(BOLD_FONT_PATH)
	if not _contains_font_hash(body_record, expected_medium) or not _contains_font_hash(title_record, expected_bold):
		push_error("CR06_CAPTURE_FAIL 实际正式字体链不含 Medium 正文或 Bold 标题源字节")
		_failed = true
	return {
		"body_theme": "res://assets/ui/themes/hud_m2.tres",
		"body_font_chain": body_record,
		"body_medium_source": MEDIUM_FONT_PATH,
		"body_medium_sha256": expected_medium,
		"title_font_resource": TITLE_FONT_PATH,
		"title_font_chain": title_record,
		"title_bold_source": BOLD_FONT_PATH,
		"title_bold_sha256": expected_bold,
	}


func _contains_font_hash(font_record: Dictionary, expected: String) -> bool:
	if str(font_record.get("font_data_sha256", "")) == expected:
		return true
	if font_record.has("base_font") and _contains_font_hash(font_record["base_font"], expected):
		return true
	for fallback_variant: Variant in font_record.get("fallbacks", []):
		if fallback_variant is Dictionary and _contains_font_hash(fallback_variant, expected):
			return true
	return false


func _camera_record() -> Dictionary:
	var global_transform: Transform2D = _camera.global_transform
	var canvas: Transform2D = root.get_canvas_transform()
	return {
		"position": _vector2_to_array(_camera.position),
		"global_position": _vector2_to_array(_camera.global_position),
		"zoom": _vector2_to_array(_camera.zoom),
		"transform": _transform_to_array(global_transform),
		"viewport_canvas_transform": _transform_to_array(canvas),
	}


func _transform_to_array(transform: Transform2D) -> Array:
	return [transform.x.x, transform.x.y, transform.y.x, transform.y.y,
		transform.origin.x, transform.origin.y]


func _vector2_to_array(value: Variant) -> Array:
	if value is Vector2:
		var vector: Vector2 = value
		return [vector.x, vector.y]
	if value is Vector2i:
		var vector_i: Vector2i = value
		return [vector_i.x, vector_i.y]
	return []
