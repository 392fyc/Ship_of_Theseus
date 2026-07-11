class_name Pathfinding
extends RefCounted

const _MAX_COST := 9999

# ── BFS 移动范围 ─────────────────────────────────────
# 返回 Dictionary{ Vector2i: int }，value = 到达该格后剩余移动力
# （ZOC 已完全移除，2026-07-06 用户裁决：移动力不再受敌方控制区惩罚。）

static func get_move_range(grid: Grid, start: Vector2i,
		move_points: int, unit_faction: String) -> Dictionary:
	var reachable: Dictionary = {start: move_points}
	var queue: Array = [{"pos": start, "mp": move_points}]

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
			var remaining: int = cur.mp - cost
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


# ── 攻击线检测已移除（2026-07-11 用户裁决）──────────────
# 地形不再阻挡任何攻击线（敌我双方）；PEAK 仅保留移动不可通行。


# ── 辅助函数 ─────────────────────────────────────────

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
