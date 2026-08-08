extends SceneTree
## 天赋载体 + after-damage 族三事件分发（Wave 1 · A1）。
##
## 四块：
##   A. 装载回读 —— data/talents/*.json 确实进了 DataLoader.talents 并注册成功。
##   B. 注册期闸门（响亮失败）—— 每条拒收规则配一张夹具卡，逐条断言「被拒」+
##      「理由说得出所以然」，拒收信号可观测（rejected_ids / rejection_reason 非空）。
##      核心是 Wave 1 §2.3 的硬判据：依赖 unevaluable 状态的天赋必须拒绝注册；
##      另含形状类校验——`requires_states` 漏写方括号不得因 cast 失败而放行。
##   C. 三事件真实分发 —— 实例化 TacticalScene 驱动真实攻击，断言三个事件各自
##      在正确时点触发，尤其是「命中后」与「造成伤害时」的分野（伤害为 0 时前者
##      触发、后者不触发）。
##   D. 运行期条件求值 —— `requires_states` 此刻不成立就不触发，且随战况即时变化。
##      这一组是 2026-08-08 独立验证抓到真实缺陷后补的：当时只有注册期闸门、
##      没有运行期求值，满血单位照样触发了依赖〔背水〕的天赋。
##      **本组共三条断言**（满血不触发 / HP 30% 触发 / 回血 80% 又不触发）——
##      交付叙述里曾报成「四条」，这里以代码为准。阈值本身的边界（29 / 30 / 31
##      三点、脱离、翻转序列、阈值来自 JSON 的反向对照）**不在本文件**，而在被测
##      谓词自己的测试 `tests/test_state_registry.gd`，那边已经锁死，本文件不重复。
##
## 另附零影响对照：talent_ids 为空 / 装了未注册的 id 时，一律不触发。
##
## 运行：
##   <Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##     --script res://tests/test_talent_carrier.gd
## 退出码 0=全过，1=有失败。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false

const TALENT_REGISTRY_PATH := "res://scripts/data/talent_registry.gd"
const STATE_REGISTRY_PATH := "res://scripts/data/state_registry.gd"
const DATA_LOADER_PATH := "res://scripts/data/data_loader.gd"

## 合成的「判不了」状态。Wave 2 之后生产库里的双持已转 evaluable，没有现成的
## unevaluable 状态可用了——但 Wave 1 §2.3 的硬判据必须继续被锁住，故自造一个。
## 这样测试也不再依赖「生产库恰好有一个判不了的状态」这个会过期的前提。
const UNEVALUABLE_STATE_ID := "test_state_unevaluable"
const UNEVALUABLE_STATE: Dictionary = {
	"id": UNEVALUABLE_STATE_ID,
	"name": "测试·判不了的状态",
	"engine_status": "unevaluable",
	"engine_blocker": "引擎尚未实现该判定（合成夹具）",
	"predicate": {"type": "hp_ratio_at_most", "params": {"hp_ratio_pct": 100}},
}

## 合成天赋夹具。前两条是可注册的（补生产数据缺的两个事件——全库当前只有
## 「击杀时」有真卡，「造成伤害时」0 张、「命中后」2 处全是被排除的双持系）；
## 其余八条各自触碰一条拒收规则。
const SYNTHETIC: Dictionary = {
	"test_ok_hit_after": {
		"id": "test_ok_hit_after", "name": "测试·命中后", "class_id": "kensei",
		"trigger_event": "命中后", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 3}],
	},
	"test_ok_on_damage": {
		"id": "test_ok_on_damage", "name": "测试·造成伤害时", "class_id": "kensei",
		"trigger_event": "造成伤害时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 5}],
	},
	"test_ok_needs_beishui": {
		"id": "test_ok_needs_beishui", "name": "测试·依赖背水", "class_id": "kensei",
		"trigger_event": "命中后", "trigger_condition": "处于〔背水〕状态",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "states", "requires_states": ["beishui"],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 7}],
	},
	"test_rej_unevaluable": {
		"id": "test_rej_unevaluable", "name": "测试·依赖判不了的状态", "class_id": "kensei",
		"trigger_event": "命中后", "trigger_condition": "处于〔测试·判不了的状态〕状态",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "states", "requires_states": ["test_state_unevaluable"],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 99}],
	},
	"test_rej_unknown_state": {
		"id": "test_rej_unknown_state", "name": "测试·依赖未注册状态", "class_id": "kensei",
		"trigger_event": "命中后", "trigger_condition": "处于〔子虚〕状态",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "states", "requires_states": ["wu_you_ci_state"],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 99}],
	},
	"test_rej_unsupported": {
		"id": "test_rej_unsupported", "name": "测试·条件表达不了", "class_id": "kensei",
		"trigger_event": "击杀时", "trigger_condition": "当目标为头目且本回合未移动",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "unsupported", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 99}],
	},
	"test_rej_a2_event": {
		"id": "test_rej_a2_event", "name": "测试·A2 事件", "class_id": "kensei",
		"trigger_event": "暴击时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 99}],
	},
	"test_rej_frequency": {
		"id": "test_rej_frequency", "name": "测试·频率未实装", "class_id": "kensei",
		"trigger_event": "击杀时", "trigger_condition": "",
		"trigger_frequency": "每回合", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 99}],
	},
	"test_rej_unknown_effect": {
		"id": "test_rej_unknown_effect", "name": "测试·未知效果类型", "class_id": "kensei",
		"trigger_event": "击杀时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "teleport_to_moon", "amount": 1}],
	},
	"test_rej_condition_mismatch": {
		"id": "test_rej_condition_mismatch", "name": "测试·声明与镜像矛盾", "class_id": "kensei",
		"trigger_event": "击杀时", "trigger_condition": "处于〔背水〕状态",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 99}],
	},
	"test_rej_no_effects": {
		"id": "test_rej_no_effects", "name": "测试·无可执行效果", "class_id": "kensei",
		"trigger_event": "击杀时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [],
	},
	# ── 以下是形状/字段类校验，2026-08-08 独立验证指出的裸奔分支 ──
	"test_rej_states_empty": {
		"id": "test_rej_states_empty", "name": "测试·states 但依赖为空", "class_id": "kensei",
		"trigger_event": "击杀时", "trigger_condition": "处于某状态",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "states", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 9}],
	},
	"test_rej_no_event": {
		"id": "test_rej_no_event", "name": "测试·缺事件", "class_id": "kensei",
		"trigger_condition": "", "trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 9}],
	},
	"test_rej_no_model": {
		"id": "test_rej_no_model", "name": "测试·缺 condition_model", "class_id": "kensei",
		"trigger_event": "击杀时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 9}],
	},
	"test_rej_bad_model": {
		"id": "test_rej_bad_model", "name": "测试·非法 condition_model", "class_id": "kensei",
		"trigger_event": "击杀时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "States", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 9}],
	},
	"test_rej_bad_resource": {
		"id": "test_rej_bad_resource", "name": "测试·未支持资源", "class_id": "kensei",
		"trigger_event": "击杀时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "gold", "amount": 9}],
	},
	"test_rej_amount_zero": {
		"id": "test_rej_amount_zero", "name": "测试·amount 为 0", "class_id": "kensei",
		"trigger_event": "击杀时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 0}],
	},
	"test_rej_amount_str": {
		"id": "test_rej_amount_str", "name": "测试·amount 是字符串", "class_id": "kensei",
		"trigger_event": "击杀时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": "20"}],
	},
	"test_rej_amount_fraction": {
		"id": "test_rej_amount_fraction", "name": "测试·amount 含小数", "class_id": "kensei",
		"trigger_event": "击杀时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 2.5}],
	},
	# JSON 里的数字全是 float（Godot JSON.parse 的行为），20.0 必须能通过——
	# 否则真实 data/talents/*.json 里的卡会被自己的校验拒掉。
	"test_ok_amount_json_float": {
		"id": "test_ok_amount_json_float", "name": "测试·amount 为 JSON 式 float",
		"class_id": "kensei",
		"trigger_event": "造成伤害时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 4.0}],
	},
	"test_rej_amount_huge": {
		"id": "test_rej_amount_huge", "name": "测试·amount 超上限", "class_id": "kensei",
		"trigger_event": "击杀时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 999999}],
	},
	# ★ 形状旁路：requires_states 漏写方括号 → 绝不能因 cast 失败而放行
	"test_rej_states_not_array": {
		"id": "test_rej_states_not_array", "name": "测试·依赖写成裸字符串", "class_id": "kensei",
		"trigger_event": "命中后", "trigger_condition": "处于〔双持〕状态",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "states", "requires_states": "test_state_unevaluable",
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 99}],
	},
	"test_rej_states_item_not_str": {
		"id": "test_rej_states_item_not_str", "name": "测试·依赖元素非字符串", "class_id": "kensei",
		"trigger_event": "命中后", "trigger_condition": "处于某状态",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "states", "requires_states": [{"id": "test_state_unevaluable"}],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 99}],
	},
	"test_rej_effects_not_array": {
		"id": "test_rej_effects_not_array", "name": "测试·效果写成字典", "class_id": "kensei",
		"trigger_event": "击杀时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": {"type": "gain_resource", "resource": "qi", "amount": 9},
	},
	"test_rej_effects_item_not_dict": {
		"id": "test_rej_effects_item_not_dict", "name": "测试·效果含非字典项", "class_id": "kensei",
		"trigger_event": "击杀时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": ["gain_resource"],
	},
	"test_rej_id_mismatch": {
		"id": "另一个id", "name": "测试·内部 id 与键不符", "class_id": "kensei",
		"trigger_event": "击杀时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 9}],
	},
}

## 期望结果由夹具键名前缀推导，不写死数字——加夹具时不会忘了同步计数。
## 命名约定：`test_ok_*` 必须注册成功，`test_rej_*` 必须被拒。
## 这仍是有力断言：某张 ok 卡被误拒会让被拒数变多，某张 rej 卡被误放行会让它变少。
func _expected_rejected() -> int:
	var n: int = 0
	for key: String in SYNTHETIC.keys():
		if key.begins_with("test_rej"):
			n += 1
	return n


func _expected_ok_synthetic() -> Array[String]:
	var ids: Array[String] = []
	for key: String in SYNTHETIC.keys():
		if key.begins_with("test_ok"):
			ids.append(key)
	return ids


func _initialize() -> void:
	print("=== test_talent_carrier (天赋载体 + after-damage 三事件 · A1) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	var dl: Object = load(DATA_LOADER_PATH).new()
	dl.load_all()

	_test_loading(dl)
	_test_rejection_discipline(dl)
	_test_event_index(dl)
	_test_extra_triggers(dl)
	_test_dispatch_integration()
	_test_offhand_followup(dl)

	dl.free()
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  ✗ " + f)
	quit(0 if _fail == 0 else 1)


# ── E. 附加触发行（Wave 2）──────────────────────────

func _test_extra_triggers(dl: Object) -> void:
	print("
[E] 附加触发行（extra_triggers 子表）")
	var reg: Object = _make_registry(dl.talents, dl.states)

	# 二天一流：主行「永久生效」属常驻不进桶，机制主体在附加行「执行攻击动作时」。
	_check("二天一流已装载", dl.talents.has("kensei_ertianyiliu"))
	_check("二天一流注册成功（主行常驻不算缺行）",
		reg.is_registered("kensei_ertianyiliu"),
		reg.rejection_reason("kensei_ertianyiliu"))
	_eq("常驻事件「永久生效」不进事件桶", reg.talents_for_event("永久生效").size(), 0)
	var action_rows: Array = reg.talents_for_event("执行攻击动作时")
	_eq("「执行攻击动作时」桶里有 1 行", action_rows.size(), 1)
	if action_rows.size() == 1:
		var row: Dictionary = action_rows[0]
		_eq("该行属于二天一流", str((row["talent"] as Dictionary).get("id", "")),
			"kensei_ertianyiliu")
		_eq("该行是附加行而非主行", str(row["row"]), "extra[0]")
		# ★ 行级条件：附加行要求〔双持〕，主行则无条件。退回卡级就会丢掉这个要求。
		var trigger: Dictionary = row["trigger"]
		_eq("附加行带自己的 requires_states",
			trigger.get("requires_states", []), ["shuangchi"])
		_eq("附加行 condition_model=states", str(trigger.get("condition_model", "")), "states")
		_eq("卡级 requires_states 为空（证明两者确实分开）",
			(row["talent"] as Dictionary).get("requires_states", []), [])

	# 纯常驻卡（只有永久生效主行、无附加行）必须被拒——引擎没有承载通道。
	var only_passive: Dictionary = {
		"passive_only": {
			"id": "passive_only", "name": "测试·纯常驻", "class_id": "kensei",
			"trigger_event": "永久生效", "trigger_condition": "",
			"trigger_frequency": "永久", "trigger_frequency_n": 1,
			"condition_model": "none", "requires_states": [],
			"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 1}],
		}
	}
	var reg2: Object = _make_registry(only_passive, dl.states)
	_check("纯常驻卡被拒", not reg2.is_registered("passive_only"))
	_check("拒绝理由说明无可分发触发行",
		reg2.rejection_reason("passive_only").contains("无任何可分发的触发行"),
		reg2.rejection_reason("passive_only"))

	# 附加行不合格 → 整卡拒（不做「主行注册、附加行丢弃」的半生效）。
	var bad_extra: Dictionary = {
		"bad_extra": {
			"id": "bad_extra", "name": "测试·附加行不合格", "class_id": "kensei",
			"trigger_event": "击杀时", "trigger_condition": "",
			"trigger_frequency": "每次", "trigger_frequency_n": 1,
			"condition_model": "none", "requires_states": [],
			"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 1}],
			"extra_triggers": [{
				"trigger_event": "暴击时", "trigger_condition": "",
				"trigger_frequency": "每次", "trigger_frequency_n": 1,
				"condition_model": "none", "requires_states": [],
			}],
		}
	}
	var reg3: Object = _make_registry(bad_extra, dl.states)
	_check("附加行事件属 A2 → 整卡被拒", not reg3.is_registered("bad_extra"))
	_check("拒绝理由指明是附加行",
		reg3.rejection_reason("bad_extra").contains("extra[0]"),
		reg3.rejection_reason("bad_extra"))
	_eq("整卡拒后「击杀时」桶里也没有它（不半生效）",
		reg3.talents_for_event("击杀时").size(), 0)


# ── F. 副手追加攻击（Wave 2 · 集成）──────────────────

func _test_offhand_followup(dl: Object) -> void:
	print("
[F] 副手追加攻击（独立结算命中/暴击，不重复主手副作用）")
	var scene: Node = load("res://scenes/tactical/TacticalScene.tscn").instantiate()
	root.add_child(scene)
	var tm: Object = scene.tactical_manager
	tm._talent_registry = null
	tm._state_registry = null
	tm.debug_harness_active = true
	tm.debug_deterministic = true
	tm.debug_crit_mode = 2          # DISABLE：去掉暴击浮动

	var attacker: Unit = null
	var enemy: Unit = null
	for u: Unit in tm.units:
		if u.faction == "player" and u.unit_id == "kensei":
			attacker = u
		elif u.faction == "enemy" and enemy == null:
			enemy = u
	if attacker == null or enemy == null:
		_check("场景中找到剑圣与敌人", false)
		scene.free()
		return

	enemy.stats.def_attr = 0
	attacker.talent_ids = ["kensei_ertianyiliu"]

	# 基准：持有二天一流但**没装副手** → 不处于双持 → 不追加。
	attacker.unequip_offhand()
	enemy.stats.max_hp = 999
	enemy.stats.hp = 999
	attacker.set_sword_qi(0)
	tm._execute_hostile_action(attacker, enemy, {})
	var main_only: int = 999 - enemy.stats.hp
	_check("主手单独造成了伤害", main_only > 0)
	_eq("未装副手 → 只有普攻 10 气（附加行条件不成立，不追加）",
		attacker.sword_qi, 10)

	# 装上副手 → 双持成立 → 追加一次。
	attacker.equip_offhand("wpn_physical_melee_basic")
	enemy.stats.hp = 999
	attacker.set_sword_qi(0)
	tm._execute_hostile_action(attacker, enemy, {})
	var with_offhand: int = 999 - enemy.stats.hp
	_check("装上副手 → 总伤害多于主手单独（追加确实发生了）",
		with_offhand > main_only, "main_only=%d with_offhand=%d" % [main_only, with_offhand])

	# ★ 不重复主手副作用：剑气仍是普攻的 10，没有因为副手再产一次。
	_eq("副手不重复产气（仍是普攻的 10，不是 20）", attacker.sword_qi, 10)

	# 卸下副手 → 立刻回到不追加（即时判定）。
	attacker.unequip_offhand()
	enemy.stats.hp = 999
	attacker.set_sword_qi(0)
	tm._execute_hostile_action(attacker, enemy, {})
	_eq("卸下副手 → 伤害回到主手单独的量", 999 - enemy.stats.hp, main_only)

	# 没有二天一流天赋 → 即便装着副手也不追加（追加由天赋驱动，不是双持本身）。
	attacker.talent_ids = []
	attacker.equip_offhand("wpn_physical_melee_basic")
	enemy.stats.hp = 999
	tm._execute_hostile_action(attacker, enemy, {})
	_eq("无二天一流 → 装着副手也不追加", 999 - enemy.stats.hp, main_only)

	# 主手即已击杀 → 不再追加（目标已经不在了）。
	attacker.talent_ids = ["kensei_ertianyiliu"]
	enemy.stats.max_hp = 1
	enemy.stats.hp = 1
	tm._execute_hostile_action(attacker, enemy, {})
	_check("主手击杀后目标已死", not enemy.stats.is_alive())

	# 副手武器 id 指向不存在的条目 → 告警并取消追加，不崩、不按 0 伤害打。
	var enemy2: Unit = null
	for u: Unit in tm.units:
		if u.faction == "enemy" and u.stats.is_alive():
			enemy2 = u
			break
	if enemy2 != null:
		enemy2.stats.def_attr = 0
		enemy2.stats.max_hp = 999
		enemy2.stats.hp = 999
		attacker.equip_offhand("wpn_does_not_exist")
		tm._execute_hostile_action(attacker, enemy2, {})
		_check("副手武器查不到 → 只有主手伤害，不崩",
			(999 - enemy2.stats.hp) > 0 and (999 - enemy2.stats.hp) <= main_only)
		attacker.unequip_offhand()

	scene.free()


# ── 断言工具（照 tests/test_affix_effects.gd）─────────────

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


func _make_registry(talents: Dictionary, states: Dictionary) -> Object:
	var merged: Dictionary = states.duplicate(true)
	merged[UNEVALUABLE_STATE_ID] = UNEVALUABLE_STATE.duplicate(true)
	var state_reg: Object = load(STATE_REGISTRY_PATH).new(merged)
	return load(TALENT_REGISTRY_PATH).new(talents, state_reg)


func _count_json_files(path: String) -> int:
	var dir := DirAccess.open(path)
	if dir == null:
		return -1
	var n: int = 0
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if filename.ends_with(".json"):
			n += 1
		filename = dir.get_next()
	return n


# ── A. 装载回读 ──────────────────────────────────────

func _test_loading(dl: Object) -> void:
	print("\n[A] 装载回读（data/talents/*.json → DataLoader.talents → 注册）")
	_check("DataLoader 有 talents 字典", dl.get("talents") is Dictionary)
	_eq("talents 装载数 == data/talents 目录 JSON 文件数",
		dl.talents.size(), _count_json_files("res://data/talents/"))
	_check("介错已装载", dl.talents.has("myrmidon_jiecuo"))
	var entry: Dictionary = dl.talents.get("myrmidon_jiecuo", {})
	_eq("条目内 id 与注册键一致", str(entry.get("id", "")), "myrmidon_jiecuo")
	# 设计库镜像字段（对照 /api/talents 与 snapshots/talents.json @ 319993a）。
	_eq("介错 trigger_event", str(entry.get("trigger_event", "")), "击杀时")
	_eq("介错 trigger_condition 为空", str(entry.get("trigger_condition", "")), "")
	_eq("介错 effect", str(entry.get("effect", "")), "获得 20 点剑气。")
	_eq("介错 class_id", str(entry.get("class_id", "")), "myrmidon")

	var reg: Object = _make_registry(dl.talents, dl.states)
	_check("介错注册成功", reg.is_registered("myrmidon_jiecuo"))
	_eq("生产数据无一被拒", reg.rejected_ids(), [] as Array[String])
	_eq("介错未被拒（拒绝理由为空）", reg.rejection_reason("myrmidon_jiecuo"), "")


# ── B. 注册纪律：八类不可执行的卡逐一响亮拒收 ──────────

func _test_rejection_discipline(dl: Object) -> void:
	print("\n[B] 注册纪律（宁可不注册，不可错误触发）")
	var mixed: Dictionary = dl.talents.duplicate(true)
	for key: String in SYNTHETIC.keys():
		mixed[key] = (SYNTHETIC[key] as Dictionary).duplicate(true)
	var reg: Object = _make_registry(mixed, dl.states)

	# ★ 硬判据（Wave 1 §2.3）：依赖 unevaluable 状态 → 拒绝注册 + 可观测理由。
	_check("依赖判不了的状态 → 拒绝注册", not reg.is_registered("test_rej_unevaluable"))
	var reason: String = reg.rejection_reason("test_rej_unevaluable")
	_check("拒绝理由非空（可观测的失败信号）", reason != "")
	_check("拒绝理由点明状态判不了", reason.contains("判不了"))
	_check("拒绝理由带上了状态的阻塞原因", reason.contains("引擎尚未实现该判定"))
	_check("被拒 id 进了 rejected_ids 清单", "test_rej_unevaluable" in reg.rejected_ids())

	# ★ 形状旁路：requires_states 漏写方括号写成裸字符串，绝不能因 cast 失败而放行
	# ——否则一个 JSON 括号就能绕过上面的硬判据。
	_check("requires_states 写成裸字符串 → 拒绝注册（不因 cast 失败放行）",
		not reg.is_registered("test_rej_states_not_array"))
	_check("该拒绝理由点明必须是数组",
		reg.rejection_reason("test_rej_states_not_array").contains("必须是数组"),
		reg.rejection_reason("test_rej_states_not_array"))

	# 其余各类，逐条断言「被拒」+「理由说得出所以然」
	var cases: Dictionary = {
		"test_rej_unknown_state": "未在 data/states/ 注册",
		"test_rej_unsupported": "unsupported",
		"test_rej_a2_event": "A2",
		"test_rej_frequency": "频率",
		"test_rej_unknown_effect": "未知 type",
		"test_rej_condition_mismatch": "矛盾",
		"test_rej_no_effects": "engine_effects 为空",
		"test_rej_states_empty": "requires_states 为空",
		"test_rej_no_event": "缺 trigger_event",
		"test_rej_no_model": "缺 condition_model",
		"test_rej_bad_model": "非法",
		"test_rej_bad_resource": "未支持",
		"test_rej_amount_zero": "正整数",
		"test_rej_amount_str": "必须是数字",
		"test_rej_amount_fraction": "必须是整数值",
		"test_rej_amount_huge": "超出合理上限",
		"test_rej_states_item_not_str": "必须是状态 id 字符串",
		"test_rej_effects_not_array": "engine_effects 必须是数组",
		"test_rej_effects_item_not_dict": "含非字典项",
		"test_rej_id_mismatch": "与注册键",
	}
	for tid: String in cases.keys():
		_check("%s → 拒绝注册" % tid, not reg.is_registered(tid))
		_check("%s 拒绝理由含「%s」" % [tid, cases[tid]],
			reg.rejection_reason(tid).contains(str(cases[tid])),
			reg.rejection_reason(tid))

	# 合法的合成卡必须仍然注册成功——证明拒收不是「一刀切全拒」。
	var ok_ids: Array[String] = _expected_ok_synthetic()
	for tid: String in ok_ids:
		_check("合法合成卡 %s 注册成功" % tid, reg.is_registered(tid))
	# 生产卡全部注册成功——这同时是「data/talents/ 里没有死卡」的守卫。
	for tid: String in dl.talents.keys():
		_check("生产卡 %s 注册成功" % tid, reg.is_registered(tid),
			reg.rejection_reason(tid))
	_eq("被拒总数 == 全部 test_rej_* 夹具数（%d）" % _expected_rejected(),
		reg.rejected_ids().size(), _expected_rejected())
	_eq("注册成功总数 == 全部生产卡 + 全部 test_ok_* 夹具（%d）"
			% (dl.talents.size() + ok_ids.size()),
		reg.registered_ids().size(), dl.talents.size() + ok_ids.size())

	# 无 StateRegistry 时，依赖状态的卡不能放行（不能因为核验不了就默认通过）。
	var no_state_reg: Object = load(TALENT_REGISTRY_PATH).new(mixed, null)
	_check("无 StateRegistry → 依赖状态的卡仍被拒",
		not no_state_reg.is_registered("test_rej_unevaluable"))


# ── C1. 事件索引 ─────────────────────────────────────

func _test_event_index(dl: Object) -> void:
	print("\n[C1] 按事件索引")
	var mixed: Dictionary = dl.talents.duplicate(true)
	for key: String in SYNTHETIC.keys():
		mixed[key] = (SYNTHETIC[key] as Dictionary).duplicate(true)
	var reg: Object = _make_registry(mixed, dl.states)

	_eq("「击杀时」下 1 张（介错）", reg.talents_for_event("击杀时").size(), 1)
	_eq("「命中后」下 2 张（两张合法合成）", reg.talents_for_event("命中后").size(), 2)
	_eq("「造成伤害时」下 2 张（含 JSON 式 float amount 的那张）", reg.talents_for_event("造成伤害时").size(), 2)
	# A2 事件即使有数据也索引不到——它在注册期就被拒了。
	_eq("「暴击时」下 0 张（A2 不接）", reg.talents_for_event("暴击时").size(), 0)
	_eq("「命中时」下 0 张（A2 不接）", reg.talents_for_event("命中时").size(), 0)
	_eq("未知事件下 0 张", reg.talents_for_event("子虚乌有时").size(), 0)


# ── C2. 三事件真实分发（驱动 TacticalScene 的真实攻击流程）──

func _test_dispatch_integration() -> void:
	print("\n[C2] 三事件真实分发（真实战斗流程，非模拟）")
	# 往 autoload DataLoader 注入合成天赋——tactical_manager 的懒构造读的是它。
	# 必须用 get_node 动态取：`DataLoader` 这个标识符在 --script 主循环下编译期
	# 解析不到（"Identifier not found: DataLoader"），但节点本身确实挂在 /root。
	var autoload_dl: Node = root.get_node_or_null("/root/DataLoader")
	if autoload_dl == null:
		_check("autoload DataLoader 可达", false, "/root/DataLoader 不存在")
		return
	_check("autoload DataLoader 可达", true)
	for key: String in SYNTHETIC.keys():
		autoload_dl.talents[key] = (SYNTHETIC[key] as Dictionary).duplicate(true)

	var scene: Node = load("res://scenes/tactical/TacticalScene.tscn").instantiate()
	root.add_child(scene)
	var tm: Object = scene.tactical_manager
	tm._talent_registry = null          # 强制按注入后的数据重建
	tm._state_registry = null
	tm.debug_harness_active = true      # 强制命中，去掉命中随机性
	tm.debug_deterministic = true
	tm.debug_crit_mode = 2              # DISABLE：禁暴击，避免伤害浮动干扰断言

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
		return
	_check("场景中找到剑圣与敌人", true)

	# ── 零影响对照：talent_ids 为空 → 一个都不触发 ──
	attacker.talent_ids = []
	enemy.stats.max_hp = 999
	enemy.stats.hp = 999
	enemy.stats.def_attr = 0
	attacker.set_sword_qi(0)
	tm._execute_hostile_action(attacker, enemy, {})
	# 剑圣普攻本身产 10 气（既有机制），天赋若触发会额外加 3+5。
	_eq("talent_ids 为空 → 只有普攻的 10 气，天赋零触发", attacker.sword_qi, 10)

	# ── 装了未注册的 id → 不触发 ──
	attacker.talent_ids = ["test_rej_unevaluable", "test_rej_unsupported", "不存在的id"]
	enemy.stats.hp = 999
	attacker.set_sword_qi(0)
	tm._execute_hostile_action(attacker, enemy, {})
	_eq("装了被拒/不存在的 id → 仍只有普攻 10 气", attacker.sword_qi, 10)

	# ── 命中且造成伤害且不死 → 命中后(+3) 与 造成伤害时(+5) 都触发 ──
	attacker.talent_ids = ["test_ok_hit_after", "test_ok_on_damage", "myrmidon_jiecuo"]
	enemy.stats.max_hp = 999
	enemy.stats.hp = 999
	enemy.stats.def_attr = 0
	attacker.set_sword_qi(0)
	tm._execute_hostile_action(attacker, enemy, {})
	_eq("命中+有伤害+不死 → 10(普攻) + 3(命中后) + 5(造成伤害时) == 18",
		attacker.sword_qi, 18)

	# ── 命中但伤害为 0 → 只有「命中后」触发，「造成伤害时」不触发 ──
	# 这是两个事件的分野：设计库定义「命中后」实际伤害为 0 也触发。
	enemy.stats.hp = 999
	enemy.stats.def_attr = 9999   # 防御拉满 → damage = maxi(0, ...) == 0
	attacker.set_sword_qi(0)
	tm._execute_hostile_action(attacker, enemy, {})
	_eq("命中但伤害为 0 → 10(普攻) + 3(命中后) == 13，造成伤害时不触发",
		attacker.sword_qi, 13)

	# ── 击杀 → 介错(+20) 触发，且命中后/造成伤害时同时成立 ──
	enemy.stats.def_attr = 0
	enemy.stats.max_hp = 1
	enemy.stats.hp = 1
	attacker.set_sword_qi(0)
	tm._execute_hostile_action(attacker, enemy, {})
	_check("击杀成功（敌人已死）", not enemy.stats.is_alive())
	# 10(普攻) + 3(命中后) + 5(造成伤害时) + 20(介错·击杀时) = 38
	_eq("击杀 → 三事件全触发，含介错 +20 → 38", attacker.sword_qi, 38)

	# ── ★ 运行期条件求值：requires_states 此刻成立才触发 ──
	# 注册期只保证「引擎判得了这个条件」；此刻成不成立必须每次重新问。
	# 少了这一步，condition_model=states 的卡会在条件不成立时照常触发
	# （2026-08-08 独立验证抓到的真实缺陷，本组断言就是为锁住它而加）。
	attacker.talent_ids = ["test_ok_needs_beishui"]
	enemy.stats.max_hp = 999
	enemy.stats.hp = 999
	enemy.stats.def_attr = 0
	attacker.stats.max_hp = 100

	attacker.stats.hp = 100            # 满血 → 不处于背水
	attacker.set_sword_qi(0)
	tm._execute_hostile_action(attacker, enemy, {})
	_eq("持有者满血（非背水）→ 依赖背水的天赋不触发，只有普攻 10 气",
		attacker.sword_qi, 10)

	attacker.stats.hp = 30             # 30% → 处于背水（边界含等号）
	enemy.stats.hp = 999
	attacker.set_sword_qi(0)
	tm._execute_hostile_action(attacker, enemy, {})
	_eq("持有者 HP 30%（背水成立）→ 触发 +7 → 17", attacker.sword_qi, 17)

	attacker.stats.hp = 80             # 回升 → 脱离背水
	enemy.stats.hp = 999
	attacker.set_sword_qi(0)
	tm._execute_hostile_action(attacker, enemy, {})
	_eq("持有者回血到 80%（脱离背水）→ 又不触发 → 10", attacker.sword_qi, 10)

	attacker.stats.hp = 100            # 复原，免得影响下面的用例

	# ── 未命中 → 三事件一个都不触发 ──
	# 不能靠「回避拉满就必不命中」：damage_calculator 的命中率有 1% 下限
	# （clampf(..., 0.01, 1.0)），单次断言约有 1% 概率假失败。改为多打几次、
	# 只对**实际未命中的那些次**断言，并要求至少观察到一次未命中。
	tm.debug_deterministic = false     # 关掉强制命中
	enemy.stats.spd = 9999             # 回避拉满 → 命中率压到 1% 下限
	enemy.stats.lck = 9999
	attacker.talent_ids = ["test_ok_hit_after", "test_ok_on_damage", "myrmidon_jiecuo"]
	var miss_seen: int = 0
	var miss_with_qi: int = 0
	for _i: int in range(12):
		enemy.stats.max_hp = 999
		enemy.stats.hp = 999
		attacker.set_sword_qi(0)
		tm._execute_hostile_action(attacker, enemy, {})
		if enemy.stats.hp == 999:       # HP 没掉 = 这次没命中（def=0 时命中必有伤害）
			miss_seen += 1
			if attacker.sword_qi != 0:
				miss_with_qi += 1
	_check("12 次攻击里至少观察到一次未命中（命中率已压到 1% 下限）", miss_seen > 0,
		"miss_seen=%d" % miss_seen)
	_eq("每一次未命中都没产生任何剑气（三事件全不触发，普攻也不产气）", miss_with_qi, 0)

	scene.free()
