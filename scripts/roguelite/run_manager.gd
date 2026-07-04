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


# ── Prep v0：HP 跨关继承 / 恢复 / 运输队 / 情报 ────────────
# 真源：runloop-reward-map-proposal.md §5 恢复模型 + §7.5 Prep
#       + v0-implementation-plan.md。所有数值从 run_config / act_config 读，禁硬编码。

## 战斗结束后把存活玩家单位 HP 写回 party（磨损跨关继承）。
## survivors: [{ class_id:String, hp:int, max_hp:int }]（仅存活玩家单位，宿主从战斗视图采集）。
## 按 class_id 匹配（消耗一次，容重复 class_id）；同时回填 max_hp（真值，占位 max_hp 首次落地）。
## 未在 survivors 中出现的 party 成员视为本关战死 → hp=0（[占位] v0 无永久死亡，下关以 hp=1 入场）。
func writeback_party_hp(survivors: Array) -> void:
	if state == null:
		return
	var used: Array[bool] = []
	for _s: Variant in survivors:
		used.append(false)
	for i: int in range(state.party.size()):
		var member: Dictionary = state.party[i]
		var cid: String = str(member.get("class_id", ""))
		var matched: int = -1
		for j: int in range(survivors.size()):
			if used[j]:
				continue
			var sv_v: Variant = survivors[j]
			if sv_v is Dictionary and str((sv_v as Dictionary).get("class_id", "")) == cid:
				matched = j
				break
		if matched >= 0:
			used[matched] = true
			var sv: Dictionary = survivors[matched]
			member["hp"] = maxi(0, int(sv.get("hp", member.get("hp", 0))))
			var mh: int = int(sv.get("max_hp", 0))
			if mh > 0:
				member["max_hp"] = mh
		else:
			# 本关战死（或未参战）→ hp=0（[占位] 无永久死亡）
			member["hp"] = 0


## 恢复配置（run 内恒定，只随开局难度档；从 run_config.recovery 读）。
func _recovery_config() -> Dictionary:
	var r_v: Variant = _run_config.get("recovery")
	return r_v if r_v is Dictionary else {}


## 恢复百分比（percent_max_hp）。
func get_recovery_percent() -> float:
	return float(_recovery_config().get("percent_max_hp", 0))


## 是否可按角色拒绝恢复（背水流[提案]）。
func get_recovery_declinable() -> bool:
	return bool(_recovery_config().get("declinable", true))


## 单角色恢复量预览：roundi(max_hp * percent / 100)。max_hp 未回填(<=0)→0。
## run 内恒定：只依赖 percent 与该角色 max_hp，不随幕/关变。
func get_recovery_amount(member: Dictionary) -> int:
	var max_hp: int = int(member.get("max_hp", 0))
	if max_hp <= 0:
		return 0
	return roundi(float(max_hp) * get_recovery_percent() / 100.0)


## 应用恢复：accepts[i]==true 的角色 hp = min(max_hp, hp + 恢复量)；
## false 不恢复（背水流[提案]）。declinable=false 时忽略 accepts 强制全恢复。
func recover_party(accepts: Array) -> void:
	if state == null:
		return
	var declinable: bool = get_recovery_declinable()
	for i: int in range(state.party.size()):
		var member: Dictionary = state.party[i]
		var accept: bool = true
		if declinable and i < accepts.size():
			accept = bool(accepts[i])
		if not accept:
			continue
		var max_hp: int = int(member.get("max_hp", 0))
		if max_hp <= 0:
			continue
		var amount: int = get_recovery_amount(member)
		member["hp"] = mini(max_hp, int(member.get("hp", 0)) + amount)


## 运输队装备 → 角色槽（slot ∈ weapon|armor）。若该槽原有装备则退回运输队（守恒）。
## v0 效果不生效（equipment 未接 stats），仅数据交换 [占位]。返回是否成功。
func equip_from_convoy(member_index: int, convoy_index: int, slot: String) -> bool:
	if state == null or (slot != "weapon" and slot != "armor"):
		return false
	if member_index < 0 or member_index >= state.party.size():
		return false
	var convoy_eq: Array = state.convoy.get("equipment", [])
	if convoy_index < 0 or convoy_index >= convoy_eq.size():
		return false
	var member: Dictionary = state.party[member_index]
	var equip: Dictionary = member.get("equipment", {"weapon": "", "armor": ""})
	var incoming: String = str(convoy_eq[convoy_index])
	var current: String = str(equip.get(slot, ""))
	convoy_eq.remove_at(convoy_index)
	equip[slot] = incoming
	if current != "":
		convoy_eq.append(current)
	member["equipment"] = equip
	state.convoy["equipment"] = convoy_eq
	return true


## 角色槽装备 → 运输队（卸下）。空槽返回 false。
func unequip_to_convoy(member_index: int, slot: String) -> bool:
	if state == null or (slot != "weapon" and slot != "armor"):
		return false
	if member_index < 0 or member_index >= state.party.size():
		return false
	var member: Dictionary = state.party[member_index]
	var equip: Dictionary = member.get("equipment", {"weapon": "", "armor": ""})
	var current: String = str(equip.get(slot, ""))
	if current == "":
		return false
	var convoy_eq: Array = state.convoy.get("equipment", [])
	equip[slot] = ""
	convoy_eq.append(current)
	member["equipment"] = equip
	state.convoy["equipment"] = convoy_eq
	return true


## 运输队遗物 → 角色遗物槽（上限 RELIC_SLOT_MAX）。满槽返回 false。
func move_relic_to_member(member_index: int, convoy_index: int) -> bool:
	if state == null or member_index < 0 or member_index >= state.party.size():
		return false
	var convoy_relics: Array = state.convoy.get("relics", [])
	if convoy_index < 0 or convoy_index >= convoy_relics.size():
		return false
	var member: Dictionary = state.party[member_index]
	var member_relics: Array = member.get("relics", [])
	if member_relics.size() >= RunStateScript.RELIC_SLOT_MAX:
		return false
	var item: String = str(convoy_relics[convoy_index])
	convoy_relics.remove_at(convoy_index)
	member_relics.append(item)
	member["relics"] = member_relics
	state.convoy["relics"] = convoy_relics
	return true


## 角色遗物 → 运输队。越界返回 false。
func move_relic_to_convoy(member_index: int, relic_index: int) -> bool:
	if state == null or member_index < 0 or member_index >= state.party.size():
		return false
	var member: Dictionary = state.party[member_index]
	var member_relics: Array = member.get("relics", [])
	if relic_index < 0 or relic_index >= member_relics.size():
		return false
	var convoy_relics: Array = state.convoy.get("relics", [])
	var item: String = str(member_relics[relic_index])
	member_relics.remove_at(relic_index)
	convoy_relics.append(item)
	member["relics"] = member_relics
	state.convoy["relics"] = convoy_relics
	return true


## 查看情报（Prep 占位）：下一关（pending_battle）地图名 + 波次 + 是否精英/Boss +
## 特殊词条名（进房前可见；基础词条隐藏＝相性赌）。数据从 _data_pools 读。
## 返回 { map_id, map_name, wave_id, elite, is_boss, special_affix_id, special_affix_name }。
func get_prep_intel() -> Dictionary:
	var out: Dictionary = {
		"map_id": "", "map_name": "", "wave_id": "",
		"elite": false, "is_boss": false,
		"special_affix_id": "", "special_affix_name": "",
	}
	if state == null:
		return out
	var battle: Dictionary = state.pending_battle if state.pending_battle is Dictionary else {}
	var map_id: String = str(battle.get("map_id", ""))
	var wave_id: String = str(battle.get("enemy_config", ""))
	out["map_id"] = map_id
	out["wave_id"] = wave_id
	var maps: Dictionary = _data_pools.get("maps") if _data_pools.get("maps") is Dictionary else {}
	var map_data: Dictionary = maps.get(map_id, {}) if maps.get(map_id) is Dictionary else {}
	out["map_name"] = str(map_data.get("name", map_id))
	var door_v: Variant = state.current_entry_door
	if door_v is Dictionary:
		var door: Dictionary = door_v
		out["elite"] = bool(door.get("elite_room", false))
		out["is_boss"] = str(door.get("reward_type", "")) == "boss"
		var preview_v: Variant = door.get("preview")
		if preview_v is Dictionary:
			var sa_v: Variant = (preview_v as Dictionary).get("special_affix", null)
			if sa_v != null and str(sa_v) != "":
				var sid: String = str(sa_v)
				out["special_affix_id"] = sid
				var affixes: Dictionary = _data_pools.get("affixes") if _data_pools.get("affixes") is Dictionary else {}
				var adef: Dictionary = affixes.get(sid, {}) if affixes.get(sid) is Dictionary else {}
				out["special_affix_name"] = str(adef.get("name", sid))
	return out


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
