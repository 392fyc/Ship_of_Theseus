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
const EXPECTED_DISPLAY_SIZES: Dictionary = {
	"ui": Vector2i(210, 118),
	"portrait": Vector2i(128, 170),
	"map_token": Vector2i(140, 93),
	"terrain": Vector2i(140, 140),
	"vfx": Vector2i(140, 140),
}
const EXPECTED_APPROVED_PREVIEWS: Dictionary = {
	"ui": {
		"file_name": "ui_preview_final_v3.png",
		"sha256": "0c6f5a7bbc78b889f09e9dccc0423caaef3323bf6e5170314d333ad2c5bc64b6",
		"pixel_size": Vector2i(1774, 887),
	},
	"portrait": {
		"file_name": "portrait_preview_final.png",
		"sha256": "9f123a2022abe62472530ebd13ba43587802623c0db7ff7af711f5cec5be0cf3",
		"pixel_size": Vector2i(1254, 1254),
	},
	"map_token": {
		"file_name": "map_token_preview_final_v2.png",
		"sha256": "9c828acb5caa501a351c6628311f8d29692c9ca4454e1614dab891444b61637f",
		"pixel_size": Vector2i(1536, 1024),
	},
	"terrain": {
		"file_name": "terrain_preview_final.png",
		"sha256": "e40f2d6685d4543c91770768a8f837b0b238f73bd8e436d7438961a15c446b53",
		"pixel_size": Vector2i(1536, 1024),
	},
	"vfx": {
		"file_name": "vfx_preview_clean.png",
		"sha256": "e4542cc0d29cc7421d801d05177e653aa85012c1bd67b303c07c966ba04ed844",
		"pixel_size": Vector2i(1254, 1254),
	},
}
const APPROVED_PREVIEW_IDENTITY_SCOPE: String = "external_review_artifact"
const VERIFIED_PREVIEW_PROVENANCE: String = "Codex image_gen 生成；本地机械透明清理；SHA256 绑定。"
const VERIFIED_RIGHTS_BASIS: String = "KB 视觉裁决@f111e237:L45；2026-08-27 用户授权；仅限五个 approved_preview.sha256 原文件。"
const SAMPLE_DIRECTORY: String = "res://assets/prototype/visual_style/samples/"
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
	"approved_preview",
]
const REQUIRED_TYPE_FIELDS: Array[String] = [
	"texture_filter",
	"alpha_required",
	"required_variants",
	"required_directions",
]
const APPROVAL_STATUSES: Array[String] = ["pending_user_approval", "approved"]
const PROVENANCE_STATUSES: Array[String] = ["unverified", "verified"]
const RIGHTS_STATUSES: Array[String] = ["unverified", "review_required", "verified"]
const TEXTURE_FILTERS: Array[String] = ["nearest", "linear"]
const DIRECTIONS_NWSE: Array[String] = ["NW", "NE", "SW", "SE"]
const UI_VARIANTS_REQUIRED: Array[String] = ["bottom_action_bar"]
const PORTRAIT_VARIANTS_REQUIRED: Array[String] = ["single_weapon", "dual_weapon"]
const MAP_TOKEN_VARIANTS_REQUIRED: Array[String] = ["single_weapon", "dual_weapon"]
const TERRAIN_VARIANTS_REQUIRED: Array[String] = ["base_ground", "transparent_overlay"]
const VFX_VARIANTS_REQUIRED: Array[String] = ["slash", "movement", "range", "status"]
const GRIP_SHAPES_REQUIRED: Array[String] = [
	"traditional_chinese_sword",
	"western_sword",
	"long_tachi",
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
	_check("样本清单版本为 4", manifest.get("version", 0) == 4)
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
	_check("asset_types 覆盖五类类型", asset_types.size() == 5, str(asset_types.keys()))

	var samples: Array = samples_value as Array
	var actual_ids: Array[String] = []
	var sha256_pattern: RegEx = RegEx.new()
	_check("SHA256 格式检查器能编译", sha256_pattern.compile("^[0-9a-f]{64}$") == OK)
	for sample_value: Variant in samples:
		if typeof(sample_value) != TYPE_DICTIONARY:
			_check("每个样本槽都是 JSON 对象", false, str(sample_value))
			continue
		var sample: Dictionary = sample_value as Dictionary
		var sample_id: String = str(sample.get("id", ""))
		actual_ids.append(sample_id)
		var asset_type: String = str(sample.get("asset_type", ""))
		var type_rules: Dictionary = asset_types.get(asset_type, {}) as Dictionary
		var expected_preview: Dictionary = EXPECTED_APPROVED_PREVIEWS.get(sample_id, {}) as Dictionary

		_check("样本槽 %s 包含字段 asset_type" % sample_id, sample.has("asset_type"))
		for field_name: String in REQUIRED_FIELDS:
			_check("样本槽 %s 包含字段 %s" % [sample_id, field_name], sample.has(field_name))
		_check("样本槽 %s asset_type 与 id 对齐" % sample_id, asset_type == sample_id)
		_check("样本槽 %s 对应类型存在于 asset_types" % sample_id, type_rules.size() > 0, str(asset_type))
		if type_rules.size() == 0:
			continue

		var source_path: String = str(sample.get("source_path", ""))
		var expected_source_path: String = SAMPLE_DIRECTORY + str(expected_preview.get("file_name", ""))
		_check("样本槽 %s source_path 指向获批仓内 PNG" % sample_id, source_path == expected_source_path, source_path)
		_check("样本槽 %s source_path 是合法 res:// 路径" % sample_id, _is_valid_resource_path(source_path), source_path)
		for required_type_field: String in REQUIRED_TYPE_FIELDS:
			_check("类型规则 %s 包含字段 %s" % [sample_id, required_type_field], type_rules.has(required_type_field))

		var sample_source_size: Vector2i = _array_to_size(sample.get("source_size"))
		_check(
			"样本槽 %s source_size 与获批原文件一致" % sample_id,
			sample_source_size == expected_preview.get("pixel_size", Vector2i.ZERO),
			str(sample_source_size)
		)
		_check(
			"样本槽 %s 显示尺寸为约定基线" % sample_id,
			_array_to_size(sample.get("display_size")) == EXPECTED_DISPLAY_SIZES.get(sample_id, Vector2i.ZERO),
			str(sample.get("display_size"))
		)

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
		_check("样本槽 %s 已经用户逐文件批准" % sample_id, str(sample.get("approval_status", "")) == "approved")
		_check("样本槽 %s 预览来源已核验" % sample_id, str(sample.get("provenance_status", "")) == "verified")
		_check("样本槽 %s 预览来源说明与统一合同一致" % sample_id, str(sample.get("provenance", "")) == VERIFIED_PREVIEW_PROVENANCE)
		_check("样本槽 %s 使用权依据与 KB 授权一致" % sample_id, str(sample.get("rights_basis", "")) == VERIFIED_RIGHTS_BASIS)
		_check("样本槽 %s 使用权已经核验" % sample_id, str(sample.get("rights_status", "")) == "verified")

		var approved_preview_value: Variant = sample.get("approved_preview", {})
		_check("样本槽 %s approved_preview 是对象" % sample_id, typeof(approved_preview_value) == TYPE_DICTIONARY)
		var approved_preview: Dictionary = approved_preview_value as Dictionary
		_check("样本槽 %s 批准预览文件名精确" % sample_id, str(approved_preview.get("file_name", "")) == str(expected_preview.get("file_name", "")))
		var approved_sha256: String = str(approved_preview.get("sha256", ""))
		_check("样本槽 %s 批准预览 SHA256 精确" % sample_id, approved_sha256 == str(expected_preview.get("sha256", "")))
		_check("样本槽 %s 批准预览 SHA256 为 64 位小写十六进制" % sample_id, sha256_pattern.search(approved_sha256) != null, approved_sha256)
		_check("样本槽 %s 批准预览像素尺寸精确" % sample_id, _array_to_size(approved_preview.get("pixel_size", [])) == expected_preview.get("pixel_size", Vector2i.ZERO), str(approved_preview.get("pixel_size", [])))
		_check("样本槽 %s 批准预览仅是仓外审查工件" % sample_id, str(approved_preview.get("identity_scope", "")) == APPROVED_PREVIEW_IDENTITY_SCOPE)

		var source_exists: bool = FileAccess.file_exists(source_path)
		_check("样本槽 %s 仓内 PNG 存在" % sample_id, source_exists, source_path)
		if source_exists:
			var actual_sha256: String = FileAccess.get_sha256(source_path)
			_check("样本槽 %s 仓内字节与批准 SHA256 一致" % sample_id, actual_sha256 == approved_sha256, actual_sha256)
			var source_image: Image = Image.load_from_file(source_path)
			var image_loaded: bool = source_image != null and not source_image.is_empty()
			_check("样本槽 %s PNG 可由 Image 加载" % sample_id, image_loaded, source_path)
			if image_loaded:
				var image_size: Vector2i = Vector2i(source_image.get_width(), source_image.get_height())
				_check("样本槽 %s PNG 实际尺寸与清单一致" % sample_id, image_size == sample_source_size, str(image_size))
				_check("样本槽 %s PNG 为 RGBA8" % sample_id, source_image.get_format() == Image.FORMAT_RGBA8, str(source_image.get_format()))
				_check("样本槽 %s PNG 存在透明像素" % sample_id, source_image.detect_alpha() != Image.ALPHA_NONE, str(source_image.detect_alpha()))

		_check(
			"样本槽 %s texture_filter 在允许枚举" % sample_id,
			TEXTURE_FILTERS.has(str(sample.get("texture_filter", "")))
		)
		_check("样本槽 %s alpha_required 是布尔值" % sample_id, typeof(sample.get("alpha_required", false)) == TYPE_BOOL)
		var required_variants: Array = sample.get("required_variants", [])
		var required_directions: Array = sample.get("required_directions", [])
		_check("样本槽 %s required_variants 是字符串数组" % sample_id, _array_is_string_list(required_variants))
		_check("样本槽 %s required_directions 是字符串数组" % sample_id, _array_is_string_list(required_directions))

		_check(
			"样本槽 %s 与类型规则一致的 texture_filter" % sample_id,
			type_rules.get("texture_filter", "") == str(sample.get("texture_filter", ""))
		)
		_check(
			"样本槽 %s 与类型规则一致的 alpha_required" % sample_id,
			type_rules.get("alpha_required", false) == bool(sample.get("alpha_required", false))
		)
		_check(
			"样本槽 %s 与类型规则一致的 required_variants" % sample_id,
			_array_equal_required_order(required_variants, type_rules.get("required_variants", []))
		)
		_check(
			"样本槽 %s 与类型规则一致的 required_directions" % sample_id,
			_array_equal_required_order(required_directions, type_rules.get("required_directions", []))
		)

		match sample_id:
			"ui":
				_check("ui 变体包含 bottom_action_bar", _array_contains_all(required_variants, UI_VARIANTS_REQUIRED), str(required_variants))
				_check("ui 变体不包含 tooltip", not required_variants.has("tooltip"), str(required_variants))
				_check("ui 规则要求 nineslice_compatible", bool(type_rules.get("nineslice_compatible", false)))
				_check("ui 规则禁止烘焙文字", bool(type_rules.get("baked_text_forbidden", false)))
				_check("ui 规则说明深色哥特像素", str(type_rules.get("gothic_pixel_style", "")) == "subtle" or bool(type_rules.get("requires_gothic_pixel_style", false)))
				var bottom_bar_layout: Dictionary = type_rules.get("bottom_bar_layout", {}) as Dictionary
				_check("ui 底部栏固定在底部", str(bottom_bar_layout.get("placement", "")) == "fixed_bottom", str(bottom_bar_layout))
				_check(
					"ui 底部栏分区顺序固定",
					_array_equal_required_order(
						bottom_bar_layout.get("section_order", []),
						["character", "equipment", "skills", "relics", "end_turn"]
					),
					str(bottom_bar_layout.get("section_order", []))
				)
				_check("ui 底部栏不包含职业资源区", not bottom_bar_layout.has("class_resource"), str(bottom_bar_layout))
				var character_layout: Dictionary = bottom_bar_layout.get("character", {}) as Dictionary
				var character_groups: Array = character_layout.get("field_groups", []) as Array
				_check("ui 角色栏包含三个字段组", character_groups.size() == 3, str(character_groups))
				var profession_name_group: Dictionary = _dictionary_at(character_groups, 0)
				var level_experience_group: Dictionary = _dictionary_at(character_groups, 1)
				var health_shield_group: Dictionary = _dictionary_at(character_groups, 2)
				_check("ui 角色栏第一组是职业与名称", str(profession_name_group.get("id", "")) == "profession_and_name", str(profession_name_group))
				_check("ui 角色栏第二组是等级与经验", str(level_experience_group.get("id", "")) == "level_and_experience", str(level_experience_group))
				_check("ui 角色栏第三组是生命与护盾", str(health_shield_group.get("id", "")) == "health_and_shield", str(health_shield_group))
				_check("ui 生命与护盾共享外框", bool(health_shield_group.get("shared_outer_frame", false)), str(health_shield_group))
				var survival_bands: Array = health_shield_group.get("independent_bands", []) as Array
				_check(
					"ui 共享外框内保留生命与护盾两条独立状态带",
					survival_bands.size() == 2
						and str(_dictionary_at(survival_bands, 0).get("id", "")) == "health"
						and str(_dictionary_at(survival_bands, 1).get("id", "")) == "shield",
					str(survival_bands)
				)
				var equipment_layout: Dictionary = bottom_bar_layout.get("equipment", {}) as Dictionary
				_check(
					"ui 装备栏恰含武器与防具两槽",
					_array_equal_required_order(equipment_layout.get("slot_ids", []), ["weapon", "armor"]),
					str(equipment_layout)
				)
				_check("ui 武器与防具槽为 52×52 正方形", _array_to_size(equipment_layout.get("slot_size", [])) == Vector2i(52, 52), str(equipment_layout))
				var potion_layout: Dictionary = equipment_layout.get("universal_potion", {}) as Dictionary
				_check("ui 通用血瓶是装备栏内的独立按钮", str(potion_layout.get("role", "")) == "independent_button" and not bool(potion_layout.get("belongs_to_equipment_slot", true)), str(potion_layout))
				_check("ui 通用血瓶为 32×32 正方形", _array_to_size(potion_layout.get("size", [])) == Vector2i(32, 32), str(potion_layout))
				var skills_layout: Dictionary = bottom_bar_layout.get("skills", {}) as Dictionary
				_check("ui 技能栏水平平铺", str(skills_layout.get("layout", "")) == "horizontal", str(skills_layout))
				_check("ui 技能栏外框固定", bool(skills_layout.get("frame_size_fixed", false)), str(skills_layout))
				_check("ui 技能栏默认 6 格", int(skills_layout.get("default_slot_count", -1)) == 6, str(skills_layout))
				var supported_skill_range: Array = skills_layout.get("supported_slot_count_range", []) as Array
				_check(
					"ui 技能栏内部适配 5—7 格",
					supported_skill_range.size() == 2
						and int(supported_skill_range[0]) == 5
						and int(supported_skill_range[1]) == 7,
					str(skills_layout)
				)
				_check("ui 默认技能槽为 64×64 正方形", _array_to_size(skills_layout.get("default_slot_size", [])) == Vector2i(64, 64), str(skills_layout))
				var action_resource_layout: Dictionary = bottom_bar_layout.get("action_resource_bar", {}) as Dictionary
				_check(
					"ui 行动资源条独立置于技能栏上方",
					str(action_resource_layout.get("role", "")) == "independent_compact_bar"
						and str(action_resource_layout.get("placement", "")) == "above_skills"
						and not bool(action_resource_layout.get("belongs_to_bottom_sections", true)),
					str(action_resource_layout)
				)
				_check("ui 行动资源条不预留职业资源槽", not bool(action_resource_layout.get("profession_resource_slot_reserved", true)), str(action_resource_layout))
				var movement_resource_layout: Dictionary = action_resource_layout.get("movement_resource", {}) as Dictionary
				_check("ui 移动资源失效态只灰化", str(movement_resource_layout.get("disabled_visual", "")) == "grayed", str(movement_resource_layout))
				_check("ui 移动资源失效态没有斜杠", not bool(movement_resource_layout.get("slash_overlay", true)), str(movement_resource_layout))
				var relics_layout: Dictionary = bottom_bar_layout.get("relics", {}) as Dictionary
				_check("ui 遗物栏共 8 格", int(relics_layout.get("slot_count", -1)) == 8, str(relics_layout))
				_check("ui 遗物栏是 2 行", int(relics_layout.get("rows", -1)) == 2, str(relics_layout))
				_check("ui 遗物栏是 4 列", int(relics_layout.get("columns", -1)) == 4, str(relics_layout))
				_check("ui 遗物槽为 44×44 正方形", _array_to_size(relics_layout.get("slot_size", [])) == Vector2i(44, 44), str(relics_layout))
				var end_turn_layout: Dictionary = bottom_bar_layout.get("end_turn", {}) as Dictionary
				_check("ui 结束回合按钮为 52×52 正方形", _array_to_size(end_turn_layout.get("button_size", [])) == Vector2i(52, 52), str(end_turn_layout))
				_check("ui 不设常驻顶部提示面板", bool(bottom_bar_layout.get("persistent_top_tooltip", true)) == false, str(bottom_bar_layout))
				_check("ui 不设独立普通攻击按钮", bool(bottom_bar_layout.get("standalone_attack_button", true)) == false, str(bottom_bar_layout))
				_check("ui 不设独立移动按钮", bool(bottom_bar_layout.get("standalone_move_button", true)) == false, str(bottom_bar_layout))
			"portrait":
				_check(
					"portrait 变体恰含 single_weapon 与 dual_weapon",
					_array_equal_required_order(required_variants, PORTRAIT_VARIANTS_REQUIRED),
					str(required_variants)
				)
				_check("portrait 规则开启第三版统一参考", str(type_rules.get("style", "")) == "third_pass_consistent_look")
				_check("portrait 规则需真实握持", bool(type_rules.get("grip_required", false)))
				_check("portrait 规则允许三种剑形", _array_equal_required_order(type_rules.get("allowed_weapon_shapes", []), GRIP_SHAPES_REQUIRED))
			"map_token":
				_check(
					"map_token 变体恰含 single_weapon 与 dual_weapon",
					_array_equal_required_order(required_variants, MAP_TOKEN_VARIANTS_REQUIRED),
					str(required_variants)
				)
				_check(
					"map_token 方向顺序严格为 NW,NE,SW,SE",
					_array_equal_required_order(required_directions, DIRECTIONS_NWSE),
					str(required_directions)
				)
				_check("map_token 规则 frame_size 为 48×48", _array_to_size(type_rules.get("frame_size", [0, 0])) == Vector2i(48, 48))
				_check("map_token 代表板源尺寸不是类型级 48×48 帧", sample_source_size != _array_to_size(type_rules.get("frame_size", [0, 0])), str(sample_source_size))
				_check("map_token 代表板按 140×93 等比例显示", _array_to_size(sample.get("display_size", [])) == Vector2i(140, 93), str(sample.get("display_size", [])))
				_check("map_token 规则静态待机", bool(type_rules.get("static_idle_only", false)) and not bool(type_rules.get("combat_animation_required", true)))
			"terrain":
				_check("terrain 规则 tile_size 为 64×32", _array_to_size(type_rules.get("tile_size", [0, 0])) == Vector2i(64, 32))
				_check("terrain 规则比例 2:1", bool(type_rules.get("ratio_2_1", false)) or str(type_rules.get("ratio_2_to_1", "")) == "true" or bool(type_rules.get("tile_ratio_2_to_1", false)))
				_check(
					"terrain 变体至少包含 base_ground 与 transparent_overlay",
					_array_contains_all(required_variants, TERRAIN_VARIANTS_REQUIRED)
				)
				_check("terrain 规则支持无缝衔接", bool(type_rules.get("seamless_connections_required", false)))
				_check("terrain 规则区分基底与覆盖物", bool(type_rules.get("separate_base_and_overlay", false)))
			"vfx":
				_check(
					"vfx 变体恰含 slash、movement、range、status 且顺序稳定",
					_array_equal_required_order(required_variants, VFX_VARIANTS_REQUIRED),
					str(required_variants)
				)
				_check("vfx 规则为静态关键帧", str(type_rules.get("animation_type", "")) == "static_keyframe")
				_check("vfx 规则像素核心使用 nearest", str(type_rules.get("pixel_core_filter", "")) == "nearest")
				_check("vfx 规则核心与光晕分离", bool(type_rules.get("optional_glow_layer_separate", false)))
				_check("vfx 规则禁止循环", bool(type_rules.get("allow_loop", true)) == false)
				_check("vfx 规则不需要粒子系统", bool(type_rules.get("particle_system_required", true)) == false)
				_check("vfx 规则不需要战斗动画", bool(type_rules.get("combat_animation_required", true)) == false)
			_:
				_check("未识别样本 id %s 不应存在" % sample_id, false)

	var asset_type_required: Array[String] = ["ui", "portrait", "map_token", "terrain", "vfx"]
	var sample_has_asset_fields: Dictionary = {}
	for sample_id: String in asset_type_required:
		sample_has_asset_fields[sample_id] = false
	for sample_value: Variant in samples:
		if typeof(sample_value) != TYPE_DICTIONARY:
			continue
		sample_has_asset_fields[str(sample_value["id"])] = true
	for sample_id: String in asset_type_required:
		var rules: Dictionary = asset_types.get(sample_id, {}) as Dictionary
		_check("类型 %s 不应使用 source_size/display_size 字段" % sample_id, not rules.has("source_size") and not rules.has("display_size"), str(rules))
		_check("样本槽顺序固定为五类视觉样本", actual_ids == asset_type_required, str(actual_ids))
		_check("样本槽 %s 必须存在" % sample_id, sample_has_asset_fields.get(sample_id, false))

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
		_check("当前样本槽 %s 运行状态为 usable" % sample_id, current_state.get("status_code") == "usable", str(current_state))
		var status_text: String = str(current_state.get("status_text", ""))
		_check("当前样本槽 %s 精确显示可用" % sample_id, status_text == "可用", status_text)
		_check("当前样本槽 %s 三道门全部通过" % sample_id, bool(current_state.get("is_usable", false)), str(current_state))
		var expected_source_size: Vector2i = (EXPECTED_APPROVED_PREVIEWS.get(sample_id, {}) as Dictionary).get("pixel_size", Vector2i.ZERO) as Vector2i
		_check("当前样本槽 %s 实际纹理尺寸与源尺寸一致" % sample_id, current_state.get("actual_texture_size") == expected_source_size, str(current_state))
		_check("当前样本槽 %s 清单源尺寸与批准文件一致" % sample_id, current_state.get("source_size") == expected_source_size, str(current_state))
		var state_display_size: Vector2i = current_state.get("display_size", Vector2i.ZERO) as Vector2i
		_check(
			"当前样本槽 %s 显示尺寸与约定一致" % sample_id,
			state_display_size == EXPECTED_DISPLAY_SIZES.get(sample_id, Vector2i.ZERO),
			str(current_state)
		)

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
	_check("720p 检查五张卡同时可见", layout_metrics.get("all_cards_visible") == true, str(layout_metrics))

	var map_state: Dictionary = instance.call("get_sample_state", "map_token") as Dictionary
	_check("战棋人物代表板源尺寸为 1536×1024", map_state.get("source_size") == Vector2i(1536, 1024), str(map_state))
	_check("战棋人物代表板显示尺寸为 140×93", map_state.get("display_size") == Vector2i(140, 93), str(map_state))
	_check("战棋人物代表板不是 48×48 单帧", map_state.get("source_size") != Vector2i(48, 48), str(map_state))

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

	var empty_path_invalid_approval: Dictionary = instance.call(
		"inspect_sample", _make_sample("", Vector2i(48, 48), "forbidden_status")
	) as Dictionary
	_check("空 source_path + 非法 approval_status 命中 invalid_approval", empty_path_invalid_approval.get("status_code") == "invalid_approval", str(empty_path_invalid_approval))

	var empty_path_invalid_provenance: Dictionary = instance.call(
		"inspect_sample", _make_sample("", Vector2i(48, 48), "approved", "unknown")
	) as Dictionary
	_check("空 source_path + 非法 provenance_status 命中 invalid_provenance", empty_path_invalid_provenance.get("status_code") == "invalid_provenance", str(empty_path_invalid_provenance))

	var empty_path_invalid_rights: Dictionary = instance.call(
		"inspect_sample", _make_sample("", Vector2i(48, 48), "approved", "unverified", "unknown")
	) as Dictionary
	_check("空 source_path + 非法 rights_status 命中 invalid_rights", empty_path_invalid_rights.get("status_code") == "invalid_rights", str(empty_path_invalid_rights))

	var pending_then_invalid: Dictionary = instance.call(
		"inspect_sample", _make_sample(TEXTURE_FIXTURE_PATH, Vector2i(1024, 1024), "pending_user_approval", "verified", "mystery")
	) as Dictionary
	_check("一个门 pending 与后续非法不会遮蔽非法枚举", pending_then_invalid.get("status_code") == "invalid_rights", str(pending_then_invalid))

	var pending_provenance_verified_empty: Dictionary = instance.call(
		"inspect_sample", _make_sample(TEXTURE_FIXTURE_PATH, Vector2i(1024, 1024), "pending_user_approval", "verified", "verified", "")
	) as Dictionary
	_check(
		"approval pending + provenance verified 且 provenance 空会命中 invalid_provenance_basis",
		pending_provenance_verified_empty.get("status_code") == "invalid_provenance_basis",
		str(pending_provenance_verified_empty)
	)

	var pending_rights_verified_empty: Dictionary = instance.call(
		"inspect_sample", _make_sample(TEXTURE_FIXTURE_PATH, Vector2i(1024, 1024), "pending_user_approval", "verified", "verified", "provenance_ok", "")
	) as Dictionary
	_check(
		"approval pending + rights verified 且 rights_basis 空会命中 invalid_rights_basis",
		pending_rights_verified_empty.get("status_code") == "invalid_rights_basis",
		str(pending_rights_verified_empty)
	)

	var provenance_unverified_rights_verified_empty: Dictionary = instance.call(
		"inspect_sample", _make_sample(TEXTURE_FIXTURE_PATH, Vector2i(1024, 1024), "approved", "unverified", "verified", "provenance_ok", "")
	) as Dictionary
	_check(
		"provenance unverified + rights verified 且 rights_basis 空会命中 invalid_rights_basis",
		provenance_unverified_rights_verified_empty.get("status_code") == "invalid_rights_basis",
		str(provenance_unverified_rights_verified_empty)
	)

	var invalid_approval_issued: Dictionary = _make_sample(TEXTURE_FIXTURE_PATH, Vector2i(1024, 1024), "forbidden_status", "verified", "verified")
	invalid_approval_issued["provenance"] = "reviewed"
	var invalid_approval: Dictionary = instance.call("inspect_sample", invalid_approval_issued) as Dictionary
	_check("非法 approval_status 会进入 invalid_approval", invalid_approval.get("status_code") == "invalid_approval", str(invalid_approval))

	var invalid_provenance_issued: Dictionary = _make_sample(TEXTURE_FIXTURE_PATH, Vector2i(1024, 1024), "approved", "unknown", "verified")
	invalid_provenance_issued["provenance"] = "reviewed"
	var invalid_provenance: Dictionary = instance.call("inspect_sample", invalid_provenance_issued) as Dictionary
	_check("非法 provenance_status 会进入 invalid_provenance", invalid_provenance.get("status_code") == "invalid_provenance", str(invalid_provenance))

	var invalid_rights_issued: Dictionary = _make_sample(TEXTURE_FIXTURE_PATH, Vector2i(1024, 1024), "approved", "verified", "unknown")
	invalid_rights_issued["provenance"] = "reviewed"
	invalid_rights_issued["rights_basis"] = "self_created"
	var invalid_rights: Dictionary = instance.call("inspect_sample", invalid_rights_issued) as Dictionary
	_check("非法 rights_status 会进入 invalid_rights", invalid_rights.get("status_code") == "invalid_rights", str(invalid_rights))

	var invalid_provenance_basis_verified: Dictionary = _make_sample(TEXTURE_FIXTURE_PATH, Vector2i(1024, 1024), "approved", "verified", "verified")
	invalid_provenance_basis_verified["provenance"] = ""
	var invalid_basis: Dictionary = instance.call("inspect_sample", invalid_provenance_basis_verified) as Dictionary
	_check("provenance_status=verified 且 provenance 空将失败", invalid_basis.get("status_code") == "invalid_provenance_basis", str(invalid_basis))

	var invalid_rights_basis_verified: Dictionary = _make_sample(TEXTURE_FIXTURE_PATH, Vector2i(1024, 1024), "approved", "verified", "verified")
	invalid_rights_basis_verified["rights_basis"] = ""
	var invalid_rights_basis: Dictionary = instance.call("inspect_sample", invalid_rights_basis_verified) as Dictionary
	_check("rights_status=verified 且 rights_basis 空将失败", invalid_rights_basis.get("status_code") == "invalid_rights_basis", str(invalid_rights_basis))

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

	var approved: Dictionary = instance.call(
		"inspect_sample", _make_sample(TEXTURE_FIXTURE_PATH, actual_size, "approved", "verified", "verified", "reviewed", "approved")
	) as Dictionary
	_check("三道门全部通过时状态为可用", approved.get("status_code") == "usable", str(approved))

	var approval_pending: Dictionary = instance.call(
		"inspect_sample", _make_sample(TEXTURE_FIXTURE_PATH, actual_size, "pending_user_approval", "verified", "verified")
	) as Dictionary
	_check("未获用户确认时状态码应为 approval_pending", approval_pending.get("status_code") == "approval_pending", str(approval_pending))

	var provenance_pending: Dictionary = instance.call(
		"inspect_sample", _make_sample(TEXTURE_FIXTURE_PATH, actual_size, "approved", "unverified", "unverified")
	) as Dictionary
	_check("来源未核验时状态码应为 provenance_unverified", provenance_pending.get("status_code") == "provenance_unverified", str(provenance_pending))

	var rights_review_required: Dictionary = instance.call(
		"inspect_sample", _make_sample(TEXTURE_FIXTURE_PATH, actual_size, "approved", "verified", "review_required")
	) as Dictionary
	_check("使用权待核验时状态码应为 rights_review_required", rights_review_required.get("status_code") == "rights_review_required", str(rights_review_required))

	var path_missing_pending_parts_only_pending: Dictionary = instance.call(
		"inspect_sample", _make_sample("", Vector2i(1024, 1024), "approved", "verified", "verified", "provenance_ok", "rights_ok")
	) as Dictionary
	_check(
		"空路径 + approved/verified/verified 显示仅待提供",
		path_missing_pending_parts_only_pending.get("status_code") == "pending_asset"
		and str(path_missing_pending_parts_only_pending.get("status_text")).strip_edges() == "待提供",
		str(path_missing_pending_parts_only_pending)
	)


func _make_sample(
	source_path: String,
	source_size: Vector2i,
	approval_status: String = "approved",
	provenance_status: String = "verified",
	rights_status: String = "verified",
	provenance: String = "provenance_basis",
	rights_basis: String = "rights_basis"
) -> Dictionary:
	return {
		"id": "test_sample",
		"label": "测试样本",
		"asset_type": "ui",
		"source_path": source_path,
		"source_size": [source_size.x, source_size.y],
		"display_size": [48, 48],
		"texture_filter": "nearest",
		"alpha_required": true,
		"required_variants": ["single_weapon", "dual_weapon"],
		"required_directions": [],
		"approval_status": approval_status,
		"provenance": provenance,
		"provenance_status": provenance_status,
		"rights_basis": rights_basis,
		"rights_status": rights_status,
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


func _array_equal_required_order(values: Variant, required: Variant) -> bool:
	if typeof(values) != TYPE_ARRAY or typeof(required) != TYPE_ARRAY:
		return false
	var expected: Array = required as Array
	var actual: Array = values as Array
	if actual.size() != expected.size():
		return false
	for i: int in range(expected.size()):
		if str(actual[i]) != str(expected[i]):
			return false
	return true


func _array_to_size(value: Variant) -> Vector2i:
	if typeof(value) != TYPE_ARRAY:
		return Vector2i.ZERO
	var values: Array = value as Array
	if values.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(values[0]), int(values[1]))


func _dictionary_at(values: Array, index: int) -> Dictionary:
	if index < 0 or index >= values.size() or typeof(values[index]) != TYPE_DICTIONARY:
		return {}
	return values[index] as Dictionary


func _is_valid_resource_path(source_path: String) -> bool:
	return (
		source_path.begins_with(SAMPLE_DIRECTORY)
		and source_path.ends_with(".png")
		and not source_path.contains("\\")
		and not source_path.contains("..")
	)


func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		_fails.append(name + ("  [" + detail + "]" if detail != "" else ""))
		print("  ✗ " + name + ("  [" + detail + "]" if detail != "" else ""))
