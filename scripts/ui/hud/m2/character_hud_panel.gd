class_name HudM2CharacterPanel
extends Panel

const CharacterViewData := preload("res://scripts/ui/hud/m2/character_hud_view_data.gd")
const PopupPlacement := preload("res://scripts/ui/hud/m2/popup_placement.gd")

var _view: CharacterViewData
var _hovered: bool = false
var _card_hovered: bool = false
var _inspection_obstacles: Array[Rect2] = []
var _pointer_local := Vector2(-1, -1)

@onready var _portrait: TextureRect = %PortraitContent
@onready var _portrait_button: Button = %PortraitInspectButton
@onready var _inspection: Panel = %InspectionPanel
@onready var _inspection_label: Label = %InspectionLabel


func _ready() -> void:
	_portrait_button.mouse_entered.connect(_on_portrait_entered)
	_portrait_button.mouse_exited.connect(_on_portrait_exited)
	_portrait_button.focus_entered.connect(_update_inspection)
	_portrait_button.focus_exited.connect(_update_inspection)
	_portrait_button.gui_input.connect(_on_inspection_input)
	_inspection.mouse_entered.connect(_on_card_entered)
	_inspection.mouse_exited.connect(_on_card_exited)
	%PortraitFallback.draw.connect(_draw_portrait_fallback)
	%InfoBorders.draw.connect(_draw_information_borders)
	theme_changed.connect(_refresh_skin)
	%InfoBorders.queue_redraw()
	if _view == null:
		_view = CharacterViewData.new()
	_apply_view_to_nodes()


func apply_view(view: CharacterViewData) -> void:
	_view = view if view != null else CharacterViewData.new()
	if is_node_ready():
		_apply_view_to_nodes()


func get_inspection_control() -> Button:
	return _portrait_button


func get_inspection_panel() -> Control:
	return _inspection


func set_inspection_obstacles(rectangles: Array[Rect2]) -> void:
	_inspection_obstacles = rectangles.duplicate()
	if is_node_ready():
		_layout_inspection()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pointer_local = get_global_transform_with_canvas().affine_inverse() * event.position
		_update_inspection.call_deferred()


func _pointer_in_inspection_bridge() -> bool:
	if not _inspection.visible:
		return false
	var card: Rect2 = _inspection.get_rect()
	var portrait: Rect2 = _portrait_button.get_rect()
	var bridge_height: float = portrait.end.y - card.end.y
	if bridge_height <= 0.0 or _pointer_local.y < card.end.y or _pointer_local.y > portrait.end.y:
		return false
	# 由头像宽度逐渐展开到属性卡宽度，允许鼠标斜向移动到右列。
	var progress: float = (portrait.end.y - _pointer_local.y) / bridge_height
	var left: float = lerpf(portrait.position.x, card.position.x, progress)
	var right: float = lerpf(portrait.end.x, card.end.x, progress)
	return _pointer_local.x >= left and _pointer_local.x <= right


func get_content_top_y() -> float:
	return _inspection.get_global_rect().position.y if _inspection.is_visible_in_tree() else get_global_rect().position.y


func get_input_blocking_rects() -> Array[Rect2]:
	var rectangles: Array[Rect2] = []
	if is_visible_in_tree():
		rectangles.append(get_global_rect())
		if _inspection.is_visible_in_tree():
			rectangles.append(_inspection.get_global_rect())
	return rectangles


func _apply_view_to_nodes() -> void:
	%IdentityLabel.text = _view.identity_text()
	%IdentityLabel.tooltip_text = _view.identity_text()
	%LevelLabel.text = "Lv.%d" % _view.level if _view.has_level else "Lv.—"
	%ExperienceValue.text = _meter_text(_view.experience) + " XP"
	%ExperienceFill.size.x = 114.0 * _meter_ratio(_view.experience)
	%HpValue.text = _meter_text(_view.hp)
	%HpFill.size.x = 114.0 * _meter_ratio(_view.hp)
	%ShieldValue.text = _meter_text(_view.shield)
	%ShieldFill.size.x = 114.0 * _meter_ratio(_view.shield)
	_portrait.texture = _view.portrait_texture
	%PortraitFallback.visible = _view.portrait_texture == null
	%PortraitFallback.queue_redraw()
	_portrait_button.tooltip_text = ""
	_portrait_button.accessibility_name = _view.identity_text() + "，查看属性"
	_inspection_label.text = _view.identity_text() + "  ·  属性"
	for key: String in CharacterViewData.ATTRIBUTE_KEYS:
		(%AttributeRows.get_node(key + "/Value") as Label).text = _view.attribute_value_text(key)
	_layout_inspection.call_deferred()
	_update_inspection()


func _meter_text(meter: RefCounted) -> String:
	return "—/—" if meter == null else str(meter.get("display_text"))


func _meter_ratio(meter: RefCounted) -> float:
	return 0.0 if meter == null else float(meter.get("ratio"))


func _on_portrait_entered() -> void:
	_hovered = true
	_update_inspection()


func _on_inspection_input(event: InputEvent) -> void:
	# 鼠标点击只保留当前悬停；键盘焦点继续作为独立检视入口。
	if event is InputEventMouseButton and event.pressed:
		_portrait_button.release_focus.call_deferred()


func _on_portrait_exited() -> void:
	_hovered = false
	_update_inspection.call_deferred()


func _on_card_entered() -> void:
	_card_hovered = true
	_update_inspection()


func _on_card_exited() -> void:
	_card_hovered = false
	_update_inspection.call_deferred()


func _update_inspection() -> void:
	_inspection.visible = is_visible_in_tree() and (_hovered or _card_hovered or _portrait_button.has_focus() or _pointer_in_inspection_bridge())
	%PortraitFocus.visible = is_visible_in_tree() and _portrait_button.has_focus()


func _layout_inspection() -> void:
	# 批准的长身份占两行；更长的输入向上扩展，完整文本不盖住属性。
	var title_height: float = maxf(40.0, _inspection_label.get_minimum_size().y)
	var extra: float = title_height - 40.0
	_inspection_label.size = Vector2(272, title_height)
	%TitleDivider.position.y = 59.0 + extra
	%AttributeRows.position.y = 70.0 + extra
	_inspection.size = Vector2(304, 188 + extra)
	var origin: Vector2 = position
	var parent: Control = get_parent_control()
	if parent != null:
		origin += parent.position
	var placed: Rect2 = PopupPlacement.place_above(Rect2(origin, size), _inspection.size, _inspection_obstacles, 14.0, Rect2(0, 0, 1280, 720))
	_inspection.position = placed.position - origin
	%InspectionFrame.size = _inspection.size


func _draw_portrait_fallback() -> void:
	if not is_node_ready():
		return
	if _view == null or _view.portrait_texture == null:
		var outline: Color = get_theme_color(&"portrait_fallback", &"HudM2")
		%PortraitFallback.draw_arc(Vector2(30, 26), 7.0, 0.0, TAU, 32, outline, 1.0, true)
		var shoulders := PackedVector2Array([
			Vector2(17, 53), Vector2(18, 46), Vector2(21, 41),
			Vector2(26, 39), Vector2(34, 39), Vector2(39, 41),
			Vector2(42, 46), Vector2(43, 53)])
		%PortraitFallback.draw_polyline(shoulders, outline, 1.0, true)


func _draw_information_borders() -> void:
	# 边框内容边距为零；更换材质不改变信息区和文字锚点。
	var rectangles: Array[Rect2] = [
		Rect2(0, 0, 124, 20), Rect2(0, 24, 124, 22), Rect2(0, 50, 124, 32)]
	for rect: Rect2 in rectangles:
		%InfoBorders.draw_style_box(get_theme_stylebox(&"panel", &"HudM2InfoBorder"), rect)


func _refresh_skin() -> void:
	if not is_node_ready():
		return
	%PortraitFallback.queue_redraw()
	%InfoBorders.queue_redraw()
	_layout_inspection.call_deferred()
