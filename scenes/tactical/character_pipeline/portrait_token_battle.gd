extends "res://scripts/ui/playground/battlefield_courtyard.gd"
## 使用正式 TacticalScene 和中庭原贴图的静态原画棋子实战入口。

const STYLE_PATH := "res://assets/prototype/character_pipeline/portrait_token_style.json"
const COURTYARD_PROFILE_PATH := "res://assets/prototype/battlefield_courtyard/visual_profile.json"
const TreePresentation := preload("res://scenes/tactical/character_pipeline/portrait_tree_presentation.gd")

var tree_presentation: RefCounted
var _tree_config: Dictionary = {}

const FACTION_RING_SCRIPT := preload("res://scenes/tactical/character_pipeline/faction_ring.gd")

var _unit_screen_height: float = 72.0
var _faction_colors: Dictionary = {}
var _token_presentation: Dictionary = {}
var _character_visuals: Dictionary = {}
var _forecast_placement: Dictionary = {}
var _unit_hover_instance: int = 0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index in [
				MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)


func _ready() -> void:
	var style_file := FileAccess.open(STYLE_PATH, FileAccess.READ)
	if style_file == null:
		push_error("[PortraitTokenBattle] Cannot open style: " + STYLE_PATH)
		return
	var style_value: Variant = JSON.parse_string(style_file.get_as_text())
	if not (style_value is Dictionary):
		push_error("[PortraitTokenBattle] Style must contain a JSON object.")
		return
	var config: Dictionary = style_value
	var layout_value: Variant = config.get("layout", {})
	var colors_value: Variant = config.get("faction_colors", {})
	if not (layout_value is Dictionary) or not (colors_value is Dictionary):
		push_error("[PortraitTokenBattle] Style is missing its layout or faction_colors object.")
		return
	var profile_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(COURTYARD_PROFILE_PATH))
	if not (profile_value is Dictionary):
		push_error("[PortraitTokenBattle] Cannot load the shared courtyard visual profile.")
		return

	_unit_screen_height = float(config.get("unit_screen_height", 72.0))
	_faction_colors = (colors_value as Dictionary).duplicate(true)
	_token_presentation = config.get("token_presentation", {}).duplicate(true)
	_character_visuals = config.get("character_visuals", {}).duplicate(true)
	var layout: Dictionary = (layout_value as Dictionary).duplicate(true)
	var layout_key := str(config.get("default_layout", "portrait_courtyard"))
	layouts = {layout_key: layout}
	layout_id = layout_key
	# 继续用中庭现有的地面、林木、石材与镜头设定，不覆写生产 visual_profile。
	visual_profile = (profile_value as Dictionary).duplicate(true)
	visual_profile["prop_tints"] = visual_profile.get("prop_tints", {}).duplicate(true)
	_tree_config = config.get("tree_presentation", {}).duplicate(true)
	if not _tree_config.is_empty():
		var path: String = str(_tree_config["texture_path"])
		if FileAccess.get_sha256(path) != str(_tree_config["sha256"]):
			push_error("[PortraitTokenBattle] Tree source identity mismatch.")
			return
		visual_profile["tree"]["texture"] = path
		visual_profile["prop_tints"]["tree"] = _tree_config["tint"]
		visual_profile["prop_tints"]["environment_tree"] = _tree_config["tint"]
		visual_profile["prop_tints"]["shrub"] = _tree_config["shrub_tint"]
		visual_profile["portrait_tree_presentation"] = _tree_config
	_build_overlay()
	get_viewport().size_changed.connect(_resize)
	await select_layout(layout_id)
	RenderingServer.frame_pre_draw.connect(_refresh_token_overlay_before_draw)


func _build_overlay() -> void:
	super._build_overlay()
	_description.clip_text = true
	_description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_description.max_lines_visible = 1
	# 入口只有一个真实战斗布局，移除基类中其他中庭候选布局按钮。
	var view_label_index: int = -1
	for index: int in _buttons.get_child_count():
		var child: Node = _buttons.get_child(index)
		if child is Label and (child as Label).text == "视图":
			view_label_index = index
			break
	if view_label_index < 0:
		return
	for _index: int in range(view_label_index):
		_buttons.get_child(0).free()
	_layout_buttons.clear()
	_layout_button_group = ButtonGroup.new()
	var scene_label := Label.new()
	scene_label.text = "战场"
	scene_label.custom_minimum_size.y = 30
	scene_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	scene_label.add_theme_font_size_override("font_size", 13)
	scene_label.add_theme_color_override("font_color", Color("cfc8b5"))
	_buttons.add_child(scene_label)
	var layout: Dictionary = layouts.get(layout_id, {})
	var scene_button := _add_button(str(layout.get("name", "原画棋子实战")), _on_layout_button_pressed.bind(layout_id))
	scene_button.toggle_mode = true
	scene_button.button_group = _layout_button_group
	scene_button.custom_minimum_size.x = 132
	_layout_buttons[layout_id] = scene_button
	_buttons.move_child(scene_button, 1)
	_buttons.move_child(scene_label, 0)


func _update_scene_labels() -> void:
	super._update_scene_labels()
	_description.text = "左键选择与移动 · 下方选择技能 · 右键取消 · 结束回合后继续行动顺序"


func _resize() -> void:
	super._resize()
	if not is_instance_valid(battle) or _description == null:
		return
	var turn_order: Control = battle.get("_turn_order_bar") as Control
	if turn_order != null:
		var right_edge: float = turn_order.get_global_rect().position.x / _overlay.scale.x
		_description.size = Vector2(maxf(1.0, right_edge - _description.position.x - 24.0), 24.0)


func _style_unit_marker(_unit: Unit) -> void:
	# 原画棋子、单位自身血条与阵营环承担占位反馈；不绘制中庭候选的平面底座。
	pass


func _create_battle() -> void:
	# 基类创建正式 TacticalScene、原 CourtyardBoardView、注入地图及 HUD。
	super._create_battle()
	if not is_instance_valid(battle) or manager == null:
		return
	battle.get("_unit_overhead_layout").call("set_owner_anchored", true)
	battle.set("forecast_placement_override", Callable(self, "_place_owned_forecast"))
	# 先按入口视口套用中庭镜头，再换算棋子所需世界高度。
	_resize()
	battle.get("_unit_overhead_layout").call("set_class_badge_reference_scale", camera.zoom.x)
	var target_world_height: float = _unit_screen_height / maxf(camera.zoom.y, 0.1)
	for unit_value: Variant in manager.units:
		if not (unit_value is Unit):
			continue
		var unit: Unit = unit_value
		var presentation: Dictionary = _token_presentation
		var unit_height: float = target_world_height
		# Enemy placeholders keep the existing presentation; only explicit player bindings vary.
		if unit.faction == "player" and _character_visuals.has(unit.unit_id):
			presentation = (_character_visuals[unit.unit_id] as Dictionary).duplicate(true)
			unit_height = float(presentation.get("display_height_px", _unit_screen_height)) / maxf(camera.zoom.y, 0.1)
		var enabled: bool = false
		if unit.has_method("enable_portrait_token"):
			enabled = bool(unit.call("enable_portrait_token", unit_height, presentation))
		if not enabled:
			push_warning("[PortraitTokenBattle] Portrait token unavailable for " + unit.unit_id)
		var ring: Node2D = FACTION_RING_SCRIPT.new()
		ring.name = "PersistentFactionRing"
		ring.center_offset = Vector2.ZERO
		ring.compact_badge_layout = false
		ring.allegiance = Color(str(_faction_colors.get(
			unit.faction, "53c5cf" if unit.faction == "player" else "e98a57")))
		# 阵营环贴地并留在 UnitLayer 的 y-sort 中，显示棋子仍决定单位前后关系。
		ring.show_behind_parent = true
		unit.add_child(ring)
		unit.move_child(ring, 0)

	if not _tree_config.is_empty():
		tree_presentation = TreePresentation.new()
		tree_presentation.configure(board_view, manager, _tree_config)


func _destroy_battle() -> void:
	tree_presentation = null
	if is_instance_valid(battle):
		battle.tactical_manager.stop_battle()
	super._destroy_battle()


func _process(delta: float) -> void:
	super._process(delta)
	_update_unit_hover_detail()
	if tree_presentation != null:
		tree_presentation.update(delta)
	# This entry alone clears the aiming panel while the real action is resolving.
	# Forecast data and the production HUD remain unchanged for all other scenes.
	if is_instance_valid(battle) and manager != null:
		var forecast: Control = battle.get("_damage_forecaster") as Control
		if forecast != null:
			if manager.input_state == manager.InputState.ANIMATING:
				forecast.hide()


## Only this entry moves the aiming popup; owned unit cards never move for it.
## Keep the production content/size and prefer the original target-relative position.
func _place_owned_forecast(forecast: Control) -> void:
	var overhead: Control = battle.get("_unit_overhead_layout") as Control
	# Sync newly visible per-target forecast glyphs before the first popup draw.
	overhead.call("refresh_layout")
	var snapshot: Dictionary = overhead.call("get_debug_snapshot")
	var visual_size: Vector2 = forecast.call("get_visual_size")
	var preferred: Vector2 = forecast.global_position
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var top: float = _buttons.get_global_rect().end.y + 6.0
	var bottom: float = viewport_size.y - 4.0
	var dashboard: Control = battle.get("_bottom_dashboard") as Control
	if dashboard != null:
		bottom = minf(bottom, float(dashboard.call("get_content_top_y")) - 8.0)
	var bounds := Rect2(Vector2(4.0, top), Vector2(viewport_size.x - 8.0, bottom - top))
	var obstacles: Array[Rect2] = []
	for row: Dictionary in snapshot.get("units", []):
		for key: String in ["group_rect", "body_rect", "forecast_rect", "class_icon_rect"]:
			var obstacle: Rect2 = row.get(key, Rect2())
			if obstacle.has_area():
				obstacles.append(obstacle.grow(6.0))
	var turn_order: Control = battle.get("_turn_order_bar") as Control
	if turn_order != null and turn_order.is_visible_in_tree():
		obstacles.append(turn_order.get_global_rect().grow(6.0))
	# Candidate edges come from real occupied rectangles, not fixed screen locations.
	var xs: Array[float] = [preferred.x]
	var ys: Array[float] = [preferred.y]
	for obstacle: Rect2 in obstacles:
		xs.append(obstacle.position.x - visual_size.x)
		xs.append(obstacle.end.x)
		ys.append(obstacle.position.y - visual_size.y)
		ys.append(obstacle.end.y)
	var found: bool = false
	var best: Vector2 = preferred
	var best_distance: float = INF
	for x: float in xs:
		for y: float in ys:
			var candidate := Rect2(Vector2(x, y), visual_size)
			if not bounds.encloses(candidate):
				continue
			var clear: bool = true
			for obstacle: Rect2 in obstacles:
				if candidate.intersects(obstacle):
					clear = false
					break
			if clear and candidate.position.distance_squared_to(preferred) < best_distance:
				found = true
				best = candidate.position
				best_distance = best.distance_squared_to(preferred)
	if found:
		forecast.global_position = best
	forecast.call("set_target_pointer_visible", not found or best.is_equal_approx(preferred))
	_forecast_placement = {"preferred_rect":Rect2(preferred, visual_size),
		"actual_rect":Rect2(forecast.global_position, visual_size),
		"placement_clear":found,"obstacles":obstacles,"bounds":bounds,
		"pointer_visible":forecast.get("target_pointer_visible")}


func get_forecast_placement_snapshot() -> Dictionary:
	return _forecast_placement.duplicate(true)


## Reuse the existing courtyard hint panel for ordinary unit hover details.
## Attack prediction and animation suppress this hint; selected HP remains in the dashboard.
func _update_unit_hover_detail() -> void:
	_unit_hover_instance = 0
	if manager == null or _tooltip == null:
		return
	if manager.is_targeting_active() or manager.input_state == manager.InputState.ANIMATING:
		_tooltip.hide()
		return
	if not _tooltip_enabled or get_viewport().gui_get_hovered_control() != null:
		return
	var hover: Dictionary = manager.get_hover_world_pos()
	if not bool(hover.get("has", false)):
		return
	var world: Vector2 = hover["world"]
	var unit: Unit = manager.grid.get_unit_at(manager.grid.world_to_grid(world))
	if not is_instance_valid(unit) or not unit.stats.is_alive():
		return
	_tooltip_text.text = "%s · HP %d/%d" % [unit.get_short_label(), unit.stats.hp, unit.stats.max_hp]
	_tooltip.reset_size()
	if _position_tooltip(get_viewport().get_canvas_transform() * world):
		_tooltip.show()
		_unit_hover_instance = unit.get_instance_id()
	else:
		_tooltip.hide()


func get_unit_hover_detail_snapshot() -> Dictionary:
	return {"visible":_unit_hover_instance != 0 and _tooltip.is_visible_in_tree(),
		"instance":_unit_hover_instance,"text":_tooltip_text.text,
		"rect":_tooltip.get_global_rect() if _unit_hover_instance != 0 and _tooltip.is_visible_in_tree() else Rect2()}


func _refresh_token_overlay_before_draw() -> void:
	# Tweens advance after Node._process; project the actual final foot before drawing.
	if not is_instance_valid(battle):
		return
	var overlay: Control = battle.get("_unit_overhead_layout")
	if is_instance_valid(overlay):
		overlay.call("refresh_layout")


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_refresh_token_overlay_before_draw):
		RenderingServer.frame_pre_draw.disconnect(_refresh_token_overlay_before_draw)
