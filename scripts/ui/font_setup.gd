extends Node
## 为 ThemeDB 的默认拉丁字族挂接随包中文字体，供普通控件和直接自绘共用。

const CJK_MEDIUM_FONT_PATH := "res://assets/fonts/noto_sans_cjk_sc/NotoSansCJKsc-Medium-subset.otf"
const SUPPLEMENTARY_FONT_PATHS: Array[String] = [
	"res://assets/fonts/noto_sans_symbols/NotoSansSymbols2-Regular-subset.ttf",
	"res://assets/fonts/noto_sans_symbols/NotoSansSymbols-Regular-subset.ttf",
	"res://assets/fonts/noto_emoji/NotoEmoji-Regular-400-subset.ttf",
]
# 本次实际字体尺寸：CR-10 8–14 px、ThemeDB 默认 16 px、M2 冷却数字 20 px；冻结数字 32 px 不走此链。
const CJK_METRIC_CACHE_SIZES: Array[int] = [8, 9, 10, 11, 12, 13, 14, 16, 20]
const HudFontSetup := preload("res://scripts/ui/hud/m2/hud_font_setup.gd")


func _enter_tree() -> void:
	var source_font := ThemeDB.fallback_font as FontFile
	if source_font == null:
		push_error("ThemeDB fallback font is not a FontFile; bundled CJK setup cannot continue.")
		return

	# 编辑器首次扫描会先解析 autoload；此时字体尚未导入，不能在解析期 preload。
	var cjk_source := load(CJK_MEDIUM_FONT_PATH) as FontFile
	if cjk_source == null:
		push_error("Could not load the bundled Medium CJK font: " + CJK_MEDIUM_FONT_PATH)
		return
	var cjk_font := cjk_source.duplicate(true) as FontFile
	if cjk_font == null:
		push_error("Could not duplicate the bundled Medium CJK font.")
		return
	cjk_font.allow_system_fallback = false
	cjk_font.fallbacks = []
	var supplementary_fallbacks: Array[Font] = []
	for font_path: String in SUPPLEMENTARY_FONT_PATHS:
		var font_file := load(font_path) as FontFile
		if font_file == null:
			push_error("Could not load a bundled fallback font: " + font_path)
			return
		var normalized_font := HudFontSetup.duplicate_font_with_reference_metrics(
			font_file, cjk_font, CJK_METRIC_CACHE_SIZES
		)
		if normalized_font == null:
			push_error("Could not duplicate a bundled fallback font: " + font_path)
			return
		supplementary_fallbacks.append(normalized_font)
	cjk_font.fallbacks = supplementary_fallbacks
	var packaged_default := source_font.duplicate(true) as FontFile
	if packaged_default == null:
		push_error("Could not duplicate the existing default font for bundled CJK fallback.")
		return
	packaged_default.allow_system_fallback = false
	packaged_default.fallbacks = [cjk_font]
	ThemeDB.fallback_font = packaged_default
	var project_theme := load("res://assets/ui/themes/default_font.tres") as Theme
	if project_theme == null:
		push_error("Could not load the default project theme for bundled CJK fallback.")
		return
	project_theme.default_font = packaged_default
