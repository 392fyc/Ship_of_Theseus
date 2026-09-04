extends SceneTree

const SCENE_PATH: String = "res://scenes/dev/hud_vertical_slice_gallery.tscn"
const SKILL_COLUMN: String = "SafeArea/Layout/Content/SkillColumn"
const RESOURCE_COLUMN: String = "SafeArea/Layout/Content/ResourceColumn"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_hud_vertical_slice_gallery ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_check("纵向切片画廊存在", packed != null)
	if packed == null:
		_finish()
		return

	var gallery: Control = packed.instantiate() as Control
	_check("画廊根节点可实例化", gallery != null)
	if gallery == null:
		_finish()
		return
	root.add_child(gallery)
	gallery.call("set_reference_size", Vector2i(1280, 720))
	await process_frame
	await process_frame

	_check("画廊脚本真实挂载", gallery.get_script() != null)
	_test_skill_board(gallery, "SkillCount5", 5, Vector2(64.0, 64.0))
	_test_skill_board(gallery, "SkillCount6", 6, Vector2(64.0, 64.0))
	_test_skill_board(gallery, "SkillCount7", 7, Vector2(56.0, 56.0))
	_test_resource_board(gallery, "ActionCapacity1", 1, 1, [false], [false])
	_test_resource_board(gallery, "ActionCapacity2", 2, 2, [false, true], [false, true])
	_test_resource_board(gallery, "ActionCapacity3", 3, 3,
		[false, false, true], [true, true, true])
	_test_movement_disabled(gallery)
	_check("所有画廊板块位于安全画布内", _all_boards_inside_safe_area(gallery))

	gallery.queue_free()
	await process_frame
	_finish()


func _test_skill_board(gallery: Control, board_name: String, expected_count: int,
		expected_slot_size: Vector2) -> void:
	var shelf: Control = gallery.get_node("%s/%s" % [SKILL_COLUMN, board_name]) as Control
	_check("%s 存在" % board_name, shelf != null)
	if shelf == null:
		return
	_eq("%s 固定尺寸" % board_name, shelf.size, Vector2(476.0, 108.0))
	_check("%s 开启裁切护栏" % board_name, shelf.clip_contents)
	var slots: HBoxContainer = shelf.get_node("Slots") as HBoxContainer
	_eq("%s 技能数量" % board_name, slots.get_child_count(), expected_count)
	_eq("%s 内部居中" % board_name, slots.alignment, BoxContainer.ALIGNMENT_CENTER)
	for slot: Control in slots.get_children():
		_eq("%s 槽位尺寸" % board_name, slot.custom_minimum_size, expected_slot_size)
		_check("%s 槽位没有越出容器" % board_name,
			_contains_rect(shelf.get_global_rect(), slot.get_global_rect()))


func _test_resource_board(gallery: Control, board_name: String,
		expected_standard: int, expected_swift: int,
		expected_standard_spent: Array[bool], expected_swift_spent: Array[bool]) -> void:
	var strip: Control = gallery.get_node(
		"%s/%s/ActionResourceStrip" % [RESOURCE_COLUMN, board_name]) as Control
	_check("%s 存在" % board_name, strip != null)
	if strip == null:
		return
	var standard: Array = strip.call("get_standard_pips") as Array
	var swift: Array = strip.call("get_swift_pips") as Array
	_eq("%s 标准容量" % board_name, standard.size(), expected_standard)
	_eq("%s 迅捷容量" % board_name, swift.size(), expected_swift)
	_eq("%s 标准状态" % board_name, _spent_states(standard), expected_standard_spent)
	_eq("%s 迅捷状态" % board_name, _spent_states(swift), expected_swift_spent)


func _test_movement_disabled(gallery: Control) -> void:
	var strip: Control = gallery.get_node(
		"%s/ActionMovementDisabled/ActionResourceStrip" % RESOURCE_COLUMN) as Control
	_check("ActionMovementDisabled 存在", strip != null)
	if strip == null:
		return
	var footprint: Control = strip.get_node(
		"Margin/MainRow/MovementZone/MovementCluster/FootprintGlyph") as Control
	_check("移动失效板足迹灰化", bool(footprint.get("spent")))
	_eq("移动失效板保留数值", (strip.get_node(
		"Margin/MainRow/MovementZone/MovementCluster/MovementValue") as Label).text, "8")


func _all_boards_inside_safe_area(gallery: Control) -> bool:
	var safe_area: Control = gallery.get_node("SafeArea") as Control
	var safe_rect: Rect2 = safe_area.get_global_rect()
	for board_name: String in ["SkillCount5", "SkillCount6", "SkillCount7"]:
		var board: Control = gallery.get_node("%s/%s" % [SKILL_COLUMN, board_name]) as Control
		if not _contains_rect(safe_rect, board.get_global_rect()):
			return false
	for board_name: String in ["ActionCapacity1", "ActionCapacity2", "ActionCapacity3", "ActionMovementDisabled"]:
		var board: Control = gallery.get_node("%s/%s" % [RESOURCE_COLUMN, board_name]) as Control
		if not _contains_rect(safe_rect, board.get_global_rect()):
			return false
	return true


func _contains_rect(outer: Rect2, inner: Rect2) -> bool:
	return inner.position.x >= outer.position.x - 0.01 \
		and inner.position.y >= outer.position.y - 0.01 \
		and inner.end.x <= outer.end.x + 0.01 \
		and inner.end.y <= outer.end.y + 0.01


func _spent_states(nodes: Array) -> Array[bool]:
	var result: Array[bool] = []
	for node: Control in nodes:
		result.append(bool(node.get("spent")))
	return result


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
