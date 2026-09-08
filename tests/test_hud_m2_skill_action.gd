extends SceneTree

const M2View := preload("res://scripts/ui/hud/m2/skill_slot_view_data.gd")
const ActionView := preload("res://scripts/ui/hud/action_resource_view_data.gd")
const SlotScene: PackedScene = preload("res://scenes/tactical/hud/m2/skill_slot_button.tscn")
const ShelfScene: PackedScene = preload("res://scenes/tactical/hud/m2/skill_shelf.tscn")
const StripScene: PackedScene = preload("res://scenes/tactical/hud/m2/action_resource_strip.tscn")

const Glyph := preload("res://scripts/ui/hud/m2/action_resource_glyph.gd")

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_cost_contract()
	_test_scaled_font_contract()
	await _test_slot()
	await _test_shelf()
	await _test_strip()
	print("test_hud_m2_skill_action: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_scaled_font_contract() -> void:
	var shared_theme: Theme = load("res://assets/ui/themes/hud_m2.tres")
	var text_server: TextServer = TextServerManager.get_primary_interface()
	for type_name: StringName in [&"HudM2NumericLabel", &"HudM2IdentityLabel", &"HudM2Text"]:
		var probe := Label.new()
		probe.theme = shared_theme
		probe.theme_type_variation = type_name
		root.add_child(probe)
		var font: Font = probe.get_theme_font(&"font")
		print("字体追踪 %s: %s / %s / MSDF=%s" % [type_name, font.get_class(), font.get_font_name(), font.get("multichannel_signed_distance_field")])
		for sample: String in ["999", "纯被动说明"]:
			var line := TextLine.new()
			line.add_string(sample, font, probe.get_theme_font_size(&"font_size"))
			var glyphs: Array[Dictionary] = text_server.shaped_text_get_glyphs(line.get_rid())
			var all_msdf: bool = not glyphs.is_empty()
			for glyph: Dictionary in glyphs:
				var rid: RID = glyph["font_rid"]
				all_msdf = all_msdf and rid.is_valid() and text_server.font_is_multichannel_signed_distance_field(rid)
			_check("%s实际%s字形为MSDF" % [type_name, sample], all_msdf)
		probe.free()
	var original: FontFile = load("res://assets/fonts/ibm_plex_mono/IBMPlexMono-SemiBold.ttf")
	_check("原IBM字体仍保持原配置", not original.multichannel_signed_distance_field)
	_check("默认项目字体仍保持原配置", not ThemeDB.fallback_font.get("multichannel_signed_distance_field"))


func _test_cost_contract() -> void:
	var view := M2View.new()
	for amount: Variant in [1, 12, 999, 12.0, 999.0]:
		view.resource_cost_display = {"amount": amount, "resource_name": " 法力 "}
		_check("通用正整数费用 %s" % amount, view.resource_cost_text() == str(int(amount)))
		_check("名称规范化", view.resource_name_text() == "法力")
	for invalid: Variant in [null, true, "12", -1, 0, 1.5, INF, NAN, 1000, 99999]:
		view.resource_cost_display = {"amount": invalid, "resource_name": "斗志"}
		_check("非法费用不显示 %s" % invalid, view.resource_cost_text().is_empty())
	for invalid: Dictionary in [{}, {"amount": 12}, {"resource_name": "法力"}, {"amount": 12, "resource_name": " "}, {"amount": 12, "resource_name": 12}, {"qi_cost": 12, "mark_cost": 3}]:
		view.resource_cost_display = invalid
		_check("缺值与旧费用字段不回填", view.resource_cost_text().is_empty())
	view.resource_cost_display = {"amount": 12, "resource_name": "任意资源名"}
	_check("组件不按职业或中文名称过滤", view.resource_cost_text() == "12")
	view.skill_id = "fixture_hybrid"
	view.passive = true
	view.active_capable = true
	_check("被动可触发能力独立", view.can_activate() and not view.is_pure_passive())
	view.active_capable = false
	_check("纯被动无激活能力", not view.can_activate() and view.is_pure_passive())
	view.passive = false
	_check("非被动不覆盖无主动能力", not view.can_activate())


func _fixture(index: int) -> M2View:
	var view := M2View.new()
	view.skill_id = "fixture_%d" % index
	view.active_capable = true
	view.hotkey_text = str(index + 1)
	view.action_type = &"standard"
	view.tooltip_text = "显示测试夹具"
	view.resource_cost_display = {"amount": 999, "resource_name": "法力"}
	view.icon_texture = GradientTexture2D.new()
	return view


func _test_slot() -> void:
	var view: M2View = _fixture(0)
	view.passive = true
	view.selected = true
	var slot: Button = SlotScene.instantiate()
	slot.position = Vector2(100, 100)
	slot.apply_view(view)
	root.add_child(slot)
	await process_frame
	var activated: Array[String] = []
	slot.skill_activated.connect(func(id: String) -> void: activated.append(id))
	_check("新Theme显式绑定", slot.theme.resource_path == "res://assets/ui/themes/hud_m2.tres")
	_check("混合被动保留快捷键", slot.get_node("Content/HotkeyBadge").visible)
	_check("混合被动保留行动", slot.get_node("Content/ActionBadge").visible)
	_check("混合被动保留费用", slot.get_node("Content/ResourceCostBadge/ResourceCostText").text == "999")
	_check("资源名称进入说明", slot.tooltip_text.contains("法力：999"))
	_check("混合被动保留选中", slot.get_node("Content/SelectedOverlay").visible)
	for extent: int in [64, 56]:
		slot.custom_minimum_size = Vector2(extent, extent)
		slot.size = Vector2(extent, extent)
		await process_frame
		var hotkey: Control = slot.get_node("Content/HotkeyBadge")
		var amount: Label = slot.get_node("Content/ResourceCostBadge/ResourceCostText")
		_check("%d快捷键18×18" % extent, hotkey.size == Vector2(18, 18))
		_check("%d快捷键右上4px" % extent, hotkey.position == Vector2(extent - 22, 4))
		_check("%d费用24×17" % extent, amount.size == Vector2(24, 17))
		_check("%d费用11px原字号" % extent, amount.get_theme_font_size(&"font_size") == 11 and amount.scale == Vector2.ONE)
		_check("%d三位数实际字宽可容纳" % extent, amount.get_theme_font(&"font").get_string_size("999", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x <= amount.size.x)
		_check("%d内容保留6px边距" % extent, slot.get_node("Content/IconRect").size == Vector2(extent - 12, extent - 12))
	await _click(slot.get_global_rect().get_center())
	_check("鼠标事件激活混合被动", activated.size() == 1)
	slot.grab_focus()
	await _key(KEY_SPACE)
	_check("焦点Space事件激活混合被动", activated.size() == 2)
	_check("焦点叠层可见", slot.get_node("Content/FocusOverlay").visible)
	view.active_capable = false
	view.enabled = false
	view.cooldown_turns = 2
	slot.apply_view(view)
	slot.grab_focus()
	await process_frame
	_check("纯被动可获得焦点", slot.has_focus() and not slot.disabled)
	_check("纯被动提供可见检视接口", slot.has_method("is_inspection_visible"))
	if slot.has_method("is_inspection_visible"):
		_check("键盘焦点说明实际可见", slot.is_inspection_visible())
		_check("键盘焦点说明内容来自显示数据", slot.get_inspection_text() == view.tooltip_text)
	_check("纯被动内容保持彩色", slot.get_node("Content/IconRect").texture == view.icon_texture and slot.get_node("Content/IconRect").modulate == Color.WHITE)
	_check("纯被动保留凹边并隐藏金属框", slot.get_node("Content/PassiveFrame").visible and not slot.get_node("Content/ActiveFrame").visible)
	for path: String in ["HotkeyBadge", "ActionBadge", "ResourceCostBadge", "SelectedOverlay", "CooldownShade", "CooldownTurnsLabel", "UnavailableShade"]:
		_check("纯被动隐藏%s" % path, not slot.get_node("Content/" + path).visible)
	await _click(slot.get_global_rect().get_center())
	await _key(KEY_SPACE)
	slot.activate_shortcut()
	_check("纯被动拒绝鼠标键盘和快捷入口", activated.size() == 2)
	view.active_capable = true
	view.enabled = true
	slot.apply_view(view)
	await _click(slot.get_global_rect().get_center())
	await _key(KEY_SPACE)
	_check("混合被动冷却拒绝输入", activated.size() == 2 and slot.disabled)
	_check("混合被动冷却仍保留费用", slot.get_node("Content/ResourceCostBadge").visible and slot.get_node("Content/CooldownShade").visible)
	view.cooldown_turns = 0
	view.enabled = false
	slot.apply_view(view)
	await _click(slot.get_global_rect().get_center())
	_check("混合被动不可用暗层与输入拒绝", slot.get_node("Content/UnavailableShade").visible and activated.size() == 2)
	view.enabled = true
	view.passive = false
	view.active_capable = false
	slot.apply_view(view)
	slot.activate_shortcut()
	_check("显式非被动无能力拒绝激活", slot.disabled and activated.size() == 2)
	slot.queue_free()
	await process_frame


func _test_shelf() -> void:
	var shelf: Panel = ShelfScene.instantiate()
	root.add_child(shelf)
	await process_frame
	for count: int in [5, 6, 7]:
		var views: Array[RefCounted] = []
		for index: int in count:
			views.append(_fixture(index))
		shelf.apply_skills(views)
		await process_frame
		await process_frame
		var slots: Array = shelf.get_skill_slots()
		var extent: float = 56.0 if count == 7 else 64.0
		var group_width: float = count * extent + (count - 1) * 8
		_check("%d槽数量" % count, slots.size() == count)
		_check("%d槽尺寸" % count, slots[0].size == Vector2(extent, extent))
		_check("%d槽整组居中" % count, slots[0].global_position.is_equal_approx(shelf.global_position + Vector2((476 - group_width) / 2, (108 - extent) / 2)))
		_check("%d槽间距8" % count, slots[1].position.x - slots[0].position.x == extent + 8)
	var activated: Array[String] = []
	shelf.skill_activated.connect(func(id: String) -> void: activated.append(id))
	await _key(KEY_2)
	_check("技能架数字键经过槽激活信号", activated == ["fixture_1"])
	shelf.position = Vector2(402, 596)
	var focus_views: Array[RefCounted] = []
	for index: int in 7:
		focus_views.append(_fixture(index))
	focus_views[3].passive = true
	focus_views[3].active_capable = false
	shelf.apply_skills(focus_views)
	await process_frame
	await process_frame
	var focus_slots: Array = shelf.get_skill_slots()
	focus_slots[1].grab_focus()
	await _key(KEY_TAB)
	await _key(KEY_TAB)
	_check("Tab实际进入纯被动", focus_slots[3].has_focus())
	_check("Tab后说明卡可见", focus_slots[3].is_inspection_visible())
	var inspection: Control = focus_slots[3].get_inspection_panel()
	_check("说明卡位于行动条上方", inspection.get_global_rect().end.y <= 542.0)
	_check("说明卡不遮挡固定技能架", not inspection.get_global_rect().intersects(shelf.get_global_rect()))
	focus_slots[0].grab_focus()
	_check("纯被动失焦关闭说明", not focus_slots[3].is_inspection_visible())
	shelf.queue_free()
	await process_frame


func _test_strip() -> void:
	var strip: Panel = StripScene.instantiate()
	var view := ActionView.new()
	view.movement_remaining = 4
	view.movement_available = false
	view.standard_capacity = 2
	view.standard_remaining = 1
	view.swift_capacity = 3
	view.swift_remaining = 2
	strip.apply_view(view)
	root.add_child(strip)
	await process_frame
	await process_frame
	_check("行动条274×40", strip.size == Vector2(274, 40))
	for index: int in 3:
		var zone: Control = strip.get_node(["MovementZone", "StandardZone", "SwiftZone"][index])
		var expected: Rect2 = [Rect2(3, 3, 88.4, 45), Rect2(92.6, 3, 88.8, 45), Rect2(182.6, 3, 88.4, 45)][index]
		_check("行动实际内窗口%d" % index, zone.get_rect().is_equal_approx(expected))
	_check("移动数字不因不可用而清零", strip.get_node("MovementZone/MovementValue").text == "4")
	_check("移动数字14px", strip.get_node("MovementZone/MovementValue").get_theme_font_size(&"font_size") == 14)
	var standard: Array = strip.get_standard_pips()
	var swift: Array = strip.get_swift_pips()
	_check("行动实际容量2/3", standard.size() == 2 and swift.size() == 3)
	_check("行动点24px视口", standard[0].size == Vector2(24, 24))
	_check("行动点间距5", swift[1].position.x - swift[0].position.x == 29)
	_check("标准可用点颜色", standard[0].get_display_color() == Color("#54B789"))
	_check("迅捷可用点颜色", swift[0].get_display_color() == Color("#D49A51"))
	_check("耗尽点颜色", standard[1].get_display_color() == Color("#655E6C"))
	_check("移动耗尽双足仍可见", strip.get_node("MovementZone/FootprintGlyph").spent and strip.get_node("MovementZone/FootprintGlyph").visible)
	var footprint: Control = strip.get_node("MovementZone/FootprintGlyph")
	var number: Label = strip.get_node("MovementZone/MovementValue")
	var foot_bounds: Rect2 = footprint.get_path_bounds()
	_check("双足实际path高度20且保持原比例", is_equal_approx(foot_bounds.size.y, 20.0) and absf(foot_bounds.size.x - 15.9634257) < 0.001)
	for movement: int in [4, 12, 999]:
		view.movement_remaining = movement
		strip.apply_view(view)
		await process_frame
		var left: float = footprint.position.x + foot_bounds.position.x
		_check("%d移动图形与数字间距7" % movement, is_equal_approx(number.position.x - left - foot_bounds.size.x, 7.0))
		_check("%d移动整体中心550.2" % movement, is_equal_approx((left + number.position.x + number.size.x) * 0.5 + 506.0, 550.2))
		_check("%d移动实际字号不缩放" % movement, number.scale == Vector2.ONE and not number.clip_text)
	for capacity: int in range(1, 4):
		view.standard_capacity = capacity
		view.swift_capacity = capacity
		strip.apply_view(view)
		await process_frame
		for family: int in 2:
			var pips: Array = strip.get_standard_pips() if family == 0 else strip.get_swift_pips()
			var zone: Control = strip.get_node("StandardZone" if family == 0 else "SwiftZone")
			var first: Control = pips[0]
			var last: Control = pips[-1]
			_check("%d容量%d族整组精确居中" % [capacity, family], is_equal_approx((first.global_position.x + last.global_position.x + 24.0) * 0.5, zone.get_global_rect().get_center().x))
			for pip: Control in pips:
				var visible_bounds: Rect2 = pip.get_path_bounds()
				visible_bounds.position += pip.global_position
				_check("%d容量%d族描边不裁切" % [capacity, family], zone.get_global_rect().encloses(visible_bounds.grow(0.5)))
				_check("行动组垂直中心575.5", is_equal_approx(visible_bounds.get_center().y + 550.0, 575.5))
				if family == 0:
					_check("标准可见直径20", visible_bounds.size == Vector2(20, 20))
				else:
					var triangle: PackedVector2Array = pip.get_swift_points()
					for side: int in 3:
						_check("迅捷为24px等边三角", is_equal_approx(triangle[side].distance_to(triangle[(side + 1) % 3]), 24.0))
	var badge := Glyph.new()
	badge.size = Vector2(13, 13)
	badge.configure(Glyph.Kind.STANDARD, false)
	_check("技能角标保留13px并不继承行动条规格", not badge.strip_sizing and badge.get_path_bounds().size == Vector2(13, 13))
	badge.size = Vector2(11, 11)
	badge.configure(Glyph.Kind.SWIFT, false)
	_check("技能角标保留11px迅捷边长", is_equal_approx(badge.get_swift_points()[0].distance_to(badge.get_swift_points()[1]), 11.0))
	badge.free()
	view.standard_capacity = 9
	view.standard_remaining = 9
	view.swift_capacity = 0
	view.swift_remaining = -1
	strip.apply_view(view)
	_check("沿用行动显示归一", strip.get_standard_pips().size() == 3 and strip.get_swift_pips().size() == 1 and strip.get_swift_pips()[0].spent)
	strip.queue_free()
	await process_frame


func _click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
	await process_frame


func _key(code: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)
	await process_frame


func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + label)
