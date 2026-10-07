extends Node
## 为 ThemeDB 的默认拉丁字族挂接随包中文字体，供普通控件和直接自绘共用。

const CJK_FONT: FontFile = preload("res://assets/fonts/noto_sans_cjk_sc/NotoSansCJKsc-Regular-subset.otf")
const SYMBOLS2_FONT: FontFile = preload("res://assets/fonts/noto_sans_symbols/NotoSansSymbols2-Regular-subset.ttf")
const SYMBOLS_FONT: FontFile = preload("res://assets/fonts/noto_sans_symbols/NotoSansSymbols-Regular-subset.ttf")
const EMOJI_FONT: FontFile = preload("res://assets/fonts/noto_emoji/NotoEmoji-Regular-400-subset.ttf")


func _enter_tree() -> void:
	var source_font := ThemeDB.fallback_font as FontFile
	if source_font == null:
		push_error("ThemeDB fallback font is not a FontFile; bundled CJK setup cannot continue.")
		return

	var bundled_fallbacks: Array[Font] = [CJK_FONT, SYMBOLS2_FONT, SYMBOLS_FONT, EMOJI_FONT]
	for fallback: Font in bundled_fallbacks:
		var font_file := fallback as FontFile
		if font_file != null:
			font_file.allow_system_fallback = false
			font_file.fallbacks = []
	var packaged_default := source_font.duplicate(true) as FontFile
	if packaged_default == null:
		push_error("Could not duplicate the existing default font for bundled CJK fallback.")
		return
	packaged_default.allow_system_fallback = false
	packaged_default.fallbacks = bundled_fallbacks
	ThemeDB.fallback_font = packaged_default
	var project_theme := load("res://assets/ui/themes/default_font.tres") as Theme
	if project_theme == null:
		push_error("Could not load the default project theme for bundled CJK fallback.")
		return
	project_theme.default_font = packaged_default
