extends SceneTree
## 高精度战棋人物隔离运行时预览合同测试。
##
## 运行：
##   <Godot_console.exe> --headless --path <worktree> \
##     --script res://tests/test_map_token_runtime_playground.gd

const MANIFEST_PATH: String = "res://assets/prototype/visual_style/sample_manifest.json"
const ASSET_PATH: String = "res://assets/prototype/visual_style/samples/map_token_source_transparent_clean_v2.png"
const SCENE_PATH: String = "res://scenes/playground/map_token_runtime_playground.tscn"
const SCRIPT_PATH: String = "res://scripts/ui/playground/map_token_runtime_playground.gd"
const EXPECTED_SHA256: String = "e6f33324c52929769d4698ed75e969470ec45748788503f4637fcb3223dc5415"
const EXPECTED_SOURCE_SIZE: Vector2i = Vector2i(1536, 1024)
const EXPECTED_SOURCE_FRAME_SIZE: Vector2i = Vector2i(384, 512)
const EXPECTED_TILE_SIZE: Vector2i = Vector2i(64, 32)
const EXPECTED_DISPLAY_SCALE: float = 0.15625
const EXPECTED_STRESS_GRID_SIZE: Vector2i = Vector2i(7, 5)
const EXPECTED_CHECK_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const EXPECTED_VARIANTS: Array[String] = ["single_weapon", "dual_weapon"]
const EXPECTED_DIRECTIONS: Array[String] = ["NW", "NE", "SW", "SE"]
const EXPECTED_FOOT_ANCHORS: Array[int] = [405, 406, 424, 423, 358, 357, 381, 380]
const EXPECTED_REGIONS: Array[Rect2] = [
	Rect2(0, 0, 384, 512),
	Rect2(384, 0, 384, 512),
	Rect2(768, 0, 384, 512),
	Rect2(1152, 0, 384, 512),
	Rect2(0, 512, 384, 512),
	Rect2(384, 512, 384, 512),
	Rect2(768, 512, 384, 512),
	Rect2(1152, 512, 384, 512),
]
const EXPECTED_CAPTURE_NAMES: Array[String] = [
	"map_token_1280x720_nearest.png",
	"map_token_1280x720_linear.png",
	"map_token_1920x1080_nearest.png",
	"map_token_1920x1080_linear.png",
	"map_token_2560x1440_nearest.png",
	"map_token_2560x1440_linear.png",
]
const EXPECTED_APPROVED_PREVIEW: Dictionary = {
	"file_name": "map_token_preview_final_v2.png",
	"sha256": "9c828acb5caa501a351c6628311f8d29692c9ca4454e1614dab891444b61637f",
	"pixel_size": [1536, 1024],
	"identity_scope": "external_review_artifact",
}

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_map_token_runtime_playground ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	_check_manifest_and_asset_contract()
	await _check_runtime_scene_contract()
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for failure: String in _fails:
			print("  ✗ " + failure)
	quit(0 if _fail == 0 else 1)


func _check_manifest_and_asset_contract() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	_check("样本清单是 JSON 对象", typeof(parsed) == TYPE_DICTIONARY)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var manifest: Dictionary = parsed as Dictionary
	var map_token: Dictionary = _find_sample(manifest.get("samples", []), "map_token")
	_check("map_token 样本存在", not map_token.is_empty())
	if map_token.is_empty():
		return
	_check(
		"旧 approved_preview 身份保持不变",
		_approved_preview_matches(map_token.get("approved_preview", {})),
		str(map_token.get("approved_preview", {}))
	)

	var runtime_value: Variant = map_token.get("runtime_candidate", null)
	_check("map_token 声明 runtime_candidate 对象", typeof(runtime_value) == TYPE_DICTIONARY)
	if typeof(runtime_value) != TYPE_DICTIONARY:
		return
	var runtime: Dictionary = runtime_value as Dictionary
	_check("运行时候选路径精确", str(runtime.get("source_path", "")) == ASSET_PATH)
	_check("运行时候选文件名精确", str(runtime.get("file_name", "")) == "map_token_source_transparent_clean_v2.png")
	_check("运行时候选 SHA256 精确", str(runtime.get("sha256", "")) == EXPECTED_SHA256)
	_check("运行时候选源尺寸为 1536×1024", _as_size(runtime.get("pixel_size", [])) == EXPECTED_SOURCE_SIZE)
	_check("运行时候选切帧为 4×2", _as_size(runtime.get("frame_grid", [])) == Vector2i(4, 2))
	_check("运行时候选单帧为 384×512", _as_size(runtime.get("source_frame_size", [])) == EXPECTED_SOURCE_FRAME_SIZE)
	_check("运行时候选变体顺序精确", runtime.get("variant_order", []) == EXPECTED_VARIANTS)
	_check("运行时候选方向顺序精确", runtime.get("direction_order", []) == EXPECTED_DIRECTIONS)
	_check("运行时候选显示缩放精确", is_equal_approx(float(runtime.get("display_scale", 0.0)), EXPECTED_DISPLAY_SCALE))
	_check("运行时候选菱形格为 64×32", _as_size(runtime.get("tile_size", [])) == EXPECTED_TILE_SIZE)
	_check("运行时候选允许 Nearest 与 Linear", runtime.get("filter_modes", []) == ["nearest", "linear"])
	_check("运行时候选默认 Linear", str(runtime.get("default_filter", "")) == "linear")
	_check("运行时候选已获用户批准", str(runtime.get("approval", "")) == "approved")
	_check("运行时候选来源已核验", str(runtime.get("provenance", "")) == "verified")
	_check("运行时候选使用权已核验", str(runtime.get("rights", "")) == "verified")

	var asset_exists: bool = FileAccess.file_exists(ASSET_PATH)
	_check("获批运行时候选 PNG 存在", asset_exists, ASSET_PATH)
	if not asset_exists:
		return
	_check("仓内字节保持获批 SHA256", FileAccess.get_sha256(ASSET_PATH) == EXPECTED_SHA256, FileAccess.get_sha256(ASSET_PATH))
	var image: Image = Image.new()
	var image_load_error: Error = image.load_png_from_buffer(FileAccess.get_file_as_bytes(ASSET_PATH))
	var image_loaded: bool = image_load_error == OK and not image.is_empty()
	_check("运行时候选 PNG 可加载", image_loaded)
	if not image_loaded:
		return
	_check("运行时候选 PNG 尺寸精确", Vector2i(image.get_width(), image.get_height()) == EXPECTED_SOURCE_SIZE)
	_check("运行时候选 PNG 为 RGBA8", image.get_format() == Image.FORMAT_RGBA8, str(image.get_format()))
	_check("运行时候选 PNG 含真实透明像素", image.detect_alpha() != Image.ALPHA_NONE, str(image.detect_alpha()))
	for region: Rect2 in EXPECTED_REGIONS:
		_check("切帧 region 不越界：%s" % region, Rect2(Vector2.ZERO, Vector2(EXPECTED_SOURCE_SIZE)).encloses(region))


func _check_runtime_scene_contract() -> void:
	var script_resource: Script = load(SCRIPT_PATH) as Script
	_check("运行时预览脚本可加载", script_resource != null, SCRIPT_PATH)
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_check("运行时预览场景可加载", packed != null, SCENE_PATH)
	if packed == null:
		return
	var instance: Node = packed.instantiate()
	_check("运行时预览场景可实例化", instance != null)
	if instance == null:
		return
	root.add_child(instance)
	await process_frame

	var attached: Script = instance.get_script() as Script
	_check("根节点挂载预期脚本", attached != null and attached.resource_path == SCRIPT_PATH)
	for method_name: String in [
		"get_frame_specs",
		"get_sprite_nodes",
		"get_direction_axes",
		"get_filter_mode",
		"set_filter_mode",
		"get_check_sizes",
		"get_check_size",
		"set_check_size",
		"get_capture_plan",
	]:
		_check("运行场提供接口 %s" % method_name, instance.has_method(method_name))
	if not instance.has_method("get_sprite_nodes") or not instance.has_method("get_frame_specs"):
		instance.queue_free()
		return

	var axes: Dictionary = instance.call("get_direction_axes") as Dictionary
	_check("方向轴 NW 对应 x-1", axes.get("NW") == Vector2i(-1, 0), str(axes))
	_check("方向轴 NE 对应 y-1", axes.get("NE") == Vector2i(0, -1), str(axes))
	_check("方向轴 SW 对应 y+1", axes.get("SW") == Vector2i(0, 1), str(axes))
	_check("方向轴 SE 对应 x+1", axes.get("SE") == Vector2i(1, 0), str(axes))

	var specs: Array = instance.call("get_frame_specs") as Array
	var sprites: Array = instance.call("get_sprite_nodes") as Array
	_check("运行场恰有 8 个帧规格", specs.size() == 8, str(specs.size()))
	_check("运行场恰有 8 个 Sprite2D", sprites.size() == 8, str(sprites.size()))
	if specs.size() == 8 and sprites.size() == 8:
		for index: int in range(8):
			var spec: Dictionary = specs[index] as Dictionary
			var sprite: Sprite2D = sprites[index] as Sprite2D
			var expected_variant: String = "single_weapon" if index < 4 else "dual_weapon"
			var expected_direction: String = EXPECTED_DIRECTIONS[index % 4]
			_check("帧 %d 变体映射正确" % index, str(spec.get("variant", "")) == expected_variant, str(spec))
			_check("帧 %d 方向映射正确" % index, str(spec.get("direction", "")) == expected_direction, str(spec))
			_check("帧 %d region 映射正确" % index, spec.get("region") == EXPECTED_REGIONS[index], str(spec))
			_check("帧 %d 脚锚基线正确" % index, int(spec.get("foot_anchor_y", -1)) == EXPECTED_FOOT_ANCHORS[index], str(spec))
			_check("帧 %d 是 Sprite2D" % index, sprite != null)
			if sprite == null:
				continue
			_check("帧 %d 启用 region" % index, sprite.region_enabled)
			_check("帧 %d 使用正确 region" % index, sprite.region_rect == EXPECTED_REGIONS[index], str(sprite.region_rect))
			_check("帧 %d 统一缩放" % index, sprite.scale.is_equal_approx(Vector2(EXPECTED_DISPLAY_SCALE, EXPECTED_DISPLAY_SCALE)), str(sprite.scale))
			_check("帧 %d 使用原始高精度母版" % index, sprite.texture != null and sprite.texture.resource_path == ASSET_PATH)
			var tile_center: Vector2 = sprite.get_meta("tile_center", Vector2.ZERO) as Vector2
			var actual_foot: Vector2 = sprite.position + Vector2(192.0, float(EXPECTED_FOOT_ANCHORS[index])) * EXPECTED_DISPLAY_SCALE
			_check("帧 %d 脚锚落在格心" % index, actual_foot.is_equal_approx(tile_center), "%s != %s" % [actual_foot, tile_center])

	_check("运行场默认 Linear", str(instance.call("get_filter_mode")) == "linear")
	instance.call("set_filter_mode", "nearest")
	_check("运行场可切换 Nearest", str(instance.call("get_filter_mode")) == "nearest")
	for sprite_value: Variant in sprites:
		var sprite: Sprite2D = sprite_value as Sprite2D
		_check("Nearest 应用于全部 Sprite2D", sprite != null and sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
	instance.call("set_filter_mode", "linear")
	_check("运行场可切换 Linear", str(instance.call("get_filter_mode")) == "linear")
	for sprite_value: Variant in sprites:
		var sprite: Sprite2D = sprite_value as Sprite2D
		_check("Linear 应用于全部 Sprite2D", sprite != null and sprite.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR)

	_check("运行场提供三档检查尺寸", instance.call("get_check_sizes") == EXPECTED_CHECK_SIZES, str(instance.call("get_check_sizes")))
	for check_size: Vector2i in EXPECTED_CHECK_SIZES:
		instance.call("set_check_size", check_size)
		_check("运行场接受检查尺寸 %s" % check_size, instance.call("get_check_size") == check_size)
	await _check_correction_contract(instance)

	var plan: Array = instance.call("get_capture_plan", "test_batch") as Array
	_check("批量截图计划恰有 6 项", plan.size() == 6, str(plan.size()))
	var names: Array[String] = []
	var targets: Array[String] = []
	for entry_value: Variant in plan:
		var entry: Dictionary = entry_value as Dictionary
		names.append(str(entry.get("file_name", "")))
		targets.append(str(entry.get("target_path", "")))
	_check("六张截图文件名与顺序固定", names == EXPECTED_CAPTURE_NAMES, str(names))
	_check("六张截图目标互不重复", _unique_count(targets) == 6, str(targets))
	for target: String in targets:
		_check(
			"截图只写入隔离 user:// 批次目录",
			target.begins_with("user://visual_style_playground/map_token_runtime/test_batch/") and target.ends_with(".png"),
			target
		)

	instance.queue_free()
	await process_frame


func _check_correction_contract(instance: Node) -> void:
	var has_stress_contract: bool = (
		instance.has_method("get_stress_grid_specs")
		and instance.has_method("get_stress_sprite_nodes")
	)
	var has_comparison_contract: bool = instance.has_method("get_filter_comparison_nodes")
	var has_stage_contract: bool = instance.has_method("get_stage_scale")
	_check("运行场提供连续格阵压力区合同", has_stress_contract)
	_check("运行场提供同帧过滤对照合同", has_comparison_contract)
	_check("运行场提供逻辑舞台缩放合同", has_stage_contract)

	if has_stress_contract:
		var grid_specs: Array = instance.call("get_stress_grid_specs") as Array
		var stress_sprites: Array = instance.call("get_stress_sprite_nodes") as Array
		_check("压力区为完整 7×5 连续格", grid_specs.size() == 35, str(grid_specs.size()))
		var stress_tiles: Array[Node] = instance.find_children("StressTile_*", "Polygon2D", true, false)
		var all_stress_tiles_visible: bool = stress_tiles.size() == 35
		for stress_tile: Node in stress_tiles:
			all_stress_tiles_visible = all_stress_tiles_visible and stress_tile.visible and stress_tile.z_index >= 0
		_check("压力区 35 个连续格绘制在背景之前", all_stress_tiles_visible, str(stress_tiles.size()))
		_check("压力区包含多名相邻单位", stress_sprites.size() >= 6, str(stress_sprites.size()))
		var origin: Dictionary = _find_grid_spec(grid_specs, Vector2i(0, 0))
		var x_neighbor: Dictionary = _find_grid_spec(grid_specs, Vector2i(1, 0))
		var y_neighbor: Dictionary = _find_grid_spec(grid_specs, Vector2i(0, 1))
		_check("压力区包含逻辑原点格", not origin.is_empty())
		_check("x+1 相邻格屏幕向量为 (32,16)", x_neighbor.get("screen_center") == Vector2(32, 16), str(x_neighbor))
		_check("y+1 相邻格屏幕向量为 (-32,16)", y_neighbor.get("screen_center") == Vector2(-32, 16), str(y_neighbor))
		var logical_positions: Array[Vector2i] = []
		var has_single_se: bool = false
		var has_dual_se: bool = false
		var previous_depth: int = -100000
		for sprite_value: Variant in stress_sprites:
			var sprite: Sprite2D = sprite_value as Sprite2D
			_check("压力区单位是 Sprite2D", sprite != null)
			if sprite == null:
				continue
			var logical_position: Vector2i = sprite.get_meta("logical_position", Vector2i(-99, -99)) as Vector2i
			var variant: String = str(sprite.get_meta("variant", ""))
			var direction: String = str(sprite.get_meta("direction", ""))
			logical_positions.append(logical_position)
			has_single_se = has_single_se or (variant == "single_weapon" and direction == "SE")
			has_dual_se = has_dual_se or (variant == "dual_weapon" and direction == "SE")
			var depth: int = logical_position.x + logical_position.y
			_check("压力区单位按 x+y 非降序排列", depth >= previous_depth, "%d < %d" % [depth, previous_depth])
			previous_depth = depth
		_check("压力区包含 single SE", has_single_se)
		_check("压力区包含 dual SE", has_dual_se)
		_check("压力区至少一对单位占据曼哈顿相邻格", _has_manhattan_neighbor(logical_positions), str(logical_positions))

	if has_comparison_contract:
		var comparison_nodes: Array = instance.call("get_filter_comparison_nodes") as Array
		_check("同帧过滤对照恰有两个 Sprite2D", comparison_nodes.size() == 2, str(comparison_nodes.size()))
		if comparison_nodes.size() == 2:
			var nearest_sprite: Sprite2D = comparison_nodes[0] as Sprite2D
			var linear_sprite: Sprite2D = comparison_nodes[1] as Sprite2D
			_check("过滤对照两个节点均有效", nearest_sprite != null and linear_sprite != null)
			if nearest_sprite != null and linear_sprite != null:
				_check("对照两侧都是 dual SE", str(nearest_sprite.get_meta("variant", "")) == "dual_weapon" and str(linear_sprite.get_meta("variant", "")) == "dual_weapon" and str(nearest_sprite.get_meta("direction", "")) == "SE" and str(linear_sprite.get_meta("direction", "")) == "SE")
				_check("对照两侧切取同一 dual SE region", nearest_sprite.region_rect == Rect2(1152, 512, 384, 512) and linear_sprite.region_rect == Rect2(1152, 512, 384, 512))
				_check("对照两侧使用同一显示缩放", nearest_sprite.scale.is_equal_approx(linear_sprite.scale), "%s != %s" % [nearest_sprite.scale, linear_sprite.scale])
				_check("对照左侧固定 Nearest", nearest_sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
				_check("对照右侧固定 Linear", linear_sprite.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR)
		var nearest_label: Label = instance.find_child("ComparisonNearestLabel", true, false) as Label
		var linear_label: Label = instance.find_child("ComparisonLinearLabel", true, false) as Label
		_check("过滤对照使用运行时 Nearest 标签", nearest_label != null and nearest_label.text == "Nearest")
		_check("过滤对照使用运行时 Linear 标签", linear_label != null and linear_label.text == "Linear")

	if has_stage_contract:
		var expected_scales: Array[float] = [1.0, 1.5, 2.0]
		for index: int in range(EXPECTED_CHECK_SIZES.size()):
			instance.call("set_check_size", EXPECTED_CHECK_SIZES[index])
			_check(
				"%s 使用逻辑舞台缩放 %.1f" % [EXPECTED_CHECK_SIZES[index], expected_scales[index]],
				is_equal_approx(float(instance.call("get_stage_scale")), expected_scales[index]),
				str(instance.call("get_stage_scale"))
			)
	await process_frame


func _find_sample(samples_value: Variant, sample_id: String) -> Dictionary:
	if typeof(samples_value) != TYPE_ARRAY:
		return {}
	for sample_value: Variant in samples_value as Array:
		if typeof(sample_value) == TYPE_DICTIONARY:
			var sample: Dictionary = sample_value as Dictionary
			if str(sample.get("id", "")) == sample_id:
				return sample
	return {}


func _find_grid_spec(specs: Array, logical_position: Vector2i) -> Dictionary:
	for spec_value: Variant in specs:
		var spec: Dictionary = spec_value as Dictionary
		if spec.get("logical_position") == logical_position:
			return spec
	return {}


func _has_manhattan_neighbor(positions: Array[Vector2i]) -> bool:
	for first_index: int in range(positions.size()):
		for second_index: int in range(first_index + 1, positions.size()):
			var delta: Vector2i = positions[first_index] - positions[second_index]
			if absi(delta.x) + absi(delta.y) == 1:
				return true
	return false


func _as_size(value: Variant) -> Vector2i:
	if typeof(value) != TYPE_ARRAY:
		return Vector2i.ZERO
	var values: Array = value as Array
	if values.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(values[0]), int(values[1]))


func _approved_preview_matches(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var preview: Dictionary = value as Dictionary
	return (
		str(preview.get("file_name", "")) == str(EXPECTED_APPROVED_PREVIEW["file_name"])
		and str(preview.get("sha256", "")) == str(EXPECTED_APPROVED_PREVIEW["sha256"])
		and _as_size(preview.get("pixel_size", [])) == Vector2i(1536, 1024)
		and str(preview.get("identity_scope", "")) == str(EXPECTED_APPROVED_PREVIEW["identity_scope"])
	)


func _unique_count(values: Array[String]) -> int:
	var unique: Dictionary = {}
	for value: String in values:
		unique[value] = true
	return unique.size()


func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		_fails.append(name + ("  [" + detail + "]" if detail != "" else ""))
		print("  ✗ " + name + ("  [" + detail + "]" if detail != "" else ""))
