class_name RangeCalculator
extends RefCounted
## 射程形态计算（diamond/line/cross/square/self）。
## 2026-07-11 用户裁决：取消地形对攻击线的阻挡（敌我双方），视线过滤层已整体移除；
## 射程只由形态与距离决定。

const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.RIGHT,
]


static func calculate_cells(grid: Grid, origin: Vector2i, pattern: Dictionary,
		direction: Vector2i = Vector2i.ZERO) -> Array[Vector2i]:
	var cells_by_pos: Dictionary = {}
	if grid == null or not grid.is_valid(origin):
		return []

	var pattern_type: String = str(pattern.get("type", "diamond"))
	var min_range: int = _get_min_range(pattern)
	var max_range: int = _get_max_range(pattern)
	if pattern_type == "self":
		cells_by_pos[origin] = true
		return _dictionary_keys_to_cells(cells_by_pos)
	if max_range < min_range:
		return []

	match pattern_type:
		"diamond":
			_append_diamond_cells(grid, origin, min_range, max_range, cells_by_pos)
		"line":
			var line_direction: Vector2i = normalize_direction(direction)
			if line_direction == Vector2i.ZERO:
				return []
			_append_line_cells(
				grid, origin, line_direction, min_range, max_range, cells_by_pos)
		"cross":
			for cardinal_direction: Vector2i in CARDINAL_DIRECTIONS:
				_append_line_cells(
					grid, origin, cardinal_direction, min_range, max_range, cells_by_pos)
		"square":
			_append_square_cells(grid, origin, min_range, max_range, cells_by_pos)
		_:
			return []

	return _dictionary_keys_to_cells(cells_by_pos)


static func get_line_selector_cells(grid: Grid, origin: Vector2i,
		pattern: Dictionary) -> Array[Vector2i]:
	var selector_cells: Array[Vector2i] = []
	for direction: Vector2i in get_line_directions(grid, origin, pattern):
		var selector_cell: Vector2i = origin + direction
		if grid != null and grid.is_valid(selector_cell):
			selector_cells.append(selector_cell)
	return selector_cells


static func get_line_directions(grid: Grid, origin: Vector2i,
		pattern: Dictionary) -> Array[Vector2i]:
	var directions: Array[Vector2i] = []
	for direction: Vector2i in CARDINAL_DIRECTIONS:
		var cells: Array[Vector2i] = calculate_cells(grid, origin, pattern, direction)
		if not cells.is_empty():
			directions.append(direction)
	return directions


static func normalize_direction(direction: Vector2i) -> Vector2i:
	if direction == Vector2i.ZERO:
		return Vector2i.ZERO
	if direction.x != 0 and direction.y != 0:
		if absi(direction.x) >= absi(direction.y):
			return Vector2i(signi(direction.x), 0)
		return Vector2i(0, signi(direction.y))
	if direction.x != 0:
		return Vector2i(signi(direction.x), 0)
	return Vector2i(0, signi(direction.y))


static func direction_from_to(from_pos: Vector2i, to_pos: Vector2i) -> Vector2i:
	return normalize_direction(to_pos - from_pos)


static func _append_diamond_cells(grid: Grid, origin: Vector2i,
		min_range: int, max_range: int, cells_by_pos: Dictionary) -> void:
	for dy: int in range(-max_range, max_range + 1):
		for dx: int in range(-max_range, max_range + 1):
			var distance: int = absi(dx) + absi(dy)
			if distance < min_range or distance > max_range:
				continue
			_try_append_cell(grid, origin + Vector2i(dx, dy), cells_by_pos)


static func _append_square_cells(grid: Grid, origin: Vector2i,
		min_range: int, max_range: int, cells_by_pos: Dictionary) -> void:
	for dy: int in range(-max_range, max_range + 1):
		for dx: int in range(-max_range, max_range + 1):
			var distance: int = maxi(absi(dx), absi(dy))
			if distance < min_range or distance > max_range:
				continue
			_try_append_cell(grid, origin + Vector2i(dx, dy), cells_by_pos)


static func _append_line_cells(grid: Grid, origin: Vector2i, direction: Vector2i,
		min_range: int, max_range: int, cells_by_pos: Dictionary) -> void:
	for distance: int in range(min_range, max_range + 1):
		var cell_pos: Vector2i = origin + direction * distance
		_try_append_cell(grid, cell_pos, cells_by_pos)


static func _try_append_cell(grid: Grid, cell_pos: Vector2i,
		cells_by_pos: Dictionary) -> void:
	if grid == null or not grid.is_valid(cell_pos):
		return
	cells_by_pos[cell_pos] = true


static func _get_min_range(pattern: Dictionary) -> int:
	return maxi(0, int(pattern.get("min_range", pattern.get("min", 0))))


static func _get_max_range(pattern: Dictionary) -> int:
	return maxi(0, int(pattern.get("max_range", pattern.get("max", 0))))


static func _dictionary_keys_to_cells(cells_by_pos: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell_pos: Variant in cells_by_pos.keys():
		if cell_pos is Vector2i:
			cells.append(cell_pos)
	return cells
