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
	fallbacks = fallback_fonts
	allow_system_fallback = false
