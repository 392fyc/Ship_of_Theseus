extends SceneTree
## 位移技能的受伤格：`_get_displacement_path_cells` 的边界（2026-08-12）。
##
## ## 这个文件补的是什么（先说清它**不是**补一个完全没人守的地方）
##
## 一闪 / 连闪 / 瞬身的受伤格全部出自这一个函数。开工时我以为它的核心口径「不含起点」
## 只有 `tactical_manager.gd:2107` 的一行注释在守 —— **那是错的**：
## `test_swordsman_qa_impl.gd:126-129` 早就端到端断言过一闪的 `affected_cells`
## 含中途格、含落点、**不含起点**。变异验证证实了这一点：把游标起点从 `origin + step`
## 改成 `origin`，那个文件也会红。
##
## 所以本文件的定位是**补齐没被覆盖的那几面**，不是从零加护栏：
##   - 量化格数（恰等于位移距离）与**顺序**（由近及远）—— 下游若按顺序逐格结算，
##     顺序反了不会有任何现有断言发现。
##   - 路径连续性（不跳格）。
##   - `origin == landing` 的退化情形 —— 由函数开头的提前 return 负责，
##     上面那个变异**打不到**它，说明它确实是独立的一条。
##   - 非共线落点的已知局限（见 [P5]）。
##   - 单元粒度：`qa_impl` 走的是完整施放链，链上任何一环坏掉都会盖住这一条。
##
## `test_support_displacement.gd` [C] 是邻近的一组，但它锁的是**时序**（路径在单位移动
## 之前算），把敌人摆在中途格上，起点含不含都不影响那条断言。
##
## ## 组
##   P1. 三件事一次锁死：不含起点、含中途格、含落点（含格数与由近及远的顺序）。
##   P2. 退化情形：`origin == landing` 返回空。
##   P3. 路径连续：相邻两格恒相接，不跳格。
##   P4. **接线**：位移技能确实走这条路径而不是 AreaCalculator ——
##       只锁函数本身、不锁接线的话，把 `_compute_skill_area_cells` 的分支删掉也不会红。
##   P5. 【如实登记】非共线落点当前**走不到落点**。不是待办、也不是本次要改的东西，
##       见该组自己的说明。
##
## 运行：
##   <Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##     --script res://tests/test_displacement_path.gd
## 退出码 0=全过，1=有失败。

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false

const DATA_LOADER_PATH := "res://scripts/data/data_loader.gd"

## 8×8 地图上的一条水平线，起点与落点都留足余量，避免断言被 `grid.is_valid` 的边界
## 截断影响（那是另一条口径，不该混进本组）。
const ORIGIN := Vector2i(1, 3)
const LANDING := Vector2i(5, 3)


func _initialize() -> void:
	print("=== test_displacement_path（位移受伤格的边界）===")


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

	_test_endpoints(tm)
	_test_degenerate(tm)
	_test_contiguous(tm)
	_test_wiring(dl, tm)
	_test_non_collinear_is_registered(tm)

	scene.free()
	dl.free()
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  ✗ " + f)
	quit(0 if _fail == 0 else 1)


# ── P1. 不含起点 / 含中途格 / 含落点 ────────────────────

## 三条一起断言，因为它们是同一句口径的三个面，分开写容易只补其中一面。
## 起点→落点水平 4 格，故正确答案恰是 4 格：(2,3) (3,3) (4,3) (5,3)。
func _test_endpoints(tm: Object) -> void:
	print("\n[P1] 不含起点、含中途格、含落点")
	var cells: Array[Vector2i] = tm._get_displacement_path_cells(ORIGIN, LANDING)

	_check("★ 不含起点（施法者原本站的那一格不受伤）", ORIGIN not in cells,
		"实际 %s" % str(cells))
	_check("★ 含落点", LANDING in cells, "实际 %s" % str(cells))
	for mid: Vector2i in [Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)]:
		_check("★ 含中途格 %s" % str(mid), mid in cells, "实际 %s" % str(cells))

	# 格数：位移 4 格 → 恰 4 格。多一格就是把起点算进去了，少一格就是丢了落点。
	_eq("格数 == 位移距离（4）", cells.size(), 4)
	# 顺序也钉住：由近及远。下游若要按顺序结算（例如逐格触发），顺序反了会静默出错。
	_eq("顺序由近及远", str(cells),
		str([Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3)]))


# ── P2. 退化情形 ───────────────────────────────────

## 落点等于起点时返回空，而不是「起点自己那一格」。
## 由函数**开头的提前 return** 负责，与游标怎么起步是两条独立的路 —— 变异验证里把
## 游标改成从 `origin` 起步，P1 那几条全红而这一条仍绿，正说明它需要单独守。
func _test_degenerate(tm: Object) -> void:
	print("\n[P2] origin == landing → 空")
	var cells: Array[Vector2i] = tm._get_displacement_path_cells(ORIGIN, ORIGIN)
	_eq("没动就没有受伤格", cells.size(), 0)


# ── P3. 路径连续 ───────────────────────────────────

func _test_contiguous(tm: Object) -> void:
	print("\n[P3] 路径连续：相邻两格恒相接")
	var cells: Array[Vector2i] = tm._get_displacement_path_cells(ORIGIN, LANDING)
	var prev: Vector2i = ORIGIN
	var gaps: Array[String] = []
	for c: Vector2i in cells:
		var d: Vector2i = c - prev
		if absi(d.x) > 1 or absi(d.y) > 1 or d == Vector2i.ZERO:
			gaps.append("%s→%s" % [str(prev), str(c)])
		prev = c
	_eq("没有跳格（含从起点到第一格这一步）", str(gaps), str([]))


# ── P4. ★接线：位移技能不走 AreaCalculator ─────────────

## 只锁 `_get_displacement_path_cells` 本身是不够的 —— 把 `_compute_skill_area_cells`
## 里那个 `displacement` 分支删掉，函数还在、还正确，但没有任何技能会用到它。
## 所以这一组从**技能**这一侧进：拿一闪的真实数据，断言算出来的受伤格等于位移路径。
## 与 `qa_impl` 的区别在粒度：那边跑完整施放链（构造 action → 执行 → 看结果），
## 链上任何一环坏掉都会先红；这里只调这一个函数，坏在哪一层分得清。
##
## 同时断言两条路径的结果**确实不同** —— 否则「等于位移路径」会是一条永真断言，
## 测不出分支被删掉。
func _test_wiring(dl: Object, tm: Object) -> void:
	print("\n[P4] 接线：一闪的受伤格来自位移路径，不来自 AreaCalculator")
	var yishan: Dictionary = dl.skills.get("swordsman_yishan", {})
	_check("前提：一闪已装载", not yishan.is_empty())
	_check("前提：一闪确实是位移技能", bool(yishan.get("displacement", false)))
	if yishan.is_empty():
		return

	var user: Unit = null
	for u: Unit in tm.units:
		if u.faction == "player":
			user = u
			break
	if user == null:
		_check("场景中找到一个玩家单位", false)
		return

	var saved: Vector2i = user.grid_position
	user.grid_position = ORIGIN
	var direction: Vector2i = Vector2i(1, 0)

	var got: Array[Vector2i] = tm._compute_skill_area_cells(
		user, yishan, LANDING, direction)
	var path: Array[Vector2i] = tm._get_displacement_path_cells(ORIGIN, LANDING)
	var area_way: Array[Vector2i] = AreaCalculator.calculate_cells(
		tm.grid, LANDING, yishan.get("area", {}), direction)

	_eq("★ 受伤格 == 位移路径", str(got), str(path))
	_check("对照：AreaCalculator 会给出不同的结果（否则上一条是永真断言）",
		str(area_way) != str(path), "两者都是 %s" % str(path))
	_check("对照：施法者那一格不在受伤格里", ORIGIN not in got, "实际 %s" % str(got))

	user.grid_position = saved


# ── P5. 【如实登记】非共线落点走不到落点 ─────────────────

## 游标按 `signi(delta)` 逐步推进，对**非共线**的落点（例如 delta=(2,1)）会一路走对角线，
## 永远撞不上落点，最后由安全上界收住 —— 结果是一条**不含落点**的对角线。
##
## 当前**触发不到**：引擎里唯一带 `displacement` 的技能是一闪，`range.type == "line"`，
## 落点必与起点共线。真正会撞上这一条的是瞬身（设计库 `kensei_huizhan`：位移 +
## `target_mode=单位` + 射程菱形 1–5，菱形射程含非共线格），而它**引擎侧还没有数据文件**。
##
## 所以本组锁的是**现状**，不是期望行为：如实登记「今天是这样」，将来实装瞬身时这条会
## 提醒实装者先处理落点求解，而不是让它安静地打偏。这与 test_skill_target_mode.gd [T6]
## 是同一种写法 —— 别看到它就以为这里有活没干完；要动它的时机是瞬身进引擎的那一次。
func _test_non_collinear_is_registered(tm: Object) -> void:
	print("\n[P5] 如实登记：非共线落点当前走不到落点（瞬身实装前触发不到）")
	var landing: Vector2i = Vector2i(3, 2)
	var cells: Array[Vector2i] = tm._get_displacement_path_cells(Vector2i(1, 1), landing)
	_check("【已知局限】非共线时路径不含落点", landing not in cells,
		"若这条红了，说明落点求解已被修好，请更新本组与 tactical_manager 的说明")
	_check("对照：它走的是对角线", Vector2i(2, 2) in cells, "实际 %s" % str(cells))


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
