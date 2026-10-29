# 战术 RPG 类 Roguelite — 核心系统设计文档 - GDD

> 本文档是所有模块设计文档的高层汇总。详细规则请查阅对应的模块文档(01~12)。
> 当与模块文档冲突时,以模块文档为准。

## 项目概览

| 属性 | 决策 |
|-----------|--------|
| 类型 | 战术 RPG + Roguelite |
| 引擎 | Godot 4(GDScript) |
| 棋盘 | 方格网格,≤10×10,无高低差 |
| 回合系统 | 基于速度的出手顺序(按 speed 降序排列) |
| 玩家数 | 单人 1 / 多人 1-4 |
| 多人模式 | 每位玩家控制若干角色,GameAction 指令同步 |
| 核心循环 | 一个 Run 结构为 3 幕 × 8 关卡(共 24 关) |
| 数据架构 | JSON 驱动(所有内容存于 JSON,代码只处理逻辑) |
| 核心差异化 | 差异化天赋架构(每职业独立的天赋结构 + 不可逆的转职(Class Advancement)+ meta/run 双层选择)是构筑深度的首要机制。 |

---

## 1. 回合系统 - 01-turn-system.md

### 基于速度的出手顺序

每个回合,所有单位按 `speed` 降序行动。不是 CT 累积模型。

- **先攻优先级**:0(正常)/ +1 / +2,优先级越高越先出手,凌驾于速度之上
- **同速裁定**:先攻优先级与速度都相同时由难度决定——旧日重现难度敌方一方先手,其下各难度玩家一方先手;同一方内部仍并列时,玩家按角色生成顺序(1P 至 4P)、敌方按敌方单位生成顺序
- **Buff/Debuff 时机**:效果触发 = 单位回合开始,持续时间递减 = 单位回合结束,施加 = 立即生效

### 行动资源系统

每个单位每回合拥有**结构化的行动资源**:

| 资源 | 额度 | 说明 |
|----------|-----------|-------------|
| 移动(Movement) | `move` 属性 | 普通移动 或 \[Move Action\] 技能(二选一) |
| 标准行动点 / 攻击机会(Standard Action Point / Attack Opportunity) | 默认容量 1 | 每个 \[Standard Action\] 技能消耗 1 点；容量允许为 1 至 3 |
| 迅捷行动点(Swift Action Point) | 默认容量 1 | 每个 \[Swift Action\] 技能消耗 1 点；容量允许为 1 至 3，且不消耗其它行动资源 |

**动作类型标签**(所有主动技能必须打标签):

| 标签 | action_cost | 消耗 | 典型用途 |
|-----|------------|----------|-------------|
| \[Move Action\] | `"move"` | 移动 | 位移技能(冲锋/闪步) |
| \[Standard Action\] | `"standard"` | 攻击机会 | 攻击/强力增益与减益 |
| \[Swift Action\] | `"swift"` | 迅捷动作(1/回合) | 姿态切换/轻量增益 |
| \[Reaction Action\] | `"reaction"` | 无(条件触发) | 受击反应/友军协同 |
| \[Free Action\] | `"free"` | 无 | 信息查看/光环开关 |

**设计理由**:防止「一回合放光所有技能」——不同技能争夺同一组资源,保留移动与基础攻击技能的战术价值。攻击方式只有技能一种,每个职业以一个占标准位的基础攻击技能(剑士 / 剑圣是〔斩击〕)兜住输出下限。

### 多人适配

- 在出手顺序系统下,同一时刻只有 1 个单位行动;只需同步当前行动者的 GameAction
- 所有操作都封装为 GameAction;单人下直接执行,多人下先广播再执行

---

## 2. 棋盘与地图 - 02-grid-and-map.md

### 三层结构

```
Layer 1: Base Terrain (9 types, always present)
Layer 2: Special Terrain (stacked on base terrain)
Layer 3: Buildings (override base terrain effects, become Ruins when destroyed)
```

### 基础地形

| ID | 地形 | 移动消耗 | 可通行 |
|----|---------|-----------|----------|
| 0 | Plain(平原) | 1 | ✓ |
| 1 | Forest(森林) | 2 | ✓ |
| 2 | Mountain(山地) | 2 | ✓ |
| 3 | Peak(山峰) | — | ✗ |
| 4 | Wall(墙) | — | ✗ |
| 5 | Shallow Water(浅水) | 2 | ✓ |
| 6 | Deep Water(深水) | — | ✗ |
| 7 | Lava(熔岩) | 2 | ✓ |
| 8 | Swamp(沼泽) | 3 | ✓ |

### 寻路

- BFS 计算移动范围,A* 计算路径
- 陷阱不影响寻路

---

## 3. 战斗计算 - 03-battle-calculation.md

### 伤害公式 - 加法制 - R1.1

```
Base Damage = max(0, STR + weapon_might - DEF)   [physical]
            = max(0, MAG + weapon_might - RES)   [magical]
Final Damage = Base Damage × skill_multiplier × terrain_modifier × crit_modifier × relic_modifier × final_modifier   (floor 0)
```

> 详见 `01-Game-Design/Core-Systems/battle-calculation.md`

### 命中 - 暴击 - R1.2 / R1.3

```
Hit Rate = weapon_hit + DEX×2 - (SPD×2 + terrain_evade)  (clamp 1~100，R1.2)
Crit Rate = weapon_crit + DEX/2 - LCK  (1.5x; pure damage does not participate in crit - R1.3)
```

### 伤害类型双轴 - ADR-004

**属性类型**(决定防御计算):

| 类型 | 防御 | 暴击 |
|------|---------|------|
| physical | DEF | ✓ |
| magical | RES | ✓ |
| pure | 无视防御 | ✗ |
| hybrid | 物理与魔法各算一次再取算术平均 [已定] | ✓ |

> **hybrid 的基础伤害**(2026-08-03 用户裁决,[已定]):物理与魔法**各按 R1.1 完整算一次**,每一侧各自带自己的 max(0, ·) 地板,再把两个结果取算术平均。
>
> ```
> base = ( max(0, STR + weapon_might - DEF) + max(0, MAG + weapon_might - RES) ) / 2
> ```
>
> 这**不等于**「一次性减去平均防御」——有地板参与时两者结果不同,不可合并简写。

**攻击方式**:`melee`(1 格) / `ranged`(>1 格) / `area`(AOE)

### 结算顺序

```
1. Hit check → miss skips to end
2. Crit check
3. Calculate damage → 4. Apply damage → 5. On-hit effects → 6. After-damage effects
(结算止于步骤 6)
```

---

## 4. 技能与射程 - 04-skills-and-range.md

### 技能数据结构

```json
{
  "id": "string",
  "action_cost": "move|standard|swift|reaction|free",
  "timing_constraint": "any|before_move|after_move|before_attack|after_attack",
  "damage_type": "physical|magical|pure|hybrid",
  "attack_type": "melee|ranged|area",
  "power": 100,
  "range": { "type": "diamond|line|cross|self", "min": 1, "max": 1 },
  "area": { "type": "single|diamond|line|cross|square", "size": 0 },
  "cooldown": 0,
  "effects": [{ "type": "string", "chance": 0, "timing": "on_hit|after_damage" }]
}
```

- `action_cost`:行动资源类型(→ 01-turn-system.md 行动资源系统)
- `timing_constraint`:施放时机约束(默认 `"any"`,可限制为移动或攻击的前/后)

### 减益施加公式

```
Actual application rate = skill.chance × max(0.1, 1 - target.LCK / 100)   (R1.5)
```

---

## 5. 职业系统 - 05-class-system.md

### 职业架构

- **8 个基础职业**:剑士(Swordsman)、佣兵(Mercenary)、弓手(Archer)、机械师(Artificer)、法师(Mage)、骑士(Knight)、猎人(Hunter)、牧师(Cleric)
- **16 条转职路线**:每个基础职业 2 条(法师有 4 条元素分支)
- v1 可玩原型当前使用 5 个职业:士兵(Soldier)/弓手(Archer)/法师(Mage)/骑士(Knight)/牧师(Cleric)
- **固定属性**:LCK、MOV(七成长属性 HP/STR/MAG/DEX/SPD/DEF/RES 见 R2.1)
- 转职是**等级事件**:到 Lv5 触发,一旦选择不可逆

### 构筑组成

```
UnitBuild = Class + Talent Tree (skeleton) + Equipment + Random Skills/Relics (flesh)
```

---

## 6. 天赋树 - 06-talent-tree.md, WIP

- 每个 Run 重置，路线重新选择；跨局 Meta 只解锁可用选项。
- Run 中通过天赋点选择天赋卡；当前组织形态是扁平卡池，结构化真源为设计库天赋实体。
- 卡片出现与解锁条件由 `unlock_trigger` 承载，不依赖固定路径拓扑。
- 天赋包含被动特性与主动技能；转职是 Lv5 的等级事件，本身不消耗天赋点。
- 初始可选范围必须包含某一条转职路线的完整核心玩法。

详细当前约束见 [[Characters/talent-tree|天赋树系统]]；名称、数量和直接字段从设计库当前接口或快照读取。

## 7. 敌人与 AI - 07-enemy-and-ai.md

### AI 行为模式

| 模式 | 说明 |
|---------|-------------|
| AGGRESSIVE | 优先攻击最近/最低 HP 目标 |
| DEFENSIVE | 守卫区域,仅在被接近时应战 |
| SUPPORT | 优先治疗/增益友军 |
| HIT_AND_RUN | 攻击后脱离 |
| BOSS | 固定技能循环 |

### 波次系统

敌人分波次进入,由条件触发(回合数/剩余数量/Boss HP 阈值)。

---

## 8. Run 循环与 Meta - 08-run-loop.md

### Run 结构

```
One Run = 3 Acts × 8 Stages (including battles/events/elites/bosses)
Preparation Phase → Battle → Reward Selection → Next Stage
```

### Meta 进程原则

**核心原则:Meta = 横向解锁(更多选择),绝不是纵向数值提升**

- ✓ 解锁新职业/转职/遗物/建筑
- ✓ 便利性升级(经济/信息层)
- ✗ 初始 HP/攻击加成
- ✗ 把核心机制锁在 Meta 进程之后

---

## 9. 数据架构 - 09-data-architecture.md

```
data/
├── classes/    # Class definitions
├── skills/     # Skill definitions
├── enemies/    # Enemy templates
├── maps/       # Map configurations
├── relics/     # Relic definitions
├── buildings/  # Building definitions
├── waves/      # Wave configurations
└── events/     # Event configurations
```

新增游戏内容 = 新增 JSON 文件,无需改代码。

---

## 10. 网络架构 - 10-network.md

- Godot 高层多人 API,Host-Client 模型
- 所有操作封装为 GameAction,多人下广播同步
- 覆盖层(Overlay)设计:不改动游戏逻辑,单人下可完全忽略

---

## 11. 系统分层

```
Layer 4 (Meta):      08-Run Loop
Layer 3 (Character): 05-Class System ←→  07-Enemy & AI  ←→ 06-Talent Tree
Layer 2 (Battle):    01-Turn System  →  04-Skills       →  03-Battle Calculation
Layer 1 (Base):      02-Grid & Map
Layer 0 (Data):      09-Data Architecture
Overlay:             10-Network Architecture (does not alter game logic)
```

开发顺序自底向上:Layer 0/1 → Layer 2 → Layer 3 → Layer 4 → Overlay

---

## 12. 设计哲学

1. **普通难度好玩,困难难度有深度**:多乘区系统支撑构筑多样性
2. **Meta 是横向的,不是纵向的**:解锁更多选择,而非更强数值
3. **天赋是骨架,随机是血肉**:可控的方向规划 + Roguelite 随机惊喜
4. **全属性透明**:命中/暴击采用加法模型,玩家可精确计算
5. **差异化天赋是核心差异化点**:每职业天赋结构 + 不可逆转职强制构筑专精。各职业靠什么表达玩法差异,见 [[Characters/talent-tree|天赋树系统]] 待裁决项
6. **转职是方向选择,而非数值提升**:每次转职开启一种不同玩法
7. **行动资源是战略深度**:每回合有限的行动资源(移动/攻击/迅捷)迫使玩家在技能间取舍——技能更多并不总是更好
