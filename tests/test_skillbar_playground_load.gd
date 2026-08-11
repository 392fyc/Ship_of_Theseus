extends SceneTree
## 剑圣底栏 Playground headless 加载自检。
## 仅保证 parse + 实例化 + _ready 不崩（headless 不渲染，_draw 视觉留待 MCP 截图）。
##
## ── 本文件曾经是一个假绿测试（2026-08-12 修）──────────────────
##
## 旧版的文档注释逐字写着「期望：**无 Parse/SCRIPT ERROR**」，但 `_run()` 只检查两件事：
## `load(SCENE_PATH)` 返回非 null、`instantiate()` 返回非 null。**这两条都拦不住 parse
## 错误** —— 场景在附着脚本 parse 失败时照样实例化得出来（脚本变成 null、节点还在），
## 于是它照常打印 `PLAYGROUND LOAD OK` 并 `quit(0)`。
##
## 后果：`skillbar_playground.gd` 自 `15aebaa` 起就 parse 失败（内部类
## `DamageForecaster` 与全局 `class_name DamageForecaster` 撞名），**坏了两个月无人发现**，
## 全量回归一直是绿的。它是「全绿 ≠ 有护栏」的实例：一个测试可以完整地跑完、退出 0、
## 打印成功标记，却从来没有检查过它被写出来要检查的那件事。
##
## 现在的判据分三层：
##   ① 脚本资源自己 `load()` 得出来。
##   ② 场景实例化后根节点 `get_script() != null` —— **旧版缺的正是这道，也是真正
##      拦住本次缺陷的那一条**。
##   ③ 挂的脚本路径就是期望的那一个 —— 拦「装上了但装错了脚本」。
##
## ⚠ **别高估第 ① 条，它不等价于 `--check-only`。** 本文件初版的注释这么写过，
## 实测证伪：把内部类名改回去重现撞车后，`--check-only` 确实退出 1，但在本测试
## 进程内 `load()` **仍然返回非 null**，① 照过不误，红的只有 ②。GDScript 的
## `load()` 对 parse 失败脚本返回什么，随调用时机与资源缓存状态而变（在 `_initialize`
## 里探测与在 `_process` 里探测，行为就不一样），**不是一个可以拿来当 parse 判据的
## 稳定信号**。① 留着当一条便宜的额外信号，但**承重的是 ②**。
##
## 记这一段是因为：一条「看着像护栏、实际不判别」的断言，正是本文件这次要修的病本身。
## 与其留一个过强的说法，不如把实测边界写清楚。
##
## 运行：
##   <Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##     --script res://tests/test_skillbar_playground_load.gd
## 退出码 0=全过，1=有失败。

const SCENE_PATH: String = "res://scenes/dev/skillbar_playground.tscn"
const SCRIPT_PATH: String = "res://scripts/ui/playground/skillbar_playground.gd"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_skillbar_playground_load ===")


## 自定义 SceneTree 主循环下，节点的 _ready 要到第一帧才触发；
## 故在首帧 _process 里跑加载（确保 add_child 后 _ready 已执行），避免构造期断言坑。
func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	await _check_all()
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  ✗ " + f)
	quit(0 if _fail == 0 else 1)


func _check_all() -> void:
	# ── 判据①：脚本资源 load 得出来（便宜的额外信号，**不承重**）────
	# ⚠ 实测：撞车重现时这一条照过不误（见文件头「别高估第 ① 条」）。留着是因为它
	# 几乎零成本、且能拦住「文件被删/路径写错」这类更粗的问题，但**别指望它测 parse**。
	var script_res: Variant = load(SCRIPT_PATH)
	_check("脚本 %s 能 load（粗筛：文件在、路径对）" % SCRIPT_PATH,
		script_res != null)

	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_check("场景 %s 能 load" % SCENE_PATH, packed != null)
	if packed == null:
		return

	var inst: Node = packed.instantiate()
	_check("场景能实例化", inst != null)
	if inst == null:
		return

	root.add_child(inst)
	# await 一帧，确保 _ready / _build / _refresh_all 全部跑过
	await process_frame

	# ── 判据②：脚本**真的挂上了** ───────────────────────
	# 旧版缺的就是这一道。脚本 parse 失败时节点还在、只是 get_script() 为 null，
	# 所以「实例化成功」证明不了任何事。
	var attached: Variant = inst.get_script()
	_check("根节点确实挂着脚本（get_script() != null）", attached != null)

	# ── 判据③：挂的是**期望的那一个** ──────────────────
	if attached != null:
		_check("挂的脚本路径就是 %s" % SCRIPT_PATH,
			str(attached.resource_path) == SCRIPT_PATH,
			str(attached.resource_path))

	inst.queue_free()


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  ✓ " + name)
	else:
		_fail += 1
		_fails.append(name + ("  [" + detail + "]" if detail != "" else ""))
		print("  ✗ " + name + ("  [" + detail + "]" if detail != "" else ""))
