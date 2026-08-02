extends SceneTree
## 剑圣资源引擎 headless 集成测试（批次2：tactical_manager 运行时接线）
##
## 批次1 覆盖真理源代码（unit.gd / damage_calculator.gd）+ JSON 数据层；
## 本批次补足「运行时接线」与「功能性寻路」：
##   A. tactical_manager._apply_sword_qi_on_hit 真实接线（命中产气/击杀返气/mark_gain/cd-1/未命中不产气）
##   B. tactical_manager._build_skill_entry 真实可用性门槛（剑气不足 / 印记不足）
##
## 施放扣气（_execute_skill_action:1249-1254 的 set_sword_qi(-qi_cost)/clear_marks）
## 需完整目标选择流程才能端到端触发；其扣减原语已在批次1验证(set_sword_qi/clear_marks)，
## 门槛读取 skill_data.qi_cost 的路径由本批次 B 段（同样读 skill_data）间接佐证。
##
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/test_swordsman_integration.gd
## 退出码 0=全过，1=有失败。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_swordsman_integration (批次2) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	# 完整实例化战斗场景（_ready 自动 spawn 单位 + start_battle）
	var scene: Node = load("res://scenes/tactical/TacticalScene.tscn").instantiate()
	root.add_child(scene)
	var tm: Object = scene.tactical_manager
	var sword: Unit = _find_kensei(tm)

	if sword == null:
		_check("场景中存在剑圣单位", false, "tm.units 未找到 unit_id==kensei")
	else:
		_check("场景中存在剑圣单位", true)
		_test_on_hit_wiring(tm, sword)
		_test_resource_gate(tm, sword)
		_test_dashboard_stats(tm)
		_test_basic_attack_qi(tm, sword)
		_test_skill_displacement(tm, sword)

	_test_dashboard_widget_format()

	scene.free()

	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  ✗ " + f)
	quit(0 if _fail == 0 else 1)


# ── 断言工具 ─────────────────────────────────────────

func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		_fails.append(name + ("  [" + detail + "]" if detail != "" else ""))
		print("  ✗ " + name + ("  [" + detail + "]" if detail != "" else ""))


func _eq(name: String, actual: Variant, expected: Variant) -> void:
	_check(name, actual == expected, "期望 %s 实际 %s" % [str(expected), str(actual)])


func _find_kensei(tm: Object) -> Unit:
	for u: Unit in tm.units:
		if u.unit_id == "kensei":
			return u
	return null


func _make_result(hit: bool, killed: bool) -> DamageCalculator.AttackResult:
	var r: DamageCalculator.AttackResult = DamageCalculator.AttackResult.new()
	r.hit = hit
	r.defender_died = killed
	return r


# ── A. _apply_sword_qi_on_hit 真实接线 ──────────────────

func _test_on_hit_wiring(tm: Object, sword: Unit) -> void:
	print("\n[A] tactical_manager._apply_sword_qi_on_hit 接线")

	# A1 斩击命中 +1 气
	sword.set_sword_qi(0)
	tm._apply_sword_qi_on_hit(sword, _make_result(true, false), {"qi_gain_on_hit": 1})
	_eq("斩击命中 → +1 气", sword.sword_qi, 1)

	# A2 未命中不产气
	sword.set_sword_qi(2)
	tm._apply_sword_qi_on_hit(sword, _make_result(false, false), {"qi_gain_on_hit": 1})
	_eq("未命中 → 不产气(仍2)", sword.sword_qi, 2)

	# A3 居合击杀返 3 气
	sword.set_sword_qi(0)
	tm._apply_sword_qi_on_hit(sword, _make_result(true, true), {"qi_gain_on_kill": 3})
	_eq("击杀 → 返3气", sword.sword_qi, 3)

	# A4 命中但未击杀，不返击杀气
	sword.set_sword_qi(0)
	tm._apply_sword_qi_on_hit(sword, _make_result(true, false), {"qi_gain_on_kill": 3})
	_eq("命中未击杀 → 不返击杀气(0)", sword.sword_qi, 0)

	# A5 mark_gain 命中得 1 印记
	sword.clear_marks()
	tm._apply_sword_qi_on_hit(sword, _make_result(true, false), {"mark_gain": 1})
	_eq("命中 mark_gain → 印记数1", sword.get_mark_count(), 1)

	# A6 居合击杀 cd-1
	sword.skill_cooldowns["swordsman_juhe"] = 3
	tm._apply_sword_qi_on_hit(sword, _make_result(true, true),
		{"ki_on_kill_cd_reduction": 1, "skill_id": "swordsman_juhe"})
	_eq("居合击杀 → cd 3→2", sword.get_skill_cooldown("swordsman_juhe"), 2)

	# A7 cd 减到 0 则移除冷却条目
	sword.skill_cooldowns["swordsman_juhe"] = 1
	tm._apply_sword_qi_on_hit(sword, _make_result(true, true),
		{"ki_on_kill_cd_reduction": 1, "skill_id": "swordsman_juhe"})
	_check("cd 减到0 → 移除冷却条目",
		sword.get_skill_cooldown("swordsman_juhe") == 0 \
		and not sword.skill_cooldowns.has("swordsman_juhe"))

	# A8 居合完整结算（命中+击杀同次：返气 + 得印记 + cd-1）
	sword.set_sword_qi(0)
	sword.clear_marks()
	sword.skill_cooldowns["swordsman_juhe"] = 3
	tm._apply_sword_qi_on_hit(sword, _make_result(true, true), {
		"qi_gain_on_hit": 0, "qi_gain_on_kill": 3, "mark_gain": 1,
		"ki_on_kill_cd_reduction": 1, "skill_id": "swordsman_juhe",
	})
	_eq("居合完整: 返3气", sword.sword_qi, 3)
	_eq("居合完整: 得1印记", sword.get_mark_count(), 1)
	_eq("居合完整: cd 3→2", sword.get_skill_cooldown("swordsman_juhe"), 2)


# ── B. _build_skill_entry 真实可用性门槛 ────────────────

func _test_resource_gate(tm: Object, sword: Unit) -> void:
	print("\n[B] tactical_manager._build_skill_entry 资源门槛")
	# 进入行动阶段（否则移动阶段会拦截 standard 技能，无法触达资源门槛）。
	# 用整数序号：从 --script 主循环引用全局类 TacticalManager 会触发早期类缓存编译失败，
	# 故直接赋 InputState.ACTION_PHASE 的序号（enum: IDLE=0, MOVE_PHASE=1, ACTION_PHASE=2）。
	tm.input_state = 2
	# 复位行动经济 + 冷却 + 资源，隔离资源门槛
	sword.standard_used = false
	sword.movement_used = false
	sword.swift_used = false
	sword.skill_cooldowns.clear()

	# B1 居合剑气门槛：0 气不可用且原因为剑气不足
	sword.set_sword_qi(0)
	sword.clear_marks()
	var e_qi0: Dictionary = tm._build_skill_entry(sword, "swordsman_juhe")
	_check("居合 0气 → 不可用 且 原因含「剑气」",
		not bool(e_qi0.get("available", false)) and ("剑气" in str(e_qi0.get("reason", ""))),
		"available=%s reason=%s" % [str(e_qi0.get("available")), str(e_qi0.get("reason"))])

	# B2 居合剑气满足：60 气可用（居合单体，上游检查应通过）
	sword.set_sword_qi(60)
	sword.standard_used = false
	var e_qi6: Dictionary = tm._build_skill_entry(sword, "swordsman_juhe")
	_check("居合 60气 → 可用",
		bool(e_qi6.get("available", false)),
		"available=%s reason=%s" % [str(e_qi6.get("available")), str(e_qi6.get("reason"))])

	# B3 拔刀印记门槛：0 印记原因含印记不足
	sword.clear_marks()
	sword.set_sword_qi(20)
	sword.standard_used = false
	var e_m0: Dictionary = tm._build_skill_entry(sword, "swordsman_badao")
	_check("拔刀 0印记 → 原因含「印记」",
		"印记" in str(e_m0.get("reason", "")),
		"available=%s reason=%s" % [str(e_m0.get("available")), str(e_m0.get("reason"))])

	# B4 拔刀印记满足：3 印记后印记门槛通过（原因不再含印记不足；
	#    其余范围/目标支持性不在本断言范围内）
	sword.marks["心"] = true
	sword.marks["道"] = true
	sword.marks["势"] = true
	sword.standard_used = false
	var e_m3: Dictionary = tm._build_skill_entry(sword, "swordsman_badao")
	_check("拔刀 3印记 → 印记门槛通过(原因不含「印记」)",
		not ("印记" in str(e_m3.get("reason", ""))),
		"available=%s reason=%s" % [str(e_m3.get("available")), str(e_m3.get("reason"))])


# ── F. 基础攻击产气（剑圣普攻命中 +10 剑气，数据驱动 basic_attack_qi_gain）──

func _test_basic_attack_qi(tm: Object, sword: Unit) -> void:
	print("\n[F] 基础攻击产气（剑圣普攻命中 +10 剑气）")
	var enemy: Unit = null
	for u: Unit in tm.units:
		if u.faction == "enemy":
			enemy = u
			break
	if enemy == null:
		_check("存在敌方单位", false)
		return
	# 让命中必然发生且目标不死
	enemy.stats.spd = 0
	enemy.stats.lck = 0
	enemy.stats.max_hp = 999
	enemy.stats.hp = 999
	sword.set_sword_qi(0)
	sword.clear_marks()
	# 空 data 模拟基础攻击 payload；_build_hostile_action_context 应按职业补 qi_gain_on_hit
	tm._execute_hostile_action(sword, enemy, {})
	_eq("剑圣普攻命中 → sword_qi==10（基础攻击产气）", sword.sword_qi, 10)


# ── G. 一闪位移（落在所选目标格）──────────────────────────

func _test_skill_displacement(tm: Object, sword: Unit) -> void:
	print("\n[G] 一闪位移 _apply_skill_displacement（落在所选目标格）")
	var start: Vector2i = sword.grid_position
	var landing: Vector2i = Vector2i(-1, -1)
	for nb: Vector2i in tm.grid.get_neighbors(start):
		var c: Cell = tm.grid.get_cell(nb)
		if c != null and c.is_passable() and c.occupant == null:
			landing = nb
			break
	if landing == Vector2i(-1, -1):
		_check("找到可落地空邻格", false)
		return
	tm._apply_skill_displacement(sword, landing)
	_eq("位移到目标空格", sword.grid_position, landing)
	# 目标格被占 → 不位移
	var enemy: Unit = null
	for u: Unit in tm.units:
		if u.faction == "enemy":
			enemy = u
			break
	if enemy != null:
		var before: Vector2i = sword.grid_position
		tm._apply_skill_displacement(sword, enemy.grid_position)
		_eq("目标格被占 → 不位移", sword.grid_position, before)


# ── D. 主属性面板 stats 接线（修复仪表盘全0显示）──────────

func _test_dashboard_stats(tm: Object) -> void:
	print("\n[D] get_dashboard_data 主属性接线 (基础值 + 加成增量)")
	var dd: Dictionary = tm.get_dashboard_data()
	_check("dashboard 含 stats 字典", dd.has("stats") and dd.get("stats") is Dictionary)
	_check("dashboard 含 stats_delta 字典", dd.has("stats_delta") and dd.get("stats_delta") is Dictionary)
	var info: Unit = tm._get_dashboard_unit()
	if info == null:
		_check("存在信息单位", false)
		return
	var st: Dictionary = dd.get("stats", {})
	var delta: Dictionary = dd.get("stats_delta", {})
	# stats 取基础值（unit.stats 原始字段）
	_eq("stats.str==基础STR", st.get("str"), info.stats.str_attr)
	_eq("stats.spd==基础SPD", st.get("spd"), info.stats.spd)
	_eq("stats.dex==基础DEX", st.get("dex"), info.stats.dex)
	_eq("stats.mov==基础MOV", st.get("mov"), info.stats.mov)
	# stats_delta == 生效 − 基础（含印记/心眼/buff 修正）
	_eq("delta.spd==生效−基础SPD", delta.get("spd"), info.get_effective_stat("SPD") - info.stats.spd)
	_eq("delta.dex==生效−基础DEX", delta.get("dex"), info.get_effective_stat("DEX") - info.stats.dex)
	# 修复前症状是全 0；真实单位基础 SPD 必 >0
	_check("主属性非全0(基础spd>0)", int(st.get("spd", 0)) > 0, "spd=%s" % str(st.get("spd")))


func _test_dashboard_widget_format() -> void:
	print("\n[E] 仪表盘部件: 基础值+括号加成文本格式")
	var dash: Control = load("res://scenes/tactical/bottom_dashboard.tscn").instantiate()
	root.add_child(dash)
	dash.update_state({
		"visible": true, "mode": "player", "unit_name": "测试单位",
		"hp": 20, "hp_max": 20,
		"stats": {"str": 10, "mag": 2, "dex": 9, "spd": 8, "def": 5, "res": 4, "lck": 5, "mov": 4},
		"stats_delta": {"str": 2, "mag": 0, "dex": 2, "spd": 1, "def": 0, "res": 0, "lck": 0, "mov": 0},
	})
	var labels: Array = dash._stat_value_labels
	if labels.size() < 4:
		_check("stat 标签已构建(>=4)", false, "labels=%d" % labels.size())
		dash.free()
		return
	# 显示顺序: str, mag, dex, spd, ...
	_eq("STR 有加成 → '10 (+2)'", labels[0].text, "10 (+2)")
	_eq("MAG 无加成 → '2'", labels[1].text, "2")
	_eq("DEX 有加成 → '9 (+2)'", labels[2].text, "9 (+2)")
	_eq("SPD 心眼加成 → '8 (+1)'", labels[3].text, "8 (+1)")
	dash.free()
