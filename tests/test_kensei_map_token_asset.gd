extends SceneTree

const SOURCE_PATH := "res://assets/prototype/visual_style/samples/map_token_source_transparent_clean_v2.png"
const PRODUCTION_PATH := "res://assets/units/kensei/map_token_clean_v2.png"
const PROFILE_PATH := "res://data/visual_profiles/kensei_map_token.json"
const EXPECTED_SHA256 := "e6f33324c52929769d4698ed75e969470ec45748788503f4637fcb3223dc5415"
const EXPECTED_PIVOTS: Array[Vector2] = [
	Vector2(205.9, 397.0), Vector2(194.0, 398.5),
	Vector2(178.5, 408.5), Vector2(178.0, 407.5),
	Vector2(203.4, 350.0), Vector2(198.8, 347.5),
	Vector2(173.5, 365.5), Vector2(182.2, 364.0),
]

var _pass := 0
var _fail := 0
var _ran := false

func _initialize() -> void:
	print("=== test_kensei_map_token_asset ===")

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true

func _run() -> void:
	var production_exists := FileAccess.file_exists(PRODUCTION_PATH)
	_check("正式 PNG 存在", production_exists)
	_check("源文件 SHA 精确", FileAccess.get_sha256(SOURCE_PATH) == EXPECTED_SHA256)
	if not production_exists:
		_finish()
		return
	_check("正式文件 SHA 精确", FileAccess.get_sha256(PRODUCTION_PATH) == EXPECTED_SHA256)
	_check("源文件与正式文件字节一致", FileAccess.get_file_as_bytes(SOURCE_PATH) == FileAccess.get_file_as_bytes(PRODUCTION_PATH))
	var image := Image.new()
	_check("正式 PNG 可加载", image.load_png_from_buffer(FileAccess.get_file_as_bytes(PRODUCTION_PATH)) == OK)
	_check("正式 PNG 尺寸精确", Vector2i(image.get_width(), image.get_height()) == Vector2i(1536, 1024))
	_check("正式 PNG 为 RGBA8", image.get_format() == Image.FORMAT_RGBA8)
	_check("正式 PNG 含透明像素", image.detect_alpha() != Image.ALPHA_NONE)
	var union_top := INF
	for index: int in range(EXPECTED_PIVOTS.size()):
		var frame_rect := Rect2i((index % 4) * 384, floori(float(index) / 4.0) * 512, 384, 512)
		var used_rect := image.get_region(frame_rect).get_used_rect()
		union_top = minf(union_top, (float(used_rect.position.y) - EXPECTED_PIVOTS[index].y) * 0.15625)
	_check("八帧不透明联合上沿精确", is_equal_approx(union_top, -51.484375))
	var profile_exists := FileAccess.file_exists(PROFILE_PATH)
	_check("显示配置存在", profile_exists)
	if not profile_exists:
		_finish()
		return
	var parsed_profile: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	_check("显示配置是 JSON 对象", typeof(parsed_profile) == TYPE_DICTIONARY)
	if typeof(parsed_profile) != TYPE_DICTIONARY:
		_finish()
		return
	var profile := parsed_profile as Dictionary
	_check("配置 ID 精确", profile.get("id") == "kensei_map_token")
	_check("正式路径不引用 prototype", profile.get("texture_path") == PRODUCTION_PATH and not PRODUCTION_PATH.contains("/prototype/"))
	_check("配置 SHA 精确", profile.get("sha256") == EXPECTED_SHA256)
	_check("图集为 4×2", profile.get("frame_grid") == [4, 2])
	_check("单帧为 384×512", profile.get("source_frame_size") == [384, 512])
	_check("变体顺序精确", profile.get("variant_order") == ["single_weapon", "dual_weapon"])
	_check("方向顺序精确", profile.get("direction_order") == ["NW", "NE", "SW", "SE"])
	_check("八组中心点精确", _pivots_match(profile.get("frame_pivot", []), EXPECTED_PIVOTS))
	_check("显示比例精确", is_equal_approx(float(profile.get("display_scale")), 0.15625))
	_check("默认过滤为 Linear", profile.get("default_filter") == "linear")
	var admission := profile.get("production_admission", {}) as Dictionary
	_check("正式准入已批准", admission.get("status") == "approved")
	_check("正式准入只绑定 kensei", admission.get("class_ids", []) == ["kensei"])
	_check("头顶联合上沿精确", is_equal_approx(float(profile.get("overhead_layout", {}).get("opaque_union_top_y")), -51.484375))
	var loader: Node = load("res://scripts/data/data_loader.gd").new()
	loader.call("load_all")
	var loaded_profiles := loader.get("visual_profiles") as Dictionary
	var loaded_classes := loader.get("classes") as Dictionary
	_check("DataLoader 注册显示配置", loaded_profiles.get("kensei_map_token", {}).get("id") == "kensei_map_token")
	_check("剑圣绑定显示配置", loaded_classes.get("kensei", {}).get("map_token_profile_id") == "kensei_map_token")
	for class_id: Variant in loaded_classes.keys():
		if str(class_id) != "kensei":
			_check("其他职业未绑定正式棋子：%s" % class_id, not (loaded_classes[class_id] as Dictionary).has("map_token_profile_id"))
	loader.free()
	_finish()

func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		push_error(label)

func _pivots_match(raw: Variant, expected: Array[Vector2]) -> bool:
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() != expected.size():
		return false
	for index: int in range(expected.size()):
		var pair: Variant = (raw as Array)[index]
		if typeof(pair) != TYPE_ARRAY or (pair as Array).size() != 2:
			return false
		var actual := Vector2(float((pair as Array)[0]), float((pair as Array)[1]))
		if not actual.is_equal_approx(expected[index]):
			return false
	return true

func _finish() -> void:
	print("--- %d pass / %d fail ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
