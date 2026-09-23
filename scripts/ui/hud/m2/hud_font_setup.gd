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


func _init() -> void:
	# 默认文字保留 Godot 已有字族；数字资源通过 source_font 指向 IBM Plex Mono。
	var default_source: FontFile = ThemeDB.fallback_font as FontFile
	if default_source != null:
		data = default_source.data
	multichannel_signed_distance_field = true
	allow_system_fallback = true
