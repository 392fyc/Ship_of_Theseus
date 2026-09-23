class_name HudM2SwordResourceViewData
extends RefCounted

var qi: HudValueMeterViewData
var threshold_ratio: float = -1.0
var band: StringName = &"none"
var marks_visible: bool = false
var mark_capacity: int = 0
var mark_mode: StringName = &"type_presence"
## 心、道、势三种位置始终保留，各自的 held 是独立布尔状态。
## 实例身份和特殊标记仍由未来的真实运行来源提供。
var marks: Array[Dictionary] = []
