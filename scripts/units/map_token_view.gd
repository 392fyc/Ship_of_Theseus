extends Sprite2D

const DIRECTIONS: Array[StringName] = [&"NW", &"NE", &"SW", &"SE"]
const EXPECTED_GRID := Vector2i(4, 2)
const EXPECTED_FRAME_SIZE := Vector2i(384, 512)

var _configured := false
var _profile: Dictionary = {}
var _facing: StringName = &"SE"
static var _source_sha256_cache: Dictionary = {}


func configure(profile: Dictionary) -> bool:
	_reset()
	if not _validate_profile(profile):
		return false
	var texture_path := str(profile["texture_path"])
	var loaded_texture := load(texture_path) as Texture2D
	if loaded_texture == null:
		push_error("[MapTokenView] Texture load failed: %s" % texture_path)
		return false
	if FileAccess.file_exists(texture_path) and _get_source_sha256(texture_path) != str(profile["sha256"]):
		push_error("[MapTokenView] Texture SHA256 mismatch: %s" % texture_path)
		return false
	texture = loaded_texture
	hframes = EXPECTED_GRID.x
	vframes = EXPECTED_GRID.y
	centered = false
	var display_scale := float(profile["display_scale"])
	scale = Vector2(display_scale, display_scale)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_profile = profile.duplicate(true)
	_configured = true
	visible = true
	return set_visual_state(&"SE", false)


func set_visual_state(facing: StringName, dual_wielding: bool) -> bool:
	if not _configured or not DIRECTIONS.has(facing):
		return false
	_facing = facing
	var column := DIRECTIONS.find(facing)
	var row := 1 if dual_wielding else 0
	frame_coords = Vector2i(column, row)
	var raw_pivot: Array = _profile["frame_pivot"][row * EXPECTED_GRID.x + column]
	offset = -Vector2(float(raw_pivot[0]), float(raw_pivot[1]))
	return true


func is_configured() -> bool:
	return _configured


func get_facing() -> StringName:
	return _facing


func get_overhead_layout() -> Dictionary:
	return _profile.get("overhead_layout", {}).duplicate(true) if _configured else {}


func _validate_profile(profile: Dictionary) -> bool:
	if str(profile.get("texture_path", "")).is_empty() or str(profile.get("texture_path", "")).contains("/prototype/"):
		return false
	if not _matches_size(profile.get("frame_grid", null), EXPECTED_GRID) or not _matches_size(profile.get("source_frame_size", null), EXPECTED_FRAME_SIZE):
		return false
	if profile.get("variant_order", []) != ["single_weapon", "dual_weapon"]:
		return false
	if profile.get("direction_order", []) != ["NW", "NE", "SW", "SE"]:
		return false
	var pivots: Variant = profile.get("frame_pivot", null)
	if typeof(pivots) != TYPE_ARRAY or (pivots as Array).size() != EXPECTED_GRID.x * EXPECTED_GRID.y:
		return false
	for pivot: Variant in pivots as Array:
		if typeof(pivot) != TYPE_ARRAY or (pivot as Array).size() != 2:
			return false
		if not [TYPE_INT, TYPE_FLOAT].has(typeof((pivot as Array)[0])) or not [TYPE_INT, TYPE_FLOAT].has(typeof((pivot as Array)[1])):
			return false
		var pivot_x := float((pivot as Array)[0])
		var pivot_y := float((pivot as Array)[1])
		if not is_finite(pivot_x) or not is_finite(pivot_y):
			return false
		if pivot_x < 0.0 or pivot_x >= float(EXPECTED_FRAME_SIZE.x) or pivot_y < 0.0 or pivot_y >= float(EXPECTED_FRAME_SIZE.y):
			return false
	if not is_equal_approx(float(profile.get("display_scale", 0.0)), 0.15625):
		return false
	if str(profile.get("default_filter", "")) != "linear":
		return false
	var sha256 := str(profile.get("sha256", ""))
	if sha256.length() != 64:
		return false
	var layout: Variant = profile.get("overhead_layout", null)
	if typeof(layout) != TYPE_DICTIONARY:
		return false
	for key: String in ["opaque_union_top_y", "health_bar_bottom_y", "status_badge_y", "popup_anchor_y"]:
		if not [TYPE_INT, TYPE_FLOAT].has(typeof((layout as Dictionary).get(key, null))):
			return false
		if not is_finite(float((layout as Dictionary)[key])):
			return false
	return true


func _matches_size(value: Variant, expected: Vector2i) -> bool:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		return false
	var size: Array = value as Array
	if not [TYPE_INT, TYPE_FLOAT].has(typeof(size[0])) or not [TYPE_INT, TYPE_FLOAT].has(typeof(size[1])):
		return false
	return is_equal_approx(float(size[0]), float(expected.x)) and is_equal_approx(float(size[1]), float(expected.y))


func _get_source_sha256(texture_path: String) -> String:
	if not _source_sha256_cache.has(texture_path):
		_source_sha256_cache[texture_path] = FileAccess.get_sha256(texture_path)
	return str(_source_sha256_cache[texture_path])


func _reset() -> void:
	texture = null
	visible = false
	_configured = false
	_profile = {}
	_facing = &"SE"
