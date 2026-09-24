class_name HudM2MarksPanel
extends Control

## 三个独立布尔值驱动纹章；素材加载失败时回退已提交的八张透明状态图。
const CREST_ATLAS_PATH := "res://assets/ui/skins/hud_mark_crest/marks-filled-generated.png"
const CREST_HOLLOW_SHADER_PATH := "res://assets/ui/shaders/hud_mark_hollow.gdshader"
const CREST_REGIONS := [
	Rect2(92, 56, 626, 586),
	Rect2(783, 18, 616, 654),
	Rect2(1500, 15, 566, 662),
]
const CREST_DESTINATIONS := [
	Rect2(17, 0, 58, 52),
	Rect2(114, 0, 50, 52),
	Rect2(209, 0, 46, 52),
]

var _state: StringName = &"000"
var _crest_enabled: bool = false
var _crest_glyphs: Array[TextureRect] = []
var _hollow_material: ShaderMaterial = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_changed.connect(queue_redraw)
	_create_crest_glyphs()
	_crest_enabled = _crest_glyphs.size() == 3
	_update_crest_glyphs()
	queue_redraw()


func _create_crest_glyphs() -> void:
	var atlas: Texture2D = load(CREST_ATLAS_PATH) as Texture2D
	var shader: Shader = load(CREST_HOLLOW_SHADER_PATH) as Shader
	if atlas == null or shader == null:
		push_error("Crest mark candidate resources could not be loaded.")
		return
	_hollow_material = ShaderMaterial.new()
	_hollow_material.shader = shader
	for index: int in 3:
		var region := AtlasTexture.new()
		region.atlas = atlas
		region.region = CREST_REGIONS[index]
		region.filter_clip = true
		var glyph := TextureRect.new()
		glyph.name = "CrestGlyph%d" % index
		glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glyph.stretch_mode = TextureRect.STRETCH_SCALE
		glyph.texture = region
		glyph.position = CREST_DESTINATIONS[index].position
		glyph.size = CREST_DESTINATIONS[index].size
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.visible = false
		add_child(glyph)
		_crest_glyphs.append(glyph)


func apply_view(view: HudM2ClassResourceViewData) -> void:
	visible = view != null and view.visible and view.body is HudM2SwordResourceViewData and view.body.marks_visible
	if not visible:
		return
	var bits := PackedStringArray()
	for index: int in 3:
		var entry: Dictionary = view.body.marks[index] if index < view.body.marks.size() else {}
		bits.append("1" if bool(entry.get("held", false)) else "0")
	_state = StringName("".join(bits))
	_update_crest_glyphs()
	queue_redraw()


func _draw() -> void:
	if _crest_enabled:
		return
	var icon: StringName = StringName("marks_" + str(_state))
	var texture: Texture2D = get_theme_icon(icon, &"HudM2FrozenResource")
	draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)


func _update_crest_glyphs() -> void:
	if _crest_glyphs.size() != 3:
		return
	for index: int in 3:
		var glyph: TextureRect = _crest_glyphs[index]
		glyph.visible = _crest_enabled
		glyph.material = null if str(_state).substr(index, 1) == "1" else _hollow_material


func get_input_blocking_rects() -> Array[Rect2]:
	if is_visible_in_tree():
		return [get_global_rect()]
	return []
