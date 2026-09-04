extends Control

const CANDIDATE_FONT: FontFile = preload(
	"res://assets/fonts/ibm_plex_mono/IBMPlexMono-SemiBold.ttf")
const SAMPLE_STRINGS: Array[String] = [
	"000000/000000",
	"666666/666666",
	"888888/888888",
	"999999/999999",
	"123456/654321",
]
const REGULAR_SAMPLE: String = "34/100"
const IDENTIFICATION_SAMPLE: String = "0 1 6 7 8 9 /"
const COLUMN_WIDTH: float = 360.0
const COLUMN_HEIGHT: float = 416.0
const ROW_HEIGHT: float = 42.0
const ROW_GAP: float = 8.0
const VALUE_WIDTH: float = 58.0
const VALUE_HEIGHT: float = 12.0
const VALUE_LOCAL_POSITION := Vector2(272.0, 16.0)

@onready var _reference_host: Control = %ReferenceHost
@onready var _candidate_host: Control = %CandidateHost

var _reference_labels: Array[Label] = []
var _candidate_labels: Array[Label] = []


func _ready() -> void:
	_build_column(_reference_host, false)
	_build_column(_candidate_host, true)


func get_sample_strings() -> Array[String]:
	return SAMPLE_STRINGS.duplicate()


func get_reference_labels() -> Array[Label]:
	return _reference_labels.duplicate()


func get_candidate_labels() -> Array[Label]:
	return _candidate_labels.duplicate()


func get_candidate_font() -> FontFile:
	return CANDIDATE_FONT


func _build_column(host: Control, use_candidate: bool) -> void:
	var labels: Array[Label] = _candidate_labels if use_candidate else _reference_labels
	var column_panel := Panel.new()
	column_panel.name = "ColumnPanel"
	column_panel.position = Vector2.ZERO
	column_panel.size = Vector2(COLUMN_WIDTH, COLUMN_HEIGHT)
	column_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column_panel.add_theme_stylebox_override(&"panel", _column_style(use_candidate))
	host.add_child(column_panel)

	var title := Label.new()
	title.name = "ColumnTitle"
	title.position = Vector2(16.0, 12.0)
	title.size = Vector2(COLUMN_WIDTH - 32.0, 18.0)
	title.text = "IBM Plex Mono SemiBold" if use_candidate else "当前回退字体"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 12)
	title.add_theme_color_override(&"font_color",
		Color("e7c989") if use_candidate else Color("b9b0a4"))
	column_panel.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "ColumnSubtitle"
	subtitle.position = Vector2(16.0, 32.0)
	subtitle.size = Vector2(COLUMN_WIDTH - 32.0, 14.0)
	subtitle.text = "候选 · 静态 TTF · 传统栅格" if use_candidate else "基准 · ThemeDB fallback"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override(&"font_size", 9)
	subtitle.add_theme_color_override(&"font_color", Color("817a72"))
	column_panel.add_child(subtitle)

	var regular: Label = _make_row(column_panel, 0,
		REGULAR_SAMPLE, "8px 常规数值", 8, use_candidate, VALUE_WIDTH)
	labels.append(regular)
	for index: int in SAMPLE_STRINGS.size():
		var label: Label = _make_row(column_panel, index + 1,
			SAMPLE_STRINGS[index], "7px 长值样本", 7, use_candidate, VALUE_WIDTH)
		labels.append(label)
	var identification: Label = _make_row(column_panel, SAMPLE_STRINGS.size() + 1,
		IDENTIFICATION_SAMPLE, "8px 字形辨识", 8, use_candidate, 100.0)
	labels.append(identification)


func _make_row(parent: Control, index: int, value_text: String, caption: String,
		font_size: int, use_candidate: bool, value_width: float) -> Label:
	var row := Panel.new()
	row.name = "SampleRow%d" % index
	row.position = Vector2(10.0, 56.0 + index * (ROW_HEIGHT + ROW_GAP))
	row.size = Vector2(COLUMN_WIDTH - 20.0, ROW_HEIGHT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_stylebox_override(&"panel", _row_style())
	parent.add_child(row)

	var caption_label := Label.new()
	caption_label.name = "Caption"
	caption_label.position = Vector2(10.0, 4.0)
	caption_label.size = Vector2(160.0, 14.0)
	caption_label.text = caption
	caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption_label.add_theme_font_size_override(&"font_size", 9)
	caption_label.add_theme_color_override(&"font_color", Color("8f877d"))
	row.add_child(caption_label)

	var guide := Label.new()
	guide.name = "BoundaryGuide"
	guide.position = Vector2(184.0, 4.0)
	guide.size = Vector2(146.0, 10.0)
	guide.text = "%dpx 右对齐边界" % int(value_width)
	guide.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	guide.add_theme_font_size_override(&"font_size", 8)
	guide.add_theme_color_override(&"font_color", Color("625d58"))
	row.add_child(guide)

	var track := Panel.new()
	track.name = "MeterTrack"
	track.position = Vector2(178.0, 16.0)
	track.size = Vector2(152.0, 12.0)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_theme_stylebox_override(&"panel", _track_style())
	row.add_child(track)

	var fill := ColorRect.new()
	fill.name = "DynamicFill"
	fill.position = Vector2(1.0, 1.0)
	fill.size = Vector2(82.0, 10.0)
	fill.color = Color("5f1f2f")
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)

	var value := Label.new()
	value.name = "ValueText"
	value.position = Vector2(VALUE_LOCAL_POSITION.x + VALUE_WIDTH - value_width,
		VALUE_LOCAL_POSITION.y)
	value.size = Vector2(value_width, VALUE_HEIGHT)
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.clip_text = true
	value.add_theme_font_size_override(&"font_size", font_size)
	value.add_theme_color_override(&"font_color", Color("f0e8d5"))
	value.add_theme_color_override(&"font_outline_color", Color("030204"))
	value.add_theme_constant_override(&"outline_size", 1)
	if use_candidate:
		value.add_theme_font_override(&"font", CANDIDATE_FONT)
	row.add_child(value)
	return value


func _column_style(use_candidate: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("15111c")
	style.border_color = Color("8c6a32") if use_candidate else Color("4a4240")
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


func _row_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0e0b13")
	style.border_color = Color("29222f")
	style.set_border_width_all(1)
	return style


func _track_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("07060a")
	style.border_color = Color("4b3842")
	style.set_border_width_all(1)
	return style
