extends SceneTree

const Adapter := preload("res://scripts/ui/hud/m2/dashboard_view_adapter.gd")

var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_real_tactical_weapon_payloads()
	_test_adapter_reserved_slots()
	print("HUD_M2_WEAPON_DISPLAY_RESULT passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


func _test_real_tactical_weapon_payloads() -> void:
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var manager: Object = scene.tactical_manager
	_check("真实 TacticalManager 可用", manager != null)
	if manager == null:
		scene.free()
		return
	var player: Unit = manager._get_dashboard_unit()
	_check("真实玩家仪表盘单位可用", player != null)
	if player != null:
		var player_before: Dictionary = _unit_snapshot(player)
		var loader: Node = root.get_node_or_null("DataLoader")
		var player_weapon_before: Dictionary = loader.weapons.get(player.weapon_id, {}).duplicate(true) if loader != null else {}
		var player_state: Dictionary = manager.get_dashboard_data()
		_assert_weapon_display("玩家武器来自当前单位和 DataLoader", player_state, player, loader)
		_check("读取玩家武器不修改单位", _unit_snapshot(player) == player_before)
		_check("读取玩家武器不修改数据记录", loader != null and loader.weapons.get(player.weapon_id, {}) == player_weapon_before)
		var saved_player_weapon_id: String = player.weapon_id
		player.weapon_id = ""
		_check("缺少武器 ID 返回空对象", (manager.get_dashboard_data().get("weapon_display", {}) as Dictionary).is_empty())
		player.weapon_id = "wpn_unknown_for_hud_m2_test"
		_check("未知武器 ID 返回空对象", (manager.get_dashboard_data().get("weapon_display", {}) as Dictionary).is_empty())
		player.weapon_id = saved_player_weapon_id
	var enemy: Unit = _first_enemy(manager.units)
	_check("真实 TacticalScene 敌方单位可用", enemy != null)
	if enemy != null:
		var enemy_before: Dictionary = _unit_snapshot(enemy)
		var loader: Node = root.get_node_or_null("DataLoader")
		var enemy_weapon_before: Dictionary = loader.weapons.get(enemy.weapon_id, {}).duplicate(true) if loader != null else {}
		manager._show_enemy_info(enemy)
		var enemy_state: Dictionary = manager.get_dashboard_data()
		_assert_weapon_display("敌方武器来自当前检视单位和 DataLoader", enemy_state, enemy, loader)
		_check("读取敌方武器不修改单位", _unit_snapshot(enemy) == enemy_before)
		_check("读取敌方武器不修改数据记录", loader != null and loader.weapons.get(enemy.weapon_id, {}) == enemy_weapon_before)
	scene.free()


func _test_adapter_reserved_slots() -> void:
	var adapter := Adapter.new()
	var source: Dictionary = {"visible": true, "weapon_display": {"content_id": "wpn_swordsman_starter", "display_name": "剑圣初始太刀"}}
	var before: Dictionary = source.duplicate(true)
	var texture := GradientTexture2D.new()
	for mode: String in ["player", "enemy"]:
		var state: Dictionary = source.duplicate(true)
		state["mode"] = mode
		var mapped: Dictionary = adapter.build(state, {"wpn_swordsman_starter": texture})
		_assert_reserved_slot(mode + " 有效武器与纹理仍为空槽", mapped["weapon"], &"weapon")
		_assert_reserved_slot(mode + " 护甲保持空槽", mapped["armor"], &"armor")
		_check(mode + " 保留八个遗物接口", mapped["relics"].size() == 8)
		for index: int in mapped["relics"].size():
			_assert_reserved_slot(mode + " 遗物保持空槽", mapped["relics"][index], StringName("relic_%d" % (index + 1)))
	var no_texture: RefCounted = adapter.build(source)["weapon"]
	_check("适配器不修改武器输入", source == before)
	_assert_reserved_slot("缺少纹理保持相同空槽", no_texture, &"weapon")
	for malformed: Variant in [null, {}, {"content_id": "", "display_name": "名称"}, {"content_id": 1, "display_name": "名称"}, {"content_id": "weapon", "display_name": ""}, {"content_id": "weapon", "display_name": 2}]:
		var state := {"visible": true, "weapon_display": malformed}
		var missing: RefCounted = adapter.build(state)["weapon"]
		_assert_reserved_slot("非法武器字段仍保持预留接口", missing, &"weapon")


func _assert_reserved_slot(label: String, view: RefCounted, slot_id: StringName) -> void:
	_check(label + " 的接口标识保留", view.slot_id == slot_id)
	_check(label + " 无内容和图标", not view.occupied and view.content_id.is_empty() and view.icon_texture == null and view.empty_kind == &"")
	_check(label + " 无锁定且不可请求", not view.locked and not view.enabled and not view.can_request())


func _assert_weapon_display(label: String, state: Dictionary, unit: Unit, loader: Node) -> void:
	_check(label + " 的数据加载器可用", loader != null)
	if loader == null:
		return
	var expected: Dictionary = loader.weapons.get(unit.weapon_id, {})
	var display: Dictionary = state.get("weapon_display", {}) as Dictionary
	_check(label, display == {"content_id": unit.weapon_id, "display_name": str(expected.get("name", "")).strip_edges()})


func _first_enemy(units: Array) -> Unit:
	for unit: Variant in units:
		if unit is Unit and unit.faction == "enemy":
			return unit
	return null


func _unit_snapshot(unit: Unit) -> Dictionary:
	return {"weapon_id": unit.weapon_id, "unit_name": unit.unit_name, "faction": unit.faction}


func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + label)
