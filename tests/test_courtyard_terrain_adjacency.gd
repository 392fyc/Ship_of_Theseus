extends SceneTree
## 仅用于固定像素几何的单元测试，不代表运行配置；截图仅作诊断，不得作为视觉验收证据。

const CaptureMetadata := preload("res://tests/claude_review/capture_metadata.gd")
const BoardView := preload("res://scripts/ui/playground/courtyard_board_view.gd")
const PROFILE_PATH := "res://assets/prototype/battlefield_courtyard/visual_profile.json"
const LAYOUTS_PATH := "res://assets/prototype/battlefield_courtyard/courtyard_layouts.json"
const WATER_CONTRACT_PATH := "res://dev_doc/ui-art-research/visual-review/water-depth-continuity-contract.json"
const CENTER := Vector2i(1, 1)
const DEPTH_TRANSITION_ROWS: Array = [
	[5,5,5,5,5,5,5], [5,5,6,6,6,5,5], [5,6,6,6,6,6,5],
	[5,6,6,6,6,5,5], [5,6,6,6,6,6,5], [5,5,6,6,6,5,5], [5,5,5,5,5,5,5],
]

var _passed: int = 0
var _failed: int = 0
var _output: String = ""
var _profile: Dictionary
var _panels: Array[Dictionary] = []
var _capture_records: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, success: bool) -> void:
	if success:
		_passed += 1
	else:
		_failed += 1
	print("[%s] %s" % ["PASS" if success else "FAIL", label])


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 760)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			_output = arg.trim_prefix("--output=")
	_profile = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	var background := ColorRect.new()
	background.color = Color("161c20")
	background.size = Vector2(1280, 760)
	root.add_child(background)
	_label("相邻地形决定边缘与连接", Vector2(24, 18), 28)
	_label("岸线与墙体检查邻接；水深展示多格连通水域和连续渐变。", Vector2(24, 62), 18)
	var water_contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WATER_CONTRACT_PATH))
	var fixtures: Array[Dictionary] = [
		{"name": "浅水接草地：湿土岸", "rows": [[0,0,0],[0,5,0],[0,0,0]], "paved": false},
		{"name": "浅水接石地：石砌岸", "rows": [[0,0,0],[0,5,0],[0,0,0]], "paved": true},
		{"name": "连续水域：外围浅水渐入深水", "rows": DEPTH_TRANSITION_ROWS, "paved": false},
		{"name": "墙接草地：覆土墙脚", "rows": [[0,0,0],[0,4,0],[0,0,0]], "paved": false},
		{"name": "墙接墙：连续墙段与石基", "rows": [[0,0,0],[4,4,4],[0,0,0]], "paved": true},
		{"name": "墙体转角：连接臂与林地墙脚", "rows": [[0,0,0],[1,4,4],[1,4,0]], "paved": false},
	]
	for i: int in fixtures.size():
		_panels.append(_make_panel(fixtures[i], i))
	await _frames(3)
	_check("浅水面对草地只生成湿土岸", _kinds(_panels[0]["view"]).count("earth_bank") == 4)
	_check("同一浅水面对铺石地生成石砌岸", _kinds(_panels[1]["view"]).count("stone_bank") == 4)
	_check("水深展示与独立多格水域规格一致",
		_matrix_matches(fixtures[2]["rows"], water_contract["basin_fixture"]["terrain_rows"])
		and _panels[2]["grid"].get_cell(Vector2i(3, 3)).terrain == Cell.Terrain.DEEP_WATER)
	_check("水域内全部浅深交界保留过渡语义且不生成陆地岸沿",
		_depth_boundaries_match(_panels[2]["view"], _panels[2]["grid"]))
	_check("直墙连接左右相邻墙格", _panels[4]["view"].wall_connection_mask(CENTER) == 10)
	_check("墙角连接右方与下方墙格", _panels[5]["view"].wall_connection_mask(CENTER) == 6)
	var changed_grid: Grid = _panels[3]["grid"]
	var changed_view: Node2D = _panels[3]["view"]
	var before_count: int = _wall_count(changed_view)
	changed_grid.get_cell(Vector2i(2, 1)).terrain = Cell.Terrain.WALL
	changed_view.refresh_terrain_visuals()
	await _frames(3)
	_check("更换邻地后刷新实际墙体物件，中心地形保持不变",
		_wall_count(changed_view) == before_count + 1
		and changed_grid.get_cell(CENTER).terrain == Cell.Terrain.WALL
		and changed_view.wall_connection_mask(CENTER) == 2)
	changed_grid.get_cell(Vector2i(2, 1)).terrain = Cell.Terrain.PLAIN
	changed_view.refresh_terrain_visuals()
	await _frames(3)
	_check("移除邻墙后端头恢复，旧物件被释放", _wall_count(changed_view) == before_count
		and changed_view.wall_connection_mask(CENTER) == 0)
	_check_scene_boundaries()
	if not _output.is_empty() and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(_output)
		await _frames(8)
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		var image_path: String = _output.path_join("terrain-adjacency.png")
		var saved: bool = image.save_png(image_path) == OK
		_check("保存邻接诊断图", saved)
		if saved:
			_capture_records.append(CaptureMetadata.capture_record(root, image, image_path, {
				"capture_kind": "diagnostic", "runtime_evidence": false,
				"diagnostic_purpose": "fixed-pixel terrain adjacency contract",
			}))
		var source_fields: Dictionary = {"runtime_evidence": false,
			"diagnostic_purpose": "fixed-pixel terrain adjacency contract"}
		if not CaptureMetadata.write_manifest(root, _output.path_join("capture-metadata.json"), _capture_records, source_fields):
			_check("写入诊断元数据清单", false)
	print("COURTYARD_ADJACENCY_RESULT ", JSON.stringify({"passed": _passed, "failed": _failed}))
	quit(1 if _failed > 0 else 0)


func _make_panel(fixture: Dictionary, index: int) -> Dictionary:
	var origin := Vector2(24 + (index % 3) * 416, 108 + (index / 3) * 300)
	var panel := ColorRect.new()
	panel.position = origin
	panel.size = Vector2(400, 282)
	panel.color = Color("303b3d")
	root.add_child(panel)
	_label(str(fixture["name"]), origin + Vector2(12, 9), 18)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400, 240)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var image := TextureRect.new()
	image.position = origin + Vector2(0, 42)
	image.size = Vector2(400, 240)
	image.texture = viewport.get_texture()
	root.add_child(image)
	var rows: Array = fixture["rows"]
	var width: int = rows[0].size()
	var height: int = rows.size()
	var data: Dictionary = {"id": "adjacency_preview", "width": width, "height": height,
		"terrain": fixture["rows"], "transition_preview": true, "paving": []}
	if fixture["paved"]:
		for y: int in 3:
			for x: int in 3:
				data["paving"].append([x, y])
	var grid := Grid.new()
	grid.initialize(data)
	var view := BoardView.new()
	view.configure(grid, _profile, data)
	view.grid_visible = false
	var zoom: float = minf(1.45, 370.0 / float((width + height) * 32))
	view.scale = Vector2.ONE * zoom
	var center := Vector2i(floori(float(width - 1) * 0.5), floori(float(height - 1) * 0.5))
	view.position = Vector2(200, 138) - grid.grid_to_world(center) * zoom
	viewport.add_child(view)
	return {"view": view, "grid": grid}


func _check_scene_boundaries() -> void:
	var layouts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUTS_PATH))
	var grid := Grid.new()
	grid.initialize(layouts["flooded"])
	var view := BoardView.new()
	view.configure(grid, _profile, layouts["flooded"])
	var aligned: bool = true
	for x: int in grid.width:
		for row: int in [0, grid.height - 1]:
			var outside_y: int = -1 if row == 0 else grid.height
			var inside: int = grid.get_cell(Vector2i(x, row)).terrain
			var outside: int = view.visual_terrain_at(Vector2i(x, outside_y))
			if inside in [Cell.Terrain.SHALLOW_WATER, Cell.Terrain.DEEP_WATER]:
				aligned = aligned and outside == inside
			else:
				aligned = aligned and outside not in [Cell.Terrain.SHALLOW_WATER, Cell.Terrain.DEEP_WATER]
	_check("河道两个出口逐列保持宽度与深浅地形一致", aligned)
	view.free()
	grid.initialize(layouts["passage"])
	view = BoardView.new()
	view.configure(grid, _profile, layouts["passage"])
	var connected: bool = true
	for y: int in grid.height:
		for x: int in grid.width:
			if grid.get_cell(Vector2i(x, y)).terrain == Cell.Terrain.WALL:
				connected = connected and view.wall_connection_mask(Vector2i(x, y)) != 0
	_check("回廊场内墙格连接建筑中的其他墙段", connected)
	var shared_heights: bool = true
	for cell: Vector2i in view._architecture_walls:
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var other: Vector2i = cell + direction
			if view.visual_terrain_at(other) != Cell.Terrain.WALL:
				continue
			var other_points: PackedVector2Array = view.wall_footprint(other)
			for vertex: Vector2 in view.wall_footprint(cell):
				if other_points.has(vertex):
					shared_heights = shared_heights and is_equal_approx(
						view._wall_vertex_height(cell, vertex), view._wall_vertex_height(other, vertex))
	_check("相接墙段的共用端点高度一致，不因段高不同留出裂口", shared_heights)
	view.free()
	for id: String in ["flooded", "overgrown"]:
		grid.initialize(layouts[id])
		view = BoardView.new()
		view.configure(grid, _profile, layouts[id])
		var corner := Vector2i(-4, -5) if id == "flooded" else Vector2i(-4, -3)
		_check(id + " 场外墙体使用同一邻接规则形成转角或分叉",
			view.wall_connection_mask(corner) == (6 if id == "flooded" else 14))
		view.free()


func _kinds(view: Node2D) -> Array[String]:
	var kinds: Array[String] = []
	for edge: Dictionary in view.transition_edges(CENTER):
		kinds.append(str(edge["kind"]))
	return kinds


func _wall_count(view: Node2D) -> int:
	var count := 0
	for child: Node in view._actor_layer.get_children():
		if child.get_meta("terrain_wall", false):
			count += 1
	return count


func _depth_boundaries_match(view: Node2D, grid: Grid) -> bool:
	var count: int = 0
	for y: int in grid.height:
		for x: int in grid.width:
			var cell := Vector2i(x, y)
			if grid.get_cell(cell).terrain != Cell.Terrain.SHALLOW_WATER:
				continue
			for edge: Dictionary in view.transition_edges(cell):
				var neighbor: Vector2i = edge["neighbor"]
				if grid.is_valid(neighbor) and grid.get_cell(neighbor).terrain == Cell.Terrain.DEEP_WATER:
					count += 1
					if edge["kind"] != "depth_blend":
						return false
	return count > 0


func _matrix_matches(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for y: int in left.size():
		var left_row: Array = left[y]
		var right_row: Array = right[y]
		if left_row.size() != right_row.size():
			return false
		for x: int in left_row.size():
			if int(left_row[x]) != int(right_row[x]):
				return false
	return true


func _label(value: String, location: Vector2, size: int) -> void:
	var label := Label.new()
	label.theme = load("res://assets/ui/themes/hud_m2.tres") as Theme
	label.text = value
	label.position = location
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("e4dfc9"))
	root.add_child(label)


func _frames(count: int) -> void:
	for unused: int in count:
		await process_frame
