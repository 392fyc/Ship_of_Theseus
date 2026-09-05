extends "res://scripts/ui/hud/skill_slot_button.gd"
## 正式技能信息附加到冻结按钮；激活、冷却和选中继续由父组件负责。

var _title: String = ""
var _cost_text: String = ""
var _accent: Color = Color.WHITE


func configure_entry(entry: Dictionary, view: SkillSlotViewData, cost_text: String, accent: Color) -> void:
	_title = str(entry.get("name", entry.get("skill_id", "")))
	_cost_text = cost_text
	_accent = accent
	apply_view(view)


func _apply_view_to_nodes() -> void:
	super._apply_view_to_nodes()
	var placeholder: Label = get_node("Content/IconPlaceholder") as Label
	var title_label: Label = get_node("NameLabel") as Label
	var cost_label: Label = get_node("Content/CostLabel") as Label
	placeholder.text = _title.left(1) if _title != "" else "技"
	title_label.text = _title
	cost_label.text = _cost_text
	cost_label.visible = _cost_text != "" and _view.cooldown_turns <= 0
	var unavailable: bool = not _view.enabled and not _view.passive
	placeholder.add_theme_color_override(&"font_color", Color(0.78, 0.80, 0.84) if unavailable else _accent)
	title_label.add_theme_color_override(&"font_color", Color(0.78, 0.80, 0.84) if unavailable else Color(0.90, 0.86, 0.78))
	cost_label.add_theme_color_override(&"font_color", Color(1.0, 0.55, 0.46) if unavailable else Color(0.373, 0.659, 0.847))
	# 纯被动仍由父组件禁止激活，禁用按钮皮肤不会掩盖其正常说明内容。
	if _view.passive and not _view.active_capable:
		add_theme_stylebox_override(&"disabled", get_theme_stylebox(&"normal"))
	else:
		remove_theme_stylebox_override(&"disabled")


func _make_custom_tooltip(for_text: String) -> Object:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.05, 0.11, 0.97)
	style.border_color = Color(0.45, 0.38, 0.22, 0.70)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 9.0
	style.content_margin_right = 9.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	panel.add_theme_stylebox_override(&"panel", style)
	var label := Label.new()
	label.text = for_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(248.0, 0.0)
	label.add_theme_font_size_override(&"font_size", 12)
	label.add_theme_color_override(&"font_color", Color(0.90, 0.86, 0.78))
	panel.add_child(label)
	return panel
