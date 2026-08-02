extends SceneTree
## RunManager v0 headless 回归测试 —— 2026-07-04
##
## 覆盖 scripts/roguelite/ 的 run_state.gd / reward_resolver.gd / run_manager.gd：
##   1. 8 关流转：start_run 后连续 victory 直到 run_completed；stage 依次 1→8，
##      每步 phase 正确；stage 2..7 有 door_select 并 choose_door；stage 8 = Boss
##      （不 door_select）。
##   2. 结算顺序：固定结算先于门奖励（summary.sequence 验证）；stage 1 无门奖励；
##      stage 8 用 Boss 固定包（含 equipment+relic）。
##   3. 金币经验账本：gold 单调累积；每角色 exp 累积；喂足 exp 触发升级
##      （level++、talent_points++、exp 扣阈值）。
##   4. 每角色独立掉落：relic 门 → 每角色各得 1 遗物；equipment 门 → 每角色各得装备。
##   5. relic_drought 按出现跨关传递（复用 door_generator 语义，非按选中）。
##   6. 失败路径：defeat → run_failed、phase==failed。
##   7. 边界：relic 6 槽上限（满则溢出 convoy）；Boss 固定包品质字段存在。
##
## 坑规避（--script 三大坑）：逻辑放 _process 首帧；preload 不用 class_name；
## DataLoader 手动 load_all()。
##
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/test_run_manager.gd
## 退出码 0=全过，1=有失败。

const ACT_CONFIG_FILE: String = "res://data/runloop/act1_config.json"
const RUN_CONFIG_FILE: String = "res://data/runloop/run_config.json"
const DATA_LOADER_SCRIPT: String = "res://scripts/data/data_loader.gd"

const RunStateScript: GDScript = preload("res://scripts/roguelite/run_state.gd")
const RewardResolverScript: GDScript = preload("res://scripts/roguelite/reward_resolver.gd")
const RunManagerScript: GDScript = preload("res://scripts/roguelite/run_manager.gd")

const RNG_SEED: int = 20260704

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _act_config: Dictionary = {}
var _run_config: Dictionary = {}
var _pools: Dictionary = {}
var _boss_stage: int = 8
var _roster: Array = []

# ── 信号收集器 ──
var _summaries: Array = []
var _doors_events: Array = []
var _stage_events: Array[int] = []
var _completed: bool = false
var _failed: bool = false

# ── 全流程统计缓存（供最终打印，避免被后续测试重置） ──
var _flow_gold: int = 0
var _flow_levels: Array[int] = []
var _flow_drops: int = 0


func _initialize() -> void:
	print("=== test_run_manager (RunManager v0 回归) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	if not _load_env():
		_finish()
		return
	_rng.seed = RNG_SEED

	_test_full_flow()
	_test_settlement_order()   # 读 _summaries（须在任何 _new_manager 重置前）
	_test_gold_ledger()        # 读 _summaries
	_test_forced_levelup()     # 新 manager（重置收集器）
	_test_multi_level_up()     # 多级跳升（while 非 if）
	_test_gold_not_scaled()    # gold 单发未按人数放大
	_test_per_char_drops()
	_test_relic_drought_appearance()
	_test_failure()
	_test_phase_guard()        # phase 守卫防非战斗阶段重复结算
	_test_boundaries()
	_print_stats()

	_finish()


# ── 环境加载 ─────────────────────────────────────────

func _load_env() -> bool:
	var act_v: Variant = _load_json(ACT_CONFIG_FILE)
	_check("act1_config.json 可解析为 Dictionary", act_v is Dictionary)
	if not (act_v is Dictionary):
		return false
	_act_config = act_v
	_boss_stage = int(_act_config.get("boss_stage", 8))

	var run_v: Variant = _load_json(RUN_CONFIG_FILE)
	_check("run_config.json 可解析为 Dictionary", run_v is Dictionary)
	if not (run_v is Dictionary):
		return false
	_run_config = run_v

	# DataLoader：手动 load_all（.new() 不入树，_ready 不触发）
	var dl: Object = load(DATA_LOADER_SCRIPT).new()
	dl.load_all()
	_pools = {
		"equipment": dl.equipment,
		"relics": dl.relics,
		"waves": dl.waves,
		"maps": dl.maps,
		"events": dl.events,
	}
	_check("data_pools.equipment 非空", not (dl.equipment as Dictionary).is_empty())
	_check("data_pools.relics 非空", not (dl.relics as Dictionary).is_empty())

	# 3 人队伍 roster（class_id / level / max_hp 最简，其余由 RunState 补齐）
	_roster = [
		{ "class_id": "kensei", "level": 1, "max_hp": 30 },
		{ "class_id": "knight", "level": 1, "max_hp": 34 },
		{ "class_id": "archer", "level": 1, "max_hp": 26 },
	]
	return _fail == 0


# ── 测试 1：8 关流转 ─────────────────────────────────

func _test_full_flow() -> void:
	var rm: Object = _new_manager()
	rm.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), _rng)
	_check("[1] start_run: stage==1", rm.get_state().stage == 1, "stage=%d" % rm.get_state().stage)
	_check("[1] start_run: phase==battle", rm.get_state().phase == "battle",
		"phase=%s" % rm.get_state().phase)
	_check("[1] start_run: 队伍 3 人且字段补齐",
		rm.get_state().party.size() == 3
		and rm.get_state().party[0].has("relics")
		and (rm.get_state().party[0].get("equipment") as Dictionary).has("weapon"))

	var stage_seq: Array[int] = [rm.get_state().stage]
	var door_selects: int = 0
	var guard: int = 0
	while not rm.is_run_complete() and not rm.is_run_failed() and guard < 40:
		guard += 1
		var cur_stage: int = rm.get_state().stage
		rm.on_battle_resolved("victory")
		if rm.is_run_complete():
			break
		var ph: String = rm.get_state().phase
		if ph == "door_select":
			door_selects += 1
			var pd: Array = rm.get_state().pending_doors
			_check("[1] 门组门数在 [2,3]（为 stage %d 掷）" % (cur_stage + 1),
				pd.size() >= 2 and pd.size() <= 3, "size=%d" % pd.size())
			var idx: int = _choose_index(pd)
			rm.choose_door(idx)
			_check("[1] choose_door 后 phase==prep", rm.get_state().phase == "prep",
				"phase=%s" % rm.get_state().phase)
			rm.confirm_departure()
			_check("[1] confirm 后 phase==battle", rm.get_state().phase == "battle")
			stage_seq.append(rm.get_state().stage)
		elif ph == "prep":
			# Boss 前分支（stage 7 → 8）：无 door_select
			_check("[1] Boss 前 prep 时 current_entry_door 为 Boss 标记",
				rm.get_state().current_entry_door != null
				and str((rm.get_state().current_entry_door as Dictionary).get("reward_type", "")) == "boss")
			rm.confirm_departure()
			_check("[1] Boss 前 confirm 后 phase==battle", rm.get_state().phase == "battle")
			stage_seq.append(rm.get_state().stage)
		else:
			_check("[1] 意外 phase: %s" % ph, false)
			break

	_check("[1] run 已完成", rm.is_run_complete())
	_check("[1] 最终 stage == boss_stage(%d)" % _boss_stage,
		rm.get_state().stage == _boss_stage, "stage=%d" % rm.get_state().stage)
	_check("[1] run_completed 信号已发", _completed)
	_check("[1] phase==complete", rm.get_state().phase == "complete")
	_check("[1] 门选择恰 6 次（stage 2..7）", door_selects == 6, "实际 %d" % door_selects)
	_check("[1] stage 序列 == [1..8]", stage_seq == [1, 2, 3, 4, 5, 6, 7, 8],
		str(stage_seq))
	_check("[1] stage_advanced 发 7 次（2..8）", _stage_events.size() == 7,
		str(_stage_events))
	_check("[1] stage_advanced 序列 == [2..8]",
		_stage_events == [2, 3, 4, 5, 6, 7, 8], str(_stage_events))
	_check("[1] reward_settled 发 8 次（每关一次）", _summaries.size() == 8,
		"实际 %d" % _summaries.size())

	# 统计缓存
	var st: Object = rm.get_state()
	_flow_gold = st.gold
	_flow_levels = []
	for member: Dictionary in st.party:
		_flow_levels.append(int(member.get("level", 1)))
	_flow_drops = 0
	for s_v: Variant in _summaries:
		var s: Dictionary = s_v
		if s.has("door") and (s["door"] as Dictionary).get("drops") is Array:
			_flow_drops += ((s["door"] as Dictionary)["drops"] as Array).size()
		if s.has("boss") and (s["boss"] as Dictionary).get("drops") is Array:
			_flow_drops += ((s["boss"] as Dictionary)["drops"] as Array).size()


# ── 测试 2：结算顺序 ─────────────────────────────────

func _test_settlement_order() -> void:
	if _summaries.size() != 8:
		_check("[2] 需要 8 条 summary 才能验证结算顺序", false)
		return
	# stage 1：只有固定结算，无门奖励
	var s1: Dictionary = _summaries[0]
	_check("[2] stage 1 只有固定结算（sequence==[fixed]）",
		(s1.get("sequence") as Array) == ["fixed"], str(s1.get("sequence")))

	# stage 2..7（索引 1..6）：固定先于门奖励
	for i: int in range(1, 7):
		var s: Dictionary = _summaries[i]
		var seq: Array = s.get("sequence", [])
		_check("[2] stage %d sequence[0]==fixed（固定先结算）" % (i + 1),
			seq.size() >= 1 and str(seq[0]) == "fixed", str(seq))
		_check("[2] stage %d 含门奖励（sequence 含 door）" % (i + 1),
			seq.has("door"), str(seq))

	# stage 8（索引 7）：固定 + Boss 固定包
	var s8: Dictionary = _summaries[7]
	_check("[2] stage 8 == 固定 + Boss 固定包（sequence==[fixed,boss]）",
		(s8.get("sequence") as Array) == ["fixed", "boss"], str(s8.get("sequence")))
	var boss_v: Variant = s8.get("boss")
	_check("[2] stage 8 boss summary 存在", boss_v is Dictionary)
	if boss_v is Dictionary:
		var kinds: Array = (boss_v as Dictionary).get("package_kinds", [])
		_check("[2] Boss 固定包含 equipment", kinds.has("equipment"), str(kinds))
		_check("[2] Boss 固定包含 relic", kinds.has("relic"), str(kinds))


# ── 测试 3a：金币账本单调 ─────────────────────────────

func _test_gold_ledger() -> void:
	var prev: int = 0
	var monotonic: bool = true
	for s_v: Variant in _summaries:
		var s: Dictionary = s_v
		var after: int = int(s.get("gold_after", -1))
		if after < prev:
			monotonic = false
		prev = after
	_check("[3] gold 全程单调不减", monotonic, "末值 %d" % prev)
	_check("[3] 末关后 gold > 0", prev > 0, "gold=%d" % prev)


# ── 测试 3b：强制升级 ─────────────────────────────────

func _test_forced_levelup() -> void:
	var rm: Object = _new_manager()
	rm.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), _rng)
	var st: Object = rm.get_state()

	var threshold: int = _exp_threshold_cfg(1)
	var exp_each: int = _fixed_exp()
	_check("[3] 前置：固定 exp 增量 >= 1（能跨阈值）", exp_each >= 1, "exp_each=%d" % exp_each)
	# 把 0 号角色经验顶到 threshold-1，一次固定结算即跨阈值升级
	st.party[0]["exp"] = threshold - 1
	var before_level: int = int(st.party[0].get("level", 1))
	var before_tp: int = int(st.party[0].get("talent_points", 0))
	var before_total_tp: int = st.talent_points

	rm.on_battle_resolved("victory")  # stage 1：仅固定结算

	_check("[3] 强制升级：0 号角色 level +1",
		int(st.party[0].get("level", 1)) == before_level + 1,
		"level=%d" % int(st.party[0].get("level", 1)))
	_check("[3] 强制升级：0 号角色 talent_points +1",
		int(st.party[0].get("talent_points", 0)) == before_tp + 1,
		"tp=%d" % int(st.party[0].get("talent_points", 0)))
	_check("[3] 强制升级：state 顶层 talent_points 合计 +1",
		st.talent_points == before_total_tp + 1, "total_tp=%d" % st.talent_points)
	_check("[3] 强制升级：exp 扣除一个阈值（余 exp_each-1）",
		int(st.party[0].get("exp", 0)) == exp_each - 1,
		"exp=%d 期望 %d" % [int(st.party[0].get("exp", 0)), exp_each - 1])


# ── 测试 3d：多级跳升（while 循环处理一次跨多级）────────

func _test_multi_level_up() -> void:
	var rm: Object = _new_manager()
	rm.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), _rng)
	var st: Object = rm.get_state()
	var t1: int = _exp_threshold_cfg(1)
	var t2: int = _exp_threshold_cfg(2)
	var exp_each: int = _fixed_exp()
	# 设 0 号角色 exp 使一次固定结算恰好跨两级：(exp + exp_each) == t1 + t2
	var seed_exp: int = t1 + t2 - exp_each
	_check("[3d] 前置：seed_exp >= 0（占位阈值合理）", seed_exp >= 0,
		"seed_exp=%d (t1=%d t2=%d exp_each=%d)" % [seed_exp, t1, t2, exp_each])
	st.party[0]["exp"] = seed_exp
	var before_level: int = int(st.party[0].get("level", 1))
	var before_tp: int = int(st.party[0].get("talent_points", 0))
	rm.on_battle_resolved("victory")  # stage 1：仅固定结算
	_check("[3d] 多级跳升：level +2（证明 while 非 if）",
		int(st.party[0].get("level", 1)) == before_level + 2,
		"level=%d 期望 %d" % [int(st.party[0].get("level", 1)), before_level + 2])
	_check("[3d] 多级跳升：talent_points +2",
		int(st.party[0].get("talent_points", 0)) == before_tp + 2,
		"tp=%d" % int(st.party[0].get("talent_points", 0)))
	_check("[3d] 多级跳升：exp 扣两个阈值后余 0",
		int(st.party[0].get("exp", 0)) == 0,
		"exp=%d" % int(st.party[0].get("exp", 0)))


# ── 测试 3e：gold 单发未按人数放大 ────────────────────

func _test_gold_not_scaled() -> void:
	var rm: Object = _new_manager()
	rm.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), _rng)
	var st: Object = rm.get_state()
	var dg: Dictionary = _act_config.get("door_gen", {})
	var fr: Dictionary = dg.get("fixed_reward_per_stage", {})
	var fixed_gold: int = int(fr.get("gold", 0))
	var n: int = st.party.size()
	rm.on_battle_resolved("victory")  # stage 1：仅固定结算（current_entry_door=null，无门奖励）
	_check("[3e] gold 单发未按人数放大（==固定 gold，非 ×party）",
		st.gold == fixed_gold,
		"gold=%d 期望 %d（人数 %d，若×人数会是 %d）" % [st.gold, fixed_gold, n, fixed_gold * n])


# ── 测试 8b：phase 守卫防重复结算 ─────────────────────

func _test_phase_guard() -> void:
	var rm: Object = _new_manager()
	rm.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), _rng)
	var st: Object = rm.get_state()
	rm.on_battle_resolved("victory")  # stage 1 → phase 变为 door_select
	var gold_after_first: int = st.gold
	var phase_now: String = str(st.phase)
	_check("[8] 前置：首次结算后处于非 battle 阶段", phase_now != "battle",
		"phase=%s" % phase_now)
	# 在非 battle 阶段（door_select）再次误调 on_battle_resolved，应被守卫拦截、不重复结算
	rm.on_battle_resolved("victory")
	_check("[8] phase 守卫：非 battle 阶段误调不重复结算（gold 不变）",
		st.gold == gold_after_first,
		"gold %d→%d" % [gold_after_first, st.gold])
	_check("[8] phase 守卫：非 battle 阶段误调不改 phase",
		str(st.phase) == phase_now, "phase %s→%s" % [phase_now, str(st.phase)])


# ── 测试 4：每角色独立掉落 ────────────────────────────

func _test_per_char_drops() -> void:
	var rm: Object = _new_manager()
	rm.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), _rng)
	var st: Object = rm.get_state()
	var resolver: Object = RewardResolverScript.new()
	var n: int = st.party.size()

	# relic 门：每角色各得 1 遗物
	var before_relics: int = _total_relics(st)
	var rsum: Dictionary = resolver.settle_door_reward(st, "relic", false, _pools, _rng, _act_config)
	var rdrops: Array = rsum.get("drops", [])
	_check("[4] relic 门掉落数 == 角色数(%d)" % n, rdrops.size() == n, "实际 %d" % rdrops.size())
	_check("[4] relic 门：遗物总数增加 == 角色数", _total_relics(st) - before_relics == n,
		"增 %d" % (_total_relics(st) - before_relics))
	var relic_idxs: Dictionary = {}
	for d_v: Variant in rdrops:
		relic_idxs[int((d_v as Dictionary).get("char_index", -1))] = true
	_check("[4] relic 门：每个角色 index 都有掉落", relic_idxs.size() == n,
		"覆盖 %d" % relic_idxs.size())

	# equipment 门：每角色各得装备（v0 先入 convoy）
	var before_convoy_eq: int = (st.convoy.get("equipment", []) as Array).size()
	var esum: Dictionary = resolver.settle_door_reward(st, "equipment", false, _pools, _rng, _act_config)
	var edrops: Array = esum.get("drops", [])
	_check("[4] equipment 门掉落数 == 角色数(%d)" % n, edrops.size() == n,
		"实际 %d" % edrops.size())
	_check("[4] equipment 门：convoy.equipment 增加 == 角色数",
		(st.convoy.get("equipment", []) as Array).size() - before_convoy_eq == n,
		"增 %d" % ((st.convoy.get("equipment", []) as Array).size() - before_convoy_eq))


# ── 测试 5：relic_drought 按出现跨关传递 ──────────────

func _test_relic_drought_appearance() -> void:
	var rm: Object = _new_manager()
	rm.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), _rng)
	var prev_drought: int = 0
	var violations: int = 0
	var reset_despite_nonrelic: bool = false
	var guard: int = 0

	while not rm.is_run_complete() and not rm.is_run_failed() and guard < 40:
		guard += 1
		rm.on_battle_resolved("victory")
		if rm.is_run_complete():
			break
		var st: Object = rm.get_state()
		if st.phase == "door_select":
			var pd: Array = st.pending_doors
			var has_relic: bool = _doors_have_relic(pd)
			var expected: int = 0 if has_relic else prev_drought + 1
			if st.relic_drought != expected:
				violations += 1
			prev_drought = st.relic_drought
			# 若组内出现 relic，则挑一扇「非 relic」门推进，验证 drought 仍归零
			var idx: int = -1
			if has_relic:
				for i: int in range(pd.size()):
					if str((pd[i] as Dictionary).get("reward_type", "")) != "relic":
						idx = i
						break
				if idx >= 0 and st.relic_drought == 0:
					reset_despite_nonrelic = true
			if idx < 0:
				idx = 0
			rm.choose_door(idx)
			rm.confirm_departure()
		elif st.phase == "prep":
			rm.confirm_departure()

	_check("[5] relic_drought 按出现语义跨关传递零违反", violations == 0,
		"违反 %d 次" % violations)
	_check("[5] 至少一次：组内出现 relic 但玩家选非 relic → drought 仍归零（按出现≠按选中）",
		reset_despite_nonrelic)


# ── 测试 6：失败路径 ─────────────────────────────────

func _test_failure() -> void:
	var rm: Object = _new_manager()
	rm.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), _rng)
	rm.on_battle_resolved("defeat")
	_check("[6] defeat → is_run_failed()", rm.is_run_failed())
	_check("[6] defeat → phase==failed", rm.get_state().phase == "failed",
		"phase=%s" % rm.get_state().phase)
	_check("[6] run_failed 信号已发", _failed)
	_check("[6] 失败后 run 未标记完成", not rm.is_run_complete())


# ── 测试 7：边界 ─────────────────────────────────────

func _test_boundaries() -> void:
	var rm: Object = _new_manager()
	rm.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), _rng)
	var st: Object = rm.get_state()
	var resolver: Object = RewardResolverScript.new()

	# a. relic 6 槽上限：0 号角色塞满 6 个 → 掉落溢出 convoy
	st.party[0]["relics"] = ["r1", "r2", "r3", "r4", "r5", "r6"]
	var before_convoy_relics: int = (st.convoy.get("relics", []) as Array).size()
	var rsum: Dictionary = resolver.settle_door_reward(st, "relic", false, _pools, _rng, _act_config)
	_check("[7] 满槽角色遗物槽仍为 6（不超上限）",
		(st.party[0].get("relics") as Array).size() == 6,
		"实际 %d" % (st.party[0].get("relics") as Array).size())
	var char0_to_convoy: bool = false
	for d_v: Variant in rsum.get("drops", []):
		var d: Dictionary = d_v
		if int(d.get("char_index", -1)) == 0:
			char0_to_convoy = bool(d.get("to_convoy", false))
	_check("[7] 满槽角色掉落 to_convoy==true", char0_to_convoy)
	_check("[7] convoy.relics 因溢出增加",
		(st.convoy.get("relics", []) as Array).size() > before_convoy_relics,
		"前 %d 后 %d" % [before_convoy_relics, (st.convoy.get("relics", []) as Array).size()])
	# 未满槽角色（1 号）应正常入槽
	_check("[7] 未满槽角色遗物入槽（1 号 relics 非空）",
		(st.party[1].get("relics") as Array).size() >= 1,
		"实际 %d" % (st.party[1].get("relics") as Array).size())

	# b. Boss 固定包品质字段存在
	var rm2: Object = _new_manager()
	rm2.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), _rng)
	var st2: Object = rm2.get_state()
	var boss_reward: Dictionary = _boss_reward()
	_check("[7] boss.reward 可读为 Dictionary", not boss_reward.is_empty())
	var bsum: Dictionary = resolver.settle_boss_package(st2, boss_reward, _pools, _rng, _act_config)
	var bdrops: Array = bsum.get("drops", [])
	_check("[7] Boss 固定包 drops 非空", not bdrops.is_empty(), "drops=%d" % bdrops.size())
	var all_have_rarity: bool = true
	for d_v2: Variant in bdrops:
		if not (d_v2 as Dictionary).has("rarity"):
			all_have_rarity = false
	_check("[7] Boss 固定包每个 drop 含 rarity 字段", all_have_rarity)
	var bkinds: Array = bsum.get("package_kinds", [])
	_check("[7] Boss 固定包 kinds 含 equipment 与 relic",
		bkinds.has("equipment") and bkinds.has("relic"), str(bkinds))


# ── 统计打印 ─────────────────────────────────────────

func _print_stats() -> void:
	print("\n[整轮 run 统计（固定种子 %d）]" % RNG_SEED)
	print("  最终 gold（共享账本）：%d" % _flow_gold)
	print("  各角色等级：%s" % str(_flow_levels))
	print("  门/Boss 掉落总数（equipment+relic）：%d" % _flow_drops)


# ── 工具 ─────────────────────────────────────────────

func _new_manager() -> Object:
	_summaries = []
	_doors_events = []
	_stage_events = []
	_completed = false
	_failed = false
	var rm: Object = RunManagerScript.new()
	rm.reward_settled.connect(_on_reward_settled)
	rm.doors_generated.connect(_on_doors_generated)
	rm.stage_advanced.connect(_on_stage_advanced)
	rm.run_completed.connect(_on_run_completed)
	rm.run_failed.connect(_on_run_failed)
	return rm


func _on_reward_settled(summary: Dictionary) -> void:
	_summaries.append(summary)


func _on_doors_generated(doors: Array) -> void:
	_doors_events.append(doors)


func _on_stage_advanced(stage: int) -> void:
	_stage_events.append(stage)


func _on_run_completed() -> void:
	_completed = true


func _on_run_failed() -> void:
	_failed = true


## 门选择偏好：优先 relic，其次 equipment/gold/exp（保证选非事件门，结算路径确定）。
func _choose_index(doors: Array) -> int:
	var priority: Array[String] = ["relic", "equipment", "gold", "exp"]
	for want: String in priority:
		for i: int in range(doors.size()):
			if str((doors[i] as Dictionary).get("reward_type", "")) == want:
				return i
	return 0


func _doors_have_relic(doors: Array) -> bool:
	for door_v: Variant in doors:
		if str((door_v as Dictionary).get("reward_type", "")) == "relic":
			return true
	return false


func _total_relics(st: Object) -> int:
	var total: int = 0
	for member: Dictionary in st.party:
		total += (member.get("relics", []) as Array).size()
	total += (st.convoy.get("relics", []) as Array).size()
	return total


## 与 RewardResolver._exp_threshold 等价的独立实现（交叉校验，读同一配置）。
func _exp_threshold_cfg(level: int) -> int:
	var prog_v: Variant = _act_config.get("progression")
	var prog: Dictionary = prog_v if prog_v is Dictionary else {}
	var base: int = int(prog.get("exp_threshold_base", 100))
	var growth: float = float(prog.get("exp_threshold_growth", 1.0))
	var lv: int = level if level >= 1 else 1
	return int(round(float(base) * pow(growth, float(lv - 1))))


func _fixed_exp() -> int:
	var dg_v: Variant = _act_config.get("door_gen")
	if dg_v is Dictionary:
		var fr_v: Variant = (dg_v as Dictionary).get("fixed_reward_per_stage")
		if fr_v is Dictionary:
			return int((fr_v as Dictionary).get("exp", 0))
	return 0


func _boss_reward() -> Dictionary:
	var b_v: Variant = _act_config.get("boss")
	if b_v is Dictionary:
		var r_v: Variant = (b_v as Dictionary).get("reward")
		if r_v is Dictionary:
			return r_v
	return {}


func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	return JSON.parse_string(text)


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  OK  " + name)
	else:
		_fail += 1
		_fails.append(name + ("  [" + detail + "]" if detail != "" else ""))
		print("  XX  " + name + ("  [" + detail + "]" if detail != "" else ""))


func _finish() -> void:
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  XX " + f)
	else:
		print("OK：全部断言通过")
	quit(0 if _fail == 0 else 1)
