class_name EnemyAI
extends RefCounted
## AGGRESSIVE AI: move toward and attack the nearest player unit.
## All decisions are returned as GameAction arrays for TacticalManager to execute,
## keeping the pattern compatible with multiplayer broadcast.


static func decide_actions(unit: Unit, grid: Grid,
		all_units: Array) -> Array[GameAction]:
	var actions: Array[GameAction] = []
	var atk_range: int = unit.attack_range

	var targets: Array[Unit] = []
	for u in all_units:
		if u.faction != unit.faction and u.stats.is_alive():
			targets.append(u)

	if targets.is_empty():
		return actions

	# 1. Already in attack range → attack immediately
	var target_in_range: Unit = _find_target_in_range(
		unit.grid_position, targets, atk_range)
	if target_in_range:
		actions.append(GameAction.make_attack(unit, target_in_range))
		return actions

	# 2. Compute reachable cells
	var move_range: Dictionary = Pathfinding.get_move_range(
		grid, unit.grid_position, unit.stats.mov, unit.faction)

	# 3. Find a move position that puts a target in attack range
	var best_move: Vector2i = unit.grid_position
	var best_target: Unit = null
	var best_dist: int = 9999

	for move_pos: Vector2i in move_range:
		var cell := grid.get_cell(move_pos)
		if cell.occupant != null and cell.occupant != unit:
			continue
		for target in targets:
			var dist: int = _manhattan(move_pos, target.grid_position)
			if dist >= 1 and dist <= atk_range:
				var target_dist: int = _manhattan(
					unit.grid_position, target.grid_position)
				if best_target == null or target_dist < best_dist:
					best_dist = target_dist
					best_move = move_pos
					best_target = target

	if best_target:
		if best_move != unit.grid_position:
			actions.append(GameAction.make_move(unit, best_move))
		actions.append(GameAction.make_attack(unit, best_target))
		return actions

	# 4. Can't attack anyone — move toward nearest target
	var nearest: Unit = _find_nearest(unit.grid_position, targets)
	if nearest:
		var approach_pos: Vector2i = _closest_reachable_to(
			move_range, nearest.grid_position, unit, grid)
		if approach_pos != unit.grid_position:
			actions.append(GameAction.make_move(unit, approach_pos))

	return actions


# ── Helpers ──────────────────────────────────────────

static func _find_target_in_range(origin: Vector2i,
		targets: Array[Unit], atk_range: int) -> Unit:
	## Pick the lowest-HP target within attack range (focus fire).
	var best: Unit = null
	var best_hp: int = 99999
	for target in targets:
		var dist: int = _manhattan(origin, target.grid_position)
		if dist >= 1 and dist <= atk_range:
			if target.stats.hp < best_hp:
				best_hp = target.stats.hp
				best = target
	return best


static func _find_nearest(origin: Vector2i,
		targets: Array[Unit]) -> Unit:
	var best: Unit = null
	var best_dist: int = 99999
	for target in targets:
		var dist: int = _manhattan(origin, target.grid_position)
		if dist < best_dist:
			best_dist = dist
			best = target
	return best


static func _closest_reachable_to(move_range: Dictionary,
		goal: Vector2i, unit: Unit, grid: Grid) -> Vector2i:
	var best_pos: Vector2i = unit.grid_position
	var best_dist: int = _manhattan(unit.grid_position, goal)
	for pos: Vector2i in move_range:
		var cell := grid.get_cell(pos)
		if cell.occupant != null and cell.occupant != unit:
			continue
		var dist: int = _manhattan(pos, goal)
		if dist < best_dist:
			best_dist = dist
			best_pos = pos
	return best_pos


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
