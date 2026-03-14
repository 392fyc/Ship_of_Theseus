class_name TurnManager
extends Node

signal turn_started(unit: Unit)
signal turn_ended(unit: Unit)
signal round_ended()
signal queue_changed()

enum Difficulty { LOW, NORMAL, HIGH, HIGHEST }

@export var difficulty: Difficulty = Difficulty.LOW

var _queue: Array[Unit] = []
var _all_units: Array[Unit] = []
var current_unit: Unit = null
var _round_number: int = 0


func add_units(units: Array[Unit]) -> void:
	for unit: Unit in units:
		if unit in _all_units:
			continue
		_all_units.append(unit)
		if not unit.buffs_changed.is_connected(_on_unit_buffs_changed):
			unit.buffs_changed.connect(_on_unit_buffs_changed)


func remove_unit(unit: Unit) -> void:
	_all_units.erase(unit)
	_queue.erase(unit)
	if unit.buffs_changed.is_connected(_on_unit_buffs_changed):
		unit.buffs_changed.disconnect(_on_unit_buffs_changed)
	if current_unit == unit:
		current_unit = null
	queue_changed.emit()


func start() -> void:
	_rebuild_queue()
	_advance()


func force_advance() -> void:
	_advance()


func get_display_queue() -> Array[Unit]:
	var result: Array[Unit] = []
	if current_unit != null and current_unit.stats.is_alive():
		result.append(current_unit)
	for unit: Unit in _queue:
		if unit.stats.is_alive():
			result.append(unit)
	return result


func stop() -> void:
	current_unit = null
	_queue.clear()
	queue_changed.emit()


func end_current_turn() -> void:
	if current_unit == null:
		return
	current_unit.mark_done()
	var ended: Unit = current_unit
	current_unit = null
	turn_ended.emit(ended)
	_advance()


func refresh_queue_order() -> void:
	var next_queue: Array[Unit] = []
	for unit: Unit in _queue:
		if unit.stats.is_alive():
			next_queue.append(unit)
	_queue = next_queue
	_queue.sort_custom(_compare_initiative)
	queue_changed.emit()


func _rebuild_queue() -> void:
	_round_number += 1
	var alive_units: Array[Unit] = []
	for unit: Unit in _all_units:
		if unit.stats.is_alive():
			alive_units.append(unit)
	_queue = alive_units
	_queue.sort_custom(_compare_initiative)
	var names: PackedStringArray = []
	for unit: Unit in _queue:
		names.append("%s(%s)" % [unit.unit_name, unit.faction])
	print("[TurnManager] Round %d queue: [%s]" % [
		_round_number, ", ".join(names)])


func _advance() -> void:
	if _queue.is_empty():
		round_ended.emit()
		_rebuild_queue()
		if _queue.is_empty():
			push_warning("[TurnManager] No units alive")
			queue_changed.emit()
			return
	current_unit = _queue.pop_front()
	queue_changed.emit()
	turn_started.emit(current_unit)


func _on_unit_buffs_changed(_unit: Unit) -> void:
	refresh_queue_order()


# priority desc → speed desc → low diff player first / highest diff enemy first
func _compare_initiative(a: Unit, b: Unit) -> bool:
	var a_priority: int = a.get_effective_priority()
	var b_priority: int = b.get_effective_priority()
	if a_priority != b_priority:
		return a_priority > b_priority
	var a_speed: int = a.get_effective_stat("SPD")
	var b_speed: int = b.get_effective_stat("SPD")
	if a_speed != b_speed:
		return a_speed > b_speed
	if a.faction != b.faction:
		if difficulty == Difficulty.HIGHEST:
			return a.faction == "enemy"
		return a.faction == "player"
	return false
