class_name StateRegistry
extends RefCounted
## 设计库 State 注册表（`/api/states`）的引擎侧映射与求值器。
##
## 这里承接的是设计库里 `kind=条件` / `duration_kind=条件维持` 的那一类状态：
## 它们**即时判定、不快照、本身不提供任何加成**，只作为其他效果的触发与生效条件被引用。
##
## 为什么不落 `data/buffs/`（2026-08-07 路径 C，判断依据留档在此）：
##   BuffEffect 是「实例 + 时长」模型——必须由技能 effects 显式 `add_buff` 挂载
##   （tactical_manager.gd:1751 是唯一挂载入口），此后按回合递减 duration
##   （unit.gd:254-264）。而条件类状态没有挂载动作、没有时长，其成立与否必须在
##   每次读取时以当时的战场数据重新求值。若做成 buff，HP 回升后旧实例不会自动脱离，
##   直接违反「HP 高于 30% 时脱离」；要让它跟随就得在 take_damage / heal 之后加重算钩子，
##   那是结算主循环，路径 C 明令不碰。另外 BuffEffect 的四种 effect_type
##   （stat_mod / dot / control / special）没有一种对应「纯条件、不给加成」，
##   落 special 会变成又一个无兑现器的死标记（先例：swordsman_parry_stance）。
##
## 因此条件类状态走本注册表：只读 `data/states/*.json`，只提供查询，不进任何结算路径。
## 真正的消费方是 Wave 1 的天赋载体（把「处于〔X〕状态」的条件段接到这里），
## 本轮不建载体，故当前无生产调用方——这是有意为之的地基件。
##
## 用法：
##     var reg := StateRegistry.new(DataLoader.states)
##     if reg.is_in_state(unit, "beishui"): ...
##
## 判不了 ≠ 判定为否：`engine_status=unevaluable` 的条目求值恒 false，但
## `is_evaluable()` 会返回 false 且 `get_blocker()` 给出原因。消费方若关心区别，
## 必须先问 `is_evaluable`，不要把「引擎还做不到」静默当成「条件不成立」。

## `data/states/*.json` 的 id → 原始 Dictionary，构造时注入（通常是 DataLoader.states）。
var _states: Dictionary = {}


func _init(states: Dictionary = {}) -> void:
	_states = states


## 该状态此刻是否成立。即时求值，不缓存、不快照。
## 未注册的 id、判不了的条目、缺 predicate 的条目一律返回 false（并告警，不静默）。
func is_in_state(unit: Unit, state_id: String) -> bool:
	var entry: Dictionary = _entry(state_id)
	if entry.is_empty():
		push_warning("[StateRegistry] 未注册的状态 id: " + state_id)
		return false
	if not is_evaluable(state_id):
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
			if unit == null or unit.stats == null or unit.stats.max_hp <= 0:
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
			# 引擎无副手武器槽，恒不成立；原因见 shuangchi.json 的 engine_blocker。
			# 该分支不会被 is_in_state 走到（engine_status=unevaluable 已先行拦截），
			# 留在这里是为了标出将来副手槽建好后的接线位置。
			return false
		_:
			push_warning("[StateRegistry] 未知的 predicate.type: " + predicate_type)
			return false
