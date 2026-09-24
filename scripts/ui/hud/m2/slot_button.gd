class_name HudM2SlotButton
extends "res://scripts/ui/hud/slot_button.gd"

const M2SlotView := preload("res://scripts/ui/hud/m2/slot_view_data.gd")

@onready var _empty_glyph: Control = %EmptyGlyph
@onready var _lock_glyph: Control = %LockGlyph
@onready var _unavailable_shade: Control = %UnavailableShade
@onready var _hover_overlay: Control = %HoverOverlay
@onready var _pressed_shade: Control = %PressedShade


func _ready() -> void:
	_empty_glyph.draw.connect(_draw_empty_glyph)
	_lock_glyph.draw.connect(_draw_lock_glyph)
	super._ready()
	theme_changed.connect(_refresh_skin)
	resized.connect(_refresh_skin)
	mouse_entered.connect(func() -> void: _hover_overlay.visible = not disabled)
	mouse_exited.connect(func() -> void: _hover_overlay.hide(); _pressed_shade.hide())
	button_down.connect(func() -> void: _pressed_shade.visible = not disabled)
	button_up.connect(_pressed_shade.hide)
	if _view == null:
		disabled = true


func _apply_view_to_nodes() -> void:
	if _view == null:
		_view = SlotViewData.new()
	super._apply_view_to_nodes()
	var view: M2SlotView = _view as M2SlotView
	var locked: bool = view != null and view.locked
	disabled = not _can_request()
	_icon_rect.visible = _view.occupied
	_empty_glyph.visible = not _view.occupied and not locked and view != null and view.empty_kind in [&"weapon", &"armor"]
	_state_overlay.visible = locked
	_lock_glyph.visible = locked
	_unavailable_shade.visible = not _view.enabled and not locked
	_hover_overlay.visible = not disabled and is_hovered()
	_pressed_shade.hide()
	_refresh_skin()
	_empty_glyph.queue_redraw()
	_lock_glyph.queue_redraw()


func _can_request() -> bool:
	if _view == null or not _view.enabled or _view.slot_id.is_empty():
		return false
	return not (_view is M2SlotView and (_view as M2SlotView).locked)


func _on_pressed() -> void:
	if is_visible_in_tree() and not disabled and _can_request():
		slot_requested.emit(_view.slot_id, _view.content_id)


func _draw_empty_glyph() -> void:
	var view: M2SlotView = _view as M2SlotView
	if view == null:
		return
	var color: Color = get_theme_color(&"empty_glyph", &"HudM2")
	var paths: Array[PackedVector2Array] = []
	if view.empty_kind == &"weapon":
		paths = [PackedVector2Array([Vector2(20, 2), Vector2(22, 4), Vector2(10, 19), Vector2(7, 16), Vector2(20, 2)]),
			PackedVector2Array([Vector2(5, 14), Vector2(12, 21)]),
			PackedVector2Array([Vector2(8, 19), Vector2(3, 25)]),
			PackedVector2Array([Vector2(2, 24), Vector2(4, 26)])]
	elif view.empty_kind == &"armor":
		paths = [PackedVector2Array([Vector2(6, 2), Vector2(9, 6), Vector2(15, 6), Vector2(18, 2), Vector2(23, 8), Vector2(19, 13), Vector2(18, 26), Vector2(6, 26), Vector2(5, 13), Vector2(1, 8), Vector2(6, 2)])]
	for path: PackedVector2Array in paths:
		_empty_glyph.draw_polyline(path, color, 1.0, true)


func _draw_lock_glyph() -> void:
	var color: Color = get_theme_color(&"lock_glyph", &"HudM2")
	var curve := Curve2D.new()
	curve.add_point(Vector2(3, 4), Vector2.ZERO, Vector2(0, -4))
	curve.add_point(Vector2(9, 4), Vector2(0, -4))
	_lock_glyph.draw_polyline(curve.tessellate(3, 2.0), color, 0.8, true)
	_lock_glyph.draw_line(Vector2(3, 6), Vector2(3, 4), color, 0.8, true)
	_lock_glyph.draw_line(Vector2(9, 4), Vector2(9, 6), color, 0.8, true)
	_lock_glyph.draw_polyline(PackedVector2Array([Vector2(1, 6), Vector2(11, 6), Vector2(11, 13), Vector2(1, 13), Vector2(1, 6)]), color, 0.8, true)
	_lock_glyph.draw_line(Vector2(6, 9), Vector2(6, 11), color, 0.8, true)


func _refresh_skin() -> void:
	if is_node_ready():
		%Frame.theme_type_variation = &"HudM2SlotFrame" if _view != null and _view.occupied else (&"HudM2RelicFrame" if size.x <= 40.0 else &"HudM2EmptySlotFrame")
		_empty_glyph.queue_redraw()
		_lock_glyph.queue_redraw()
