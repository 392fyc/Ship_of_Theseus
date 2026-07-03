class_name RunManager
extends RefCounted
## run-loop v0 一幕 × 8 关状态机（非 autoload，由 RunScene 持有）。
##
## 真源：KB run-loop.md:74-79 结算顺序 + runloop-reward-map-proposal.md §6/§7
##       + dev_doc/runloop-design/v0-implementation-plan.md。
##
## 关卡与门的关系【真源】：
##   - 8 关：stage 1 = 起点（无门直接进入、无门奖励，只有固定结算）；
##           stage 8 = 固定 Boss（无门选、无掷门，用 Boss 固定包）。
##   - 门为「下一关」掷：stage N(1..6) 打完 → 为 stage N+1 掷门组 → 玩家选 → 进 N+1。
##   - stage 7 打完 → 不掷门 → 直接进 stage 8 (Boss)。
##   - 门组仅为 stage 2..7 生成（共 6 次选门）。
##   - 某关门奖励 = 进入该关时所选门的 reward_type（stage 1 无；stage 8 用 Boss 固定包）。
##   - 事件门（reward_type=="event"）：进入后走事件流程（本任务留钩子，不结算门奖励）。
##
## 结算顺序（每关战斗胜利后）：
##   1) 固定 Gold + EXP 结算（EXP 可能升级 → 天赋点）
##   2) 门奖励（每角色独立）结算；Boss 关用 Boss 固定包
##   3) 门选择：从 2-3 扇门选下一关（reward type 前置可见）
##   4) 进 Prep（Prep/商店为后续任务，本任务留 enter_prep/confirm_departure 钩子占位）
##
## 设计约束：纯逻辑（RefCounted，无场景依赖）；所有数值从配置读；信号 past-tense。

const RunStateScript: GDScript = preload("res://scripts/roguelite/run_state.gd")
const RewardResolverScript: GDScript = preload("res://scripts/roguelite/reward_resolver.gd")
const DoorGeneratorScript: GDScript = preload("res://scripts/roguelite/door_generator.gd")

## past-tense 信号（供 UI 订阅）
signal doors_generated(doors: Array)
signal reward_settled(summary: Dictionary)
signal stage_advanced(stage: int)
signal run_completed()
signal run_failed()

# 注：state/生成器/结算器静态类型用 Object（非 class_name），以便 headless
# --script 依赖编译期（全局 class 缓存未建）也能解析；成员动态访问、实例经 preload 常量创建。
var state: Object = null
var _door_generator: Object = null
var _reward_resolver: Object = null
var _rng: RandomNumberGenerator = null
var _act_config: Dictionary = {}
var _run_config: Dictionary = {}
var _data_pools: Dictionary = {}   # { equipment, relics, waves, maps, events }
var _boss_stage: int = 8
var _stage_count: int = 8


func _init() -> void:
	_door_generator = DoorGeneratorScript.new()
	_reward_resolver = RewardResolverScript.new()


## 初始化 run：建 RunState(stage=1)、规整队伍、定 stage1 战斗、phase="battle"。
func start_run(run_config: Dictionary, act_config: Dictionary,
		data_pools: Dictionary, party_roster: Array, rng: RandomNumberGenerator) -> void:
	_run_config = run_config
	_act_config = act_config
	_data_pools = data_pools
	_rng = rng
	_stage_count = int(act_config.get("stage_count", 8))
	_boss_stage = int(act_config.get("boss_stage", 8))

	state = RunStateScript.new()
	state.difficulty = str(run_config.get("difficulty", ""))
	state.act = int(act_config.get("act", 1))
	state.stage = 1
	state.gold = 0
	state.talent_points = 0
	state.relic_drought = 0
	state.last_choice_type = ""
	state.current_entry_door = null  # stage 1 无 entry door
	var roster: Array[Dictionary] = []
	for raw_v: Variant in party_roster:
		if raw_v is Dictionary:
			roster.append(RunStateScript.normalize_member(raw_v))
	state.party = roster
	# stage 1 战斗 [占位]：从普通池随机
	state.current_battle = _random_normal_battle()
	state.phase = "battle"


## 战斗结算入口：result ∈ "victory"|"defeat"（其余视为失败）。
func on_battle_resolved(result: String) -> void:
	if state == null:
		return
	# 仅在战斗阶段结算：防在 door_select/prep/complete/failed 阶段被误调导致重复结算（账本翻倍）
	if state.phase != "battle":
		return
	if result != "victory":
		state.phase = "failed"
		run_failed.emit()
		return

	var summary: Dictionary = {
		"stage": state.stage,
		"sequence": [],
	}

	# 1) 固定结算（每关都发）
	var fixed_summary: Dictionary = _reward_resolver.settle_fixed(state, _act_config)
	summary["fixed"] = fixed_summary
	(summary["sequence"] as Array).append("fixed")

	# 2) 门奖励 / Boss 固定包
	if state.stage == _boss_stage:
		var boss_reward: Dictionary = _boss_reward()
		var boss_summary: Dictionary = _reward_resolver.settle_boss_package(
			state, boss_reward, _data_pools, _rng, _act_config)
		summary["boss"] = boss_summary
		(summary["sequence"] as Array).append("boss")
	elif state.current_entry_door != null:
		var door: Dictionary = state.current_entry_door
		var reward_type: String = str(door.get("reward_type", ""))
		if reward_type != "event":
			var elite_room: bool = bool(door.get("elite_room", false))
			var door_summary: Dictionary = _reward_resolver.settle_door_reward(
				state, reward_type, elite_room, _data_pools, _rng, _act_config)
			summary["door"] = door_summary
			(summary["sequence"] as Array).append("door")
		else:
			# 事件门 entry：门奖励不在此结算（走事件流程钩子，v0 占位）
			summary["door_event_hook"] = true

	summary["gold_after"] = state.gold
	reward_settled.emit(summary)

	# 3) 推进 / 结束
	if state.stage == _boss_stage:
		state.phase = "complete"
		run_completed.emit()
		return

	var next_stage: int = state.stage + 1
	if next_stage == _boss_stage:
		# 下一关是 Boss：不掷门，直接备 Boss 战斗进 Prep
		_prepare_boss()
	else:
		# 为 next_stage 掷门组
		_generate_doors()


## 玩家从门组选一扇门（index），据其定下一关战斗，进 Prep。
func choose_door(index: int) -> void:
	if state == null or state.phase != "door_select":
		return
	if index < 0 or index >= state.pending_doors.size():
		return
	var door: Dictionary = state.pending_doors[index]
	state.pending_next_door = door
	state.current_entry_door = door  # 进入下一关所依据的门
	state.last_choice_type = str(door.get("reward_type", ""))
	# 事件门 → 走事件流程钩子（v0 占位，无战斗）
	var battle_v: Variant = door.get("battle")
	state.pending_battle = battle_v if battle_v is Dictionary else {}
	state.phase = "prep"


## Prep 阶段进入钩子（占位：恢复 / 运输队 / 情报为后续任务）。
func enter_prep() -> void:
	if state == null:
		return
	if state.phase != "prep":
		state.phase = "prep"


## 确认出发：stage += 1，装载战斗，phase="battle"，发 stage_advanced。
func confirm_departure() -> void:
	if state == null or state.phase != "prep":
		return
	state.stage += 1
	state.current_battle = state.pending_battle.duplicate(true)
	var empty_doors: Array[Dictionary] = []  # 显式类型：pending_doors 为 Array[Dictionary]
	state.pending_doors = empty_doors
	state.pending_battle = {}
	state.phase = "battle"
	stage_advanced.emit(state.stage)


func is_boss_stage() -> bool:
	return state != null and state.stage == _boss_stage


func is_run_complete() -> bool:
	return state != null and state.phase == "complete"


func is_run_failed() -> bool:
	return state != null and state.phase == "failed"


func get_state() -> Object:
	return state


# ── 内部 ─────────────────────────────────────────────

## 为 state.stage+1 掷门组（更新 relic_drought：按出现跨关传递），进 door_select。
func _generate_doors() -> void:
	var door_gen: Dictionary = _door_gen_config()
	var waves: Dictionary = _data_pools.get("waves") if _data_pools.get("waves") is Dictionary else {}
	var ctx: Dictionary = {
		"last_choice_type": state.last_choice_type,
		"relic_drought": state.relic_drought,
	}
	var gen: Dictionary = _door_generator.generate_group(door_gen, ctx, waves, _rng)
	state.relic_drought = int(gen.get("relic_drought_after", state.relic_drought))
	state.pending_doors = _to_dict_array(gen.get("doors", []))
	state.phase = "door_select"
	doors_generated.emit(state.pending_doors)


## 备 Boss 战斗（不掷门），进 Prep。current_entry_door 记 Boss 标记。
func _prepare_boss() -> void:
	var boss: Dictionary = _boss_config()
	var boss_battle: Dictionary = {
		"map_id": str(boss.get("map_id", "")),
		"enemy_config": str(boss.get("enemy_config", "")),
	}
	var marker: Dictionary = {
		"reward_type": "boss",
		"elite_room": false,
		"battle": boss_battle,
		"is_boss": true,
	}
	state.pending_next_door = marker
	state.current_entry_door = marker
	state.pending_battle = boss_battle
	state.phase = "prep"


## stage1 战斗 [占位]：普通池随机 map+wave。
func _random_normal_battle() -> Dictionary:
	var door_gen: Dictionary = _door_gen_config()
	var map_pool: Array[String] = _string_array(door_gen.get("map_pool"))
	var normal_pool: Array[String] = []
	var bp_v: Variant = door_gen.get("battle_pools")
	if bp_v is Dictionary:
		normal_pool = _string_array((bp_v as Dictionary).get("normal"))
	return {
		"map_id": _pick(map_pool),
		"enemy_config": _pick(normal_pool),
	}


func _door_gen_config() -> Dictionary:
	var dg_v: Variant = _act_config.get("door_gen")
	return dg_v if dg_v is Dictionary else {}


func _boss_config() -> Dictionary:
	var b_v: Variant = _act_config.get("boss")
	return b_v if b_v is Dictionary else {}


func _boss_reward() -> Dictionary:
	var r_v: Variant = _boss_config().get("reward")
	return r_v if r_v is Dictionary else {}


func _pick(arr: Array[String]) -> String:
	if arr.is_empty():
		return ""
	return arr[_rng.randi_range(0, arr.size() - 1)]


func _to_dict_array(a: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if a is Array:
		for e: Variant in (a as Array):
			if e is Dictionary:
				out.append(e)
	return out


func _string_array(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if v is Array:
		for item: Variant in (v as Array):
			out.append(str(item))
	return out
