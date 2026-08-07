extends SceneTree
## 设计库 State 注册表的引擎映射（路径 C · 2026-08-07）。
##
## 覆盖三件事：
##   1. 装载回读——data/states/*.json 确实被 DataLoader 读进 states 字典（不是「文件写了就算」）。
##   2. 背水的即时判定——含 30% 边界，以及 HP 回升后自动脱离（证明不快照）。
##   3. 双持的「判不了」与「判定为否」可区分——引擎无副手槽，不许静默当成条件不成立。
##
## 另附零影响对照：新增 states 注册表不动 buffs 命名空间、不改既有注册表。
##
## 关于下面的 AUTHORITATIVE 常量——它是设计库权威定义的**手抄副本**，比对它只能
## 抓住「JSON 事后被人改了」这一类漂移，抓不住「当初就抄错」：抄错时两边一起错、
## 测试照样绿。对设计库的真正核对必须回 `/api/states` 或设计库仓
## `snapshots/states.json` 做外部比对，不在本测试的能力范围内。
##
## 运行：
##   <Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##     --script res://tests/test_state_registry.gd
## 退出码 0=全过，1=有失败。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false

# 设计库 /api/states 2026-08-07 权威定义的逐字副本，用于比对镜像字段是否漂移。
const AUTHORITATIVE: Dictionary = {
	"beishui": {
		"name": "背水",
		"kind": "条件",
		"duration_kind": "条件维持",
		"resistable": false,
		"definition": "一种持续状态：HP 不高于 30% 时处于背水状态，HP 高于 30% 时脱离该状态。背水采用即时判定，每次结算都以当前 HP 重新计算，不在进入时做快照。背水本身不提供任何加成，而是作为其他效果的触发条件。",
	},
	"shuangchi": {
		"name": "双持",
		"kind": "条件",
		"duration_kind": "条件维持",
		"resistable": false,
		"definition": "条件类。经〔二天一流〕等效果使副手装备武器时处于双持状态；副手武器卸下或前置失效时立即脱离。即时判定，不快照。本身不提供任何加成，仅作为其他效果的触发与生效条件被引用。不可抵抗。",
	},
}


func _initialize() -> void:
	print("=== test_state_registry (设计库状态注册的引擎映射 · 路径 C) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	var dl: Object = load("res://scripts/data/data_loader.gd").new()
	dl.load_all()

	_test_loading(dl)
	_test_mirror_fidelity(dl)
	_test_beishui_live_evaluation(dl)
	_test_shuangchi_unevaluable(dl)
	_test_robustness(dl)
	_test_threshold_from_json(dl)
	_test_zero_impact(dl)

	dl.free()
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  ✗ " + f)
	quit(0 if _fail == 0 else 1)


# ── 断言工具（照 tests/test_affix_effects.gd）─────────────

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


func _make_unit(class_data: Dictionary, faction: String = "player") -> Unit:
	var u: Unit = load("res://scenes/tactical/Unit.tscn").instantiate()
	u.faction = faction
	root.add_child(u)
	u.setup(class_data)
	return u


## 把单位的 HP 调到指定百分比（max_hp 固定 100，百分比即 HP 值）。
func _set_hp_pct(u: Unit, pct: int) -> void:
	u.stats.max_hp = 100
	u.stats.hp = pct


## 数目录下的 JSON 文件数，用于校验「目录里的都装载了」而不写死条数。
func _count_json_files(path: String) -> int:
	var dir := DirAccess.open(path)
	if dir == null:
		return -1
	var n: int = 0
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if filename.ends_with(".json"):
			n += 1
		filename = dir.get_next()
	return n


# ── 1. 装载回读：文件确实进了 DataLoader，不是「写入即完成」──

func _test_loading(dl: Object) -> void:
	print("\n[1] 装载回读（data/states/*.json → DataLoader.states）")
	_check("DataLoader 有 states 字典", dl.get("states") is Dictionary)
	_eq("states 装载条数 == 2", dl.states.size(), 2)
	_check("beishui 已注册", dl.states.has("beishui"))
	_check("shuangchi 已注册", dl.states.has("shuangchi"))
	# 键必须来自 JSON 的 id 字段（data_loader.gd:54-55），与文件名一致。
	for sid: String in ["beishui", "shuangchi"]:
		var entry: Dictionary = dl.states.get(sid, {})
		_eq("%s 条目内 id 与注册键一致" % sid, str(entry.get("id", "")), sid)


# ── 2. 镜像保真：设计库五字段逐字一致（防双写静默分叉）──

func _test_mirror_fidelity(dl: Object) -> void:
	print("\n[2] 设计库镜像字段保真（lane §2.2 字段归属表）")
	for sid: String in AUTHORITATIVE.keys():
		var entry: Dictionary = dl.states.get(sid, {})
		var truth: Dictionary = AUTHORITATIVE[sid]
		_eq("%s name" % sid, str(entry.get("name", "")), truth["name"])
		_eq("%s kind" % sid, str(entry.get("kind", "")), truth["kind"])
		_eq("%s duration_kind" % sid, str(entry.get("duration_kind", "")), truth["duration_kind"])
		_eq("%s resistable" % sid, bool(entry.get("resistable", true)), truth["resistable"])
		_eq("%s definition 逐字一致" % sid, str(entry.get("definition", "")), truth["definition"])


# ── 3. 背水：即时判定 + 边界 + 不快照 ──

func _test_beishui_live_evaluation(dl: Object) -> void:
	print("\n[3] 背水即时判定（HP<=30% 成立，回升即脱离，不快照）")
	var reg: Object = load("res://scripts/data/state_registry.gd").new(dl.states)
	var u: Unit = _make_unit(dl.enemies["goblin_melee"], "enemy")

	_check("背水是可判定状态", reg.is_evaluable("beishui"))

	_set_hp_pct(u, 100)
	_eq("HP 100% → 不处于背水", reg.is_in_state(u, "beishui"), false)

	_set_hp_pct(u, 31)
	_eq("HP 31% → 不处于背水（高于阈值）", reg.is_in_state(u, "beishui"), false)

	# 边界：definition 说「不高于 30%」，故 30% 本身成立（<=，非 <）。
	_set_hp_pct(u, 30)
	_eq("HP 30% → 处于背水（边界含等号）", reg.is_in_state(u, "beishui"), true)

	_set_hp_pct(u, 29)
	_eq("HP 29% → 处于背水", reg.is_in_state(u, "beishui"), true)

	_set_hp_pct(u, 1)
	_eq("HP 1% → 处于背水", reg.is_in_state(u, "beishui"), true)

	# 关键：回升后必须自动脱离。这一条就是「不能做成 BuffEffect」的原因——
	# buff 实例挂上后不会因 HP 变化自行消失。
	_set_hp_pct(u, 50)
	_eq("HP 回升到 50% → 自动脱离背水（不快照）", reg.is_in_state(u, "beishui"), false)

	# 反复切换，证明每次都是重新求值而非一次性锁定。
	var flips: Array[bool] = []
	for pct: int in [10, 80, 20, 90, 30]:
		_set_hp_pct(u, pct)
		flips.append(reg.is_in_state(u, "beishui"))
	_eq("反复升降 HP 逐次重算 [10,80,20,90,30]",
		flips, [true, false, true, false, true] as Array[bool])

	u.free()


# ── 4. 双持：判不了 ≠ 判定为否 ──

func _test_shuangchi_unevaluable(dl: Object) -> void:
	print("\n[4] 双持：引擎无副手槽 → 标记为判不了，且与「判定为否」可区分")
	var reg: Object = load("res://scripts/data/state_registry.gd").new(dl.states)
	var u: Unit = _make_unit(dl.enemies["goblin_melee"], "enemy")

	_eq("双持不可判定（is_evaluable=false）", reg.is_evaluable("shuangchi"), false)
	_check("双持给出了阻塞原因（get_blocker 非空）", reg.get_blocker("shuangchi") != "")
	_check("阻塞原因点明副手槽缺失", reg.get_blocker("shuangchi").contains("副手"))
	_eq("双持求值恒为不成立", reg.is_in_state(u, "shuangchi"), false)

	# 对照：背水在满血时同样返回 false，但它是「判定为否」而非「判不了」。
	# 消费方靠 is_evaluable 区分这两种 false，本断言锁住这个区别不被抹平。
	_set_hp_pct(u, 100)
	_eq("对照·背水满血也返回 false", reg.is_in_state(u, "beishui"), false)
	_eq("但背水 is_evaluable=true（两种 false 可区分）", reg.is_evaluable("beishui"), true)
	_eq("可判定的状态没有阻塞原因", reg.get_blocker("beishui"), "")

	u.free()


# ── 5. 健壮性：未知 id / 空 unit 不崩、不误报成立 ──

func _test_robustness(dl: Object) -> void:
	print("\n[5] 健壮性（未知 id / null 单位）")
	var reg: Object = load("res://scripts/data/state_registry.gd").new(dl.states)
	var u: Unit = _make_unit(dl.enemies["goblin_melee"], "enemy")
	_set_hp_pct(u, 1)

	_eq("未注册 id 求值为 false", reg.is_in_state(u, "not_a_real_state"), false)
	_eq("未注册 id 不可判定", reg.is_evaluable("not_a_real_state"), false)
	_eq("未注册 id 无阻塞原因", reg.get_blocker("not_a_real_state"), "")
	_eq("未注册 id 取条目为空字典", reg.get_state("not_a_real_state"), {})
	_eq("空串 id 求值为 false", reg.is_in_state(u, ""), false)
	# null 单位：即便条件本身可判定也必须安全返回 false，不能崩。
	_eq("null 单位求值为 false 且不崩", reg.is_in_state(null, "beishui"), false)

	var ids: Array = reg.known_state_ids()
	_eq("known_state_ids 返回 2 条", ids.size(), 2)
	_check("known_state_ids 含 beishui", ids.has("beishui"))
	_check("known_state_ids 含 shuangchi", ids.has("shuangchi"))

	# 空注册表构造：不崩、什么都判不了。
	var empty_reg: Object = load("res://scripts/data/state_registry.gd").new({})
	_eq("空注册表求值为 false", empty_reg.is_in_state(u, "beishui"), false)
	_eq("空注册表 known_state_ids 为 0", empty_reg.known_state_ids().size(), 0)

	u.free()


# ── 6. 阈值必须来自 JSON（项目禁则：不硬编码数值）──

func _test_threshold_from_json(dl: Object) -> void:
	print("\n[6] 阈值来自 JSON 而非代码写死")
	var u: Unit = _make_unit(dl.enemies["goblin_melee"], "enemy")
	var loader: Resource = load("res://scripts/data/state_registry.gd")

	# 造一个阈值 50 的注册表：若代码里写死 30，下面两条必失败。
	var alt_reg: Object = loader.new({
		"beishui": {
			"id": "beishui",
			"engine_status": "evaluable",
			"predicate": { "type": "hp_ratio_at_most", "params": { "hp_ratio_pct": 50 } },
		}
	})
	_set_hp_pct(u, 40)
	_eq("阈值 50 时 HP 40% → 成立（真实值 30 会判否）", alt_reg.is_in_state(u, "beishui"), true)
	_set_hp_pct(u, 60)
	_eq("阈值 50 时 HP 60% → 不成立", alt_reg.is_in_state(u, "beishui"), false)

	# 阈值 10 的反向对照：同一个 HP 在不同阈值下结论相反，证明读的是参数。
	var low_reg: Object = loader.new({
		"beishui": {
			"id": "beishui",
			"engine_status": "evaluable",
			"predicate": { "type": "hp_ratio_at_most", "params": { "hp_ratio_pct": 10 } },
		}
	})
	_set_hp_pct(u, 20)
	_eq("阈值 10 时 HP 20% → 不成立（同 HP 阈值 30 时成立）", low_reg.is_in_state(u, "beishui"), false)
	var real_reg: Object = loader.new(dl.states)
	_eq("对照·真实注册表同 HP 20% → 成立", real_reg.is_in_state(u, "beishui"), true)

	# 缺参数：必须放弃判定并告警，不能静默当成阈值 0（那样状态永不成立且无人察觉）。
	var noparam_reg: Object = loader.new({
		"beishui": {
			"id": "beishui",
			"engine_status": "evaluable",
			"predicate": { "type": "hp_ratio_at_most", "params": {} },
		}
	})
	_set_hp_pct(u, 1)
	_eq("缺 hp_ratio_pct → 放弃判定返回 false", noparam_reg.is_in_state(u, "beishui"), false)

	# get_state 交出的是副本：改它不得污染注册表（防设计库镜像被就地改写）。
	var snapshot: Dictionary = real_reg.get_state("beishui")
	snapshot["name"] = "被篡改"
	_eq("get_state 返回副本，改副本不影响注册表",
		str(real_reg.get_state("beishui").get("name", "")), "背水")
	_eq("原始 DataLoader.states 也未被污染",
		str(dl.states["beishui"].get("name", "")), "背水")

	u.free()


# ── 7. 零影响对照：不动 buffs 命名空间、不改既有注册表 ──

func _test_zero_impact(dl: Object) -> void:
	print("\n[7] 零影响对照（新注册表不污染既有数据层）")
	# states 与 buffs 是两套独立命名空间，id 不得交叉——交叉会让
	# tactical_manager._make_buff_effect_instance 误把状态当 buff 模板取走。
	var overlap: Array[String] = []
	for sid: String in dl.states.keys():
		if dl.buffs.has(sid):
			overlap.append(sid)
	_eq("states 与 buffs 无 id 交集", overlap, [] as Array[String])

	# 既有 buff 注册表未被本次改动影响。不写死条数（加第 11 个 buff 不该让
	# 状态注册表的测试变红），改为断言装载数与目录里的 JSON 文件数一致。
	_eq("buffs 装载数 == data/buffs 目录 JSON 文件数",
		dl.buffs.size(), _count_json_files("res://data/buffs/"))
	_eq("states 装载数 == data/states 目录 JSON 文件数",
		dl.states.size(), _count_json_files("res://data/states/"))
	_check("既有 buff haste 仍在", dl.buffs.has("haste"))
	_check("既有 buff swordsman_parry_stance 仍在", dl.buffs.has("swordsman_parry_stance"))

	# 状态条目不含 BuffEffect 字段——防止将来有人把它当 buff 模板喂进 from_dict。
	for sid: String in dl.states.keys():
		var entry: Dictionary = dl.states[sid]
		_check("%s 不含 effect_type（不是 buff 模板）" % sid, not entry.has("effect_type"))
		_check("%s 不含 duration（条件维持，无时长）" % sid, not entry.has("duration"))
