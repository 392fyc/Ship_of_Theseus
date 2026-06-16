class_name UnitStats
extends Resource
## ADR-005: 10-attribute system (STR/MAG/DEX/SPD/LCK/DEF/RES/HP/MOV/VIS)
## Growth attributes (6): HP, STR, MAG, DEX, DEF, RES
## Fixed attributes (4): SPD, LCK, MOV, VIS

# ── Core attributes ─────────────────────────────────
@export var max_hp:    int = 20
@export var hp:        int = 20
@export var str_attr:  int = 8   # STR — physical attack power
@export var mag:       int = 3   # MAG — magical attack power
@export var dex:       int = 6   # DEX — hit/crit derivation
@export var spd:       int = 5   # SPD — turn order / avoid (no growth)
@export var lck:       int = 3   # LCK — crit avoid + status resist + minor hit (fixed, no growth)
@export var def_attr:  int = 4   # DEF — physical defense
@export var res:       int = 2   # RES — magical defense

# Fixed (no level-up growth)
@export var mov:       int = 4   # MOV — movement range
@export var vis:       int = 3   # VIS — vision range

# ── Growth system ───────────────────────────────────
# growth_rates: percentage chance per attribute on level-up (HP/STR/MAG/DEX/DEF/RES)
var growth_rates: Dictionary = {}
# Pity counters: tracks consecutive failures per attribute
var _pity_counts: Dictionary = {}


func load_from_dict(d: Dictionary) -> void:
	max_hp   = d.get("hp", d.get("HP", 20))
	hp       = max_hp
	str_attr = d.get("STR", d.get("phys_atk", 8))
	mag      = d.get("MAG", d.get("mag_atk", 3))
	dex      = d.get("DEX", d.get("hit", 6))
	spd      = d.get("SPD", d.get("speed", 5))
	lck      = d.get("LCK", d.get("crit_evade", 3))
	def_attr = d.get("DEF", d.get("physical_defense", 4))
	res      = d.get("RES", d.get("magical_defense", 2))
	mov      = d.get("MOV", d.get("move", 4))
	vis      = d.get("VIS", d.get("vision", 3))


func load_growth_rates(rates: Dictionary) -> void:
	growth_rates = rates
	_pity_counts = {}
	for key: String in ["HP", "STR", "MAG", "DEX", "DEF", "RES"]:
		_pity_counts[key] = 0


# ── Derived combat stats ────────────────────────────
# These replace the old independent hit/evade/crit/crit_evade attributes.
# Formula source: ADR-005 §4.3

func get_hit(weapon_hit: int = 90) -> int:
	return weapon_hit + dex * 2 + roundi(lck * 0.5)


func get_avoid(terrain_evade_bonus: int = 0) -> int:
	return spd * 2 + roundi(lck * 0.5) + terrain_evade_bonus


func get_crit(weapon_crit: int = 0) -> int:
	return weapon_crit + int(dex / 2.0)


func get_crit_avoid() -> int:
	return lck


func get_status_resist_mult() -> float:
	## Returns multiplier for debuff application (lower = more resistant).
	## Formula: max(0.1, 1 - LCK/100)
	return maxf(0.1, 1.0 - lck / 100.0)


# ── Level-up (probability growth + pity) ────────────

func level_up() -> Dictionary:
	## Roll growth for each growable attribute. Returns dict of increases.
	## Uses pity: after N consecutive failures, force +1.
	var gains: Dictionary = {}
	for key: String in ["HP", "STR", "MAG", "DEX", "DEF", "RES"]:
		var rate: float = growth_rates.get(key, 0) / 100.0
		var grew: bool = false
		if rate > 0.0:
			if randf() < rate:
				grew = true
			else:
				_pity_counts[key] = _pity_counts.get(key, 0) + 1
				var threshold: int = _get_pity_threshold(rate * 100.0)
				if _pity_counts[key] >= threshold:
					grew = true

		if grew:
			_apply_growth(key)
			gains[key] = 1
			_pity_counts[key] = 0
	return gains


func _get_pity_threshold(growth_pct: float) -> int:
	if growth_pct >= 40.0:
		return 3
	elif growth_pct >= 20.0:
		return 5
	else:
		return 8


func _apply_growth(key: String) -> void:
	match key:
		"HP":
			max_hp += 1
			hp += 1
		"STR":
			str_attr += 1
		"MAG":
			mag += 1
		"DEX":
			dex += 1
		"DEF":
			def_attr += 1
		"RES":
			res += 1


# ── HP utilities ────────────────────────────────────

func is_alive() -> bool:
	return hp > 0


func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)


func heal(amount: int) -> void:
	hp = mini(max_hp, hp + amount)
