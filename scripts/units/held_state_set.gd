class_name HeldStateSet
extends RefCounted
## 单位持有的状态（设计库 State 中有层数、有持续时间的那一类）。
##
## 与两套旧机制并存，互不迁移（用户 2026-10-28 裁决 S4/S5「新增入口不迁移旧 buff」）：
## - `data/buffs` + BuffEffect：旧 buff，持有者回合结束时持续时间 −1。
## - `data/states` + StateRegistry：条件状态（背水、双持），即时求值，不持有。
## 本类只管 `data/held_states`：状态本体的再获得方式、层数上限、是否永久来自设计库镜像；
## 持续时间按 R3.4 由给予状态的技能写明，在 `apply()` 时传入。
##
## 持续时间口径（`duration.kind`）：
## - `permanent`：永久；每场战斗开始时由调用方 `clear()`。设计库 is_permanent=true 的状态一律按此处理。
## - `until_own_turn_start`：持续到其后第 N 个自身回合开始（`duration.count` = N）。
## - `until_own_turn_end`：持续到其后第 N 个自身回合结束；在自身回合内获得时，当前回合的结束不计数。
## - `until_this_turn_end`：持续到持有者当前（或下一个）自身回合结束，额外回合同样会结束它。
##   只按持有者的回合计时；「持续到施加者本回合结束」（设计库〔破绽〕）这类按他人回合计时的口径
##   尚未承载，接入时新增口径，不要借用本口径。
## 额外回合不计入 N（设计库〔架势〕rules：只按常规自身回合计算）。

signal changed

const DURATION_PERMANENT := "permanent"
const DURATION_UNTIL_OWN_TURN_START := "until_own_turn_start"
const DURATION_UNTIL_OWN_TURN_END := "until_own_turn_end"
const DURATION_UNTIL_THIS_TURN_END := "until_this_turn_end"

const REAPPLY_ADD_STACKS := "add_stacks"
const REAPPLY_SET_STACKS := "set_stacks"
const REAPPLY_REFRESH := "refresh_duration"
const REAPPLY_IGNORE := "ignore_incoming"
const REAPPLY_INDEPENDENT := "create_independent_instance"

## 状态 id → 定义（通常是 DataLoader.held_states）。
var _defs: Dictionary = {}
## 持有中的实例；每项：id / stacks / kind / remaining / skip_turn_end / params / source_unit_id。
var _entries: Array[Dictionary] = []


func _init(defs: Dictionary = {}) -> void:
	_defs = defs


func set_definitions(defs: Dictionary) -> void:
	_defs = defs


func has_definition(state_id: String) -> bool:
	return _defs.get(state_id, null) is Dictionary


## 施加状态。返回是否改变了持有状态（被忽略、未注册或参数不合法时为 false）。
## `params` 是给予它的技能写明的数值（例如〔架势〕的总降比例），本类只保存不解释。
## `during_own_turn`：施加发生在持有者自己的回合内，影响 until_own_turn_end 的计数。
func apply(state_id: String, stacks: int = 1, duration: Dictionary = {},
		params: Dictionary = {}, source_unit_id: String = "",
		during_own_turn: bool = false) -> bool:
	var def: Dictionary = _definition(state_id)
	if def.is_empty():
		push_error("[HeldStateSet] 未注册的状态 id: " + state_id)
		return false
	if stacks <= 0:
		push_error("[HeldStateSet] 施加层数必须为正: %s ×%d" % [state_id, stacks])
		return false
	var timing: Dictionary = _resolve_duration(state_id, def, duration)
	if timing.is_empty():
		return false
	var max_stacks: int = maxi(1, int(def.get("max_stacks", 1)))
	var incoming_stacks: int = mini(stacks, max_stacks)
	var mode: String = str(def.get("engine_reapplication_mode",
		def.get("reapplication_mode", REAPPLY_IGNORE)))
	var index: int = _index_of(state_id)
	if index < 0 or mode == REAPPLY_INDEPENDENT:
		_entries.append(_new_entry(state_id, incoming_stacks, timing, params,
			source_unit_id, during_own_turn))
		changed.emit()
		return true
	var entry: Dictionary = _entries[index]
	match mode:
		REAPPLY_IGNORE:
			return false
		REAPPLY_REFRESH:
			_refresh(entry, timing, params, source_unit_id, during_own_turn)
		REAPPLY_ADD_STACKS:
			var old_stacks: int = int(entry["stacks"])
			entry["stacks"] = mini(old_stacks + incoming_stacks, max_stacks)
			if str(def.get("duration_update_mode", "")) == "use_incoming":
				_refresh(entry, timing, params, source_unit_id, during_own_turn)
			elif int(entry["stacks"]) == old_stacks:
				# 已满层且不刷新持续时间：持有状态没有任何变化。
				return false
		REAPPLY_SET_STACKS:
			entry["stacks"] = incoming_stacks
			_refresh(entry, timing, params, source_unit_id, during_own_turn)
		_:
			push_error("[HeldStateSet] 未知的再获得方式 %s: %s" % [mode, state_id])
			return false
	changed.emit()
	return true


func has(state_id: String) -> bool:
	return _index_of(state_id) >= 0


## 当前层数；独立实例的状态返回各实例层数之和；未持有为 0。
func stacks(state_id: String) -> int:
	var total: int = 0
	for entry: Dictionary in _entries:
		if entry["id"] == state_id:
			total += int(entry["stacks"])
	return total


## 给予状态时写明的参数（副本）；未持有为空字典。独立实例取最早的一份。
func params(state_id: String) -> Dictionary:
	var index: int = _index_of(state_id)
	if index < 0:
		return {}
	var stored: Dictionary = _entries[index]["params"]
	return stored.duplicate(true)


## 剩余计数（until_* 口径的 N）；永久或未持有返回 -1。供 UI 与测试读取。
func remaining(state_id: String) -> int:
	var index: int = _index_of(state_id)
	if index < 0 or _entries[index]["kind"] == DURATION_PERMANENT:
		return -1
	return int(_entries[index]["remaining"])


## 消耗层数，返回实际消耗数；层数归零的实例移除。独立实例的状态按获得顺序依次扣减，
## 与 stacks() 的「各实例层数之和」口径一致。
func consume_stacks(state_id: String, count: int = 1) -> int:
	if count <= 0:
		return 0
	var used: int = 0
	var kept: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		if entry["id"] == state_id and used < count:
			var take: int = mini(count - used, int(entry["stacks"]))
			entry["stacks"] = int(entry["stacks"]) - take
			used += take
			if int(entry["stacks"]) <= 0:
				continue
		kept.append(entry)
	if used == 0:
		return 0
	_entries = kept
	changed.emit()
	return used


## 移除该 id 的全部实例；返回是否移除了任何东西。
func remove(state_id: String) -> bool:
	var kept: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		if entry["id"] != state_id:
			kept.append(entry)
	if kept.size() == _entries.size():
		return false
	_entries = kept
	changed.emit()
	return true


## 持有中的状态 id（去重，按获得顺序）。
func held_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry: Dictionary in _entries:
		var sid: String = str(entry["id"])
		if not ids.has(sid):
			ids.append(sid)
	return ids


func clear() -> void:
	if _entries.is_empty():
		return
	_entries.clear()
	changed.emit()


## 持有者的自身回合开始：until_own_turn_start 计数 −1，到 0 的移除。返回移除的 id。
func on_own_turn_started(is_extra_turn: bool = false) -> Array[String]:
	var expired: Array[String] = []
	if is_extra_turn:
		return expired
	for entry: Dictionary in _entries.duplicate():
		if entry["kind"] != DURATION_UNTIL_OWN_TURN_START:
			continue
		entry["remaining"] = int(entry["remaining"]) - 1
		if int(entry["remaining"]) <= 0:
			_entries.erase(entry)
			expired.append(str(entry["id"]))
	if not expired.is_empty():
		changed.emit()
	return expired


## 持有者的自身回合结束：until_this_turn_end 移除；until_own_turn_end 计数 −1
## （本回合内获得的跳过这一次，额外回合不计数）。返回移除的 id。
func on_own_turn_ended(is_extra_turn: bool = false) -> Array[String]:
	var expired: Array[String] = []
	for entry: Dictionary in _entries.duplicate():
		match entry["kind"]:
			DURATION_UNTIL_THIS_TURN_END:
				_entries.erase(entry)
				expired.append(str(entry["id"]))
			DURATION_UNTIL_OWN_TURN_END:
				if bool(entry["skip_turn_end"]):
					entry["skip_turn_end"] = false
					continue
				if is_extra_turn:
					continue
				entry["remaining"] = int(entry["remaining"]) - 1
				if int(entry["remaining"]) <= 0:
					_entries.erase(entry)
					expired.append(str(entry["id"]))
	# 本回合内获得的 until_own_turn_start 不受影响；until_own_turn_end 的跳过标记
	# 只对获得时所在的那个回合生效，上面已清除。
	if not expired.is_empty():
		changed.emit()
	return expired


func to_array() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		out.append(entry.duplicate(true))
	return out


func load_array(data: Array[Dictionary]) -> void:
	_entries.clear()
	for entry: Dictionary in data:
		_entries.append(entry.duplicate(true))
	changed.emit()


# ── 内部 ─────────────────────────────────────────────

func _definition(state_id: String) -> Dictionary:
	var def: Variant = _defs.get(state_id, null)
	return def if def is Dictionary else {}


func _index_of(state_id: String) -> int:
	for i: int in range(_entries.size()):
		if _entries[i]["id"] == state_id:
			return i
	return -1


## 把调用方给的持续时间规范成 {kind, remaining}；不合法时报错并返回空字典。
func _resolve_duration(state_id: String, def: Dictionary, duration: Dictionary) -> Dictionary:
	if bool(def.get("is_permanent", false)):
		return {"kind": DURATION_PERMANENT, "remaining": -1}
	var kind: String = str(duration.get("kind", ""))
	match kind:
		DURATION_UNTIL_OWN_TURN_START, DURATION_UNTIL_OWN_TURN_END:
			var count: int = int(duration.get("count", 0))
			if count <= 0:
				push_error("[HeldStateSet] %s 的持续时间 %s 缺正整数 count" % [state_id, kind])
				return {}
			return {"kind": kind, "remaining": count}
		DURATION_UNTIL_THIS_TURN_END:
			return {"kind": kind, "remaining": 1}
		DURATION_PERMANENT:
			return {"kind": kind, "remaining": -1}
	# R3.4：非永久状态的持续时间必须由给予它的来源写明。
	push_error("[HeldStateSet] %s 不是永久状态，施加时必须给出持续时间（R3.4）" % state_id)
	return {}


func _new_entry(state_id: String, stacks: int, timing: Dictionary, params: Dictionary,
		source_unit_id: String, during_own_turn: bool) -> Dictionary:
	return {
		"id": state_id,
		"stacks": stacks,
		"kind": timing["kind"],
		"remaining": timing["remaining"],
		"skip_turn_end": during_own_turn and timing["kind"] == DURATION_UNTIL_OWN_TURN_END,
		"params": params.duplicate(true),
		"source_unit_id": source_unit_id,
	}


func _refresh(entry: Dictionary, timing: Dictionary, params: Dictionary,
		source_unit_id: String, during_own_turn: bool) -> void:
	entry["kind"] = timing["kind"]
	entry["remaining"] = timing["remaining"]
	entry["skip_turn_end"] = during_own_turn and timing["kind"] == DURATION_UNTIL_OWN_TURN_END
	entry["params"] = params.duplicate(true)
	entry["source_unit_id"] = source_unit_id
