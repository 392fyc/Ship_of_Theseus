extends SceneTree

var _failed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	if not OS.get_cmdline_user_args().has("--expect-main-preview"):
		scene.run_injected = true
		scene.injected_map_id = "test_arena"
		scene.injected_player_units = [{"class_id": "myrmidon", "pos": Vector2i(1, 2)}]
		scene.injected_enemy_units = [{"class_id": "test_lancer", "pos": Vector2i(5, 2)}]
	scene.debug_harness_enabled = false
	root.add_child(scene)
	await process_frame
	await process_frame

	var manager: Node = scene.get_node("TacticalManager")
	var unit: Node = manager.units[0] as Node
	var dashboard: Control = scene.get("_bottom_dashboard") as Control
	var state: Dictionary = dashboard.get_last_state()
	var metadata: Dictionary = state.get("class_resource_display", {})
	_check("剑士职业", unit.unit_id == "myrmidon" and str(metadata.get("class_id", "")) == "myrmidon")
	_check("剑士拥有剑气", unit._qi_max == 100 and int(state.get("sword_qi_max", 0)) == 100)
	_check("剑士印记容量为零", unit._mark_max == 0 and int(metadata.get("mark_capacity", -1)) == 0)
	_check("界面不发送印记状态", state.get("marks", {}) == {})
	_check("印记面板隐藏", not dashboard.get_composition().get_marks_panel().visible)
	_check("剑士无法获得印记", unit.gain_random_mark() == "" and unit.get_mark_count() == 0)
	var character: Control = dashboard.get_composition().get_node("BottomRow/CharacterHudPanel") as Control
	var portrait: TextureRect = character.get_node("PortraitContent") as TextureRect
	_check("剑士显示正式头像", portrait.texture is AtlasTexture and not character.get_node("PortraitFallback").visible)

	var shelf: Control = dashboard.get_composition().get_node("BottomRow/SkillShelf") as Control
	var slots: Array = shelf.get_skill_slots()
	_check("基础剑士显示五张技能图", slots.size() == 5)
	for slot: Button in slots:
		var skill_id: String = slot._view.skill_id
		var icon: TextureRect = slot.get_node("%IconRect") as TextureRect
		var icon_path: String = "res://assets/ui/skills/myrmidon/%s.png" % skill_id.trim_prefix("swordsman_")
		_check("正式图标：" + skill_id, icon.texture != null and icon.texture.resource_path == icon_path)
	for source: Variant in state.get("skills", []):
		if source is Dictionary:
			var entry: Dictionary = source
			_check("剑士技能说明不提印记：" + str(entry.get("skill_id", "")), not str(entry.get("description", "")).contains("印记"))

	scene.queue_free()
	await process_frame
	print("MYRMIDON_QI_ONLY_RESULT failed=%d" % _failed)
	quit(0 if _failed == 0 else 1)


func _check(label: String, passed: bool) -> void:
	if not passed:
		_failed += 1
		push_error(label)
