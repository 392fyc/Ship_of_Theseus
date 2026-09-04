class_name HudActionResourceViewData
extends RefCounted

var movement_remaining: int = 0
var movement_available: bool = true
var standard_capacity: int = 1
var standard_remaining: int = 1
var swift_capacity: int = 1
var swift_remaining: int = 1


func normalize() -> void:
	movement_remaining = maxi(movement_remaining, 0)
	standard_capacity = clampi(standard_capacity, 1, 3)
	standard_remaining = clampi(standard_remaining, 0, standard_capacity)
	swift_capacity = clampi(swift_capacity, 1, 3)
	swift_remaining = clampi(swift_remaining, 0, swift_capacity)
