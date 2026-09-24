class_name HudM2RuntimeDashboard
extends Control

## 真实 TacticalManager 载荷的 M2 宿主。它只绑定既有视图组合，行为仍由调用方连接到 manager。

signal attack_requested
signal skill_toggle_requested
signal skill_selected(skill_id: String)
signal end_turn_requested
signal end_move_requested
signal cancel_requested

const CompositionScene: PackedScene = preload("res://scenes/tactical/hud/m2/bottom_hud_composition.tscn")
const DashboardViewAdapter := preload("res://scripts/ui/hud/m2/dashboard_view_adapter.gd")
const SkillIconCatalog := preload("res://scripts/ui/hud/m2/skill_icon_catalog.gd")
const DefaultSkin: Theme = preload("res://assets/ui/themes/hud_m2.tres")

var _composition: Control = null
var _icon_textures: Dictionary = {}
var _last_state: Dictionary = {}
var _skin_theme: Theme = DefaultSkin
var _skill_icon_catalog := SkillIconCatalog.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_composition = CompositionScene.instantiate() as Control
	_composition.set_skin_theme(_skin_theme)
	_composition.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_composition)
	_composition.skill_activated.connect(_on_skill_activated)
	_composition.end_turn_requested.connect(_on_end_turn_requested)
	_composition.end_move_requested.connect(_on_end_move_requested)
	_layout_composition()
	_apply_state()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_composition()


func set_icon_textures(icon_textures: Dictionary) -> void:
	_icon_textures = icon_textures.duplicate()
	_apply_state()


func update_state(state: Dictionary) -> void:
	_last_state = state.duplicate(true)
	_apply_state()


func get_last_state() -> Dictionary:
	return _last_state.duplicate(true)


func get_composition() -> Control:
	return _composition


func set_skin_theme(value: Theme) -> void:
	_skin_theme = value if value != null else DefaultSkin
	if _composition != null:
		_composition.set_skin_theme(_skin_theme)


func get_skin_theme() -> Theme:
	return _composition.get_skin_theme() if _composition != null else _skin_theme


func get_content_top_y() -> float:
	var rectangles: Array[Rect2] = get_input_blocking_rects()
	if rectangles.is_empty():
		return get_viewport().get_visible_rect().end.y
	var top: float = rectangles[0].position.y
	for rectangle: Rect2 in rectangles:
		top = minf(top, rectangle.position.y)
	return top


func get_input_blocking_rects() -> Array[Rect2]:
	var rectangles: Array[Rect2] = []
	if _composition == null or not _composition.is_visible_in_tree():
		return rectangles
	rectangles.append_array(_composition.get_shared_frame().get_input_blocking_rects())
	rectangles.append_array(_composition.get_class_resource_host().get_input_blocking_rects())
	rectangles.append_array(_composition.get_marks_panel().get_input_blocking_rects())
	var row: Control = _composition.get_node("BottomRow") as Control
	for child: Node in row.get_children():
		var control: Control = child as Control
		if control != null and control.is_visible_in_tree():
			if control.name == &"CharacterHudPanel" and control.has_method("get_input_blocking_rects"):
				rectangles.append_array(control.get_input_blocking_rects())
			else:
				rectangles.append(control.get_global_rect())
			if control.name == &"SkillShelf":
				_append_skill_inspection_rectangles(control, rectangles)
	var action_strip: Control = _composition.get_node("ActionResourceStrip") as Control
	if action_strip.is_visible_in_tree():
		rectangles.append(action_strip.get_global_rect())
	return rectangles


func _layout_composition() -> void:
	if _composition == null:
		return
	var visible_size: Vector2 = get_viewport_rect().size
	if visible_size.x <= 0.0 or visible_size.y <= 0.0:
		return
	var factor: float = minf(visible_size.x / 1280.0, visible_size.y / 720.0)
	_composition.scale = Vector2.ONE * factor
	_composition.position = (visible_size - Vector2(1280.0, 720.0) * factor) * 0.5


func _apply_state() -> void:
	if _composition == null:
		return
	var entries: Array = _last_state.get("skills", []) if _last_state.get("skills", []) is Array else []
	var class_id: StringName = &""
	var class_display: Variant = _last_state.get("class_resource_display", {})
	if class_display is Dictionary:
		class_id = StringName(str(class_display.get("class_id", "")))
	var resolved_icons: Dictionary = _skill_icon_catalog.resolve_entries(entries, class_id)
	resolved_icons.merge(_icon_textures, true)
	var views: Dictionary = DashboardViewAdapter.new().build(_last_state, resolved_icons)
	_composition.visible = bool(views.get("visible", false))
	if not _composition.visible:
		return
	_composition.apply_character(views["character"])
	var skills: Array[RefCounted] = []
	if bool(_last_state.get("skills_visible", false)):
		skills.assign(views["skills"])
	_composition.apply_skills(skills)
	_composition.get_node("BottomRow/SkillShelf").set_shortcut_input_enabled(false)
	_composition.apply_equipment(views["weapon"], views["armor"], views["potion"])
	_composition.apply_relics(views["relics"])
	var action_strip: Control = _composition.get_node("ActionResourceStrip") as Control
	action_strip.visible = bool(views["action_resources_valid"])
	if action_strip.visible:
		_composition.apply_action_resources(views["action_resources"])
	_composition.apply_class_resources(views["class_resources"])
	_composition.apply_end_action(views["end_action"])
	var end_control: Control = _composition.get_node("BottomRow/EndTurnControl") as Control
	var end_active: bool = bool(views["end_action"].visible)
	end_control.visible = true
	end_control.get_node("EndTurnButton").visible = end_active
	end_control.get_node("EndLabel").visible = end_active


func _append_skill_inspection_rectangles(shelf: Control, rectangles: Array[Rect2]) -> void:
	for slot: Node in shelf.get_skill_slots():
		if slot is Control and slot.is_inspection_visible():
			rectangles.append(slot.get_inspection_panel().get_global_rect())


func _on_skill_activated(skill_id: String) -> void:
	if not _can_select_skill(skill_id):
		return
	skill_selected.emit(skill_id)


func _on_end_turn_requested() -> void:
	if _is_player_action_state():
		end_turn_requested.emit()


func _on_end_move_requested() -> void:
	if _is_player_action_state():
		end_move_requested.emit()


func _is_player_action_state() -> bool:
	return bool(_last_state.get("visible", false)) \
		and str(_last_state.get("mode", "")) == "player" \
		and bool(_last_state.get("show_actions", false))


func _can_select_skill(skill_id: String) -> bool:
	if not _is_player_action_state():
		return false
	var entries: Variant = _last_state.get("skills", [])
	if not entries is Array:
		return false
	for source: Variant in entries:
		if source is Dictionary and str(source.get("skill_id", "")) == skill_id:
			return bool(source.get("active_capable", not bool(source.get("is_passive", false)))) \
				and bool(source.get("available", false))
	return false
