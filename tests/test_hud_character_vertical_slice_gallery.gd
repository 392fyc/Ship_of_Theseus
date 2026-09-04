extends SceneTree

const SCENE_PATH: String = "res://scenes/dev/hud_character_vertical_slice_gallery.tscn"
const CHARACTER_COLUMN: String = "SafeArea/Layout/Content/CharacterColumn"
const STATE_NAMES: Array[String] = [
	"NormalState",
	"LongNameState",
	"ZeroShieldState",
	"FullValuesState",
	"LargeValuesState",
]

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_hud_character_vertical_slice_gallery ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_check("角色栏纵向切片画廊存在", packed != null)
	if packed == null:
		_finish()
		return

	var gallery: Control = packed.instantiate() as Control
	_check("角色栏画廊根节点可实例化", gallery != null)
	if gallery == null:
		_finish()
		return
	root.add_child(gallery)
	gallery.call("set_reference_size", Vector2i(1280, 720))
	await process_frame
	await process_frame

	_check("角色栏画廊脚本真实挂载", gallery.get_script() != null)
	var safe_area: Control = gallery.get_node("SafeArea") as Control
	_check("角色栏画廊安全画布存在", safe_area != null)
	var title: Label = gallery.get_node("SafeArea/Layout/Title") as Label
	var subtitle: Label = gallery.get_node("SafeArea/Layout/Subtitle") as Label
	_check("标题位于安全画布内", _contains_rect(safe_area.get_global_rect(), title.get_global_rect()))
	_check("副标题位于安全画布内", _contains_rect(safe_area.get_global_rect(), subtitle.get_global_rect()))
	for state_name: String in STATE_NAMES:
		_test_state(gallery, safe_area, state_name)

	gallery.queue_free()
	await process_frame
	_finish()


func _test_state(gallery: Control, safe_area: Control, state_name: String) -> void:
	var panel: Control = gallery.get_node_or_null(
		"%s/%s/CharacterHudPanel" % [CHARACTER_COLUMN, state_name]) as Control
	_check("%s 角色栏存在" % state_name, panel != null)
	if panel == null:
		return
	_eq("%s 使用固定角色栏尺寸" % state_name, panel.custom_minimum_size, Vector2(226.0, 108.0))
	_eq("%s 实际角色栏尺寸固定" % state_name, panel.size, Vector2(226.0, 108.0))
	_check("%s 没有越出安全画布" % state_name,
		_contains_rect(safe_area.get_global_rect(), panel.get_global_rect()))
	var state_label: Label = gallery.get_node(
		"%s/%s/Label" % [CHARACTER_COLUMN, state_name]) as Label
	_check("%s 状态标签可见" % state_name, state_label.visible
		and _contains_rect(safe_area.get_global_rect(), state_label.get_global_rect()))


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
