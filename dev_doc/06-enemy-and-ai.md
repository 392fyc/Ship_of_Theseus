# 06 - 敌人与AI系统

> 返回 [总纲](./README.md)

## 概述

小规模战场（≤10×10，敌人分批入场）下的AI系统。设计原则：**简单评分制，行为可预测但有威胁**。玩家应该能通过观察推断敌人意图。

---

## AI行为模式

```
AIBehavior: enum
  AGGRESSIVE    # 优先攻击，冲向目标
  DEFENSIVE     # 守在区域内，被接近才反击
  SUPPORT       # 优先治疗/Buff队友
  HIT_AND_RUN   # 攻击后拉开距离
  BOSS          # 特殊行动模式（固定技能循环）
```

```
EnemyUnit extends Unit:
  ai_behavior: AIBehavior
  target_priority: "nearest" | "lowest_hp" | "highest_threat" | "specific_class"
  patrol_zone: Rect2i | null    # DEFENSIVE模式的守卫区域
```

---

## AI决策流程

每个敌方单位行动时：

```
1. 枚举所有可行组合:
   - 可移动的目标格（BFS范围内）
   - 每个目标格可使用的技能
   - 每个技能可攻击的目标

2. 对每个组合评分:
   score = 预期伤害 × 1.0
         + 击杀奖励 × 3.0        # 能击杀目标额外加分
         + 地形评分 × 0.5        # 移动到有利地形加分
         + 行为权重              # 根据AIBehavior调整
         - 危险惩罚 × 0.8       # 移动到敌方攻击范围内扣分

3. 行为权重调整:
   AGGRESSIVE:  攻击得分 ×1.5, 危险惩罚 ×0.3
   DEFENSIVE:   离开patrol_zone扣分, 防守位置加分
   SUPPORT:     治疗/Buff得分 ×2.0, 攻击得分 ×0.3
   HIT_AND_RUN: 攻击后远离目标加分

4. 选择最高分组合执行
   若无法攻击任何目标 → 向最近目标移动（AGGRESSIVE）或原地等待（DEFENSIVE）
```

---

## 分批入场（Wave System）

敌人不一次性全部出现，按条件分批加入战场。

```
WaveConfig:
  waves: Array[Wave]

Wave:
  trigger: WaveTrigger
  enemies: Array[EnemySpawn]
  announcement: String       # 入场提示文本

WaveTrigger:
  type: "turn" | "enemy_count" | "hp_threshold" | "immediate"
  value: int
  # "turn": 第N个行动轮次后触发
  # "enemy_count": 场上敌人数≤value时触发
  # "hp_threshold": Boss血量≤value%时触发
  # "immediate": 战斗开始立即出现

EnemySpawn:
  template_id: String      # 引用敌人模板
  position: Vector2i       # 入场位置
  initial_delay: int     # 入场后跳过的回合数（0=立即可行动，1=下回合才行动）
```

### 示例：一场普通战斗

```json
{
  "waves": [
    {
      "trigger": { "type": "immediate" },
      "enemies": [
        { "template_id": "goblin_melee", "position": [7,3], "initial_delay": 0 },
        { "template_id": "goblin_melee", "position": [8,4], "initial_delay": 0 },
        { "template_id": "goblin_archer", "position": [9,2], "initial_delay": 0 }
      ]
    },
    {
      "trigger": { "type": "enemy_count", "value": 1 },
      "announcement": "增援到达！",
      "enemies": [
        { "template_id": "goblin_melee", "position": [9,7], "initial_delay": 0 },
        { "template_id": "goblin_shaman", "position": [8,8], "initial_delay": 0 }
      ]
    }
  ]
}
```

---

## 敌人模板

```json
{
  "id": "goblin_melee",
  "name": "哥布林战士",
  "stats": {
    "hp": 40, "attack": 10, "magic": 2,
    "defense": 5, "resistance": 3, "speed": 9,
    "move": 3, "hit": 75, "evade": 10, "crit": 5
  },
  "skills": ["slash"],
  "ai_behavior": "AGGRESSIVE",
  "target_priority": "nearest",
  "exp_reward": 15,
  "drop_table": [
    { "type": "gold", "amount": 10, "chance": 100 },
    { "type": "skill", "id": "power_strike", "chance": 10 }
  ]
}
```

---

## Boss设计方向

Boss使用特殊AI模式，有固定的技能循环或阶段变化：

```
BossAI:
  phases: Array[BossPhase]

BossPhase:
  hp_threshold: int          # 进入该阶段的HP百分比
  skill_rotation: Array[String]  # 固定技能循环
  behavior_override: AIBehavior
  summon_wave: Wave | null   # 阶段转换时召唤增援
```

Boss可读性很重要——玩家应该能通过几次尝试学会Boss的模式。

---

相关文档：
- [02-网格与地图](./02-grid-and-map.md) — 地图上的敌人配置位置
- [04-技能与射程](./04-skills-and-range.md) — 敌人使用的技能定义
- [07-Run循环](./07-run-loop.md) — 战斗难度在Run中的递增
