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


func configure(value: Grid, visual_profile: Dictionary, layout: Dictionary = {}) -> void:
	grid = value
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


func _draw_wall_footings(canvas: Node2D = null) -> void:
	if canvas == null:
		canvas = self
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
		var shadow := PackedVector2Array()
		for p: Vector2 in base:
			apron.append(center + (p - center) * 1.18)
			shadow.append(center + (p - center) * 1.28 + Vector2(1.5, 2.0))
		canvas.draw_colored_polygon(shadow, Color("18201638"))
		tint.a = 0.42
		_textured_ground_polygon(apron, texture, tint, canvas)


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
		var wear: float = sin(base_world[i].x * 0.075 + base_world[i].y * 0.11) * (2.5 if visual_variant_at(cell) == "ruined" else 0.35)
		top[i].y -= _wall_vertex_height(cell, base_world[i]) - wear
	for edge: int in base.size():
		var next: int = (edge + 1) % base.size()
		if base[next].x >= base[edge].x or _is_join_edge(base[edge], base[next], connection_mask):
			continue
		_polygon(root, PackedVector2Array([top[edge], top[next], base[next], base[edge]]),
			_prop_tint("wall_lit_side", Color("aaa792")) if base[next].y > base[edge].y else _prop_tint("wall_dark_side", Color("7f8372")), true)
	_polygon(root, top, _prop_tint("wall_top", Color("b6b29b")))
	for edge: int in base.size():
		var next: int = (edge + 1) % base.size()
		if not _is_join_edge(base[edge], base[next], connection_mask):
			var lit_edge: bool = top[next].x > top[edge].x and top[next].y < top[edge].y
			var edge_tint: Color = _prop_tint("wall_lit_edge", Color("777e6738")) if lit_edge else _prop_tint("wall_other_edge", Color("777e6738"))
			var strokes: Dictionary = profile.get("prop_strokes", {})
			var edge_width: float = float(strokes.get("wall_lit_edge" if lit_edge else "wall_other_edge", 0.45))
			_line(root, PackedVector2Array([top[edge], top[next]]), edge_tint, edge_width)
	_actor_layer.add_child(root)
	_props.append({"node": root, "wind": false, "bounds": Rect2(-34, -height - 17, 68, height + 34)})


func _add_pillar(cell: Vector2i) -> void:
	var root := Node2D.new()
	root.name = "WeatheredStonePillar"
	root.position = point(cell.x, cell.y)
	var foot := PackedVector2Array([Vector2(0, -9), Vector2(16, -2), Vector2(16, 3), Vector2(0, 11), Vector2(-16, 3), Vector2(-16, -2)])
	var shaft := PackedVector2Array([Vector2(0, -6), Vector2(10, -1), Vector2(10, 2), Vector2(0, 7), Vector2(-10, 2), Vector2(-10, -1)])
	_polygon(root, foot, _prop_tint("pillar_foot", Color("777d69")))
	var top: PackedVector2Array = shaft.duplicate()
	for i: int in top.size():
		top[i].y -= 38.0 + sin(float(i) * 1.5 + float(cell.x)) * 2.0
	for edge: int in range(2, 5):
		var next: int = (edge + 1) % shaft.size()
		_polygon(root, PackedVector2Array([top[edge], top[next], shaft[next], shaft[edge]]), _prop_tint("pillar_lit_side", Color("a5a691")) if edge < 3 else _prop_tint("pillar_dark_side", Color("7a806e")), true)
	_polygon(root, top, _prop_tint("pillar_top", Color("c0bca6")))
	_actor_layer.add_child(root)
	_props.append({"node": root, "wind": false, "bounds": Rect2(-18, -48, 36, 61)})


func _is_join_edge(a: Vector2, b: Vector2, mask: int) -> bool:
	var a_grid := Vector2((a.x / 32.0 + a.y / 16.0) * 0.5, (a.y / 16.0 - a.x / 32.0) * 0.5)
	var b_grid := Vector2((b.x / 32.0 + b.y / 16.0) * 0.5, (b.y / 16.0 - b.x / 32.0) * 0.5)
	return (mask & 1 and is_equal_approx(a_grid.y, -0.5) and is_equal_approx(b_grid.y, -0.5)) \
		or (mask & 2 and is_equal_approx(a_grid.x, 0.5) and is_equal_approx(b_grid.x, 0.5)) \
		or (mask & 4 and is_equal_approx(a_grid.y, 0.5) and is_equal_approx(b_grid.y, 0.5)) \
		or (mask & 8 and is_equal_approx(a_grid.x, -0.5) and is_equal_approx(b_grid.x, -0.5))


func _polygon(parent: Node2D, points: PackedVector2Array, tint: Color, wall_face: bool = false) -> void:
	var node := Polygon2D.new()
	node.polygon = points
	var top_uv := PackedVector2Array()
	for p: Vector2 in points:
		top_uv.append((p + parent.position) * 10.0 + Vector2(400, 400))
	node.uv = top_uv
	node.texture = _ground
	if wall_face:
		var u0: float = (parent.position.x + points[0].x) * 22.36068
		var u1: float = (parent.position.x + points[1].x) * 22.36068
		node.uv = PackedVector2Array([Vector2(u0, -(points[3].y - points[0].y) * 20.0),
			Vector2(u1, -(points[2].y - points[1].y) * 20.0), Vector2(u1, 0), Vector2(u0, 0)])
		node.texture = _masonry
	# Polygon2D 的顶点颜色会压到 RGBA8；节点着色保留大于 1 的亮度系数。
	node.color = Color(1.0, 1.0, 1.0, tint.a)
	node.self_modulate = Color(tint.r, tint.g, tint.b, 1.0)
	parent.add_child(node)


func _line(parent: Node2D, points: PackedVector2Array, color: Color, width: float) -> void:
	var node := Line2D.new()
	node.points = points
	node.default_color = color
	node.width = width
	node.antialiased = true
	parent.add_child(node)


func _draw_blocked_corners(cell: Vector2i, canvas: Node2D = null) -> void:
	if canvas == null:
		canvas = self
	var corners: PackedVector2Array = diamond(cell, 2)
	for i: int in 4:
		var corner: Vector2 = corners[i]
		canvas.draw_polyline(PackedVector2Array([corner.lerp(corners[(i + 3) % 4], 0.17),
			corner, corner.lerp(corners[(i + 1) % 4], 0.17)]), Color("d2b68a99"), 1.0, true)
