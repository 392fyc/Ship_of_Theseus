extends SceneTree
## 敌人词条（affix）效果执行器 v0 —— 迭代#13：4 个声明式占位词条的真实生效验证。
##
## 覆盖本迭代把「占位」升级为「真实生效」的三条 hook + 一条诚实占位：
##   - af_vanguard（先手部署）：unit.gd 首回合速度加成态（round_ended 关闭）——已实装。
##   - af_zone_expand（控域）：pathfinding.gd ZOC 半径 = 1 + zoc_radius_bonus——已实装。
##   - afs_bulwark（壁垒统御）：damage_calculator 防御乘区 + tactical_manager 己方全队光环——已实装。
##   - af_siege（攻城）：无「建筑作为可攻击战斗目标」系统 —— 保持诚实占位（不测生效，见说明）。
##
## 每条已实装词条均附「无词条零影响对照」，证明纯加法门控（无词条单位行为逐位不变）。
##
## 运行：
##   <Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##     --script res://tests/test_affix_effects.gd
## 退出码 0=全过，1=有失败。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_affix_effects (词条效果执行器 v0 · 迭代#13) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	var dl: Object = load("res://scripts/data/data_loader.gd").new()
	dl.load_all()

	_test_vanguard(dl)
	_test_zone_expand(dl)
	_test_bulwark(dl)
	_test_siege_placeholder(dl)
	_test_global_zero_impact(dl)

	dl.free()
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


func _feq(name: String, actual: float, expected: float, eps: float = 0.0001) -> void:
	_check(name, absf(actual - expected) <= eps, "期望≈%s 实际 %s" % [str(expected), str(actual)])


func _make_unit(class_data: Dictionary, faction: String = "player") -> Unit:
	var u: Unit = load("res://scenes/tactical/Unit.tscn").instantiate()
	u.faction = faction
	root.add_child(u)
	u.setup(class_data)
	return u


# ── 1. af_vanguard：首回合速度加成（已实装 · hook=unit.gd get_effective_stat SPD 态）──

func _test_vanguard(dl: Object) -> void:
	print("\n[1] af_vanguard 首回合速度加成（已实装）")
	# 基准：goblin_melee base SPD==5（见 test_affix_system 回归零影响）。
	var base_spd: int = 5
	# 无词条对照：SPD 不变 + expire_vanguard() 为空操作。
	var plain: Unit = _make_unit(dl.enemies["goblin_melee"], "enemy")
	_eq("无词条 SPD==5（零影响对照）", plain.get_effective_stat("SPD"), base_spd)
	plain.expire_vanguard()
	_eq("无词条 expire_vanguard() 后 SPD 仍==5（空操作）", plain.get_effective_stat("SPD"), base_spd)
	plain.free()
	# 带 af_vanguard(first_round_spd=2)：挂载即激活 → SPD==7。
	var u: Unit = _make_unit(dl.enemies["goblin_melee"], "enemy")
	u.apply_affixes(["af_vanguard"], null, 1.0, dl.affixes)
	_eq("af_vanguard 挂载 → 首回合 SPD==7 (+2)", u.get_effective_stat("SPD"), base_spd + 2)
	# 其它属性不受影响（仅 SPD 键加成）。
	_eq("af_vanguard → STR 不受影响==2", u.get_effective_stat("STR"), 2)
	# round 1 结束 → expire_vanguard() 关闭 → SPD 回落 base。
	u.expire_vanguard()
	_eq("expire_vanguard()（round 1 末）→ SPD 回落==5", u.get_effective_stat("SPD"), base_spd)
	u.free()
	# turn_manager 回合序号 hook 存在性（vanguard 首回合判定所依赖的语义源）。
	var tm: Object = load("res://scripts/core/turn_manager.gd").new()
	root.add_child(tm)
	_eq("TurnManager.get_round_number() start 前==0", tm.get_round_number(), 0)
	var mover: Unit = _make_unit(dl.enemies["goblin_melee"], "enemy")
	var typed: Array[Unit] = [mover]
	tm.add_units(typed)
	tm.start()
	_eq("TurnManager.get_round_number() start 后==1（首回合）", tm.get_round_number(), 1)
	tm.stop()
	mover.free()
	tm.free()


# ── 2. af_zone_expand：ZOC 半径扩展（已实装 · hook=pathfinding.gd _in_enemy_zoc）──

func _test_zone_expand(dl: Object) -> void:
	print("\n[2] af_zone_expand 控域 ZOC 半径（已实装）")
	var grid_script: GDScript = load("res://scripts/core/grid.gd")
	var path_script: GDScript = load("res://scripts/core/pathfinding.gd")
	var start: Vector2i = Vector2i(2, 2)
	var move_points: int = 5

	# 场景 A（无词条对照）：敌方在 distance 2（非相邻）→ 无 ZOC 惩罚 → 起点剩余==5。
	var grid_a: Object = grid_script.new()
	grid_a.initialize({"width": 5, "height": 5, "id": "zoc_a"})
	var player_a: Unit = _make_unit(dl.enemies["goblin_melee"], "player")
	var enemy_a: Unit = _make_unit(dl.enemies["goblin_melee"], "enemy")
	grid_a.place_unit(player_a, start)
	grid_a.place_unit(enemy_a, Vector2i(2, 4))  # distance 2
	var mr_a: Dictionary = path_script.get_move_range(grid_a, start, move_points, "player")
	_eq("无 zone_expand · 敌方 dist2 → 起点剩余 MP==5（无惩罚，零影响）",
		int(mr_a.get(start, -1)), 5)

	# 场景 B：同布局，敌方带 af_zone_expand(zoc_radius_bonus=1) → 半径 2 → 起点入 ZOC → 剩余==4。
	var grid_b: Object = grid_script.new()
	grid_b.initialize({"width": 5, "height": 5, "id": "zoc_b"})
	var player_b: Unit = _make_unit(dl.enemies["goblin_melee"], "player")
	var enemy_b: Unit = _make_unit(dl.enemies["goblin_melee"], "enemy")
	enemy_b.apply_affixes(["af_zone_expand"], null, 1.0, dl.affixes)
	grid_b.place_unit(player_b, start)
	grid_b.place_unit(enemy_b, Vector2i(2, 4))  # distance 2，radius 2 覆盖
	var mr_b: Dictionary = path_script.get_move_range(grid_b, start, move_points, "player")
	_eq("af_zone_expand · 敌方 dist2 → 起点剩余 MP==4（半径2 命中，扣 ZOC 惩罚）",
		int(mr_b.get(start, -1)), 4)

	# 场景 C（基础 ZOC 不变）：普通敌方相邻 dist1 → 仍触发惩罚（与引入词条前一致）。
	var grid_c: Object = grid_script.new()
	grid_c.initialize({"width": 5, "height": 5, "id": "zoc_c"})
	var player_c: Unit = _make_unit(dl.enemies["goblin_melee"], "player")
	var enemy_c: Unit = _make_unit(dl.enemies["goblin_melee"], "enemy")
	grid_c.place_unit(player_c, start)
	grid_c.place_unit(enemy_c, Vector2i(2, 3))  # distance 1（相邻）
	var mr_c: Dictionary = path_script.get_move_range(grid_c, start, move_points, "player")
	_eq("基础 ZOC 不变 · 无词条敌方 dist1 → 起点剩余 MP==4（相邻惩罚照旧）",
		int(mr_c.get(start, -1)), 4)

	player_a.free(); enemy_a.free()
	player_b.free(); enemy_b.free()
	player_c.free(); enemy_c.free()


# ── 3. afs_bulwark：己方减伤光环（已实装 · hook=damage_calculator 防御乘区 + 全队扫描）──

func _test_bulwark(dl: Object) -> void:
	print("\n[3] afs_bulwark 壁垒统御 己方减伤光环（已实装）")
	# 3a. damage_calculator 层：honor affix_defense_multiplier（默认 1.0 零影响；显式 0.8 减伤）。
	var atk: Unit = _make_unit(dl.enemies["goblin_melee"], "enemy")
	atk.stats.str_attr = 20
	atk.stats.dex = 0  # 不暴击（确定性）
	var dft: Unit = _make_unit(dl.enemies["goblin_melee"], "player")
	dft.stats.def_attr = 0
	dft.stats.lck = 5
	dft.stats.max_hp = 999
	dft.stats.hp = 999
	var base_action: Dictionary = {
		"damage_type": "physical", "weapon_might": 0, "guaranteed_hit": true}
	# 无 affix_defense_multiplier → base 20（零影响对照）。
	var pv_plain: Dictionary = DamageCalculator.preview_attack(atk, dft, base_action)
	_eq("无防御乘区 → 伤害==20（零影响对照）", pv_plain["damage"], 20)
	# affix_defense_multiplier=0.8（20% 减伤）→ 16，且 preview==resolve。
	var reduced_action: Dictionary = base_action.duplicate(true)
	reduced_action["affix_defense_multiplier"] = 0.8
	var pv_red: Dictionary = DamageCalculator.preview_attack(atk, dft, reduced_action)
	_eq("防御乘区 0.8 → preview 伤害==16 (20*0.8)", pv_red["damage"], 16)
	var rz_red: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft, reduced_action)
	_eq("防御乘区 0.8 → resolve 伤害==preview(16)", rz_red.damage, pv_red["damage"])
	atk.free()
	dft.free()

	# 3b. tactical_manager 全队光环扫描纯函数：无携带→1.0；有存活携带→0.8；仅死者携带→1.0。
	var tm_script: GDScript = load("res://scripts/core/tactical_manager.gd")
	var normal_ally: Unit = _make_unit(dl.enemies["goblin_melee"], "player")
	_feq("无 bulwark 己方 → 乘区==1.0（零影响对照）",
		tm_script._compute_bulwark_multiplier([normal_ally]), 1.0)
	var bulwark_ally: Unit = _make_unit(dl.enemies["goblin_melee"], "player")
	bulwark_ally.apply_affixes([], "afs_bulwark", 1.0, dl.affixes)
	_feq("存活 bulwark 己方 → 乘区==0.8 (1 - 20%)",
		tm_script._compute_bulwark_multiplier([normal_ally, bulwark_ally]), 0.8)
	# 携带者死亡 → 光环失效 → 1.0。
	bulwark_ally.stats.hp = 0
	_feq("bulwark 携带者阵亡 → 光环失效 乘区==1.0",
		tm_script._compute_bulwark_multiplier([normal_ally, bulwark_ally]), 1.0)
	normal_ally.free()
	bulwark_ally.free()


# ── 4. af_siege：诚实占位（无建筑战斗目标系统，不测真实生效）──

func _test_siege_placeholder(dl: Object) -> void:
	print("\n[4] af_siege 攻城（保持占位 · 系统依赖）")
	# 词条仍可正常挂载（声明式骨架不缺失），但战斗中无建筑目标 → 效果不生效，属诚实占位。
	var u: Unit = _make_unit(dl.enemies["goblin_melee"], "enemy")
	u.apply_affixes(["af_siege"], null, 1.0, dl.affixes)
	_check("af_siege 可挂载（声明式骨架完整）", u.has_affix("af_siege"))
	# 对单位（非建筑）攻击不因 af_siege 增伤：damage_calculator 无建筑目标分支 → 输出乘区仍 1.0。
	var dft: Unit = _make_unit(dl.enemies["goblin_melee"], "player")
	dft.stats.def_attr = 0
	dft.stats.lck = 5
	dft.stats.max_hp = 999
	dft.stats.hp = 999
	u.stats.str_attr = 20
	u.stats.dex = 0
	var pv: Dictionary = DamageCalculator.preview_attack(u, dft,
		{"damage_type": "physical", "weapon_might": 0, "guaranteed_hit": true})
	_eq("af_siege 对普通单位无增伤==20（对建筑增伤依赖未实装的建筑战斗目标系统）",
		pv["damage"], 20)
	print("  · 说明：af_siege 保持占位——Cell.building 仅地图数据（无 HP/无战斗接线），")
	print("    resolve_attack 仅接受 defender: Unit，战斗中无「建筑作为可攻击目标」概念。")
	u.free()
	dft.free()


# ── 5. 全局无词条零影响：get_effective_stat / damage_calculator 逐位不变 ──

func _test_global_zero_impact(dl: Object) -> void:
	print("\n[5] 全局无词条零影响对照")
	var g: Unit = _make_unit(dl.enemies["goblin_melee"], "enemy")
	# 无词条单位各属性与引入前一致（含新加的 vanguard SPD 分支不触发）。
	_eq("无词条 SPD==5", g.get_effective_stat("SPD"), 5)
	_eq("无词条 STR==2", g.get_effective_stat("STR"), 2)
	_eq("无词条 DEF==4", g.get_effective_stat("DEF"), 4)
	_feq("无词条 affix_damage_mult==1.0", g.affix_damage_mult, 1.0)
	_eq("无词条 get_affixes()==空", g.get_affixes().size(), 0)
	# damage_calculator 空 action_data（无 affix_defense_multiplier）→ 输出==纯 base。
	var t: Unit = _make_unit(dl.enemies["goblin_melee"], "player")
	t.stats.def_attr = 0
	g.stats.str_attr = 10
	g.stats.dex = 0
	var pv: Dictionary = DamageCalculator.preview_attack(g, t,
		{"damage_type": "physical", "weapon_might": 0, "guaranteed_hit": true})
	_eq("无词条 · 空 action_data 输出==base(10)", pv["damage"], 10)
	var rz: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(g, t,
		{"damage_type": "physical", "weapon_might": 0, "guaranteed_hit": true})
	_eq("无词条 · resolve==preview(10)", rz.damage, pv["damage"])
	g.free()
	t.free()
