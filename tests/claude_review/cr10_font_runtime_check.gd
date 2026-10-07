extends SceneTree

const FONT_MANIFEST_PATH := "res://assets/fonts/noto_sans_cjk_sc/source.json"
const CJK_FONT_PATH := "res://assets/fonts/noto_sans_cjk_sc/NotoSansCJKsc-Regular-subset.otf"
const SYMBOLS2_FONT_PATH := "res://assets/fonts/noto_sans_symbols/NotoSansSymbols2-Regular-subset.ttf"
const SYMBOLS_FONT_PATH := "res://assets/fonts/noto_sans_symbols/NotoSansSymbols-Regular-subset.ttf"
const EMOJI_FONT_PATH := "res://assets/fonts/noto_emoji/NotoEmoji-Regular-400-subset.ttf"
const IBM_PLEX_PATH := "res://assets/fonts/ibm_plex_mono/IBMPlexMono-SemiBold.ttf"
const SOURCE_SANS_PATH := "res://assets/fonts/source_sans_pro/SourceSansPro-Semibold.ttf"
const EXPECTED_FALLBACK_PATHS := [CJK_FONT_PATH, SYMBOLS2_FONT_PATH, SYMBOLS_FONT_PATH, EMOJI_FONT_PATH]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var manifest_text := FileAccess.get_file_as_string(FONT_MANIFEST_PATH)
	_check(not manifest_text.is_empty(), "CJK source manifest is readable")
	var manifest_value: Variant = JSON.parse_string(manifest_text)
	_check(manifest_value is Dictionary, "CJK source manifest is valid JSON")
	if not manifest_value is Dictionary:
		_finish()
		return

	var subset: Dictionary = manifest_value.get("subset", {})
	var codepoints: Array = subset.get("required_codepoints", [])
	_check(int(subset.get("gb2312_character_count", 0)) == 7445, "manifest records the complete GB2312 set")
	_check(codepoints.size() == int(subset.get("unique_character_count", -1)), "manifest Unicode list count matches its declared count")

	var cjk := load(CJK_FONT_PATH) as FontFile
	var symbols2 := load(SYMBOLS2_FONT_PATH) as FontFile
	var symbols := load(SYMBOLS_FONT_PATH) as FontFile
	var emoji := load(EMOJI_FONT_PATH) as FontFile
	var cjk_m2 := load("res://assets/ui/themes/hud_m2_cjk_font.tres") as FontFile
	var expected_files: Array[FontFile] = [cjk, symbols2, symbols, emoji]
	for index in expected_files.size():
		var font := expected_files[index]
		_check(font != null, "bundled fallback %d loads" % index)
		if font != null:
			_check(not font.allow_system_fallback, "bundled fallback %d disables system fallback" % index)
		_check(font != null and font.fallbacks.is_empty(), "raw bundled fallback %d has no nested resource cycle" % index)

	var default_font := ThemeDB.fallback_font as FontFile
	_check(default_font != null, "ThemeDB default font remains a FontFile")
	_check_fallback_order(default_font, EXPECTED_FALLBACK_PATHS, "ThemeDB fallback")
	_check_coverage(default_font, codepoints, "ThemeDB fallback")
	_check(not _font_chain_has_cycle(default_font, {}, {}), "ThemeDB fallback chain has no resource cycle")

	var ordinary_label := Label.new()
	root.add_child(ordinary_label)
	var ordinary_font := ordinary_label.get_theme_font("font")
	_check(ordinary_font != null, "ordinary Label resolves a default theme font")
	var project_theme := load("res://assets/ui/themes/default_font.tres") as Theme
	var project_default_font: FontFile = null
	if project_theme != null:
		project_default_font = project_theme.default_font as FontFile
	_check(project_default_font != null and default_font != null and project_default_font.data == default_font.data, "ordinary theme uses the existing default Latin font data")
	_check_coverage(ordinary_font, codepoints, "ordinary Label theme font")
	_check_system_fallback_disabled(ordinary_font, "ordinary Label theme font")
	_check(not _font_chain_has_cycle(ordinary_font, {}, {}), "ordinary Label fallback chain has no resource cycle")
	_check(ordinary_font.has_char(65), "ordinary Label retains the existing Latin character data")
	_emit_text_metrics("ordinary_default", ordinary_font, ["命中 100%", "暴击 25%", "必定生效"], 9)
	var ordinary_button := Button.new()
	root.add_child(ordinary_button)
	var ordinary_button_font := ordinary_button.get_theme_font("font")
	_check(ordinary_button_font != null, "ordinary Button resolves a default theme font")
	_check_coverage(ordinary_button_font, codepoints, "ordinary Button theme font")
	_check_system_fallback_disabled(ordinary_button_font, "ordinary Button theme font")
	_check(not _font_chain_has_cycle(ordinary_button_font, {}, {}), "ordinary Button fallback chain has no resource cycle")
	_check(ordinary_button_font.has_char(65), "ordinary Button retains the existing Latin character data")

	var hud_theme := load("res://assets/ui/themes/hud_m2.tres") as Theme
	_check(hud_theme != null, "M2 theme loads")
	if hud_theme != null:
		var hud_default := hud_theme.default_font
		_check_coverage(hud_default, codepoints, "M2 default text font")
		_check_system_fallback_disabled(hud_default, "M2 default text font")
		_check(not _font_chain_has_cycle(hud_default, {}, {}), "M2 default text fallback chain has no resource cycle")
		_check(hud_default.has_char(65), "M2 default text font retains the existing Latin character data")
		_emit_text_metrics("m2_default", hud_default, ["命中 100%", "暴击 25%", "必定生效"], 9)
		var numeric_font := hud_theme.get_font("font", "HudM2NumericLabel")
		_check_coverage(numeric_font, codepoints, "M2 numeric font")
		_check_system_fallback_disabled(numeric_font, "M2 numeric font")
		_check(numeric_font.has_char(65), "M2 numeric font retains its existing Latin font data")
		_emit_text_metrics("m2_numeric", numeric_font, ["命中 100%", "暴击 25%", "必定生效"], 9)
		var frozen_font := hud_theme.get_font("number", "HudM2FrozenResource") as FontVariation
		_check(frozen_font != null, "frozen resource numbers retain a FontVariation wrapper")
		if frozen_font != null:
			var frozen_base := frozen_font.base_font as FontFile
			var source_sans := load(SOURCE_SANS_PATH) as FontFile
			_check(frozen_base != null and source_sans != null and frozen_base.data == source_sans.data, "frozen number Latin data is unchanged")
			_check(not source_sans.allow_system_fallback, "Source Sans Pro import disables system fallback")
			_check(not source_sans.multichannel_signed_distance_field, "frozen number source keeps its raster font settings")
			_check(frozen_font.fallbacks.is_empty(), "frozen number font does not inherit unrelated fallback metrics")
			_check(is_equal_approx(frozen_font.get_ascent(32), source_sans.get_ascent(32)), "frozen number ascent matches the existing Source Sans Pro metrics")
			_check(is_equal_approx(frozen_font.get_descent(32), source_sans.get_descent(32)), "frozen number descent matches the existing Source Sans Pro metrics")
			_check(is_equal_approx(frozen_font.get_height(32), source_sans.get_height(32)), "frozen number height matches the existing Source Sans Pro metrics")
			_check(is_equal_approx(frozen_font.get_string_size("100", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x, source_sans.get_string_size("100", HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x), "frozen number width matches the existing Source Sans Pro metrics")
			_check_system_fallback_disabled(frozen_base, "frozen resource number source font")

	var numeric_wrapper := load("res://assets/ui/themes/hud_m2_fonts.tres") as FontFile
	var ibm_plex := load(IBM_PLEX_PATH) as FontFile
	_check(numeric_wrapper != null and ibm_plex != null and numeric_wrapper.data == ibm_plex.data, "M2 numeric Latin font data is unchanged")
	_check(ibm_plex != null and not ibm_plex.allow_system_fallback, "IBM Plex Mono import disables system fallback")
	var structure_theme := load("res://assets/ui/themes/hud_structure_prototype.tres") as Theme
	var structure_numeric_font := structure_theme.get_font("font", "HudMeterValueLabel") if structure_theme != null else null
	_check_coverage(structure_numeric_font, codepoints, "prototype HUD numeric label font")
	_check_system_fallback_disabled(structure_numeric_font, "prototype HUD numeric label font")
	_check(structure_numeric_font is FontFile and (structure_numeric_font as FontFile).data == ibm_plex.data, "prototype HUD numeric labels preserve the IBM Plex Mono Latin font")
	_check_coverage(cjk_m2, codepoints, "M2 MSDF CJK fallback")
	_check(cjk_m2 != null and cjk_m2.multichannel_signed_distance_field, "M2 CJK fallback has MSDF enabled for scaled HUD text")
	_check(not _font_chain_has_cycle(cjk_m2, {}, {}), "M2 CJK fallback chain has no resource cycle")
	_check_coverage(numeric_wrapper, codepoints, "M2 numeric wrapper")

	var cjk_resource := load(CJK_FONT_PATH) as FontFile
	var symbol2_resource := load(SYMBOLS2_FONT_PATH) as FontFile
	var symbol_resource := load(SYMBOLS_FONT_PATH) as FontFile
	var emoji_resource := load(EMOJI_FONT_PATH) as FontFile
	for point_variant in codepoints:
		var point := int(point_variant)
		var found := false
		for font in [cjk_resource, symbol2_resource, symbol_resource, emoji_resource]:
			if font != null and font.has_char(point):
				found = true
				break
		if not found:
			_fail("package font union is missing U+%04X" % point)

	var imported_plex := load(IBM_PLEX_PATH) as FontFile
	var imported_source_sans := load(SOURCE_SANS_PATH) as FontFile
	_check(imported_plex != null and not imported_plex.allow_system_fallback, "importer default applies to IBM Plex Mono source")
	_check(imported_source_sans != null and not imported_source_sans.allow_system_fallback, "importer default applies to Source Sans Pro source")
	_finish()


func _check_fallback_order(font: FontFile, expected_paths: Array, label: String) -> void:
	if font == null:
		return
	var fallbacks := font.fallbacks
	_check(fallbacks.size() == expected_paths.size(), "%s has the complete bundled fallback list" % label)
	for index in mini(fallbacks.size(), expected_paths.size()):
		_check(fallbacks[index].resource_path == expected_paths[index], "%s fallback %d order is stable" % [label, index])


func _check_coverage(font: Font, codepoints: Array, label: String) -> void:
	if font == null:
		return
	var missing: Array[int] = []
	for point_variant in codepoints:
		var point := int(point_variant)
		if not _font_chain_has_char(font, point, {}):
			missing.append(point)
	if not missing.is_empty():
		var sample: Array[String] = []
		for index in mini(missing.size(), 12):
			sample.append("U+%04X" % missing[index])
		var suffix := " ..." if missing.size() > sample.size() else ""
		_fail("%s is missing %d codepoints: %s%s" % [label, missing.size(), ", ".join(sample), suffix])


func _font_chain_has_char(font: Font, point: int, visited: Dictionary) -> bool:
	if font == null:
		return false
	var instance_id := font.get_instance_id()
	if visited.has(instance_id):
		return false
	visited[instance_id] = true
	if font.has_char(point):
		return true
	for fallback in font.fallbacks:
		if _font_chain_has_char(fallback, point, visited):
			return true
	return false


func _font_chain_has_cycle(font: Font, active: Dictionary, visited: Dictionary) -> bool:
	if font == null:
		return false
	var instance_id := font.get_instance_id()
	if active.has(instance_id):
		return true
	if visited.has(instance_id):
		return false
	active[instance_id] = true
	for fallback in font.fallbacks:
		if _font_chain_has_cycle(fallback, active, visited):
			return true
	active.erase(instance_id)
	visited[instance_id] = true
	return false


func _check_system_fallback_disabled(font: Font, label: String) -> void:
	_check_system_fallback_disabled_recursive(font, label, {})


func _check_system_fallback_disabled_recursive(font: Font, label: String, visited: Dictionary) -> void:
	if font == null:
		return
	var instance_id := font.get_instance_id()
	if visited.has(instance_id):
		return
	visited[instance_id] = true
	if font is FontFile:
		_check(not (font as FontFile).allow_system_fallback, "%s disables system fallback" % label)
	for fallback in font.fallbacks:
		_check_system_fallback_disabled_recursive(fallback, "%s child fallback" % label, visited)


func _emit_text_metrics(label: String, font: Font, samples: Array[String], size: int) -> void:
	if font == null:
		return
	var primary := font.duplicate(true) as Font
	if primary != null:
		primary.fallbacks = []
	var rows: Array[String] = []
	for sample in samples:
		var with_fallback := font.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		var without_fallback := primary.get_string_size(sample, HORIZONTAL_ALIGNMENT_LEFT, -1, size) if primary != null else Vector2.ZERO
		rows.append("%s=%s/%s" % [sample, str(with_fallback), str(without_fallback)])
	print("CR10_TEXT_METRICS %s ascent=%.3f descent=%.3f height=%.3f primary_ascent=%.3f primary_descent=%.3f primary_height=%.3f samples=%s" % [label, font.get_ascent(size), font.get_descent(size), font.get_height(size), primary.get_ascent(size) if primary != null else -1.0, primary.get_descent(size) if primary != null else -1.0, primary.get_height(size) if primary != null else -1.0, ";".join(rows)])


func _check(condition: bool, label: String) -> void:
	if not condition:
		_fail(label)


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("CR10_FONT_RUNTIME_FAIL " + message)


func _finish() -> void:
	if _failures.is_empty():
		print("CR10_FONT_RUNTIME_RESULT failed=0")
		quit(0)
	else:
		print("CR10_FONT_RUNTIME_RESULT failed=%d" % _failures.size())
		quit(1)
