class_name UnitStats
extends Resource
## ADR-005: 9-attribute system (STR/MAG/DEX/SPD/LCK/DEF/RES/HP/MOV)
## Growth attributes (7): HP, STR, MAG, DEX, SPD, DEF, RES
## Fixed attributes (2): LCK, MOV

# ── Core attributes ─────────────────────────────────
@export var max_hp:    int = 20
@export var hp:        int = 20
@export var str_attr:  int = 8   # STR — physical attack power
@export var mag:       int = 3   # MAG — magical attack power
@export var dex:       int = 6   # DEX — hit/crit derivation
@export var spd:       int = 5   # SPD — turn order / avoid (growth-eligible, R2.1)
@export var lck:       int = 3   # LCK — crit avoid + status resist (fixed, no growth)
@export var def_attr:  int = 4   # DEF — physical defense
@export var res:       int = 2   # RES — magical defense

# Fixed (no level-up growth)
@export var mov:       int = 4   # MOV — movement range

# ── Growth system ───────────────────────────────────
# growth_rates: percentage chance per attribute on level-up (HP/STR/MAG/DEX/SPD/DEF/RES)
var growth_rates: Dictionary = {}
# SS 档属性（R2.3 预留，2026-07-07 建 / 2026-07-11 修正语义）：列于此的属性每级做两次**独立**
# 成长判定，每次成功各 +1（单级至多 +2、期望 +1.5），任一成功重置该属性 pity。
# 当前剑圣线无 SS 属性 → class_data 不含 ss_growth_stats、此表恒空、不触发。
var _ss_growth_stats: Array = []
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


func load_growth_rates(rates: Dictionary, ss_stats: Array = []) -> void:
	growth_rates = rates
	_ss_growth_stats = ss_stats
	_pity_counts = {}
	for key: String in ["HP", "STR", "MAG", "DEX", "SPD", "DEF", "RES"]:
		_pity_counts[key] = 0


# ── Derived combat stats ────────────────────────────
# These replace the old independent hit/evade/crit/crit_evade attributes.
# Formula source: ADR-005 §4.3

func get_hit(weapon_hit: int = 90) -> int:
	return weapon_hit + dex * 2


func get_avoid(terrain_evade_bonus: int = 0) -> int:
	return spd * 2 + terrain_evade_bonus


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
	for key: String in ["HP", "STR", "MAG", "DEX", "SPD", "DEF", "RES"]:
		var rate: float = growth_rates.get(key, 0) / 100.0
		var grew_count: int = 0
		if rate > 0.0:
			# SS 档属性掷两次、普通属性掷一次；每次成功独立计 +1
			# （R2.3：SS = 每级两次 S 判定，至多 +2、期望 +1.5）
			var roll_count: int = 2 if key in _ss_growth_stats else 1
			for _i: int in roll_count:
				if randf() < rate:
					grew_count += 1
			if grew_count == 0:
				# [占位] KB 未定义 SS 双判定全失败时 pity 计数，保守取 +1（与单判定同），待用户确认
				_pity_counts[key] = _pity_counts.get(key, 0) + 1
				var threshold: int = _get_pity_threshold(rate * 100.0)
				if _pity_counts[key] >= threshold:
					grew_count = 1

		if grew_count > 0:
			for _i: int in grew_count:
				_apply_growth(key)
			gains[key] = grew_count
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
		"SPD":
			spd += 1
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
