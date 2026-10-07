extends SceneTree

const FONT_MANIFEST_PATH := "res://assets/fonts/noto_sans_cjk_sc/source.json"
const CJK_REGULAR_FONT_PATH := "res://assets/fonts/noto_sans_cjk_sc/NotoSansCJKsc-Regular-subset.otf"
const CJK_MEDIUM_FONT_PATH := "res://assets/fonts/noto_sans_cjk_sc/NotoSansCJKsc-Medium-subset.otf"
const CJK_BOLD_FONT_PATH := "res://assets/fonts/noto_sans_cjk_sc/NotoSansCJKsc-Bold-subset.otf"
const SYMBOLS2_FONT_PATH := "res://assets/fonts/noto_sans_symbols/NotoSansSymbols2-Regular-subset.ttf"
const SYMBOLS_FONT_PATH := "res://assets/fonts/noto_sans_symbols/NotoSansSymbols-Regular-subset.ttf"
const EMOJI_FONT_PATH := "res://assets/fonts/noto_emoji/NotoEmoji-Regular-400-subset.ttf"
const M2_CJK_FONT_PATH := "res://assets/ui/themes/hud_m2_cjk_font.tres"
const M2_CJK_BOLD_FONT_PATH := "res://assets/ui/themes/hud_m2_cjk_bold_font.tres"
const M2_TITLE_FONT_PATH := "res://assets/ui/themes/hud_m2_title_font.tres"
const M2_THEME_PATH := "res://assets/ui/themes/hud_m2.tres"
const M2_NUMERIC_FONT_PATH := "res://assets/ui/themes/hud_m2_fonts.tres"
const PROJECT_THEME_PATH := "res://assets/ui/themes/default_font.tres"
const IBM_PLEX_PATH := "res://assets/fonts/ibm_plex_mono/IBMPlexMono-SemiBold.ttf"
const SOURCE_SANS_PATH := "res://assets/fonts/source_sans_pro/SourceSansPro-Semibold.ttf"
const CJK_METRIC_CACHE_SIZES: Array[int] = [8, 9, 10, 11, 12, 13, 14, 16, 20]
const HudFontSetup := preload("res://scripts/ui/hud/m2/hud_font_setup.gd")

var _failures: Array[String] = []


static func configure_capture_weight(weight: String) -> bool:
	if weight != "Regular" and weight != "Medium":
		push_error("CR10_FONT_CAPTURE_FAIL unsupported comparison weight: " + weight)
		return false
	var source_path := CJK_REGULAR_FONT_PATH if weight == "Regular" else CJK_MEDIUM_FONT_PATH
	var selected_cjk := load(source_path) as FontFile
	var default_font := ThemeDB.fallback_font as FontFile
	var project_theme := load(PROJECT_THEME_PATH) as Theme
	if selected_cjk == null or default_font == null or project_theme == null or default_font.fallbacks.is_empty():
		push_error("CR10_FONT_CAPTURE_FAIL comparison font chain is not loaded")
		return false
	var default_cjk := default_font.fallbacks[0] as FontFile
	if default_cjk == null:
		push_error("CR10_FONT_CAPTURE_FAIL ThemeDB CJK fallback is not a FontFile")
		return false
	default_cjk.data = selected_cjk.data
	var default_supplementary: Array[Font] = []
	for fallback_font: Font in default_cjk.fallbacks:
		var normalized_font := HudFontSetup.duplicate_font_with_reference_metrics(
			fallback_font, selected_cjk, CJK_METRIC_CACHE_SIZES
		)
		if normalized_font == null:
			push_error("CR10_FONT_CAPTURE_FAIL could not rebuild ThemeDB supplementary fallback")
			return false
		default_supplementary.append(normalized_font)
	default_cjk.fallbacks = default_supplementary
	default_cjk.allow_system_fallback = false
	default_font.allow_system_fallback = false
	project_theme.default_font = default_font
	var hud_theme := load(M2_THEME_PATH) as Theme
	var m2_cjk := load(M2_CJK_FONT_PATH) as FontFile
	var m2_numeric := load(M2_NUMERIC_FONT_PATH) as FontFile
	if hud_theme == null or m2_cjk == null or m2_numeric == null:
		push_error("CR10_FONT_CAPTURE_FAIL M2 body or numeric font is not loaded")
		return false
	m2_cjk.set("source_font", selected_cjk.duplicate(true))
	if m2_numeric.fallbacks.size() > 0 and m2_numeric.fallbacks[0] != m2_cjk:
		var numeric_cjk := m2_numeric.fallbacks[0] as FontFile
		if numeric_cjk == null:
			push_error("CR10_FONT_CAPTURE_FAIL M2 numeric CJK fallback is not a FontFile")
			return false
		numeric_cjk.set("source_font", selected_cjk.duplicate(true))
	return true


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
	var cjk_codepoints: Array = subset.get("primary_font_codepoints", [])
	_check(int(subset.get("gb2312_character_count", 0)) == 7445, "manifest records the complete GB2312 set")
	_check(codepoints.size() == int(subset.get("unique_character_count", -1)), "manifest Unicode list count matches its declared count")

	var cjk := load(CJK_MEDIUM_FONT_PATH) as FontFile
	var cjk_regular := load(CJK_REGULAR_FONT_PATH) as FontFile
	var cjk_bold := load(CJK_BOLD_FONT_PATH) as FontFile
	var symbols2 := load(SYMBOLS2_FONT_PATH) as FontFile
	var symbols := load(SYMBOLS_FONT_PATH) as FontFile
	var emoji := load(EMOJI_FONT_PATH) as FontFile
	var symbols2_metrics := Vector2(symbols2.get_ascent(9), symbols2.get_descent(9)) if symbols2 != null else Vector2.ZERO
	var symbols_metrics := Vector2(symbols.get_ascent(9), symbols.get_descent(9)) if symbols != null else Vector2.ZERO
	var emoji_metrics := Vector2(emoji.get_ascent(9), emoji.get_descent(9)) if emoji != null else Vector2.ZERO
	var cjk_m2 := load(M2_CJK_FONT_PATH) as FontFile
	var cjk_m2_bold := load(M2_CJK_BOLD_FONT_PATH) as FontFile
	var title_font := load(M2_TITLE_FONT_PATH) as FontFile
	_check(cjk_regular != null and cjk != null and cjk_bold != null, "Regular, Medium, and Bold CJK subset fonts load")
	if cjk_regular != null and cjk != null and cjk_bold != null:
		_check(cjk_regular.data != cjk.data, "Medium uses a distinct font face from Regular")
		_check(cjk_bold.data != cjk.data and cjk_bold.data != cjk_regular.data, "Bold uses a distinct font face from Regular and Medium")
		_check_coverage(cjk_regular, cjk_codepoints, "Regular comparison CJK font")
		_check_coverage(cjk, cjk_codepoints, "Medium candidate CJK font")
		_check_coverage(cjk_bold, cjk_codepoints, "Bold title CJK font")
	var expected_files: Array[FontFile] = [cjk, symbols2, symbols, emoji]
	for index in expected_files.size():
		var font := expected_files[index]
		_check(font != null, "bundled fallback %d loads" % index)
		if font != null:
			_check(not font.allow_system_fallback, "bundled fallback %d disables system fallback" % index)
		_check(font != null and font.fallbacks.is_empty(), "raw bundled fallback %d has no nested resource cycle" % index)

	var default_font := ThemeDB.fallback_font as FontFile
	_check(default_font != null, "ThemeDB default font remains a FontFile")
	_check(default_font != null and default_font.fallbacks.size() == 1, "ThemeDB has a single primary CJK fallback")
	var default_cjk := default_font.fallbacks[0] as FontFile if default_font != null and default_font.fallbacks.size() > 0 else null
	_check_cjk_primary_chain(default_cjk, cjk, [symbols2, symbols, emoji], "ThemeDB CJK fallback")
	_check_coverage(default_font, codepoints, "ThemeDB fallback")
	_check(not _font_chain_has_cycle(default_font, {}, {}), "ThemeDB fallback chain has no resource cycle")

	var ordinary_label := Label.new()
	root.add_child(ordinary_label)
	var ordinary_font := ordinary_label.get_theme_font("font")
	_check(ordinary_font != null, "ordinary Label resolves a default theme font")
	var project_theme := load(PROJECT_THEME_PATH) as Theme
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

	var hud_theme := load(M2_THEME_PATH) as Theme
	_check(hud_theme != null, "M2 theme loads")
	if hud_theme != null:
		var hud_default := hud_theme.default_font
		_check_coverage(hud_default, codepoints, "M2 default text font")
		_check_system_fallback_disabled(hud_default, "M2 default text font")
		_check(not _font_chain_has_cycle(hud_default, {}, {}), "M2 default text fallback chain has no resource cycle")
		_check(hud_default.has_char(65), "M2 default text font retains the existing Latin character data")
		_emit_text_metrics("m2_default", hud_default, ["命中 100%", "暴击 25%", "必定生效"], 9)
		var rich_normal_font := hud_theme.get_font("normal_font", "HudM2RichText")
		var rich_bold_font := hud_theme.get_font("bold_font", "HudM2RichText")
		_check(rich_normal_font != null and rich_bold_font != null, "M2 rich text resolves named normal and bold font styles")
		_check(rich_normal_font is FontFile and cjk != null and not (rich_normal_font as FontFile).fallbacks.is_empty() and (rich_normal_font as FontFile).fallbacks[0].data == cjk.data, "M2 rich text normal style uses Medium CJK")
		_check(rich_bold_font is FontFile and cjk_bold != null and not (rich_bold_font as FontFile).fallbacks.is_empty() and (rich_bold_font as FontFile).fallbacks[0].data == cjk_bold.data, "M2 rich text bold style uses Bold CJK")
		_check_system_fallback_disabled(rich_normal_font, "M2 rich text normal style")
		_check_system_fallback_disabled(rich_bold_font, "M2 rich text bold style")
		_emit_text_metrics("m2_rich_normal", rich_normal_font, ["技能说明", "每回合获得 1 点", "伤害预测"], 12)
		_emit_text_metrics("m2_rich_bold", rich_bold_font, ["技能标题", "属性", "伤害预测"], 12)
		var numeric_font := hud_theme.get_font("font", "HudM2NumericLabel")
		_check_coverage(numeric_font, codepoints, "M2 numeric font")
		_check_system_fallback_disabled(numeric_font, "M2 numeric font")
		_check(numeric_font.has_char(65), "M2 numeric font retains its existing Latin font data")
		_emit_text_metrics("m2_numeric", numeric_font, ["命中 100%", "暴击 25%", "必定生效"], 9)
		_check_cjk_primary_chain(cjk_m2, cjk, [symbols2, symbols, emoji], "M2 Medium body CJK")
		_check_cjk_primary_chain(cjk_m2_bold, cjk_bold, [symbols2, symbols, emoji], "M2 Bold title CJK")
	if hud_theme != null:
		var title_cjk := title_font.fallbacks[0] as FontFile if title_font != null and title_font.fallbacks.size() > 0 else null
		_check(title_cjk != null and cjk_bold != null and title_cjk.data == cjk_bold.data, "M2 title font uses the dedicated Bold CJK chain")
		var m2_cjk_metric_reference := cjk_m2.duplicate(false) as FontFile if cjk_m2 != null else null
		if m2_cjk_metric_reference != null:
			m2_cjk_metric_reference.fallbacks = []
		_check(m2_cjk_metric_reference != null and is_equal_approx(m2_cjk_metric_reference.get_ascent(9), 10.5) and is_equal_approx(m2_cjk_metric_reference.get_descent(9), 2.625), "M2 CJK primary keeps its measured intrinsic 9 px metrics")
		_check_system_fallback_disabled(title_font, "M2 title font")
		_check_coverage(title_font, codepoints, "M2 title font")
		_check(not _font_chain_has_cycle(title_font, {}, {}), "M2 title font fallback chain has no resource cycle")
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

	var cjk_resource := load(CJK_MEDIUM_FONT_PATH) as FontFile
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
	_check(symbols2 != null and is_equal_approx(symbols2.get_ascent(9), symbols2_metrics.x) and is_equal_approx(symbols2.get_descent(9), symbols2_metrics.y), "raw Symbols2 source metrics are unchanged")
	_check(symbols != null and is_equal_approx(symbols.get_ascent(9), symbols_metrics.x) and is_equal_approx(symbols.get_descent(9), symbols_metrics.y), "raw Symbols source metrics are unchanged")
	_check(emoji != null and is_equal_approx(emoji.get_ascent(9), emoji_metrics.x) and is_equal_approx(emoji.get_descent(9), emoji_metrics.y), "raw Emoji source metrics are unchanged")
	_check_capture_weight_helper(hud_theme)
	_finish()


func _check_capture_weight_helper(hud_theme: Theme) -> void:
	var default_font := ThemeDB.fallback_font as FontFile
	var m2_cjk := load(M2_CJK_FONT_PATH) as FontFile
	var m2_numeric := load(M2_NUMERIC_FONT_PATH) as FontFile
	var title_font := load(M2_TITLE_FONT_PATH) as FontFile
	var title_cjk := title_font.fallbacks[0] as FontFile if title_font != null and title_font.fallbacks.size() > 0 else null
	var bold_source := load(CJK_BOLD_FONT_PATH) as FontFile
	var frozen_font := hud_theme.get_font("number", "HudM2FrozenResource") as FontVariation if hud_theme != null else null
	if default_font == null or m2_cjk == null or m2_numeric == null or title_cjk == null or bold_source == null or frozen_font == null:
		_fail("comparison-weight smoke test resources are available")
		return
	var frozen_ascent := frozen_font.get_ascent(32)
	var frozen_descent := frozen_font.get_descent(32)
	var loaded_helper := load("res://tests/claude_review/cr10_font_runtime_check.gd") as GDScript
	_check(loaded_helper != null and loaded_helper.configure_capture_weight("Regular"), "capture can call the static helper through the loaded checker script")
	for weight: String in ["Regular", "Medium"]:
		_check(configure_capture_weight(weight), "capture helper accepts %s for this process" % weight)
		var source_path := CJK_REGULAR_FONT_PATH if weight == "Regular" else CJK_MEDIUM_FONT_PATH
		var selected_cjk := load(source_path) as FontFile
		var active_default_cjk := default_font.fallbacks[0] as FontFile if not default_font.fallbacks.is_empty() else null
		var active_numeric_cjk := m2_numeric.fallbacks[0] as FontFile if not m2_numeric.fallbacks.is_empty() else null
		var active_m2_source := m2_cjk.get("source_font") as FontFile
		_check(selected_cjk != null and active_default_cjk != null and active_default_cjk.data == selected_cjk.data, "capture helper selects %s in ThemeDB" % weight)
		_check(selected_cjk != null and active_m2_source != null and active_m2_source.data == selected_cjk.data, "capture helper selects %s in M2 body" % weight)
		_check(selected_cjk != null and active_numeric_cjk != null and active_numeric_cjk.data == selected_cjk.data, "capture helper selects %s in M2 numeric CJK" % weight)
		_check(title_cjk.data == bold_source.data, "capture helper keeps Bold title CJK while selecting %s" % weight)
		_check(is_equal_approx(frozen_font.get_ascent(32), frozen_ascent) and is_equal_approx(frozen_font.get_descent(32), frozen_descent), "capture helper preserves frozen number metrics while selecting %s" % weight)
	_check(configure_capture_weight("Medium"), "capture helper restores the production Medium weight in this process")


func _check_cjk_primary_chain(primary: FontFile, expected_primary: FontFile, supplementary_sources: Array[FontFile], label: String) -> void:
	if primary == null or expected_primary == null:
		_fail("%s primary CJK font is available" % label)
		return
	_check(primary.data == expected_primary.data, "%s uses the selected CJK font data" % label)
	_check(not primary.allow_system_fallback, "%s disables system fallback" % label)
	_check(primary.fallbacks.size() == supplementary_sources.size(), "%s keeps the full supplementary fallback chain" % label)
	var metric_reference := primary.duplicate(false) as FontFile
	_check(metric_reference != null, "%s can measure its primary font without supplementary fallbacks" % label)
	if metric_reference != null:
		metric_reference.fallbacks = []
	var fallback_names: Array[String] = ["Symbols2", "Symbols", "Emoji"]
	for index in mini(primary.fallbacks.size(), supplementary_sources.size()):
		var fallback := primary.fallbacks[index] as FontFile
		var source := supplementary_sources[index]
		var fallback_name := fallback_names[index] if index < fallback_names.size() else "fallback%d" % index
		_check(fallback != null, "%s %s fallback is a FontFile" % [label, fallback_name])
		if fallback == null:
			continue
		_check(fallback.data == source.data, "%s %s preserves the original font glyph data" % [label, fallback_name])
		_check(fallback.fallbacks.is_empty(), "%s %s has no nested fallback" % [label, fallback_name])
		_check(not fallback.allow_system_fallback, "%s %s disables system fallback" % [label, fallback_name])
		_check(fallback.get_cache_count() > 0, "%s %s has a writable font cache" % [label, fallback_name])
	var metric_rows: Array[String] = []
	for size: int in CJK_METRIC_CACHE_SIZES:
		var expected_ascent := metric_reference.get_ascent(size) if metric_reference != null else -1.0
		var expected_descent := metric_reference.get_descent(size) if metric_reference != null else -1.0
		var supplement_rows: Array[String] = []
		for index in mini(primary.fallbacks.size(), supplementary_sources.size()):
			var fallback := primary.fallbacks[index] as FontFile
			if fallback == null:
				continue
			var fallback_name := fallback_names[index] if index < fallback_names.size() else "fallback%d" % index
			var cache_size := fallback.msdf_size if fallback.multichannel_signed_distance_field else size
			for cache_index: int in range(fallback.get_cache_count()):
				var actual_ascent: float = fallback.get_cache_ascent(cache_index, cache_size)
				var actual_descent: float = fallback.get_cache_descent(cache_index, cache_size)
				var cache_reference_ascent := metric_reference.get_ascent(cache_size) if metric_reference != null else -1.0
				var cache_reference_descent := metric_reference.get_descent(cache_size) if metric_reference != null else -1.0
				_check(is_equal_approx(actual_ascent, cache_reference_ascent), "%s %s cache %d ascent at %d px matches the CJK primary" % [label, fallback_name, cache_index, cache_size])
				_check(is_equal_approx(actual_descent, cache_reference_descent), "%s %s cache %d descent at %d px matches the CJK primary" % [label, fallback_name, cache_index, cache_size])
				_check(is_equal_approx(fallback.get_ascent(size), expected_ascent), "%s %s ascent at UI size %d px matches the CJK primary" % [label, fallback_name, size])
				_check(is_equal_approx(fallback.get_descent(size), expected_descent), "%s %s descent at UI size %d px matches the CJK primary" % [label, fallback_name, size])
				supplement_rows.append("%s#%d@%d=%.3f/%.3f" % [fallback_name, cache_index, cache_size, actual_ascent, actual_descent])
		metric_rows.append("%s:%dpx primary=%.3f/%.3f supplements=[%s]" % [label, size, expected_ascent, expected_descent, ",".join(supplement_rows)])
	for row: String in metric_rows:
		print("CR10_FONT_CHAIN_METRICS " + row)


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
