extends SceneTree

## 从正式 TacticalScene 捕获人物栏常态与头像悬停态；--original 捕获原画对照。
const OUTPUT := "res://dev_doc/ui-art-research/hud-character-panel-portrait/candidate"
const ORIGINAL_ART := "res://assets/prototype/visual_style/samples/portrait_preview_final.png"

var _variant_suffix := "-generated"
var _override_texture: AtlasTexture


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Native HUD capture requires a visible rendering display.")
		quit(1)
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var dashboard: Control = scene.get("_bottom_dashboard") as Control
	var character: Control = dashboard.get_composition().get_node("BottomRow/CharacterHudPanel") as Control
	if OS.get_cmdline_user_args().has("--original"):
		_variant_suffix = ""
		_override_texture = AtlasTexture.new()
		_override_texture.atlas = load(ORIGINAL_ART) as Texture2D
		_override_texture.region = Rect2(240, 225, 90, 103)
		_override_texture.filter_clip = true
	var failed: bool = false
	for target_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = target_size
		await process_frame
		await process_frame
		_move_pointer(Vector2(target_size) * Vector2(0.5, 0.4))
		await process_frame
		failed = (not await _capture("idle-%d%s" % [target_size.x, _variant_suffix], dashboard)) or failed
		_move_pointer(character.get_inspection_control().get_global_rect().get_center())
		await process_frame
		await process_frame
		if not character.get_inspection_panel().visible:
			push_error("Portrait hover did not reveal attributes at %s" % target_size)
			failed = true
		else:
			failed = (not await _capture("hover-%d%s" % [target_size.x, _variant_suffix], dashboard)) or failed
			if target_size.x == 1280:
				failed = (not _capture_portrait_detail()) or failed
	scene.queue_free()
	await process_frame
	quit(1 if failed else 0)


func _move_pointer(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	root.push_input(event, true)


func _capture(name: String, dashboard: Control) -> bool:
	for unused: int in 3:
		await process_frame
		if _override_texture != null:
			var character: Control = dashboard.get_composition().get_node("BottomRow/CharacterHudPanel") as Control
			(character.get_node("PortraitContent") as TextureRect).texture = _override_texture
		await RenderingServer.frame_post_draw
	if dashboard == null or not dashboard.visible:
		push_error("HUD is not visible: " + name)
		return false
	var image: Image = root.get_texture().get_image()
	if image.get_size() != root.size:
		push_error("Viewport size mismatch: " + name)
		return false
	var directory: String = ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(directory)
	var path: String = directory.path_join(name + ".png")
	if image.save_png(path) != OK:
		push_error("PNG save failed: " + name)
		return false
	print("CHARACTER_CAPTURE ", name, " ", image.get_width(), "x", image.get_height(), " ", FileAccess.get_sha256(path))
	return true


func _capture_portrait_detail() -> bool:
	var directory: String = ProjectSettings.globalize_path(OUTPUT)
	var source_path: String = directory.path_join("hover-1280%s.png" % _variant_suffix)
	var source: Image = Image.load_from_file(source_path)
	if source == null or source.get_size() != Vector2i(1280, 720):
		push_error("Cannot read the full TacticalScene screenshot for portrait detail")
		return false
	var detail: Image = source.get_region(Rect2i(32, 596, 100, 100))
	detail.resize(400, 400, Image.INTERPOLATE_NEAREST)
	var target_path: String = directory.path_join("portrait-detail-4x%s.png" % _variant_suffix)
	if detail.save_png(target_path) != OK:
		push_error("Portrait detail PNG save failed")
		return false
	print("CHARACTER_CAPTURE portrait-detail-4x%s 400x400 " % _variant_suffix, FileAccess.get_sha256(target_path))
	return true
