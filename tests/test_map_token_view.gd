extends SceneTree

const PROFILE_PATH := "res://data/visual_profiles/kensei_map_token.json"

var _pass := 0
var _fail := 0
var _ran := false


func _initialize() -> void:
	print("=== test_map_token_view ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	var view: Sprite2D = load("res://scripts/units/map_token_view.gd").new()
	root.add_child(view)
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	_check("合法配置成功", view.call("configure", profile))
	_check("默认节点可见", view.visible)
	_check("使用正式纹理", view.texture != null and view.texture.resource_path == profile["texture_path"])
	_check("图集为 4×2", view.hframes == 4 and view.vframes == 2)
	_check("不按中心绘制", not view.centered)
	_check("使用 Linear", view.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR)
	_check("默认方向为 SE", view.call("get_facing") == &"SE")
	_check("保存头顶布局", view.call("get_overhead_layout") == profile["overhead_layout"])
	for row: int in range(2):
		for column: int in range(4):
			var dual := row == 1
			var facing := StringName(["NW", "NE", "SW", "SE"][column])
			_check("状态可设置", view.call("set_visual_state", facing, dual))
			_check("帧坐标精确", view.frame_coords == Vector2i(column, row))
			var pivot_data: Array = profile["frame_pivot"][row * 4 + column]
			var pivot := Vector2(float(pivot_data[0]), float(pivot_data[1]))
			_check("人物中心点落在组件原点", (view.offset + pivot).distance_to(Vector2.ZERO) <= 0.001)
			_check("缩放精确", view.scale.is_equal_approx(Vector2(0.15625, 0.15625)))
	_check("拒绝未知方向", not view.call("set_visual_state", &"N", false))
	_check_invalid_profile("缺少纹理路径", profile, func(invalid: Dictionary): invalid.erase("texture_path"))
	_check_invalid_profile("内容错误哈希", profile, func(invalid: Dictionary): invalid["sha256"] = "0".repeat(64))
	_check_invalid_profile("不存在纹理路径", profile, func(invalid: Dictionary): invalid["texture_path"] = "res://assets/units/kensei/does_not_exist.png")
	_check_invalid_profile("错误图集", profile, func(invalid: Dictionary): invalid["frame_grid"] = [2.0, 4.0])
	_check_invalid_profile("缺少中心点", profile, func(invalid: Dictionary): invalid.erase("frame_pivot"))
	_check_invalid_profile("缺少布局字段", profile, func(invalid: Dictionary): invalid["overhead_layout"].erase("popup_anchor_y"))
	for layout_key: String in ["opaque_union_top_y", "health_bar_bottom_y", "status_badge_y", "popup_anchor_y"]:
		_check_invalid_profile("非有限布局字段 %s" % layout_key, profile, func(invalid: Dictionary): invalid["overhead_layout"][layout_key] = NAN)
		_check_invalid_profile("无穷布局字段 %s" % layout_key, profile, func(invalid: Dictionary): invalid["overhead_layout"][layout_key] = INF)
	_check_invalid_profile("越界人物中心点", profile, func(invalid: Dictionary): invalid["frame_pivot"][0] = [500.0, 397.0])
	_check_invalid_profile("非有限人物中心点", profile, func(invalid: Dictionary): invalid["frame_pivot"][0] = [NAN, 397.0])
	view.queue_free()
	_finish()


func _check_invalid_profile(label: String, profile: Dictionary, mutate: Callable) -> void:
	var view: Sprite2D = load("res://scripts/units/map_token_view.gd").new()
	root.add_child(view)
	var invalid := profile.duplicate(true)
	mutate.call(invalid)
	_check(label + " 被拒绝", not view.call("configure", invalid))
	_check(label + " 时节点不可见", not view.visible)
	view.queue_free()


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  ✓ " + label)
	else:
		_fail += 1
		push_error(label)


func _finish() -> void:
	print("--- %d pass / %d fail ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
