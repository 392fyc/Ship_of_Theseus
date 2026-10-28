extends SceneTree
## Structural adjacency/ownership checks; original-size scene review remains required.
const Board := preload("res://scripts/ui/playground/courtyard_board_view.gd")
const STYLE := "res://assets/prototype/character_pipeline/portrait_token_style.json"
const OFFSETS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
var checks: int = 0
var failures: Array[String] = []

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures.append(label)
	print("[", "PASS" if ok else "FAIL", "] ", label)

func make_board(cells: Array[Vector2i]) -> Node2D:
	var value := Grid.new()
	value.initialize({"width": 5, "height": 5})
	for cell: Vector2i in cells:
		value.get_cell(cell).terrain = Cell.Terrain.FOREST
	var board := Board.new()
	board.grid = value
	board.profile = {"portrait_tree_presentation": JSON.parse_string(FileAccess.get_file_as_string(STYLE))["tree_presentation"]}
	return board

func _initialize() -> void:
	var center := Vector2i(2, 2)
	var cases: Dictionary = {"isolated": 0, "end": 1, "straight": 5,
		"corner": 3, "branch": 11, "solid": 15}
	var plans: Dictionary = {}
	for label: String in cases:
		var cells: Array[Vector2i] = [center]
		for edge: int in 4:
			if int(cases[label]) & (1 << edge):
				cells.append(center + OFFSETS[edge])
		var board := make_board(cells)
		check(label + " orthogonal mask", board.portrait_forest_connection_mask(center) == cases[label])
		plans[label] = board.portrait_forest_patches(center)
		board.free()
	check("dense canopy replaces point-sprite arrangements", plans.corner.is_empty() and plans.straight.is_empty() and plans.solid.is_empty())
	var diagonal := make_board([center, center + Vector2i(-1, -1), center + Vector2i(1, 1)])
	check("diagonal-only cells do not connect", diagonal.portrait_forest_connection_mask(center) == 0)
	diagonal.free()
	for mask: int in 16:
		var cells: Array[Vector2i] = [center]
		for edge: int in 4:
			if mask & (1 << edge):
				cells.append(center + OFFSETS[edge])
		var board := make_board(cells)
		var floor_points: PackedVector2Array = board.portrait_forest_floor(center)
		var origin: Vector2 = board.point(center.x, center.y)
		var within: bool = true
		for vertex: Vector2 in floor_points:
			var local: Vector2 = vertex - origin
			if absf(local.x) / 32.0 + absf(local.y) / 16.0 > 1.0:
				var distance: float = INF
				var diamond: PackedVector2Array = board.diamond(center)
				for line_edge: int in 4:
					distance = minf(distance, vertex.distance_to(Geometry2D.get_closest_point_to_segment(vertex, diamond[line_edge], diamond[(line_edge + 1) % 4])))
				within = within and distance <= 2.600001
		check("mask%d leaf tips limited to the configured small fringe" % mask, within)
		for edge: int in 4:
			if not (mask & (1 << edge)):
				continue
			var neighbor: Vector2i = center + OFFSETS[edge]
			var shared: PackedVector2Array = board.diamond(center)
			var other: PackedVector2Array = board.portrait_forest_floor(neighbor)
			check("mask%d edge%d exact shared floor endpoints" % [mask, edge],
				floor_points.has(shared[edge]) and floor_points.has(shared[(edge + 1) % 4])
				and other.has(shared[edge]) and other.has(shared[(edge + 1) % 4]))
			var depth: Vector2 = board.portrait_forest_region_depth(center)
			var other_depth: Vector2 = board.portrait_forest_region_depth(neighbor)
			check("mask%d edge%d shared raised surface has identical height" % [mask, edge],
				is_equal_approx(board.portrait_forest_canopy_rise(shared[edge], depth), board.portrait_forest_canopy_rise(shared[edge], other_depth)))
		board.free()
	for mask: int in 16:
		var cells: Array[Vector2i] = [center]
		for edge: int in 4:
			if mask & (1 << edge):
				cells.append(center + OFFSETS[edge])
		var board := make_board(cells)
		var patches: Array = board.portrait_forest_patches(center)
		check("mask%d no old high shrub point sprites in dense-canopy mode" % mask, patches.is_empty())
		board.free()
	print("CONNECTED_SHRUB_RESULT=", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
