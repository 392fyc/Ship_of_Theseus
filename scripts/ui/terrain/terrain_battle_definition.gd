extends RefCounted
## 将地形创作数据转换为可执行的试战配置；不写全局注册表或角色规则。

const Catalog := preload("res://scripts/ui/terrain/terrain_catalog.gd")
const PRESET_PATH := "res://data/battlefields/terrain_workshop_test.json"


static func build(source: Dictionary) -> Dictionary:
	var errors := Catalog.validate_map(source)
	if not errors.is_empty():
		return {"ok": false, "message": str(errors[0]["reason"]), "map": {}}
	var preset_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PRESET_PATH))
	if not preset_value is Dictionary:
		return {"ok": false, "message": "试战配置无法读取。", "map": {}}
	var preset: Dictionary = preset_value
	if preset.get("placement", "") != "largest_connected_passable_region":
		return {"ok": false, "message": "试战配置使用了尚未支持的出生点选择方式。", "map": {}}
	var player_id := str(preset.get("player_class_id", ""))
	var enemy_id := str(preset.get("enemy_class_id", ""))
	var tree := Engine.get_main_loop() as SceneTree
	var data_loader: Variant = tree.root.get_node_or_null("DataLoader") if tree != null else null
	if data_loader == null or not data_loader.classes.has(player_id) or not data_loader.enemies.has(enemy_id):
		return {"ok": false, "message": "试战所需的职业或敌人数据缺失。", "map": {}}
	# 地形工作台只消费这些字段；文件不能注入特殊地形规则、职业数值或外部资源路径。
	var map: Dictionary = {"id": "terrain_workshop_session", "name": "自定义地图试战",
		"description": "沿用当前地图 · 基础剑士与枪兵 · 返回后继续编辑",
		"environment": "terrain_workshop", "transition_preview": true,
		"paving": [], "terrain_variants": {}}
	for key: String in ["width", "height", "terrain", "paving", "terrain_variants"]:
		if source.has(key):
			var value: Variant = source[key]
			map[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	var grid := Grid.new()
	grid.initialize(map)
	var visited: Dictionary = {}
	var largest: Array[Vector2i] = []
	for y: int in grid.height:
		for x: int in grid.width:
			var at := Vector2i(x, y)
			if visited.has(at) or not grid.get_cell(at).is_passable():
				continue
			var component := _component(grid, at, visited)
			if component.size() > largest.size():
				largest = component
	if largest.size() < 2:
		return {"ok": false, "message": "至少需要两格互相连通的可通行地形，才能放置双方试战单位。", "map": {}}
	var player := largest[0]
	var enemy := largest[largest.size() - 1]
	# 广度优先遍历末项是该起点的最远层；相同地图总是选择相同出生点。
	map["player_units"] = [{"class_id": player_id, "position": [player.x, player.y]}]
	map["enemy_units"] = [{"class_id": enemy_id, "position": [enemy.x, enemy.y]}]
	return {"ok": true, "message": "", "map": map}


static func _component(grid: Grid, start: Vector2i, visited: Dictionary) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	var cursor := 0
	while cursor < queue.size():
		var at := queue[cursor]
		cursor += 1
		for next: Vector2i in grid.get_neighbors(at):
			if not visited.has(next) and grid.get_cell(next).is_passable():
				visited[next] = true
				queue.append(next)
	return queue
