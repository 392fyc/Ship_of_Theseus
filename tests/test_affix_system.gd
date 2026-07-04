extends SceneTree
## 敌人词条（affix）系统 v0 headless 回归测试。
##
## 覆盖「真理源」代码（unit.gd / damage_calculator.gd）+ 纯逻辑装配器（battle_assembler.gd）：
##   词条挂载、stat_scale(HP+输出)、常驻数值分发(get_effective_stat)、afs_frenzy(低血增伤,
##   preview==resolve)、affix_damage_mult 输出乘区、BattleAssembler.build、回归零影响对照。
## tactical_manager.gd 的时机分发器（on_turn_start/on_hit/on_kill/on_counter + 占位提示）
##   为纯加法门控，不改变无词条单位行为；其运行时接线由集成/手动测试覆盖。
##
## 运行：
##   <Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##     --script res://tests/test_affix_system.gd
## 退出码 0=全过，1=有失败。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_affix_system (敌人词条 v0) ===")


## 自定义 SceneTree 主循环下 @onready 到首帧才触发；故首帧 _process 里跑测试。
func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	var dl: Object = load("res://scripts/data/data_loader.gd").new()
	dl.load_all()
	var ba: GDScript = load("res://scripts/roguelite/battle_assembler.gd")

	_test_mount(dl)
	_test_stat_scale(dl)
	_test_numeric_dispatch(dl)
	_test_frenzy(dl)
	_test_damage_mult(dl)
	_test_assembler(dl, ba)
	_test_regression_zero_impact(dl)
	_test_idempotent(dl)
	_test_heal_resist(dl)

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


func _make_unit(class_data: Dictionary) -> Unit:
	var u: Unit = load("res://scenes/tactical/Unit.tscn").instantiate()
	root.add_child(u)
	u.setup(class_data)
	return u


# ── 8. 幂等守卫：apply_affixes 每单位仅注入一次（防重复累乘/累加）──

func _test_idempotent(dl: Object) -> void:
	print("\n[8] 幂等守卫（apply_affixes 仅注入一次）")
	var u: Unit = _make_unit(dl.enemies["goblin_melee"])
	u.apply_affixes(["af_counter_boost"], null, 1.5, dl.affixes)
	var after_first_hp: int = u.stats.max_hp
	var after_first_count: int = u.get_affixes().size()
	# 重复调用（不同参数）应被幂等守卫忽略
	u.apply_affixes(["af_counter_boost", "af_vanguard"], "afs_bulwark", 2.0, dl.affixes)
	_eq("重复 apply_affixes → max_hp 不再累乘（仍==首次）", u.stats.max_hp, after_first_hp)
	_eq("重复 apply_affixes → _affixes 不重复累加", u.get_affixes().size(), after_first_count)
	_feq("重复 apply_affixes → affix_damage_mult 不变(1.5)", u.affix_damage_mult, 1.5)
	u.free()


# ── 9. af_heal_resist：受治疗折损（存疑B 补真实生效词条护栏）──

func _test_heal_resist(dl: Object) -> void:
	print("\n[9] af_heal_resist 受治疗折损")
	# 无词条对照：正常全额回血
	var plain: Unit = _make_unit(dl.enemies["goblin_melee"])
	plain.stats.hp = plain.stats.max_hp - 40
	plain.heal(40)
	_eq("无词条 → heal(40) 全额回满", plain.stats.hp, plain.stats.max_hp)
	plain.free()
	# 带 af_heal_resist(incoming_heal_pct=-50) → 回血减半
	var u: Unit = _make_unit(dl.enemies["goblin_melee"])
	u.apply_affixes(["af_heal_resist"], null, 1.0, dl.affixes)
	var target_hp: int = u.stats.max_hp - 40
	u.stats.hp = target_hp
	u.heal(40)
	_eq("af_heal_resist → heal(40) 只回 20（-50%）", u.stats.hp, target_hp + 20)
	u.free()


# ── 1. 挂载：apply_affixes 后 has_affix / _affixes / special 并入 ──

func _test_mount(dl: Object) -> void:
	print("\n[1] 词条挂载")
	var u: Unit = _make_unit(dl.enemies["goblin_melee"])
	u.apply_affixes(["af_counter_boost", "af_vanguard", "af_zone_expand"],
		"afs_bulwark", 1.35, dl.affixes)
	_check("has_affix(af_counter_boost)", u.has_affix("af_counter_boost"))
	_check("has_affix(af_vanguard)", u.has_affix("af_vanguard"))
	_check("has_affix(af_zone_expand)", u.has_affix("af_zone_expand"))
	_check("special afs_bulwark 并入 _affixes", u.has_affix("afs_bulwark"))
	_eq("_affixes 数量==4(3基础+1特殊)", u.get_affixes().size(), 4)
	_check("未挂载词条 has_affix==false", not u.has_affix("af_siege"))
	u.free()


# ── 2. stat_scale：HP 缩放 + affix_damage_mult；scale==1.0 无变化 ──

func _test_stat_scale(dl: Object) -> void:
	print("\n[2] stat_scale (HP + 输出增强)")
	var u: Unit = _make_unit(dl.enemies["goblin_melee"])
	var base_hp: int = u.stats.max_hp  # goblin=80
	u.apply_affixes([], null, 1.5, dl.affixes)
	_eq("scale=1.5 → max_hp==roundi(80*1.5)", u.stats.max_hp, roundi(float(base_hp) * 1.5))
	_eq("scale=1.5 → hp==max_hp(满血)", u.stats.hp, u.stats.max_hp)
	_feq("scale=1.5 → affix_damage_mult==1.5", u.affix_damage_mult, 1.5)
	u.free()
	# scale==1.0 → 无变化
	var u2: Unit = _make_unit(dl.enemies["goblin_melee"])
	var base_hp2: int = u2.stats.max_hp
	u2.apply_affixes([], null, 1.0, dl.affixes)
	_eq("scale=1.0 → max_hp 不变", u2.stats.max_hp, base_hp2)
	_feq("scale=1.0 → affix_damage_mult==1.0", u2.affix_damage_mult, 1.0)
	u2.free()


# ── 3. 常驻数值分发：stat_flat / stat_pct 进 get_effective_stat；不带者零影响 ──

func _test_numeric_dispatch(dl: Object) -> void:
	print("\n[3] 常驻数值分发 (get_effective_stat)")
	# 合成常驻属性词条（真实 JSON 无「带 stat_key 的常驻属性词条」）。
	var pool: Dictionary = dl.affixes.duplicate()
	pool["test_str_flat"] = {
		"id": "test_str_flat", "type": "stat_flat",
		"params": {"stat_key": "STR", "value": 5}}
	pool["test_str_pct"] = {
		"id": "test_str_pct", "type": "stat_pct",
		"params": {"stat_key": "STR", "value": 50}}
	var u: Unit = _make_unit(dl.enemies["goblin_melee"])  # base STR=2
	u.apply_affixes(["test_str_flat", "test_str_pct"], null, 1.0, pool)
	# 期望：2(base) + 5(flat) + 2*50/100=1(pct) = 8
	_eq("stat_flat+stat_pct → STR==8", u.get_effective_stat("STR"), 8)
	_eq("未涉及属性 DEF 不变==4", u.get_effective_stat("DEF"), 4)
	u.free()
	# 零影响对照：无词条 goblin STR==base(2)
	var plain: Unit = _make_unit(dl.enemies["goblin_melee"])
	_eq("无词条 goblin STR==2(零影响)", plain.get_effective_stat("STR"), 2)
	plain.free()


# ── 4. afs_frenzy：低血增伤，preview==resolve，满血不加成 ──

func _test_frenzy(dl: Object) -> void:
	print("\n[4] afs_frenzy 低血增伤")
	var atk: Unit = _make_unit(dl.enemies["goblin_melee"])
	atk.stats.str_attr = 20
	atk.stats.dex = 0  # crit_value=0 → 不暴击（确定性）
	atk.apply_affixes([], "afs_frenzy", 1.0, dl.affixes)  # 阈值50%,增伤40%
	var dft: Unit = _make_unit(dl.enemies["goblin_melee"])
	dft.stats.def_attr = 0
	dft.stats.lck = 5
	dft.stats.max_hp = 999
	dft.stats.hp = 999
	var action: Dictionary = {
		"damage_type": "physical", "weapon_might": 0, "guaranteed_hit": true}
	# 满血：frenzy 未触发 → base 20
	atk.stats.max_hp = 80
	atk.stats.hp = 80
	var pv_full: Dictionary = DamageCalculator.preview_attack(atk, dft, action)
	_eq("满血 frenzy 未触发 → 20", pv_full["damage"], 20)
	# 低血(30/80=37.5%<50%)：×1.4 → 28
	atk.stats.hp = 30
	var pv_low: Dictionary = DamageCalculator.preview_attack(atk, dft, action)
	_eq("低血 frenzy 触发 → 28 (20*1.4)", pv_low["damage"], 28)
	# preview == resolve
	var rz: DamageCalculator.AttackResult = DamageCalculator.resolve_attack(atk, dft, action)
	_eq("低血 resolve.damage==preview(28)", rz.damage, pv_low["damage"])
	_check("低血 resolve 未暴击(确定性)", not rz.crit)
	atk.free()
	dft.free()


# ── 5. affix_damage_mult：stat_scale 单位输出 ×scale；普通单位 ×1.0 ──

func _test_damage_mult(dl: Object) -> void:
	print("\n[5] affix_damage_mult 输出乘区")
	var dft: Unit = _make_unit(dl.enemies["goblin_melee"])
	dft.stats.def_attr = 0
	dft.stats.lck = 5
	dft.stats.max_hp = 999
	dft.stats.hp = 999
	var action: Dictionary = {
		"damage_type": "physical", "weapon_might": 0, "guaranteed_hit": true}
	# stat_scale=1.5 单位：base 20 → 30
	var atk: Unit = _make_unit(dl.enemies["goblin_melee"])
	atk.stats.str_attr = 20
	atk.stats.dex = 0
	atk.apply_affixes([], null, 1.5, dl.affixes)
	var pv: Dictionary = DamageCalculator.preview_attack(atk, dft, action)
	_eq("stat_scale 单位输出 ×1.5 → 30", pv["damage"], 30)
	# 普通单位（无词条）：base 20 → 20（与基线一致）
	var plain: Unit = _make_unit(dl.enemies["goblin_melee"])
	plain.stats.str_attr = 20
	plain.stats.dex = 0
	var pv_plain: Dictionary = DamageCalculator.preview_attack(plain, dft, action)
	_eq("无词条单位输出 ×1.0 → 20(基线)", pv_plain["damage"], 20)
	atk.free()
	plain.free()
	dft.free()


# ── 6. BattleAssembler.build：波次词条 + 地图站位 + 容错 ──

func _test_assembler(dl: Object, ba: GDScript) -> void:
	print("\n[6] BattleAssembler.build")
	var pools: Dictionary = {"maps": dl.maps, "waves": dl.waves}
	var roster: Array = [{"class_id": "swordsman", "level": 1}, {"class_id": "soldier"}]
	var result: Dictionary = ba.build("test_arena", "wave_act1_elite_01", roster, pools)
	_eq("map_id 透传", result["map_id"], "test_arena")
	# 敌人清单（含词条）
	var enemies: Array = result["enemy_units"]
	_eq("敌人数==3", enemies.size(), 3)
	var e0: Dictionary = enemies[0]
	_eq("敌0 class_id==goblin_melee", e0["class_id"], "goblin_melee")
	_eq("敌0 tier==elite_chief", e0["tier"], "elite_chief")
	_eq("敌0 pos==(7,3)", e0["pos"], Vector2i(7, 3))
	_feq("敌0 stat_scale==1.35", e0["stat_scale"], 1.35)
	_eq("敌0 special_affix==afs_bulwark", e0["special_affix"], "afs_bulwark")
	_eq("敌0 affixes 长度==3", (e0["affixes"] as Array).size(), 3)
	_check("敌0 affixes 含 af_counter_boost", "af_counter_boost" in (e0["affixes"] as Array))
	# normal 敌人缺省
	var e1: Dictionary = enemies[1]
	_eq("敌1 tier==normal", e1["tier"], "normal")
	_feq("敌1 stat_scale 缺省==1.0", e1["stat_scale"], 1.0)
	_eq("敌1 affixes 缺省==空", (e1["affixes"] as Array).size(), 0)
	_eq("敌1 special_affix 缺省==null", e1["special_affix"], null)
	# 玩家站位来自地图 spawns [[0,2],[0,3],[1,2]]
	var players: Array = result["player_units"]
	_eq("玩家数==2", players.size(), 2)
	_eq("玩家0 class_id==swordsman", players[0]["class_id"], "swordsman")
	_eq("玩家0 pos==(0,2)", players[0]["pos"], Vector2i(0, 2))
	_eq("玩家0 level==1", players[0]["level"], 1)
	_eq("玩家1 class_id==soldier", players[1]["class_id"], "soldier")
	_eq("玩家1 pos==(0,3)", players[1]["pos"], Vector2i(0, 3))
	# 容错：缺波次 → 敌人空清单（不崩，仍返回玩家）
	var empty: Dictionary = ba.build("test_arena", "__nonexistent__", roster, pools)
	_eq("缺波次 → 敌人空清单", (empty["enemy_units"] as Array).size(), 0)
	_eq("缺波次 → 玩家仍解析==2", (empty["player_units"] as Array).size(), 2)
	# 容错：缺地图 → 玩家空清单（不崩，敌人仍解析）
	var nomap: Dictionary = ba.build("__nomap__", "wave_act1_elite_01", roster, pools)
	_eq("缺地图 → 玩家空清单", (nomap["player_units"] as Array).size(), 0)
	_eq("缺地图 → 敌人仍解析==3", (nomap["enemy_units"] as Array).size(), 3)


# ── 7. 回归零影响：无词条 goblin 各属性 / 暴击 / 乘区 与引入前一致 ──

func _test_regression_zero_impact(dl: Object) -> void:
	print("\n[7] 回归零影响 (无词条单位构造对照)")
	var g: Unit = _make_unit(dl.enemies["goblin_melee"])
	_eq("STR==2", g.get_effective_stat("STR"), 2)
	_eq("MAG==2", g.get_effective_stat("MAG"), 2)
	_eq("DEX==3", g.get_effective_stat("DEX"), 3)
	_eq("SPD==5", g.get_effective_stat("SPD"), 5)
	_eq("LCK==1", g.get_effective_stat("LCK"), 1)
	_eq("DEF==4", g.get_effective_stat("DEF"), 4)
	_eq("RES==2", g.get_effective_stat("RES"), 2)
	_eq("HP==80", g.get_effective_stat("HP"), 80)
	# get_crit_value：weapon_crit 0 + DEX(3)/2=1 + crit_bonus 0 = 1
	_eq("get_crit_value(0)==1", g.get_crit_value(0), 1)
	_feq("affix_damage_mult==1.0", g.affix_damage_mult, 1.0)
	_eq("get_affixes()==空", g.get_affixes().size(), 0)
	# damage_calc 对无词条单位乘区==1.0（间接：输出==纯 base）
	var t: Unit = _make_unit(dl.enemies["goblin_melee"])
	t.stats.def_attr = 0
	g.stats.str_attr = 10
	g.stats.dex = 0
	var pv: Dictionary = DamageCalculator.preview_attack(g, t,
		{"damage_type": "physical", "weapon_might": 0, "guaranteed_hit": true})
	_eq("无词条输出==base(10)", pv["damage"], 10)
	g.free()
	t.free()
