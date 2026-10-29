class_name MemoryUpgrades
extends RefCounted
## 一个单位的回忆升级记录（gameplay-impl PR5，差距清单 M10）。
##
## 回忆天赋把一个基础技能永久升级成同职业的新技能（KB 天赋设计要点 §12）。这里只管
## 「升级关系成立与否、记下来、按身份解析」，升级技能本身的玩法在各自的技能 JSON 里。
##
## 硬约束（KB §12「硬约束」）：
##   - 一个技能一局只能被回忆升级一次；
##   - 回忆、基础技能、升级技能属于同一职业；
##   - 禁止链式升级：已经是升级技能的不能再作为基础；
##   - 升级技能完整替换基础技能（槽位上换成升级技能，不保留原技能）。
## R2.5：明确作用于基础技能的效果也作用于它的升级版本。为此记录每个形态的「技能身份」
## （= 它取代的基础技能 id），多形态回忆（如兵无常势的决心、回天、霸天）的各形态共用这一身份。

## 基础技能 id → 回忆 id
var _applied: Dictionary = {}
## 回忆 id → 回忆定义（data/memories/*.json 的副本）
var _definitions: Dictionary = {}
## 形态技能 id → 基础技能 id
var _identity: Dictionary = {}


func clear() -> void:
	_applied.clear()
	_definitions.clear()
	_identity.clear()


## 已兑现的回忆 id，按兑现顺序。
func get_memory_ids() -> Array[String]:
	var out: Array[String] = []
	for base_id: Variant in _applied.keys():
		out.append(str(_applied[base_id]))
	return out


func is_upgraded(base_skill_id: String) -> bool:
	return _applied.has(base_skill_id)


## 槽位上现在代表这个基础技能的技能 id：升级过的给升级技能，否则原样返回。
func resolve(base_skill_id: String) -> String:
	if not _applied.has(base_skill_id):
		return base_skill_id
	var memory: Dictionary = _definitions.get(str(_applied[base_skill_id]), {})
	return str(memory.get("upgrade_skill_id", base_skill_id))


## 槽位上可能代表这个基础技能的全部形态：没升级过的只有它自己；升级过的是回忆的形态组
## （升级技能在前，例如兵无常势 = 决心、回天、霸天）。同槽替换（R3.6）按顺序逐个判定条件。
func resolve_forms(base_skill_id: String) -> Array[String]:
	if not _applied.has(base_skill_id):
		return [base_skill_id]
	return _form_ids(_definitions.get(str(_applied[base_skill_id]), {}))


## 技能身份（R2.5）：升级技能及其各形态返回被取代的基础技能 id，其余原样返回。
func get_identity(skill_id: String) -> String:
	return str(_identity.get(skill_id, skill_id))


## 检查这张回忆能否兑现；能则返回空串，否则返回原因（给调试与测试读）。
## loadout：单位当前的技能 id（技能栏加被动）；skills：技能定义表（DataLoader.skills）。
func check(memory: Dictionary, class_id: String, loadout: Array[String],
		skills: Dictionary) -> String:
	if memory.is_empty():
		return "未知的回忆"
	if str(memory.get("rarity", "")) != "回忆":
		return "不是回忆天赋"
	var memory_id: String = str(memory.get("id", ""))
	if str(memory.get("class_id", "")) != class_id:
		return "职业不符：回忆属于 %s，单位是 %s" % [str(memory.get("class_id", "")), class_id]
	var base_id: String = str(memory.get("base_skill_id", ""))
	var forms: Array[String] = _form_ids(memory)
	if base_id == "" or forms.is_empty():
		return "回忆 %s 缺少基础技能或升级技能" % memory_id
	if _identity.has(base_id) or str((skills.get(base_id, {}) as Dictionary).get("upgrade_of", "")) != "":
		return "%s 已经是升级技能，不能再升级（禁止链式升级）" % base_id
	if _applied.has(base_id):
		return "%s 本局已被回忆 %s 升级，一个技能只能升级一次" % [base_id, str(_applied[base_id])]
	if not loadout.has(base_id):
		return "单位没有基础技能 %s" % base_id
	for form_id: String in forms:
		var form: Variant = skills.get(form_id, null)
		if not (form is Dictionary):
			return "升级技能 %s 尚未实装" % form_id
		if str((form as Dictionary).get("upgrade_of", "")) != base_id:
			return "升级技能 %s 的 upgrade_of 不是 %s" % [form_id, base_id]
	return ""


## 记下一张已通过 check 的回忆。调用方负责替换槽位。
func record(memory: Dictionary) -> void:
	var memory_id: String = str(memory.get("id", ""))
	var base_id: String = str(memory.get("base_skill_id", ""))
	_applied[base_id] = memory_id
	_definitions[memory_id] = memory.duplicate(true)
	for form_id: String in _form_ids(memory):
		_identity[form_id] = base_id


func _form_ids(memory: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var forms: Variant = memory.get("form_skill_ids", [])
	if forms is Array:
		for form_id: Variant in forms:
			if str(form_id) != "":
				out.append(str(form_id))
	var upgrade_id: String = str(memory.get("upgrade_skill_id", ""))
	if upgrade_id != "" and not out.has(upgrade_id):
		out.push_front(upgrade_id)
	return out
