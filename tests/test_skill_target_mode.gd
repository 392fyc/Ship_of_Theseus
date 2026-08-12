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
	_test_area_direction_decoupled(dl, tm)
	_test_direction_capture_is_range_driven(dl, tm)

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


# ── T5. 方向捕获与 area 脱钩（2026-08-12）──────────────

## `_get_skill_area_direction` 的**旧**判据，独立重实现（不调被测代码，理由同 [T2]）。
func _old_area_direction(origin: Vector2i, target_pos: Vector2i,
		sk: Dictionary, captured: Vector2i) -> Vector2i:
	if str((sk.get("area", {}) as Dictionary).get("type", "")) == "line" \
			and captured != Vector2i.ZERO:
		return captured
	return RangeCalculator.direction_from_to(origin, target_pos)


## ★ 本组的判据是**受伤格**，不是函数返回值 —— 两者结论不同，必须分开说。
##
## `knight_charge`（range=line / area=single）的**函数返回值确实变了**：旧实现因
## area 非 line 而丢弃玩家选的方向、改用推导方向；新实现直接用玩家选的。但
## `AreaCalculator.calculate_cells` **只在 line 分支使用 direction**（single/diamond/
## cross/square 四个分支都不读它），所以它的**受伤格一格没变**。
##
## 笼统说「零变化」是不准的；准确说法是「受伤格零变化，函数级有一处差异且无观测后果」。
## 这一组把两条都断言出来，包括「那处差异确实存在」——否则那是一条永真断言。
func _test_area_direction_decoupled(dl: Object, tm: Object) -> void:
	print("\n[T5] 方向捕获与 area 脱钩：受伤格零变化，函数级差异仅 knight_charge")
	var origin: Vector2i = Vector2i(2, 2)
	var target: Vector2i = Vector2i(5, 2)
	var captured: Vector2i = Vector2i(0, 1)   # 刻意不等于 origin→target 的方向
	_check("前提：模拟的捕获方向与推导方向不同（否则整组失去区分力）",
		captured != RangeCalculator.direction_from_to(origin, target))

	var saved: Vector2i = tm._targeting_direction

	var cells_changed: Array[String] = []
	var dir_changed: Array[String] = []
	for key: Variant in dl.skills.keys():
		var sid: String = str(key)
		var sk: Dictionary = dl.skills[key]
		# ★ 每条技能用它**实际可能处于**的捕获状态，不能一律强设成「已捕获」。
		# 方向捕获只在 `range.type == "line"` 时发生（`_is_waiting_for_line_direction`），
		# 所以对其余技能 `_targeting_direction` 恒为 ZERO。一律强设会把新旧实现放到一个
		# **现实中不可能出现的状态**下比较，得出 18 条「差异」——那是测试造出来的，不是
		# 代码的。（初版就是这么写的，被这一组自己抓了出来。）
		var can_capture: bool = \
			str((sk.get("range", {}) as Dictionary).get("type", "")) == "line"
		var actual: Vector2i = captured if can_capture else Vector2i.ZERO
		tm._targeting_direction = actual
		var new_dir: Vector2i = tm._get_skill_area_direction(origin, target)
		var old_dir: Vector2i = _old_area_direction(origin, target, sk, actual)
		if new_dir != old_dir:
			dir_changed.append(sid)
		var area: Dictionary = sk.get("area", {})
		var new_cells: Array[Vector2i] = AreaCalculator.calculate_cells(
			tm.grid, target, area, new_dir)
		var old_cells: Array[Vector2i] = AreaCalculator.calculate_cells(
			tm.grid, target, area, old_dir)
		if str(new_cells) != str(old_cells):
			cells_changed.append(sid)
	tm._targeting_direction = saved

	cells_changed.sort()
	dir_changed.sort()
	_eq("★ 受伤格：20 条一格没变", str(cells_changed), str([]))
	# 函数级差异 == 「range=line 且 area 非 line」的那一批，当前恰好只有 knight_charge。
	_eq("函数级差异只有 knight_charge", str(dir_changed), str(["knight_charge"]))
	_check("对照：那处差异确实存在（否则上一条是永真断言）", dir_changed.size() == 1)

	# 差异无观测后果的**机制**要单独钉住：AreaCalculator 对 single 忽略 direction。
	var single_a: Dictionary = {"type": "single", "size": 0}
	_eq("机制：area=single 时 direction 不影响受伤格",
		str(AreaCalculator.calculate_cells(tm.grid, target, single_a, Vector2i(0, 1))),
		str(AreaCalculator.calculate_cells(tm.grid, target, single_a, Vector2i(1, 0))))


## 如实锁住「格子 / 方向 **尚未**完全声明式」这个状态。
##
## 任务书要求「`target_mode=格子` 的技能不再捕获方向」——**本次改动做不到这件事**，
## 因为方向捕获由 `range.type == "line"` 驱动，而那一处按界线不动（它是射程形状要不要
## 定方向，本就归射程管，不属于「拿 area 猜」）。
##
## 与其假装做到了，不如把现状钉成断言：构造一条 `格子 + range=line` 的合成技能，
## 断言它**仍会**进入方向选择模式。哪天有人把捕获改成声明式，这条会红——那时它是提醒
## 「该更新这条用例了」，而不是一条掩盖现状的绿灯。
##
## ⚠ **这个状态是「已裁决现在不做」，不是待办**（2026-08-12）。所以本组锁的不是一个
## 半成品，而是一个**有意维持的现状** —— 别看到它就以为这里有活没干完。要翻过来的
## 条件写在 lane §2.2 注 10 第四条：测试单位正式化、`knight_charge` 拿到真正的定性
## 之后（它现在的 `target_mode` 是「按行为保持」推出来的，本就登记着将来要重判）。
func _test_direction_capture_is_range_driven(dl: Object, tm: Object) -> void:
	print("\n[T6] 方向捕获仍由 range 驱动（如实登记：格子/方向尚未完全声明式）")
	# 真实数据：两条「格子」技能的 range 都不是 line，故不进方向选择模式。
	for sid: String in ["cleric_bless", "mage_fireball"]:
		var sk: Dictionary = dl.skills.get(sid, {})
		_eq("%s 是 target_mode=格子" % sid, str(sk.get("target_mode", "")), "格子")
		_check("%s 的 range 不是 line → 不进方向选择" % sid,
			str((sk.get("range", {}) as Dictionary).get("type", "")) != "line")

	# 合成夹具：格子 + range=line。**当前仍会进方向选择模式** —— 这就是未完成的那一半。
	var autoload_dl: Node = root.get_node_or_null("/root/DataLoader")
	if autoload_dl == null:
		_check("autoload DataLoader 可达", false)
		return
	autoload_dl.skills["test_cell_with_line_range"] = {
		"id": "test_cell_with_line_range", "target_mode": "格子",
		"range": {"type": "line", "min": 1, "max": 3},
		"area": {"type": "single", "size": 0}, "power": 100,
	}
	var saved_state: int = tm.input_state
	var saved_skill: String = tm._selected_skill_id
	var saved_dir: Vector2i = tm._targeting_direction
	tm.input_state = tm.InputState.SKILL_TARGETING
	tm._selected_skill_id = "test_cell_with_line_range"
	tm._targeting_direction = Vector2i.ZERO
	_check("【已知未完成】格子 + range=line 仍会进方向选择模式",
		tm._is_waiting_for_line_direction(),
		"若这条红了，说明捕获已改成声明式，请更新本用例与 lane §2.2 注 10")
	tm.input_state = saved_state
	tm._selected_skill_id = saved_skill
	tm._targeting_direction = saved_dir
	autoload_dl.skills.erase("test_cell_with_line_range")


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
