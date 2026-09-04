extends SceneTree

const SCENE_PATH: String = "res://scenes/tactical/hud/skill_shelf.tscn"
const VIEW_DATA_PATH: String = "res://scripts/ui/hud/skill_slot_view_data.gd"
const REUSED_SURFACE_PATH: String = "res://assets/ui/skins/hud/character_panel_surface_v1.png"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_hud_skill_shelf ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var view_script: GDScript = load(VIEW_DATA_PATH) as GDScript
	_check("技能栏场景存在", packed != null)
	_check("技能槽显示数据存在", view_script != null)
	if packed == null or view_script == null:
		_finish()
		return

	var shelf: Control = packed.instantiate() as Control
	_check("技能栏根节点可实例化", shelf != null)
	if shelf == null:
		_finish()
		return
	var center: CenterContainer = shelf.get_node_or_null("SlotsCenter") as CenterContainer
	var slots: HBoxContainer = shelf.get_node_or_null("SlotsCenter/Slots") as HBoxContainer
	_check("居中容器和槽容器由 tscn 声明", center != null and slots != null)
	_check("技能栏场景不静态声明虚假技能槽", slots != null and slots.get_child_count() == 0)
	root.add_child(shelf)
	await process_frame
	await process_frame
	_eq("技能栏固定为 476×108", shelf.size, Vector2(476, 108))
	_eq("技能槽间距固定为 8", slots.get_theme_constant(&"separation"), 8)
	_eq("技能槽容器自身采用居中排列", slots.alignment, BoxContainer.ALIGNMENT_CENTER)
	_check("技能栏开放 apply_skills 接口", shelf.has_method("apply_skills"))
	_check("技能栏开放 get_skill_slots 接口", shelf.has_method("get_skill_slots"))
	_check("技能栏转发 skill_activated 信号", shelf.has_signal("skill_activated"))
	_check("技能栏使用 HudSkillShelf Theme 类型", shelf.theme_type_variation == &"HudSkillShelf")
	var shelf_style: StyleBoxTexture = shelf.get_theme_stylebox(&"panel") as StyleBoxTexture
	_check("技能栏安全复用现有中性面板外壳", shelf_style != null
		and shelf_style.texture != null
		and shelf_style.texture.resource_path == REUSED_SURFACE_PATH)

	await _test_count_layout(shelf, view_script, 5, 64.0, 352.0, 62.0)
	await _test_count_layout(shelf, view_script, 6, 64.0, 424.0, 26.0)
	await _test_count_layout(shelf, view_script, 7, 56.0, 440.0, 18.0)
	await _test_signal_forwarding(shelf, view_script)
	await _test_unsupported_count_does_not_create_slots(shelf, view_script)

	shelf.queue_free()
	await process_frame
	_finish()


func _test_count_layout(shelf: Control, view_script: GDScript, count: int,
		slot_size: float, expected_width: float, expected_x: float) -> void:
	shelf.call("apply_skills", _make_views(view_script, count))
	await process_frame
	await process_frame
	var slots: Array = shelf.call("get_skill_slots") as Array
	_eq("%d 技能只创建真实槽数" % count, slots.size(), count)
	var container: HBoxContainer = shelf.get_node("SlotsCenter/Slots") as HBoxContainer
	_eq("%d 技能总宽" % count, container.size.x, expected_width)
	_eq("%d 技能整体精确居中" % count,
		container.global_position.x - shelf.global_position.x, expected_x)
	for slot: Control in slots:
		_eq("%d 技能槽为 %d×%d" % [count, int(slot_size), int(slot_size)],
			slot.size, Vector2(slot_size, slot_size))
		_check("%d 技能槽未越出固定外框" % count,
			_contains_rect(shelf.get_global_rect(), slot.get_global_rect()))


func _test_signal_forwarding(shelf: Control, view_script: GDScript) -> void:
	var activated: Array[String] = []
	shelf.connect("skill_activated",
		func(skill_id: String) -> void: activated.append(skill_id))
	shelf.call("apply_skills", _make_views(view_script, 5))
	await process_frame
	var slots: Array = shelf.call("get_skill_slots") as Array
	(slots[2] as Button).pressed.emit()
	_eq("子技能槽激活信号按原 skill_id 转发", activated, ["shelf_skill_5_3"])


func _test_unsupported_count_does_not_create_slots(shelf: Control,
		view_script: GDScript) -> void:
	shelf.call("apply_skills", _make_views(view_script, 4))
	await process_frame
	_eq("少于 5 个时不伪造槽位", (shelf.call("get_skill_slots") as Array).size(), 0)
	shelf.call("apply_skills", _make_views(view_script, 8))
	await process_frame
	_eq("多于 7 个时不裁切或伪造槽位", (shelf.call("get_skill_slots") as Array).size(), 0)


func _make_views(view_script: GDScript, count: int) -> Array[RefCounted]:
	var views: Array[RefCounted] = []
	for index: int in count:
		var view: RefCounted = view_script.new()
		view.set("skill_id", "shelf_skill_%d_%d" % [count, index + 1])
		view.set("hotkey_text", str(index + 1))
		view.set("enabled", true)
		view.set("active_capable", true)
		views.append(view)
	return views


func _contains_rect(outer: Rect2, inner: Rect2) -> bool:
	return inner.position.x >= outer.position.x - 0.01 \
		and inner.position.y >= outer.position.y - 0.01 \
		and inner.end.x <= outer.end.x + 0.01 \
		and inner.end.y <= outer.end.y + 0.01


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
