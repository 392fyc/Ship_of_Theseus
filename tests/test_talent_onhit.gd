extends SceneTree
## Wave 3：触发来源接线（trigger_source）+ 真 on-hit 两事件（A2）+ 递归副手追加。
##
## 单独开一个文件而不是继续往 test_talent_carrier.gd 里塞：那个文件已经 1180 行，
## 再加四组会彻底失去可读性。分工是——A1/Wave 2 的载体、注册纪律、副手规格留在
## 那边；本文件只管 Wave 3 新接的三件事。
##
## 五组：
##   I. trigger_source 双向 —— 这是任务书 §1.1 的验收判据。「主手」的卡在副手那次
##      不触发、「副手」的卡在主手那次不触发，**两个方向都要断言**（带方向的机制
##      只测一边，反着接也能过）。外加空值语义：不填来源 = 两次都触发。
##  II. requires_contexts 的注册期把关 —— 闭集、形状、与 condition_model 的自洽。
## III. 行级效果绑定 —— 剑气回荡两行两效果，主行给必暴标记、附加行给剑气，
##      各行只执行自己那条。这一组的期望值刻意设计成「绑定失效就会算出另一个数」。
##  IV. A2 钩子确实能改写本次伤害 —— 死线的「(DEX/2)% 更多伤害」，精确对照。
##      外加剑气回荡的跨主副手因果：主手暴击让副手那次必暴。
##   V. 燕返的递归追加 —— 概率 0 不追加、概率 1 必追加、护栏不被突破，
##      以及「副手追加不发『执行攻击动作时』」（否则二天一流会自己无限登记）。
##
## 运行：
##   <Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##     --script res://tests/test_talent_onhit.gd
## 退出码 0=全过，1=有失败。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false

const TALENT_REGISTRY_PATH := "res://scripts/data/talent_registry.gd"
const STATE_REGISTRY_PATH := "res://scripts/data/state_registry.gd"
const DATA_LOADER_PATH := "res://scripts/data/data_loader.gd"

## 副手武器：王者之剑（might 20）。选它是因为数值大到不会与主手的量碰巧相等——
## Wave 2 吃过一次亏：银剑 13 的 50% 与主手 might 6 算出同一个数，断言当场失去区分力。
const OFFHAND_WEAPON := "eq_wpn_regal_blade"

## 调试暴击三态（对应 TacticalManager.CritMode）。
const CRIT_RANDOM: int = 0
const CRIT_FORCE: int = 1
const CRIT_DISABLE: int = 2

## 来源夹具。三张卡只差 trigger_source 一个字段，产气量各不相同——
## 于是「谁触发了」可以直接从剑气总量反推，不需要额外插桩。
const SYNTHETIC: Dictionary = {
	"test_src_main": {
		"id": "test_src_main", "name": "测试·只认主手", "class_id": "kensei",
		"trigger_event": "命中后", "trigger_source": "主手", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 3}],
	},
	"test_src_off": {
		"id": "test_src_off", "name": "测试·只认副手", "class_id": "kensei",
		"trigger_event": "命中后", "trigger_source": "副手", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 5}],
	},
	"test_src_any": {
		"id": "test_src_any", "name": "测试·不限来源", "class_id": "kensei",
		"trigger_event": "命中后", "trigger_source": "", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 7}],
	},
	# 计数用：每次副手命中 +1 气，于是「副手打了几次」== 剑气 − 普攻的 10。
	# 刻意用 1 而不是 5——递归链最长 20 次，用 5 会撞上剑气上限 100 被 clamp，
	# 计数就失真了。
	"test_count_off": {
		"id": "test_count_off", "name": "测试·副手计数", "class_id": "kensei",
		"trigger_event": "命中后", "trigger_source": "副手", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 1}],
	},
	# 燕返的极端衰减变体：用来把链长**钉在 2**。DEX=100 时首次概率 1.0 必成功，
	# 第二次概率 1.0×0.01 几乎必失败。用来验「必暴标记只消费一次」——那条语义
	# 需要至少两次副手追加才观测得到。
	"test_yanfan_once": {
		"id": "test_yanfan_once", "name": "测试·只递归一次", "class_id": "kensei",
		"trigger_event": "命中后", "trigger_source": "副手", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{
			"type": "offhand_recursive_followup", "chance_stat": "DEX",
			"chance_decay_pct": 1, "damage_pct": 50, "damage_type": "physical",
			"self_retriggerable": true,
		}],
	},
	# 燕返的高衰减变体：用来撞引擎侧的链长护栏。decay=99 衰减极慢，
	# 20 次之内概率仍在 0.8 以上，链会一路顶到上限。
	"test_yanfan_slow_decay": {
		"id": "test_yanfan_slow_decay", "name": "测试·极慢衰减递归", "class_id": "kensei",
		"trigger_event": "命中后", "trigger_source": "副手", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{
			"type": "offhand_recursive_followup", "chance_stat": "DEX",
			"chance_decay_pct": 99, "damage_pct": 50, "damage_type": "physical",
			"self_retriggerable": true,
		}],
	},
}


func _initialize() -> void:
	print("=== test_talent_onhit (触发来源 + 真 on-hit 两事件 + 递归追加 · Wave 3) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	var dl: Object = load(DATA_LOADER_PATH).new()
	dl.load_all()

	_test_new_cards_registered(dl)
	_test_contexts_gate(dl)
	_test_row_binding_gate(dl)
	_test_source_directions()
	_test_row_binding_runtime()
	_test_on_hit_rewrites_damage()
	_test_recursive_followup()

	dl.free()
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  ✗ " + f)
	quit(0 if _fail == 0 else 1)


# ── 装载：三张新卡进得来 ───────────────────────────

func _test_new_cards_registered(dl: Object) -> void:
	print("\n[W1] 三张新卡装载与注册")
	var reg: Object = _make_registry(dl.talents, dl.states)
	for tid: String in ["kensei_jianqihuidang", "kensei_yanfan", "myrmidon_sixian"]:
		_check("%s 已装载" % tid, dl.talents.has(tid))
		_check("%s 注册成功" % tid, reg.is_registered(tid), reg.rejection_reason(tid))

	# 镜像保真：Wave 2 手抄错过一次 trigger_frequency（「每次」抄成「永久」），
	# 表现是卡被拒、看起来像「引擎不支持」。逐字对照设计库权威值。
	var jqhd: Dictionary = dl.talents["kensei_jianqihuidang"]
	_eq("剑气回荡 主行事件", str(jqhd.get("trigger_event", "")), "暴击时")
	_eq("剑气回荡 主行来源", str(jqhd.get("trigger_source", "")), "主手")
	_eq("剑气回荡 频率", str(jqhd.get("trigger_frequency", "")), "每次")
	var jqhd_extra: Array = jqhd.get("extra_triggers", [])
	_eq("剑气回荡 附加行数", jqhd_extra.size(), 1)
	if jqhd_extra.size() == 1:
		var row0: Dictionary = jqhd_extra[0]
		_eq("剑气回荡 附加行事件", str(row0.get("trigger_event", "")), "命中后")
		_eq("剑气回荡 附加行来源", str(row0.get("trigger_source", "")), "副手")
	var yf: Dictionary = dl.talents["kensei_yanfan"]
	_eq("燕返 主行事件", str(yf.get("trigger_event", "")), "命中后")
	_eq("燕返 主行来源", str(yf.get("trigger_source", "")), "副手")
	_eq("燕返 频率（任务书说这里卡住了，其实没有）",
		str(yf.get("trigger_frequency", "")), "每次")
	var sx: Dictionary = dl.talents["myrmidon_sixian"]
	_eq("死线 主行事件", str(sx.get("trigger_event", "")), "暴击时")
	_eq("死线 主行来源", str(sx.get("trigger_source", "")), "主手")

	# 事件桶：两个新事件下各有真卡，不再是空桶。
	_check("「暴击时」桶非空（剑气回荡主行 + 死线）",
		reg.talents_for_event("暴击时").size() >= 2)
	_check("「命中时」桶当前无生产卡（没有卡挂这个事件，不是接不了）",
		reg.talents_for_event("命中时").size() == 0)


# ── requires_contexts 的注册期把关 ─────────────────

func _test_contexts_gate(dl: Object) -> void:
	print("\n[W2] requires_contexts 注册期把关")
	var cases: Dictionary = {
		# 闭集外的标签 → 拒。引擎从不注入它，依赖它的卡是永不触发的死卡。
		"ctx_unknown": {
			"card": {
				"id": "ctx_unknown", "name": "测试·未知路径", "class_id": "kensei",
				"trigger_event": "命中后", "trigger_condition": "受到攻击时反击",
				"trigger_frequency": "每次", "trigger_frequency_n": 1,
				"condition_model": "states", "requires_states": [],
				"requires_contexts": ["defensive_reaction"],
				"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 1}],
			},
			"keyword": "引擎不注入",
		},
		# 形状不对 → 拒（写成裸字符串会让 as Array 静默放行）。
		"ctx_not_array": {
			"card": {
				"id": "ctx_not_array", "name": "测试·路径非数组", "class_id": "kensei",
				"trigger_event": "命中后", "trigger_condition": "在主动攻击中",
				"trigger_frequency": "每次", "trigger_frequency_n": 1,
				"condition_model": "states", "requires_states": [],
				"requires_contexts": "active_attack",
				"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 1}],
			},
			"keyword": "必须是数组",
		},
		# condition_model=none 却带了路径要求 → 自相矛盾，拒。
		"ctx_none_mismatch": {
			"card": {
				"id": "ctx_none_mismatch", "name": "测试·none 却有路径", "class_id": "kensei",
				"trigger_event": "命中后", "trigger_condition": "",
				"trigger_frequency": "每次", "trigger_frequency_n": 1,
				"condition_model": "none", "requires_states": [],
				"requires_contexts": ["active_attack"],
				"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 1}],
			},
			"keyword": "none 的语义是无条件",
		},
		# 来源挂在不带伤害来源的事件上 → 拒。
		"src_on_actionless_event": {
			"card": {
				"id": "src_on_actionless_event", "name": "测试·动作事件带来源",
				"class_id": "kensei",
				"trigger_event": "执行攻击动作时", "trigger_source": "主手",
				"trigger_condition": "",
				"trigger_frequency": "每次", "trigger_frequency_n": 1,
				"condition_model": "none", "requires_states": [],
				"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 1}],
			},
			"keyword": "不带伤害来源",
		},
		# 闭集外的来源值 → 拒（不能当成空放行，那等于丢掉一个读不懂的限制）。
		"src_unknown": {
			"card": {
				"id": "src_unknown", "name": "测试·未知来源", "class_id": "kensei",
				"trigger_event": "命中后", "trigger_source": "双手", "trigger_condition": "",
				"trigger_frequency": "每次", "trigger_frequency_n": 1,
				"condition_model": "none", "requires_states": [],
				"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 1}],
			},
			"keyword": "不在闭集",
		},
	}
	for tid: String in cases.keys():
		var case: Dictionary = cases[tid]
		var reg: Object = _make_registry({tid: case["card"]}, dl.states)
		_check("%s → 拒绝注册" % tid, not reg.is_registered(tid))
		_check("%s 的理由说得出所以然" % tid,
			reg.rejection_reason(tid).contains(str(case["keyword"])),
			reg.rejection_reason(tid))

	# ★ 反向：条件**只有**路径要求、没有状态依赖的卡，必须能注册。
	# A1 的自洽性检查是「states 却 requires_states 空 → 拒」，若不把 contexts
	# 一起算上，这种卡会无路可走：填 states 被拒、填 none 也被拒。
	var only_ctx: Dictionary = {
		"ctx_only": {
			"id": "ctx_only", "name": "测试·只有路径要求", "class_id": "kensei",
			"trigger_event": "命中后", "trigger_condition": "发生在主动攻击动作中",
			"trigger_frequency": "每次", "trigger_frequency_n": 1,
			"condition_model": "states", "requires_states": [],
			"requires_contexts": ["active_attack"],
			"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 1}],
		}
	}
	var reg_ok: Object = _make_registry(only_ctx, dl.states)
	_check("条件只有路径要求（无状态依赖）→ 能注册，不死锁",
		reg_ok.is_registered("ctx_only"), reg_ok.rejection_reason("ctx_only"))


# ── 行级效果绑定的注册期把关 ───────────────────────

func _test_row_binding_gate(dl: Object) -> void:
	print("\n[W3] engine_effects 的 row 绑定（注册期）")
	# 绑到不存在的行 → 拒。
	var bad_row: Dictionary = {
		"bind_ghost": {
			"id": "bind_ghost", "name": "测试·绑到不存在的行", "class_id": "kensei",
			"trigger_event": "命中后", "trigger_condition": "",
			"trigger_frequency": "每次", "trigger_frequency_n": 1,
			"condition_model": "none", "requires_states": [],
			"engine_effects": [
				{"type": "gain_resource", "resource": "qi", "amount": 1, "row": "extra[7]"},
			],
		}
	}
	var reg1: Object = _make_registry(bad_row, dl.states)
	_check("效果绑到不存在的触发行 → 拒绝注册", not reg1.is_registered("bind_ghost"))
	_check("理由点明绑到了不存在的行",
		reg1.rejection_reason("bind_ghost").contains("不存在的触发行"),
		reg1.rejection_reason("bind_ghost"))

	# 有行没有任何效果落上去 → 拒（那一行触发了也什么都不做）。
	var empty_row: Dictionary = {
		"bind_starved": {
			"id": "bind_starved", "name": "测试·有行无效果", "class_id": "kensei",
			"trigger_event": "命中后", "trigger_condition": "",
			"trigger_frequency": "每次", "trigger_frequency_n": 1,
			"condition_model": "none", "requires_states": [],
			"engine_effects": [
				{"type": "gain_resource", "resource": "qi", "amount": 1, "row": "main"},
			],
			"extra_triggers": [{
				"trigger_event": "击杀时", "trigger_condition": "",
				"trigger_frequency": "每次", "trigger_frequency_n": 1,
				"condition_model": "none", "requires_states": [],
			}],
		}
	}
	var reg2: Object = _make_registry(empty_row, dl.states)
	_check("附加行没有任何效果绑定 → 拒绝注册", not reg2.is_registered("bind_starved"))
	_check("理由点明是哪一行空着",
		reg2.rejection_reason("bind_starved").contains("extra[0]"),
		reg2.rejection_reason("bind_starved"))

	# 不写 row = 全行共用（向后兼容）——已有三张卡都是这么写的。
	var reg3: Object = _make_registry(dl.talents, dl.states)
	_check("二天一流（不写 row，两行共用一条效果）仍注册成功",
		reg3.is_registered("kensei_ertianyiliu"),
		reg3.rejection_reason("kensei_ertianyiliu"))
	_eq("不写 row 的效果对主行可见",
		reg3.effects_for_row(dl.talents["kensei_ertianyiliu"], "main").size(), 1)
	_eq("不写 row 的效果对附加行也可见",
		reg3.effects_for_row(dl.talents["kensei_ertianyiliu"], "extra[0]").size(), 1)
	# 剑气回荡：两行各只看见自己那一条。
	var jqhd: Dictionary = dl.talents["kensei_jianqihuidang"]
	var main_fx: Array = reg3.effects_for_row(jqhd, "main")
	var extra_fx: Array = reg3.effects_for_row(jqhd, "extra[0]")
	_eq("剑气回荡 主行只看见 1 条效果", main_fx.size(), 1)
	_eq("剑气回荡 主行那条是 grant_offhand_guaranteed_crit",
		str((main_fx[0] as Dictionary).get("type", "")) if main_fx.size() > 0 else "",
		"grant_offhand_guaranteed_crit")
	_eq("剑气回荡 附加行只看见 1 条效果", extra_fx.size(), 1)
	_eq("剑气回荡 附加行那条是 gain_resource",
		str((extra_fx[0] as Dictionary).get("type", "")) if extra_fx.size() > 0 else "",
		"gain_resource")


# ── I. trigger_source 双向（任务书 §1.1 验收判据）──────

func _test_source_directions() -> void:
	print("\n[W4] trigger_source 双向 —— 主手的卡在副手不触发、副手的卡在主手不触发")
	var ctx: Dictionary = _make_battle(CRIT_DISABLE)
	if ctx.is_empty():
		return
	var tm: Object = ctx["tm"]
	var attacker: Unit = ctx["attacker"]
	var enemy: Unit = ctx["enemy"]

	# 基线先确认副手追加确实在发生，否则下面「副手卡没触发」会因为压根没有副手
	# 那一击而假通过——这类假通过最难发现。
	attacker.equip_offhand(OFFHAND_WEAPON)
	attacker.talent_ids = ["kensei_ertianyiliu"]
	var main_plus_off: int = _strike(tm, attacker, enemy)
	attacker.unequip_offhand()
	var main_only: int = _strike(tm, attacker, enemy)
	_check("基线：副手追加确实发生了（装副手打得更多）",
		main_plus_off > main_only,
		"main_only=%d main_plus_off=%d" % [main_only, main_plus_off])

	attacker.equip_offhand(OFFHAND_WEAPON)

	# 方向一：source=主手 的卡，只在主手那次触发。
	attacker.talent_ids = ["kensei_ertianyiliu", "test_src_main"]
	_strike(tm, attacker, enemy)
	_eq("source=主手 → 只主手触发：10(普攻) + 3 == 13", attacker.sword_qi, 13)

	# 方向二：source=副手 的卡，只在副手追加那次触发。
	attacker.talent_ids = ["kensei_ertianyiliu", "test_src_off"]
	_strike(tm, attacker, enemy)
	_eq("source=副手 → 只副手触发：10(普攻) + 5 == 15", attacker.sword_qi, 15)

	# 空值语义：不填来源 = 不限来源，两次都触发。
	attacker.talent_ids = ["kensei_ertianyiliu", "test_src_any"]
	_strike(tm, attacker, enemy)
	_eq("source 为空 → 两次都触发：10 + 7 + 7 == 24", attacker.sword_qi, 24)

	# 三张一起装，各按各的来源计一次。
	attacker.talent_ids = [
		"kensei_ertianyiliu", "test_src_main", "test_src_off", "test_src_any",
	]
	_strike(tm, attacker, enemy)
	_eq("三张同装：10 + 3(主) + 5(副) + 7×2(不限) == 32", attacker.sword_qi, 32)

	# 没有副手武器时，副手的卡完全不触发（不是「来源不匹配」，是根本没有那一击）。
	attacker.unequip_offhand()
	attacker.talent_ids = ["kensei_ertianyiliu", "test_src_off", "test_src_any"]
	_strike(tm, attacker, enemy)
	_eq("无副手 → 副手卡不触发、不限来源的卡只触发主手那次：10 + 7 == 17",
		attacker.sword_qi, 17)

	(ctx["scene"] as Node).free()


# ── III. 行级效果绑定（运行期）───────────────────────

func _test_row_binding_runtime() -> void:
	print("\n[W5] 行级效果绑定（运行期）—— 剑气回荡两行两效果")
	var ctx: Dictionary = _make_battle(CRIT_FORCE)
	if ctx.is_empty():
		return
	var tm: Object = ctx["tm"]
	var attacker: Unit = ctx["attacker"]
	var enemy: Unit = ctx["enemy"]

	attacker.equip_offhand(OFFHAND_WEAPON)
	attacker.talent_ids = ["kensei_ertianyiliu", "kensei_jianqihuidang"]
	_strike(tm, attacker, enemy)
	# 期望 20 = 10(普攻) + 10(附加行·副手命中后)。
	# ★ 这个数字是为区分而选的：若行级绑定失效、两行各执行全部效果，
	#   主手暴击也会给 10 → 总数变成 30。20 与 30 一眼可辨。
	_eq("剑气回荡：只有附加行给气，主行不给 → 10 + 10 == 20",
		attacker.sword_qi, 20)

	# 没装副手 → 主行的必暴标记没有消费者，附加行也不触发 → 只有普攻的气。
	attacker.unequip_offhand()
	_strike(tm, attacker, enemy)
	_eq("未装副手 → 剑气回荡两行都不生效（条件不成立）→ 10", attacker.sword_qi, 10)

	(ctx["scene"] as Node).free()


# ── IV. A2 钩子确实能改写本次伤害 ──────────────────

func _test_on_hit_rewrites_damage() -> void:
	print("\n[W6] 「暴击时」钩子改写本次伤害（死线）+ 跨主副手因果（剑气回荡）")
	var ctx: Dictionary = _make_battle(CRIT_FORCE)
	if ctx.is_empty():
		return
	var tm: Object = ctx["tm"]
	var attacker: Unit = ctx["attacker"]
	var enemy: Unit = ctx["enemy"]

	# 把基数做成整数好算：STR 10 + might 10 − DEF 0 = 20，强制暴击 ×1.5 = 30。
	attacker.stats.str_attr = 10
	attacker.unequip_offhand()
	var payload: Dictionary = {"weapon_might": 10}

	attacker.talent_ids = []
	var base_crit: int = _strike(tm, attacker, enemy, payload)
	_eq("对照组：(10+10-0) × 1.5 == 30", base_crit, 30)

	# ★ precomputed_outcome 只能在调用点现场注入，绝不能回写到调用方传进来的字典。
	# 若它污染了上游 payload，一发范围技能的每个目标就会共用同一次命中/暴击判定
	# ——违反 R1.10「计次按被作用的目标单位分别进行」。
	_check("precomputed_outcome 没有污染调用方传入的 payload",
		not payload.has("precomputed_outcome"), str(payload.keys()))

	attacker.talent_ids = ["myrmidon_sixian"]
	var with_sixian: int = _strike(tm, attacker, enemy, payload)
	# 期望从**实际生效**的 DEX 推，不写死——DEX 会被心眼分档与印记加成影响，
	# 写死 stats.dex 会让断言在那些机制变动时假失败。
	var dex_eff: int = attacker.get_effective_stat("DEX")
	var expected: int = floori(30.0 * (1.0 + float(dex_eff) * 0.5 / 100.0))
	_eq("死线：暴击伤害 × (1 + DEX×0.5%%)，DEX_eff=%d → %d" % [dex_eff, expected],
		with_sixian, expected)
	_check("死线确实改大了伤害（DEX>0 时期望值必须真的不同）",
		dex_eff <= 0 or with_sixian > base_crit,
		"dex_eff=%d base=%d with=%d" % [dex_eff, base_crit, with_sixian])

	# 死线是 source=主手：副手那次即使暴击也不吃它的加成。
	# 用副手总伤害对照——装死线前后，副手那一击的量应当一致。
	attacker.equip_offhand(OFFHAND_WEAPON)
	attacker.talent_ids = ["kensei_ertianyiliu"]
	var total_no_sixian: int = _strike(tm, attacker, enemy, payload)
	attacker.talent_ids = ["kensei_ertianyiliu", "myrmidon_sixian"]
	var total_with_sixian: int = _strike(tm, attacker, enemy, payload)
	_eq("死线只加主手那一击：总伤害的增量 == 主手单独时的增量",
		total_with_sixian - total_no_sixian, with_sixian - base_crit)

	(ctx["scene"] as Node).free()

	# ── 跨主副手因果：主手暴击 → 副手那次必定暴击 ──
	# 要能观测到「是剑气回荡让副手暴的」，就不能用 FORCE 模式（那样副手本来也暴）。
	# 改用 RANDOM 模式 + 主手 payload 里显式给 guaranteed_crit，并把敌人 LCK 拉高
	# 使副手的暴击率恒为 0 —— 这样副手若暴，只可能是剑气回荡给的。
	var ctx2: Dictionary = _make_battle(CRIT_RANDOM)
	if ctx2.is_empty():
		return
	var tm2: Object = ctx2["tm"]
	var atk2: Unit = ctx2["attacker"]
	var foe2: Unit = ctx2["enemy"]
	foe2.stats.lck = 9999          # 暴击回避拉满 → crit_rate = max(0, crit − LCK) = 0
	atk2.equip_offhand(OFFHAND_WEAPON)
	var crit_payload: Dictionary = {"guaranteed_crit": true}

	atk2.talent_ids = ["kensei_ertianyiliu"]
	var off_normal: int = _strike(tm2, atk2, foe2, crit_payload)
	atk2.talent_ids = ["kensei_ertianyiliu", "kensei_jianqihuidang"]
	var off_crit: int = _strike(tm2, atk2, foe2, crit_payload)
	_check("剑气回荡：主手暴击让副手那次也暴（总伤害变高）",
		off_crit > off_normal,
		"无剑气回荡=%d 有剑气回荡=%d" % [off_normal, off_crit])

	# 主手没暴时，标记不该被设——副手回到普通掷骰（LCK 拉满 → 必不暴）。
	var no_crit_payload: Dictionary = {"disable_crit": true}
	atk2.talent_ids = ["kensei_ertianyiliu"]
	var base_nocrit: int = _strike(tm2, atk2, foe2, no_crit_payload)
	atk2.talent_ids = ["kensei_ertianyiliu", "kensei_jianqihuidang"]
	var with_nocrit: int = _strike(tm2, atk2, foe2, no_crit_payload)
	_eq("主手未暴击 → 剑气回荡不触发，副手也不暴，伤害与无卡时一致",
		with_nocrit, base_nocrit)

	# ── 必暴标记**只消费一次** ────────────────────────
	# effect 写的是「该次副手追加伤害」——单数。燕返递归出来的第二次不该继承它，
	# 得各自独立掷骰（燕返 rules 逐字要求每次独立结算命中与暴击）。
	# 这条语义已经写进卡的 engine_note，所以必须有测试锁住，否则那句话只是注释。
	#
	# 观测手段：把链长钉在 2（test_yanfan_once 的第二次概率只有 1%），
	# 比较「装剑气回荡」相对「不装」的伤害增量——
	#   只消费一次 → 增量 == 一次暴击的增量
	#   没有清除   → 增量 == 两次暴击的增量（正好翻倍，一眼可辨）
	atk2.stats.str_attr = 10
	atk2.stats.dex = 100      # 让 test_yanfan_once 的首次递归必成功
	# DEX 改了会影响暴击值，基准要在改完之后重新测。
	atk2.talent_ids = ["kensei_ertianyiliu"]
	var n1_plain: int = _strike(tm2, atk2, foe2, crit_payload)
	atk2.talent_ids = ["kensei_ertianyiliu", "kensei_jianqihuidang"]
	var n1_crit: int = _strike(tm2, atk2, foe2, crit_payload)
	var one_crit_gain: int = n1_crit - n1_plain
	_check("基准：副手那一次因剑气回荡而暴击，增量为正", one_crit_gain > 0,
		"n1_plain=%d n1_crit=%d" % [n1_plain, n1_crit])

	# 链长 2 的样本要碰运气取（第二次有 1% 会成功），所以循环到取够为止。
	# 链长从剑气反推：不装剑气回荡时每次副手命中 +1（test_count_off）；
	# 装了则每次 +1+10=11。
	var chain2_plain: int = -1
	var chain2_crit: int = -1
	for _i: int in range(40):
		if chain2_plain < 0:
			atk2.talent_ids = [
				"kensei_ertianyiliu", "test_yanfan_once", "test_count_off",
			]
			var t: int = _strike(tm2, atk2, foe2, crit_payload)
			if atk2.sword_qi - 10 == 2:
				chain2_plain = t
		if chain2_crit < 0:
			atk2.talent_ids = [
				"kensei_ertianyiliu", "test_yanfan_once", "test_count_off",
				"kensei_jianqihuidang",
			]
			var t2: int = _strike(tm2, atk2, foe2, crit_payload)
			if atk2.sword_qi - 10 == 22:      # 2 次 × (1 + 10)
				chain2_crit = t2
		if chain2_plain >= 0 and chain2_crit >= 0:
			break
	_check("取到了链长恰好为 2 的对照样本", chain2_plain >= 0 and chain2_crit >= 0,
		"plain=%d crit=%d" % [chain2_plain, chain2_crit])
	if chain2_plain >= 0 and chain2_crit >= 0:
		_eq("必暴标记只消费一次：两次副手追加里只有第一次暴（增量 == 一次暴击的增量，不是两次）",
			chain2_crit - chain2_plain, one_crit_gain)

	(ctx2["scene"] as Node).free()


# ── V. 燕返的递归追加 ─────────────────────────────

func _test_recursive_followup() -> void:
	print("\n[W7] 燕返的递归副手追加")
	var ctx: Dictionary = _make_battle(CRIT_DISABLE)
	if ctx.is_empty():
		return
	var tm: Object = ctx["tm"]
	var attacker: Unit = ctx["attacker"]
	var enemy: Unit = ctx["enemy"]
	attacker.equip_offhand(OFFHAND_WEAPON)

	# 副手命中次数 == 剑气 − 普攻的 10（test_count_off 每次副手命中 +1）。
	# DEX=0 → 概率 0 → 一次都不追加，只有二天一流那一次。
	attacker.stats.dex = 0
	attacker.talent_ids = ["kensei_ertianyiliu", "kensei_yanfan", "test_count_off"]
	_strike(tm, attacker, enemy)
	_eq("DEX=0 → 概率 0，不递归：副手只打 1 次", attacker.sword_qi - 10, 1)

	# ★ 同一条断言还锁住另一件事：副手追加**不发**「执行攻击动作时」。
	# 若发了，二天一流会在副手那次又登记一次追加，次数就不止 1（R1.10：挂在
	# 「执行攻击动作时」的效果，一次攻击动作只触发一次）。
	_eq("副手追加不发「执行攻击动作时」→ 二天一流不自我登记（仍是 1 次）",
		attacker.sword_qi - 10, 1)

	# DEX=100 → 首次概率 1.0。randf() 取值在 [0,1)，所以 `randf() >= 1.0` 恒不成立
	# → 第一次递归**必定**发生。这是这条链上唯一可确定断言的一环。
	attacker.stats.dex = 100
	var seen_min: int = 999
	var seen_max: int = 0
	for _i: int in range(12):
		_strike(tm, attacker, enemy)
		var n: int = attacker.sword_qi - 10
		seen_min = mini(seen_min, n)
		seen_max = maxi(seen_max, n)
	_check("DEX=100 → 首次递归必成功，副手至少打 2 次（12 轮的最小值）",
		seen_min >= 2, "最少 %d 次" % seen_min)
	_check("链长不超过引擎护栏 20（12 轮的最大值）",
		seen_max <= 20, "最多 %d 次" % seen_max)
	_check("衰减真的在起作用：12 轮里出现过链长差异（不是每轮都顶到上限）",
		seen_max > seen_min or seen_max < 20,
		"min=%d max=%d" % [seen_min, seen_max])

	# 护栏：极慢衰减（decay=99）+ DEX=100 会让链一路顶上去，但绝不能突破 20。
	attacker.talent_ids = [
		"kensei_ertianyiliu", "test_yanfan_slow_decay", "test_count_off",
	]
	var guard_max: int = 0
	for _i: int in range(8):
		_strike(tm, attacker, enemy)
		guard_max = maxi(guard_max, attacker.sword_qi - 10)
	_check("极慢衰减也不突破护栏（≤ 20 次）", guard_max <= 20,
		"实测最多 %d 次" % guard_max)
	_check("极慢衰减确实把链拉长了（比 DEX=0 的 1 次多得多）", guard_max >= 5,
		"实测最多 %d 次" % guard_max)

	# 没有燕返时，装着 test_count_off 也只有二天一流那一次——排除「计数卡自己
	# 造成了追加」这种解释。
	attacker.talent_ids = ["kensei_ertianyiliu", "test_count_off"]
	_strike(tm, attacker, enemy)
	_eq("无燕返 → 副手仍只打 1 次（递归确实来自燕返）", attacker.sword_qi - 10, 1)

	(ctx["scene"] as Node).free()


# ── 夹具 ─────────────────────────────────────────

## 起一局真实战斗，返回 {scene, tm, attacker, enemy}；找不到单位时返回空字典。
func _make_battle(crit_mode: int) -> Dictionary:
	var autoload_dl: Node = root.get_node_or_null("/root/DataLoader")
	if autoload_dl == null:
		_check("autoload DataLoader 可达", false, "/root/DataLoader 不存在")
		return {}
	for key: String in SYNTHETIC.keys():
		autoload_dl.talents[key] = (SYNTHETIC[key] as Dictionary).duplicate(true)

	var scene: Node = load("res://scenes/tactical/TacticalScene.tscn").instantiate()
	root.add_child(scene)
	var tm: Object = scene.tactical_manager
	tm._talent_registry = null      # 强制按注入后的数据重建
	tm._state_registry = null
	tm.debug_harness_active = true
	tm.debug_deterministic = true   # 强制命中，去掉命中随机性
	tm.debug_crit_mode = crit_mode

	var attacker: Unit = null
	var enemy: Unit = null
	for u: Unit in tm.units:
		if u.faction == "player" and u.unit_id == "kensei":
			attacker = u
		elif u.faction == "enemy" and enemy == null:
			enemy = u
	if attacker == null or enemy == null:
		_check("场景中找到剑圣与敌人", false, "attacker/enemy 缺失")
		scene.free()
		return {}
	enemy.stats.def_attr = 0
	return {"scene": scene, "tm": tm, "attacker": attacker, "enemy": enemy}


## 打一次，返回本次造成的总伤害。每次都把敌人血量与攻方剑气复位，
## 让相邻用例互不串味。
func _strike(tm: Object, attacker: Unit, enemy: Unit,
		payload: Dictionary = {}) -> int:
	enemy.stats.max_hp = 99999
	enemy.stats.hp = 99999
	attacker.set_sword_qi(0)
	tm._execute_hostile_action(attacker, enemy, payload)
	return 99999 - enemy.stats.hp


func _make_registry(talents: Dictionary, states: Dictionary) -> Object:
	var state_reg: Object = load(STATE_REGISTRY_PATH).new(states)
	return load(TALENT_REGISTRY_PATH).new(talents, state_reg)


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		_fails.append(name + ("  [" + detail + "]" if detail != "" else ""))
		print("  ✗ " + name + ("  [" + detail + "]" if detail != "" else ""))


func _eq(name: String, actual: Variant, expected: Variant) -> void:
	_check(name, actual == expected, "期望 %s 实际 %s" % [str(expected), str(actual)])
