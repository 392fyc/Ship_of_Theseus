extends SceneTree
## 天赋载体 + after-damage 族三事件分发（Wave 1 · A1）。
##
## 三块：
##   A. 装载回读 —— data/talents/*.json 确实进了 DataLoader.talents 并注册成功。
##   B. 注册纪律（响亮失败）—— 八类不可执行的卡逐一拒收，且拒收信号可观测
##      （rejected_ids / rejection_reason 非空）。核心是 Wave 1 §2.3 的硬判据：
##      依赖 unevaluable 状态的天赋必须拒绝注册，不许当「条件不成立」静默消费。
##   C. 三事件真实分发 —— 实例化 TacticalScene 驱动真实攻击，断言三个事件各自
##      在正确时点触发，尤其是「命中后」与「造成伤害时」的分野（伤害为 0 时前者
##      触发、后者不触发）。
##
## 另附零影响对照：talent_ids 为空 / 装了未注册的 id 时，一律不触发。
##
## 运行：
##   <Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##     --script res://tests/test_talent_carrier.gd
## 退出码 0=全过，1=有失败。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false

const TALENT_REGISTRY_PATH := "res://scripts/data/talent_registry.gd"
const STATE_REGISTRY_PATH := "res://scripts/data/state_registry.gd"
const DATA_LOADER_PATH := "res://scripts/data/data_loader.gd"

## 合成天赋夹具。前两条是可注册的（补生产数据缺的两个事件——全库当前只有
## 「击杀时」有真卡，「造成伤害时」0 张、「命中后」2 处全是被排除的双持系）；
## 其余八条各自触碰一条拒收规则。
const SYNTHETIC: Dictionary = {
	"test_ok_hit_after": {
		"id": "test_ok_hit_after", "name": "测试·命中后", "class_id": "kensei",
		"trigger_event": "命中后", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 3}],
	},
	"test_ok_on_damage": {
		"id": "test_ok_on_damage", "name": "测试·造成伤害时", "class_id": "kensei",
		"trigger_event": "造成伤害时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 5}],
	},
	"test_rej_unevaluable": {
		"id": "test_rej_unevaluable", "name": "测试·依赖判不了的状态", "class_id": "kensei",
		"trigger_event": "命中后", "trigger_condition": "处于〔双持〕状态",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "states", "requires_states": ["shuangchi"],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 99}],
	},
	"test_rej_unknown_state": {
		"id": "test_rej_unknown_state", "name": "测试·依赖未注册状态", "class_id": "kensei",
		"trigger_event": "命中后", "trigger_condition": "处于〔子虚〕状态",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "states", "requires_states": ["wu_you_ci_state"],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 99}],
	},
	"test_rej_unsupported": {
		"id": "test_rej_unsupported", "name": "测试·条件表达不了", "class_id": "kensei",
		"trigger_event": "击杀时", "trigger_condition": "当目标为头目且本回合未移动",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "unsupported", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 99}],
	},
	"test_rej_a2_event": {
		"id": "test_rej_a2_event", "name": "测试·A2 事件", "class_id": "kensei",
		"trigger_event": "暴击时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 99}],
	},
	"test_rej_frequency": {
		"id": "test_rej_frequency", "name": "测试·频率未实装", "class_id": "kensei",
		"trigger_event": "击杀时", "trigger_condition": "",
		"trigger_frequency": "每回合", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 99}],
	},
	"test_rej_unknown_effect": {
		"id": "test_rej_unknown_effect", "name": "测试·未知效果类型", "class_id": "kensei",
		"trigger_event": "击杀时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "teleport_to_moon", "amount": 1}],
	},
	"test_rej_condition_mismatch": {
		"id": "test_rej_condition_mismatch", "name": "测试·声明与镜像矛盾", "class_id": "kensei",
		"trigger_event": "击杀时", "trigger_condition": "处于〔背水〕状态",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [{"type": "gain_resource", "resource": "qi", "amount": 99}],
	},
	"test_rej_no_effects": {
		"id": "test_rej_no_effects", "name": "测试·无可执行效果", "class_id": "kensei",
		"trigger_event": "击杀时", "trigger_condition": "",
		"trigger_frequency": "每次", "trigger_frequency_n": 1,
		"condition_model": "none", "requires_states": [],
		"engine_effects": [],
	},
}


func _initialize() -> void:
	print("=== test_talent_carrier (天赋载体 + after-damage 三事件 · A1) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	var dl: Object = load(DATA_LOADER_PATH).new()
	dl.load_all()

	_test_loading(dl)
	_test_rejection_discipline(dl)
	_test_event_index(dl)
	_test_dispatch_integration()

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


func _make_registry(talents: Dictionary, states: Dictionary) -> Object:
	var state_reg: Object = load(STATE_REGISTRY_PATH).new(states)
	return load(TALENT_REGISTRY_PATH).new(talents, state_reg)


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


# ── A. 装载回读 ──────────────────────────────────────

func _test_loading(dl: Object) -> void:
	print("\n[A] 装载回读（data/talents/*.json → DataLoader.talents → 注册）")
	_check("DataLoader 有 talents 字典", dl.get("talents") is Dictionary)
	_eq("talents 装载数 == data/talents 目录 JSON 文件数",
		dl.talents.size(), _count_json_files("res://data/talents/"))
	_check("介错已装载", dl.talents.has("myrmidon_jiecuo"))
	var entry: Dictionary = dl.talents.get("myrmidon_jiecuo", {})
	_eq("条目内 id 与注册键一致", str(entry.get("id", "")), "myrmidon_jiecuo")
	# 设计库镜像字段（对照 /api/talents 与 snapshots/talents.json @ 319993a）。
	_eq("介错 trigger_event", str(entry.get("trigger_event", "")), "击杀时")
	_eq("介错 trigger_condition 为空", str(entry.get("trigger_condition", "")), "")
	_eq("介错 effect", str(entry.get("effect", "")), "获得 20 点剑气。")
	_eq("介错 class_id", str(entry.get("class_id", "")), "myrmidon")

	var reg: Object = _make_registry(dl.talents, dl.states)
	_check("介错注册成功", reg.is_registered("myrmidon_jiecuo"))
	_eq("生产数据无一被拒", reg.rejected_ids(), [] as Array[String])
	_eq("介错未被拒（拒绝理由为空）", reg.rejection_reason("myrmidon_jiecuo"), "")


# ── B. 注册纪律：八类不可执行的卡逐一响亮拒收 ──────────

func _test_rejection_discipline(dl: Object) -> void:
	print("\n[B] 注册纪律（宁可不注册，不可错误触发）")
	var mixed: Dictionary = dl.talents.duplicate(true)
	for key: String in SYNTHETIC.keys():
		mixed[key] = (SYNTHETIC[key] as Dictionary).duplicate(true)
	var reg: Object = _make_registry(mixed, dl.states)

	# ★ 硬判据（Wave 1 §2.3）：依赖 unevaluable 状态 → 拒绝注册 + 可观测理由。
	_check("依赖判不了的状态 → 拒绝注册", not reg.is_registered("test_rej_unevaluable"))
	var reason: String = reg.rejection_reason("test_rej_unevaluable")
	_check("拒绝理由非空（可观测的失败信号）", reason != "")
	_check("拒绝理由点明状态判不了", reason.contains("判不了"))
	_check("拒绝理由带上了状态的阻塞原因（副手）", reason.contains("副手"))
	_check("被拒 id 进了 rejected_ids 清单", "test_rej_unevaluable" in reg.rejected_ids())

	# 其余七类
	var cases: Dictionary = {
		"test_rej_unknown_state": "未在 data/states/ 注册",
		"test_rej_unsupported": "unsupported",
		"test_rej_a2_event": "A2",
		"test_rej_frequency": "频率",
		"test_rej_unknown_effect": "未知 type",
		"test_rej_condition_mismatch": "矛盾",
		"test_rej_no_effects": "engine_effects 为空",
	}
	for tid: String in cases.keys():
		_check("%s → 拒绝注册" % tid, not reg.is_registered(tid))
		_check("%s 拒绝理由含「%s」" % [tid, cases[tid]],
			reg.rejection_reason(tid).contains(str(cases[tid])),
			reg.rejection_reason(tid))

	# 合法的合成卡必须仍然注册成功——证明拒收不是「一刀切全拒」。
	_check("合法合成卡 test_ok_hit_after 注册成功", reg.is_registered("test_ok_hit_after"))
	_check("合法合成卡 test_ok_on_damage 注册成功", reg.is_registered("test_ok_on_damage"))
	_check("生产卡 介错 仍注册成功", reg.is_registered("myrmidon_jiecuo"))
	_eq("被拒总数 == 8", reg.rejected_ids().size(), 8)
	_eq("注册成功总数 == 3（介错 + 两张合法合成）", reg.registered_ids().size(), 3)

	# 无 StateRegistry 时，依赖状态的卡不能放行（不能因为核验不了就默认通过）。
	var no_state_reg: Object = load(TALENT_REGISTRY_PATH).new(mixed, null)
	_check("无 StateRegistry → 依赖状态的卡仍被拒",
		not no_state_reg.is_registered("test_rej_unevaluable"))


# ── C1. 事件索引 ─────────────────────────────────────

func _test_event_index(dl: Object) -> void:
	print("\n[C1] 按事件索引")
	var mixed: Dictionary = dl.talents.duplicate(true)
	for key: String in SYNTHETIC.keys():
		mixed[key] = (SYNTHETIC[key] as Dictionary).duplicate(true)
	var reg: Object = _make_registry(mixed, dl.states)

	_eq("「击杀时」下 1 张（介错）", reg.talents_for_event("击杀时").size(), 1)
	_eq("「命中后」下 1 张（合成）", reg.talents_for_event("命中后").size(), 1)
	_eq("「造成伤害时」下 1 张（合成）", reg.talents_for_event("造成伤害时").size(), 1)
	# A2 事件即使有数据也索引不到——它在注册期就被拒了。
	_eq("「暴击时」下 0 张（A2 不接）", reg.talents_for_event("暴击时").size(), 0)
	_eq("「命中时」下 0 张（A2 不接）", reg.talents_for_event("命中时").size(), 0)
	_eq("未知事件下 0 张", reg.talents_for_event("子虚乌有时").size(), 0)


# ── C2. 三事件真实分发（驱动 TacticalScene 的真实攻击流程）──

func _test_dispatch_integration() -> void:
	print("\n[C2] 三事件真实分发（真实战斗流程，非模拟）")
	# 往 autoload DataLoader 注入合成天赋——tactical_manager 的懒构造读的是它。
	# 必须用 get_node 动态取：`DataLoader` 这个标识符在 --script 主循环下编译期
	# 解析不到（"Identifier not found: DataLoader"），但节点本身确实挂在 /root。
	var autoload_dl: Node = root.get_node_or_null("/root/DataLoader")
	if autoload_dl == null:
		_check("autoload DataLoader 可达", false, "/root/DataLoader 不存在")
		return
	_check("autoload DataLoader 可达", true)
	for key: String in SYNTHETIC.keys():
		autoload_dl.talents[key] = (SYNTHETIC[key] as Dictionary).duplicate(true)

	var scene: Node = load("res://scenes/tactical/TacticalScene.tscn").instantiate()
	root.add_child(scene)
	var tm: Object = scene.tactical_manager
	tm._talent_registry = null          # 强制按注入后的数据重建
	tm.debug_harness_active = true      # 强制命中，去掉命中随机性
	tm.debug_deterministic = true
	tm.debug_crit_mode = 2              # DISABLE：禁暴击，避免伤害浮动干扰断言

	var attacker: Unit = null
	var enemy: Unit = null
	for u: Unit in tm.units:
		if u.faction == "player" and u.unit_id == "kensei":
			attacker = u
		elif u.faction == "enemy" and enemy == null:
			enemy = u
	if attacker == null or enemy == null:
		_check("场景中找到剑圣与敌人", false, "attacker/enemy 缺失")
		scene.free()
		return
	_check("场景中找到剑圣与敌人", true)

	# ── 零影响对照：talent_ids 为空 → 一个都不触发 ──
	attacker.talent_ids = []
	enemy.stats.max_hp = 999
	enemy.stats.hp = 999
	enemy.stats.def_attr = 0
	attacker.set_sword_qi(0)
	tm._execute_hostile_action(attacker, enemy, {})
	# 剑圣普攻本身产 10 气（既有机制），天赋若触发会额外加 3+5。
	_eq("talent_ids 为空 → 只有普攻的 10 气，天赋零触发", attacker.sword_qi, 10)

	# ── 装了未注册的 id → 不触发 ──
	attacker.talent_ids = ["test_rej_unevaluable", "test_rej_unsupported", "不存在的id"]
	enemy.stats.hp = 999
	attacker.set_sword_qi(0)
	tm._execute_hostile_action(attacker, enemy, {})
	_eq("装了被拒/不存在的 id → 仍只有普攻 10 气", attacker.sword_qi, 10)

	# ── 命中且造成伤害且不死 → 命中后(+3) 与 造成伤害时(+5) 都触发 ──
	attacker.talent_ids = ["test_ok_hit_after", "test_ok_on_damage", "myrmidon_jiecuo"]
	enemy.stats.max_hp = 999
	enemy.stats.hp = 999
	enemy.stats.def_attr = 0
	attacker.set_sword_qi(0)
	tm._execute_hostile_action(attacker, enemy, {})
	_eq("命中+有伤害+不死 → 10(普攻) + 3(命中后) + 5(造成伤害时) == 18",
		attacker.sword_qi, 18)

	# ── 命中但伤害为 0 → 只有「命中后」触发，「造成伤害时」不触发 ──
	# 这是两个事件的分野：设计库定义「命中后」实际伤害为 0 也触发。
	enemy.stats.hp = 999
	enemy.stats.def_attr = 9999   # 防御拉满 → damage = maxi(0, ...) == 0
	attacker.set_sword_qi(0)
	tm._execute_hostile_action(attacker, enemy, {})
	_eq("命中但伤害为 0 → 10(普攻) + 3(命中后) == 13，造成伤害时不触发",
		attacker.sword_qi, 13)

	# ── 击杀 → 介错(+20) 触发，且命中后/造成伤害时同时成立 ──
	enemy.stats.def_attr = 0
	enemy.stats.max_hp = 1
	enemy.stats.hp = 1
	attacker.set_sword_qi(0)
	tm._execute_hostile_action(attacker, enemy, {})
	_check("击杀成功（敌人已死）", not enemy.stats.is_alive())
	# 10(普攻) + 3(命中后) + 5(造成伤害时) + 20(介错·击杀时) = 38
	_eq("击杀 → 三事件全触发，含介错 +20 → 38", attacker.sword_qi, 38)

	# ── 未命中 → 三事件一个都不触发 ──
	tm.debug_deterministic = false     # 关掉强制命中
	enemy.stats.max_hp = 999
	enemy.stats.hp = 999
	enemy.stats.spd = 9999             # 回避拉满 → 必不命中
	enemy.stats.lck = 9999
	attacker.set_sword_qi(0)
	tm._execute_hostile_action(attacker, enemy, {})
	_eq("未命中 → 剑气纹丝不动（三事件全不触发，普攻也不产气）",
		attacker.sword_qi, 0)

	scene.free()
