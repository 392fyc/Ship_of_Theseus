extends SceneTree

const SCENE_PATH: String = "res://scenes/dev/hud_bottom_composition_gallery.tscn"
const EXPECTED_PROFILE_PATH: String = "res://data/visual_profiles/kensei_map_token.json"
const EXPECTED_TEXTURE_PATH: String = "res://assets/units/kensei/map_token_clean_v2.png"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_hud_bottom_composition_gallery ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_check("完整底部 HUD 压力画廊存在", packed != null)
	if packed == null:
		_finish()
		return
	var gallery: Control = packed.instantiate() as Control
	_check("压力画廊根可实例化", gallery != null)
	if gallery == null:
		_finish()
		return
	root.add_child(gallery)
	await process_frame
	await process_frame
	var default_shelf: Control = gallery.get_node(
		"DesignRoot/BottomHudComposition/BottomRow/SkillShelf") as Control
	_eq("未显式配置时默认记录五技能", gallery.call("get_skill_count"), 5)
	_eq("未显式配置时真实显示五技能",
		(default_shelf.call("get_skill_slots") as Array).size(), 5)
	_test_board_and_token(gallery)
	await _test_uniform_scaling(gallery)
	await _test_skill_counts(gallery)
	gallery.queue_free()
	await process_frame
	_finish()


func _test_board_and_token(gallery: Control) -> void:
	var design_root: Control = gallery.get_node_or_null("DesignRoot") as Control
	var board: Control = gallery.get_node_or_null("DesignRoot/DiamondBoardStress") as Control
	var token: Sprite2D = gallery.get_node_or_null("DesignRoot/KenseiScaleAnchor") as Sprite2D
	var composition: Control = gallery.get_node_or_null(
		"DesignRoot/BottomHudComposition") as Control
	_check("画廊声明 DesignRoot、棋盘、棋子和 HUD", design_root != null
		and board != null and token != null and composition != null)
	if design_root == null or board == null or token == null or composition == null:
		return
	_eq("DesignRoot 固定为唯一 1280×720 逻辑画布", design_root.size, Vector2(1280, 720))
	_check("棋盘脚本只位于开发 playground",
		str(board.get_script().resource_path).begins_with("res://scripts/ui/playground/"))
	_eq("压力棋盘为 20×20", board.call("get_grid_size"), Vector2i(20, 20))
	_eq("压力棋盘格为 64×32", board.call("get_tile_size"), Vector2i(64, 32))
	_eq("压力棋盘绘制 400 格", board.call("get_drawn_tile_count"), 400)
	_eq("压力棋盘不创建 400 个交互节点", board.get_child_count(), 0)
	var board_bounds: Rect2 = board.call("get_board_bounds") as Rect2
	_eq("压力棋盘覆盖逻辑画布宽度", board_bounds, Rect2(0, 80, 1280, 640))
	_check("压力棋盘延伸至 HUD 后方",
		board_bounds.end.y > composition.get_node("BottomRow").position.y)

	_check("正式准入棋子配置成功", bool(token.call("is_configured")))
	_eq("比例锚点使用单武器 SE 帧", token.frame_coords, Vector2i(3, 0))
	_eq("比例锚点朝向为 SE", token.call("get_facing"), &"SE")
	_eq("棋子位于中央压力格人体中心", token.position,
		board.call("get_tile_center", 10, 10))
	_check("比例锚点使用正式准入纹理",
		token.texture != null and token.texture.resource_path == EXPECTED_TEXTURE_PATH)
	var profile: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPECTED_PROFILE_PATH))
	_check("棋子配置声明正式准入",
		profile is Dictionary
		and str((profile as Dictionary).get("production_admission", {}).get("status", "")) == "approved")


func _test_uniform_scaling(gallery: Control) -> void:
	var cases: Array[Dictionary] = [
		{"size": Vector2i(1280, 720), "scale": 1.0},
		{"size": Vector2i(1920, 1080), "scale": 1.5},
		{"size": Vector2i(2560, 1440), "scale": 2.0},
	]
	for case: Dictionary in cases:
		gallery.call("configure", 5, case["size"])
		await process_frame
		var expected_scale: float = float(case["scale"])
		var design_root: Control = gallery.get_node("DesignRoot") as Control
		_eq("%s 输出画布尺寸" % str(case["size"]), gallery.size, Vector2(case["size"]))
		_eq("%s 统一缩放系数" % str(case["size"]),
			gallery.call("get_output_scale"), expected_scale)
		_eq("%s 只缩放整张 DesignRoot" % str(case["size"]),
			design_root.scale, Vector2(expected_scale, expected_scale))
		_eq("%s 逻辑画布尺寸保持不变" % str(case["size"]),
			design_root.size, Vector2(1280, 720))


func _test_skill_counts(gallery: Control) -> void:
	for count: int in [5, 6, 7]:
		gallery.call("configure", count, Vector2i(1280, 720))
		await process_frame
		var shelf: Control = gallery.get_node(
			"DesignRoot/BottomHudComposition/BottomRow/SkillShelf") as Control
		var slots: Array = shelf.call("get_skill_slots") as Array
		_eq("%d 技能画板只显示实际技能" % count, slots.size(), count)
		_eq("%d 技能画板记录当前数量" % count, gallery.call("get_skill_count"), count)
		var expected_size: Vector2 = Vector2(56, 56) if count == 7 else Vector2(64, 64)
		for index: int in slots.size():
			_eq("%d 技能画板槽 %d 尺寸" % [count, index + 1],
				(slots[index] as Control).size, expected_size)
			_eq("%d 技能画板槽 %d 内容图标为空" % [count, index + 1],
				(slots[index] as Control).get_node("Content/IconRect").texture, null)


func _finish() -> void:
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for failure: String in _fails:
			print("  ✗ " + failure)
	else:
		print("OK")
	quit(0 if _fail == 0 else 1)


func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  ✓ " + name)
		return
	_fail += 1
	_fails.append(name + ("  [" + detail + "]" if detail != "" else ""))
	print("  ✗ " + name + ("  [" + detail + "]" if detail != "" else ""))


func _eq(name: String, actual: Variant, expected: Variant) -> void:
	_check(name, actual == expected, "期望 %s 实际 %s" % [str(expected), str(actual)])
