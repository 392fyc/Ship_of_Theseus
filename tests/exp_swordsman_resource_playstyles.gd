extends SceneTree
## 核心战斗循环最小实证实验 —— 剑圣资源打法模式对照（纯测量，无新设计）
##
## 背景（见记忆 sot-combat-loop-design）：裁定"有条件能"——现循环可能只产
## 数值差异而不产打法差异。本脚本经验性测量：剑圣的剑气/印记资源系统在不同
## "打法策略"下，是否产生【不同可行打法】（打法差异），还是收敛到【单一最优线】
## （仅数值差异）。结论喂用户的机制优先级排序，不在此拍板设计取向。
##
## 方法：实例化正式 TacticalScene，对固定目标用确定性策略跑 N 回合，
##   蒙特卡洛多次取均值（捕获心眼暴击随机 + 随机印记获取）。
##
## 三类目标场景（覆盖设计空间端点 + 多目标，公平评估拔刀 AoE）：
##   WALL = 单·不灭木桩(HP999,DEF2)——耐久 boss，永不死，回合末回满。
##   WAVE = 单·复活木桩(HP30,DEF1)——脆弱波次敌，死后回合末复活。
##   PACK = 三·复活木桩簇(围绕主目标正交相邻)——验证拔刀菱形 AoE+溅射的多目标价值。
## 五种打法策略（每回合 ≤1 标准动作，动作经济对齐 → 逐动作可比）：
##   BASE   平推基线：每回合只斩击（资源被动积累但不主动消费）。
##   IAI    攒气-居合（设计意图）：剑气≥居合费用且居合就绪 → 居合，否则斩击。
##   IAI_CD 居合-冷却流（引擎实允）：只看冷却就放居合（忽略剑气门槛）——
##          探针：validate_skill_usage 不强制 qi_cost（资源门槛是否形同虚设）。
##   BADAO  斩击产印记-拔刀倾泻：印记满且剑气够 → 拔刀，否则斩击。
##   GREEDY 贪婪最优混合：能居合先居合，否则能拔刀就拔刀，否则斩击——
##          探针：放开所有手段后是否坍缩成单一最优。
##
## 运行：
##   <Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##     --script res://tests/exp_swordsman_resource_playstyles.gd
##   结果文件：res://tests/_exp_results.md（兼 stdout 末尾 SUMMARY 块）。
##
## headless 工程坑规避：
##   - 逻辑放 _process；不在顶层引用重 class_name（tm/action 用 Object）。
##   - 单帧内不能 queue_free/tween 回收 → 每帧只跑一格(cell)，逐回合即时 free 飘字层，
##     并把 status_icons 置 null 使图标重建变空操作（否则徽章节点 O(N²) 累积崩溃）。

const TRIALS: int = 120
const ROUNDS: int = 14

const SK_ZHANJI: String = "swordsman_zhanji"
const SK_YISHAN: String = "swordsman_yishan"
const SK_ZHAOJIA: String = "swordsman_zhaojia"
const SK_JUHE: String = "swordsman_juhe"
const SK_BADAO: String = "swordsman_badao"
const TRACKED_SKILLS: Array[String] = [SK_ZHANJI, SK_YISHAN, SK_ZHAOJIA, SK_JUHE, SK_BADAO]

var _phase: int = 0
var _done: bool = false
var _scene: Node = null
var _tm: Object = null
var _sword: Unit = null
var _popup_layer: Node = null
var _cells: Array[Dictionary] = []
var _ci: int = 0
var _results: Array[Dictionary] = []
var _out_lines: Array[String] = []
var _juhe_qi_cost: int = 0
var _badao_qi_cost: int = 0


func _initialize() -> void:
	print("=== 实证：剑圣资源打法对照 (TRIALS=%d, ROUNDS=%d) ===" % [TRIALS, ROUNDS])


func _process(_delta: float) -> bool:
	match _phase:
		0:
			if not _setup():
				_finish(1)
				return true
			_phase = 1
			return false
		1:
			if _ci >= _cells.size():
				_phase = 2  # 防止 quit 延迟期内 _process 再次进入导致重复 finalize
				_finalize()
				_finish(0)
				return true
			var cell: Dictionary = _cells[_ci]
			var res: Dictionary = _run_cell(cell)
			res["scenario"] = str(cell["scn"])
			res["policy"] = str(cell["pol"])
			_results.append(res)
			_ci += 1
			return false
	return true


# ── setup ────────────────────────────────────────────────────────

func _setup() -> bool:
	_scene = load("res://scenes/tactical/TacticalScene.tscn").instantiate()
	root.add_child(_scene)
	_tm = _scene.tactical_manager
	if _tm.turn_manager != null:
		_tm.turn_manager.stop()
	_tm.input_state = 2  # ACTION_PHASE
	_popup_layer = _tm.popup_layer

	_sword = _find_unit("swordsman")
	var regen: Unit = _find_unit("test_dummy_regen")
	var revive: Unit = _find_unit("test_dummy_revive")
	if _sword == null or regen == null or revive == null:
		print("[FATAL] 缺单位 sword=%s regen=%s revive=%s" % [_sword, regen, revive])
		return false

	_juhe_qi_cost = int(_tm._get_skill_data(SK_JUHE).get("qi_cost", 0))
	_badao_qi_cost = int(_tm._get_skill_data(SK_BADAO).get("qi_cost", 0))

	# 移除非木桩敌人出格（避免溅射/反击串扰），其格腾空给 PACK 簇用。
	for other_id: String in ["test_lancer", "test_archer", "test_mage"]:
		var other: Unit = _find_unit(other_id)
		if other != null:
			var oc: Object = _tm.grid.get_cell(other.grid_position)
			if oc != null and oc.occupant == other:
				oc.occupant = null

	# PACK 簇：主目标 (4,3) + 正交相邻两枚，剑圣站 (3,3)，拔刀瞄准主目标 → 命中三枚。
	var pack_main: Unit = _tm.spawn_unit("test_dummy_revive", Vector2i(4, 3), "enemy")
	var pack_b: Unit = _tm.spawn_unit("test_dummy_revive", Vector2i(4, 2), "enemy")
	var pack_c: Unit = _tm.spawn_unit("test_dummy_revive", Vector2i(4, 4), "enemy")
	if pack_main == null or pack_b == null or pack_c == null:
		print("[FATAL] PACK 簇生成失败 %s %s %s" % [pack_main, pack_b, pack_c])
		return false

	# 关闭所有相关单位的图标重建（防徽章节点累积 O(N²) 崩溃）。
	for u: Unit in [_sword, regen, revive, pack_main, pack_b, pack_c]:
		u.status_icons = null

	_emit("# 核心战斗循环实证结果 — 剑圣资源打法对照")
	_emit("")
	_emit("TRIALS=%d  ROUNDS=%d  居合剑气费=%d  拔刀剑气费=%d  剑气上限=%d"
		% [TRIALS, ROUNDS, _juhe_qi_cost, _badao_qi_cost, _sword._qi_max])
	_emit("WALL=单·不灭木桩(HP%d DEF%d 永不死)  WAVE=单·复活木桩(HP%d DEF%d 每回合复活)  PACK=三·复活木桩簇"
		% [regen.stats.max_hp, regen.stats.def_attr, revive.stats.max_hp, revive.stats.def_attr])
	_emit("")

	var scenarios: Array[Dictionary] = [
		{"name": "WALL", "targets": [regen] as Array[Unit], "primary": regen, "killable": false},
		{"name": "WAVE", "targets": [revive] as Array[Unit], "primary": revive, "killable": true},
		{"name": "PACK", "targets": [pack_main, pack_b, pack_c] as Array[Unit],
			"primary": pack_main, "killable": true},
	]
	var policies: Array[String] = ["BASE", "IAI", "IAI_CD", "BADAO", "GREEDY"]
	for sc: Dictionary in scenarios:
		for pol: String in policies:
			_cells.append({
				"scn": str(sc["name"]), "pol": pol,
				"targets": sc["targets"], "primary": sc["primary"],
				"killable": bool(sc["killable"]),
			})
	return true


# ── 单格运行 ──────────────────────────────────────────────────────

func _run_cell(cell: Dictionary) -> Dictionary:
	var targets: Array[Unit] = cell["targets"]
	var primary: Unit = cell["primary"]
	var policy: String = str(cell["pol"])
	_place_adjacent(_sword, primary)

	var sum_dmg: float = 0.0
	var sumsq_dmg: float = 0.0
	var sum_entropy: float = 0.0
	var sum_qi_start: float = 0.0
	var capped_rounds: int = 0
	var wasted_qi: int = 0
	var wasted_marks: int = 0
	var dumps: int = 0
	var kills: int = 0
	var juhe_kills: int = 0
	var skill_counts: Dictionary = {}
	var skill_dmg: Dictionary = {}
	for sid: String in TRACKED_SKILLS:
		skill_counts[sid] = 0
		skill_dmg[sid] = 0.0
	var round_samples: int = TRIALS * ROUNDS

	for t: int in range(TRIALS):
		seed(t)
		_trial_reset(targets)
		var trial_dmg: float = 0.0
		var trial_counts: Dictionary = {}
		for sid: String in TRACKED_SKILLS:
			trial_counts[sid] = 0

		for r: int in range(ROUNDS):
			_reset_round()
			var qi0: int = _sword.sword_qi
			sum_qi_start += float(qi0)
			if qi0 >= _sword._qi_max:
				capped_rounds += 1
			var marks_full_before: bool = _sword.is_marks_full()

			var skill: String = _choose_skill(policy)
			if skill == SK_ZHANJI:
				if qi0 >= _sword._qi_max:
					wasted_qi += 1
				if marks_full_before:
					wasted_marks += 1

			# 多目标快照（命中前 HP + 存活）
			var hp_before: Array[int] = []
			var alive_before: Array[bool] = []
			for tg: Unit in targets:
				hp_before.append(tg.stats.hp)
				alive_before.append(tg.stats.is_alive())

			_tm._selected_skill_id = skill
			var action: Object = _tm._build_skill_action(_sword, primary.grid_position, primary)
			if action == null:
				continue
			var ok: bool = _tm._execute_skill_action(action)
			_clear_popups()
			if not ok:
				continue

			var action_dmg: int = 0
			var primary_killed_now: bool = false
			for i: int in range(targets.size()):
				var tg: Unit = targets[i]
				var hp_after: int = tg.stats.hp
				action_dmg += maxi(0, hp_before[i] - maxi(0, hp_after))
				if alive_before[i] and not tg.stats.is_alive():
					kills += 1
					if tg == primary:
						primary_killed_now = true
			trial_dmg += float(action_dmg)
			trial_counts[skill] = int(trial_counts[skill]) + 1
			skill_dmg[skill] = float(skill_dmg[skill]) + float(action_dmg)
			if skill == SK_JUHE or skill == SK_BADAO:
				dumps += 1
			if skill == SK_JUHE and primary_killed_now:
				juhe_kills += 1

			_restore_targets(targets)

		sum_dmg += trial_dmg
		sumsq_dmg += trial_dmg * trial_dmg
		sum_entropy += _entropy(trial_counts)
		for sid: String in TRACKED_SKILLS:
			skill_counts[sid] = int(skill_counts[sid]) + int(trial_counts[sid])

	var mean_dmg: float = sum_dmg / float(TRIALS)
	var var_dmg: float = maxf(0.0, sumsq_dmg / float(TRIALS) - mean_dmg * mean_dmg)
	return {
		"total_dmg_mean": mean_dmg,
		"total_dmg_std": sqrt(var_dmg),
		"dmg_per_round": mean_dmg / float(ROUNDS),
		"entropy_mean": sum_entropy / float(TRIALS),
		"avg_qi_start": sum_qi_start / float(round_samples),
		"capped_qi_frac": float(capped_rounds) / float(round_samples),
		"wasted_qi_per_trial": float(wasted_qi) / float(TRIALS),
		"wasted_marks_per_trial": float(wasted_marks) / float(TRIALS),
		"dumps_per_trial": float(dumps) / float(TRIALS),
		"kills_per_trial": float(kills) / float(TRIALS),
		"juhe_kills_per_trial": float(juhe_kills) / float(TRIALS),
		"skill_counts": skill_counts,
		"skill_dmg": skill_dmg,
	}


# ── 策略 ─────────────────────────────────────────────────────────

func _choose_skill(policy: String) -> String:
	match policy:
		"BASE":
			return SK_ZHANJI
		"IAI":
			if _sword.sword_qi >= _juhe_qi_cost and _sword.is_skill_available(SK_JUHE):
				return SK_JUHE
			return SK_ZHANJI
		"IAI_CD":
			if _sword.is_skill_available(SK_JUHE):
				return SK_JUHE
			return SK_ZHANJI
		"BADAO":
			if _sword.is_marks_full() and _sword.sword_qi >= _badao_qi_cost \
					and _sword.is_skill_available(SK_BADAO):
				return SK_BADAO
			return SK_ZHANJI
		"GREEDY":
			if _sword.sword_qi >= _juhe_qi_cost and _sword.is_skill_available(SK_JUHE):
				return SK_JUHE
			if _sword.is_marks_full() and _sword.sword_qi >= _badao_qi_cost \
					and _sword.is_skill_available(SK_BADAO):
				return SK_BADAO
			return SK_ZHANJI
	return SK_ZHANJI


# ── 工具 ─────────────────────────────────────────────────────────

func _reset_round() -> void:
	_sword.reset_action_resources()
	_sword._tick_skill_cooldowns()
	_sword.stats.hp = _sword.stats.max_hp  # 保活攻击者（消除反击致死噪音）


func _entropy(counts: Dictionary) -> float:
	var total: int = 0
	for sid: String in counts.keys():
		total += int(counts[sid])
	if total <= 0:
		return 0.0
	var h: float = 0.0
	for sid: String in counts.keys():
		var n: int = int(counts[sid])
		if n <= 0:
			continue
		var p: float = float(n) / float(total)
		h -= p * (log(p) / log(2.0))
	return h


func _trial_reset(targets: Array[Unit]) -> void:
	_sword.skill_cooldowns.clear()
	_sword.set_sword_qi(0)
	_sword.clear_marks()
	_sword.reset_action_resources()
	_sword.stats.hp = _sword.stats.max_hp
	_restore_targets(targets)


func _restore_targets(targets: Array[Unit]) -> void:
	for tg: Unit in targets:
		tg.stats.hp = tg.stats.max_hp
		var cell: Object = _tm.grid.get_cell(tg.grid_position)
		if cell != null and cell.occupant == null:
			cell.occupant = tg


func _clear_popups() -> void:
	if _popup_layer == null:
		return
	for child: Node in _popup_layer.get_children():
		child.free()


func _find_unit(uid: String) -> Unit:
	for u: Unit in _tm.units:
		if u.unit_id == uid:
			return u
	return null


func _find_empty_neighbor(origin: Vector2i) -> Vector2i:
	for nb: Vector2i in _tm.grid.get_neighbors(origin):
		var c: Object = _tm.grid.get_cell(nb)
		if c != null and c.is_passable() and c.occupant == null:
			return nb
	return Vector2i(-1, -1)


func _place_adjacent(mover: Unit, target: Unit) -> void:
	var dest: Vector2i = _find_empty_neighbor(target.grid_position)
	if dest == Vector2i(-1, -1):
		return
	var old_cell: Object = _tm.grid.get_cell(mover.grid_position)
	if old_cell != null and old_cell.occupant == mover:
		old_cell.occupant = null
	_tm.grid.place_unit(mover, dest)


# ── 输出 ─────────────────────────────────────────────────────────

func _emit(line: String) -> void:
	_out_lines.append(line)


func _finalize() -> void:
	_emit("## 汇总表")
	_emit("")
	_emit("| 场景 | 策略 | 总伤害 | ±std | 每回合 | 动作熵 | 均剑气 | 满气% | 浪费气/局 | 浪费印/局 | 倾泻/局 | 击杀/局 | 居合杀/局 |")
	_emit("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
	for c: Dictionary in _results:
		_emit("| %s | %s | %.1f | %.1f | %.1f | %.2f | %.1f | %d%% | %.2f | %.2f | %.2f | %.2f | %.2f |" % [
			str(c["scenario"]), str(c["policy"]),
			float(c["total_dmg_mean"]), float(c["total_dmg_std"]),
			float(c["dmg_per_round"]), float(c["entropy_mean"]),
			float(c["avg_qi_start"]), int(round(float(c["capped_qi_frac"]) * 100.0)),
			float(c["wasted_qi_per_trial"]), float(c["wasted_marks_per_trial"]),
			float(c["dumps_per_trial"]), float(c["kills_per_trial"]),
			float(c["juhe_kills_per_trial"]),
		])
	_emit("")
	_emit("## 技能使用分布（次数合计 / 伤害占比）")
	_emit("")
	_emit("| 场景 | 策略 | 斩击 | 居合 | 拔刀 | 居合伤% | 拔刀伤% | 斩击伤% |")
	_emit("|---|---|---:|---:|---:|---:|---:|---:|")
	for c: Dictionary in _results:
		var sc_counts: Dictionary = c["skill_counts"]
		var sc_dmg: Dictionary = c["skill_dmg"]
		var tot_dmg: float = 0.0
		for sid: String in TRACKED_SKILLS:
			tot_dmg += float(sc_dmg[sid])
		_emit("| %s | %s | %d | %d | %d | %d%% | %d%% | %d%% |" % [
			str(c["scenario"]), str(c["policy"]),
			int(sc_counts[SK_ZHANJI]), int(sc_counts[SK_JUHE]), int(sc_counts[SK_BADAO]),
			int(round(_share(sc_dmg, SK_JUHE, tot_dmg))),
			int(round(_share(sc_dmg, SK_BADAO, tot_dmg))),
			int(round(_share(sc_dmg, SK_ZHANJI, tot_dmg))),
		])
	_emit("")
	_emit("## DATA")
	for c: Dictionary in _results:
		_emit("DATA|scn=%s|pol=%s|dmg=%.2f|std=%.2f|dpr=%.2f|ent=%.3f|qi=%.2f|capped=%.3f|wqi=%.2f|wmk=%.2f|dump=%.2f|kill=%.2f|jkill=%.2f" % [
			str(c["scenario"]), str(c["policy"]),
			float(c["total_dmg_mean"]), float(c["total_dmg_std"]),
			float(c["dmg_per_round"]), float(c["entropy_mean"]),
			float(c["avg_qi_start"]), float(c["capped_qi_frac"]),
			float(c["wasted_qi_per_trial"]), float(c["wasted_marks_per_trial"]),
			float(c["dumps_per_trial"]), float(c["kills_per_trial"]),
			float(c["juhe_kills_per_trial"]),
		])
	_write_results_file()


func _share(sc_dmg: Dictionary, sid: String, total: float) -> float:
	if total <= 0.0:
		return 0.0
	return float(sc_dmg[sid]) / total * 100.0


func _write_results_file() -> void:
	var f: FileAccess = FileAccess.open("res://tests/_exp_results.md", FileAccess.WRITE)
	if f == null:
		print("[WARN] 无法写结果文件 res://tests/_exp_results.md")
		return
	for line: String in _out_lines:
		f.store_line(line)
	f.close()


func _finish(code: int) -> void:
	if _done:
		return
	_done = true
	print("\n===SUMMARY_BEGIN===")
	for line: String in _out_lines:
		print(line)
	print("===SUMMARY_END===")
	if is_instance_valid(_scene):
		_scene.free()
	quit(code)
