extends SceneTree

const VIEW_DATA_PATH: String = "res://scripts/ui/hud/action_resource_view_data.gd"
const SCENE_PATH: String = "res://scenes/tactical/hud/action_resource_strip.tscn"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_hud_action_resource_strip ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var view_script: GDScript = load(VIEW_DATA_PATH) as GDScript
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_check("有类型行动资源显示数据脚本存在", view_script != null)
	_check("行动资源条场景存在", packed != null)
	if view_script == null or packed == null:
		_finish()
		return

	_test_normalization(view_script)
	await _test_declared_structure_and_states(view_script, packed)
	_finish()


func _test_normalization(view_script: GDScript) -> void:
	var view: RefCounted = view_script.new()
	view.set("movement_remaining", -4)
	view.set("standard_capacity", 0)
	view.set("standard_remaining", 9)
	view.set("swift_capacity", 8)
	view.set("swift_remaining", -2)
	view.call("normalize")
	_eq("移动力不小于零", view.get("movement_remaining"), 0)
	_eq("标准行动容量下限为一", view.get("standard_capacity"), 1)
	_eq("标准行动剩余量不超过容量", view.get("standard_remaining"), 1)
	_eq("迅捷行动容量上限为三", view.get("swift_capacity"), 3)
	_eq("迅捷行动剩余量不小于零", view.get("swift_remaining"), 0)


func _test_declared_structure_and_states(view_script: GDScript,
		packed: PackedScene) -> void:
	var strip: Control = packed.instantiate() as Control
	_check("行动资源条根节点可实例化", strip != null)
	if strip == null:
		return

	_check("固定语义区域由场景声明", strip.get_node_or_null("Margin/MainRow/MovementZone/MovementCluster") != null
		and strip.get_node_or_null("Margin/MainRow/MovementZone/MovementCluster/FootprintGlyph") != null
		and strip.get_node_or_null("Margin/MainRow/MovementZone/MovementCluster/MovementValue") != null
		and strip.get_node_or_null("Margin/MainRow/StandardZone/StandardPips") != null
		and strip.get_node_or_null("Margin/MainRow/SwiftZone/SwiftPips") != null)
	_check("场景序列化静态组件树", packed.get_state().get_node_count() >= 9)
	var main_row: HBoxContainer = strip.get_node("Margin/MainRow") as HBoxContainer
	_check("三个语义区域使用水平容器", main_row != null)
	_eq("水平容器只有三个直接分区", main_row.get_child_count(), 3)
	_eq("三个完整内框之间保留四像素间距", main_row.get_theme_constant(&"separation"), 4)

	strip.size = strip.custom_minimum_size
	root.add_child(strip)
	await process_frame
	await process_frame
	await process_frame
	_check("行动资源条脚本真实挂载", strip.get_script() != null)
	_eq("行动资源条 Theme 类型", strip.theme_type_variation, &"ActionResourceStrip")
	_check("行动资源条保留独立整体外框",
		strip.get_theme_stylebox(&"panel") is StyleBoxTexture)
	var movement_zone: PanelContainer = strip.get_node_or_null("Margin/MainRow/MovementZone") as PanelContainer
	var standard_zone: PanelContainer = strip.get_node_or_null("Margin/MainRow/StandardZone") as PanelContainer
	var swift_zone: PanelContainer = strip.get_node_or_null("Margin/MainRow/SwiftZone") as PanelContainer
	_check("移动、标准、迅捷均为独立内嵌区域",
		movement_zone != null and standard_zone != null and swift_zone != null)
	if movement_zone != null and standard_zone != null and swift_zone != null:
		_eq("三区使用同一个完整类边框变体", [
			movement_zone.theme_type_variation,
			standard_zone.theme_type_variation,
			swift_zone.theme_type_variation,
		], [&"ActionResourceSegment", &"ActionResourceSegment", &"ActionResourceSegment"])
		var movement_style: StyleBoxFlat = movement_zone.get_theme_stylebox(&"panel") as StyleBoxFlat
		var standard_style: StyleBoxFlat = standard_zone.get_theme_stylebox(&"panel") as StyleBoxFlat
		var swift_style: StyleBoxFlat = swift_zone.get_theme_stylebox(&"panel") as StyleBoxFlat
		_check("三区复用同一套边框资源", movement_style != null
			and movement_style == standard_style
			and standard_style == swift_style)
		_check("三区内部透明且不形成区域色块", movement_style != null
			and is_zero_approx(movement_style.bg_color.a))
		_check("同款类边框保持低对比度", movement_style != null
			and movement_style.border_color.a > 0.35
			and movement_style.border_color.a < 0.75)
		_check("每个区域都绘制完整四边框", movement_style != null
			and movement_style.border_width_left == 1
			and movement_style.border_width_top == 1
			and movement_style.border_width_right == 1
			and movement_style.border_width_bottom == 1)
		_check("每个区域都使用相同四角收边", movement_style != null
			and movement_style.corner_radius_top_left == 2
			and movement_style.corner_radius_top_right == 2
			and movement_style.corner_radius_bottom_right == 2
			and movement_style.corner_radius_bottom_left == 2)
		_check("三个完整边框由小间距保持独立",
			is_equal_approx(movement_zone.position.x + movement_zone.size.x + 4.0, standard_zone.position.x)
			and is_equal_approx(standard_zone.position.x + standard_zone.size.x + 4.0, swift_zone.position.x),
			"movement=%s/%s standard=%s/%s swift=%s/%s" % [
				str(movement_zone.position.x), str(movement_zone.size.x),
				str(standard_zone.position.x), str(standard_zone.size.x),
				str(swift_zone.position.x), str(swift_zone.size.x)])

	var standard_pips: HBoxContainer = strip.get_node("Margin/MainRow/StandardZone/StandardPips") as HBoxContainer
	var swift_pips: HBoxContainer = strip.get_node("Margin/MainRow/SwiftZone/SwiftPips") as HBoxContainer
	var movement_value: Label = strip.get_node(
		"Margin/MainRow/MovementZone/MovementCluster/MovementValue") as Label
	_eq("标准行动点在固定区域居中", standard_pips.alignment, BoxContainer.ALIGNMENT_CENTER)
	_eq("迅捷行动点在固定区域居中", swift_pips.alignment, BoxContainer.ALIGNMENT_CENTER)
	_eq("移动力使用 18px", movement_value.get_theme_font_size(&"font_size"), 18)
	_eq("移动力承载区宽度随文字放大为 30", movement_value.size.x, 30.0)
	_check("移动力承载区采用字体所需的真实高度", movement_value.size.y >= 24.0)
	_check("移动力文字完整落在独立区域内",
		movement_value.position.x >= 0.0 and movement_value.position.y >= 0.0
		and movement_value.position.x + movement_value.size.x <= movement_zone.size.x + 0.01
		and movement_value.position.y + movement_value.size.y <= movement_zone.size.y + 0.01,
		"value=%s/%s zone=%s" % [
			str(movement_value.position), str(movement_value.size), str(movement_zone.size)])
	_eq("移动力数值水平居中", movement_value.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER)
	_eq("移动力数值垂直居中", movement_value.vertical_alignment, VERTICAL_ALIGNMENT_CENTER)

	var view: RefCounted = view_script.new()
	view.set("movement_remaining", 7)
	view.set("movement_available", false)
	view.set("standard_capacity", 3)
	view.set("standard_remaining", 2)
	view.set("swift_capacity", 2)
	view.set("swift_remaining", 0)
	strip.call("apply_view", view)

	var standard_nodes: Array = strip.call("get_standard_pips") as Array
	var swift_nodes: Array = strip.call("get_swift_pips") as Array
	_eq("标准行动只创建实际容量", standard_nodes.size(), 3)
	_eq("迅捷行动只创建实际容量", swift_nodes.size(), 2)
	_eq("标准行动部分消耗", _spent_states(standard_nodes), [false, false, true])
	_eq("迅捷行动全部消耗", _spent_states(swift_nodes), [true, true])
	_eq("标准行动点保持圆点类型", _kinds(standard_nodes), [1, 1, 1])
	_eq("迅捷行动点保持三角类型", _kinds(swift_nodes), [2, 2])

	var spent_colors: Array[Color] = []
	for glyph: Control in standard_nodes + swift_nodes:
		if bool(glyph.get("spent")):
			spent_colors.append(glyph.call("get_display_color") as Color)
	_check("所有耗尽点使用同一灰色", not spent_colors.is_empty()
		and spent_colors.all(func(color: Color) -> bool: return color == spent_colors[0]))

	var footprint: Control = strip.get_node_or_null(
		"Margin/MainRow/MovementZone/MovementCluster/FootprintGlyph") as Control
	_check("移动力足迹节点存在", footprint != null)
	if footprint == null:
		strip.queue_free()
		await process_frame
		return
	_eq("移动力使用足迹类型", int(footprint.get("kind")), 0)
	_check("移动不可用时足迹灰化", bool(footprint.get("spent")))
	_eq("移动力只显示数值", _visible_label_text(strip), ["7"])
	_check("节点树不含分隔柱", not _node_name_contains(strip, "divider"))
	_check("不显示可用或已用文字", not "可用" in _visible_label_text(strip)
		and not "已用" in _visible_label_text(strip))

	var glyph_properties: Array[String] = []
	for property: Dictionary in footprint.get_property_list():
		glyph_properties.append(str(property["name"]).to_lower())
	_check("图形组件没有斜杠状态属性",
		glyph_properties.all(func(name: String) -> bool: return not "slash" in name))

	strip.queue_free()
	await process_frame


func _spent_states(nodes: Array) -> Array[bool]:
	var result: Array[bool] = []
	for node: Control in nodes:
		result.append(bool(node.get("spent")))
	return result


func _kinds(nodes: Array) -> Array[int]:
	var result: Array[int] = []
	for node: Control in nodes:
		result.append(int(node.get("kind")))
	return result


func _visible_label_text(node: Node) -> Array[String]:
	var result: Array[String] = []
	var label: Label = node as Label
	if label != null and label.is_visible_in_tree() and label.text != "":
		result.append(label.text)
	for child: Node in node.get_children():
		result.append_array(_visible_label_text(child))
	return result


func _node_name_contains(node: Node, needle: String) -> bool:
	if needle in str(node.name).to_lower():
		return true
	for child: Node in node.get_children():
		if _node_name_contains(child, needle):
			return true
	return false


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
