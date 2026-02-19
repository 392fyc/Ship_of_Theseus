# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Language

All design documents are in Chinese (Simplified). Respond in Chinese when discussing design, game mechanics, or documentation, unless the user switches to English.

---

## 项目概述

战棋RPG + Roguelite + 城镇建设，Godot 4 (GDScript) 开发。
支持单机1人 / 联机1-4人。画风GBA像素（初期跳过，先搭系统）。
当前阶段：设计文档已完成，尚无代码。开发方式：Vibe Coding + AI辅助。

**核心差异化**：城镇建设融入战棋Roguelite，玩家在角色强化和建筑投资之间做经济抉择。

---

## 技术栈

- **引擎**: Godot 4.x (GDScript)
- **数据**: JSON驱动（所有游戏内容用JSON定义，代码只处理逻辑）
- **联机**: Godot High-Level Multiplayer API, Host-Client模型
- **架构**: GameAction指令驱动（所有操作封装为GameAction，联机时广播同步）

---

## 项目结构

```
project/
├── docs/                          # 设计文档（只读参考，不要修改）
│   ├── README.md                  # 总纲和文档目录
│   ├── design-roadmap.md          # 设计思路梳理和发展方向
│   ├── module-relations-agent.md  # ⭐ 模块依赖表（修改代码前必查）
│   ├── 01 ~ 11 模块文档
│   └── module-relations.mermaid
├── scenes/
│   ├── battle/                    # 战斗场景 (BattleScene, Grid, Unit, UI)
│   ├── roguelite/                 # Roguelite流程 (RunMap, RewardScreen, ShopScreen)
│   └── menus/
├── scripts/
│   ├── core/                      # grid, pathfinding, turn_manager, battle_manager,
│   │                              # damage_calculator, hit_calculator, game_action
│   ├── units/                     # unit, unit_stats, skill_executor
│   ├── ai/                        # enemy_ai
│   ├── data/                      # data_loader
│   ├── roguelite/                 # run_manager, relic_system, town_manager,
│   │                              # building_system, talent_tree, reward_generator
│   └── network/                   # network_manager
├── data/                          # JSON游戏数据
│   ├── classes/  skills/  enemies/  maps/
│   ├── relics/  buildings/  waves/  events/
└── assets/
```

---

## 设计文档查阅规则

**修改任何代码前**，必须：

1. 阅读 `docs/module-relations-agent.md` 确认影响范围
2. 阅读对应模块的设计文档了解规则细节
3. 检查 depended_by 列表确认是否需要同步修改其他模块

### 文档稳定性状态

**已核查完成**（视为稳定参考，非用户明确要求不要修改）：
- `01-turn-system.md`, `02-grid-and-map.md`, `03-battle-calculation.md`, `05-class-system.md`, `11-town-building.md`

**待核查/更新**：
- `04-skills-and-range.md`, `06-enemy-and-ai.md`, `07-run-loop.md`, `08-network.md`, `09-data-architecture.md`, `10-milestones.md`

**待建**：
- `12-talent-tree.md`（设计方向已确定，文档未建）
- 视野系统文档

### 系统分层（开发顺序自下而上）

```
Layer 4 (Meta层):   07-Run循环  ←→  11-城镇建设
Layer 3 (角色层):   05-职业系统  ←→  06-敌人与AI  ←→ 12-天赋树
Layer 2 (战斗层):   01-回合  →  04-技能  →  03-伤害计算
Layer 1 (基础层):   02-网格与地图
Layer 0 (数据层):   09-数据架构
叠加层:             08-联机架构（不改变游戏逻辑）
```

### 开发里程碑（→ docs/10-milestones.md）

1. 网格原型（TileMap, BFS, A*）
2. 回合与战斗
3. 技能与射程
4. 职业与AI完善
5. Roguelite框架 + 城镇建设
6. 联机

---

## 核心游戏规则（编码时必须遵守）

### 回合系统 (→ docs/01)

- **速度轮动**：每回合所有单位按speed降序排列行动，speed相同按先制优先级排序
- **先制优先级**：0(普通) / +1 / +2，高优先级无视speed排在前面
- **同速处理**：低难度玩家先，最高难度敌人先
- **Buff/Debuff时机**：
  - 效果触发（燃烧扣血等）= **角色回合开始**时
  - 持续回合扣减 = **角色回合结束**时
  - 施加Buff = 立即生效，从**下一个角色回合结束**开始扣减

### 网格与地图 (→ docs/02)

- 正方形网格，≤10×10，无高低差
- **三层结构**：
  1. 基础地形（始终存在，9种）
  2. 特殊地形（叠加在基础地形上）
  3. 建筑（覆盖基础地形效果）
- **基础地形枚举**: PLAIN=0, FOREST=1, MOUNTAIN=2, PEAK=3, WALL=4, SHALLOW_WATER=5, DEEP_WATER=6, LAVA=7, SWAMP=8
- **攻击线阻挡**：仅PEAK阻挡远程攻击线，WALL不阻挡
- 建筑摧毁后变废墟，**不恢复**基础地形效果
- 寻路：BFS计算移动范围，A*计算路径。陷阱不影响寻路

### 伤害计算 (→ docs/03)

**伤害公式（乘区分层）**：
```
最终伤害 = 基础伤害 × 技能倍率 × 特殊地形修正 × 暴击修正 × 格挡修正 × 最终伤害增减

基础伤害 = 攻击力 × 武器威力 - 防御力 × 护甲抵抗  (最低0，无保底)
```

**命中公式（加法模型）**：
```
命中率 = attacker.hit + weapon.hit + skill_hit_bonus - defender.evade - terrain_evade + other
范围: 20% ~ 100%
```

**暴击公式**：
```
暴击率 = (attacker.crit + weapon.crit + skill_crit_bonus - defender.crit_evade) × 暴击抵抗率
范围: 0% ~ 50%，基础倍率 1.5x
```

**格挡**：职业基础固定（不成长），70%减免，**与暴击互斥**

**结算顺序**：命中→格挡→暴击→伤害→命中后附加效果→伤害后附加效果→反击

### 伤害类型双轴 (→ docs/03)

每个技能/攻击有两个轴：

**属性类型**（element_type，决定防御计算，四选一互斥）：
| 类型 | 防御 | 暴击 | 格挡 |
|------|------|------|------|
| physical | 物防×护甲 | Yes | Yes |
| magical | 魔防×魔抗 | Yes | Yes |
| holy | 无视防御 | No | No |
| hybrid | 取物防/魔防较低者 | Yes | Yes |

**攻击方式**（attack_type，由技能固定声明）：
- `melee`: 射程仅1格
- `ranged`: 射程>1格（即使实际打1格距离也算远程）
- `area`: 有AOE范围（即使只命中单体也算范围）

### 反击系统 (→ docs/05)

```
反击条件:
  attack_type != "area" AND 目标存活 AND 目标未眩晕/冰冻 AND 目标射程可达攻击者
反击方式: 普通攻击（走完整结算），不触发二次反击
```

### 职业系统 (→ docs/05)

- 8基础职业 + 16转职方向（魔法师4系分支）
- v1测试5职业：佣兵/弓箭手/魔法师/骑士/牧师
- **不随升级成长的属性**：speed, move, block, vision
- 转职通过天赋树特殊节点触发，选后不可更改
- 职业有 `class_tags` 用于建筑占据判定

### 建筑系统 (→ docs/11)

- 建筑耐久**不使用常规伤害公式**，按伤害类型固定扣减
- 四种子类型：通用/限制/阻挡/范围
- 占据 = 停留（符合条件的单位停留即自动占据，无需操作）
- 玩家建造的建筑仅对玩家方生效，地图预设建筑对双方生效
- 准备阶段可消耗金币修复被摧毁的建筑

### Meta进度 (→ docs/07)

**核心原则：Meta = 横向解锁（更多选择），绝不纵向强化（数值提升）**

- 禁止：因Meta不足导致核心机制缺失；起始HP/攻击力等数值加成
- 允许：解锁新职业/转职/遗物/建筑；便利性升级（经济/信息层面）

### 天赋树 (→ docs/12, 待建)

- **每次Run重置**，重新选择路径
- Meta解锁可选范围，Run中获得天赋点解锁节点
- 包含被动特性、主动技能、转职节点
- 初始天赋区域包含1个转职的完整核心玩法

---

## 编码规范

### GDScript 风格

```gdscript
# 类命名：PascalCase
class_name DamageCalculator

# 变量/函数：snake_case
var current_hp: int = 0
func calculate_damage(attacker: Unit, defender: Unit, skill: SkillData) -> int:

# 常量：UPPER_SNAKE_CASE
const MAX_GRID_SIZE: int = 10
const BASE_CRIT_MULTIPLIER: float = 1.5

# 枚举
enum TerrainType { PLAIN, FOREST, MOUNTAIN, PEAK, WALL, SHALLOW_WATER, DEEP_WATER, LAVA, SWAMP }
enum ElementType { PHYSICAL, MAGICAL, HOLY, HYBRID }
enum AttackType { MELEE, RANGED, AREA }

# 信号：past_tense
signal damage_dealt(attacker: Unit, target: Unit, amount: int)
signal unit_killed(unit: Unit)
signal turn_started(unit: Unit)
```

### GameAction 模式

所有游戏操作封装为GameAction，便于联机同步和回放：

```gdscript
var action = GameAction.new({
    "type": "move",
    "unit_id": unit.id,
    "target_position": Vector2i(3, 5)
})
battle_manager.execute_action(action)

# 联机时广播
if multiplayer.is_server():
    network_manager.broadcast_action(action)
```

### 数据驱动

```gdscript
# 正确：从JSON数据中读取
var skill_data = DataLoader.skills[skill_id]
var damage = attacker.attack * skill_data.power / 100

# 错误：在代码中硬编码游戏数值
var damage = attacker.attack * 1.5  # 不要这样做
```

新增游戏内容（职业/技能/敌人/遗物/地图/建筑/事件）= 新增JSON文件，不改代码逻辑。

### JSON 数据文件规范

**技能JSON**必须包含的字段：
```json
{
  "id": "string",
  "name": "string",
  "element_type": "physical|magical|holy|hybrid",
  "attack_type": "melee|ranged|area",
  "power": 100,
  "hit_bonus": 0,
  "crit_bonus": 0,
  "range": { "type": "diamond|line|cross|self", "min": 1, "max": 1 },
  "area": { "type": "single|diamond|line|cross|square", "size": 0 },
  "cooldown": 0,
  "effects": [],
  "effect_timing": "on_hit|after_damage",
  "pre_move": false,
  "post_attack_move": false,
  "description": "string"
}
```

**职业JSON**必须包含的字段：
```json
{
  "id": "string",
  "name": "string",
  "base_stats": {
    "hp": 0, "attack": 0, "magic": 0,
    "physical_defense": 0, "magical_defense": 0,
    "speed": 0, "move": 0, "vision": 3,
    "hit": 0, "evade": 0, "crit": 0, "crit_evade": 0,
    "resistance": 0, "block": 0
  },
  "stat_growth": {},
  "innate_skills": [],
  "equip_types": [],
  "class_tags": [],
  "move_type": "foot|armored|mounted",
  "advancement": []
}
```

注意：`speed`, `move`, `vision`, `block` 不出现在 `stat_growth` 中（不随升级成长）。

---

## 关键实现注意事项

### 伤害结算顺序（必须严格遵守）

```
1. 命中判定 (加法公式, 20%~100%) → miss则跳到结束
2. 格挡判定 → 成功则标记格挡修正=0.3, 跳过暴击
3. 暴击判定 (加法+抵抗率, 0%~50%) → 仅格挡失败时判定
4. 计算伤害 (乘区分层)
5. 应用伤害 (扣HP, 检查击杀, 建筑联动伤害)
6. 命中后附加效果 (Debuff等, 受resistance影响)
7. 伤害后附加效果 (吸血/击杀触发等)
8. 反击判定 (attack_type!=area, 目标存活, 射程可达, 未被控制)
   → 反击走1-7步，但不再触发反击
```

### 地形效果应用

```
地形属性加成（如山地+防御）→ 直接加到属性上（参与加减法计算）
特殊地形修正 → 独立乘区（参与乘法计算）
建筑效果 → 最终伤害增减乘区
以上三者是不同层级，不要混淆
```

### Debuff附加公式

```
实际附加率 = skill_effect.chance × (1 - defender.resistance / 100)
```

### 建筑耐久结算（独立于伤害公式）

```
建筑受到攻击时:
  不使用常规伤害公式
  根据攻击的 element_type 和 attack_type 查表扣减固定点数耐久
```

---

## 开发流程

1. **接到任务时**：先查 `docs/module-relations-agent.md` 确认涉及哪些模块
2. **编码前**：阅读对应模块的设计文档
3. **编码时**：遵循数据驱动原则，不硬编码数值
4. **测试时**：确保GameAction模式正确（所有操作可序列化）
5. **完成后**：检查 depended_by 列表，确认是否需要修改其他模块

### 常见陷阱

- 在代码中硬编码伤害数值或职业属性 → 应该读JSON
- 格挡和暴击同时生效 → 互斥，先判格挡
- holy伤害触发暴击或格挡 → 神圣伤害无视这两者
- 建筑耐久用常规伤害公式 → 应该固定扣减
- 攻击线检查所有地形 → 仅PEAK阻挡
- 反击触发反击 → 反击不触发二次反击
- 范围攻击触发反击 → attack_type="area"不触发
- speed/move/block/vision随升级成长 → 这些属性固定
- Meta解锁包含数值强化 → Meta只做横向解锁
- 建筑摧毁后恢复基础地形效果 → 变为废墟，无效果
- 距离影响伤害或命中 → 无距离衰减机制
