extends SceneTree
## 回忆升级入口回归（gameplay-impl PR5，差距清单 M10）。
##
##   ① 数据：11 张回忆逐条对照设计库 762393b（基础技能、升级技能、形态组）。
##   ② 升级技能尚未实装时拒绝兑现，单位保持不变。
##   ③ 兑现：槽位原位替换、技能身份（R2.5）、冷却转移、被动〔心眼〕的升级、多形态的身份。
##   ④ 硬约束（KB 天赋设计要点 §12）：一个技能一局只升级一次、同职业、禁止链式升级，
##      以及未知回忆、不是回忆、单位没有基础技能、形态的 upgrade_of 不符。每条拒绝都确认单位没变。
##   ⑤ R2.5 槽位替换：〔拔刀〕升级为〔满月〕后，〔招架〕槽换出来的是〔满月〕。
##   ⑥ 入口：GameAction.make_apply_memory 只带可序列化的 id；TacticalManager.request_apply_memory
##      不消耗行动资源；为技能选目标途中、动作结算途中拒绝。
##   ⑦ 带进战斗：RunState 规整 memories、BattleAssembler 转交、TacticalScene 注入时兑现。
##
## 升级技能的 JSON 随下一个 PR（回忆技能六组）实装。这里在测试进程里装夹具技能代替：
## 基础技能的副本，换 id 并写上 upgrade_of；〔心眼〕没有技能文件，夹具只有 id 与 upgrade_of。
##
## 运行：<Godot_console.exe> --headless --path <Ship> --script res://tests/test_memory_upgrades.gd
## 退出码 0=全过，1=有失败。

const UNIT_SCENE := "res://scenes/tactical/Unit.tscn"
const RunStateScript := preload("res://scripts/roguelite/run_state.gd")
const AssemblerScript := preload("res://scripts/roguelite/battle_assembler.gd")
const MemoryUpgradesScript := preload("res://scripts/units/memory_upgrades.gd")

## 设计库 762393b：回忆 id → [基础技能, 形态（第一个是 upgrade_skill_id）]。写死在这里，
## 让「镜像抄错」也能被测出来。
const EXPECTED: Dictionary = {
	"kensei_huajianweiqi": ["kensei_zhanji", ["kensei_liekong"]],
	"kensei_yiguzuoqi": ["kensei_zhanji", ["kensei_yijue"]],
	"kensei_tuodaoji": ["kensei_yishan", ["kensei_huizhan"]],
	"kensei_houfazhiren": ["kensei_zhaojia", ["kensei_jieli"]],
	"kensei_shihuo": ["kensei_zhaojia", ["kensei_qiefan"]],
	"kensei_guzhuyizhi": ["kensei_badao", ["kensei_dashangduan"]],
	"kensei_huazhengweiling": ["kensei_badao", ["kensei_sanduanzhan", "kensei_huitian", "kensei_batian"]],
	"kensei_xinwupangwu": ["kensei_xinyan", ["kensei_xinyan_cheng"]],
	"kensei_xinyanche": ["kensei_xinyan", ["kensei_xinyan_che", "kensei_kongxiangjian"]],
	"kensei_juhe_xushi": ["kensei_juhe", ["kensei_linmo", "kensei_diandao"]],
	"kensei_juhe_yinyang": ["kensei_juhe", ["kensei_taiyangjian", "kensei_taiyinjian"]],
}

var _pass: int = 0
var _fail: int = 0
var _fails: Array[String] = []


func _initialize() -> void:
	print("=== test_memory_upgrades（回忆升级入口）===")
	_run.call_deferred()


func _run() -> void:
	var dl: Node = root.get_node("DataLoader")
	# 没装夹具的技能表：用来测「升级技能尚未实装」。先去掉全部形态 id，免得日后
	# 升级技能实装后这一组变成测不到东西。
	var skills_without: Dictionary = (dl.skills as Dictionary).duplicate()
	for memory_id: String in EXPECTED.keys():
		for form_id: Variant in EXPECTED[memory_id][1]:
			skills_without.erase(str(form_id))
	_install_fixtures(dl)

	_test_data(dl)
	_test_script_attach()
	_test_missing_upgrade_skill(dl, skills_without)
	_test_apply(dl)
	_test_constraints(dl)
	_test_slot_swap(dl)
	_test_game_action()
	await _test_tactical_entry()
	_test_run_carry()
	await _test_injected_spawn()

	print("\n--- 结果：%d 过 / %d 失败 ---" % [_pass, _fail])
	if _fail > 0:
		print("失败项：")
		for f: String in _fails:
			print("  ✗ " + f)
	quit(0 if _fail == 0 else 1)


# ── 夹具 ─────────────────────────────────────────────

## 每个形态装一份夹具：有基础技能文件的复制它，没有的（心眼）只给 id 与 upgrade_of。
## 已经存在的 id 不覆盖（升级技能实装后就用真数据）。
func _install_fixtures(dl: Node) -> void:
	for memory_id: String in EXPECTED.keys():
		var base_id: String = str(EXPECTED[memory_id][0])
		for form_v: Variant in EXPECTED[memory_id][1]:
			var form_id: String = str(form_v)
			if (dl.skills as Dictionary).has(form_id):
				continue
			var fixture: Dictionary = {}
			if (dl.skills as Dictionary).has(base_id):
				fixture = (dl.skills[base_id] as Dictionary).duplicate(true)
			fixture["id"] = form_id
			fixture["name"] = form_id
			fixture["upgrade_of"] = base_id
			dl.skills[form_id] = fixture


func _make_unit(class_id: String) -> Unit:
	var u: Unit = load(UNIT_SCENE).instantiate()
	root.add_child(u)
	u.setup(root.get_node("DataLoader").classes[class_id])
	return u


# ── ① 数据 ───────────────────────────────────────────

func _test_data(dl: Node) -> void:
	print("\n[①] data/memories 镜像设计库 762393b")
	var memories: Dictionary = dl.memories
	_eq("回忆共 11 张", memories.size(), 11)
	for memory_id: String in EXPECTED.keys():
		var m: Dictionary = memories.get(memory_id, {})
		_check("%s 已装载" % memory_id, not m.is_empty())
		_eq("%s 基础技能" % memory_id, str(m.get("base_skill_id", "")), str(EXPECTED[memory_id][0]))
		_eq("%s 升级技能" % memory_id, str(m.get("upgrade_skill_id", "")), str(EXPECTED[memory_id][1][0]))
		_eq("%s 形态组" % memory_id, str(m.get("form_skill_ids", [])), str(EXPECTED[memory_id][1]))
		_eq("%s 职业" % memory_id, str(m.get("class_id", "")), "kensei")
		_eq("%s 稀有度" % memory_id, str(m.get("rarity", "")), "回忆")
	var kensei_skills: Array = (dl.classes["kensei"] as Dictionary).get("skill_ids", [])
	for memory_id: String in EXPECTED.keys():
		var base_id: String = str(EXPECTED[memory_id][0])
		_check("%s 的基础技能属于剑圣（技能栏或心眼）" % memory_id,
			kensei_skills.has(base_id) or base_id == str(dl.classes["kensei"].get("passive_skill_id", "")))
	_check("阴阳剑登记了未接的前置（Q9）",
		str((memories.get("kensei_juhe_yinyang", {}) as Dictionary).get("_prerequisite_unwired", "")).contains("二天一流"))


func _test_script_attach() -> void:
	print("\n[①'] 脚本挂载")
	var u: Unit = _make_unit("kensei")
	_check("Unit 脚本已挂载", u.get_script() != null)
	_eq("Unit 脚本路径", (u.get_script() as Script).resource_path, "res://scripts/units/unit.gd")
	_check("单位持有回忆记录", u.memory_upgrades != null)
	_eq("回忆记录的脚本路径", (u.memory_upgrades.get_script() as Script).resource_path,
		"res://scripts/units/memory_upgrades.gd")
	u.free()


# ── ② 升级技能尚未实装 ─────────────────────────────

func _test_missing_upgrade_skill(dl: Node, skills_without: Dictionary) -> void:
	print("\n[②] 升级技能尚未实装时拒绝")
	var u: Unit = _make_unit("kensei")
	var before: String = str(u.skill_ids)
	var r: Dictionary = u.apply_memory("kensei_huajianweiqi", dl.memories, skills_without)
	_check("拒绝兑现", not bool(r.get("ok", true)))
	_check("原因写明升级技能尚未实装", str(r.get("reason", "")).contains("尚未实装"), str(r.get("reason", "")))
	_eq("技能栏不变", str(u.skill_ids), before)
	_eq("没有记下回忆", u.memory_upgrades.get_memory_ids().size(), 0)
	# 多形态回忆：第一个形态已实装、其余没有，也要拒绝（不允许只兑现一半）。
	var partial: Dictionary = skills_without.duplicate()
	partial["kensei_sanduanzhan"] = dl.skills["kensei_sanduanzhan"]
	var r2: Dictionary = u.apply_memory("kensei_huazhengweiling", dl.memories, partial)
	_check("多形态只实装一个时拒绝", not bool(r2.get("ok", true))
		and str(r2.get("reason", "")).contains("kensei_huitian"), str(r2.get("reason", "")))
	_eq("技能栏仍不变", str(u.skill_ids), before)
	u.free()


# ── ③ 兑现 ───────────────────────────────────────────

func _test_apply(dl: Node) -> void:
	print("\n[③] 兑现：原位替换、身份、冷却、被动、多形态")
	var u: Unit = _make_unit("kensei")
	var zhanji_index: int = u.skill_ids.find("kensei_zhanji")
	_check("前提：剑圣有斩击", zhanji_index >= 0)
	var r: Dictionary = u.apply_memory("kensei_huajianweiqi")
	_check("化剑为气兑现成功", bool(r.get("ok", false)), str(r.get("reason", "")))
	_eq("斩击原位换成裂空", u.skill_ids[zhanji_index], "kensei_liekong")
	_check("技能栏里不再有斩击", not u.skill_ids.has("kensei_zhanji"))
	_eq("技能栏仍是 5 个", u.skill_ids.size(), 5)
	_eq("裂空的技能身份是斩击（R2.5）", u.get_skill_identity("kensei_liekong"), "kensei_zhanji")
	_eq("未升级技能的身份是它自己", u.get_skill_identity("kensei_juhe"), "kensei_juhe")
	_eq("斩击现在解析为裂空", u.memory_upgrades.resolve("kensei_zhanji"), "kensei_liekong")
	_eq("记下的回忆", str(u.memory_upgrades.get_memory_ids()), str(["kensei_huajianweiqi"]))

	# 冷却转移：战斗中途升级，基础技能剩余的冷却交给升级技能。
	u.skill_cooldowns["kensei_yishan"] = 2
	_check("如影随形兑现成功", bool(u.apply_memory("kensei_tuodaoji").get("ok", false)))
	_eq("踏影接过一闪剩余的冷却", u.get_skill_cooldown("kensei_huizhan"), 2)
	_check("一闪的冷却条目已移除", not u.skill_cooldowns.has("kensei_yishan"))

	# 被动心眼的升级：passive_skill_id 换掉，技能栏不变。
	var bar_before: String = str(u.skill_ids)
	_check("心无旁骛兑现成功", bool(u.apply_memory("kensei_xinwupangwu").get("ok", false)))
	_eq("心眼换成心眼·澄", u.passive_skill_id, "kensei_xinyan_cheng")
	_eq("技能栏不受心眼升级影响", str(u.skill_ids), bar_before)
	_eq("心眼·澄的身份是心眼", u.get_skill_identity("kensei_xinyan_cheng"), "kensei_xinyan")
	u.free()

	# 多形态：三个形态都以拔刀为身份；槽位上放的是 upgrade_skill_id（决心）。
	var v: Unit = _make_unit("kensei")
	var badao_index: int = v.skill_ids.find("kensei_badao")
	_check("兵无常势兑现成功", bool(v.apply_memory("kensei_huazhengweiling").get("ok", false)))
	_eq("拔刀原位换成决心", v.skill_ids[badao_index], "kensei_sanduanzhan")
	for form_id: String in ["kensei_sanduanzhan", "kensei_huitian", "kensei_batian"]:
		_eq("%s 的身份是拔刀" % form_id, v.get_skill_identity(form_id), "kensei_badao")
	v.free()

	# setup 会清空回忆记录（新单位从头来）。
	var w: Unit = _make_unit("kensei")
	w.apply_memory("kensei_huajianweiqi")
	w.setup(dl.classes["kensei"])
	_eq("重新 setup 后没有回忆", w.memory_upgrades.get_memory_ids().size(), 0)
	_check("重新 setup 后斩击回来了", w.skill_ids.has("kensei_zhanji"))
	w.free()


# ── ④ 硬约束 ─────────────────────────────────────────

func _test_constraints(dl: Node) -> void:
	print("\n[④] 硬约束：每条拒绝都不改单位")
	var u: Unit = _make_unit("kensei")
	_check("前提：化剑为气兑现成功", bool(u.apply_memory("kensei_huajianweiqi").get("ok", false)))

	_reject(u, "kensei_yiguzuoqi", {}, {}, "只能升级一次", "斩击已被化剑为气升级，疾风骤雨被拒")
	_reject(u, "kensei_huajianweiqi", {}, {}, "只能升级一次", "同一张回忆不能兑现两次")
	_reject(u, "kensei_no_such_memory", {}, {}, "未知的回忆", "未知回忆")

	var memories: Dictionary = (dl.memories as Dictionary).duplicate(true)
	var skills: Dictionary = (dl.skills as Dictionary).duplicate()
	# 链式升级：以裂空（已经是升级技能）为基础。
	memories["test_chain"] = {"id": "test_chain", "rarity": "回忆", "class_id": "kensei",
		"base_skill_id": "kensei_liekong", "upgrade_skill_id": "test_chain_up",
		"form_skill_ids": ["test_chain_up"]}
	skills["test_chain_up"] = {"id": "test_chain_up", "upgrade_of": "kensei_liekong"}
	_reject(u, "test_chain", memories, skills, "禁止链式升级", "以已兑现的升级技能为基础")
	var fresh: Unit = _make_unit("kensei")
	_reject(fresh, "test_chain", memories, skills, "禁止链式升级",
		"以带 upgrade_of 的技能为基础（未兑现过也拒绝）")
	fresh.free()
	# 不是回忆天赋。
	memories["test_not_memory"] = (memories["kensei_tuodaoji"] as Dictionary).duplicate(true)
	memories["test_not_memory"]["id"] = "test_not_memory"
	memories["test_not_memory"]["rarity"] = "史诗"
	_reject(u, "test_not_memory", memories, skills, "不是回忆", "稀有度不是回忆")
	# 单位没有基础技能。
	memories["test_not_owned"] = {"id": "test_not_owned", "rarity": "回忆", "class_id": "kensei",
		"base_skill_id": "kensei_not_owned", "upgrade_skill_id": "test_not_owned_up",
		"form_skill_ids": ["test_not_owned_up"]}
	skills["test_not_owned_up"] = {"id": "test_not_owned_up", "upgrade_of": "kensei_not_owned"}
	_reject(u, "test_not_owned", memories, skills, "没有基础技能", "单位没有这个基础技能")
	# 形态的 upgrade_of 不指向基础技能。
	var wrong: Dictionary = skills.duplicate()
	wrong["kensei_huizhan"] = (skills["kensei_huizhan"] as Dictionary).duplicate(true)
	wrong["kensei_huizhan"]["upgrade_of"] = "kensei_zhanji"
	_reject(u, "kensei_tuodaoji", memories, wrong, "upgrade_of", "升级技能的 upgrade_of 不符")
	u.free()

	# 职业不符：剑士兑现剑圣回忆。
	var m: Unit = _make_unit("myrmidon")
	_reject(m, "kensei_huajianweiqi", {}, {}, "职业不符", "剑士不能兑现剑圣回忆")
	m.free()


## 断言拒绝、原因含 expect，且技能栏、被动、冷却、回忆记录都没变。
func _reject(u: Unit, memory_id: String, memories: Dictionary, skills: Dictionary,
		expect: String, label: String) -> void:
	var bar: String = str(u.skill_ids)
	var passive: String = u.passive_skill_id
	var cds: String = str(u.skill_cooldowns)
	var ids: String = str(u.memory_upgrades.get_memory_ids())
	var r: Dictionary = u.apply_memory(memory_id, memories, skills)
	_check(label + "：拒绝且原因含「%s」" % expect,
		not bool(r.get("ok", true)) and str(r.get("reason", "")).contains(expect), str(r.get("reason", "")))
	_check(label + "：单位没变", str(u.skill_ids) == bar and u.passive_skill_id == passive
		and str(u.skill_cooldowns) == cds and str(u.memory_upgrades.get_memory_ids()) == ids)


# ── ⑤ R2.5 槽位替换 ─────────────────────────────────

func _test_slot_swap(dl: Node) -> void:
	print("\n[⑤] 拔刀升级为满月后，招架槽换出来的是满月（R2.5）")
	var zj: Dictionary = dl.skills["kensei_zhaojia"]
	var trig: String = str(zj.get("slot_swap_trigger", ""))
	var tgt: String = str(zj.get("slot_swap_target", ""))
	var req: Dictionary = zj.get("slot_swap_requires", {})
	var u: Unit = _make_unit("kensei")
	u.set_sword_qi(20)
	u.marks["心"] = true
	u.marks["道"] = true
	u.marks["势"] = true
	_eq("对照：升级前换出来的是拔刀", u.get_visible_skill_id("kensei_zhaojia", trig, tgt, req), "kensei_badao")
	_check("鞘之内兑现成功", bool(u.apply_memory("kensei_guzhuyizhi").get("ok", false)))
	_eq("升级后换出来的是满月", u.get_visible_skill_id("kensei_zhaojia", trig, tgt, req), "kensei_dashangduan")
	u.skill_cooldowns["kensei_dashangduan"] = 1
	_eq("满月冷却中时保持招架（R3.6）", u.get_visible_skill_id("kensei_zhaojia", trig, tgt, req), "kensei_zhaojia")
	u.free()


# ── ⑥ 入口 ───────────────────────────────────────────

func _test_game_action() -> void:
	print("\n[⑥] GameAction.make_apply_memory")
	var u: Unit = _make_unit("kensei")
	var a: GameAction = GameAction.make_apply_memory(u, "kensei_huajianweiqi")
	_eq("动作类型", a.type, GameAction.Type.APPLY_MEMORY)
	_check("动作者", a.actor == u)
	_eq("data 只带 id", str(a.data), str({"actor_id": "kensei", "memory_id": "kensei_huajianweiqi"}))
	_eq("data 可经 JSON 往返", str(JSON.parse_string(JSON.stringify(a.data))), str(a.data))
	u.free()


func _test_tactical_entry() -> void:
	print("\n[⑥'] TacticalManager.request_apply_memory")
	var scene: Node = load("res://scenes/tactical/TacticalScene.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var tm: Object = scene.tactical_manager
	var sword: Unit = null
	for unit: Unit in tm.units:
		if unit.unit_id == "kensei":
			sword = unit
	_check("场景中有剑圣", sword != null)
	if sword == null:
		scene.free()
		return
	sword.standard_used = false
	sword.movement_used = false
	sword.swift_used = false
	var r: Dictionary = tm.request_apply_memory(sword, "kensei_huajianweiqi")
	_check("兑现成功", bool(r.get("ok", false)), str(r.get("reason", "")))
	_check("剑圣技能栏有裂空", sword.skill_ids.has("kensei_liekong"))
	_check("不消耗行动资源", not sword.standard_used and not sword.movement_used and not sword.swift_used)
	var bad: Dictionary = tm.request_apply_memory(sword, "kensei_yiguzuoqi")
	_check("违反约束时 TacticalManager 也拒绝", not bool(bad.get("ok", true)))
	var saved_unit: Unit = tm.current_unit
	var saved_state: int = tm.input_state
	tm.current_unit = sword
	tm.input_state = 3  # InputState.SKILL_TARGETING
	var busy: Dictionary = tm.request_apply_memory(sword, "kensei_tuodaoji")
	_check("为技能选目标途中拒绝", not bool(busy.get("ok", true))
		and str(busy.get("reason", "")).contains("选择目标"), str(busy.get("reason", "")))
	_check("拒绝后一闪还在", sword.skill_ids.has("kensei_yishan"))
	tm.input_state = 6  # InputState.ANIMATING
	var animating: Dictionary = tm.request_apply_memory(sword, "kensei_tuodaoji")
	_check("动作结算中拒绝", not bool(animating.get("ok", true))
		and str(animating.get("reason", "")).contains("结算中"), str(animating.get("reason", "")))
	_check("结算中拒绝后一闪还在", sword.skill_ids.has("kensei_yishan"))
	tm.input_state = saved_state
	tm.current_unit = saved_unit
	var wrong_type: GameAction = GameAction.make_end_turn(sword)
	_check("不是回忆动作时拒绝", not bool(tm._execute_apply_memory(wrong_type).get("ok", true)))
	scene.free()


# ── ⑦ 带进战斗 ───────────────────────────────────────

func _test_run_carry() -> void:
	print("\n[⑦] RunState 与 BattleAssembler 带上回忆")
	var member: Dictionary = RunStateScript.normalize_member(
		{"class_id": "kensei", "level": 3, "max_hp": 20, "memories": ["kensei_huajianweiqi", "kensei_shihuo"]})
	_eq("RunState 规整保留回忆", str(member.get("memories", [])), str(["kensei_huajianweiqi", "kensei_shihuo"]))
	var plain: Dictionary = RunStateScript.normalize_member({"class_id": "kensei"})
	_check("没写回忆时不加字段（旧存档形状不变）", not plain.has("memories"))
	var map_data: Dictionary = {"player_spawns": [[0, 2], [0, 3]]}
	var units: Array = AssemblerScript._build_player_units(map_data, [member, plain])
	_eq("装配出两名成员", units.size(), 2)
	if units.size() == 2:
		_eq("第一名带上回忆", str((units[0] as Dictionary).get("memories", [])), str(member["memories"]))
		_check("第二名没有回忆字段", not (units[1] as Dictionary).has("memories"))


func _test_injected_spawn() -> void:
	print("\n[⑦'] TacticalScene 注入时兑现回忆")
	var scene: Node = (load("res://scenes/tactical/TacticalScene.tscn") as PackedScene).instantiate()
	scene.run_injected = true
	scene.injected_map_id = "test_arena"
	scene.injected_player_units = [
		{"class_id": "kensei", "pos": Vector2i(1, 2), "memories": ["kensei_huajianweiqi", "kensei_yiguzuoqi"]},
	]
	scene.injected_enemy_units = [{"class_id": "test_lancer", "pos": Vector2i(5, 2)}]
	scene.debug_harness_enabled = false
	root.add_child(scene)
	await process_frame
	await process_frame
	var sword: Unit = null
	for unit: Unit in scene.tactical_manager.units:
		if unit.unit_id == "kensei":
			sword = unit
	_check("注入的剑圣已生成", sword != null)
	if sword != null:
		_check("第一张回忆已兑现（裂空）", sword.skill_ids.has("kensei_liekong"))
		_check("冲突的第二张被拒（没有连斩）", not sword.skill_ids.has("kensei_yijue"))
		_eq("只记下第一张", str(sword.memory_upgrades.get_memory_ids()), str(["kensei_huajianweiqi"]))
	scene.queue_free()
	await process_frame


# ── 工具 ─────────────────────────────────────────────

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
