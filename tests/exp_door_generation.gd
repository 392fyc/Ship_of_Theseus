extends SceneTree
## run-loop v0 门生成器实证实验（headless）——2026-07-03
##
## ⚠⚠ 语义快照警告（2026-07-04 标注，实装 v0 前必读）⚠⚠
## 本脚本写于「商店还是一种门」的旧语义下。2026-07-03 用户裁决后已变更：
##   1. 商店退出门池 → 改为固定插入（幕中一次 + Boss 前一次，嵌入对应 Prep）。
##      当前配置已无 shop 权重——本脚本能适配新配置并复测通过（商店重掷恒为 0），
##      但下方「商店重掷」逻辑已是死代码，【勿据此实装商店门】。
##   2. 遗物保底改为【按出现计数】（run-loop.md 正本），本脚本仍是旧「按选中计数」，
##      实装时以 KB 为准。
##   3. 门数下限=2（已随配置生效）。
## 定位：门生成器 v0 的起点参考 + 约束可满足性实证留档，不是实装规格。
##
## 目的：按 2026-07-02 门模式骨架实现 v0 门生成器，模拟 1000 个 Act1，
## 用统计验证三条硬约束（事件门不相邻、同组类型互不相同、boss_stage 固定 Boss）
## + 遗物保底 + 商店语义在真实随机流下成立且无死锁。
##
## 生成器模型（v0，实验假设标注）：
##   - 每关战斗结算后为下一关掷门组：door_count 在 [min,max] 均匀取值；
##     门类型按 type_weights 加权、同组不放回（互不相同[提案]）。
##   - 上一关（推进关卡的选择）为事件门 → 本组生成时整体排除 event
##     （生成侧强制，保证「事件门不得连续[已定]」不可能被选出）。
##   - 遗物保底：连续 relic_drought_stages 关未选中遗物门 → 下组强制含 relic。
##   - 精英房：每扇战斗门（非 event/shop）独立掷 elite_room_weight% 概率
##     （实验假设：权重按百分比解释）。
##   - 商店语义：选中 shop 不推进关卡、逛完对同一关重掷门组；
##     同一关连续重掷 3 次商店后，后续重掷排除 shop 防死循环（实验假设）。
##   - boss_stage 关不掷门组，固定 Boss 战。
##   - 选门策略：组内均匀随机。
##   - 若加权池被排除项耗尽（理论上 6 类 - event - shop - 强制 relic 仍 ≥3 ≥
##     door_count 上限 3，不应发生），回退策略 = 放宽同组互斥允许重复，计数打印。
##
## 坑规避（--script 三大坑）：逻辑放 _process 首帧；不引用重全局 class_name；
## 纯 FileAccess+JSON + RandomNumberGenerator，不实例化场景。
##
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/exp_door_generation.gd
## 退出码 0=约束违反为 0，1=有违反或配置加载失败。

const RUN_CONFIG_FILE: String = "res://data/runloop/run_config.json"
const ACT_CONFIG_FILE: String = "res://data/runloop/act1_config.json"

const NUM_ACTS: int = 1000
const RNG_SEED: int = 20260703
## 实验假设：同一关卡最多连续重掷 3 次商店，之后重掷排除 shop（防死循环占位）
const MAX_SHOP_REROLLS_PER_STAGE: int = 3

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _ran: bool = false

# ── 配置（JSON 读入，不硬编码） ──────────────────────
var _stage_count: int = 0
var _boss_stage: int = 0
var _dc_min: int = 0
var _dc_max: int = 0
var _type_weights: Dictionary = {}
var _elite_room_weight: float = 0.0
var _pity_stages: int = 0

# ── 统计 ─────────────────────────────────────────────
var _v_consec_event: int = 0
var _v_dup_in_group: int = 0
var _v_boss_misplaced: int = 0

var _appear: Dictionary = {}          # type -> 出现次数（门组内）
var _chosen: Dictionary = {}          # type -> 被选次数（含 shop）
var _door_count_hist: Dictionary = {} # 门数 -> 组数
var _groups_total: int = 0
var _doors_total: int = 0
var _battle_doors_total: int = 0      # 可掷精英的门（非 event/shop）
var _elite_doors_total: int = 0
var _elite_chosen_total: int = 0
var _pity_forced_groups: int = 0
var _pity_relic_taken: int = 0        # 保底组中 relic 实际被选中次数
var _shop_rerolls_total: int = 0
var _shop_cap_hits: int = 0           # 同一关达到重掷上限的次数
var _fallback_relax_distinct: int = 0 # 回退：放宽同组互斥的次数
var _battles_total: int = 0
var _event_stages_total: int = 0
var _single_door_groups_forced_relic: int = 0 # 门数=1 且保底强制 → 无选择权


func _initialize() -> void:
	print("=== exp_door_generation (run-loop v0 门生成器 1000×Act1 实证) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	if not _load_configs():
		print("FAIL: 配置加载失败")
		quit(1)
		return

	_rng.seed = RNG_SEED
	for act_i: int in range(NUM_ACTS):
		_simulate_act()

	_report()
	var violations: int = _v_consec_event + _v_dup_in_group + _v_boss_misplaced
	quit(0 if violations == 0 else 1)


# ── 配置加载 ─────────────────────────────────────────

func _load_configs() -> bool:
	var run_v: Variant = _load_json(RUN_CONFIG_FILE)
	if not (run_v is Dictionary):
		return false
	var act_v: Variant = _load_json(ACT_CONFIG_FILE)
	if not (act_v is Dictionary):
		return false
	var cfg: Dictionary = act_v
	_stage_count = int(cfg.get("stage_count", 0))
	_boss_stage = int(cfg.get("boss_stage", 0))
	var dg_v: Variant = cfg.get("door_gen")
	if not (dg_v is Dictionary):
		return false
	var dg: Dictionary = dg_v
	var dc_v: Variant = dg.get("door_count")
	if not (dc_v is Dictionary):
		return false
	_dc_min = int((dc_v as Dictionary).get("min", 0))
	_dc_max = int((dc_v as Dictionary).get("max", 0))
	var tw_v: Variant = dg.get("type_weights")
	if not (tw_v is Dictionary):
		return false
	for key_v: Variant in (tw_v as Dictionary).keys():
		var key: String = str(key_v)
		if key.begins_with("_"):
			continue
		_type_weights[key] = float((tw_v as Dictionary)[key_v])
	_elite_room_weight = float(dg.get("elite_room_weight", 0))
	var pity_v: Variant = dg.get("pity")
	if not (pity_v is Dictionary):
		return false
	_pity_stages = int((pity_v as Dictionary).get("relic_drought_stages", 0))
	if _stage_count <= 0 or _boss_stage <= 0 or _dc_min <= 0 \
			or _dc_max < _dc_min or _type_weights.is_empty() or _pity_stages <= 0:
		return false
	print("配置：stage_count=%d boss_stage=%d door_count=[%d,%d] elite_w=%s pity=%d" \
		% [_stage_count, _boss_stage, _dc_min, _dc_max,
			str(_elite_room_weight), _pity_stages])
	print("type_weights=%s" % str(_type_weights))
	return true


# ── 单幕模拟 ─────────────────────────────────────────

func _simulate_act() -> void:
	var stage: int = 1                # 第 1 关战斗为起点（无门直接进入）
	var last_type: String = ""        # 上一次推进关卡的选择类型
	var drought: int = 0              # 连续未选中遗物门的关数
	var chosen_seq: Array[String] = []  # 推进关卡的选择序列（不含 shop）
	var boss_fought_at: int = -1

	while true:
		# 当前关战斗
		if stage == _boss_stage:
			boss_fought_at = stage
			_battles_total += 1
			break
		if last_type == "event" and stage > 1:
			_event_stages_total += 1  # 事件关：无战斗（实验假设：事件门替代战斗）
		else:
			_battles_total += 1

		var next_stage: int = stage + 1
		if next_stage == _boss_stage:
			# Boss 关不掷门组，固定 Boss 门
			chosen_seq.append("boss")
			last_type = "boss"
			stage = next_stage
			continue

		# ── 为 next_stage 掷门组（含商店重掷循环） ──
		var shop_rerolls: int = 0
		var choice_type: String = ""
		var choice_elite: bool = false
		while true:
			var force_relic: bool = drought >= _pity_stages
			var exclude_event: bool = last_type == "event"
			var exclude_shop: bool = shop_rerolls >= MAX_SHOP_REROLLS_PER_STAGE
			var group: Array[Dictionary] = _gen_group(
				force_relic, exclude_event, exclude_shop)
			if force_relic:
				_pity_forced_groups += 1
				if group.size() == 1:
					_single_door_groups_forced_relic += 1

			# 组内统计 + 违反检查
			_groups_total += 1
			_door_count_hist[group.size()] = \
				int(_door_count_hist.get(group.size(), 0)) + 1
			var seen: Dictionary = {}
			for door: Dictionary in group:
				var t: String = str(door["type"])
				_doors_total += 1
				_appear[t] = int(_appear.get(t, 0)) + 1
				if seen.has(t):
					_v_dup_in_group += 1
				seen[t] = true
				if t != "event" and t != "shop":
					_battle_doors_total += 1
					if bool(door["elite"]):
						_elite_doors_total += 1

			# 选门：均匀随机
			var pick: Dictionary = group[_rng.randi_range(0, group.size() - 1)]
			var pick_t: String = str(pick["type"])
			_chosen[pick_t] = int(_chosen.get(pick_t, 0)) + 1
			if pick_t == "shop":
				shop_rerolls += 1
				_shop_rerolls_total += 1
				if shop_rerolls == MAX_SHOP_REROLLS_PER_STAGE:
					_shop_cap_hits += 1
				continue  # 不推进关卡，重掷门组
			choice_type = pick_t
			choice_elite = bool(pick["elite"])
			if force_relic and pick_t == "relic":
				_pity_relic_taken += 1
			break

		# ── 推进关卡 ──
		if choice_elite:
			_elite_chosen_total += 1
		if choice_type == "relic":
			drought = 0
		else:
			drought += 1
		chosen_seq.append(choice_type)
		last_type = choice_type
		stage = next_stage

	# ── 幕级违反检查 ──
	if boss_fought_at != _boss_stage:
		_v_boss_misplaced += 1
	# Boss 只应出现在序列末尾（chosen_seq 最后一项）
	for i: int in range(chosen_seq.size() - 1):
		if chosen_seq[i] == "boss":
			_v_boss_misplaced += 1
	# 相邻事件（选中序列层面）
	for i: int in range(1, chosen_seq.size()):
		if chosen_seq[i] == "event" and chosen_seq[i - 1] == "event":
			_v_consec_event += 1


## 掷一个门组：加权不放回 + 排除项 + 保底强制
func _gen_group(force_relic: bool, exclude_event: bool,
		exclude_shop: bool) -> Array[Dictionary]:
	var count: int = _rng.randi_range(_dc_min, _dc_max)
	var avail: Dictionary = _type_weights.duplicate()
	if exclude_event:
		avail.erase("event")
	if exclude_shop:
		avail.erase("shop")
	var types: Array[String] = []
	if force_relic and count >= 1:
		types.append("relic")
		avail.erase("relic")
	while types.size() < count:
		if avail.is_empty():
			# 回退策略：加权池耗尽 → 放宽同组互斥，从全池（保留排除项）重取
			_fallback_relax_distinct += 1
			avail = _type_weights.duplicate()
			if exclude_event:
				avail.erase("event")
			if exclude_shop:
				avail.erase("shop")
			print("  [回退] 池耗尽：count=%d exclude_event=%s exclude_shop=%s force_relic=%s → 放宽同组互斥" \
				% [count, str(exclude_event), str(exclude_shop), str(force_relic)])
		var t: String = _weighted_pick(avail)
		types.append(t)
		avail.erase(t)  # 同组类型互不相同[提案]
	var group: Array[Dictionary] = []
	for t: String in types:
		var elite: bool = false
		if t != "event" and t != "shop":
			elite = _rng.randf() * 100.0 < _elite_room_weight
		group.append({"type": t, "elite": elite})
	return group


func _weighted_pick(weights: Dictionary) -> String:
	var total: float = 0.0
	for k: Variant in weights.keys():
		total += float(weights[k])
	var roll: float = _rng.randf() * total
	var acc: float = 0.0
	for k: Variant in weights.keys():
		acc += float(weights[k])
		if roll < acc:
			return str(k)
	return str(weights.keys()[weights.size() - 1])


# ── 报告 ─────────────────────────────────────────────

func _report() -> void:
	var violations: int = _v_consec_event + _v_dup_in_group + _v_boss_misplaced
	print("\n=== 结果（%d 幕，seed=%d） ===" % [NUM_ACTS, RNG_SEED])
	print("[约束违反] 总计 %d ：相邻事件=%d 同组重复类型=%d Boss错位=%d" \
		% [violations, _v_consec_event, _v_dup_in_group, _v_boss_misplaced])
	print("[回退] 放宽同组互斥触发 %d 次" % _fallback_relax_distinct)

	# 权重归一 vs 出现/被选分布
	var w_total: float = 0.0
	for k: Variant in _type_weights.keys():
		w_total += float(_type_weights[k])
	var chosen_total: int = 0
	for k: Variant in _chosen.keys():
		chosen_total += int(_chosen[k])
	print("\n[门类型分布] 类型: 配置权重% | 出现% (n) | 被选% (n)")
	for k: Variant in _type_weights.keys():
		var t: String = str(k)
		var cfg_pct: float = float(_type_weights[k]) / w_total * 100.0
		var ap: int = int(_appear.get(t, 0))
		var ch: int = int(_chosen.get(t, 0))
		print("  %-9s: %5.1f%% | %5.1f%% (%d) | %5.1f%% (%d)" \
			% [t, cfg_pct, float(ap) / float(_doors_total) * 100.0, ap,
				float(ch) / float(chosen_total) * 100.0, ch])

	print("\n[门数分布] 组总数=%d" % _groups_total)
	for n: int in range(_dc_min, _dc_max + 1):
		var c: int = int(_door_count_hist.get(n, 0))
		print("  %d 扇: %5.1f%% (%d)" % [n, float(c) / float(_groups_total) * 100.0, c])

	print("\n[精英房] 门级出现率 %.1f%%（%d/%d 战斗门，配置 %.0f%%）| 每幕被选精英战 %.2f" \
		% [float(_elite_doors_total) / float(_battle_doors_total) * 100.0,
			_elite_doors_total, _battle_doors_total, _elite_room_weight,
			float(_elite_chosen_total) / float(NUM_ACTS)])

	print("[遗物保底] 强制含relic组 %d（每幕 %.2f）| 保底组中relic被选 %d（%.1f%%）| 门数=1保底组（无选择权） %d" \
		% [_pity_forced_groups, float(_pity_forced_groups) / float(NUM_ACTS),
			_pity_relic_taken,
			(float(_pity_relic_taken) / float(_pity_forced_groups) * 100.0) \
				if _pity_forced_groups > 0 else 0.0,
			_single_door_groups_forced_relic])

	print("[商店] 重掷总数 %d（每幕 %.2f）| 同关达重掷上限(%d次) %d 回" \
		% [_shop_rerolls_total, float(_shop_rerolls_total) / float(NUM_ACTS),
			MAX_SHOP_REROLLS_PER_STAGE, _shop_cap_hits])

	print("[战斗数] 平均每幕实际战斗 %.2f（事件关不计战斗，平均事件关 %.2f；含Boss，关卡数恒 %d）" \
		% [float(_battles_total) / float(NUM_ACTS),
			float(_event_stages_total) / float(NUM_ACTS), _stage_count])

	if violations == 0:
		print("\nOK：三条硬约束在 %d 幕模拟中零违反" % NUM_ACTS)
	else:
		print("\nFAIL：存在约束违反")


# ── 工具 ─────────────────────────────────────────────

func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	return JSON.parse_string(text)
