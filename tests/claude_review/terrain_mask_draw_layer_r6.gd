extends "res://tests/claude_review/terrain_mask_draw_layer.gd"
## R6 capture masks ask the live production board for footing geometry.
## This keeps the capture aligned with the game's draw order and coordinates.

signal capture_failed(reason: String)

var _r6_failure_reported := false


func _draw_wall_footings(include_shadow: bool) -> void:
	if not is_instance_valid(_board):
		_fail_capture("R6 wall-footing mask has no live production board")
		return
	if not _board.has_method("draw_wall_footing_visuals"):
		_fail_capture("R6 production board is missing draw_wall_footing_visuals(canvas, include_shadow)")
		return
	var production_board: Variant = _board
	production_board.draw_wall_footing_visuals(self, include_shadow)


func _draw_contact_shadows() -> void:
	if not is_instance_valid(_board):
		_fail_capture("R6 contact-shadow mask has no live production board")
		return
	if not _board.has_method("wall_footing_visuals"):
		_fail_capture("R6 production board is missing wall_footing_visuals()")
		return
	var production_board: Variant = _board
	var visuals: Variant = production_board.wall_footing_visuals()
	if not visuals is Dictionary:
		_fail_capture("R6 wall_footing_visuals() did not return a Dictionary")
		return
	var visual_record: Dictionary = visuals
	if not visual_record.has("shadows"):
		_fail_capture("R6 wall_footing_visuals() result has no shadows array")
		return
	if not visual_record.has("aprons") or not visual_record["aprons"] is Array:
		_fail_capture("R6 wall_footing_visuals() result has no aprons array")
		return
	if not visual_record.has("shadow_color") or not visual_record["shadow_color"] is Color:
		_fail_capture("R6 wall_footing_visuals() result has no Color shadow_color")
		return
	var shadow_value: Variant = visual_record["shadows"]
	if not shadow_value is Array:
		_fail_capture("R6 wall_footing_visuals()['shadows'] is not an Array")
		return
	var shadows: Array = shadow_value
	if shadows.is_empty():
		_fail_capture("R6 wall_footing_visuals()['shadows'] has no polygons for this courtyard capture")
		return
	for index: int in shadows.size():
		var points_value: Variant = shadows[index]
		if not points_value is PackedVector2Array:
			_fail_capture("R6 shadow polygon %d is not a PackedVector2Array" % index)
			return
		var points: PackedVector2Array = points_value
		if points.size() < 3:
			_fail_capture("R6 shadow polygon %d has fewer than three points" % index)
			return
		draw_colored_polygon(points, Color.WHITE)


func _fail_capture(reason: String) -> void:
	if _r6_failure_reported:
		return
	_r6_failure_reported = true
	push_error("[TerrainMaskCapture R6] " + reason)
	capture_failed.emit(reason)
