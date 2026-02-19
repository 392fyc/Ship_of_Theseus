# 04 - 技能与射程系统

> 返回 [总纲](./README.md)

## 概述

每个武器/技能拥有独立的射程模式和效果范围，配合冷却和附加效果形成丰富的战术选择。

---

## 技能数据结构

```
Skill:
  id: String
  name: String
  element_type: "physical" | "magical" | "holy" | "hybrid"  # 属性类型（决定防御计算）
  attack_type: "melee" | "ranged" | "area"                  # 攻击方式（决定特殊交互）
  power: int              # 技能倍率（100=基础，150=1.5倍）
  hit_bonus: int          # 命中修正（加法）
  crit_bonus: int         # 暴击修正（加法）
  range: RangePattern     # 可释放的射程
  area: AreaPattern       # 命中后的影响范围
  cooldown: int           # 冷却（使用后需等待N回合才可再用）
  effects: Array[Effect]  # 附加效果
  effect_timing: "on_hit" | "after_damage"  # 附加效果触发时机（默认on_hit）
  pre_move: bool = false          # 是否可在移动前使用
  post_attack_move: bool = false  # 使用后是否允许再移动（需职业也支持）
  description: String
```

### 属性类型与攻击方式说明

- **element_type**：决定伤害公式中使用哪种防御计算。详见 → [03-战斗计算](./03-battle-calculation.md) 伤害类型体系
- **attack_type**：由技能固定声明，不受实际攻击距离影响
  - `melee`：技能射程仅为1格
  - `ranged`：技能射程>1格（即使实际攻击1格距离的目标也是远程）
  - `area`：技能有AOE范围（即使只命中单体也是范围）

详见 → [03-战斗计算](./03-battle-calculation.md) 中的角色回合时序

---

## 射程模式（RangePattern）

定义技能"可以对多远的目标释放"。

```
RangePattern:
  type: "diamond" | "line" | "cross" | "square" | "self"
  min_range: int    # 最小射程
  max_range: int    # 最大射程
```

### 类型说明

**diamond（菱形）** — 最常用，曼哈顿距离

```
min=1, max=2:        min=2, max=3:
  . X .              . . X . .
  X X X              . X . X .
  . X .              X . . . X
  X X X              . X . X .
  . X .              . . X . .
                     (中心不可选)
```

**line（直线）** — 四方向任选一条直线

```
max=3:
  . . . X            X
  . . . .            .
  X . ★ .    或      ★
  . . . .            .
  . . . X            X
```

**cross（十字）** — 四方向同时

```
max=2:
    X
    X
  X X ★ X X
    X
    X
```

**self** — 仅自身位置（buff/回复类）

---

## 效果范围（AreaPattern）

定义技能"命中点周围影响多大面积"。

```
AreaPattern:
  type: "single" | "diamond" | "line" | "cross" | "square"
  size: int
```

- **single**：仅命中目标格
- **diamond(1)**：目标格 + 上下左右 = 5格
- **diamond(2)**：13格菱形范围
- **line(2)**：从释放方向延伸2格的直线
- **square(1)**：目标格为中心的3×3方形 = 9格

---

## 技能示例

| 技能 | 属性/方式 | 射程 | 范围 | 冷却 | 说明 |
|------|---------|------|------|------|------|
| 斩击 | physical/melee | diamond 1-1 | single | 0 | 近战基础攻击 |
| 重击 | physical/melee | diamond 1-1 | single | 1 | 150%倍率 |
| 快速斩 | physical/melee | diamond 1-1 | single | 0 | 80%倍率，无冷却 |
| 射击 | physical/ranged | diamond 2-4 | single | 0 | 远程基础攻击 |
| 狙击 | physical/ranged | diamond 3-5 | single | 2 | 超远程，高命中 |
| 火球术 | magical/area | diamond 2-4 | diamond(1) | 2 | 5格AOE |
| 冰冻术 | magical/ranged | diamond 1-3 | single | 1 | 附加减速 |
| 治疗 | holy/ranged | diamond 0-3 | single | 1 | 回复HP |
| 治疗光环 | holy/area | self | diamond(2) | 3 | 大范围回复 |
| 突进斩 | physical/melee | line 2-3 | single | 1 | 移动到目标旁攻击 |

---

## 附加效果（Effect）

```
Effect:
  type: String          # 效果类型
  chance: int           # 基础触发概率（%），受目标resistance影响
  duration: int         # 持续回合数（在角色回合结束时扣减）
  value: int            # 效果数值
  timing: "on_hit" | "after_damage"  # 触发时机（默认on_hit）

实际附加率 = chance × (1 - defender.resistance / 100)

常见效果类型:
  "burn"         - 角色回合开始时受到value点伤害
  "poison"       - 角色回合开始时受到value点伤害（通常持续更久）
  "slow"         - speed降低value点（影响下回合行动顺序）
  "haste"        - speed增加value点（影响下回合行动顺序）
  "stun"         - 角色回合开始时检查，跳过本次行动
  "freeze"       - 跳过行动，受到攻击时提前解除
  "defense_up"   - physical_defense增加value点
  "defense_down" - physical_defense降低value点
  "priority_up"  - 先制优先级+value（1或2），影响下回合排序
```

### 两种附加效果时机

| 时机 | 说明 | 示例 |
|------|------|------|
| on_hit（命中后） | 攻击命中即触发，与伤害无关 | Debuff附加（减速、中毒）、标记效果 |
| after_damage（伤害后） | 伤害结算完成后触发 | 吸血（基于实际伤害）、击杀触发效果 |

详见 → [03-战斗计算](./03-battle-calculation.md) 攻击结算流程

---

## 技能数据文件示例

```json
{
  "id": "fireball",
  "name": "火球术",
  "element_type": "magical",
  "attack_type": "area",
  "power": 120,
  "hit_bonus": 10,
  "crit_bonus": 0,
  "range": { "type": "diamond", "min": 2, "max": 4 },
  "area": { "type": "diamond", "size": 1 },
  "cooldown": 2,
  "effects": [
    { "type": "burn", "chance": 30, "duration": 3, "value": 10 }
  ],
  "description": "向目标投掷火球，爆炸范围1格，有几率附加燃烧"
}
```

---

## 技能槽位限制

角色不能装备所有已获得的技能，需要在Build中做选择：

```
UnitBuild:
  active_skills: Array[Skill]  # 最多4个主动技能槽
  passive_skills: Array[Skill] # 最多2个被动技能槽（待定）
```

详见 → [05-职业系统](./05-class-system.md)

---

相关文档：
- [03-战斗计算](./03-battle-calculation.md) — 技能倍率如何参与伤害公式
- [01-回合系统](./01-turn-system.md) — 速度如何决定行动顺序
