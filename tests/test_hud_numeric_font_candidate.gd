extends SceneTree

const FONT_PATH: String = "res://assets/fonts/ibm_plex_mono/IBMPlexMono-SemiBold.ttf"
const LICENSE_PATH: String = "res://assets/fonts/ibm_plex_mono/LICENSE.txt"
const SOURCE_PATH: String = "res://assets/fonts/ibm_plex_mono/source.json"
const SCENE_PATH: String = "res://scenes/dev/hud_numeric_font_candidate_gallery.tscn"
const HUD_PREVIEW_SCENE_PATH: String = "res://scenes/dev/hud_bottom_numeric_font_preview.tscn"
const GHV5_SCENE_PATH: String = "res://scenes/dev/hud_bottom_dynamic_states_gallery.tscn"
const OFFICIAL_RELEASE_URL: String = "https://github.com/IBM/plex/releases/tag/%40ibm%2Fplex-mono%402.5.0"
const EXPECTED_ZIP_SHA256: String = "6d23f01257663d8cc49a0d64c22ced630b79e0e2a0ac08a0da86e9a38bbc481c"
const EXPECTED_SAMPLES: Array[String] = [
	"000000/000000",
	"666666/666666",
	"888888/888888",
	"999999/999999",
	"123456/654321",
]

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_hud_numeric_font_candidate ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var files_present: bool = FileAccess.file_exists(FONT_PATH) \
		and FileAccess.file_exists(LICENSE_PATH) \
		and FileAccess.file_exists(SOURCE_PATH)
	_check("字体、许可和来源清单存在", files_present)
	if not files_present:
		_finish()
		return

	var source_text: String = FileAccess.get_file_as_string(SOURCE_PATH)
	var source_value: Variant = JSON.parse_string(source_text)
	_check("来源清单是 JSON 对象", source_value is Dictionary)
	if not source_value is Dictionary:
		_finish()
		return
	var source: Dictionary = source_value as Dictionary
	_eq("来源版本固定", source.get("version"), "@ibm/plex-mono@2.5.0")
	_eq("字体版本标记日期单独记录", source.get("font_version_date"), "2026-04-21")
	_eq("GitHub Release 发布时间单独记录", source.get("release_published_at"),
		"2026-06-11T19:24:51Z")
	_eq("来源指向官方发布页", source.get("release_url"), OFFICIAL_RELEASE_URL)
	_eq("官方 ZIP 哈希登记", source.get("zip_sha256"), EXPECTED_ZIP_SHA256)
	_eq("字体哈希与实物一致", source.get("font_sha256"), _sha256(FONT_PATH))
	_eq("许可哈希与实物一致", source.get("license_sha256"), _sha256(LICENSE_PATH))
	_check("取得日期有记录", str(source.get("retrieved_at", "")) != "")

	var license_text: String = FileAccess.get_file_as_string(LICENSE_PATH)
	_check("许可文本含 SIL OFL 1.1", "SIL OPEN FONT LICENSE Version 1.1" in license_text)
	_check("许可文本保留 Plex 字体名", "Reserved Font Name \"Plex\"" in license_text)

	var candidate: FontFile = load(FONT_PATH) as FontFile
	_check("静态 TTF 可加载为 FontFile", candidate != null)
	if candidate != null:
		_check("候选未启用 MSDF", not candidate.multichannel_signed_distance_field)
		_eq("候选使用灰度抗锯齿", int(candidate.get("antialiasing")), 1)
		_eq("候选使用 Light hinting", int(candidate.get("hinting")), 1)
		_eq("候选使用 Auto 子像素定位", int(candidate.get("subpixel_positioning")), 1)
		_check("候选未生成 mipmap", not bool(candidate.get("generate_mipmaps")))
		_eq("候选沿用视口 oversampling", float(candidate.get("oversampling")), 0.0)
		var required_glyphs: String = "0123456789/"
		for glyph_index: int in required_glyphs.length():
			var codepoint: int = required_glyphs.unicode_at(glyph_index)
			_check("候选自身包含字符 %s" % required_glyphs[glyph_index],
				candidate.has_char(codepoint))
		_check("候选提供字体元数据接口", candidate.has_method("get_font_name")
			and candidate.has_method("get_font_style_name")
			and candidate.has_method("get_font_weight"))
		_eq("候选字体内部家族", candidate.call("get_font_name"), "IBM Plex Mono SmBld")
		_eq("候选字体样式", candidate.call("get_font_style_name"), "SemiBold")
		_eq("候选字体字重", candidate.call("get_font_weight"), 600)

	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_check("字体候选画廊存在", packed != null)
	if packed == null:
		_finish()
		return
	var gallery: Control = packed.instantiate() as Control
	_check("字体候选画廊可实例化", gallery != null)
	if gallery == null:
		_finish()
		return
	root.add_child(gallery)
	await process_frame
	await process_frame
	_test_gallery(gallery, candidate)
	gallery.queue_free()
	await process_frame
	await _test_hud_preview(candidate)
	_finish()


func _test_gallery(gallery: Control, candidate: FontFile) -> void:
	_eq("画廊固定为 1280×720", gallery.size, Vector2(1280, 720))
	_check("画廊提供样本接口", gallery.has_method("get_sample_strings")
		and gallery.has_method("get_reference_labels")
		and gallery.has_method("get_candidate_labels"))
	if not gallery.has_method("get_sample_strings"):
		return
	_eq("画廊只使用规定数值样本", gallery.call("get_sample_strings"), EXPECTED_SAMPLES)
	var reference_labels: Array = gallery.call("get_reference_labels") as Array
	var candidate_labels: Array = gallery.call("get_candidate_labels") as Array
	_eq("两列各含一个常规、五个长值和一个辨识样本", reference_labels.size(), 7)
	_eq("候选列数量与参考列一致", candidate_labels.size(), reference_labels.size())
	if reference_labels.size() != 7 or candidate_labels.size() != 7:
		return
	for index: int in reference_labels.size():
		var reference: Label = reference_labels[index] as Label
		var proposed: Label = candidate_labels[index] as Label
		_check("参考标签 %d 存在" % index, reference != null)
		_check("候选标签 %d 存在" % index, proposed != null)
		if reference == null or proposed == null:
			continue
		_eq("两列样本 %d 相同" % index, proposed.text, reference.text)
		_eq("两列样本 %d 尺寸相同" % index, proposed.size, reference.size)
		_eq("两列样本 %d 右边界相同" % index,
			proposed.global_position.x + proposed.size.x,
			reference.global_position.x + reference.size.x + 424.0)
		_eq("两列样本 %d 均右对齐" % index,
			[reference.horizontal_alignment, proposed.horizontal_alignment],
			[HORIZONTAL_ALIGNMENT_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT])
		_check("候选标签 %d 使用 IBM Plex 文件" % index,
			proposed.get_theme_font(&"font") == candidate)
		_check("参考标签 %d 不覆盖字体" % index,
			not reference.has_theme_font_override(&"font"))
		_eq("两列样本 %d 字号一致" % index,
			proposed.get_theme_font_size(&"font_size"),
			reference.get_theme_font_size(&"font_size"))
		_check("两列样本 %d 均限制在标签边界" % index,
			reference.clip_text and proposed.clip_text)
		var rendered_width: float = proposed.get_theme_font(&"font").get_string_size(
			proposed.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			proposed.get_theme_font_size(&"font_size")).x
		_check("候选样本 %d 不依赖裁切隐藏字符" % index,
			rendered_width <= proposed.size.x + 0.01,
			"rendered=%s label=%s" % [str(rendered_width), str(proposed.size.x)])
	_eq("常规样本文字", (candidate_labels[0] as Label).text, "34/100")
	_eq("普通样本使用 8px", (candidate_labels[0] as Label).get_theme_font_size(&"font_size"), 8)
	for index: int in range(1, 6):
		_eq("长值样本 %d 使用 7px" % index,
			(candidate_labels[index] as Label).get_theme_font_size(&"font_size"), 7)
	_eq("辨识样本完整", (candidate_labels[6] as Label).text, "0 1 6 7 8 9 /")
	_eq("辨识样本使用 8px", (candidate_labels[6] as Label).get_theme_font_size(&"font_size"), 8)


func _test_hud_preview(candidate: FontFile) -> void:
	var packed: PackedScene = load(HUD_PREVIEW_SCENE_PATH) as PackedScene
	_check("实际 HUD 字体预览存在", packed != null)
	if packed == null:
		return
	var preview: Control = packed.instantiate() as Control
	_check("实际 HUD 字体预览可实例化", preview != null)
	if preview == null:
		return
	root.add_child(preview)
	await process_frame
	await process_frame
	_eq("实际预览只复用一个 GHV-5 画廊", preview.get_child_count(), 1)
	var base: Control = preview.get_node_or_null("BaseGallery") as Control
	_check("实际预览复用 GHV-5 原场景", base != null
		and base.scene_file_path == GHV5_SCENE_PATH)
	if base != null:
		_eq("实际预览固定使用长值状态", base.call("get_state_id"),
			&"capacity_2_early_move_lock_long_values")
	var values: Array = preview.call("get_value_labels") as Array
	_eq("实际预览只覆盖 XP、HP、SH 三个数值", values.size(), 3)
	for index: int in values.size():
		var label: Label = values[index] as Label
		_check("实际预览数值 %d 存在" % index, label != null)
		if label == null:
			continue
		_eq("实际预览数值 %d 保留长值" % index, label.text, "999999/999999")
		_eq("实际预览数值 %d 使用现行 9px 长值策略" % index,
			label.get_theme_font_size(&"font_size"), 9)
		_check("实际预览数值 %d 局部使用候选字体" % index,
			label.get_theme_font(&"font") == candidate
			and label.has_theme_font_override(&"font"))
	if base != null:
		var identity: Label = base.get_node(
			"BaseGallery/DesignRoot/BottomHudComposition/BottomRow/CharacterHudPanel/"
			+ "Margin/ContentRow/InfoColumn/IdentityLabel") as Label
		_check("实际预览不替换身份栏字体",
			not identity.has_theme_font_override(&"font"))
	preview.queue_free()
	await process_frame


func _sha256(path: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()


func _finish() -> void:
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for failure: String in _fails:
			print("  ✗ " + failure)
	else:
		print("OK")
	quit(0 if _fail == 0 else 1)


func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  ✓ " + name)
		return
	_fail += 1
	_fails.append(name + ("  [" + detail + "]" if detail != "" else ""))
	print("  ✗ " + name + ("  [" + detail + "]" if detail != "" else ""))


func _eq(name: String, actual: Variant, expected: Variant) -> void:
	_check(name, actual == expected, "期望 %s 实际 %s" % [str(expected), str(actual)])
