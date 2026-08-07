class_name TalentRegistry
extends RefCounted
## 天赋载体（`data/talents/*.json`）的注册与按事件索引 —— Wave 1 · A1。
##
## A1 范围：只接 **after-damage 族三事件**（命中后 / 造成伤害时 / 击杀时）。这三个在
## 引擎里零新钩子可接——`tactical_manager.gd` 的 `_apply_affixes` 分发位就在
## `defender.take_damage()` 之后。命中时 / 暴击时两个真 on-hit 事件需要新开钩子，
## 属 A2，本注册器一律拒收。
##
## ★ 贯穿原则：**宁可不注册，不可错误触发。**
##
## 设计库的 `trigger_condition` 是自由文本，引擎无法通用解析。所以引擎不去猜条件，
## 而是要求每张卡显式声明自己的可执行性（`condition_model` / `requires_states` /
## `engine_effects`，三者已入 lane §2.2 字段归属表）。任何一项对不上就**拒绝注册**，
## 并且拒绝必须响亮：`push_warning` + 进 `rejected_ids()` / `rejection_reason()`
## 可查询清单。绝不静默跳过，更不允许「条件读不懂就当它没有条件」照常触发——那会让
## 天赋在不该触发的时候触发，比不触发危险得多。
##
## 尤其是 `requires_states` 里出现 `engine_status=unevaluable` 的状态时（当前的
## 「双持」就是），拒绝注册是硬判据（Wave 1 任务书 §2.3）：不许把「引擎还做不到」
## 当成「条件不成立」静默消费，否则那些卡会变成永不触发且运行时一声不吭的死卡。
##
## 用法：
##     var states := StateRegistry.new(DataLoader.states)
##     var talents := TalentRegistry.new(DataLoader.talents, states)
##     for t in talents.talents_for_event("击杀时"): ...

## A1 接的三个事件（设计库 trigger_event 的中文原值，不另造英文枚举避免双写）。
const AFTER_DAMAGE_EVENTS: Array[String] = ["命中后", "造成伤害时", "击杀时"]

## A1 支持的触发频率。「每次」= 不限次；其余（每回合 N 次等）需要计数器状态，
## 未实装故拒收——按「宁可不注册」处理，不是当成不限次放行。
const SUPPORTED_FREQUENCIES: Array[String] = ["每次"]

## `condition_model` 的合法取值。
const CONDITION_MODELS: Array[String] = ["none", "states", "unsupported"]

## `engine_effects` 支持的指令类型。
const SUPPORTED_EFFECT_TYPES: Array[String] = ["gain_resource"]

## `gain_resource` 支持的资源 id（设计库 `/api/resources` 的 id）。
const SUPPORTED_RESOURCES: Array[String] = ["qi", "mark"]

var _registered: Dictionary = {}   # id -> 条目
var _rejected: Dictionary = {}     # id -> 拒绝理由
var _by_event: Dictionary = {}     # 事件中文名 -> Array[Dictionary]


## state_registry 形参类型写 RefCounted 而不是 StateRegistry：Godot 的全局类名缓存
## 只在编辑器导入时重建，headless 下引用新 class_name 会解析失败（详见
## tactical_manager.gd 里 preload 两行的注释）。调用方传 StateRegistry 实例即可。
func _init(talents: Dictionary = {}, state_registry: RefCounted = null) -> void:
	_build(talents, state_registry)


func _build(talents: Dictionary, state_registry: RefCounted) -> void:
	for key: Variant in talents.keys():
		var tid: String = str(key)
		var entry: Variant = talents[key]
		if not entry is Dictionary:
			_reject(tid, "条目不是字典")
			continue
		var reason: String = _rejection_reason(entry, state_registry)
		if reason != "":
			_reject(tid, reason)
			continue
		_registered[tid] = entry
		var event: String = str(entry.get("trigger_event", ""))
		if not _by_event.has(event):
			_by_event[event] = []
		_by_event[event].append(entry)


func _reject(tid: String, reason: String) -> void:
	_rejected[tid] = reason
	push_warning("[TalentRegistry] 拒绝注册天赋 %s：%s" % [tid, reason])


## 返回拒绝理由；空串表示可以注册。检查顺序按「最有信息量的理由优先」排。
func _rejection_reason(entry: Dictionary, state_registry: RefCounted) -> String:
	var event: String = str(entry.get("trigger_event", ""))
	if event == "":
		return "缺 trigger_event"
	if event not in AFTER_DAMAGE_EVENTS:
		return "事件「%s」不在 A1 范围（A1 只接 after-damage 三事件 %s；命中时/暴击时属 A2）" \
			% [event, str(AFTER_DAMAGE_EVENTS)]

	var model: String = str(entry.get("condition_model", ""))
	if model == "":
		return "缺 condition_model（必须显式声明条件的引擎表达力）"
	if model not in CONDITION_MODELS:
		return "condition_model「%s」非法，合法值 %s" % [model, str(CONDITION_MODELS)]
	if model == "unsupported":
		return "condition_model=unsupported：条件含引擎尚不能表达的部分，按「宁可不注册」拒收"

	var condition: String = str(entry.get("trigger_condition", ""))
	var required: Array = entry.get("requires_states", []) as Array
	# 声明与镜像数据必须自洽，否则说明建卡时判断错了。
	if model == "none" and condition.strip_edges() != "":
		return "condition_model=none 但 trigger_condition 非空（「%s」）——声明与设计库镜像矛盾" % condition
	if model == "states" and required.is_empty():
		return "condition_model=states 但 requires_states 为空——声明与数据矛盾"

	# ★ 硬判据：依赖的状态必须已注册且引擎判得了。
	for item: Variant in required:
		var sid: String = str(item)
		if state_registry == null:
			return "依赖状态「%s」但未提供 StateRegistry，无法核验" % sid
		if state_registry.get_state(sid).is_empty():
			return "依赖的状态「%s」未在 data/states/ 注册" % sid
		if not state_registry.is_evaluable(sid):
			return "依赖的状态「%s」引擎判不了（%s）——按 Wave 1 §2.3 响亮失败，拒绝注册" \
				% [sid, state_registry.get_blocker(sid)]

	var frequency: String = str(entry.get("trigger_frequency", ""))
	if frequency not in SUPPORTED_FREQUENCIES:
		return "触发频率「%s」未实装（当前只支持 %s），拒收而非当作不限次" \
			% [frequency, str(SUPPORTED_FREQUENCIES)]

	var effects: Array = entry.get("engine_effects", []) as Array
	if effects.is_empty():
		return "engine_effects 为空——没有可执行的效果，注册了也是死卡"
	for item: Variant in effects:
		if not item is Dictionary:
			return "engine_effects 含非字典项"
		var effect: Dictionary = item
		var effect_type: String = str(effect.get("type", ""))
		if effect_type not in SUPPORTED_EFFECT_TYPES:
			return "engine_effects 含未知 type「%s」（当前支持 %s）" \
				% [effect_type, str(SUPPORTED_EFFECT_TYPES)]
		if effect_type == "gain_resource":
			var resource: String = str(effect.get("resource", ""))
			if resource not in SUPPORTED_RESOURCES:
				return "gain_resource 的 resource「%s」未支持（当前支持 %s）" \
					% [resource, str(SUPPORTED_RESOURCES)]
			if int(effect.get("amount", 0)) <= 0:
				return "gain_resource 的 amount 必须为正整数"

	return ""


## 该事件下已注册的天赋条目（副本列表，元素是活引用——调用方只读）。
func talents_for_event(event: String) -> Array:
	var found: Variant = _by_event.get(event, [])
	return (found as Array).duplicate() if found is Array else []


func is_registered(talent_id: String) -> bool:
	return _registered.has(talent_id)


func registered_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: Variant in _registered.keys():
		ids.append(str(key))
	return ids


## 被拒绝的天赋 id。这是「响亮失败」的可观测信号之一，测试据此断言。
func rejected_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: Variant in _rejected.keys():
		ids.append(str(key))
	return ids


## 某张天赋被拒的理由；未被拒则为空串。
func rejection_reason(talent_id: String) -> String:
	return str(_rejected.get(talent_id, ""))


## 注册条目的副本；未注册返回空字典。
func get_talent(talent_id: String) -> Dictionary:
	var entry: Variant = _registered.get(talent_id, {})
	return (entry as Dictionary).duplicate(true) if entry is Dictionary else {}
