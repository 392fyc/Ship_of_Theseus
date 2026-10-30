extends RefCounted

## 按当前技能排列为可主动使用的条目编号；被动升级为主动后参与编号。
## 可用性和冷却不改变编号；本函数不修改源条目。
const MAX_NUMBERED_SKILLS: int = 5
static func numbered_entries(entries: Array, _passive_skill_id: String = "") -> Array[Dictionary]:
	var numbered: Array[Dictionary] = []
	for value: Variant in entries:
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		if not bool(entry.get("active_capable", not bool(entry.get("is_passive", false)))):
			continue
		numbered.append(entry)
		if numbered.size() == MAX_NUMBERED_SKILLS:
			break
	return numbered
