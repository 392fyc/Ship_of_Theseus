class_name HudM2MarksPanel
extends Control

## 八张定版透明状态图由三个独立布尔值选择；未引入充能数值。
var _state: StringName = &"000"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_changed.connect(queue_redraw)


func apply_view(view: HudM2ClassResourceViewData) -> void:
	visible = view != null and view.visible and view.body is HudM2SwordResourceViewData and view.body.marks_visible
	if not visible:
		return
	var bits := PackedStringArray()
	for index: int in 3:
		var entry: Dictionary = view.body.marks[index] if index < view.body.marks.size() else {}
		bits.append("1" if bool(entry.get("held", false)) else "0")
	_state = StringName("".join(bits))
	queue_redraw()


func _draw() -> void:
	var icon: StringName = StringName("marks_" + str(_state))
	var texture: Texture2D = get_theme_icon(icon, &"HudM2FrozenResource")
	draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)


func get_input_blocking_rects() -> Array[Rect2]:
	if is_visible_in_tree():
		return [get_global_rect()]
	return []
