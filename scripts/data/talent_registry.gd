class_name TalentRegistry
extends RefCounted
## 天赋载体的注册、触发行索引与执行边界。
##
## 贯穿原则：宁可拒绝注册，也不可错误触发。注册期核验引擎是否能完整表达
## `condition_model` 声明的条件；运行期再按当前状态逐行求值。
## `requires_states` 引用的状态必须已注册且可求值，不可求值时整卡拒收并保留原因。
##
## 字段边界：`trigger_source` 来自设计库；`requires_states`、`requires_contexts`、
## `requires_turn_phase` 与 `engine_effects` 是引擎侧结构字段；`trigger_object` 当前不读。
## 附加触发行各自保存条件字段，效果保存在卡级并可通过 `row` 绑定触发行。
##
## 用法：
##     var states := StateRegistry.new(DataLoader.states)
##     var talents := TalentRegistry.new(DataLoader.talents, states)

## 伤害结算后分发的三个事件，使用设计库 trigger_event 中文原值。
const AFTER_DAMAGE_EVENTS: Array[String] = ["命中后", "造成伤害时", "击杀时"]

## 动作级事件在命中判定之前分发。
const ACTION_EVENTS: Array[String] = ["执行攻击动作时"]

## on-hit 事件在伤害数值结算之前分发，可修改本次伤害参数。
## ⚠ R1.4 逐字只把效果时机分成 on-hit 与 after-damage **两类**，规则层没有独立的
## 「暴击时」。所以引擎把「暴击时」实现为 on-hit 的**条件化分支**：命中且暴击时，
## 与「命中时」在同一时点、同一次分发批次里发出，而不是并列的第三类时机。
const ON_HIT_EVENTS: Array[String] = ["命中时", "暴击时"]

## 防御侧事件分发给被攻击者，时点在命中判定之后、伤害数值结算之前。
const DEFENSIVE_EVENTS: Array[String] = ["受到攻击时"]

## 引擎当前能分发的全部事件。
const SUPPORTED_EVENTS: Array[String] = [
	"命中后", "造成伤害时", "击杀时", "执行攻击动作时", "命中时", "暴击时",
	"受到攻击时",
]

## `trigger_source` 的闭集（不含空串——空串单独判，语义是「不限来源」）。
const SUPPORTED_TRIGGER_SOURCES: Array[String] = ["主手", "副手"]

## 带伤害来源的事件。设计库侧 `trigger_source` 的 schema 绑在攻击链五事件上；
## 引擎再加上防御侧的「受到攻击时」——被打的那一下同样分得清是主手还是副手打的，
## 主手与副手追加会各分发一次。「执行攻击动作时」不在内：那一刻还没掷命中，
## 谈不上来源。
const SOURCE_BEARING_EVENTS: Array[String] = [
	"命中时", "暴击时", "命中后", "造成伤害时", "击杀时", "受到攻击时",
]

## `requires_contexts` 的闭集：本次伤害的产生路径标签。
const SUPPORTED_CONTEXTS: Array[String] = ["active_attack"]

## `requires_turn_phase` 的闭集（不含空串——空串单独判，语义是「不限」）。
## 只收当前真有消费方的那一个值：交刃要求「不处于自身回合内」。
## 反向的 `own_turn` 没有任何卡需要，故不预先造——`swordsman_parry_stance` 那个
## 挂上后全库零消费方的死标记就是先例。
const SUPPORTED_TURN_PHASES: Array[String] = ["outside_own_turn"]

## `more_damage_from_stat` / `offhand_recursive_followup` 允许读取的属性名。
## 照 2026-07-08 定的 9 属性模型（成长 7 + 固定 2），此处列可被效果读取的 8 个
## （HP 不在内——按属性读 HP 做伤害系数没有已知设计意图，要用时再开）。
const SUPPORTED_STATS: Array[String] = [
	"STR", "MAG", "DEX", "SPD", "DEF", "RES", "LCK", "MOV",
]

## 常驻类事件——**不是**触发时机，而是「一直生效」。这类行不进事件桶（没有可分发的
## 时点），也不因此拒卡；它对应的机制由别处承载（例如二天一流的「失去防具槽、该槽改
## 副手武器槽」是装备层的事，不是战斗事件）。一张卡若**只有**常驻行、无任何可分发行，
## 仍会被拒——引擎当前没有承载纯常驻天赋的通道，宁可不注册。
const PASSIVE_EVENTS: Array[String] = ["永久生效"]

## 触发频率当前只支持「每次」；其他频率需要计数器状态，注册期拒收。
const SUPPORTED_FREQUENCIES: Array[String] = ["每次"]

## `condition_model` 的合法取值。
const CONDITION_MODELS: Array[String] = ["none", "states", "unsupported"]

## `engine_effects` 支持的指令类型。
const SUPPORTED_EFFECT_TYPES: Array[String] = [
	"gain_resource", "offhand_followup", "unlock_offhand_weapon_effect",
	"empower_next_offhand", "more_damage_from_stat",
	"offhand_recursive_followup", "parry_damage_reduction",
]

## 递归追加的衰减系数下限（护栏）。衰减必须真的衰减——填 100 就是永不衰减的
## 无限链。这不是游戏数值，是防手误。
const MIN_CHANCE_DECAY_PCT: float = 1.0
const MAX_CHANCE_DECAY_PCT: float = 99.0

## 效果类型 → 它能挂在哪些**可分发事件**上。不在表里的（`gain_resource`）= 任何
## 时机都能执行。值为**空数组** = 常驻类效果，只能挂常驻行。
##
## 为什么要管这个：效果的执行分支是往 ctx 里写一个键，而那个键只有特定时点的
## 消费方会读。挂错时机时，效果**被静默吞掉**——ctx 里那个键没人读——而日志还
## 照样打印「已生效」。这种失效最难查，所以在注册期就拦住。
##
## `offhand_followup` 只允许动作级事件，避免被自身产生的副手事件再次触发；
## 可递归追加必须使用带 `self_retriggerable` 明示开关的效果类型。
const EFFECT_ALLOWED_EVENTS: Dictionary = {
	"offhand_followup": ["执行攻击动作时"],
	"offhand_recursive_followup": ["命中后", "造成伤害时"],
	"empower_next_offhand": ["命中时", "暴击时"],
	"more_damage_from_stat": ["命中时", "暴击时"],
	"unlock_offhand_weapon_effect": [],
	"parry_damage_reduction": ["受到攻击时"],
}

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
# 常驻天赋（trigger_event ∈ PASSIVE_EVENTS）：没有触发时点，不进事件桶，改由消费方
# 主动查询「该单位有没有这张卡、它的条件此刻成不成立」。二刀开刃就是这一类——
# 它不是某个时机触发，而是一个持续生效的开关（解锁副手武器特效、按 50% 折算）。
var _passive: Dictionary = {}      # id -> {"talent": 条目, "trigger": 常驻行}


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
			_reject(tid, "无任何触发行（主行缺 trigger_event 且无 extra_triggers）")
			continue
		# 整卡拒收粒度：任一触发行不合格就整卡拒。不做「主行注册、附加行丢弃」——
		# 那会让一张卡半生效，而设计库那边看到的是完整的卡，两边理解不一致。
		var reason: String = ""
		for row: Dictionary in rows:
			reason = _row_rejection_reason(row, state_registry)
			if reason != "":
				break
		if reason == "":
			reason = _effects_rejection_reason(entry, rows)
		if reason != "":
			_reject(tid, reason)
			continue
		_registered[tid] = entry
		for row: Dictionary in rows:
			var trigger: Dictionary = row["trigger"]
			if bool(row.get("passive", false)):
				_passive[tid] = {
					"talent": entry, "trigger": trigger, "row": str(row["row"]),
				}
				continue
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
	if main_event != "":
		# 常驻行照样进 rows（要过同一套条件与频率校验），只是打上标记——
		# _build 会把它放进 _passive 而不是事件桶。
		rows.append({
			"trigger": entry, "row": "main",
			"passive": main_event in PASSIVE_EVENTS,
		})
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
	# 常驻行不进事件桶，它的合法事件名是 PASSIVE_EVENTS，不是可分发事件表。
	if bool(row.get("passive", false)):
		if event not in PASSIVE_EVENTS:
			return "触发行 %s 被标为常驻但事件「%s」不在 %s" \
				% [where, event, str(PASSIVE_EVENTS)]
	elif event not in SUPPORTED_EVENTS:
		return "触发行 %s 的事件「%s」引擎不分发（当前支持 %s）" \
			% [where, event, str(SUPPORTED_EVENTS)]

	var model: String = str(entry.get("condition_model", ""))
	if model == "":
		return "触发行 %s 缺 condition_model（必须显式声明条件的引擎表达力）" % where
	if model not in CONDITION_MODELS:
		return "触发行 %s 的 condition_model「%s」非法，合法值 %s" \
			% [where, model, str(CONDITION_MODELS)]
	if model == "unsupported":
		return "触发行 %s 的 condition_model=unsupported：条件含引擎尚不能表达的部分，按「宁可不注册」拒收" % where

	# trigger_source 空串表示不限来源；非空值必须在设计库闭集内。
	var source: String = str(entry.get("trigger_source", "")).strip_edges()
	if source != "" and source not in SUPPORTED_TRIGGER_SOURCES:
		return "触发行 %s 的 trigger_source「%s」不在闭集 %s 内（空串=不限来源）" \
			% [where, source, str(SUPPORTED_TRIGGER_SOURCES)]
	# 来源只对攻击链五事件有意义（设计库 schema 也是这么绑的）。「执行攻击动作时」
	# 发生在命中判定之前，那一刻还没有伤害、也就谈不上由哪只手产生——一张卡若把
	# 来源挂在那种事件上，说明建卡时判断错了，拒收比静默忽略掉那个限制安全。
	if source != "" and event not in SOURCE_BEARING_EVENTS:
		return "触发行 %s 指定了 trigger_source「%s」，但事件「%s」不带伤害来源（带来源的只有 %s）" \
			% [where, source, event, str(SOURCE_BEARING_EVENTS)]

	# requires_contexts 是触发行级的引擎字段。
	var contexts_raw: Variant = entry.get("requires_contexts", [])
	if not contexts_raw is Array:
		return "触发行 %s 的 requires_contexts 必须是数组，实际是 %s" \
			% [where, type_string(typeof(contexts_raw))]
	for item: Variant in (contexts_raw as Array):
		if not item is String:
			return "触发行 %s 的 requires_contexts 元素必须是字符串，实际含 %s" \
				% [where, type_string(typeof(item))]
		if str(item) not in SUPPORTED_CONTEXTS:
			return "触发行 %s 依赖的产生路径「%s」引擎不注入（当前只有 %s）——依赖它的卡永不触发，拒收" \
				% [where, str(item), str(SUPPORTED_CONTEXTS)]
	# 常驻行不许带产生路径。理由与 trigger_source 那条对称：常驻行没有「本次伤害」，
	# 谈不上它由哪条路径产生；而常驻天赋的消费方（_offhand_effect_scale）是主动
	# 查询、手上没有 ctx，求值不了这个维度。允许它填写等于留一个**注册期收下、
	# 运行期永不校验**的字段——比不支持更危险。
	if bool(row.get("passive", false)) and not (contexts_raw as Array).is_empty():
		return "触发行 %s 是常驻行，不能声明 requires_contexts（常驻没有「本次伤害的产生路径」，消费方也无从求值）" \
			% where

	# requires_turn_phase 是单值字段；空串表示不限，非空值必须在闭集内。
	var turn_phase: String = str(entry.get("requires_turn_phase", "")).strip_edges()
	if turn_phase != "" and turn_phase not in SUPPORTED_TURN_PHASES:
		return "触发行 %s 的 requires_turn_phase「%s」不在闭集 %s 内（空串=不限）" \
			% [where, turn_phase, str(SUPPORTED_TURN_PHASES)]
	# 常驻行不许带回合位置，理由与 requires_contexts 那条对称：常驻行没有「本次
	# 事件」，谈不上它发生在谁的回合里；常驻天赋的消费方是主动查询、手上没有 ctx，
	# 求值不了这个维度。允许它填写等于留一个注册期收下、运行期永不校验的字段。
	if bool(row.get("passive", false)) and turn_phase != "":
		return "触发行 %s 是常驻行，不能声明 requires_turn_phase（常驻没有「本次事件」，消费方也无从求值）" \
			% where

	# trigger_object 引擎不读。填了值却不读 = 静默丢掉一个限制，与 trigger_source
	# 那条「读不懂的限制不许当空放行」是同一条纪律，所以非空一律拒收而不是忽略。
	var obj: String = str(entry.get("trigger_object", "")).strip_edges()
	if obj != "":
		return "触发行 %s 声明了 trigger_object「%s」，但引擎不读这个槽——静默忽略等于丢掉一个限制，故拒收" \
			% [where, obj]

	var condition: String = str(entry.get("trigger_condition", ""))
	# 形状先于语义：`as Array` 对非数组会抛 cast 错误然后**放行**，一个漏写的
	# 方括号就能让下面整个状态依赖循环被跳过、绕过 §2.3 硬判据。必须显式判类型。
	var required_raw: Variant = entry.get("requires_states", [])
	if not required_raw is Array:
		return "requires_states 必须是数组，实际是 %s（写成裸字符串会绕过状态依赖检查）" \
			% type_string(typeof(required_raw))
	var required: Array = required_raw
	# condition_model=states 表示条件文本已由 requires_states、requires_contexts
	# 与 requires_turn_phase 完整表达。
	var contexts: Array = contexts_raw
	if model == "none" and condition.strip_edges() != "":
		return "condition_model=none 但 trigger_condition 非空（「%s」）——声明与设计库镜像矛盾" % condition
	if model == "none" and not contexts.is_empty():
		return "condition_model=none 但 requires_contexts 非空（%s）——none 的语义是无条件" \
			% str(contexts)
	if model == "none" and turn_phase != "":
		return "condition_model=none 但 requires_turn_phase 非空（%s）——none 的语义是无条件" \
			% turn_phase
	# 新增结构化条件字段时必须纳入这项完整性检查。
	if model == "states" and required.is_empty() and contexts.is_empty() and turn_phase == "":
		return "condition_model=states 但 requires_states / requires_contexts / requires_turn_phase 全为空——声明与数据矛盾"

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


## `engine_effects` 保存在卡级，每条效果可用 `row` 绑定到指定触发行。
## 不写 `row` 时全部触发行共享；绑定必须指向现有行，且每个可分发行都有可执行效果。
func _effects_rejection_reason(entry: Dictionary, rows: Array) -> String:
	var effects_raw: Variant = entry.get("engine_effects", [])
	if not effects_raw is Array:
		return "engine_effects 必须是数组，实际是 %s" % type_string(typeof(effects_raw))
	var effects: Array = effects_raw
	if effects.is_empty():
		return "engine_effects 为空——没有可执行的效果，注册了也是死卡"
	var row_names: Array[String] = []
	for row: Dictionary in rows:
		row_names.append(str(row["row"]))
	# 每行落到了几条效果，用来查「有没有哪一行是空的」。
	var per_row: Dictionary = {}
	for name: String in row_names:
		per_row[name] = 0
	var index: int = -1
	for item: Variant in effects:
		index += 1
		if not item is Dictionary:
			return "engine_effects 含非字典项（%s）" % type_string(typeof(item))
		var effect: Dictionary = item
		var effect_type: String = str(effect.get("type", ""))
		if effect_type not in SUPPORTED_EFFECT_TYPES:
			return "engine_effects 含未知 type「%s」（当前支持 %s）" \
				% [effect_type, str(SUPPORTED_EFFECT_TYPES)]
		var bound: String = str(effect.get("row", "")).strip_edges()
		if bound != "" and bound not in row_names:
			return "engine_effects 第 %d 条绑定到不存在的触发行「%s」（本卡有 %s）" \
				% [index, bound, str(row_names)]
		for name: String in row_names:
			if bound == "" or bound == name:
				per_row[name] = int(per_row[name]) + 1

		# ── 效果类型 × 触发时机的相容性 ──────────────────
		# 常驻行在这里被跳过：它不进事件桶，效果对它没有「时机」可言。判据因此是
		# 「每条效果至少要落在一个相容的可分发行上」，而不是「所有行都相容」——
		# 二天一流就是主行常驻、附加行才是真时机的形状。
		var allowed_raw: Variant = EFFECT_ALLOWED_EVENTS.get(effect_type, null)
		if allowed_raw is Array:
			var allowed: Array = allowed_raw
			var compatible: int = 0
			var passive_hits: int = 0
			for row: Dictionary in rows:
				var rname: String = str(row["row"])
				if bound != "" and bound != rname:
					continue
				if bool(row.get("passive", false)):
					passive_hits += 1
					continue
				var ev: String = str((row["trigger"] as Dictionary).get("trigger_event", ""))
				if allowed.is_empty():
					return "engine_effects 第 %d 条（%s）是常驻类效果，必须落在常驻行上，实际落在触发行 %s 的事件「%s」上" \
						% [index, effect_type, rname, ev]
				if ev in allowed:
					compatible += 1
				else:
					return "engine_effects 第 %d 条（%s）落在触发行 %s 的事件「%s」上，但该效果只能挂 %s——挂错时机会被静默吞掉" \
						% [index, effect_type, rname, ev, str(allowed)]
			if allowed.is_empty():
				if passive_hits == 0:
					return "engine_effects 第 %d 条（%s）是常驻类效果，必须落在常驻行上" \
						% [index, effect_type]
			elif compatible == 0:
				return "engine_effects 第 %d 条（%s）没有落在任何相容的触发行上（只能挂 %s）" \
					% [index, effect_type, str(allowed)]
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
		elif effect_type == "unlock_offhand_weapon_effect":
			# 解锁副手武器特效，并按 effect_scale% 折算效果量（二刀开刃）。
			var scale_raw: Variant = effect.get("effect_scale", null)
			var scale_type: int = typeof(scale_raw)
			if scale_type != TYPE_INT and scale_type != TYPE_FLOAT:
				return "unlock_offhand_weapon_effect 的 effect_scale 必须是数字，实际是 %s" 					% type_string(scale_type)
			var scale: float = float(scale_raw)
			if scale <= 0.0 or scale > float(MAX_FOLLOWUP_PCT):
				return "unlock_offhand_weapon_effect 的 effect_scale 越界（0 < x <= %d），实际 %s" 					% [MAX_FOLLOWUP_PCT, str(scale_raw)]
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
		elif effect_type == "more_damage_from_stat":
			# R1.8 的「更多」类修正：`N% 更多 X`，各条独立连乘，落在伤害链最外层。
			# ★ 它**不是**「暴击倍率 ×N」那一类——后者是 R1.3 暴击倍率上的乘算
			# （拔刀的「暴击倍率 ×1.2」走那条），两者落层不同，别混用。死线写的是
			# 「该次暴击造成 (DEX/2)% 更多伤害」，措辞是「更多 伤害」，落伤害链。
			var stat: String = str(effect.get("stat", ""))
			if stat not in SUPPORTED_STATS:
				return "more_damage_from_stat 的 stat「%s」未支持（当前支持 %s）" \
					% [stat, str(SUPPORTED_STATS)]
			var per_point_raw: Variant = effect.get("pct_per_point", null)
			var per_point_type: int = typeof(per_point_raw)
			if per_point_type != TYPE_INT and per_point_type != TYPE_FLOAT:
				return "more_damage_from_stat 的 pct_per_point 必须是数字，实际是 %s" \
					% type_string(per_point_type)
			if float(per_point_raw) <= 0.0:
				return "more_damage_from_stat 的 pct_per_point 必须为正，实际 %s" \
					% str(per_point_raw)
		elif effect_type == "empower_next_offhand":
			# 强化随后那一次副手追加（剑气回荡）。两个子效果都可选，但不能全空
			# ——全空就是一条什么也不做的效果。数值从 JSON 读，代码不写死。
			var give_crit: bool = bool(effect.get("guaranteed_crit", false))
			var qi_raw: Variant = effect.get("qi_on_hit", null)
			var qi_amount: int = 0
			if qi_raw != null:
				var qi_type: int = typeof(qi_raw)
				if qi_type != TYPE_INT and qi_type != TYPE_FLOAT:
					return "empower_next_offhand 的 qi_on_hit 必须是数字，实际是 %s" \
						% type_string(qi_type)
				if float(qi_raw) != floorf(float(qi_raw)):
					return "empower_next_offhand 的 qi_on_hit 必须是整数值，实际 %s" % str(qi_raw)
				qi_amount = int(qi_raw)
				if qi_amount <= 0 or qi_amount > MAX_RESOURCE_GAIN:
					return "empower_next_offhand 的 qi_on_hit 越界（0 < x <= %d），实际 %d" \
						% [MAX_RESOURCE_GAIN, qi_amount]
			if not give_crit and qi_amount == 0:
				return "empower_next_offhand 既不给必暴也不给剑气——这是一条什么都不做的效果"
		elif effect_type == "offhand_recursive_followup":
			# 燕返：副手追加命中后按概率再追加，每成功一次概率乘衰减系数，可反复。
			#
			# ★ R1.10 的默认约束逐字是「一个效果不被自己引发的事件再次触发，多个
			# 效果之间也不构成循环触发」，豁免句是「除非效果描述显式声明可以反复
			# 追加」。所以递归**必须由数据显式开启**，代码里不预设放开——`
			# self_retriggerable` 缺省或非 true 一律拒收。燕返的 effect 原文写着
			# 「可以反复追加」，是豁免适用的那一类；将来若有卡漏写这句，它就该被
			# 这道闸门挡住，而不是跟着一起递归。
			if bool(effect.get("self_retriggerable", false)) != true:
				return "offhand_recursive_followup 必须显式声明 self_retriggerable=true" \
					+ "（R1.10 默认禁止自触发，豁免要求效果描述显式写明可反复追加）"
			var chance_stat: String = str(effect.get("chance_stat", ""))
			if chance_stat not in SUPPORTED_STATS:
				return "offhand_recursive_followup 的 chance_stat「%s」未支持（当前支持 %s）" \
					% [chance_stat, str(SUPPORTED_STATS)]
			var decay_raw: Variant = effect.get("chance_decay_pct", null)
			var decay_type: int = typeof(decay_raw)
			if decay_type != TYPE_INT and decay_type != TYPE_FLOAT:
				return "offhand_recursive_followup 的 chance_decay_pct 必须是数字，实际是 %s" \
					% type_string(decay_type)
			var decay: float = float(decay_raw)
			if decay < MIN_CHANCE_DECAY_PCT or decay > MAX_CHANCE_DECAY_PCT:
				return "offhand_recursive_followup 的 chance_decay_pct 越界（%s ~ %s），实际 %s——衰减必须真的衰减，填 100 就是永不收敛的无限链" \
					% [str(MIN_CHANCE_DECAY_PCT), str(MAX_CHANCE_DECAY_PCT), str(decay_raw)]
			# 递归追加沿用触发它的副手伤害规格；本效果不得另存 damage_pct / damage_type。
			if effect.has("damage_pct") or effect.has("damage_type"):
				return "offhand_recursive_followup 不得声明 damage_pct / damage_type——追加的规格沿用触发它的那一次副手追加（用户裁决：基于二天一流的伤害再次计算），自带一份就是双写"
		elif effect_type == "parry_damage_reduction":
			# 交刃：花剑气买一次必定的招架减伤。
			#
			# ★ 本效果**不声明减伤幅度**。设计库 effect 逐字是「该次攻击对你造成的
			# 伤害按**招架的**减伤结算」——幅度的权威在招架那边，引擎侧落在
			# data/buffs/swordsman_parry_stance.json 的 parry 段，两条入口共读。
			# 自带一份 (40+DEX) 就是把同一个设计数值存两处，正是 lane §2.2 要封杀
			# 的双写；写了就拒，免得日后有人照招架抄一份过来。
			if effect.has("reduction_base_pct") or effect.has("reduction_stat"):
				return "parry_damage_reduction 不得声明 reduction_base_pct / reduction_stat——减伤幅度的权威是招架架势的 parry 段（设计库逐字：「按招架的减伤结算」），自带一份就是双写"
			# qi_cost 是游戏数值（设计库 effect 逐字「消耗 10 点剑气」），必须来自
			# JSON。允许为 0：将来若有「不花剑气的必定减伤」类卡，写 0 比省略更明确。
			var qi_cost_raw: Variant = effect.get("qi_cost", null)
			var qi_cost_type: int = typeof(qi_cost_raw)
			if qi_cost_type != TYPE_INT and qi_cost_type != TYPE_FLOAT:
				return "parry_damage_reduction 的 qi_cost 必须是数字，实际是 %s" \
					% type_string(qi_cost_type)
			if float(qi_cost_raw) != floorf(float(qi_cost_raw)):
				return "parry_damage_reduction 的 qi_cost 必须是整数值，实际 %s 含小数部分" \
					% str(qi_cost_raw)
			var qi_cost: int = int(qi_cost_raw)
			if qi_cost < 0 or qi_cost > MAX_RESOURCE_GAIN:
				return "parry_damage_reduction 的 qi_cost 越界（0 <= x <= %d），实际 %d" \
					% [MAX_RESOURCE_GAIN, qi_cost]
		# grant_offhand_guaranteed_crit 无参数，type 在闭集内即合格。

	# 每一**可分发**行都必须至少有一条效果落在它上面。有行没效果 = 那行触发了也什么
	# 都不做，而设计库那边看到的是一张完整的卡，两边理解会分叉。
	#
	# ⚠ 常驻行豁免：它根本不进事件桶，没有「触发了什么都不做」这回事；而且常驻行
	# 完全可以是纯声明性的——二天一流主行的「失去防具槽、该槽改副手武器槽」是装备层
	# 的事，没有也不该有对应的 engine_effects。不豁免的话，一旦有人把效果正确地绑给
	# 附加行，整卡反而会被这道校验拒掉。
	for row: Dictionary in rows:
		var name: String = str(row["row"])
		if bool(row.get("passive", false)):
			continue
		if int(per_row.get(name, 0)) == 0:
			return "触发行 %s 没有任何效果绑定到它（engine_effects 的 row 绑定漏了这一行）" % name

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


## 返回指定触发行可执行的效果；写 `row` 仅绑定该行，不写则全部行共享。
## 分发必须走此函数，避免执行属于其他触发行的效果。
func effects_for_row(talent: Dictionary, row: String) -> Array:
	var out: Array = []
	var effects: Variant = talent.get("engine_effects", [])
	if not effects is Array:
		return out
	for item: Variant in (effects as Array):
		# 非字典项**不在这里丢弃**——注册期已经拒过这种数据，能走到这里说明是
		# 绕过注册器直接塞进来的。原样传下去，让分发方的告警分支去报，不然那条
		# 告警就成了永不执行的死代码，坏数据反而更隐蔽。
		if not item is Dictionary:
			out.append(item)
			continue
		var bound: String = str((item as Dictionary).get("row", "")).strip_edges()
		if bound == "" or bound == row:
			out.append(item)
	return out


## 常驻天赋条目（`{"talent":…, "trigger":…}`）；不是常驻卡则返回空字典。
## 消费方拿到后要自己用 trigger 里的 requires_states 求值——常驻不等于无条件，
## 二刀开刃就要求〔双持〕。
func passive_entry(talent_id: String) -> Dictionary:
	var e: Variant = _passive.get(talent_id, {})
	return e if e is Dictionary else {}


func passive_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: Variant in _passive.keys():
		ids.append(str(key))
	return ids


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
