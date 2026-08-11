extends SceneTree
## Wave 4：防御侧反应 —— 受到攻击时 + 招架减伤 + 交刃。
##
## 单独开一个文件的理由同 test_talent_onhit.gd：那两个文件已经分别 1190 / 1290 行。
## 分工是——A1/Wave 2 的载体与注册纪律在 test_talent_carrier.gd，Wave 3 的来源与
## on-hit 在 test_talent_onhit.gd，本文件只管 Wave 4 的防御侧。
##
## ★ 本文件的攻守方向与前两个文件**相反**：那两个是剑圣打敌人、看攻击者的天赋；
## 这里是**敌人打剑圣**、看被攻击者的天赋。写测试时最容易顺手写成前者，那样
## 「分发给谁」这条根本测不到——[D2] 就是专门钉这一条的。
##
## 七组：
##   D0. 注册期把关 —— requires_turn_phase 的闭集/常驻行/自洽，
##       parry_damage_reduction 的参数与时机相容性。
##   D1. 交刃装载、注册与镜像保真。
##   D2. **分发对象是被攻击者，不是攻击者** —— 两个方向都断言。
##   D3. 回合位置双向 —— 回合外触发、自身回合内不触发。
##   D4. 剑气门槛 —— 不足不触发**且不扣**，足额触发并扣。
##   D5. 未命中 —— 不触发**且不扣剑气**。
##   D6. 非双持 —— 不触发。
##   D7. 招架架势 —— 概率 0 与概率 100 两个边界各有断言；减伤幅度精确对照。
##   D8. 减伤每次攻击至多一次 —— 架势成功时交刃不白扣剑气。
##   D9. prevented（实际减免量）精确等于「不减伤时的伤害 − 减伤后的伤害」。
##
## 运行：
##   <Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##     --script res://tests/test_talent_defense.gd
## 退出码 0=全过，1=有失败。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false

const TALENT_REGISTRY_PATH := "res://scripts/data/talent_registry.gd"
const STATE_REGISTRY_PATH := "res://scripts/data/state_registry.gd"
const DATA_LOADER_PATH := "res://scripts/data/data_loader.gd"

const PARRY_BUFF := "swordsman_parry_stance"
## 副手武器：与 test_talent_onhit 同一把，理由也一样（数值大到不会与别的量撞）。
const OFFHAND_WEAPON := "eq_wpn_regal_blade"

## 调试暴击三态（对应 TacticalManager.CritMode）。
const CRIT_DISABLE: int = 2

const SYNTHETIC: Dictionary = {
	# 无条件的防御侧产气卡：用来观测「事件发给了谁」。挂在攻击者身上不该响，
	# 挂在被攻击者身上才该响。
	"test_def_any": {
		"id": "test_def_any", "name": "测试·受击产气", "class_id": "kensei",
		"trigger_event": "受到攻击时", "trigger_source": "", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 3}],
	},
	# 只在自身回合**外**响的产气卡：D3 用它把回合位置这一维单独拎出来测，
	# 不与交刃的剑气消耗纠缠（交刃扣气、本卡产气，两者混在一起读不出方向）。
	"test_def_outside": {
		"id": "test_def_outside", "name": "测试·仅回合外受击产气", "class_id": "kensei",
		"trigger_event": "受到攻击时", "trigger_source": "", "trigger_condition": "不处于自身回合内",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "states", "requires_states": [],
		"requires_turn_phase": "outside_own_turn",
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 3}],
	},
	# 闭集外的回合位置 → 拒收。不能当空放行，否则卡会在本该被排除的时机触发。
	"test_rej_phase_bad": {
		"id": "test_rej_phase_bad", "name": "测试·回合位置越界", "class_id": "kensei",
		"trigger_event": "受到攻击时", "trigger_condition": "敌方回合",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "states", "requires_states": [],
		"requires_turn_phase": "敌方回合",
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 1}],
	},
	# 常驻行带回合位置 → 拒收（常驻没有「本次事件」，消费方无从求值）。
	"test_rej_phase_passive": {
		"id": "test_rej_phase_passive", "name": "测试·常驻行带回合位置", "class_id": "kensei",
		"trigger_event": "永久生效", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"requires_turn_phase": "outside_own_turn",
		"engine_effects": [{"type": "unlock_offhand_weapon_effect", "effect_scale": 50}],
	},
	# condition_model=none 但带了回合位置 → 拒收（none 的语义是无条件）。
	"test_rej_phase_none_model": {
		"id": "test_rej_phase_none_model", "name": "测试·none 却带回合位置", "class_id": "kensei",
		"trigger_event": "受到攻击时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"requires_turn_phase": "outside_own_turn",
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 1}],
	},
	# 减伤幅度自带一份 → 拒收（幅度权威在招架的 parry 段，两处各存一份就是双写）。
	"test_rej_parry_dup": {
		"id": "test_rej_parry_dup", "name": "测试·自带减伤幅度", "class_id": "kensei",
		"trigger_event": "受到攻击时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{
			"type": "parry_damage_reduction", "qi_cost": 10,
			"reduction_base_pct": 40, "reduction_stat": "DEX",
		}],
	},
	# qi_cost 是字符串 → 拒收（错类型经 int() 也能变成 10，静默通过就等于接受错数据）。
	"test_rej_parry_qi_str": {
		"id": "test_rej_parry_qi_str", "name": "测试·qi_cost 是字符串", "class_id": "kensei",
		"trigger_event": "受到攻击时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "parry_damage_reduction", "qi_cost": "10"}],
	},
	# 挂在攻击链事件上 → 拒收（挂错时机会被静默吞掉：那个时点的 ctx 没有
	# pending_parry，效果登记不进去，而日志还照样跑）。
	"test_rej_parry_wrong_event": {
		"id": "test_rej_parry_wrong_event", "name": "测试·减伤挂错时机", "class_id": "kensei",
		"trigger_event": "命中后", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "parry_damage_reduction", "qi_cost": 10}],
	},
}


func _initialize() -> void:
	print("=== test_talent_defense（Wave 4 · 防御侧反应）===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	var dl: Object = load(DATA_LOADER_PATH).new()
	dl.load_all()

	_test_registration_gates(dl)
	_test_jiaoren_loaded(dl)
	_test_parry_params_present(dl)
	_test_dispatch_target()
	_test_turn_phase_directions()
	_test_qi_threshold()
	_test_miss_path()
	_test_dual_wield_gate()
	_test_parry_stance_edges()
	_test_at_most_once()
	_test_prevented_exact()
	_test_offhand_side_defense()

	dl.free()
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  ✗ " + f)
	quit(0 if _fail == 0 else 1)


# ── D0. 注册期把关 ────────────────────────────────

func _test_registration_gates(dl: Object) -> void:
	print("\n[D0] 注册期把关：requires_turn_phase 与 parry_damage_reduction")
	var reg: Object = _make_registry(SYNTHETIC, dl.states)

	var cases: Dictionary = {
		"test_rej_phase_bad": "requires_turn_phase",
		"test_rej_phase_passive": "常驻行",
		"test_rej_phase_none_model": "none 的语义是无条件",
		"test_rej_parry_dup": "双写",
		"test_rej_parry_qi_str": "必须是数字",
		"test_rej_parry_wrong_event": "只能挂",
	}
	for tid: String in cases.keys():
		_check("%s 被拒" % tid, not reg.is_registered(tid),
			reg.rejection_reason(tid))
		_check("%s 的理由说得出所以然" % tid,
			reg.rejection_reason(tid).contains(str(cases[tid])),
			reg.rejection_reason(tid))

	# ★ 自洽性：条件**只由** requires_turn_phase 表达的卡必须能注册。
	# Wave 3 加 requires_contexts 时踩过一次同型的坑——判据没算进自洽检查，
	# 那种卡就无路可走（填 states 因旧判据全空被拒、填 none 因 condition 非空被拒）。
	_check("条件只由 requires_turn_phase 表达的卡能注册（自洽检查算上了新判据）",
		reg.is_registered("test_def_outside"),
		reg.rejection_reason("test_def_outside"))
	_check("无条件的防御侧卡能注册", reg.is_registered("test_def_any"),
		reg.rejection_reason("test_def_any"))


# ── D1. 交刃装载与镜像保真 ────────────────────────

func _test_jiaoren_loaded(dl: Object) -> void:
	print("\n[D1] 交刃装载、注册与镜像保真")
	_check("kensei_jiaoren 已装载", dl.talents.has("kensei_jiaoren"))
	var reg: Object = _make_registry(dl.talents, dl.states)
	_check("kensei_jiaoren 注册成功", reg.is_registered("kensei_jiaoren"),
		reg.rejection_reason("kensei_jiaoren"))

	# 镜像保真：Wave 2 手抄错过一次 trigger_frequency，表现是卡被拒、看起来像
	# 「引擎不支持」。逐字对照设计库权威值。
	var jr: Dictionary = dl.talents.get("kensei_jiaoren", {})
	_eq("交刃 事件", str(jr.get("trigger_event", "")), "受到攻击时")
	_eq("交刃 来源为空（= 不限来源，主副手都触发）",
		str(jr.get("trigger_source", "")), "")
	_eq("交刃 频率", str(jr.get("trigger_frequency", "")), "每次")
	_eq("交刃 回合位置", str(jr.get("requires_turn_phase", "")), "outside_own_turn")
	_eq("交刃 依赖双持", str(jr.get("requires_states", [])), str(["shuangchi"]))
	var effects: Array = jr.get("engine_effects", [])
	_eq("交刃 只有一条效果", effects.size(), 1)
	_eq("交刃 效果类型", str((effects[0] as Dictionary).get("type", "")),
		"parry_damage_reduction")
	_eq("交刃 剑气消耗从 JSON 读（设计库逐字 10 点）",
		int((effects[0] as Dictionary).get("qi_cost", -1)), 10)
	_check("交刃 不自带减伤幅度（幅度权威在招架的 parry 段）",
		not (effects[0] as Dictionary).has("reduction_base_pct")
			and not (effects[0] as Dictionary).has("reduction_stat"))

	_eq("「受到攻击时」桶里有交刃", reg.talents_for_event("受到攻击时").size(), 1)


func _test_parry_params_present(dl: Object) -> void:
	print("\n[D1b] 招架架势的 parry 段（减伤参数的唯一权威）")
	var buff: Dictionary = dl.buffs.get(PARRY_BUFF, {})
	_check("%s 已装载" % PARRY_BUFF, not buff.is_empty())
	var params: Dictionary = buff.get("parry", {})
	_check("parry 段存在", not params.is_empty())
	# 逐字对照设计库招架 effect：「按 SPD% 概率减少 (40+DEX)% 的伤害」。
	_eq("概率属性 = SPD", str(params.get("chance_stat", "")), "SPD")
	_eq("减伤基数 = 40", int(params.get("reduction_base_pct", -1)), 40)
	_eq("减伤属性 = DEX", str(params.get("reduction_stat", "")), "DEX")
	# 待实装括号已去掉——这条是防「实装完忘了改 description」的回归锁。
	var zj: Dictionary = dl.skills.get("swordsman_zhaojia", {})
	_check("招架 description 已去掉「待后续实装」",
		not str(zj.get("description", "")).contains("待后续实装"),
		str(zj.get("description", "")))


# ── D2. 分发对象：被攻击者，不是攻击者 ──────────────

## 本波最容易写反的一处：`_dispatch_talents` 的第一个参数写成 attacker，
## 交刃就会变成「我打人时我自己触发」。两个方向都断言，只测一边反着接也能过。
func _test_dispatch_target() -> void:
	print("\n[D2] 受到攻击时发给被攻击者，不发给攻击者")
	var ctx: Dictionary = _make_battle()
	if ctx.is_empty():
		return
	var tm: Object = ctx["tm"]
	var kensei: Unit = ctx["kensei"]
	var enemy: Unit = ctx["enemy"]

	# 方向一：卡挂在**被攻击者**（剑圣）身上 → 该响。
	kensei.talent_ids = ["test_def_any"]
	enemy.talent_ids = []
	kensei.set_sword_qi(0)
	var dmg: int = _incoming(tm, enemy, kensei)
	_check("基线：敌人确实打出了伤害（否则下面全是假通过）", dmg > 0, "dmg=%d" % dmg)
	_eq("卡在被攻击者身上 → 触发（+3 剑气）", kensei.sword_qi, 3)

	# 方向二：同一张卡改挂在**攻击者**身上 → 不该响。
	kensei.talent_ids = []
	enemy.talent_ids = ["test_def_any"]
	enemy.set_sword_qi(0)
	kensei.set_sword_qi(0)
	_incoming(tm, enemy, kensei)
	_eq("卡在攻击者身上 → 不触发（攻击者剑气不变）", enemy.sword_qi, 0)
	_eq("卡在攻击者身上 → 被攻击者也不获益", kensei.sword_qi, 0)

	(ctx["scene"] as Node).free()


# ── D3. 回合位置双向 ──────────────────────────────

func _test_turn_phase_directions() -> void:
	print("\n[D3] requires_turn_phase 双向：回合外触发、自身回合内不触发")
	var ctx: Dictionary = _make_battle()
	if ctx.is_empty():
		return
	var tm: Object = ctx["tm"]
	var kensei: Unit = ctx["kensei"]
	var enemy: Unit = ctx["enemy"]
	kensei.talent_ids = ["test_def_outside"]

	# 方向一：当前行动的是敌人 → 剑圣处于自身回合**外** → 触发。
	tm.turn_manager.current_unit = enemy
	kensei.set_sword_qi(0)
	_incoming(tm, enemy, kensei)
	_eq("被攻击者不是当前行动单位 → 回合外 → 触发（+3）", kensei.sword_qi, 3)

	# 方向二：当前行动的就是剑圣自己 → 处于自身回合**内** → 不触发。
	# 现实里走不到（引擎没有能让单位在自己回合内被攻击的路径），这里是直接把
	# current_unit 摆过去构造出那个状态——正因为生产路径造不出来，才更要测，
	# 否则这条判据是否真的接上了完全无从观测。
	tm.turn_manager.current_unit = kensei
	kensei.set_sword_qi(0)
	_incoming(tm, enemy, kensei)
	_eq("被攻击者就是当前行动单位 → 回合内 → 不触发（剑气不变）",
		kensei.sword_qi, 0)

	# 反向对照：同一时点、同一次攻击，不带回合位置要求的卡照样触发。
	# 少了这条，上面那个 0 也可能是「事件根本没发」造成的假通过。
	tm.turn_manager.current_unit = kensei
	kensei.talent_ids = ["test_def_any"]
	kensei.set_sword_qi(0)
	_incoming(tm, enemy, kensei)
	_eq("同一时点，不限回合位置的卡仍触发（证明事件确实发了）",
		kensei.sword_qi, 3)

	(ctx["scene"] as Node).free()


# ── D4. 剑气门槛 ─────────────────────────────────

func _test_qi_threshold() -> void:
	print("\n[D4] 交刃的剑气门槛：不足不触发且不扣，足额触发并扣")
	var ctx: Dictionary = _make_battle()
	if ctx.is_empty():
		return
	var tm: Object = ctx["tm"]
	var kensei: Unit = ctx["kensei"]
	var enemy: Unit = ctx["enemy"]
	_arm_jiaoren(tm, kensei, enemy)

	# 足额：扣 10 点，并且确实减了伤。
	var dmg_full: int = _incoming(tm, enemy, kensei, 10)
	_eq("剑气足额 → 扣掉 10 点", kensei.sword_qi, 0)

	# 不足：一点都不扣，也不减伤。
	var dmg_poor: int = _incoming(tm, enemy, kensei, 9)
	_eq("剑气不足 → 一点都不扣（不是扣到 0）", kensei.sword_qi, 9)
	_check("剑气不足 → 不减伤（挨得更多）", dmg_poor > dmg_full,
		"足额挨 %d / 不足挨 %d" % [dmg_full, dmg_poor])

	# 边界：正好 10 点 → 触发（条件是「≥ 10」不是「> 10」）。
	var dmg_exact: int = _incoming(tm, enemy, kensei, 10)
	_eq("正好 10 点 → 触发并扣光", kensei.sword_qi, 0)
	_eq("正好 10 点时的伤害与足额时相同", dmg_exact, dmg_full)

	(ctx["scene"] as Node).free()


# ── D5. 未命中 ───────────────────────────────────

func _test_miss_path() -> void:
	print("\n[D5] 攻击未命中 → 不触发、不消耗剑气")
	var ctx: Dictionary = _make_battle()
	if ctx.is_empty():
		return
	var tm: Object = ctx["tm"]
	var kensei: Unit = ctx["kensei"]
	var enemy: Unit = ctx["enemy"]
	_arm_jiaoren(tm, kensei, enemy)
	# 再挂一张无条件产气卡：它是「事件到底发没发」的观测手段。只看剑气没少，
	# 分不出「没触发」和「触发了但没扣」。
	kensei.talent_ids = ["kensei_jiaoren", "test_def_any"]

	# 关掉强制命中，用命中率下限打出必未命中。
	tm.debug_deterministic = false
	kensei.stats.max_hp = 99999
	kensei.stats.hp = 99999
	kensei.set_sword_qi(50)
	tm._execute_hostile_action(enemy, kensei,
		{"weapon_hit": -99999, "terrain_evade_bonus": 99999})
	_eq("未命中 → 剑圣没掉血", kensei.stats.hp, 99999)
	_eq("未命中 → 交刃不扣剑气", kensei.sword_qi, 50)

	# 同一发若命中，那张观测卡会 +3；未命中时它一点没加 → 证明事件整个没分发，
	# 而不是「分发了但交刃自己没响」。
	tm.debug_deterministic = true
	kensei.set_sword_qi(50)
	_incoming(tm, enemy, kensei, 50)
	_check("对照：命中时事件确实分发（观测卡加了气）", kensei.sword_qi > 40,
		"命中后剑气 %d（扣 10 加 3 → 43）" % kensei.sword_qi)

	(ctx["scene"] as Node).free()


# ── D6. 非双持 ───────────────────────────────────

func _test_dual_wield_gate() -> void:
	print("\n[D6] 非双持 → 交刃不触发")
	var ctx: Dictionary = _make_battle()
	if ctx.is_empty():
		return
	var tm: Object = ctx["tm"]
	var kensei: Unit = ctx["kensei"]
	var enemy: Unit = ctx["enemy"]
	_arm_jiaoren(tm, kensei, enemy)

	var dmg_dual: int = _incoming(tm, enemy, kensei, 30)
	_eq("双持时触发（扣 10）", kensei.sword_qi, 20)

	kensei.unequip_offhand()
	_check("前提：确实不再是双持", not kensei.is_dual_wielding())
	var dmg_solo: int = _incoming(tm, enemy, kensei, 30)
	_eq("非双持 → 不触发、不扣剑气", kensei.sword_qi, 30)
	_check("非双持 → 不减伤（挨得更多）", dmg_solo > dmg_dual,
		"双持挨 %d / 单持挨 %d" % [dmg_dual, dmg_solo])

	(ctx["scene"] as Node).free()


# ── D7. 招架架势的两个概率边界 ──────────────────────

func _test_parry_stance_edges() -> void:
	print("\n[D7] 招架架势：概率 0 与概率 100 两个边界 + 减伤幅度精确对照")
	var ctx: Dictionary = _make_battle()
	if ctx.is_empty():
		return
	var tm: Object = ctx["tm"]
	var kensei: Unit = ctx["kensei"]
	var enemy: Unit = ctx["enemy"]
	kensei.talent_ids = []
	kensei.stats.dex = 10          # 减伤 = 40 + 10 = 50%

	# 无架势基线。
	var base: int = _incoming(tm, enemy, kensei, 0)
	_check("基线伤害为正（否则减伤断言全是假通过）", base > 0, "base=%d" % base)

	# 边界一：SPD=0 → 概率 0 → randf() < 0.0 恒为假 → 永不招架。
	kensei.stats.spd = 0
	_add_parry_stance(kensei)
	_check("前提：架势确实挂上了", kensei.has_buff(PARRY_BUFF))
	var spd0: int = _incoming(tm, enemy, kensei, 0)
	_eq("SPD=0（概率 0 边界）→ 有架势也不减伤", spd0, base)

	# 边界二：SPD=100 → 概率 1.0 → randf() < 1.0 恒为真 → 必定招架。
	kensei.stats.spd = 100
	_add_parry_stance(kensei)
	var spd100: int = _incoming(tm, enemy, kensei, 0)
	_check("SPD=100（概率 100 边界）→ 必定减伤", spd100 < base,
		"base=%d spd100=%d" % [base, spd100])
	# 幅度精确对照：50% 减伤 → 乘 0.5。两次都向下取整，所以用 floor 比。
	_eq("减伤幅度 = (40+DEX)% = 50% → 伤害减半（向下取整）",
		spd100, int(floor(float(base) * 0.5)))

	# DEX 换一个值，幅度跟着变 → 证明它真的从 parry 段的 reduction_stat 来，
	# 不是写死的 50。
	kensei.stats.dex = 20          # 减伤 = 60%
	kensei.stats.spd = 100
	_add_parry_stance(kensei)
	var base2: int = base           # 基线与 DEX 无关（DEX 不进伤害公式的防御侧）
	var dex20: int = _incoming(tm, enemy, kensei, 0)
	_eq("DEX=20 → 减伤 60% → 伤害乘 0.4",
		dex20, int(floor(float(base2) * 0.4)))

	(ctx["scene"] as Node).free()


# ── D8. 减伤每次攻击至多一次 ────────────────────────

## 架势与交刃给的是同一份减伤，叠乘等于凭空双倍。顺序是免费的架势先掷、
## 交刃兜底——所以架势成功那次，交刃不该白扣剑气。
func _test_at_most_once() -> void:
	print("\n[D8] 减伤至多结算一次：架势成功时交刃不白扣剑气")
	var ctx: Dictionary = _make_battle()
	if ctx.is_empty():
		return
	var tm: Object = ctx["tm"]
	var kensei: Unit = ctx["kensei"]
	var enemy: Unit = ctx["enemy"]
	_arm_jiaoren(tm, kensei, enemy)
	kensei.stats.dex = 10

	# 只有交刃（无架势）：扣 10，减伤 50%。
	kensei.stats.spd = 0
	var only_talent: int = _incoming(tm, enemy, kensei, 30)
	_eq("只有交刃 → 扣 10 剑气", kensei.sword_qi, 20)

	# 架势必成功 + 交刃同时在身：减伤只结算一次，且剑气一点不扣。
	kensei.stats.spd = 100
	_add_parry_stance(kensei)
	var both: int = _incoming(tm, enemy, kensei, 30)
	_eq("架势成功 → 交刃不扣剑气（免费的先掷，付费的兜底）", kensei.sword_qi, 30)
	_eq("两者同在时减伤只结算一次（伤害与只有交刃时相同）", both, only_talent)

	(ctx["scene"] as Node).free()


# ── D9. prevented 的精确值 ─────────────────────────

## 借力的蓄劲要读「被减免了多少数值」。本波不实装借力，但接口按它的需要做好
## （任务书 §2 问题②答 (a)），所以这个数必须现在就是对的——否则借力落地时
## 会连着减伤实现一起返工。
func _test_prevented_exact() -> void:
	print("\n[D9] prevented（实际减免量）= 不减伤时的伤害 − 减伤后的伤害")
	var ctx: Dictionary = _make_battle()
	if ctx.is_empty():
		return
	var tm: Object = ctx["tm"]
	var kensei: Unit = ctx["kensei"]
	var enemy: Unit = ctx["enemy"]
	kensei.talent_ids = []
	kensei.stats.dex = 10
	kensei.stats.spd = 0

	var base: int = _incoming(tm, enemy, kensei, 0)
	kensei.stats.spd = 100
	_add_parry_stance(kensei)

	# 直接调 _resolve_defense + resolve_attack 走一遍，把 defense 字典拿在手上。
	var action_data: Dictionary = tm._build_hostile_action_context(enemy, kensei, {})
	var outcome: Dictionary = {"hit": true, "crit": false}
	var defense: Dictionary = tm._resolve_defense(enemy, kensei, outcome, "主手")
	_check("架势必成功时 applied=true", bool(defense.get("applied", false)))
	_eq("via 指明是架势那条入口",
		str(defense.get("via", "")), "stance:" + PARRY_BUFF)
	tm._apply_defense_to_action(action_data, defense)
	action_data["precomputed_outcome"] = outcome
	var result: Object = DamageCalculator.resolve_attack(enemy, kensei, action_data)
	tm._record_parry_prevented(enemy, kensei, action_data, result, defense)
	_eq("prevented == 不减伤时的伤害 − 减伤后的伤害",
		int(defense.get("prevented", -1)), base - result.damage)
	_check("prevented 为正（这一档确实挡下了东西）",
		int(defense.get("prevented", 0)) > 0,
		"prevented=%d base=%d after=%d" % [
			int(defense.get("prevented", 0)), base, result.damage])

	(ctx["scene"] as Node).free()


# ── D10. 副手那一击也走防御侧 ──────────────────────

## 攻击方双持时，主手与副手追加**各分发一次**「受到攻击时」（沿用 Wave 3 问题①
## 的 (c)：副手是独立结算命中与暴击的一次伤害）。
##
## 这一组同时把那个已知疑点变成**可观测的事实**而不是推测：交刃在被双持者攻击时，
## 一次攻击动作内会扣两次剑气。数字摆出来，用户才好裁决要不要改成每动作一次。
func _test_offhand_side_defense() -> void:
	print("\n[D10] 攻击方双持时，主手与副手各分发一次防御侧事件")
	var ctx: Dictionary = _make_battle()
	if ctx.is_empty():
		return
	var tm: Object = ctx["tm"]
	var kensei: Unit = ctx["kensei"]
	var enemy: Unit = ctx["enemy"]

	# 先测单手基线：观测卡只加一次气。
	kensei.talent_ids = ["test_def_any"]
	enemy.talent_ids = []
	_incoming(tm, enemy, kensei, 0)
	_eq("攻击方单手 → 防御侧事件发 1 次（+3）", kensei.sword_qi, 3)

	# 让**攻击方**双持并装上二天一流，制造副手追加。
	if enemy.weapon_id == "":
		enemy.weapon_id = "sword_basic"
	enemy.equip_offhand(OFFHAND_WEAPON)
	enemy.talent_ids = ["kensei_ertianyiliu"]
	_check("前提：攻击方确实双持", enemy.is_dual_wielding())
	_incoming(tm, enemy, kensei, 0)
	_eq("攻击方双持 → 主手与副手各发一次（+3×2）", kensei.sword_qi, 6)

	# 交刃在这种局面下会扣两次剑气 —— 已知疑点，用断言把它钉成事实。
	_arm_jiaoren(tm, kensei, enemy)
	_incoming(tm, enemy, kensei, 30)
	_eq("被双持者攻击 → 交刃一次动作内扣两次剑气（30−10−10=10）【已知疑点，待用户裁决】",
		kensei.sword_qi, 10)

	# 剑气只够一次时，只扣一次、扣完就没了（不会扣成负数）。
	_incoming(tm, enemy, kensei, 10)
	_eq("剑气只够一次 → 只扣一次，不扣成负数", kensei.sword_qi, 0)

	(ctx["scene"] as Node).free()


# ── 辅助 ────────────────────────────────────────

## 造一场「敌人打剑圣」的战斗。注意与 test_talent_onhit 的 _make_battle 方向相反。
func _make_battle() -> Dictionary:
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
	tm.debug_crit_mode = CRIT_DISABLE

	var kensei: Unit = null
	var enemy: Unit = null
	for u: Unit in tm.units:
		if u.faction == "player" and u.unit_id == "kensei":
			kensei = u
		elif u.faction == "enemy" and enemy == null:
			enemy = u
	if kensei == null or enemy == null:
		_check("场景中找到剑圣与敌人", false, "kensei/enemy 缺失")
		scene.free()
		return {}
	# 剑圣当被攻击者：防御归零让伤害稳定为正，攻方拉高保证减伤看得出差。
	kensei.stats.def_attr = 0
	kensei.stats.res = 0
	enemy.stats.str_attr = 40
	# 回合归属默认摆在敌人身上（= 剑圣处于自身回合外），D3 会自己改。
	tm.turn_manager.current_unit = enemy
	return {"scene": scene, "tm": tm, "kensei": kensei, "enemy": enemy}


## 让剑圣具备交刃的全部前置：双持 + 装上卡。
func _arm_jiaoren(tm: Object, kensei: Unit, _enemy: Unit) -> void:
	if kensei.weapon_id == "":
		kensei.weapon_id = "sword_basic"
	kensei.equip_offhand(OFFHAND_WEAPON)
	_check("前提：剑圣处于双持", kensei.is_dual_wielding())
	kensei.talent_ids = ["kensei_jiaoren"]
	_check("前提：交刃已注册（否则装了也不会触发）",
		tm._ensure_talent_registry().is_registered("kensei_jiaoren"),
		tm._ensure_talent_registry().rejection_reason("kensei_jiaoren"))


## 挂一层招架架势。duration=1 会在回合结束时递减，测试里不走回合流程，
## 但每次攻击前重挂一次更稳（refresh_on_reapply=true）。
## ★ 走 `/root/DataLoader` 节点查找而不是写 `DataLoader.xxx`：autoload 的**标识符**
## 在 `--script` 起的 SceneTree 上下文里解析不了（编译期就报 Identifier not found），
## 节点本身倒是在的。全仓测试都用这个写法，别改回去。
func _add_parry_stance(unit: Unit) -> void:
	var dl: Node = root.get_node_or_null("/root/DataLoader")
	if dl == null:
		_check("autoload DataLoader 可达", false)
		return
	var raw: Variant = dl.buffs.get(PARRY_BUFF, {})
	if not raw is Dictionary:
		_check("招架架势 buff 数据可读", false)
		return
	unit.add_buff(BuffEffect.from_dict(raw as Dictionary))


## 挨一次打，返回本次挨到的伤害。每次复位血量，让相邻用例互不串味。
func _incoming(tm: Object, enemy: Unit, kensei: Unit, qi: int = -1) -> int:
	kensei.stats.max_hp = 99999
	kensei.stats.hp = 99999
	if qi >= 0:
		kensei.set_sword_qi(qi)
	tm._execute_hostile_action(enemy, kensei, {})
	return 99999 - kensei.stats.hp


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
