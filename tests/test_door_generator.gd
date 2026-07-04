extends SceneTree
## DoorGenerator v0 headless 回归测试 —— 2026-07-04
##
## 覆盖 scripts/roguelite/door_generator.gd 的 generate_group：
##   1. 门数恒在 [min,max]。
##   2. 无 shop：任何门 reward_type 都在五类枚举内。
##   3. 事件不连续：last_choice_type=="event" 时组内无 event 门。
##   4. distinct=true 时同组 reward_type 无重复。
##   5. 保底按出现（专项，最关键）：
##      a. drought >= 阈值 → 组内必含 relic；
##      b. 组内出现 relic（哪怕玩家选了别的门）→ relic_drought_after==0；
##      c. 组内未出现 relic → relic_drought_after == drought+1；
##      d. 反例：drought 达阈值→组含 relic→模拟选中非 relic 门→下次 drought 传 0。
##   6. 内容装配正确：非事件门 battle 非空、map_id/enemy_config 属对应池；
##      事件门 battle==null 且 event_id ∈ event_pool。
##   7. 精英门 special_affix == 该波次 elite_chief 的 special_affix。
##   8. 多幕流下三条硬约束零违反 + 打印统计。
##
## 坑规避（--script 三大坑）：逻辑放 _process 首帧；不引用重全局 class_name
## （DoorGenerator 用 preload().new() 而非 class_name）；DataLoader 手动
## load_all()（.new() 不入树，_ready 不触发）。
##
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/test_door_generator.gd
## 退出码 0=全过，1=有失败。

const ACT_CONFIG_FILE: String = "res://data/runloop/act1_config.json"
const DOOR_GEN_SCRIPT: String = "res://scripts/roguelite/door_generator.gd"
const DATA_LOADER_SCRIPT: String = "res://scripts/data/data_loader.gd"

## 五类奖励门枚举（无 shop）
const DOOR_TYPES: Array[String] = ["gold", "exp", "equipment", "relic", "event"]

const GEN_ITERS: int = 2000       # 聚合生成测试次数
const NUM_ACTS: int = 1000        # 多幕流模拟幕数
const STAGES_PER_ACT: int = 7     # 每幕掷门组次数（骨架 8 关，末关 Boss 不掷）
const RNG_SEED: int = 20260704

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _gen: Object = null

# ── 配置缓存 ──
var _door_gen: Dictionary = {}
var _waves: Dictionary = {}
var _dc_min: int = 0
var _dc_max: int = 0
var _distinct: bool = true
var _pity_stages: int = 0
var _map_pool: Array[String] = []
var _event_pool: Array[String] = []
var _normal_pool: Array[String] = []
var _elite_pool: Array[String] = []

# ── 统计 ──
var _type_appear: Dictionary = {}
var _door_count_hist: Dictionary = {}
var _elite_doors: int = 0
var _battle_doors: int = 0
var _pity_forced_groups: int = 0


func _initialize() -> void:
	print("=== test_door_generator (DoorGenerator v0 回归) ===")


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

	_test_aggregate_generation()
	_test_pity_appearance_explicit()
	_test_pity_counterexample()
	_test_guarantee_non_elite()
	_test_multi_act_flow()

	_finish()


# ── 环境加载 ─────────────────────────────────────────

func _load_env() -> bool:
	var cfg_v: Variant = _load_json(ACT_CONFIG_FILE)
	_check("act1_config.json 可解析为 Dictionary", cfg_v is Dictionary)
	if not (cfg_v is Dictionary):
		return false
	var dg_v: Variant = (cfg_v as Dictionary).get("door_gen")
	_check("door_gen 为 Dictionary", dg_v is Dictionary)
	if not (dg_v is Dictionary):
		return false
	_door_gen = dg_v

	var dc_v: Variant = _door_gen.get("door_count")
	if dc_v is Dictionary:
		_dc_min = int((dc_v as Dictionary).get("min", 0))
		_dc_max = int((dc_v as Dictionary).get("max", 0))
	_check("door_count [min,max] 合法（min>=2, max>=min）",
		_dc_min >= 2 and _dc_max >= _dc_min, "min=%d max=%d" % [_dc_min, _dc_max])

	var cons_v: Variant = _door_gen.get("constraints")
	if cons_v is Dictionary:
		_distinct = bool((cons_v as Dictionary).get("same_offer_types_distinct", true))
	var pity_v: Variant = _door_gen.get("pity")
	if pity_v is Dictionary:
		_pity_stages = int((pity_v as Dictionary).get("relic_drought_stages", 0))
	_check("pity.relic_drought_stages > 0", _pity_stages > 0, "实际 %d" % _pity_stages)

	_map_pool = _string_array(_door_gen.get("map_pool"))
	_event_pool = _string_array(_door_gen.get("event_pool"))
	var bp_v: Variant = _door_gen.get("battle_pools")
	if bp_v is Dictionary:
		_normal_pool = _string_array((bp_v as Dictionary).get("normal"))
		_elite_pool = _string_array((bp_v as Dictionary).get("elite"))
	_check("map_pool 非空", not _map_pool.is_empty())
	_check("event_pool 非空", not _event_pool.is_empty())
	_check("battle_pools.normal 非空", not _normal_pool.is_empty())
	_check("battle_pools.elite 非空", not _elite_pool.is_empty())

	# DataLoader：手动 load_all（.new() 不入树，_ready 不触发）
	var dl: Object = load(DATA_LOADER_SCRIPT).new()
	dl.load_all()
	_waves = dl.waves
	_check("DataLoader.waves 非空", not _waves.is_empty(), "waves=%d" % _waves.size())

	# 生成器实例（preload().new()，不用 class_name）
	_gen = preload("res://scripts/roguelite/door_generator.gd").new()
	_check("DoorGenerator 实例化成功", _gen != null)

	return _fail == 0


# ── 测试 1-4,6,7：聚合生成 ───────────────────────────

func _test_aggregate_generation() -> void:
	var door_count_violations: int = 0
	var shop_violations: int = 0
	var enum_violations: int = 0
	var event_excl_violations: int = 0
	var dup_violations: int = 0
	var battle_null_violations: int = 0
	var map_violations: int = 0
	var enemy_violations: int = 0
	var ev_battle_violations: int = 0
	var ev_id_violations: int = 0
	var ev_affix_violations: int = 0
	var affix_violations: int = 0
	var pity_appear_violations: int = 0
	var pity_noappear_violations: int = 0
	var force_relic_violations: int = 0
	var fallback_total: int = 0
	var non_elite_violations: int = 0

	var last_pool: Array[String] = ["", "gold", "exp", "equipment", "relic", "event"]

	for i: int in range(GEN_ITERS):
		var last_choice: String = last_pool[_rng.randi_range(0, last_pool.size() - 1)]
		var drought: int = _rng.randi_range(0, _pity_stages + 2)
		var ctx: Dictionary = {
			"last_choice_type": last_choice,
			"relic_drought": drought,
		}
		var res: Dictionary = _gen.generate_group(_door_gen, ctx, _waves, _rng)
		var doors: Array = res.get("doors", [])
		fallback_total += int(res.get("_fallback_count", 0))

		# 1. 门数
		if doors.size() < _dc_min or doors.size() > _dc_max:
			door_count_violations += 1
		_door_count_hist[doors.size()] = int(_door_count_hist.get(doors.size(), 0)) + 1

		var seen: Dictionary = {}
		var has_relic: bool = false
		var group_has_non_elite: bool = false
		for door_v: Variant in doors:
			var door: Dictionary = door_v
			var rt: String = str(door.get("reward_type", ""))
			if not bool(door.get("elite_room", false)):
				group_has_non_elite = true
			_type_appear[rt] = int(_type_appear.get(rt, 0)) + 1

			# 2. 无 shop + 枚举内
			if rt == "shop":
				shop_violations += 1
			if not DOOR_TYPES.has(rt):
				enum_violations += 1
			# 3. 事件不连续
			if last_choice == "event" and rt == "event":
				event_excl_violations += 1
			# 4. distinct 无重复
			if _distinct and seen.has(rt):
				dup_violations += 1
			seen[rt] = true
			if rt == "relic":
				has_relic = true

			# 6+7. 内容装配 + 精英 affix
			var battle_v: Variant = door.get("battle")
			var preview_v: Variant = door.get("preview")
			var preview: Dictionary = preview_v if preview_v is Dictionary else {}
			if rt == "event":
				if battle_v != null:
					ev_battle_violations += 1
				var eid: String = str(door.get("event_id", ""))
				if not _event_pool.has(eid):
					ev_id_violations += 1
				if preview.get("special_affix") != null:
					ev_affix_violations += 1
			else:
				_battle_doors += 1
				if not (battle_v is Dictionary):
					battle_null_violations += 1
				else:
					var battle: Dictionary = battle_v
					var map_id: String = str(battle.get("map_id", ""))
					var enemy_config: String = str(battle.get("enemy_config", ""))
					if not _map_pool.has(map_id):
						map_violations += 1
					var elite_room: bool = bool(door.get("elite_room", false))
					var expect_pool: Array[String] = _elite_pool if elite_room else _normal_pool
					if not expect_pool.has(enemy_config):
						enemy_violations += 1
					if elite_room:
						_elite_doors += 1
						var expected_affix: Variant = _elite_chief_affix(enemy_config)
						if preview.get("special_affix") != expected_affix:
							affix_violations += 1

		# 每门组 ≥1 非精英门（默认配置修复后应零违反）
		if not group_has_non_elite:
			non_elite_violations += 1

		# 5b/5c. 保底按出现
		var after: int = int(res.get("relic_drought_after", -999))
		if has_relic:
			if after != 0:
				pity_appear_violations += 1
		else:
			if after != drought + 1:
				pity_noappear_violations += 1
		# 5a. drought 达阈值 → 必含 relic
		if drought >= _pity_stages:
			_pity_forced_groups += 1
			if not has_relic:
				force_relic_violations += 1

	# ── 断言（聚合） ──
	_check("[1] 门数恒在 [%d,%d]" % [_dc_min, _dc_max], door_count_violations == 0,
		"越界 %d 次" % door_count_violations)
	_check("[2] 无 shop 类型门", shop_violations == 0, "shop 出现 %d 次" % shop_violations)
	_check("[2] 所有 reward_type 在五类枚举内", enum_violations == 0,
		"越界 %d 次" % enum_violations)
	_check("[3] 事件不连续：last==event 时组内无 event", event_excl_violations == 0,
		"违反 %d 次" % event_excl_violations)
	_check("[4] distinct 同组 reward_type 无重复", dup_violations == 0,
		"重复 %d 次" % dup_violations)
	_check("[6] 非事件门 battle 非空", battle_null_violations == 0,
		"空 %d 次" % battle_null_violations)
	_check("[6] 非事件门 map_id ∈ map_pool", map_violations == 0,
		"越界 %d 次" % map_violations)
	_check("[6] 非事件门 enemy_config ∈ 对应 battle_pool", enemy_violations == 0,
		"越界 %d 次" % enemy_violations)
	_check("[6] 事件门 battle==null", ev_battle_violations == 0,
		"非空 %d 次" % ev_battle_violations)
	_check("[6] 事件门 event_id ∈ event_pool", ev_id_violations == 0,
		"越界 %d 次" % ev_id_violations)
	_check("[6] 事件门 preview.special_affix==null", ev_affix_violations == 0,
		"非空 %d 次" % ev_affix_violations)
	_check("[7] 精英门 special_affix == 波次 elite_chief 的 special_affix",
		affix_violations == 0, "不符 %d 次" % affix_violations)
	_check("[5b] 组内出现 relic → relic_drought_after==0", pity_appear_violations == 0,
		"违反 %d 次" % pity_appear_violations)
	_check("[5c] 组内无 relic → relic_drought_after==drought+1",
		pity_noappear_violations == 0, "违反 %d 次" % pity_noappear_violations)
	_check("[5a] drought>=阈值 → 组内必含 relic", force_relic_violations == 0,
		"缺失 %d 次（保底组 %d）" % [force_relic_violations, _pity_forced_groups])
	_check("回退（池耗尽放宽 distinct）恒为 0（五类配置）", fallback_total == 0,
		"触发 %d 次" % fallback_total)
	_check("[新] 每门组 ≥1 非精英门（默认配置 elite=25%）", non_elite_violations == 0,
		"违反 %d 次" % non_elite_violations)


# ── 测试 5a：保底强制含 relic（确定性重复） ────────────

func _test_pity_appearance_explicit() -> void:
	var trials: int = 200
	var missing: int = 0
	for i: int in range(trials):
		var ctx: Dictionary = {
			"last_choice_type": "",
			"relic_drought": _pity_stages,  # 恰达阈值
		}
		var res: Dictionary = _gen.generate_group(_door_gen, ctx, _waves, _rng)
		if not _doors_have_relic(res.get("doors", [])):
			missing += 1
	_check("[5a-专项] drought==阈值 连续 %d 次均含 relic 门" % trials, missing == 0,
		"缺失 %d 次" % missing)


# ── 测试 5d：按出现 ≠ 按选中（反例） ───────────────────

func _test_pity_counterexample() -> void:
	# 构造：drought 达阈值 → 组必含 relic → 模拟玩家「选中非 relic 门」→
	# 下一次 ctx.relic_drought 应传 0（因为上组「出现」了 relic，与被选无关）。
	var found_case: bool = false
	var wrong_after: int = 0
	var chose_non_relic_but_reset: bool = false

	for attempt: int in range(500):
		var ctx: Dictionary = {
			"last_choice_type": "",
			"relic_drought": _pity_stages,
		}
		var res: Dictionary = _gen.generate_group(_door_gen, ctx, _waves, _rng)
		var doors: Array = res.get("doors", [])
		if not _doors_have_relic(doors):
			continue  # 5a 已单独验证「必含」；这里只挑含 relic 的组做反例
		# 找一扇「非 relic」的门来模拟玩家选择
		var non_relic_idx: int = -1
		for i: int in range(doors.size()):
			if str((doors[i] as Dictionary).get("reward_type", "")) != "relic":
				non_relic_idx = i
				break
		if non_relic_idx < 0:
			continue  # 全是 relic（distinct 下门数≥2 不会，但容错）
		found_case = true
		var chosen_type: String = str((doors[non_relic_idx] as Dictionary).get("reward_type", ""))
		# 关键：玩家选了非 relic，但因为组内「出现」了 relic → after 必须 0
		var after: int = int(res.get("relic_drought_after", -999))
		if after != 0:
			wrong_after += 1
		else:
			# 证明「按出现」：选中的是非 relic，drought 仍归零
			if chosen_type != "relic":
				chose_non_relic_but_reset = true
		break

	_check("[5d] 找到反例场景（drought 达阈值且组含 relic）", found_case)
	_check("[5d] 反例：玩家选中非 relic 门，relic_drought_after 仍 == 0（按出现≠按选中）",
		found_case and wrong_after == 0 and chose_non_relic_but_reset)


# ── 测试 8：多幕流三硬约束零违反 ──────────────────────

func _test_multi_act_flow() -> void:
	var consec_event_violations: int = 0   # 选中层面：相邻事件
	var dup_violations: int = 0
	var shop_violations: int = 0
	var groups: int = 0
	var doors_total: int = 0
	var elite_doors: int = 0
	var battle_doors: int = 0
	var type_dist: Dictionary = {}
	var dc_hist: Dictionary = {}
	var pity_triggers: int = 0

	for act_i: int in range(NUM_ACTS):
		var last_choice: String = ""     # 上一关推进选择类型
		var drought: int = 0             # 按出现计数，跨关线程传递
		for stage_i: int in range(STAGES_PER_ACT):
			var ctx: Dictionary = {
				"last_choice_type": last_choice,
				"relic_drought": drought,
			}
			if drought >= _pity_stages:
				pity_triggers += 1
			var res: Dictionary = _gen.generate_group(_door_gen, ctx, _waves, _rng)
			var doors: Array = res.get("doors", [])
			groups += 1
			dc_hist[doors.size()] = int(dc_hist.get(doors.size(), 0)) + 1

			var seen: Dictionary = {}
			for door_v: Variant in doors:
				var door: Dictionary = door_v
				var rt: String = str(door.get("reward_type", ""))
				doors_total += 1
				type_dist[rt] = int(type_dist.get(rt, 0)) + 1
				if rt == "shop":
					shop_violations += 1
				if seen.has(rt):
					dup_violations += 1
				seen[rt] = true
				if rt != "event":
					battle_doors += 1
					if bool(door.get("elite_room", false)):
						elite_doors += 1

			# 玩家均匀随机选一扇门推进
			var pick: Dictionary = doors[_rng.randi_range(0, doors.size() - 1)]
			var pick_type: String = str(pick.get("reward_type", ""))
			# 选中层面：相邻事件（生成侧排除后不应发生）
			if pick_type == "event" and last_choice == "event":
				consec_event_violations += 1
			# 按出现更新 drought（用返回值，非「是否选中 relic」）
			drought = int(res.get("relic_drought_after", 0))
			last_choice = pick_type

	_check("[8] 多幕流：相邻事件（选中层面）零违反", consec_event_violations == 0,
		"违反 %d 次" % consec_event_violations)
	_check("[8] 多幕流：同组类型重复零违反", dup_violations == 0,
		"违反 %d 次" % dup_violations)
	_check("[8] 多幕流：无 shop 门零违反", shop_violations == 0,
		"违反 %d 次" % shop_violations)

	# ── 统计打印 ──
	print("\n[多幕流统计] %d 幕 × %d 关 = %d 门组，%d 扇门" \
		% [NUM_ACTS, STAGES_PER_ACT, groups, doors_total])
	print("  门数分布：")
	for n: int in range(_dc_min, _dc_max + 1):
		var c: int = int(dc_hist.get(n, 0))
		print("    %d 扇: %5.1f%% (%d)" % [n, float(c) / float(groups) * 100.0, c])
	print("  类型分布（出现）：")
	for t: String in DOOR_TYPES:
		var c2: int = int(type_dist.get(t, 0))
		print("    %-10s: %5.1f%% (%d)" % [t, float(c2) / float(doors_total) * 100.0, c2])
	if battle_doors > 0:
		print("  精英率：%.1f%%（%d/%d 战斗门，配置 %s%%）" \
			% [float(elite_doors) / float(battle_doors) * 100.0, elite_doors,
				battle_doors, str(float(_door_gen.get("elite_room_weight", 0)))])
	print("  保底触发（drought>=阈值 %d）门组数：%d" % [_pity_stages, pity_triggers])


# ── 测试：每门组 ≥1 非精英门硬约束（强制全精英场景 + 开关两态） ──

func _test_guarantee_non_elite() -> void:
	# 构造强制全精英场景：elite_room_weight=100（所有战斗门必精英）+
	# type_weights 去 event（全战斗门）→ 无约束时每组必全精英。
	var forced: Dictionary = _door_gen.duplicate(true)
	forced["elite_room_weight"] = 100.0
	forced["type_weights"] = {"gold": 20, "exp": 20, "equipment": 20, "relic": 15}
	var cons_on: Dictionary = {}
	if forced.get("constraints") is Dictionary:
		cons_on = (forced["constraints"] as Dictionary).duplicate(true)
	cons_on["guarantee_non_elite_door"] = true
	forced["constraints"] = cons_on

	var on_violations: int = 0
	var degraded_bad: int = 0
	var dup_after_degrade: int = 0
	for _i: int in range(500):
		var ctx: Dictionary = {"last_choice_type": "", "relic_drought": 0}
		var res: Dictionary = _gen.generate_group(forced, ctx, _waves, _rng)
		var doors: Array = res.get("doors", [])
		var has_non_elite: bool = false
		var seen: Dictionary = {}
		for door_v: Variant in doors:
			var door: Dictionary = door_v
			var rt: String = str(door.get("reward_type", ""))
			if seen.has(rt):
				dup_after_degrade += 1
			seen[rt] = true
			if not bool(door.get("elite_room", false)):
				has_non_elite = true
				# 降级门：敌人应 ∈ normal_pool、无 special_affix
				var battle_v: Variant = door.get("battle")
				if battle_v is Dictionary:
					var ec: String = str((battle_v as Dictionary).get("enemy_config", ""))
					if ec != "" and not _normal_pool.has(ec):
						degraded_bad += 1
				var pv: Variant = door.get("preview")
				if pv is Dictionary and (pv as Dictionary).get("special_affix") != null:
					degraded_bad += 1
		if not has_non_elite:
			on_violations += 1
	_check("[非精英] 强制全精英场景（elite=100%,无event）每组仍 ≥1 非精英门",
		on_violations == 0, "违反 %d 次" % on_violations)
	_check("[非精英] 降级门敌人 ∈ normal_pool 且 special_affix==null",
		degraded_bad == 0, "异常 %d 次" % degraded_bad)
	_check("[非精英] 降级不破坏 distinct（同组 reward_type 无重复）",
		dup_after_degrade == 0, "重复 %d 次" % dup_after_degrade)

	# 反向：关闭开关 → 允许全精英（证明开关有效 + 无此约束确会全精英）
	var off: Dictionary = forced.duplicate(true)
	var cons_off: Dictionary = (off["constraints"] as Dictionary).duplicate(true)
	cons_off["guarantee_non_elite_door"] = false
	off["constraints"] = cons_off
	var all_elite_groups: int = 0
	for _i: int in range(500):
		var ctx: Dictionary = {"last_choice_type": "", "relic_drought": 0}
		var res: Dictionary = _gen.generate_group(off, ctx, _waves, _rng)
		var any_non_elite: bool = false
		for door_v: Variant in res.get("doors", []):
			if not bool((door_v as Dictionary).get("elite_room", false)):
				any_non_elite = true
		if not any_non_elite:
			all_elite_groups += 1
	# 强制场景完全确定（elite=100%+无event+开关off）→ 每组必全精英，用等号断言更强
	_check("[非精英] 开关=false 时门组恒全精英（证明约束确实在起作用）",
		all_elite_groups == 500, "全精英组 %d（期望 ==500）" % all_elite_groups)


# ── 工具 ─────────────────────────────────────────────

func _doors_have_relic(doors: Array) -> bool:
	for door_v: Variant in doors:
		if str((door_v as Dictionary).get("reward_type", "")) == "relic":
			return true
	return false


## 与 door_generator._lookup_special_affix 等价的独立实现，用于交叉校验。
func _elite_chief_affix(wave_id: String) -> Variant:
	if not _waves.has(wave_id):
		return null
	var wave_v: Variant = _waves[wave_id]
	if not (wave_v is Dictionary):
		return null
	var enemies_v: Variant = (wave_v as Dictionary).get("enemies")
	if not (enemies_v is Array):
		return null
	for enemy_v: Variant in (enemies_v as Array):
		if not (enemy_v is Dictionary):
			continue
		if str((enemy_v as Dictionary).get("tier", "")) == "elite_chief":
			var sa: String = str((enemy_v as Dictionary).get("special_affix", ""))
			return sa if sa != "" else null
	return null


func _string_array(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if v is Array:
		for item: Variant in (v as Array):
			out.append(str(item))
	return out


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
