extends SceneTree
## attack_type 分类轴校验（R4.3）—— 2026-07-11 漂移修复 FIX-2
##
## 断言每个 data/skills/*.json 都显式声明 attack_type，且与 R4.3 派生规则一致：
##   area.type != "single" → "area"；否则 range.max > 1 → "ranged"；否则 "melee"。
## 防止未来新技能缺字段、或声明值与射程/AOE 定义脱节的静默漂移。
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/test_skill_attack_type.gd  （退出码 0=全过）

const SKILLS_DIR: String = "res://data/skills/"

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false


func _initialize() -> void:
	print("=== test_skill_attack_type (R4.3 attack_type 校验) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	var dir: DirAccess = DirAccess.open(SKILLS_DIR)
	_check("skills 目录可打开", dir != null)
	if dir == null:
		_finish()
		return
	var json_count: int = 0
	for f: String in dir.get_files():
		if not f.ends_with(".json"):
			continue
		json_count += 1
		_check_skill(SKILLS_DIR + f, f)
	_check("技能 JSON 数量 >= 20", json_count >= 20, "实际 %d" % json_count)
	_finish()


func _check_skill(path: String, fname: String) -> void:
	var data: Variant = _load_json(path)
	if not (data is Dictionary):
		_check(fname + " 可解析", false)
		return
	var d: Dictionary = data
	var declared: String = str(d.get("attack_type", ""))
	_check(fname + " 声明了 attack_type", declared != "")
	var area_dict: Dictionary = d.get("area", {})
	var range_dict: Dictionary = d.get("range", {})
	var area_type: String = str(area_dict.get("type", "single"))
	var range_max: int = int(range_dict.get("max", 1))
	var expected: String = "melee"
	if area_type != "single":
		expected = "area"
	elif range_max > 1:
		expected = "ranged"
	_eq(fname + " attack_type 符合派生规则", declared, expected)


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
