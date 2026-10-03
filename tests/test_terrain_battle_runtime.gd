extends SceneTree

const CaptureMetadata := preload("res://tests/claude_review/capture_metadata.gd")
var _capture_records: Array[Dictionary] = []
## 自定义地形进入正式战斗：数据、通行、实际交互、重开、结果及释放验证。

const Definition := preload("res://scripts/ui/terrain/terrain_battle_definition.gd")
const EXAMPLES := "res://assets/prototype/battlefield_courtyard/terrain_examples.json"
var failures: Array[String] = []
var checks := 0
var output := ""
var captures: Dictionary = {}
var session_script: GDScript
var data_loader: Variant


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, value: bool) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("[FAIL] ", label)


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	if not output.is_absolute_path() or DisplayServer.get_name() == "headless":
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	root.borderless = true
	root.size = Vector2i(1280, 720)
	data_loader = root.get_node("DataLoader")
	session_script = load("res://scripts/tactical/terrain_battle_session.gd")
	var maps_before: Dictionary = data_loader.maps.duplicate(true)
	_check_definitions()
	var examples: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXAMPLES))
	for id: String in examples:
		var source: Dictionary = examples[id].duplicate(true)
		var saved := source.duplicate(true)
		var session: Node2D = session_script.new()
		var config: Dictionary = session.configure_map(source)
		check(id + " 配置有效", config["ok"])
		if not config["ok"]:
			session.free()
			continue
		root.add_child(session)
		await frames(6)
		var manager: Object = session.manager
		check(id + " 使用正式战斗场景", session.battle.scene_file_path == "res://scenes/tactical/TacticalScene.tscn")
		check(id + " 地图未进入全局注册表", data_loader.maps == maps_before)
		check(id + " 显示与战斗共用同一Grid", session.board_view.grid == manager.grid and not manager.terrain_layer.visible)
		check(id + " 逐格地形一致", _same_terrain(manager.grid, saved))
		check(id + " 未修改作者原地图", source == saved)
		check(id + " 双方均在合法且互异出生格", manager.units.size() == 2
			and manager.units[0].grid_position != manager.units[1].grid_position
			and manager.units.all(func(unit: Unit) -> bool: return manager.grid.get_cell(unit.grid_position).is_passable()))
		check(id + " 基础剑士界面没有印记", not session.battle._bottom_dashboard.get_composition().get_marks_panel().visible)
		check(id + " 正式移动范围排除阻挡地形", manager._move_range.keys().all(func(at: Vector2i) -> bool:
			return manager.grid.get_cell(at).is_passable()))
		for dimensions: Vector2i in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2560,1440)]:
			root.size = dimensions
			await frames(4)
			session.fit_board()
			await frames(2)
			var logical_size: Vector2 = root.get_visible_rect().size
			var factor := logical_size.y / 720.0
			var clear := true
			for y: int in manager.grid.height:
				for x: int in manager.grid.width:
					var at := _screen(manager.grid, Vector2i(x,y))
					clear = clear and at.y > 130 * factor and at.y < 506 * factor and at.x > 20 * factor and at.x < logical_size.x - 200 * factor
			check("%s %d 棋盘避开工具栏和HUD" % [id,dimensions.x], clear)
			_move_pointer(Vector2(8,8))
			session.board_view.set_process(false)
			session._update_board_visibility_context(Vector2i(-1,-1))
			session.board_view._time = 1.0
			session.board_view._process(1.0)
			await frames(4)
			await RenderingServer.frame_post_draw
			var name := "battle-%s-%d.png" % [id,dimensions.x]
			var image: Image = root.get_texture().get_image()
			check("保存 " + name, image.save_png(output.path_join(name)) == OK)
			_capture_records.append(CaptureMetadata.capture_record(root, image, output.path_join(name)))
			captures[name] = FileAccess.get_sha256(output.path_join(name))
		root.size = Vector2i(1280,720)
		await frames(4)
		session.fit_board()
		var hero: Unit = manager.current_unit
		var start := hero.grid_position
		var target := Vector2i(-1,-1)
		for neighbor: Vector2i in manager.grid.get_neighbors(start):
			if manager._move_range.has(neighbor) and manager.grid.get_unit_at(neighbor) == null:
				target = neighbor
				break
		check(id + " 存在实际移动目标", target != Vector2i(-1,-1))
		if target != Vector2i(-1,-1):
			var expected: int = hero.stats.mov - manager.grid.get_cell(target).get_move_cost()
			check(id + " 移动预算读取Cell", manager._move_range[target] == expected)
			await click(_screen(manager.grid, target))
			await create_timer(0.5).timeout
			check(id + " 实际鼠标完成移动", hero.grid_position == target)
		await session._on_restart_pressed()
		await frames(4)
		check(id + " 重开恢复初始站位", session.manager.units[0].grid_position == start)
		check(id + " 重开仍无全局地图污染", data_loader.maps == maps_before)
		var enemy: Unit = session.manager.units[1]
		enemy.take_damage(enemy.stats.hp + 1)
		await frames(5)
		check(id + " 胜利界面可返回编辑", session.battle.result_overlay.visible and session.battle.result_label.text == "胜利"
			and session.battle.return_button.text == "返回编辑")
		var returned: Array[bool] = [false]
		session.editing_resumed.connect(func() -> void: returned[0] = true)
		await click(session.battle.return_button.get_global_rect().get_center())
		check(id + " 胜利结果按钮实际触发返回", returned[0] and not session.manager.battle_active)
		root.remove_child(session)
		session.free()
		await frames(4)
		check(id + " 释放后无地图注册残留", data_loader.maps == maps_before)
	await _check_short_battle(maps_before)
	# 让最后一次 timeout 回调退出，SceneTree 才会移除已到期的测试计时器。
	await frames(2)
	check("记录真实采集配置", CaptureMetadata.write_manifest(root, output.path_join("capture-metadata.json"), _capture_records, {"script": "res://tests/test_terrain_battle_runtime.gd"}))
	var report := {"result":"pass" if failures.is_empty() else "fail", "checks":checks, "failures":failures,
		"captures":captures,"engine":Engine.get_version_info()["string"],"global_maps_unchanged":data_loader.maps == maps_before}
	var file := FileAccess.open(output.path_join("terrain-battle-runtime-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("TERRAIN_BATTLE_RUNTIME_RESULT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)


func _check_definitions() -> void:
	for rows: Array in [[[4]], [[0]], [[0,4],[4,0]], [[6,6],[3,4]]]:
		var result := Definition.build(_map(rows))
		check("不可行地图返回解释而不创建战斗 " + str(rows), not result["ok"] and not str(result["message"]).is_empty())
	var source := _map([[0,4,0,0],[4,4,0,0]])
	var built := Definition.build(source)
	check("出生选择最大连通区域", built["ok"] and built["map"]["player_units"][0]["position"] == [2,0])
	check("相同地图出生点确定", built == Definition.build(source))
	source["special_terrain"] = [{"position":[2,0],"kind":"untrusted"}]
	source["player_units"] = [{"class_id":"kensei","position":[0,0]}]
	var filtered := Definition.build(source)
	check("地形文件不会注入额外玩法或职业", not filtered["map"].has("special_terrain")
		and filtered["map"]["player_units"][0]["class_id"] == "myrmidon")
	var wrong := _map([[0,9]])
	check("未知地形拒绝", not Definition.build(wrong)["ok"])
	wrong = _map([[0,0]])
	wrong["width"] = 3
	check("不完整矩阵拒绝", not Definition.build(wrong)["ok"])
	var isolated := Grid.new()
	isolated.initialize(_map([[0,1,2,3,4,5,6,7,8]]))
	for terrain: int in 9:
		var cell := isolated.get_cell(Vector2i(terrain,0))
		check("地形通行沿用现行Cell " + str(terrain), cell.is_passable() == (terrain not in [3,4,6]))


func _check_short_battle(maps_before: Dictionary) -> void:
	var session: Node2D = session_script.new()
	check("短地图可进入", session.configure_map(_map([[0,0,0],[0,0,0]]))["ok"])
	root.add_child(session)
	await frames(6)
	var manager: Object = session.manager
	var hero: Unit = manager.current_unit
	manager.request_end_turn()
	await create_timer(1.5).timeout
	check("结束回合后敌人按正式AI行动", hero.stats.hp < hero.stats.max_hp or manager.units[1].grid_position != Vector2i(2,1))
	await session._on_restart_pressed()
	await frames(4)
	session.manager.units[0].take_damage(session.manager.units[0].stats.hp + 1)
	await frames(5)
	check("战败界面保留返回编辑", session.battle.result_overlay.visible and session.battle.result_label.text == "战败")
	var returned: Array[bool] = [false]
	session.editing_resumed.connect(func() -> void: returned[0] = true)
	await click(session.battle.return_button.get_global_rect().get_center())
	check("战败结果按钮实际触发返回", returned[0] and not session.manager.battle_active)
	root.remove_child(session)
	session.free()
	session = session_script.new()
	session.configure_map(_map([[0,0,0],[0,0,0]]))
	root.add_child(session)
	await frames(4)
	session.manager.request_end_turn()
	root.remove_child(session)
	session.free()
	await create_timer(0.7).timeout
	check("敌方回合退出不污染地图", data_loader.maps == maps_before)
	# 覆盖敌人移动动画及移动后短暂停顿期间的退出。
	for elapsed: float in [0.35, 0.62]:
		session = session_script.new()
		session.configure_map(_map([[0,0,0],[0,0,0]]))
		root.add_child(session)
		await frames(6)
		session.manager.request_end_turn()
		await create_timer(elapsed).timeout
		root.remove_child(session)
		session.free()
		await create_timer(0.7).timeout
		check("敌人行动 %.2f 秒后退出无地图残留" % elapsed, data_loader.maps == maps_before)
	session = session_script.new()
	session.configure_map(_map([[0,0,0],[0,0,0]]))
	root.add_child(session)
	await frames(6)
	await click(_screen(session.manager.grid, Vector2i(1,0)))
	await create_timer(0.08).timeout
	root.remove_child(session)
	session.free()
	await create_timer(0.5).timeout
	check("玩家移动动画中退出无地图残留", data_loader.maps == maps_before)


func _map(rows: Array) -> Dictionary:
	# 最小合法地图为10×10，狭小连通区外以不可通行格封闭。
	var square: Array = []
	for y: int in 10:
		var row: Array[int] = []
		for x: int in 10:
			row.append(int(rows[y][x]) if y < rows.size() and x < rows[y].size() else Cell.Terrain.WALL)
		square.append(row)
	return {"width":10,"height":10,"terrain":square,"paving":[],"terrain_variants":{},
		"environment":"terrain_workshop","transition_preview":true}


func _same_terrain(grid: Grid, data: Dictionary) -> bool:
	if grid.width != int(data["width"]) or grid.height != int(data["height"]):
		return false
	for y: int in grid.height:
		for x: int in grid.width:
			if grid.get_cell(Vector2i(x,y)).terrain != int(data["terrain"][y][x]):
				return false
	return true


func _screen(grid: Grid, at: Vector2i) -> Vector2:
	return root.get_canvas_transform() * grid.grid_to_world(at)


func _move_pointer(at: Vector2) -> void:
	Input.warp_mouse(root.get_stretch_transform() * at)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)


func click(at: Vector2) -> void:
	_move_pointer(at)
	await frames(2)
	# 同一次点击直接送入正式视口；按下和释放之间不让系统鼠标事件误触发拖动。
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.global_position = at
		event.pressed = pressed
		root.push_input(event, true)
	await frames(2)


func frames(count: int) -> void:
	for step: int in count:
		await process_frame
