extends SceneTree

var _pass := 0
var _fail := 0
var _ran := false


func _initialize() -> void:
	print("=== test_unit_map_token_visual ===")


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var data_loader: Node = load("res://scripts/data/data_loader.gd").new()
	data_loader.call("load_all")
	var packed := load("res://scenes/tactical/Unit.tscn") as PackedScene
	_check("Unit 场景可加载", packed != null)
	if packed == null:
		_finish()
		return
	var kensei: Unit = packed.instantiate()
	kensei.faction = "player"
	root.add_child(kensei)
	var required_methods: Array[String] = [
		"set_facing", "get_facing", "refresh_map_token_visual",
		"has_runtime_map_token", "get_combat_text_anchor_world",
	]
	for method_name: String in required_methods:
		_check("Unit 提供 %s" % method_name, kensei.has_method(method_name))
	var token_view := kensei.get_node_or_null("MapTokenView") as Sprite2D
	_check("Unit 包含 MapTokenView", token_view != null)
	if token_view == null or not _has_all_methods(kensei, required_methods):
		kensei.queue_free()
		data_loader.free()
		_finish()
		return

	kensei.call("setup", data_loader.get("classes")["kensei"], &"SE")
	var placeholder_sprite := kensei.get_node("Sprite") as AnimatedSprite2D
	var health_bar := kensei.get_node("HealthBar") as ProgressBar
	_check("剑圣启用正式棋子", kensei.call("has_runtime_map_token"))
	_check("正式棋子显示且占位隐藏", token_view.visible and not placeholder_sprite.visible)
	_check("初始方向 SE", kensei.call("get_facing") == &"SE")
	_check("正式棋子不使用阵营染色", token_view.self_modulate == Color.WHITE)
	_check("占位职业文字不存在", kensei.get_node_or_null("UnitLabel") == null)
	_check("血条底边为 -58", is_equal_approx(health_bar.position.y + health_bar.size.y, -58.0))
	_check("状态锚点为 -84", is_equal_approx(float(kensei.get("_status_badge_y")), -84.0))
	_check("实际文字锚点为 -82", (kensei.call("get_combat_text_anchor_world", -50.0) as Vector2).is_equal_approx(kensei.global_position + Vector2(0, -82)))
	kensei.equip_offhand("wpn_swordsman_starter")
	_check("装副手切到双武器行", token_view.frame_coords.y == 1)
	kensei.unequip_offhand()
	_check("卸副手切回单武器行", token_view.frame_coords.y == 0)
	kensei.call("_set_walk_direction", Vector2i(1, -1))
	_check("多轴移动 Y 优先为 NE", kensei.call("get_facing") == &"NE")

	var placeholder: Unit = packed.instantiate()
	placeholder.faction = "enemy"
	root.add_child(placeholder)
	placeholder.call("setup", data_loader.get("classes")["soldier"], &"NW")
	var placeholder_token := placeholder.get_node("MapTokenView") as Sprite2D
	var placeholder_sprite_node := placeholder.get_node("Sprite") as AnimatedSprite2D
	_check("占位单位不启用正式棋子", not placeholder.call("has_runtime_map_token"))
	_check("占位单位显示原 Sprite", placeholder_sprite_node.visible and not placeholder_token.visible)
	_check("占位单位保留阵营染色", placeholder_sprite_node.self_modulate == Unit.FACTION_COLORS["enemy"])
	_check("占位单位保留旧文字锚点", (placeholder.call("get_combat_text_anchor_world", -50.0) as Vector2).is_equal_approx(placeholder.global_position + Vector2(0, -50)))

	var broken: Unit = packed.instantiate()
	root.add_child(broken)
	var broken_data: Dictionary = data_loader.get("classes")["kensei"].duplicate(true)
	broken_data["map_token_profile_id"] = "missing_profile"
	broken.call("setup", broken_data, &"SW")
	_check("坏配置降级为占位", not broken.call("has_runtime_map_token"))
	_check("坏配置占位 Sprite 可见", (broken.get_node("Sprite") as AnimatedSprite2D).visible)
	_check("坏配置正式棋子隐藏", not (broken.get_node("MapTokenView") as Sprite2D).visible)

	kensei.take_damage(kensei.stats.hp)
	await process_frame
	await process_frame
	_check("正式棋子致死后无需等待动画即释放", not is_instance_valid(kensei))
	placeholder.queue_free()
	broken.queue_free()
	data_loader.free()
	_finish()


func _has_all_methods(unit: Unit, methods: Array[String]) -> bool:
	for method_name: String in methods:
		if not unit.has_method(method_name):
			return false
	return true


func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
		print("  ✓ " + label)
	else:
		_fail += 1
		push_error(label)


func _finish() -> void:
	print("--- %d pass / %d fail ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
