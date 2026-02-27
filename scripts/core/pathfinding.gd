class_name Pathfinding
extends RefCounted

const _MAX_COST := 9999


# ── BFS 移动范围 ─────────────────────────────────────
# 返回 Dictionary{ Vector2i: int }，value = 到达该格后剩余移动力
# ZOC 规则（设计文档 02-grid-and-map）：
#   仅在移动开始时一次性扣除 -2，不是每经过 ZOC 格都扣
#   即：起始位置处于敌方 ZOC → 总移动力 -2 后再 BFS 展开

static func get_move_range(grid: Grid, start: Vector2i,
		move_points: int, unit_faction: String) -> Dictionary:
	var effective_mp := move_points
	if _in_enemy_zoc(grid, start, unit_faction):
		effective_mp = maxi(0, effective_mp - 2)

	var reachable: Dictionary = {start: effective_mp}
	var queue: Array = [{"pos": start, "mp": effective_mp}]

	while not queue.is_empty():
		var cur = queue.pop_front()
		for nb in grid.get_neighbors(cur.pos):
			var cell := grid.get_cell(nb)
			if cell == null or not cell.is_passable():
				continue
			var occ = cell.occupant
			if occ != null and occ.faction != unit_faction:
				continue
			var cost := cell.get_move_cost()
			var remaining := cur.mp - cost
			if remaining < 0:
				continue
			if remaining > reachable.get(nb, -1):
				reachable[nb] = remaining
				queue.append({"pos": nb, "mp": remaining})

	var result: Dictionary = {}
	for pos in reachable:
		var c := grid.get_cell(pos)
		if c.occupant == null or pos == start:
			result[pos] = reachable[pos]
	return result


# ── A* 寻路 ──────────────────────────────────────────
# 返回 Array[Vector2i]（含起点和终点），空数组 = 不可达
# 只计算最短路径，不检查移动力预算（由调用者结合 BFS 结果使用）

static func find_path(grid: Grid, start: Vector2i,
		end: Vector2i, unit_faction: String) -> Array[Vector2i]:
	if start == end:
		return [start]
	if not grid.is_valid(end):
		return []

	var open_set: Array[Vector2i] = [start]
	var closed_set: Dictionary = {}
	var came_from: Dictionary = {}
	var g_cost: Dictionary = {start: 0}
	var f_cost: Dictionary = {start: _heuristic(start, end)}

	while not open_set.is_empty():
		var current := _pop_lowest(open_set, f_cost)
		if current == end:
			return _reconstruct_path(came_from, current)

		closed_set[current] = true

		for nb in grid.get_neighbors(current):
			if closed_set.has(nb):
				continue
			var cell := grid.get_cell(nb)
			if cell == null or not cell.is_passable():
				continue
			var occ = cell.occupant
			if occ != null and occ.faction != unit_faction:
				continue

			var tentative_g: int = g_cost[current] + cell.get_move_cost()
			if tentative_g < g_cost.get(nb, _MAX_COST):
				came_from[nb] = current
				g_cost[nb] = tentative_g
				f_cost[nb] = tentative_g + _heuristic(nb, end)
				if not open_set.has(nb):
					open_set.append(nb)

	return []


# ── 攻击线检测（Bresenham）───────────────────────────
# 仅 PEAK 阻挡远程攻击线，WALL 不阻挡
# 起点终点本身不检测

static func check_attack_line(grid: Grid,
		from_pos: Vector2i, to_pos: Vector2i) -> bool:
	if from_pos == to_pos:
		return true

	var x0 := from_pos.x
	var y0 := from_pos.y
	var x1 := to_pos.x
	var y1 := to_pos.y

	var dx := absi(x1 - x0)
	var dy := absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx - dy

	var x := x0
	var y := y0

	while true:
		var pos := Vector2i(x, y)
		if pos != from_pos and pos != to_pos:
			var cell := grid.get_cell(pos)
			if cell != null and cell.terrain == Cell.Terrain.PEAK:
				return false

		if x == x1 and y == y1:
			break

		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy

	return true


# ── 辅助函数 ─────────────────────────────────────────

static func _in_enemy_zoc(grid: Grid, pos: Vector2i, faction: String) -> bool:
	for nb in grid.get_neighbors(pos):
		var unit = grid.get_unit_at(nb)
		if unit != null and unit.faction != faction:
			return true
	return false


static func _heuristic(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func _pop_lowest(open_set: Array[Vector2i], f_cost: Dictionary) -> Vector2i:
	var best_idx := 0
	var best_f: int = f_cost.get(open_set[0], _MAX_COST)
	for i in range(1, open_set.size()):
		var f: int = f_cost.get(open_set[i], _MAX_COST)
		if f < best_f:
			best_f = f
			best_idx = i
	var result := open_set[best_idx]
	open_set.remove_at(best_idx)
	return result


static func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	return path
