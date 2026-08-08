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
## ── 附加触发行（Wave 2 起支持）─────────────────────
##
## 设计库的 `talent_trigger_extra` / `extra_triggers` 子表承载**另一组触发五段**，
## 效果仍共用卡级 `engine_effects`（子表本身没有效果字段）。引擎侧的条件字段
## （`requires_states` / `condition_model`）附加行**各自独立**——二天一流的机制主体
## 就只挂在附加行上（事件「执行攻击动作时」、条件「处于〔双持〕状态」），主行则是
## 永久生效无条件。两者必须分开求值，退回卡级就错了。
##
## 注册时整卡摊平成触发行列表（`_trigger_rows`），逐行校验；**任一行不合格整卡拒收**
## ——不做「主行注册、附加行丢弃」，那会让一张卡半生效，而设计库那边看到的是完整的卡。
##
## ── 仍然不处理的东西（明确记下，免得误以为已覆盖）──────
##
##   - **`trigger_object` / `trigger_source` 两个槽**：不读。设计库侧 `trigger_source`
##     是「主手 / 副手」闭集，当前 3 张卡在用；引擎分发时不区分来源手别。
##   - **超出 `requires_states` 的条件**：一律走 `condition_model=unsupported` 拒收，
##     不做部分执行。
##   - **命中时 / 暴击时**两个真 on-hit 事件：属 A2，未接，注册期拒收。
##
## 用法：
##     var states := StateRegistry.new(DataLoader.states)
##     var talents := TalentRegistry.new(DataLoader.talents, states)
##     for t in talents.talents_for_event("击杀时"): ...

## A1 接的三个 after-damage 事件（设计库 trigger_event 的中文原值，不另造英文枚举避免双写）。
const AFTER_DAMAGE_EVENTS: Array[String] = ["命中后", "造成伤害时", "击杀时"]

## Wave 2 新接的动作级事件。它比「命中时」还早——在命中判定之前，
## 分发点在 `_execute_hostile_action` 开头（`resolve_attack` 之前）。
## 与 A2 的真 on-hit 钩子（命中时 / 暴击时）**不是同一处**，故不越 A2 的界。
const ACTION_EVENTS: Array[String] = ["执行攻击动作时"]

## 引擎当前能分发的全部事件。
const SUPPORTED_EVENTS: Array[String] = [
	"命中后", "造成伤害时", "击杀时", "执行攻击动作时",
]

## 常驻类事件——**不是**触发时机，而是「一直生效」。这类行不进事件桶（没有可分发的
## 时点），也不因此拒卡；它对应的机制由别处承载（例如二天一流的「失去防具槽、该槽改
## 副手武器槽」是装备层的事，不是战斗事件）。一张卡若**只有**常驻行、无任何可分发行，
## 仍会被拒——引擎当前没有承载纯常驻天赋的通道，宁可不注册。
const PASSIVE_EVENTS: Array[String] = ["永久生效"]

## A1 支持的触发频率。「每次」= 不限次；其余（每回合 N 次等）需要计数器状态，
## 未实装故拒收——按「宁可不注册」处理，不是当成不限次放行。
const SUPPORTED_FREQUENCIES: Array[String] = ["每次"]

## `condition_model` 的合法取值。
const CONDITION_MODELS: Array[String] = ["none", "states", "unsupported"]

## `engine_effects` 支持的指令类型。
const SUPPORTED_EFFECT_TYPES: Array[String] = ["gain_resource", "offhand_followup"]

## `offhand_followup` 的伤害百分比合理上限（护栏，不是游戏数值——数值从 JSON 读）。
const MAX_FOLLOWUP_PCT: int = 1000

## 引擎侧的伤害类型 taxonomy。注意它与设计库的 `damage_type`（无/物理/魔法/混合）
## 是**两套独立枚举**，不要互相套用（见 sot-designlib SKILL.md 第七节）。
const SUPPORTED_DAMAGE_TYPES: Array[String] = ["physical", "magical", "pure"]

## `gain_resource` 支持的资源 id（设计库 `/api/resources` 的 id）。
const SUPPORTED_RESOURCES: Array[String] = ["qi", "mark"]

## 单次资源获取量的合理性上限。**这不是游戏数值**（游戏数值一律从 JSON 读），
## 是一道防手误的护栏：剑气上限 100、印记上限 3，写出三位数以上必然是打错了位数。
## 真要超过它，说明设计变了，那就连这个常量一起改，而不是让错数据静默通过。
const MAX_RESOURCE_GAIN: int = 999

var _registered: Dictionary = {}   # id -> 条目
var _rejected: Dictionary = {}     # id -> 拒绝理由
# 事件中文名 -> Array[Dictionary]，元素是**触发行包裹**而非整条天赋：
#   { "talent": <整条天赋条目>, "trigger": <该触发行的五段+引擎条件字段>, "row": "main"|"extra[i]" }
# 一张卡有主行和附加行时会在**多个事件桶**里各出现一次，分发时必须用行级的
# requires_states / condition_model 求值，不能退回卡级——那正是附加行的意义所在。
var _by_event: Dictionary = {}


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
		var rows: Array = _trigger_rows(entry)
		if rows.is_empty():
			_reject(tid, "无任何可分发的触发行（主行缺 trigger_event 或只是常驻 %s，且无 extra_triggers）——"
				% str(PASSIVE_EVENTS) + "引擎当前没有承载纯常驻天赋的通道")
			continue
		# 整卡拒收粒度：任一触发行不合格就整卡拒。不做「主行注册、附加行丢弃」——
		# 那会让一张卡半生效，而设计库那边看到的是完整的卡，两边理解不一致。
		var reason: String = ""
		for row: Dictionary in rows:
			reason = _row_rejection_reason(row, state_registry)
			if reason != "":
				break
		if reason == "":
			reason = _effects_rejection_reason(entry)
		if reason != "":
			_reject(tid, reason)
			continue
		_registered[tid] = entry
		for row: Dictionary in rows:
			var trigger: Dictionary = row["trigger"]
			var event: String = str(trigger.get("trigger_event", ""))
			if not _by_event.has(event):
				_by_event[event] = []
			_by_event[event].append({
				"talent": entry, "trigger": trigger, "row": str(row["row"]),
			})


## 把一张天赋摊平成触发行列表：主行 + 每条附加行各一项。
##
## 附加触发行（设计库 `talent_trigger_extra` 子表）承载的是**另一组触发五段**，
## 效果仍共用卡级 `engine_effects`——设计库那边子表只有触发字段、没有效果字段。
## 引擎侧的条件字段（`requires_states` / `condition_model`）附加行**各自独立**：
## 二天一流的附加行条件是「处于〔双持〕状态」，主行则是永久生效无条件，
## 两者必须分开求值，退回卡级就错了。
##
## 返回 `[{"trigger": <五段+条件字段>, "row": "main"|"extra[i]"}, ...]`。
## 主行 trigger_event 为空视为「这张卡没有主触发行」（例如机制全挂在附加行上），
## 此时只返回附加行——但整卡至少要有一行，否则 `_build` 会拒收。
func _trigger_rows(entry: Dictionary) -> Array:
	var rows: Array = []
	var main_event: String = str(entry.get("trigger_event", ""))
	# 常驻主行不进桶（没有分发时点），但也不算这张卡缺行——它的机制由别处承载。
	if main_event != "" and main_event not in PASSIVE_EVENTS:
		rows.append({"trigger": entry, "row": "main"})
	var extras: Variant = entry.get("extra_triggers", [])
	if extras is Array:
		var idx: int = 0
		for item: Variant in (extras as Array):
			if item is Dictionary:
				rows.append({"trigger": item, "row": "extra[%d]" % idx})
			else:
				# 形状不对不能静默丢——丢了就等于「附加行不存在」，
				# 而设计库那边它是存在的，两边理解会分叉。塞一个必被拒的空行。
				rows.append({"trigger": {}, "row": "extra[%d]" % idx})
			idx += 1
	return rows


func _reject(tid: String, reason: String) -> void:
	_rejected[tid] = reason
	push_warning("[TalentRegistry] 拒绝注册天赋 %s：%s" % [tid, reason])


## 单条触发行的拒绝理由；空串表示这一行合格。**逐行调用**，主行与每条附加行各一次。
## 检查顺序按「最有信息量的理由优先」排。
func _row_rejection_reason(row: Dictionary, state_registry: RefCounted) -> String:
	var entry: Dictionary = row["trigger"]
	var where: String = str(row["row"])
	var event: String = str(entry.get("trigger_event", ""))
	if event == "":
		return "触发行 %s 缺 trigger_event" % where
	if event not in SUPPORTED_EVENTS:
		return "触发行 %s 的事件「%s」引擎不分发（当前支持 %s；命中时/暴击时属 A2 未接）" \
			% [where, event, str(SUPPORTED_EVENTS)]

	var model: String = str(entry.get("condition_model", ""))
	if model == "":
		return "触发行 %s 缺 condition_model（必须显式声明条件的引擎表达力）" % where
	if model not in CONDITION_MODELS:
		return "触发行 %s 的 condition_model「%s」非法，合法值 %s" \
			% [where, model, str(CONDITION_MODELS)]
	if model == "unsupported":
		return "触发行 %s 的 condition_model=unsupported：条件含引擎尚不能表达的部分，按「宁可不注册」拒收" % where

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

	return ""


## 卡级效果检查（`engine_effects` 由主行与全部附加行共用，只查一次）。
## 设计库的 `talent_trigger_extra` 子表只承载触发五段、没有效果字段，所以效果
## 天然是卡级的——附加行触发时执行的是同一组 `engine_effects`。
func _effects_rejection_reason(entry: Dictionary) -> String:
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
		elif effect_type == "offhand_followup":
			# 副手追加攻击。damage_pct 是游戏数值，必须来自 JSON（设计库二天一流的
			# effect 逐字写的是 50%），代码只做类型与合理性校验，不写死数值。
			var pct_raw: Variant = effect.get("damage_pct", null)
			var pct_type: int = typeof(pct_raw)
			if pct_type != TYPE_INT and pct_type != TYPE_FLOAT:
				return "offhand_followup 的 damage_pct 必须是数字，实际是 %s" \
					% type_string(pct_type)
			var pct: float = float(pct_raw)
			if pct <= 0.0:
				return "offhand_followup 的 damage_pct 必须为正，实际 %s" % str(pct_raw)
			if pct > float(MAX_FOLLOWUP_PCT):
				return "offhand_followup 的 damage_pct %s 超出合理上限 %d" \
					% [str(pct_raw), MAX_FOLLOWUP_PCT]
			# damage_type 与 damage_pct 出自设计库同一句 effect（「50%物理伤害」），
			# 两个值都要从 JSON 读——一个进 JSON、一个写死在代码里是口径不一致。
			var dtype: String = str(effect.get("damage_type", ""))
			if dtype not in SUPPORTED_DAMAGE_TYPES:
				return "offhand_followup 的 damage_type「%s」未支持（当前支持 %s）" \
					% [dtype, str(SUPPORTED_DAMAGE_TYPES)]

	return ""


## 该事件下的**触发行包裹**列表，每项 = `{"talent": 整条天赋, "trigger": 该触发行,
## "row": "main"|"extra[i]"}`。同一张卡若有多行落在不同事件，会在各自的桶里出现。
##
## ★ 分发时的条件求值必须读 `["trigger"]` 里的 `requires_states`，**不是**
## `["talent"]` 里的——附加行有自己的条件，退回卡级会让二天一流那种
## 「主行无条件、附加行要求双持」的卡在不该触发时触发。
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
