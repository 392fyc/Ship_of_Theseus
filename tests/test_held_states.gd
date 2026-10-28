extends SceneTree
## 状态与资源底座（gameplay-impl PR2，gap-list M1 / M2 / 回合钩子）。
##
## 覆盖：
##   ① 装载回读：data/held_states/*.json 进了 DataLoader.held_states，镜像字段与设计库快照一致的关键项。
##   ② HeldStateSet 语义：四种持续时间口径、额外回合不计数、四种再获得方式加 set_stacks、
##      层数上限与按层消耗、永久状态无视传入时长、非永久状态缺时长被拒（R3.4）。
##   ③ 剑气统一入口：上限作废、下限 0、拦截器改写方向、sword_qi_changed 报实际变化量。
##   ④ 接入战术管理器：回合开始 / 结束钩子计数、is_taking_turn、命中得气走统一入口、战斗开始清零。
##
## 运行：
##   <Godot_console.exe> --headless --path <worktree> --script res://tests/test_held_states.gd
## 退出码 0=全过，1=有失败。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_held_states (状态与资源底座) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	var dl: Object = load("res://scripts/data/data_loader.gd").new()
	dl.load_all()
	_test_loading(dl)
	var defs: Dictionary = dl.held_states
	_test_durations(defs)
	_test_reapplication(defs)
	_test_stacks_and_guards(defs)
	dl.free()

	var scene: Node = load("res://scenes/tactical/TacticalScene.tscn").instantiate()
	root.add_child(scene)
	var tm: Object = scene.tactical_manager
	_check("tactical_manager 脚本已挂载", tm != null and tm.get_script() != null)
	if tm != null and tm.get_script() != null:
		_eq("tactical_manager 挂的是 tactical_manager.gd",
			(tm.get_script() as Script).resource_path, "res://scripts/core/tactical_manager.gd")
		if tm.turn_manager != null:
			tm.turn_manager.stop()
		var sword: Unit = _find(tm, "kensei")
		var enemy: Unit = _find_enemy(tm)
		if sword == null or enemy == null:
			_check("场景含剑圣与敌人", false)
		else:
			_check("单位脚本已挂载", sword.get_script() != null
				and (sword.get_script() as Script).resource_path == "res://scripts/units/unit.gd")
			_test_qi_pipeline(sword)
			_test_turn_hooks(tm, sword)
			_test_on_hit_routes_through_pipeline(tm, sword, enemy)
			_test_battle_start_clears(tm, sword)
	scene.queue_free()

	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  ✗ " + f)
	quit(0 if _fail == 0 else 1)


# ── ① 装载回读 ───────────────────────────────────────

const EXPECTED_IDS: Array[String] = ["kensei_nadao", "kensei_jiashi", "kensei_jianqie_stance",
	"kensei_ruoji", "kensei_ruoli", "kensei_chengxin", "kensei_kongxiang", "kensei_jianhen",
	"kensei_taiyang", "kensei_taiyin", "taunt"]


func _test_loading(dl: Object) -> void:
	print("\n[①] 装载回读")
	_check("DataLoader 有 held_states 字典", dl.get("held_states") is Dictionary)
	_eq("held_states 装载数 == 目录 JSON 文件数",
		dl.held_states.size(), _count_json_files("res://data/held_states/"))
	for sid: String in EXPECTED_IDS:
		_check("已注册 " + sid, dl.held_states.has(sid))
	var overlap: Array[String] = []
	for sid: Variant in dl.held_states.keys():
		if dl.states.has(sid) or dl.buffs.has(sid):
			overlap.append(str(sid))
	_eq("与条件状态、旧 buff 无 id 交集", overlap, [] as Array[String])
	_eq("条件状态注册表不受影响（仍为背水、双持 2 条）", dl.states.size(), 2)
	# 关键结构字段：来自设计库快照 762393b，抄错会直接改变运行行为。
	var jianqie: Dictionary = dl.held_states.get("kensei_jianqie_stance", {})
	_eq("见切 最大 3 层", int(jianqie.get("max_stacks", 0)), 3)
	_eq("见切 设计库再获得方式原值保留", jianqie.get("reapplication_mode"), "add_stacks")
	_eq("见切 引擎按 effect 设为本次层数（Q3）", jianqie.get("engine_reapplication_mode"), "set_stacks")
	var jiashi: Dictionary = dl.held_states.get("kensei_jiashi", {})
	_eq("架势 刷新持续时间", jiashi.get("reapplication_mode"), "refresh_duration")
	_eq("架势 非永久", jiashi.get("is_permanent"), false)
	_eq("澄心 永久", dl.held_states.get("kensei_chengxin", {}).get("is_permanent"), true)
	_eq("剑痕 最大 5 层", int(dl.held_states.get("kensei_jianhen", {}).get("max_stacks", 0)), 5)
	_eq("嘲讽 独立实例", dl.held_states.get("taunt", {}).get("reapplication_mode"),
		"create_independent_instance")


# ── ② 持续时间 ───────────────────────────────────────

func _test_durations(defs: Dictionary) -> void:
	print("\n[②a] 持续时间口径")
	var start2: Dictionary = {"kind": "until_own_turn_start", "count": 2}

	# 架势：在自身回合内获得，持续到其后第 2 个自身回合开始。
	var s := HeldStateSet.new(defs)
	_check("施加架势", s.apply("kensei_jiashi", 1, start2, {"total_reduction_pct": 20}, "", true))
	s.on_own_turn_ended()                    # 获得时所在回合结束
	_check("本回合结束后仍持有", s.has("kensei_jiashi"))
	s.on_own_turn_started()                  # 其后第 1 个自身回合开始
	_check("其后第 1 个自身回合开始时仍持有", s.has("kensei_jiashi"))
	_eq("剩余计数 1", s.remaining("kensei_jiashi"), 1)
	s.on_own_turn_ended()
	s.on_own_turn_started(true)              # 额外回合不计数
	_check("额外回合开始不计入持续时间", s.has("kensei_jiashi"))
	s.on_own_turn_ended(true)
	var expired: Array[String] = s.on_own_turn_started()   # 其后第 2 个常规自身回合开始
	_check("其后第 2 个自身回合开始时结束", not s.has("kensei_jiashi"))
	_eq("结束时报出 id", expired, ["kensei_jiashi"] as Array[String])

	# 若离：持续到下个自身回合结束。自身回合内获得 → 本回合结束不计。
	var r := HeldStateSet.new(defs)
	r.apply("kensei_ruoli", 1, {"kind": "until_own_turn_end", "count": 1}, {}, "", true)
	r.on_own_turn_ended()
	_check("自身回合内获得：本回合结束不计数", r.has("kensei_ruoli"))
	r.on_own_turn_started()
	r.on_own_turn_ended()
	_check("下个自身回合结束时结束", not r.has("kensei_ruoli"))

	# 敌方回合内获得 → 即将到来的自身回合结束就是「下个」。
	var r2 := HeldStateSet.new(defs)
	r2.apply("kensei_ruoli", 1, {"kind": "until_own_turn_end", "count": 1}, {}, "", false)
	r2.on_own_turn_started()
	r2.on_own_turn_ended(true)
	_check("额外回合结束不计数", r2.has("kensei_ruoli"))
	r2.on_own_turn_ended()
	_check("敌方回合内获得：下个常规自身回合结束时结束", not r2.has("kensei_ruoli"))

	# 空想：到本回合结束，额外回合也结束它。
	var k := HeldStateSet.new(defs)
	k.apply("kensei_kongxiang", 1, {"kind": "until_this_turn_end"}, {}, "", true)
	k.on_own_turn_started()
	_check("回合开始不影响「到本回合结束」", k.has("kensei_kongxiang"))
	k.on_own_turn_ended(true)
	_check("回合结束时结束（含额外回合）", not k.has("kensei_kongxiang"))

	# 永久状态：无视传入的时长，回合推进不结束。
	var c := HeldStateSet.new(defs)
	c.apply("kensei_chengxin", 1, start2)
	for _i: int in range(5):
		c.on_own_turn_started()
		c.on_own_turn_ended()
	_check("永久状态不随回合结束", c.has("kensei_chengxin"))
	_eq("永久状态剩余计数为 -1", c.remaining("kensei_chengxin"), -1)

	# 敌方回合内获得「到其后第 2 个自身回合开始」：计数与自身回合内获得相同。
	var e := HeldStateSet.new(defs)
	e.apply("kensei_jiashi", 1, start2, {}, "", false)
	e.on_own_turn_started()
	_eq("敌方回合获得：其后第 1 个回合开始剩 1", e.remaining("kensei_jiashi"), 1)
	e.on_own_turn_ended()
	e.on_own_turn_started()
	_check("敌方回合获得：其后第 2 个回合开始结束", not e.has("kensei_jiashi"))

	# 敌方回合获得「到下个自身回合结束」，在 T1 内被刷新：刷新时所在的 T1 不计，T2 结束才结束。
	var rf := HeldStateSet.new(defs)
	var end1: Dictionary = {"kind": "until_own_turn_end", "count": 1}
	rf.apply("kensei_ruoli", 1, end1, {}, "", false)
	rf.on_own_turn_started()
	rf.apply("kensei_ruoli", 1, end1, {}, "", true)
	rf.on_own_turn_ended()
	_check("自身回合内刷新：刷新所在回合的结束不计", rf.has("kensei_ruoli"))
	rf.on_own_turn_started()
	rf.on_own_turn_ended()
	_check("刷新后的下个自身回合结束时结束", not rf.has("kensei_ruoli"))

	# 在持有者回合之外获得「到本回合结束」：保留到持有者下一个自身回合结束（已写明的口径）。
	var ko := HeldStateSet.new(defs)
	ko.apply("kensei_kongxiang", 1, {"kind": "until_this_turn_end"}, {}, "", false)
	ko.on_own_turn_started()
	_check("回合外获得：持有者回合开始时仍在", ko.has("kensei_kongxiang"))
	ko.on_own_turn_ended()
	_check("回合外获得：持有者回合结束时结束", not ko.has("kensei_kongxiang"))


# ── ② 再获得方式 ─────────────────────────────────────

func _test_reapplication(defs: Dictionary) -> void:
	print("\n[②b] 再获得方式")
	var start2: Dictionary = {"kind": "until_own_turn_start", "count": 2}

	var s := HeldStateSet.new(defs)
	s.apply("kensei_jiashi", 1, start2, {"total_reduction_pct": 20})
	s.on_own_turn_started()
	s.apply("kensei_jiashi", 1, start2, {"total_reduction_pct": 25})
	_eq("refresh_duration：持续时间刷新为 2", s.remaining("kensei_jiashi"), 2)
	_eq("refresh_duration：参数取本次给予的（浮生若梦 25%）",
		int(s.params("kensei_jiashi").get("total_reduction_pct", 0)), 25)
	_eq("refresh_duration：不叠层", s.stacks("kensei_jiashi"), 1)

	var j := HeldStateSet.new(defs)
	j.apply("kensei_jianqie_stance", 3, start2)
	j.consume_stacks("kensei_jianqie_stance", 2)
	j.on_own_turn_started()
	j.apply("kensei_jianqie_stance", 2, start2)
	_eq("set_stacks：层数改为本次获得的 2（不是 1+2）", j.stacks("kensei_jianqie_stance"), 2)
	_eq("set_stacks：刷新持续时间", j.remaining("kensei_jianqie_stance"), 2)

	var ruoji := HeldStateSet.new(defs)
	ruoji.apply("kensei_ruoji", 2, start2)
	ruoji.on_own_turn_started()
	ruoji.apply("kensei_ruoji", 2, start2)
	_eq("add_stacks：层数相加并截到上限 3", ruoji.stacks("kensei_ruoji"), 3)
	_eq("add_stacks + use_incoming：刷新持续时间", ruoji.remaining("kensei_ruoji"), 2)

	var cx := HeldStateSet.new(defs)
	cx.apply("kensei_chengxin", 1)
	cx.apply("kensei_chengxin", 1)
	_eq("永久 add_stacks：逐层叠加", cx.stacks("kensei_chengxin"), 2)

	var n := HeldStateSet.new(defs)
	_check("纳刀首次施加成功", n.apply("kensei_nadao"))
	_check("ignore_incoming：重复施加被忽略", not n.apply("kensei_nadao"))
	_eq("ignore_incoming：仍为 1 层", n.stacks("kensei_nadao"), 1)

	var t := HeldStateSet.new(defs)
	t.apply("taunt")
	t.apply("taunt")
	_eq("create_independent_instance：两个独立实例", t.to_array().size(), 2)
	_eq("held_ids 去重", t.held_ids(), ["taunt"] as Array[String])
	t.remove("taunt")
	_check("remove 移除全部实例", not t.has("taunt"))

	t.apply("taunt")
	t.apply("taunt")
	_eq("独立实例层数合计 2", t.stacks("taunt"), 2)
	_eq("跨实例消耗 2 层返回 2", t.consume_stacks("taunt", 2), 2)
	_check("两个实例都已移除", not t.has("taunt"))

	var full := HeldStateSet.new(defs)
	full.apply("kensei_jianhen", 5)
	_check("满层且不刷新时再获得返回 false", not full.apply("kensei_jianhen", 1))
	_eq("满层仍为 5", full.stacks("kensei_jianhen"), 5)
	var ruoji_full := HeldStateSet.new(defs)
	ruoji_full.apply("kensei_ruoji", 3, start2)
	ruoji_full.on_own_turn_started()
	_check("满层但刷新持续时间时返回 true", ruoji_full.apply("kensei_ruoji", 1, start2))
	_eq("满层刷新后剩余计数为 2", ruoji_full.remaining("kensei_ruoji"), 2)


# ── ② 层数与防护 ─────────────────────────────────────

func _test_stacks_and_guards(defs: Dictionary) -> void:
	print("\n[②c] 层数消耗与防护")
	var s := HeldStateSet.new(defs)
	s.apply("kensei_jianhen", 9)
	_eq("首次施加截到上限 5", s.stacks("kensei_jianhen"), 5)
	_eq("消耗 2 层返回 2", s.consume_stacks("kensei_jianhen", 2), 2)
	_eq("剩 3 层", s.stacks("kensei_jianhen"), 3)
	_eq("消耗超过持有只扣到 0", s.consume_stacks("kensei_jianhen", 9), 3)
	_check("层数归零即移除", not s.has("kensei_jianhen"))
	_eq("未持有时消耗返回 0", s.consume_stacks("kensei_jianhen"), 0)

	var changes: Array[int] = [0]
	s.changed.connect(func() -> void: changes[0] += 1)
	s.apply("kensei_ruoli", 1, {"kind": "until_own_turn_end", "count": 1})
	_eq("变化时发出 changed", changes[0], 1)

	print("  （以下 3 项预期打印 [HeldStateSet] 错误，属于被测行为）")
	_check("R3.4：非永久状态缺持续时间被拒", not s.apply("kensei_jiashi"))
	_check("未注册 id 被拒", not s.apply("not_a_state", 1, {"kind": "until_this_turn_end"}))
	_check("count 非正被拒", not s.apply("kensei_jiashi", 1, {"kind": "until_own_turn_start"}))
	_check("被拒后不持有", not s.has("kensei_jiashi"))

	var round_trip := HeldStateSet.new(defs)
	round_trip.load_array(s.to_array())
	_eq("to_array / load_array 往返", round_trip.to_array(), s.to_array())


# ── ③ 剑气统一入口 ───────────────────────────────────

func _test_qi_pipeline(u: Unit) -> void:
	print("\n[③] 剑气统一入口")
	var events: Array[Dictionary] = []
	var listener: Callable = func(_unit: Unit, kind: String, requested: int, actual: int,
			source: String) -> void:
		events.append({"kind": kind, "requested": requested, "actual": actual, "source": source})
	u.sword_qi_changed.connect(listener)
	var qi_max: int = u._qi_max
	_check("剑圣有剑气上限", qi_max > 0)

	u.set_sword_qi(qi_max - 5)
	events.clear()
	_eq("获得超过上限：实际只加到上限", u.gain_sword_qi(20, "t"), 5)
	_eq("剑气 = 上限", u.sword_qi, qi_max)
	_eq("事件报请求量 20、实际 +5", [events[0]["requested"], events[0]["actual"]], [20, 5])
	_eq("事件带来源", events[0]["source"], "t")

	u.set_sword_qi(10)
	_eq("消耗超过持有：最低到 0，实际 −10", u.spend_sword_qi(30, "cost"), -10)
	_eq("剑气 = 0", u.sword_qi, 0)
	_eq("消耗事件方向为 spend", events[-1]["kind"], "spend")
	_eq("lose 也走同一入口", u.lose_sword_qi(5), 0)
	_eq("lose 事件方向为 lose", events[-1]["kind"], "lose")

	var before: int = events.size()
	_eq("请求量为 0 时不变化", u.gain_sword_qi(0), 0)
	_eq("请求量为 0 时不发事件", events.size(), before)

	# 拦截器：模拟〔空想〕把获得改为失去。
	var invert: Callable = func(_unit: Unit, kind: String, amount: int, _source: String) -> Dictionary:
		return {"kind": "lose", "amount": amount} if kind == "gain" else {}
	u.add_qi_interceptor(invert)
	u.set_sword_qi(40)
	_eq("拦截后获得 15 变为失去 15", u.gain_sword_qi(15, "on_hit"), -15)
	_eq("剑气 40 → 25", u.sword_qi, 25)
	_eq("拦截后事件方向为 lose", events[-1]["kind"], "lose")
	_eq("消耗不受该拦截器影响", u.spend_sword_qi(5), -5)
	u.remove_qi_interceptor(invert)
	_eq("移除拦截器后恢复获得", u.gain_sword_qi(5), 5)
	u.sword_qi_changed.disconnect(listener)


# ── ④ 回合钩子 ───────────────────────────────────────

func _test_turn_hooks(tm: Object, u: Unit) -> void:
	print("\n[④a] 回合钩子")
	u.held_states.clear()
	tm.battle_active = true
	tm.turn_manager.current_unit = u
	tm._on_turn_started(u)
	_check("回合开始后 is_taking_turn = true", u.is_taking_turn)
	_check("在自身回合内施加架势",
		u.apply_held_state("kensei_jiashi", 1, {"kind": "until_own_turn_start", "count": 2}))
	_check("在自身回合内施加若离",
		u.apply_held_state("kensei_ruoli", 1, {"kind": "until_own_turn_end", "count": 1}))
	tm._on_turn_ended(u)
	_check("回合结束后 is_taking_turn = false", not u.is_taking_turn)
	_check("获得时所在回合结束：若离仍在", u.held_states.has("kensei_ruoli"))
	tm.turn_manager.current_unit = u
	tm._on_turn_started(u)
	_eq("下个回合开始：架势剩余 1", u.held_states.remaining("kensei_jiashi"), 1)
	tm._on_turn_ended(u)
	_check("下个回合结束：若离结束", not u.held_states.has("kensei_ruoli"))
	tm.turn_manager.current_unit = u
	tm._on_turn_started(u)
	_check("其后第 2 个回合开始：架势结束", not u.held_states.has("kensei_jiashi"))
	tm._on_turn_ended(u)
	tm.battle_active = false
	tm.turn_manager.current_unit = null


func _test_on_hit_routes_through_pipeline(tm: Object, atk: Unit, _dfn: Unit) -> void:
	print("\n[④b] 命中得气走统一入口")
	var events: Array[String] = []
	var listener: Callable = func(_unit: Unit, kind: String, _requested: int, _actual: int,
			source: String) -> void:
		events.append(kind + "|" + source)
	atk.sword_qi_changed.connect(listener)
	atk.set_sword_qi(0)
	var result := DamageCalculator.AttackResult.new()
	result.hit = true
	tm._apply_sword_qi_on_hit(atk, result, {"qi_gain_on_hit": 25, "skill_id": "probe"})
	_eq("命中得 25 剑气", atk.sword_qi, 25)
	_eq("经统一入口发出事件", events, ["gain|on_hit:probe"] as Array[String])
	events.clear()
	tm._apply_talent_effect(atk, "probe_talent",
		{"type": "gain_resource", "resource": "qi", "amount": 10}, {})
	_eq("天赋 gain_resource 得 10 剑气", atk.sword_qi, 35)
	_eq("天赋得气经统一入口", events, ["gain|talent:probe_talent"] as Array[String])
	print("  （下一项预期打印 [Talent] 告警，属于被测行为）")
	tm._apply_talent_effect(atk, "probe_talent",
		{"type": "gain_resource", "resource": "qi", "amount": 0}, {})
	_eq("数量为 0 的 gain_resource 被忽略、剑气不变", atk.sword_qi, 35)
	atk.sword_qi_changed.disconnect(listener)


func _test_battle_start_clears(tm: Object, u: Unit) -> void:
	print("\n[④c] 战斗开始清零")
	u.apply_held_state("kensei_chengxin", 2)
	u.is_taking_turn = true
	_check("战斗前持有澄心", u.held_states.has("kensei_chengxin"))
	tm.start_battle()
	tm.stop_battle()
	_check("start_battle 清空持有型状态（含永久）", not u.held_states.has("kensei_chengxin"))
	u.is_taking_turn = true
	tm.stop_battle()
	_check("stop_battle 复位 is_taking_turn", not u.is_taking_turn)
	u.apply_held_state("kensei_chengxin", 1)
	tm._debug_reset_unit(u)
	_check("调试复位清空持有型状态", not u.held_states.has("kensei_chengxin"))


# ── 工具 ─────────────────────────────────────────────

func _find(tm: Object, unit_id: String) -> Unit:
	for u: Variant in tm.units:
		if u is Unit and (u as Unit).unit_id == unit_id:
			return u
	return null


func _find_enemy(tm: Object) -> Unit:
	for u: Variant in tm.units:
		if u is Unit and (u as Unit).faction == "enemy":
			return u
	return null


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
