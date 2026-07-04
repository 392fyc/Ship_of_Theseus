extends SceneTree
## v0 门循环综合端到端集成测试 —— 2026-07-04
##
## 目的：把各子系统单测（test_run_scene_flow 门循环+装配 / test_prep_flow 恢复+HP继承 /
## test_shop_flow 商店）未覆盖的「协同链路」串成一整幕（RunManager + BattleAssembler
## + 固定种子驱动，不实例化真 UI / 真战斗），验证子系统交界处贯通：
##   磨损 → writeback → 恢复 → 跨关继承 → 装配 → 结算（gold/exp/升级）→ 门选 →
##   商店 → Boss 固定包 → 通关；另测事件门推进与失败路径。
##
## 覆盖（编号对应任务清单）：
##   1. start_run：party 4 人满血。
##   2. 逐关装配 + 磨损写回链（含精英词条透传）。
##   3. 结算：gold 单调不减 + 每角色 exp 累积 + 一次必然升级 level++/talent_points++。
##   4. 门选择 + 恢复链（恢复量恒定、clamp、磨损角色 hp 提升）。
##   5. HP 跨关继承（磨损→恢复→下一关 BattleAssembler 带该 hp）。
##   6. 事件门推进（不装配战斗、不 soft-lock）。
##   7. 商店 Prep（stage4 是商店、buy 扣减+入 convoy；抽查 stage2/3 非商店）。
##   8. Boss + 通关（Boss 固定包 gold 增 + equipment/relic 掉落 + run_completed，最终 stage8）。
##   9. 失败路径（defeat → run_failed）。
##
## 坑规避（headless --script 三大坑）：逻辑放 _process 首帧；只 preload 不引全局 class_name；
## DataLoader 手动 load_all()。本文件独立，不影响既有三份单测。
##
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/test_v0_integration.gd
## 退出码 0=全过，1=有失败。

const ACT_CONFIG_FILE: String = "res://data/runloop/act1_config.json"
const RUN_CONFIG_FILE: String = "res://data/runloop/run_config.json"
const DATA_LOADER_SCRIPT: String = "res://scripts/data/data_loader.gd"

const RunManagerScript: GDScript = preload("res://scripts/roguelite/run_manager.gd")
const BattleAssemblerScript: GDScript = preload("res://scripts/roguelite/battle_assembler.gd")

const RNG_SEED: int = 20260704

# 确定性精英装配对照（与 test_run_scene_flow 一致：afs_bulwark / stat_scale 1.35）。
const ELITE_MAP: String = "forest_01"
const ELITE_WAVE: String = "wave_act1_elite_01"
const ELITE_SPECIAL: String = "afs_bulwark"
const ELITE_SCALE: float = 1.35

# party 下标（roster 顺序固定）。
const IDX_SWORDSMAN: int = 0
const IDX_SOLDIER: int = 1
const IDX_ARCHER: int = 2
const IDX_CLERIC: int = 3

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

# 主幕运行时收集
var _summaries: Array = []
var _completed: bool = false
var _failed: bool = false
var _expected_soldier_hp_stage2: int = -1  # 磨损→恢复后 soldier 的 hp（供 stage2 继承断言）


func _initialize() -> void:
	print("=== test_v0_integration (v0 门循环综合端到端集成) ===")


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

	_test_full_act_integration()   # 1/2/3(gold+exp)/4/5/7/8
	_test_forced_levelup()         # 3(升级)
	_test_event_door_advance()     # 6
	_test_elite_transfer_det()     # 2(精英透传，确定性保底)
	_test_failure_path()           # 9

	_finish()


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
	_check("run_config.recovery 存在", _run_config.get("recovery") is Dictionary)

	var dl: Object = load(DATA_LOADER_SCRIPT).new()
	dl.load_all()
	_pools = {
		"maps": dl.maps,
		"waves": dl.waves,
		"affixes": dl.affixes,
		"relics": dl.relics,
		"equipment": dl.equipment,
		"events": dl.events,
	}
	_check("data_pools.maps 非空", not (dl.maps as Dictionary).is_empty())
	_check("data_pools.waves 非空", not (dl.waves as Dictionary).is_empty())
	_check("data_pools.equipment 非空", not (dl.equipment as Dictionary).is_empty())
	_check("data_pools.relics 非空", not (dl.relics as Dictionary).is_empty())

	# 4 人队伍（带 max_hp 真值，便于测磨损/恢复/继承）。顺序＝上方 IDX_* 常量。
	_roster = [
		{ "class_id": "swordsman", "level": 1, "max_hp": 30 },
		{ "class_id": "soldier", "level": 1, "max_hp": 40 },
		{ "class_id": "archer", "level": 1, "max_hp": 26 },
		{ "class_id": "cleric", "level": 1, "max_hp": 24 },
	]
	return _fail == 0


# ── 主幕集成：磨损→写回→恢复→继承→装配→结算→门→商店→Boss→通关 ──

func _test_full_act_integration() -> void:
	_summaries = []
	_completed = false
	_failed = false
	_expected_soldier_hp_stage2 = -1
	_rng.seed = RNG_SEED

	var rm: Object = RunManagerScript.new()
	rm.reward_settled.connect(_on_reward_settled)
	rm.run_completed.connect(_on_run_completed)
	rm.run_failed.connect(_on_run_failed)
	rm.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), _rng)

	# [1] start_run：party 4 人满血
	var st0: Object = rm.get_state()
	_check("[1] start_run: stage==1", st0.stage == 1, "stage=%d" % st0.stage)
	_check("[1] start_run: phase==battle", st0.phase == "battle", "phase=%s" % st0.phase)
	_check("[1] start_run: party 恰 4 人", st0.party.size() == 4, "size=%d" % st0.party.size())
	var all_full: bool = true
	var ids_ok: bool = true
	var expect_ids: Array[String] = ["swordsman", "soldier", "archer", "cleric"]
	for i: int in range(st0.party.size()):
		var m: Dictionary = st0.party[i]
		if int(m.get("hp", -1)) != int(m.get("max_hp", -2)):
			all_full = false
		if i < expect_ids.size() and str(m.get("class_id", "")) != expect_ids[i]:
			ids_ok = false
	_check("[1] start_run: 4 人满血（hp==max_hp）", all_full)
	_check("[1] start_run: class_id 顺序 == [swordsman,soldier,archer,cleric]", ids_ok)

	var base_exp: int = _exp_base()
	var stages_seq: Array[int] = []
	var door_selects: int = 0
	var elite_transfer_seen: bool = false
	var boss_gold_delta: int = -1
	var guard: int = 0

	while not rm.is_run_complete() and not rm.is_run_failed() and guard < 40:
		guard += 1
		var st: Object = rm.get_state()
		var cur: int = st.stage
		stages_seq.append(cur)

		# ── 装配当前关 + 验证（map 一致 / 玩家非空 / 敌人数与波次一致）──
		var assembled: Dictionary = _verify_assembly(cur, st.current_battle, st.party)
		var enemy_units: Array = assembled.get("enemy_units", [])

		# 精英门透传（条件性：本关入口门为精英房时，敌人须带增强/词条）
		if _is_elite_entry(st):
			var has_scale: bool = false
			var has_affix: bool = false
			for e_v: Variant in enemy_units:
				if not (e_v is Dictionary):
					continue
				if absf(float((e_v as Dictionary).get("stat_scale", 1.0)) - 1.0) > 0.001:
					has_scale = true
				if ((e_v as Dictionary).get("affixes", []) as Array).size() >= 1:
					has_affix = true
			_check("[2] stage %d 精英入口：敌人透传增强(stat_scale!=1 或 affixes 非空)" % cur,
				has_scale or has_affix)
			elite_transfer_seen = elite_transfer_seen or has_scale or has_affix

		# ── [5] stage2 继承断言：soldier 带 stage1 恢复后的 hp ──
		if cur == 2 and _expected_soldier_hp_stage2 >= 0:
			var player_units: Array = assembled.get("player_units", [])
			var sol: Dictionary = _find_player(player_units, "soldier")
			_check("[5] stage2 装配含 soldier 单位", not sol.is_empty())
			_check("[5] stage2 soldier 带 hp 字段（磨损后恢复仍<max）", sol.has("hp"))
			_check("[5] stage2 soldier.hp == stage1 恢复后 hp(%d)" % _expected_soldier_hp_stage2,
				int(sol.get("hp", -1)) == _expected_soldier_hp_stage2,
				"hp=%d 期望 %d" % [int(sol.get("hp", -1)), _expected_soldier_hp_stage2])
			# 满血者（swordsman 恢复到满）不带 hp 字段
			var sw: Dictionary = _find_player(player_units, "swordsman")
			_check("[5] stage2 swordsman 满血→不带 hp 字段",
				not sw.is_empty() and not sw.has("hp"))

		# ── [2] stage1 模拟战斗磨损 → writeback（先写回，镜像 RunScene 顺序）──
		if cur == 1:
			var survivors: Array = [
				{ "class_id": "swordsman", "hp": 15, "max_hp": 30 },  # 磨损 15/30
				{ "class_id": "soldier", "hp": 8, "max_hp": 40 },     # 深度磨损 8/40
				{ "class_id": "archer", "hp": 26, "max_hp": 26 },     # 满血 26/26
				# cleric 缺席 → 战死 hp=0
			]
			rm.writeback_party_hp(survivors)
			_check("[2] writeback: swordsman hp 写回磨损值 15",
				int(st.party[IDX_SWORDSMAN].get("hp", -1)) == 15,
				"hp=%d" % int(st.party[IDX_SWORDSMAN].get("hp", -1)))
			_check("[2] writeback: soldier hp 写回磨损值 8",
				int(st.party[IDX_SOLDIER].get("hp", -1)) == 8)
			_check("[2] writeback: archer hp 写回满血 26",
				int(st.party[IDX_ARCHER].get("hp", -1)) == 26)
			_check("[2] writeback: 缺席的 cleric hp=0（战死占位）",
				int(st.party[IDX_CLERIC].get("hp", -1)) == 0,
				"hp=%d" % int(st.party[IDX_CLERIC].get("hp", -1)))

		# ── [3] 结算：gold 单调不减 + exp 累积（cum=(level-1)*base+exp）──
		var g_before: int = int(st.gold)
		var cum_before: int = _cumulative_exp(st.party[IDX_SWORDSMAN], base_exp)
		rm.on_battle_resolved("victory")
		var st_after: Object = rm.get_state()
		_check("[3] stage %d 结算 gold 单调不减" % cur,
			int(st_after.gold) >= g_before, "gold %d→%d" % [g_before, int(st_after.gold)])
		var cum_after: int = _cumulative_exp(st_after.party[IDX_SWORDSMAN], base_exp)
		_check("[3] stage %d 结算 swordsman 累计经验不减" % cur,
			cum_after >= cum_before, "cum %d→%d" % [cum_before, cum_after])

		# ── [8] Boss 关：固定包 gold 增 ──
		if cur == _boss_stage:
			boss_gold_delta = int(st_after.gold) - g_before

		if rm.is_run_complete():
			break

		var ph: String = str(st_after.phase)
		if ph == "door_select":
			door_selects += 1
			var pd: Array = st_after.pending_doors
			_check("[4] stage %d→%d 门数在 [2,3]" % [cur, cur + 1],
				pd.size() >= 2 and pd.size() <= 3, "size=%d" % pd.size())
			var idx: int = _choose_non_event_index(pd)
			rm.choose_door(idx)
			_check("[4] choose_door 后 phase==prep", str(rm.get_state().phase) == "prep")
			_do_prep_actions(rm, cur)   # 此刻 state.stage 仍 == cur
			rm.confirm_departure()
			_check("[4] confirm 后 phase==battle", str(rm.get_state().phase) == "battle")
		elif ph == "prep":
			# Boss 前分支（stage7 打完）：无 door_select，state.stage 仍==7 → 也是商店 Prep
			_check("[8] Boss 前 prep：current_entry_door 为 boss 标记",
				rm.get_state().current_entry_door != null
				and str((rm.get_state().current_entry_door as Dictionary).get("reward_type", "")) == "boss")
			_check("[7] Boss 前 prep（stage%d）→ is_shop_prep()==true" % cur, rm.is_shop_prep())
			rm.confirm_departure()
			_check("[8] Boss 前 confirm 后 phase==battle", str(rm.get_state().phase) == "battle")
		else:
			_check("[4] 意外 phase: %s（stage %d）" % [ph, cur], false)
			break

	# ── 全幕收尾断言 ──
	_check("[2] 逐关装配序列 == [1..8]",
		stages_seq == [1, 2, 3, 4, 5, 6, 7, 8], str(stages_seq))
	_check("[4] 门选择恰 6 次（stage 2..7）", door_selects == 6, "实际 %d" % door_selects)
	_check("[8] run 已完成", rm.is_run_complete())
	_check("[8] run_completed 信号已发", _completed)
	_check("[8] 最终 stage == boss_stage(%d)" % _boss_stage,
		int(rm.get_state().stage) == _boss_stage, "stage=%d" % int(rm.get_state().stage))

	# [8] Boss 固定包：gold 增（>= 配置固定 gold）+ equipment/relic 掉落
	var boss_fixed_gold: int = _boss_fixed_gold()
	_check("[8] Boss 结算 gold 增（delta>=固定 gold %d）" % boss_fixed_gold,
		boss_gold_delta >= boss_fixed_gold, "delta=%d" % boss_gold_delta)
	var boss_sum: Dictionary = _find_summary_with("boss")
	_check("[8] Boss 结算摘要存在（sequence 含 boss）", not boss_sum.is_empty())
	if not boss_sum.is_empty():
		var boss_pkg: Dictionary = boss_sum.get("boss", {}) if boss_sum.get("boss") is Dictionary else {}
		var kinds: Array = boss_pkg.get("package_kinds", [])
		_check("[8] Boss 固定包含 equipment 掉落", kinds.has("equipment"), str(kinds))
		_check("[8] Boss 固定包含 relic 掉落", kinds.has("relic"), str(kinds))
		_check("[8] Boss 固定包 drops 非空",
			(boss_pkg.get("drops", []) as Array).size() > 0,
			"drops=%d" % (boss_pkg.get("drops", []) as Array).size())

	# 主幕全程见过至少一次精英透传（若随机门未掷精英，由确定性子测 _test_elite_transfer_det 兜底）
	if elite_transfer_seen:
		_check("[2] 主幕内精英透传已触发（bonus）", true)


## Prep 阶段动作（state.stage 仍为刚打完的 resolved_stage）。
##   stage1：恢复（磨损角色 hp 提升 + clamp + 恒定），记录 soldier 恢复后 hp 供继承断言。
##   stage2/3：抽查非商店 Prep。
##   stage4（mid_act_after_stage）：商店 Prep + buy 扣减/入 convoy/库存移除。
func _do_prep_actions(rm: Object, resolved_stage: int) -> void:
	var st: Object = rm.get_state()

	if resolved_stage == 1:
		# 恢复量恒定校验（与 stage 无关）
		var a1: int = rm.get_recovery_amount(st.party[IDX_SOLDIER])
		st.stage = 5
		var a2: int = rm.get_recovery_amount(st.party[IDX_SOLDIER])
		st.stage = resolved_stage  # 还原
		_check("[4] 恢复量 run 内恒定（与 stage 无关）", a1 == a2, "a1=%d a2=%d" % [a1, a2])

		var sol_hp_before: int = int(st.party[IDX_SOLDIER].get("hp", 0))
		var sw_hp_before: int = int(st.party[IDX_SWORDSMAN].get("hp", 0))
		var cleric_hp_before: int = int(st.party[IDX_CLERIC].get("hp", 0))
		var sol_amount: int = rm.get_recovery_amount(st.party[IDX_SOLDIER])
		_check("[4] 恢复量 == roundi(max_hp*pct/100)",
			sol_amount == roundi(float(st.party[IDX_SOLDIER].get("max_hp", 0)) * rm.get_recovery_percent() / 100.0))

		rm.recover_party([true, true, true, true])

		# soldier 深度磨损：恢复后仍 < max（继承链的关键样本）
		var sol_max: int = int(st.party[IDX_SOLDIER].get("max_hp", 0))
		var sol_expected: int = mini(sol_max, sol_hp_before + sol_amount)
		_check("[4] soldier 恢复：hp 提升到 min(max, hp+amount)",
			int(st.party[IDX_SOLDIER].get("hp", 0)) == sol_expected,
			"hp=%d 期望 %d" % [int(st.party[IDX_SOLDIER].get("hp", 0)), sol_expected])
		_check("[4] soldier 恢复后 hp 高于恢复前",
			int(st.party[IDX_SOLDIER].get("hp", 0)) > sol_hp_before)
		_check("[4] soldier 恢复后仍 < max（继承样本有效）",
			int(st.party[IDX_SOLDIER].get("hp", 0)) < sol_max)
		_expected_soldier_hp_stage2 = int(st.party[IDX_SOLDIER].get("hp", 0))

		# swordsman 磨损 15/30 + 50% 恢复 → clamp 到满 30
		_check("[4] swordsman 恢复 clamp 到 max_hp（15+15→30）",
			int(st.party[IDX_SWORDSMAN].get("hp", 0)) == int(st.party[IDX_SWORDSMAN].get("max_hp", 0)),
			"hp=%d max=%d 前=%d" % [
				int(st.party[IDX_SWORDSMAN].get("hp", 0)),
				int(st.party[IDX_SWORDSMAN].get("max_hp", 0)), sw_hp_before])
		# cleric hp=0 → 恢复到 amount
		_check("[4] cleric 恢复：hp 从 0 提升",
			int(st.party[IDX_CLERIC].get("hp", 0)) > cleric_hp_before)
		return

	if resolved_stage == 2 or resolved_stage == 3:
		_check("[7] stage%d Prep 非商店（is_shop_prep()==false）" % resolved_stage,
			not rm.is_shop_prep())
		return

	if resolved_stage == _mid_shop_stage():
		_check("[7] stage%d（mid_act_after_stage）Prep → is_shop_prep()==true" % resolved_stage,
			rm.is_shop_prep())
		var stock: Array = rm.get_shop_stock()
		_check("[7] 商店库存非空", not stock.is_empty(), "size=%d" % stock.size())
		if stock.is_empty():
			return
		var item: Dictionary = stock[0]
		var price: int = int(item.get("price", 0))
		var kind: String = str(item.get("kind", ""))
		var ref_id: String = str(item.get("ref_id", ""))
		# 保证 gold 足（precondition，非放宽断言）：不足则补足，测的是买入扣减/入库/移除机制
		if int(st.gold) < price:
			st.gold = price + 50
		var gold_before: int = int(st.gold)
		var convoy_before: int = _convoy_count(st, kind)
		var ok: bool = rm.buy_item(item)
		_check("[7] buy_item 成功", ok)
		_check("[7] gold 扣减 == price",
			int(st.gold) == gold_before - price,
			"gold %d→%d 期望 %d" % [gold_before, int(st.gold), gold_before - price])
		_check("[7] 该件入 convoy（对应库 +1）",
			_convoy_count(st, kind) == convoy_before + 1,
			"前 %d 后 %d" % [convoy_before, _convoy_count(st, kind)])
		_check("[7] 买后库存移除该件（同件不可重复买）",
			not _stock_has(rm.get_shop_stock(), kind, ref_id))


# ── [3] 一次必然升级（喂 exp 到阈值 → 升级）─────────────

func _test_forced_levelup() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = RNG_SEED
	var rm: Object = RunManagerScript.new()
	rm.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), rng)
	var st: Object = rm.get_state()

	var base_exp: int = _exp_base()
	var fixed_exp: int = _fixed_exp()
	_check("[3] 前置：fixed exp(%d) 足以在 exp=base-1 时触发升级" % fixed_exp,
		fixed_exp >= 1)

	# 全员 exp = base-1，一次固定结算(+fixed_exp) 必越阈值升级
	for i: int in range(st.party.size()):
		st.party[i]["exp"] = base_exp - 1
	var lvl_before: int = int(st.party[IDX_SWORDSMAN].get("level", 1))
	var tp_before: int = int(st.party[IDX_SWORDSMAN].get("talent_points", 0))
	var top_tp_before: int = int(st.talent_points)

	rm.on_battle_resolved("victory")

	_check("[3] 升级：swordsman level++（%d→%d）" % [lvl_before, int(st.party[IDX_SWORDSMAN].get("level", 1))],
		int(st.party[IDX_SWORDSMAN].get("level", 1)) == lvl_before + 1,
		"level=%d" % int(st.party[IDX_SWORDSMAN].get("level", 1)))
	_check("[3] 升级：swordsman talent_points++",
		int(st.party[IDX_SWORDSMAN].get("talent_points", 0)) == tp_before + _tp_per_level(),
		"tp=%d" % int(st.party[IDX_SWORDSMAN].get("talent_points", 0)))
	_check("[3] 升级：顶层 talent_points 合计随全队升级累加",
		int(st.talent_points) == top_tp_before + _tp_per_level() * st.party.size(),
		"top=%d 前=%d" % [int(st.talent_points), top_tp_before])


# ── [6] 事件门推进（不装配战斗 + 不 soft-lock）──────────

func _test_event_door_advance() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = RNG_SEED
	var rm: Object = RunManagerScript.new()
	rm.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), rng)
	rm.on_battle_resolved("victory")  # stage1 → 生成 stage2 门组（door_select）
	_check("[6] stage1 后 phase==door_select", str(rm.get_state().phase) == "door_select")

	# 确定性塞入一个事件门（battle=null），绕开随机门生成
	var event_door: Dictionary = {
		"reward_type": "event", "elite_room": false,
		"battle": null, "event_id": "event_blessing_altar",
		"preview": { "icon": "event", "rarity_hint": null, "special_affix": null },
	}
	var doors: Array[Dictionary] = [event_door]
	rm.get_state().pending_doors = doors
	rm.choose_door(0)
	_check("[6] 事件门 choose 后 phase==prep", str(rm.get_state().phase) == "prep")
	rm.confirm_departure()
	var cb: Dictionary = rm.get_state().current_battle
	_check("[6] 事件门 confirm 后 current_battle 无 map（不装配战斗）",
		str(cb.get("map_id", "")) == "", "map=%s" % str(cb.get("map_id", "")))
	_check("[6] 事件门 current_entry_door.reward_type==event",
		str((rm.get_state().current_entry_door as Dictionary).get("reward_type", "")) == "event")
	var gold_before: int = int(rm.get_state().gold)
	rm.on_battle_resolved("victory")
	_check("[6] 事件门 on_battle_resolved(victory) 推进（phase 离开 battle，不 soft-lock）",
		str(rm.get_state().phase) != "battle", "phase=%s" % str(rm.get_state().phase))
	_check("[6] 事件门结算固定金币（gold 增；门奖励按 event 跳过）",
		int(rm.get_state().gold) > gold_before,
		"gold %d→%d" % [gold_before, int(rm.get_state().gold)])


# ── [2] 精英词条透传（确定性保底：装配器把词条送入注入层）──

func _test_elite_transfer_det() -> void:
	var assembled: Dictionary = BattleAssemblerScript.build(
		ELITE_MAP, ELITE_WAVE, _roster.duplicate(true), _pools)
	var enemy_units: Array = assembled.get("enemy_units", [])
	_check("[2] 精英波次装配敌人非空", not enemy_units.is_empty(), "size=%d" % enemy_units.size())

	var has_affix: bool = false
	var has_special: bool = false
	var has_scale: bool = false
	for e_v: Variant in enemy_units:
		if not (e_v is Dictionary):
			continue
		var e: Dictionary = e_v
		if (e.get("affixes", []) as Array).size() >= 1:
			has_affix = true
		if str(e.get("special_affix", "")) == ELITE_SPECIAL:
			has_special = true
		if absf(float(e.get("stat_scale", 1.0)) - ELITE_SCALE) < 0.001:
			has_scale = true
	_check("[2] 精英装配透传基础词条（affixes 非空）", has_affix)
	_check("[2] 精英装配透传 special_affix==%s" % ELITE_SPECIAL, has_special)
	_check("[2] 精英装配透传 stat_scale==%.2f" % ELITE_SCALE, has_scale)


# ── [9] 失败路径 ─────────────────────────────────────

func _test_failure_path() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = RNG_SEED
	# 复用成员标志（GDScript lambda 按值捕获局部变量，改不到外层 → 用成员方法回调）。
	_failed = false
	_completed = false
	var rm: Object = RunManagerScript.new()
	rm.run_failed.connect(_on_run_failed)
	rm.run_completed.connect(_on_run_completed)
	rm.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), rng)
	rm.on_battle_resolved("defeat")
	_check("[9] defeat → is_run_failed()", rm.is_run_failed())
	_check("[9] defeat → phase==failed", str(rm.get_state().phase) == "failed",
		"phase=%s" % str(rm.get_state().phase))
	_check("[9] run_failed 信号已发", _failed)
	_check("[9] 失败后未标记完成", not rm.is_run_complete() and not _completed)


# ── 信号 ─────────────────────────────────────────────

func _on_reward_settled(summary: Dictionary) -> void:
	_summaries.append(summary)


func _on_run_completed() -> void:
	_completed = true


func _on_run_failed() -> void:
	_failed = true


# ── 装配验证 ─────────────────────────────────────────

## 装配一关战斗并断言（map 一致 / 玩家非空 / 敌人数与波次一致），返回装配结果。
func _verify_assembly(stage: int, battle: Dictionary, party: Array) -> Dictionary:
	var map_id: String = str(battle.get("map_id", ""))
	var wave_id: String = str(battle.get("enemy_config", ""))
	var assembled: Dictionary = BattleAssemblerScript.build(map_id, wave_id, party, _pools)

	_check("[2] stage %d 装配 map_id 与 current_battle 一致" % stage,
		str(assembled.get("map_id", "")) == map_id,
		"assembled=%s battle=%s" % [str(assembled.get("map_id", "")), map_id])
	var player_units: Array = assembled.get("player_units", [])
	_check("[2] stage %d 玩家清单非空（map 有 player_spawns）" % stage,
		not player_units.is_empty(), "map=%s size=%d" % [map_id, player_units.size()])
	var enemy_units: Array = assembled.get("enemy_units", [])
	var waves: Dictionary = _pools.get("waves", {})
	var wave_data: Dictionary = waves.get(wave_id, {})
	var wave_enemies: Array = wave_data.get("enemies", [])
	_check("[2] stage %d 敌人数与波次 %s 一致(%d)" % [stage, wave_id, wave_enemies.size()],
		enemy_units.size() == wave_enemies.size(),
		"装配 %d 波次 %d" % [enemy_units.size(), wave_enemies.size()])
	return assembled


# ── 工具 ─────────────────────────────────────────────

## 当前关入口门是否精英房。
func _is_elite_entry(st: Object) -> bool:
	var door_v: Variant = st.current_entry_door
	return door_v is Dictionary and bool((door_v as Dictionary).get("elite_room", false))


## 累计经验代理（growth=1.0 下精确）：cum = (level-1)*base + exp。
func _cumulative_exp(member: Dictionary, base: int) -> int:
	return (int(member.get("level", 1)) - 1) * base + int(member.get("exp", 0))


func _exp_base() -> int:
	var prog: Dictionary = _act_config.get("progression", {}) if _act_config.get("progression") is Dictionary else {}
	return int(prog.get("exp_threshold_base", 100))


func _tp_per_level() -> int:
	var prog: Dictionary = _act_config.get("progression", {}) if _act_config.get("progression") is Dictionary else {}
	return int(prog.get("talent_point_per_level", 1))


func _fixed_exp() -> int:
	var dg: Dictionary = _act_config.get("door_gen", {}) if _act_config.get("door_gen") is Dictionary else {}
	var fr: Dictionary = dg.get("fixed_reward_per_stage", {}) if dg.get("fixed_reward_per_stage") is Dictionary else {}
	return int(fr.get("exp", 0))


func _boss_fixed_gold() -> int:
	var boss: Dictionary = _act_config.get("boss", {}) if _act_config.get("boss") is Dictionary else {}
	var reward: Dictionary = boss.get("reward", {}) if boss.get("reward") is Dictionary else {}
	var fixed: Dictionary = reward.get("fixed", {}) if reward.get("fixed") is Dictionary else {}
	return int(fixed.get("gold", 0))


func _mid_shop_stage() -> int:
	var dg: Dictionary = _act_config.get("door_gen", {}) if _act_config.get("door_gen") is Dictionary else {}
	var fs: Dictionary = dg.get("fixed_shops", {}) if dg.get("fixed_shops") is Dictionary else {}
	return int(fs.get("mid_act_after_stage", 4))


func _find_summary_with(seq_key: String) -> Dictionary:
	for s_v: Variant in _summaries:
		if not (s_v is Dictionary):
			continue
		var seq: Array = (s_v as Dictionary).get("sequence", [])
		if seq.has(seq_key):
			return s_v
	return {}


func _convoy_count(st: Object, kind: String) -> int:
	var key: String = "equipment" if kind == "equipment" else ("relics" if kind == "relic" else "potions")
	return (st.convoy.get(key, []) as Array).size()


func _stock_has(stock: Array, kind: String, ref_id: String) -> bool:
	for it_v: Variant in stock:
		if it_v is Dictionary and str((it_v as Dictionary).get("kind", "")) == kind \
				and str((it_v as Dictionary).get("ref_id", "")) == ref_id:
			return true
	return false


func _choose_non_event_index(doors: Array) -> int:
	for i: int in range(doors.size()):
		if str((doors[i] as Dictionary).get("reward_type", "")) != "event":
			return i
	return 0


func _find_player(player_units: Array, class_id: String) -> Dictionary:
	for pu_v: Variant in player_units:
		if pu_v is Dictionary and str((pu_v as Dictionary).get("class_id", "")) == class_id:
			return pu_v
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
