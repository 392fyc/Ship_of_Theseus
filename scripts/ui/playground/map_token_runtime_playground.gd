extends Control
## 已批准高精度战棋人物的隔离运行时检查场。
##
## 该场景只读取视觉样本清单中的 runtime_candidate，不接入正式 Unit 或 TacticalScene。

const MANIFEST_PATH: String = "res://assets/prototype/visual_style/sample_manifest.json"
const SCREENSHOT_ROOT: String = "user://visual_style_playground/map_token_runtime/"
const FILTER_MODES: Array[String] = ["nearest", "linear"]
const CHECK_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const LOGICAL_STAGE_SIZE: Vector2i = Vector2i(1280, 720)
const STRESS_GRID_SIZE: Vector2i = Vector2i(7, 5)
const DIRECTION_AXES: Dictionary = {
	"NW": Vector2i(-1, 0),
	"NE": Vector2i(0, -1),
	"SW": Vector2i(0, 1),
	"SE": Vector2i(1, 0),
}
const COLOR_BACKGROUND: Color = Color("10131b")
const COLOR_PANEL: Color = Color("191d29")
const COLOR_TILE: Color = Color("303848")
const COLOR_TILE_SELECTED: Color = Color("665f4b")
const COLOR_TILE_BORDER: Color = Color("8c7b58")
const COLOR_TEXT: Color = Color("e8dfcf")
const COLOR_SUBTLE: Color = Color("a69e91")

var _runtime_candidate: Dictionary = {}
var _frame_specs: Array[Dictionary] = []
var _sprites: Array[Sprite2D] = []
var _tiles: Array[Polygon2D] = []
var _frame_labels: Array[Label] = []
var _stress_grid_specs: Array[Dictionary] = []
var _stress_sprites: Array[Sprite2D] = []
var _comparison_sprites: Array[Sprite2D] = []
var _check_size: Vector2i = CHECK_SIZES[0]
var _stage_scale: float = 1.0
var _filter_mode: String = "linear"
var _selected_variant: String = "single_weapon"
var _selected_direction: String = "NW"
var _render_viewport: SubViewport = null
var _viewport_container: SubViewportContainer = null
var _canvas_root: Control = null
var _stage_root: Control = null
var _preview_root: Node2D = null
var _stress_root: Node2D = null
var _comparison_root: Node2D = null
var _filter_button: Button = null
var _size_option: OptionButton = null
var _variant_option: OptionButton = null
var _direction_option: OptionButton = null
var _status_label: Label = null
var _capture_failed: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not _load_runtime_candidate():
		return
	_build_render_canvas()
	_build_interface()
	_build_frames()
	_build_stress_grid()
	_build_filter_comparison()
	set_filter_mode(str(_runtime_candidate.get("default_filter", "linear")))
	set_check_size(CHECK_SIZES[0])
	_refresh_selection()
	if OS.get_cmdline_user_args().has("--capture-all"):
		_capture_all.call_deferred()


func get_frame_specs() -> Array:
	var result: Array = []
	for spec: Dictionary in _frame_specs:
		result.append(spec.duplicate())
	return result


func get_sprite_nodes() -> Array:
	var result: Array = []
	for sprite: Sprite2D in _sprites:
		result.append(sprite)
	return result


func get_direction_axes() -> Dictionary:
	return DIRECTION_AXES.duplicate()


func get_stress_grid_specs() -> Array:
	var result: Array = []
	for spec: Dictionary in _stress_grid_specs:
		result.append(spec.duplicate())
	return result


func get_stress_sprite_nodes() -> Array:
	var result: Array = []
	for sprite: Sprite2D in _stress_sprites:
		result.append(sprite)
	return result


func get_filter_comparison_nodes() -> Array:
	var result: Array = []
	for sprite: Sprite2D in _comparison_sprites:
		result.append(sprite)
	return result


func get_stage_scale() -> float:
	return _stage_scale


func get_filter_mode() -> String:
	return _filter_mode


func set_filter_mode(mode: String) -> void:
	if not FILTER_MODES.has(mode):
		return
	_filter_mode = mode
	var filter_value: CanvasItem.TextureFilter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
		if mode == "nearest"
		else CanvasItem.TEXTURE_FILTER_LINEAR
	)
	for sprite: Sprite2D in _sprites:
		sprite.texture_filter = filter_value
	for sprite: Sprite2D in _stress_sprites:
		sprite.texture_filter = filter_value
	if _filter_button != null:
		_filter_button.text = "过滤：%s" % ("Nearest" if mode == "nearest" else "Linear")


func get_check_sizes() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for size: Vector2i in CHECK_SIZES:
		result.append(size)
	return result


func get_check_size() -> Vector2i:
	return _check_size


func set_check_size(check_size: Vector2i) -> void:
	if not CHECK_SIZES.has(check_size):
		return
	_check_size = check_size
	if _render_viewport != null:
		_render_viewport.size = check_size
	if _viewport_container != null:
		_viewport_container.custom_minimum_size = Vector2(check_size)
	if DisplayServer.get_name() != "headless":
		get_window().size = check_size
	if _size_option != null:
		_size_option.select(CHECK_SIZES.find(check_size))
	_update_stage_transform()
	_update_layout()


func get_capture_plan(batch: String) -> Array:
	var safe_batch: String = _sanitize_batch_name(batch)
	var result: Array = []
	for size: Vector2i in CHECK_SIZES:
		for mode: String in FILTER_MODES:
			var file_name: String = "map_token_%dx%d_%s.png" % [size.x, size.y, mode]
			result.append({
				"check_size": size,
				"filter_mode": mode,
				"file_name": file_name,
				"target_path": "%s%s/%s" % [SCREENSHOT_ROOT, safe_batch, file_name],
			})
	return result


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F:
			set_filter_mode("linear" if _filter_mode == "nearest" else "nearest")
		KEY_R:
			var next_size_index: int = (CHECK_SIZES.find(_check_size) + 1) % CHECK_SIZES.size()
			set_check_size(CHECK_SIZES[next_size_index])
		KEY_V:
			_select_next_variant()
		KEY_D:
			_select_next_direction()


func _load_runtime_candidate() -> bool:
	var file: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		push_error("无法读取视觉样本清单：%s" % MANIFEST_PATH)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("视觉样本清单不是 JSON 对象")
		return false
	var samples_value: Variant = (parsed as Dictionary).get("samples", [])
	if typeof(samples_value) != TYPE_ARRAY:
		push_error("视觉样本清单缺少 samples 数组")
		return false
	for sample_value: Variant in samples_value as Array:
		if typeof(sample_value) != TYPE_DICTIONARY:
			continue
		var sample: Dictionary = sample_value as Dictionary
		if str(sample.get("id", "")) != "map_token":
			continue
		var candidate_value: Variant = sample.get("runtime_candidate", {})
		if typeof(candidate_value) == TYPE_DICTIONARY:
			_runtime_candidate = (candidate_value as Dictionary).duplicate(true)
			return _validate_runtime_candidate()
	push_error("map_token 样本缺少 runtime_candidate")
	return false


func _validate_runtime_candidate() -> bool:
	var source_path: String = str(_runtime_candidate.get("source_path", ""))
	var source_size: Vector2i = _array_to_size(_runtime_candidate.get("pixel_size", []))
	var frame_grid: Vector2i = _array_to_size(_runtime_candidate.get("frame_grid", []))
	var frame_size: Vector2i = _array_to_size(_runtime_candidate.get("source_frame_size", []))
	var variants: Array = _runtime_candidate.get("variant_order", []) as Array
	var directions: Array = _runtime_candidate.get("direction_order", []) as Array
	var pivots: Array = _runtime_candidate.get("frame_pivot", []) as Array
	if (
		not source_path.begins_with("res://assets/prototype/visual_style/samples/")
		or not source_path.ends_with(".png")
		or source_size != Vector2i(1536, 1024)
		or frame_grid != Vector2i(4, 2)
		or frame_size != Vector2i(384, 512)
		or frame_size * frame_grid != source_size
		or variants.size() != 2
		or directions.size() != 4
		or not _frame_pivots_are_valid(pivots, frame_size)
	):
		push_error("map_token runtime_candidate 切帧合同无效")
		return false
	if not FileAccess.file_exists(source_path):
		push_error("map_token runtime_candidate 文件不存在：%s" % source_path)
		return false
	return true


func _build_render_canvas() -> void:
	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "RenderViewportContainer"
	_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport_container.stretch = false
	_viewport_container.mouse_target = true
	_viewport_container.custom_minimum_size = Vector2(_check_size)
	add_child(_viewport_container)

	_render_viewport = SubViewport.new()
	_render_viewport.name = "RenderViewport"
	_render_viewport.size = _check_size
	_render_viewport.disable_3d = true
	_render_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport_container.add_child(_render_viewport)

	_canvas_root = Control.new()
	_canvas_root.name = "CanvasRoot"
	_canvas_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_render_viewport.add_child(_canvas_root)

	var background: ColorRect = ColorRect.new()
	background.name = "Background"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = COLOR_BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas_root.add_child(background)

	_stage_root = Control.new()
	_stage_root.name = "LogicalStage"
	_stage_root.size = Vector2(LOGICAL_STAGE_SIZE)
	_canvas_root.add_child(_stage_root)


func _build_interface() -> void:
	var title: Label = Label.new()
	title.name = "Title"
	title.text = "高精度战棋人物 · 64×32 菱形格运行时检查"
	title.position = Vector2(28, 20)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	title.add_theme_font_size_override("font_size", 24)
	_stage_root.add_child(title)

	var controls: HBoxContainer = HBoxContainer.new()
	controls.name = "Controls"
	controls.position = Vector2(28, 60)
	controls.add_theme_constant_override("separation", 10)
	_stage_root.add_child(controls)

	_filter_button = Button.new()
	_filter_button.name = "FilterModeButton"
	_filter_button.tooltip_text = "切换纹理过滤方式（F）"
	_filter_button.pressed.connect(_toggle_filter)
	controls.add_child(_filter_button)

	_size_option = OptionButton.new()
	_size_option.name = "CheckSizeOption"
	for size: Vector2i in CHECK_SIZES:
		_size_option.add_item("%d×%d" % [size.x, size.y])
	_size_option.item_selected.connect(_on_check_size_selected)
	controls.add_child(_size_option)

	_variant_option = OptionButton.new()
	_variant_option.name = "VariantOption"
	_variant_option.add_item("单武器")
	_variant_option.add_item("双武器")
	_variant_option.item_selected.connect(_on_variant_selected)
	controls.add_child(_variant_option)

	_direction_option = OptionButton.new()
	_direction_option.name = "DirectionOption"
	for direction: String in ["NW", "NE", "SW", "SE"]:
		_direction_option.add_item(direction)
	_direction_option.item_selected.connect(_on_direction_selected)
	controls.add_child(_direction_option)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.position = Vector2(28, 104)
	_status_label.add_theme_color_override("font_color", COLOR_SUBTLE)
	_stage_root.add_child(_status_label)

	_preview_root = Node2D.new()
	_preview_root.name = "PreviewRoot"
	_stage_root.add_child(_preview_root)

	var overview_label: Label = Label.new()
	overview_label.name = "OverviewLabel"
	overview_label.text = "八方向总览"
	overview_label.position = Vector2(84, 142)
	overview_label.add_theme_color_override("font_color", COLOR_TEXT)
	overview_label.add_theme_font_size_override("font_size", 18)
	_stage_root.add_child(overview_label)


func _build_frames() -> void:
	var source_path: String = str(_runtime_candidate.get("source_path", ""))
	var texture: Texture2D = load(source_path) as Texture2D
	if texture == null:
		push_error("无法加载 map_token runtime_candidate：%s" % source_path)
		return
	var frame_size: Vector2i = _array_to_size(_runtime_candidate.get("source_frame_size", []))
	var variants: Array = _runtime_candidate.get("variant_order", []) as Array
	var directions: Array = _runtime_candidate.get("direction_order", []) as Array
	var pivots: Array = _runtime_candidate.get("frame_pivot", []) as Array
	var display_scale: float = float(_runtime_candidate.get("display_scale", 0.15625))
	for row: int in range(variants.size()):
		for column: int in range(directions.size()):
			var index: int = row * directions.size() + column
			var region: Rect2 = Rect2(
				Vector2(column * frame_size.x, row * frame_size.y),
				Vector2(frame_size)
			)
			var spec: Dictionary = {
				"variant": str(variants[row]),
				"direction": str(directions[column]),
				"region": region,
				"frame_pivot": _array_to_vector2(pivots[index]),
			}
			_frame_specs.append(spec)

			var tile: Polygon2D = Polygon2D.new()
			tile.name = "Tile_%d" % index
			tile.polygon = PackedVector2Array([
				Vector2(-32, 0),
				Vector2(0, -16),
				Vector2(32, 0),
				Vector2(0, 16),
			])
			tile.color = COLOR_TILE
			_preview_root.add_child(tile)
			_tiles.append(tile)

			var outline: Line2D = Line2D.new()
			outline.name = "TileOutline_%d" % index
			outline.points = PackedVector2Array([
				Vector2(-32, 0),
				Vector2(0, -16),
				Vector2(32, 0),
				Vector2(0, 16),
				Vector2(-32, 0),
			])
			outline.width = 1.0
			outline.default_color = COLOR_TILE_BORDER
			tile.add_child(outline)

			var sprite: Sprite2D = Sprite2D.new()
			sprite.name = "%s_%s" % [str(variants[row]), str(directions[column])]
			sprite.texture = texture
			sprite.region_enabled = true
			sprite.region_rect = region
			sprite.region_filter_clip_enabled = true
			sprite.centered = false
			sprite.scale = Vector2(display_scale, display_scale)
			sprite.set_meta("variant", str(variants[row]))
			sprite.set_meta("direction", str(directions[column]))
			sprite.set_meta("frame_pivot", spec.get("frame_pivot", Vector2.ZERO) as Vector2)
			_preview_root.add_child(sprite)
			_sprites.append(sprite)

			var label: Label = Label.new()
			label.name = "FrameLabel_%d" % index
			label.text = "%s · %s" % ["单武器" if row == 0 else "双武器", str(directions[column])]
			label.add_theme_color_override("font_color", COLOR_SUBTLE)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.size = Vector2(128, 28)
			_preview_root.add_child(label)
			_frame_labels.append(label)
	_update_layout()


func _build_stress_grid() -> void:
	_stress_root = Node2D.new()
	_stress_root.name = "StressGrid"
	_stage_root.add_child(_stress_root)

	var heading: Label = Label.new()
	heading.name = "StressGridLabel"
	heading.text = "7×5 连续格 · 相邻遮挡压力区"
	heading.position = Vector2(748, 142)
	heading.add_theme_color_override("font_color", COLOR_TEXT)
	heading.add_theme_font_size_override("font_size", 18)
	_stage_root.add_child(heading)

	var tile_size: Vector2i = _array_to_size(_runtime_candidate.get("tile_size", []))
	var grid_origin: Vector2 = Vector2(900, 190)
	for y: int in range(STRESS_GRID_SIZE.y):
		for x: int in range(STRESS_GRID_SIZE.x):
			var logical_position: Vector2i = Vector2i(x, y)
			var screen_center: Vector2 = Vector2(
				float(x - y) * float(tile_size.x) * 0.5,
				float(x + y) * float(tile_size.y) * 0.5
			)
			_stress_grid_specs.append({
				"logical_position": logical_position,
				"screen_center": screen_center,
				"tile_size": tile_size,
			})
			var tile: Polygon2D = _make_diamond_tile(tile_size, COLOR_TILE)
			tile.name = "StressTile_%d_%d" % [x, y]
			tile.position = grid_origin + screen_center
			tile.z_index = 0
			_stress_root.add_child(tile)

	var placements: Array[Dictionary] = [
		{"logical_position": Vector2i(2, 1), "variant": "single_weapon", "direction": "SE"},
		{"logical_position": Vector2i(3, 1), "variant": "dual_weapon", "direction": "NW"},
		{"logical_position": Vector2i(2, 2), "variant": "dual_weapon", "direction": "SE"},
		{"logical_position": Vector2i(3, 2), "variant": "single_weapon", "direction": "NE"},
		{"logical_position": Vector2i(4, 2), "variant": "dual_weapon", "direction": "SW"},
		{"logical_position": Vector2i(2, 3), "variant": "single_weapon", "direction": "NW"},
		{"logical_position": Vector2i(3, 3), "variant": "dual_weapon", "direction": "NE"},
		{"logical_position": Vector2i(4, 3), "variant": "single_weapon", "direction": "SE"},
	]
	placements.sort_custom(_stress_placement_before)
	var display_scale: float = float(_runtime_candidate.get("display_scale", 0.15625))
	var texture: Texture2D = load(str(_runtime_candidate.get("source_path", ""))) as Texture2D
	for placement: Dictionary in placements:
		var variant: String = str(placement.get("variant", ""))
		var direction: String = str(placement.get("direction", ""))
		var spec: Dictionary = _find_frame_spec(variant, direction)
		var logical_position: Vector2i = placement.get("logical_position", Vector2i.ZERO) as Vector2i
		var screen_center: Vector2 = Vector2(
			float(logical_position.x - logical_position.y) * float(tile_size.x) * 0.5,
			float(logical_position.x + logical_position.y) * float(tile_size.y) * 0.5
		)
		var sprite: Sprite2D = _make_frame_sprite(texture, spec, display_scale)
		sprite.name = "Stress_%s_%s_%d_%d" % [variant, direction, logical_position.x, logical_position.y]
		var frame_pivot: Vector2 = spec.get("frame_pivot", Vector2.ZERO) as Vector2
		sprite.position = grid_origin + screen_center - frame_pivot * display_scale
		sprite.z_index = (logical_position.x + logical_position.y) * 10 + logical_position.x
		sprite.set_meta("logical_position", logical_position)
		sprite.set_meta("tile_center", grid_origin + screen_center)
		_stress_root.add_child(sprite)
		_stress_sprites.append(sprite)


func _build_filter_comparison() -> void:
	_comparison_root = Node2D.new()
	_comparison_root.name = "FilterComparison"
	_stage_root.add_child(_comparison_root)

	var heading: Label = Label.new()
	heading.name = "FilterComparisonLabel"
	heading.text = "同帧过滤对照 · dual SE"
	heading.position = Vector2(800, 462)
	heading.add_theme_color_override("font_color", COLOR_TEXT)
	heading.add_theme_font_size_override("font_size", 18)
	_stage_root.add_child(heading)

	var texture: Texture2D = load(str(_runtime_candidate.get("source_path", ""))) as Texture2D
	var spec: Dictionary = _find_frame_spec("dual_weapon", "SE")
	var display_scale: float = float(_runtime_candidate.get("display_scale", 0.15625)) * 1.6
	var tile_size: Vector2i = _array_to_size(_runtime_candidate.get("tile_size", []))
	var centers: Array[Vector2] = [Vector2(875, 565), Vector2(1065, 565)]
	var modes: Array[String] = ["nearest", "linear"]
	for index: int in range(2):
		var tile: Polygon2D = _make_diamond_tile(tile_size, COLOR_TILE_SELECTED)
		tile.position = centers[index]
		_comparison_root.add_child(tile)
		var sprite: Sprite2D = _make_frame_sprite(texture, spec, display_scale)
		sprite.name = "Comparison%s" % modes[index].capitalize()
		var frame_pivot: Vector2 = spec.get("frame_pivot", Vector2.ZERO) as Vector2
		sprite.position = centers[index] - frame_pivot * display_scale
		sprite.texture_filter = (
			CanvasItem.TEXTURE_FILTER_NEAREST
			if modes[index] == "nearest"
			else CanvasItem.TEXTURE_FILTER_LINEAR
		)
		_comparison_root.add_child(sprite)
		_comparison_sprites.append(sprite)

		var label: Label = Label.new()
		label.name = "Comparison%sLabel" % modes[index].capitalize()
		label.text = modes[index].capitalize()
		label.position = centers[index] + Vector2(-50, 42)
		label.size = Vector2(100, 28)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", COLOR_TEXT)
		_stage_root.add_child(label)


func _update_layout() -> void:
	if _preview_root == null or _frame_specs.size() != 8:
		return
	var horizontal_gap: float = 150.0
	var vertical_gap: float = 150.0
	var center: Vector2 = Vector2(365, 285)
	var display_scale: float = float(_runtime_candidate.get("display_scale", 0.15625))
	for index: int in range(_frame_specs.size()):
		var row: int = index / 4
		var column: int = index % 4
		var tile_center: Vector2 = center + Vector2(
			(float(column) - 1.5) * horizontal_gap,
			(float(row) - 0.5) * vertical_gap
		)
		_tiles[index].position = tile_center
		var spec: Dictionary = _frame_specs[index]
		var frame_pivot: Vector2 = spec.get("frame_pivot", Vector2.ZERO) as Vector2
		var sprite: Sprite2D = _sprites[index]
		sprite.position = tile_center - frame_pivot * display_scale
		sprite.set_meta("tile_center", tile_center)
		_frame_labels[index].position = tile_center + Vector2(-64, 27)


func _update_stage_transform() -> void:
	if _stage_root == null:
		return
	_stage_scale = minf(
		float(_check_size.x) / float(LOGICAL_STAGE_SIZE.x),
		float(_check_size.y) / float(LOGICAL_STAGE_SIZE.y)
	)
	_stage_root.scale = Vector2(_stage_scale, _stage_scale)
	_stage_root.position = (
		Vector2(_check_size) - Vector2(LOGICAL_STAGE_SIZE) * _stage_scale
	) * 0.5


func _make_diamond_tile(tile_size: Vector2i, color: Color) -> Polygon2D:
	var half_width: float = float(tile_size.x) * 0.5
	var half_height: float = float(tile_size.y) * 0.5
	var tile: Polygon2D = Polygon2D.new()
	tile.polygon = PackedVector2Array([
		Vector2(-half_width, 0),
		Vector2(0, -half_height),
		Vector2(half_width, 0),
		Vector2(0, half_height),
	])
	tile.color = color
	var outline: Line2D = Line2D.new()
	outline.points = PackedVector2Array([
		Vector2(-half_width, 0),
		Vector2(0, -half_height),
		Vector2(half_width, 0),
		Vector2(0, half_height),
		Vector2(-half_width, 0),
	])
	outline.width = 1.0
	outline.default_color = COLOR_TILE_BORDER
	tile.add_child(outline)
	return tile


func _make_frame_sprite(texture: Texture2D, spec: Dictionary, display_scale: float) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.region_enabled = true
	sprite.region_rect = spec.get("region", Rect2()) as Rect2
	sprite.region_filter_clip_enabled = true
	sprite.centered = false
	sprite.scale = Vector2(display_scale, display_scale)
	sprite.set_meta("variant", str(spec.get("variant", "")))
	sprite.set_meta("direction", str(spec.get("direction", "")))
	sprite.set_meta("frame_pivot", spec.get("frame_pivot", Vector2.ZERO) as Vector2)
	return sprite


func _find_frame_spec(variant: String, direction: String) -> Dictionary:
	for spec: Dictionary in _frame_specs:
		if str(spec.get("variant", "")) == variant and str(spec.get("direction", "")) == direction:
			return spec
	return {}


func _stress_placement_before(first: Dictionary, second: Dictionary) -> bool:
	var first_position: Vector2i = first.get("logical_position", Vector2i.ZERO) as Vector2i
	var second_position: Vector2i = second.get("logical_position", Vector2i.ZERO) as Vector2i
	var first_depth: int = first_position.x + first_position.y
	var second_depth: int = second_position.x + second_position.y
	if first_depth == second_depth:
		return first_position.x < second_position.x
	return first_depth < second_depth


func _refresh_selection() -> void:
	for index: int in range(_frame_specs.size()):
		var spec: Dictionary = _frame_specs[index]
		var selected: bool = (
			str(spec.get("variant", "")) == _selected_variant
			and str(spec.get("direction", "")) == _selected_direction
		)
		_tiles[index].color = COLOR_TILE_SELECTED if selected else COLOR_TILE
		_sprites[index].modulate = Color.WHITE if selected else Color(0.72, 0.72, 0.72, 1.0)
	if _status_label != null:
		_status_label.text = "当前：%s · %s · %s · %d×%d" % [
			"单武器" if _selected_variant == "single_weapon" else "双武器",
			_selected_direction,
			"Nearest" if _filter_mode == "nearest" else "Linear",
			_check_size.x,
			_check_size.y,
		]


func _toggle_filter() -> void:
	set_filter_mode("linear" if _filter_mode == "nearest" else "nearest")
	_refresh_selection()


func _select_next_variant() -> void:
	_selected_variant = "dual_weapon" if _selected_variant == "single_weapon" else "single_weapon"
	if _variant_option != null:
		_variant_option.select(0 if _selected_variant == "single_weapon" else 1)
	_refresh_selection()


func _select_next_direction() -> void:
	var directions: Array[String] = ["NW", "NE", "SW", "SE"]
	var next_index: int = (directions.find(_selected_direction) + 1) % directions.size()
	_selected_direction = directions[next_index]
	if _direction_option != null:
		_direction_option.select(next_index)
	_refresh_selection()


func _on_check_size_selected(index: int) -> void:
	if index >= 0 and index < CHECK_SIZES.size():
		set_check_size(CHECK_SIZES[index])
		_refresh_selection()


func _on_variant_selected(index: int) -> void:
	_selected_variant = "single_weapon" if index == 0 else "dual_weapon"
	_refresh_selection()


func _on_direction_selected(index: int) -> void:
	var directions: Array[String] = ["NW", "NE", "SW", "SE"]
	if index >= 0 and index < directions.size():
		_selected_direction = directions[index]
		_refresh_selection()


func _capture_all() -> void:
	var batch: String = _make_batch_name()
	var plan: Array = get_capture_plan(batch)
	var absolute_directory: String = ProjectSettings.globalize_path(SCREENSHOT_ROOT + batch + "/")
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK:
		push_error("无法创建截图批次目录：%s" % error_string(directory_error))
		get_tree().quit(1)
		return
	for entry_value: Variant in plan:
		var entry: Dictionary = entry_value as Dictionary
		set_check_size(entry.get("check_size", Vector2i.ZERO) as Vector2i)
		set_filter_mode(str(entry.get("filter_mode", "")))
		_refresh_selection()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image = _render_viewport.get_texture().get_image()
		var expected_size: Vector2i = entry.get("check_size", Vector2i.ZERO) as Vector2i
		if Vector2i(image.get_width(), image.get_height()) != expected_size:
			_capture_failed = true
			push_error("截图尺寸错误：%s != %s" % [Vector2i(image.get_width(), image.get_height()), expected_size])
			continue
		var target_path: String = str(entry.get("target_path", ""))
		var save_error: Error = image.save_png(target_path)
		if save_error != OK:
			_capture_failed = true
			push_error("截图保存失败：%s（%s）" % [target_path, error_string(save_error)])
		else:
			print("MAP_TOKEN_RUNTIME_CAPTURED=%s" % ProjectSettings.globalize_path(target_path))
	print("MAP_TOKEN_RUNTIME_CAPTURE_DIR=%s" % absolute_directory)
	get_tree().quit(1 if _capture_failed else 0)


func _make_batch_name() -> String:
	var timestamp: String = Time.get_datetime_string_from_system(false, true)
	return _sanitize_batch_name(timestamp.replace("-", "").replace(":", "").replace("T", "_").replace(" ", "_"))


func _sanitize_batch_name(value: String) -> String:
	var result: String = value.strip_edges()
	for forbidden: String in ["/", "\\", ":", ".."]:
		result = result.replace(forbidden, "_")
	return result if result != "" else "batch"


func _array_to_size(value: Variant) -> Vector2i:
	if typeof(value) != TYPE_ARRAY:
		return Vector2i.ZERO
	var values: Array = value as Array
	if values.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(values[0]), int(values[1]))


func _array_to_vector2(value: Variant) -> Vector2:
	if typeof(value) != TYPE_ARRAY:
		return Vector2.ZERO
	var values: Array = value as Array
	if values.size() != 2:
		return Vector2.ZERO
	return Vector2(float(values[0]), float(values[1]))


func _frame_pivots_are_valid(pivots: Array, frame_size: Vector2i) -> bool:
	if pivots.size() != 8:
		return false
	for pivot_value: Variant in pivots:
		if typeof(pivot_value) != TYPE_ARRAY:
			return false
		var components: Array = pivot_value as Array
		if components.size() != 2:
			return false
		if not (
			typeof(components[0]) in [TYPE_INT, TYPE_FLOAT]
			and typeof(components[1]) in [TYPE_INT, TYPE_FLOAT]
		):
			return false
		var frame_pivot: Vector2 = Vector2(float(components[0]), float(components[1]))
		if (
			frame_pivot.x < 0.0
			or frame_pivot.x >= float(frame_size.x)
			or frame_pivot.y < 0.0
			or frame_pivot.y >= float(frame_size.y)
		):
			return false
	return true
