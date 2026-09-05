extends SceneTree
## 在真实 TacticalScene 中捕获 HUD-PROD-1C 行动资源条原始视觉证据。

const CAPTURE_ROOT := "res://dev_doc/ui-art-research/hud-prod-1c-action-resource-cutover/evidence/"
const CAPTURE_NAMES := [
	"action_resources_default_1280x720.png",
	"action_resources_multi_point_1280x720.png",
]
const CAPTURE_WIDTH := 1280
const CAPTURE_HEIGHT := 720


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--capture-action-resources"):
		push_error("ACTION_RESOURCE_CAPTURE_ARGUMENT_ERROR=missing --capture-action-resources")
		quit(1)
		return
	if DisplayServer.get_name().to_lower() == "headless":
		push_error("ACTION_RESOURCE_CAPTURE_UNSUPPORTED_HEADLESS=use windowed Godot console")
		quit(1)
		return
	call_deferred("_capture_all")


func _capture_all() -> void:
	var absolute_directory: String = ProjectSettings.globalize_path(CAPTURE_ROOT)
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		push_error("Cannot create capture directory: %s" % absolute_directory)
		quit(1)
		return
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var manager: Object = scene.tactical_manager
	var dashboard: BottomDashboard = scene._bottom_dashboard
	var unit: Unit = manager._get_dashboard_unit() if manager != null else null
	if manager == null or dashboard == null or unit == null or not _has_property(dashboard, "_action_resource_strip"):
		push_error("TacticalScene did not provide the production action resource strip")
		scene.queue_free()
		quit(1)
		return
	unit.reset_action_resources()
	scene._refresh_dashboard()
	var success: bool = await _capture_state(manager, dashboard, unit, CAPTURE_NAMES[0], 1, 1, 1, 1, true)
	if success:
		unit.configure_action_resource_capacities(3, 3)
		unit.consume_movement_resource()
		unit.consume_standard_resource()
		unit.consume_standard_resource()
		unit.consume_swift_resource()
		scene._refresh_dashboard()
		success = await _capture_state(manager, dashboard, unit, CAPTURE_NAMES[1], 3, 1, 3, 2, false)
	scene.queue_free()
	if not success:
		quit(1)
		return
	print("ACTION_RESOURCE_CAPTURE_DIR=%s" % absolute_directory)
	quit(0)


func _capture_state(manager: Object, dashboard: BottomDashboard, unit: Unit, file_name: String,
		standard_capacity: int, standard_remaining: int, swift_capacity: int, swift_remaining: int,
		movement_available: bool) -> bool:
	await process_frame
	await process_frame
	var strip: Control = dashboard.get("_action_resource_strip") as Control
	var skill_bar: Control = dashboard.get("_skill_bar") as Control
	if not _validate_capture_state(manager, strip, skill_bar, unit, standard_capacity, standard_remaining,
		swift_capacity, swift_remaining, movement_available):
		return false
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null or image.get_width() != CAPTURE_WIDTH or image.get_height() != CAPTURE_HEIGHT:
		push_error("Capture size must be 1280x720")
		return false
	var output_path: String = ProjectSettings.globalize_path(CAPTURE_ROOT.path_join(file_name))
	if image.save_png(output_path) != OK:
		push_error("Cannot save capture: %s" % output_path)
		return false
	var saved: Image = Image.load_from_file(output_path)
	if saved == null or saved.get_width() != CAPTURE_WIDTH or saved.get_height() != CAPTURE_HEIGHT:
		push_error("Saved capture validation failed: %s" % output_path)
		return false
	print("ACTION_RESOURCE_CAPTURED=%s" % output_path)
	return true


func _validate_capture_state(manager: Object, strip: Control, skill_bar: Control, unit: Unit,
		standard_capacity: int, standard_remaining: int, swift_capacity: int, swift_remaining: int,
		movement_available: bool) -> bool:
	if strip == null or skill_bar == null or not strip.visible:
		push_error("Production strip or skill bar is unavailable")
		return false
	if strip.size != Vector2(274.0, 40.0) or not is_equal_approx(skill_bar.position.y - (strip.position.y + strip.size.y), 6.0):
		push_error("Production strip geometry must be 274x40 with a 6px gap")
		return false
	var view: RefCounted = strip.get("_view") as RefCounted
	if view == null or view.get("standard_capacity") != standard_capacity \
			or view.get("standard_remaining") != standard_remaining \
			or view.get("swift_capacity") != swift_capacity \
			or view.get("swift_remaining") != swift_remaining \
			or view.get("movement_available") != movement_available:
		push_error("Production ViewData did not match capture state")
		return false
	if _spent_states(strip.call("get_standard_pips") as Array) != _expected_spent(standard_capacity, standard_remaining) \
			or _spent_states(strip.call("get_swift_pips") as Array) != _expected_spent(swift_capacity, swift_remaining):
		push_error("Pip states did not match capture state")
		return false
	if _map_has_action_badges(manager):
		push_error("Map StatusIcons must not contain action badges")
		return false
	return true


func _expected_spent(capacity: int, remaining: int) -> Array[bool]:
	var result: Array[bool] = []
	for index: int in capacity:
		result.append(index >= remaining)
	return result


func _spent_states(nodes: Array) -> Array[bool]:
	var result: Array[bool] = []
	for node: Variant in nodes:
		result.append(bool((node as Object).get("spent")))
	return result


func _map_has_action_badges(manager: Object) -> bool:
	for candidate: Variant in manager.units as Array:
		var unit: Unit = candidate as Unit
		var icons: Node2D = unit.get_node_or_null("StatusIcons") as Node2D if unit != null else null
		if icons == null:
			continue
		for child: Node in icons.get_children():
			var label: Label = child as Label
			if label != null and label.text in ["M", "A", "S"]:
				return true
	return false


func _has_property(value: Object, property_name: String) -> bool:
	for property: Dictionary in value.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false
