extends RefCounted
## Entry-local tree presentation. Reads actual Unit poses; never changes Grid or actions.
const TREE_SHADER := preload("res://scenes/tactical/character_pipeline/portrait_tree.gdshader")
var _board_ref: WeakRef
var _manager_ref: WeakRef
var _trees: Array[Dictionary] = []
var _config: Dictionary = {}

func configure(board: Node2D, manager: Node, config: Dictionary) -> void:
	_board_ref = weakref(board)
	_manager_ref = weakref(manager)
	_config = config.duplicate(true)
	_trees.clear()
	for prop: Dictionary in board.get("_props"):
		if str(prop.get("sprite_contact_type", "")) != "tree":
			continue
		var root: Node2D = prop["node"]
		var sprite: Sprite2D = root.get_node(NodePath(prop["sprite_contact_path"])) as Sprite2D
		var material := ShaderMaterial.new()
		material.shader = TREE_SHADER
		material.set_shader_parameter("source_size", sprite.texture.get_size())
		material.set_shader_parameter("saturation", float(config.get("saturation", 0.86)))
		material.set_shader_parameter("contrast", float(config.get("contrast", 0.92)))
		material.set_shader_parameter("reveal_alpha", float(config.get("canopy_reveal_alpha", 0.18)))
		sprite.material = material
		prop["portrait_tree_presented"] = true
		prop["wind"] = false
		root.rotation = 0.0
		root.modulate.a = 1.0
		var cell: Vector2i = root.get_meta("courtyard_cell", Vector2i(-99, -99))
		var on_board: bool = (board.get("grid") as Grid).is_valid(cell)
		if not on_board:
			root.scale *= float(config.get("environment_scale", 0.85))
		# Preserve real y-sort, with trees first only at equal foot depth.
		root.get_parent().move_child(root, 0)
		_trees.append({"root": root, "sprite": sprite, "material": material,
			"cell": cell, "on_board": on_board, "weight": 0.0,
			"regions": PackedVector4Array(), "owners": []})

func update(delta: float) -> void:
	if _manager_ref == null:
		return
	var manager: Node = _manager_ref.get_ref() as Node
	if not is_instance_valid(manager):
		return
	for tree: Dictionary in _trees:
		var root: Node2D = tree["root"]
		var sprite: Sprite2D = tree["sprite"]
		if not is_instance_valid(root) or not is_instance_valid(sprite):
			continue
		var regions := PackedVector4Array()
		var owners: Array[int] = []
		var tree_rect: Rect2 = sprite.get_global_transform_with_canvas() * sprite.get_rect()
		for unit: Unit in manager.get("units"):
			if not is_instance_valid(unit) or not unit.stats.is_alive() or unit.global_position.y > root.global_position.y + 0.01:
				continue
			var canvas: Transform2D = unit.get_viewport().get_canvas_transform()
			var foot: Vector2 = canvas * unit.global_position
			var head: Vector2 = foot - Vector2(0, 64)
			if unit.has_character_animation() and unit.character_animation.has_method("overhead_anchor_world_position"):
				head = canvas * unit.character_animation.call("overhead_anchor_world_position")
			var height: float = maxf(24.0, foot.y - head.y)
			var body := Rect2(Vector2(foot.x - 20, head.y), Vector2(40, height + 8))
			if not body.intersects(tree_rect):
				continue
			regions.append(Vector4(foot.x, (head.y + foot.y) * 0.5, 28.0, height * 0.65))
			owners.append(unit.get_instance_id())
			if regions.size() == 8:
				break
		var weight: float = float(tree["weight"])
		weight = move_toward(weight, 1.0 if not regions.is_empty() else 0.0, delta * 7.0)
		if not regions.is_empty():
			tree["regions"] = regions
			tree["owners"] = owners
		elif weight <= 0.0:
			tree["regions"] = PackedVector4Array()
			tree["owners"] = []
		tree["weight"] = weight
		var retained: PackedVector4Array = tree["regions"]
		var padded := PackedVector4Array()
		padded.resize(8)
		for i: int in retained.size():
			padded[i] = retained[i]
		var material: ShaderMaterial = tree["material"]
		material.set_shader_parameter("reveal_count", retained.size())
		material.set_shader_parameter("reveal_regions", padded)
		material.set_shader_parameter("reveal_strength", weight)

func debug_snapshot() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for tree: Dictionary in _trees:
		var root: Node2D = tree["root"]
		if not is_instance_valid(root):
			continue
		rows.append({"cell": tree["cell"], "on_board": tree["on_board"],
			"world_foot": root.global_position, "root_alpha": root.modulate.a,
			"root_rotation": root.rotation, "root_scale": root.scale,
			"reveal_weight": tree["weight"], "reveal_owners": tree["owners"]})
	return rows
