extends Node2D
## Viewport Angle Static Mockup
## 使用等身人物参考图，静态比较 B1(伪3/4) 与 C(等距) 两种视角。

const BG_COLOR := Color(0.11, 0.11, 0.13)
const GRID_LINE_COLOR := Color(0.0, 0.0, 0.0, 0.18)
const PANEL_STROKE := Color(1.0, 1.0, 1.0, 0.10)
const TITLE_COLOR := Color.WHITE
const SUBTITLE_COLOR := Color(0.82, 0.82, 0.88)
const NOTE_COLOR := Color(0.60, 0.63, 0.70)
const PLAYER_RING_COLOR := Color(0.19, 0.38, 0.75, 0.92)
const ENEMY_RING_COLOR := Color(0.75, 0.19, 0.19, 0.92)

const MAP_WIDTH := 6
const MAP_HEIGHT := 6

const PANEL_TOP := 88.0
const PANEL_HEIGHT := 548.0
const PANEL_WIDTH := 1136.0
const PANEL_MAIN_X := 72.0

const B1_CELL_WIDTH := 64.0
const B1_TOP_HEIGHT := 28.0
const B1_SIDE_HEIGHT := 18.0
const B1_COL_PITCH := 64.0
const B1_ROW_PITCH := 38.0
const B1_GRID_ORIGIN := Vector2(PANEL_MAIN_X + 52.0, PANEL_TOP + 106.0)

const ISO_TILE_WIDTH := 84.0
const ISO_TILE_HEIGHT := 42.0
const ISO_TILE_DEPTH := 24.0
const ISO_GRID_ORIGIN := Vector2(PANEL_MAIN_X + 560.0, PANEL_TOP + 122.0)

const T_GRASS := 0
const T_FOREST := 1
const T_MOUNTAIN := 2
const T_WATER := 3

const REFERENCE_SPRITE_PATH := "C:/Users/392fy/.cursor/projects/d-ShipOfTheseus-Ship-of-Theseus/assets/c__Users_392fy_AppData_Roaming_Cursor_User_workspaceStorage_587fee967f3b867beeb7f021a30164a6_images_image-5d22e967-9dd4-4053-926a-5eb16a51c435.png"

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

const TOKEN_DATA: Array = [
	{
		"grid": Vector2i(1, 2),
		"label": "S",
		"ring": PLAYER_RING_COLOR,
		"modulate": Color(1.0, 1.0, 1.0),
		"sprite_index": 0,
	},
	{
		"grid": Vector2i(2, 4),
		"label": "A",
		"ring": PLAYER_RING_COLOR,
		"modulate": Color(0.96, 0.98, 1.0),
		"sprite_index": 1,
	},
	{
		"grid": Vector2i(4, 3),
		"label": "G",
		"ring": ENEMY_RING_COLOR,
		"modulate": Color(1.0, 0.92, 0.92),
		"sprite_index": 2,
	},
]
const B1_SPRITE_SIZE := Vector2(46.0, 84.0)
const ISO_SPRITE_SIZE := Vector2(50.0, 92.0)
const B1_SPRITE_OFFSET := Vector2(0.0, -30.0)
const ISO_SPRITE_OFFSET := Vector2(0.0, -28.0)
const B1_RING_OFFSET := Vector2(0.0, 8.0)
const ISO_RING_OFFSET := Vector2(0.0, 20.0)
const C_HOVER_OFFSET_Y := 6.0
const C_SPRITE_NUDGE := Vector2(8.0, -6.0)

var _unit_textures: Array[Texture2D] = []


func _ready() -> void:
	_unit_textures = _build_unit_textures()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-20.0, -20.0, 1340.0, 780.0), BG_COLOR)

	var font: Font = ThemeDB.fallback_font

	_draw_panel_frame(PANEL_MAIN_X)
	_draw_panel_header(font, PANEL_MAIN_X, "SCHEME C ONLY", "Isometric + full-body sprite", "Single-direction polish: anchor, shadow, readability")
	_draw_isometric_mockup(font)

	_draw_text(font, Vector2(80.0, 682.0), "Source reference: user-provided full-body sprite proportion sample", 13, SUBTITLE_COLOR)
	_draw_text(font, Vector2(80.0, 704.0), "C-only polish: slight hover allowed, but shadow/ring must maintain clear ground contact.", 12, NOTE_COLOR)


func _draw_panel_frame(panel_x: float) -> void:
	draw_rect(
		Rect2(panel_x - 12.0, PANEL_TOP - 18.0, PANEL_WIDTH, PANEL_HEIGHT),
		Color(1.0, 1.0, 1.0, 0.03)
	)
	draw_rect(
		Rect2(panel_x - 12.0, PANEL_TOP - 18.0, PANEL_WIDTH, PANEL_HEIGHT),
		PANEL_STROKE,
		false,
		1.0
	)


func _draw_panel_header(font: Font, panel_x: float, title: String, subtitle: String, note: String) -> void:
	_draw_text(font, Vector2(panel_x, 28.0), title, 22, TITLE_COLOR)
	_draw_text(font, Vector2(panel_x, 54.0), subtitle, 17, SUBTITLE_COLOR)
	_draw_text(font, Vector2(panel_x, 76.0), note, 12, NOTE_COLOR)


func _draw_b1_mockup(font: Font) -> void:
	for grid_y in range(MAP_HEIGHT):
		var row: Array = MAP_DATA[grid_y] as Array
		for grid_x in range(MAP_WIDTH):
			var terrain_id: int = row[grid_x] as int
			var terrain_color: Color = TERRAIN_COLORS[terrain_id] as Color
			var cell_origin: Vector2 = Vector2(
				B1_GRID_ORIGIN.x + float(grid_x) * B1_COL_PITCH,
				B1_GRID_ORIGIN.y + float(grid_y) * B1_ROW_PITCH
			)
			var top_rect: Rect2 = Rect2(cell_origin, Vector2(B1_CELL_WIDTH, B1_TOP_HEIGHT))
			var front_rect: Rect2 = Rect2(cell_origin + Vector2(0.0, B1_TOP_HEIGHT), Vector2(B1_CELL_WIDTH, B1_SIDE_HEIGHT))

			draw_rect(front_rect, _darken(terrain_color, 0.72))
			draw_rect(top_rect, terrain_color)
			draw_rect(top_rect, GRID_LINE_COLOR, false, 1.0)
			draw_line(front_rect.position, front_rect.position + Vector2(B1_CELL_WIDTH, 0.0), GRID_LINE_COLOR, 1.0)
			draw_line(front_rect.position + Vector2(0.0, B1_SIDE_HEIGHT), front_rect.position + Vector2(B1_CELL_WIDTH, B1_SIDE_HEIGHT), GRID_LINE_COLOR, 1.0)
			draw_line(front_rect.position, front_rect.position + Vector2(0.0, B1_SIDE_HEIGHT), GRID_LINE_COLOR, 1.0)
			draw_line(front_rect.position + Vector2(B1_CELL_WIDTH, 0.0), front_rect.position + Vector2(B1_CELL_WIDTH, B1_SIDE_HEIGHT), GRID_LINE_COLOR, 1.0)

	for grid_y in range(MAP_HEIGHT):
		var row_detail: Array = MAP_DATA[grid_y] as Array
		for grid_x in range(MAP_WIDTH):
			var terrain_id_detail: int = row_detail[grid_x] as int
			var terrain_color_detail: Color = TERRAIN_COLORS[terrain_id_detail] as Color
			var detail_origin: Vector2 = Vector2(
				B1_GRID_ORIGIN.x + float(grid_x) * B1_COL_PITCH,
				B1_GRID_ORIGIN.y + float(grid_y) * B1_ROW_PITCH
			)
			_draw_b1_terrain_detail(terrain_id_detail, terrain_color_detail, detail_origin)

		for token in TOKEN_DATA:
			var grid_pos: Vector2i = token["grid"] as Vector2i
			if grid_pos.y != grid_y:
				continue
			_draw_b1_token(font, token)


func _draw_isometric_mockup(font: Font) -> void:
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

		for token in TOKEN_DATA:
			var grid_pos: Vector2i = token["grid"] as Vector2i
			if grid_pos.x + grid_pos.y != sum_index:
				continue
			_draw_c_token(font, token)


func _draw_b1_terrain_detail(terrain_id: int, terrain_color: Color, cell_origin: Vector2) -> void:
	match terrain_id:
		T_GRASS:
			draw_line(cell_origin + Vector2(12.0, 12.0), cell_origin + Vector2(54.0, 10.0), _lighten(terrain_color, 1.16), 2.0)
			draw_line(cell_origin + Vector2(10.0, 20.0), cell_origin + Vector2(52.0, 19.0), Color(1.0, 1.0, 1.0, 0.08), 1.0)
		T_FOREST:
			draw_rect(Rect2(cell_origin + Vector2(30.0, 6.0), Vector2(8.0, 30.0)), Color(0.27, 0.16, 0.08))
			draw_circle(cell_origin + Vector2(24.0, 9.0), 13.0, _lighten(terrain_color, 1.08))
			draw_circle(cell_origin + Vector2(38.0, 7.0), 14.0, _lighten(terrain_color, 1.05))
			draw_circle(cell_origin + Vector2(50.0, 12.0), 11.0, _lighten(terrain_color, 1.02))
			draw_rect(Rect2(cell_origin + Vector2(24.0, 34.0), Vector2(20.0, 4.0)), Color(0.0, 0.0, 0.0, 0.12))
		T_MOUNTAIN:
			var ridge_points: PackedVector2Array = PackedVector2Array([
				cell_origin + Vector2(10.0, 28.0),
				cell_origin + Vector2(24.0, 6.0),
				cell_origin + Vector2(38.0, 28.0),
			])
			var ridge_points_2: PackedVector2Array = PackedVector2Array([
				cell_origin + Vector2(26.0, 30.0),
				cell_origin + Vector2(44.0, 10.0),
				cell_origin + Vector2(58.0, 30.0),
			])
			_draw_filled_polygon(ridge_points, _lighten(terrain_color, 1.12))
			_draw_filled_polygon(ridge_points_2, _darken(_lighten(terrain_color, 1.08), 0.94))
			draw_line(cell_origin + Vector2(24.0, 6.0), cell_origin + Vector2(30.0, 28.0), Color(1.0, 1.0, 1.0, 0.12), 1.0)
			draw_line(cell_origin + Vector2(44.0, 10.0), cell_origin + Vector2(44.0, 29.0), Color(0.0, 0.0, 0.0, 0.20), 1.0)
		T_WATER:
			draw_line(cell_origin + Vector2(10.0, 12.0), cell_origin + Vector2(56.0, 11.0), _lighten(terrain_color, 1.15), 2.0)
			draw_line(cell_origin + Vector2(12.0, 20.0), cell_origin + Vector2(52.0, 19.0), _lighten(terrain_color, 1.10), 2.0)
			draw_line(cell_origin + Vector2(8.0, 28.0), cell_origin + Vector2(58.0, 28.0), Color(0.0, 0.0, 0.0, 0.08), 1.0)


func _draw_isometric_terrain_detail(terrain_id: int, top_center: Vector2) -> void:
	match terrain_id:
		T_GRASS:
			draw_line(top_center + Vector2(-10.0, -2.0), top_center + Vector2(6.0, -7.0), Color(1.0, 1.0, 1.0, 0.20), 1.5)
			draw_line(top_center + Vector2(-4.0, 5.0), top_center + Vector2(8.0, 1.0), Color(1.0, 1.0, 1.0, 0.10), 1.0)
		T_FOREST:
			draw_rect(Rect2(top_center + Vector2(-2.0, -2.0), Vector2(4.0, 14.0)), Color(0.25, 0.15, 0.08, 0.88))
			draw_circle(top_center + Vector2(-6.0, -10.0), 6.0, Color(0.14, 0.28, 0.10, 0.90))
			draw_circle(top_center + Vector2(4.0, -7.0), 7.0, Color(0.17, 0.33, 0.12, 0.90))
			draw_circle(top_center + Vector2(2.0, -12.0), 4.0, Color(0.19, 0.36, 0.13, 0.84))
		T_MOUNTAIN:
			var peak_points: PackedVector2Array = PackedVector2Array([
				top_center + Vector2(-7.0, 4.0),
				top_center + Vector2(0.0, -8.0),
				top_center + Vector2(8.0, 4.0),
			])
			_draw_filled_polygon(peak_points, Color(0.76, 0.69, 0.58, 0.80))
			draw_line(top_center + Vector2(0.0, -8.0), top_center + Vector2(2.0, 4.0), Color(0.0, 0.0, 0.0, 0.18), 1.0)
		T_WATER:
			draw_line(top_center + Vector2(-12.0, 0.0), top_center + Vector2(1.0, -5.0), Color(1.0, 1.0, 1.0, 0.18), 1.5)
			draw_line(top_center + Vector2(-5.0, 6.0), top_center + Vector2(8.0, 2.0), Color(1.0, 1.0, 1.0, 0.18), 1.5)
			draw_line(top_center + Vector2(-7.0, 9.0), top_center + Vector2(5.0, 5.0), Color(0.0, 0.0, 0.0, 0.08), 1.0)


func _b1_anchor(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		B1_GRID_ORIGIN.x + float(grid_pos.x) * B1_COL_PITCH + B1_CELL_WIDTH * 0.5,
		B1_GRID_ORIGIN.y + float(grid_pos.y) * B1_ROW_PITCH + B1_TOP_HEIGHT + 2.0
	)


func _draw_b1_token(font: Font, token: Dictionary) -> void:
	var grid_pos: Vector2i = token["grid"] as Vector2i
	var anchor: Vector2 = _b1_anchor(grid_pos)
	var ring_color: Color = token["ring"] as Color
	var sprite_texture: Texture2D = _unit_textures[token["sprite_index"] as int]
	var sprite_modulate: Color = token["modulate"] as Color

	_draw_unit_shadow(anchor + Vector2(0.0, 14.0), 22.0, 8.0)
	_draw_unit_ring(anchor + B1_RING_OFFSET, 18.0, 9.0, ring_color)
	_draw_unit_sprite(sprite_texture, anchor + B1_SPRITE_OFFSET, B1_SPRITE_SIZE, sprite_modulate)
	_draw_badge(font, anchor + Vector2(18.0, -28.0), token["label"] as String, ring_color)


func _draw_c_token(font: Font, token: Dictionary) -> void:
	var grid_pos: Vector2i = token["grid"] as Vector2i
	var contact: Vector2 = _iso_top_center(grid_pos)
	var anchor: Vector2 = contact + Vector2(0.0, -C_HOVER_OFFSET_Y)
	var ring_color: Color = token["ring"] as Color
	var sprite_texture: Texture2D = _unit_textures[token["sprite_index"] as int]
	var sprite_modulate: Color = token["modulate"] as Color

	_draw_unit_shadow(contact + ISO_RING_OFFSET + Vector2(0.0, 2.0), 24.0, 9.0)
	_draw_iso_ring(contact + ISO_RING_OFFSET, ring_color)
	_draw_unit_sprite(sprite_texture, anchor + ISO_SPRITE_OFFSET + C_SPRITE_NUDGE, ISO_SPRITE_SIZE, sprite_modulate)
	_draw_badge(font, anchor + Vector2(28.0, -32.0), token["label"] as String, ring_color)


func _draw_unit_sprite(texture: Texture2D, center: Vector2, size: Vector2, modulate: Color = Color.WHITE) -> void:
	if texture == null:
		return

	var rect: Rect2 = Rect2(center - size * 0.5, size)
	draw_texture_rect(texture, rect, false, modulate)


func _draw_unit_shadow(center: Vector2, radius_x: float, radius_y: float) -> void:
	var shadow_points: PackedVector2Array = _make_ellipse_points(center, radius_x, radius_y, 20)
	_draw_filled_polygon(shadow_points, Color(0.0, 0.0, 0.0, 0.22))


func _draw_unit_ring(center: Vector2, radius_x: float, radius_y: float, color: Color) -> void:
	var ring_points: PackedVector2Array = _make_ellipse_points(center, radius_x, radius_y, 20)
	_draw_filled_polygon(ring_points, color)
	_draw_polygon_outline(ring_points, Color(1.0, 1.0, 1.0, 0.30), 1.0)


func _draw_iso_ring(center: Vector2, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array([
		center + Vector2(0.0, -10.0),
		center + Vector2(22.0, 0.0),
		center + Vector2(0.0, 10.0),
		center + Vector2(-22.0, 0.0),
	])
	_draw_filled_polygon(points, color)
	_draw_polygon_outline(points, Color(1.0, 1.0, 1.0, 0.30), 1.0)


func _draw_badge(font: Font, center: Vector2, text: String, color: Color) -> void:
	draw_circle(center, 12.0, color)
	draw_circle(center, 12.0, Color(1.0, 1.0, 1.0, 0.28))
	_draw_centered_text(font, center, text, 14, Color.WHITE)


func _build_unit_textures() -> Array[Texture2D]:
	var textures: Array[Texture2D] = []
	var source_image: Image = Image.load_from_file(REFERENCE_SPRITE_PATH)
	_clear_flat_background(source_image)
	var trimmed: Image = _trim_transparent_bounds(source_image)

	for _index in range(3):
		textures.append(ImageTexture.create_from_image(trimmed))

	return textures


func _clear_flat_background(image: Image) -> void:
	var width: int = image.get_width()
	var height: int = image.get_height()
	var queue: Array[Vector2i] = []
	var visited: PackedByteArray = PackedByteArray()
	var background_color: Color = image.get_pixel(0, 0)

	visited.resize(width * height)
	visited.fill(0)

	for x in range(width):
		queue.append(Vector2i(x, 0))
		queue.append(Vector2i(x, height - 1))
	for y in range(height):
		queue.append(Vector2i(0, y))
		queue.append(Vector2i(width - 1, y))

	while not queue.is_empty():
		var point: Vector2i = queue.pop_back()
		if point.x < 0 or point.y < 0 or point.x >= width or point.y >= height:
			continue

		var visit_index: int = point.y * width + point.x
		if visited[visit_index] == 1:
			continue
		visited[visit_index] = 1

		var color: Color = image.get_pixelv(point)
		if not _is_flat_background(color, background_color):
			continue

		image.set_pixelv(point, Color(color.r, color.g, color.b, 0.0))
		queue.append(point + Vector2i.LEFT)
		queue.append(point + Vector2i.RIGHT)
		queue.append(point + Vector2i.UP)
		queue.append(point + Vector2i.DOWN)


func _is_flat_background(color: Color, background_color: Color) -> bool:
	if color.a < 0.9:
		return false

	return (
		absf(color.r - background_color.r) <= 0.08
		and absf(color.g - background_color.g) <= 0.08
		and absf(color.b - background_color.b) <= 0.08
	)


func _trim_transparent_bounds(image: Image) -> Image:
	var width: int = image.get_width()
	var height: int = image.get_height()
	var min_x: int = width
	var min_y: int = height
	var max_x: int = -1
	var max_y: int = -1

	for y in range(height):
		for x in range(width):
			if image.get_pixel(x, y).a < 0.05:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)

	if max_x < min_x or max_y < min_y:
		return image

	var padding: int = 4
	var rect: Rect2i = Rect2i(
		maxi(min_x - padding, 0),
		maxi(min_y - padding, 0),
		mini(max_x - min_x + 1 + padding * 2, width - maxi(min_x - padding, 0)),
		mini(max_y - min_y + 1 + padding * 2, height - maxi(min_y - padding, 0))
	)
	return image.get_region(rect)


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
	var pos: Vector2 = center + Vector2(-text_size.x * 0.5, text_size.y * 0.35)
	_draw_text(font, pos, text, size, color)


func _draw_text(font: Font, pos: Vector2, text: String, size: int, color: Color) -> void:
	draw_string(font, pos + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.0, 0.0, 0.0, 0.6))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _darken(color: Color, factor: float) -> Color:
	return Color(color.r * factor, color.g * factor, color.b * factor, color.a)


func _lighten(color: Color, factor: float) -> Color:
	return Color(
		minf(color.r * factor, 1.0),
		minf(color.g * factor, 1.0),
		minf(color.b * factor, 1.0),
		color.a
	)
