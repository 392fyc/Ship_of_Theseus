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
## 可查询清单。绝不静默跳过，更不允许「条件读不懂就当它没有条件」照常触发。
##
## 尤其是 `requires_states` 里出现 `engine_status=unevaluable` 的状态时（当前的
## 「双持」就是），拒绝注册是硬判据（Wave 1 任务书 §2.3）：不许把「引擎还做不到」
## 当成「条件不成立」静默消费，否则那些卡会变成永不触发且运行时一声不吭的死卡。
##
## ── 条件把关分两层，本文件只管第一层 ──────────────────
##
##   第一层 · 注册期（本文件）：问「引擎**有没有能力**判定这个条件」。判不了的、
##   声明不自洽的、效果执行不了的，一律拒收，不进池。
##
##   第二层 · 运行期（`tactical_manager._talent_conditions_hold`）：问「此刻条件
##   **成立不成立**」。对每张已注册卡的 `requires_states` 逐个调
##   `StateRegistry.is_in_state()` 即时求值，不成立就不触发。
##
## 两层缺一不可。只做第一层的话，`condition_model=states` 的卡会在条件不成立时
## 照常触发——2026-08-08 的独立验证正是在这里抓到过一个真实缺陷（满血单位触发了
## 依赖〔背水〕的天赋），修法就是补上第二层。改动本文件的拒收逻辑时，别把这段
## 分工忘了：放宽注册期而运行期没有对应的求值，等于开洞。
##
## ── A1 不处理的东西（明确记下，免得误以为已覆盖）──────
##
##   - **附加触发行**（设计库 `talent_trigger_extra` / `extra_triggers` 子表）：
##     引擎侧零认知，既不读也不分发。当前唯一在用附加行的两张卡（二天一流、
##     剑气回荡）都是双持系、已被排除，故暂无影响；将来接附加行要在这里扩。
##   - **`trigger_object` / `trigger_source` 两个槽**：同样不读。
##   - **超出 `requires_states` 的条件**：一律走 `condition_model=unsupported` 拒收，
##     不做部分执行。
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

## 单次资源获取量的合理性上限。**这不是游戏数值**（游戏数值一律从 JSON 读），
## 是一道防手误的护栏：剑气上限 100、印记上限 3，写出三位数以上必然是打错了位数。
## 真要超过它，说明设计变了，那就连这个常量一起改，而不是让错数据静默通过。
const MAX_RESOURCE_GAIN: int = 999

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
		# 条目内 id 必须与注册键一致。不一致会造成「按键查得到、按 id 分发不到」
		# （或反过来）的错配——分发用的是条目内 id，注册/查询用的是键。
		var inner_id: String = str(entry.get("id", ""))
		if inner_id != tid:
			_reject(tid, "条目内 id「%s」与注册键「%s」不一致" % [inner_id, tid])
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
	# 形状先于语义：`as Array` 对非数组会抛 cast 错误然后**放行**，一个漏写的
	# 方括号就能让下面整个状态依赖循环被跳过、绕过 §2.3 硬判据。必须显式判类型。
	var required_raw: Variant = entry.get("requires_states", [])
	if not required_raw is Array:
		return "requires_states 必须是数组，实际是 %s（写成裸字符串会绕过状态依赖检查）" \
			% type_string(typeof(required_raw))
	var required: Array = required_raw
	# 声明与镜像数据必须自洽，否则说明建卡时判断错了。
	if model == "none" and condition.strip_edges() != "":
		return "condition_model=none 但 trigger_condition 非空（「%s」）——声明与设计库镜像矛盾" % condition
	if model == "states" and required.is_empty():
		return "condition_model=states 但 requires_states 为空——声明与数据矛盾"

	# ★ 硬判据：依赖的状态必须已注册且引擎判得了。
	for item: Variant in required:
		if not item is String:
			return "requires_states 的元素必须是状态 id 字符串，实际含 %s" \
				% type_string(typeof(item))
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

	var effects_raw: Variant = entry.get("engine_effects", [])
	if not effects_raw is Array:
		return "engine_effects 必须是数组，实际是 %s" % type_string(typeof(effects_raw))
	var effects: Array = effects_raw
	if effects.is_empty():
		return "engine_effects 为空——没有可执行的效果，注册了也是死卡"
	for item: Variant in effects:
		if not item is Dictionary:
			return "engine_effects 含非字典项（%s）" % type_string(typeof(item))
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
			# amount 必须是整数值的数字。要卡的是「字符串 "20"」这类错类型——
			# 它经 int() 也能变成 20，静默通过就等于接受了错数据。
			# ★ 但不能直接要求 TYPE_INT：Godot 的 JSON.parse 把**所有**数字都解析成
			# float，JSON 里写 20 读出来是 20.0。只有 GDScript 内联字面量才是 int。
			# 所以判「是不是数字」+「有没有小数部分」，而不是判 int。
			var amount_raw: Variant = effect.get("amount", null)
			var amount_type: int = typeof(amount_raw)
			if amount_type != TYPE_INT and amount_type != TYPE_FLOAT:
				return "gain_resource 的 amount 必须是数字，实际是 %s" \
					% type_string(amount_type)
			if amount_type == TYPE_FLOAT and float(amount_raw) != floorf(float(amount_raw)):
				return "gain_resource 的 amount 必须是整数值，实际 %s 含小数部分" \
					% str(amount_raw)
			var amount: int = int(amount_raw)
			if amount <= 0:
				return "gain_resource 的 amount 必须为正整数，实际 %d" % amount
			if amount > MAX_RESOURCE_GAIN:
				return "gain_resource 的 amount %d 超出合理上限 %d（疑似手误多打了位数）" \
					% [amount, MAX_RESOURCE_GAIN]

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
