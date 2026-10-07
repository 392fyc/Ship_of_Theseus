extends SceneTree
## 正式 10x10 Courtyard TacticalScene 中核对名牌、血条与伤害预测头顶布局。

const COURTYARD_EXAMPLES: String = "res://assets/prototype/battlefield_courtyard/terrain_examples.json"

var _pass: int = 0
var _fail: int = 0
var _failures: Array[String] = []
func _initialize() -> void:
	print("=== test_unit_overhead_layout ===")
	_run.call_deferred()


func _run() -> void:
	var root_window: Window = root as Window
	root_window.size = Vector2i(1280, 720)
	var examples_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(COURTYARD_EXAMPLES))
	_check("Courtyard 试战地图可读", examples_value is Dictionary and (examples_value as Dictionary).has("courtyard"))
	if not (examples_value is Dictionary):
		_finish()
		return
	var session_script: GDScript = load("res://scripts/tactical/terrain_battle_session.gd") as GDScript
	var session: Node2D = session_script.new()
	var configured: Dictionary = session.call("configure_map", (examples_value as Dictionary)["courtyard"].duplicate(true))
	_check("正式 TerrainBattleSession 接受 courtyard", bool(configured.get("ok", false)))
	if not bool(configured.get("ok", false)):
		session.free()
		_finish()
		return
	var map_data: Dictionary = session.get("_configured_map")
	_check("Courtyard 地图为 10x10", int(map_data.get("width", 0)) == 10 and int(map_data.get("height", 0)) == 10)
	if int(map_data.get("width", 0)) != 10 or int(map_data.get("height", 0)) != 10:
		session.free()
		_finish()
		return
	var adjacent: Vector2i = _move_enemy_to_adjacent_passable_cell(map_data)
	_check("枪兵使用现有相邻出生夹具", adjacent != Vector2i(-1, -1))
	if adjacent == Vector2i(-1, -1):
		session.free()
		_finish()
		return
	session.set("_configured_map", map_data)
	root.add_child(session)
	await _frames(5)
	session.call("fit_board")
	await _frames(3)
	var scene: Node = session.get("battle")
	var manager: Node = session.get("manager")
	_check("进入正式 TacticalScene", scene != null and is_instance_valid(scene))
	if scene == null or not is_instance_valid(scene) or manager == null:
		root.remove_child(session)
		session.free()
		_finish()
		return
	var layout: Control = scene.get_node_or_null("UILayer/UnitOverheadLayout") as Control
	_check("头顶控件统一位于 UILayer/UnitOverheadLayout", layout != null)
	if layout == null:
		root.remove_child(session)
		session.free()
		_finish()
		return
	var actor: Unit = _find_unit(manager.units, "myrmidon")
	var target: Unit = _find_unit(manager.units, "test_lancer")
	var actors_adjacent: bool = false
	if actor != null and target != null:
		actors_adjacent = absi(actor.grid_position.x - target.grid_position.x) \
			+ absi(actor.grid_position.y - target.grid_position.y) == 1
	_check("场景使用相邻 myrmidon/test_lancer", actors_adjacent)
	if actor == null or target == null:
		root.remove_child(session)
		session.free()
		_finish()
		return
	_check("目标血量基线为 26/26", target.stats.hp == 26 and target.stats.max_hp == 26)
	_check("玩家/敌人阵营染色仍由原单位精灵保留",
		actor.sprite.self_modulate == Color("315670") and target.sprite.self_modulate == Color("713e43"))
	var legacy_name: Control = target.get_node_or_null("UnitLabel") as Control
	var legacy_hp: Control = target.get_node_or_null("HPLabel") as Control
	_check("旧单位内头顶标签与血条隐藏，统一头顶层负责显示",
		not target.health_bar.visible and legacy_name != null and not legacy_name.visible
		and legacy_hp != null and not legacy_hp.visible)

	layout.call("sync_units", manager.units)
	layout.call("set_forecast_targets", [])
	layout.call("refresh_layout")
	var hidden_snapshot: Dictionary = layout.call("get_debug_snapshot")
	var hidden_target: Dictionary = _snapshot_unit(hidden_snapshot, target.get_instance_id())
	var initial_bar_rect: Rect2 = hidden_target.get("health_bar_rect", Rect2())
	var initial_hp_rect: Rect2 = hidden_target.get("hp_text_rect", Rect2())
	var initial_body_rect: Rect2 = hidden_target.get("body_rect", Rect2())
	_check("默认显示血条与 HP 文本",
		initial_bar_rect.size.y == 4.0 and initial_hp_rect.size.x > 0.0
		and str(hidden_target.get("hp_text", "")) == "26 / 26")
	_check("身体矩形只覆盖当前可见棋子绘制区域",
		initial_body_rect.size.x > 0.0 and initial_body_rect.size.y > 0.0
		and initial_body_rect.size.x <= 40.0 and initial_body_rect.size.y <= 40.0)
	var health_bar: ProgressBar = layout.find_child(
		"HealthBar_%d" % target.get_instance_id(), true, false) as ProgressBar
	var bar_background: StyleBoxFlat = null
	if health_bar != null:
		bar_background = health_bar.get_theme_stylebox("background") as StyleBoxFlat
	_check("血条描边读取枪兵现有阵营色",
		bar_background != null and bar_background.border_color.is_equal_approx(Unit.FACTION_COLORS[target.faction]))
	_check("默认不显示伤害预测数字", not bool(hidden_target.get("forecast_visible", true))
		and str(hidden_target.get("forecast_text", "")).is_empty())
	_check_layout_geometry("无预测", hidden_snapshot)
	_check_reserved_geometry("无预测", hidden_snapshot, scene)

	# 由 TacticalManager 的既有攻击预测生成实际 9 点伤害，不在测试或布局器中造预测值。
	manager.call("request_end_move")
	await _frames(8)
	manager.call("request_skill_selection", "swordsman_zhanji")
	manager.call("handle_pointer_hover", target.get_global_transform_with_canvas().origin)
	await _frames(12)
	var forecast: Dictionary = manager.get_dashboard_data().get("forecast", {})
	var forecast_targets: Array = forecast.get("targets", [])
	_check("正式预测结果包含目标 9", forecast_targets.size() == 1
		and int((forecast_targets[0] as Dictionary).get("damage", -1)) == 9)
	layout.call("refresh_layout")
	var shown_snapshot: Dictionary = layout.call("get_debug_snapshot")
	var shown_target: Dictionary = _snapshot_unit(shown_snapshot, target.get_instance_id())
	_check("预测头顶显示 9 且目标仍为 test_lancer",
		bool(shown_target.get("forecast_visible", false))
		and str(shown_target.get("forecast_text", "")) == "9"
		and str(shown_target.get("unit_id", "")) == "test_lancer")
	_check("预测类型字形语义保留为物理剑形",
		str(shown_target.get("forecast_glyph_shape", "")) == "sword")
	_check("HP 26/26 与预测 9 均保留且各有独立矩形",
		str(shown_target.get("hp_text", "")) == "26 / 26"
		and (shown_target.get("hp_text_rect", Rect2()) as Rect2).size.x > 0.0
		and (shown_target.get("forecast_rect", Rect2()) as Rect2).size.x > 0.0)
	_check_layout_geometry("显示预测", shown_snapshot)
	_check_reserved_geometry("显示预测", shown_snapshot, scene)

	var initial_actor: Dictionary = _snapshot_unit(shown_snapshot, actor.get_instance_id())
	var initial_body: Rect2 = initial_actor.get("body_rect", Rect2())
	var camera: Camera2D = scene.get("_camera") as Camera2D
	camera.position += Vector2(28.0, -16.0)
	camera.force_update_scroll()
	await _frames(2)
	layout.call("refresh_layout")
	var moved_snapshot: Dictionary = layout.call("get_debug_snapshot")
	var moved_actor: Dictionary = _snapshot_unit(moved_snapshot, actor.get_instance_id())
	_check("镜头平移后身体与头顶控件同步重排",
		(not (moved_actor.get("body_rect", Rect2()) as Rect2).position.is_equal_approx(initial_body.position))
		and str(_snapshot_unit(moved_snapshot, target.get_instance_id()).get("forecast_text", "")) == "9")
	_check_layout_geometry("镜头平移", moved_snapshot)
	_check_reserved_geometry("镜头平移", moved_snapshot, scene)

	var initial_zoom: Vector2 = camera.zoom
	var body_before_zoom: Rect2 = moved_actor.get("body_rect", Rect2())
	camera.zoom = initial_zoom * 1.2
	camera.force_update_scroll()
	await _frames(2)
	layout.call("refresh_layout")
	var zoomed_snapshot: Dictionary = layout.call("get_debug_snapshot")
	var body_after_zoom: Rect2 = _snapshot_unit(zoomed_snapshot, actor.get_instance_id()).get("body_rect", Rect2())
	_check("镜头缩放后正文屏幕矩形变化并保持预测关联",
		not (zoomed_snapshot["viewport_size"] as Vector2).is_zero_approx()
		and (not body_after_zoom.position.is_equal_approx(body_before_zoom.position)
		or not body_after_zoom.size.is_equal_approx(body_before_zoom.size))
		and str(_snapshot_unit(zoomed_snapshot, target.get_instance_id()).get("forecast_text", "")) == "9")
	_check_layout_geometry("镜头缩放", zoomed_snapshot)
	_check_reserved_geometry("镜头缩放", zoomed_snapshot, scene)

	for window_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		root_window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root_window.content_scale_size = window_size
		root_window.size = window_size
		await _frames(2)
		session.call("fit_board")
		await _frames(2)
		layout.call("refresh_layout")
		var size_snapshot: Dictionary = layout.call("get_debug_snapshot")
		_check("窗口档位 %dx%d 已采样" % [window_size.x, window_size.y],
			(size_snapshot.get("viewport_size", Vector2.ZERO) as Vector2).x >= float(window_size.x) * 0.95
			and (size_snapshot.get("viewport_size", Vector2.ZERO) as Vector2).y >= float(window_size.y) * 0.95)
		_check_layout_geometry("窗口 %dx%d" % [window_size.x, window_size.y], size_snapshot)
		_check_reserved_geometry("窗口 %dx%d" % [window_size.x, window_size.y], size_snapshot, scene)

	var fixed_a: Dictionary = layout.call("get_debug_snapshot")
	await _frames(2)
	var fixed_b: Dictionary = layout.call("get_debug_snapshot")
	_check("静止镜头连续帧矩形稳定",
		_snapshot_rect(fixed_a, actor.get_instance_id(), "name_rect").is_equal_approx(
			_snapshot_rect(fixed_b, actor.get_instance_id(), "name_rect"))
		and _snapshot_rect(fixed_a, target.get_instance_id(), "forecast_rect").is_equal_approx(
			_snapshot_rect(fixed_b, target.get_instance_id(), "forecast_rect")))

	# 显式退出瞄准并验证预测控件清理；HP 默认保持可见。
	manager.call("request_skill_selection", "swordsman_zhanji")
	await _frames(5)
	var cleared_snapshot: Dictionary = layout.call("get_debug_snapshot")
	var cleared_target: Dictionary = _snapshot_unit(cleared_snapshot, target.get_instance_id())
	_check("预测关闭后头顶数字隐藏而 HP 仍可见",
		not bool(cleared_target.get("forecast_visible", true))
		and (cleared_target.get("health_bar_rect", Rect2()) as Rect2).size.y == 4.0
		and str(cleared_target.get("hp_text", "")) == "26 / 26")

	target.take_damage(target.stats.hp)
	await _frames(2)
	var after_death: Dictionary = layout.call("get_debug_snapshot")
	_check("死亡单位的头顶节点随单位集合清理",
		_snapshot_unit(after_death, target.get_instance_id()).is_empty())

	var layout_ref: WeakRef = weakref(layout)
	root.remove_child(session)
	session.free()
	await process_frame
	_check("场景销毁后统一头顶节点一并销毁", layout_ref.get_ref() == null)
	_finish()


func _move_enemy_to_adjacent_passable_cell(map_data: Dictionary) -> Vector2i:
	var grid: Grid = Grid.new()
	grid.initialize(map_data)
	var player_units: Array = map_data.get("player_units", [])
	var enemy_units: Array = map_data.get("enemy_units", [])
	if player_units.is_empty() or enemy_units.is_empty():
		return Vector2i(-1, -1)
	var player_record: Dictionary = player_units[0]
	var enemy_record: Dictionary = enemy_units[0]
	var player_position: Array = player_record.get("position", [])
	if player_position.size() < 2:
		return Vector2i(-1, -1)
	var player_cell: Vector2i = Vector2i(int(player_position[0]), int(player_position[1]))
	for candidate: Vector2i in grid.get_neighbors(player_cell):
		if not grid.get_cell(candidate).is_passable():
			continue
		enemy_record["position"] = [candidate.x, candidate.y]
		enemy_units[0] = enemy_record
		map_data["enemy_units"] = enemy_units
		return candidate
	return Vector2i(-1, -1)


func _find_unit(units: Array, unit_id: String) -> Unit:
	for unit_value: Variant in units:
		if unit_value is Unit and unit_value.unit_id == unit_id:
			return unit_value
	return null


func _snapshot_unit(snapshot: Dictionary, instance_id: int) -> Dictionary:
	for row_value: Variant in snapshot.get("units", []):
		if row_value is Dictionary and int((row_value as Dictionary).get("instance_id", 0)) == instance_id:
			return row_value
	return {}


func _snapshot_rect(snapshot: Dictionary, instance_id: int, key: String) -> Rect2:
	return _snapshot_unit(snapshot, instance_id).get(key, Rect2()) as Rect2


func _check_layout_geometry(label: String, snapshot: Dictionary) -> void:
	var rows: Array = snapshot.get("units", [])
	var bodies: Array[Rect2] = []
	for row_value: Variant in rows:
		if row_value is Dictionary:
			var body: Rect2 = (row_value as Dictionary).get("body_rect", Rect2())
			if body.size.x > 0.0 and body.size.y > 0.0:
				bodies.append(body)
	for index: int in range(rows.size()):
		var row: Dictionary = rows[index]
		var body_rect: Rect2 = row.get("body_rect", Rect2())
		var group_rect: Rect2 = row.get("group_rect", Rect2())
		var bar_rect: Rect2 = row.get("health_bar_rect", Rect2())
		_check("%s %s 保留可见HP血条" % [label, row.get("unit_id", "")],
			bar_rect.size.y == 4.0 and bar_rect.size.x <= body_rect.size.x + 0.01)
		_check("%s %s 头顶部件属于对应单位组" % [label, row.get("unit_id", "")],
			str(row.get("overhead_group_name", "")) == "OverheadGroup_%d" % int(row.get("instance_id", 0))
			and group_rect.size.x > 0.0 and group_rect.size.y > 0.0)
		var item_rects: Array[Rect2] = []
		for key: String in ["name_rect", "health_bar_rect", "hp_text_rect", "forecast_rect"]:
			var item_rect: Rect2 = row.get(key, Rect2())
			if item_rect.size.x > 0.0 and item_rect.size.y > 0.0:
				item_rects.append(item_rect)
				_check("%s %s %s 留在同一头顶组内" % [label, row.get("unit_id", ""), key],
					_rect_contains(group_rect, item_rect))
				for body_index: int in range(bodies.size()):
					_check("%s %s %s 避开第%d个实际身体矩形" % [label, row.get("unit_id", ""), key, body_index],
						not item_rect.intersects(bodies[body_index]))
		var name_rect: Rect2 = row.get("name_rect", Rect2())
		var hp_rect: Rect2 = row.get("hp_text_rect", Rect2())
		var forecast_rect: Rect2 = row.get("forecast_rect", Rect2())
		_check("%s %s 名牌与HP按同组宽度纵向对齐" % [label, row.get("unit_id", "")],
			absf(name_rect.position.x - group_rect.position.x) <= 0.01
			and absf(hp_rect.position.x - group_rect.position.x) <= 0.01
			and absf(bar_rect.get_center().x - group_rect.get_center().x) <= 0.01
			and (forecast_rect.size.x <= 0.0
			or absf(forecast_rect.get_center().x - group_rect.get_center().x) <= 0.01))
		_check("%s %s 组内名牌、预测、血条和HP顺序固定" % [label, row.get("unit_id", "")],
			name_rect.position.y >= group_rect.position.y - 0.01
			and (forecast_rect.size.y <= 0.0 or name_rect.end.y <= forecast_rect.position.y + 0.01)
			and (forecast_rect.size.y <= 0.0 or forecast_rect.end.y <= bar_rect.position.y + 0.01)
			and (forecast_rect.size.y > 0.0 or name_rect.end.y <= bar_rect.position.y + 0.01)
			and bar_rect.end.y <= hp_rect.position.y + 0.01
			and hp_rect.end.y <= group_rect.end.y + 0.01)
		for body_index: int in range(rows.size()):
			if body_index == index:
				continue
			var other_body: Rect2 = (rows[body_index] as Dictionary).get("body_rect", Rect2())
			_check("%s %s 整组避开相邻单位身体" % [label, row.get("unit_id", "")],
				not group_rect.intersects(other_body))
		for first: int in range(item_rects.size()):
			for second: int in range(first + 1, item_rects.size()):
				_check("%s %s 内部头顶矩形互不遮挡" % [label, row.get("unit_id", "")],
					not item_rects[first].intersects(item_rects[second]))
		for other_index: int in range(index + 1, rows.size()):
			var other: Dictionary = rows[other_index]
			var other_group: Rect2 = other.get("group_rect", Rect2())
			_check("%s 相邻单位整组保持分离" % label, not group_rect.intersects(other_group))
			for key: String in ["name_rect", "health_bar_rect", "hp_text_rect", "forecast_rect"]:
				var first_rect: Rect2 = row.get(key, Rect2())
				if first_rect.size.x <= 0.0 or first_rect.size.y <= 0.0:
					continue
				for other_key: String in ["name_rect", "health_bar_rect", "hp_text_rect", "forecast_rect"]:
					var second_rect: Rect2 = other.get(other_key, Rect2())
					if second_rect.size.x <= 0.0 or second_rect.size.y <= 0.0:
						continue
					_check("%s 相邻单位头顶控件互不遮挡" % label,
						not first_rect.intersects(second_rect))


func _check_reserved_geometry(label: String, snapshot: Dictionary, scene: Node) -> void:
	var reserved_rects: Array[Rect2] = []
	for control_value: Variant in [
		scene.get("_turn_order_bar"), scene.get("_bottom_dashboard"), scene.get("_damage_forecaster")]:
		if not (control_value is Control):
			continue
		var control: Control = control_value
		if not control.is_visible_in_tree():
			continue
		if control.has_method("get_input_blocking_rects"):
			var blocking_value: Variant = control.call("get_input_blocking_rects")
			if blocking_value is Array:
				for rect_value: Variant in blocking_value:
					if rect_value is Rect2:
						var blocking_rect: Rect2 = rect_value
						if blocking_rect.size.x > 0.0 and blocking_rect.size.y > 0.0:
							reserved_rects.append(blocking_rect)
		else:
			var control_rect: Rect2 = control.get_global_rect()
			if control_rect.size.x > 0.0 and control_rect.size.y > 0.0:
				reserved_rects.append(control_rect)
	for row_value: Variant in snapshot.get("units", []):
		if not (row_value is Dictionary):
			continue
		var row: Dictionary = row_value
		for key: String in ["group_rect", "name_rect", "health_bar_rect", "hp_text_rect", "forecast_rect"]:
			var overhead_rect: Rect2 = row.get(key, Rect2())
			if overhead_rect.size.x <= 0.0 or overhead_rect.size.y <= 0.0:
				continue
			for obstacle: Rect2 in reserved_rects:
					_check("%s %s %s 避开真实 HUD/浮窗阻挡矩形" % [label, row.get("unit_id", ""), key],
						not overhead_rect.intersects(obstacle.grow(5.0)))


func _rect_contains(outer: Rect2, inner: Rect2) -> bool:
	return outer.position.x <= inner.position.x + 0.01 \
		and outer.position.y <= inner.position.y + 0.01 \
		and outer.end.x >= inner.end.x - 0.01 \
		and outer.end.y >= inner.end.y - 0.01


func _frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame


func _check(description: String, condition: bool) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		_failures.append(description)
		print("  ✗ FAIL: ", description)


func _finish() -> void:
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		for failure: String in _failures:
			print("  ✗ ", failure)
		quit(1)
	else:
		print("ALL PASS")
		quit(0)
