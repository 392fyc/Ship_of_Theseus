extends Control
## 与正式玩法隔离的视觉素材统一质感检查场。
## 样本槽、检查显示尺寸和准入状态都由仓库内清单驱动；清单中的显示尺寸只用于
## Playground 评审，不是生产规格。

const MANIFEST_PATH: String = "res://assets/prototype/visual_style/sample_manifest.json"
const SCREENSHOT_DIRECTORY: String = "user://visual_style_playground/"
const FILTER_MODES: Array[String] = ["nearest", "linear"]

const COLOR_BACKGROUND: Color = Color("11121a")
const COLOR_PANEL: Color = Color("1b1c28")
const COLOR_PANEL_BORDER: Color = Color("6e6147")
const COLOR_TEXT: Color = Color("e6dbc7")
const COLOR_SUBTLE: Color = Color("96909a")
const COLOR_PENDING: Color = Color("d5ad52")
const COLOR_ERROR: Color = Color("ef6a6a")
const COLOR_USABLE: Color = Color("65c18c")

var _samples: Array = []
var _check_sizes: Array[Vector2i] = []
var _sample_states: Dictionary = {}
var _filter_mode: String = "nearest"
var _check_size: Vector2i = Vector2i.ZERO
var _preview_rects: Dictionary = {}
var _card_nodes: Array[Control] = []
var _render_viewport: SubViewport = null
var _viewport_container: SubViewportContainer = null
var _canvas_root: Control = null
var _cards_container: HBoxContainer = null
var _filter_button: Button = null
var _size_option: OptionButton = null
var _scale_label: Label = null
var _screenshot_status: Label = null
var _screenshot_sequence: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not _load_manifest():
		return
	_build_render_canvas()
	_build_interface()
	_refresh_filter_state()
	_refresh_check_size_state()


func get_sample_ids() -> Array[String]:
	var ids: Array[String] = []
	for sample_value: Variant in _samples:
		var sample: Dictionary = sample_value as Dictionary
		ids.append(str(sample.get("id", "")))
	return ids


func get_sample_state(sample_id: String) -> Dictionary:
	if not _sample_states.has(sample_id):
		return {}
	var state: Dictionary = (_sample_states[sample_id] as Dictionary).duplicate()
	var preview: TextureRect = _preview_rects.get(sample_id) as TextureRect
	if preview != null and preview.is_inside_tree():
		state["display_size"] = Vector2i(roundi(preview.size.x), roundi(preview.size.y))
	return state


func inspect_sample(sample: Dictionary) -> Dictionary:
	var state: Dictionary = _inspect_sample_internal(sample)
	state.erase("_texture")
	return state


func get_preview_nodes() -> Array:
	var previews: Array = []
	for sample_id: String in get_sample_ids():
		var preview: TextureRect = _preview_rects.get(sample_id) as TextureRect
		if preview != null:
			previews.append(preview)
	return previews


func get_filter_mode() -> String:
	return _filter_mode


func set_filter_mode(mode: String) -> void:
	if not FILTER_MODES.has(mode):
		return
	_filter_mode = mode
	_refresh_filter_state()


func get_check_sizes() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for check_size: Vector2i in _check_sizes:
		result.append(check_size)
	return result


func get_check_size() -> Vector2i:
	return _check_size


func get_render_size() -> Vector2i:
	return _render_viewport.size if _render_viewport != null else Vector2i.ZERO


func set_check_size(check_size: Vector2i) -> void:
	if not _check_sizes.has(check_size):
		return
	_check_size = check_size
	if _render_viewport != null:
		_render_viewport.size = check_size
	if _viewport_container != null:
		_viewport_container.custom_minimum_size = Vector2(check_size)
	if DisplayServer.get_name() != "headless":
		get_window().size = check_size
	_refresh_check_size_state()


func get_layout_metrics() -> Dictionary:
	var uses_horizontal_scroll: bool = false
	var ancestor: Node = _cards_container.get_parent() if _cards_container != null else null
	while ancestor != null and ancestor != _canvas_root:
		if ancestor is ScrollContainer:
			uses_horizontal_scroll = true
			break
		ancestor = ancestor.get_parent()

	var canvas_size: Vector2i = get_render_size()
	if _card_nodes.is_empty():
		return {
			"uses_horizontal_scroll": uses_horizontal_scroll,
			"all_cards_visible": false,
			"card_count": 0,
			"canvas_size": canvas_size,
		}

	var cards_left: float = INF
	var cards_top: float = INF
	var cards_right: float = -INF
	var cards_bottom: float = -INF
	for card: Control in _card_nodes:
		var card_rect: Rect2 = card.get_global_rect()
		cards_left = minf(cards_left, card_rect.position.x)
		cards_top = minf(cards_top, card_rect.position.y)
		cards_right = maxf(cards_right, card_rect.end.x)
		cards_bottom = maxf(cards_bottom, card_rect.end.y)
	var all_cards_visible: bool = (
		cards_left >= 0.0
		and cards_top >= 0.0
		and cards_right <= float(canvas_size.x)
		and cards_bottom <= float(canvas_size.y)
	)
	return {
		"uses_horizontal_scroll": uses_horizontal_scroll,
		"all_cards_visible": all_cards_visible,
		"card_count": _card_nodes.size(),
		"canvas_size": canvas_size,
		"cards_left": cards_left,
		"cards_right": cards_right,
		"cards_top": cards_top,
		"cards_bottom": cards_bottom,
	}


func get_screenshot_target_path() -> String:
	_screenshot_sequence += 1
	var timestamp: String = Time.get_datetime_string_from_system(false, true)
	timestamp = timestamp.replace("-", "").replace(":", "").replace("T", "_").replace(" ", "_")
	var tick_msec: int = Time.get_ticks_msec()
	return "%svisual_style_%dx%d_%s_%d_%03d.png" % [
		SCREENSHOT_DIRECTORY,
		_check_size.x,
		_check_size.y,
		timestamp,
		tick_msec,
		_screenshot_sequence,
	]


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F:
			_toggle_filter()
		KEY_R:
			_select_next_check_size()
		KEY_P:
			_save_screenshot()


func _load_manifest() -> bool:
	var file: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		push_error("无法读取视觉样本清单：%s" % MANIFEST_PATH)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("视觉样本清单不是 JSON 对象：%s" % MANIFEST_PATH)
		return false
	var manifest: Dictionary = parsed as Dictionary
	var parsed_check_sizes: Array[Vector2i] = _parse_check_sizes(manifest.get("check_sizes", []))
	if parsed_check_sizes.size() != 3:
		push_error("视觉样本清单必须按升序提供三档有效的 16:9 检查尺寸")
		return false
	_check_sizes = parsed_check_sizes
	_check_size = _check_sizes[0]

	var samples_value: Variant = manifest.get("samples", [])
	if typeof(samples_value) != TYPE_ARRAY:
		push_error("视觉样本清单缺少 samples 数组")
		return false
	_samples = samples_value as Array

	var default_filter: String = str(manifest.get("default_filter", ""))
	if not FILTER_MODES.has(default_filter):
		push_error("视觉样本清单的 default_filter 无效：%s" % default_filter)
		return false
	_filter_mode = default_filter
	return true


func _parse_check_sizes(value: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	var raw_sizes: Array = value as Array
	if raw_sizes.size() != 3:
		return result
	for raw_size: Variant in raw_sizes:
		if not _is_two_number_array(raw_size):
			return []
		var check_size: Vector2i = _array_to_size(raw_size)
		if check_size.x < 2 or check_size.y < 2:
			return []
		if check_size.x * 9 != check_size.y * 16:
			return []
		if not result.is_empty():
			var previous: Vector2i = result[-1]
			if check_size.x <= previous.x or check_size.y <= previous.y:
				return []
		result.append(check_size)
	return result


func _is_two_number_array(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	var values: Array = value as Array
	if values.size() != 2:
		return false
	for component: Variant in values:
		if typeof(component) != TYPE_INT and typeof(component) != TYPE_FLOAT:
			return false
		if float(component) != floorf(float(component)):
			return false
	return true


func _build_render_canvas() -> void:
	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "RenderViewportContainer"
	_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport_container.stretch = false
	_viewport_container.mouse_target = false
	_viewport_container.custom_minimum_size = Vector2(_check_size)
	add_child(_viewport_container)

	_render_viewport = SubViewport.new()
	_render_viewport.name = "RenderViewport"
	_render_viewport.unique_name_in_owner = true
	_render_viewport.size = _check_size
	_render_viewport.disable_3d = true
	_render_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport_container.add_child(_render_viewport)
	_render_viewport.owner = self

	_canvas_root = Control.new()
	_canvas_root.name = "InspectionCanvas"
	_canvas_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_render_viewport.add_child(_canvas_root)
	_canvas_root.owner = self


func _build_interface() -> void:
	var background: ColorRect = ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = COLOR_BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas_root.add_child(background)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	_canvas_root.add_child(margin)

	var page: VBoxContainer = VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	margin.add_child(page)

	var title: Label = Label.new()
	title.text = "视觉素材统一质感 Playground"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	page.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "UI、人物、战棋人物、场景地形与特效并排检查；状态由样本清单实时判定。"
	subtitle.add_theme_color_override("font_color", COLOR_SUBTLE)
	page.add_child(subtitle)

	var controls: HBoxContainer = _build_controls()
	page.add_child(controls)
	_filter_button.owner = self
	_size_option.owner = self

	var separator: HSeparator = HSeparator.new()
	page.add_child(separator)

	_cards_container = HBoxContainer.new()
	_cards_container.name = "SampleCards"
	_cards_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_container.add_theme_constant_override("separation", 8)
	_cards_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_cards_container)
	for sample_value: Variant in _samples:
		var card: PanelContainer = _build_sample_card(sample_value as Dictionary)
		_cards_container.add_child(card)
		_card_nodes.append(card)


func _build_controls() -> HBoxContainer:
	var controls: HBoxContainer = HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)

	_filter_button = Button.new()
	_filter_button.name = "FilterModeButton"
	_filter_button.unique_name_in_owner = true
	_filter_button.tooltip_text = "切换纹理过滤方式（快捷键 F）"
	_filter_button.pressed.connect(_toggle_filter)
	controls.add_child(_filter_button)

	_size_option = OptionButton.new()
	_size_option.name = "CheckSizeOption"
	_size_option.unique_name_in_owner = true
	_size_option.tooltip_text = "选择检查画布尺寸（快捷键 R）"
	for check_size: Vector2i in _check_sizes:
		_size_option.add_item("%d × %d" % [check_size.x, check_size.y])
	_size_option.item_selected.connect(_on_check_size_selected)
	controls.add_child(_size_option)

	_scale_label = Label.new()
	_scale_label.add_theme_color_override("font_color", COLOR_SUBTLE)
	_scale_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(_scale_label)

	var screenshot_button: Button = Button.new()
	screenshot_button.text = "截图（P）"
	screenshot_button.tooltip_text = "从检查画布写入 user://visual_style_playground/"
	screenshot_button.pressed.connect(_save_screenshot)
	controls.add_child(screenshot_button)

	_screenshot_status = Label.new()
	_screenshot_status.add_theme_color_override("font_color", COLOR_SUBTLE)
	controls.add_child(_screenshot_status)
	return controls


func _build_sample_card(sample: Dictionary) -> PanelContainer:
	var sample_id: String = str(sample.get("id", ""))
	var state: Dictionary = _inspect_sample_internal(sample)
	var texture: Texture2D = state.get("_texture") as Texture2D
	var cached_state: Dictionary = state.duplicate()
	cached_state.erase("_texture")
	_sample_states[sample_id] = cached_state

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(238.0, 330.0)
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = COLOR_PANEL
	panel_style.border_color = COLOR_ERROR if state.get("placeholder_kind") == "error" else COLOR_PANEL_BORDER
	panel_style.set_border_width_all(2 if state.get("placeholder_kind") == "error" else 1)
	panel_style.set_corner_radius_all(4)
	panel_style.content_margin_left = 8.0
	panel_style.content_margin_top = 8.0
	panel_style.content_margin_right = 8.0
	panel_style.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", panel_style)

	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	card.add_child(content)

	var heading: Label = Label.new()
	heading.text = str(sample.get("label", sample_id))
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", COLOR_TEXT)
	content.add_child(heading)

	var status: Label = Label.new()
	status.text = str(state.get("status_text", "状态未知"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 34.0
	status.add_theme_color_override("font_color", _status_color(state))
	content.add_child(status)

	var preview_area: CenterContainer = CenterContainer.new()
	preview_area.custom_minimum_size = Vector2(220.0, 170.0)
	preview_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(preview_area)

	var display_size: Vector2i = _array_to_size(sample.get("display_size", [0, 0]))
	var preview: TextureRect = TextureRect.new()
	preview.name = "%sPreview" % sample_id.to_pascal_case()
	preview.custom_minimum_size = Vector2(display_size)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture = texture if bool(state.get("is_usable", false)) else _create_placeholder_texture(
		sample_id,
		display_size,
		str(state.get("placeholder_kind", "error"))
	)
	preview_area.add_child(preview)
	_preview_rects[sample_id] = preview

	var source_size: Vector2i = _array_to_size(sample.get("source_size", [0, 0]))
	var source_label: Label = Label.new()
	source_label.text = "清单源尺寸：%s" % (_format_size(source_size) if source_size != Vector2i.ZERO else "待提供")
	source_label.add_theme_color_override("font_color", COLOR_SUBTLE)
	content.add_child(source_label)

	var actual_size: Vector2i = state.get("actual_texture_size", Vector2i.ZERO) as Vector2i
	var actual_label: Label = Label.new()
	actual_label.text = "实际纹理：%s" % (_format_size(actual_size) if actual_size != Vector2i.ZERO else "无")
	actual_label.add_theme_color_override("font_color", COLOR_SUBTLE)
	content.add_child(actual_label)

	var display_label: Label = Label.new()
	display_label.text = "Playground 显示：%s" % _format_size(display_size)
	display_label.add_theme_color_override("font_color", COLOR_SUBTLE)
	content.add_child(display_label)

	var provenance_label: Label = Label.new()
	provenance_label.text = "来源：%s\n许可：%s" % [
		str(sample.get("provenance", "unassigned")),
		str(sample.get("license_status", "unverified")),
	]
	provenance_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	provenance_label.custom_minimum_size.y = 32.0
	provenance_label.add_theme_color_override("font_color", COLOR_SUBTLE)
	content.add_child(provenance_label)
	return card


func _inspect_sample_internal(sample: Dictionary) -> Dictionary:
	var source_path: String = str(sample.get("source_path", ""))
	var declared_size: Vector2i = _array_to_size(sample.get("source_size", [0, 0]))
	var display_size: Vector2i = _array_to_size(sample.get("display_size", [0, 0]))
	var approval_status: String = str(sample.get("approval_status", ""))
	var license_status: String = str(sample.get("license_status", ""))
	var result: Dictionary = {
		"status_code": "unknown",
		"status_text": "状态未知",
		"is_usable": false,
		"placeholder_kind": "error",
		"source_path": source_path,
		"source_size": declared_size,
		"actual_texture_size": Vector2i.ZERO,
		"display_size": display_size,
		"approval_status": approval_status,
		"license_status": license_status,
	}

	if source_path.is_empty():
		var pending_parts: Array[String] = ["待提供"]
		if approval_status != "approved":
			pending_parts.append("待用户确认")
		if license_status != "verified":
			pending_parts.append("许可未核验")
		return _set_sample_status(result, "pending_asset", " · ".join(pending_parts), "pending")

	if approval_status != "approved":
		var approval_text: String = "待用户确认" if approval_status == "pending_user_approval" else "用户确认状态无效"
		return _set_sample_status(result, "approval_pending", approval_text, "pending")
	if license_status != "verified":
		var license_text: String = "许可未核验" if license_status == "unverified" else "许可状态无效"
		return _set_sample_status(result, "license_unverified", license_text, "pending")
	if not _is_valid_resource_path(source_path):
		return _set_sample_status(result, "invalid_path", "路径格式错误：必须使用仓库内 res:// 路径", "error")
	if not ResourceLoader.exists(source_path):
		return _set_sample_status(result, "resource_missing", "资源不存在", "error")

	var loaded: Variant = load(source_path)
	if not loaded is Texture2D:
		return _set_sample_status(result, "wrong_resource_type", "资源类型错误：需要 Texture2D", "error")
	var texture: Texture2D = loaded as Texture2D
	var actual_size: Vector2i = Vector2i(texture.get_size())
	result["actual_texture_size"] = actual_size
	if declared_size == Vector2i.ZERO or declared_size != actual_size:
		return _set_sample_status(
			result,
			"size_mismatch",
			"尺寸不符：清单 %s，实际 %s" % [_format_size(declared_size), _format_size(actual_size)],
			"error"
		)
	result["_texture"] = texture
	result["is_usable"] = true
	return _set_sample_status(result, "usable", "可用", "usable")


func _set_sample_status(result: Dictionary, code: String, text: String, placeholder_kind: String) -> Dictionary:
	result["status_code"] = code
	result["status_text"] = text
	result["placeholder_kind"] = placeholder_kind
	return result


func _is_valid_resource_path(source_path: String) -> bool:
	return (
		source_path.begins_with("res://")
		and source_path.length() > "res://".length()
		and not source_path.contains("\\")
		and not source_path.contains("..")
	)


func _create_placeholder_texture(sample_id: String, display_size: Vector2i, kind: String) -> ImageTexture:
	var image_size: Vector2i = Vector2i(maxi(display_size.x, 1), maxi(display_size.y, 1))
	var image: Image = Image.create(image_size.x, image_size.y, false, Image.FORMAT_RGBA8)
	var is_error: bool = kind == "error"
	var base: Color = Color("351b24") if is_error else Color("292a38")
	var alternate: Color = Color("4c2430") if is_error else Color("343646")
	var accent: Color = Color("ef6a6a") if is_error else Color("b69a5d")
	for y: int in range(image_size.y):
		for x: int in range(image_size.x):
			var tile_even: bool = ((x / 8) as int + (y / 8) as int) % 2 == 0
			var color: Color = base if tile_even else alternate
			var border: bool = x < 2 or y < 2 or x >= image_size.x - 2 or y >= image_size.y - 2
			var error_cross: bool = is_error and (
				absi(x * image_size.y - y * image_size.x) < maxi(image_size.x, image_size.y) * 2
				or absi((image_size.x - 1 - x) * image_size.y - y * image_size.x) < maxi(image_size.x, image_size.y) * 2
			)
			if border or error_cross:
				color = accent
			image.set_pixel(x, y, color)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	texture.resource_name = "%s_runtime_%s_placeholder" % [sample_id, kind]
	return texture


func _status_color(state: Dictionary) -> Color:
	if bool(state.get("is_usable", false)):
		return COLOR_USABLE
	return COLOR_ERROR if state.get("placeholder_kind") == "error" else COLOR_PENDING


func _toggle_filter() -> void:
	set_filter_mode("linear" if _filter_mode == "nearest" else "nearest")


func _select_next_check_size() -> void:
	var current_index: int = _check_sizes.find(_check_size)
	var next_index: int = (current_index + 1) % _check_sizes.size()
	set_check_size(_check_sizes[next_index])


func _on_check_size_selected(index: int) -> void:
	if index >= 0 and index < _check_sizes.size():
		set_check_size(_check_sizes[index])


func _refresh_filter_state() -> void:
	if _filter_button != null:
		_filter_button.text = "过滤：%s" % ("Nearest" if _filter_mode == "nearest" else "Linear")
	var texture_filter: CanvasItem.TextureFilter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
		if _filter_mode == "nearest"
		else CanvasItem.TEXTURE_FILTER_LINEAR
	)
	for preview_value: Variant in _preview_rects.values():
		var preview: TextureRect = preview_value as TextureRect
		if preview != null:
			preview.texture_filter = texture_filter


func _refresh_check_size_state() -> void:
	if _size_option != null:
		var selected_index: int = _check_sizes.find(_check_size)
		if selected_index >= 0:
			_size_option.select(selected_index)
	if _scale_label != null:
		var baseline_height: int = _check_sizes[0].y
		var scale_from_baseline: float = float(_check_size.y) / float(baseline_height)
		_scale_label.text = "实际画布：%s · 相对首档：%.2f×" % [
			_format_size(_check_size),
			scale_from_baseline,
		]


func _save_screenshot() -> void:
	if _render_viewport == null:
		_set_screenshot_status("检查画布尚未就绪", true)
		return
	var target_path: String = get_screenshot_target_path()
	var absolute_directory: String = ProjectSettings.globalize_path(SCREENSHOT_DIRECTORY)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK:
		_set_screenshot_status("无法创建截图目录（%s）" % error_string(directory_error), true)
		return
	var image: Image = _render_viewport.get_texture().get_image()
	var save_error: Error = image.save_png(target_path)
	if save_error == OK:
		_set_screenshot_status("已写入 %s" % target_path, false)
	else:
		_set_screenshot_status("截图失败（%s）" % error_string(save_error), true)


func _set_screenshot_status(message: String, is_error: bool) -> void:
	if _screenshot_status == null:
		return
	_screenshot_status.text = message
	_screenshot_status.add_theme_color_override("font_color", COLOR_ERROR if is_error else COLOR_SUBTLE)


func _array_to_size(value: Variant) -> Vector2i:
	if typeof(value) != TYPE_ARRAY:
		return Vector2i.ZERO
	var values: Array = value as Array
	if values.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(values[0]), int(values[1]))


func _format_size(value: Vector2i) -> String:
	return "%d×%d" % [value.x, value.y]
