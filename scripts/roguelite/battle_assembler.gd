class_name BattleAssembler
extends RefCounted
## v0 战斗装配器（纯逻辑，无场景依赖，headless 可测）。
##
## 把「地图 player_spawns + 波次 enemies(含词条)」组装成一份可供运行时（TacticalManager）
## 消费的部署清单：玩家单位站位 + 敌人单位站位/tier/词条/数值增强(stat_scale)。
##
## 敌人词条来自波次数据（data/waves 的 enemy entry），非敌人 class JSON：
##   { class_id, spawn_pos:[x,y], tier, affixes:[id], special_affix:id, stat_scale:float }
## 运输到运行时后，spawn_unit(class_id,...) 之后对该 unit 调 apply_affixes 注入。
##
## 容错：缺波次 / 缺地图 → 返回空清单，不崩。


## 组装战斗部署清单。
## map_id       : data_pools.maps 的键（读 player_spawns）。
## wave_id      : data_pools.waves 的键（读 enemies）。
## player_roster: 玩家成员列表，元素可为 {class_id/id, level} 字典或纯 class_id 字符串。
## data_pools   : { "maps": DataLoader.maps, "waves": DataLoader.waves }。
## 返回         : { map_id, player_units:[{class_id,pos,level,hp?}], enemy_units:[{...}] }。
##                （player_units 的 hp 仅在成员磨损态时出现，见 _build_player_units）。
static func build(map_id: String, wave_id: String, player_roster: Array,
		data_pools: Dictionary) -> Dictionary:
	var maps: Dictionary = data_pools.get("maps", {})
	var waves: Dictionary = data_pools.get("waves", {})
	var map_data: Dictionary = maps.get(map_id, {})
	var wave_data: Dictionary = waves.get(wave_id, {})

	return {
		"map_id": map_id,
		"player_units": _build_player_units(map_data, player_roster),
		"enemy_units": _build_enemy_units(wave_data),
	}


## 从波次数据构造敌人部署清单（含词条字段，缺省容错）。
static func _build_enemy_units(wave_data: Dictionary) -> Array:
	var out: Array = []
	var enemies: Array = wave_data.get("enemies", [])
	for entry_v: Variant in enemies:
		if not (entry_v is Dictionary):
			continue
		var entry: Dictionary = entry_v
		var affixes_typed: Array[String] = []
		for a: Variant in entry.get("affixes", []):
			affixes_typed.append(str(a))
		out.append({
			"class_id": str(entry.get("class_id", "")),
			"pos": _to_vec2i(entry.get("spawn_pos", [0, 0])),
			"tier": str(entry.get("tier", "normal")),
			"affixes": affixes_typed,
			"special_affix": entry.get("special_affix", null),
			"stat_scale": float(entry.get("stat_scale", 1.0)),
		})
	return out


## 给 player_roster 每个成员分配站位（用地图 player_spawns）。
## 缺地图 / 地图无 player_spawns → 返回空清单（容错，不崩）。
## HP 跨关继承（磨损模型 #8）：仅当成员处于「已知磨损」态才带 hp 字段——
##   max_hp>0（真值已回填）且 0<=hp<max_hp。满血 / 未回填占位（hp==max_hp）不带 hp，
##   注入层据缺省满血 spawn。首关 party 为占位（hp==max_hp），不带 hp → 满血入场。
static func _build_player_units(map_data: Dictionary, player_roster: Array) -> Array:
	var out: Array = []
	var spawns: Array = map_data.get("player_spawns", [])
	if spawns.is_empty():
		return out
	for i: int in range(player_roster.size()):
		var member_v: Variant = player_roster[i]
		var class_id: String = ""
		var level: int = 1
		var hp: int = -1
		var max_hp: int = -1
		if member_v is Dictionary:
			var member: Dictionary = member_v
			class_id = str(member.get("class_id", member.get("id", "")))
			level = int(member.get("level", 1))
			hp = int(member.get("hp", -1))
			max_hp = int(member.get("max_hp", -1))
		else:
			class_id = str(member_v)
		var entry: Dictionary = {
			"class_id": class_id,
			"pos": _assign_player_pos(spawns, i),
			"level": level,
		}
		# 仅磨损态（含战死 hp=0）带 hp；满血 / 未回填占位不带 → 注入层满血 spawn。
		if max_hp > 0 and hp >= 0 and hp < max_hp:
			entry["hp"] = hp
		out.append(entry)
	return out


## 分配玩家站位：roster ≤ spawns 时按序取；超出时从末位向右相邻错位兜底 [占位]。
static func _assign_player_pos(spawns: Array, index: int) -> Vector2i:
	if spawns.is_empty():
		# [占位] 无 spawn 数据兜底：沿 x 轴依次排开。
		return Vector2i(index, 0)
	if index < spawns.size():
		return _to_vec2i(spawns[index])
	# [占位] roster 超出 spawn 数：从最后一个 spawn 向右相邻错位偏移。
	var last: Vector2i = _to_vec2i(spawns[spawns.size() - 1])
	var overflow: int = index - spawns.size() + 1
	return Vector2i(last.x + overflow, last.y)


## 把 [x,y] 数组 / Vector2i 归一为 Vector2i；非法输入 → Vector2i.ZERO。
static func _to_vec2i(v: Variant) -> Vector2i:
	if v is Vector2i:
		return v
	if v is Array and (v as Array).size() >= 2:
		var arr: Array = v
		return Vector2i(int(arr[0]), int(arr[1]))
	return Vector2i.ZERO
