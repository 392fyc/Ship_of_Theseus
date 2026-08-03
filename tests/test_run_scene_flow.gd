extends SceneTree
## RunScene 门循环逻辑集成回归 —— 2026-07-04（任务 #6）
##
## 目的：不实例化真 UI，纯逻辑驱动 RunManager + BattleAssembler 走完整一幕，验证
## 「战斗结算 → 门装配清单 → 门选择 → 进下一关」链路端到端一致。补 test_run_manager
## （只测 RunManager 内部账本）未覆盖的「BattleAssembler 装配当前关清单」这一步。
##
## 覆盖：
##   1. start_run：stage==1 / phase==battle。
##   2. 8 关流转：连续 victory + 每关用 BattleAssembler.build 装配当前关战斗，验证
##      装配 map_id 与 current_battle 一致、玩家清单非空、敌人数与波次数据一致。
##   3. 门在 stage 2..7 生成（door_select，门数 [2,3]），choose_door→confirm 推进。
##   4. 精英波次装配敌人含词条（affixes 非空 + special_affix==afs_bulwark + stat_scale 1.35），
##      证明 BattleAssembler 把词条透传给注入层（apply_affixes 的输入）。
##   5. run_completed / 最终 stage==8。
##   6. 失败路径：defeat → run_failed / phase==failed。
##
## 坑规避（--script 三大坑）：断言放 _process 首帧；只用 preload（不引全局 class_name）；
## DataLoader 手动 load_all()。
##
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/test_run_scene_flow.gd
## 退出码 0=全过，1=有失败。

const ACT_CONFIG_FILE: String = "res://data/runloop/act1_config.json"
const RUN_CONFIG_FILE: String = "res://data/runloop/run_config.json"
const DATA_LOADER_SCRIPT: String = "res://scripts/data/data_loader.gd"

const RunManagerScript: GDScript = preload("res://scripts/roguelite/run_manager.gd")
const BattleAssemblerScript: GDScript = preload("res://scripts/roguelite/battle_assembler.gd")

const RNG_SEED: int = 20260704

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []
var _ran: bool = false

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _act_config: Dictionary = {}
var _run_config: Dictionary = {}
var _pools: Dictionary = {}
var _boss_stage: int = 8
var _roster: Array = []

var _completed: bool = false
var _failed: bool = false


func _initialize() -> void:
	print("=== test_run_scene_flow (RunScene 门循环逻辑集成) ===")


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	if not _load_env():
		_finish()
		return
	_rng.seed = RNG_SEED

	_test_full_flow_with_assembly()
	_test_elite_affix_surfacing()
	_test_event_door_flow()
	_test_failure()

	_finish()


func _load_env() -> bool:
	var act_v: Variant = _load_json(ACT_CONFIG_FILE)
	_check("act1_config.json 可解析为 Dictionary", act_v is Dictionary)
	if not (act_v is Dictionary):
		return false
	_act_config = act_v
	_boss_stage = int(_act_config.get("boss_stage", 8))

	var run_v: Variant = _load_json(RUN_CONFIG_FILE)
	_check("run_config.json 可解析为 Dictionary", run_v is Dictionary)
	if not (run_v is Dictionary):
		return false
	_run_config = run_v

	var dl: Object = load(DATA_LOADER_SCRIPT).new()
	dl.load_all()
	_pools = {
		"maps": dl.maps,
		"waves": dl.waves,
		"affixes": dl.affixes,
		"relics": dl.relics,
		"equipment": dl.equipment,
		"events": dl.events,
	}
	_check("data_pools.maps 非空", not (dl.maps as Dictionary).is_empty())
	_check("data_pools.waves 非空", not (dl.waves as Dictionary).is_empty())

	# [占位] 4 人队伍（与 RunScene.PARTY_ROSTER 同构）
	_roster = [
		{"class_id": "kensei", "level": 1},
		{"class_id": "soldier", "level": 1},
		{"class_id": "archer", "level": 1},
		{"class_id": "cleric", "level": 1},
	]
	return _fail == 0


# ── 测试 1+2+3+5：全流转 + 逐关装配验证 ──────────────

func _test_full_flow_with_assembly() -> void:
	_completed = false
	_failed = false
	var rm: Object = RunManagerScript.new()
	rm.run_completed.connect(_on_run_completed)
	rm.run_failed.connect(_on_run_failed)
	rm.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), _rng)

	_check("[1] start_run: stage==1", rm.get_state().stage == 1,
		"stage=%d" % rm.get_state().stage)
	_check("[1] start_run: phase==battle", rm.get_state().phase == "battle",
		"phase=%s" % rm.get_state().phase)

	var stages_assembled: Array[int] = []
	var door_selects: int = 0
	var guard: int = 0
	while not rm.is_run_complete() and not rm.is_run_failed() and guard < 40:
		guard += 1
		var st: Object = rm.get_state()
		var cur_stage: int = st.stage
		# 装配「当前关」战斗清单并验证（模拟 RunScene._enter_battle 的装配步骤）
		_verify_assembly(cur_stage, st.current_battle, st.party)
		stages_assembled.append(cur_stage)

		rm.on_battle_resolved("victory")
		if rm.is_run_complete():
			break
		var ph: String = str(rm.get_state().phase)
		if ph == "door_select":
			door_selects += 1
			var pd: Array = rm.get_state().pending_doors
			_check("[3] stage %d→%d 门组门数在 [2,3]" % [cur_stage, cur_stage + 1],
				pd.size() >= 2 and pd.size() <= 3, "size=%d" % pd.size())
			var idx: int = _choose_non_event_index(pd)
			rm.choose_door(idx)
			_check("[3] choose_door 后 phase==prep", rm.get_state().phase == "prep",
				"phase=%s" % rm.get_state().phase)
			rm.confirm_departure()
			_check("[3] confirm 后 phase==battle", rm.get_state().phase == "battle")
		elif ph == "prep":
			# Boss 前分支（stage 7→8）：无 door_select，直接确认出发
			_check("[3] Boss 前 prep：current_entry_door 为 boss 标记",
				rm.get_state().current_entry_door != null
				and str((rm.get_state().current_entry_door as Dictionary).get("reward_type", "")) == "boss")
			rm.confirm_departure()
			_check("[3] Boss 前 confirm 后 phase==battle", rm.get_state().phase == "battle")
		else:
			_check("[3] 意外 phase: %s" % ph, false)
			break

	_check("[2] 逐关装配序列 == [1..8]",
		stages_assembled == [1, 2, 3, 4, 5, 6, 7, 8], str(stages_assembled))
	_check("[3] 门选择恰 6 次（stage 2..7）", door_selects == 6, "实际 %d" % door_selects)
	_check("[5] run 已完成", rm.is_run_complete())
	_check("[5] run_completed 信号已发", _completed)
	_check("[5] 最终 stage == boss_stage(%d)" % _boss_stage,
		rm.get_state().stage == _boss_stage, "stage=%d" % rm.get_state().stage)


## 装配一关战斗清单并断言（map 一致 / 玩家非空 / 敌人数与波次一致）。
func _verify_assembly(stage: int, battle: Dictionary, party: Array) -> void:
	var map_id: String = str(battle.get("map_id", ""))
	var wave_id: String = str(battle.get("enemy_config", ""))
	var assembled: Dictionary = BattleAssemblerScript.build(map_id, wave_id, party, _pools)

	_check("[2] stage %d 装配 map_id 与 current_battle 一致" % stage,
		str(assembled.get("map_id", "")) == map_id,
		"assembled=%s battle=%s" % [str(assembled.get("map_id", "")), map_id])

	var player_units: Array = assembled.get("player_units", [])
	_check("[2] stage %d 玩家清单非空（map 有 player_spawns）" % stage,
		not player_units.is_empty(), "map=%s size=%d" % [map_id, player_units.size()])

	var enemy_units: Array = assembled.get("enemy_units", [])
	var waves: Dictionary = _pools.get("waves", {})
	var wave_data: Dictionary = waves.get(wave_id, {})
	var wave_enemies: Array = wave_data.get("enemies", [])
	_check("[2] stage %d 敌人数与波次 %s 一致(%d)" % [stage, wave_id, wave_enemies.size()],
		enemy_units.size() == wave_enemies.size(),
		"装配 %d 波次 %d" % [enemy_units.size(), wave_enemies.size()])


# ── 测试 4：精英波次装配透传词条 ─────────────────────

func _test_elite_affix_surfacing() -> void:
	var assembled: Dictionary = BattleAssemblerScript.build(
		"forest_01", "wave_act1_elite_01", _roster.duplicate(true), _pools)
	var enemy_units: Array = assembled.get("enemy_units", [])
	_check("[4] elite 波次装配敌人非空", not enemy_units.is_empty(),
		"size=%d" % enemy_units.size())

	var has_affix: bool = false
	var has_special: bool = false
	var has_scale: bool = false
	for e_v: Variant in enemy_units:
		if not (e_v is Dictionary):
			continue
		var e: Dictionary = e_v
		if (e.get("affixes", []) as Array).size() >= 1:
			has_affix = true
		if str(e.get("special_affix", "")) == "afs_bulwark":
			has_special = true
		if absf(float(e.get("stat_scale", 1.0)) - 1.35) < 0.001:
			has_scale = true
	_check("[4] elite 装配敌人含基础词条（affixes 非空）", has_affix)
	_check("[4] elite 装配敌人 special_affix==afs_bulwark", has_special)
	_check("[4] elite 装配敌人 stat_scale==1.35", has_scale)


# ── 测试 7：事件门流转（不装配战斗 + 推进，锁 soft-lock 修复前提）──
# soft-lock 曾因事件门 battle=null 被当普通战斗装配→0 单位→battle_ended 永不发出。
# RunScene 修复=选事件门走 _enter_event（不打战斗）→继续→on_battle_resolved(victory)。
# 本测试确定性构造事件门（不依赖随机是否掷出），验证 RunScene 事件分支依赖的逻辑契约。

func _test_event_door_flow() -> void:
	var rm: Object = RunManagerScript.new()
	rm.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), _rng)
	rm.on_battle_resolved("victory")  # stage1 胜利 → 生成 stage2 门组（phase=door_select）
	_check("[7] stage1 后 phase==door_select", str(rm.get_state().phase) == "door_select")
	# 确定性放入一个事件门（battle=null），绕过随机门生成
	var event_door: Dictionary = {
		"reward_type": "event", "elite_room": false,
		"battle": null, "event_id": "event_blessing_altar",
		"preview": {"icon": "event", "rarity_hint": null, "special_affix": null},
	}
	var doors: Array[Dictionary] = [event_door]
	rm.get_state().pending_doors = doors
	rm.choose_door(0)
	_check("[7] 事件门 choose 后 phase==prep", str(rm.get_state().phase) == "prep")
	rm.confirm_departure()
	var cb: Dictionary = rm.get_state().current_battle
	_check("[7] 事件门 confirm 后 current_battle 无 map（RunScene 据此走 _enter_event 不装配战斗）",
		str(cb.get("map_id", "")) == "", "map=%s" % str(cb.get("map_id", "")))
	_check("[7] 事件门 current_entry_door.reward_type==event",
		str((rm.get_state().current_entry_door as Dictionary).get("reward_type", "")) == "event")
	# 模拟 RunScene 事件「继续」→ on_battle_resolved(victory)：视为无战斗完成，推进不卡
	var gold_before: int = int(rm.get_state().gold)
	rm.on_battle_resolved("victory")
	_check("[7] 事件门 on_battle_resolved(victory) 推进（phase 离开 battle，不 soft-lock）",
		str(rm.get_state().phase) != "battle", "phase=%s" % str(rm.get_state().phase))
	_check("[7] 事件门结算固定金币（gold 增加，门奖励按 event 跳过）",
		int(rm.get_state().gold) > gold_before,
		"gold %d→%d" % [gold_before, int(rm.get_state().gold)])


# ── 测试 6：失败路径 ─────────────────────────────────

func _test_failure() -> void:
	_completed = false
	_failed = false
	var rm: Object = RunManagerScript.new()
	rm.run_completed.connect(_on_run_completed)
	rm.run_failed.connect(_on_run_failed)
	rm.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), _rng)
	rm.on_battle_resolved("defeat")
	_check("[6] defeat → is_run_failed()", rm.is_run_failed())
	_check("[6] defeat → phase==failed", rm.get_state().phase == "failed",
		"phase=%s" % rm.get_state().phase)
	_check("[6] run_failed 信号已发", _failed)
	_check("[6] 失败后未标记完成", not rm.is_run_complete())


# ── 信号 ─────────────────────────────────────────────

func _on_run_completed() -> void:
	_completed = true


func _on_run_failed() -> void:
	_failed = true


# ── 工具 ─────────────────────────────────────────────

## 优先选非事件门（避免走事件流程钩子，保证结算路径确定）；无非事件门则回退 0。
func _choose_non_event_index(doors: Array) -> int:
	for i: int in range(doors.size()):
		if str((doors[i] as Dictionary).get("reward_type", "")) != "event":
			return i
	return 0


func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	return JSON.parse_string(text)


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  OK  " + name)
	else:
		_fail += 1
		_fails.append(name + ("  [" + detail + "]" if detail != "" else ""))
		print("  XX  " + name + ("  [" + detail + "]" if detail != "" else ""))


func _finish() -> void:
	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  XX " + f)
	else:
		print("OK：全部断言通过")
	quit(0 if _fail == 0 else 1)
