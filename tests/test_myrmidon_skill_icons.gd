extends SceneTree

const Catalog := preload("res://scripts/ui/hud/m2/skill_icon_catalog.gd")
const SKILLS := ["xinyan", "zhanji", "yishan", "zhaojia", "juhe"]

var _failed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var catalog: RefCounted = Catalog.new()
	for skill: String in SKILLS:
		var id := StringName("swordsman_" + skill)
		var texture: Texture2D = catalog.resolve(id, &"myrmidon")
		_check("剑士图标存在且为 104 像素: " + skill, texture != null and texture.get_size() == Vector2(104, 104))
		if texture != null:
			_check("剑士图标路径: " + skill, texture.resource_path == "res://assets/ui/skills/myrmidon/%s.png" % skill)
		var legacy: Texture2D = catalog.resolve(id, &"kensei")
		_check("剑圣保留原图标: " + skill, legacy != null and legacy.resource_path == "res://assets/prototype/hud_m2/skill-%s.png" % skill)
		var unknown: Texture2D = catalog.resolve(id, &"unknown")
		_check("未登记职业回退默认图标: " + skill, unknown == legacy)
	var missing_override: RefCounted = Catalog.new()
	missing_override._class_paths = {"myrmidon": {"swordsman_zhanji": "res://assets/ui/skills/myrmidon/missing.png"}}
	_check("职业图标资源失效时回退默认图标", missing_override.resolve(&"swordsman_zhanji", &"myrmidon") == catalog.resolve(&"swordsman_zhanji", &"kensei"))
	await _check_real_scene("myrmidon", "res://assets/ui/skills/myrmidon/")
	await _check_real_scene("kensei", "res://assets/prototype/hud_m2/skill-")
	print("MYRMIDON_SKILL_ICON_RESULT failed=%d" % _failed)
	quit(0 if _failed == 0 else 1)


func _check_real_scene(class_id: String, expected_prefix: String) -> void:
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	scene.run_injected = true
	scene.injected_map_id = "test_arena"
	scene.injected_player_units = [{"class_id": class_id, "pos": Vector2i(1, 2)}]
	scene.injected_enemy_units = [{"class_id": "test_lancer", "pos": Vector2i(5, 2)}]
	scene.debug_harness_enabled = false
	root.add_child(scene)
	await process_frame
	await process_frame
	var dashboard: Control = scene.get("_bottom_dashboard") as Control
	var shelf: Control = dashboard.get_composition().get_node("BottomRow/SkillShelf") as Control
	var slots: Array = shelf.get_skill_slots()
	_check("%s 正式技能栏显示五个技能" % class_id, slots.size() == 5)
	for slot: Button in slots:
		var skill_id: String = slot._view.skill_id
		var icon: TextureRect = slot.get_node("%IconRect") as TextureRect
		var name: String = skill_id.trim_prefix("swordsman_")
		var expected: String = expected_prefix + name + ".png"
		_check("%s 正式技能栏使用 %s 对应图标" % [class_id, name], icon.texture != null and icon.texture.resource_path == expected)
	if class_id == "myrmidon":
		var no_metadata: Dictionary = dashboard.get_last_state()
		no_metadata.erase("class_resource_display")
		dashboard.update_state(no_metadata)
		_check("缺少职业元数据时回退默认图标", ((slots[1] as Button).get_node("%IconRect") as TextureRect).texture.resource_path == "res://assets/prototype/hud_m2/skill-zhanji.png")
		var override := GradientTexture2D.new()
		dashboard.set_icon_textures({"swordsman_zhanji": override})
		var zhanji: Button = slots[1] as Button
		_check("调用方显式图标覆盖仍优先", (zhanji.get_node("%IconRect") as TextureRect).texture == override)
	scene.queue_free()
	await process_frame


func _check(label: String, passed: bool) -> void:
	if not passed:
		_failed += 1
		push_error(label)
