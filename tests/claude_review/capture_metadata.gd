extends RefCounted
## 为视觉采集及其清单记录统一的运行配置与图像信息。

static var _captures_by_directory: Dictionary = {}


static func capture_record(root: Window, image: Image, image_path: String,
		details: Dictionary = {}) -> Dictionary:
	var visible_rect: Rect2 = root.get_visible_rect()
	var record: Dictionary = {
		"file": image_path.get_file(),
		"sha256": FileAccess.get_sha256(image_path),
		"renderer": str(RenderingServer.get_current_rendering_method()),
		"project_stretch_mode": str(ProjectSettings.get_setting("display/window/stretch/mode")),
		"content_scale_mode": int(root.content_scale_mode),
		"content_scale_size": [root.content_scale_size.x, root.content_scale_size.y],
		"window_size": [root.size.x, root.size.y],
		"image_size": [image.get_width(), image.get_height()],
		"visible_rect": [visible_rect.position.x, visible_rect.position.y,
			visible_rect.size.x, visible_rect.size.y],
		"capture_kind": "viewport",
	}
	record.merge(details, true)
	return record


static func build_manifest(root: Window, captures: Array[Dictionary],
		source_fields: Dictionary = {}) -> Dictionary:
	var manifest: Dictionary = source_fields.duplicate(true)
	manifest["schema_version"] = 1
	manifest["renderer"] = str(RenderingServer.get_current_rendering_method())
	manifest["project_stretch_mode"] = str(ProjectSettings.get_setting("display/window/stretch/mode"))
	manifest["captures"] = captures.duplicate(true)
	return manifest


static func write_manifest(root: Window, manifest_path: String,
		captures: Array[Dictionary], source_fields: Dictionary = {}) -> bool:
	var file: FileAccess = FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(build_manifest(root, captures, source_fields), "  "))
	file.close()
	return true


static func save_png(root: Window, image: Image, image_path: String,
		details: Dictionary = {}) -> Error:
	var save_error: Error = image.save_png(image_path)
	if save_error != OK:
		return save_error
	var directory: String = image_path.get_base_dir()
	var key: String = ProjectSettings.globalize_path(directory).simplify_path()
	var captures: Array[Dictionary] = []
	if _captures_by_directory.has(key):
		captures = (_captures_by_directory[key] as Array[Dictionary]).duplicate(true)
	captures.append(capture_record(root, image, image_path, details))
	_captures_by_directory[key] = captures
	var manifest_path: String = directory.path_join("capture-metadata.json")
	if not write_manifest(root, manifest_path, captures):
		push_error("无法写入采集元数据清单：" + manifest_path)
		return FAILED
	return OK
