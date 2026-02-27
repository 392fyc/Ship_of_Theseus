class_name UnitStats
extends Resource

@export var max_hp:     int = 20
@export var hp:         int = 20
@export var atk:        int = 8
@export var def:        int = 4
@export var magic:      int = 0
@export var magic_def:  int = 2
@export var hit:        int = 75
@export var evade:      int = 10
@export var crit:       int = 5
@export var crit_evade: int = 0

# speed/move/vision/block 不成长（来自职业固定值）
@export var speed:  int = 5
@export var move:   int = 4
@export var vision: int = 3
@export var block:  bool = false


func load_from_dict(d: Dictionary) -> void:
	max_hp    = d.get("hp", 20)
	hp        = max_hp
	atk       = d.get("atk", d.get("attack", 8))
	def       = d.get("def", d.get("physical_defense", 4))
	magic     = d.get("magic", 0)
	magic_def = d.get("magic_def", d.get("magical_defense", 2))
	hit       = d.get("hit", 75)
	evade     = d.get("evade", 10)
	crit      = d.get("crit", 5)
	crit_evade = d.get("crit_evade", 0)
	speed     = d.get("speed", 5)
	move      = d.get("move", 4)
	vision    = d.get("vision", 3)
	block     = d.get("block", false)


func is_alive() -> bool:
	return hp > 0


func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)


func heal(amount: int) -> void:
	hp = mini(max_hp, hp + amount)
