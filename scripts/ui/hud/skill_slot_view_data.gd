class_name HudSkillSlotViewData
extends RefCounted

var skill_id: String = ""
var icon_texture: Texture2D = null
var hotkey_text: String = ""
var enabled: bool = true
var selected: bool = false
var cooldown_turns: int = 0
var charges: int = 0
var show_charges: bool = false
var passive: bool = false
var active_capable: bool = false
var tooltip_text: String = ""


func can_activate() -> bool:
	return skill_id != "" and active_capable and enabled and cooldown_turns <= 0
