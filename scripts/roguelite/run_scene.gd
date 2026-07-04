extends Node2D
## RunScene v0 宿主：串起「战斗子视图 → 2-3 扇门选择 → Prep 确认出发 → 下一关」的门循环。
##
## 真源：runloop-reward-map-proposal.md §7 门模式 + v0-implementation-plan.md §1
##       + KB run-loop.md 结算顺序。
##
## 职责边界：
##   - 纯接线宿主，不改战斗场景非注入路径；逻辑层（RunManager / BattleAssembler）已实装。
##   - 战斗子视图 = TacticalScene.tscn 实例（run_injected=true + debug_harness_enabled=false）。
##   - 门选择子视图 = DoorSelect.tscn 实例。
##   - Prep 子视图 = v0 最简「确认出发」按钮（恢复 / 运输队 / 情报为后续任务 #7/#8）。
##   - 信号 past-tense。
##
## 手动测试：编辑器打开本场景 RunScene.tscn，跑一整幕验证门循环（见门循环手动测试清单.md）。

const RunManagerScript: GDScript = preload("res://scripts/roguelite/run_manager.gd")
const BattleAssemblerScript: GDScript = preload("res://scripts/roguelite/battle_assembler.gd")
const TacticalSceneScene: PackedScene = preload("res://scenes/tactical/TacticalScene.tscn")
const DoorSelectScene: PackedScene = preload("res://scenes/roguelite/DoorSelect.tscn")

const ACT_CONFIG_FILE: String = "res://data/runloop/act1_config.json"
const RUN_CONFIG_FILE: String = "res://data/runloop/run_config.json"

# [占位] v0 队伍 roster：4 人 class_id + level=1，其余账本字段由 RunState 补齐。数值临时占位。
const PARTY_ROSTER: Array[Dictionary] = [
	{"class_id": "swordsman", "level": 1},
	{"class_id": "soldier", "level": 1},
	{"class_id": "archer", "level": 1},
	{"class_id": "cleric", "level": 1},
]
# [占位] 固定随机种子，便于手动复现；正式版由 run 生成器提供。
const RUN_SEED: int = 20260704

var _run_manager: Object = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _data_pools: Dictionary = {}

var _ui_layer: CanvasLayer = null
var _battle_view: Node = null
var _door_select: Control = null
var _prep_panel: Control = null
var _end_panel: Control = null
var _event_panel: Control = null


func _ready() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 20
	add_child(_ui_layer)

	# data_pools 取自 DataLoader autoload（RunManager 用 equipment/relics/waves/maps/events；
	# BattleAssembler 用 maps/waves；apply_affixes 用 affixes）。
	_data_pools = {
		"maps": DataLoader.maps,
		"waves": DataLoader.waves,
		"affixes": DataLoader.affixes,
		"relics": DataLoader.relics,
		"equipment": DataLoader.equipment,
		"events": DataLoader.events,
	}

	var act_config: Dictionary = _load_json(ACT_CONFIG_FILE)
	var run_config: Dictionary = _load_json(RUN_CONFIG_FILE)
	_rng.seed = RUN_SEED

	_run_manager = RunManagerScript.new()
	_run_manager.doors_generated.connect(_on_doors_generated)
	_run_manager.reward_settled.connect(_on_reward_settled)
	_run_manager.stage_advanced.connect(_on_stage_advanced)
	_run_manager.run_completed.connect(_on_run_completed)
	_run_manager.run_failed.connect(_on_run_failed)

	var roster: Array = []
	for member: Dictionary in PARTY_ROSTER:
		roster.append(member.duplicate(true))
	_run_manager.start_run(run_config, act_config, _data_pools, roster, _rng)
	_enter_battle()


# ── 战斗子视图 ───────────────────────────────────────

## 装配当前关战斗并挂载 TacticalScene 注入实例。
func _enter_battle() -> void:
	_clear_battle_view()
	var st: Object = _run_manager.get_state()
	var battle: Dictionary = st.current_battle
	var map_id: String = str(battle.get("map_id", ""))
	var wave_id: String = str(battle.get("enemy_config", ""))
	var assembled: Dictionary = BattleAssemblerScript.build(
		map_id, wave_id, st.party, _data_pools)

	var inst: Node = TacticalSceneScene.instantiate()
	# 注入字段必须在 add_child（触发 _ready）前设置。
	inst.run_injected = true
	inst.debug_harness_enabled = false
	inst.injected_map_id = str(assembled.get("map_id", map_id))
	inst.injected_player_units = assembled.get("player_units", [])
	inst.injected_enemy_units = assembled.get("enemy_units", [])
	inst.battle_ended.connect(_on_battle_ended)
	_battle_view = inst
	add_child(inst)
	print("[RunScene] 进入 stage %d 战斗：map=%s wave=%s（玩家 %d / 敌人 %d）" % [
		st.stage, inst.injected_map_id,
		wave_id, (inst.injected_player_units as Array).size(),
		(inst.injected_enemy_units as Array).size()])


func _clear_battle_view() -> void:
	if _battle_view != null and is_instance_valid(_battle_view):
		_battle_view.queue_free()
	_battle_view = null


## 战斗结束回调：结算 → 据新 phase 切子视图。
func _on_battle_ended(result: String) -> void:
	_clear_battle_view()
	_run_manager.on_battle_resolved(result)
	var st: Object = _run_manager.get_state()
	match str(st.phase):
		"door_select":
			_show_door_select(st.pending_doors)
		"prep":
			# Boss 前分支：on_battle_resolved 已备 Boss 战斗并置 prep（无门选）。
			_show_prep()
		"complete":
			_show_end_panel(true)
		"failed":
			_show_end_panel(false)
		_:
			push_warning("[RunScene] 未预期 phase: %s" % str(st.phase))


# ── 门选择子视图 ─────────────────────────────────────

func _show_door_select(doors: Array) -> void:
	_clear_door_select()
	var ds: Control = DoorSelectScene.instantiate()
	_ui_layer.add_child(ds)
	ds.door_chosen.connect(_on_door_chosen)
	ds.populate(doors)
	_door_select = ds


func _clear_door_select() -> void:
	if _door_select != null and is_instance_valid(_door_select):
		_door_select.queue_free()
	_door_select = null


func _on_door_chosen(index: int) -> void:
	_clear_door_select()
	_run_manager.choose_door(index)  # → phase=prep
	_show_prep()


# ── Prep 子视图（v0 最简：仅「确认出发」）────────────────

func _show_prep() -> void:
	_clear_prep()
	var st: Object = _run_manager.get_state()
	var next_stage: int = st.stage + 1
	var panel: Control = _build_center_panel()
	var vbox: VBoxContainer = panel.get_node("VBox")

	var label: Label = Label.new()
	label.text = "备战 (Prep)\n下一关：stage %d" % next_stage
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(label)

	var hint: Label = Label.new()
	hint.text = "恢复 / 运输队 / 情报为后续任务（#7/#8）"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.82))
	vbox.add_child(hint)

	var btn: Button = Button.new()
	btn.text = "确认出发"
	btn.add_theme_font_size_override("font_size", 20)
	btn.custom_minimum_size = Vector2(180.0, 44.0)
	btn.pressed.connect(_on_confirm_departure)
	vbox.add_child(btn)

	_ui_layer.add_child(panel)
	_prep_panel = panel


func _clear_prep() -> void:
	if _prep_panel != null and is_instance_valid(_prep_panel):
		_prep_panel.queue_free()
	_prep_panel = null


func _on_confirm_departure() -> void:
	_clear_prep()
	_run_manager.confirm_departure()  # → stage += 1, phase=battle
	# 事件门 battle=null，不打战斗，走事件流程占位（防 0 单位战斗 soft-lock）；否则正常装配战斗。
	var st: Object = _run_manager.get_state()
	var entry: Variant = st.current_entry_door
	if entry is Dictionary and str((entry as Dictionary).get("reward_type", "")) == "event":
		_enter_event(entry as Dictionary)
	else:
		_enter_battle()


# ── 事件子视图（v0 占位：不打战斗，事件效果执行器待建）─────

## 事件关：显示事件占位 → 继续 → 视为无战斗完成推进。
## RunManager 对事件门 reward_type=="event" 只结算固定金币经验、跳过门奖励
## （run_manager.gd on_battle_resolved 内 event 分支），并推进下一关。
func _enter_event(door: Dictionary) -> void:
	_clear_battle_view()
	var event_id: String = str(door.get("event_id", ""))
	var st: Object = _run_manager.get_state()
	var panel: Control = _build_center_panel()
	var vbox: VBoxContainer = panel.get_node("VBox")

	var label: Label = Label.new()
	label.text = "事件 · stage %d\n%s" % [int(st.stage), event_id]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(label)

	var hint: Label = Label.new()
	hint.text = "[v0 占位] 事件效果执行器待建；本关不打战斗，仅结算固定金币经验"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.82))
	vbox.add_child(hint)

	var btn: Button = Button.new()
	btn.text = "继续"
	btn.add_theme_font_size_override("font_size", 20)
	btn.custom_minimum_size = Vector2(160.0, 42.0)
	btn.pressed.connect(_on_event_continue)
	vbox.add_child(btn)

	_ui_layer.add_child(panel)
	_event_panel = panel


func _clear_event_panel() -> void:
	if _event_panel != null and is_instance_valid(_event_panel):
		_event_panel.queue_free()
	_event_panel = null


## 事件「继续」：视为无战斗胜利，复用结算+切视图入口（事件门在 RunManager 内跳过门奖励）。
func _on_event_continue() -> void:
	_clear_event_panel()
	_on_battle_ended("victory")


# ── 结算 / 结束子视图 ─────────────────────────────────

func _show_end_panel(completed: bool) -> void:
	_clear_end_panel()
	var st: Object = _run_manager.get_state()
	var panel: Control = _build_center_panel()
	var vbox: VBoxContainer = panel.get_node("VBox")

	var label: Label = Label.new()
	if completed:
		label.text = "RUN 通关！\n最终金币：%d" % int(st.gold)
		label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	else:
		label.text = "RUN 失败\n于 stage %d" % int(st.stage)
		label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 30)
	vbox.add_child(label)

	_ui_layer.add_child(panel)
	_end_panel = panel


func _clear_end_panel() -> void:
	if _end_panel != null and is_instance_valid(_end_panel):
		_end_panel.queue_free()
	_end_panel = null


# ── 信号收集（v0 仅打印观测；UI 展示由子视图承担）─────────

func _on_doors_generated(doors: Array) -> void:
	print("[RunScene] 掷出 %d 扇门" % doors.size())


func _on_reward_settled(summary: Dictionary) -> void:
	print("[RunScene] stage %d 结算：sequence=%s gold_after=%d" % [
		int(summary.get("stage", 0)),
		str(summary.get("sequence", [])),
		int(summary.get("gold_after", 0))])


func _on_stage_advanced(stage: int) -> void:
	print("[RunScene] 推进至 stage %d" % stage)


func _on_run_completed() -> void:
	print("[RunScene] === RUN 通关 ===")


func _on_run_failed() -> void:
	print("[RunScene] === RUN 失败 ===")


# ── 工具 ─────────────────────────────────────────────

## 构造一个居中面板（含名为 "VBox" 的 VBoxContainer 供填充），返回根 Control。
func _build_center_panel() -> Control:
	var root_ctrl: Control = Control.new()
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.add_child(bg)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.add_child(center)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)
	return root_ctrl


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("[RunScene] 配置缺失: " + path)
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[RunScene] 无法打开: " + path)
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
