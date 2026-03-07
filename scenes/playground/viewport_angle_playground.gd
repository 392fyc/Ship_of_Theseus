extends Node2D
## Viewport Angle Comparison Playground
## F6 运行此场景可直接对比 A/B/C 三种地图视角方案。

const CELL_SIZE := 64
const SCHEME_GAP := 80

const MAP_WIDTH := 6
const MAP_HEIGHT := 6

const PANEL_TOP := 92.0
const PANEL_BOTTOM := 636.0
const PANEL_A_X := 12.0
const PANEL_B_X := PANEL_A_X + float(MAP_WIDTH * CELL_SIZE + SCHEME_GAP)
const PANEL_C_X := PANEL_B_X + float(MAP_WIDTH * CELL_SIZE + SCHEME_GAP)

const GRID_LINE_COLOR := Color(0.0, 0.0, 0.0, 0.18)
const BG_COLOR := Color(0.11, 0.11, 0.13)
const LABEL_COLOR := Color(0.82, 0.82, 0.88)
const SUBLABEL_COLOR := Color(0.62, 0.62, 0.70)
const PLAYER_COLOR := Color(0.19, 0.38, 0.75)
const ENEMY_COLOR := Color(0.75, 0.19, 0.19)

const OBLIQUE_TOP_HEIGHT := 48.0
const OBLIQUE_SIDE_HEIGHT := 16.0

const ISO_TILE_WIDTH := 56.0
const ISO_TILE_HEIGHT := 28.0
const ISO_TILE_DEPTH := 18.0
const ISO_GRID_ORIGIN := Vector2(PANEL_C_X + 168.0, PANEL_TOP + 82.0)

const T_GRASS := 0
const T_FOREST := 1
const T_MOUNTAIN := 2
const T_WATER := 3

const MAP_DATA: Array = [
	[0, 0, 1, 0, 0, 0],
	[0, 1, 1, 0, 0, 0],
	[0, 0, 0, 0, 2, 0],
	[0, 0, 3, 0, 0, 0],
	[0, 0, 3, 0, 1, 0],
	[0, 0, 0, 0, 0, 0],
]

const TERRAIN_COLORS := {
	T_GRASS: Color(0.29, 0.55, 0.25),
	T_FOREST: Color(0.18, 0.35, 0.12),
	T_MOUNTAIN: Color(0.55, 0.45, 0.33),
	T_WATER: Color(0.23, 0.49, 0.75),
}

const TOKENS: Array = [
	{
		"grid": Vector2i(1, 2),
		"color": PLAYER_COLOR,
		"label": "S",
	},
	{
		"grid": Vector2i(2, 4),
		"color": PLAYER_COLOR,
		"label": "A",
	},
	{
		"grid": Vector2i(4, 3),
		"color": ENEMY_COLOR,
		"label": "G",
	},
]


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-20.0, -20.0, 1320.0, 760.0), BG_COLOR)

	var font: Font = ThemeDB.fallback_font

	_draw_scheme_header(font, PANEL_A_X, "SCHEME A", "Pure Top-Down", "Flat square grid")
	_draw_scheme_header(font, PANEL_B_X, "SCHEME B", "Oblique 3/4 View", "Square grid + faux depth")
	_draw_scheme_header(font, PANEL_C_X, "SCHEME C", "Isometric", "Diamond grid projection")

	_draw_scheme_a(font)
	_draw_scheme_b(font)
	_draw_scheme_c(font)


func _draw_scheme_header(font: Font, panel_x: float, title: String, subtitle: String, footer: String) -> void:
	_draw_text(font, Vector2(panel_x, 28.0), title, 20, Color.WHITE)
	_draw_text(font, Vector2(panel_x, 52.0), subtitle, 16, LABEL_COLOR)
	_draw_text(font, Vector2(panel_x, PANEL_BOTTOM), footer, 13, SUBLABEL_COLOR)


func _draw_scheme_a(font: Font) -> void:
	for grid_y in range(MAP_HEIGHT):
		var row: Array = MAP_DATA[grid_y] as Array
		for grid_x in range(MAP_WIDTH):
			var terrain_id: int = row[grid_x] as int
			var terrain_color: Color = TERRAIN_COLORS[terrain_id] as Color
			var rect: Rect2 = Rect2(
				PANEL_A_X + float(grid_x * CELL_SIZE),
				PANEL_TOP + float(grid_y * CELL_SIZE),
				float(CELL_SIZE),
				float(CELL_SIZE)
			)

			draw_rect(rect, terrain_color)
			draw_rect(rect, GRID_LINE_COLOR, false, 1.0)

	for token_data in TOKENS:
		var token_grid: Vector2i = token_data["grid"] as Vector2i
		var token_center: Vector2 = Vector2(
			PANEL_A_X + (float(token_grid.x) + 0.5) * float(CELL_SIZE),
			PANEL_TOP + (float(token_grid.y) + 0.5) * float(CELL_SIZE)
		)
		var token_color: Color = token_data["color"] as Color
		var token_label: String = token_data["label"] as String

		draw_circle(token_center + Vector2(0.0, 2.0), 18.0, Color(0.0, 0.0, 0.0, 0.30))
		draw_circle(token_center, 16.0, token_color)
		_draw_centered_text(font, token_center, token_label, 16, Color.WHITE)


func _draw_scheme_b(font: Font) -> void:
	for grid_y in range(MAP_HEIGHT):
		var row: Array = MAP_DATA[grid_y] as Array
		for grid_x in range(MAP_WIDTH):
			var terrain_id: int = row[grid_x] as int
			var terrain_color: Color = TERRAIN_COLORS[terrain_id] as Color
			var side_color: Color = _darken(terrain_color, 0.70)
			var cell_origin: Vector2 = Vector2(
				PANEL_B_X + float(grid_x * CELL_SIZE),
				PANEL_TOP + float(grid_y * CELL_SIZE)
			)

			var top_face: PackedVector2Array = PackedVector2Array([
				cell_origin,
				cell_origin + Vector2(float(CELL_SIZE), 0.0),
				cell_origin + Vector2(float(CELL_SIZE) - 4.0, OBLIQUE_TOP_HEIGHT),
				cell_origin + Vector2(4.0, OBLIQUE_TOP_HEIGHT),
			])
			var front_face: PackedVector2Array = PackedVector2Array([
				cell_origin + Vector2(4.0, OBLIQUE_TOP_HEIGHT),
				cell_origin + Vector2(float(CELL_SIZE) - 4.0, OBLIQUE_TOP_HEIGHT),
				cell_origin + Vector2(float(CELL_SIZE), OBLIQUE_TOP_HEIGHT + OBLIQUE_SIDE_HEIGHT),
				cell_origin + Vector2(0.0, OBLIQUE_TOP_HEIGHT + OBLIQUE_SIDE_HEIGHT),
			])

			_draw_filled_polygon(top_face, terrain_color)
			_draw_filled_polygon(front_face, side_color)
			_draw_polygon_outline(top_face, GRID_LINE_COLOR, 1.0)
			_draw_polygon_outline(front_face, GRID_LINE_COLOR, 1.0)
			_draw_oblique_terrain_detail(terrain_id, terrain_color, cell_origin)

	for token_data in TOKENS:
		var token_grid: Vector2i = token_data["grid"] as Vector2i
		var token_center: Vector2 = Vector2(
			PANEL_B_X + (float(token_grid.x) + 0.5) * float(CELL_SIZE),
			PANEL_TOP + float(token_grid.y * CELL_SIZE) + 28.0
		)
		var token_color: Color = token_data["color"] as Color
		var token_label: String = token_data["label"] as String
		var shadow_points: PackedVector2Array = _make_ellipse_points(token_center + Vector2(0.0, 12.0), 16.0, 7.0, 20)
		var token_points: PackedVector2Array = _make_ellipse_points(token_center, 16.0, 13.0, 20)

		_draw_filled_polygon(shadow_points, Color(0.0, 0.0, 0.0, 0.24))
		_draw_filled_polygon(token_points, token_color)
		_draw_polygon_outline(token_points, Color(0.0, 0.0, 0.0, 0.35), 1.0)
		_draw_centered_text(font, token_center, token_label, 16, Color.WHITE)


func _draw_scheme_c(font: Font) -> void:
	for sum_index in range(MAP_WIDTH + MAP_HEIGHT - 1):
		for grid_x in range(MAP_WIDTH):
			var grid_y: int = sum_index - grid_x
			if grid_y < 0 or grid_y >= MAP_HEIGHT:
				continue

			var row: Array = MAP_DATA[grid_y] as Array
			var terrain_id: int = row[grid_x] as int
			var terrain_color: Color = TERRAIN_COLORS[terrain_id] as Color
			var top_center: Vector2 = _iso_top_center(Vector2i(grid_x, grid_y))
			var top_face: PackedVector2Array = PackedVector2Array([
				top_center + Vector2(0.0, -ISO_TILE_HEIGHT * 0.5),
				top_center + Vector2(ISO_TILE_WIDTH * 0.5, 0.0),
				top_center + Vector2(0.0, ISO_TILE_HEIGHT * 0.5),
				top_center + Vector2(-ISO_TILE_WIDTH * 0.5, 0.0),
			])
			var left_face: PackedVector2Array = PackedVector2Array([
				top_face[3],
				top_face[2],
				top_face[2] + Vector2(0.0, ISO_TILE_DEPTH),
				top_face[3] + Vector2(0.0, ISO_TILE_DEPTH),
			])
			var right_face: PackedVector2Array = PackedVector2Array([
				top_face[2],
				top_face[1],
				top_face[1] + Vector2(0.0, ISO_TILE_DEPTH),
				top_face[2] + Vector2(0.0, ISO_TILE_DEPTH),
			])

			_draw_filled_polygon(left_face, _darken(terrain_color, 0.80))
			_draw_filled_polygon(right_face, _darken(terrain_color, 0.60))
			_draw_filled_polygon(top_face, terrain_color)
			_draw_polygon_outline(left_face, GRID_LINE_COLOR, 1.0)
			_draw_polygon_outline(right_face, GRID_LINE_COLOR, 1.0)
			_draw_polygon_outline(top_face, GRID_LINE_COLOR, 1.0)
			_draw_isometric_terrain_detail(terrain_id, top_center)

	for token_data in TOKENS:
		var token_grid: Vector2i = token_data["grid"] as Vector2i
		var token_center: Vector2 = _iso_top_center(token_grid) + Vector2(0.0, -4.0)
		var token_color: Color = token_data["color"] as Color
		var token_label: String = token_data["label"] as String
		var token_shape: PackedVector2Array = PackedVector2Array([
			token_center + Vector2(0.0, -18.0),
			token_center + Vector2(18.0, 0.0),
			token_center + Vector2(0.0, 18.0),
			token_center + Vector2(-18.0, 0.0),
		])

		draw_circle(token_center + Vector2(0.0, 12.0), 12.0, Color(0.0, 0.0, 0.0, 0.18))
		_draw_filled_polygon(token_shape, token_color)
		_draw_polygon_outline(token_shape, Color(0.0, 0.0, 0.0, 0.35), 1.0)
		_draw_centered_text(font, token_center, token_label, 16, Color.WHITE)


func _draw_oblique_terrain_detail(terrain_id: int, terrain_color: Color, cell_origin: Vector2) -> void:
	match terrain_id:
		T_GRASS:
			draw_line(
				cell_origin + Vector2(10.0, 18.0),
				cell_origin + Vector2(54.0, 14.0),
				_lighten(terrain_color, 1.18),
				2.0
			)
		T_FOREST:
			draw_rect(Rect2(cell_origin + Vector2(28.0, 24.0), Vector2(8.0, 14.0)), Color(0.26, 0.16, 0.08))
			draw_circle(cell_origin + Vector2(26.0, 22.0), 10.0, _lighten(terrain_color, 1.12))
			draw_circle(cell_origin + Vector2(38.0, 20.0), 12.0, _lighten(terrain_color, 1.06))
		T_MOUNTAIN:
			var mountain_points: PackedVector2Array = PackedVector2Array([
				cell_origin + Vector2(18.0, 34.0),
				cell_origin + Vector2(32.0, 12.0),
				cell_origin + Vector2(48.0, 34.0),
			])
			_draw_filled_polygon(mountain_points, _lighten(terrain_color, 1.14))
			draw_line(cell_origin + Vector2(32.0, 12.0), cell_origin + Vector2(32.0, 34.0), _darken(terrain_color, 0.72), 1.0)
		T_WATER:
			draw_line(cell_origin + Vector2(14.0, 20.0), cell_origin + Vector2(50.0, 20.0), _lighten(terrain_color, 1.18), 2.0)
			draw_line(cell_origin + Vector2(18.0, 30.0), cell_origin + Vector2(46.0, 30.0), _lighten(terrain_color, 1.10), 2.0)


func _draw_isometric_terrain_detail(terrain_id: int, top_center: Vector2) -> void:
	var detail_color: Color = Color(1.0, 1.0, 1.0, 0.20)
	match terrain_id:
		T_GRASS:
			draw_line(top_center + Vector2(-8.0, -3.0), top_center + Vector2(6.0, -7.0), detail_color, 1.5)
		T_FOREST:
			draw_circle(top_center + Vector2(-4.0, -6.0), 4.0, Color(0.14, 0.28, 0.10, 0.85))
			draw_circle(top_center + Vector2(4.0, -4.0), 5.0, Color(0.17, 0.33, 0.12, 0.88))
		T_MOUNTAIN:
			var ridge_points: PackedVector2Array = PackedVector2Array([
				top_center + Vector2(-6.0, 4.0),
				top_center + Vector2(0.0, -8.0),
				top_center + Vector2(8.0, 4.0),
			])
			_draw_filled_polygon(ridge_points, Color(0.75, 0.68, 0.58, 0.80))
		T_WATER:
			draw_line(top_center + Vector2(-10.0, -1.0), top_center + Vector2(0.0, -5.0), detail_color, 1.5)
			draw_line(top_center + Vector2(-4.0, 5.0), top_center + Vector2(8.0, 1.0), detail_color, 1.5)


func _iso_top_center(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		(float(grid_pos.x) - float(grid_pos.y)) * ISO_TILE_WIDTH * 0.5,
		(float(grid_pos.x) + float(grid_pos.y)) * ISO_TILE_HEIGHT * 0.5
	) + ISO_GRID_ORIGIN


func _make_ellipse_points(center: Vector2, radius_x: float, radius_y: float, segments: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()

	for index in range(segments):
		var angle: float = TAU * float(index) / float(segments)
		points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))

	return points


func _draw_filled_polygon(points: PackedVector2Array, color: Color) -> void:
	var colors: PackedColorArray = PackedColorArray()

	for _index in range(points.size()):
		colors.append(color)

	draw_polygon(points, colors)


func _draw_polygon_outline(points: PackedVector2Array, color: Color, width: float) -> void:
	for index in range(points.size()):
		var next_index: int = (index + 1) % points.size()
		draw_line(points[index], points[next_index], color, width)


func _draw_centered_text(font: Font, center: Vector2, text: String, size: int, color: Color) -> void:
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var text_pos: Vector2 = center + Vector2(-text_size.x * 0.5, text_size.y * 0.35)
	_draw_text(font, text_pos, text, size, color)


func _draw_text(font: Font, pos: Vector2, text: String, size: int, color: Color) -> void:
	draw_string(font, pos + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.0, 0.0, 0.0, 0.6))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _darken(color: Color, factor: float) -> Color:
	return Color(color.r * factor, color.g * factor, color.b * factor, color.a)


func _lighten(color: Color, factor: float) -> Color:
	return Color(
		min(color.r * factor, 1.0),
		min(color.g * factor, 1.0),
		min(color.b * factor, 1.0),
		color.a
	)
