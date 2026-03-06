class_name Cell
extends Resource

enum Terrain {
	PLAIN = 0, FOREST = 1, MOUNTAIN = 2, PEAK = 3,
	WALL = 4, SHALLOW_WATER = 5, DEEP_WATER = 6, LAVA = 7, SWAMP = 8
}

const IMPASSABLE := 99

const TERRAIN_MOVE_COST: Dictionary = {
	Terrain.PLAIN:         1,
	Terrain.FOREST:        2,
	Terrain.MOUNTAIN:      2,   # 设计文档：+防御+魔防，移动消耗2
	Terrain.PEAK:          IMPASSABLE,
	Terrain.WALL:          IMPASSABLE,
	Terrain.SHALLOW_WATER: 2,
	Terrain.DEEP_WATER:    IMPASSABLE,
	Terrain.LAVA:          2,  # 设计文档：可通行（触发燃烧Debuff），移动消耗2
	Terrain.SWAMP:         3,
}

const TERRAIN_EVADE_BONUS: Dictionary = {
	Terrain.FOREST: 20,
	Terrain.MOUNTAIN: 10,
}

const TERRAIN_DEF_BONUS: Dictionary = {
	Terrain.MOUNTAIN: 2,
}

const TERRAIN_MAGIC_DEF_BONUS: Dictionary = {
	Terrain.MOUNTAIN: 2,  # 设计文档：MOUNTAIN 同时提供物防和魔防加成
}

@export var position:        Vector2i = Vector2i.ZERO
@export var terrain:         int = Terrain.PLAIN
@export var special_terrain: Dictionary = {}
@export var building:        Dictionary = {}
var occupant = null


func is_passable() -> bool:
	return TERRAIN_MOVE_COST.get(terrain, IMPASSABLE) < IMPASSABLE


func get_move_cost() -> int:
	return TERRAIN_MOVE_COST.get(terrain, IMPASSABLE)


func get_evade_bonus() -> int:
	return TERRAIN_EVADE_BONUS.get(terrain, 0)


func get_def_bonus() -> int:
	return TERRAIN_DEF_BONUS.get(terrain, 0)


func get_magic_def_bonus() -> int:
	return TERRAIN_MAGIC_DEF_BONUS.get(terrain, 0)


func is_occupied() -> bool:
	return occupant != null
