extends SceneTree

const RunStateScript := preload("res://scripts/roguelite/run_state.gd")
const SCENE_PATH: String = "res://scenes/tactical/hud/relic_grid.tscn"
const SLOT_VIEW_PATH: String = "res://scripts/ui/hud/slot_view_data.gd"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_hud_relic_grid ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var view_script: GDScript = load(SLOT_VIEW_PATH) as GDScript
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_check("遗物槽使用通用纯显示数据", view_script != null)
	_eq("受保护玩法遗物上限仍为 6", RunStateScript.RELIC_SLOT_MAX, 6)
	_check("8 不是通用槽显示数据中的玩法容量",
		view_script != null and _has_no_capacity_property(view_script.new()))
	_check("遗物视觉网格场景存在", packed != null)
	if view_script == null or packed == null:
		_finish()
		return
	await _test_visual_grid(packed, view_script)
	_finish()


func _has_no_capacity_property(view: RefCounted) -> bool:
	for property: Dictionary in view.get_property_list():
		var name: String = str(property["name"]).to_lower()
		if "capacity" in name or "relic_slot_max" in name or "gameplay_limit" in name:
			return false
	return true


func _test_visual_grid(packed: PackedScene, view_script: GDScript) -> void:
	var relic_panel: Control = packed.instantiate() as Control
	_check("遗物栏根节点可实例化", relic_panel != null)
	if relic_panel == null:
		return
	var grid: GridContainer = relic_panel.get_node_or_null("VisualGrid") as GridContainer
	_check("遗物视觉网格由 tscn 声明", grid != null)
	if grid == null:
		relic_panel.free()
		return
	_eq("遗物栏固定为 278×108", relic_panel.custom_minimum_size, Vector2(278, 108))
	_eq("视觉网格固定为四列", grid.columns, 4)
	_eq("视觉网格只声明 8 个槽壳", grid.get_child_count(), 8)
	root.add_child(relic_panel)
	await process_frame
	await process_frame
	_eq("视觉网格固定为 250×88", grid.size, Vector2(250, 88))
	_eq("视觉网格固定位置", grid.position, Vector2(14, 10))
	_check("视觉网格四周至少保留 10 像素边界净距",
		_has_minimum_edge_clearance(grid, relic_panel, 10.0))
	var slots: Array[Node] = grid.get_children()
	for index: int in slots.size():
		var slot: Control = slots[index] as Control
		_check("视觉槽 %d 为 40×40 正方形" % (index + 1),
			slot != null and slot.size == Vector2(40, 40))
		_check("视觉槽 %d 保持在网格边界内" % (index + 1),
			slot != null and _relative_rect(slot, grid).position.x >= 0.0
			and _relative_rect(slot, grid).position.y >= 0.0
			and _relative_rect(slot, grid).end.x <= grid.size.x
			and _relative_rect(slot, grid).end.y <= grid.size.y)
	_eq("第一行相邻槽横向间距为 30",
		(slots[1] as Control).position.x - ((slots[0] as Control).position.x + 40.0), 30.0)
	_eq("两行槽纵向间距为 8",
		(slots[4] as Control).position.y - ((slots[0] as Control).position.y + 40.0), 8.0)
	for first_index: int in slots.size():
		for second_index: int in range(first_index + 1, slots.size()):
			_check("视觉槽 %d 与 %d 互不重叠" % [first_index + 1, second_index + 1],
				not _relative_rect(slots[first_index] as Control, grid).intersects(
					_relative_rect(slots[second_index] as Control, grid)))

	var mock_views: Array[RefCounted] = []
	for index: int in 3:
		var view: RefCounted = view_script.new()
		view.set("slot_id", "visual_relic_%d" % index)
		view.set("content_id", "mock_relic_%d" % index)
		view.set("occupied", true)
		view.set("tooltip_text", "mock-only relic %d" % index)
		mock_views.append(view)
	relic_panel.call("apply_slots", mock_views)
	_eq("部分 mock 只绑定到对应视觉槽", (slots[0] as Control).tooltip_text, "mock-only relic 0")
	_eq("未提供 mock 的视觉槽仍为空", (slots[7] as Control).tooltip_text, "")
	relic_panel.queue_free()
	await process_frame


func _relative_rect(control: Control, boundary: Control) -> Rect2:
	return Rect2(control.global_position - boundary.global_position, control.size)


func _has_minimum_edge_clearance(control: Control, boundary: Control,
		minimum: float) -> bool:
	var rect: Rect2 = _relative_rect(control, boundary)
	return rect.position.x >= minimum \
		and rect.position.y >= minimum \
		and boundary.size.x - rect.end.x >= minimum \
		and boundary.size.y - rect.end.y >= minimum


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
