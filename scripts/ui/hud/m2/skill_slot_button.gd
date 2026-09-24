class_name HudM2SkillSlotButton
extends "res://scripts/ui/hud/skill_slot_button.gd"

const M2SkillView := preload("res://scripts/ui/hud/m2/skill_slot_view_data.gd")
const M2Glyph := preload("res://scripts/ui/hud/m2/action_resource_glyph.gd")
const PopupPlacement := preload("res://scripts/ui/hud/m2/popup_placement.gd")

@export var inspection_clearance: float = 8.0
var _inspection_obstacles: Array[Rect2] = []
var _hovered: bool = false
var _card_hovered: bool = false
var _pointer_local := Vector2(-1, -1)

@onready var _frame: Control = %ActiveFrame
@onready var _passive_frame: Control = %PassiveFrame
@onready var _unavailable_shade: Control = %UnavailableShade
@onready var _action_badge: Control = %ActionBadge
@onready var _action_glyph: M2Glyph = %ActionGlyph
@onready var _cost_badge: Control = %ResourceCostBadge
@onready var _cost_label: Label = %ResourceCostText
@onready var _focus_overlay: Control = %FocusOverlay
@onready var _inspection_panel: Panel = %InspectionPanel
@onready var _inspection_label: Label = %InspectionLabel


func _ready() -> void:
	super._ready()
	theme_changed.connect(_refresh_skin, CONNECT_DEFERRED)
	_refresh_skin()
	focus_entered.connect(_update_focus)
	focus_exited.connect(_update_focus)
	mouse_entered.connect(func() -> void: _hovered = true; _update_focus())
	mouse_exited.connect(func() -> void: _hovered = false; _update_focus.call_deferred())
	_inspection_panel.mouse_entered.connect(func() -> void: _card_hovered = true; _update_focus())
	_inspection_panel.mouse_exited.connect(func() -> void: _card_hovered = false; _update_focus.call_deferred())
	resized.connect(_update_focus)
	_update_focus()
	if _view == null:
		disabled = true


func _apply_view_to_nodes() -> void:
	super._apply_view_to_nodes()
	var view: M2SkillView = _view as M2SkillView
	var pure_passive: bool = _view.passive and not _view.active_capable
	var actionable: bool = _view.active_capable
	_frame.visible = not pure_passive
	_passive_frame.visible = pure_passive
	# Button 保持焦点与悬停入口；父类 _on_pressed 始终再次核对 can_activate。
	disabled = not _view.can_activate() and not pure_passive
	mouse_default_cursor_shape = Control.CURSOR_ARROW if pure_passive else Control.CURSOR_POINTING_HAND
	_hotkey_badge.visible = actionable and not _view.hotkey_text.is_empty()
	_charge_text.visible = false
	_selected_overlay.visible = actionable and _view.selected
	_cooldown_shade.visible = actionable and _view.cooldown_turns > 0
	_cooldown_turns_label.visible = _cooldown_shade.visible
	_unavailable_shade.visible = not pure_passive and not _view.enabled and not _cooldown_shade.visible
	_action_badge.visible = actionable and view != null and view.action_type in [&"move", &"standard", &"swift"]
	if _action_badge.visible:
		var kind: M2Glyph.Kind = M2Glyph.Kind.FOOTPRINT
		if view.action_type == &"standard":
			kind = M2Glyph.Kind.STANDARD
		elif view.action_type == &"swift":
			kind = M2Glyph.Kind.SWIFT
		var side: float = 13.0 if kind == M2Glyph.Kind.FOOTPRINT else 11.0
		var height: float = side * sqrt(3.0) / 2.0 if kind == M2Glyph.Kind.SWIFT else side
		_action_glyph.position = Vector2(4.0, 8.5 - height * 0.5)
		_action_glyph.size = Vector2(side, height)
		_action_glyph.configure(kind, not _view.can_activate())
	var cost: String = view.resource_cost_text() if view != null and actionable else ""
	_cost_label.text = cost
	_cost_badge.visible = not cost.is_empty()
	_refresh_skin()
	if not cost.is_empty():
		tooltip_text += ("\n" if not tooltip_text.is_empty() else "") + "%s：%s" % [view.resource_name_text(), cost]
	_update_focus()


func activate_shortcut() -> void:
	_on_pressed()


func _refresh_skin() -> void:
	if not is_node_ready() or _view == null:
		return
	_cost_label.add_theme_color_override(&"font_color", get_theme_color(&"text" if _view.can_activate() else &"spent_edge", &"HudM2"))
	_update_focus.call_deferred()


func get_inspection_panel() -> Control:
	return _inspection_panel


func is_inspection_visible() -> bool:
	return _inspection_panel.is_visible_in_tree()


func get_inspection_text() -> String:
	return _inspection_label.text


func set_inspection_obstacles(rectangles: Array[Rect2]) -> void:
	_inspection_obstacles = rectangles.duplicate()
	if is_node_ready():
		_update_focus()


func _get_tooltip(_at_position: Vector2) -> String:
	# 保留 tooltip_text 的兼容文本访问；原生弹窗由受控面板取代。
	return ""


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pointer_local = get_global_transform_with_canvas().affine_inverse() * event.position
		_update_focus.call_deferred()


func _pointer_in_inspection_bridge() -> bool:
	var card: Rect2 = _inspection_panel.get_rect()
	var left: float = maxf(0.0, card.position.x)
	var right: float = minf(size.x, card.end.x)
	return _inspection_panel.visible and Rect2(left, card.end.y, right - left, -card.end.y).has_point(_pointer_local)


func _update_focus() -> void:
	if not is_node_ready():
		return
	_focus_overlay.visible = has_focus()
	_inspection_label.text = tooltip_text if _view != null else ""
	# 真实心眼说明需六行。保留既定宽度、字号、内边距和底边，仅向上增加卡片高度。
	var inspection_height: float = maxf(104.0, _inspection_label.get_minimum_size().y + 24.0)
	var origin := Vector2.ZERO
	var current: Control = self
	while current != null and current.name != &"BottomHudComposition":
		origin += current.position
		current = current.get_parent_control()
	var anchor := Rect2(origin + Vector2(size.x * 0.5 - 130.0, 8.0 - inspection_clearance), size)
	var placed: Rect2 = PopupPlacement.place_above(anchor, Vector2(260, inspection_height), _inspection_obstacles, 8.0, Rect2(0, 0, 1280, 720))
	_inspection_panel.size = placed.size
	_inspection_panel.position = placed.position - origin
	_inspection_panel.visible = is_visible_in_tree() and (has_focus() or _hovered or _card_hovered or _pointer_in_inspection_bridge()) and not _inspection_label.text.is_empty()
