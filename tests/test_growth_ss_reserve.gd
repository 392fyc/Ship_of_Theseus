extends SceneTree
## growth_rates 新标定 + SS 档双判定预留 —— 2026-07-07（引擎侧两条任务）
##
## 覆盖：
##   1. swordsman.json growth_rates 新标定（DEX75 / HP50 / STR50 / DEF50 / MAG40 / RES40；LCK 已移除）。
##   2. SS 档双判定预留（unit_stats.load_growth_rates 的 ss_stats 参数 + level_up 双判定分支）：
##      SS 档属性每级做两次 S 率判定、任一成功即成长并重置 pity；剑圣无 SS 属性（纯预留、恒不触发）。
##
## 坑规避：用 load().new() + 动态属性访问，避免 --script 下引用全局 class_name UnitStats 的缓存问题。
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/test_growth_ss_reserve.gd  （退出码 0=全过）

const SWORDSMAN_JSON: String = "res://data/classes/swordsman.json"
const UNIT_STATS: String = "res://scripts/units/unit_stats.gd"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_growth_ss_reserve (growth 标定 + SS 双判定预留) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	_test_growth_rates_calibration()
	_test_swordsman_no_ss()
	_test_ss_boundary()
	_test_ss_dual_roll_effect()
	_finish()


# ── 1. growth_rates 新标定（任务1）─────────────────────
func _test_growth_rates_calibration() -> void:
	var cfg: Variant = _load_json(SWORDSMAN_JSON)
	_check("swordsman.json 可解析为 Dictionary", cfg is Dictionary)
	if not (cfg is Dictionary):
		return
	var gr: Dictionary = (cfg as Dictionary).get("growth_rates", {})
	_eq("growth DEX==75", int(gr.get("DEX", -1)), 75)
	_eq("growth HP==50", int(gr.get("HP", -1)), 50)
	_eq("growth STR==50", int(gr.get("STR", -1)), 50)
	_eq("growth DEF==50", int(gr.get("DEF", -1)), 50)
	_eq("growth MAG==40", int(gr.get("MAG", -1)), 40)
	_eq("growth RES==40", int(gr.get("RES", -1)), 40)
	_check("growth 无 LCK（LCK 移除已完成）", not gr.has("LCK"))


# ── 2. 剑圣无 SS 属性（纯预留、不触发）──────────────────
func _test_swordsman_no_ss() -> void:
	var cfg: Variant = _load_json(SWORDSMAN_JSON)
	if not (cfg is Dictionary):
		return
	_check("swordsman.json 不含 ss_growth_stats（剑圣无 SS 属性）",
		not (cfg as Dictionary).has("ss_growth_stats"))
	# 空 ss_stats 时 level_up 行为与无参调用一致（单判定，现状不变）：
	var s: Object = load(UNIT_STATS).new()
	s.load_growth_rates({"DEX": 100})  # 不传 ss_stats → 默认空
	var dex0: int = s.dex
	for _i in 10:
		s.level_up()
	_eq("空 SS + rate100 → 单判定每级必成长（+10）", s.dex, dex0 + 10)


# ── 3. SS 边界（确定性）────────────────────────────────
func _test_ss_boundary() -> void:
	# rate=0 + SS：恒不成长（rate>0 才进判定，SS 也不例外）
	var s0: Object = load(UNIT_STATS).new()
	s0.load_growth_rates({"DEX": 0}, ["DEX"])
	var dex0: int = s0.dex
	for _i in 50:
		s0.level_up()
	_eq("SS + rate=0 → DEX 不成长（50 级）", s0.dex, dex0)
	# rate=100 + SS：每级必成长（首次判定即中，第二次不影响）
	var s100: Object = load(UNIT_STATS).new()
	s100.load_growth_rates({"DEX": 100}, ["DEX"])
	var dex100: int = s100.dex
	for _i in 20:
		s100.level_up()
	_eq("SS + rate=100 → DEX 每级必成长（+20）", s100.dex, dex100 + 20)


# ── 4. SS 双判定生效（固定 seed 统计：SS 成长率 > 非 SS）──
func _test_ss_dual_roll_effect() -> void:
	var trials: int = 3000
	var rate: int = 40   # 单判定 40% vs SS 双判定 1-(0.6)^2=64%（另受 pity 拉高，两者同受）

	seed(20260707)
	var ss: Object = load(UNIT_STATS).new()
	ss.load_growth_rates({"DEX": rate}, ["DEX"])  # DEX 为 SS 档
	var ss_grows: int = 0
	for _i in trials:
		if (ss.level_up() as Dictionary).has("DEX"):
			ss_grows += 1

	seed(20260707)  # 同 seed 起点
	var nm: Object = load(UNIT_STATS).new()
	nm.load_growth_rates({"DEX": rate})  # 非 SS 对照
	var nm_grows: int = 0
	for _i in trials:
		if (nm.level_up() as Dictionary).has("DEX"):
			nm_grows += 1

	_check("SS 双判定成长次数 > 非 SS（%d vs %d / %d 级 @rate %d%%）"
		% [ss_grows, nm_grows, trials, rate], ss_grows > nm_grows,
		"ss=%d nm=%d" % [ss_grows, nm_grows])
	# 双判定 64% vs 40% ≈ 差 720/3000；留宽松下限 300 防统计抖动 flaky。
	_check("SS 成长率明显高于非 SS（差 > 300）", ss_grows - nm_grows > 300,
		"差=%d（ss=%d nm=%d）" % [ss_grows - nm_grows, ss_grows, nm_grows])


# ── 工具 ───────────────────────────────────────────────
func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	return JSON.parse_string(text)


func _eq(name: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_pass += 1
		print("  OK  " + name)
	else:
		_fail += 1
		var msg: String = "%s [期望 %s 实际 %s]" % [name, str(expected), str(actual)]
		_fails.append(msg)
		print("  XX  " + msg)


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  OK  " + name)
	else:
		_fail += 1
		var msg: String = name + ("  [" + detail + "]" if detail != "" else "")
		_fails.append(msg)
		print("  XX  " + msg)


func _finish() -> void:
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  XX " + f)
	quit(0 if _fail == 0 else 1)
