class_name AreaCalculator
extends RefCounted


static func calculate_cells(grid: Grid, target_pos: Vector2i,
		pattern: Dictionary,
		direction: Vector2i = Vector2i.ZERO) -> Array[Vector2i]:
	var cells_by_pos: Dictionary = {}
	if grid == null or not grid.is_valid(target_pos):
		return []

	var pattern_type: String = str(pattern.get("type", "single"))
	var size: int = maxi(0, int(pattern.get("size", 0)))
	var resolved_direction: Vector2i = RangeCalculator.normalize_direction(direction)

	match pattern_type:
		"single":
			cells_by_pos[target_pos] = true
		"diamond":
			for dy: int in range(-size, size + 1):
				for dx: int in range(-size, size + 1):
					if absi(dx) + absi(dy) > size:
						continue
					_append_cell(grid, target_pos + Vector2i(dx, dy), cells_by_pos)
		"line":
			cells_by_pos[target_pos] = true
			if resolved_direction != Vector2i.ZERO:
				for distance: int in range(1, size + 1):
					_append_cell(
						grid, target_pos + resolved_direction * distance, cells_by_pos)
		"cross":
			cells_by_pos[target_pos] = true
			for cardinal_direction: Vector2i in RangeCalculator.CARDINAL_DIRECTIONS:
				for distance: int in range(1, size + 1):
					_append_cell(
						grid,
						target_pos + cardinal_direction * distance,
						cells_by_pos)
		"square":
			for dy: int in range(-size, size + 1):
				for dx: int in range(-size, size + 1):
					_append_cell(grid, target_pos + Vector2i(dx, dy), cells_by_pos)
		_:
			return []

	return _dictionary_keys_to_cells(cells_by_pos)


static func _append_cell(grid: Grid, cell_pos: Vector2i,
		cells_by_pos: Dictionary) -> void:
	if grid != null and grid.is_valid(cell_pos):
		cells_by_pos[cell_pos] = true


static func _dictionary_keys_to_cells(cells_by_pos: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell_pos: Variant in cells_by_pos.keys():
		if cell_pos is Vector2i:
			cells.append(cell_pos)
	return cells
