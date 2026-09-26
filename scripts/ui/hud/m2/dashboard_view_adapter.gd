class_name HudM2DashboardViewAdapter
extends RefCounted

## TacticalManager 仪表盘载荷到 M2 视图对象的无副作用转换。
## 本类不查询资源库，不补造运行时未提供的角色、装备、库存或职业资源事实。

const CharacterView := preload("res://scripts/ui/hud/m2/character_hud_view_data.gd")
const SkillView := preload("res://scripts/ui/hud/m2/skill_slot_view_data.gd")
const SlotView := preload("res://scripts/ui/hud/m2/slot_view_data.gd")
const PotionView := preload("res://scripts/ui/hud/potion_view_data.gd")
const ActionResourceView := preload("res://scripts/ui/hud/action_resource_view_data.gd")
const EndActionView := preload("res://scripts/ui/hud/end_turn_view_data.gd")
const MeterView := preload("res://scripts/ui/hud/value_meter_view_data.gd")
const ClassResourceView := preload("res://scripts/ui/hud/m2/class_resource_view_data.gd")
const SwordResourceView := preload("res://scripts/ui/hud/m2/sword_resource_view_data.gd")
const ProfileCatalog := preload("res://scripts/ui/hud/m2/class_resource_profile_catalog.gd")
const KenseiPortrait: Texture2D = preload("res://assets/ui/portraits/kensei_hud_portrait.tres")
const MyrmidonPortrait: Texture2D = preload("res://assets/ui/portraits/myrmidon_hud_portrait.tres")

var _resource_profiles := ProfileCatalog.new()

const ATTRIBUTE_MAP: Array[Dictionary] = [
	{"view_key": "STR", "state_key": "str"}, {"view_key": "MAG", "state_key": "mag"},
	{"view_key": "DEX", "state_key": "dex"}, {"view_key": "SPE", "state_key": "spd"},
	{"view_key": "DEF", "state_key": "def"}, {"view_key": "RES", "state_key": "res"},
	{"view_key": "LCK", "state_key": "lck"}, {"view_key": "MOV", "state_key": "mov"},
]


func build(state: Dictionary, icon_textures: Dictionary = {}) -> Dictionary:
	var visible: bool = bool(state.get("visible", false))
	var player_actions: bool = visible and str(state.get("mode", "player")) == "player" and bool(state.get("show_actions", false))
	return {
		"visible": visible,
		"character": _build_character(state),
		"class_resources": _build_class_resources(state),
		"skills": _build_skills(state, icon_textures, player_actions),
		"action_resources": _build_action_resources(state.get("action_resources")) if player_actions else null,
		"action_resources_valid": player_actions and _is_action_resources_valid(state.get("action_resources")),
		"weapon": _reserved_slot(&"weapon", "装备槽位预留"),
		"armor": _reserved_slot(&"armor", "装备槽位预留"),
		"potion": _missing_potion(),
		"relics": _reserved_relics(),
		"end_action": _build_end_action(state, player_actions),
	}


func _build_class_resources(state: Dictionary) -> RefCounted:
	var view := ClassResourceView.new()
	var current: Variant = state.get("sword_qi")
	var maximum: Variant = state.get("sword_qi_max")
	if not bool(state.get("visible", false)) or not _is_nonnegative_integer(current) or not _is_integer(maximum) or int(maximum) <= 0:
		return view
	var metadata: Dictionary = state.get("class_resource_display", {}) if state.get("class_resource_display") is Dictionary else {}
	var profile: Dictionary = _resource_profiles.profile_for(StringName(str(metadata.get("class_id", ""))))
	var body := SwordResourceView.new()
	body.qi = _meter(int(current), int(maximum))
	var threshold: Variant = metadata.get("qi_threshold_ratio")
	if (threshold is float or threshold is int) and is_finite(float(threshold)) and float(threshold) >= 0.0 and float(threshold) <= 1.0:
		body.threshold_ratio = float(threshold)
		var band: StringName = StringName(str(metadata.get("qi_band", "none")))
		body.band = band if band in [&"low", &"high"] else &"none"
	body.marks_visible = bool(profile.get("show_marks", false)) and _is_nonnegative_integer(metadata.get("mark_capacity")) and state.get("marks") is Dictionary
	if body.marks_visible:
		body.mark_capacity = int(metadata["mark_capacity"])
		var marks: Dictionary = state.get("marks", {}) if state.get("marks") is Dictionary else {}
		for kind: String in ["心", "道", "势"]:
			body.marks.append({
				"type_id": StringName(kind),
				"held": marks.get(kind) is bool and marks[kind],
				"instance_id": "",
				"special_marker": &"",
			})
	view.visible = true
	view.renderer_key = StringName(str(profile.get("renderer_key", "sword")))
	view.source_kind = &"registered_profile" if not profile.is_empty() else &"runtime_qi_only"
	view.body = body
	return view


func _build_character(state: Dictionary) -> RefCounted:
	var view := CharacterView.new()
	# TacticalManager 的 unit_name 是职业或敌方记录名，不能冒充玩家姓名。
	view.profession_name = str(state.get("unit_name", "")).strip_edges()
	view.player_name = ""
	view.portrait_fallback_text = str(state.get("unit_label", "")).strip_edges()
	var class_display: Dictionary = state.get("class_resource_display", {}) if state.get("class_resource_display") is Dictionary else {}
	match str(class_display.get("class_id", "")):
		"kensei":
			view.portrait_texture = KenseiPortrait
		"myrmidon":
			view.portrait_texture = MyrmidonPortrait
	var hp: Variant = state.get("hp")
	var hp_max: Variant = state.get("hp_max")
	if _is_integer(hp) and _is_integer(hp_max):
		view.hp = _meter(int(hp), int(hp_max))
	var stats: Dictionary = state.get("stats", {}) if state.get("stats") is Dictionary else {}
	var deltas: Dictionary = state.get("stats_delta", {}) if state.get("stats_delta") is Dictionary else {}
	for mapping: Dictionary in ATTRIBUTE_MAP:
		var state_key: String = mapping["state_key"]
		var value: Variant = stats.get(state_key)
		if not _is_integer(value):
			continue
		var description := {"value": int(value)}
		var delta: Variant = deltas.get(state_key)
		if _is_integer(delta):
			description["delta"] = int(delta)
		view.attribute_descriptions[mapping["view_key"]] = description
	return view


func _build_skills(state: Dictionary, icon_textures: Dictionary, player_actions: bool) -> Array[RefCounted]:
	var source: Variant = state.get("skills", [])
	var views: Array[RefCounted] = []
	if not source is Array:
		return views
	var hotkey_index: int = 1
	for entry_source: Variant in source:
		if not entry_source is Dictionary:
			continue
		var entry: Dictionary = entry_source
		var view := SkillView.new()
		view.skill_id = str(entry.get("skill_id", ""))
		var passive: bool = bool(entry.get("is_passive", false))
		view.passive = passive
		view.active_capable = bool(entry.get("active_capable", not passive))
		view.enabled = player_actions and bool(entry.get("available", false))
		view.selected = bool(entry.get("selected", false))
		view.cooldown_turns = _nonnegative_integer(entry.get("cooldown"))
		view.action_type = StringName(str(entry.get("action_cost", "")))
		view.tooltip_text = _skill_tooltip(entry)
		if not view.is_pure_passive():
			view.resource_cost_display = _cost_display(entry.get("resource_cost_display"))
		# 键位位置属于原始主动技能顺序；不可用与冷却只能拒绝激活，不能令后续技能改号。
		if player_actions and view.active_capable and hotkey_index <= 4:
			view.hotkey_text = str(hotkey_index)
			hotkey_index += 1
		var texture: Variant = icon_textures.get(view.skill_id)
		if texture is Texture2D:
			view.icon_texture = texture
		views.append(view)
	return views


func _build_action_resources(source: Variant) -> RefCounted:
	if not _is_action_resources_valid(source):
		return null
	var resources: Dictionary = source
	var view := ActionResourceView.new()
	view.movement_remaining = int(resources["movement_remaining"])
	view.movement_available = bool(resources["movement_available"])
	view.standard_capacity = int(resources["standard_capacity"])
	view.standard_remaining = int(resources["standard_remaining"])
	view.swift_capacity = int(resources["swift_capacity"])
	view.swift_remaining = int(resources["swift_remaining"])
	return view


func _build_end_action(state: Dictionary, player_actions: bool) -> RefCounted:
	var view := EndActionView.new()
	view.visible = false
	if not player_actions or not state.get("buttons") is Dictionary:
		return view
	var buttons: Dictionary = state["buttons"]
	if bool(buttons.get("end_move_visible", false)):
		view.action_kind = EndActionView.ACTION_END_MOVE
		view.visible = true
		view.enabled = not bool(buttons.get("end_move_disabled", false))
		return view
	if bool(buttons.get("end_turn_visible", false)):
		view.action_kind = EndActionView.ACTION_END_TURN
		view.visible = true
		view.enabled = not bool(buttons.get("end_turn_disabled", false))
	return view


func _reserved_slot(slot_id: StringName, reason: String) -> RefCounted:
	var view := SlotView.new()
	view.slot_id = slot_id
	# 当前装备与遗物只预留接口；原始武器载荷保持给其他调用方使用。
	view.empty_kind = &""
	view.occupied = false
	view.locked = false
	view.enabled = false
	view.tooltip_text = reason
	return view


func _missing_potion() -> RefCounted:
	var view := PotionView.new()
	view.enabled = false
	view.tooltip_text = "暂无药剂信息"
	return view


func _reserved_relics() -> Array[RefCounted]:
	var views: Array[RefCounted] = []
	for index: int in 8:
		views.append(_reserved_slot(StringName("relic_%d" % (index + 1)), "遗物槽位预留"))
	return views


func _meter(current_value: int, maximum_value: int) -> RefCounted:
	var view := MeterView.new()
	view.current_value = current_value
	view.maximum_value = maximum_value
	return view


func _cost_display(source: Variant) -> Dictionary:
	if not source is Dictionary:
		return {}
	var amount: Variant = source.get("amount")
	var name: Variant = source.get("resource_name")
	if not _is_integer(amount) or int(amount) <= 0 or int(amount) > 999:
		return {}
	if not (name is String or name is StringName) or str(name).strip_edges().is_empty():
		return {}
	return {"amount": int(amount), "resource_name": str(name).strip_edges()}


func _skill_tooltip(entry: Dictionary) -> String:
	var lines: PackedStringArray = []
	var name: String = str(entry.get("name", "")).strip_edges()
	var description: String = str(entry.get("description", "")).strip_edges()
	var reason: String = str(entry.get("reason", "")).strip_edges()
	if not name.is_empty():
		lines.append(name)
	if not description.is_empty():
		lines.append(description)
	if not reason.is_empty():
		lines.append(reason)
	return "\n".join(lines)


func _is_action_resources_valid(source: Variant) -> bool:
	if not source is Dictionary:
		return false
	var required: Array[String] = ["movement_remaining", "movement_available", "standard_capacity", "standard_remaining", "swift_capacity", "swift_remaining"]
	for key: String in required:
		if not source.has(key):
			return false
	return (
		_is_nonnegative_integer(source["movement_remaining"])
		and typeof(source["movement_available"]) == TYPE_BOOL
		and _is_capacity(source["standard_capacity"])
		and _is_remaining(source["standard_remaining"], source["standard_capacity"])
		and _is_capacity(source["swift_capacity"])
		and _is_remaining(source["swift_remaining"], source["swift_capacity"])
	)


func _is_capacity(value: Variant) -> bool:
	return _is_integer(value) and int(value) >= 1 and int(value) <= 3


func _is_remaining(value: Variant, capacity: Variant) -> bool:
	return _is_integer(value) and _is_integer(capacity) and int(value) >= 0 and int(value) <= int(capacity)


func _is_nonnegative_integer(value: Variant) -> bool:
	return _is_integer(value) and int(value) >= 0


func _nonnegative_integer(value: Variant) -> int:
	return maxi(int(value), 0) if _is_integer(value) else 0


func _is_integer(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var numeric: float = float(value)
	return is_finite(numeric) and numeric == floor(numeric) and absf(numeric) < 9223372036854775808.0
