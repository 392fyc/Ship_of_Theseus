extends SceneTree
## 同一次运行采集全部候选状态，并记录渲染源码与原始截图摘要。

const CaptureMetadata := preload("res://tests/claude_review/capture_metadata.gd")
const SOURCES: Array[String] = [
	"res://scripts/ui/playground/courtyard_board_view.gd",
	"res://scripts/ui/playground/battlefield_courtyard.gd",
	"res://scripts/tactical/tactical_scene.gd",
	"res://assets/prototype/battlefield_courtyard/courtyard_layouts.json",
	"res://assets/prototype/battlefield_courtyard/visual_profile.json",
	"res://tests/capture_courtyard_visual_review.gd",
	"res://tests/claude_review/capture_metadata.gd",
	"res://scenes/playground/battlefield_courtyard.tscn",
	"res://scenes/tactical/TacticalScene.tscn",
	"res://assets/ui/themes/hud_m2.tres",
	"res://assets/prototype/battlefield_courtyard/source-manifest.json",
	"res://project.godot",
	"res://assets/prototype/battlefield_courtyard/terrain_catalog.json",
	"res://scripts/ui/terrain/terrain_blend.gdshader",
]
const CAPTURE_TIME := 2.0
const CAPTURE_SEED := 270927
var _output: String = ""
var _captures: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			_output = arg.trim_prefix("--output=")
	if _output.is_empty() or DisplayServer.get_name() == "headless":
		push_error("视觉采集需要图形渲染及 --output=<absolute-directory>。")
		quit(1)
		return
	if not _output.is_absolute_path() or DirAccess.make_dir_recursive_absolute(_output) != OK:
		push_error("无法创建绝对路径输出目录。")
		quit(1)
		return
	seed(CAPTURE_SEED)
	var sources: Array[String] = SOURCES.duplicate()
	for setting: Dictionary in ProjectSettings.get_property_list():
		var setting_name: String = str(setting["name"])
		if setting_name.begins_with("autoload/"):
			var autoload_path: String = str(ProjectSettings.get_setting(setting_name)).trim_prefix("*")
			if autoload_path.begins_with("res://") and not sources.has(autoload_path):
				sources.append(autoload_path)
	# DataLoader 的运行时 JSON 和全局脚本类不一定出现在静态资源依赖中。
	_append_tree_files("res://data", "json", sources)
	_append_tree_files("res://scripts", "gd", sources)
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCES[4]))
	for value: Variant in profile.values():
		var asset: String = str(value.get("texture", "")) if value is Dictionary else str(value)
		if asset.begins_with("res://") and not sources.has(asset):
			sources.append(asset)
	# 场景和主题的递归资源依赖也参与身份检查；JSON 中的动态素材已在上方补齐。
	var cursor: int = 0
	while cursor < sources.size():
		var source: String = sources[cursor]
		if source.get_extension() in ["tscn", "tres", "gd"]:
			for dependency: String in ResourceLoader.get_dependencies(source):
				var path: String = dependency.get_slice("::", 2) if dependency.contains("::") else dependency
				if path.begins_with("res://") and not sources.has(path):
					sources.append(path)
		if FileAccess.file_exists(source + ".import") and not sources.has(source + ".import"):
			sources.append(source + ".import")
		cursor += 1
	var hashes: Dictionary = {}
	for source: String in sources:
		if not FileAccess.file_exists(source):
			push_error("采集依赖缺失：" + source)
			quit(1)
			return
		hashes[source] = FileAccess.get_sha256(source)
	root.borderless = true
	root.size = Vector2i(1280, 720)
	var scene: Node = load("res://scenes/playground/battlefield_courtyard.tscn").instantiate()
	root.add_child(scene)
	await _frames(5)
	for id: String in ["overgrown", "flooded", "passage"]:
		await scene.select_layout(id)
		scene.board_view.set_process(false)
		for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
			root.size = dimensions
			await _frames(4)
			scene.fit_board()
			Input.warp_mouse(Vector2(20, 600))
			for annotations: bool in [true, false]:
				if scene._ranges_shown != annotations:
					scene._toggle_ranges()
				if scene._tooltip_enabled != annotations:
					scene._toggle_tooltip()
				scene._grid_shown = annotations
				scene.board_view.grid_visible = annotations
				# 固定水纹、树摆与遮挡淡化的最终状态，不依赖采集机器的帧耗时。
				scene._update_board_visibility_context(Vector2i(-1, -1))
				scene.board_view.set("_time", CAPTURE_TIME - 1.0)
				scene.board_view._process(1.0)
				await _frames(30)
				await RenderingServer.frame_post_draw
				var captured: Image = root.get_texture().get_image()
				await _frames(3)
				await RenderingServer.frame_post_draw
				var repeated: Image = root.get_texture().get_image()
				if captured.get_data() != repeated.get_data():
					push_error("冻结后连续画面仍有变化：" + id)
					quit(1)
					return
				var filename: String = id + "-" + str(dimensions.x) + ("-play" if annotations else "-clear") + ".png"
				var output_path: String = _output.path_join(filename)
				if CaptureMetadata.save_png(root, captured, output_path) != OK:
					push_error("截图保存失败：" + filename)
					quit(1)
					return
				_captures.append(CaptureMetadata.capture_record(root, captured, output_path, {
					"layout": id, "annotations": annotations, "size": [dimensions.x, dimensions.y],
					"process_frame": Engine.get_process_frames(), "animation_time": CAPTURE_TIME,
					"repeated_frame_identical": true,
				}))
	for source: String in sources:
		if hashes[source] != FileAccess.get_sha256(source):
			push_error("采集期间源码发生变化，本批截图不可作为同版证据。")
			quit(1)
			return
	var source_fields: Dictionary = {"captured_at_utc": Time.get_datetime_string_from_system(true),
		"engine": Engine.get_version_info()["string"], "post_processing": false,
		"seed": CAPTURE_SEED, "animation_time": CAPTURE_TIME,
		"baseline_status": "candidate_unapproved",
		"comparison_scope": "identical consecutive frames, not aesthetic approval",
		"sources_sha256": hashes}
	var manifest_path: String = _output.path_join("capture-manifest.json")
	if not CaptureMetadata.write_manifest(root, manifest_path, _captures, source_fields):
		push_error("截图清单无法保存。")
		quit(1)
		return
	print("COURTYARD_VISUAL_CAPTURE_RESULT ", JSON.stringify({"captures": _captures.size(), "failed": 0}))
	scene.queue_free()
	await _frames(3)
	quit()


func _frames(count: int) -> void:
	for unused: int in count:
		await process_frame


func _append_tree_files(directory: String, extension: String, sources: Array[String]) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	for filename: String in dir.get_files():
		var path: String = directory.path_join(filename)
		if filename.get_extension() == extension and not sources.has(path):
			sources.append(path)
	for folder: String in dir.get_directories():
		_append_tree_files(directory.path_join(folder), extension, sources)
