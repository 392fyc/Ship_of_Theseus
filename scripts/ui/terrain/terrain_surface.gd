extends RefCounted
## 连续地表：手工地图和生成地图共享这一层与同一坐标采样。

const BlendShader := preload("res://scripts/ui/terrain/terrain_blend.gdshader")
const Catalog := preload("res://scripts/ui/terrain/terrain_catalog.gd")

static func make_material(board: Node2D, relief: bool = false) -> ShaderMaterial:
	var padding := 32
	var size := Vector2i(board.grid.width + padding * 2, board.grid.height + padding * 2)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y: int in size.y:
		for x: int in size.x:
			var pos := Vector2i(x - padding, y - padding)
			image.set_pixel(x, y, Color(float(board.visual_terrain_at(pos)) / 255.0,
				(1.0 / 255.0) if board._is_paved_at(pos) else 0.0,
				(1.0 / 255.0) if board.visual_variant_at(pos) == "mossy" else 0.0, 1.0))
	var material := ShaderMaterial.new()
	material.shader = BlendShader
	material.set_shader_parameter("terrain_map", ImageTexture.create_from_image(image))
	# 组合合同提供实际岸宽、湿暗和冷却边参数；两种地图创建方式共享此表。
	var catalog := Catalog.catalog()
	var pair_styles := Image.create(9, 9, false, Image.FORMAT_RGBAF)
	for b: int in 9:
		for a: int in 9:
			var style := Catalog.transition_style(a, b, catalog)
			pair_styles.set_pixel(a, b, Color(float(style["shore_width"]),
				float(style["wet_darkening"]), float(style["scorch_darkening"]), 1.0))
	material.set_shader_parameter("pair_styles", ImageTexture.create_from_image(pair_styles))
	var paving_style: Dictionary = catalog["variant_styles"]["paving_bank"]
	material.set_shader_parameter("paving_bank", Vector2(float(paving_style["shore_width"]), float(paving_style["wet_darkening"])))
	material.set_shader_parameter("map_origin", Vector2(-padding, -padding))
	material.set_shader_parameter("map_size", Vector2(size))
	material.set_shader_parameter("meadow", board._meadow)
	material.set_shader_parameter("moss", board._moss)
	material.set_shader_parameter("paving", board._ground)
	material.set_shader_parameter("rock", board._rock)
	material.set_shader_parameter("relief", relief)
	return material


static func make_surface(board: Node2D, material: ShaderMaterial) -> Polygon2D:
	var node := Polygon2D.new()
	node.name = "SharedTerrainSurface"
	var low := Vector2(-31.5, -31.5)
	var high := Vector2(board.grid.width + 30.5, board.grid.height + 30.5)
	node.polygon = board._quad(low.x, low.y, high.x, high.y)
	# 无 texture 时 Godot 使用 polygon 位置作 UV；绑定 1×1 白图确保 UV 是世界格坐标。
	var white := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	node.texture = ImageTexture.create_from_image(white)
	node.uv = PackedVector2Array([low, Vector2(high.x, low.y), high, Vector2(low.x, high.y)])
	node.material = material
	return node


static func relief_height(board: Node2D, at: Vector2) -> float:
	var base := Vector2i(floori(at.x), floori(at.y))
	var height := 0.0
	for y: int in range(-1, 3):
		for x: int in range(-1, 3):
			var cell := base + Vector2i(x, y)
			var type: int = board.visual_terrain_at(cell)
			if type not in [Cell.Terrain.MOUNTAIN, Cell.Terrain.PEAK]:
				continue
			var weight: float = board._depth_kernel(at.x - cell.x) * board._depth_kernel(at.y - cell.y)
			height += weight * (72.0 if type == Cell.Terrain.PEAK else 16.0)
	var erosion: float = 0.69 + 0.38 * _value_noise(at * 2.4) + 0.15 * _value_noise(at * 5.1 + Vector2(21.0, 13.0))
	# 坡脚可以跨界，但非岩格的中心必须回到地面，不能吞掉窄水道或熔岩格。
	var f := at - Vector2(base)
	f = Vector2(smoothstep(0.1, 0.9, f.x), smoothstep(0.1, 0.9, f.y))
	var coverage := 0.0
	for y: int in 2:
		for x: int in 2:
			if board.visual_terrain_at(base + Vector2i(x, y)) in [Cell.Terrain.MOUNTAIN, Cell.Terrain.PEAK]:
				coverage += (1.0 - f.x if x == 0 else f.x) * (1.0 - f.y if y == 0 else f.y)
	return maxf(0.0, height - 1.3) * erosion * smoothstep(0.0, 0.8, coverage)


static func _value_noise(at: Vector2) -> float:
	var base := at.floor()
	var f := at - base
	f = f * f * (Vector2.ONE * 3.0 - f * 2.0)
	return lerpf(lerpf(_hash(base), _hash(base + Vector2.RIGHT), f.x),
		lerpf(_hash(base + Vector2.DOWN), _hash(base + Vector2.ONE), f.x), f.y)


static func _hash(at: Vector2) -> float:
	return fposmod(sin(at.dot(Vector2(127.1, 311.7))) * 43758.5453, 1.0)


static func make_relief(board: Node2D, cell: Vector2i, material: ShaderMaterial) -> MeshInstance2D:
	var nearby := false
	for y: int in range(-2, 3):
		for x: int in range(-2, 3):
			if board.visual_terrain_at(cell + Vector2i(x, y)) in [Cell.Terrain.MOUNTAIN, Cell.Terrain.PEAK]:
				nearby = true
	if not nearby:
		return null
	var parts := 8
	var vertices := PackedVector2Array()
	var uv := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var foot: Vector2 = board.point(cell.x, cell.y)
	var max_height := 0.0
	for y: int in parts + 1:
		for x: int in parts + 1:
			var at := Vector2(cell) - Vector2.ONE * 0.5 + Vector2(x, y) / float(parts)
			var h := relief_height(board, at)
			max_height = maxf(max_height, h)
			var slope_x := relief_height(board, at + Vector2(0.04, 0)) - h
			var slope_y := relief_height(board, at + Vector2(0, 0.04)) - h
			var light := clampf(0.88 + (slope_x + slope_y) * 0.25, 0.50, 1.22)
			vertices.append(board.point(at.x, at.y) - foot - Vector2(0, h))
			uv.append(at)
			colors.append(Color(light, light, light, smoothstep(0.0, 1.5, h)))
	for y: int in parts:
		for x: int in parts:
			var a := y * (parts + 1) + x
			var b := a + parts + 1
			indices.append_array(PackedInt32Array([a, a + 1, b + 1, a, b + 1, b]))
	if max_height <= 0.01:
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance2D.new()
	node.name = "TerrainRelief"
	node.mesh = mesh
	node.material = material
	node.position = foot
	return node
