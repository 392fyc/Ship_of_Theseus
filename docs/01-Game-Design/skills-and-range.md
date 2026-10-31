# 04 - 技能与射程系统(Skill and Range System)

> 返回 [[game-design-doc|GDD]]

## 概览

每件武器/技能拥有独立的射程形态与效果范围,再配合冷却与附加效果,构成丰富的战术选择。

---

## 技能数据结构

```
Skill:
  id: String
  name: String
  damage_type: "physical" | "magical" | "pure" | "hybrid"   # Damage type (determines defense calculation)
  attack_type: "melee" | "ranged" | "area"                  # Attack method (determines special interactions)
  power: int              # Skill multiplier (100 = base, 150 = 1.5x)
  hit_bonus: int          # Additive bonus to derived Hit (weapon_hit + DEX*2; LCK 不参与命中链, R1.2)
  crit_bonus: int         # Additive bonus to derived Crit (weapon_crit + DEX/2)
  range: RangePattern     # Castable range
  area: AreaPattern       # Effect area after hit
  cooldown: int           # Cooldown (wait N turns after use before reuse)
  action_cost: "move" | "standard" | "swift" | "reaction" | "free"  # Action resource consumed ("free" consumes none)
  timing_constraint: "any" | "before_move" | "after_move" | "before_attack" | "after_attack"
  swift_limit: int = 1    # 迅捷技能每回合使用次数上限;1 = R3.2 的初始值
  effects: Array[Effect]  # Additional effects
  effect_timing: "on_hit" | "after_damage"  # Effect trigger timing (default on_hit)
  # pre_move / post_attack_move 两个 flag 从未实装，引擎中不存在同名字段：
  #   pre_move        —— 语义已由上方 timing_constraint 的 "before_move" 承担，不要再新增 flag
  #   post_attack_move —— 已由 R3.2 的特殊规则「再行动」取代（攻击后重新赋予行动，
  #                       重新赋予哪些资源由授予它的条目声明）；不要再按 bool flag 建模
  description: String
```

### 属性类型与攻击方式说明

- **damage_type**:决定伤害公式采用哪套防御计算(physical 减 DEF / magical 减 RES / pure 无视防御 / hybrid 物理与魔法各算一次再取算术平均)。见 → [[battle-calculation|03 - Battle Calculation]] 伤害类型系统
- **attack_type**:由技能声明,不受实际攻击距离影响
  - `melee`:技能射程仅 1 格
  - `ranged`:技能射程 > 1 格(即使实际攻击 1 格外目标仍算 ranged)
  - `area`:技能带 AOE 范围(即使只命中单目标仍算 area)
- **hit_bonus**:在派生命中计算(`weapon_hit + DEX*2`,即 R1.2 命中链第一层 base_hit)之后作用;LCK 不参与命中链
- **crit_bonus**:在 R1.3 派生暴击计算(`weapon_crit + DEX/2`)之后作用

### 技能分类(设计库层)

设计库额外沿**两条正交维度**对每个技能分类,独立于上文引擎侧的 `action_cost` 分类体系:

- **`skill_type`** —— 技能*做什么*(attack / mobility / buff / support / control)。Support 涵盖治疗。
- **`resource_type`** —— 技能消耗哪种每回合行动资源(standard / swift / move / reaction / none)。「None」保留给完全被动、无主动触发成本的技能(尚无任何真实技能使用)。

这两个字段存在设计库的 `Skill` 记录上(中文枚举值,用于设计叙述/审阅),与上文引擎侧的 `action_cost` 字段(英文值,由 Godot 消费)是**两套独立分类**。不要混为一谈——技能的 `resource_type` 与其引擎 `action_cost` 应描述同一现实资源,但它们是独立维护的字段,不是单一共享枚举。

当前 5 技能阵容(剑圣线)按此方案分类:

| 技能 | skill_type | resource_type |
|-------|-----------|----------------|
| 斩击(Slash) | Attack | Standard |
| 居合(Iaijutsu) | Attack | Standard |
| 拔刀(Batto) | Attack | Standard |
| 一闪(Flash Step) | Mobility | Move |
| 招架(Parry) | Buff(自身指向) | Swift |

招架归类为 Buff 而非独立的「Stance/Reaction」类别——其 `range.type = self` 已完整表达「目标恒为自身」,无需为该约束单设 skill_type。

### 时机约束

- `any`:无时机限制
- `before_move`:只能在单位本回合消耗移动之前使用
- `after_move`:只能在单位移动之后使用
- `before_attack`:只能在单位消耗其标准攻击机会之前使用
- `after_attack`:只能在单位攻击之后使用

见 → [[battle-calculation|03 - Battle Calculation]] 单位回合序列

---

## 射程形态(Range Pattern)

定义「技能能瞄准多远」。

```
RangePattern:
  type: "diamond" | "line" | "cross" | "square" | "self"
  min_range: int    # Minimum range
  max_range: int    # Maximum range
```

### 类型说明

**diamond** —— 最常见,曼哈顿距离

```
min=1, max=2:        min=2, max=3:
  . X .              . . X . .
  X X X              . X . X .
  . X .              X . . . X
  X X X              . X . X .
  . X .              . . X . .
                     (center not selectable)
```

**line** —— 从四个正方向中选一个

```
max=3:
  . . . X            X
  . . . .            .
  X . ★ .    or      ★
  . . . .            .
  . . . X            X
```

**cross** —— 四个正方向同时

```
max=2:
    X
    X
  X X ★ X X
    X
    X
```

**self** —— 仅自身位置(buff/治疗类技能)

---

## 效果范围(Area Pattern)

定义「命中点周围受影响的区域有多大」。

```
AreaPattern:
  type: "single" | "diamond" | "line" | "cross" | "square"
  size: int
```

- **single**:仅目标格
- **diamond(1)**:目标格 + 相邻 4 格 = 5 格
- **diamond(2)**:13 格菱形区域
- **line(2)**:从施放方向延伸 2 格的直线
- **square(1)**:以目标为中心的 3×3 方形 = 9 格

---

## 技能示例

| 技能 | 类型/方式 | 射程 | 范围 | CD | 说明 |
|-------|-------------|-------|------|----|-------------|
| Slash | physical/melee | diamond 1-1 | single | 0 | 基础近战攻击 |
| Heavy Strike | physical/melee | diamond 1-1 | single | 1 | 150% 倍率 |
| Quick Slash | physical/melee | diamond 1-1 | single | 0 | 80% 倍率,无冷却 |
| Shot | physical/ranged | diamond 2-4 | single | 0 | 基础远程攻击 |
| Snipe | physical/ranged | diamond 3-5 | single | 2 | 超远射程,高命中 |
| Fireball | magical/area | diamond 2-4 | diamond(1) | 2 | 5 格 AOE |
| Ice Spell | magical/ranged | diamond 1-3 | single | 1 | 施加减速 |
| Heal | magical/ranged | diamond 0-3 | single | 1 | 恢复 HP |
| Healing Aura | magical/area | self | diamond(2) | 3 | 大范围治疗 |
| Lunge Strike | physical/melee | line 2-3 | single | 1 | 移动至目标并攻击 |

---

## 附加效果(Additional Effects)

```
Effect:
  type: String          # Effect type
  chance: int           # Base trigger probability (%), affected by target LCK
  duration: int         # Duration in turns (decremented at unit turn end)
  value: int            # Effect value
  timing: "on_hit" | "after_damage"  # Trigger timing (default on_hit)

Actual application rate = chance × max(0.1, 1 - defender.LCK / 100)

Common effect types:
  "burn"         - Takes value damage at unit turn start
  "poison"       - Takes value damage at unit turn start (usually longer duration)
  "slow"         - SPD reduced by value (affects next turn order)
  "haste"        - SPD increased by value (affects next turn order)
  "stun"         - Checked at unit turn start, skips action
  "freeze"       - Skips action, removed early when attacked
  "defense_up"   - DEF increased by value
  "defense_down" - DEF decreased by value
  "priority_up"  - Initiative priority +value (1 or 2), affects next turn order
```

### 两种效果时机

| 时机 | 说明 | 例子 |
|--------|-------------|---------|
| on_hit | 命中即触发,不论伤害 | Debuff 施加(减速、中毒)、标记效果 |
| after_damage | 伤害结算后触发 | 吸血(按实际伤害)、击杀触发效果 |

见 → [[battle-calculation|03 - Battle Calculation]] 攻击结算流程

---

## 技能数据文件示例

```json
{
  "id": "fireball",
  "name": "Fireball",
  "damage_type": "magical",
  "attack_type": "area",
  "power": 120,
  "hit_bonus": 10,
  "crit_bonus": 0,
  "range": { "type": "diamond", "min": 2, "max": 4 },
  "area": { "type": "diamond", "size": 1 },
  "cooldown": 2,
  "action_cost": "standard",
  "timing_constraint": "any",
  "effects": [
    { "type": "burn", "chance": 30, "duration": 3, "value": 10 }
  ],
  "description": "Hurl a fireball at the target, explosion radius 1 cell, chance to apply burn"
}
```

---

相关文档:
- [[battle-calculation|03 - Battle Calculation]] —— 技能倍率如何参与伤害公式
- [[turn-system|01 - Turn System]] —— SPD 如何决定出手顺序

## 永久升级、临时替换与同槽形态

当前已经存在永久升级、状态期间的临时替换和按资源条件占用同一技能槽的真实设计对象，三者必须分开理解：

- **永久升级**会在本局中完整取代基础技能，升级技能本身保存完整的名称、效果、动作、射程、范围、资源消耗和冷却。明确作用于基础技能的效果按 R2.5 默认也作用于升级版本，但只能修改升级技能实际存在的内容；纯防御形态不会因此凭空获得攻击或伤害。
- **临时替换**只在来源声明的状态或时段内，把当前技能槽换成另一条完整技能；条件结束后恢复原技能。临时形态不是第二次永久升级，也不自动继承永久升级的全部语义。
- **条件同槽形态**由当前资源或状态决定显示哪一形态。按 R3.6，形态只有在条件成立且自身已经结束冷却时才替换原技能；仍在冷却时保留原技能。各形态的冷却独立记录，离开技能槽后仍继续经过。
- **动态显示名**可以属于同一个技能身份，只改变当前展示名称，不因此产生多套独立冷却。

每个非永久形态仍应有完整技能记录或等价的结构化定义，来源只保存“何时出现、何时消失、占用哪个槽位”的单向关系，不复制技能正文，不建立互相指向的循环。玩家文案负责让玩家理解技能如何出现，结构化关系负责校验与导入，禁止从玩家文案反推关系。

当前设计库只能直接表达一张回忆天赋指向一个升级技能，尚不能完整表示一张天赋下的多个条件形态、动态显示名和临时替换关系。现阶段以版本化迁移检查点保存真实关系；不得为了适配单一 `upgrade_skill_id`，把不同形态压成一套虚假的统一字段。剑圣当前对象及缺口见 [[Characters/kensei-memory-upgrades|剑圣回忆升级]]。
