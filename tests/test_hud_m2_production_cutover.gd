extends SceneTree

const RuntimeDashboard := preload("res://scripts/ui/hud/m2/runtime_dashboard.gd")
const LegacyDashboard := preload("res://scripts/ui/bottom_dashboard.gd")
const SkillIconCatalog := preload("res://scripts/ui/hud/m2/skill_icon_catalog.gd")

# 只观察正式入口调用；PackedScene 原有 manager 节点保留，三个入口立即 super。
# 不替换棋盘、单位、HUD 或 forecast。正常入口与 reload 另用未经此桩的场景。
const COUNTING_MANAGER_SOURCE := """
extends TacticalManager
var skill_requests: Array[String] = []
var board_clicks: int = 0
var cancel_requests: int = 0
var display_contract_fixture: bool = false

func request_skill_selection(skill_id: String) -> void:
	skill_requests.append(skill_id)
	super.request_skill_selection(skill_id)

func handle_pointer_click(screen_pos: Vector2) -> void:
	board_clicks += 1
	super.handle_pointer_click(screen_pos)

func request_cancel_action() -> void:
	cancel_requests += 1
	super.request_cancel_action()

func get_dashboard_data() -> Dictionary:
	var state: Dictionary = super.get_dashboard_data()
	if display_contract_fixture:
		# display contract fixture：仅副本把真实斩击标为混合接口条目。
		# 此用例证明 UI 编号/分发，不宣称现行玩法支持混合技能。
		var entries: Array = (state.get("skills", []) as Array).duplicate(true)
		for entry: Dictionary in entries:
			if str(entry.get("skill_id", "")) == "swordsman_zhanji":
				entry["is_passive"] = true
				entry["active_capable"] = true
		state["skills"] = entries
	return state

"""

var _counting_manager_script: GDScript

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("=== test_hud_m2_production_cutover ===")
	# --script 的顶层继承会在 autoload 注册前编译 manager；延迟编译内嵌子类。
	_counting_manager_script = GDScript.new()
	_counting_manager_script.source_code = COUNTING_MANAGER_SOURCE
	var compile_result: Error = _counting_manager_script.reload()
	_check("autoload就绪后编译内嵌计数子类", compile_result == OK)
	if compile_result != OK:
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var scene: Node = (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var dashboard: Control = scene.get("_bottom_dashboard") as Control
	_check("正常场景使用未经计数桩的正式manager", scene.tactical_manager.get_script() == load("res://scripts/core/tactical_manager.gd"))
	_check("正式实例是M2", dashboard is RuntimeDashboard)
	_check("正式实例已由场景挂载", dashboard != null and dashboard.get_parent() == scene.get_node("UILayer"))
	var counts: Dictionary = {"m2": 0, "legacy": 0}
	_count_dashboards(scene, counts)
	_check("正式场景只有一个M2", int(counts["m2"]) == 1)
	_check("正式场景没有旧BottomDashboard", int(counts["legacy"]) == 0)
	if dashboard is RuntimeDashboard:
		_check("正式实例消费manager状态", dashboard.get_last_state() == scene.tactical_manager.get_dashboard_data())
		await _test_real_skill_icons(dashboard, scene.tactical_manager)
		var forecaster: Control = scene.get("_damage_forecaster") as Control
		_check("预测器完整尺寸包含三角", forecaster.get_visual_size().is_equal_approx(Vector2(180.0, 111.0)))
	scene.queue_free()
	await process_frame
	await _test_myrmidon_and_enemy_resources()
	await _test_formal_skill_requests()
	await _test_restricted_and_display_contract_inputs()
	await _test_live_forecast_input_and_reload()
	print("HUD_M2_PRODUCTION_CUTOVER_RESULT passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_real_skill_icons(dashboard: Control, manager: Object) -> void:
	var catalog := SkillIconCatalog.new()
	var entries: Array = manager.get_dashboard_data().get("skills", [])
	var resolved: Dictionary = catalog.resolve_entries(entries)
	_check("正式catalog按真实技能身份解析", not resolved.is_empty() and resolved.size() == entries.size())
	_check("未知技能保持缺图", catalog.resolve(&"unknown_skill") == null)
	var slots: Array = dashboard.get_composition().get_node("BottomRow/SkillShelf").get_skill_slots()
	var exact_identity: bool = slots.size() == entries.size()
	for index: int in mini(slots.size(), entries.size()):
		var skill_id := StringName(str((entries[index] as Dictionary).get("skill_id", "")))
		exact_identity = exact_identity and (slots[index] as Control).find_child("IconRect", true, false).texture == catalog.resolve(skill_id)
	_check("正式实例按skill_id显示对应图标", exact_identity)
	var one_entry: Array = [(entries[1] as Dictionary).duplicate(true)]
	dashboard.update_state({"visible": true, "mode": "player", "show_actions": true, "skills_visible": true, "skills": one_entry})
	await process_frame
	slots = dashboard.get_composition().get_node("BottomRow/SkillShelf").get_skill_slots()
	_check("切换技能清单不遗留旧图标", slots.size() == 1 and (slots[0] as Control).get("_view").skill_id == str(one_entry[0].get("skill_id", "")) and (slots[0] as Control).find_child("IconRect", true, false).texture == catalog.resolve(StringName(str(one_entry[0].get("skill_id", "")))))
	var override := GradientTexture2D.new()
	dashboard.set_icon_textures({str(one_entry[0].get("skill_id", "")): override})
	await process_frame
	_check("显式图标覆盖优先于catalog", (slots[0] as Control).find_child("IconRect", true, false).texture == override)
	dashboard.set_icon_textures({})
	dashboard.update_state(manager.get_dashboard_data())
	await process_frame


func _test_myrmidon_and_enemy_resources() -> void:
	var scene: Node = _new_injected_scene("myrmidon")
	root.add_child(scene)
	await _settle()
	var dashboard: Control = scene.get("_bottom_dashboard") as Control
	var resource_host: Control = dashboard.get_composition().get_class_resource_host()
	_check("myrmidon注入显示真实剑气且不显示印记", resource_host.visible and not resource_host.get("_view").body.marks_visible)
	var enemy: Object = scene.tactical_manager.units.filter(func(unit: Object) -> bool: return unit.faction == "enemy")[0]
	await _click(_unit_screen(scene, enemy))
	_check("无资源敌方检视不残留职业资源", str(scene.tactical_manager.get_dashboard_data().get("mode", "")) == "enemy" and not resource_host.visible)
	await _key(KEY_ESCAPE)
	_check("Escape从敌方检视返回玩家", str(scene.tactical_manager.get_dashboard_data().get("mode", "")) == "player")
	scene.queue_free()
	await process_frame


func _test_formal_skill_requests() -> void:
	# 每次使用新鲜真实 Unit，避免招架自身施放消耗行动影响下一个用例。
	var expected_ids: Array[String] = ["swordsman_zhanji", "swordsman_yishan", "swordsman_zhaojia", "swordsman_juhe"]
	for input_kind: String in ["mouse", "key"]:
		for index: int in 4:
			var scene: Node = _new_injected_scene("kensei", true)
			root.add_child(scene)
			await _settle()
			var manager: Node = scene.tactical_manager
			var player: Object = manager.current_unit
			# 实际库存来自职业上限，不覆盖 manager 的 available 或技能规则。
			player.sword_qi = player._qi_max
			if index in [0, 3]:
				await _click(_unit_screen(scene, player))
			manager.call("_emit_dashboard_state_changed")
			await _settle()
			var dashboard: Control = scene.get("_bottom_dashboard")
			var expected_id: String = expected_ids[index]
			var label: String = "%s正式主动%d %s" % [input_kind, index + 1, expected_id]
			_check_numbering(label, dashboard, manager)
			var slot: Button = _skill_slot(dashboard, expected_id)
			var entry: Dictionary = _skill_entry(manager, expected_id)
			_check(label + "真实manager判定可用且可见控件可点击", bool(entry.get("available", false)) and slot != null and slot.is_visible_in_tree() and not slot.disabled and slot.get_global_rect().has_area())
			var requests_before: int = manager.skill_requests.size()
			if input_kind == "mouse":
				await _click(slot.get_global_rect().get_center())
			else:
				await _key((KEY_1 + index) as Key)
			_check(label + "按下释放合计恰好一次正确请求", manager.skill_requests.size() == requests_before + 1 and manager.skill_requests.back() == expected_id)
			print("REQUEST %s calls=%s" % [label, manager.skill_requests])
			scene.queue_free()
			await _settle()


func _test_restricted_and_display_contract_inputs() -> void:
	var scene: Node = _new_injected_scene("kensei", true)
	root.add_child(scene)
	await _settle()
	var manager: Node = scene.tactical_manager
	var dashboard: Control = scene.get("_bottom_dashboard")
	var player: Object = manager.current_unit
	var enemy: Object = manager.units.filter(func(unit: Object) -> bool: return unit.faction == "enemy")[0]
	await _click(_unit_screen(scene, player))
	var unavailable: Dictionary = _skill_entry(manager, "swordsman_juhe")
	_check("资源不足取真实Unit库存与技能费用", player.sword_qi < int(unavailable.get("qi_cost", 0)) and not bool(unavailable.get("available", true)) and str(unavailable.get("reason", "")).contains("剑气不足"))
	var requests_before: int = manager.skill_requests.size()
	await _key(KEY_4)
	_check("真实资源不足KEY_4零请求", manager.skill_requests.size() == requests_before)
	await _click(_skill_slot(dashboard, "swordsman_juhe").get_global_rect().get_center())
	_check("真实资源不足技能点击零请求", manager.skill_requests.size() == requests_before)
	player.skill_cooldowns["swordsman_zhanji"] = 1
	manager.call("_emit_dashboard_state_changed")
	await _settle()
	unavailable = _skill_entry(manager, "swordsman_zhanji")
	_check("冷却限制来自真实Unit并显示不可用", int(unavailable.get("cooldown", 0)) > 0 and not bool(unavailable.get("available", true)) and str(unavailable.get("reason", "")).contains("冷却"))
	await _key(KEY_1)
	_check("真实冷却KEY_1零请求", manager.skill_requests.size() == requests_before)
	await _click(_skill_slot(dashboard, "swordsman_zhanji").get_global_rect().get_center())
	_check("真实冷却技能点击零请求", manager.skill_requests.size() == requests_before)
	player.skill_cooldowns.erase("swordsman_zhanji")
	manager.call("_emit_dashboard_state_changed")
	await _settle()
	var passive: Button = _skill_slot(dashboard, "swordsman_xinyan")
	_check("纯被动可检视但无主动角标", passive.is_visible_in_tree() and passive.get("_view").is_pure_passive() and not passive.get_node("%HotkeyBadge").visible)
	await _click(passive.get_global_rect().get_center())
	_check("真实纯被动点击零请求", manager.skill_requests.size() == requests_before)
	passive.release_focus()
	await _click(_unit_screen(scene, enemy))
	_check("敌方限制用例由真实点击进入检视", str(manager.get_dashboard_data().get("mode", "")) == "enemy")
	for index: int in 4:
		await _key((KEY_1 + index) as Key)
		_check("敌方检视KEY_%d零请求且保持检视" % [index + 1], manager.skill_requests.size() == requests_before and str(manager.get_dashboard_data().get("mode", "")) == "enemy")
	await _key(KEY_ESCAPE)
	_check("敌方限制用例Escape返回真实玩家状态", str(manager.get_dashboard_data().get("mode", "")) == "player")
	var real_entry: Dictionary = _skill_entry(manager, "swordsman_zhanji")
	_check("display contract fixture前真实斩击为普通主动", not bool(real_entry.get("is_passive", false)) and bool(real_entry.get("available", false)))
	manager.display_contract_fixture = true
	manager.call("_emit_dashboard_state_changed")
	await _settle()
	var mixed: Dictionary = _skill_entry(manager, "swordsman_zhanji")
	_check("display contract fixture仅标明混合显示字段", bool(mixed.get("is_passive", false)) and bool(mixed.get("active_capable", false)))
	_check_numbering("display contract fixture", dashboard, manager)
	await _key(KEY_1)
	_check("display contract fixture正式KEY_1仍恰好请求混合槽一次", manager.skill_requests.size() == requests_before + 1 and manager.skill_requests.back() == "swordsman_zhanji")
	await _right_click(Vector2(640, 320))
	manager.display_contract_fixture = false
	manager.call("_emit_dashboard_state_changed")
	await _settle()
	_check("display contract fixture关闭后真实数据完整恢复", _skill_entry(manager, "swordsman_zhanji") == real_entry)
	_check_numbering("恢复真实数据", dashboard, manager)
	requests_before = manager.skill_requests.size()
	await _key(KEY_1)
	_check("恢复真实数据后KEY_1仍恰好请求一次且进入targeting", manager.skill_requests.size() == requests_before + 1 and manager.skill_requests.back() == "swordsman_zhanji" and manager.is_targeting_active())
	scene.queue_free()
	await _settle()


func _skill_entry(manager: Object, skill_id: String) -> Dictionary:
	for entry: Dictionary in manager.get_dashboard_data().get("skills", []):
		if str(entry.get("skill_id", "")) == skill_id:
			return entry
	return {}


func _skill_slot(dashboard: Control, skill_id: String) -> Button:
	for slot: Button in dashboard.get_composition().get_node("BottomRow/SkillShelf").get_skill_slots():
		if str(slot.get("_view").skill_id) == skill_id:
			return slot
	return null


func _check_numbering(label: String, dashboard: Control, manager: Object) -> void:
	var active_index: int = 0
	var valid: bool = true
	var shelf: Control = dashboard.get_composition().get_node("BottomRow/SkillShelf")
	for entry: Dictionary in manager.get_dashboard_data().get("skills", []):
		var slot: Button = _skill_slot(dashboard, str(entry.get("skill_id", "")))
		if slot == null:
			valid = false
			continue
		var active: bool = bool(entry.get("active_capable", not bool(entry.get("is_passive", false))))
		if active:
			active_index += 1
			valid = valid and slot.get("_view").active_capable and slot.get_node("%HotkeyBadge").is_visible_in_tree() and slot.get_node("%HotkeyText").text == str(active_index)
		else:
			valid = valid and not slot.get_node("%HotkeyBadge").visible and slot.get("_view").hotkey_text.is_empty()
	_check(label + "四个主动ID与正式Shelf角标1—4一致且Shelf快捷键关闭", valid and active_index == 4 and not shelf.shortcut_input_enabled)


func _test_live_forecast_input_and_reload() -> void:
	# 与既有原生 capture 一致，让尺寸变化到达实际 viewport，验证 HUD 自身重排。
	var original_content_scale_size: Vector2i = root.content_scale_size
	root.content_scale_size = Vector2i.ZERO
	var first: Node = _new_injected_scene("kensei", true)
	root.add_child(first)
	current_scene = first
	await _settle()
	var manager: Node = first.tactical_manager
	var first_dashboard: Control = first.get("_bottom_dashboard") as Control
	var counts: Dictionary = {"m2": 0, "legacy": 0}
	_count_dashboards(first, counts)
	_check("注入入口同样只有一份M2", first_dashboard is RuntimeDashboard and int(counts["m2"]) == 1 and int(counts["legacy"]) == 0)
	var player: Object = manager.units.filter(func(unit: Object) -> bool: return unit.faction == "player")[0]
	var enemy: Object = manager.units.filter(func(unit: Object) -> bool: return unit.faction == "enemy")[0]
	await _click(_unit_screen(first, player))
	var selection_transitions: Array[String] = []
	var last_selected: Array[String] = [manager.get_selected_skill_id()]
	manager.dashboard_state_changed.connect(func() -> void:
		var current_selected: String = manager.get_selected_skill_id()
		if current_selected != last_selected[0]:
			selection_transitions.append(current_selected)
			last_selected[0] = current_selected
	)
	await _key(KEY_1)
	var selected_after_key: String = manager.get_selected_skill_id()
	_check("正式数字键只产生一次技能选择状态及一次请求", selected_after_key == "swordsman_zhanji" and selection_transitions.count(selected_after_key) == 1 and manager.skill_requests == ["swordsman_zhanji"])
	await _right_click(Vector2(640, 320))
	_check("真实右键点击调用一次取消并退出targeting", manager.cancel_requests == 1 and not manager.is_targeting_active())
	var before_restricted: int = selection_transitions.size()
	var requests_before_restricted: int = manager.skill_requests.size()
	player.skill_cooldowns["swordsman_zhanji"] = 1
	manager.call("_emit_dashboard_state_changed")
	await process_frame
	await _key(KEY_1)
	_check("冷却限制态不激活技能", selection_transitions.size() == before_restricted and manager.get_selected_skill_id().is_empty() and manager.skill_requests.size() == requests_before_restricted)
	player.skill_cooldowns.erase("swordsman_zhanji")
	manager.call("_emit_dashboard_state_changed")
	await process_frame
	await _key(KEY_1)
	await _move_pointer(_unit_screen(first, enemy))
	var forecast: Dictionary = manager.get_dashboard_data().get("forecast", {})
	var forecaster: Control = first.get("_damage_forecaster") as Control
	_check("合法目标鼠标移动由manager生成非空forecast", manager.is_targeting_active() and not forecast.is_empty() and bool(forecast.get("visible", false)) and not (forecast.get("targets", []) as Array).is_empty() and forecaster.is_visible_in_tree())
	var heads_before: Array[int] = _instance_ids(first.get("_forecast_head_nodes"))
	_check("真实forecast产生非空头顶节点", not heads_before.is_empty())
	var character: Control = first_dashboard.get_composition().get_node("BottomRow/CharacterHudPanel") as Control
	var card: Control = character.get_inspection_panel()
	var no_card_top: float = first_dashboard.get_content_top_y()
	_check("打开浮卡前人物卡未显示", not card.is_visible_in_tree())
	character.get_inspection_control().grab_focus()
	await _settle()
	await _check_forecaster_clearance("人物浮卡", first, first_dashboard, forecaster, card, no_card_top, heads_before)
	var character_top: float = first_dashboard.get_content_top_y()
	var heads_character: Array[int] = _instance_ids(first.get("_forecast_head_nodes"))
	character.get_inspection_control().release_focus()
	var passive: Control = (first_dashboard.get_composition().get_node("BottomRow/SkillShelf").get_skill_slots() as Array)[0]
	_check("浮卡目标确为真实纯被动", passive.get("_view").is_pure_passive())
	passive.grab_focus()
	await _settle()
	_check("切换到被动卡后人物卡已关闭且content_top_y改变", not card.is_visible_in_tree() and not is_equal_approx(first_dashboard.get_content_top_y(), character_top))
	await _check_forecaster_clearance("纯被动浮卡", first, first_dashboard, forecaster, passive.get_inspection_panel(), no_card_top, heads_before)
	var passive_rect_before_resize: Rect2 = passive.get_inspection_panel().get_global_rect()
	root.size = Vector2i(1920, 1080)
	await _settle()
	_check("缩放确实到达1920x1080viewport并改变浮卡实际矩形", root.get_visible_rect().size == Vector2(1920, 1080) and first_dashboard.get_composition().scale.is_equal_approx(Vector2(1.5, 1.5)) and passive.get_inspection_panel().get_global_rect() != passive_rect_before_resize)
	await _check_forecaster_clearance("纯被动浮卡和缩放", first, first_dashboard, forecaster, passive.get_inspection_panel(), no_card_top * 1.5, heads_before)
	_check("可见预测器重排不重建非空头顶节点", not heads_before.is_empty() and heads_before == heads_character and heads_character == _instance_ids(first.get("_forecast_head_nodes")))
	root.size = Vector2i(1280, 720)
	passive.release_focus()
	await _settle()
	var input_before: Variant = manager.input_state
	var resource_host: Control = first_dashboard.get_composition().get_class_resource_host()
	_check("资源实体点击前控件可见且矩形有效", resource_host.is_visible_in_tree() and resource_host.get_global_rect().has_area())
	var board_before: int = manager.board_clicks
	await _click(resource_host.get_global_rect().get_center())
	_check("点击资源实体不发送棋盘点击", manager.board_clicks == board_before and manager.input_state == input_before)
	print("POINTER resource board_delta=%d" % [manager.board_clicks - board_before])
	var transparent_point := Vector2(450, 580)
	_move_pointer(transparent_point)
	await process_frame
	_check("共享透明区域允许棋盘输入", root.gui_get_hovered_control() == null and not first.call("_should_ignore_board_pointer"))
	board_before = manager.board_clicks
	await _click(transparent_point)
	_check("共享透明区域真实点击恰好发送一次棋盘请求", manager.board_clicks == board_before + 1)
	print("POINTER transparent board_delta=%d" % [manager.board_clicks - board_before])
	if not manager.is_targeting_active():
		await _key(KEY_1)
	_check("右键拖动前处于targeting", manager.is_targeting_active())
	var camera: Camera2D = first.get("_camera") as Camera2D
	var camera_before: Vector2 = camera.position
	var cancel_before: int = manager.cancel_requests
	await _drag(MOUSE_BUTTON_RIGHT, Vector2(640, 320), Vector2(680, 340))
	_check("右键拖动平移且零取消并保持targeting", camera.position != camera_before and manager.cancel_requests == cancel_before and manager.is_targeting_active())
	print("DRAG right camera_delta=%s cancel_delta=%d targeting=%s" % [camera.position - camera_before, manager.cancel_requests - cancel_before, manager.is_targeting_active()])
	camera_before = camera.position
	cancel_before = manager.cancel_requests
	_check("中键拖动前处于targeting", manager.is_targeting_active())
	await _drag(MOUSE_BUTTON_MIDDLE, Vector2(640, 320), Vector2(620, 350))
	_check("中键拖动平移且零取消并保持targeting", camera.position != camera_before and manager.cancel_requests == cancel_before and manager.is_targeting_active())
	print("DRAG middle camera_delta=%s cancel_delta=%d targeting=%s" % [camera.position - camera_before, manager.cancel_requests - cancel_before, manager.is_targeting_active()])
	character.get_inspection_control().grab_focus()
	await _settle()
	_check("卸载前人物浮卡已打开", card.visible)
	manager.stop_battle()
	await process_frame
	_check("停止战斗后正式底栏无可见阻挡", first_dashboard.get_input_blocking_rects().is_empty())
	first.queue_free()
	current_scene = null
	await process_frame
	_check("注入场景释放后宿主与已开浮卡失效", not is_instance_valid(first_dashboard) and not is_instance_valid(card))
	root.content_scale_size = original_content_scale_size
	var reload_source: Node = (load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene).instantiate()
	root.add_child(reload_source)
	current_scene = reload_source
	await _settle()
	var reload_dashboard: Control = reload_source.get("_bottom_dashboard") as Control
	reload_source.call("_end_battle", "victory")
	await process_frame
	var return_button: Button = reload_source.get_node("UILayer/ReturnButton") as Button
	_check("战斗结束后ReturnButton真实可操作", return_button.visible and not return_button.disabled)
	_check("ReturnButton点击中心位于真实可见矩形", return_button.is_visible_in_tree() and return_button.get_global_rect().has_area() and root.get_visible_rect().encloses(return_button.get_global_rect()))
	await _click(return_button.get_global_rect().get_center())
	for frame: int in 12:
		await process_frame
		if current_scene != reload_source:
			break
	var second: Node = current_scene
	_check("ReturnButton经真实current_scene完成reload", second != null and second != reload_source and not is_instance_valid(reload_dashboard))
	counts = {"m2": 0, "legacy": 0}
	_count_dashboards(second, counts)
	_check("重载后仅创建一份新M2", second.get("_bottom_dashboard") is RuntimeDashboard and int(counts["m2"]) == 1 and int(counts["legacy"]) == 0)
	_check("重载后仍使用未经计数桩的正式manager", second.tactical_manager.get_script() == load("res://scripts/core/tactical_manager.gd"))
	second.queue_free()
	current_scene = null
	await process_frame


func _check_forecaster_clearance(label: String, scene: Node, dashboard: Control, forecaster: Control, card: Control, no_card_top: float, expected_heads: Array[int]) -> void:
	var previous_rect := Rect2()
	for frame: int in 2:
		await process_frame
		var card_rect: Rect2 = card.get_global_rect()
		var visual_rect := Rect2(forecaster.position, forecaster.get_visual_size())
		var content_top: float = dashboard.get_content_top_y()
		_check("%s第%d帧浮卡可见且实际Rect2有效" % [label, frame + 1], card.is_visible_in_tree() and card_rect.has_area() and root.get_visible_rect().encloses(card_rect) and dashboard.get_input_blocking_rects().has(card_rect))
		_check("%s第%d帧content_top_y随当前卡上移" % [label, frame + 1], content_top < no_card_top and is_equal_approx(content_top, card_rect.position.y))
		_check("%s第%d帧完整180x111预测矩形与卡不相交且留8px" % [label, frame + 1], forecaster.is_visible_in_tree() and visual_rect.size.is_equal_approx(Vector2(180, 111)) and not visual_rect.intersects(card_rect) and visual_rect.end.y <= content_top - 8.0 + 0.01)
		var ids: Array[int] = _instance_ids(scene.get("_forecast_head_nodes"))
		_check("%s第%d帧非空头顶节点ID不变" % [label, frame + 1], not ids.is_empty() and ids == expected_heads)
		if frame > 0:
			_check(label + "连续两帧预测器位置稳定", visual_rect == previous_rect)
		previous_rect = visual_rect
		print("GEOMETRY %s frame=%d card=%s forecast=%s content_top_y=%s heads=%s" % [label, frame + 1, card_rect, visual_rect, content_top, ids])


func _instance_ids(nodes: Array) -> Array[int]:
	var ids: Array[int] = []
	for node: Node in nodes:
		ids.append(node.get_instance_id())
	return ids


func _new_injected_scene(player_class: String, count_inputs: bool = false) -> Node:
	var first: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	if count_inputs:
		first.get_node("TacticalManager").set_script(_counting_manager_script)
	first.run_injected = true
	first.debug_harness_enabled = false
	first.injected_map_id = "forest_01"
	first.injected_player_units = [{"class_id": player_class, "pos": Vector2i(1, 2)}]
	first.injected_enemy_units = [{"class_id": "goblin_melee", "pos": Vector2i(2, 2)}]
	return first


func _unit_screen(scene: Node, unit: Object) -> Vector2:
	return scene.get_viewport().get_canvas_transform() * scene.tactical_manager.grid.grid_to_world(unit.grid_position)


func _count_dashboards(node: Node, counts: Dictionary) -> void:
	if node is RuntimeDashboard:
		counts["m2"] = int(counts["m2"]) + 1
	if node is LegacyDashboard:
		counts["legacy"] = int(counts["legacy"]) + 1
	for child: Node in node.get_children():
		_count_dashboards(child, counts)


func _settle() -> void:
	await process_frame
	await process_frame


func _move_pointer(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	root.push_input(event, true)


func _click(position: Vector2) -> void:
	_move_pointer(position)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


func _right_click(position: Vector2) -> void:
	_move_pointer(position)
	await process_frame
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


func _key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		event.keycode = keycode
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame


func _drag(button: MouseButton, from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.position = from
	press.global_position = from
	press.button_index = button
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.global_position = to
	motion.relative = to - from
	root.push_input(motion, true)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = to
	release.global_position = to
	release.button_index = button
	release.pressed = false
	root.push_input(release, true)
	await process_frame


func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("PASS: " + label)
	else:
		_failed += 1
		printerr("FAIL: " + label)
