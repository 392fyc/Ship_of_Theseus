extends Node
## 为 ThemeDB 的默认拉丁字族挂接随包中文字体，供普通控件和直接自绘共用。

const BUNDLED_FONT_PATHS: Array[String] = [
	"res://assets/fonts/noto_sans_cjk_sc/NotoSansCJKsc-Regular-subset.otf",
	"res://assets/fonts/noto_sans_symbols/NotoSansSymbols2-Regular-subset.ttf",
	"res://assets/fonts/noto_sans_symbols/NotoSansSymbols-Regular-subset.ttf",
	"res://assets/fonts/noto_emoji/NotoEmoji-Regular-400-subset.ttf",
]


func _enter_tree() -> void:
	var source_font := ThemeDB.fallback_font as FontFile
	if source_font == null:
		push_error("ThemeDB fallback font is not a FontFile; bundled CJK setup cannot continue.")
		return

	# 编辑器首次扫描会先解析 autoload；此时字体尚未导入，不能在解析期 preload。
	var bundled_fallbacks: Array[Font] = []
	for font_path: String in BUNDLED_FONT_PATHS:
		var font_file := load(font_path) as FontFile
		if font_file == null:
			push_error("Could not load a bundled fallback font: " + font_path)
			return
		font_file.allow_system_fallback = false
		font_file.fallbacks = []
		bundled_fallbacks.append(font_file)
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
