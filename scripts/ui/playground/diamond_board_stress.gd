extends Control

const GRID_SIZE: Vector2i = Vector2i(20, 20)
const TILE_SIZE: Vector2i = Vector2i(64, 32)
const BOARD_ORIGIN: Vector2 = Vector2(640.0, 96.0)

const TILE_COLOR_A: Color = Color(0.105, 0.125, 0.14, 1.0)
const TILE_COLOR_B: Color = Color(0.075, 0.09, 0.105, 1.0)
const GRID_COLOR: Color = Color(0.31, 0.34, 0.35, 0.72)

var _drawn_tile_count: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	_drawn_tile_count = 0
	for row: int in GRID_SIZE.y:
		for column: int in GRID_SIZE.x:
			var center: Vector2 = get_tile_center(column, row)
			var corners := PackedVector2Array([
				center + Vector2(0.0, -16.0),
				center + Vector2(32.0, 0.0),
				center + Vector2(0.0, 16.0),
				center + Vector2(-32.0, 0.0),
			])
			var fill: Color = TILE_COLOR_A if (column + row) % 2 == 0 else TILE_COLOR_B
			draw_colored_polygon(corners, fill)
			var outline := PackedVector2Array([corners[0], corners[1], corners[2],
				corners[3], corners[0]])
			draw_polyline(outline, GRID_COLOR, 1.0, false)
			_drawn_tile_count += 1


func get_grid_size() -> Vector2i:
	return GRID_SIZE


func get_tile_size() -> Vector2i:
	return TILE_SIZE


func get_drawn_tile_count() -> int:
	return _drawn_tile_count


func get_tile_center(column: int, row: int) -> Vector2:
	return BOARD_ORIGIN + Vector2(
		float(column - row) * float(TILE_SIZE.x) * 0.5,
		float(column + row) * float(TILE_SIZE.y) * 0.5)


func get_board_bounds() -> Rect2:
	return Rect2(0.0, 80.0, 1280.0, 640.0)
