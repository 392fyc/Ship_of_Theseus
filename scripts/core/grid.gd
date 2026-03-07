class_name Grid
extends RefCounted

const CELL_SIZE := Vector2i(64, 64)
const TILE_WIDTH := 64
const TILE_HEIGHT := 32

signal unit_placed(unit, pos: Vector2i)
signal unit_moved(unit, from: Vector2i, to: Vector2i)
signal unit_removed(unit, pos: Vector2i)

var cells: Array = []   # cells[row][col] = cells[y][x]
var width:  int = 0
var height: int = 0
var _iso_offset: Vector2 = Vector2.ZERO


func initialize(map_data: Dictionary) -> void:
	width  = map_data.get("width", 8)
	height = map_data.get("height", 8)
	var terrain_rows: Array = map_data.get("terrain", [])
	cells = []
	for row in height:
		var row_arr: Array = []
		for col in width:
			var cell := Cell.new()
			cell.position = Vector2i(col, row)
			var terrain_val: int = 0
			if row < terrain_rows.size() and col < terrain_rows[row].size():
				terrain_val = terrain_rows[row][col]
			cell.terrain = terrain_val
			row_arr.append(cell)
		cells.append(row_arr)
	for st in map_data.get("special_terrain", []):
		var pos: Array = st.get("position", [0, 0])
		var c := get_cell(Vector2i(pos[0], pos[1]))
		if c:
			c.special_terrain = st
	_update_iso_offset()
	print("[Grid] Initialized %dx%d map: %s" % [width, height, map_data.get("id", "?")])


# ── 基础访问 ─────────────────────────────────────────

func is_valid(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height


func get_cell(pos: Vector2i) -> Cell:
	if not is_valid(pos):
		return null
	return cells[pos.y][pos.x]


func get_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var nb := pos + offset
		if is_valid(nb):
			result.append(nb)
	return result


# ── 坐标转换 ─────────────────────────────────────────

func grid_to_world(pos: Vector2i) -> Vector2:
	var sx: float = float(pos.x - pos.y) * TILE_WIDTH / 2.0 + _iso_offset.x
	var sy: float = float(pos.x + pos.y) * TILE_HEIGHT / 2.0 + _iso_offset.y
	return Vector2(sx, sy)


func world_to_grid(world_pos: Vector2) -> Vector2i:
	var wx: float = world_pos.x - _iso_offset.x
	var wy: float = world_pos.y - _iso_offset.y
	var gx: float = (wx / (TILE_WIDTH / 2.0) + wy / (TILE_HEIGHT / 2.0)) / 2.0
	var gy: float = (wy / (TILE_HEIGHT / 2.0) - wx / (TILE_WIDTH / 2.0)) / 2.0
	return Vector2i(roundi(gx), roundi(gy))


func _update_iso_offset() -> void:
	_iso_offset = Vector2(float(width) * TILE_WIDTH / 2.0, 64.0)


# ── Unit 放置（双向引用，ADR-003）─────────────────────

func get_unit_at(pos: Vector2i):
	var cell := get_cell(pos)
	return cell.occupant if cell else null


func place_unit(unit, pos: Vector2i) -> void:
	assert(is_valid(pos), "place_unit: pos out of bounds")
	var cell := get_cell(pos)
	assert(cell.occupant == null, "place_unit: cell already occupied")
	cell.occupant = unit
	unit.grid_position = pos
	unit_placed.emit(unit, pos)


func move_unit(unit, from: Vector2i, to: Vector2i) -> void:
	assert(is_valid(to), "move_unit: destination out of bounds")
	var src := get_cell(from)
	var dst := get_cell(to)
	assert(dst.occupant == null, "move_unit: destination already occupied")
	if src:
		src.occupant = null
	if dst:
		dst.occupant = unit
		unit.grid_position = to
	unit_moved.emit(unit, from, to)


func remove_unit(unit) -> void:
	var cell := get_cell(unit.grid_position)
	if cell and cell.occupant == unit:
		cell.occupant = null
		unit_removed.emit(unit, unit.grid_position)
