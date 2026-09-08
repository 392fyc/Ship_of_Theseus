class_name HudM2SwordResourceViewData
extends RefCounted

var qi: HudValueMeterViewData
var threshold_ratio: float = -1.0
var band: StringName = &"none"
var marks_visible: bool = false
var mark_capacity: int = 0
var mark_mode: StringName = &"type_presence"
## 当前运行输入只提供种类持有状态；实例身份和特殊标记留空。
var marks: Array[Dictionary] = []
