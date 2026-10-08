extends "res://tests/claude_review/capture_terrain_readability_v3.gd"


func _run_headless_check() -> void:
	var diagnostic: Dictionary = await _run_input_routing_regression()
	if _failed:
		return
	if not _write_route_diagnostic(diagnostic):
		_abort("could not save the concise v3 input-routing diagnostic")
		return
	print("TERRAIN_MASK_CAPTURE_V3_INPUT_ROUTING_TEST " + JSON.stringify({
		"route_divergence_observed": diagnostic.get("route_divergence_observed", false),
		"normalization_pass": diagnostic.get("normalization_pass", false),
		"highlight_payload_pass": diagnostic.get("highlight_payload_pass", false),
		"freeze_and_sync_pass": diagnostic.get("freeze_and_sync_pass", false),
		"diagnostic_saved": true,
	}))
	quit(0)
