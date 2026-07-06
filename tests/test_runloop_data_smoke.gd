extends SceneTree
## run-loop v0 数据骨架冒烟测试（headless）——第三轮门模式版
##
## 目的：验证 data/events/*.json（3 个事件）、data/runloop/run_config.json
## （run 级：难度档+恢复，2026-07-03 恢复挪 run 级）与 data/runloop/act1_config.json
## （门生成配置，2026-07-02 第三轮定稿 schema，取代线性 MapGraph）能被 Godot
## 解析，且字段满足骨架 schema：
##   - Event{id,title,description,choices[]} / EventChoice{text,outcomes[]}
##     / EventOutcome{weight,effects[],description}
##   - RunConfig{difficulty,recovery}（恢复只随难度档变动、run 内恒定、可拒绝）
##   - ActConfig{act,stage_count,boss_stage,boss,door_gen,shop}
##     五类门 type_weights（商店已退出门池，2026-07-03）、生成约束、
##     遗物保底（按出现计数）、固定商店插入（幕中+Boss前）、门数 2-3、
##     资源池引用完整性、RewardDrop.kind 合法枚举（无 "talent_point"/"skill"/"rune"）、
##     Boss 固定包含 金币+经验+装备+遗物、
##     shop 固定商店配置（库存件数+按品质定价+回收比例，任务 #7）。
##
## 坑规避（--script 三大坑）：测试逻辑放 _process 首帧；不引用重全局 class_name；
## 纯 FileAccess+JSON 数据校验，不实例化场景。
##
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/test_runloop_data_smoke.gd
## 退出码 0=全过，1=有失败。

const EVENT_FILES: Array[String] = [
	"res://data/events/event_mysterious_merchant.json",
	"res://data/events/event_abandoned_mine.json",
	"res://data/events/event_blessing_altar.json",
]
const ACT_CONFIG_FILE: String = "res://data/runloop/act1_config.json"
const RUN_CONFIG_FILE: String = "res://data/runloop/run_config.json"
const EVENTS_DIR: String = "res://data/events"
const MAPS_DIR: String = "res://data/maps"

## 五类奖励门（2026-07-02 门模式定稿；2026-07-03 商店退出门池改固定插入）
const DOOR_TYPES: Array[String] = ["gold", "exp", "equipment", "relic", "event"]
## 掉落 kind 合法枚举（第三轮修订：无 talent_point / skill / rune）
const REWARD_KINDS: Array[String] = ["gold", "exp", "equipment", "relic", "potion"]
const FORBIDDEN_KINDS: Array[String] = ["talent_point", "skill", "rune"]
## Boss 固定包必含的四类（金币+经验+装备+特殊遗物）
const BOSS_PACKAGE_KINDS: Array[String] = ["gold", "exp", "equipment", "relic"]

## ── 新建数据层目录（波次 / 词条 / 遗物 / 装备）──────────
const WAVES_DIR: String = "res://data/waves"
const AFFIX_BASE_DIR: String = "res://data/affixes/base"
const AFFIX_SPECIAL_DIR: String = "res://data/affixes/special"
const RELICS_DIR: String = "res://data/relics"
const EQUIPMENT_DIR: String = "res://data/equipment"
const EVENT_MINE_FILE: String = "res://data/events/event_abandoned_mine.json"

## 7 个已知波次文件（无扩展名 id）
const WAVE_FILES: Array[String] = [
	"wave_act1_normal_01", "wave_act1_normal_02", "wave_act1_normal_03",
	"wave_act1_elite_01", "wave_act1_elite_02", "wave_act1_boss_01",
	"wave_event_mine_ambush",
]
## 敌人层级合法枚举（词条制敌人五层，v0 暂用四档）
const ENEMY_TIERS: Array[String] = ["normal", "lesser_elite", "greater_elite", "elite_chief"]
## 基础词条池 3 个 + 特殊词条池 2 个
const AFFIX_BASE_FILES: Array[String] = [
	"af_counter_boost", "af_vanguard", "af_heal_resist",
]
const AFFIX_SPECIAL_FILES: Array[String] = ["afs_bulwark", "afs_frenzy"]
## 遗物 / 装备合法枚举
const RELIC_RARITIES: Array[String] = ["common", "rare", "epic", "legendary"]
const RELIC_CATEGORIES: Array[String] = ["economy", "stat", "build"]
const EQUIP_SLOTS: Array[String] = ["weapon", "armor"]

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_runloop_data_smoke (run-loop v0 门模式数据骨架冒烟) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	# ── 1. 事件 JSON：解析 + schema ─────────────────────
	var event_ids: Dictionary = {}
	for path: String in EVENT_FILES:
		var parsed: Variant = _load_json(path)
		var short: String = path.get_file()
		_check("%s 可解析且为 Dictionary" % short,
			parsed is Dictionary, "解析结果类型 %s" % type_string(typeof(parsed)))
		if not (parsed is Dictionary):
			continue
		var ev: Dictionary = parsed
		_validate_event(short, ev)
		var ev_id: String = str(ev.get("id", ""))
		if ev_id != "":
			event_ids[ev_id] = true

	# 补充：扫描 data/events 目录，收集全部事件 id（供 event_pool 校验）
	var dir: DirAccess = DirAccess.open(EVENTS_DIR)
	_check("data/events 目录可打开", dir != null)
	if dir != null:
		for fname: String in dir.get_files():
			if not fname.ends_with(".json"):
				continue
			var extra: Variant = _load_json(EVENTS_DIR + "/" + fname)
			if extra is Dictionary:
				var extra_id: String = str((extra as Dictionary).get("id", ""))
				if extra_id != "":
					event_ids[extra_id] = true

	# ── 1.5 RunConfig：难度档 + 恢复（2026-07-03 挪 run 级） ──
	var run_parsed: Variant = _load_json(RUN_CONFIG_FILE)
	_check("run_config.json 可解析且为 Dictionary", run_parsed is Dictionary,
		"解析结果类型 %s" % type_string(typeof(run_parsed)))
	if run_parsed is Dictionary:
		var run_cfg: Dictionary = run_parsed
		_check("difficulty 非空字符串（开局难度档）",
			str(run_cfg.get("difficulty", "")) != "")
		var rrec_v: Variant = run_cfg.get("recovery")
		_check("run 级 recovery 为 Dictionary", rrec_v is Dictionary)
		if rrec_v is Dictionary:
			var rrec: Dictionary = rrec_v
			var rpct: int = int(rrec.get("percent_max_hp", -1))
			_check("recovery.percent_max_hp 在 1-100（占位值，run 内恒定）",
				rpct >= 1 and rpct <= 100, "实际 %d" % rpct)
			_eq("recovery.declinable == true（可拒绝，背水流）",
				bool(rrec.get("declinable", false)), true)

	# ── 2. ActConfig：解析 + 顶层字段 ───────────────────
	var cfg_parsed: Variant = _load_json(ACT_CONFIG_FILE)
	_check("act1_config.json 可解析且为 Dictionary", cfg_parsed is Dictionary,
		"解析结果类型 %s" % type_string(typeof(cfg_parsed)))
	if not (cfg_parsed is Dictionary):
		_finish()
		return
	var cfg: Dictionary = cfg_parsed

	_eq("act == 1", int(cfg.get("act", -1)), 1)
	_eq("stage_count == 8", int(cfg.get("stage_count", -1)), 8)
	_eq("boss_stage == 8（Boss 固定末关）", int(cfg.get("boss_stage", -1)), 8)

	# ── 3. Boss 固定包 ──────────────────────────────────
	var boss_v: Variant = cfg.get("boss")
	_check("boss 为 Dictionary", boss_v is Dictionary)
	if boss_v is Dictionary:
		var boss: Dictionary = boss_v
		var boss_map: String = str(boss.get("map_id", ""))
		_check("boss.map_id 对应地图存在 (%s)" % boss_map,
			FileAccess.file_exists(MAPS_DIR + "/" + boss_map + ".json"))
		_check("boss.enemy_config 非空", str(boss.get("enemy_config", "")) != "")
		var breward_v: Variant = boss.get("reward")
		_check("boss.reward 为 Dictionary", breward_v is Dictionary)
		if breward_v is Dictionary:
			var breward: Dictionary = breward_v
			var bfixed_v: Variant = breward.get("fixed")
			_check("boss.reward.fixed 含 gold+exp",
				bfixed_v is Dictionary and (bfixed_v as Dictionary).has("gold")
				and (bfixed_v as Dictionary).has("exp"))
			var pkg_v: Variant = breward.get("package")
			_check("boss.reward.package 为非空 Array",
				pkg_v is Array and not (pkg_v as Array).is_empty())
			if pkg_v is Array:
				var pkg_kinds: Array[String] = []
				for drop_v: Variant in (pkg_v as Array):
					var kind: String = str((drop_v as Dictionary).get("kind", "")) \
						if drop_v is Dictionary else "<非字典>"
					_check("Boss 包 RewardDrop.kind 合法 (%s)" % kind,
						REWARD_KINDS.has(kind) and not FORBIDDEN_KINDS.has(kind))
					pkg_kinds.append(kind)
				for need: String in BOSS_PACKAGE_KINDS:
					_check("Boss 固定包含 %s" % need, pkg_kinds.has(need))

	# ── 4. 幕级配置不再含恢复（2026-07-03 挪 run 级） ────
	_check("ActConfig 不含 recovery 字段（已挪 run_config.json）",
		not cfg.has("recovery"))

	# ── 5. DoorGenConfig ────────────────────────────────
	var dg_v: Variant = cfg.get("door_gen")
	_check("door_gen 为 Dictionary", dg_v is Dictionary)
	if not (dg_v is Dictionary):
		_finish()
		return
	var dg: Dictionary = dg_v

	# 门数范围
	var dc_v: Variant = dg.get("door_count")
	_check("door_count 为 Dictionary", dc_v is Dictionary)
	if dc_v is Dictionary:
		var dc_min: int = int((dc_v as Dictionary).get("min", -1))
		var dc_max: int = int((dc_v as Dictionary).get("max", -1))
		_check("door_count 2 <= min <= max <= 3（下限暂定 2，2026-07-03 裁决）",
			dc_min >= 2 and dc_min <= dc_max and dc_max <= 3,
			"min=%d max=%d" % [dc_min, dc_max])

	# 六类门权重
	var tw_v: Variant = dg.get("type_weights")
	_check("type_weights 为 Dictionary", tw_v is Dictionary)
	if tw_v is Dictionary:
		var tw: Dictionary = tw_v
		for door_type: String in DOOR_TYPES:
			var w: int = int(tw.get(door_type, -1))
			_check("type_weights 含 %s 且权重 > 0" % door_type, w > 0, "权重 %d" % w)
		for key_v: Variant in tw.keys():
			var key: String = str(key_v)
			if key.begins_with("_"):
				continue
			_check("type_weights 键 %s 在五类门枚举内（无 shop）" % key, DOOR_TYPES.has(key))
			_check("type_weights 无禁用类型 (%s)" % key, not FORBIDDEN_KINDS.has(key))

	_check("elite_room_weight > 0", int(dg.get("elite_room_weight", -1)) > 0)

	# 生成约束
	var cons_v: Variant = dg.get("constraints")
	_check("constraints 为 Dictionary", cons_v is Dictionary)
	if cons_v is Dictionary:
		var cons: Dictionary = cons_v
		_eq("约束：事件门不得连续 [已定]",
			bool(cons.get("events_non_consecutive", false)), true)
		_eq("约束：同组门类型互不相同 [提案]",
			bool(cons.get("same_offer_types_distinct", false)), true)
		_check("旧约束 shop_not_counted_as_stage 已移除（商店退出门池，2026-07-03）",
			not cons.has("shop_not_counted_as_stage"))

	# 保底（2026-07-03：按出现计数）
	var pity_v: Variant = dg.get("pity")
	_check("pity 为 Dictionary", pity_v is Dictionary)
	if pity_v is Dictionary:
		var pity: Dictionary = pity_v
		_check("pity.relic_drought_stages > 0（遗物保底占位）",
			int(pity.get("relic_drought_stages", -1)) > 0)
		_eq("pity.count_by == appearance（按出现计数 [已定]）",
			str(pity.get("count_by", "")), "appearance")

	# 固定商店插入（2026-07-03：幕中 + Boss 前，不占门不占关）
	var shops_v: Variant = dg.get("fixed_shops")
	_check("fixed_shops 为 Dictionary", shops_v is Dictionary)
	if shops_v is Dictionary:
		var shops: Dictionary = shops_v
		var mid: int = int(shops.get("mid_act_after_stage", -1))
		_check("fixed_shops.mid_act_after_stage 在 1-7（幕中定位占位）",
			mid >= 1 and mid <= 7, "实际 %d" % mid)
		_eq("fixed_shops.pre_boss == true（Boss 前一次）",
			bool(shops.get("pre_boss", false)), true)

	# 资源池引用完整性
	var bp_v: Variant = dg.get("battle_pools")
	_check("battle_pools 为 Dictionary", bp_v is Dictionary)
	if bp_v is Dictionary:
		var bp: Dictionary = bp_v
		for pool_name: String in ["normal", "elite"]:
			var pool_v: Variant = bp.get(pool_name)
			_check("battle_pools.%s 为非空 Array" % pool_name,
				pool_v is Array and not (pool_v as Array).is_empty())
			if pool_v is Array:
				for wave_v: Variant in (pool_v as Array):
					_check("battle_pools.%s 条目非空字符串 (%s)" % [pool_name, str(wave_v)],
						wave_v is String and str(wave_v) != "")

	var mp_v: Variant = dg.get("map_pool")
	_check("map_pool 为非空 Array", mp_v is Array and not (mp_v as Array).is_empty())
	if mp_v is Array:
		for map_v: Variant in (mp_v as Array):
			var map_id: String = str(map_v)
			_check("map_pool 地图存在 (%s)" % map_id,
				FileAccess.file_exists(MAPS_DIR + "/" + map_id + ".json"))

	var ep_v: Variant = dg.get("event_pool")
	_check("event_pool 为非空 Array", ep_v is Array and not (ep_v as Array).is_empty())
	if ep_v is Array:
		for eid_v: Variant in (ep_v as Array):
			var eid: String = str(eid_v)
			_check("event_pool 事件存在于 data/events (%s)" % eid, event_ids.has(eid))

	var fr_v: Variant = dg.get("fixed_reward_per_stage")
	_check("fixed_reward_per_stage 含 gold+exp（每图固定结算）",
		fr_v is Dictionary and (fr_v as Dictionary).has("gold")
		and (fr_v as Dictionary).has("exp"))

	_check("party_size_bonus 为 Dictionary（不满4人补偿占位）",
		dg.get("party_size_bonus") is Dictionary)

	# ── 6. 新建数据层：波次 / 词条 / 遗物 / 装备 ────────────
	# （2026-07-04 接入 DataLoader 同批扩展；断言自行 FileAccess 读文件，
	#  与既有风格一致，不经 DataLoader。）
	_check_wave_references(cfg)   # a. 波次存在性升级：非空字符串 → 文件存在
	_check_wave_files()           # b. 波次 schema
	_check_affix_files()          # c. 词条 schema（base 4 + special 2）
	_check_relic_files()          # d. 遗物 schema（≥10）
	_check_equipment_files()      # e. 装备 schema（≥8）

	# ── 7. 升级/门奖励配置（2026-07-04 run 骨架扩展） ────────
	_check_progression(cfg)       # progression：升级阈值 + 天赋点
	_check_door_rewards(cfg)      # door_rewards：门奖励数额 + 品质权重

	# ── 8. 固定商店配置（2026-07-04 任务 #7：库存件数 + 按品质定价 + 回收比例） ──
	_check_shop(cfg)

	_finish()


# ── 事件 schema 校验 ─────────────────────────────────

func _validate_event(short: String, ev: Dictionary) -> void:
	_check("%s → id 非空" % short, str(ev.get("id", "")) != "")
	_check("%s → title 非空" % short, str(ev.get("title", "")) != "")
	_check("%s → description 非空" % short, str(ev.get("description", "")) != "")
	var choices_v: Variant = ev.get("choices")
	_check("%s → choices 为非空 Array" % short,
		choices_v is Array and not (choices_v as Array).is_empty())
	if not (choices_v is Array):
		return
	var choices: Array = choices_v
	var ci: int = 0
	for choice_v: Variant in choices:
		ci += 1
		var tag: String = "%s choice#%d" % [short, ci]
		if not (choice_v is Dictionary):
			_check("%s → 为 Dictionary" % tag, false)
			continue
		var choice: Dictionary = choice_v
		_check("%s → text 非空" % tag, str(choice.get("text", "")) != "")
		var outcomes_v: Variant = choice.get("outcomes")
		_check("%s → outcomes 为非空 Array" % tag,
			outcomes_v is Array and not (outcomes_v as Array).is_empty())
		if not (outcomes_v is Array):
			continue
		var oi: int = 0
		for outcome_v: Variant in (outcomes_v as Array):
			oi += 1
			var otag: String = "%s outcome#%d" % [tag, oi]
			if not (outcome_v is Dictionary):
				_check("%s → 为 Dictionary" % otag, false)
				continue
			var outcome: Dictionary = outcome_v
			var weight_v: Variant = outcome.get("weight")
			_check("%s → weight 为正数" % otag,
				(weight_v is float or weight_v is int) and float(weight_v) > 0.0,
				"weight=%s" % str(weight_v))
			var effects_v: Variant = outcome.get("effects")
			_check("%s → effects 为非空 Array" % otag,
				effects_v is Array and not (effects_v as Array).is_empty())
			if effects_v is Array:
				for eff_v: Variant in (effects_v as Array):
					_check("%s → effect 为含 type 的 Dictionary" % otag,
						eff_v is Dictionary
						and str((eff_v as Dictionary).get("type", "")) != "")
			_check("%s → description 非空" % otag,
				str(outcome.get("description", "")) != "")


# ── 新建数据层 schema 校验 ───────────────────────────

## a. 波次存在性升级：从「非空字符串」升级为「data/waves/<id>.json 文件存在」。
##    覆盖 7 个已知波次文件、battle_pools.normal/elite、boss.enemy_config、
##    以及 event_abandoned_mine 里 start_battle 的 enemy_config。
func _check_wave_references(cfg: Dictionary) -> void:
	# 逐一断言 7 个已知波次文件存在
	for wid: String in WAVE_FILES:
		_check("波次文件存在 (%s)" % wid,
			FileAccess.file_exists(WAVES_DIR + "/" + wid + ".json"))

	# battle_pools.normal/elite 引用的每个 waveId → 文件存在
	var dg_v: Variant = cfg.get("door_gen")
	if dg_v is Dictionary:
		var bp_v: Variant = (dg_v as Dictionary).get("battle_pools")
		if bp_v is Dictionary:
			for pool_name: String in ["normal", "elite"]:
				var pool_v: Variant = (bp_v as Dictionary).get(pool_name)
				if pool_v is Array:
					for wave_v: Variant in (pool_v as Array):
						var wid2: String = str(wave_v)
						_check("battle_pools.%s 波次文件存在 (%s)" % [pool_name, wid2],
							FileAccess.file_exists(WAVES_DIR + "/" + wid2 + ".json"))

	# boss.enemy_config → 波次文件存在
	var boss_v: Variant = cfg.get("boss")
	if boss_v is Dictionary:
		var boss_wave: String = str((boss_v as Dictionary).get("enemy_config", ""))
		_check("boss.enemy_config 波次文件存在 (%s)" % boss_wave,
			FileAccess.file_exists(WAVES_DIR + "/" + boss_wave + ".json"))

	# event_abandoned_mine 的 start_battle enemy_config → 波次文件存在
	var mine_v: Variant = _load_json(EVENT_MINE_FILE)
	_check("event_abandoned_mine 可解析", mine_v is Dictionary)
	if mine_v is Dictionary:
		var found_battle: bool = false
		var choices_v: Variant = (mine_v as Dictionary).get("choices")
		if choices_v is Array:
			for choice_v: Variant in (choices_v as Array):
				if not (choice_v is Dictionary):
					continue
				var outs_v: Variant = (choice_v as Dictionary).get("outcomes")
				if not (outs_v is Array):
					continue
				for out_v: Variant in (outs_v as Array):
					if not (out_v is Dictionary):
						continue
					var effs_v: Variant = (out_v as Dictionary).get("effects")
					if not (effs_v is Array):
						continue
					for eff_v: Variant in (effs_v as Array):
						if not (eff_v is Dictionary):
							continue
						if str((eff_v as Dictionary).get("type", "")) == "start_battle":
							found_battle = true
							var ec: String = str((eff_v as Dictionary).get("enemy_config", ""))
							_check("event_abandoned_mine start_battle 波次文件存在 (%s)" % ec,
								FileAccess.file_exists(WAVES_DIR + "/" + ec + ".json"))
		_check("event_abandoned_mine 含 start_battle 战斗结局", found_battle)


## b. 波次 schema：遍历 data/waves/*.json。
func _check_wave_files() -> void:
	var dir: DirAccess = DirAccess.open(WAVES_DIR)
	_check("data/waves 目录可打开", dir != null)
	if dir == null:
		return
	var count: int = 0
	for fname: String in dir.get_files():
		if not fname.ends_with(".json"):
			continue
		count += 1
		var wid: String = fname.get_basename()
		var parsed: Variant = _load_json(WAVES_DIR + "/" + fname)
		_check("波次 %s 可解析为 Dictionary" % fname, parsed is Dictionary)
		if not (parsed is Dictionary):
			continue
		var wave: Dictionary = parsed
		_eq("波次 %s → id 与文件名一致" % fname, str(wave.get("id", "")), wid)
		var enemies_v: Variant = wave.get("enemies")
		_check("波次 %s → enemies 为非空 Array" % fname,
			enemies_v is Array and not (enemies_v as Array).is_empty())
		if not (enemies_v is Array):
			continue
		var ei: int = 0
		for enemy_v: Variant in (enemies_v as Array):
			ei += 1
			var tag: String = "%s enemy#%d" % [wid, ei]
			if not (enemy_v is Dictionary):
				_check("%s → 为 Dictionary" % tag, false)
				continue
			var enemy: Dictionary = enemy_v
			_check("%s → class_id 非空字符串" % tag, str(enemy.get("class_id", "")) != "")
			# spawn_pos：2 元数组，x/y 在 0..7
			var sp_v: Variant = enemy.get("spawn_pos")
			var sp_ok: bool = sp_v is Array and (sp_v as Array).size() == 2
			_check("%s → spawn_pos 为 2 元数组" % tag, sp_ok, "实际 %s" % str(sp_v))
			if sp_ok:
				var sx: int = int((sp_v as Array)[0])
				var sy: int = int((sp_v as Array)[1])
				_check("%s → spawn_pos x/y 在 0..7 (%d,%d)" % [tag, sx, sy],
					sx >= 0 and sx <= 7 and sy >= 0 and sy <= 7)
			# tier
			var tier: String = str(enemy.get("tier", ""))
			_check("%s → tier 合法枚举 (%s)" % [tag, tier], ENEMY_TIERS.has(tier))
			# elite_chief 须含 special_affix 且能解析到文件
			if tier == "elite_chief":
				var sa: String = str(enemy.get("special_affix", ""))
				_check("%s → elite_chief 含 special_affix (%s)" % [tag, sa], sa != "")
				if sa != "":
					_check("%s → special_affix 文件存在 (%s)" % [tag, sa],
						_affix_file_exists(sa))
			# affixes（若有）→ 每个 id 能在 base|special 找到文件
			var af_v: Variant = enemy.get("affixes")
			if af_v is Array:
				for aid_v: Variant in (af_v as Array):
					var aid: String = str(aid_v)
					_check("%s → affix 文件存在 (%s)" % [tag, aid],
						_affix_file_exists(aid))
	_check("data/waves 至少 7 个 JSON（实际 %d）" % count, count >= 7)


## c. 词条 schema：base 4 + special 2；pool 与所在子目录一致。
func _check_affix_files() -> void:
	for aid: String in AFFIX_BASE_FILES:
		var path: String = AFFIX_BASE_DIR + "/" + aid + ".json"
		_check("词条 base 文件存在 (%s)" % aid, FileAccess.file_exists(path))
		_validate_affix_schema(path, aid, "base")
	for aid2: String in AFFIX_SPECIAL_FILES:
		var path2: String = AFFIX_SPECIAL_DIR + "/" + aid2 + ".json"
		_check("词条 special 文件存在 (%s)" % aid2, FileAccess.file_exists(path2))
		_validate_affix_schema(path2, aid2, "special")


func _validate_affix_schema(path: String, aid: String, expect_pool: String) -> void:
	var parsed: Variant = _load_json(path)
	_check("词条 %s 可解析为 Dictionary" % aid, parsed is Dictionary)
	if not (parsed is Dictionary):
		return
	var af: Dictionary = parsed
	_eq("词条 %s → id 与文件名一致" % aid, str(af.get("id", "")), aid)
	_check("词条 %s → name 非空" % aid, str(af.get("name", "")) != "")
	_check("词条 %s → type 非空" % aid, str(af.get("type", "")) != "")
	_check("词条 %s → is_passive 为 bool" % aid, typeof(af.get("is_passive")) == TYPE_BOOL)
	_eq("词条 %s → pool 与子目录一致（%s）" % [aid, expect_pool],
		str(af.get("pool", "")), expect_pool)


## d. 遗物 schema：data/relics/*.json 至少 10 个。
func _check_relic_files() -> void:
	var dir: DirAccess = DirAccess.open(RELICS_DIR)
	_check("data/relics 目录可打开", dir != null)
	if dir == null:
		return
	var count: int = 0
	for fname: String in dir.get_files():
		if not fname.ends_with(".json"):
			continue
		count += 1
		var rid: String = fname.get_basename()
		var parsed: Variant = _load_json(RELICS_DIR + "/" + fname)
		_check("遗物 %s 可解析为 Dictionary" % fname, parsed is Dictionary)
		if not (parsed is Dictionary):
			continue
		var relic: Dictionary = parsed
		_check("遗物 %s → id 非空" % rid, str(relic.get("id", "")) != "")
		_check("遗物 %s → name 非空" % rid, str(relic.get("name", "")) != "")
		var rar: String = str(relic.get("rarity", ""))
		_check("遗物 %s → rarity 合法 (%s)" % [rid, rar], RELIC_RARITIES.has(rar))
		var cat: String = str(relic.get("category", ""))
		_check("遗物 %s → category 合法 (%s)" % [rid, cat], RELIC_CATEGORIES.has(cat))
		_check("遗物 %s → effects 为数组" % rid, relic.get("effects") is Array)
	_check("data/relics 至少 10 个 JSON（实际 %d）" % count, count >= 10)


## e. 装备 schema：data/equipment/*.json 至少 8 个。
func _check_equipment_files() -> void:
	var dir: DirAccess = DirAccess.open(EQUIPMENT_DIR)
	_check("data/equipment 目录可打开", dir != null)
	if dir == null:
		return
	var count: int = 0
	for fname: String in dir.get_files():
		if not fname.ends_with(".json"):
			continue
		count += 1
		var eid: String = fname.get_basename()
		var parsed: Variant = _load_json(EQUIPMENT_DIR + "/" + fname)
		_check("装备 %s 可解析为 Dictionary" % fname, parsed is Dictionary)
		if not (parsed is Dictionary):
			continue
		var eq: Dictionary = parsed
		_check("装备 %s → id 非空" % eid, str(eq.get("id", "")) != "")
		_check("装备 %s → name 非空" % eid, str(eq.get("name", "")) != "")
		var slot: String = str(eq.get("slot", ""))
		_check("装备 %s → slot 合法 (%s)" % [eid, slot], EQUIP_SLOTS.has(slot))
		_check("装备 %s → tier 存在" % eid, eq.has("tier"))
		_check("装备 %s → rarity 非空" % eid, str(eq.get("rarity", "")) != "")
		_check("装备 %s → stats 为 Dictionary" % eid, eq.get("stats") is Dictionary)
	_check("data/equipment 至少 8 个 JSON（实际 %d）" % count, count >= 8)


func _affix_file_exists(aid: String) -> bool:
	return FileAccess.file_exists(AFFIX_BASE_DIR + "/" + aid + ".json") \
		or FileAccess.file_exists(AFFIX_SPECIAL_DIR + "/" + aid + ".json")


## 固定商店配置 schema（任务 #7）：库存件数 + 按品质定价 + 回收比例（数值占位，只校验类型/区间）。
func _check_shop(cfg: Dictionary) -> void:
	var shop_v: Variant = cfg.get("shop")
	_check("shop 为 Dictionary（固定商店配置占位）", shop_v is Dictionary)
	if not (shop_v is Dictionary):
		return
	var shop: Dictionary = shop_v
	_check("shop.stock_size > 0（库存件数占位）",
		int(shop.get("stock_size", -1)) > 0, "实际 %d" % int(shop.get("stock_size", -1)))
	# 按品质定价：非空、键在 rarity 枚举内、价格 > 0
	var pbr_v: Variant = shop.get("price_by_rarity")
	_check("shop.price_by_rarity 为 Dictionary", pbr_v is Dictionary)
	if pbr_v is Dictionary:
		var pbr: Dictionary = pbr_v
		_check("shop.price_by_rarity 非空", not pbr.is_empty())
		for rk_v: Variant in pbr.keys():
			var rk: String = str(rk_v)
			if rk.begins_with("_"):
				continue
			_check("shop.price_by_rarity 品质键 %s 在 rarity 枚举内" % rk, RELIC_RARITIES.has(rk))
			_check("shop.price_by_rarity.%s 价格 > 0" % rk, int(pbr[rk_v]) > 0,
				"价 %s" % str(pbr[rk_v]))
	# 回收比例：0 < sell_ratio <= 1
	var ratio: float = float(shop.get("sell_ratio", -1.0))
	_check("shop.sell_ratio 在 (0,1]（回收比例占位）",
		ratio > 0.0 and ratio <= 1.0, "实际 %s" % str(shop.get("sell_ratio")))


## 升级配置 schema（run 骨架用；数值为占位，只校验类型与合法区间）。
func _check_progression(cfg: Dictionary) -> void:
	var prog_v: Variant = cfg.get("progression")
	_check("progression 为 Dictionary（升级阈值+天赋点占位）", prog_v is Dictionary)
	if not (prog_v is Dictionary):
		return
	var prog: Dictionary = prog_v
	_check("progression.exp_threshold_base > 0（占位）",
		int(prog.get("exp_threshold_base", -1)) > 0,
		"实际 %d" % int(prog.get("exp_threshold_base", -1)))
	_check("progression.exp_threshold_growth >= 0（占位，1.0=平坦）",
		float(prog.get("exp_threshold_growth", -1.0)) >= 0.0,
		"实际 %s" % str(prog.get("exp_threshold_growth")))
	_check("progression.talent_point_per_level >= 1（升级得天赋点，占位）",
		int(prog.get("talent_point_per_level", -1)) >= 1,
		"实际 %d" % int(prog.get("talent_point_per_level", -1)))


## 门奖励配置 schema（数额+品质权重占位）。
func _check_door_rewards(cfg: Dictionary) -> void:
	var dr_v: Variant = cfg.get("door_rewards")
	_check("door_rewards 为 Dictionary（门奖励数额+品质权重占位）", dr_v is Dictionary)
	if not (dr_v is Dictionary):
		return
	var dr: Dictionary = dr_v
	_check("door_rewards.gold > 0（共享账本，占位）",
		int(dr.get("gold", -1)) > 0, "实际 %d" % int(dr.get("gold", -1)))
	_check("door_rewards.exp > 0（每角色，占位）",
		int(dr.get("exp", -1)) > 0, "实际 %d" % int(dr.get("exp", -1)))
	_check("door_rewards.relic_per_drop >= 1（每次掉落个数，占位）",
		int(dr.get("relic_per_drop", -1)) >= 1,
		"实际 %d" % int(dr.get("relic_per_drop", -1)))
	# 两组装备品质权重：键须在 rarity 枚举内、权重 > 0
	for wkey: String in ["equipment_rarity_weights", "elite_equipment_rarity_weights"]:
		var w_v: Variant = dr.get(wkey)
		_check("door_rewards.%s 为 Dictionary" % wkey, w_v is Dictionary)
		if w_v is Dictionary:
			var w: Dictionary = w_v
			_check("door_rewards.%s 非空" % wkey, not w.is_empty())
			for rk_v: Variant in w.keys():
				var rk: String = str(rk_v)
				if rk.begins_with("_"):
					continue
				_check("%s 品质键 %s 在 rarity 枚举内" % [wkey, rk], RELIC_RARITIES.has(rk))
				_check("%s.%s 权重 > 0" % [wkey, rk], float(w[rk_v]) > 0.0,
					"权重 %s" % str(w[rk_v]))


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


func _finish() -> void:
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  ✗ " + f)
	else:
		print("OK")
	quit(0 if _fail == 0 else 1)


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
