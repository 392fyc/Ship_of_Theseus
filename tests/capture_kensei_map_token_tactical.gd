extends SceneTree
## 真实 TacticalScene 中剑圣地图棋子的视觉证据捕获。
##
## 运行：Godot_console.exe --path <project-root> \
##   --script res://tests/capture_kensei_map_token_tactical.gd -- --capture-all

const CAPTURE_ROOT := "user://visual_style_playground/kensei_map_token_tactical/"
const CAPTURE_NAMES := [
	"kensei_single_four_directions.png",
	"kensei_dual_four_directions.png",
	"kensei_occlusion_hud_popup.png",
]
const KENSEI_CLASS_ID := "kensei"
const OFFHAND_WEAPON_ID := "wpn_swordsman_starter"
const MAP_ID := "forest_01"

var _capture_directory := ""


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--capture-all"):
		print("KENSEI_TACTICAL_CAPTURE_ARGUMENT_ERROR=missing --capture-all")
		quit(1)
		return
	if DisplayServer.get_name().to_lower() == "headless":
		print("KENSEI_TACTICAL_CAPTURE_UNSUPPORTED_HEADLESS=use windowed Godot console")
		quit(1)
		return
	call_deferred("_capture_all")


func _capture_all() -> void:
	if not _prepare_capture_directory():
		quit(1)
		return

	var success := await _capture_single_four_directions()
	if success:
		success = await _capture_dual_four_directions()
	if success:
		success = await _capture_occlusion_hud_popup()

	if not success:
		quit(1)
		return
	print("KENSEI_TACTICAL_CAPTURE_DIR=%s" % _capture_directory)
	quit(0)


func _prepare_capture_directory() -> bool:
	var batch_name := "batch_%d" % int(Time.get_unix_time_from_system())
	_capture_directory = ProjectSettings.globalize_path(CAPTURE_ROOT.path_join(batch_name))
	var make_result := DirAccess.make_dir_recursive_absolute(_capture_directory)
	if make_result != OK:
		push_error("Cannot create capture directory: %s (error %d)" % [_capture_directory, make_result])
		return false
	return true


func _capture_single_four_directions() -> bool:
	var scene := _make_tactical_scene([
		Vector2i(2, 2), Vector2i(4, 2), Vector2i(2, 5), Vector2i(4, 5),
	])
	if scene == null:
		return false
	var units := await _get_kensei_units(scene, 4)
	if units.is_empty():
		scene.queue_free()
		return false
	var directions: Array[StringName] = [&"NW", &"NE", &"SW", &"SE"]
	for index: int in range(units.size()):
		if not units[index].set_facing(directions[index]):
			push_error("Unable to set facing for single-weapon kensei")
			scene.queue_free()
			return false
	var success := await _capture_scene(CAPTURE_NAMES[0])
	scene.queue_free()
	return success


func _capture_dual_four_directions() -> bool:
	var scene := _make_tactical_scene([
		Vector2i(2, 2), Vector2i(4, 2), Vector2i(2, 5), Vector2i(4, 5),
	])
	if scene == null:
		return false
	var units := await _get_kensei_units(scene, 4)
	if units.is_empty():
		scene.queue_free()
		return false
	var directions: Array[StringName] = [&"NW", &"NE", &"SW", &"SE"]
	for index: int in range(units.size()):
		units[index].equip_offhand(OFFHAND_WEAPON_ID)
		if not units[index].set_facing(directions[index]) or not units[index].is_dual_wielding():
			push_error("Unable to configure dual-weapon kensei")
			scene.queue_free()
			return false
	var success := await _capture_scene(CAPTURE_NAMES[1])
	scene.queue_free()
	return success


func _capture_occlusion_hud_popup() -> bool:
	var scene := _make_tactical_scene([Vector2i(3, 3), Vector2i(3, 4)])
	if scene == null:
		return false
	var units := await _get_kensei_units(scene, 2)
	if units.is_empty():
		scene.queue_free()
		return false
	var rear_unit: Unit = units[0]
	var front_unit: Unit = units[1]
	if not rear_unit.set_facing(&"NW"):
		push_error("Unable to set rear kensei facing for occlusion capture")
		scene.queue_free()
		return false
	front_unit.equip_offhand(OFFHAND_WEAPON_ID)
	if not front_unit.is_dual_wielding():
		push_error("Occlusion capture front kensei did not equip an offhand weapon")
		scene.queue_free()
		return false
	if not front_unit.set_facing(&"SE"):
		push_error("Unable to set front kensei facing for occlusion capture")
		scene.queue_free()
		return false
	front_unit.consume_movement_resource()
	front_unit.consume_standard_resource()

	var tactical_manager: Node = scene.get("tactical_manager") as Node
	var popup_layer: Node = tactical_manager.get_node_or_null("PopupLayer")
	if popup_layer == null:
		push_error("TacticalScene PopupLayer is unavailable")
		scene.queue_free()
		return false
	DamagePopup.spawn_at_anchor(
		popup_layer, front_unit.get_combat_text_anchor_world(-30.0), 84, "physical", true)
	var success := await _capture_scene(CAPTURE_NAMES[2])
	scene.queue_free()
	return success

func _make_tactical_scene(positions: Array[Vector2i]) -> Node:
	# 在 SceneTree 初始化后才 load：--script 入口的脚本预加载会早于 autoload 注册，
	# 而 TacticalScene 的正式逻辑依赖 DataLoader autoload。
	var tactical_scene := load("res://scenes/tactical/TacticalScene.tscn") as PackedScene
	if tactical_scene == null:
		push_error("Unable to load TacticalScene")
		return null
	var scene := tactical_scene.instantiate()
	if scene == null:
		push_error("Unable to instantiate TacticalScene")
		return null
	scene.run_injected = true
	scene.debug_harness_enabled = false
	scene.injected_map_id = MAP_ID
	scene.injected_player_units = []
	for position: Vector2i in positions:
		scene.injected_player_units.append({"class_id": KENSEI_CLASS_ID, "pos": position})
	scene.injected_enemy_units = []
	root.add_child(scene)
	return scene


func _get_kensei_units(scene: Node, expected_count: int) -> Array[Unit]:
	await process_frame
	await process_frame
	var tactical_manager: Node = scene.get("tactical_manager") as Node
	if tactical_manager == null:
		push_error("TacticalScene tactical_manager is unavailable")
		return []
	var units: Array[Unit] = []
	var all_units: Array = tactical_manager.get("units") as Array
	for value: Variant in all_units:
		var unit := value as Unit
		if unit != null and unit.unit_id == KENSEI_CLASS_ID and unit.has_runtime_map_token():
			units.append(unit)
	if units.size() != expected_count:
		push_error("Expected %d runtime kensei map tokens, got %d" % [expected_count, units.size()])
		return []
	return units


func _capture_scene(file_name: String) -> bool:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var viewport: Viewport = root
	var image := viewport.get_texture().get_image()
	if image == null:
		push_error("Root viewport did not provide a capture image")
		return false
	if image.get_width() != 1280 or image.get_height() != 720:
		push_error("Capture size must be 1280x720, got %dx%d" % [image.get_width(), image.get_height()])
		return false
	var output_path := _capture_directory.path_join(file_name)
	var save_result := image.save_png(output_path)
	if save_result != OK:
		push_error("Cannot save capture: %s (error %d)" % [output_path, save_result])
		return false
	print("KENSEI_TACTICAL_CAPTURED=%s" % output_path)
	return true
