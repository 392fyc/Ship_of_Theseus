extends SceneTree
## 素材入库检查只生成原生预览和身份记录，不自动认可材质质量。

const BoardView := preload("res://scripts/ui/playground/courtyard_board_view.gd")
const BASE := "res://assets/prototype/battlefield_courtyard/"

class RepeatedMaterial:
	extends Node2D
	var material_texture: Texture2D
	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(300, 0), Vector2(300, 300), Vector2(0, 300)]),
			Color.WHITE, PackedVector2Array([Vector2.ZERO, Vector2(3, 0), Vector2(3, 3), Vector2(0, 3)]), material_texture)

var _output: String = ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			_output = arg.trim_prefix("--output=")
	if DisplayServer.get_name() == "headless" or not _output.is_absolute_path():
		push_error("材质检查需要图形渲染及绝对输出目录。")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(_output) != OK:
		quit(1)
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1120, 520)
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "visual_profile.json"))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "source-manifest.json"))
	var sources: Dictionary = {}
	for item: Dictionary in manifest["assets"]:
		sources[str(item["path"])] = item
	var records: Array[Dictionary] = []
	for spec: Dictionary in [{"key": "water", "name": "水面", "terrain": 5}, {"key": "ground", "name": "石材", "terrain": 0}, {"key": "rock", "name": "自然岩面", "terrain": 2}]:
		var source: String = str(profile[spec["key"]])
		var digest: String = FileAccess.get_sha256(source)
		if digest != sources[source.get_file()]["sha256"]:
			push_error("素材与来源记录不一致：" + source.get_file())
			quit(1)
			return
		var page := Node2D.new()
		root.add_child(page)
		var background := ColorRect.new()
		background.color = Color("171e22")
		background.size = Vector2(1120, 520)
		page.add_child(background)
		_label(page, "素材检查 · " + str(spec["name"]), Vector2(24, 14), 24)
		_label(page, "单张输入", Vector2(24, 60), 18)
		_label(page, "3 × 3 重复：检查接缝与周期图案", Vector2(356, 60), 18)
		_label(page, "实际引擎尺寸：1.36 倍", Vector2(708, 60), 18)
		var texture: Texture2D = load(source)
		var single := TextureRect.new()
		single.position = Vector2(24, 96)
		single.size = Vector2(300, 300)
		single.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		single.texture = texture
		page.add_child(single)
		var repeated := RepeatedMaterial.new()
		repeated.position = Vector2(356, 96)
		repeated.material_texture = texture
		repeated.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		repeated.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		page.add_child(repeated)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(388, 300)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		page.add_child(viewport)
		var display := TextureRect.new()
		display.position = Vector2(708, 96)
		display.size = Vector2(viewport.size)
		display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		display.texture = viewport.get_texture()
		page.add_child(display)
		var data: Dictionary = {"width": 4, "height": 4, "terrain": [], "transition_preview": true, "paving": []}
		for y: int in 4:
			var row: Array = []
			for x: int in 4:
				row.append(int(spec["terrain"]))
				if spec["key"] == "ground":
					data["paving"].append([x, y])
			data["terrain"].append(row)
		var grid := Grid.new()
		grid.initialize(data)
		var view := BoardView.new()
		view.configure(grid, profile, data)
		view.grid_visible = false
		view.scale = Vector2.ONE * 1.36
		view.position = Vector2(194, 150) - (grid.grid_to_world(Vector2i.ZERO) + grid.grid_to_world(Vector2i(3, 3))) * 0.68
		viewport.add_child(view)
		view.set_process(false)
		view._time = 2.0
		_label(page, "输入图只提供材质；水深、岸沿和格子含义由引擎数据决定。", Vector2(24, 416), 19)
		_label(page, "本页是检查证据；重复纹理、光照或材质语义仍需逐项审查。", Vector2(24, 454), 17)
		for frame: int in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		var name: String = "material-" + str(spec["key"]) + ".png"
		if root.get_texture().get_image().save_png(_output.path_join(name)) != OK:
			quit(1)
			return
		records.append({"source": source, "source_sha256": digest, "file": name,
			"image_sha256": FileAccess.get_sha256(_output.path_join(name)), "identity_matches_manifest": true,
			"repeats": [3, 3], "engine_scale": 1.36, "visual_acceptance": "pending_review"})
		page.queue_free()
		await process_frame
	var output := FileAccess.open(_output.path_join("material-intake.json"), FileAccess.WRITE)
	if output == null:
		quit(1)
		return
	output.store_string(JSON.stringify({"engine": Engine.get_version_info()["string"], "post_processing": false,
		"script_sha256": FileAccess.get_sha256("res://tests/capture_courtyard_material_intake.gd"),
		"source_manifest_sha256": FileAccess.get_sha256(BASE + "source-manifest.json"),
		"board_sha256": FileAccess.get_sha256("res://scripts/ui/playground/courtyard_board_view.gd"),
		"profile_sha256": FileAccess.get_sha256(BASE + "visual_profile.json"), "records": records}, "  "))
	output.close()
	print("COURTYARD_MATERIAL_INTAKE_RESULT ", JSON.stringify({"captures": records.size(), "identity_checks": "pass", "visual_acceptance": "pending_review"}))
	quit()


func _label(parent: Node, content: String, at: Vector2, size: int) -> void:
	var label := Label.new()
	label.theme = load("res://assets/ui/themes/hud_m2.tres")
	label.text = content
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("e4dfc9"))
	parent.add_child(label)
