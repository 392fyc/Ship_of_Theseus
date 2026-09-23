class_name HudSkillSlotButton
extends Button

signal skill_activated(skill_id: String)

# Godot 的 `--script` 不会刷新全局 class_name 缓存。通过资源路径预加载仍可
# 保留静态类型，同时让全新工作区的无界面测试不依赖预先打开编辑器。
const SkillSlotViewData := preload("res://scripts/ui/hud/skill_slot_view_data.gd")

var _view: SkillSlotViewData = null

@onready var _icon_rect: TextureRect = %IconRect
@onready var _cooldown_shade: Control = %CooldownShade
@onready var _cooldown_turns_label: Label = %CooldownTurnsLabel
@onready var _selected_overlay: Control = %SelectedOverlay
@onready var _hotkey_badge: Control = %HotkeyBadge
@onready var _hotkey_text: Label = %HotkeyText
@onready var _charge_text: Label = %ChargeText


func _ready() -> void:
	pressed.connect(_on_pressed)
	if _view != null:
		_apply_view_to_nodes()


func apply_view(view: SkillSlotViewData) -> void:
	_view = view
	if is_node_ready():
		_apply_view_to_nodes()


func _apply_view_to_nodes() -> void:
	var remaining_turns: int = maxi(_view.cooldown_turns, 0)
	_icon_rect.texture = _view.icon_texture
	_hotkey_text.text = _view.hotkey_text
	_hotkey_badge.visible = _view.hotkey_text != ""
	_charge_text.text = str(_view.charges) if _view.show_charges else ""
	_charge_text.visible = _view.show_charges
	_cooldown_shade.visible = remaining_turns > 0
	_cooldown_turns_label.text = str(remaining_turns) if remaining_turns > 0 else ""
	_cooldown_turns_label.visible = remaining_turns > 0
	_selected_overlay.visible = _view.selected
	tooltip_text = _view.tooltip_text
	disabled = not _view.can_activate()


func _on_pressed() -> void:
	if _view != null and _view.can_activate():
		skill_activated.emit(_view.skill_id)
