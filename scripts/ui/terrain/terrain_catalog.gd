extends RefCounted
## 地图创作外观合同；不改变 Cell 的玩法、移动或状态规则。

const PATH := "res://assets/prototype/battlefield_courtyard/terrain_catalog.json"
const MIN_MAP_SIDE := 10
const MAX_MAP_SIDE := 25

static func catalog() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PATH)) as Dictionary


static func pair_rule(a: int, b: int) -> Dictionary:
	var key := "%d:%d" % [mini(a, b), maxi(a, b)]
	return (catalog().get("pairs", {}) as Dictionary).get(key,
		{"allowed": false, "kind": "undefined", "reason": "没有登记该地形组合。"})


static func transition_style(a: int, b: int, source: Dictionary = {}) -> Dictionary:
	var data := catalog() if source.is_empty() else source
	var rule: Dictionary = data["pairs"]["%d:%d" % [mini(a, b), maxi(a, b)]]
	var style: Dictionary = data["transition_defaults"].duplicate(true)
	style.merge(data["transition_styles"].get(rule["kind"], {}), true)
	style.merge(rule.get("style", {}), true)
	return style


static func validate_map(data: Dictionary) -> Array[Dictionary]:
	var errors := validate_layout(data)
	if not errors.is_empty():
		return errors
	var width := int(data["width"])
	if width != int(data["height"]) or width < MIN_MAP_SIDE:
		return [{"cell": [], "neighbor": [], "reason": "地图须为正方形，边长为 %d 至 %d 格。" % [MIN_MAP_SIDE, MAX_MAP_SIDE]}]
	return []


## 地形片段的通用检查，供边角素材测试使用；创作、导入和试战使用 validate_map。
static func validate_layout(data: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	var rows: Variant = data.get("terrain")
	var width_value: Variant = data.get("width")
	var height_value: Variant = data.get("height")
	if not _integer(width_value) or not _integer(height_value):
		return [{"cell": [], "neighbor": [], "reason": "地图宽高必须为整数。"}]
	var width := int(width_value)
	var height := int(height_value)
	if width < 1 or width > MAX_MAP_SIDE or height < 1 or height > MAX_MAP_SIDE or not rows is Array or rows.size() != height:
		return [{"cell": [], "neighbor": [], "reason": "地形数据须完整，行列数不得超过 %d。" % MAX_MAP_SIDE}]
	for y: int in height:
		if not rows[y] is Array or rows[y].size() != width:
			return [{"cell": [], "neighbor": [], "reason": "地形行列数与地图尺寸不符。"}]
		for x: int in width:
			if not _integer(rows[y][x]) or int(rows[y][x]) < 0 or int(rows[y][x]) > 8:
				return [{"cell": [x, y], "neighbor": [], "reason": "地形必须是已登记的九种类型。"}]
	var pairs: Dictionary = catalog()["pairs"]
	for y: int in height:
		for x: int in width:
			for step: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i(1, 1), Vector2i(-1, 1)]:
				var n := Vector2i(x, y) + step
				if n.x < 0 or n.x >= width or n.y >= height:
					continue
				var a := int(rows[y][x])
				var b := int(rows[n.y][n.x])
				var rule: Dictionary = pairs["%d:%d" % [mini(a, b), maxi(a, b)]]
				if not bool(rule["allowed"]):
					errors.append({"cell": [x, y], "neighbor": [n.x, n.y], "reason": str(rule["reason"])})
	var paving: Variant = data.get("paving", [])
	if not paving is Array:
		errors.append({"cell": [], "neighbor": [], "reason": "铺路列表格式错误。"})
	else:
		var occupied_paving: Dictionary = {}
		for at: Variant in paving:
			if not at is Array or at.size() != 2 or not _integer(at[0]) or not _integer(at[1]) or int(at[0]) < 0 or int(at[0]) >= width or int(at[1]) < 0 or int(at[1]) >= height:
				errors.append({"cell": [], "neighbor": [], "reason": "铺路坐标越界或格式错误。"})
			elif int(rows[int(at[1])][int(at[0])]) != 0:
				errors.append({"cell": at, "neighbor": [], "reason": "石板路只作为平原外观。"})
			else:
				var key := "%d,%d" % [int(at[0]), int(at[1])]
				if occupied_paving.has(key):
					errors.append({"cell": at, "neighbor": [], "reason": "铺路坐标重复。"})
				occupied_paving[key] = true
	var variants: Variant = data.get("terrain_variants", {})
	if not variants is Dictionary:
		errors.append({"cell": [], "neighbor": [], "reason": "外观变体格式错误。"})
	else:
		var types: Dictionary = catalog()["terrains"]
		for key: Variant in variants:
			var parts: PackedStringArray = str(key).split(",")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
				errors.append({"cell": [], "neighbor": [], "reason": "外观变体坐标格式错误。"})
				continue
			var x := int(parts[0])
			var y := int(parts[1])
			if str(key) != "%d,%d" % [x, y]:
				errors.append({"cell": [x, y], "neighbor": [], "reason": "外观坐标须为规范的 x,y 整数字符串。"})
				continue
			if x < 0 or y < 0 or x >= width or y >= height:
				errors.append({"cell": [x, y], "neighbor": [], "reason": "外观变体坐标越界。"})
			elif not str(variants[key]) in types[str(int(rows[y][x]))]["variants"]:
				errors.append({"cell": [x, y], "neighbor": [], "reason": "此外观不属于该地形。"})
	return errors


static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value))
