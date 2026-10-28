extends Control
## TacticalScene 的屏幕空间单位头顶控件。只呈现 Unit 与 forecast 提供的数据。

const ClassBadgeScript := preload("res://scripts/ui/character_class_badge.gd")
const DamagePopupScript: GDScript = preload("res://scripts/ui/damage_popup.gd")
const HEALTH_BAR_MAX_WIDTH: float = 40.0
const HEALTH_BAR_HEIGHT: float = 4.0
const CONTROL_GAP: float = 3.0
const COLLISION_GAP: float = 5.0 # 包含文字描边外扩与可见间隔。
const GROUP_ROW_GAP: float = 2.0
const PLACEMENT_STEP: float = 16.0
const SEARCH_RINGS: int = 32

var _owner_anchored: bool = false
var _class_badge_reference_scale: float = 1.0


func set_class_badge_reference_scale(value: float) -> void:
	_class_badge_reference_scale = maxf(value, 0.01)


## 原画棋子入口采用固定头顶小血条；旧入口保留其原布局。
func set_owner_anchored(enabled: bool) -> void:
	_owner_anchored = enabled
	for record: Dictionary in _records.values():
		record.erase("slot_offset")


var _records: Dictionary = {} # instance_id -> WeakRef + actual controls
var _forecast_targets: Dictionary = {} # instance_id -> unchanged forecast target data
var _reserved_controls: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


## 保持显示控件与当前战场单位集合一致；弱引用避免头顶 UI 延长单位寿命。
func sync_units(units: Array) -> void:
	var active_ids: Dictionary = {}
	for unit_value: Variant in units:
		if not (unit_value is Unit) or not is_instance_valid(unit_value):
			continue
		var unit: Unit = unit_value
		var instance_id: int = unit.get_instance_id()
		active_ids[instance_id] = true
		if not _records.has(instance_id):
			_records[instance_id] = _make_record(unit)
		unit.set_overhead_ui_managed(true)
	for instance_id_value: Variant in _records.keys():
		var instance_id: int = int(instance_id_value)
		var record: Dictionary = _records[instance_id]
		var weak_ref: WeakRef = record["unit_ref"]
		var unit: Object = weak_ref.get_ref()
		if not active_ids.has(instance_id) or unit == null or not is_instance_valid(unit):
			_remove_record(instance_id, record)
			_records.erase(instance_id)
			_forecast_targets.erase(instance_id)


## 取 TacticalManager 生成的 forecast targets；world/damage/type 不在此处重算。
func set_forecast_targets(targets: Array) -> void:
	_forecast_targets.clear()
	if targets.is_empty():
		return
	for target_value: Variant in targets:
		if not (target_value is Dictionary):
			continue
		var target: Dictionary = target_value
		var world: Vector2 = target.get("world", Vector2.ZERO)
		var matched_id: int = _find_target_unit_id(world)
		if matched_id == 0:
			continue
		_forecast_targets[matched_id] = target.duplicate(true)


func set_reserved_controls(controls: Array) -> void:
	_reserved_controls = controls.duplicate()


## 每帧按当前 viewport/camera 变换重排，静止时由固定排序与候选顺序保持稳定。
func refresh_layout() -> void:
	if not is_inside_tree():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var visible_records: Array[Dictionary] = []
	var body_obstacles: Array[Rect2] = []
	for instance_id_value: Variant in _records.keys():
		var record: Dictionary = _records[int(instance_id_value)]
		var weak_ref: WeakRef = record["unit_ref"]
		var unit: Object = weak_ref.get_ref()
		if unit == null or not is_instance_valid(unit):
			continue
		var data: Dictionary = (unit as Unit).get_overhead_presentation_data()
		if _owner_anchored and str(data.get("name_text", "")).is_empty():
			data["name_text"] = (unit as Unit).get_short_label()
		record["data"] = data
		record["body_rect"] = data["body_rect"]
		var canvas: Transform2D = get_viewport().get_canvas_transform()
		record["unit_screen_anchor"] = canvas * (unit as Unit).global_position
		var head: Vector2 = Vector2((record["unit_screen_anchor"] as Vector2).x, (data["body_rect"] as Rect2).position.y)
		if (unit as Unit).has_character_animation() and (unit as Unit).character_animation.has_method("overhead_anchor_world_position"):
			head = canvas * (unit as Unit).character_animation.call("overhead_anchor_world_position")
			if _owner_anchored:
				var view: Node2D = (unit as Unit).character_animation
				var local_rect: Rect2 = view.call("overhead_obstacle_rect_local")
				var transform: Transform2D = canvas * view.global_transform
				record["body_rect"] = transform * local_rect
		record["stable_head_anchor"] = head
		record["screen_tile_width"] = canvas.basis_xform(Vector2(Grid.TILE_WIDTH, 0.0)).length()
		record["forecast"] = _forecast_targets.get(int(instance_id_value), {})
		visible_records.append(record)
		var body_rect: Rect2 = record["body_rect"]
		if body_rect.size.x > 0.0 and body_rect.size.y > 0.0:
			body_obstacles.append(body_rect.grow(COLLISION_GAP))

	visible_records.sort_custom(_record_less)
	var reserved_rects: Array[Rect2] = _get_reserved_rects()
	var placed_rects: Array[Rect2] = []
	for record: Dictionary in visible_records:
		_layout_record(record, viewport_size, body_obstacles, placed_rects, reserved_rects)
	queue_redraw()


## 供同帧离屏采集观察实际 Control 矩形与单位对应关系。
func get_debug_snapshot() -> Dictionary:
	var rows: Array[Dictionary] = []
	var sorted_records: Array[Dictionary] = []
	for record_value: Variant in _records.values():
		sorted_records.append(record_value)
	sorted_records.sort_custom(_record_less)
	for record: Dictionary in sorted_records:
		var unit: Object = (record["unit_ref"] as WeakRef).get_ref()
		if unit == null or not is_instance_valid(unit):
			continue
		var data: Dictionary = record.get("data", {})
		var overhead_group: Control = record["overhead_group"]
		var forecast_group: Control = record["forecast_group"]
		var forecast_visible: bool = forecast_group.is_visible_in_tree()
		var forecast_rect: Rect2 = _forecast_control_rect(record) if forecast_visible else Rect2()
		var forecast: Dictionary = record.get("forecast", {})
		rows.append({
			"unit_id": str(data.get("unit_id", "")),
			"unit_name": str(data.get("unit_name", "")),
			"faction": str(data.get("faction", "")),
			"grid_position": data.get("grid_position", Vector2i.ZERO),
			"instance_id": int(data.get("instance_id", 0)),
			"hp_text": str(data.get("hp_text", "")),
			"name_visible": record["name_label"].is_visible_in_tree(),
			"hp_visible": record["hp_label"].is_visible_in_tree(),
			"owner_plate_visible": record["owner_plate"].is_visible_in_tree(),
			"class_icon_kind": record["class_badge"].kind if record.has("class_badge") else "",
			"class_icon_scale": record["class_badge"].scale.x if record.has("class_badge") else 1.0,
			"class_icon_ink_local": record["class_badge"].ink_polygons() if record.has("class_badge") else [],
			"class_icon_rect": _control_rect(record["class_badge"]) if record.has("class_badge") else Rect2(),
			"bar_value": record["health_bar"].value,
			"bar_max": record["health_bar"].max_value,
			"body_rect": record.get("body_rect", Rect2()),
			"unit_screen_anchor": record.get("unit_screen_anchor", Vector2.ZERO),
			"stable_head_anchor": record.get("stable_head_anchor", Vector2.ZERO),
			"screen_tile_width": record.get("screen_tile_width", 0.0),
			"slot_offset": record.get("slot_offset", Vector2.ZERO),
			"target_offset": record.get("target_offset", Vector2.ZERO),
			"slot_anchor": record.get("slot_anchor", "head"),
			"placement_clear": record.get("placement_clear", false),
			"overhead_group_name": overhead_group.name,
			"group_rect": _control_rect(overhead_group),
			"name_rect": _control_rect(record["name_label"]),
			"health_bar_rect": _control_rect(record["health_bar"]),
			"hp_text_rect": _control_rect(record["hp_label"]),
			"forecast_text": str(record["forecast_label"].text) if forecast_visible else "",
			"forecast_glyph_shape": str(record["forecast_glyph"].get("shape")) if forecast_visible and record["forecast_glyph"].visible else "",
			"forecast_rect": forecast_rect,
			"forecast_visible": forecast_visible,
			"forecast_world": forecast.get("world", Vector2.ZERO) if forecast_visible else Vector2.ZERO,
		})
	return {"viewport_size": get_viewport_rect().size, "units": rows}


func _make_record(unit: Unit) -> Dictionary:
	var overhead_group: Control = Control.new()
	overhead_group.name = "OverheadGroup_%d" % unit.get_instance_id()
	overhead_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overhead_group)
	var owner_plate: Panel = Panel.new()
	owner_plate.name = "OwnerPlate_%d" % unit.get_instance_id()
	owner_plate.visible = false
	owner_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var owner_plate_style: StyleBoxFlat = StyleBoxFlat.new()
	owner_plate_style.bg_color = Color(0.07, 0.066, 0.058, 0.93)
	owner_plate_style.set_border_width_all(1)
	owner_plate_style.border_color = Unit.FACTION_COLORS.get(unit.faction, Color.WHITE)
	owner_plate_style.set_corner_radius_all(2)
	owner_plate.add_theme_stylebox_override("panel", owner_plate_style)
	overhead_group.add_child(owner_plate)

	var name_label: Label = Label.new()
	name_label.name = "Name_%d" % unit.get_instance_id()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 3)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overhead_group.add_child(name_label)

	var health_bar: ProgressBar = ProgressBar.new()
	health_bar.name = "HealthBar_%d" % unit.get_instance_id()
	health_bar.show_percentage = false
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = Color(0.10, 0.10, 0.12, 0.96)
	background.set_border_width_all(1)
	background.border_color = Unit.FACTION_COLORS.get(unit.faction, Color.WHITE)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = Unit.HP_FULL_COLOR
	health_bar.add_theme_stylebox_override("background", background)
	health_bar.add_theme_stylebox_override("fill", fill)
	overhead_group.add_child(health_bar)

	var hp_label: Label = Label.new()
	hp_label.name = "HP_%d" % unit.get_instance_id()
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_label.add_theme_color_override("font_color", Color.WHITE)
	hp_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	hp_label.add_theme_constant_override("outline_size", 2)
	hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overhead_group.add_child(hp_label)

	var forecast_group: Control = Control.new()
	forecast_group.name = "ForecastGroup_%d" % unit.get_instance_id()
	forecast_group.visible = false
	forecast_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overhead_group.add_child(forecast_group)

	var forecast_glyph: Control = DamagePopupScript._Glyph.new()
	forecast_glyph.name = "ForecastGlyph_%d" % unit.get_instance_id()
	forecast_glyph.visible = false
	forecast_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	forecast_group.add_child(forecast_glyph)

	var forecast_label: Label = Label.new()
	forecast_label.name = "Forecast_%d" % unit.get_instance_id()
	forecast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	forecast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	forecast_label.visible = false
	forecast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	forecast_group.add_child(forecast_label)
	return {
		"unit_ref": weakref(unit),
		"overhead_group": overhead_group,
		"owner_plate": owner_plate,
		"name_label": name_label,
		"health_bar": health_bar,
		"hp_label": hp_label,
		"forecast_group": forecast_group,
		"forecast_glyph": forecast_glyph,
		"forecast_label": forecast_label,
		"data": {},
		"body_rect": Rect2(),
		"forecast": {},
	}


func _remove_record(instance_id: int, record: Dictionary) -> void:
	if record.has("class_badge") and is_instance_valid(record["class_badge"]):
		record["class_badge"].queue_free()
	var overhead_group: Control = record["overhead_group"]
	if is_instance_valid(overhead_group):
		overhead_group.queue_free()


func _find_target_unit_id(world: Vector2) -> int:
	for instance_id_value: Variant in _records.keys():
		var record: Dictionary = _records[int(instance_id_value)]
		var unit: Object = (record["unit_ref"] as WeakRef).get_ref()
		if unit == null or not is_instance_valid(unit):
			continue
		var anchor: Vector2 = (unit as Unit).get_combat_text_anchor_world(-30.0)
		if anchor.is_equal_approx(world):
			return int(instance_id_value)
	return 0


func _layout_record(record: Dictionary, viewport_size: Vector2,
		body_obstacles: Array[Rect2], placed_rects: Array[Rect2], reserved_rects: Array[Rect2]) -> void:
	if _owner_anchored:
		_layout_owned_health_bar(record, viewport_size, body_obstacles, placed_rects, reserved_rects)
		return
	if record.has("class_badge"):
		record["class_badge"].hide()
	# Legacy entries retain their existing name/HP/forecast presentation.
	var data: Dictionary = record["data"]
	var body_rect: Rect2 = record["body_rect"]
	var overhead_group: Control = record["overhead_group"]
	var alive: bool = bool(data.get("alive", false))
	var name_label: Label = record["name_label"]
	var health_bar: ProgressBar = record["health_bar"]
	var hp_label: Label = record["hp_label"]
	var forecast_group: Control = record["forecast_group"]
	var forecast_glyph: Control = record["forecast_glyph"]
	var forecast_label: Label = record["forecast_label"]
	overhead_group.visible = alive
	record["owner_plate"].hide()
	name_label.text = str(data.get("name_text", ""))
	name_label.visible = alive and not name_label.text.is_empty()
	name_label.add_theme_font_size_override("font_size", int(data.get("name_font_size", 18)))
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 3)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var name_size: Vector2 = _measure_label(name_label, Vector2.ZERO, 3.0)
	name_label.size = name_size
	health_bar.visible = alive
	health_bar.max_value = maxf(1.0, float(data.get("hp_max", 1)))
	health_bar.value = float(data.get("hp_value", 0))
	health_bar.size = Vector2(minf(HEALTH_BAR_MAX_WIDTH, maxf(1.0, body_rect.size.x)), HEALTH_BAR_HEIGHT)
	var fill_style: StyleBoxFlat = health_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style != null:
		fill_style.bg_color = data.get("hp_color", Unit.HP_FULL_COLOR)
	hp_label.text = str(data.get("hp_text", ""))
	hp_label.visible = alive and not hp_label.text.is_empty()
	hp_label.add_theme_font_size_override("font_size", int(data.get("hp_font_size", 9)))
	hp_label.add_theme_color_override("font_color", Color.WHITE)
	hp_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	hp_label.add_theme_constant_override("outline_size", 2)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hp_size: Vector2 = _measure_label(hp_label, Vector2.ZERO, 2.0)
	hp_label.size = hp_size
	var background_style: StyleBoxFlat = health_bar.get_theme_stylebox("background") as StyleBoxFlat
	if background_style != null:
		background_style.border_color = data.get("faction_color", Color.WHITE)
	var forecast: Dictionary = record.get("forecast", {})
	var has_forecast: bool = alive and not forecast.is_empty()
	forecast_group.visible = has_forecast
	forecast_label.visible = has_forecast
	forecast_glyph.visible = has_forecast and str(forecast.get("shape", "")) != "none"
	if not has_forecast:
		forecast_label.text = ""
		forecast_label.position = Vector2.ZERO
		forecast_glyph.position = Vector2.ZERO
		forecast_group.position = Vector2.ZERO
		forecast_group.size = Vector2.ZERO
	else:
		var parts: Dictionary = DamagePopupScript.compose(
			int(forecast.get("damage", 0)), str(forecast.get("damage_type", "physical")), false)
		forecast_label.text = str(parts.get("text", ""))
		var font_size: int = int(parts.get("size", 16))
		forecast_label.add_theme_font_size_override("font_size", font_size)
		forecast_label.add_theme_color_override("font_color", parts.get("color", Color.WHITE))
		forecast_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.75))
		forecast_label.add_theme_constant_override("outline_size", 2)
		var forecast_size: Vector2 = _measure_label(forecast_label, Vector2.ZERO, 2.0)
		forecast_label.size = forecast_size
		forecast_glyph.set("shape", str(parts.get("shape", "sword")))
		forecast_glyph.set("color", parts.get("color", Color.WHITE))
		forecast_glyph.size = Vector2(DamagePopupScript.GLYPH_SIZE, DamagePopupScript.GLYPH_SIZE)
		var glyph_size: Vector2 = forecast_glyph.size if forecast_glyph.visible else Vector2.ZERO
		var forecast_size_with_glyph: Vector2 = forecast_size
		if forecast_glyph.visible:
			forecast_size_with_glyph.x += glyph_size.x + DamagePopupScript.GLYPH_GAP
			forecast_size_with_glyph.y = maxf(forecast_size_with_glyph.y, glyph_size.y)
		forecast_group.size = forecast_size_with_glyph
		if forecast_glyph.visible:
			forecast_glyph.position = Vector2(0.0, (forecast_size_with_glyph.y - glyph_size.y) * 0.5)
			forecast_label.position = Vector2(
				glyph_size.x + DamagePopupScript.GLYPH_GAP,
				(forecast_size_with_glyph.y - forecast_size.y) * 0.5)
		else:
			forecast_label.position = Vector2.ZERO

	var forecast_row_size: Vector2 = forecast_group.size if has_forecast else Vector2.ZERO
	var group_width: float = maxf(name_size.x, maxf(health_bar.size.x, hp_label.size.x))
	if has_forecast:
		group_width = maxf(group_width, forecast_row_size.x)
	var row_y: float = 0.0
	name_label.size = Vector2(group_width, name_size.y)
	name_label.position = Vector2(0.0, row_y)
	row_y += name_size.y
	if has_forecast:
		row_y += GROUP_ROW_GAP
		forecast_group.position = Vector2((group_width - forecast_row_size.x) * 0.5, row_y)
		row_y += forecast_row_size.y
	row_y += GROUP_ROW_GAP
	health_bar.position = Vector2((group_width - health_bar.size.x) * 0.5, row_y)
	row_y += HEALTH_BAR_HEIGHT + GROUP_ROW_GAP
	hp_label.size = Vector2(group_width, hp_label.size.y)
	hp_label.position = Vector2(0.0, row_y)
	row_y += hp_label.size.y
	var group_size: Vector2 = Vector2(group_width, row_y)
	overhead_group.size = group_size

	var base_center: Vector2
	if has_forecast:
		var forecast_anchor: Vector2 = get_viewport().get_canvas_transform() * (forecast.get("world", Vector2.ZERO) as Vector2)
		var forecast_row_center_y: float = forecast_group.position.y + forecast_row_size.y * 0.5
		base_center = Vector2(forecast_anchor.x, forecast_anchor.y + group_size.y * 0.5 - forecast_row_center_y)
	else:
		base_center = Vector2(body_rect.get_center().x, body_rect.position.y - COLLISION_GAP - group_size.y * 0.5)
	_place_group(overhead_group, base_center, viewport_size, body_obstacles, placed_rects, reserved_rects)




func _layout_owned_health_bar(record: Dictionary, viewport_size: Vector2,
		body_obstacles: Array[Rect2], placed_rects: Array[Rect2], reserved_rects: Array[Rect2]) -> void:
	var data: Dictionary = record["data"]
	var group: Control = record["overhead_group"]
	group.visible = bool(data.get("alive", false))
	# Details belong to the existing selection/hover/attack HUD, not every world unit.
	for key: String in ["name_label", "hp_label", "owner_plate", "forecast_group"]:
		record[key].hide()
	var bar: ProgressBar = record["health_bar"]
	bar.visible = group.visible
	bar.max_value = maxf(1.0, float(data.get("hp_max", 1)))
	bar.value = float(data.get("hp_value", 0))
	bar.position = Vector2.ZERO
	bar.size = Vector2(HEALTH_BAR_MAX_WIDTH, HEALTH_BAR_HEIGHT)
	group.size = bar.size
	var faction: Color = data.get("faction_color", Color.WHITE)
	var fill: StyleBoxFlat = bar.get_theme_stylebox("fill") as StyleBoxFlat
	var background: StyleBoxFlat = bar.get_theme_stylebox("background") as StyleBoxFlat
	if fill != null:
		fill.bg_color = faction
	if background != null:
		# Keep the 40x4 bar and head anchor; separate its silhouette from bright ground.
		background.border_color = Color("101319")
		background.shadow_color = Color("080b10f5")
		background.shadow_size = 2
		background.shadow_offset = Vector2.ZERO
	_place_owned_group(record, viewport_size, body_obstacles, placed_rects, reserved_rects)
	if not record.has("class_badge"):
		var created_badge: Control = ClassBadgeScript.new()
		created_badge.name = "ClassBadge_%d" % int(data["instance_id"])
		created_badge.call("configure", str(data["unit_id"]), faction)
		add_child(created_badge)
		record["class_badge"] = created_badge
	var badge: Control = record["class_badge"]
	badge.visible = group.visible and not str(badge.get("kind")).is_empty()
	var projection_ratio: float = float(record["screen_tile_width"]) / float(Grid.TILE_WIDTH) / _class_badge_reference_scale
	badge.scale = Vector2.ONE * projection_ratio
	badge.position = (record["unit_screen_anchor"] as Vector2) + ClassBadgeScript.OFFSET * projection_ratio


## 当前原画棋子入口统一头顶；冲突只记录，不移动人物牌逃避。
func _place_owned_group(record: Dictionary, viewport_size: Vector2,
		body_obstacles: Array[Rect2], placed_rects: Array[Rect2], reserved_rects: Array[Rect2]) -> void:
	var group: Control = record["overhead_group"]
	var head: Vector2 = record["stable_head_anchor"]
	var foot: Vector2 = record["unit_screen_anchor"]
	var chosen := Rect2(Vector2(foot.x - group.size.x * 0.5,
		head.y - COLLISION_GAP - group.size.y), group.size)
	record["slot_anchor"] = "head"
	record["slot_offset"] = Vector2.ZERO
	record["target_offset"] = Vector2.ZERO
	group.position = chosen.position
	record["placement_clear"] = _fits(chosen, viewport_size, body_obstacles, placed_rects, reserved_rects)
	var forecast: Control = record["forecast_group"]
	if forecast.is_visible_in_tree():
		record["placement_clear"] = bool(record["placement_clear"]) and _fits(
			forecast.get_global_rect(), viewport_size, body_obstacles, placed_rects, reserved_rects)
	placed_rects.append(chosen.grow(COLLISION_GAP))


func _place_group(group: Control, base_center: Vector2, viewport_size: Vector2,
		body_obstacles: Array[Rect2], placed_rects: Array[Rect2],
		reserved_rects: Array[Rect2]) -> Rect2:
	var chosen: Rect2 = _find_placement(
		base_center, group.size, viewport_size, body_obstacles, placed_rects, reserved_rects)
	group.position = chosen.position
	placed_rects.append(chosen.grow(COLLISION_GAP))
	return chosen


func _find_placement(base_center: Vector2, control_size: Vector2, viewport_size: Vector2,
		body_obstacles: Array[Rect2], placed_rects: Array[Rect2],
		reserved_rects: Array[Rect2]) -> Rect2:
	var fallback: Rect2 = Rect2(base_center - control_size * 0.5, control_size)
	var step_x: float = maxf(20.0, control_size.x + CONTROL_GAP)
	var step_y: float = PLACEMENT_STEP
	var center_candidate: Rect2 = fallback
	if _fits(center_candidate, viewport_size, body_obstacles, placed_rects, reserved_rects):
		return center_candidate
	for ring: int in range(1, SEARCH_RINGS + 1):
		# 先沿单位中心线上下找位置，使同一单位的名称、HP 与预测保持对齐。
		var top_center: Vector2 = base_center + Vector2(0.0, -float(ring) * step_y)
		var top_candidate: Rect2 = Rect2(top_center - control_size * 0.5, control_size)
		if _fits(top_candidate, viewport_size, body_obstacles, placed_rects, reserved_rects):
			return top_candidate
		var bottom_center: Vector2 = base_center + Vector2(0.0, float(ring) * step_y)
		var bottom_candidate: Rect2 = Rect2(bottom_center - control_size * 0.5, control_size)
		if _fits(bottom_candidate, viewport_size, body_obstacles, placed_rects, reserved_rects):
			return bottom_candidate
		var left_center: Vector2 = base_center + Vector2(-float(ring) * step_x, 0.0)
		var left_candidate: Rect2 = Rect2(left_center - control_size * 0.5, control_size)
		if _fits(left_candidate, viewport_size, body_obstacles, placed_rects, reserved_rects):
			return left_candidate
		var right_center: Vector2 = base_center + Vector2(float(ring) * step_x, 0.0)
		var right_candidate: Rect2 = Rect2(right_center - control_size * 0.5, control_size)
		if _fits(right_candidate, viewport_size, body_obstacles, placed_rects, reserved_rects):
			return right_candidate
		for offset_x: int in range(-ring, ring + 1):
			if offset_x == 0:
				continue
			var top_edge_center: Vector2 = base_center + Vector2(float(offset_x) * step_x, -float(ring) * step_y)
			var top_edge_candidate: Rect2 = Rect2(top_edge_center - control_size * 0.5, control_size)
			if _fits(top_edge_candidate, viewport_size, body_obstacles, placed_rects, reserved_rects):
				return top_edge_candidate
			var bottom_edge_center: Vector2 = base_center + Vector2(float(offset_x) * step_x, float(ring) * step_y)
			var bottom_edge_candidate: Rect2 = Rect2(bottom_edge_center - control_size * 0.5, control_size)
			if _fits(bottom_edge_candidate, viewport_size, body_obstacles, placed_rects, reserved_rects):
				return bottom_edge_candidate
		for offset_y: int in range(-ring, ring + 1):
			if offset_y == 0:
				continue
			var left_edge_center: Vector2 = base_center + Vector2(-float(ring) * step_x, float(offset_y) * step_y)
			var left_edge_candidate: Rect2 = Rect2(left_edge_center - control_size * 0.5, control_size)
			if _fits(left_edge_candidate, viewport_size, body_obstacles, placed_rects, reserved_rects):
				return left_edge_candidate
			var right_edge_center: Vector2 = base_center + Vector2(float(ring) * step_x, float(offset_y) * step_y)
			var right_edge_candidate: Rect2 = Rect2(right_edge_center - control_size * 0.5, control_size)
			if _fits(right_edge_candidate, viewport_size, body_obstacles, placed_rects, reserved_rects):
				return right_edge_candidate
	return fallback


func _fits(candidate: Rect2, viewport_size: Vector2, body_obstacles: Array[Rect2],
		placed_rects: Array[Rect2], reserved_rects: Array[Rect2]) -> bool:
	if candidate.position.x < 1.0 or candidate.position.y < 1.0 \
			or candidate.end.x > viewport_size.x - 1.0 \
			or candidate.end.y > viewport_size.y - 1.0:
		return false
	for obstacle: Rect2 in body_obstacles:
		if candidate.intersects(obstacle):
			return false
	for obstacle: Rect2 in placed_rects:
		if candidate.intersects(obstacle):
			return false
	for obstacle: Rect2 in reserved_rects:
		if candidate.intersects(obstacle.grow(COLLISION_GAP)):
			return false
	return true


func _get_reserved_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for control_value: Variant in _reserved_controls:
		if not (control_value is Control):
			continue
		var control: Control = control_value
		if not control.is_visible_in_tree():
			continue
		if control.has_method("get_input_blocking_rects"):
			var blocking_value: Variant = control.call("get_input_blocking_rects")
			if blocking_value is Array:
				for rect_value: Variant in blocking_value:
					if not (rect_value is Rect2):
						continue
					var blocking_rect: Rect2 = rect_value
					if blocking_rect.size.x > 0.0 and blocking_rect.size.y > 0.0:
						result.append(blocking_rect)
			continue
		var rect: Rect2 = control.get_global_rect()
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			result.append(rect)
	return result


func _measure_label(label: Label, floor_size: Vector2, outline_margin: float) -> Vector2:
	var minimum: Vector2 = label.get_combined_minimum_size()
	return Vector2(
		maxf(floor_size.x, ceilf(minimum.x) + outline_margin * 2.0),
		maxf(floor_size.y, ceilf(minimum.y) + outline_margin * 2.0))


func _control_rect(control: Control) -> Rect2:
	return control.get_global_rect() if is_instance_valid(control) and control.is_visible_in_tree() else Rect2()


func _forecast_control_rect(record: Dictionary) -> Rect2:
	var group: Control = record["forecast_group"]
	return group.get_global_rect() if group.is_visible_in_tree() else Rect2()


func _record_less(left: Dictionary, right: Dictionary) -> bool:
	var left_data: Dictionary = left.get("data", {})
	var right_data: Dictionary = right.get("data", {})
	var left_key: String = "%s|%s|%010d" % [str(left_data.get("faction", "")), str(left_data.get("unit_id", "")), int(left_data.get("instance_id", 0))]
	var right_key: String = "%s|%s|%010d" % [str(right_data.get("faction", "")), str(right_data.get("unit_id", "")), int(right_data.get("instance_id", 0))]
	return left_key < right_key
