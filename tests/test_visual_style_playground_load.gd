extends SceneTree
## 视觉素材统一质感 Playground 的清单、加载与交互合同测试。
##
## 运行：
##   <Godot_console.exe> --headless --path <worktree> \
##     --script res://tests/test_visual_style_playground_load.gd

const MANIFEST_PATH: String = "res://assets/prototype/visual_style/sample_manifest.json"
const SCENE_PATH: String = "res://scenes/playground/visual_style_playground.tscn"
const SCRIPT_PATH: String = "res://scripts/ui/playground/visual_style_playground.gd"
const EXPECTED_IDS: Array[String] = ["ui", "portrait", "map_token", "terrain", "vfx"]
const EXPECTED_CHECK_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const TEXTURE_FIXTURE_PATH: String = "res://dev_doc/ui-art-research/mood/01-cold-stone.png"
const REQUIRED_FIELDS: Array[String] = [
	"source_path",
	"source_size",
	"display_size",
	"approval_status",
	"provenance",
	"license_status",
]

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_visual_style_playground_load ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	_check_manifest_contract()
	await _check_scene_contract()
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for failure: String in _fails:
			print("  ✗ " + failure)
	quit(0 if _fail == 0 else 1)


func _check_manifest_contract() -> void:
	var manifest_exists: bool = FileAccess.file_exists(MANIFEST_PATH)
	_check("样本清单存在", manifest_exists, MANIFEST_PATH)
	if not manifest_exists:
		return

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	_check("样本清单是有效 JSON 对象", typeof(parsed) == TYPE_DICTIONARY)
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	var manifest: Dictionary = parsed as Dictionary
	_check("样本清单版本为 1", manifest.get("version", 0) == 1)
	var manifest_sizes_value: Variant = manifest.get("check_sizes", [])
	_check("清单包含且只包含三档检查尺寸", typeof(manifest_sizes_value) == TYPE_ARRAY)
	if typeof(manifest_sizes_value) == TYPE_ARRAY:
		var manifest_sizes: Array[Vector2i] = []
		for size_value: Variant in manifest_sizes_value as Array:
			manifest_sizes.append(_array_to_size(size_value))
		_check("三档检查尺寸由清单严格定义", manifest_sizes == EXPECTED_CHECK_SIZES, str(manifest_sizes))
	var samples_value: Variant = manifest.get("samples", [])
	_check("样本清单包含 samples 数组", typeof(samples_value) == TYPE_ARRAY)
	if typeof(samples_value) != TYPE_ARRAY:
		return

	var samples: Array = samples_value as Array
	var actual_ids: Array[String] = []
	for sample_value: Variant in samples:
		if typeof(sample_value) != TYPE_DICTIONARY:
			_check("每个样本槽都是 JSON 对象", false, str(sample_value))
			continue
		var sample: Dictionary = sample_value as Dictionary
		var sample_id: String = str(sample.get("id", ""))
		actual_ids.append(sample_id)
		for field_name: String in REQUIRED_FIELDS:
			_check("样本槽 %s 包含字段 %s" % [sample_id, field_name], sample.has(field_name))
		_check("样本槽 %s 尚未导入素材" % sample_id, str(sample.get("source_path", "missing")) == "")
		_check(
			"样本槽 %s 等待用户确认" % sample_id,
			str(sample.get("approval_status", "")) == "pending_user_approval"
		)
		_check(
			"样本槽 %s 许可尚未核验" % sample_id,
			str(sample.get("license_status", "")) == "unverified"
		)

	_check("样本槽顺序固定为五类视觉样本", actual_ids == EXPECTED_IDS, str(actual_ids))
	_check("初版不包含战棋战斗动画槽", not actual_ids.has("combat_animation"))


func _check_scene_contract() -> void:
	var script_resource: Variant = load(SCRIPT_PATH)
	_check("Playground 脚本能够加载", script_resource != null, SCRIPT_PATH)

	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_check("Playground 场景能够加载", packed != null, SCENE_PATH)
	if packed == null:
		return

	var instance: Node = packed.instantiate()
	_check("Playground 场景能够实例化", instance != null)
	if instance == null:
		return

	root.add_child(instance)
	await process_frame

	var attached_script: Variant = instance.get_script()
	_check("根节点确实挂载脚本", attached_script != null)
	if attached_script != null:
		_check(
			"根节点挂载预期脚本",
			str(attached_script.resource_path) == SCRIPT_PATH,
			str(attached_script.resource_path)
		)

	var sample_ids: Array = instance.call("get_sample_ids") as Array
	_check("运行时按清单构建五个样本槽", sample_ids == EXPECTED_IDS, str(sample_ids))
	for sample_id: String in EXPECTED_IDS:
		var current_state: Dictionary = instance.call("get_sample_state", sample_id) as Dictionary
		_check(
			"当前样本槽 %s 的运行状态来自待确认清单" % sample_id,
			current_state.get("status_code") == "pending_asset",
			str(current_state)
		)
		var status_text: String = str(current_state.get("status_text", ""))
		_check("当前样本槽 %s 显示待提供" % sample_id, status_text.contains("待提供"), status_text)
		_check("当前样本槽 %s 显示待用户确认" % sample_id, status_text.contains("待用户确认"), status_text)
		_check("当前样本槽 %s 显示许可未核验" % sample_id, status_text.contains("许可未核验"), status_text)
		_check(
			"当前样本槽 %s 没有伪造实际纹理尺寸" % sample_id,
			current_state.get("actual_texture_size") == Vector2i.ZERO,
			str(current_state)
		)

	_check_sample_statuses(instance)

	_check("默认过滤方式为 Nearest", instance.call("get_filter_mode") == "nearest")
	instance.call("set_filter_mode", "nearest")
	await process_frame
	if instance.has_method("get_preview_nodes"):
		var nearest_previews: Array = instance.call("get_preview_nodes") as Array
		_check("能读取五个真实纹理预览控件", nearest_previews.size() == EXPECTED_IDS.size(), str(nearest_previews.size()))
		for preview_value: Variant in nearest_previews:
			var preview: TextureRect = preview_value as TextureRect
			_check(
				"Nearest 直接应用到每个 TextureRect",
				preview != null and preview.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
			)
	else:
		_check("提供真实纹理预览控件只读接口", false)
	instance.call("set_filter_mode", "linear")
	await process_frame
	_check("能够切换到 Linear", instance.call("get_filter_mode") == "linear")
	if instance.has_method("get_preview_nodes"):
		for preview_value: Variant in instance.call("get_preview_nodes") as Array:
			var preview: TextureRect = preview_value as TextureRect
			_check(
				"Linear 直接应用到每个 TextureRect",
				preview != null and preview.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR
			)
	var filter_button: Button = instance.get_node_or_null("%FilterModeButton") as Button
	_check("过滤切换按钮存在", filter_button != null)
	if filter_button != null:
		_check("过滤按钮同步显示 Linear", filter_button.text == "过滤：Linear", filter_button.text)

	_check("检查尺寸只有清单这个权威来源", instance.call("get_check_sizes") == EXPECTED_CHECK_SIZES)
	_check("默认检查尺寸为 1280×720", instance.call("get_check_size") == EXPECTED_CHECK_SIZES[0])
	var render_viewport: SubViewport = instance.get_node_or_null("%RenderViewport") as SubViewport
	_check("存在承载检查界面的 SubViewport", render_viewport != null)
	for check_size: Vector2i in EXPECTED_CHECK_SIZES:
		instance.call("set_check_size", check_size)
		await process_frame
		_check("内部检查尺寸切换为 %s" % check_size, instance.call("get_check_size") == check_size)
		_check("公开渲染尺寸切换为 %s" % check_size, instance.call("get_render_size") == check_size)
		_check(
			"SubViewport 实际尺寸切换为 %s" % check_size,
			render_viewport != null and render_viewport.size == check_size,
			str(render_viewport.size if render_viewport != null else Vector2i.ZERO)
		)

	instance.call("set_check_size", Vector2i(1920, 1080))
	await process_frame
	var size_option: OptionButton = instance.get_node_or_null("%CheckSizeOption") as OptionButton
	_check("检查尺寸选择器存在", size_option != null)
	if size_option != null:
		_check(
			"检查尺寸选择器同步显示 1920×1080",
			size_option.get_item_text(size_option.selected) == "1920 × 1080",
			size_option.get_item_text(size_option.selected)
			)

	instance.call("set_check_size", Vector2i(1280, 720))
	await process_frame
	var layout_metrics: Dictionary = instance.call("get_layout_metrics") as Dictionary
	_check("720p 检查画布不使用横向滚动", layout_metrics.get("uses_horizontal_scroll") == false, str(layout_metrics))
	_check("720p 检查画布同时容纳五张卡", layout_metrics.get("all_cards_visible") == true, str(layout_metrics))
	_check("720p 检查画布实际包含五张卡", layout_metrics.get("card_count") == 5, str(layout_metrics))

	var map_state: Dictionary = instance.call("get_sample_state", "map_token") as Dictionary
	_check("战棋人物标注源尺寸 48×48", map_state.get("source_size") == Vector2i(48, 48), str(map_state))
	_check("战棋人物保持真实 48×48 检查区", map_state.get("display_size") == Vector2i(48, 48), str(map_state))

	var screenshot_target: String = str(instance.call("get_screenshot_target_path"))
	var second_screenshot_target: String = str(instance.call("get_screenshot_target_path"))
	_check(
		"截图目标严格位于 user://visual_style_playground/",
		screenshot_target.begins_with("user://visual_style_playground/"),
		screenshot_target
	)
	_check("同一毫秒连续生成的截图名不会覆盖", screenshot_target != second_screenshot_target)

	instance.queue_free()
	await process_frame


func _check_sample_statuses(instance: Node) -> void:
	_check("提供清单样本运行状态检查接口", instance.has_method("inspect_sample"))
	if not instance.has_method("inspect_sample"):
		return

	var invalid_path: Dictionary = instance.call(
		"inspect_sample", _make_sample("C:/outside.png", Vector2i(48, 48))
	) as Dictionary
	_check("仓库外路径判定为路径格式错误", invalid_path.get("status_code") == "invalid_path", str(invalid_path))

	var missing: Dictionary = instance.call(
		"inspect_sample", _make_sample("res://assets/prototype/visual_style/missing.png", Vector2i(48, 48))
	) as Dictionary
	_check("缺失路径不会被当成普通待导入", missing.get("status_code") == "resource_missing", str(missing))

	var wrong_type: Dictionary = instance.call(
		"inspect_sample", _make_sample(SCENE_PATH, Vector2i(48, 48))
	) as Dictionary
	_check("非 Texture2D 资源判定为类型错误", wrong_type.get("status_code") == "wrong_resource_type", str(wrong_type))

	var fixture: Texture2D = load(TEXTURE_FIXTURE_PATH) as Texture2D
	_check("状态测试使用真实 Texture2D fixture", fixture != null, TEXTURE_FIXTURE_PATH)
	if fixture == null:
		return
	var actual_size: Vector2i = Vector2i(fixture.get_size())
	var mismatch: Dictionary = instance.call(
		"inspect_sample", _make_sample(TEXTURE_FIXTURE_PATH, actual_size + Vector2i.ONE)
	) as Dictionary
	_check("声明尺寸与实际纹理不符时明确报错", mismatch.get("status_code") == "size_mismatch", str(mismatch))
	_check("尺寸错误仍返回实际纹理尺寸", mismatch.get("actual_texture_size") == actual_size, str(mismatch))

	var usable: Dictionary = instance.call(
		"inspect_sample", _make_sample(TEXTURE_FIXTURE_PATH, actual_size)
	) as Dictionary
	_check("批准、许可和纹理均有效时状态为可用", usable.get("status_code") == "usable", str(usable))

	var approval_pending_sample: Dictionary = _make_sample(TEXTURE_FIXTURE_PATH, actual_size)
	approval_pending_sample["approval_status"] = "pending_user_approval"
	var approval_pending: Dictionary = instance.call("inspect_sample", approval_pending_sample) as Dictionary
	_check("未获用户确认时不会加载为可用", approval_pending.get("status_code") == "approval_pending", str(approval_pending))

	var license_pending_sample: Dictionary = _make_sample(TEXTURE_FIXTURE_PATH, actual_size)
	license_pending_sample["license_status"] = "unverified"
	var license_pending: Dictionary = instance.call("inspect_sample", license_pending_sample) as Dictionary
	_check("许可未核验时不会加载为可用", license_pending.get("status_code") == "license_unverified", str(license_pending))


func _make_sample(source_path: String, source_size: Vector2i) -> Dictionary:
	return {
		"id": "test_sample",
		"label": "测试样本",
		"source_path": source_path,
		"source_size": [source_size.x, source_size.y],
		"display_size": [48, 48],
		"approval_status": "approved",
		"provenance": "test_fixture",
		"license_status": "verified",
	}


func _array_to_size(value: Variant) -> Vector2i:
	if typeof(value) != TYPE_ARRAY:
		return Vector2i.ZERO
	var values: Array = value as Array
	if values.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(values[0]), int(values[1]))


func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		_fails.append(name + ("  [" + detail + "]" if detail != "" else ""))
		print("  ✗ " + name + ("  [" + detail + "]" if detail != "" else ""))
