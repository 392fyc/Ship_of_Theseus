extends Sprite2D
## Static original token with map-space presentation only; never resolves an action.
const DIRECTIONS: Array[StringName] = [&"NE", &"NW", &"SW", &"SE"]
const SCREEN_DIRECTION: Dictionary = {
	&"NW": Vector2(-1.0, -0.5),
	&"NE": Vector2(1.0, -0.5),
	&"SW": Vector2(-1.0, 0.5),
	&"SE": Vector2(1.0, 0.5),
}
const DEFAULT_COLUMN_BY_DIRECTION: Dictionary = {
	&"NE": 0,
	&"NW": 1,
	&"SW": 2,
	&"SE": 3,
}
const DEFAULT_SUPPORT_CENTER_PX_BY_DIRECTION: Dictionary = {
	&"NE": Vector2(210.5, 396.0),
	&"NW": Vector2(184.0, 395.0),
	&"SW": Vector2(170.0, 406.5),
	&"SE": Vector2(176.5, 406.5),
}

var action: String = "idle"
var facing: StringName = &"SE"
var elapsed: float = 0.0
var _flash: float = 0.0
var _profile: Dictionary = {}
var _bounds: Rect2
var contact_count: int = 0
var _effects: Node2D
var _cell_by_direction: Dictionary = {}
var _cell_used_rect_by_direction: Dictionary = {}
var _support_center_px_by_direction: Dictionary = {}
var _overhead_rect_by_direction: Dictionary = {}
var _frame_grid: Vector2i = Vector2i.ZERO
var _frame_size: Vector2i = Vector2i.ZERO
var foot_support_center_source_px: Vector2 = Vector2.ZERO


func configure(height: float, presentation_config: Dictionary = {}) -> bool:
	var config: Dictionary = _unwrap_presentation_config(presentation_config)
	var explicit_asset: bool = _has_explicit_asset_fields(config)
	if explicit_asset and not _has_complete_explicit_asset_fields(config):
		return false
	var path: String = ""
	var expected_sha256: String = ""
	if explicit_asset:
		_profile.clear()
		path = str(config.get("texture_path", ""))
		expected_sha256 = str(config.get("sha256", ""))
	else:
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/visual_profiles/kensei_map_token.json"))
		if not value is Dictionary:
			return false
		_profile = value
		path = str(_profile.get("texture_path", ""))
		expected_sha256 = str(_profile.get("sha256", ""))
	if path.is_empty() or expected_sha256.is_empty() or not FileAccess.file_exists(path):
		return false
	if FileAccess.get_sha256(path) != expected_sha256:
		return false
	texture = load(path) as Texture2D
	if texture == null:
		return false
	centered = false
	if not _configure_presentation(config, explicit_asset):
		return false
	hframes = _frame_grid.x
	vframes = _frame_grid.y
	var source: Image = texture.get_image()
	if source == null or source.is_empty():
		return false
	if source.get_width() % _frame_grid.x != 0 or source.get_height() % _frame_grid.y != 0:
		return false
	_frame_size = Vector2i(source.get_width() / _frame_grid.x, source.get_height() / _frame_grid.y)
	if _frame_size.x <= 0 or _frame_size.y <= 0 or not _cache_frame_metrics(source):
		return false
	_effects = Node2D.new()
	_effects.name = "MapContactEffects"
	_effects.z_index = 2
	_effects.draw.connect(_draw_effects)
	add_child(_effects)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var tallest: float = 1.0
	for direction: StringName in DIRECTIONS:
		var used_rect: Rect2i = _cell_used_rect_by_direction[direction]
		tallest = maxf(tallest, float(used_rect.size.y))
	scale = Vector2.ONE * height / tallest
	play("idle", &"SE")
	return true


func _unwrap_presentation_config(value: Dictionary) -> Dictionary:
	var nested_value: Variant = value.get("token_presentation", null)
	if nested_value is Dictionary:
		return nested_value
	return value


func _has_explicit_asset_fields(config: Dictionary) -> bool:
	return config.has("texture_path") or config.has("sha256") or config.has("frame_grid") or config.has("cell_by_direction")


func _has_complete_explicit_asset_fields(config: Dictionary) -> bool:
	return config.has("texture_path") and config.has("sha256") and config.has("frame_grid") \
		and config.has("cell_by_direction") and config.has("support_center_px_by_direction")


func _configure_presentation(config: Dictionary, explicit_asset: bool) -> bool:
	var grid_value: Variant = config.get("frame_grid", null) if explicit_asset else _profile.get("frame_grid", null)
	_frame_grid = _read_frame_grid(grid_value)
	if _frame_grid.x <= 0 or _frame_grid.y <= 0:
		return false

	var next_cells: Dictionary = {}
	var next_centers: Dictionary = {}
	if explicit_asset:
		var explicit_cells_value: Variant = config.get("cell_by_direction", null)
		var explicit_centers_value: Variant = config.get("support_center_px_by_direction", null)
		if not explicit_cells_value is Dictionary or not explicit_centers_value is Dictionary:
			return false
		var explicit_cells: Dictionary = explicit_cells_value
		var explicit_centers: Dictionary = explicit_centers_value
		for direction: StringName in DIRECTIONS:
			var explicit_cell_value: Variant = _direction_value(explicit_cells, direction)
			var explicit_cell: Vector2i = _read_cell(explicit_cell_value)
			if explicit_cell.x < 0 or explicit_cell.y < 0 or explicit_cell.x >= _frame_grid.x or explicit_cell.y >= _frame_grid.y:
				return false
			var explicit_center_value: Variant = _direction_value(explicit_centers, direction)
			var explicit_center: Variant = _read_point(explicit_center_value)
			if explicit_center == null:
				return false
			next_cells[direction] = explicit_cell
			next_centers[direction] = explicit_center
	else:
		var legacy_columns: Dictionary
		var legacy_centers: Dictionary
		if config.is_empty():
			legacy_columns = DEFAULT_COLUMN_BY_DIRECTION
			legacy_centers = DEFAULT_SUPPORT_CENTER_PX_BY_DIRECTION
		else:
			var legacy_columns_value: Variant = config.get("column_by_direction", null)
			var legacy_centers_value: Variant = config.get("support_center_px_by_direction", null)
			if not legacy_columns_value is Dictionary or not legacy_centers_value is Dictionary:
				return false
			legacy_columns = legacy_columns_value
			legacy_centers = legacy_centers_value
		for direction: StringName in DIRECTIONS:
			var legacy_column_value: Variant = _direction_value(legacy_columns, direction)
			var legacy_column: int = _read_integer(legacy_column_value)
			if legacy_column < 0 or legacy_column >= _frame_grid.x:
				return false
			var legacy_center_value: Variant = _direction_value(legacy_centers, direction)
			var legacy_center: Variant = _read_point(legacy_center_value)
			if legacy_center == null:
				return false
			next_cells[direction] = Vector2i(legacy_column, 0)
			next_centers[direction] = legacy_center
	_cell_by_direction = next_cells
	_support_center_px_by_direction = next_centers
	_cell_used_rect_by_direction.clear()
	return true


func _direction_value(values: Dictionary, direction: StringName) -> Variant:
	var key: String = String(direction)
	return values.get(key, values.get(direction, null))


func _read_frame_grid(value: Variant) -> Vector2i:
	var columns_value: Variant = null
	var rows_value: Variant = null
	if value is Array and (value as Array).size() == 2:
		columns_value = (value as Array)[0]
		rows_value = (value as Array)[1]
	elif value is Dictionary:
		var grid: Dictionary = value
		columns_value = grid.get("cols", null)
		rows_value = grid.get("rows", null)
	else:
		return Vector2i.ZERO
	var columns: int = _read_integer(columns_value)
	var rows: int = _read_integer(rows_value)
	if columns <= 0 or rows <= 0:
		return Vector2i.ZERO
	return Vector2i(columns, rows)


func _read_cell(value: Variant) -> Vector2i:
	var x_value: Variant = null
	var y_value: Variant = null
	if value is Array and (value as Array).size() == 2:
		x_value = (value as Array)[0]
		y_value = (value as Array)[1]
	elif value is Dictionary:
		var cell: Dictionary = value
		x_value = cell.get("x", null)
		y_value = cell.get("y", null)
	else:
		return Vector2i(-1, -1)
	var x: int = _read_integer(x_value)
	var y: int = _read_integer(y_value)
	if x < 0 or y < 0:
		return Vector2i(-1, -1)
	return Vector2i(x, y)


func _read_point(value: Variant) -> Variant:
	if typeof(value) == TYPE_VECTOR2:
		var vector_value: Vector2 = value
		if not is_finite(vector_value.x) or not is_finite(vector_value.y):
			return null
		return vector_value
	var x_value: Variant = null
	var y_value: Variant = null
	if value is Array and (value as Array).size() == 2:
		x_value = (value as Array)[0]
		y_value = (value as Array)[1]
	elif value is Dictionary:
		var point_dictionary: Dictionary = value
		x_value = point_dictionary.get("x", null)
		y_value = point_dictionary.get("y", null)
	else:
		return null
	if not _is_number(x_value) or not _is_number(y_value):
		return null
	var source_point: Vector2 = Vector2(float(x_value), float(y_value))
	if not is_finite(source_point.x) or not is_finite(source_point.y):
		return null
	return source_point


func _read_integer(value: Variant) -> int:
	if not _is_number(value):
		return -1
	var number: float = float(value)
	if not is_finite(number) or number != floorf(number) or number > 2147483647.0 or number < -2147483648.0:
		return -1
	return int(number)


func _is_number(value: Variant) -> bool:
	var value_type: int = typeof(value)
	return value_type == TYPE_INT or value_type == TYPE_FLOAT


func _cache_frame_metrics(source: Image) -> bool:
	var next_rects: Dictionary = {}
	_overhead_rect_by_direction.clear()
	for direction: StringName in DIRECTIONS:
		var cell: Vector2i = _cell_by_direction[direction]
		var center: Vector2 = _support_center_px_by_direction[direction]
		if center.x < 0.0 or center.y < 0.0 or center.x > float(_frame_size.x) or center.y > float(_frame_size.y):
			return false
		var cell_origin := Vector2i(cell.x * _frame_size.x, cell.y * _frame_size.y)
		var cell_image: Image = source.get_region(Rect2i(cell_origin, _frame_size))
		if cell_image == null or cell_image.is_empty():
			return false
		var used_rect: Rect2i = cell_image.get_used_rect()
		if used_rect.size.x <= 0 or used_rect.size.y <= 0:
			return false
		next_rects[direction] = used_rect
		# 仅 UI 避让忽略几乎透明的散点；原贴图、绘制 alpha、缩放与足点完全不变。
		var opaque_min := _frame_size
		var opaque_max := Vector2i(-1, -1)
		for y: int in _frame_size.y:
			for x: int in _frame_size.x:
				if cell_image.get_pixel(x, y).a >= 0.125:
					opaque_min = Vector2i(mini(opaque_min.x, x), mini(opaque_min.y, y))
					opaque_max = Vector2i(maxi(opaque_max.x, x), maxi(opaque_max.y, y))
		_overhead_rect_by_direction[direction] = Rect2i(opaque_min, opaque_max - opaque_min + Vector2i.ONE) if opaque_max.x >= 0 else used_rect
	_cell_used_rect_by_direction = next_rects
	return true


func play(next: String, direction: StringName = &"") -> void:
	if DIRECTIONS.has(direction) and not _direction_is_locked() or direction == facing:
		facing = direction
	var already_playing_melee: bool = action == "melee" and elapsed < duration() and next == "melee"
	if action != next or (next == "melee" and not already_playing_melee):
		elapsed = 0.0
	action = next
	_update_pose()


func duration() -> float:
	return 1.0


func impact_delay() -> float:
	return 5.0 / 12.0


func show_contact(direction: StringName) -> void:
	if action != "melee" or elapsed >= duration():
		if DIRECTIONS.has(direction):
			facing = direction
		play("melee", direction)
	# A bound cast/attack keeps the direction selected before contact, even when
	# several targets report contact in different directions.
	if action != "melee":
		return
	_elapsed_at_contact()
	contact_count += 1
	_update_pose()


func _elapsed_at_contact() -> void:
	elapsed = maxf(elapsed, impact_delay())


func show_hit() -> void:
	_flash = 0.20


func cancel_presentation() -> void:
	_flash = 0.0
	self_modulate = Color.WHITE
	play("idle", facing)
	position = Vector2.ZERO


func visible_local_rect() -> Rect2:
	return _bounds


## 固定四向联合上沿；武器/alpha 包围盒中心不能充当人物所属锚点。
func overhead_anchor_world_position() -> Vector2:
	var top: float = 0.0
	for direction: StringName in DIRECTIONS:
		var used: Rect2i = _overhead_rect_by_direction[direction]
		var support: Vector2 = _support_center_px_by_direction[direction]
		top = minf(top, float(used.position.y) - support.y)
	return to_global(Vector2(0.0, top))


func overhead_obstacle_rect_local() -> Rect2:
	var used: Rect2i = _overhead_rect_by_direction[facing]
	return Rect2(Vector2(used.position) - foot_support_center_source_px, Vector2(used.size))


func get_foot_local() -> Vector2:
	return foot_support_center_source_px + offset


func foot_support_world_position() -> Vector2:
	return to_global(get_foot_local())


func direction_for_screen_vector(screen_vector: Vector2) -> StringName:
	if screen_vector.is_zero_approx():
		return facing
	var normalized: Vector2 = screen_vector.normalized()
	var best_score: float = -INF
	var best_directions: Array[StringName] = []
	for direction: StringName in DIRECTIONS:
		var candidate: Vector2 = (SCREEN_DIRECTION[direction] as Vector2).normalized()
		var score: float = normalized.dot(candidate)
		if score > best_score + 0.0001:
			best_score = score
			best_directions = [direction]
		elif absf(score - best_score) <= 0.0001:
			best_directions.append(direction)
	if best_directions.has(facing):
		return facing
	return best_directions[0] if not best_directions.is_empty() else facing


func _direction_is_locked() -> bool:
	return action == "melee" and elapsed < duration()


func _process(delta: float) -> void:
	elapsed += delta
	_flash = maxf(_flash - delta, 0.0)
	self_modulate = Color(1.6, 1.18, 1.12) if _flash > 0.0 else Color.WHITE
	if action == "melee" and elapsed >= duration():
		play("idle")
	_update_pose()


func _update_pose() -> void:
	if texture == null:
		return
	if not _cell_by_direction.has(facing) or not _support_center_px_by_direction.has(facing) \
		or not _cell_used_rect_by_direction.has(facing):
		return
	var cell: Vector2i = _cell_by_direction[facing]
	frame_coords = cell
	foot_support_center_source_px = _support_center_px_by_direction[facing]
	offset = -foot_support_center_source_px
	var used_rect: Rect2i = _cell_used_rect_by_direction[facing]
	_bounds = Rect2(Vector2(used_rect.position) - foot_support_center_source_px, Vector2(used_rect.size))
	# The feet stay on the Unit/grid anchor during attacks; only effects animate.
	position = Vector2.ZERO
	if is_instance_valid(_effects):
		_effects.queue_redraw()


func _draw_effects() -> void:
	# Local source-pixel units scale with the approved token; effects remain on the map.
	if _flash > 0.0:
		var center := Vector2(0, -150)
		var glow := Color(1.0, 0.92, 0.66, minf(1.0, _flash / 0.10))
		for spoke: int in range(4):
			var ray := Vector2.from_angle(float(spoke) * PI / 4.0) * 48.0
			_effects.draw_line(center - ray, center + ray, Color(0.15, 0.11, 0.08, glow.a), 17.0, true)
			_effects.draw_line(center - ray, center + ray, glow, 8.0, true)
	if action != "melee" or elapsed < impact_delay() or elapsed > impact_delay() + 0.26:
		return
	var fade: float = 1.0 - (elapsed - impact_delay()) / 0.26
	var forward: Vector2 = (SCREEN_DIRECTION[facing] as Vector2).normalized()
	var center: Vector2 = Vector2(0, -130) + forward * 130
	var points := PackedVector2Array()
	for index: int in range(13):
		var angle: float = forward.angle() - 1.0 + float(index) / 6.0
		points.append(center + Vector2.from_angle(angle) * 110.0)
	_effects.draw_polyline(points, Color(0.16, 0.12, 0.09, fade * 0.9), 34.0, true)
	_effects.draw_polyline(points, Color(0.92, 0.85, 0.65, fade), 23.0, true)
	_effects.draw_polyline(points, Color(1, 0.97, 0.88, fade), 8.0, true)
