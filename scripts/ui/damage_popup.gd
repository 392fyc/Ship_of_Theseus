class_name DamagePopup
extends RefCounted
## Proposal B — Classic TRPG damage popup.
## Shadow text + bounce-up animation. Color-coded by damage type.
## Usage: DamagePopup.spawn(parent_node2d, world_pos, 24, "physical", false)

# ── Damage type colors (matches ADR-004 four types) ──
const COLOR_PHYS   := Color.WHITE
const COLOR_MAGIC  := Color(0.67, 0.53, 1.0)       # #AA88FF
const COLOR_PURE   := Color(1.0, 0.84, 0.0)        # #FFD700
const COLOR_HYBRID := Color(1.0, 0.55, 0.0)        # #FF8C00
const COLOR_MISS   := Color(0.60, 0.60, 0.60)
const COLOR_HEAL   := Color(0.30, 0.90, 0.30)

# ── Sizing ──
const NORMAL_SIZE := 18
const CRIT_SIZE   := 24
const MISS_SIZE   := 16

# ── Animation ──
const RISE_DIST := 60.0
const DURATION  := 1.4


static func spawn(parent: Node, world_pos: Vector2,
		amount: int, damage_type: String, is_crit: bool) -> void:
	var text := "-%d" % amount
	if is_crit:
		text += " CRIT!"
	var color := _type_color(damage_type)
	var sz: int = CRIT_SIZE if is_crit else NORMAL_SIZE
	_create(parent, world_pos, text, color, sz)


static func spawn_miss(parent: Node, world_pos: Vector2) -> void:
	_create(parent, world_pos, "MISS", COLOR_MISS, MISS_SIZE)


static func spawn_heal(parent: Node, world_pos: Vector2, amount: int) -> void:
	_create(parent, world_pos, "+%d" % amount, COLOR_HEAL, NORMAL_SIZE)


static func _create(parent: Node, world_pos: Vector2,
		text: String, color: Color, font_size: int) -> void:
	var base := Vector2(world_pos.x - 60.0, world_pos.y - 50.0)

	var shadow := _make_label(text, font_size,
		Color(0.0, 0.0, 0.0, 0.70), base + Vector2(2.0, 2.0))
	parent.add_child(shadow)

	var label := _make_label(text, font_size, color, base)
	parent.add_child(label)

	for node: Label in [shadow, label]:
		var off := 2.0 if node == shadow else 0.0
		var tw := parent.create_tween().set_parallel(true)
		tw.tween_property(node, "position:y",
			base.y - RISE_DIST + off, DURATION) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(node, "modulate:a", 0.0, DURATION) \
			.set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(node.queue_free)


static func _make_label(text: String, font_size: int,
		color: Color, pos: Vector2) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size = Vector2(120.0, 40.0)
	lbl.position = pos
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


static func _type_color(damage_type: String) -> Color:
	match damage_type:
		"physical": return COLOR_PHYS
		"magical":  return COLOR_MAGIC
		"pure":     return COLOR_PURE
		"hybrid":   return COLOR_HYBRID
	return COLOR_PHYS
