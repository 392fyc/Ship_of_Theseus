class_name HudValueMeterViewData
extends RefCounted

var current_value: int = 0
var maximum_value: int = 0

var ratio: float:
	get:
		if maximum_value <= 0:
			return 0.0
		return clampf(float(current_value) / float(maximum_value), 0.0, 1.0)

var display_text: String:
	get:
		return "%d/%d" % [current_value, maxi(maximum_value, 0)]
