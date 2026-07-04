extends SceneTree
## 固定商店 v0 headless 逻辑回归测试 —— 2026-07-04（任务 #7）
##
## 覆盖 RunManager 商店层（纯经济，不占门不占关，不碰战斗）：
##   1. is_shop_prep 判定：驱动到「stage4 打完的 Prep」= 真、「stage7 Boss 前 Prep」= 真；
##      stage2/3/5/6 打完的 Prep = 假（商店只固定插入两处）。
##   2. get_shop_stock：商店 Prep 非空、每件 price>0、kind/ref_id/name 合法；
##      同一 Prep 稳定（两次调用一致）；非商店 Prep 返回空。
##   3. buy_item：gold 足 → 扣减 + 入 convoy；gold 不足 → 拒绝不扣；同件买后从库存移除。
##   4. sell_item：gold 增 + 出 convoy；无该 item → false。
##   5. 金币守恒：buy 后 sell 回收 sell_ratio（gold 净变 = -买价 + roundi(买价×比例)）。
##   6. 价格从 config 读：改 config 价格 → stock 价格随之变（同种子同库存，价格按比例）。
##
## 坑规避（--script 三大坑）：逻辑放 _process 首帧；preload 不用 class_name；
## DataLoader 手动 load_all()。
##
## 运行：<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus \
##   --script res://tests/test_shop_flow.gd
## 退出码 0=全过，1=有失败。

const ACT_CONFIG_FILE: String = "res://data/runloop/act1_config.json"
const RUN_CONFIG_FILE: String = "res://data/runloop/run_config.json"
const DATA_LOADER_SCRIPT: String = "res://scripts/data/data_loader.gd"

const RunManagerScript: GDScript = preload("res://scripts/roguelite/run_manager.gd")

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


func _initialize() -> void:
	print("=== test_shop_flow (固定商店 v0：判定 / 库存 / 买卖 / 守恒) ===")


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

	_test_is_shop_prep()
	_test_get_stock()
	_test_buy()
	_test_sell()
	_test_gold_conservation()
	_test_price_from_config()

	_finish()


# ── 环境加载 ─────────────────────────────────────────

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

	# 前置：act_config.shop 存在（供 is_shop_prep / 定价）
	_check("act_config.shop 为 Dictionary", _act_config.get("shop") is Dictionary)
	var fs_v: Variant = (_act_config.get("door_gen") as Dictionary).get("fixed_shops") \
		if _act_config.get("door_gen") is Dictionary else null
	_check("door_gen.fixed_shops 为 Dictionary", fs_v is Dictionary)

	var dl: Object = load(DATA_LOADER_SCRIPT).new()
	dl.load_all()
	_pools = {
		"equipment": dl.equipment,
		"relics": dl.relics,
		"waves": dl.waves,
		"maps": dl.maps,
		"events": dl.events,
	}
	_check("data_pools.equipment 非空", not (dl.equipment as Dictionary).is_empty())
	_check("data_pools.relics 非空", not (dl.relics as Dictionary).is_empty())

	_roster = [
		{ "class_id": "swordsman", "level": 1, "max_hp": 30 },
		{ "class_id": "knight", "level": 1, "max_hp": 34 },
		{ "class_id": "archer", "level": 1, "max_hp": 26 },
	]
	return _fail == 0


# ── 测试 1：is_shop_prep 判定 ─────────────────────────

func _test_is_shop_prep() -> void:
	var mid: int = _mid_shop_stage()
	_check("[1] 前置：mid_act_after_stage 在 1-7", mid >= 1 and mid <= 7, "mid=%d" % mid)

	# 幕中商店：stage4 打完的 Prep = 真
	var rm4: Object = _new_manager_at_prep_after(mid)
	_check("[1] 驱动到 stage%d 打完的 Prep（phase==prep）" % mid,
		rm4 != null and rm4.get_state().phase == "prep" and rm4.get_state().stage == mid,
		"phase=%s stage=%d" % [
			str(rm4.get_state().phase) if rm4 != null else "<null>",
			int(rm4.get_state().stage) if rm4 != null else -1])
	_check("[1] 幕中商店 Prep（stage%d）→ is_shop_prep()==true" % mid,
		rm4 != null and rm4.is_shop_prep())

	# Boss 前商店：stage7 打完的 Boss 前 Prep = 真
	var pre_boss_stage: int = _boss_stage - 1
	var rm7: Object = _new_manager_at_prep_after(pre_boss_stage)
	_check("[1] 驱动到 stage%d 打完的 Boss 前 Prep（phase==prep）" % pre_boss_stage,
		rm7 != null and rm7.get_state().phase == "prep" and rm7.get_state().stage == pre_boss_stage,
		"phase=%s stage=%d" % [
			str(rm7.get_state().phase) if rm7 != null else "<null>",
			int(rm7.get_state().stage) if rm7 != null else -1])
	_check("[1] Boss 前商店 Prep（stage%d）→ is_shop_prep()==true" % pre_boss_stage,
		rm7 != null and rm7.is_shop_prep())

	# 非商店 Prep：stage2/3/5/6 打完的 Prep = 假
	for s: int in [2, 3, 5, 6]:
		if s == mid or s == pre_boss_stage:
			continue  # 避免与两处商店定位撞车
		var rm: Object = _new_manager_at_prep_after(s)
		_check("[1] stage%d 打完的 Prep = 非商店（is_shop_prep()==false）" % s,
			rm != null and rm.get_state().phase == "prep" and not rm.is_shop_prep(),
			"phase=%s shop=%s" % [
				str(rm.get_state().phase) if rm != null else "<null>",
				str(rm.is_shop_prep()) if rm != null else "<null>"])

	# 非 prep 阶段（battle）→ false
	var rmb: Object = _new_manager()
	rmb.start_run(_run_config, _act_config, _pools, _roster.duplicate(true), _reseeded_rng())
	_check("[1] battle 阶段 is_shop_prep()==false", not rmb.is_shop_prep(),
		"phase=%s" % str(rmb.get_state().phase))


# ── 测试 2：get_shop_stock ───────────────────────────

func _test_get_stock() -> void:
	var rm: Object = _new_manager_at_prep_after(_mid_shop_stage())
	_check("[2] 商店 Prep 就绪", rm != null and rm.is_shop_prep())
	if rm == null:
		return
	var stock: Array = rm.get_shop_stock()
	_check("[2] 商店库存非空", not stock.is_empty(), "size=%d" % stock.size())

	var stock_size: int = _stock_size_cfg()
	_check("[2] 库存件数 == stock_size(%d)（候选池充足）" % stock_size,
		stock.size() == stock_size, "size=%d" % stock.size())

	var all_ok: bool = true
	for item_v: Variant in stock:
		if not (item_v is Dictionary):
			all_ok = false
			continue
		var item: Dictionary = item_v
		var kind: String = str(item.get("kind", ""))
		var ref_id: String = str(item.get("ref_id", ""))
		var price: int = int(item.get("price", -1))
		var name: String = str(item.get("name", ""))
		if not (kind == "equipment" or kind == "relic" or kind == "potion"):
			all_ok = false
		if ref_id == "" or name == "" or price <= 0:
			all_ok = false
	_check("[2] 每件 kind 合法 + ref_id/name 非空 + price>0", all_ok)

	# 稳定性：同一 Prep 两次调用一致
	var stock2: Array = rm.get_shop_stock()
	_check("[2] 同一 Prep 库存稳定（两次调用件数一致）", stock.size() == stock2.size())
	var same: bool = true
	for i: int in range(mini(stock.size(), stock2.size())):
		if str((stock[i] as Dictionary).get("ref_id", "")) != str((stock2[i] as Dictionary).get("ref_id", "")):
			same = false
	_check("[2] 同一 Prep 库存稳定（逐件 ref_id 一致）", same)

	# 非商店 Prep：返回空
	var rm_non: Object = _new_manager_at_prep_after(_non_shop_stage())
	_check("[2] 非商店 Prep get_shop_stock() 返回空",
		rm_non != null and rm_non.get_shop_stock().is_empty())


# ── 测试 3：buy_item ─────────────────────────────────

func _test_buy() -> void:
	var rm: Object = _new_manager_at_prep_after(_mid_shop_stage())
	if rm == null or not rm.is_shop_prep():
		_check("[3] 商店 Prep 就绪", false)
		return
	var st: Object = rm.get_state()
	var stock: Array = rm.get_shop_stock()
	_check("[3] 前置：库存非空", not stock.is_empty())
	if stock.is_empty():
		return
	var item: Dictionary = stock[0]
	var price: int = int(item.get("price", 0))
	var kind: String = str(item.get("kind", ""))
	var ref_id: String = str(item.get("ref_id", ""))

	# gold 足 → 买成功、扣减、入 convoy
	st.gold = price + 100
	var gold_before: int = st.gold
	var convoy_before: int = _convoy_count(st, kind)
	var ok: bool = rm.buy_item(item)
	_check("[3] gold 足 → buy_item 返回 true", ok)
	_check("[3] gold 足 → 扣减买价（gold -= price）",
		st.gold == gold_before - price, "gold %d→%d 期望 %d" % [gold_before, st.gold, gold_before - price])
	_check("[3] gold 足 → 该件入运输队（convoy 对应库 +1）",
		_convoy_count(st, kind) == convoy_before + 1,
		"前 %d 后 %d" % [convoy_before, _convoy_count(st, kind)])
	_check("[3] gold 足 → 买后库存移除该件（同件不可重复买）",
		not _stock_has(rm.get_shop_stock(), kind, ref_id))

	# gold 不足 → 拒绝、不扣、不入
	var item2: Dictionary = _first_stock_item(rm)
	if not item2.is_empty():
		var price2: int = int(item2.get("price", 0))
		var kind2: String = str(item2.get("kind", ""))
		st.gold = maxi(0, price2 - 1)
		var gold_before2: int = st.gold
		var convoy_before2: int = _convoy_count(st, kind2)
		var ok2: bool = rm.buy_item(item2)
		_check("[3] gold 不足 → buy_item 返回 false", not ok2)
		_check("[3] gold 不足 → gold 不扣", st.gold == gold_before2,
			"gold %d→%d" % [gold_before2, st.gold])
		_check("[3] gold 不足 → convoy 不增",
			_convoy_count(st, kind2) == convoy_before2)

	# 非法 kind → 拒绝
	var bad: Dictionary = { "kind": "rune", "ref_id": "x", "price": 0 }
	st.gold = 999
	var gold_b3: int = st.gold
	_check("[3] 非法 kind（rune）→ buy_item 返回 false", not rm.buy_item(bad))
	_check("[3] 非法 kind → gold 不扣", st.gold == gold_b3)


# ── 测试 4：sell_item ────────────────────────────────

func _test_sell() -> void:
	var rm: Object = _new_manager_at_prep_after(_mid_shop_stage())
	if rm == null:
		_check("[4] 商店 Prep 就绪", false)
		return
	var st: Object = rm.get_state()

	# 预置一件装备入运输队
	var eq_id: String = _any_equipment_id()
	_check("[4] 前置：存在装备样本", eq_id != "")
	st.convoy["equipment"] = [eq_id]
	st.gold = 0

	var sell_price: int = rm.get_sell_price("equipment", eq_id)
	_check("[4] 卖价预览 > 0（= 买价×比例）", sell_price > 0, "sell=%d" % sell_price)

	var ok: bool = rm.sell_item("equipment", eq_id, "convoy")
	_check("[4] 卖出返回 true", ok)
	_check("[4] 卖出 → gold 增 sell_price", st.gold == sell_price,
		"gold=%d 期望 %d" % [st.gold, sell_price])
	_check("[4] 卖出 → 该件出运输队",
		not (st.convoy.get("equipment", []) as Array).has(eq_id))

	# 无该 item → false 不加钱
	var gold_now: int = st.gold
	_check("[4] 卖不存在的物品 → 返回 false", not rm.sell_item("equipment", eq_id, "convoy"))
	_check("[4] 卖不存在 → gold 不变", st.gold == gold_now)


# ── 测试 5：金币守恒（买后卖回收 sell_ratio）──────────

func _test_gold_conservation() -> void:
	var rm: Object = _new_manager_at_prep_after(_mid_shop_stage())
	if rm == null or not rm.is_shop_prep():
		_check("[5] 商店 Prep 就绪", false)
		return
	var st: Object = rm.get_state()
	var item: Dictionary = _first_stock_item(rm)
	_check("[5] 前置：库存有货", not item.is_empty())
	if item.is_empty():
		return
	var price: int = int(item.get("price", 0))
	var kind: String = str(item.get("kind", ""))
	var ref_id: String = str(item.get("ref_id", ""))

	st.gold = price + 500
	var gold_before: int = st.gold
	_check("[5] buy 成功", rm.buy_item(item))
	# 从 convoy 把这件卖回去
	_check("[5] sell 成功", rm.sell_item(kind, ref_id, "convoy"))

	var ratio: float = _sell_ratio_cfg()
	var recovered: int = roundi(float(price) * ratio)
	var expected: int = gold_before - price + recovered
	_check("[5] 金币守恒：净变 == -买价 + roundi(买价×比例)",
		st.gold == expected,
		"gold=%d 期望 %d（price=%d ratio=%.2f recovered=%d）" % [
			st.gold, expected, price, ratio, recovered])
	_check("[5] 回收 == 买价×sell_ratio（占位比例生效）",
		recovered == roundi(float(price) * ratio))


# ── 测试 6：价格从 config 读（改价 → stock 价格变）──────

func _test_price_from_config() -> void:
	# 原配置库存
	var rm1: Object = _new_manager_at_prep_after(_mid_shop_stage())
	_check("[6] 原配置商店 Prep 就绪", rm1 != null and rm1.is_shop_prep())
	if rm1 == null:
		return
	var stock1: Array = rm1.get_shop_stock()

	# 复制 act_config，把 price_by_rarity 全部 ×10
	var cfg2: Dictionary = _deep_dup(_act_config)
	var shop2: Dictionary = cfg2.get("shop", {})
	var pbr2: Dictionary = shop2.get("price_by_rarity", {})
	for rk_v: Variant in pbr2.keys():
		var rk: String = str(rk_v)
		if rk.begins_with("_"):
			continue
		pbr2[rk_v] = int(pbr2[rk_v]) * 10
	shop2["price_by_rarity"] = pbr2
	cfg2["shop"] = shop2

	# 同种子驱动到同一商店 Prep（库存件相同，价格应 ×10）
	var rm2: Object = _new_manager_at_prep_after_cfg(_mid_shop_stage(), cfg2)
	_check("[6] 改价后商店 Prep 就绪", rm2 != null and rm2.is_shop_prep())
	if rm2 == null:
		return
	var stock2: Array = rm2.get_shop_stock()

	_check("[6] 改价前后库存件数一致（同种子同库存）",
		stock1.size() == stock2.size(), "%d vs %d" % [stock1.size(), stock2.size()])
	var price_scaled_ok: bool = true
	var item_match_ok: bool = true
	for i: int in range(mini(stock1.size(), stock2.size())):
		var a: Dictionary = stock1[i]
		var b: Dictionary = stock2[i]
		if str(a.get("ref_id", "")) != str(b.get("ref_id", "")):
			item_match_ok = false
			continue
		# 价格随 config ×10（仅对 price>0 的品质有意义）
		if int(a.get("price", 0)) > 0 and int(b.get("price", 0)) != int(a.get("price", 0)) * 10:
			price_scaled_ok = false
	_check("[6] 同种子库存逐件 ref_id 一致（改的是价不是库存）", item_match_ok)
	_check("[6] 价格随 config ×10（价格从 config 读，非硬编码）", price_scaled_ok)


# ── 工具 ─────────────────────────────────────────────

func _new_manager() -> Object:
	return RunManagerScript.new()


## 复位并返回 _rng（每次驱动前重置种子，保证跨 manager 库存派生一致）。
func _reseeded_rng() -> RandomNumberGenerator:
	_rng.seed = RNG_SEED
	return _rng


## 新建 manager 并驱动到「stage target 打完后的 Prep」（未 confirm_departure）。用当前 _act_config。
func _new_manager_at_prep_after(target: int) -> Object:
	return _new_manager_at_prep_after_cfg(target, _act_config)


## 同上，但用指定 act_config（供改价对照）。
func _new_manager_at_prep_after_cfg(target: int, act_cfg: Dictionary) -> Object:
	var rm: Object = _new_manager()
	rm.start_run(_run_config, act_cfg, _pools, _roster.duplicate(true), _reseeded_rng())
	var guard: int = 0
	while guard < 80:
		guard += 1
		var st: Object = rm.get_state()
		if st.phase == "battle":
			rm.on_battle_resolved("victory")
			var st2: Object = rm.get_state()
			if st2.phase == "prep":
				# Boss 前 Prep（stage7）：无 door_select
				if int(st2.stage) == target:
					return rm
				rm.confirm_departure()
			elif st2.phase == "door_select":
				var idx: int = _pick_non_event(st2.pending_doors)
				rm.choose_door(idx)  # → prep，stage 不变
				if int(rm.get_state().stage) == target:
					return rm
				rm.confirm_departure()
			else:
				return rm  # complete / failed
		else:
			return rm
	return rm


## 门组中挑一扇非事件门（避免事件分支），无则回退 0。
func _pick_non_event(doors: Array) -> int:
	for i: int in range(doors.size()):
		if str((doors[i] as Dictionary).get("reward_type", "")) != "event":
			return i
	return 0


## 幕中商店定位关。
func _mid_shop_stage() -> int:
	var dg: Dictionary = _act_config.get("door_gen", {})
	var fs: Dictionary = dg.get("fixed_shops", {})
	return int(fs.get("mid_act_after_stage", 4))


## 一个确定非商店的 Prep 关（避开 mid 与 boss-1）。
func _non_shop_stage() -> int:
	var mid: int = _mid_shop_stage()
	var pre_boss: int = _boss_stage - 1
	for s: int in [2, 3, 5, 6]:
		if s != mid and s != pre_boss:
			return s
	return 2


func _stock_size_cfg() -> int:
	var shop: Dictionary = _act_config.get("shop", {})
	return int(shop.get("stock_size", 4))


func _sell_ratio_cfg() -> float:
	var shop: Dictionary = _act_config.get("shop", {})
	return float(shop.get("sell_ratio", 0.5))


func _first_stock_item(rm: Object) -> Dictionary:
	var stock: Array = rm.get_shop_stock()
	if stock.is_empty():
		return {}
	return stock[0]


func _convoy_count(st: Object, kind: String) -> int:
	var key: String = "equipment" if kind == "equipment" else ("relics" if kind == "relic" else "potions")
	return (st.convoy.get(key, []) as Array).size()


func _stock_has(stock: Array, kind: String, ref_id: String) -> bool:
	for it_v: Variant in stock:
		if it_v is Dictionary and str((it_v as Dictionary).get("kind", "")) == kind \
				and str((it_v as Dictionary).get("ref_id", "")) == ref_id:
			return true
	return false


func _any_equipment_id() -> String:
	var eq: Dictionary = _pools.get("equipment", {})
	for k_v: Variant in eq.keys():
		return str(k_v)
	return ""


func _deep_dup(d: Dictionary) -> Dictionary:
	return d.duplicate(true)


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
