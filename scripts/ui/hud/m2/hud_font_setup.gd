@tool
extends FontFile
## M2 独立字形缓存：读取现有向量数据，不修改原 FontFile 或导入配置。
## Control.scale 不影响普通字体的 oversampling；使用 MSDF 保留整体缩放。
## https://docs.godotengine.org/en/4.6/classes/class_control.html#class-control-property-scale
## https://docs.godotengine.org/en/4.6/classes/class_fontfile.html#class-fontfile-property-data

@export var source_font: FontFile:
	set(value):
		source_font = value
		if source_font != null:
			data = source_font.data
		_configure_font()

@export var fallback_fonts: Array[Font] = []:
	set(value):
		fallback_fonts = value
		_configure_font()

@export var normalize_fallback_metrics: bool = false:
	set(value):
		normalize_fallback_metrics = value
		_configure_font()

# 只用于当前 M2 正文、卡片和 TurnOrder 字号，不重写 FontFile 的其他缓存。
@export var fallback_metric_sizes: Array[int] = []:
	set(value):
		fallback_metric_sizes = value
		_configure_font()

@export var use_msdf: bool = true:
	set(value):
		use_msdf = value
		multichannel_signed_distance_field = use_msdf


func _init() -> void:
	# 默认文字保留 Godot 已有字族；数字资源通过 source_font 指向 IBM Plex Mono。
	var default_source: FontFile = ThemeDB.fallback_font as FontFile
	if default_source != null:
		data = default_source.data
	_configure_font()


func _configure_font() -> void:
	# 主字体数据与字重不变，按资源声明的包内回退链显示缺少的字形。
	multichannel_signed_distance_field = use_msdf
	var metric_reference: Font = source_font if source_font != null else self
	if normalize_fallback_metrics and source_font != null:
		# 以当前 M2 字体实例的实际缓存（含 MSDF 设置）为准，不让补充符号反过来扩大整条链。
		fallbacks = []
		metric_reference = self
	var configured_fallbacks: Array[Font] = []
	for fallback_font: Font in fallback_fonts:
		var configured_font: Font = fallback_font
		if normalize_fallback_metrics and source_font != null and fallback_font is FontFile:
			configured_font = duplicate_font_with_reference_metrics(
				fallback_font, metric_reference, fallback_metric_sizes
			)
		if configured_font != null:
			configured_fallbacks.append(configured_font)
	fallbacks = configured_fallbacks
	allow_system_fallback = false


static func duplicate_font_with_reference_metrics(font: Font, reference: Font, sizes: Array[int]) -> FontFile:
	if font == null or reference == null or not font is FontFile:
		return null
	var duplicate_font := font.duplicate(true) as FontFile
	if duplicate_font == null:
		return null
	duplicate_font.fallbacks = []
	duplicate_font.allow_system_fallback = false
	var cache_sizes := sizes
	if duplicate_font.multichannel_signed_distance_field:
		cache_sizes = [duplicate_font.msdf_size]
	for size: int in cache_sizes:
		# FontFile may not have a cache entry immediately after duplication. Query both resources first.
		reference.get_ascent(size)
		reference.get_descent(size)
		duplicate_font.get_ascent(size)
		duplicate_font.get_descent(size)
	for cache_index: int in range(duplicate_font.get_cache_count()):
		for size: int in cache_sizes:
			duplicate_font.set_cache_ascent(cache_index, size, reference.get_ascent(size))
			duplicate_font.set_cache_descent(cache_index, size, reference.get_descent(size))
	return duplicate_font
