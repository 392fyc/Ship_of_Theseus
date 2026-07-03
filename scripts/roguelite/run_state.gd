class_name RunState
extends RefCounted
## run-loop v0 运行时状态数据类（纯数据账本，无场景依赖）。
##
## 真源：KB run-loop.md 结算顺序 + runloop-reward-map-proposal.md §6/§7
##       + dev_doc/runloop-design/v0-implementation-plan.md。
##
## 设计约束：
##   - 本层是纯数据账本，绝不实例化 Unit、不调 UnitStats.level_up。
##     角色成长（按 level 应用成长曲线）在战斗 spawn 时另行处理，属后续任务。
##   - party 每角色独立持有等级 / 经验 / 天赋点 / 遗物 / 装备，实现「每角色独立掉落」。
##   - talent_points 顶层字段为「全队天赋点合计」镜像（升级时与角色 talent_points 同步累加）；
##     单角色 talent_points 为权威值，存于 party。
##   - gold 单一共享账本（顶层字段）。
##   - convoy = 运输队大背包，装备/遗物溢出（角色槽满或 v0 先入库）时暂存。
##   - relic_drought 遗物保底计数（按出现语义），由 DoorGenerator 跨关传递。
##
## 提供 to_dict / from_dict 便于测试与调试。所有字段显式类型。

const RELIC_SLOT_MAX: int = 6  # 每角色遗物槽上限（真源 KB：6 槽）

var difficulty: String = ""
var act: int = 1
var stage: int = 1
var gold: int = 0                       # 单一共享账本
var talent_points: int = 0              # 全队合计镜像（权威值在 party 各角色）
var party: Array[Dictionary] = []       # 每角色一份数据账本
var convoy: Dictionary = {}             # { "equipment": Array[String], "relics": Array[String] }
var relic_drought: int = 0
var last_choice_type: String = ""       # 上一关推进所选门的 reward_type（首关 ""）
var current_entry_door: Variant = null  # Dictionary|null：进入当前关所选的门
var current_battle: Dictionary = {}     # 当前关的 { "map_id":String, "enemy_config":String }
var pending_doors: Array[Dictionary] = []   # 待选门组（door_select 阶段）
var pending_next_door: Variant = null       # Dictionary|null：已选中、待出发的下一关门
var pending_battle: Dictionary = {}         # 已选中、待出发的下一关战斗
var phase: String = "battle"            # battle|door_select|prep|complete|failed


func _init() -> void:
	convoy = { "equipment": [], "relics": [] }


## 构造一个满配的角色账本条目（缺省字段补齐）。
static func new_member(class_id: String, level: int, max_hp: int) -> Dictionary:
	return {
		"class_id": class_id,
		"level": level,
		"exp": 0,
		"hp": max_hp,
		"max_hp": max_hp,
		"talent_points": 0,
		"relics": [],
		"equipment": { "weapon": "", "armor": "" },
	}


## 把外部传入的 roster 条目规整为满配账本（缺省补齐，不破坏已有字段）。
static func normalize_member(raw: Dictionary) -> Dictionary:
	var class_id: String = str(raw.get("class_id", ""))
	var level: int = int(raw.get("level", 1))
	var max_hp: int = int(raw.get("max_hp", 1))
	var member: Dictionary = new_member(class_id, level, max_hp)
	if raw.has("exp"):
		member["exp"] = int(raw.get("exp"))
	if raw.has("hp"):
		member["hp"] = int(raw.get("hp"))
	if raw.has("talent_points"):
		member["talent_points"] = int(raw.get("talent_points"))
	if raw.has("relics") and raw.get("relics") is Array:
		var relics: Array[String] = []
		for r: Variant in (raw.get("relics") as Array):
			relics.append(str(r))
		member["relics"] = relics
	if raw.has("equipment") and raw.get("equipment") is Dictionary:
		var eq: Dictionary = raw.get("equipment")
		member["equipment"] = {
			"weapon": str(eq.get("weapon", "")),
			"armor": str(eq.get("armor", "")),
		}
	return member


func to_dict() -> Dictionary:
	return {
		"difficulty": difficulty,
		"act": act,
		"stage": stage,
		"gold": gold,
		"talent_points": talent_points,
		"party": party.duplicate(true),
		"convoy": convoy.duplicate(true),
		"relic_drought": relic_drought,
		"last_choice_type": last_choice_type,
		"current_entry_door": current_entry_door,
		"current_battle": current_battle.duplicate(true),
		"pending_doors": pending_doors.duplicate(true),
		"pending_next_door": pending_next_door,
		"pending_battle": pending_battle.duplicate(true),
		"phase": phase,
	}


## 注：用 load(SELF).new() 自实例化（不用 class_name 标识符），
## 以便 headless --script 依赖编译期（全局 class 缓存未建）也能解析。
static func from_dict(d: Dictionary) -> RefCounted:
	var s: Object = load("res://scripts/roguelite/run_state.gd").new()
	s.difficulty = str(d.get("difficulty", ""))
	s.act = int(d.get("act", 1))
	s.stage = int(d.get("stage", 1))
	s.gold = int(d.get("gold", 0))
	s.talent_points = int(d.get("talent_points", 0))
	var party_in: Array[Dictionary] = []
	if d.get("party") is Array:
		for m: Variant in (d.get("party") as Array):
			if m is Dictionary:
				party_in.append((m as Dictionary).duplicate(true))
	s.party = party_in
	if d.get("convoy") is Dictionary:
		s.convoy = (d.get("convoy") as Dictionary).duplicate(true)
	s.relic_drought = int(d.get("relic_drought", 0))
	s.last_choice_type = str(d.get("last_choice_type", ""))
	s.current_entry_door = d.get("current_entry_door")
	if d.get("current_battle") is Dictionary:
		s.current_battle = (d.get("current_battle") as Dictionary).duplicate(true)
	var pending_in: Array[Dictionary] = []
	if d.get("pending_doors") is Array:
		for door_v: Variant in (d.get("pending_doors") as Array):
			if door_v is Dictionary:
				pending_in.append((door_v as Dictionary).duplicate(true))
	s.pending_doors = pending_in
	s.pending_next_door = d.get("pending_next_door")
	if d.get("pending_battle") is Dictionary:
		s.pending_battle = (d.get("pending_battle") as Dictionary).duplicate(true)
	s.phase = str(d.get("phase", "battle"))
	return s
