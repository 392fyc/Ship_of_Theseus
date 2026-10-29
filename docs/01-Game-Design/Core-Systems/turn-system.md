# 01 - 回合系统(Turn System)

> Back to [[game-design-doc|GDD]]

## 概览

基于速度的出手顺序系统。每一回合,所有单位按 `speed` 降序行动。不是 CT(行动值)累积模型。每个单位每回合拥有**结构化的行动资源**,技能与操作按消耗类型分类,在单个回合内制造策略取舍。

---

## 基于速度的出手顺序

每回合开始时,所有存活单位按 `speed` 降序排序,生成行动队列。

### 先攻优先级

| 优先级 | 说明 |
|----------|-------------|
| +2 | 最高优先级,无视速度,强制排到队列最前 |
| +1 | 次级优先级,排在 +2 之后、普通单位之前 |
| 0 | 普通(默认),按速度排序 |

同一优先级内,单位仍按 `speed` 降序排序。

### 同速裁决

当两个单位的先攻优先级与速度都相同时,由难度决定先手方:
- **旧日重现难度**:敌方一方先手
- **其下的各难度**:玩家一方先手

同一方内部仍然并列时按固定顺序行动:玩家按角色的生成顺序(多人游戏即 1P 至 4P),敌方按敌方单位的生成顺序。

### 增益与减益时机规则

| 时机 | 触发 |
|--------|---------|
| 效果触发 | 在**单位回合开始**时(如 DOT 持续伤害、再生) |
| 持续时间递减 | 在**单位回合结束**时(剩余回合 −1) |
| 效果施加 | **立即**(施加时即影响属性) |

**术语**:
- **单位回合开始/结束**(unit turn start/end):某个具体单位开始/结束其行动阶段
- **回合开始/结束**(turn start/end):整个行动队列的循环开始/结束

---

## 行动资源系统

### 设计理念

每个单位的回合被拆分为多个**行动资源**。技能与操作各自消耗不同资源,迫使玩家在有限资源内做出战术决策。

**核心目标**:
- 防止「一回合放光所有技能」的无脑循环——不同技能争夺同一资源
- 保留移动与基础攻击技能的战术价值——高级技能有机会成本
- 制造职业差异化——某些职业擅长利用特定资源类型
- 允许「纯施法者」构筑存在,但不作为通用常态

### 回合资源池

每个单位在其回合开始时获得以下资源:

| 资源 | 默认额度 | 说明 |
|----------|-------------------|-------------|
| **移动**(Movement) | 由 `move` 属性决定 | 用于普通移动和 \[Move Action\] 技能 |
| **标准行动点 / 攻击机会**(Standard Action Point / Attack Opportunity) | 默认容量 1 | 自身回合开始时恢复到当前容量,每个 \[Standard Action\] 技能消耗 1 点;容量允许为 1 至 3 |
| **迅捷行动点**(Swift Action Point) | 默认容量 1 | 自身回合开始时恢复到当前容量,每个 \[Swift Action\] 技能消耗 1 点,不消耗移动或标准行动点;容量允许为 1 至 3 |

### 行动类型标签

所有主动技能和操作必须标注以下行动类型之一:

#### 移动动作 — action_cost move

消耗本回合的**移动**(部分或全部)。使用后不再能进行普通移动,但仍可进行攻击。

- 典型用途:位移技能(冲锋、闪避步、传送)
- 设计约束:使用后剩余移动力归零
- 与普通移动互斥:普通移动同样消耗移动力,已移动后不能再用 \[Move Action\] 技能

```
Examples:
  Swordsman "Lunge Strike": [Move Action] Move 2 cells toward target
  Archer "Backstep": [Move Action] Move 1 cell backward and gain Evasion +10 (1 turn)
  Knight "Charge": [Move Action] Charge straight toward target, dealing AOE damage along the path
```

#### 标准动作 — action_cost standard

每次消耗 1 点**标准行动点**(也称攻击机会),并使尚未使用的移动失效。只要仍有标准行动点,单位就可以继续使用其他标准动作；已经失效的移动不会因此恢复。

- 典型用途:攻击技能、强力增益/减益
- 默认容量为 1 时,携带的多个 \[Standard Action\] 技能之间只能择一；容量提高后可以继续支付标准行动点
- 设计原则:这是最「昂贵」的行动资源。攻击方式只有技能一种,所以每个职业都有一个占标准位的**基础攻击技能**(剑士 / 剑圣是〔斩击〕)作为这一档的下限;更强的 \[Standard Action\] 技能与它争夺同一个槽位,凭强度或场景分工把它挤下去
- 默认资源级联:执行标准动作也会消耗剩余的移动,强制「先移动后行动」的阶段顺序

```
Examples:
  Mage "Fireball": [Standard Action] Ranged AOE magical damage
  Cleric "Group Heal": [Standard Action] Heal all allies within range
  Swordsman "Ten Thousand Swords": [Standard Action] High-multiplier single-target attack
```

#### 敏捷动作 — action_cost swift

每次消耗 1 点迅捷行动点，**不消耗**移动或标准行动点。默认容量为 1，容量提高后可以在同一自身回合继续支付。典型用途:切换架势、短时增益、轻度减益。
零成本的光环开关、信息查看类操作走自由动作 free,不占敏捷次数。

- 灵活时机:可在移动或攻击之前/之后的任意时点使用

```
Examples:
  Swordsman "Quick Draw": [Swift Action] Switch attack stance, next attack crit rate +15% (1/turn)
  Mage "Mana Infusion": [Swift Action] Next magical attack damage +20% (1/turn)
  Tactician "Aura Switch": [Free Action] Switch between attack aura and defense aura
  Hunter "Scout": [Free Action] View target unit's detailed attributes
```

#### 反应动作 — action_cost reaction

**不消耗主动回合资源**。由特定条件被动触发,发生在其他单位的回合或特定事件期间。

- 典型用途:受击反应、友军协同
- 限制机制:可能消耗专用资源(如剑圣的剑气,R1.6),或有每回合使用次数限制
- 不可主动施放:必须满足触发条件才能激活

```
Examples:
  Knight "Protect": [Reaction Action] Take damage in place of adjacent ally when attacked
  Cleric "Divine Grace": [Reaction Action] Automatically apply shield when ally HP drops below 20%
```

#### 自由动作 — action_cost free

**不消耗任何行动资源**,无每回合次数限制(除非技能自身另有限制)。

- 典型用途:信息查看、光环开关类零成本操作
- 与敏捷动作的区别:敏捷每回合 1 次并占用敏捷次数,free 完全脱离行动资源系统、不占任何次数

### 回合内行动流程(分阶段顺序)

```
Unit Turn Start
  │
  ├─ Buff/Debuff trigger (unit turn start effects)
  │
  ├─ Move Phase
  │   ├─ Normal movement OR [Move Action] skill    ← Consumes Movement (choose one)
  │   ├─ [Swift Action] (if timing allows)          ← Can be used before/after move
  │   └─ Skip move (proceed directly to Action Phase)
  │
  ├─ Action Phase
  │   ├─ [Standard Action] skill                    ← Consumes Attack Opportunity + Movement
  │   ├─ [Swift Action] (if timing allows)           ← Can be used before/after attack
  │   └─ Skip attack (end turn or use remaining Swift)
  │
  ├─ Swift Phase (if the Swift use is still available)
  │   └─ Use remaining [Swift Action] skills
  │
  ├─ Manually end turn / auto-end when all resources exhausted
  │
  └─ Buff/Debuff duration decrement (unit turn end)
```

**分阶段顺序**:行动遵循 **Move → Attack → End** 的阶段推进:
- 先移动,再攻击/用技能(标准 SRPG 流程)
- 跳过移动直接攻击/用技能(默认放弃剩余移动力)
- 敏捷动作可在回合结束前的任意阶段穿插使用
- 特殊天赋/技能(如「再行动」,R3.2)可覆盖默认的阶段限制
- 只移动不攻击(经手动结束回合提前结束)

### 技能施放时机约束

部分技能,除行动类型外,还可带有**施放时机约束**:

| 约束 | 字段值 | 说明 |
|-----------|-------------|-------------|
| 无约束 | `"any"` | 默认,可在行动阶段任意时点施放 |
| 移动前 | `"before_move"` | 必须在本回合移动前施放 |
| 移动后 | `"after_move"` | 必须在本回合已移动后施放 |
| 攻击前 | `"before_attack"` | 必须在本回合攻击前施放 |
| 攻击后 | `"after_attack"` | 必须在本回合已攻击后施放 |

```
Examples:
  Archer "Aim": [Swift Action, before_attack] Must be used before attacking
  Swordsman "Chase Strike": [Standard Action, after_move] Must be used after moving
  Knight "Shield Wall": [Swift Action, before_move] Sacrifice mobility for defensive posture
```

---

## 行动资源与构筑设计

### 技能数量的策略深度

行动资源系统天然限制每回合可用的技能数量:

| 资源 | 每回合额度 | 可用技能数 |
|----------|-------------------|-------------------|
| 移动 | 通常 1 次(移动或移动动作技能) | 通常至多 1 个 \[Move Action\] |
| 标准行动点 | 默认容量 1,允许 1 至 3 | 每个 \[Standard Action\] 消耗 1 点 |
| 迅捷行动点 | 默认容量 1,允许 1 至 3 | 每个 \[Swift Action\] 消耗 1 点 |
| 反应动作 | 条件触发 | 取决于触发条件与槽 |

在默认容量下,一个单位回合通常至多支付 1 次移动、1 次标准动作和 1 次迅捷动作。容量被明确提高后,可继续支付同类行动点；因此“默认 1 点”不是不可突破的每回合技能次数上限。\[Free Action\] 不消耗行动点,\[Reaction Action\] 取决于触发条件。这确保:

- **技能不是越多越好**:默认容量下,携带多个 \[Standard Action\] 技能仍争夺同一个标准行动点
- **构筑决策至关重要**:选择携带哪些技能 = 选择如何分配行动资源
- **标准位空着就是真的空转**:攻击方式只有技能一种,标准位没有可放的技能,这一回合就打不出伤害。因此每个职业都需要一个占标准位的**基础攻击技能**兜住下限(剑士 / 剑圣是〔斩击〕),它保证「总有得打」;移动侧则由普通移动兜底

### 职业行动模式倾向

| 职业倾向 | 典型模式 | 说明 |
|---------------|-----------------|-------------|
| 近战 DPS | 移动 → 标准动作技能 | 接近目标后使用高伤害技能 |
| 远程炮台 | 敏捷增益 → 标准动作技能 | 无需移动,专注放大输出 |
| 高机动游击 | 移动动作技能 → 基础攻击技能 | 位移技能接近/脱离后用基础攻击技能出手 |
| 防御坦克 | 敏捷防御 → 基础攻击技能 + 反应动作 | 主动回合简单,依赖反应动作 |
| 辅助 | 敏捷增益 → 标准动作治疗/增益 | 每回合一次增益一次治疗 |
| 纯施法者 - 特殊 | 移动动作 → 标准动作 → 敏捷动作 | 三种资源全用于技能,牺牲普通移动 |

### 再行动(特殊规则,规则锚:R3.2)

标准动作会消耗 1 点标准行动点并使剩余移动失效；只要仍有标准行动点,单位仍可继续使用标准动作。迅捷动作不消耗移动或标准行动点,只要仍有迅捷行动点即可使用,包括标准动作之后(见上文「迅捷动作」一节与 R3.2)。
由天赋 / 遗物 / 技能授予的**「再行动」是这条的例外**——在攻击后重新赋予行动,
重新赋予哪些行动资源由授予它的条目声明。

> **命名提醒**:本机制此前写作 Re-Action,与 R3.2 的反应动作 Reaction 仅差一个连字符,极易混淆。
> 中文统一用「再行动」;若需英文名,另择措辞,不要沿用 Re-Action。

---

## 多人游戏适配

- 在出手顺序系统下,同一时刻只有 1 个单位行动;只需同步当前行动者的 GameAction
- 所有操作都封装为 GameAction;单人下直接执行,多人下先广播再执行
- 行动资源状态(剩余移动力、是否已攻击、是否已用敏捷动作)作为回合状态同步

---

## 出手顺序 UI - 预留

- 专用 UI 显示当前行动队列
- 标记单位状态(Buff/Debuff 图标、HP 条)
- 速度变化时(Buff/Debuff 影响速度)动态更新队列
- 高亮当前行动者,预览接下来的 N 个行动者

---

## 常见误区

- 敏捷动作与标准动作叠加 → **允许**,它们消耗不同资源
- 移动动作与普通移动叠加 → **不允许**,二选一
- 一回合内两个标准动作技能 → **默认容量下不允许**；标准行动点容量提高到至少 2 时允许
- 每回合多个迅捷动作 → **默认容量下不允许**；迅捷行动点容量提高到至少 2 时允许
- 不移动直接攻击 → **允许**,但默认也消耗移动资源(除非有特殊天赋,否则攻击后不能移动)
- 移动后撤销 → **允许**,直到提交攻击或技能为止;之后移动被锁定
- 反应动作在自己回合触发 → **允许**,反应动作不限于特定时机
- 先攻 +2 的单位每回合行动两次 → **不会**,先攻只影响行动顺序

---

相关文档:
- [[battle-calculation|03 - Battle Calculation]] — 攻击结算流程(命中 → 暴击 → 伤害)
- [[skills-and-range|04 - Skill and Range]] — 技能数据结构中的 `action_cost` 与 `timing` 字段
- [[class-system|05 - Class System]] — 职业行动模式倾向
- [[talent-tree|06 - Talent Tree]] — 标注行动资源标签的天赋节点
