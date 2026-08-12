extends SceneTree
## `target_mode` 导引擎：选择模型不再从 area 形状反推（2026-08-12）。
##
## ## 这次改的是什么
##
## 旧实现拿**伤害波及的形状**去猜**选择模型**：
## `_is_ground_target_skill` = `range.type != "self" and area.type != "single"`。
## 设计库 2026-08-06 立 `target_mode` 时就把这个反推判定失效了（`TargetMode` 的
## docstring 点名「**拔刀被判为选地面**」），但引擎侧一直零承载，于是拔刀在游戏里
## 一直能点空地释放，与设计库 `target_mode=单位` 矛盾。
##
## ## 这个文件的重点是那条**遍历式**用例，不是那两条验收断言
##
## 引擎 20 条技能里只有 5 条有设计库权威值可抄，另外 15 条是引擎自有的测试单位技能。
## 对那 15 条我**没有**重新判定，做法是「保持现有行为不变」—— 而「保持不变」这句话
## 必须是**可验证的**，不能靠我保证。所以 [T2] 逐条比对新实现与旧反推的输出，
## **例外名单写死在 EXPECTED_BEHAVIOR_CHANGES 里**：不在名单上的技能一旦行为变了，
## 用例立刻红。这样「我不小心改掉了另外 14 条」这件事在结构上不可能悄悄发生。
##
## 四组：
##   T1. 20 条技能全部带上了 target_mode，且取值在闭集内。
##   T2. **行为保持**：新实现 vs 旧反推逐条比对，只有拔刀允许不同。
##   T3. 验收判据（任务书 §4）：拔刀不能再点空地、一闪仍能点空格作落点。
##   T4. 缺字段 / 值越界时**响亮退回**旧反推，不静默。
##
## 运行：
##   <Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##     --script res://tests/test_skill_target_mode.gd
## 退出码 0=全过，1=有失败。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false

const DATA_LOADER_PATH := "res://scripts/data/data_loader.gd"

## 本次**允许**行为改变的技能，以及改变的理由。名单之外一律必须与旧反推一致。
## ★ 这个名单就是本次改动的全部行为影响面，评审看这一处即可。
const EXPECTED_BEHAVIOR_CHANGES: Dictionary = {
	"swordsman_badao": "拔刀 area=diamond/1 被旧反推误判为选地面；设计库 target_mode=单位",
}

## 5 条有设计库对应的技能，值从设计库快照抄来（1:2 映射的四条两版取值一致）。
## 写死在这里是为了让「抄错了」也能被测出来——否则数据与实现同源，测不出偏差。
const DESIGNLIB_BACKED: Dictionary = {
	"swordsman_badao": "单位",
	"swordsman_juhe": "单位",
	"swordsman_yishan": "方向",
	"swordsman_zhanji": "单位",
	"swordsman_zhaojia": "自身",
}


func _initialize() -> void:
	print("=== test_skill_target_mode（target_mode 导引擎）===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	var dl: Object = load(DATA_LOADER_PATH).new()
	dl.load_all()
	var scene: Node = load("res://scenes/tactical/TacticalScene.tscn").instantiate()
	root.add_child(scene)
	var tm: Object = scene.tactical_manager

	_test_all_skills_declare_it(dl, tm)
	_test_behavior_preserved(dl, tm)
	_test_acceptance(dl, tm)
	_test_missing_field_is_loud(tm)

	scene.free()
	dl.free()
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  ✗ " + f)
	quit(0 if _fail == 0 else 1)


# ── T1. 全部带上了，且取值合法 ──────────────────────

func _test_all_skills_declare_it(dl: Object, tm: Object) -> void:
	print("\n[T1] 20 条技能都声明了 target_mode 且取值在闭集内")
	var missing: Array[String] = []
	var bad: Array[String] = []
	for key: Variant in dl.skills.keys():
		var sk: Dictionary = dl.skills[key]
		var mode: String = str(sk.get("target_mode", ""))
		if mode == "":
			missing.append(str(key))
		elif mode not in tm.SUPPORTED_TARGET_MODES:
			bad.append("%s=%s" % [str(key), mode])
	_eq("没有技能漏填 target_mode", str(missing), str([]))
	_eq("没有技能填了闭集外的值", str(bad), str([]))
	_check("技能总数 >= 20", dl.skills.size() >= 20, "实际 %d" % dl.skills.size())

	# 有设计库权威值的那 5 条，逐条对照抄没抄错。
	for sid: String in DESIGNLIB_BACKED.keys():
		var sk2: Variant = dl.skills.get(sid, {})
		_eq("%s 的 target_mode 与设计库一致" % sid,
			str((sk2 as Dictionary).get("target_mode", "")), str(DESIGNLIB_BACKED[sid]))


# ── T2. ★行为保持：新实现 vs 旧反推，逐条 ────────────

## 旧反推的**独立重实现**（照改动前的源码逐字复刻，不调用被测代码）。
## 独立写一份是有意的：直接调 `tm._legacy_target_mode_from_area()` 会让「新旧一致」
## 变成自证——那个函数正是我这次写的，它错了这条用例也跟着错。
func _old_is_ground_target(sk: Dictionary) -> bool:
	if str((sk.get("range", {}) as Dictionary).get("type", "")) == "self":
		return false
	return str((sk.get("area", {}) as Dictionary).get("type", "single")) != "single"


func _old_target_relation(sk: Dictionary) -> String:
	var is_self: bool = \
		str((sk.get("range", {}) as Dictionary).get("type", "")) == "self" \
		and str((sk.get("area", {}) as Dictionary).get("type", "single")) == "single"
	if is_self:
		return "self"
	return "ally" if int(sk.get("power", 0)) <= 0 else "enemy"


func _test_behavior_preserved(dl: Object, tm: Object) -> void:
	print("\n[T2] 行为保持：只有例外名单上的技能允许与旧反推不同")
	var changed_ground: Array[String] = []
	var changed_relation: Array[String] = []
	for key: Variant in dl.skills.keys():
		var sid: String = str(key)
		var sk: Dictionary = dl.skills[key]
		if tm._is_ground_target_skill(sk) != _old_is_ground_target(sk):
			changed_ground.append(sid)
		if tm._get_skill_target_relation(sk) != _old_target_relation(sk):
			changed_relation.append(sid)
	changed_ground.sort()
	changed_relation.sort()

	var allowed: Array[String] = []
	for k: Variant in EXPECTED_BEHAVIOR_CHANGES.keys():
		allowed.append(str(k))
	allowed.sort()

	_eq("「能否点空地」的变化面 == 例外名单", str(changed_ground), str(allowed))
	_eq("「瞄准谁」一条都没变（本次不该动这一维）", str(changed_relation), str([]))
	for sid: String in allowed:
		_check("例外 %s 的理由已登记：%s" % [sid, str(EXPECTED_BEHAVIOR_CHANGES[sid])],
			str(EXPECTED_BEHAVIOR_CHANGES[sid]) != "")


# ── T3. 验收判据（任务书 §4，两个方向）──────────────

func _test_acceptance(dl: Object, tm: Object) -> void:
	print("\n[T3] 验收：拔刀不能再点空地、一闪仍能点空格")
	var badao: Dictionary = dl.skills.get("swordsman_badao", {})
	var yishan: Dictionary = dl.skills.get("swordsman_yishan", {})
	_check("前提：两条技能都装载了", not badao.is_empty() and not yishan.is_empty())

	# 方向一：拔刀（target_mode=单位）→ 必须选单位，不能点空地。这是本次修的那个错。
	_check("拔刀不再是「可点空地」", not tm._is_ground_target_skill(badao))
	_eq("拔刀瞄准敌军", tm._get_skill_target_relation(badao), "enemy")
	# 旧行为对照：证明这确实是**变了**，而不是本来就这样（否则这条断言是永真的）。
	_check("对照：旧反推确实把拔刀判成可点空地（所以这是一处真实修复）",
		_old_is_ground_target(badao))
	# 而拔刀的**溅射**不受影响——本次只拆选择那一半。
	# ★ size 用 int() 转过再比：Godot 的 JSON.parse 把**所有**数字解析成 float，
	# JSON 里写的 1 读出来是 1.0，直接拿字符串比会得到「diamond/1.0 != diamond/1」这种
	# 与被测行为无关的假失败（同一个坑 talent_registry.gd 的 gain_resource 校验里登记过）。
	var badao_area: Dictionary = badao.get("area", {})
	_eq("拔刀的 area 形状未被改动", str(badao_area.get("type", "")), "diamond")
	_eq("拔刀的 area 大小未被改动（伤害波及仍是菱形 1）",
		int(badao_area.get("size", -1)), 1)

	# 方向二：一闪（target_mode=方向）→ 仍然能点空格作落点。
	_check("一闪仍是「可点空地」", tm._is_ground_target_skill(yishan))
	_check("对照：旧反推也认为一闪可点空地（这一条本就该保持不变）",
		_old_is_ground_target(yishan))


# ── T4. 缺字段 / 越界值：响亮退回，不静默 ──────────

func _test_missing_field_is_loud(tm: Object) -> void:
	print("\n[T4] 缺字段或值越界时退回旧反推（并告警，不静默）")
	# 缺字段：形状与拔刀同构（area=diamond/1）→ 旧反推给「格子」。
	var no_mode: Dictionary = {
		"id": "test_no_target_mode",
		"range": {"type": "diamond", "min": 1, "max": 2},
		"area": {"type": "diamond", "size": 1}, "power": 100,
	}
	_check("缺 target_mode → 退回旧反推（可点空地）",
		tm._is_ground_target_skill(no_mode))
	# 闭集外的值同样退回，不当成「没填」也不当成合法值放行。
	var bad_mode: Dictionary = no_mode.duplicate(true)
	bad_mode["id"] = "test_bad_target_mode"
	bad_mode["target_mode"] = "区域"
	_check("闭集外的值 → 同样退回旧反推", tm._is_ground_target_skill(bad_mode))
	# 退回路径本身要正确：range=self + area=single 的旧口径是「自身」。
	var self_like: Dictionary = {
		"id": "test_legacy_self",
		"range": {"type": "self", "min": 0, "max": 0},
		"area": {"type": "single", "size": 0}, "power": 0,
	}
	_eq("退回路径对 range=self+area=single 给出「自身」",
		tm._legacy_target_mode_from_area(self_like), tm.TARGET_MODE_SELF)
	_eq("退回后瞄准关系仍是 self",
		tm._get_skill_target_relation(self_like), "self")


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
