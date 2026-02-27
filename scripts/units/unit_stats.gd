class_name UnitStats
extends Resource

@export var max_hp:            int = 20
@export var hp:                int = 20
@export var phys_atk:          int = 8
@export var mag_atk:           int = 3
@export var physical_defense:  int = 4
@export var magical_defense:   int = 2
@export var hit:               int = 75
@export var evade:             int = 10
@export var crit:              int = 5
@export var crit_evade:        int = 0

# speed/move/vision/block 不成长（来自职业固定值）
@export var speed:  int = 5
@export var move:   int = 4
@export var vision: int = 3
@export var block:  int = 0  # block chance % (0-100)


func load_from_dict(d: Dictionary) -> void:
	max_hp           = d.get("hp", 20)
	hp               = max_hp
	phys_atk         = d.get("phys_atk", d.get("attack", 8))
	mag_atk          = d.get("mag_atk", d.get("magic", 3))
	physical_defense = d.get("physical_defense", d.get("def", 4))
	magical_defense  = d.get("magical_defense", d.get("magic_def", 2))
	hit              = d.get("hit", 75)
	evade            = d.get("evade", 10)
	crit             = d.get("crit", 5)
	crit_evade       = d.get("crit_evade", 0)
	speed            = d.get("speed", 5)
	move             = d.get("move", 4)
	vision           = d.get("vision", 3)
	var raw_block    = d.get("block", 0)
	if raw_block is bool:
		block = 15 if raw_block else 0
	else:
		block = int(raw_block)


func is_alive() -> bool:
	return hp > 0


func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)


func heal(amount: int) -> void:
	hp = mini(max_hp, hp + amount)
