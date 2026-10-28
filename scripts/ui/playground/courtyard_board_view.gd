extends Node2D
## 逻辑格只决定地形；地表、建筑、林木和水面分别构成可交互的场景。

const TerrainSurface := preload("res://scripts/ui/terrain/terrain_surface.gd")
const TerrainCatalog := preload("res://scripts/ui/terrain/terrain_catalog.gd")

const CONTACT_TREE_CELL_WORLD_WIDTH := 64.0
const CONTACT_TREE_AMBIENT_ELLIPSE_SEGMENTS := 32

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


var _sprite_contact_edge_cache: Dictionary = {}
var _sprite_contact_frame_cache: int = -1
var _sprite_contact_visual_cache: Array[Dictionary] = []


func configure(value: Grid, visual_profile: Dictionary, layout: Dictionary = {}) -> void:
	grid = value
	_sprite_contact_edge_cache.clear()
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
	_sprite_contact_frame_cache = -1
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
		if bool(spec.get("portrait_tree_presented", false)):
			node.modulate.a = 1.0
			continue
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
	_sprite_contact_frame_cache = -1
	queue_redraw()
	if is_instance_valid(_detail_layer):
		_detail_layer.queue_redraw()


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
				if grid.is_valid(pos) and bool(profile.get("portrait_tree_presentation", {}).get("low_forest_cells", false)):
					_add_portrait_low_forest(pos)
					continue
				var tree_node: Node2D = _add_sprite(_tree, profile["tree"], point(x, y), 0.91 + float((x * 3 + y) % 3) * 0.055,
					Color("dedac1"), true, (x + y) % 2 == 0)
				tree_node.set_meta("courtyard_cell", pos)
			elif terrain == Cell.Terrain.WALL:
				if _architecture_walls.has(pos):
					continue
				_add_wall_shape(pos)
				if visual_variant_at(pos) == "ruined" and wall_connection_mask(pos) in [0, 1, 2, 4, 8]:
					_add_sprite(_rubble, profile["rubble"], point(x + 0.12, y + 0.08), 0.35, Color("acae97"))


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
		var exterior_style: Dictionary = profile.get("portrait_tree_presentation", {})
		if exterior_style.has("environment_tree_positions"):
			var positions: Array = []
			for coordinates: Array in exterior_style["environment_tree_positions"]:
				positions.append(Vector2(float(coordinates[0]), float(coordinates[1])))
			_grove(positions, float(exterior_style["environment_grove_scale"]), false)
			return
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
	if profile.has("portrait_tree_presentation"):
		for contact: Dictionary in _sprite_contact_shadow_visuals([]):
			var rgba: Array = profile["portrait_tree_presentation"]["root_shadow_rgba"]
			var color := Color(rgba[0], rgba[1], rgba[2], rgba[3])
			for polygon: PackedVector2Array in contact["shadow_polygons"]:
				var center := Vector2.ZERO
				for p: Vector2 in polygon:
					center += p / float(polygon.size())
				for band: int in 3:
					var factor: float = [1.0, 0.76, 0.52][band]
					var soft := PackedVector2Array()
					for p: Vector2 in polygon:
						soft.append(center + (p - center) * factor)
					var band_color := color
					band_color.a *= [0.2, 0.25, 0.35][band]
					canvas.draw_colored_polygon(soft, band_color)


func _build_architecture_walls() -> void:
	for cell: Vector2i in _architecture_walls:
		if visual_terrain_at(cell) != Cell.Terrain.WALL:
			continue
		_add_wall_shape(cell)
		var mask: int = wall_connection_mask(cell)
		if mask in [1, 2, 4, 8]:
			_add_sprite(_rubble, profile["rubble"], point(cell.x + 0.10, cell.y + 0.10), 0.29, Color("b1b19a"))


func _grove(positions: Array, size_scale: float, understory: bool = true) -> void:
	for i: int in positions.size():
		var p: Vector2 = positions[i]
		_add_sprite(_tree, profile["tree"], point(p.x, p.y), size_scale + float(i % 3) * 0.13,
			_prop_tint("environment_tree", Color("a4b096")), true, i % 2 == 0)
		if understory and i % 2 == 0:
			_add_sprite(_shrub, profile["shrub"], point(p.x + 0.45, p.y + 0.3), 0.9, _prop_tint("shrub", Color("a2b083")))


func _add_sprite(texture: Texture2D, spec: Dictionary, foot: Vector2, size_scale: float,
		tint: Color, wind: bool = false, mirrored: bool = false) -> Node2D:
	var root := Node2D.new()
	root.name = "CourtyardProp"
	root.position = foot
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var sprite := Sprite2D.new()
	sprite.texture = texture
	if texture == _tree and profile.has("portrait_tree_presentation"):
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
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
	if texture == _tree and profile.has("portrait_tree_presentation"):
		_props[-1]["sprite_contact_type"] = "tree"
		_props[-1]["sprite_contact_path"] = str(root.get_path_to(sprite))
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
			Color("aaa792") if base[next].y > base[edge].y else Color("7f8372"), true)
	_polygon(root, top, Color("b6b29b"))
	for edge: int in base.size():
		var next: int = (edge + 1) % base.size()
		if not _is_join_edge(base[edge], base[next], connection_mask):
			_line(root, PackedVector2Array([top[edge], top[next]]), Color("777e6738"), 0.45)
	_actor_layer.add_child(root)
	_props.append({"node": root, "wind": false, "bounds": Rect2(-34, -height - 17, 68, height + 34)})


func _add_pillar(cell: Vector2i) -> void:
	var root := Node2D.new()
	root.name = "WeatheredStonePillar"
	root.position = point(cell.x, cell.y)
	var foot := PackedVector2Array([Vector2(0, -9), Vector2(16, -2), Vector2(16, 3), Vector2(0, 11), Vector2(-16, 3), Vector2(-16, -2)])
	var shaft := PackedVector2Array([Vector2(0, -6), Vector2(10, -1), Vector2(10, 2), Vector2(0, 7), Vector2(-10, 2), Vector2(-10, -1)])
	_polygon(root, foot, Color("777d69"))
	var top: PackedVector2Array = shaft.duplicate()
	for i: int in top.size():
		top[i].y -= 38.0 + sin(float(i) * 1.5 + float(cell.x)) * 2.0
	for edge: int in range(2, 5):
		var next: int = (edge + 1) % shaft.size()
		_polygon(root, PackedVector2Array([top[edge], top[next], shaft[next], shaft[edge]]), Color("a5a691") if edge < 3 else Color("7a806e"), true)
	_polygon(root, top, Color("c0bca6"))
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
	node.color = tint
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
func _prop_tint(key: String, fallback: Color) -> Color:
	var tints: Dictionary = profile.get("prop_tints", {})
	var rgba: Array = tints.get(key, [])
	if rgba.size() != 4:
		return fallback
	# RGB 可超过 1 以提亮道具；alpha 仍独立保留。
	return Color(float(rgba[0]), float(rgba[1]), float(rgba[2]), float(rgba[3]))


func portrait_forest_connection_mask(pos: Vector2i) -> int:
	# Only actual board forest joins; exterior trees and diagonal contact do not.
	if not grid.is_valid(pos) or visual_terrain_at(pos) != Cell.Terrain.FOREST:
		return 0
	var result: int = 0
	var offsets: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for i: int in 4:
		var neighbor: Vector2i = pos + offsets[i]
		if grid.is_valid(neighbor) and visual_terrain_at(neighbor) == Cell.Terrain.FOREST:
			result |= 1 << i
	return result


func portrait_forest_edge(pos: Vector2i, edge: int) -> PackedVector2Array:
	var center: Vector2 = point(pos.x, pos.y)
	var mask: int = portrait_forest_connection_mask(pos)
	var corners := PackedVector2Array([Vector2(0, -16), Vector2(32, 0), Vector2(0, 16), Vector2(-32, 0)])
	var style: Dictionary = profile["portrait_tree_presentation"]
	var inset: float = float(style.get("low_forest_floor_edge_inset", 0.98))
	var fringe: float = float(style.get("low_forest_leaf_fringe", 2.6))
	var a: Vector2 = corners[edge]
	var b: Vector2 = corners[(edge + 1) % 4]
	var outward := Vector2((b - a).y, -(b - a).x).normalized()
	var points := PackedVector2Array()
	var steps: int = 1 if mask & (1 << edge) else 8
	var lobes: Array[float] = [-0.35, 1.0, -0.3, 0.8, -0.45, 1.0, -0.2, 0.7, -0.3]
	for step: int in range(steps + 1):
		var t: float = float(step) / float(steps)
		var vertex: Vector2 = a.lerp(b, t)
		if not (mask & (1 << edge)):
			vertex *= lerpf(1.0, inset, sin(t * PI))
			vertex += outward * fringe * lobes[(step + pos.x + pos.y * 3 + edge) % lobes.size()] * sin(t * PI)
		points.append(center + vertex)
	return points


func portrait_forest_floor(pos: Vector2i) -> PackedVector2Array:
	var outline := PackedVector2Array()
	for edge: int in 4:
		for vertex: Vector2 in portrait_forest_edge(pos, edge):
			if outline.is_empty() or not outline[-1].is_equal_approx(vertex):
				outline.append(vertex)
	if outline[0].is_equal_approx(outline[-1]):
		outline.remove_at(outline.size() - 1)
	return outline


func portrait_forest_region_depth(pos: Vector2i) -> Vector2:
	var pending: Array[Vector2i] = [pos]
	var visited: Dictionary = {pos: true}
	var depth := Vector2(INF, -INF)
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		var y: float = point(cell.x, cell.y).y
		depth.x = minf(depth.x, y - 16.0)
		depth.y = maxf(depth.y, y + 16.0)
		for offset: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var neighbor: Vector2i = cell + offset
			if not visited.has(neighbor) and grid.is_valid(neighbor) and visual_terrain_at(neighbor) == Cell.Terrain.FOREST:
				visited[neighbor] = true
				pending.append(neighbor)
	return depth


func portrait_forest_canopy_rise(at: Vector2, depth: Vector2) -> float:
	var style: Dictionary = profile["portrait_tree_presentation"]
	return lerpf(float(style.get("low_forest_rear_height", 3.0)), float(style.get("low_forest_front_height", 1.5)),
		clampf(inverse_lerp(depth.x, depth.y, at.y), 0.0, 1.0))


func portrait_forest_patches(pos: Vector2i) -> Array[Array]:
	var style: Dictionary = profile["portrait_tree_presentation"]
	var mask: int = portrait_forest_connection_mask(pos)
	var result: Array[Array] = []
	if not str(style.get("low_forest_canopy_texture", "")).is_empty():
		return result # Dense ground-layer canopy replaces the rejected point sprites.
	var size_scale: float = float(style.get("low_forest_boundary_scale", 0.56))
	# Plants belong to exposed region edges, not to shared-cell connectors.
	# Their roots stay in their own cell; no 14-unit lift into a neighbor.
	for edge: int in [0, 3, 2]:
		if mask & (1 << edge):
			continue
		var variant: int = (pos.x * 3 + pos.y * 5 + edge) % 3
		var scale_factor: float = [0.92, 1.0, 1.06][variant]
		var mirrored: bool = (pos.x + pos.y + edge) % 2 == 0
		if edge == 0:
			result.append([13.0, -6.5, size_scale * scale_factor, mirrored, edge])
		elif edge == 3:
			result.append([-13.0, -6.5, size_scale * scale_factor * 0.90, mirrored, edge])
		else:
			result.append([-21.0, 0.0, size_scale * scale_factor * 0.72, mirrored, edge])
	# The front/right standing and badge area is described by low floor texture,
	# not another tall plant. Shared interiors have no repeated shrub end-cap.
	return result


func _add_portrait_low_forest(pos: Vector2i) -> void:
	# Entry-local visual only: rear/side shrubs leave the actual cell foot clear.
	# No tree sprite is created, hence no tree trunk or tree-contact shadow remains.
	var style: Dictionary = profile["portrait_tree_presentation"]
	var rgba: Array = style.get("low_forest_tint", [0.78, 0.83, 0.77, 1.0])
	var tint := Color(float(rgba[0]), float(rgba[1]), float(rgba[2]), float(rgba[3]))
	# Thin textured leaf litter is ground, not an outline or a raised canopy.
	if style.has("low_forest_floor_rgba"):
		var forest_texture: Texture2D = _moss
		var canopy_path: String = str(style.get("low_forest_canopy_texture", ""))
		if not canopy_path.is_empty():
			forest_texture = load(canopy_path) as Texture2D
		var floor_node := Polygon2D.new()
		floor_node.name = "PortraitForestLitter"
		var ground_outline: PackedVector2Array = portrait_forest_floor(pos)
		var depth: Vector2 = portrait_forest_region_depth(pos)
		var raised: bool = not canopy_path.is_empty() and bool(style.get("low_forest_raised_canopy", false))
		var top := PackedVector2Array()
		for vertex: Vector2 in ground_outline:
			top.append(vertex - Vector2(0, portrait_forest_canopy_rise(vertex, depth) if raised else 0.0))
		floor_node.polygon = top
		floor_node.texture = forest_texture
		floor_node.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		floor_node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var span: float = float(style.get("low_forest_floor_texture_span", 96.0))
		var uv := PackedVector2Array()
		for vertex: Vector2 in ground_outline:
			uv.append(vertex / span * forest_texture.get_size())
		floor_node.uv = uv
		var floor_rgba: Array = style.get("low_forest_floor_rgba", [0.82, 1.12, 1.42, 0.96])
		floor_node.color = Color(float(floor_rgba[0]), float(floor_rgba[1]), float(floor_rgba[2]), float(floor_rgba[3]))
		if raised:
			# Only exposed screen-front edges receive a thin same-material side
			# and contact shadow. Shared edges have neither rim nor duplicate shadow.
			var mask: int = portrait_forest_connection_mask(pos)
			for edge: int in [1, 2]:
				if mask & (1 << edge):
					continue
				var rim: PackedVector2Array = portrait_forest_edge(pos, edge)
				for i: int in range(rim.size() - 1):
					var a: Vector2 = rim[i]
					var b: Vector2 = rim[i + 1]
					var shadow := Polygon2D.new()
					shadow.polygon = PackedVector2Array([a, b, b + Vector2(0, 1.0), a + Vector2(0, 1.0)])
					shadow.color = Color(0.025, 0.035, 0.02, 0.24)
					shadow.show_behind_parent = true
					floor_node.add_child(shadow)
					var side := Polygon2D.new()
					side.polygon = PackedVector2Array([a - Vector2(0, portrait_forest_canopy_rise(a, depth)),
						b - Vector2(0, portrait_forest_canopy_rise(b, depth)), b, a])
					side.texture = forest_texture
					side.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
					side.uv = PackedVector2Array([a / span * forest_texture.get_size(), b / span * forest_texture.get_size(),
						(b + Vector2(0, 1.0)) / span * forest_texture.get_size(), (a + Vector2(0, 1.0)) / span * forest_texture.get_size()])
					side.color = Color(0.58, 0.66, 0.60, 1.0)
					side.show_behind_parent = true
					floor_node.add_child(side)
		add_child(floor_node)
		if raised:
			move_child(floor_node, -1) # Over forest grid only; highlights/Units are later sibling layers.
		else:
			move_child(floor_node, _detail_layer.get_index())
		_props.append({"node": floor_node, "wind": false, "bounds": Rect2(),
			"portrait_tree_presented": true})
	for patch: Array in portrait_forest_patches(pos):
		var foot: Vector2 = point(pos.x, pos.y) + Vector2(float(patch[0]), float(patch[1]))
		var node: Node2D = _add_sprite(_shrub, profile["shrub"], foot, float(patch[2]), tint, false, bool(patch[3]))
		node.set_meta("portrait_low_forest_cell", pos)


func _sprite_source_contact_edge(sprite: Sprite2D, spec: Dictionary) -> Dictionary:
	var key: int = sprite.texture.get_instance_id()
	if _sprite_contact_edge_cache.has(key):
		return _sprite_contact_edge_cache[key]
	var image: Image = sprite.texture.get_image()
	var dims := Vector2(float(spec["display_size"][0]), float(spec["display_size"][1]))
	var anchor := Vector2(float(spec["foot_offset"][0]), float(spec["foot_offset"][1]))
	var size: Vector2i = image.get_size()
	var pixel := Vector2i(clampi(int(anchor.x / dims.x * size.x), 0, size.x - 1),
		clampi(int(anchor.y / dims.y * size.y), 0, size.y - 1))
	var result := {"edges": [], "anchor_row_runs": [], "anchor_pixel": pixel,
		"image_size": size, "alpha_threshold": 0.5,
		"reason": "No opaque source at the configured ground anchor."}
	if image.get_pixelv(pixel).a > 0.5:
		var edges: Array[PackedVector2Array] = []
		var anchor_row_runs: Array[Vector2i] = []
		var x: int = 0
		while x < size.x:
			while x < size.x and image.get_pixel(x, pixel.y).a <= 0.5:
				x += 1
			if x >= size.x:
				break
			var left: int = x
			while x < size.x and image.get_pixel(x, pixel.y).a > 0.5:
				x += 1
			var right: int = x - 1
			anchor_row_runs.append(Vector2i(left, right))
			var edge := PackedVector2Array()
			for column: int in range(left, right + 1):
				var y: int = size.y - 1
				while y > pixel.y and image.get_pixel(column, y).a <= 0.5:
					y -= 1
				for point: Vector2 in [Vector2(column, y + 1), Vector2(column + 1, y + 1)]:
					if not edge.is_empty() and point == edge[-1]:
						continue
					while edge.size() >= 2 and is_zero_approx((edge[-1] - edge[-2]).cross(point - edge[-1])):
						edge.remove_at(edge.size() - 1)
					edge.append(point)
			if edge.size() >= 2:
				edges.append(edge)
		result["edges"] = edges
		result["anchor_row_runs"] = anchor_row_runs
		result["reason"] = "Source alpha lower boundaries from every opaque run on the existing ground-anchor row."
	_sprite_contact_edge_cache[key] = result
	return result


func _tree_ambient_ground_shadow_ellipse(sprite: Sprite2D, texture_to_board: Transform2D,
		edges: Array[PackedVector2Array]) -> PackedVector2Array:
	if edges.is_empty():
		return PackedVector2Array()
	var bounds := Rect2()
	var has_point: bool = false
	for edge: PackedVector2Array in edges:
		for point: Vector2 in edge:
			if not has_point:
				bounds = Rect2(point, Vector2.ZERO)
				has_point = true
			else:
				bounds = bounds.expand(point)
	if not has_point:
		return PackedVector2Array()
	var sprite_rect_width: float = sprite.get_rect().size.x
	var actual_display_width: float = texture_to_board.x.length() * sprite_rect_width
	var local_style: Dictionary = profile.get("portrait_tree_presentation", {})
	var fraction: float = float(local_style.get("root_shadow_width_fraction", 0.5))
	var width: float = minf(CONTACT_TREE_CELL_WORLD_WIDTH * 0.5, actual_display_width * fraction)
	if width <= 0.0:
		return PackedVector2Array()
	var height: float = width * (32.0 / 64.0)
	var center: Vector2 = bounds.get_center() + Vector2(1.5, 2.0)
	if not local_style.is_empty():
		var dims: Array = profile["tree"]["display_size"]
		var foot: Array = profile["tree"]["foot_offset"]
		center = texture_to_board * (Vector2(foot[0], foot[1]) / Vector2(dims[0], dims[1]) * sprite.texture.get_size()) + Vector2(1.0, 1.0)
	var ellipse := PackedVector2Array()
	for index: int in CONTACT_TREE_AMBIENT_ELLIPSE_SEGMENTS:
		var angle: float = TAU * float(index) / float(CONTACT_TREE_AMBIENT_ELLIPSE_SEGMENTS)
		ellipse.append(center + Vector2(cos(angle) * width * 0.5, sin(angle) * height * 0.5))
	return ellipse


func _sprite_contact_shadow_visuals(existing_shadows: Array) -> Array[Dictionary]:
	if _sprite_contact_frame_cache == Engine.get_process_frames():
		return _sprite_contact_visual_cache
	var result: Array[Dictionary] = []
	var blockers: Array = existing_shadows.duplicate()
	for prop: Dictionary in _props:
		if not prop.has("sprite_contact_path"):
			continue
		var root: Node2D = prop["node"]
		if not is_instance_valid(root) or not root.is_visible_in_tree():
			continue
		var sprite := root.get_node_or_null(NodePath(prop["sprite_contact_path"])) as Sprite2D
		if sprite == null:
			continue
		var kind: String = prop["sprite_contact_type"]
		var source: Dictionary = _sprite_source_contact_edge(sprite, profile[kind])
		var transform: Transform2D = global_transform.affine_inverse() * sprite.global_transform
		var edges: Array[PackedVector2Array] = []
		var outward_normals_by_edge: Array[PackedVector2Array] = []
		var source_edges: Array = source["edges"]
		for source_edge_value: Variant in source_edges:
			var source_edge: PackedVector2Array = source_edge_value
			var edge: PackedVector2Array = transform * source_edge
			edges.append(edge)
			var normals := PackedVector2Array()
			for index: int in maxi(0, edge.size() - 1):
				var tangent: Vector2 = edge[index + 1] - edge[index]
				normals.append(Vector2(-tangent.y, tangent.x).normalized() * signf(transform.determinant()))
			outward_normals_by_edge.append(normals)
		var contact := {"node": root, "sprite": sprite, "type": kind,
			"source": source, "texture_to_board": transform,
			"edges": edges, "outward_normals_by_edge": outward_normals_by_edge,
			"shadow_polygons": [], "reason": source["reason"]}
		var rejected_shadow_count: int = 0
		var ground_shadow_draw_rule: String = "per_source_arc_cast_v1"
		var draw_shapes: Array[PackedVector2Array] = []
		if kind == "tree":
			ground_shadow_draw_rule = "tree_ambient_ellipse_v1"
			var ellipse: PackedVector2Array = _tree_ambient_ground_shadow_ellipse(
				sprite, transform, edges)
			if ellipse.size() >= 3:
				draw_shapes.append(ellipse)
		else:
			for edge: PackedVector2Array in edges:
				if edge.size() < 2:
					continue
				var dims: Array = profile[kind]["display_size"]
				var anchor: Array = profile[kind]["foot_offset"]
				var center: Vector2 = transform * Vector2(float(anchor[0]) / float(dims[0]) * sprite.texture.get_width(),
					float(anchor[1]) / float(dims[1]) * sprite.texture.get_height())
				var cast_points: PackedVector2Array = edge.duplicate()
				for point: Vector2 in edge:
					cast_points.append(center + (point - center) * 1.18 + Vector2(1.5, 2.0))
				var hull: PackedVector2Array = Geometry2D.convex_hull(cast_points)
				if hull.size() > 1 and hull[0] == hull[-1]:
					hull.remove_at(hull.size() - 1)
				draw_shapes.append(hull)
		for draw_shape: PackedVector2Array in draw_shapes:
			var pieces: Array[PackedVector2Array] = [draw_shape]
			for blocker: PackedVector2Array in blockers:
				var remaining: Array[PackedVector2Array] = []
				for piece: PackedVector2Array in pieces:
					remaining.append_array(Geometry2D.clip_polygons(piece, blocker))
				pieces = remaining
			var has_hole: bool = false
			for piece: PackedVector2Array in pieces:
				has_hole = has_hole or Geometry2D.is_polygon_clockwise(piece)
			if has_hole:
				rejected_shadow_count += 1
			else:
				contact["shadow_polygons"].append_array(pieces)
				blockers.append_array(pieces)
		contact["ground_shadow_draw_rule"] = ground_shadow_draw_rule
		if rejected_shadow_count > 0:
			contact["reason"] = ("The tree ambient ellipse was omitted after subtraction produced a hole."
				if kind == "tree" else "One or more root-arc shadows were omitted after subtraction produced a hole.")
		elif edges.is_empty():
			contact["reason"] = source["reason"]
		elif contact["shadow_polygons"].is_empty():
			contact["reason"] = ("Tree ambient ellipse was covered by existing shadow geometry or had no valid draw shape."
				if kind == "tree" else "Independent root-arc shadows were covered by existing shadow geometry; no additional components drawn.")
		result.append(contact)
	_sprite_contact_frame_cache = Engine.get_process_frames()
	_sprite_contact_visual_cache = result
	return result
