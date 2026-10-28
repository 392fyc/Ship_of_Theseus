extends SceneTree
## 原画棋子真实战斗入口中的固定头顶血条、职业图标与交互详情回归。

const BATTLE_SCENE: String = "res://scenes/tactical/character_pipeline/portrait_token_battle.tscn"
const LAYOUT_ID: String = "portrait_courtyard"
const HEAD_GAP: float = 5.0
const CLASS_BADGE_SIZE: Vector2 = Vector2(17.0, 17.0)
const CLASS_BADGE_OFFSET: Vector2 = Vector2(14.5, -8.5)

var checks: int = 0
var failures: Array[String] = []
var session: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	seed(20261027)
	session = load(BATTLE_SCENE).instantiate()
	root.add_child(session)
	await wait(0.2)

	var battle: Node = session.get("battle") as Node
	var manager: Node = session.get("manager") as Node
	var layout: Control = _overhead_layout(battle)
	_check("进入真实 portrait_token_battle / TacticalScene 四单位战斗",
		battle != null and manager != null and manager.units.size() == 4 and layout != null)
	if battle == null or manager == null or layout == null or manager.units.size() != 4:
		_finish()
		return
	_check_original_ring_geometry(manager)
	_check("本入口启用 owner anchored，且没有打开测试 AI harness",
		bool(layout.get("_owner_anchored")) and not bool(manager.get("debug_harness_active"))
		and not bool(battle.get("debug_harness_enabled")))
	_check("战斗处于运行态且当前由玩家行动", bool(manager.get("battle_active"))
		and manager.current_unit != null and manager.current_unit.faction == "player")

	layout.call("refresh_layout")
	await frames(2)
	var initial_snapshot: Dictionary = layout.call("get_debug_snapshot")
	_check("开场四个单位都只有固定头顶小血条",
		_check_live_rows("开场", initial_snapshot, layout) == 4)
	print("PORTRAIT_OVERHEAD_OPENING_PLACEMENT=", JSON.stringify(_placement_state(initial_snapshot)))

	var actor: Unit = manager.current_unit as Unit
	var target: Unit = _find_unit_at(manager.units, Vector2i(4, 4))
	_check("当前玩家与中庭目标枪兵存在", actor != null and actor.faction == "player"
		and target != null and target.faction == "enemy")
	if actor == null or target == null:
		_finish()
		return
	var empty_cell: Vector2i = _find_empty_cell(manager)
	_check("真实战场存在未占据格用于离开悬浮详情", empty_cell != Vector2i(-1, -1))
	manager.handle_pointer_hover(_screen_for_cell(manager, target.grid_position))
	await frames(3)
	var ordinary_hover: Dictionary = _hover_detail_snapshot(session)
	_check("普通单位悬停显示短名和真实 HP，且归属目标实例",
		bool(ordinary_hover.get("visible", false))
		and int(ordinary_hover.get("instance", 0)) == target.get_instance_id()
		and str(ordinary_hover.get("text", "")) == "%s · HP %d/%d" % [
			target.get_short_label(), target.stats.hp, target.stats.max_hp]
		and _rect_has_area(ordinary_hover.get("rect", Rect2())))
	if empty_cell != Vector2i(-1, -1):
		manager.handle_pointer_hover(_screen_for_cell(manager, empty_cell))
		await frames(3)
		var left_hover: Dictionary = _hover_detail_snapshot(session)
		_check("指针离开单位后悬浮详情隐藏并清空实例归属",
			not bool(left_hover.get("visible", true))
			and int(left_hover.get("instance", -1)) == 0
			and not _rect_has_area(left_hover.get("rect", Rect2())))

	# 固定 world foot 的镜头变换只移动屏幕投影，不得重选任何单位槽位。
	var opening_actor_row: Dictionary = _snapshot_unit(initial_snapshot, actor.get_instance_id())
	var opening_actor_screen_foot: Vector2 = opening_actor_row.get("unit_screen_anchor", Vector2.ZERO)
	var opening_target_offsets: Dictionary = _target_offsets(initial_snapshot)
	var opening_slots: Dictionary = _slot_offsets(initial_snapshot)
	var camera: Camera2D = battle.get("_camera") as Camera2D
	_check("真实 TacticalScene Camera2D 可用于投影平移检查", camera != null)
	if camera != null:
		var camera_origin: Vector2 = camera.position
		var actor_world_foot: Vector2 = actor.global_position
		camera.position += Vector2(22.0, -11.0)
		camera.force_update_scroll()
		await frames(2)
		var panned_snapshot: Dictionary = layout.call("get_debug_snapshot")
		var panned_row: Dictionary = _snapshot_unit(panned_snapshot, actor.get_instance_id())
		_check("镜头平移改变屏幕足点，但 Unit 的 world foot 保持不变",
			actor.global_position.is_equal_approx(actor_world_foot)
			and not (panned_row.get("unit_screen_anchor", Vector2.ZERO) as Vector2)
				.is_equal_approx(opening_actor_screen_foot))
		_check_slots_unchanged("固定 world foot 的镜头平移", opening_slots, _slot_offsets(panned_snapshot))
		_check_target_offsets_unchanged("固定 world foot 的镜头平移",
			opening_target_offsets, _target_offsets(panned_snapshot))
		_check_live_rows("固定 world foot 的镜头平移", panned_snapshot, layout)
		camera.position = camera_origin
		camera.force_update_scroll()
		await frames(2)
		layout.call("refresh_layout")
		initial_snapshot = layout.call("get_debug_snapshot")
	# This entry keeps the current 1280x720 framing fixed; wheel input cannot alter it.
	var reference_zoom: Vector2 = camera.zoom
	var reference_camera_position: Vector2 = camera.position
	_check("1280x720 当前镜头缩放为 1.36",
		reference_zoom.is_equal_approx(Vector2.ONE * 1.36))
	for button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		for _index: int in 4:
			var wheel := InputEventMouseButton.new()
			wheel.button_index = button_index
			wheel.pressed = true
			wheel.position = Vector2(850, 300)
			session.call("_unhandled_input", wheel)
			await frames(1)
	_check("本入口滚轮上下事件均不改变缩放或镜头位置",
		camera.zoom.is_equal_approx(reference_zoom)
		and camera.position.is_equal_approx(reference_camera_position))
	_check_live_rows("固定镜头下的实际格、环与头顶血条", layout.call("get_debug_snapshot"), layout)
	# 每个单位切换四向素材时，固定头锚和零槽位均不得抖动。
	for unit_value: Variant in manager.units:
		if not (unit_value is Unit):
			continue
		var facing_unit: Unit = unit_value as Unit
		var base_row: Dictionary = _snapshot_unit(initial_snapshot, facing_unit.get_instance_id())
		var original_facing: StringName = facing_unit.get_facing()
		var base_head: Vector2 = base_row.get("stable_head_anchor", Vector2.ZERO)
		var base_foot: Vector2 = base_row.get("unit_screen_anchor", Vector2.ZERO)
		var base_badge_rect: Rect2 = base_row.get("class_icon_rect", Rect2())
		for direction: StringName in [&"NE", &"NW", &"SW", &"SE"]:
			facing_unit.set_facing(direction)
			await frames(2)
			layout.call("refresh_layout")
			var turned_snapshot: Dictionary = layout.call("get_debug_snapshot")
			var turned_row: Dictionary = _snapshot_unit(turned_snapshot, facing_unit.get_instance_id())
			var turned_head: Vector2 = turned_row.get("stable_head_anchor", Vector2.ZERO)
			var turned_foot: Vector2 = turned_row.get("unit_screen_anchor", Vector2.ZERO)
			_check("%s 朝向 %s 不改变 head/foot 锚" % [facing_unit.unit_id, direction],
				turned_head.is_equal_approx(base_head) and turned_foot.is_equal_approx(base_foot))
			_check_fixed_head_anchor("%s 朝向 %s" % [facing_unit.unit_id, direction], turned_row)
			_check_class_badge("%s 朝向 %s" % [facing_unit.unit_id, direction], turned_row, layout)
			_check("%s 朝向 %s 不移动职业图标矩形" % [facing_unit.unit_id, direction],
				base_badge_rect.is_equal_approx(turned_row.get("class_icon_rect", Rect2())))
		facing_unit.set_facing(original_facing)
		await frames(2)

	# 选择敌人旁真实可达格，通过正式点击/移动路径提交一次 GameAction movement。
	var move_cell: Vector2i = _find_adjacent_reachable_cell(manager, actor, target)
	_check("正式移动范围内存在与目标相邻的可达格", move_cell != Vector2i(-1, -1)
		and move_cell != actor.grid_position)
	if move_cell == Vector2i(-1, -1) or move_cell == actor.grid_position:
		_finish()
		return
	layout.call("refresh_layout")
	var before_move: Dictionary = _snapshot_unit(layout.call("get_debug_snapshot"), actor.get_instance_id())
	var previous_move_row: Dictionary = before_move.duplicate(true)
	var max_follow_error: float = 0.0
	var max_anchor_x_error: float = 0.0
	var max_head_bottom_error: float = 0.0
	var max_badge_offset_error: float = 0.0
	var move_samples: int = 0
	var settled_frames: int = 0
	var move_follow_ok: bool = true
	var fixed_anchor_ok: bool = true
	var badge_follow_ok: bool = true
	click(manager, move_cell)
	# Multi-cell routes now show every step; wait for actual arrival, with a bound.
	var movement_timeout: SceneTreeTimer = create_timer(3.0)
	while movement_timeout.time_left > 0.0:
		await process_frame
		var sample_snapshot: Dictionary = layout.call("get_debug_snapshot")
		var sample_row: Dictionary = _snapshot_unit(sample_snapshot, actor.get_instance_id())
		var group_delta_in_frame: Vector2 = (
			(sample_row.get("group_rect", Rect2()) as Rect2).position
			- (previous_move_row.get("group_rect", Rect2()) as Rect2).position)
		var foot_delta_in_frame: Vector2 = (
			(sample_row.get("unit_screen_anchor", Vector2.ZERO) as Vector2)
			- (previous_move_row.get("unit_screen_anchor", Vector2.ZERO) as Vector2))
		var follow_error: float = (group_delta_in_frame - foot_delta_in_frame).length()
		var slot_offset: Vector2 = sample_row.get("slot_offset", Vector2.ZERO)
		var target_offset: Vector2 = sample_row.get("target_offset", Vector2.ZERO)
		var group_rect: Rect2 = sample_row.get("group_rect", Rect2())
		var foot: Vector2 = sample_row.get("unit_screen_anchor", Vector2.ZERO)
		var head: Vector2 = sample_row.get("stable_head_anchor", Vector2.ZERO)
		var badge_rect: Rect2 = sample_row.get("class_icon_rect", Rect2())
		var icon_ratio: float = float(sample_row["screen_tile_width"]) / 87.04
		var badge_offset_error: float = (badge_rect.position - (foot + CLASS_BADGE_OFFSET * icon_ratio)).length()
		var anchor_x_error: float = absf(group_rect.get_center().x - foot.x)
		var head_bottom_error: float = absf(group_rect.end.y - (head.y - HEAD_GAP))
		max_follow_error = maxf(max_follow_error, follow_error)
		max_anchor_x_error = maxf(max_anchor_x_error, anchor_x_error)
		max_head_bottom_error = maxf(max_head_bottom_error, head_bottom_error)
		max_badge_offset_error = maxf(max_badge_offset_error, badge_offset_error)
		move_follow_ok = move_follow_ok and follow_error <= 0.1
		fixed_anchor_ok = fixed_anchor_ok and slot_offset.is_zero_approx() \
			and target_offset.is_zero_approx() and anchor_x_error <= 0.01 and head_bottom_error <= 0.01
		badge_follow_ok = badge_follow_ok \
			and str(sample_row.get("class_icon_kind", "")) == _expected_class_icon_kind(actor.unit_id) \
			and badge_rect.size.is_equal_approx(CLASS_BADGE_SIZE * icon_ratio) and badge_offset_error <= 0.01
		if foot_delta_in_frame.length() <= 0.01:
			settled_frames += 1
		else:
			settled_frames = 0
		previous_move_row = sample_row
		move_samples += 1
		if actor.grid_position == move_cell and manager.input_state == manager.InputState.ACTION_PHASE \
				and settled_frames >= 2:
			break
	var after_move_snapshot: Dictionary = layout.call("get_debug_snapshot")
	var after_move: Dictionary = _snapshot_unit(after_move_snapshot, actor.get_instance_id())
	var after_move_group: Rect2 = after_move.get("group_rect", Rect2())
	var after_move_foot: Vector2 = after_move.get("unit_screen_anchor", Vector2.ZERO)
	_check("正式移动已更新 Grid、结束移动动画并进入行动阶段",
		actor.grid_position == move_cell and actor.character_animation.action == "idle"
		and manager.input_state == manager.InputState.ACTION_PHASE and settled_frames >= 2)
	_check("移动期间组只随人物足点平移，无侧移或脚下偏移（最大误差 %.3fpx）" % max_follow_error,
		move_follow_ok and move_samples > 0)
	_check("移动每帧保持 slot_anchor=head 且 slot/target 偏移均为零",
		fixed_anchor_ok and move_samples > 0)
	_check("移动期间职业图标随足点保持固定右下偏移，最大误差 %.3fpx" % max_badge_offset_error,
		badge_follow_ok and move_samples > 0)
	print("PORTRAIT_OVERHEAD_MOVE_TRACE=", JSON.stringify({"samples": move_samples,
		"settled_frames": settled_frames, "max_follow_error_px": max_follow_error,
		"max_anchor_x_error_px": max_anchor_x_error,
		"max_head_bottom_error_px": max_head_bottom_error,
		"max_badge_offset_error_px": max_badge_offset_error,
		"final_foot": after_move_foot, "final_group_center": after_move_group.get_center(),
		"final_slot_offset": after_move.get("slot_offset", Vector2.ZERO),
		"final_target_offset": after_move.get("target_offset", Vector2.ZERO)}))
	_check_fixed_head_anchor("移动终点", after_move)
	var after_move_target_offsets: Dictionary = _target_offsets(after_move_snapshot)
	_check("移动后的所有存活单位 target_offset 均归零",
		after_move_target_offsets.size() == 4 and after_move_target_offsets.values().all(
			func(offset: Vector2) -> bool: return offset.is_zero_approx()))
	_check("移动后的四单位头顶仍分别绑定原有单位",
		_check_live_rows("移动后", after_move_snapshot, layout) == 4)
	print("PORTRAIT_OVERHEAD_POST_MOVE_PLACEMENT=", JSON.stringify(_placement_state(after_move_snapshot)))

	# 预测使用正式 damage_forecaster；单位固定血条旁不挂预测数字。
	_begin_strike(manager)
	manager.handle_pointer_hover(_screen_for_cell(manager, target.grid_position))
	await frames(3)
	layout.call("refresh_layout")
	var forecast_snapshot: Dictionary = layout.call("get_debug_snapshot")
	var target_forecast_row: Dictionary = _snapshot_unit(forecast_snapshot, target.get_instance_id())
	var forecast: Dictionary = manager.get_dashboard_data().get("forecast", {})
	var forecast_targets: Array = forecast.get("targets", [])
	var damage_forecaster: Control = battle.get("_damage_forecaster") as Control
	var targeting_hover: Dictionary = _hover_detail_snapshot(session)
	_check("真实攻击预测显示在 damage_forecaster，悬停详情与之互斥",
		bool(forecast.get("visible", false)) and forecast_targets.size() == 1
		and damage_forecaster != null and damage_forecaster.is_visible_in_tree()
		and not bool(targeting_hover.get("visible", true))
		and int(targeting_hover.get("instance", -1)) == 0)
	_check("预测目标仍为枪兵，常驻血条组不带预测数字或字形",
		str(target_forecast_row.get("unit_id", "")) == target.unit_id
		and str(target_forecast_row.get("overhead_group_name", ""))
			== "OverheadGroup_%d" % target.get_instance_id()
		and not bool(target_forecast_row.get("forecast_visible", true))
		and str(target_forecast_row.get("forecast_text", "")).is_empty()
		and str(target_forecast_row.get("forecast_glyph_shape", "")).is_empty())
	_check_slots_unchanged("显示预测", _slot_offsets(after_move_snapshot), _slot_offsets(forecast_snapshot))
	_check_target_offsets_unchanged("显示预测", after_move_target_offsets, _target_offsets(forecast_snapshot))
	_check_static_anchors_unchanged("显示预测", after_move_snapshot, forecast_snapshot)
	_check_unit_content_rects_unchanged("显示预测",
		_snapshot_unit(after_move_snapshot, target.get_instance_id()), target_forecast_row)
	_check_live_rows("显示预测", forecast_snapshot, layout)
	print("PORTRAIT_OVERHEAD_FORECAST_PLACEMENT=", JSON.stringify(_placement_state(forecast_snapshot)))

	manager.request_cancel_action()
	await frames(3)
	layout.call("refresh_layout")
	var cancelled_snapshot: Dictionary = layout.call("get_debug_snapshot")
	var cancelled_target: Dictionary = _snapshot_unit(cancelled_snapshot, target.get_instance_id())
	_check("取消真实瞄准后 damage_forecaster 关闭，常驻仍只有血条",
		(damage_forecaster == null or not damage_forecaster.is_visible_in_tree())
		and not bool(cancelled_target.get("forecast_visible", true))
		and bool(cancelled_target.get("name_visible", true)) == false
		and bool(cancelled_target.get("hp_visible", true)) == false
		and (cancelled_target.get("health_bar_rect", Rect2()) as Rect2).size == Vector2(40.0, 4.0))
	_check_slots_unchanged("取消预测", _slot_offsets(forecast_snapshot), _slot_offsets(cancelled_snapshot))
	_check_target_offsets_unchanged("取消预测", after_move_target_offsets, _target_offsets(cancelled_snapshot))
	_check_static_anchors_unchanged("取消预测", forecast_snapshot, cancelled_snapshot)
	_check_unit_content_rects_unchanged("取消预测", target_forecast_row, cancelled_target)
	_check_live_rows("取消预测", cancelled_snapshot, layout)

	# 仍从真实 UI 攻击选择提交 GameAction；不改人物属性或战斗规则值。
	var target_hp_before: int = target.stats.hp
	var contacts_before: int = actor.character_animation.contact_count
	_begin_strike(manager)
	manager.handle_pointer_click(_screen_for_cell(manager, target.grid_position))
	var attack_locked: bool = manager.input_state == manager.InputState.ANIMATING
	manager.handle_pointer_click(_screen_for_cell(manager, target.grid_position))
	manager.request_cancel_action()
	manager.request_end_turn()
	_check("真实攻击 windup 锁住再次点击、取消和结束回合输入",
		attack_locked and manager.input_state == manager.InputState.ANIMATING
		and manager.current_unit == actor)
	await frames(2)
	var animating_hover: Dictionary = _hover_detail_snapshot(session)
	var animating_snapshot: Dictionary = layout.call("get_debug_snapshot")
	var animating_target_row: Dictionary = _snapshot_unit(animating_snapshot, target.get_instance_id())
	_check("攻击 ANIMATING 期间隐藏普通悬浮详情和预测窗",
		not bool(animating_hover.get("visible", true))
		and (damage_forecaster == null or not damage_forecaster.is_visible_in_tree()))
	_check_live_rows("攻击 ANIMATING", animating_snapshot, layout)
	_check_static_anchors_unchanged("攻击 ANIMATING", cancelled_snapshot, animating_snapshot)
	_check_unit_content_rects_unchanged("攻击 ANIMATING", cancelled_target, animating_target_row)
	await wait(1.1)
	layout.call("refresh_layout")
	await frames(2)
	var after_attack_snapshot: Dictionary = layout.call("get_debug_snapshot")
	var after_attack_target: Dictionary = _snapshot_unit(after_attack_snapshot, target.get_instance_id())
	_check("真实 GameAction 攻击执行并完成接触表现", actor.standard_used
		and actor.character_animation.contact_count == contacts_before + 1)
	_check("真实攻击造成目标 HP 变化且目标仍存活", target.stats.hp < target_hp_before
		and target.stats.is_alive())
	_check("HP 元数据和血条数值同步实际战斗结果，文本本身隐藏",
		str(after_attack_target.get("hp_text", "")) == "%d / %d" % [target.stats.hp, target.stats.max_hp]
		and is_equal_approx(float(after_attack_target.get("bar_value", -1.0)), float(target.stats.hp))
		and is_equal_approx(float(after_attack_target.get("bar_max", -1.0)), float(target.stats.max_hp))
		and not bool(after_attack_target.get("hp_visible", true))
		and not bool(after_attack_target.get("forecast_visible", true)))
	_check_slots_unchanged("实际 HP 变化", _slot_offsets(cancelled_snapshot), _slot_offsets(after_attack_snapshot))
	_check_target_offsets_unchanged("实际 HP 变化", after_move_target_offsets, _target_offsets(after_attack_snapshot))
	_check_static_anchors_unchanged("实际 HP 变化", cancelled_snapshot, after_attack_snapshot)
	_check_unit_content_rects_unchanged("实际 HP 变化", cancelled_target, after_attack_target)
	_check("实际攻击后存活单位仍各有独立 40x4 血条组",
		_check_live_rows("攻击后", after_attack_snapshot, layout) >= 3)

	# 無關單位只經 Unit.take_damage 的正式死亡回调退出队列；未写入任何属性或规则值。
	var unrelated: Unit = _find_other_living_player(manager.units, actor)
	_check("存在不属于攻击目标的存活玩家单位用于死亡清理采样", unrelated != null)
	if unrelated != null:
		var unrelated_id: int = unrelated.get_instance_id()
		var unrelated_badge_name: String = "ClassBadge_%d" % unrelated_id
		var unrelated_badge: Control = layout.get_node_or_null(unrelated_badge_name) as Control
		var unrelated_badge_ref: WeakRef = weakref(unrelated_badge) if unrelated_badge != null else null
		_check("死亡清理前无关单位有独立职业图标节点", unrelated_badge != null)
		var before_unrelated_death: Dictionary = layout.call("get_debug_snapshot")
		var before_unrelated_target_offsets: Dictionary = _target_offsets(before_unrelated_death)
		unrelated.take_damage(unrelated.stats.hp)
		await frames(3)
		layout.call("refresh_layout")
		var after_unrelated_death: Dictionary = layout.call("get_debug_snapshot")
		_check("无关死亡经正式死亡信号移除头顶组", manager.units.size() == 3
			and _snapshot_unit(after_unrelated_death, unrelated_id).is_empty())
		_check("无关单位死亡同时释放其 ClassBadge 节点", layout.get_node_or_null(unrelated_badge_name) == null
			and unrelated_badge_ref != null and unrelated_badge_ref.get_ref() == null)
		_check_slots_unchanged("无关单位死亡", _slot_offsets(before_unrelated_death),
			_slot_offsets(after_unrelated_death), unrelated_id)
		_check_target_offsets_unchanged("无关单位死亡", before_unrelated_target_offsets,
			_target_offsets(after_unrelated_death), unrelated_id)
		_check_static_anchors_unchanged("无关单位死亡", before_unrelated_death,
			after_unrelated_death, unrelated_id)
		_check("无关死亡后存活单位仍各有自己的固定血条",
			_check_live_rows("无关死亡后", after_unrelated_death, layout) == 3)

	# 将一条窄 reserved rect 放在已占用槽位中，验证冲突被报告且归属槽位不逃逸。
	var before_blocker: Dictionary = _snapshot_unit(layout.call("get_debug_snapshot"), actor.get_instance_id())
	var before_blocker_rect: Rect2 = before_blocker.get("group_rect", Rect2())
	var before_blocker_slot: Vector2 = before_blocker.get("slot_offset", Vector2.ZERO)
	var blocker: Control = Control.new()
	blocker.name = "TestNarrowReservedRect"
	blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocker.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	blocker.size = Vector2(maxf(12.0, before_blocker_rect.size.x * 0.55), 4.0)
	blocker.position = Vector2(before_blocker_rect.get_center().x - blocker.size.x * 0.5,
		before_blocker_rect.get_center().y - blocker.size.y * 0.5)
	layout.add_child(blocker)
	var reserved_controls: Array = [battle.get("_turn_order_bar"), battle.get("_bottom_dashboard"),
		battle.get("_damage_forecaster"), blocker]
	layout.call("set_reserved_controls", reserved_controls)
	layout.call("refresh_layout")
	await frames(2)
	var blocked_snapshot: Dictionary = layout.call("get_debug_snapshot")
	var blocked_actor: Dictionary = _snapshot_unit(blocked_snapshot, actor.get_instance_id())
	var blocked_rect: Rect2 = blocked_actor.get("group_rect", Rect2())
	_check("窄 reserved rect 与头顶槽位冲突被 placement_clear=false 准确报告",
		not bool(blocked_actor.get("placement_clear", true)))
	_check("冲突状态保留原槽位且组心未飞离所属 Unit",
		(blocked_actor.get("slot_offset", Vector2.ZERO) as Vector2).is_equal_approx(before_blocker_slot)
		and blocked_rect.position.is_equal_approx(before_blocker_rect.position)
		and _check_fixed_head_anchor("reserved rect 冲突", blocked_actor))
	layout.call("set_reserved_controls", [battle.get("_turn_order_bar"),
		battle.get("_bottom_dashboard"), battle.get("_damage_forecaster")])
	blocker.queue_free()
	await frames(2)
	layout.call("refresh_layout")
	var after_blocker_snapshot: Dictionary = layout.call("get_debug_snapshot")
	var after_blocker_actor: Dictionary = _snapshot_unit(after_blocker_snapshot, actor.get_instance_id())
	_check("移除测试 reserved rect 后槽位与阻挡前状态一致",
		(after_blocker_actor.get("slot_offset", Vector2.ZERO) as Vector2).is_equal_approx(before_blocker_slot)
		and (after_blocker_actor.get("group_rect", Rect2()) as Rect2).position.is_equal_approx(before_blocker_rect.position)
		and bool(after_blocker_actor.get("placement_clear", false))
			== bool(before_blocker.get("placement_clear", false)))

	# 正式入口关闭 debug harness；推进玩家回合后由 EnemyAI 真实决定并执行动作。
	var enemy_action_started: bool = false
	for unit_value: Variant in manager.units:
		if unit_value is Unit and (unit_value as Unit).faction == "enemy":
			var enemy: Unit = unit_value as Unit
			enemy_action_started = enemy_action_started or enemy.movement_used or enemy.standard_used
	manager.request_end_turn()
	await wait(3.5)
	var enemy_action_executed: bool = enemy_action_started
	var ai_state: Array[Dictionary] = []
	for unit_value: Variant in manager.units:
		if unit_value is Unit and (unit_value as Unit).faction == "enemy":
			var enemy: Unit = unit_value as Unit
			var acted: bool = enemy.movement_used or enemy.standard_used
			enemy_action_executed = enemy_action_executed or acted
			ai_state.append({"unit_id": enemy.unit_id, "movement_used": enemy.movement_used,
				"standard_used": enemy.standard_used, "hp": enemy.stats.hp})
	print("PORTRAIT_OVERHEAD_AI_STATE=", JSON.stringify(ai_state))
	_check("真实战斗 EnemyAI 在关闭调试 harness 下执行行动",
		not bool(manager.get("debug_harness_active")) and enemy_action_executed)

	# 重开并采样旧 UI 弱引用，确保前一场的组节点不留在真实入口中。
	var previous_unit_ids: Array[int] = []
	for old_unit_value: Variant in manager.units:
		if old_unit_value is Unit:
			previous_unit_ids.append((old_unit_value as Unit).get_instance_id())
	var old_layout_ref: WeakRef = weakref(layout)
	var old_group_name: String = "OverheadGroup_%d" % actor.get_instance_id()
	var old_group_ref: WeakRef = weakref(layout.get_node(old_group_name))
	var old_badge_name: String = "ClassBadge_%d" % actor.get_instance_id()
	var old_badge: Control = layout.get_node_or_null(old_badge_name) as Control
	var old_badge_ref: WeakRef = weakref(old_badge) if old_badge != null else null
	await session.select_layout(LAYOUT_ID)
	await frames(2)
	var restarted_battle: Node = session.get("battle") as Node
	var restarted_manager: Node = session.get("manager") as Node
	var restarted_layout: Control = _overhead_layout(restarted_battle)
	_check("重开释放旧头顶布局/单位组并建立全新四单位场景",
		old_layout_ref.get_ref() == null and old_group_ref.get_ref() == null
		and old_badge_ref != null and old_badge_ref.get_ref() == null
		and restarted_layout != layout and restarted_manager.units.size() == 4)
	var restarted_snapshot: Dictionary = restarted_layout.call("get_debug_snapshot")
	_check("重开只保留当前战斗的悬浮详情，不显示上一场 Unit 残影",
		_hover_snapshot_matches_units(_hover_detail_snapshot(session), restarted_manager.units,
			previous_unit_ids))
	_check("重开后没有上一场单位组或预测残留",
		restarted_layout.find_child(old_group_name, true, false) == null
		and _all_forecasts_hidden(restarted_snapshot)
		and _check_live_rows("重开", restarted_snapshot, restarted_layout) == 4)

	# 在新战斗中建立真实可见预测，再停止并重开，验证旧预测 UI 不残留。
	var restarted_actor: Unit = restarted_manager.current_unit as Unit
	var restarted_target: Unit = _find_unit_at(restarted_manager.units, Vector2i(4, 4))
	var restarted_move_cell: Vector2i = _find_adjacent_reachable_cell(
		restarted_manager, restarted_actor, restarted_target)
	_check("重开后的真实玩家可以移动到枪兵相邻格", restarted_move_cell != Vector2i(-1, -1)
		and restarted_move_cell != restarted_actor.grid_position)
	if restarted_move_cell != Vector2i(-1, -1) and restarted_move_cell != restarted_actor.grid_position:
		click(restarted_manager, restarted_move_cell)
		await wait(0.4)
		_begin_strike(restarted_manager)
		restarted_manager.handle_pointer_hover(_screen_for_cell(restarted_manager, restarted_target.grid_position))
		await frames(3)
		restarted_layout.call("refresh_layout")
		var cleanup_snapshot: Dictionary = restarted_layout.call("get_debug_snapshot")
		var cleanup_target_row: Dictionary = _snapshot_unit(cleanup_snapshot, restarted_target.get_instance_id())
		var old_forecaster: Control = restarted_battle.get("_damage_forecaster") as Control
		var old_forecaster_ref: WeakRef = weakref(old_forecaster)
		var cleanup_hover: Dictionary = _hover_detail_snapshot(session)
		_check("停止前真实 damage_forecaster 可见，固定血条旁无预测字形",
			bool(restarted_manager.get_dashboard_data().get("forecast", {}).get("visible", false))
			and old_forecaster != null and old_forecaster.is_visible_in_tree()
			and not bool(cleanup_target_row.get("forecast_visible", true))
			and str(cleanup_target_row.get("forecast_glyph_shape", "")).is_empty()
			and not bool(cleanup_hover.get("visible", true)))
		var cleanup_layout_ref: WeakRef = weakref(restarted_layout)
		var cleanup_group_name: String = "OverheadGroup_%d" % restarted_actor.get_instance_id()
		var cleanup_group_ref: WeakRef = weakref(restarted_layout.get_node(cleanup_group_name))
		var cleanup_badge_name: String = "ClassBadge_%d" % restarted_actor.get_instance_id()
		var cleanup_badge: Control = restarted_layout.get_node_or_null(cleanup_badge_name) as Control
		var cleanup_badge_ref: WeakRef = weakref(cleanup_badge) if cleanup_badge != null else null
		_check("停止前存活单位仍有直属布局根的职业图标", cleanup_badge != null
			and cleanup_badge.get_parent() == restarted_layout)
		restarted_manager.stop_battle()
		await frames(2)
		var stopped_snapshot: Dictionary = restarted_layout.call("get_debug_snapshot")
		var stopped_hover: Dictionary = _hover_detail_snapshot(session)
		_check("停止战斗清掉 damage_forecaster，固定血条组仍可采样到销毁时",
			old_forecaster_ref.get_ref() != null and not old_forecaster.visible
			and _all_forecasts_hidden(stopped_snapshot)
			and not bool(stopped_hover.get("visible", true))
			and int(stopped_hover.get("instance", -1)) == 0
			and not _rect_has_area(stopped_hover.get("rect", Rect2())))
		await session.select_layout(LAYOUT_ID)
		await frames(2)
		var final_layout: Control = _overhead_layout(session.get("battle") as Node)
		var final_snapshot: Dictionary = final_layout.call("get_debug_snapshot")
		_check("停止后重开彻底释放旧预测层/头顶组且无残留",
			cleanup_layout_ref.get_ref() == null and cleanup_group_ref.get_ref() == null
			and cleanup_badge_ref != null and cleanup_badge_ref.get_ref() == null
			and final_layout.get_node_or_null(cleanup_badge_name) == null
			and old_forecaster_ref.get_ref() == null
			and final_layout != restarted_layout and _all_forecasts_hidden(final_snapshot)
			and (final_snapshot.get("units", []) as Array).size() == 4
			and _check_live_rows("停止后重开", final_snapshot, final_layout) == 4)

	session.queue_free()
	await frames(2)
	_finish()


func _overhead_layout(battle: Node) -> Control:
	if battle == null:
		return null
	return battle.get_node_or_null("UILayer/UnitOverheadLayout") as Control


func _find_unit_at(units: Array, cell: Vector2i) -> Unit:
	for unit_value: Variant in units:
		if unit_value is Unit and (unit_value as Unit).grid_position == cell:
			return unit_value as Unit
	return null


func _find_empty_cell(manager: Node) -> Vector2i:
	if manager == null or manager.grid == null:
		return Vector2i(-1, -1)
	for y: int in range(manager.grid.height):
		for x: int in range(manager.grid.width):
			var cell := Vector2i(x, y)
			if manager.grid.get_unit_at(cell) == null:
				return cell
	return Vector2i(-1, -1)


func _hover_detail_snapshot(entry: Node) -> Dictionary:
	if entry == null or not entry.has_method("get_unit_hover_detail_snapshot"):
		return {}
	return entry.call("get_unit_hover_detail_snapshot")


func _hover_snapshot_matches_units(hover: Dictionary, units: Array,
		previous_instance_ids: Array[int]) -> bool:
	if not bool(hover.get("visible", false)):
		return int(hover.get("instance", -1)) == 0 and not _rect_has_area(hover.get("rect", Rect2()))
	var instance_id: int = int(hover.get("instance", 0))
	if instance_id == 0 or previous_instance_ids.has(instance_id) \
			or not _rect_has_area(hover.get("rect", Rect2())):
		return false
	for unit_value: Variant in units:
		if not (unit_value is Unit):
			continue
		var unit: Unit = unit_value as Unit
		if unit.get_instance_id() == instance_id:
			return str(hover.get("text", "")) == "%s · HP %d/%d" % [
				unit.get_short_label(), unit.stats.hp, unit.stats.max_hp]
	return false


func _find_other_living_player(units: Array, actor: Unit) -> Unit:
	for unit_value: Variant in units:
		if unit_value is Unit:
			var unit: Unit = unit_value as Unit
			if unit != actor and unit.faction == "player" and unit.stats.is_alive():
				return unit
	return null


func _find_adjacent_reachable_cell(manager: Node, actor: Unit, target: Unit) -> Vector2i:
	if manager == null or actor == null or target == null:
		return Vector2i(-1, -1)
	var movement: Dictionary = manager.get("_move_range") as Dictionary
	for candidate: Vector2i in manager.grid.get_neighbors(target.grid_position):
		if candidate != actor.grid_position and movement.has(candidate):
			return candidate
	return Vector2i(-1, -1)


func click(manager: Node, cell: Vector2i) -> void:
	manager.handle_pointer_click(_screen_for_cell(manager, cell))


func _screen_for_cell(manager: Node, cell: Vector2i) -> Vector2:
	return root.get_canvas_transform() * manager.grid.grid_to_world(cell)


func _snapshot_unit(snapshot: Dictionary, instance_id: int) -> Dictionary:
	for row_value: Variant in snapshot.get("units", []):
		if row_value is Dictionary and int((row_value as Dictionary).get("instance_id", 0)) == instance_id:
			return row_value as Dictionary
	return {}


func _slot_offsets(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for row_value: Variant in snapshot.get("units", []):
		if row_value is Dictionary:
			var row: Dictionary = row_value as Dictionary
			result[int(row.get("instance_id", 0))] = row.get("slot_offset", Vector2.ZERO)
	return result


func _target_offsets(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for row_value: Variant in snapshot.get("units", []):
		if not (row_value is Dictionary):
			continue
		var row: Dictionary = row_value as Dictionary
		var target_offset: Variant = row.get("target_offset", null)
		if target_offset is Vector2:
			result[int(row.get("instance_id", 0))] = target_offset as Vector2
	return result


func _check_slots_unchanged(label: String, before: Dictionary, after: Dictionary,
		excluded_instance_id: int = 0) -> void:
	for instance_id_value: Variant in before.keys():
		var instance_id: int = int(instance_id_value)
		if instance_id == excluded_instance_id or not after.has(instance_id):
			continue
		var old_slot: Vector2 = before[instance_id]
		var new_slot: Vector2 = after[instance_id]
		_check("%s 存活单位 %d 保持原头顶槽位" % [label, instance_id],
			old_slot.is_equal_approx(new_slot))


func _check_target_offsets_unchanged(label: String, before: Dictionary, after: Dictionary,
		excluded_instance_id: int = 0) -> void:
	for instance_id_value: Variant in before.keys():
		var instance_id: int = int(instance_id_value)
		if instance_id == excluded_instance_id or not after.has(instance_id):
			continue
		var old_target: Vector2 = before[instance_id]
		var new_target: Vector2 = after[instance_id]
		_check("%s 存活单位 %d 未重选槽位目标" % [label, instance_id],
			old_target.is_equal_approx(new_target))


func _check_static_anchors_unchanged(label: String, before: Dictionary, after: Dictionary,
		excluded_instance_id: int = 0) -> void:
	var compared: int = 0
	for row_value: Variant in before.get("units", []):
		if not (row_value is Dictionary):
			continue
		var old_row: Dictionary = row_value as Dictionary
		var instance_id: int = int(old_row.get("instance_id", 0))
		if instance_id == excluded_instance_id:
			continue
		var new_row: Dictionary = _snapshot_unit(after, instance_id)
		if new_row.is_empty():
			continue
		var old_head: Vector2 = old_row.get("stable_head_anchor", Vector2.ZERO)
		var new_head: Vector2 = new_row.get("stable_head_anchor", Vector2.ZERO)
		var old_foot: Vector2 = old_row.get("unit_screen_anchor", Vector2.ZERO)
		var new_foot: Vector2 = new_row.get("unit_screen_anchor", Vector2.ZERO)
		_check("%s 存活单位 %d 的静止 head/foot 锚不变" % [label, instance_id],
			old_head.is_equal_approx(new_head) and old_foot.is_equal_approx(new_foot))
		compared += 1
	_check("%s 至少核对一个未移动存活单位的锚" % label, compared > 0)


func _check_unit_content_rects_unchanged(label: String, before: Dictionary,
		after: Dictionary) -> void:
	var fixed_bar_rects: bool = true
	for key: String in ["group_rect", "health_bar_rect"]:
		var old_rect: Rect2 = before.get(key, Rect2())
		var new_rect: Rect2 = after.get(key, Rect2())
		fixed_bar_rects = fixed_bar_rects and old_rect.is_equal_approx(new_rect)
	var old_badge_rect: Rect2 = before.get("class_icon_rect", Rect2())
	var new_badge_rect: Rect2 = after.get("class_icon_rect", Rect2())
	fixed_bar_rects = fixed_bar_rects and old_badge_rect.is_equal_approx(new_badge_rect)
	var hidden_details: bool = true
	for key: String in ["name_rect", "hp_text_rect", "forecast_rect"]:
		var old_hidden_rect: Rect2 = before.get(key, Rect2())
		var new_hidden_rect: Rect2 = after.get(key, Rect2())
		hidden_details = hidden_details and not _rect_has_area(old_hidden_rect) \
			and not _rect_has_area(new_hidden_rect)
	_check("%s 常驻血条组矩形保持稳定" % label, fixed_bar_rects)
	_check("%s 名称/HP/预测旁挂控件持续隐藏" % label, hidden_details)


func _expected_class_icon_kind(unit_id: String) -> String:
	match unit_id:
		"myrmidon":
			return "sword"
		"kensei":
			return "master_sword"
		"test_lancer", "lancer":
			return "spear"
		_:
			return ""


func _check_original_ring_geometry(manager: Node) -> void:
	var active_ring_found: bool = false
	for unit_value: Variant in manager.units:
		if not (unit_value is Unit):
			continue
		var unit: Unit = unit_value as Unit
		var ring: Node = unit.get_node_or_null("PersistentFactionRing")
		var ring_present: bool = ring != null
		var center_offset: Vector2 = Vector2.ONE
		var compact: bool = true
		var normal_radius: Vector2 = Vector2.ZERO
		var normal_center: Vector2 = Vector2.ONE
		var selected_radius: Vector2 = Vector2.ZERO
		var selected_center: Vector2 = Vector2.ONE
		if ring_present:
			center_offset = ring.get("center_offset")
			compact = bool(ring.get("compact_badge_layout"))
			var normal_points: PackedVector2Array = ring.call("_ellipse", 18.0, 8.0)
			var selected_points: PackedVector2Array = ring.call("_ellipse", 22.0, 10.0)
			var normal_bounds: Rect2 = _ellipse_bounds(normal_points)
			var selected_bounds: Rect2 = _ellipse_bounds(selected_points)
			normal_radius = normal_bounds.size * 0.5
			normal_center = normal_bounds.get_center()
			selected_radius = selected_bounds.size * 0.5
			selected_center = selected_bounds.get_center()
			if unit == manager.current_unit:
				active_ring_found = bool(ring.get("_active"))
		var original_geometry: bool = normal_radius.is_equal_approx(Vector2(18.0, 8.0)) \
			and selected_radius.is_equal_approx(Vector2(22.0, 10.0))
		_check("%s 阵营环保留普通18/8和选中22/10原半径" % unit.unit_id,
			ring_present and original_geometry)
		_check("%s 阵营环中心偏移和两种椭圆中心都为零" % unit.unit_id,
			ring_present and center_offset.is_zero_approx()
			and normal_center.is_zero_approx() and selected_center.is_zero_approx()
			and not compact)
	_check("当前行动单位显示原选中圈状态", active_ring_found)


func _ellipse_bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var minimum: Vector2 = Vector2(INF, INF)
	var maximum: Vector2 = Vector2(-INF, -INF)
	for point: Vector2 in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	return Rect2(minimum, maximum - minimum)


func _check_class_badge(label: String, row: Dictionary, layout: Control) -> bool:
	var unit_id: String = str(row.get("unit_id", ""))
	var instance_id: int = int(row.get("instance_id", 0))
	var expected_kind: String = _expected_class_icon_kind(unit_id)
	var icon_kind: String = str(row.get("class_icon_kind", ""))
	var badge: Control = layout.get_node_or_null("ClassBadge_%d" % instance_id) as Control
	var group: Control = layout.get_node_or_null("OverheadGroup_%d" % instance_id) as Control
	var icon_rect: Rect2 = row.get("class_icon_rect", Rect2())
	var foot: Vector2 = row.get("unit_screen_anchor", Vector2.ZERO)
	var icon_ratio: float = float(row["screen_tile_width"]) / 87.04
	var expected_position: Vector2 = foot + CLASS_BADGE_OFFSET * icon_ratio
	var mapping_ok: bool = not expected_kind.is_empty() and icon_kind == expected_kind
	var node_ok: bool = badge != null and badge.name == "ClassBadge_%d" % instance_id \
		and badge.get_parent() == layout and badge.get_parent() != group \
		and badge.visible and badge.is_visible_in_tree() \
		and badge.size.is_equal_approx(CLASS_BADGE_SIZE)
	var geometry_ok: bool = icon_rect.size.is_equal_approx(CLASS_BADGE_SIZE * icon_ratio) \
		and (icon_rect.position - expected_position).length() <= 0.01
	_check("%s %s 职业图标映射为 %s 并直接归属布局根" % [label, unit_id, expected_kind],
		mapping_ok and node_ok)
	_check("%s %s 职业图标为 17px圆底，中心位于足点 +(23,0)；实际笔画另验格界与环线" % [label, unit_id], geometry_ok)
	var footprint_ok: bool = true
	var tile_half: Vector2 = Vector2(float(row.get("screen_tile_width", 0.0))*0.5,
		float(row.get("screen_tile_width", 0.0))*0.25)
	for polygon: PackedVector2Array in badge.call("ink_polygons"):
		for point: Vector2 in polygon:
			var q: Vector2 = (point + CLASS_BADGE_OFFSET) * icon_ratio
			# Rectangle control is transparent: test the actual drawn vertices, not its bbox.
			footprint_ok = footprint_ok and absf(q.x)/tile_half.x + absf(q.y)/tile_half.y < 1.0
	_check("%s %s 实绘笔画留在所属格菱形内；原半径脚环允许局部重叠" % [
		label, unit_id], footprint_ok)
	return mapping_ok and node_ok and geometry_ok and footprint_ok


func _check_live_rows(label: String, snapshot: Dictionary, layout: Control) -> int:
	var count: int = 0
	for row_value: Variant in snapshot.get("units", []):
		if not (row_value is Dictionary):
			continue
		var row: Dictionary = row_value as Dictionary
		var instance_id: int = int(row.get("instance_id", 0))
		var group: Control = layout.get_node_or_null("OverheadGroup_%d" % instance_id) as Control
		var name_label: Label = layout.get_node_or_null("OverheadGroup_%d/Name_%d" % [instance_id, instance_id]) as Label
		var health_bar: ProgressBar = layout.get_node_or_null("OverheadGroup_%d/HealthBar_%d" % [instance_id, instance_id]) as ProgressBar
		var hp_label: Label = layout.get_node_or_null("OverheadGroup_%d/HP_%d" % [instance_id, instance_id]) as Label
		var owner_plate: Control = layout.get_node_or_null("OverheadGroup_%d/OwnerPlate_%d" % [instance_id, instance_id]) as Control
		var forecast_group: Control = layout.get_node_or_null("OverheadGroup_%d/ForecastGroup_%d" % [instance_id, instance_id]) as Control
		var forecast_glyph: Control = layout.get_node_or_null(
			"OverheadGroup_%d/ForecastGroup_%d/ForecastGlyph_%d" % [instance_id, instance_id, instance_id]) as Control
		var group_rect: Rect2 = row.get("group_rect", Rect2())
		var name_rect: Rect2 = row.get("name_rect", Rect2())
		var bar_rect: Rect2 = row.get("health_bar_rect", Rect2())
		var hp_rect: Rect2 = row.get("hp_text_rect", Rect2())
		var tile_width: float = float(row.get("screen_tile_width", 0.0))
		var same_group: bool = group != null and name_label != null and health_bar != null \
			and hp_label != null and owner_plate != null and forecast_group != null \
			and name_label.get_parent() == group and health_bar.get_parent() == group \
			and hp_label.get_parent() == group and owner_plate.get_parent() == group \
			and forecast_group.get_parent() == group
		_check("%s %s 的血条和隐藏详情控件仍归属同一 Unit 组" % [label, row.get("unit_id", "")], same_group)
		var hidden_details: bool = name_label != null and hp_label != null and owner_plate != null \
			and forecast_group != null and not name_label.is_visible_in_tree() \
			and not hp_label.is_visible_in_tree() and not owner_plate.is_visible_in_tree() \
			and not forecast_group.is_visible_in_tree() \
			and not bool(row.get("name_visible", true)) and not bool(row.get("hp_visible", true)) \
			and not bool(row.get("owner_plate_visible", true)) \
			and not bool(row.get("forecast_visible", true))
		var only_bar_visible: bool = group != null and health_bar != null and group.visible \
			and health_bar.is_visible_in_tree() and health_bar.size.is_equal_approx(Vector2(40.0, 4.0))
		var visible_children: int = 0
		if group != null:
			for child: Node in group.get_children():
				if child is CanvasItem and (child as CanvasItem).is_visible_in_tree():
					visible_children += 1
					only_bar_visible = only_bar_visible and child == health_bar
			only_bar_visible = only_bar_visible and visible_children == 1
		_check("%s %s 常驻只显示一个 40x4 HP ProgressBar，其余详情均隐藏" % [
			label, row.get("unit_id", "")], hidden_details and only_bar_visible
			and (forecast_glyph == null or not forecast_glyph.is_visible_in_tree()))
		var expected_hp_text: String = "%d / %d" % [
			roundi(float(row.get("bar_value", -1.0))), roundi(float(row.get("bar_max", -1.0)))]
		var hp_metadata_matches: bool = float(row.get("bar_max", 0.0)) > 0.0 \
			and float(row.get("bar_value", -1.0)) >= 0.0 \
			and float(row.get("bar_value", -1.0)) <= float(row.get("bar_max", 0.0)) \
			and str(row.get("hp_text", "")) == expected_hp_text
		_check("%s %s 的隐藏 HP 元数据与实际血条数值一致" % [label, row.get("unit_id", "")],
			hp_metadata_matches and not _rect_has_area(hp_rect)
			and not _rect_has_area(name_rect)
			and not _rect_has_area(row.get("forecast_rect", Rect2())))
		_check("%s %s 实际只占 40x4 血条矩形" % [label, row.get("unit_id", "")],
			group_rect.size.is_equal_approx(Vector2(40.0, 4.0))
			and bar_rect.size.is_equal_approx(Vector2(40.0, 4.0))
			and group_rect.is_equal_approx(bar_rect))
		_check_class_badge(label, row, layout)
		_check_fixed_head_anchor(label + " " + str(row.get("unit_id", "")), row)
		_check("%s %s 的屏幕格宽来自实际 canvas 投影" % [label, row.get("unit_id", "")],
			tile_width > 0.0 and is_finite(tile_width))
		count += 1
	return count


func _placement_state(snapshot: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row_value: Variant in snapshot.get("units", []):
		if row_value is Dictionary:
			var row: Dictionary = row_value as Dictionary
			result.append({"unit_id": str(row.get("unit_id", "")),
				"placement_clear": bool(row.get("placement_clear", false)),
				"slot_offset": row.get("slot_offset", Vector2.ZERO)})
	return result


func _check_fixed_head_anchor(label: String, row: Dictionary) -> bool:
	var group_rect: Rect2 = row.get("group_rect", Rect2())
	var foot: Vector2 = row.get("unit_screen_anchor", Vector2.ZERO)
	var head: Vector2 = row.get("stable_head_anchor", Vector2.ZERO)
	var slot: Vector2 = row.get("slot_offset", Vector2.ONE)
	var target: Vector2 = row.get("target_offset", Vector2.ONE)
	var screen_tile_width: float = float(row.get("screen_tile_width", 0.0))
	var group_center_x_error: float = absf(group_rect.get_center().x - foot.x)
	var head_bottom_error: float = absf(group_rect.end.y - (head.y - HEAD_GAP))
	var slot_anchor: Vector2 = Vector2(group_rect.get_center().x, group_rect.end.y + HEAD_GAP)
	var zero_offsets: bool = row.has("slot_offset") and row.has("target_offset") \
		and slot.is_zero_approx() and target.is_zero_approx()
	var anchor_is_head: bool = slot_anchor.is_equal_approx(head)
	if row.has("slot_anchor"):
		anchor_is_head = anchor_is_head and str(row.get("slot_anchor", "")) == "head"
	var valid: bool = group_rect.size.x > 0.0 and group_rect.size.y > 0.0 \
		and screen_tile_width > 0.0 and zero_offsets and anchor_is_head \
		and group_center_x_error <= 0.01 and head_bottom_error <= 0.01
	_check("%s slot_anchor=head 且 slot_offset/target_offset 均为零" % label,
		group_rect.size.x > 0.0 and zero_offsets and anchor_is_head)
	_check("%s group.center.x 与 Unit 足点投影 x 重合（误差 %.4fpx）" % [label, group_center_x_error],
		group_center_x_error <= 0.01)
	_check("%s group.end.y = stable_head_anchor.y - %.1fpx（误差 %.4fpx）" % [
		label, HEAD_GAP, head_bottom_error], head_bottom_error <= 0.01)
	return valid


func _all_forecasts_hidden(snapshot: Dictionary) -> bool:
	for row_value: Variant in snapshot.get("units", []):
		if row_value is Dictionary and bool((row_value as Dictionary).get("forecast_visible", false)):
			return false
	return true


func _rect_has_area(rect_value: Variant) -> bool:
	if not (rect_value is Rect2):
		return false
	var rect: Rect2 = rect_value as Rect2
	return rect.size.x > 0.0 and rect.size.y > 0.0


func frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame


func wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _check(label: String, passed: bool) -> void:
	checks += 1
	print("[", "PASS" if passed else "FAIL", "] ", label)
	if not passed:
		failures.append(label)


func _finish() -> void:
	if is_instance_valid(session):
		session.queue_free()
	print("PORTRAIT_OVERHEAD_RESULT=", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

## 剑士线没有普通攻击（gameplay-impl PR3，用户 2026-10-28 裁决 S2）。对没有普攻的单位改用其
## 技能栏第一格（剑士为斩击）：技能走同一条真实出手、动画锁与接触表现路径
## （_execute_presented_skill → begin_attack_visual），本测试要验的东西不变。
func _begin_strike(manager: Node) -> void:
	var actor: Unit = manager.current_unit
	if actor != null and not actor.has_basic_attack and not actor.skill_ids.is_empty():
		manager.request_skill_selection(actor.skill_ids[0])
	else:
		manager.request_attack_targeting()
