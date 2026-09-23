class_name HudM2ClassResourceLayout
extends Resource

## 固定画板坐标。皮肤图层与运行状态由各自的资源和视图提供。
@export var bounds: Rect2
@export var marks_bounds: Rect2
@export var base_rect: Rect2
@export var energy_rect: Rect2
@export var flow_rect: Rect2
@export var number_rect: Rect2


func geometry() -> Dictionary:
	return {
		"base": _local(base_rect),
		"energy": _local(energy_rect),
		"flow": _local(flow_rect),
		"number": _local(number_rect),
	}


func _local(rect: Rect2) -> Rect2:
	return Rect2(rect.position - bounds.position, rect.size)
