extends Node2D
## 逻辑格只决定地形；地表、建筑、林木和水面分别构成可交互的场景。

const TerrainSurface := preload("res://scripts/ui/terrain/terrain_surface.gd")
const TerrainCatalog := preload("res://scripts/ui/terrain/terrain_catalog.gd")

var grid: Grid
var profile: Dictionary = {}
var layout_data: Dictionary = {}
var grid_visible: bool = true
var graybox: bool = false
var _ground: Texture2D
var _meadow: Texture2D
var _moss: Texture2D
var _water: Texture2D
var _masonry: Texture2D
var _coping: Texture2D
var _rock: Texture2D
var _surface_layer: Polygon2D
var _detail_layer: Node2D
var _relief_material: ShaderMaterial
var _rubble: AtlasTexture
var _entry: AtlasTexture
var _tree: AtlasTexture
var _shrub: AtlasTexture
var _props: Array[Dictionary] = []
var _paved: Dictionary = {}
var _architecture: Dictionary = {}
var _architecture_walls: Dictionary = {}
var _transition_cache: Array[Dictionary] = []
var _terrain_catalog: Dictionary = {}
var _water_surface_meshes: Dictionary = {}
var _hover_cell := Vector2i(-1, -1)
var _unit_positions: Array[Vector2] = []
var _highlight_positions: Array[Vector2] = []
var _time: float = 0.0
var _actor_layer: Node2D
var _footing_visual_cache: Dictionary = {}


func configure(value: Grid, visual_profile: Dictionary, layout: Dictionary = {}) -> void:
	grid = value
	_footing_visual_cache.clear()
	profile = visual_profile
	layout_data = layout
	_terrain_catalog = TerrainCatalog.catalog()
	_paved.clear()
	_architecture_walls.clear()
	_water_surface_meshes.clear()
	_ground = load(str(profile["ground"])) as Texture2D
	_meadow = load(str(profile["meadow"])) as Texture2D
	_moss = load(str(profile["moss"])) as Texture2D
	_water = load(str(profile["water"])) as Texture2D
	_masonry = load(str(profile["masonry"])) as Texture2D
	_coping = load(str(profile.get("coping", profile["ground"]))) as Texture2D
	_rock = load(str(profile.get("rock", profile["ground"]))) as Texture2D
	_rubble = _atlas(profile["rubble"])
	_entry = _atlas(profile["entry"])
	_tree = _atlas(profile["tree"])
	_shrub = _atlas(profile["shrub"])
	for cell: Array in layout_data.get("paving", []):
		_paved[Vector2i(cell[0], cell[1])] = true
	_architecture = layout_data.get("architecture", {})
	var wall_segments: Array = _architecture.get("walls", []).duplicate()
	wall_segments.append_array(layout_data.get("environment_walls", []))
	for wall: Dictionary in wall_segments:
		var start := Vector2i(wall["from"][0], wall["from"][1])
		var end := Vector2i(wall["to"][0], wall["to"][1])
		var direction := Vector2i(signi(end.x - start.x), signi(end.y - start.y))
		for step: int in maxi(absi(end.x - start.x), absi(end.y - start.y)) + 1:
			var cell: Vector2i = start + direction * step
			_architecture_walls[cell] = {"height": float(wall["height"])}
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	queue_redraw()


func _ready() -> void:
	_actor_layer = get_parent().get_node_or_null("UnitLayer") as Node2D
	if _actor_layer == null:
		_actor_layer = Node2D.new()
		_actor_layer.y_sort_enabled = true
		add_child(_actor_layer)
	refresh_terrain_visuals()


func refresh_terrain_visuals() -> void:
	_footing_visual_cache.clear()
	for spec: Dictionary in _props:
		var old_node: Node2D = spec["node"]
		if is_instance_valid(old_node):
			old_node.hide()
			old_node.queue_free()
	_props.clear()
	_water_surface_meshes.clear()
	_rebuild_transition_cache()
	if is_instance_valid(_surface_layer):
		_surface_layer.free()
	_surface_layer = TerrainSurface.make_surface(self, TerrainSurface.make_material(self))
	add_child(_surface_layer)
	if not is_instance_valid(_detail_layer):
		_detail_layer = Node2D.new()
		_detail_layer.name = "TerrainDetails"
		add_child(_detail_layer)
		_detail_layer.draw.connect(_draw_details)
	move_child(_detail_layer, -1)
	if _actor_layer != null and _actor_layer.get_parent() == self:
		move_child(_actor_layer, -1)
	_relief_material = TerrainSurface.make_material(self, true)
	if _actor_layer != null:
		_build_environment_props()
		_build_board_props()
	queue_redraw()
	if is_instance_valid(_detail_layer):
		_detail_layer.queue_redraw()


func _exit_tree() -> void:
	for spec: Dictionary in _props:
		var node: Node = spec["node"]
		if is_instance_valid(node):
			node.queue_free()
	_props.clear()


func update_visibility_context(hover_cell: Vector2i, unit_positions: Array[Vector2], highlight_positions: Array[Vector2] = []) -> void:
	_hover_cell = hover_cell
	_unit_positions = unit_positions
	_highlight_positions = highlight_positions


func _process(delta: float) -> void:
	_time += delta
	if is_instance_valid(_surface_layer):
		_surface_layer.visible = not graybox
	for spec: Dictionary in _props:
		var node: Node2D = spec["node"]
		if not is_instance_valid(node):
			continue
		var r10_grooves: Array = spec.get("r10_grooves", [])
		if not r10_grooves.is_empty():
			var r10_context: Dictionary = spec["r10_context"]
			var r10_cache: Dictionary = spec["r10_cache"]
			_update_r10_pillar_grooves(node, r10_grooves, r10_context, r10_cache)
		node.visible = not graybox
		var covered: bool = false
		var bounds: Rect2 = spec["bounds"]
		if grid.is_valid(_hover_cell):
			var hover_world: Vector2 = grid.grid_to_world(_hover_cell)
			covered = hover_world.y <= node.position.y and bounds.has_point(hover_world - node.position + Vector2(0, -10))
		for unit_world: Vector2 in _unit_positions:
			var unit_pos: Vector2 = _actor_layer.to_local(unit_world)
			var unit_rect := Rect2(unit_pos - node.position + Vector2(-24, -44), Vector2(48, 64))
			if unit_pos.y <= node.position.y and bounds.intersects(unit_rect):
				covered = true
		var range_covered: bool = false
		for highlight_world: Vector2 in _highlight_positions:
			var highlight_pos: Vector2 = _actor_layer.to_local(highlight_world)
			if highlight_pos.y <= node.position.y and bounds.grow(4.0).has_point(highlight_pos - node.position):
				range_covered = true
				break
		# 行动范围适度淡化；单位与悬停格更透明，移开后平滑恢复。
		var target_alpha: float = 0.18 if covered else (0.32 if range_covered else 1.0)
		node.modulate.a = target_alpha if node.modulate.a > target_alpha else lerpf(node.modulate.a, target_alpha, minf(delta * 10.0, 1.0))
		if bool(spec.get("wind", false)):
			node.rotation = sin(_time * 1.25 + node.position.x * 0.03) * 0.009
	queue_redraw()
	if is_instance_valid(_detail_layer):
		_detail_layer.queue_redraw()


func _prop_tint(key: String, fallback: Color) -> Color:
	var tints: Dictionary = profile.get("prop_tints", {})
	var rgba: Array = tints.get(key, [])
	if rgba.size() != 4:
		return fallback
	# RGB 可超过 1 以提亮道具；alpha 仍独立保留。
	return Color(float(rgba[0]), float(rgba[1]), float(rgba[2]), float(rgba[3]))


func _atlas(spec: Dictionary) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = load(str(spec["texture"])) as Texture2D
	var region: Array = spec["region"]
	texture.region = Rect2(region[0], region[1], region[2], region[3])
	texture.filter_clip = true
	return texture


func point(x: float, y: float) -> Vector2:
	return grid.grid_to_world(Vector2i.ZERO) + Vector2((x - y) * 32.0, (x + y) * 16.0)


func diamond(cell: Vector2i, inset: float = 0.0) -> PackedVector2Array:
	var p: Vector2 = grid.grid_to_world(cell)
	return PackedVector2Array([p + Vector2(0, -16 + inset * 0.5),
		p + Vector2(32 - inset, 0), p + Vector2(0, 16 - inset * 0.5), p + Vector2(-32 + inset, 0)])


func _quad(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([point(x0, y0), point(x1, y0), point(x1, y1), point(x0, y1)])


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = points.duplicate()
	result.append(result[0])
	return result


func _surface(x0: float, y0: float, x1: float, y1: float, texture: Texture2D, tint: Color, scale_uv: float = 8.0) -> void:
	var uv := PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])
	for i: int in uv.size():
		uv[i] /= scale_uv
	draw_colored_polygon(_quad(x0, y0, x1, y1), tint, uv, texture)


func _draw() -> void:
	if grid == null or _ground == null:
		return
	if not graybox:
		_draw_landscape()
	for y: int in grid.height:
		for x: int in grid.width:
			_draw_cell_surface(Vector2i(x, y))
	if not graybox:
		_draw_terrain_transitions()


func _draw_details() -> void:
	if grid == null:
		return
	if not graybox:
		_draw_wall_footings(_detail_layer)
	if grid_visible or graybox:
		for y: int in grid.height:
			for x: int in grid.width:
				_detail_layer.draw_polyline(_closed(diamond(Vector2i(x, y))), Color(str(profile["grid_color"])), 0.55, true)
		# 边界仅在格线模式显示，不把环境切成有装饰边框的菱形底板。
		_detail_layer.draw_polyline(_closed(_quad(-0.5, -0.5, grid.width - 0.5, grid.height - 0.5)),
			Color(str(profile["boundary_color"])), 0.7, true)
		for y: int in grid.height:
			for x: int in grid.width:
				var pos := Vector2i(x, y)
				if grid.get_cell(pos).terrain in [Cell.Terrain.WALL, Cell.Terrain.PEAK, Cell.Terrain.DEEP_WATER]:
					_draw_blocked_corners(pos, _detail_layer)


func _draw_landscape() -> void:
	var environment: String = str(layout_data.get("environment", "overgrown"))
	# 地表由统一混合层绘制，水体位于其下，格线与墙脚位于其上。
	for y: int in range(-1, grid.height + 1):
		for x: int in range(-1, grid.width + 1):
			var pos := Vector2i(x, y)
			if not grid.is_valid(pos) and _near_water(pos):
				draw_mesh(_water_surface_mesh(pos), _water)
	if bool(layout_data.get("transition_preview", false)):
		return
	if environment == "flooded":
		# 场外水面逐列延续边缘地形；宽度、深浅和材质均共用场内定义。
		_draw_channel_extension()


func _draw_cell_surface(pos: Vector2i) -> void:
	var terrain: int = grid.get_cell(pos).terrain
	if graybox:
		var colors: Dictionary = {0: "777d5d", 1: "405a40", 2: "8c856d", 3: "5e5d57", 4: "777166", 5: "478391", 6: "163e51", 7: "a64f26", 8: "4c6244"}
		draw_colored_polygon(diamond(pos), Color(str(colors.get(terrain, "777d5d"))))
		return
	# 地表混合层覆盖水底；岸内外均有底色，透明接壤不会透出背景。
	if terrain in [Cell.Terrain.SHALLOW_WATER, Cell.Terrain.DEEP_WATER]:
		_draw_water_surface(pos)
	else:
		draw_mesh(_water_surface_mesh(pos), _water)


## 深度仅用于外观。共享坐标的顶点取同一个值，格边和转角不会各自叠加色带。
func _water_depth_at(at: Vector2) -> float:
	var base := Vector2i(floori(at.x), floori(at.y))
	var total_weight: float = 0.0
	var weighted_depth: float = 0.0
	# 三次 B 样条把周边深度连接为缓坡。小孤格只形成柔和低洼，连续深区才达到最深色。
	for y: int in range(-1, 3):
		for x: int in range(-1, 3):
			var sample_at := base + Vector2i(x, y)
			var terrain: int = visual_water_terrain(sample_at)
			if terrain not in [Cell.Terrain.SHALLOW_WATER, Cell.Terrain.DEEP_WATER]:
				continue
			var weight: float = _depth_kernel(at.x - sample_at.x) * _depth_kernel(at.y - sample_at.y)
			total_weight += weight
			weighted_depth += weight if terrain == Cell.Terrain.DEEP_WATER else 0.0
	return weighted_depth / total_weight if total_weight > 0.0 else 0.0


func _depth_kernel(distance: float) -> float:
	var d: float = absf(distance)
	if d < 1.0:
		return (4.0 - 6.0 * d * d + 3.0 * d * d * d) / 6.0
	if d < 2.0:
		return pow(2.0 - d, 3.0) / 6.0
	return 0.0


func _water_surface_mesh(pos: Vector2i) -> ArrayMesh:
	if _water_surface_meshes.has(pos):
		return _water_surface_meshes[pos] as ArrayMesh
	var settings: Dictionary = profile.get("water_surface", {})
	var subdivisions: int = maxi(2, int(settings.get("subdivisions_per_cell", 8)))
	var shallow := Color(str(settings.get("shallow_tint", "89b9be")))
	var deep := Color(str(settings.get("deep_tint", "234f62")))
	var vertices := PackedVector2Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for y: int in subdivisions + 1:
		for x: int in subdivisions + 1:
			var at := Vector2(pos) - Vector2.ONE * 0.5 + Vector2(x, y) / float(subdivisions)
			vertices.append(point(at.x, at.y))
			uv.append(at / 8.0)
			colors.append(shallow.lerp(deep, _water_depth_at(at)))
	for y: int in subdivisions:
		for x: int in subdivisions:
			var first: int = y * (subdivisions + 1) + x
			var next: int = first + subdivisions + 1
			indices.append_array(PackedInt32Array([first, first + 1, next + 1, first, next + 1, next]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_water_surface_meshes[pos] = mesh
	return mesh


func _draw_water_surface(pos: Vector2i, ripple: bool = true) -> void:
	draw_mesh(_water_surface_mesh(pos), _water)
	if ripple:
		_draw_ripple(point(pos.x, pos.y), float(pos.x * 7 + pos.y * 3),
			visual_water_terrain(pos) == Cell.Terrain.DEEP_WATER)


## 仅供场景外观延伸；不注册格子，也不参与寻路或通行规则。
func visual_water_terrain(pos: Vector2i) -> int:
	if grid.is_valid(pos):
		return grid.get_cell(pos).terrain
	if str(layout_data.get("environment", "")) != "flooded" or pos.x < 0 or pos.x >= grid.width:
		return Cell.Terrain.PLAIN
	# 上游桥道占据两个场外行，水陆接缝跟随桥道两端。
	if pos.y in [-3, -2]:
		return Cell.Terrain.PLAIN
	var edge: Cell = grid.get_cell(Vector2i(pos.x, clampi(pos.y, 0, grid.height - 1)))
	return edge.terrain if edge.terrain in [Cell.Terrain.SHALLOW_WATER, Cell.Terrain.DEEP_WATER] else Cell.Terrain.PLAIN


func visual_terrain_at(pos: Vector2i) -> int:
	if grid.is_valid(pos):
		return grid.get_cell(pos).terrain
	if _architecture_walls.has(pos):
		return Cell.Terrain.WALL
	return visual_water_terrain(pos)


func _is_paved_at(pos: Vector2i) -> bool:
	if grid.is_valid(pos):
		if grid.get_cell(pos).terrain == Cell.Terrain.PLAIN:
			var variant: String = str(layout_data.get("terrain_variants", {}).get("%d,%d" % [pos.x, pos.y], ""))
			if variant in ["meadow", "paving"]:
				return variant == "paving"
		return _paved.has(pos)
	if not _architecture.is_empty():
		var areas: Array = _architecture.get("rooms", []).duplicate()
		areas.append({"floor": _architecture["corridor"]})
		for area: Dictionary in areas:
			var rect: Array = area["floor"]
			if pos.x >= rect[0] and pos.x <= rect[2] and pos.y >= rect[1] and pos.y <= rect[3]:
				return true
	if str(layout_data.get("environment", "")) == "flooded":
		return pos.x in [0, 6] or pos.y in [-3, -2]
	if str(layout_data.get("environment", "")) == "overgrown":
		return pos.x in [2, 3] or pos.y == 4 or (pos.y >= -5 and pos.y <= -2 and pos.x >= -6 and pos.x <= 11) or (pos.x >= -6 and pos.x <= -2 and pos.y >= -1 and pos.y <= 12)
	return false


## 每条边由一侧负责绘制，连续同类地形不会产生重复岸沿或接缝。
func transition_edges(pos: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var offsets: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var own: int = visual_terrain_at(pos)
	for edge: int in 4:
		var other_pos: Vector2i = pos + offsets[edge]
		var other: int = visual_terrain_at(other_pos)
		var kind: String = "continuous"
		if own in [Cell.Terrain.SHALLOW_WATER, Cell.Terrain.DEEP_WATER]:
			if other in [Cell.Terrain.SHALLOW_WATER, Cell.Terrain.DEEP_WATER]:
				if own == Cell.Terrain.SHALLOW_WATER and other == Cell.Terrain.DEEP_WATER:
					kind = "depth_blend"
			else:
				kind = "stone_bank" if other == Cell.Terrain.WALL or _is_paved_at(other_pos) else "earth_bank"
		elif own == Cell.Terrain.WALL:
			if other == Cell.Terrain.WALL:
				kind = "wall_join"
			elif other in [Cell.Terrain.SHALLOW_WATER, Cell.Terrain.DEEP_WATER]:
				kind = "wet_wall_foot"
			elif other == Cell.Terrain.FOREST:
				kind = "rooted_wall_foot"
			else:
				kind = "stone_wall_foot" if _is_paved_at(other_pos) else "soil_wall_foot"
		elif own == Cell.Terrain.FOREST and other == Cell.Terrain.PLAIN:
			kind = "forest_fringe"
		elif own == Cell.Terrain.PLAIN and other == Cell.Terrain.PLAIN and _is_paved_at(pos) and not _is_paved_at(other_pos):
			kind = "paving_edge"
		var rule: Dictionary = _terrain_catalog["pairs"]["%d:%d" % [mini(own, other), maxi(own, other)]]
		if kind == "continuous" and own != other and not (own == Cell.Terrain.DEEP_WATER and other == Cell.Terrain.SHALLOW_WATER):
			kind = str(rule["kind"])
		result.append({"cell": pos, "edge": edge, "kind": kind, "neighbor": other_pos,
			"allowed": bool(rule["allowed"]), "pair_kind": str(rule["kind"])})
	return result


func _rebuild_transition_cache() -> void:
	_transition_cache.clear()
	var minimum := Vector2i(-1, -1)
	var maximum := Vector2i(grid.width, grid.height)
	if str(layout_data.get("environment", "")) == "flooded":
		minimum.y = -24
		maximum.y = 28
	for pos: Vector2i in _architecture_walls:
		minimum = minimum.min(pos - Vector2i.ONE)
		maximum = maximum.max(pos + Vector2i.ONE)
	for y: int in range(minimum.y, maximum.y + 1):
		for x: int in range(minimum.x, maximum.x + 1):
			for transition: Dictionary in transition_edges(Vector2i(x, y)):
				if transition["kind"] in ["stone_bank", "earth_bank", "depth_blend", "forest_fringe", "paving_edge"]:
					_transition_cache.append(transition)


func _draw_channel_extension() -> void:
	for y: int in range(-24, 29):
		if y >= 0 and y < grid.height:
			continue
		for x: int in range(-1, grid.width + 1):
			var terrain: int = visual_water_terrain(Vector2i(x, y))
			if terrain not in [Cell.Terrain.SHALLOW_WATER, Cell.Terrain.DEEP_WATER]:
				if _near_water(Vector2i(x, y)):
					draw_mesh(_water_surface_mesh(Vector2i(x, y)), _water)
				continue
			_draw_water_surface(Vector2i(x, y), (x + y) % 3 == 0 and y >= -12 and y <= 18)


func _near_water(pos: Vector2i) -> bool:
	for y: int in range(-1, 2):
		for x: int in range(-1, 2):
			if visual_terrain_at(pos + Vector2i(x, y)) in [Cell.Terrain.SHALLOW_WATER, Cell.Terrain.DEEP_WATER]:
				return true
	return false


func _draw_terrain_transitions() -> void:
	# 接壤由 TerrainSurface 统一处理。保留此入口供同一检查器注入历史坏样本。
	pass


func _draw_bank_edge(a: Vector2, b: Vector2, inward: Vector2, stone: bool) -> void:
	if stone:
		# 铺石自身延续到水边；只叠加接触处的湿暗，不用不透明色带覆盖水面。
		var contact := PackedVector2Array([a, b])
		for i: int in range(8, -1, -1):
			var p: Vector2 = a.lerp(b, float(i) / 8.0)
			var width: float = 0.65 + sin(p.x * 0.43 + p.y * 0.31) * 0.2
			contact.append(p + inward * width)
		draw_colored_polygon(contact, Color("06131655"))
		draw_colored_polygon(PackedVector2Array([a, b, b - inward * 1.5, a - inward * 1.5]), Color("07131028"))
	else:
		var land: Vector2 = -inward * 6.0
		_textured_ground_polygon(PackedVector2Array([a, b, b + land * 0.7,
			a.lerp(b, 0.5) + land, a + land * 0.8]), _moss, Color("939e7499"))
		# 世界坐标采样让相接边缘延续；湿土只在格边内数像素变化。
		var shore := PackedVector2Array()
		var wet_edge := PackedVector2Array()
		for i: int in 9:
			var p: Vector2 = a.lerp(b, float(i) / 8.0)
			var roughness: float = sin(p.x * 0.55 + p.y * 0.12) + sin(p.y * 0.67 - p.x * 0.21) * 0.5
			var soil: Vector2 = p + inward * (2.6 + roughness * 0.9)
			shore.append(soil)
			wet_edge.append(soil + inward * 1.1)
		var soil_band := PackedVector2Array([a, b])
		for i: int in range(shore.size() - 1, -1, -1):
			soil_band.append(shore[i])
		_textured_ground_polygon(soil_band, _moss, Color("939e74"))
		var wet_band: PackedVector2Array = shore.duplicate()
		for i: int in range(wet_edge.size() - 1, -1, -1):
			wet_band.append(wet_edge[i])
		_textured_ground_polygon(wet_band, _moss, Color("68766099"))


func _textured_ground_polygon(points: PackedVector2Array, texture: Texture2D, tint: Color, canvas: Node2D = null) -> void:
	if canvas == null:
		canvas = self
	var uv := PackedVector2Array()
	var origin: Vector2 = grid.grid_to_world(Vector2i.ZERO)
	for p: Vector2 in points:
		var relative: Vector2 = p - origin
		uv.append(Vector2((relative.x / 32.0 + relative.y / 16.0) * 0.5,
			(relative.y / 16.0 - relative.x / 32.0) * 0.5) / 8.0)
	canvas.draw_colored_polygon(points, tint, uv, texture)


func _draw_ripple(p: Vector2, phase: float, deep: bool) -> void:
	var progress: float = fposmod(_time * 0.23 + phase * 0.19, 1.0)
	var radius: float = 3.0 + progress * 9.0
	var color := Color("bad7cd")
	color.a = (1.0 - progress) * (0.24 if deep else 0.32)
	var arc := PackedVector2Array()
	for i: int in 13:
		var angle: float = float(i) / 12.0 * PI * 1.65
		arc.append(p + Vector2(cos(angle) * radius, sin(angle) * radius * 0.34))
	draw_polyline(arc, color, 0.65, true)


func _build_board_props() -> void:
	for y: int in range(-2, grid.height + 2):
		for x: int in range(-2, grid.width + 2):
			var pos := Vector2i(x, y)
			var terrain: int = visual_terrain_at(pos)
			var relief: MeshInstance2D = TerrainSurface.make_relief(self, pos, _relief_material)
			if relief != null:
				_actor_layer.add_child(relief)
				_props.append({"node": relief, "wind": false, "bounds": Rect2(-36, -86, 72, 105)})
			if terrain == Cell.Terrain.FOREST:
				var tree_node: Node2D = _add_sprite(_tree, profile["tree"], point(x, y), 0.91 + float((x * 3 + y) % 3) * 0.055,
					_prop_tint("tree", Color("dedac1")), true, (x + y) % 2 == 0)
				tree_node.set_meta("courtyard_cell", pos)
			elif terrain == Cell.Terrain.WALL:
				if _architecture_walls.has(pos):
					continue
				_add_wall_shape(pos)
				if visual_variant_at(pos) == "ruined" and wall_connection_mask(pos) in [0, 1, 2, 4, 8]:
					_add_sprite(_rubble, profile["rubble"], point(x + 0.12, y + 0.08), 0.35, _prop_tint("rubble", Color("acae97")))


func _is_wall(pos: Vector2i) -> bool:
	var cell: Cell = grid.get_cell(pos)
	return cell != null and cell.terrain == Cell.Terrain.WALL


func _build_environment_props() -> void:
	if bool(layout_data.get("transition_preview", false)):
		return
	_build_architecture_walls()
	var environment: String = str(layout_data.get("environment", "overgrown"))
	if environment == "flooded":
		# 两岸遗迹、上游桥梁与沿岸林带，共同限定庭园水道。
		_grove([Vector2(-2, 1), Vector2(-1.4, 4), Vector2(-2.1, 7), Vector2(-0.9, 9),
			Vector2(8.7, 1), Vector2(9.4, 4), Vector2(8.9, 7), Vector2(9.7, 9),
			Vector2(0.1, -4), Vector2(6.5, -4.2), Vector2(6.7, 10.5)], 1.35)
	elif environment == "passage":
		_grove([Vector2(-4.8, 0.8), Vector2(-4.4, 4), Vector2(-4.8, 7.5),
			Vector2(10.7, -2), Vector2(11.3, 2), Vector2(10.8, 7), Vector2(11.5, 10.5),
			Vector2(3.0, 11.0)], 1.4)
	else:
		# 废弃回廊位于后场，树林包围两侧及前景，入口道接入庭院主路。
		_add_sprite(_entry, profile["entry"], point(3.2, -3.35), 0.9, Color("ceccb8"))
		_grove([Vector2(8.6, -1.1), Vector2(9.4, 0.8), Vector2(8.8, 3), Vector2(10.1, 5),
			Vector2(9.2, 7.5), Vector2(8.4, 9.4), Vector2(6.3, 9.2), Vector2(4.4, 10.3),
			Vector2(1.1, 9.6), Vector2(-0.6, 8.2), Vector2(-1.1, 6.2), Vector2(-1.4, 3.5),
			Vector2(-1.3, -0.5), Vector2(-1.8, -2.6)], 1.4)
	# 近景树丛从画面边缘切入，形成空间前后关系；占格范围内不补装饰树。
	_grove([Vector2(-5, 9), Vector2(-3, 11), Vector2(11, 10), Vector2(12.5, 7)], 1.75)


func _draw_architecture_floors() -> void:
	var corridor: Array = _architecture["corridor"]
	_surface(corridor[0], corridor[1], corridor[2], corridor[3], _ground, Color("c4c1aa"))
	for room: Dictionary in _architecture["rooms"]:
		var r: Array = room["floor"]
		_surface(r[0], r[1], r[2], r[3], _ground, Color("b2b09a"))


func _wall_render_cells() -> Array[Vector2i]:
	var cells: Dictionary = {}
	for cell: Vector2i in _architecture_walls:
		if visual_terrain_at(cell) == Cell.Terrain.WALL:
			cells[cell] = true
	for y: int in grid.height:
		for x: int in grid.width:
			if _is_wall(Vector2i(x, y)):
				cells[Vector2i(x, y)] = true
	var result: Array[Vector2i] = []
	for cell: Vector2i in cells:
		result.append(cell)
	return result


func wall_connection_mask(pos: Vector2i) -> int:
	if visual_variant_at(pos) == "pillar":
		return 0
	var result: int = 0
	var offsets: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for i: int in 4:
		if visual_terrain_at(pos + offsets[i]) == Cell.Terrain.WALL and visual_variant_at(pos + offsets[i]) != "pillar":
			result |= 1 << i
	return result


## 中央墙体与四条连接臂共用一个轮廓，转角与分叉不会留出接缝。
func wall_footprint(pos: Vector2i) -> PackedVector2Array:
	var mask: int = wall_connection_mask(pos)
	var left: float = -0.5 if mask & 8 else -0.25
	var right: float = 0.5 if mask & 2 else 0.25
	var back: float = -0.5 if mask & 1 else -0.25
	var front: float = 0.5 if mask & 4 else 0.25
	var outline: Array[Vector2] = [Vector2(-0.25, back), Vector2(0.25, back),
		Vector2(0.25, -0.25), Vector2(right, -0.25), Vector2(right, 0.25),
		Vector2(0.25, 0.25), Vector2(0.25, front), Vector2(-0.25, front),
		Vector2(-0.25, 0.25), Vector2(left, 0.25), Vector2(left, -0.25), Vector2(-0.25, -0.25)]
	var result := PackedVector2Array()
	for p: Vector2 in outline:
		var world: Vector2 = point(pos.x + p.x, pos.y + p.y)
		if result.is_empty() or not result[-1].is_equal_approx(world):
			result.append(world)
	if result[0].is_equal_approx(result[-1]):
		result.remove_at(result.size() - 1)
	return result


func wall_footing_visuals() -> Dictionary:
	if not _footing_visual_cache.is_empty():
		return _footing_visual_cache
	var aprons: Array[Dictionary] = []
	var shadows: Array[PackedVector2Array] = []
	for cell: Vector2i in _wall_render_cells():
		var center: Vector2 = point(cell.x, cell.y)
		var base: PackedVector2Array = wall_footprint(cell)
		var texture: Texture2D = _ground
		var tint := Color("92957b")
		for transition: Dictionary in transition_edges(cell):
			if transition["kind"] == "wet_wall_foot":
				tint = Color("63786e")
				break
			if transition["kind"] in ["rooted_wall_foot", "soil_wall_foot"]:
				texture = _moss
				tint = Color("8c916c")
		var apron := PackedVector2Array()
		for p: Vector2 in base:
			apron.append(center + (p - center) * 1.18)
		tint.a = 0.42
		aprons.append({"polygon": apron, "texture": texture, "tint": tint})
		# 柱影贴着宽底座；墙影沿实际墙脚伸到地面一侧。
		var shadow_base: PackedVector2Array = base
		if visual_variant_at(cell) == "pillar":
			shadow_base = PackedVector2Array([center + Vector2(0, -9),
				center + Vector2(17, -1), center + Vector2(16, 4),
				center + Vector2(0, 11), center + Vector2(-16, 4), center + Vector2(-17, -1)])
		var shadow := PackedVector2Array()
		for p: Vector2 in shadow_base:
			shadow.append(center + (p - center) * 1.18 + Vector2(1.5, 2.0))
		shadows.append(shadow)
	_footing_visual_cache = {"aprons": aprons, "shadows": shadows,
		"shadow_color": _prop_tint("contact_shadow", Color(0.024, 0.031, 0.024, 0.5))}
	return _footing_visual_cache


func draw_wall_footing_visuals(canvas: Node2D, include_shadow: bool) -> void:
	var visuals: Dictionary = wall_footing_visuals()
	for apron: Dictionary in visuals["aprons"]:
		_textured_ground_polygon(apron["polygon"], apron["texture"], apron["tint"], canvas)
	if include_shadow:
		for shadow: PackedVector2Array in visuals["shadows"]:
			canvas.draw_colored_polygon(shadow, visuals["shadow_color"])


func _draw_wall_footings(canvas: Node2D = null) -> void:
	draw_wall_footing_visuals(self if canvas == null else canvas, true)


func _build_architecture_walls() -> void:
	for cell: Vector2i in _architecture_walls:
		if visual_terrain_at(cell) != Cell.Terrain.WALL:
			continue
		_add_wall_shape(cell)
		var mask: int = wall_connection_mask(cell)
		if mask in [1, 2, 4, 8]:
			_add_sprite(_rubble, profile["rubble"], point(cell.x + 0.10, cell.y + 0.10), 0.29, _prop_tint("environment_rubble", Color("b1b19a")))


func _grove(positions: Array, size_scale: float) -> void:
	for i: int in positions.size():
		var p: Vector2 = positions[i]
		_add_sprite(_tree, profile["tree"], point(p.x, p.y), size_scale + float(i % 3) * 0.13,
			_prop_tint("environment_tree", Color("a4b096")), true, i % 2 == 0)
		if i % 2 == 0:
			_add_sprite(_shrub, profile["shrub"], point(p.x + 0.45, p.y + 0.3), 0.9, _prop_tint("shrub", Color("a2b083")))


func _add_sprite(texture: Texture2D, spec: Dictionary, foot: Vector2, size_scale: float,
		tint: Color, wind: bool = false, mirrored: bool = false) -> Node2D:
	var root := Node2D.new()
	root.name = "CourtyardProp"
	root.position = foot
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = false
	var dims: Array = spec["display_size"]
	var anchor: Array = spec["foot_offset"]
	var displayed := Vector2(dims[0], dims[1]) * size_scale
	sprite.scale = displayed / texture.get_size()
	sprite.position = -Vector2(anchor[0], anchor[1]) * size_scale
	sprite.modulate = tint
	root.add_child(sprite)
	if mirrored:
		root.scale.x = -1.0
	_actor_layer.add_child(root)
	_props.append({"node": root, "wind": wind,
		"bounds": Rect2(Vector2(-displayed.x * 0.55, -displayed.y), Vector2(displayed.x * 1.1, displayed.y + 6))})
	return root


func _wall_height_at(cell: Vector2i) -> float:
	var height: float = float(_architecture_walls[cell]["height"]) if _architecture_walls.has(cell) else 25.0
	if visual_variant_at(cell) == "ruined":
		height *= 0.66 + 0.18 * (0.5 + 0.5 * sin(cell.x * 1.91 + cell.y * 2.34))
	return height


func visual_variant_at(cell: Vector2i) -> String:
	return str(layout_data.get("terrain_variants", {}).get("%d,%d" % [cell.x, cell.y], "ruined" if visual_terrain_at(cell) == Cell.Terrain.WALL else "rocky"))


func _wall_vertex_height(cell: Vector2i, vertex: Vector2) -> float:
	var height: float = _wall_height_at(cell)
	var local: Vector2 = vertex - point(cell.x, cell.y)
	var at := Vector2((local.x / 32.0 + local.y / 16.0) * 0.5,
		(local.y / 16.0 - local.x / 32.0) * 0.5)
	var offsets: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var ends: Array[bool] = [is_equal_approx(at.y, -0.5), is_equal_approx(at.x, 0.5),
		is_equal_approx(at.y, 0.5), is_equal_approx(at.x, -0.5)]
	for i: int in 4:
		var other: Vector2i = cell + offsets[i]
		if ends[i] and visual_terrain_at(other) == Cell.Terrain.WALL:
			return (height + _wall_height_at(other)) * 0.5
	return height


func _add_wall_shape(cell: Vector2i) -> void:
	if visual_variant_at(cell) == "pillar":
		_add_pillar(cell)
		return
	var foot: Vector2 = point(cell.x, cell.y)
	var base_world: PackedVector2Array = wall_footprint(cell)
	var connection_mask: int = wall_connection_mask(cell)
	var height: float = _wall_height_at(cell)
	var wall_variant: String = visual_variant_at(cell)
	var root := Node2D.new()
	root.name = "CourtyardWall"
	root.set_meta("terrain_wall", true)
	root.position = foot
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var base: PackedVector2Array = base_world.duplicate()
	for i: int in base.size():
		base[i] -= root.position
	var top: PackedVector2Array = base.duplicate()
	for i: int in top.size():
		# 相接端点使用同一个世界坐标采样，墙顶也随连接连续。
		var wear: float = sin(base_world[i].x * 0.075 + base_world[i].y * 0.11) * (2.5 if wall_variant == "ruined" else 0.35)
		top[i].y -= _wall_vertex_height(cell, base_world[i]) - wear
	# 只在外轮廓的角点压低顶线，接壤顶点保持共享高度。
	var chip_requested: bool = wall_variant == "ruined" or (wall_variant == "dressed" and posmod(cell.x * 3 + cell.y, 4) in [1, 3])
	var chip_vertex: int = -1
	if chip_requested:
		for i: int in base.size():
			var previous: int = (i + base.size() - 1) % base.size()
			var following: int = (i + 1) % base.size()
			if _is_join_edge(base[previous], base[i], connection_mask) or _is_join_edge(base[i], base[following], connection_mask):
				continue
			if chip_vertex < 0 or top[i].y < top[chip_vertex].y:
				chip_vertex = i
	if chip_vertex >= 0:
		var chipped_top: Vector2 = top[chip_vertex]
		chipped_top.y += 2.5
		top[chip_vertex] = chipped_top
	for edge: int in base.size():
		var next: int = (edge + 1) % base.size()
		if base[next].x >= base[edge].x or _is_join_edge(base[edge], base[next], connection_mask):
			continue
		var side_is_lit: bool = base[next].y > base[edge].y
		var side_tint: Color = _prop_tint("wall_lit_side", Color("aaa792")) if side_is_lit else _prop_tint("wall_dark_side", Color("7f8372"))
		_polygon(root, PackedVector2Array([top[edge], top[next], base[next], base[edge]]), side_tint, true, "wall_side")
		var dirt_a: Vector2 = base[edge].lerp(top[edge], 0.18)
		var dirt_b: Vector2 = base[next].lerp(top[next], 0.18)
		_polygon(root, PackedVector2Array([dirt_a, dirt_b, base[next], base[edge]]),
			_prop_tint("wall_foot_dirt", side_tint * Color(0.9, 0.9, 0.9, 1.0)), true, "wall_side")
		_add_wall_masonry_courses(root, edge, next, base, top, side_is_lit)
	_polygon(root, top, _prop_tint("wall_top", Color("b6b29b")), false, "wall_top")
	# 压顶上铺小块深浅风化斑；它们仍使用 R6 压顶纹理，不改墙体整体明度。
	var top_center := Vector2.ZERO
	for p: Vector2 in top:
		top_center += p
	top_center /= float(top.size())
	var weather_seed: int = absi(cell.x * 17 + cell.y * 29)
	for stain_index: int in 4:
		var stain_edge: int = posmod(weather_seed + stain_index * 3, top.size())
		var stain_next: int = (stain_edge + 1) % top.size()
		var outer_a: Vector2 = top[stain_edge].lerp(top_center, 0.08)
		var outer_b: Vector2 = top[stain_next].lerp(top_center, 0.08)
		var inner_a: Vector2 = top[stain_edge].lerp(top_center, 0.72)
		var inner_b: Vector2 = top[stain_next].lerp(top_center, 0.72)
		var stain_tint: Color = _prop_tint("wall_weather_dark", Color(0.48, 0.48, 0.49, 1.0)) if stain_index % 2 == 0 else _prop_tint("wall_weather_light", Color(0.77, 0.79, 0.84, 1.0))
		_polygon(root, PackedVector2Array([outer_a, outer_b, inner_b, inner_a]), stain_tint, false, "wall_top")
	# 两道窄暗流痕从压顶外缘向内收，位置随单元变化而稳定。
	for streak_index: int in 2:
		var streak_edge: int = posmod(weather_seed + 2 + streak_index * 5, top.size())
		var streak_next: int = (streak_edge + 1) % top.size()
		var streak_outer: Vector2 = top[streak_edge].lerp(top_center, 0.18)
		var streak_outer_side: Vector2 = top[streak_next].lerp(top_center, 0.28)
		var streak_inner: Vector2 = top[streak_edge].lerp(top_center, 0.82)
		var streak_inner_side: Vector2 = top[streak_next].lerp(top_center, 0.70)
		_polygon(root, PackedVector2Array([streak_outer, streak_outer_side, streak_inner_side, streak_inner]),
			_prop_tint("wall_weather_dark", Color(0.48, 0.48, 0.49, 1.0)), false, "wall_top")
	if chip_vertex >= 0:
		var chip_previous: int = (chip_vertex + top.size() - 1) % top.size()
		var chip_following: int = (chip_vertex + 1) % top.size()
		var chip_face := PackedVector2Array([top[chip_vertex],
			top[chip_vertex].lerp(top[chip_following], 0.24),
			top[chip_vertex].lerp(top[chip_previous], 0.22)])
		_polygon(root, chip_face, _prop_tint("wall_chip", Color(0.71, 0.73, 0.77, 1.0)), false, "wall_top")
	for edge: int in base.size():
		var next: int = (edge + 1) % base.size()
		if _is_join_edge(base[edge], base[next], connection_mask):
			continue
		var lit_edge: bool = top[next].x > top[edge].x and top[next].y < top[edge].y
		if lit_edge:
			var strokes: Dictionary = profile.get("prop_strokes", {})
			var edge_width: float = float(strokes.get("wall_lit_edge", 1.0))
			_line(root, PackedVector2Array([top[edge], top[next]]), _prop_tint("wall_lit_edge", Color("777e67")), edge_width, "wall_outline")
	_actor_layer.add_child(root)
	_props.append({"node": root, "wind": false, "bounds": Rect2(-34, -height - 17, 68, height + 34)})


func _add_pillar(cell: Vector2i) -> void:
	var root := Node2D.new()
	root.name = "WeatheredStonePillar"
	root.position = point(cell.x, cell.y)
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var cell_variant: int = posmod(cell.x * 3 + cell.y, 5)
	var height_level: int = 2 - absi(cell_variant - 2)
	var height: float = 34.0 + 8.0 * float(height_level)
	var has_fallen_drum: bool = cell_variant == 3
	# 六点柱础维持约 32 px 宽；柱身收窄后保留清楚的三级台阶。
	var shaft_radius: float = 12.0
	var shaft_depth: float = 6.0
	var light_direction := Vector2(-0.3420201433, 0.9396926208)
	root.set_meta("r7_height", height)
	root.set_meta("r7_height_level", height_level)
	var foot := PackedVector2Array([Vector2(0, -9), Vector2(17, -1),
		Vector2(16, 4), Vector2(0, 11), Vector2(-16, 4), Vector2(-17, -1)])
	var foot_tint: Color = _prop_tint("pillar_foot", Color("777d69"))
	var foot_node: Polygon2D = _polygon(root, foot, foot_tint, false, "pillar_base")
	# 污渍写入底板自己的纹理副本，保留唯一六点底板与原始 alpha。
	var foot_stain: Color = _prop_tint("pillar_foot_dirt", Color(0.42, 0.41, 0.41, 1.0))
	var stain_rgb_ratio := Color(foot_stain.r / maxf(foot_tint.r, 0.0001),
		foot_stain.g / maxf(foot_tint.g, 0.0001),
		foot_stain.b / maxf(foot_tint.b, 0.0001), 1.0)
	var coping_source_path: String = str(profile.get("coping", profile.get("ground", "")))
	var foot_source_image: Image
	if FileAccess.file_exists(coping_source_path):
		foot_source_image = Image.load_from_file(coping_source_path)
	if foot_source_image == null or foot_source_image.is_empty():
		# 导出包可不包含源 PNG；此时从正常渲染器的导入纹理读取同一份无损像素。
		foot_source_image = _coping.get_image()
	if foot_source_image == null or foot_source_image.is_empty():
		push_error("无法读取柱础纹理源图，不能生成柱础污渍：" + coping_source_path)
		return
	if foot_source_image.is_compressed():
		foot_source_image = foot_source_image.duplicate()
		if foot_source_image.decompress() != OK:
			push_error("无法解压柱础纹理源图：" + coping_source_path)
			return
	var source_size: Vector2i = foot_source_image.get_size()
	if source_size != Vector2i(_coping.get_width(), _coping.get_height()) or foot_source_image.has_mipmaps():
		push_error("柱础纹理源图尺寸或 mipmap 与导入纹理不一致：" + coping_source_path)
		return
	if foot_source_image.get_format() not in [Image.FORMAT_RGB8, Image.FORMAT_RGBA8]:
		push_error("柱础纹理源图不是 RGB8/RGBA8：" + coping_source_path)
		return
	var uv_min := Vector2(1e20, 1e20)
	var uv_max := Vector2(-1e20, -1e20)
	for uv: Vector2 in foot_node.uv:
		uv_min = uv_min.min(uv)
		uv_max = uv_max.max(uv)
	# UV 以原纹理像素为单位。裁剪边界落在整数像素线上，之后仅减去整数原点。
	var crop_origin := Vector2i(floori(uv_min.x) - 1, floori(uv_min.y) - 1)
	var crop_end := Vector2i(ceili(uv_max.x) + 2, ceili(uv_max.y) + 2)
	var crop_rect := Rect2i(crop_origin, crop_end - crop_origin)
	if crop_origin.x < 0 or crop_origin.y < 0 or crop_end.x > source_size.x or crop_end.y > source_size.y:
		push_error("柱础纹理裁剪区超出原图像素范围：" + coping_source_path)
		return
	var foot_texture_image: Image = foot_source_image.get_region(crop_rect)
	var stain_polygon := PackedVector2Array([Vector2(-14.0, -1.8), Vector2(-12.5, -2.5),
		Vector2(-11.3, -1.6), Vector2(-12.1, 0.0), Vector2(-13.8, 0.7)])
	var offset_u: float = fposmod(root.position.x * 0.017, 0.16)
	for image_y: int in foot_texture_image.get_height():
		for image_x: int in foot_texture_image.get_width():
			var source_x: float = float(crop_origin.x + image_x) + 0.5
			var source_y: float = float(crop_origin.y + image_y) + 0.5
			# 与 _polygon 的仿射 UV 公式互逆，点取原图 texel 中心。
			var local_point := Vector2((source_x / float(source_size.x) - 0.08 - offset_u) * (68.0 / 0.62) - 34.0,
				(source_y / float(source_size.y) - 0.82) / 0.0105)
			var stain_mask: float = 0.0
			for stain_x: float in [local_point.x, -local_point.x]:
				var stain_point := Vector2(stain_x, local_point.y)
				if not Geometry2D.is_point_in_polygon(stain_point, stain_polygon):
					continue
				var stain_edge_distance: float = INF
				for edge_index: int in range(stain_polygon.size()):
					var edge_start: Vector2 = stain_polygon[edge_index]
					var edge_end: Vector2 = stain_polygon[(edge_index + 1) % stain_polygon.size()]
					var edge: Vector2 = edge_end - edge_start
					var edge_t: float = clampf((stain_point - edge_start).dot(edge) / edge.length_squared(), 0.0, 1.0)
					stain_edge_distance = minf(stain_edge_distance, stain_point.distance_to(edge_start + edge * edge_t))
				var stain_t: float = clampf(stain_edge_distance / 0.55, 0.0, 1.0)
				var polygon_edge_mask: float = stain_t * stain_t * (3.0 - 2.0 * stain_t)
				stain_mask = maxf(stain_mask, polygon_edge_mask)
			if stain_mask <= 0.0 or not Geometry2D.is_point_in_polygon(local_point, foot):
				continue
			var foot_edge_distance: float = INF
			for edge_index: int in range(foot.size()):
				var edge_start: Vector2 = foot[edge_index]
				var edge_end: Vector2 = foot[(edge_index + 1) % foot.size()]
				var edge: Vector2 = edge_end - edge_start
				var edge_t: float = clampf((local_point - edge_start).dot(edge) / edge.length_squared(), 0.0, 1.0)
				foot_edge_distance = minf(foot_edge_distance, local_point.distance_to(edge_start + edge * edge_t))
			var inset_t: float = clampf((foot_edge_distance - 1.0) / 0.8, 0.0, 1.0)
			var stain_amount: float = stain_mask * inset_t * inset_t * (3.0 - 2.0 * inset_t)
			if stain_amount <= 0.0:
				continue
			var original_srgb: Color = foot_texture_image.get_pixel(image_x, image_y)
			var original_linear: Color = original_srgb.srgb_to_linear()
			var stained_linear := Color(
				original_linear.r * lerpf(1.0, stain_rgb_ratio.r, stain_amount),
				original_linear.g * lerpf(1.0, stain_rgb_ratio.g, stain_amount),
				original_linear.b * lerpf(1.0, stain_rgb_ratio.b, stain_amount), original_srgb.a)
			var stained_srgb: Color = stained_linear.linear_to_srgb()
			stained_srgb.a = original_srgb.a
			foot_texture_image.set_pixel(image_x, image_y, stained_srgb)
	var foot_texture := ImageTexture.create_from_image(foot_texture_image)
	if foot_texture == null:
		push_error("无法创建柱础纹理副本：" + coping_source_path)
		return
	foot_node.texture = foot_texture
	var remapped_uv := PackedVector2Array()
	for uv: Vector2 in foot_node.uv:
		remapped_uv.append(uv - Vector2(crop_origin))
	foot_node.uv = remapped_uv
	var shaft := PackedVector2Array()
	var top_base := PackedVector2Array()
	var cut_profile: Dictionary = {
		"curve": PackedVector2Array([
			Vector2(0.00, 0.0), Vector2(0.40, 0.0), Vector2(0.55, 9.0),
			Vector2(0.70, 4.0), Vector2(0.85, 13.0), Vector2(1.00, 12.0),
		]),
	}
	for i: int in 12:
		var angle: float = -PI * 0.5 + float(i) * TAU / 12.0
		var point_at_base := Vector2(cos(angle) * shaft_radius, sin(angle) * shaft_depth)
		shaft.append(point_at_base)
		var base_top_point := Vector2(point_at_base.x * 0.92,
			point_at_base.y * 0.92 - height)
		top_base.append(base_top_point)
	var top_surface: PackedVector2Array = _r13_expand_pillar_top_surface(
		top_base, shaft_radius, cut_profile["curve"])
	# 横倒鼓石继续压在柱身右侧，保留原断面形状和占地。
	if has_fallen_drum:
		var drum_lit: Color = _prop_tint("pillar_lit_side", Color("a5a691"))
		var drum_mid: Color = drum_lit.lerp(_prop_tint("pillar_dark_side", Color("7a806e")), 0.42)
		var drum_dark: Color = _prop_tint("pillar_dark_side", Color("7a806e"))
		_polygon(root, PackedVector2Array([Vector2(13.2, -1.7), Vector2(14.4, -2.5),
			Vector2(22.4, -2.6), Vector2(23.0, -1.7), Vector2(22.0, -0.7), Vector2(14.0, -0.6)]),
			drum_lit, false, "pillar_side")
		_polygon(root, PackedVector2Array([Vector2(14.0, -0.6), Vector2(22.0, -0.7),
			Vector2(23.0, 0.0), Vector2(22.0, 1.0), Vector2(14.2, 0.9)]),
			drum_mid, false, "pillar_side")
		_polygon(root, PackedVector2Array([Vector2(14.2, 0.9), Vector2(22.0, 1.0),
			Vector2(22.5, 2.2), Vector2(15.0, 2.6), Vector2(13.5, 1.8)]),
			drum_dark, false, "pillar_side")
		var drum_end := PackedVector2Array([Vector2(23.0, -3.0), Vector2(24.0, -2.7),
			Vector2(24.7, -1.7), Vector2(25.0, 0.0), Vector2(24.7, 1.7), Vector2(24.0, 2.7),
			Vector2(23.0, 3.0), Vector2(22.0, 2.7), Vector2(21.3, 1.7), Vector2(21.0, 0.0),
			Vector2(21.3, -1.7), Vector2(22.0, -2.7)])
		_polygon(root, drum_end, drum_lit, false, "pillar_side")
		_polygon(root, PackedVector2Array([Vector2(23.0, -1.8), Vector2(23.9, -1.5),
			Vector2(24.3, 0.0), Vector2(23.9, 1.5), Vector2(23.0, 1.8),
			Vector2(22.1, 1.5), Vector2(21.7, 0.0), Vector2(22.1, -1.5)]),
			_prop_tint("pillar_foot", Color("777d69")), false, "pillar_side")
		_line(root, PackedVector2Array([Vector2(22.3, -0.7), Vector2(22.8, 0.0), Vector2(22.4, 0.7)]),
			_prop_tint("pillar_groove_dark", Color(0.257316, 0.228295, 0.192539, 1.0)), 0.8, "pillar_side", false)
	var lit_rim_tint: Color = _prop_tint("pillar_lit_rim", Color(0.7246, 0.7334, 0.7670, 1.0))
	var backlit_rim_tint: Color = _prop_tint("pillar_backlit_rim", Color(0.6811, 0.6747, 0.6816, 1.0))
	var core_tint: Color = _prop_tint("pillar_core_dark", Color(0.4562, 0.4519, 0.4565, 1.0))
	var linear_luminance: Callable = func(color: Color) -> float:
		return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
	var lstar_luminance: Callable = func(lightness: float) -> float:
		var fy: float = (lightness + 16.0) / 116.0
		return fy * fy * fy if lightness > 8.0 else lightness / 903.2962962963
	var tint_at_lstar: Callable = func(base_tint: Color, target_lstar: float) -> Color:
		var base_linear: Color = base_tint.srgb_to_linear()
		var base_y: float = float(linear_luminance.call(base_linear))
		var scale: float = float(lstar_luminance.call(target_lstar)) / maxf(base_y, 0.000001)
		var scaled_linear := Color(base_linear.r * scale, base_linear.g * scale,
			base_linear.b * scale, base_tint.a)
		var scaled_srgb: Color = scaled_linear.linear_to_srgb()
		scaled_srgb.a = base_tint.a
		return scaled_srgb
	var texture_tint_at_lstar: Callable = func(points: PackedVector2Array, base_tint: Color,
			target_lstar: float) -> Color:
		if points.size() < 3:
			var small_polygon_tint: Color = tint_at_lstar.call(base_tint, target_lstar)
			return small_polygon_tint
		var min_x: float = INF
		var max_x: float = -INF
		var min_y: float = INF
		var max_y: float = -INF
		for sample_point: Vector2 in points:
			min_x = minf(min_x, sample_point.x)
			max_x = maxf(max_x, sample_point.x)
			min_y = minf(min_y, sample_point.y)
			max_y = maxf(max_y, sample_point.y)
		var base_linear: Color = base_tint.srgb_to_linear()
		var total_y: float = 0.0
		var sample_count: int = 0
		for sample_y_index: int in 12:
			for sample_x_index: int in 12:
				var sample_point := Vector2(
					lerpf(min_x, max_x, (float(sample_x_index) + 0.5) / 12.0),
					lerpf(min_y, max_y, (float(sample_y_index) + 0.5) / 12.0))
				if not Geometry2D.is_point_in_polygon(sample_point, points):
					continue
				var sample_u: float = clampf(0.08 + offset_u + (sample_point.x + 34.0) / 68.0 * 0.62, 0.04, 0.96)
				var sample_v: float = clampf(0.82 + sample_point.y * 0.0105, 0.04, 0.96)
				var sample_x: int = clampi(floori(sample_u * float(source_size.x)), 0, source_size.x - 1)
				var sample_y: int = clampi(floori(sample_v * float(source_size.y)), 0, source_size.y - 1)
				var texture_linear: Color = foot_source_image.get_pixel(sample_x, sample_y).srgb_to_linear()
				if texture_linear.a <= 0.5:
					continue
				var combined_linear := Color(texture_linear.r * base_linear.r,
					texture_linear.g * base_linear.g, texture_linear.b * base_linear.b, 1.0)
				total_y += float(linear_luminance.call(combined_linear))
				sample_count += 1
		if sample_count == 0:
			var empty_polygon_tint: Color = tint_at_lstar.call(base_tint, target_lstar)
			return empty_polygon_tint
		var average_y: float = total_y / float(sample_count)
		var scale: float = float(lstar_luminance.call(target_lstar)) / maxf(average_y, 0.000001)
		var scaled_linear := Color(base_linear.r * scale, base_linear.g * scale,
			base_linear.b * scale, base_tint.a)
		var scaled_srgb: Color = scaled_linear.linear_to_srgb()
		scaled_srgb.a = base_tint.a
		return scaled_srgb
	var pillar_light_profile := PackedVector2Array([
		Vector2(0.00, 51.5), Vector2(0.12, 51.5), Vector2(0.30, 47.0),
		Vector2(0.48, 42.0), Vector2(0.52, 40.0), Vector2(0.60, 34.0),
		Vector2(0.70, 36.0), Vector2(0.80, 46.5), Vector2(1.00, 46.5)])
	var pillar_lstar_at_u: Callable = func(u: float) -> float:
		var value: float = clampf(u, 0.0, 1.0)
		for profile_index: int in range(1, pillar_light_profile.size()):
			var a: Vector2 = pillar_light_profile[profile_index - 1]
			var b: Vector2 = pillar_light_profile[profile_index]
			if value <= b.x:
				return lerpf(a.y, b.y, (value - a.x) / maxf(b.x - a.x, 0.0001))
		return pillar_light_profile[pillar_light_profile.size() - 1].y
	var pillar_column_tint: Callable = func(x: float, target_lstar: float,
			top_points: PackedVector2Array) -> Color:
		var normalized_x: float = clampf(x / shaft_radius, -1.0, 1.0)
		var u: float = (normalized_x + 1.0) * 0.5
		var surface_normal := Vector2(normalized_x, sqrt(maxf(0.0, 1.0 - normalized_x * normalized_x))).normalized()
		var light_share: float = clampf(surface_normal.dot(light_direction), 0.0, 1.0)
		var normal_tint: Color = _prop_tint("pillar_dark_side", Color("7a806e")).lerp(
			_prop_tint("pillar_lit_side", Color("a5a691")), light_share)
		var base_tint: Color = normal_tint
		# 只混合色相基色；下面仍按原 pillar_lstar_at_u 目标重新缩放明度。
		if u >= 0.08 and u <= 0.16:
			var t: float = clampf((u - 0.08) / 0.08, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			base_tint = lit_rim_tint.lerp(normal_tint, t)
		elif u < 0.08:
			base_tint = lit_rim_tint
		if u >= 0.48 and u <= 0.56:
			var t: float = clampf((u - 0.48) / 0.08, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			base_tint = normal_tint.lerp(core_tint, t)
		elif u > 0.56 and u < 0.66:
			base_tint = core_tint
		elif u >= 0.66 and u <= 0.74:
			var t: float = clampf((u - 0.66) / 0.08, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			base_tint = core_tint.lerp(normal_tint, t)
		if u >= 0.76 and u <= 0.84:
			var t: float = clampf((u - 0.76) / 0.08, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			base_tint = normal_tint.lerp(backlit_rim_tint, t)
		elif u > 0.84:
			# 0.80–1.00 的反射带仍完整存在，过渡只改变色相，不移动明度节点。
			base_tint = backlit_rim_tint
		var base_linear: Color = base_tint.srgb_to_linear()
		var top_query_x: float = x
		if x > top_points[3].x or x < top_points[9].x:
			# 与原窄条算法相同，超出顶面投影时使用最前顶点的行。
			top_query_x = top_points[6].x
		var top_y: float = _pillar_front_top_y(top_points, top_query_x)
		var top_across: float = _r10_pillar_across_at_x(top_query_x, shaft_radius)
		top_y += _r10_pillar_cut_drop(top_across, height, cut_profile)
		var lower_y: float = shaft_depth * sqrt(maxf(0.0, 1.0 - normalized_x * normalized_x))
		var total_y: float = 0.0
		var sample_count: int = 0
		var sample_u: float = clampf(0.08 + offset_u + (x + 34.0) / 68.0 * 0.62, 0.04, 0.96)
		var sample_x: int = clampi(floori(sample_u * float(source_size.x)), 0, source_size.x - 1)
		for sample_index: int in 16:
			var sample_local_y: float = lerpf(top_y, lower_y, (float(sample_index) + 0.5) / 16.0)
			var sample_v: float = clampf(0.82 + sample_local_y * 0.0105, 0.04, 0.96)
			var sample_y: int = clampi(floori(sample_v * float(source_size.y)), 0, source_size.y - 1)
			var texture_linear: Color = foot_source_image.get_pixel(sample_x, sample_y).srgb_to_linear()
			if texture_linear.a <= 0.5:
				continue
			var combined_linear := Color(texture_linear.r * base_linear.r,
				texture_linear.g * base_linear.g, texture_linear.b * base_linear.b, 1.0)
			total_y += float(linear_luminance.call(combined_linear))
			sample_count += 1
		if sample_count == 0:
			var empty_column_tint: Color = tint_at_lstar.call(base_tint, target_lstar)
			return empty_column_tint
		var average_y: float = total_y / float(sample_count)
		var scale: float = float(lstar_luminance.call(target_lstar)) / maxf(average_y, 0.000001)
		var scaled_linear := Color(base_linear.r * scale, base_linear.g * scale,
			base_linear.b * scale, base_tint.a)
		var scaled_srgb: Color = scaled_linear.linear_to_srgb()
		scaled_srgb.a = base_tint.a
		return scaled_srgb
	var pillar_strip_width: float = 0.5
	var pillar_strip_count: int = ceili(shaft_radius * 2.0 / pillar_strip_width)
	var pillar_band_tints: Array[Color] = []
	for strip_index: int in pillar_strip_count:
		var band_min_x: float = -shaft_radius + float(strip_index) * pillar_strip_width
		var band_max_x: float = minf(shaft_radius, band_min_x + pillar_strip_width)
		var band_mid_x: float = (band_min_x + band_max_x) * 0.5
		var band_u: float = (band_mid_x / shaft_radius + 1.0) * 0.5
		var target_lstar: float = float(pillar_lstar_at_u.call(band_u))
		var band_tint: Color = pillar_column_tint.call(band_mid_x, target_lstar, top_base)
		pillar_band_tints.append(band_tint)
		# 每条 0.5 局部单位窄带用 Polygon2D 乘色，边界折点按曲线精确保留。
		for edge: int in range(3, 9):
			var next: int = (edge + 1) % shaft.size()
			var side_face: PackedVector2Array = _r13_pillar_front_side_face(
				top_base[edge], top_base[next], shaft[edge], shaft[next],
				shaft_radius, cut_profile["curve"])
			var clipped_points: PackedVector2Array = side_face
			for boundary_index: int in 2:
				if clipped_points.size() < 3:
					break
				var boundary_x: float = band_min_x if boundary_index == 0 else band_max_x
				var keep_greater: bool = boundary_index == 0
				var clipped_result := PackedVector2Array()
				var previous: Vector2 = clipped_points[clipped_points.size() - 1]
				var previous_inside: bool = previous.x >= boundary_x if keep_greater else previous.x <= boundary_x
				for vertex_index: int in clipped_points.size():
					var current: Vector2 = clipped_points[vertex_index]
					var current_inside: bool = current.x >= boundary_x if keep_greater else current.x <= boundary_x
					if current_inside != previous_inside:
						var delta_x: float = current.x - previous.x
						if not is_zero_approx(delta_x):
							var fraction: float = (boundary_x - previous.x) / delta_x
							clipped_result.append(previous.lerp(current, fraction))
					if current_inside:
						clipped_result.append(current)
					previous = current
					previous_inside = current_inside
				clipped_points = clipped_result
			if clipped_points.size() >= 3:
				# 仅剔除有限的同一点；非有限几何仍保留给原有校验拒收。
				var is_finite_point: bool = clipped_points[0].is_finite()
				for clipped_point: Vector2 in clipped_points:
					if clipped_point != clipped_points[0]:
						is_finite_point = false
						break
				if not is_finite_point:
					_polygon(root, clipped_points, band_tint, false, "pillar_side")
	# 柱础环每侧外扩约 2 px，厚度为 3 px。
	var ring_upper := PackedVector2Array()
	var ring_lower := PackedVector2Array()
	for i: int in shaft.size():
		var outer: Vector2 = shaft[i] * Vector2((shaft_radius + 2.0) / shaft_radius,
			(shaft_depth + 2.0) / shaft_depth) + Vector2(0.0, -1.0)
		if i in range(3, 10):
			# 柱础环前沿中央仅比两端低 2.5 px，形成浅椭圆弧。
			var normalized_x: float = outer.x / (shaft_radius + 2.0)
			var arc_height: float = sqrt(maxf(0.0, 1.0 - normalized_x * normalized_x))
			outer.y = -1.0 + 2.5 * arc_height
		ring_upper.append(outer)
		ring_lower.append(outer + Vector2(0.0, 3.0))
	for edge: int in range(3, 9):
		var next: int = (edge + 1) % ring_upper.size()
		var midpoint: Vector2 = (shaft[edge] + shaft[next]) * 0.5
		var surface_normal := Vector2(midpoint.x / shaft_radius, midpoint.y / shaft_depth).normalized()
		var light_share: float = clampf(surface_normal.dot(light_direction), 0.0, 1.0)
		var ring_tint: Color = _prop_tint("pillar_torus_dark", Color(0.6524, 0.6541, 0.6740, 1.0)).lerp(
			_prop_tint("pillar_torus_lit", Color(0.6996, 0.7136, 0.7548, 1.0)), light_share)
		var ring_piece := PackedVector2Array([ring_upper[edge], ring_upper[next], ring_lower[next], ring_lower[edge]])
		var textured_ring_tint: Color = texture_tint_at_lstar.call(ring_piece, ring_tint, 50.0)
		_polygon(root, ring_piece, textured_ring_tint, false, "pillar_side")
	var ring_upper_arc := PackedVector2Array()
	var ring_lower_arc := PackedVector2Array()
	for arc_index: int in range(3, 10):
		ring_upper_arc.append(ring_upper[arc_index])
		ring_lower_arc.append(ring_lower[arc_index])
	var ring_upper_color: Color = tint_at_lstar.call(lit_rim_tint, 52.0)
	var ring_lower_color: Color = tint_at_lstar.call(core_tint, 44.0)
	_line(root, ring_upper_arc, ring_upper_color, 1.0, "pillar_side", false)
	_line(root, ring_lower_arc, ring_lower_color, 1.0, "pillar_side", false)
	# 四道 1 px 竖槽按柱面透视压缩，核心带内保留至少 4 L* 的槽面差。
	var groove_positions := PackedFloat32Array([0.25, 0.44, 0.61, 0.76])
	var groove_base_tints: Array[Color] = []
	var groove_nodes: Array[Line2D] = []
	for groove_index: int in groove_positions.size():
		var groove_u: float = groove_positions[groove_index]
		var groove_x: float = (groove_u * 2.0 - 1.0) * shaft_radius
		var groove_across: float = clampf((groove_x / (shaft_radius * 0.92) + 1.0) * 0.5, 0.0, 1.0)
		var groove_y: float = _pillar_front_top_y(top_base, groove_x) \
			+ _r10_pillar_cut_drop(groove_across, height, cut_profile) + 1.0
		var groove_end := Vector2(groove_x, 5.0)
		var groove_start := Vector2(groove_x, groove_y)
		var groove_normal_x: float = groove_x / shaft_radius
		var groove_normal := Vector2(groove_normal_x, sqrt(maxf(0.0, 1.0 - groove_normal_x * groove_normal_x)))
		var groove_light_share: float = clampf(groove_normal.dot(light_direction), 0.0, 1.0)
		var groove_base_tint: Color = _prop_tint("pillar_groove_dark", Color(0.356, 0.346, 0.338, 1.0)).lerp(
			_prop_tint("pillar_groove_lit", Color(0.510, 0.510, 0.524, 1.0)), groove_light_share)
		groove_base_tints.append(groove_base_tint)
		var groove_body_lstar: float = float(pillar_lstar_at_u.call(groove_u))
		var groove_delta: float = 5.0 if groove_index == 2 else 6.3
		var groove_tint: Color = tint_at_lstar.call(groove_base_tint, groove_body_lstar - groove_delta)
		_line(root, PackedVector2Array([groove_start, groove_end]), groove_tint, 1.0, "pillar_side", false)
		var groove_line: Line2D = root.get_child(root.get_child_count() - 1) as Line2D
		groove_line.name = "R9Groove%d" % (groove_index + 1)
		groove_line.set_meta("r9_groove_index", groove_index + 1)
		groove_line.set_meta("r9_groove_u", groove_u)
		groove_nodes.append(groove_line)
	var top_base_tint: Color = _prop_tint("pillar_top", Color("c0bca6"))
	var top_tint: Color = texture_tint_at_lstar.call(top_surface, top_base_tint, 56.0)
	_polygon(root, top_surface, top_tint, false, "pillar_top")
	var pillar_curve: PackedVector2Array = cut_profile["curve"]
	# 沿用原 1.0 局部单位轮廓宽度，把断面颜色画进顶面而不扩展实体。
	var fracture_face_depth: float = 1.0
	var fracture_shadow_width: float = 1.6
	var add_clipped_top_patch: Callable = func(polygon: PackedVector2Array,
			target_lstar: float) -> void:
		if polygon.size() < 3:
			return
		var patches: Array[PackedVector2Array] = Geometry2D.intersect_polygons(top_surface, polygon)
		for patch: PackedVector2Array in patches:
			if patch.size() < 3 or _r13_pillar_polygon_area(patch) <= 0.0001:
				continue
			var patch_tint: Color = texture_tint_at_lstar.call(patch, top_base_tint, target_lstar)
			_polygon(root, patch, patch_tint, false, "pillar_top")
	# 先画背光断面脚下的投影：沿断面落向一侧偏移 1.6 局部单位，并裁入新顶面。
	for curve_index: int in range(2, pillar_curve.size()):
		var curve_start: Vector2 = pillar_curve[curve_index - 1]
		var curve_end: Vector2 = pillar_curve[curve_index]
		var cut_delta: float = curve_end.y - curve_start.y
		if cut_delta <= 0.0:
			continue
		var face_boundary: PackedVector2Array = _r13_pillar_front_boundary_between(
			top_base, shaft_radius, pillar_curve, curve_start.x, curve_end.x)
		var shadow_direction_x: float = -signf(light_direction.x)
		var shadow_band: PackedVector2Array = _r13_pillar_offset_band(
			face_boundary, Vector2.ZERO, Vector2(shadow_direction_x * fracture_shadow_width, 0.0))
		add_clipped_top_patch.call(shadow_band, 44.0)
	# 各斜面本体依其真实曲线朝向着色；向右下落面背光，回升面受光。
	for curve_index: int in range(2, pillar_curve.size()):
		var curve_start: Vector2 = pillar_curve[curve_index - 1]
		var curve_end: Vector2 = pillar_curve[curve_index]
		var cut_delta: float = curve_end.y - curve_start.y
		if is_zero_approx(cut_delta):
			continue
		var face_boundary: PackedVector2Array = _r13_pillar_front_boundary_between(
			top_base, shaft_radius, pillar_curve, curve_start.x, curve_end.x)
		var face_band: PackedVector2Array = _r13_pillar_offset_band(
			face_boundary, Vector2.ZERO, Vector2(0.0, -fracture_face_depth))
		var face_normal := Vector2(signf(cut_delta), 0.0)
		var face_lstar: float = 50.0 if face_normal.dot(light_direction) > 0.0 else 36.0
		add_clipped_top_patch.call(face_band, face_lstar)
	var r10_step_lines: Array[Line2D] = []
	var top_front_arc: PackedVector2Array = _r13_pillar_front_boundary_between(
		top_base, shaft_radius, pillar_curve, 0.0, 0.40)
	var top_front_color: Color = tint_at_lstar.call(lit_rim_tint, 56.0)
	_line(root, top_front_arc, top_front_color, 1.0, "pillar_top", false)
	_actor_layer.add_child(root)
	var r10_context: Dictionary = {
		"texture_image": foot_source_image,
		"source_size": source_size,
		"offset_u": offset_u,
		"shaft_radius": shaft_radius,
		"shaft_depth": shaft_depth,
		"pillar_height": height,
		"top_base": top_base,
		"cut_profile": cut_profile,
		"strip_width": pillar_strip_width,
		"band_tints": pillar_band_tints,
		"groove_base_tints": groove_base_tints,
		"step_lines": r10_step_lines,
		"tint_at_lstar": tint_at_lstar,
	}
	var r10_cache: Dictionary = {}
	_update_r10_pillar_grooves(root, groove_nodes, r10_context, r10_cache)
	# 最高实例的淡化 bounds 上缘为 -56 px；下缘覆盖原底板与鼓石位置。
	_props.append({"node": root, "wind": false,
		"bounds": Rect2(-18.0, -height - 6.0, 44.0, height + 19.0),
		"r10_grooves": groove_nodes, "r10_step_lines": r10_step_lines,
		"r10_context": r10_context, "r10_cache": r10_cache})

func _r10_pillar_cut_drop(across: float, pillar_height: float, cut_profile: Dictionary) -> float:
	var clamped_across: float = clampf(across, 0.0, 1.0)
	if cut_profile.has("curve"):
		var curve: PackedVector2Array = cut_profile["curve"]
		return _r13_pillar_cut_drop(clamped_across, curve)
	var slope_fraction: float = float(cut_profile.get("slope_fraction", 0.0))
	var slope_direction: float = float(cut_profile.get("slope_direction", 1.0))
	var slope_across: float = clamped_across if slope_direction >= 0.0 else 1.0 - clamped_across
	var drop: float = pillar_height * slope_fraction * slope_across
	var steps: PackedVector2Array = cut_profile.get("steps", PackedVector2Array())
	for step: Vector2 in steps:
		if clamped_across >= step.x:
			drop += step.y
	return drop


func _r13_pillar_cut_drop(across: float, curve: PackedVector2Array) -> float:
	if curve.is_empty():
		return 0.0
	var value: float = clampf(across, 0.0, 1.0)
	for curve_index: int in range(1, curve.size()):
		var a: Vector2 = curve[curve_index - 1]
		var b: Vector2 = curve[curve_index]
		if value <= b.x:
			return lerpf(a.y, b.y, (value - a.x) / maxf(b.x - a.x, 0.0001))
	return curve[curve.size() - 1].y


func _r13_pillar_cut_edge_points(a: Vector2, b: Vector2, shaft_radius: float,
		curve: PackedVector2Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	var across_a: float = _r10_pillar_across_at_x(a.x, shaft_radius)
	var across_b: float = _r10_pillar_across_at_x(b.x, shaft_radius)
	points.append(Vector2(a.x, a.y + _r13_pillar_cut_drop(across_a, curve)))
	if not is_equal_approx(across_a, across_b):
		var crossings: Array[Vector2] = []
		for curve_index: int in range(1, curve.size() - 1):
			var knot_across: float = curve[curve_index].x
			var t: float = (knot_across - across_a) / (across_b - across_a)
			if t > 0.00001 and t < 0.99999:
				crossings.append(Vector2(t, knot_across))
		crossings.sort_custom(func(left: Vector2, right: Vector2) -> bool: return left.x < right.x)
		for crossing: Vector2 in crossings:
			var base_point: Vector2 = a.lerp(b, crossing.x)
			points.append(Vector2(base_point.x,
				base_point.y + _r13_pillar_cut_drop(crossing.y, curve)))
	points.append(Vector2(b.x, b.y + _r13_pillar_cut_drop(across_b, curve)))
	return points


func _r13_expand_pillar_top_surface(base_top: PackedVector2Array, shaft_radius: float,
		curve: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for edge: int in base_top.size():
		var next: int = (edge + 1) % base_top.size()
		var edge_points: PackedVector2Array = _r13_pillar_cut_edge_points(
			base_top[edge], base_top[next], shaft_radius, curve)
		for point_index: int in range(edge_points.size() - 1):
			result.append(edge_points[point_index])
	return result


func _r13_pillar_front_side_face(top_a: Vector2, top_b: Vector2, shaft_a: Vector2,
		shaft_b: Vector2, shaft_radius: float, curve: PackedVector2Array) -> PackedVector2Array:
	var face: PackedVector2Array = _r13_pillar_cut_edge_points(top_a, top_b, shaft_radius, curve)
	face.append(shaft_b)
	face.append(shaft_a)
	return face


func _r13_pillar_front_boundary_between(top_base: PackedVector2Array, shaft_radius: float,
		curve: PackedVector2Array, across_start: float, across_end: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var start_value: float = clampf(minf(across_start, across_end), 0.0, 1.0)
	var end_value: float = clampf(maxf(across_start, across_end), 0.0, 1.0)
	var across_values: Array[float] = [start_value, end_value]
	for curve_index: int in range(1, curve.size() - 1):
		var knot_across: float = curve[curve_index].x
		if knot_across > start_value + 0.00001 and knot_across < end_value - 0.00001:
			across_values.append(knot_across)
	for front_index: int in range(3, 10):
		var front_across: float = _r10_pillar_across_at_x(top_base[front_index].x, shaft_radius)
		if front_across > start_value + 0.00001 and front_across < end_value - 0.00001:
			across_values.append(front_across)
	across_values.sort()
	var unique_values: Array[float] = []
	for value: float in across_values:
		if not unique_values.is_empty() and is_equal_approx(value, unique_values[unique_values.size() - 1]):
			continue
		unique_values.append(value)
	for across: float in unique_values:
		var x: float = (across * 2.0 - 1.0) * shaft_radius * 0.92
		var y: float = _pillar_front_top_y(top_base, x) + _r13_pillar_cut_drop(across, curve)
		points.append(Vector2(x, y))
	return points


func _r13_pillar_offset_band(boundary: PackedVector2Array, offset_a: Vector2,
		offset_b: Vector2) -> PackedVector2Array:
	var band := PackedVector2Array()
	if boundary.size() < 2:
		return band
	for point: Vector2 in boundary:
		band.append(point + offset_a)
	for point_index: int in range(boundary.size() - 1, -1, -1):
		band.append(boundary[point_index] + offset_b)
	return band


func _r13_pillar_polygon_area(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var twice_area: float = 0.0
	for point_index: int in points.size():
		var current: Vector2 = points[point_index]
		var next: Vector2 = points[(point_index + 1) % points.size()]
		twice_area += current.x * next.y - next.x * current.y
	return absf(twice_area) * 0.5


func _r10_pillar_across_at_x(x: float, shaft_radius: float) -> float:
	return clampf((x / (shaft_radius * 0.92) + 1.0) * 0.5, 0.0, 1.0)


func _r10_expand_pillar_top_surface(base_top: PackedVector2Array, shaft_radius: float,
		pillar_height: float, cut_profile: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	var steps: PackedVector2Array = cut_profile.get("steps", PackedVector2Array())
	for edge: int in base_top.size():
		var next: int = (edge + 1) % base_top.size()
		var a: Vector2 = base_top[edge]
		var b: Vector2 = base_top[next]
		var across_a: float = _r10_pillar_across_at_x(a.x, shaft_radius)
		var across_b: float = _r10_pillar_across_at_x(b.x, shaft_radius)
		result.append(Vector2(a.x, a.y + _r10_pillar_cut_drop(across_a, pillar_height, cut_profile)))
		var crossings: Array[Vector2] = []
		if not is_equal_approx(across_a, across_b):
			for step: Vector2 in steps:
				var t: float = (step.x - across_a) / (across_b - across_a)
				if t > 0.00001 and t < 0.99999:
					crossings.append(Vector2(t, step.x))
		crossings.sort_custom(func(left: Vector2, right: Vector2) -> bool: return left.x < right.x)
		for crossing: Vector2 in crossings:
			var base_point: Vector2 = a.lerp(b, crossing.x)
			var lower_across: float = maxf(0.0, crossing.y - 0.0001)
			var upper_across: float = minf(1.0, crossing.y + 0.0001)
			var lower_drop: float = _r10_pillar_cut_drop(lower_across, pillar_height, cut_profile)
			var upper_drop: float = _r10_pillar_cut_drop(upper_across, pillar_height, cut_profile)
			if across_b > across_a:
				result.append(Vector2(base_point.x, base_point.y + lower_drop))
				result.append(Vector2(base_point.x, base_point.y + upper_drop))
			else:
				result.append(Vector2(base_point.x, base_point.y + upper_drop))
				result.append(Vector2(base_point.x, base_point.y + lower_drop))
	return result


func _r10_pillar_front_side_face(top_a: Vector2, top_b: Vector2, shaft_a: Vector2,
		shaft_b: Vector2, shaft_radius: float, pillar_height: float,
		cut_profile: Dictionary) -> PackedVector2Array:
	var face := PackedVector2Array()
	var across_a: float = _r10_pillar_across_at_x(top_a.x, shaft_radius)
	var across_b: float = _r10_pillar_across_at_x(top_b.x, shaft_radius)
	face.append(Vector2(top_a.x, top_a.y + _r10_pillar_cut_drop(across_a, pillar_height, cut_profile)))
	var crossings: Array[Vector2] = []
	var steps: PackedVector2Array = cut_profile.get("steps", PackedVector2Array())
	if not is_equal_approx(across_a, across_b):
		for step: Vector2 in steps:
			var t: float = (step.x - across_a) / (across_b - across_a)
			if t > 0.00001 and t < 0.99999:
				crossings.append(Vector2(t, step.x))
	crossings.sort_custom(func(left: Vector2, right: Vector2) -> bool: return left.x < right.x)
	for crossing: Vector2 in crossings:
		var base_point: Vector2 = top_a.lerp(top_b, crossing.x)
		var lower_across: float = maxf(0.0, crossing.y - 0.0001)
		var upper_across: float = minf(1.0, crossing.y + 0.0001)
		var lower_drop: float = _r10_pillar_cut_drop(lower_across, pillar_height, cut_profile)
		var upper_drop: float = _r10_pillar_cut_drop(upper_across, pillar_height, cut_profile)
		if across_b > across_a:
			face.append(Vector2(base_point.x, base_point.y + lower_drop))
			face.append(Vector2(base_point.x, base_point.y + upper_drop))
		else:
			face.append(Vector2(base_point.x, base_point.y + upper_drop))
			face.append(Vector2(base_point.x, base_point.y + lower_drop))
	face.append(Vector2(top_b.x, top_b.y + _r10_pillar_cut_drop(across_b, pillar_height, cut_profile)))
	face.append(shaft_b)
	face.append(shaft_a)
	return face


func _r10_pillar_intact_front_arc(base_top: PackedVector2Array, shaft_radius: float,
		pillar_height: float, cut_profile: Dictionary) -> PackedVector2Array:
	var arc := PackedVector2Array()
	var steps: PackedVector2Array = cut_profile.get("steps", PackedVector2Array())
	if steps.is_empty():
		for index: int in range(3, 10):
			arc.append(base_top[index])
		return arc
	var boundary_across: float = steps[0].x
	var boundary_x: float = (boundary_across * 2.0 - 1.0) * shaft_radius * 0.92
	var boundary_y: float = _pillar_front_top_y(base_top, boundary_x) + _r10_pillar_cut_drop(
		maxf(0.0, boundary_across - 0.0001), pillar_height, cut_profile)
	arc.append(Vector2(boundary_x, boundary_y))
	for index: int in range(3, 10):
		var point: Vector2 = base_top[index]
		var across: float = _r10_pillar_across_at_x(point.x, shaft_radius)
		if across <= boundary_across:
			arc.append(Vector2(point.x, point.y + _r10_pillar_cut_drop(across, pillar_height, cut_profile)))
	return arc


func _r10_pillar_arc_segment(base_top: PackedVector2Array, shaft_radius: float,
		min_x: float, max_x: float) -> PackedVector2Array:
	var arc := PackedVector2Array()
	var start_x: float = max_x
	var end_x: float = min_x
	arc.append(Vector2(start_x, _pillar_front_top_y(base_top, start_x)))
	for index: int in range(3, 10):
		var point: Vector2 = base_top[index]
		if point.x < start_x and point.x > end_x:
			arc.append(point)
	arc.append(Vector2(end_x, _pillar_front_top_y(base_top, end_x)))
	return arc


func _r10_median(values: Array[float]) -> float:
	values.sort()
	var middle: int = values.size() / 2
	return values[middle] if values.size() % 2 == 1 else (values[middle - 1] + values[middle]) * 0.5


func _r10_lstar_from_linear_rgb(color: Color) -> float:
	var luminance: float = 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
	return 116.0 * pow(luminance, 1.0 / 3.0) - 16.0 if luminance > 0.008856 else 903.3 * luminance


func _r10_pillar_pixel_lstar(screen_transform: Transform2D, screen_x: int, screen_y: int,
		context: Dictionary) -> float:
	var image: Image = context["texture_image"]
	var source_size: Vector2i = context["source_size"]
	var radius: float = float(context["shaft_radius"])
	var strip_width: float = float(context["strip_width"])
	var local_point: Vector2 = screen_transform.affine_inverse() * Vector2(
		float(screen_x) + 0.5, float(screen_y) + 0.5)
	var shaft_depth: float = float(context["shaft_depth"])
	if absf(local_point.x) > radius * 0.92:
		return -1.0
	var top_base: PackedVector2Array = context["top_base"]
	var across: float = _r10_pillar_across_at_x(local_point.x, radius)
	var top_y: float = _pillar_front_top_y(top_base, local_point.x) + _r10_pillar_cut_drop(
		across, float(context["pillar_height"]), context["cut_profile"])
	var normalized_x: float = clampf(local_point.x / radius, -1.0, 1.0)
	var lower_y: float = shaft_depth * sqrt(maxf(0.0, 1.0 - normalized_x * normalized_x))
	if local_point.y < top_y or local_point.y > lower_y:
		return -1.0
	var band_tints: Array[Color] = context["band_tints"]
	var band_index: int = clampi(floori((local_point.x + radius) / strip_width), 0, band_tints.size() - 1)
	var tint_srgb: Color = band_tints[band_index]
	var offset_u: float = float(context["offset_u"])
	var sample_u: float = clampf(0.08 + offset_u + (local_point.x + 34.0) / 68.0 * 0.62, 0.04, 0.96)
	var sample_v: float = clampf(0.82 + local_point.y * 0.0105, 0.04, 0.96)
	var sample_x: int = clampi(floori(sample_u * float(source_size.x)), 0, source_size.x - 1)
	var sample_y: int = clampi(floori(sample_v * float(source_size.y)), 0, source_size.y - 1)
	var texel: Color = image.get_pixel(sample_x, sample_y)
	# 按本项目 Compatibility 原图匹配的 sRGB 乘色预测，再转线性求 L*。
	var combined_srgb := Color(texel.r * tint_srgb.r,
		texel.g * tint_srgb.g, texel.b * tint_srgb.b, 1.0)
	return _r10_lstar_from_linear_rgb(combined_srgb.srgb_to_linear())


func _r10_point_segment_distance(point: Vector2, first: Vector2, last: Vector2) -> float:
	var segment: Vector2 = last - first
	var length_squared: float = segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(first)
	var t: float = clampf((point - first).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(first + segment * t)


func _r10_pillar_neighbor_reference(line: Line2D, all_grooves: Array,
		screen_transform: Transform2D, context: Dictionary) -> float:
	var points: PackedVector2Array = line.points
	if points.size() < 2:
		return -1.0
	var first: Vector2 = screen_transform * points[0]
	var last: Vector2 = screen_transform * points[points.size() - 1]
	var delta: Vector2 = last - first
	if absf(delta.y) < 0.001:
		return -1.0
	var start_y: int = ceili(minf(first.y, last.y) - 0.5)
	var end_y: int = floori(maxf(first.y, last.y) - 0.5)
	var other_lines: Array[Dictionary] = []
	var stroke_scale: float = screen_transform.x.length()
	for other_value: Variant in all_grooves:
		var other_line: Line2D = other_value as Line2D
		if not is_instance_valid(other_line) or other_line == line:
			continue
		var other_points: PackedVector2Array = other_line.points
		if other_points.size() < 2:
			continue
		other_lines.append({
			"first": screen_transform * other_points[0],
			"last": screen_transform * other_points[other_points.size() - 1],
			"half_width": other_line.width * stroke_scale * 0.5,
		})
	var row_medians: Array[float] = []
	for screen_y: int in range(start_y, end_y + 1):
		var t: float = (float(screen_y) + 0.5 - first.y) / delta.y
		if t < 0.0 or t > 1.0:
			continue
		var center_x: float = first.x + delta.x * t
		var center_pixel_x: int = floori(center_x)
		if center_pixel_x < 2:
			continue
		var sample_x: Array[int] = [center_pixel_x - 2, center_pixel_x - 1,
			center_pixel_x + 1, center_pixel_x + 2]
		var all_sample_x: Array[int] = [center_pixel_x]
		all_sample_x.append_array(sample_x)
		var contaminated: bool = false
		for other: Dictionary in other_lines:
			var other_first: Vector2 = other["first"]
			var other_last: Vector2 = other["last"]
			var half_width: float = float(other["half_width"])
			for candidate_x: int in all_sample_x:
				if _r10_point_segment_distance(Vector2(float(candidate_x) + 0.5,
						float(screen_y) + 0.5), other_first, other_last) <= half_width:
					contaminated = true
					break
			if contaminated:
				break
		if contaminated:
			continue
		var neighbor_lstar: Array[float] = []
		for screen_x: int in sample_x:
			var value: float = _r10_pillar_pixel_lstar(screen_transform, screen_x, screen_y, context)
			if value < 0.0:
				neighbor_lstar.clear()
				break
			neighbor_lstar.append(value)
		if neighbor_lstar.size() == 4:
			row_medians.append(_r10_median(neighbor_lstar))
	if row_medians.is_empty():
		return -1.0
	return _r10_median(row_medians)


func _update_r10_pillar_grooves(root: Node2D, grooves: Array, context: Dictionary,
		cache: Dictionary) -> void:
	if not is_instance_valid(root) or not root.is_inside_tree():
		return
	var viewport: Viewport = root.get_viewport()
	var screen_transform: Transform2D = viewport.get_final_transform() * root.get_global_transform_with_canvas()
	var context_key := PackedFloat64Array([
		screen_transform.x.x, screen_transform.x.y,
		screen_transform.y.x, screen_transform.y.y,
		screen_transform.origin.x, screen_transform.origin.y,
		float(context["offset_u"]),
	])
	var previous_key: PackedFloat64Array = cache.get("context_key", PackedFloat64Array())
	if context_key == previous_key:
		return
	var pixel_scale: float = screen_transform.x.length()
	if pixel_scale <= 0.000001:
		return
	var groove_base_tints: Array[Color] = context["groove_base_tints"]
	var tint_at_lstar: Callable = context["tint_at_lstar"]
	for groove_value: Variant in grooves:
		var groove: Line2D = groove_value as Line2D
		if is_instance_valid(groove):
			groove.width = 1.0 / pixel_scale
	for groove_value: Variant in grooves:
		var groove: Line2D = groove_value as Line2D
		if not is_instance_valid(groove):
			continue
		var groove_index: int = int(groove.get_meta("r9_groove_index", 0))
		if groove_index < 1 or groove_index > groove_base_tints.size():
			continue
		var reference_lstar: float = _r10_pillar_neighbor_reference(
			groove, grooves, screen_transform, context)
		if reference_lstar < 0.0:
			push_warning("R10 凹槽缺少有效的同帧纹理邻像素，保留上次颜色：%s / %d" % [
				root.name, groove_index])
			continue
		var groove_delta: float = 5.0 if groove_index == 3 else 6.3
		groove.default_color = tint_at_lstar.call(groove_base_tints[groove_index - 1],
			reference_lstar - groove_delta)
	var step_lines: Array = context.get("step_lines", [])
	for line_value: Variant in step_lines:
		var step_line: Line2D = line_value as Line2D
		if is_instance_valid(step_line):
			step_line.width = 1.0 / pixel_scale
	cache["context_key"] = context_key


func _is_join_edge(a: Vector2, b: Vector2, mask: int) -> bool:
	var a_grid := Vector2((a.x / 32.0 + a.y / 16.0) * 0.5, (a.y / 16.0 - a.x / 32.0) * 0.5)
	var b_grid := Vector2((b.x / 32.0 + b.y / 16.0) * 0.5, (b.y / 16.0 - b.x / 32.0) * 0.5)
	return (mask & 1 and is_equal_approx(a_grid.y, -0.5) and is_equal_approx(b_grid.y, -0.5)) \
		or (mask & 2 and is_equal_approx(a_grid.x, 0.5) and is_equal_approx(b_grid.x, 0.5)) \
		or (mask & 4 and is_equal_approx(a_grid.y, 0.5) and is_equal_approx(b_grid.y, 0.5)) \
		or (mask & 8 and is_equal_approx(a_grid.x, -0.5) and is_equal_approx(b_grid.x, -0.5))


func _add_wall_masonry_courses(parent: Node2D, edge: int, next: int, base: PackedVector2Array,
		top: PackedVector2Array, side_is_lit: bool) -> void:
	var mortar_key: String = "wall_joint_lit" if side_is_lit else "wall_joint_dark"
	# Line2D 没有石材纹理可供乘色，fallback 与 profile 都是纯色 sRGB。
	var mortar_fallback: Color = Color(0.293637, 0.263669, 0.227090, 1.0)
	var mortar_tint: Color = _prop_tint(mortar_key, mortar_fallback)
	var mortar_width: float = float(profile.get("prop_strokes", {}).get("wall_mortar", 1.0))
	# 两道横缝把侧面分成三层；每层竖缝交替偏左、偏右。
	for course_index: int in range(1, 3):
		var course_height: float = float(course_index) / 3.0
		_add_wall_mortar_line(parent,
			_wall_face_point(base[edge], base[next], top[edge], top[next], course_height, 0.0),
			_wall_face_point(base[edge], base[next], top[edge], top[next], course_height, 1.0),
			mortar_tint, mortar_width)
	for course_index: int in 3:
		var lower_height: float = float(course_index) / 3.0
		var upper_height: float = float(course_index + 1) / 3.0
		var across: float = 0.36 if (edge + course_index) % 2 == 0 else 0.64
		_add_wall_mortar_line(parent,
			_wall_face_point(base[edge], base[next], top[edge], top[next], lower_height, across),
			_wall_face_point(base[edge], base[next], top[edge], top[next], upper_height, across),
			mortar_tint, mortar_width)


func _wall_face_point(base_a: Vector2, base_b: Vector2, top_a: Vector2, top_b: Vector2,
		height_fraction: float, across_fraction: float) -> Vector2:
	var left: Vector2 = base_a.lerp(top_a, height_fraction)
	var right: Vector2 = base_b.lerp(top_b, height_fraction)
	return left.lerp(right, across_fraction)


func _add_wall_mortar_line(parent: Node2D, a: Vector2, b: Vector2, tint: Color, width: float) -> void:
	if a.distance_squared_to(b) <= 0.0001:
		return
	_line(parent, PackedVector2Array([a, b]), tint, width, "wall_side", false)


func _pillar_front_top_y(top: PackedVector2Array, x: float) -> float:
	for edge: int in range(3, 9):
		var next: int = edge + 1
		var a: Vector2 = top[edge]
		var b: Vector2 = top[next]
		var low_x: float = minf(a.x, b.x)
		var high_x: float = maxf(a.x, b.x)
		if x < low_x or x > high_x or is_equal_approx(a.x, b.x):
			continue
		return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return top[6].y


func _polygon(parent: Node2D, points: PackedVector2Array, tint: Color, wall_face: bool = false,
		terrain_part: String = "") -> Polygon2D:
	var node := Polygon2D.new()
	node.polygon = points
	node.texture = _masonry if wall_face else _coping
	var stone_uv := PackedVector2Array()
	var texture_size: Vector2 = node.texture.get_size()
	var offset_u: float = fposmod(parent.position.x * 0.017, 0.16)
	for p: Vector2 in points:
		# 每一面使用原图内部坐标，非周期的边缘不会重复到面内。
		var u: float = clampf(0.08 + offset_u + (p.x + 34.0) / 68.0 * 0.62, 0.04, 0.96)
		var v: float = clampf(0.82 + p.y * 0.0105, 0.04, 0.96)
		stone_uv.append(Vector2(u, v) * texture_size)
	node.uv = stone_uv
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	# Polygon2D 的顶点颜色会压到 RGBA8；节点着色保留大于 1 的亮度系数。
	node.color = Color(1.0, 1.0, 1.0, tint.a)
	node.self_modulate = Color(tint.r, tint.g, tint.b, 1.0)
	if not terrain_part.is_empty():
		node.set_meta("terrain_part", terrain_part)
	parent.add_child(node)
	return node


func _line(parent: Node2D, points: PackedVector2Array, color: Color, width: float,
		terrain_part: String = "", antialiased: bool = true) -> Line2D:
	var node := Line2D.new()
	node.points = points
	node.default_color = color
	node.width = width
	node.antialiased = antialiased
	if not terrain_part.is_empty():
		node.set_meta("terrain_part", terrain_part)
	parent.add_child(node)
	return node


func _draw_blocked_corners(cell: Vector2i, canvas: Node2D = null) -> void:
	if canvas == null:
		canvas = self
	var corners: PackedVector2Array = diamond(cell, 2)
	for i: int in 4:
		var corner: Vector2 = corners[i]
		canvas.draw_polyline(PackedVector2Array([corner.lerp(corners[(i + 3) % 4], 0.17),
			corner, corner.lerp(corners[(i + 1) % 4], 0.17)]), Color("d2b68a99"), 1.0, true)
