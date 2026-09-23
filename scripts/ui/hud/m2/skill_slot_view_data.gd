class_name HudM2SkillSlotViewData
extends "res://scripts/ui/hud/skill_slot_view_data.gd"
## 职业主资源的显示元数据；不读取旧费用字段或执行扣费。

var action_type: StringName = &""
var resource_cost_display: Dictionary = {}


func is_pure_passive() -> bool:
	return passive and not active_capable


func resource_cost_text() -> String:
	var amount: Variant = resource_cost_display.get("amount")
	if not (amount is int or amount is float):
		return ""
	var numeric: float = float(amount)
	# 当前数字承载区只覆盖获批的 1—3 位整数。
	if not is_finite(numeric) or numeric != floor(numeric) or numeric <= 0 or numeric > 999:
		return ""
	if resource_name_text().is_empty():
		return ""
	return str(int(numeric))


func resource_name_text() -> String:
	var resource_name: Variant = resource_cost_display.get("resource_name")
	if not (resource_name is String or resource_name is StringName):
		return ""
	return str(resource_name).strip_edges()
