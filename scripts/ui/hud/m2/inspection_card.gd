extends Panel

## 固定镜头的左侧说明区；只有最新的鼠标或键盘检视入口可以显示卡片。
const CARD_GROUP: StringName = &"hud_m2_inspection_cards"
const SIDE_LEFT: float = 16.0
const SIDE_BOTTOM: float = 518.0
var _claimed: bool = false


func _ready() -> void:
	add_to_group(CARD_GROUP)
	self_modulate.a = 0.82
	theme_changed.connect(_refresh_frame)
	_refresh_frame()


func claim() -> void:
	for card: Node in get_tree().get_nodes_in_group(CARD_GROUP):
		if card != self and card.get_viewport() == get_viewport():
			card.dismiss()
	_claimed = true


func dismiss() -> void:
	_claimed = false
	hide()


func refresh_visibility(wanted: bool) -> void:
	visible = _claimed and wanted
	if not wanted:
		_claimed = false


func place_in_sidebar(origin: Vector2, card_size: Vector2) -> void:
	size = card_size
	position = Vector2(SIDE_LEFT, SIDE_BOTTOM - size.y) - origin


func _refresh_frame() -> void:
	# 只绘制原金色边框，避免框材质的实心底叠加后抵消半透明。
	var frame: Panel = get_child(0) as Panel
	var style: StyleBox = get_theme_stylebox(&"panel", &"HudM2Panel").duplicate()
	if style is StyleBoxTexture:
		style.draw_center = false
	frame.add_theme_stylebox_override(&"panel", style)
