extends SceneTree

const SCENE_PATH: String = "res://scenes/tactical/hud/equipment_hud_panel.tscn"
const SLOT_VIEW_PATH: String = "res://scripts/ui/hud/slot_view_data.gd"
const POTION_VIEW_PATH: String = "res://scripts/ui/hud/potion_view_data.gd"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_hud_equipment_panel ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_check("装备栏场景存在", packed != null)
	if packed == null:
		_finish()
		return
	var slot_view_script: GDScript = load(SLOT_VIEW_PATH) as GDScript
	var potion_view_script: GDScript = load(POTION_VIEW_PATH) as GDScript
	_check("装备栏使用通用槽显示数据", slot_view_script != null)
	_check("装备栏使用独立血瓶显示数据", potion_view_script != null)
	if slot_view_script == null or potion_view_script == null:
		_finish()
		return
	await _test_panel(packed, slot_view_script, potion_view_script)
	_finish()


func _test_panel(packed: PackedScene, slot_view_script: GDScript,
		potion_view_script: GDScript) -> void:
	var panel: Control = packed.instantiate() as Control
	_check("装备栏根节点可实例化", panel != null)
	if panel == null:
		return
	var weapon: Button = panel.get_node_or_null("WeaponSlot") as Button
	var armor: Button = panel.get_node_or_null("ArmorSlot") as Button
	var potion: Button = panel.get_node_or_null("PotionButton") as Button
	_check("武器、防具和血瓶均由 tscn 声明",
		weapon != null and armor != null and potion != null)
	root.add_child(panel)
	await process_frame
	await process_frame
	_eq("装备栏固定为 128×108", panel.size, Vector2(128, 108))
	_eq("武器槽固定为 52×52", weapon.size, Vector2(52, 52))
	_eq("武器槽位置固定", weapon.position, Vector2(10, 46))
	_eq("防具槽固定为 52×52", armor.size, Vector2(52, 52))
	_eq("防具槽位置固定", armor.position, Vector2(66, 46))
	_eq("血瓶固定为 32×32", potion.size, Vector2(32, 32))
	_eq("血瓶位于装备栏右上角", potion.position, Vector2(86, 10))
	for entry: Dictionary in [
		{"name": "武器槽", "control": weapon},
		{"name": "防具槽", "control": armor},
		{"name": "血瓶", "control": potion},
	]:
		_check("%s 四周至少保留 10 像素边界净距" % entry["name"],
			_has_minimum_edge_clearance(entry["control"] as Control, panel, 10.0))
	_eq("武器槽与防具槽横向间距为 4", armor.position.x - (weapon.position.x + weapon.size.x), 4.0)
	_eq("血瓶与防具槽纵向间距为 4", armor.position.y - (potion.position.y + potion.size.y), 4.0)
	_check("武器槽与防具槽互不重叠", not _relative_rect(weapon, panel).intersects(
		_relative_rect(armor, panel)))
	_check("武器槽与血瓶互不重叠", not _relative_rect(weapon, panel).intersects(
		_relative_rect(potion, panel)))
	_check("防具槽与血瓶互不重叠", not _relative_rect(armor, panel).intersects(
		_relative_rect(potion, panel)))

	var weapon_view: RefCounted = slot_view_script.new()
	weapon_view.set("slot_id", "weapon")
	weapon_view.set("content_id", "mock_weapon")
	weapon_view.set("occupied", true)
	weapon_view.set("tooltip_text", "mock-only weapon")
	var armor_view: RefCounted = slot_view_script.new()
	armor_view.set("slot_id", "armor")
	armor_view.set("content_id", "")
	armor_view.set("occupied", false)
	armor_view.set("tooltip_text", "mock-only empty armor")
	var potion_view: RefCounted = potion_view_script.new()
	potion_view.set("content_id", "mock_universal_potion")
	potion_view.set("tooltip_text", "mock-only potion")
	panel.call("apply_view", weapon_view, armor_view, potion_view)
	_eq("武器 mock tooltip 由显示数据传递", weapon.tooltip_text, "mock-only weapon")
	_eq("空防具 mock tooltip 由显示数据传递", armor.tooltip_text, "mock-only empty armor")
	_eq("血瓶 mock tooltip 由显示数据传递", potion.tooltip_text, "mock-only potion")
	_check("正式可见树不显示审核文字", _forbidden_visible_text(panel).is_empty())
	panel.queue_free()
	await process_frame


func _forbidden_visible_text(node: Node) -> Array[String]:
	var found: Array[String] = []
	var label: Label = node as Label
	if label != null and label.visible:
		for forbidden: String in ["EQUIPMENT", "WPN", "ARM"]:
			if forbidden in label.text:
				found.append(forbidden)
	for child: Node in node.get_children():
		found.append_array(_forbidden_visible_text(child))
	return found


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
