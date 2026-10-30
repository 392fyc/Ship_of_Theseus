extends RefCounted

## 1–4 属于原有主动槽。被动槽临时变成可点击技能时仍不占数字键。
## 可用性、冷却与技能形态不改变后续编号；本函数不修改源条目。
static func numbered_entries(entries: Array, passive_skill_id: String = "") -> Array[Dictionary]:
	var numbered: Array[Dictionary] = []
	for value: Variant in entries:
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		if not passive_skill_id.is_empty() and str(entry.get("slot_origin_id", "")) == passive_skill_id:
			continue
		if not bool(entry.get("active_capable", not bool(entry.get("is_passive", false)))):
			continue
		numbered.append(entry)
		if numbered.size() == 4:
			break
	return numbered
