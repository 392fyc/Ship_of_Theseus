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
var _act_config: Dictionary = {}          # 缓存 act1_config（伏击地图 [占位] 取 door_gen.map_pool[0]）
var _event_id: String = ""                # 当前事件门的 event_id（choices → outcome → effects 流程共用）

var _ui_layer: CanvasLayer = null
var _battle_view: Node = null
var _door_select: Control = null
var _prep_panel: Control = null
var _end_panel: Control = null
var _event_panel: Control = null

# ── Prep v0 交互状态（恢复选择 / 运输队选中角色 / 出发提示一次）──
var _prep_accepts: Array[bool] = []       # 每角色是否接受恢复（默认 true）
var _prep_selected_member: int = 0        # 运输队面板当前操作的角色下标
var _prep_warned: bool = false            # 出发时「有人拒绝恢复」提示是否已给过
var _prep_body: VBoxContainer = null      # Prep 可刷新主体容器（切换恢复/运输队后重建）
var _prep_warn_label: Label = null        # 出发提示标签


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
	_act_config = act_config
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


## 从战斗视图采集存活玩家单位 HP，经 RunManager 写回 party（HP 跨关继承 #8）。
## 事件门无战斗（_battle_view 为空）→ 直接返回，不改 party。
func _writeback_party_hp() -> void:
	if _battle_view == null or not is_instance_valid(_battle_view):
		return
	var tm: Object = _battle_view.tactical_manager
	if tm == null:
		return
	var survivors: Array = []
	for u: Variant in tm.units:
		if u == null or not is_instance_valid(u):
			continue
		if str(u.faction) != "player":
			continue
		if u.stats == null or not u.stats.is_alive():
			continue
		survivors.append({
			"class_id": str(u.unit_id),
			"hp": int(u.stats.hp),
			"max_hp": int(u.stats.max_hp),
		})
	_run_manager.writeback_party_hp(survivors)


## 战斗结束回调：先把存活玩家 HP 写回 party（磨损跨关继承），再结算 → 据新 phase 切子视图。
func _on_battle_ended(result: String) -> void:
	_writeback_party_hp()  # 必须在 _clear_battle_view 之前读战斗视图单位
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


# ── Prep 子视图（v0：查看情报 + 恢复 + 运输队 + 确认出发）────────
# 真源：runloop-reward-map-proposal.md §5 恢复模型 + §7.5 Prep；逻辑落在 RunManager。
# 本层纯 UI：读 RunManager 的情报/恢复量，调 recover_party / 运输队 move 方法。

func _show_prep() -> void:
	_clear_prep()
	var st: Object = _run_manager.get_state()
	_prep_warned = false
	_init_prep_accepts(st)
	if _prep_selected_member < 0 or _prep_selected_member >= st.party.size():
		_prep_selected_member = 0

	var panel: Control = _build_center_panel()
	var vbox: VBoxContainer = panel.get_node("Center/VBox")

	var title: Label = Label.new()
	title.text = "备战 (Prep) — 下一关：stage %d" % (int(st.stage) + 1)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	# 查看情报
	vbox.add_child(_build_intel_section())

	# 可刷新主体（恢复 + 运输队），切换选择/移动后重建
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(580.0, 340.0)
	vbox.add_child(scroll)
	_prep_body = VBoxContainer.new()
	_prep_body.add_theme_constant_override("separation", 8)
	_prep_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prep_body.custom_minimum_size = Vector2(560.0, 0.0)
	scroll.add_child(_prep_body)
	_rebuild_prep_body()

	_prep_warn_label = Label.new()
	_prep_warn_label.text = ""
	_prep_warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prep_warn_label.add_theme_font_size_override("font_size", 13)
	_prep_warn_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.35))
	vbox.add_child(_prep_warn_label)

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
	_prep_body = null
	_prep_warn_label = null


## 初始化每角色恢复接受标记（默认接受恢复[提案]）。
func _init_prep_accepts(st: Object) -> void:
	var accepts: Array[bool] = []
	for _m: Variant in st.party:
		accepts.append(true)
	_prep_accepts = accepts


## 查看情报区（下一关地图/波次 + 精英/Boss + 特殊词条名；基础词条隐藏=相性赌）。
func _build_intel_section() -> Control:
	var intel: Dictionary = _run_manager.get_prep_intel()
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(_make_section_label("查看情报"))

	var lines: PackedStringArray = []
	var map_name: String = str(intel.get("map_name", ""))
	if bool(intel.get("is_boss", false)):
		lines.append("下一关：Boss 战 — %s" % map_name)
	else:
		lines.append("下一关：%s（波次 %s）" % [map_name, str(intel.get("wave_id", ""))])
	if bool(intel.get("elite", false)):
		lines.append("💀 精英房")
	var sa_name: String = str(intel.get("special_affix_name", ""))
	if sa_name != "":
		lines.append("特殊词条（进房前可见）：%s" % sa_name)
	elif bool(intel.get("elite", false)):
		lines.append("特殊词条：无")
	lines.append("（基础词条进房前隐藏 — 相性赌）")

	var body: Label = Label.new()
	body.text = "\n".join(lines)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 14)
	body.add_theme_color_override("font_color", Color(0.78, 0.84, 0.92))
	box.add_child(body)
	return box


## 重建 Prep 主体（[商店区] + 恢复区 + 运输队区）。切换恢复接受 / 买卖 / 运输队移动后刷新。
func _rebuild_prep_body() -> void:
	if _prep_body == null or not is_instance_valid(_prep_body):
		return
	for c: Node in _prep_body.get_children():
		c.queue_free()
	var st: Object = _run_manager.get_state()

	# ── 商店区（仅商店 Prep：幕中第4关后 + Boss 前；不占门不占关）──
	if _run_manager.is_shop_prep():
		_prep_body.add_child(_build_shop_section(st))

	# ── 恢复区 ──
	var pct: int = roundi(_run_manager.get_recovery_percent())
	_prep_body.add_child(_make_section_label(
		"恢复（%d%% 最大生命，run 内恒定；可按角色拒绝＝背水流[提案]）" % pct))
	for i: int in range(st.party.size()):
		_prep_body.add_child(_build_recovery_row(i, st.party[i]))

	# ── 运输队区 ──
	_prep_body.add_child(_make_section_label(
		"运输队 / 装备（v0 仅数据交换，装备/遗物效果不生效[占位]）"))
	_prep_body.add_child(_build_member_selector(st))
	_prep_body.add_child(_build_convoy_panel(st))


## 单角色恢复行：HP x/max + 恢复量预览 + 恢复/拒绝切换。
func _build_recovery_row(index: int, member: Dictionary) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var hp: int = int(member.get("hp", 0))
	var max_hp: int = int(member.get("max_hp", 0))
	var amount: int = _run_manager.get_recovery_amount(member)
	var effective_gain: int = mini(amount, maxi(0, max_hp - hp))
	var accept: bool = index < _prep_accepts.size() and _prep_accepts[index]

	var lbl: Label = Label.new()
	var preview: String = ("+%d" % effective_gain) if accept else "拒绝"
	lbl.text = "%s  HP %d/%d  (%s)" % [str(member.get("class_id", "")), hp, max_hp, preview]
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.custom_minimum_size = Vector2(320.0, 0.0)
	row.add_child(lbl)

	var toggle: Button = Button.new()
	toggle.text = "恢复" if accept else "拒绝"
	toggle.add_theme_font_size_override("font_size", 13)
	toggle.disabled = not _run_manager.get_recovery_declinable()
	toggle.pressed.connect(_on_toggle_recovery.bind(index))
	row.add_child(toggle)
	return row


func _on_toggle_recovery(index: int) -> void:
	if index >= 0 and index < _prep_accepts.size():
		_prep_accepts[index] = not _prep_accepts[index]
	_rebuild_prep_body()


## 运输队面板操作对象选择（角色行）。
func _build_member_selector(st: Object) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var head: Label = Label.new()
	head.text = "操作角色："
	head.add_theme_font_size_override("font_size", 13)
	row.add_child(head)
	for i: int in range(st.party.size()):
		var b: Button = Button.new()
		var prefix: String = "▶ " if i == _prep_selected_member else ""
		b.text = "%s%s" % [prefix, str((st.party[i] as Dictionary).get("class_id", ""))]
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_on_select_member.bind(i))
		row.add_child(b)
	return row


func _on_select_member(index: int) -> void:
	_prep_selected_member = index
	_rebuild_prep_body()


## 运输队面板：选中角色装备槽 / 遗物 与 运输队库存 的存取（数据交换）。
func _build_convoy_panel(st: Object) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var m: int = clampi(_prep_selected_member, 0, maxi(0, st.party.size() - 1))
	if st.party.is_empty():
		return box
	var member: Dictionary = st.party[m]
	var cid: String = str(member.get("class_id", ""))
	var equip: Dictionary = member.get("equipment", {"weapon": "", "armor": ""})
	var relics: Array = member.get("relics", [])
	var convoy_eq: Array = st.convoy.get("equipment", [])
	var convoy_relics: Array = st.convoy.get("relics", [])

	# 角色装备槽（可卸下）
	box.add_child(_make_line_label("角色 %s 装备：兵器=%s 防具=%s" % [
		cid, _slot_text(str(equip.get("weapon", ""))), _slot_text(str(equip.get("armor", "")))]))
	for slot: String in ["weapon", "armor"]:
		if str(equip.get(slot, "")) != "":
			var r: HBoxContainer = HBoxContainer.new()
			r.add_theme_constant_override("separation", 8)
			r.add_child(_make_line_label("  %s: %s" % [slot, str(equip.get(slot))]))
			var ub: Button = _make_small_button("卸下→运输队")
			ub.pressed.connect(_on_unequip.bind(m, slot))
			r.add_child(ub)
			box.add_child(r)

	# 角色遗物（可收回）
	box.add_child(_make_line_label("角色遗物（%d/%d）：" % [relics.size(), 6]))
	for ri: int in range(relics.size()):
		var rr: HBoxContainer = HBoxContainer.new()
		rr.add_theme_constant_override("separation", 8)
		rr.add_child(_make_line_label("  %s" % str(relics[ri])))
		var cb: Button = _make_small_button("收回→运输队")
		cb.pressed.connect(_on_relic_to_convoy.bind(m, ri))
		rr.add_child(cb)
		box.add_child(rr)

	# 运输队装备（装到选中角色）
	box.add_child(_make_line_label("运输队装备（%d）：" % convoy_eq.size()))
	for ci: int in range(convoy_eq.size()):
		var er: HBoxContainer = HBoxContainer.new()
		er.add_theme_constant_override("separation", 6)
		er.add_child(_make_line_label("  %s" % str(convoy_eq[ci])))
		var wbtn: Button = _make_small_button("装兵器")
		wbtn.pressed.connect(_on_equip.bind(m, ci, "weapon"))
		er.add_child(wbtn)
		var abtn: Button = _make_small_button("装防具")
		abtn.pressed.connect(_on_equip.bind(m, ci, "armor"))
		er.add_child(abtn)
		box.add_child(er)

	# 运输队遗物（给选中角色）
	box.add_child(_make_line_label("运输队遗物（%d）：" % convoy_relics.size()))
	for cri: int in range(convoy_relics.size()):
		var cr: HBoxContainer = HBoxContainer.new()
		cr.add_theme_constant_override("separation", 6)
		cr.add_child(_make_line_label("  %s" % str(convoy_relics[cri])))
		var gb: Button = _make_small_button("给 %s" % cid)
		gb.pressed.connect(_on_relic_to_member.bind(m, cri))
		cr.add_child(gb)
		box.add_child(cr)
	return box


func _on_equip(member_index: int, convoy_index: int, slot: String) -> void:
	_run_manager.equip_from_convoy(member_index, convoy_index, slot)
	_rebuild_prep_body()


func _on_unequip(member_index: int, slot: String) -> void:
	_run_manager.unequip_to_convoy(member_index, slot)
	_rebuild_prep_body()


func _on_relic_to_member(member_index: int, convoy_index: int) -> void:
	_run_manager.move_relic_to_member(member_index, convoy_index)
	_rebuild_prep_body()


func _on_relic_to_convoy(member_index: int, relic_index: int) -> void:
	_run_manager.move_relic_to_convoy(member_index, relic_index)
	_rebuild_prep_body()


# ── 商店区（v0：库存买入 + 运输队回收卖出 + 金币显示；纯经济层，不碰战斗）──
# 真源：runloop-reward-map-proposal.md §7.4 商店固定插入；逻辑落在 RunManager。
# 价格 / 库存 / sell_ratio 为 [占位]，从 act_config.shop 读。

## 商店面板：当前金币 + 库存列表（买）+ 运输队可卖项（卖）。买卖后 _rebuild_prep_body 刷新。
func _build_shop_section(st: Object) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_make_section_label(
		"商店（固定插入：幕中第4关后 + Boss 前；不占门不占关；价格[占位]）"))

	# 当前金币
	var gold_lbl: Label = Label.new()
	gold_lbl.text = "当前金币：%d" % int(st.gold)
	gold_lbl.add_theme_font_size_override("font_size", 15)
	gold_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	box.add_child(gold_lbl)

	# 库存（买入）
	box.add_child(_make_line_label("库存（买入）："))
	var stock: Array = _run_manager.get_shop_stock()
	if stock.is_empty():
		box.add_child(_make_line_label("  （售罄）"))
	for item_v: Variant in stock:
		if not (item_v is Dictionary):
			continue
		var item: Dictionary = item_v
		var price: int = int(item.get("price", 0))
		var affordable: bool = int(st.gold) >= price
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(_make_line_label("  %s [%s·%s]  价 %d" % [
			str(item.get("name", "")), str(item.get("kind", "")),
			str(item.get("rarity", "")), price]))
		var bb: Button = _make_small_button("买入")
		bb.disabled = not affordable
		bb.pressed.connect(_on_shop_buy.bind(item))
		row.add_child(bb)
		box.add_child(row)

	# 卖出（运输队回收）
	box.add_child(_make_line_label("卖出（运输队回收，回收比例[占位]）："))
	var convoy_eq: Array = st.convoy.get("equipment", [])
	for ci: int in range(convoy_eq.size()):
		box.add_child(_build_sell_row("equipment", str(convoy_eq[ci])))
	var convoy_relics: Array = st.convoy.get("relics", [])
	for cri: int in range(convoy_relics.size()):
		box.add_child(_build_sell_row("relic", str(convoy_relics[cri])))
	var convoy_potions: Array = st.convoy.get("potions", [])
	for cpi: int in range(convoy_potions.size()):
		box.add_child(_build_sell_row("potion", str(convoy_potions[cpi])))
	if convoy_eq.is_empty() and convoy_relics.is_empty() and convoy_potions.is_empty():
		box.add_child(_make_line_label("  （运输队无可卖物）"))
	return box


## 单个卖出行：物品名 + 卖价预览 + 卖按钮。
func _build_sell_row(kind: String, ref_id: String) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var sell_price: int = _run_manager.get_sell_price(kind, ref_id)
	row.add_child(_make_line_label("  %s [%s]  卖价 %d" % [ref_id, kind, sell_price]))
	var sb: Button = _make_small_button("卖出")
	sb.pressed.connect(_on_shop_sell.bind(kind, ref_id))
	row.add_child(sb)
	return row


func _on_shop_buy(item: Dictionary) -> void:
	_run_manager.buy_item(item)
	_rebuild_prep_body()


func _on_shop_sell(kind: String, ref_id: String) -> void:
	_run_manager.sell_item(kind, ref_id, "convoy")
	_rebuild_prep_body()


## 确认出发：先按 accepts 应用恢复 → confirm_departure → 装配下一关（事件门走事件流程）。
## 若有角色未满血且拒绝恢复 → 首次点击仅提示一次[提案]，再次点击才出发。
func _on_confirm_departure() -> void:
	var st: Object = _run_manager.get_state()
	if not _prep_warned and _has_worn_declined(st):
		_prep_warned = true
		if _prep_warn_label != null and is_instance_valid(_prep_warn_label):
			_prep_warn_label.text = "有角色未满血且拒绝恢复（背水流）。再次点击「确认出发」继续。"
		return
	_run_manager.recover_party(_prep_accepts)  # 先恢复再出发
	_clear_prep()
	_run_manager.confirm_departure()  # → stage += 1, phase=battle
	# 事件门 battle=null，不打战斗，走事件流程占位（防 0 单位战斗 soft-lock）；否则正常装配战斗。
	var entry: Variant = _run_manager.get_state().current_entry_door
	if entry is Dictionary and str((entry as Dictionary).get("reward_type", "")) == "event":
		_enter_event(entry as Dictionary)
	else:
		_enter_battle()


## 是否存在「未满血且拒绝恢复」的角色（供出发提示一次判定）。
func _has_worn_declined(st: Object) -> bool:
	for i: int in range(st.party.size()):
		var m: Dictionary = st.party[i]
		var hp: int = int(m.get("hp", 0))
		var max_hp: int = int(m.get("max_hp", 0))
		var accept: bool = i < _prep_accepts.size() and _prep_accepts[i]
		if max_hp > 0 and hp < max_hp and not accept:
			return true
	return false


func _slot_text(item: String) -> String:
	return item if item != "" else "（空）"


## Prep 小节标题（黄色，稍大）。
func _make_section_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	return label


## Prep 明细行文本（浅灰）。
func _make_line_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
	label.custom_minimum_size = Vector2(300.0, 0.0)
	return label


## Prep 小按钮。
func _make_small_button(text: String) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 12)
	return btn


# ── 事件子视图（v0：choices → 加权抽 outcome → 应用 effects → 伏击战斗或推进）─────
# 真源：data/events/*.json + 迭代 #12 规格。事件门 soft-lock 修复保留：事件门不当普通战斗
# 装配（confirm_departure 后 current_battle 无 map → _on_confirm_departure 走本流程）。
# 无战斗 outcome → 「继续」视为无战斗胜利推进；start_battle outcome → 装配伏击战斗（复用注入路径）。

## 事件关入口：清战斗视图，记 event_id，显示 choices 面板。
func _enter_event(door: Dictionary) -> void:
	_clear_battle_view()
	_event_id = str(door.get("event_id", ""))
	_show_event_choices()


## 显示事件 title + description + 每个 choice 一个按钮。缺事件数据 → 占位「继续」兜底（防 soft-lock）。
func _show_event_choices() -> void:
	_clear_event_panel()
	var st: Object = _run_manager.get_state()
	var panel: Control = _build_center_panel()
	var vbox: VBoxContainer = panel.get_node("Center/VBox")
	var event: Dictionary = _current_event()

	if event.is_empty():
		push_warning("[RunScene] 事件数据缺失: %s，回退占位继续" % _event_id)
		var miss: Label = Label.new()
		miss.text = "事件 · stage %d\n[数据缺失] %s" % [int(st.stage), _event_id]
		miss.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		miss.add_theme_font_size_override("font_size", 20)
		vbox.add_child(miss)
		var cbtn: Button = Button.new()
		cbtn.text = "继续"
		cbtn.custom_minimum_size = Vector2(160.0, 42.0)
		cbtn.pressed.connect(_on_event_continue)
		vbox.add_child(cbtn)
		_ui_layer.add_child(panel)
		_event_panel = panel
		return

	var title: Label = Label.new()
	title.text = "事件 · stage %d — %s" % [int(st.stage), str(event.get("title", _event_id))]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	var desc: Label = Label.new()
	desc.text = str(event.get("description", ""))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(560.0, 0.0)
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
	vbox.add_child(desc)

	var choices: Array = event.get("choices", []) if event.get("choices") is Array else []
	for ci: int in range(choices.size()):
		if not (choices[ci] is Dictionary):
			continue
		var choice: Dictionary = choices[ci]
		var btn: Button = Button.new()
		btn.text = str(choice.get("text", "选项 %d" % (ci + 1)))
		btn.add_theme_font_size_override("font_size", 16)
		btn.custom_minimum_size = Vector2(440.0, 40.0)
		btn.pressed.connect(_on_event_choice.bind(ci))
		vbox.add_child(btn)

	_ui_layer.add_child(panel)
	_event_panel = panel


## 选中 choice：加权抽 outcome → 应用 effects → 显示结果面板。缺数据兜底继续（防卡）。
func _on_event_choice(choice_index: int) -> void:
	var event: Dictionary = _current_event()
	var choices: Array = event.get("choices", []) if event.get("choices") is Array else []
	if choice_index < 0 or choice_index >= choices.size() or not (choices[choice_index] is Dictionary):
		_on_event_continue()
		return
	var choice: Dictionary = choices[choice_index]
	var outcome: Dictionary = _run_manager.pick_event_outcome(choice, _rng)
	var result: Dictionary = _run_manager.apply_event_outcome(outcome)
	_show_event_outcome(outcome, result)


## 显示 outcome.description + effect 日志（金币/血量变化可见）+ 当前金币 +
## 「迎战伏击」（battle_triggered）或「继续」按钮。
func _show_event_outcome(outcome: Dictionary, result: Dictionary) -> void:
	_clear_event_panel()
	var st: Object = _run_manager.get_state()
	var panel: Control = _build_center_panel()
	var vbox: VBoxContainer = panel.get_node("Center/VBox")

	var head: Label = Label.new()
	head.text = "事件结果 · stage %d" % int(st.stage)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 22)
	vbox.add_child(head)

	var desc: Label = Label.new()
	desc.text = str(outcome.get("description", ""))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(560.0, 0.0)
	desc.add_theme_font_size_override("font_size", 15)
	desc.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	vbox.add_child(desc)

	var logs: Array = result.get("logs", []) if result.get("logs") is Array else []
	if not logs.is_empty():
		var lines: PackedStringArray = []
		for l_v: Variant in logs:
			lines.append(str(l_v))
		var log_lbl: Label = Label.new()
		log_lbl.text = "\n".join(lines)
		log_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		log_lbl.add_theme_font_size_override("font_size", 13)
		log_lbl.add_theme_color_override("font_color", Color(0.72, 0.86, 0.72))
		vbox.add_child(log_lbl)

	var gold_lbl: Label = Label.new()
	gold_lbl.text = "当前金币：%d" % int(st.gold)
	gold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_lbl.add_theme_font_size_override("font_size", 15)
	gold_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	vbox.add_child(gold_lbl)

	var btn: Button = Button.new()
	btn.add_theme_font_size_override("font_size", 20)
	btn.custom_minimum_size = Vector2(180.0, 44.0)
	if bool(result.get("battle_triggered", false)):
		btn.text = "迎战伏击"
		btn.pressed.connect(_on_event_start_battle.bind(str(result.get("enemy_config", ""))))
	else:
		btn.text = "继续"
		btn.pressed.connect(_on_event_continue)
	vbox.add_child(btn)

	_ui_layer.add_child(panel)
	_event_panel = panel


## 伏击战斗：用事件 effect 的 enemy_config + 占位地图装配，复用 #6 注入路径（不改战斗核心）。
## 胜利 → battle_ended → _on_battle_ended 正常结算推进（事件门在 RunManager 内跳过门奖励）。
func _on_event_start_battle(enemy_config: String) -> void:
	_clear_event_panel()
	_clear_battle_view()
	var st: Object = _run_manager.get_state()
	var map_id: String = _ambush_map_id()
	var assembled: Dictionary = BattleAssemblerScript.build(
		map_id, enemy_config, st.party, _data_pools)

	var inst: Node = TacticalSceneScene.instantiate()
	inst.run_injected = true
	inst.debug_harness_enabled = false
	inst.injected_map_id = str(assembled.get("map_id", map_id))
	inst.injected_player_units = assembled.get("player_units", [])
	inst.injected_enemy_units = assembled.get("enemy_units", [])
	inst.battle_ended.connect(_on_battle_ended)
	_battle_view = inst
	add_child(inst)
	print("[RunScene] 事件伏击战斗：map=%s wave=%s（玩家 %d / 敌人 %d）" % [
		inst.injected_map_id, enemy_config,
		(inst.injected_player_units as Array).size(),
		(inst.injected_enemy_units as Array).size()])


## 伏击地图 [占位]：事件门 battle=null 无 map，取 act_config.door_gen.map_pool[0]（数据驱动，
## 非硬编码 id）；缺配置回退首张已加载地图。
func _ambush_map_id() -> String:
	var dg_v: Variant = _act_config.get("door_gen")
	if dg_v is Dictionary:
		var mp_v: Variant = (dg_v as Dictionary).get("map_pool")
		if mp_v is Array and not (mp_v as Array).is_empty():
			return str((mp_v as Array)[0])
	var maps: Dictionary = _data_pools.get("maps") if _data_pools.get("maps") is Dictionary else {}
	for k: Variant in maps.keys():
		return str(k)
	return ""


## 取当前事件门的 Event 数据字典（缺失返回 {}）。
func _current_event() -> Dictionary:
	var events: Dictionary = _data_pools.get("events") if _data_pools.get("events") is Dictionary else {}
	var event_v: Variant = events.get(_event_id)
	return event_v if event_v is Dictionary else {}


func _clear_event_panel() -> void:
	if _event_panel != null and is_instance_valid(_event_panel):
		_event_panel.queue_free()
	_event_panel = null


## 事件「继续」（无战斗 outcome）：视为无战斗胜利，复用结算+切视图入口
## （事件门在 RunManager 内跳过门奖励，只结算固定金币经验）。
func _on_event_continue() -> void:
	_clear_event_panel()
	_on_battle_ended("victory")


# ── 结算 / 结束子视图 ─────────────────────────────────

func _show_end_panel(completed: bool) -> void:
	_clear_end_panel()
	var st: Object = _run_manager.get_state()
	var panel: Control = _build_center_panel()
	var vbox: VBoxContainer = panel.get_node("Center/VBox")

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
	center.name = "Center"  # VBox 挂其下；面板函数经 get_node("Center/VBox") 访问
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
