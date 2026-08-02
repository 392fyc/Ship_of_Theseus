extends SceneTree
## 事件效果执行器 v0 headless 回归测试 —— 2026-07-04（迭代 #12）
##
## 覆盖 scripts/roguelite/run_manager.gd 新增的事件执行器（apply_event_outcome /
## pick_event_outcome）+ run_state.gd 的 run_buffs 字段：
##   1. 三事件加载：event_mysterious_merchant / event_abandoned_mine /
##      event_blessing_altar 从 DataLoader.events 可读，结构完整（choices/outcomes/effects）。
##   2. apply_event_outcome 各 effect：gold 增 / gold 减 clamp0 / hp_cost 每角色扣血 clamp1 /
##      none 无变化 / start_battle 返回 battle_triggered+enemy_config / buff 占位记 run_buffs /
##      item 占位不崩；每 effect 记一条 log。
##   3. pick_event_outcome：单 outcome 直接返回；空 outcomes → {}；多 outcome 按 weight
##      加权（固定种子大样本，分布贴近 50/30/20 权重）。
##   4. 伏击 enemy_config==wave_event_mine_ambush 存在于 DataLoader.waves。
##
## 坑规避（--script 三大坑）：断言放 _process 首帧；只用 preload（不引全局 class_name）；
## DataLoader 手动 load_all()。
##
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/test_event_resolver.gd
## 退出码 0=全过，1=有失败。

const ACT_CONFIG_FILE: String = "res://data/runloop/act1_config.json"
const RUN_CONFIG_FILE: String = "res://data/runloop/run_config.json"
const DATA_LOADER_SCRIPT: String = "res://scripts/data/data_loader.gd"

const RunManagerScript: GDScript = preload("res://scripts/roguelite/run_manager.gd")

const RNG_SEED: int = 20260704
const AMBUSH_WAVE: String = "wave_event_mine_ambush"
const EVENT_IDS: Array[String] = [
	"event_mysterious_merchant", "event_abandoned_mine", "event_blessing_altar",
]

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _act_config: Dictionary = {}
var _run_config: Dictionary = {}
var _pools: Dictionary = {}
var _roster: Array = []


func _initialize() -> void:
	print("=== test_event_resolver (事件效果执行器 v0) ===")


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

	_test_events_loaded()
	_test_effect_gold()
	_test_effect_gold_clamp_zero()
	_test_effect_hp_cost()
	_test_effect_none()
	_test_effect_start_battle()
	_test_effect_buff_placeholder()
	_test_effect_item_placeholder()
	_test_effect_multi_and_unknown()
	_test_pick_single_and_empty()
	_test_pick_weighted_distribution()
	_test_ambush_wave_exists()
	_test_real_event_outcome()

	_finish()


# ── 环境加载 ─────────────────────────────────────────

func _load_env() -> bool:
	var act_v: Variant = _load_json(ACT_CONFIG_FILE)
	_check("act1_config.json 可解析为 Dictionary", act_v is Dictionary)
	if not (act_v is Dictionary):
		return false
	_act_config = act_v

	var run_v: Variant = _load_json(RUN_CONFIG_FILE)
	_check("run_config.json 可解析为 Dictionary", run_v is Dictionary)
	if not (run_v is Dictionary):
		return false
	_run_config = run_v

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
	_check("data_pools.events 非空", not (dl.events as Dictionary).is_empty())
	_check("data_pools.waves 非空", not (dl.waves as Dictionary).is_empty())

	_roster = [
		{ "class_id": "kensei", "level": 1, "max_hp": 30 },
		{ "class_id": "knight", "level": 1, "max_hp": 34 },
		{ "class_id": "archer", "level": 1, "max_hp": 26 },
	]
	return _fail == 0


# ── 测试 1：三事件加载与结构 ──────────────────────────

func _test_events_loaded() -> void:
	var events: Dictionary = _pools.get("events", {})
	for eid: String in EVENT_IDS:
		_check("[1] 事件已加载：%s" % eid, events.has(eid))
		var ev_v: Variant = events.get(eid)
		if not (ev_v is Dictionary):
			_check("[1] %s 为 Dictionary" % eid, false)
			continue
		var ev: Dictionary = ev_v
		_check("[1] %s 有 title" % eid, str(ev.get("title", "")) != "")
		_check("[1] %s 有 description" % eid, str(ev.get("description", "")) != "")
		var choices: Array = ev.get("choices", []) if ev.get("choices") is Array else []
		_check("[1] %s choices 非空" % eid, not choices.is_empty(), "size=%d" % choices.size())
		# 每个 choice 至少一个 outcome，每个 outcome 有 effects 数组
		var structure_ok: bool = true
		for c_v: Variant in choices:
			if not (c_v is Dictionary):
				structure_ok = false
				continue
			var outs: Array = (c_v as Dictionary).get("outcomes", []) if (c_v as Dictionary).get("outcomes") is Array else []
			if outs.is_empty():
				structure_ok = false
			for o_v: Variant in outs:
				if not (o_v is Dictionary) or not ((o_v as Dictionary).get("effects") is Array):
					structure_ok = false
		_check("[1] %s 每 choice≥1 outcome 且 outcome 含 effects 数组" % eid, structure_ok)


# ── 测试 2a：gold 增 ─────────────────────────────────

func _test_effect_gold() -> void:
	var rm: Object = _fresh_manager()
	var st: Object = rm.get_state()
	st.gold = 100
	var result: Dictionary = rm.apply_event_outcome(_outcome([{ "type": "gold", "amount": 80 }]))
	_check("[2a] gold +80：100 → 180", int(st.gold) == 180, "gold=%d" % int(st.gold))
	_check("[2a] gold effect 记一条 log", (result.get("logs", []) as Array).size() == 1,
		"logs=%d" % (result.get("logs", []) as Array).size())
	_check("[2a] gold 未触发战斗", not bool(result.get("battle_triggered", false)))


# ── 测试 2b：gold 减 clamp 0 ─────────────────────────

func _test_effect_gold_clamp_zero() -> void:
	var rm: Object = _fresh_manager()
	var st: Object = rm.get_state()
	st.gold = 50
	rm.apply_event_outcome(_outcome([{ "type": "gold", "amount": -120 }]))
	_check("[2b] gold -120（余额 50 不足）→ clamp 0（不为负）", int(st.gold) == 0,
		"gold=%d" % int(st.gold))
	# 正常足额扣款
	st.gold = 200
	rm.apply_event_outcome(_outcome([{ "type": "gold", "amount": -120 }]))
	_check("[2b] gold -120（余额 200 足）→ 80", int(st.gold) == 80, "gold=%d" % int(st.gold))


# ── 测试 2c：hp_cost_percent 每角色扣血 clamp1 ────────

func _test_effect_hp_cost() -> void:
	var rm: Object = _fresh_manager()
	var st: Object = rm.get_state()
	# 造已知 hp/max_hp：满血 20/20、残血 3/20、极低 1/10
	st.party[0]["max_hp"] = 20
	st.party[0]["hp"] = 20
	st.party[1]["max_hp"] = 20
	st.party[1]["hp"] = 3
	st.party[2]["max_hp"] = 10
	st.party[2]["hp"] = 1
	var result: Dictionary = rm.apply_event_outcome(
		_outcome([{ "type": "hp_cost_percent", "amount": 20 }]))
	# cost = roundi(max_hp * 20 / 100)：20→4、10→2
	_check("[2c] 满血角色 20-4=16", int(st.party[0].get("hp", -1)) == 16,
		"hp=%d" % int(st.party[0].get("hp", -1)))
	_check("[2c] 残血角色 3-4 → clamp 1（不低于 1）", int(st.party[1].get("hp", -1)) == 1,
		"hp=%d" % int(st.party[1].get("hp", -1)))
	_check("[2c] 低血角色 1-2 → clamp 1", int(st.party[2].get("hp", -1)) == 1,
		"hp=%d" % int(st.party[2].get("hp", -1)))
	_check("[2c] hp_cost effect 记一条 log", (result.get("logs", []) as Array).size() == 1)
	# max_hp<=0（占位未回填）跳过不崩
	var rm2: Object = _fresh_manager()
	var st2: Object = rm2.get_state()
	st2.party[0]["max_hp"] = 0
	st2.party[0]["hp"] = 0
	rm2.apply_event_outcome(_outcome([{ "type": "hp_cost_percent", "amount": 20 }]))
	_check("[2c] max_hp<=0 角色跳过（hp 仍 0，不崩不变负）", int(st2.party[0].get("hp", -1)) == 0,
		"hp=%d" % int(st2.party[0].get("hp", -1)))


# ── 测试 2d：none 无变化 ─────────────────────────────

func _test_effect_none() -> void:
	var rm: Object = _fresh_manager()
	var st: Object = rm.get_state()
	st.gold = 123
	var hp0: int = int(st.party[0].get("hp", 0))
	var result: Dictionary = rm.apply_event_outcome(_outcome([{ "type": "none" }]))
	_check("[2d] none：gold 不变", int(st.gold) == 123, "gold=%d" % int(st.gold))
	_check("[2d] none：hp 不变", int(st.party[0].get("hp", 0)) == hp0)
	_check("[2d] none：不触发战斗", not bool(result.get("battle_triggered", false)))
	_check("[2d] none 记一条 log", (result.get("logs", []) as Array).size() == 1)


# ── 测试 2e：start_battle 返回 battle_triggered + enemy_config ──

func _test_effect_start_battle() -> void:
	var rm: Object = _fresh_manager()
	var st: Object = rm.get_state()
	var gold_before: int = int(st.gold)
	var result: Dictionary = rm.apply_event_outcome(
		_outcome([{ "type": "start_battle", "enemy_config": AMBUSH_WAVE }]))
	_check("[2e] start_battle：battle_triggered==true", bool(result.get("battle_triggered", false)))
	_check("[2e] start_battle：enemy_config 透传", str(result.get("enemy_config", "")) == AMBUSH_WAVE,
		"enemy_config=%s" % str(result.get("enemy_config", "")))
	_check("[2e] start_battle：不动 gold（战斗单独装配）", int(st.gold) == gold_before)


# ── 测试 2f：buff 占位记 run_buffs 不崩 ───────────────

func _test_effect_buff_placeholder() -> void:
	var rm: Object = _fresh_manager()
	var st: Object = rm.get_state()
	_check("[2f] 前置：run_buffs 初始为空", (st.run_buffs as Array).is_empty())
	rm.apply_event_outcome(_outcome([{ "type": "buff", "ref_id": "buff_altar_might_placeholder", "duration": "run" }]))
	_check("[2f] buff 占位：run_buffs 记入一条", (st.run_buffs as Array).size() == 1,
		"size=%d" % (st.run_buffs as Array).size())
	_check("[2f] buff 占位：记入的是 ref_id",
		(st.run_buffs as Array).size() == 1 and str((st.run_buffs as Array)[0]) == "buff_altar_might_placeholder")


# ── 测试 2g：item 占位不崩 ───────────────────────────

func _test_effect_item_placeholder() -> void:
	var rm: Object = _fresh_manager()
	var st: Object = rm.get_state()
	st.gold = 77
	var convoy_eq_before: int = (st.convoy.get("equipment", []) as Array).size()
	var result: Dictionary = rm.apply_event_outcome(
		_outcome([{ "type": "item", "ref_id": "equipment_merchant_rare_placeholder" }]))
	_check("[2g] item 占位：不改 gold", int(st.gold) == 77, "gold=%d" % int(st.gold))
	_check("[2g] item 占位：不真实入运输队（占位未发放）",
		(st.convoy.get("equipment", []) as Array).size() == convoy_eq_before)
	_check("[2g] item 占位：记一条 log", (result.get("logs", []) as Array).size() == 1)


# ── 测试 2h：多 effect 组合 + 未知 type 跳过 ──────────

func _test_effect_multi_and_unknown() -> void:
	var rm: Object = _fresh_manager()
	var st: Object = rm.get_state()
	st.gold = 100
	# gold -120（clamp 会到 0，再... 顺序应用）+ item + 未知 type
	var result: Dictionary = rm.apply_event_outcome(_outcome([
		{ "type": "gold", "amount": -80 },
		{ "type": "item", "ref_id": "potion_mine_cache_placeholder" },
		{ "type": "definitely_unknown_type" },
	]))
	_check("[2h] 多 effect：gold 100-80=20", int(st.gold) == 20, "gold=%d" % int(st.gold))
	_check("[2h] 多 effect：3 effect 记 3 条 log", (result.get("logs", []) as Array).size() == 3,
		"logs=%d" % (result.get("logs", []) as Array).size())
	_check("[2h] 未知 type 不崩（正常返回结果）", result.has("battle_triggered"))


# ── 测试 3a：pick 单 outcome / 空 ─────────────────────

func _test_pick_single_and_empty() -> void:
	var rm: Object = _fresh_manager()
	# 单 outcome 直接返回
	var single: Dictionary = {
		"outcomes": [{ "weight": 1, "effects": [{ "type": "gold", "amount": 10 }], "_tag": "solo" }],
	}
	var picked: Dictionary = rm.pick_event_outcome(single, _rng)
	_check("[3a] 单 outcome 直接返回（_tag==solo）", str(picked.get("_tag", "")) == "solo")
	# 空 outcomes → {}
	var empty_choice: Dictionary = { "outcomes": [] }
	var picked_empty: Dictionary = rm.pick_event_outcome(empty_choice, _rng)
	_check("[3a] 空 outcomes → 返回 {}", picked_empty.is_empty())
	# 缺 outcomes 键 → {}
	var no_key: Dictionary = { "text": "x" }
	_check("[3a] 缺 outcomes 键 → 返回 {}", rm.pick_event_outcome(no_key, _rng).is_empty())


# ── 测试 3b：pick 加权分布（固定种子大样本贴近权重）──

func _test_pick_weighted_distribution() -> void:
	var rm: Object = _fresh_manager()
	var choice: Dictionary = {
		"outcomes": [
			{ "weight": 50, "effects": [{ "type": "none" }], "_tag": "a" },
			{ "weight": 30, "effects": [{ "type": "none" }], "_tag": "b" },
			{ "weight": 20, "effects": [{ "type": "none" }], "_tag": "c" },
		],
	}
	var drng: RandomNumberGenerator = RandomNumberGenerator.new()
	drng.seed = RNG_SEED
	var n: int = 6000
	var counts: Dictionary = { "a": 0, "b": 0, "c": 0 }
	for _i: int in range(n):
		var picked: Dictionary = rm.pick_event_outcome(choice, drng)
		var tag: String = str(picked.get("_tag", ""))
		if counts.has(tag):
			counts[tag] = int(counts[tag]) + 1
	var pa: float = float(counts["a"]) / float(n)
	var pb: float = float(counts["b"]) / float(n)
	var pc: float = float(counts["c"]) / float(n)
	# 总权重 100 → 期望 0.5 / 0.3 / 0.2；容差 0.05（大样本 3σ 内）
	_check("[3b] 全部抽样命中三 tag 之一（无丢样）",
		int(counts["a"]) + int(counts["b"]) + int(counts["c"]) == n)
	_check("[3b] 权重 50 → 占比 ≈0.5（±0.05）", absf(pa - 0.5) < 0.05, "pa=%.3f" % pa)
	_check("[3b] 权重 30 → 占比 ≈0.3（±0.05）", absf(pb - 0.3) < 0.05, "pb=%.3f" % pb)
	_check("[3b] 权重 20 → 占比 ≈0.2（±0.05）", absf(pc - 0.2) < 0.05, "pc=%.3f" % pc)
	_check("[3b] 占比排序 a>b>c（与权重同序）", pa > pb and pb > pc,
		"a=%.3f b=%.3f c=%.3f" % [pa, pb, pc])


# ── 测试 4：伏击波次存在 ─────────────────────────────

func _test_ambush_wave_exists() -> void:
	var waves: Dictionary = _pools.get("waves", {})
	_check("[4] 伏击波次 %s 存在于 DataLoader.waves" % AMBUSH_WAVE, waves.has(AMBUSH_WAVE))
	var wave_v: Variant = waves.get(AMBUSH_WAVE)
	if wave_v is Dictionary:
		var enemies: Array = (wave_v as Dictionary).get("enemies", []) if (wave_v as Dictionary).get("enemies") is Array else []
		_check("[4] 伏击波次含敌人（enemies 非空）", not enemies.is_empty(),
			"size=%d" % enemies.size())
	# 交叉：event_abandoned_mine 的 start_battle effect enemy_config 指向该波次
	var events: Dictionary = _pools.get("events", {})
	var mine_v: Variant = events.get("event_abandoned_mine")
	var found_ambush_ref: bool = false
	if mine_v is Dictionary:
		for c_v: Variant in ((mine_v as Dictionary).get("choices", []) as Array):
			if not (c_v is Dictionary):
				continue
			for o_v: Variant in ((c_v as Dictionary).get("outcomes", []) as Array):
				if not (o_v is Dictionary):
					continue
				for e_v: Variant in ((o_v as Dictionary).get("effects", []) as Array):
					if e_v is Dictionary and str((e_v as Dictionary).get("type", "")) == "start_battle" \
							and str((e_v as Dictionary).get("enemy_config", "")) == AMBUSH_WAVE:
						found_ambush_ref = true
	_check("[4] event_abandoned_mine 引用伏击波次 %s（数据一致）" % AMBUSH_WAVE, found_ambush_ref)


# ── 测试 5：真实事件 outcome 端到端应用 ───────────────

func _test_real_event_outcome() -> void:
	var rm: Object = _fresh_manager()
	var st: Object = rm.get_state()
	st.gold = 500
	var events: Dictionary = _pools.get("events", {})
	# 神秘商人「购买」choice（单 outcome：gold -120 + item）
	var merchant: Dictionary = events.get("event_mysterious_merchant", {})
	var buy_choice: Dictionary = (merchant.get("choices", [])[0]) as Dictionary
	var outcome: Dictionary = rm.pick_event_outcome(buy_choice, _rng)
	var result: Dictionary = rm.apply_event_outcome(outcome)
	_check("[5] 商人购买：gold 500-120=380（真实 effect 数值从事件读）",
		int(st.gold) == 380, "gold=%d" % int(st.gold))
	_check("[5] 商人购买：不触发战斗", not bool(result.get("battle_triggered", false)))
	_check("[5] 商人购买：effect 日志非空（金币变化可见）",
		not (result.get("logs", []) as Array).is_empty())

	# 祝福祭坛「献血」choice（单 outcome：hp_cost_percent + buff 占位）
	var altar: Dictionary = events.get("event_blessing_altar", {})
	var blood_choice: Dictionary = (altar.get("choices", [])[1]) as Dictionary
	st.party[0]["max_hp"] = 20
	st.party[0]["hp"] = 20
	var buffs_before: int = (st.run_buffs as Array).size()
	var altar_outcome: Dictionary = rm.pick_event_outcome(blood_choice, _rng)
	rm.apply_event_outcome(altar_outcome)
	_check("[5] 祭坛献血：0 号角色扣血（hp<20）", int(st.party[0].get("hp", 99)) < 20,
		"hp=%d" % int(st.party[0].get("hp", 99)))
	_check("[5] 祭坛献血：run_buffs 记入占位 buff", (st.run_buffs as Array).size() == buffs_before + 1)


# ── 工具 ─────────────────────────────────────────────

## 新建一个已 start_run 的 RunManager（state 就绪，party 3 人）。
func _fresh_manager() -> Object:
	var rm: Object = RunManagerScript.new()
	rm.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), _rng)
	return rm


## 构造一个 outcome 字典（effects 数组），供 apply_event_outcome 测试用。
func _outcome(effects: Array) -> Dictionary:
	return { "weight": 1, "effects": effects, "description": "（测试 outcome）" }


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
