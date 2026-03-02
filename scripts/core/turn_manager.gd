class_name TurnManager
extends Node

signal turn_started(unit: Unit)
signal turn_ended(unit: Unit)
signal round_ended()

var _queue: Array[Unit] = []
var _all_units: Array[Unit] = []
var current_unit: Unit = null
var _round_number: int = 0


func add_units(units: Array[Unit]) -> void:
	for u in units:
		if u not in _all_units:
			_all_units.append(u)


func remove_unit(unit: Unit) -> void:
	_all_units.erase(unit)
	_queue.erase(unit)
	if current_unit == unit:
		current_unit = null


func start() -> void:
	_rebuild_queue()
	_advance()


func force_advance() -> void:
	_advance()


func stop() -> void:
	current_unit = null
	_queue.clear()


func end_current_turn() -> void:
	if current_unit == null:
		return
	current_unit.mark_done()
	var ended := current_unit
	current_unit = null
	turn_ended.emit(ended)
	_advance()


func _rebuild_queue() -> void:
	_round_number += 1
	_queue = _all_units.filter(func(u: Unit): return u.stats.is_alive())
	_queue.sort_custom(_compare_initiative)
	var names: PackedStringArray = []
	for u in _queue:
		names.append("%s(%s)" % [u.unit_name, u.faction])
	print("[TurnManager] Round %d queue: [%s]" % [
		_round_number, ", ".join(names)])


func _advance() -> void:
	if _queue.is_empty():
		round_ended.emit()
		_rebuild_queue()
		if _queue.is_empty():
			push_warning("[TurnManager] No units alive")
			return
	current_unit = _queue.pop_front()
	turn_started.emit(current_unit)


# speed desc → priority desc → player first
static func _compare_initiative(a: Unit, b: Unit) -> bool:
	if a.stats.spd != b.stats.spd:
		return a.stats.spd > b.stats.spd
	if a.priority != b.priority:
		return a.priority > b.priority
	if a.faction != b.faction:
		return a.faction == "player"
	return false
