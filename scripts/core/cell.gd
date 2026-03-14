class_name Cell
extends Resource

enum Terrain {
	PLAIN = 0, FOREST = 1, MOUNTAIN = 2, PEAK = 3,
	WALL = 4, SHALLOW_WATER = 5, DEEP_WATER = 6, LAVA = 7, SWAMP = 8
}

const IMPASSABLE := 99
const TERRAIN_COMBAT_DATA_PATH: String = "res://data/terrain/terrain_combat.json"
const TERRAIN_KEY_BY_ID: Dictionary = {
	Terrain.PLAIN: "PLAIN",
	Terrain.FOREST: "FOREST",
	Terrain.MOUNTAIN: "MOUNTAIN",
	Terrain.PEAK: "PEAK",
	Terrain.WALL: "WALL",
	Terrain.SHALLOW_WATER: "SHALLOW_WATER",
	Terrain.DEEP_WATER: "DEEP_WATER",
	Terrain.LAVA: "LAVA",
	Terrain.SWAMP: "SWAMP",
}

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

static var _terrain_combat_loaded: bool = false
static var _terrain_combat_by_id: Dictionary = {}

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
	return get_combat_modifiers().get("evade_bonus", 0)


func get_def_bonus() -> int:
	return get_combat_modifiers().get("def_bonus", 0)


func get_magic_def_bonus() -> int:
	return get_combat_modifiers().get("res_bonus", 0)


func get_combat_modifiers() -> Dictionary:
	_ensure_terrain_combat_data_loaded()
	var modifiers: Dictionary = _terrain_combat_by_id.get(terrain, {})
	return {
		"terrain_id": terrain,
		"terrain_name": get_terrain_name(terrain),
		"evade_bonus": int(modifiers.get("evade_bonus", 0)),
		"def_bonus": int(modifiers.get("def_bonus", 0)),
		"res_bonus": int(modifiers.get("res_bonus", 0)),
	}


func is_occupied() -> bool:
	return occupant != null


static func get_terrain_name(terrain_id: int) -> String:
	return str(TERRAIN_KEY_BY_ID.get(terrain_id, "PLAIN"))


static func _ensure_terrain_combat_data_loaded() -> void:
	if _terrain_combat_loaded:
		return
	_terrain_combat_loaded = true
	_terrain_combat_by_id = {}

	var file: FileAccess = FileAccess.open(TERRAIN_COMBAT_DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("[Cell] Terrain combat data missing: " + TERRAIN_COMBAT_DATA_PATH)
		return

	var json: JSON = JSON.new()
	var parse_error: int = json.parse(file.get_as_text())
	if parse_error != OK:
		push_warning("[Cell] Failed to parse terrain combat data: %s" % json.get_error_message())
		return

	var root: Variant = json.data
	if not (root is Dictionary):
		push_warning("[Cell] Terrain combat data root must be a dictionary")
		return

	var terrain_types: Dictionary = root.get("terrain_types", {})
	for terrain_key_value: Variant in terrain_types.keys():
		var terrain_key: String = str(terrain_key_value)
		var terrain_entry: Dictionary = terrain_types.get(terrain_key, {})
		var terrain_id: int = int(terrain_entry.get("terrain_id", -1))
		if terrain_id < 0:
			continue
		_terrain_combat_by_id[terrain_id] = {
			"terrain_name": terrain_key,
			"evade_bonus": int(terrain_entry.get("evade_bonus", 0)),
			"def_bonus": int(terrain_entry.get("def_bonus", 0)),
			"res_bonus": int(terrain_entry.get("res_bonus", 0)),
		}
