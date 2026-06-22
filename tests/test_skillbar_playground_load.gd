extends SceneTree
## 剑圣底栏 Playground headless 加载自检。
## 仅保证 parse + 实例化 + _ready 不崩（headless 不渲染，_draw 视觉留待 MCP 截图）。
##
## 运行：
##   <Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##     --script res://tests/test_skillbar_playground_load.gd
## 期望：无 Parse/SCRIPT ERROR，打印 "PLAYGROUND LOAD OK"，退出码 0。

const SCENE_PATH: String = "res://scenes/dev/skillbar_playground.tscn"

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
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		printerr("FAIL: 无法 load 场景 " + SCENE_PATH)
		quit(1)
		return

	var inst: Node = packed.instantiate()
	if inst == null:
		printerr("FAIL: instantiate 返回 null")
		quit(1)
		return

	root.add_child(inst)
	# await 一帧，确保 _ready / _build / _refresh_all 全部跑过
	await process_frame

	print("PLAYGROUND LOAD OK")
	inst.queue_free()
	quit(0)
