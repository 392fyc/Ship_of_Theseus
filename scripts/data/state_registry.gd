class_name StateRegistry
extends RefCounted
## 设计库条件状态的引擎侧注册表与求值器。
##
## 条件状态只作为其他效果的触发条件，每次读取时按当前战场数据即时求值，
## 不缓存、不快照，也不自行提供加成。
## `special` Buff 没有通用自动兑现器，需要由具体消费方读取并结算。
## `engine_status=unevaluable` 不等于条件不成立；依赖它的内容必须拒绝注册。
##
## 用法：
##     var reg := StateRegistry.new(DataLoader.states)
##     if reg.is_in_state(unit, "beishui"): ...

## `data/states/*.json` 的 id → 原始 Dictionary，构造时注入（通常是 DataLoader.states）。
var _states: Dictionary = {}


func _init(states: Dictionary = {}) -> void:
	_states = states


## 该状态此刻是否成立；每次读取即时求值，不缓存或快照。
## 未注册、不可求值或缺少 predicate 时返回 false 并告警。
func is_in_state(unit: Unit, state_id: String) -> bool:
	var entry: Dictionary = _entry(state_id)
	if entry.is_empty():
		push_warning("[StateRegistry] 未注册的状态 id: " + state_id)
		return false
	if not is_evaluable(state_id):
		# 不可求值必须告警；消费方应在注册期先用 is_evaluable() 拒收依赖。
		push_warning("[StateRegistry] 状态判不了（engine_status=unevaluable），求值按不成立处理: "
			+ state_id + "；原因: " + get_blocker(state_id))
		return false
	var predicate: Dictionary = entry.get("predicate", {})
	if predicate.is_empty():
		push_warning("[StateRegistry] 状态缺 predicate: " + state_id)
		return false
	return _evaluate(unit, str(predicate.get("type", "")), predicate.get("params", {}))


## 引擎当前是否具备判定该状态的能力（对应 JSON 的 engine_status）。
## 未注册的 id 同样返回 false。
func is_evaluable(state_id: String) -> bool:
	var entry: Dictionary = _entry(state_id)
	if entry.is_empty():
		return false
	return str(entry.get("engine_status", "")) == "evaluable"


## 判不了的原因（对应 JSON 的 engine_blocker）；可判定或未注册时为空串。
func get_blocker(state_id: String) -> String:
	var entry: Dictionary = _entry(state_id)
	if entry.is_empty():
		return ""
	return str(entry.get("engine_blocker", ""))


## 注册条目的**副本**（含设计库镜像字段）；未注册返回空字典。
## 返回副本而非活引用：`_states` 通常就是 DataLoader.states，交出引用会让调用方
## 能就地改掉设计库镜像，那是 §2.2 字段归属表禁的分叉口。
func get_state(state_id: String) -> Dictionary:
	return _entry(state_id).duplicate(true)


## 内部取条目：不拷贝，供本类自用。
func _entry(state_id: String) -> Dictionary:
	var entry: Variant = _states.get(state_id, {})
	return entry if entry is Dictionary else {}


## 已注册的全部状态 id。
func known_state_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: Variant in _states.keys():
		ids.append(str(key))
	return ids


## 谓词求值。新增谓词类型时在此加分支，并在对应 JSON 的 predicate.type 里声明。
## 参数一律从 JSON 的 params 读，不在代码里写死阈值。
func _evaluate(unit: Unit, predicate_type: String, params: Dictionary) -> bool:
	match predicate_type:
		"hp_ratio_at_most":
			# 当前 HP 占上限的百分比不高于阈值。措辞取自设计库 definition 的
			# 「不高于 30%」→ 用 <=（注意词条 afs_frenzy 的低血判定用的是严格 <，两者不同）。
			# 数据不全同样要响亮——这是本类「一律告警、不静默」口径的一部分，
			# 不是「条件不成立」。静默的话，一个没 setup 的单位会表现得跟满血一样。
			if unit == null or unit.stats == null or unit.stats.max_hp <= 0:
				push_warning("[StateRegistry] hp_ratio_at_most 无法求值：单位或 stats 缺失、"
					+ "或 max_hp<=0，按不成立处理")
				return false
			# 阈值必须来自 JSON（项目禁则：不在代码里硬编码数值）。缺键时不能
			# 静默退化成 0——那会让状态永远不成立且无人察觉，与本函数其他
			# 异常路径一律告警的口径也不一致。
			if not params.has("hp_ratio_pct"):
				push_warning("[StateRegistry] hp_ratio_at_most 缺 params.hp_ratio_pct，判定放弃")
				return false
			var threshold_pct: float = float(params["hp_ratio_pct"])
			var hp_ratio_pct: float = float(unit.stats.hp) \
				/ float(unit.stats.max_hp) * 100.0
			return hp_ratio_pct <= threshold_pct
		"offhand_weapon_equipped":
			# 双持按当前两个武器槽即时求值，不缓存装备状态。
			if unit == null:
				push_warning("[StateRegistry] offhand_weapon_equipped 无法求值：单位缺失")
				return false
			return unit.is_dual_wielding()
		_:
			push_warning("[StateRegistry] 未知的 predicate.type: " + predicate_type)
			return false
