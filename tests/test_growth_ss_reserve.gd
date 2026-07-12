extends SceneTree
## growth_rates 新标定 + SS 档预留 —— 2026-07-07 建 / 2026-07-12 语义定稿（用户裁决 [已定]）
##
## 覆盖：
##   1. swordsman.json growth_rates 新标定（DEX75 / HP50 / STR50 / DEF50 / MAG40 / RES40；LCK 已移除）。
##   2. SS 档预留（unit_stats.load_growth_rates 的 ss_stats 参数 + level_up SS 分支）：
##      SS 档属性每级**仅判定一次** S 率，成功 +2、失败保底 +1（最少 +1、至多 +2；
##      S=75% 期望 +1.75），每级必有成长、pity 恒重置；剑圣无 SS 属性（纯预留、恒不触发）。
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
	print("=== test_growth_ss_reserve (growth 标定 + SS 档预留) ===")


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
	# rate=100 + SS：单判定必成功 → 每级 +2（至多 +2）
	var s100: Object = load(UNIT_STATS).new()
	s100.load_growth_rates({"DEX": 100}, ["DEX"])
	var dex100: int = s100.dex
	var gains_first: Dictionary = s100.level_up()
	_eq("SS + rate=100 → 单级 gains 为 +2", int(gains_first.get("DEX", 0)), 2)
	for _i in 19:
		s100.level_up()
	_eq("SS + rate=100 → 每级 +2（20 级 +40）", s100.dex, dex100 + 40)


# ── 4. SS 分支生效（固定 seed 统计：保底每级必成长 + 成功级 +2）──
func _test_ss_dual_roll_effect() -> void:
	var trials: int = 3000
	# SS 语义（2026-07-12 [已定]）：单判定，成功 +2 / 失败保底 +1 →
	# 成长事件率 100%（每级必成长）；成长量期望 @rate40% = 2×0.4+1×0.6 = 1.4/级。
	# 非 SS 对照：单判定 40%（另受 pity 拉高）。
	var rate: int = 40

	seed(20260707)
	var ss: Object = load(UNIT_STATS).new()
	ss.load_growth_rates({"DEX": rate}, ["DEX"])  # DEX 为 SS 档
	var ss_grows: int = 0
	var ss_total: int = 0
	for _i in trials:
		var g: Dictionary = ss.level_up() as Dictionary
		if g.has("DEX"):
			ss_grows += 1
			ss_total += int(g["DEX"])

	seed(20260707)  # 同 seed 起点
	var nm: Object = load(UNIT_STATS).new()
	nm.load_growth_rates({"DEX": rate})  # 非 SS 对照
	var nm_grows: int = 0
	for _i in trials:
		if (nm.level_up() as Dictionary).has("DEX"):
			nm_grows += 1

	_eq("SS 保底：每级必成长（事件数 == %d）" % trials, ss_grows, trials)
	_check("SS 成长事件率高于非 SS（%d vs %d / %d 级 @rate %d%%）"
		% [ss_grows, nm_grows, trials, rate], ss_grows > nm_grows,
		"ss=%d nm=%d" % [ss_grows, nm_grows])
	# +2 级存在：rate 40% 下成功级 ≈ 1200/3000，总成长量应明显大于事件数。
	_check("SS 存在单级 +2（总成长量 - 事件数 > 300）", ss_total - ss_grows > 300,
		"total=%d events=%d" % [ss_total, ss_grows])
	# 成长量上下界：全失败=3000、全成功=6000，实际应落在开区间内（保底与+2并存）。
	_check("SS 总成长量在 (3000, 6000) 开区间（保底+1 与成功+2 并存）",
		ss_total > trials and ss_total < trials * 2,
		"total=%d" % ss_total)


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
