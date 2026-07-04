extends SceneTree
## Prep v0 headless 逻辑回归测试 —— 2026-07-04（任务 #8）
##
## 覆盖 RunManager 的 Prep 层：HP 跨关继承（writeback_party_hp）、恢复（磨损模型）、
## 运输队数据交换（convoy ↔ party 装备/遗物）、以及 BattleAssembler 对继承 HP 的透传。
##
## 覆盖：
##   1. 恢复量：hp += roundi(max_hp*pct/100)，clamp max_hp，pct 从 run_config 读；
##      拒绝不恢复；run 内恒定（与 stage 无关）；declinable=false 强制恢复。
##   2. HP 跨关继承：writeback_party_hp 写回存活 hp（战死→0）+ 回填 max_hp；
##      下关 BattleAssembler.build 的 player_units 磨损者带该 hp、满血者不带 hp。
##   3. 运输队交换：装备/遗物 convoy↔party move 后数量守恒；遗物 6 槽上限拦截。
##
## 坑规避（--script 三大坑）：逻辑放 _process 首帧；preload 不用 class_name；
## DataLoader 手动 load_all()。
##
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/test_prep_flow.gd
## 退出码 0=全过，1=有失败。

const ACT_CONFIG_FILE: String = "res://data/runloop/act1_config.json"
const RUN_CONFIG_FILE: String = "res://data/runloop/run_config.json"
const DATA_LOADER_SCRIPT: String = "res://scripts/data/data_loader.gd"

const RunManagerScript: GDScript = preload("res://scripts/roguelite/run_manager.gd")
const BattleAssemblerScript: GDScript = preload("res://scripts/roguelite/battle_assembler.gd")

const RNG_SEED: int = 20260704
# 装配用地图（含 player_spawns）+ 普通波次。
const ASSEMBLE_MAP: String = "forest_01"
const ASSEMBLE_WAVE: String = "wave_act1_normal_01"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _act_config: Dictionary = {}
var _run_config: Dictionary = {}
var _pools: Dictionary = {}
var _roster: Array = []


func _initialize() -> void:
	print("=== test_prep_flow (Prep v0：HP 继承 / 恢复 / 运输队) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	if not _load_env():
		_finish()
		return
	_rng.seed = RNG_SEED

	_test_recovery()
	_test_recover_member()
	_test_hp_inheritance()
	_test_convoy_exchange()

	_finish()


func _load_env() -> bool:
	var act_v: Variant = _load_json(ACT_CONFIG_FILE)
	_check("act1_config.json 可解析为 Dictionary", act_v is Dictionary)
	if not (act_v is Dictionary):
		return false
	_act_config = act_v

	var run_v: Variant = _load_json(RUN_CONFIG_FILE)
	_check("run_config.json 可解析为 Dictionary", run_v is Dictionary)
	if not (run_v is Dictionary):
		return false
	_run_config = run_v
	_check("run_config.recovery 存在", _run_config.get("recovery") is Dictionary)

	var dl: Object = load(DATA_LOADER_SCRIPT).new()
	dl.load_all()
	_pools = {
		"maps": dl.maps,
		"waves": dl.waves,
		"affixes": dl.affixes,
		"relics": dl.relics,
		"equipment": dl.equipment,
		"events": dl.events,
	}
	_check("data_pools.maps 含装配地图 %s" % ASSEMBLE_MAP, (dl.maps as Dictionary).has(ASSEMBLE_MAP))

	# 队伍带 max_hp（模拟已回填真值），便于测恢复/继承。
	_roster = [
		{ "class_id": "swordsman", "level": 1, "max_hp": 30 },
		{ "class_id": "knight", "level": 1, "max_hp": 34 },
		{ "class_id": "archer", "level": 1, "max_hp": 26 },
	]
	return _fail == 0


# ── 测试 1：恢复（磨损模型）─────────────────────────────

func _test_recovery() -> void:
	var rm: Object = _new_manager()
	rm.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), _rng)
	var st: Object = rm.get_state()

	var pct_cfg: float = float((_run_config.get("recovery") as Dictionary).get("percent_max_hp", 0))
	_check("[1] 恢复百分比与 run_config 一致", absf(rm.get_recovery_percent() - pct_cfg) < 0.001,
		"rm=%.1f cfg=%.1f" % [rm.get_recovery_percent(), pct_cfg])

	# 0 号角色磨损：hp=10 < max_hp=30
	st.party[0]["hp"] = 10
	var max_hp0: int = int(st.party[0].get("max_hp", 0))
	var expected_amount: int = roundi(float(max_hp0) * pct_cfg / 100.0)
	_check("[1] 恢复量 == roundi(max_hp*pct/100)",
		rm.get_recovery_amount(st.party[0]) == expected_amount,
		"得 %d 期望 %d" % [rm.get_recovery_amount(st.party[0]), expected_amount])

	# 接受恢复：hp = min(max_hp, hp+amount)
	rm.recover_party([true, true, true])
	var expected_hp: int = mini(max_hp0, 10 + expected_amount)
	_check("[1] 接受恢复：hp = min(max_hp, hp+amount)",
		int(st.party[0].get("hp", 0)) == expected_hp,
		"hp=%d 期望 %d" % [int(st.party[0].get("hp", 0)), expected_hp])

	# 拒绝恢复：不变
	st.party[1]["hp"] = 10
	rm.recover_party([false, false, false])
	_check("[1] 拒绝恢复：hp 不变", int(st.party[1].get("hp", 0)) == 10,
		"hp=%d" % int(st.party[1].get("hp", 0)))

	# clamp：hp 接近满 → 不超过 max_hp
	st.party[2]["hp"] = int(st.party[2].get("max_hp", 0)) - 1
	rm.recover_party([true, true, true])
	_check("[1] 恢复 clamp 到 max_hp 不溢出",
		int(st.party[2].get("hp", 0)) == int(st.party[2].get("max_hp", 0)),
		"hp=%d max=%d" % [int(st.party[2].get("hp", 0)), int(st.party[2].get("max_hp", 0))])

	# run 内恒定：恢复量与 stage 无关
	st.stage = 2
	var a_stage2: int = rm.get_recovery_amount(st.party[0])
	st.stage = 6
	var a_stage6: int = rm.get_recovery_amount(st.party[0])
	_check("[1] 恢复量 run 内恒定（与 stage 无关）", a_stage2 == a_stage6,
		"stage2=%d stage6=%d" % [a_stage2, a_stage6])

	# max_hp 未回填（<=0）→ 恢复量 0（不崩）
	var placeholder_member: Dictionary = { "hp": 0, "max_hp": 0 }
	_check("[1] max_hp<=0 → 恢复量 0（占位安全）",
		rm.get_recovery_amount(placeholder_member) == 0)


# ── 测试 1c：即时恢复 recover_member（点击即恢复模型）──────

func _test_recover_member() -> void:
	var rm: Object = _new_manager()
	rm.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), _rng)
	var st: Object = rm.get_state()
	var pct_cfg: float = float((_run_config.get("recovery") as Dictionary).get("percent_max_hp", 0))

	# 0 号磨损 → recover_member 即时恢复该角色，返回恢复量
	st.party[0]["hp"] = 10
	var max_hp0: int = int(st.party[0].get("max_hp", 0))
	var amount: int = roundi(float(max_hp0) * pct_cfg / 100.0)
	var expected_hp: int = mini(max_hp0, 10 + amount)
	var gained: int = rm.recover_member(0)
	_check("[1c] recover_member(0) 即时恢复 hp=min(max_hp,hp+amount)",
		int(st.party[0].get("hp", 0)) == expected_hp,
		"hp=%d 期望 %d" % [int(st.party[0].get("hp", 0)), expected_hp])
	_check("[1c] recover_member 返回实际恢复量",
		gained == expected_hp - 10, "得 %d 期望 %d" % [gained, expected_hp - 10])

	# 只恢复被点角色：1 号不点 → 不变（拒绝=不点恢复）
	st.party[1]["hp"] = 10
	_check("[1c] 未点角色 hp 不变（拒绝=不点恢复）",
		int(st.party[1].get("hp", 0)) == 10, "hp=%d" % int(st.party[1].get("hp", 0)))

	# 满血 recover_member → 返回 0，不超额（可安全重复调用）
	st.party[2]["hp"] = int(st.party[2].get("max_hp", 0))
	_check("[1c] 满血 recover_member 返回 0", rm.recover_member(2) == 0)
	_check("[1c] 满血后 hp 仍 == max_hp",
		int(st.party[2].get("hp", 0)) == int(st.party[2].get("max_hp", 0)))

	# 越界索引安全返回 0
	_check("[1c] recover_member 越界索引返回 0", rm.recover_member(99) == 0)


# ── 测试 2：HP 跨关继承 ─────────────────────────────────

func _test_hp_inheritance() -> void:
	var rm: Object = _new_manager()
	rm.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), _rng)
	var st: Object = rm.get_state()

	# 初始满血：hp==max_hp
	_check("[2] 初始 party hp==max_hp（满血）",
		int(st.party[0].get("hp", 0)) == int(st.party[0].get("max_hp", 0)))

	# 写回存活 HP：swordsman 磨损 12/30、knight 满血 34/34、archer 缺席（战死）
	var survivors: Array = [
		{ "class_id": "swordsman", "hp": 12, "max_hp": 30 },
		{ "class_id": "knight", "hp": 34, "max_hp": 34 },
	]
	rm.writeback_party_hp(survivors)
	_check("[2] 磨损者写回存活 hp（swordsman=12）", int(st.party[0].get("hp", 0)) == 12,
		"hp=%d" % int(st.party[0].get("hp", 0)))
	_check("[2] 满血者写回 hp==max_hp（knight=34）", int(st.party[1].get("hp", 0)) == 34)
	_check("[2] 战死者（缺席 survivors）hp=0（archer）", int(st.party[2].get("hp", 0)) == 0,
		"hp=%d" % int(st.party[2].get("hp", 0)))
	_check("[2] 写回回填 max_hp（swordsman=30）", int(st.party[0].get("max_hp", 0)) == 30)

	# 下关 BattleAssembler：磨损者带 hp、满血者不带 hp、战死者带 hp=0
	var assembled: Dictionary = BattleAssemblerScript.build(
		ASSEMBLE_MAP, ASSEMBLE_WAVE, st.party, _pools)
	var player_units: Array = assembled.get("player_units", [])
	_check("[2] 装配 player_units 非空", not player_units.is_empty(),
		"size=%d" % player_units.size())

	var sw_entry: Dictionary = _find_player(player_units, "swordsman")
	var kn_entry: Dictionary = _find_player(player_units, "knight")
	var ar_entry: Dictionary = _find_player(player_units, "archer")

	_check("[2] 磨损者 player_unit 带 hp 字段", sw_entry.has("hp"))
	if sw_entry.has("hp"):
		_check("[2] 磨损者 player_unit.hp == 写回 hp（12）", int(sw_entry.get("hp", -1)) == 12,
			"hp=%d" % int(sw_entry.get("hp", -1)))
	_check("[2] 满血者 player_unit 不带 hp 字段（缺省满血 spawn）", not kn_entry.has("hp"))
	_check("[2] 战死者 player_unit 带 hp=0（注入层转 hp=1 入场）",
		ar_entry.has("hp") and int(ar_entry.get("hp", -1)) == 0,
		"has=%s hp=%d" % [str(ar_entry.has("hp")), int(ar_entry.get("hp", -1))])

	# 恢复后再装配：磨损者 hp 提升后仍带 hp（继续磨损但更高）
	rm.recover_party([true, true, true])
	var assembled2: Dictionary = BattleAssemblerScript.build(
		ASSEMBLE_MAP, ASSEMBLE_WAVE, st.party, _pools)
	var sw_entry2: Dictionary = _find_player(assembled2.get("player_units", []), "swordsman")
	_check("[2] 恢复后磨损者 hp 提升（12 → >12 且 <=max）",
		sw_entry2.has("hp") and int(sw_entry2.get("hp", 0)) > 12,
		"hp=%d" % int(sw_entry2.get("hp", -1)))


# ── 测试 3：运输队交换（数量守恒 + 槽上限）──────────────

func _test_convoy_exchange() -> void:
	var rm: Object = _new_manager()
	rm.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), _rng)
	var st: Object = rm.get_state()

	# 预置运输队库存
	st.convoy["equipment"] = ["eq_a", "eq_b"]
	st.convoy["relics"] = ["rl_a", "rl_b"]

	# ── 装备守恒 ──
	var total_eq_before: int = _total_equipment(st)
	_check("[3] 前置：装备总数 == 2", total_eq_before == 2, "total=%d" % total_eq_before)

	# 装到空槽：convoy -1、equipped +1，总数守恒
	_check("[3] equip_from_convoy(空槽) 成功", rm.equip_from_convoy(0, 0, "weapon"))
	_check("[3] 装空槽后 party[0].weapon 落地",
		str((st.party[0].get("equipment") as Dictionary).get("weapon", "")) != "")
	_check("[3] 装空槽后装备总数守恒", _total_equipment(st) == total_eq_before,
		"total=%d" % _total_equipment(st))

	# 装到占位槽：旧件退回 convoy，总数守恒
	var eq_count_now: int = (st.convoy.get("equipment", []) as Array).size()
	_check("[3] 前置：convoy 尚有装备可再装", eq_count_now >= 1, "convoy_eq=%d" % eq_count_now)
	_check("[3] equip_from_convoy(占位槽) 成功", rm.equip_from_convoy(0, 0, "weapon"))
	_check("[3] 占位槽换装后装备总数仍守恒", _total_equipment(st) == total_eq_before,
		"total=%d" % _total_equipment(st))

	# 卸下：equipped -1、convoy +1，总数守恒
	_check("[3] unequip_to_convoy 成功", rm.unequip_to_convoy(0, "weapon"))
	_check("[3] 卸下后 party[0].weapon 为空",
		str((st.party[0].get("equipment") as Dictionary).get("weapon", "")) == "")
	_check("[3] 卸下后装备总数守恒", _total_equipment(st) == total_eq_before,
		"total=%d" % _total_equipment(st))
	_check("[3] 卸空槽再卸返回 false（无副作用）", not rm.unequip_to_convoy(0, "weapon"))

	# ── 遗物守恒 ──
	var total_rl_before: int = _total_relics(st)
	_check("[3] 前置：遗物总数 == 2", total_rl_before == 2, "total=%d" % total_rl_before)
	_check("[3] move_relic_to_member 成功", rm.move_relic_to_member(0, 0))
	_check("[3] 给遗物后 party[0].relics 非空",
		(st.party[0].get("relics") as Array).size() >= 1)
	_check("[3] 给遗物后遗物总数守恒", _total_relics(st) == total_rl_before,
		"total=%d" % _total_relics(st))
	_check("[3] move_relic_to_convoy 成功", rm.move_relic_to_convoy(0, 0))
	_check("[3] 收回后遗物总数守恒", _total_relics(st) == total_rl_before,
		"total=%d" % _total_relics(st))

	# ── 遗物 6 槽上限拦截 ──
	st.party[0]["relics"] = ["r1", "r2", "r3", "r4", "r5", "r6"]
	st.convoy["relics"] = ["rl_x"]
	var convoy_rl_before: int = (st.convoy.get("relics", []) as Array).size()
	_check("[3] 满槽角色 move_relic_to_member 返回 false", not rm.move_relic_to_member(0, 0))
	_check("[3] 满槽角色遗物仍为 6（不超上限）",
		(st.party[0].get("relics") as Array).size() == 6)
	_check("[3] 满槽拦截后 convoy 遗物数不变",
		(st.convoy.get("relics", []) as Array).size() == convoy_rl_before)


# ── 工具 ─────────────────────────────────────────────

func _new_manager() -> Object:
	return RunManagerScript.new()


## 装备总数守恒度量 = convoy.equipment 数 + 全角色已装备槽数。
func _total_equipment(st: Object) -> int:
	var total: int = (st.convoy.get("equipment", []) as Array).size()
	for member: Dictionary in st.party:
		var equip: Dictionary = member.get("equipment", {})
		if str(equip.get("weapon", "")) != "":
			total += 1
		if str(equip.get("armor", "")) != "":
			total += 1
	return total


## 遗物总数守恒度量 = convoy.relics 数 + 全角色遗物数。
func _total_relics(st: Object) -> int:
	var total: int = (st.convoy.get("relics", []) as Array).size()
	for member: Dictionary in st.party:
		total += (member.get("relics", []) as Array).size()
	return total


## 在 player_units 中按 class_id 找条目，找不到返回 {}。
func _find_player(player_units: Array, class_id: String) -> Dictionary:
	for pu_v: Variant in player_units:
		if pu_v is Dictionary and str((pu_v as Dictionary).get("class_id", "")) == class_id:
			return pu_v
	return {}


func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	return JSON.parse_string(text)


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  OK  " + name)
	else:
		_fail += 1
		_fails.append(name + ("  [" + detail + "]" if detail != "" else ""))
		print("  XX  " + name + ("  [" + detail + "]" if detail != "" else ""))


func _finish() -> void:
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  XX " + f)
	else:
		print("OK：全部断言通过")
	quit(0 if _fail == 0 else 1)
