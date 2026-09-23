class_name HudM2BottomComposition
extends "res://scripts/ui/hud/bottom_hud_composition.gd"

const DefaultSkin: Theme = preload("res://assets/ui/themes/hud_m2.tres")
const ResourceLayout = preload("res://assets/ui/layouts/hud_m2_class_resource.tres")


func _enter_tree() -> void:
	# 独立子场景保留默认 Theme；进入组合后统一继承组合的皮肤。
	_inherit_skin(self)


func _ready() -> void:
	super._ready()
	for region: Control in $BottomRow.get_children():
		region.theme_type_variation = &"HudM2Transparent"
		var frame: Control = region.get_node("MetalFrame" if region.name == &"CharacterHudPanel" else "Frame")
		frame.hide()
	_action_resource_strip.theme_type_variation = &"HudM2Transparent"
	_action_resource_strip.get_node("Frame").hide()
	for zone_name: String in ["MovementZone", "StandardZone", "SwiftZone"]:
		_action_resource_strip.get_node(zone_name).theme_type_variation = &"HudM2Transparent"
	_action_resource_strip.visibility_changed.connect($SharedFrame.queue_redraw)
	_action_resource_strip.visibility_changed.connect(_refresh_resource_layout)
	$ClassResourceHost.set_layout(ResourceLayout)
	$MarksPanel.position = ResourceLayout.marks_bounds.position
	$MarksPanel.size = ResourceLayout.marks_bounds.size
	_refresh_resource_layout()


func apply_class_resources(view: HudM2ClassResourceViewData) -> void:
	$ClassResourceHost.apply_view(view)
	$MarksPanel.apply_view(view)
	_refresh_resource_layout()


func get_class_resource_host() -> Control:
	return $ClassResourceHost


func get_marks_panel() -> Control:
	return $MarksPanel


func _refresh_resource_layout() -> void:
	if not is_node_ready():
		return
	$SharedFrame.queue_redraw()
	var obstacles: Array[Rect2] = []
	if $ClassResourceHost.visible:
		obstacles.append(ResourceLayout.bounds)
	if $MarksPanel.visible:
		obstacles.append(ResourceLayout.marks_bounds)
	if _action_resource_strip.visible:
		obstacles.append(Rect2(503, 550, 274, 46))
	_character_panel.set_inspection_obstacles(obstacles)
	_skill_shelf.set_inspection_obstacles(obstacles)


func set_skin_theme(value: Theme) -> void:
	theme = value if value != null else DefaultSkin


func get_skin_theme() -> Theme:
	return theme if theme != null else DefaultSkin


func get_shared_frame() -> Control:
	return $SharedFrame


func _inherit_skin(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Control:
			child.theme = null
		_inherit_skin(child)
