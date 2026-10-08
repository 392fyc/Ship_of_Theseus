extends Node2D
## Synchronized mask drawing for the formal board's procedural grid and
## wall-footing contact shadow commands. Coordinates come from the live board.

const CELL_SCRIPT := preload("res://scripts/core/cell.gd")

var _mode := ""
var _board: Node2D
var _mask_color := Color.WHITE


func configure(mode: String, board: Node2D, mask_color: Color) -> void:
	_mode = mode
	_board = board
	_mask_color = mask_color
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(_board):
		return
	match _mode:
		"grid":
			_draw_grid()
		"contact_shadow":
			_draw_contact_shadows()
		"ground_with_footings":
			_draw_wall_footings(true)
		"ground_without_shadow":
			_draw_wall_footings(false)
		"ground_types":
			_draw_ground_types()


func _draw_grid() -> void:
	var grid: Variant = _board.get("grid")
	if grid == null or not bool(_board.get("grid_visible")):
		return
	for y: int in grid.height:
		for x: int in grid.width:
			var cell := Vector2i(x, y)
			var points: PackedVector2Array = _board.call("diamond", cell)
			var closed := points.duplicate()
			closed.append(points[0])
			draw_polyline(closed, _mask_color, 0.55, true)
	var low: float = -0.5
	var high_x: float = float(grid.width) - 0.5
	var high_y: float = float(grid.height) - 0.5
	var boundary := PackedVector2Array([
		_board.call("point", low, low),
		_board.call("point", high_x, low),
		_board.call("point", high_x, high_y),
		_board.call("point", low, high_y),
	])
	boundary.append(boundary[0])
	draw_polyline(boundary, _mask_color, 0.7, true)
	for y: int in grid.height:
		for x: int in grid.width:
			var cell := Vector2i(x, y)
			if grid.get_cell(cell).terrain in [CELL_SCRIPT.Terrain.WALL, CELL_SCRIPT.Terrain.PEAK, CELL_SCRIPT.Terrain.DEEP_WATER]:
				var corners: PackedVector2Array = _board.call("diamond", cell, 2.0)
				for index: int in 4:
					var corner: Vector2 = corners[index]
					var previous: Vector2 = corners[(index + 3) % 4]
					var next: Vector2 = corners[(index + 1) % 4]
					draw_polyline(PackedVector2Array([corner.lerp(previous, 0.17), corner,
						corner.lerp(next, 0.17)]), _mask_color, 1.0, true)


func _draw_contact_shadows() -> void:
	var cells: Array = _board.call("_wall_render_cells")
	for cell_value: Variant in cells:
		var cell: Vector2i = cell_value
		var center: Vector2 = _board.call("point", cell.x, cell.y)
		var footprint: PackedVector2Array = _board.call("wall_footprint", cell)
		var shadow := PackedVector2Array()
		for point: Vector2 in footprint:
			shadow.append(center + (point - center) * 1.28 + Vector2(1.5, 2.0))
		draw_colored_polygon(shadow, _mask_color)


func _draw_wall_footings(include_shadow: bool) -> void:
	var cells: Array = _board.call("_wall_render_cells")
	for cell_value: Variant in cells:
		var cell: Vector2i = cell_value
		var center: Vector2 = _board.call("point", cell.x, cell.y)
		var base: PackedVector2Array = _board.call("wall_footprint", cell)
		var texture: Texture2D = _board.get("_ground") as Texture2D
		var tint := Color("92957b")
		for transition: Dictionary in _board.call("transition_edges", cell):
			if transition["kind"] == "wet_wall_foot":
				tint = Color("63786e")
				break
			if transition["kind"] in ["rooted_wall_foot", "soil_wall_foot"]:
				texture = _board.get("_moss") as Texture2D
				tint = Color("8c916c")
				break
		var apron := PackedVector2Array()
		var shadow := PackedVector2Array()
		for point: Vector2 in base:
			apron.append(center + (point - center) * 1.18)
			shadow.append(center + (point - center) * 1.28 + Vector2(1.5, 2.0))
		if include_shadow:
			draw_colored_polygon(shadow, Color("18201638"))
		tint.a = 0.42
		_board.call("_textured_ground_polygon", apron, texture, tint, self)


func _draw_ground_types() -> void:
	var grid: Variant = _board.get("grid")
	if grid == null:
		return
	for y: int in grid.height:
		for x: int in grid.width:
			var cell := Vector2i(x, y)
			var terrain: int = grid.get_cell(cell).terrain
			var color: Color = CaptureColors.terrain_color(terrain)
			if bool(_board.call("_is_paved_at", cell)):
				color = Color(1.0, 0.5, 0.0, 1.0)
			var points: PackedVector2Array = _board.call("diamond", cell)
			draw_colored_polygon(points, color)


class CaptureColors:
	static func terrain_color(terrain: int) -> Color:
		match terrain:
			CELL_SCRIPT.Terrain.PLAIN:
				return Color(0.0, 1.0, 0.0, 1.0)
			CELL_SCRIPT.Terrain.FOREST:
				return Color(0.0, 0.5, 0.0, 1.0)
			CELL_SCRIPT.Terrain.MOUNTAIN:
				return Color(0.6, 0.4, 0.0, 1.0)
			CELL_SCRIPT.Terrain.PEAK:
				return Color(1.0, 0.0, 0.0, 1.0)
			CELL_SCRIPT.Terrain.WALL:
				return Color(0.5, 0.5, 0.5, 1.0)
			CELL_SCRIPT.Terrain.SHALLOW_WATER:
				return Color(0.0, 1.0, 1.0, 1.0)
			CELL_SCRIPT.Terrain.DEEP_WATER:
				return Color(0.0, 0.0, 0.5, 1.0)
			CELL_SCRIPT.Terrain.LAVA:
				return Color(0.72, 0.25, 0.0, 1.0)
			CELL_SCRIPT.Terrain.SWAMP:
				return Color(0.5, 0.0, 1.0, 1.0)
			_:
				return Color(1.0, 1.0, 1.0, 1.0)
