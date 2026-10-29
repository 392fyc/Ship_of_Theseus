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
## 当前回合是不是额外回合（〔阴阳剑〕阴阳圆满）。额外回合是完整的自身回合，但不计入状态的持续时间。
var current_is_extra_turn: bool = false
## 已排入队首、尚未开始的额外回合：单位 → 待开始的次数。
var _pending_extra_turns: Dictionary = {}


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


## 当前回合序号（1-based；start() 后为 1）。供敌人词条 af_vanguard 判首回合等外部逻辑读取。
func get_round_number() -> int:
	return _round_number


## 给单位一个额外的自身回合，排在当前回合结束之后（插到待行动队列最前）。额外回合不占用它
## 原本的回合；在别的单位的回合里达成时，等那个回合结束后插入（同样是队首）。
func grant_extra_turn(unit: Unit) -> void:
	if unit == null or not unit.stats.is_alive():
		return
	_queue.push_front(unit)
	_pending_extra_turns[unit] = int(_pending_extra_turns.get(unit, 0)) + 1
	queue_changed.emit()


## 该单位本轮次是否还没轮到行动：仍在本轮的待行动队列里（当前行动者已出队，不算）。
## 供〔踏影〕「目标在本轮尚未行动」判定。
func has_pending_turn(unit: Unit) -> bool:
	if unit == null or not unit in _queue:
		return false
	# 排在队里的只是额外回合时，它本轮原本的回合已经用过。
	return _queue.count(unit) > int(_pending_extra_turns.get(unit, 0))


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
	current_is_extra_turn = false
	_pending_extra_turns.clear()
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
	current_is_extra_turn = false
	var pending_extra: int = int(_pending_extra_turns.get(current_unit, 0))
	if pending_extra > 0:
		current_is_extra_turn = true
		if pending_extra == 1:
			_pending_extra_turns.erase(current_unit)
		else:
			_pending_extra_turns[current_unit] = pending_extra - 1
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
