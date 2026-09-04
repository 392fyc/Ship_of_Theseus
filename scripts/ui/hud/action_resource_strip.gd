class_name HudActionResourceStrip
extends PanelContainer

# 与技能槽相同：资源路径预加载既保留静态类型，又不依赖编辑器刷新全局类缓存。
const ActionResourceViewData := preload("res://scripts/ui/hud/action_resource_view_data.gd")
const ActionResourceGlyph := preload("res://scripts/ui/hud/action_resource_glyph.gd")

var _view: ActionResourceViewData = null

@onready var _footprint_glyph: ActionResourceGlyph = %FootprintGlyph
@onready var _movement_value: Label = %MovementValue
@onready var _standard_pips: HBoxContainer = %StandardPips
@onready var _swift_pips: HBoxContainer = %SwiftPips


func _ready() -> void:
	if _view == null:
		_view = ActionResourceViewData.new()
	_apply_view_to_nodes()


func apply_view(view: ActionResourceViewData) -> void:
	_view = view
	_view.normalize()
	if is_node_ready():
		_apply_view_to_nodes()


func get_standard_pips() -> Array[Node]:
	return _standard_pips.get_children()


func get_swift_pips() -> Array[Node]:
	return _swift_pips.get_children()


func _apply_view_to_nodes() -> void:
	_view.normalize()
	_footprint_glyph.configure(ActionResourceGlyph.Kind.FOOTPRINT,
		not _view.movement_available)
	_movement_value.text = str(_view.movement_remaining)
	_movement_value.modulate = _footprint_glyph.get_display_color()
	_rebuild_pips(_standard_pips, ActionResourceGlyph.Kind.STANDARD,
		_view.standard_capacity, _view.standard_remaining)
	_rebuild_pips(_swift_pips, ActionResourceGlyph.Kind.SWIFT,
		_view.swift_capacity, _view.swift_remaining)


func _rebuild_pips(container: HBoxContainer, glyph_kind: ActionResourceGlyph.Kind,
		capacity: int, remaining: int) -> void:
	for child: Node in container.get_children():
		child.free()
	for index: int in capacity:
		var glyph: ActionResourceGlyph = ActionResourceGlyph.new()
		glyph.name = "%sPip%d" % ["Standard" if glyph_kind == ActionResourceGlyph.Kind.STANDARD else "Swift", index + 1]
		glyph.custom_minimum_size = Vector2(18.0, 18.0)
		glyph.configure(glyph_kind, index >= remaining)
		container.add_child(glyph)
