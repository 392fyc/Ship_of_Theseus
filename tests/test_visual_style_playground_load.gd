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
	"asset_type",
	"source_path",
	"source_size",
	"display_size",
	"texture_filter",
	"alpha_required",
	"required_variants",
	"required_directions",
	"approval_status",
	"provenance",
	"provenance_status",
	"rights_basis",
	"rights_status",
]
const APPROVAL_STATUSES: Array[String] = ["pending_user_approval", "approved"]
const PROVENANCE_STATUSES: Array[String] = ["unverified", "verified"]
const RIGHTS_STATUSES: Array[String] = ["unverified", "review_required", "verified"]
const TEXTURE_FILTERS: Array[String] = ["nearest", "linear"]
const DIRECTIONS_NWSE: Array[String] = ["NW", "NE", "SW", "SE"]

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
	_check("样本清单版本为 2", manifest.get("version", 0) == 2)
	_check("样本清单声明 check_sizes", manifest.has("check_sizes"))
	var manifest_sizes_value: Variant = manifest.get("check_sizes", [])
	_check("清单包含且只包含三档检查尺寸", typeof(manifest_sizes_value) == TYPE_ARRAY)
	if typeof(manifest_sizes_value) == TYPE_ARRAY:
		var manifest_sizes: Array[Vector2i] = []
		for size_value: Variant in manifest_sizes_value as Array:
			manifest_sizes.append(_array_to_size(size_value))
		_check("三档检查尺寸与约定一致", manifest_sizes == EXPECTED_CHECK_SIZES, str(manifest_sizes))

	var samples_value: Variant = manifest.get("samples", [])
	_check("样本清单包含 samples 数组", typeof(samples_value) == TYPE_ARRAY)
	if typeof(samples_value) != TYPE_ARRAY:
		return

	var asset_types_value: Variant = manifest.get("asset_types", {})
	_check("样本清单包含 asset_types", typeof(asset_types_value) == TYPE_DICTIONARY)
	var asset_types: Dictionary = asset_types_value as Dictionary

	var samples: Array = samples_value as Array
	var actual_ids: Array[String] = []
	for sample_value: Variant in samples:
		if typeof(sample_value) != TYPE_DICTIONARY:
			_check("每个样本槽都是 JSON 对象", false, str(sample_value))
			continue
		var sample: Dictionary = sample_value as Dictionary
		var sample_id: String = str(sample.get("id", ""))
		actual_ids.append(sample_id)
		var asset_type: String = str(sample.get("asset_type", ""))
		var type_rules: Dictionary = asset_types.get(asset_type, {}) as Dictionary

		for field_name: String in REQUIRED_FIELDS:
			_check("样本槽 %s 包含字段 %s" % [sample_id, field_name], sample.has(field_name))
		_check("样本槽 %s asset_type 与 id 对齐" % sample_id, asset_type == sample_id)
		_check("样本槽 %s 具有对应类型规则" % sample_id, type_rules.size() > 0, str(asset_type))
		_check("样本槽 %s source_path 为空" % sample_id, str(sample.get("source_path", "missing")) == "")
		_check(
			"样本槽 %s approval_status 在允许枚举" % sample_id,
			APPROVAL_STATUSES.has(str(sample.get("approval_status", "")))
		)
		_check(
			"样本槽 %s provenance_status 在允许枚举" % sample_id,
			PROVENANCE_STATUSES.has(str(sample.get("provenance_status", "")))
		)
		_check(
			"样本槽 %s rights_status 在允许枚举" % sample_id,
			RIGHTS_STATUSES.has(str(sample.get("rights_status", "")))
		)

		var declared_source_size: Vector2i = _array_to_size(sample.get("source_size"))
		var declared_display_size: Vector2i = _array_to_size(sample.get("display_size"))
		_check("样本槽 %s 有效 source_size" % sample_id, declared_source_size.x > 0 and declared_source_size.y > 0)
		_check("样本槽 %s 有效 display_size" % sample_id, declared_display_size.x > 0 and declared_display_size.y > 0)
		_check("样本槽 %s texture_filter 枚举有效" % sample_id, TEXTURE_FILTERS.has(str(sample.get("texture_filter", ""))))
		_check("样本槽 %s alpha_required 是布尔值" % sample_id, typeof(sample.get("alpha_required", false)) == TYPE_BOOL)
		var required_variants: Array = sample.get("required_variants", [])
		var required_directions: Array = sample.get("required_directions", [])
		_check("样本槽 %s required_variants 是数组" % sample_id, typeof(required_variants) == TYPE_ARRAY)
		_check("样本槽 %s required_directions 是数组" % sample_id, typeof(required_directions) == TYPE_ARRAY)
		_check("样本槽 %s required_variants 为字符串" % sample_id, _array_is_string_list(required_variants))
		_check("样本槽 %s required_directions 为字符串" % sample_id, _array_is_string_list(required_directions))

		match sample_id:
			"ui":
				_check(
					"ui 变体至少包含 bottom_action_bar 与 tooltip",
					_array_contains_all(required_variants, ["bottom_action_bar", "tooltip"]),
					str(required_variants)
				)
			"portrait":
				_check(
					"portrait 变体恰含 single_weapon 与 dual_weapon",
					required_variants.size() == 2
					and required_variants.has("single_weapon")
					and required_variants.has("dual_weapon"),
					str(required_variants)
				)
			"map_token":
				_check(
					"map_token 变体恰含 single_weapon 与 dual_weapon",
					required_variants.size() == 2
					and required_variants.has("single_weapon")
					and required_variants.has("dual_weapon"),
					str(required_variants)
				)
				_check(
					"map_token 方向恰是 NW/NE/SW/SE",
					required_directions.size() == DIRECTIONS_NWSE.size()
					and _array_contains_all(required_directions, DIRECTIONS_NWSE),
					str(required_directions)
				)
			"terrain":
				_check(
					"terrain 变体至少包含 base_ground 与 transparent_overlay",
					required_variants.has("base_ground")
					and required_variants.has("transparent_overlay"),
					str(required_variants)
				)
				_check(
					"terrain 规则声明 tile_size 为 64×32",
					_array_to_size(type_rules.get("tile_size", [0, 0])) == Vector2i(64, 32)
				)
			"vfx":
				_check(
					"vfx 变体恰含 slash、movement、range、status",
					required_variants.size() == 4
					and required_variants.has("slash")
					and required_variants.has("movement")
					and required_variants.has("range")
					and required_variants.has("status"),
					str(required_variants)
				)
				_check(
					"vfx 规则声明为静态关键帧参考",
					type_rules.get("animation_type", "") == "static_keyframe"
				)

		_check(
			"样本槽 %s 规则的 texture_filter 与样本一致" % sample_id,
			type_rules.get("texture_filter", "") == str(sample.get("texture_filter", ""))
		)

		_check("样本槽 %s 规则的 alpha_required 与样本一致" % sample_id, type_rules.get("alpha_required", false) == bool(sample.get("alpha_required", false)))

	_check("样本槽顺序固定为五类视觉样本", actual_ids == EXPECTED_IDS, str(actual_ids))
	_check("不存在 combat_animation 槽", not actual_ids.has("combat_animation"))


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

	_check("根节点挂载脚本", instance.get_script() != null)
	_check("根节点挂载预期脚本", str(instance.get_script().resource_path) == SCRIPT_PATH, str(instance.get_script().resource_path))

	var sample_ids: Array = instance.call("get_sample_ids") as Array
	_check("运行时按清单构建五个样本槽", sample_ids == EXPECTED_IDS, str(sample_ids))

	for sample_id: String in EXPECTED_IDS:
		var current_state: Dictionary = instance.call("get_sample_state", sample_id) as Dictionary
		_check("当前样本槽 %s 运行状态为 pending_asset" % sample_id, current_state.get("status_code") == "pending_asset", str(current_state))
		var status_text: String = str(current_state.get("status_text", ""))
		_check("当前样本槽 %s 显示待提供" % sample_id, status_text.contains("待提供"), status_text)
		_check("当前样本槽 %s 显示待用户确认" % sample_id, status_text.contains("待用户确认"), status_text)
		_check("当前样本槽 %s 显示来源未核验" % sample_id, status_text.contains("来源未核验"), status_text)
		_check("当前样本槽 %s 显示使用权依据未核验" % sample_id, status_text.contains("使用权依据未核验"), status_text)
		_check("当前样本槽 %s 不伪造实际纹理尺寸" % sample_id, current_state.get("actual_texture_size") == Vector2i.ZERO, str(current_state))

	_check_sample_statuses(instance)

	_check("默认过滤方式为 Nearest", instance.call("get_filter_mode") == "nearest")
	instance.call("set_filter_mode", "nearest")
	await process_frame
	var nearest_previews: Array = instance.call("get_preview_nodes") as Array
	_check("能读取五个真实纹理预览控件", nearest_previews.size() == EXPECTED_IDS.size(), str(nearest_previews.size()))
	for preview_value: Variant in nearest_previews:
		var preview: TextureRect = preview_value as TextureRect
		_check(
			"Nearest 直接应用到每个 TextureRect",
			preview != null and preview.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
		)
	instance.call("set_filter_mode", "linear")
	await process_frame
	_check("能够切换到 Linear", instance.call("get_filter_mode") == "linear")
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
	_check("720p 检查画布实际包含五张卡", layout_metrics.get("card_count") == 5, str(layout_metrics))

	var map_state: Dictionary = instance.call("get_sample_state", "map_token") as Dictionary
	_check("战棋人物标注源尺寸 48×48", map_state.get("source_size") == Vector2i(48, 48), str(map_state))
	_check("战棋人物显示尺寸 48×48", map_state.get("display_size") == Vector2i(48, 48), str(map_state))

	var screenshot_target: String = str(instance.call("get_screenshot_target_path"))
	var second_screenshot_target: String = str(instance.call("get_screenshot_target_path"))
	_check(
		"截图目标严格位于 user://visual_style_playground/",
		screenshot_target.begins_with("user://visual_style_playground/"),
		screenshot_target
	)
	_check("同一毫秒连续生成截图名不会覆盖", screenshot_target != second_screenshot_target)

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

	var approved: Dictionary = _make_sample(TEXTURE_FIXTURE_PATH, actual_size)
	var usable: Dictionary = instance.call("inspect_sample", approved) as Dictionary
	_check("三道门全部通过时状态为可用", usable.get("status_code") == "usable", str(usable))

	var approval_pending_sample: Dictionary = _make_sample(TEXTURE_FIXTURE_PATH, actual_size)
	approval_pending_sample["approval_status"] = "pending_user_approval"
	var approval_pending: Dictionary = instance.call("inspect_sample", approval_pending_sample) as Dictionary
	_check("未获用户确认时状态码应为 approval_pending", approval_pending.get("status_code") == "approval_pending", str(approval_pending))

	var provenance_pending: Dictionary = _make_sample(TEXTURE_FIXTURE_PATH, actual_size)
	provenance_pending["provenance_status"] = "unverified"
	_check(
		"来源未核验时状态码应为 provenance_unverified",
		instance.call("inspect_sample", provenance_pending).get("status_code") == "provenance_unverified",
		str(instance.call("inspect_sample", provenance_pending))
	)

	var rights_review: Dictionary = _make_sample(TEXTURE_FIXTURE_PATH, actual_size)
	rights_review["rights_status"] = "review_required"
	_check(
		"使用权未核验时状态码应为 rights_review_required",
		instance.call("inspect_sample", rights_review).get("status_code") == "rights_review_required",
		str(instance.call("inspect_sample", rights_review))
	)

	var invalid_approval: Dictionary = _make_sample(TEXTURE_FIXTURE_PATH, actual_size)
	invalid_approval["approval_status"] = "forbidden_status"
	_check(
		"非法 approval_status 会进入 invalid_approval",
		instance.call("inspect_sample", invalid_approval).get("status_code") == "invalid_approval",
		str(instance.call("inspect_sample", invalid_approval))
	)

	var invalid_provenance: Dictionary = _make_sample(TEXTURE_FIXTURE_PATH, actual_size)
	invalid_provenance["provenance_status"] = "unknown"
	_check(
		"非法 provenance_status 会进入 invalid_provenance",
		instance.call("inspect_sample", invalid_provenance).get("status_code") == "invalid_provenance",
		str(instance.call("inspect_sample", invalid_provenance))
	)

	var invalid_rights: Dictionary = _make_sample(TEXTURE_FIXTURE_PATH, actual_size)
	invalid_rights["rights_status"] = "unknown"
	_check(
		"非法 rights_status 会进入 invalid_rights",
		instance.call("inspect_sample", invalid_rights).get("status_code") == "invalid_rights",
		str(instance.call("inspect_sample", invalid_rights))
	)


func _make_sample(source_path: String, source_size: Vector2i) -> Dictionary:
	return {
		"id": "test_sample",
		"label": "测试样本",
		"asset_type": "ui",
		"source_path": source_path,
		"source_size": [source_size.x, source_size.y],
		"display_size": [48, 48],
		"texture_filter": "nearest",
		"alpha_required": true,
		"required_variants": [],
		"required_directions": [],
		"approval_status": "approved",
		"provenance": "test_fixture",
		"provenance_status": "verified",
		"rights_basis": "self_created",
		"rights_status": "verified",
	}


func _array_is_string_list(values: Variant) -> bool:
	if typeof(values) != TYPE_ARRAY:
		return false
	var array_values: Array = values as Array
	for item: Variant in array_values:
		if typeof(item) != TYPE_STRING:
			return false
	return true


func _array_contains_all(values: Variant, required: Array[String]) -> bool:
	if typeof(values) != TYPE_ARRAY:
		return false
	var array_values: Array = values as Array
	for item: String in required:
		if not array_values.has(item):
			return false
	return true


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
