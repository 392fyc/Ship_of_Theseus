extends RefCounted
## 测试夹具：已下线的旧剑圣拔刀（`swordsman_badao`）的原样副本，只换了 id、名字和说明。
##
## 剑圣改用设计库的 `kensei_badao`（自身中心、范围内敌人各自满额结算）之后，正式数据里
## 已没有技能用到下面两条引擎通路，但引擎仍保留它们：
##   ① 选一个单位作为落点的区域技能（target_mode=单位 + area 菱形）；
##   ② `splash_damage_pct`：落点上的主目标满额，范围内其余目标按百分比衰减。
## 几组回归借这份副本继续锁住这两条通路。字段值与旧文件逐项相同，所以这些用例的
## 期望值不需要重算。
##
## `install` 只写进当前测试进程的 DataLoader.skills，不代表游戏数据。

const SKILL_ID: String = "test_fixture_splash_area"


static func install(data_loader: Object) -> String:
	data_loader.skills[SKILL_ID] = {
		"id": SKILL_ID,
		"target_mode": "单位",
		"name": "溅射区域（测试夹具）",
		"damage_type": "physical",
		"power": 180,
		"hit_bonus": 10,
		"range": {"type": "diamond", "min": 1, "max": 2},
		"area": {"type": "diamond", "size": 1},
		"attack_type": "area",
		"cooldown": 0,
		"action_cost": "standard",
		"timing_constraint": "any",
		"effects": [],
		"tags": ["sword", "mark", "area"],
		"qi_cost": 20,
		"qi_gain_on_hit": 0,
		"qi_gain_on_kill": 0,
		"mark_gain": 0,
		"mark_cost": 3,
		"requires_marks": 3,
		"guaranteed_crit": false,
		"guaranteed_hit": false,
		"crit_damage_mult": 1.2,
		"splash_damage_pct": 50,
		"slot_swap_provider": true,
		"description": "测试夹具：距离 1-2，180% 物理伤害；主目标满额，周围 1 格内的目标受 50% 溅射伤害。",
	}
	return SKILL_ID
