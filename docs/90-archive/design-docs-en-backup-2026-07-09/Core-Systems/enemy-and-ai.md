# 06 - Enemy and AI System

> Back to [[game-design-doc|GDD]]

## Overview

AI system for small-scale battlefields (≤10×10, enemies enter in waves). Design principle: **Simple scoring system, behavior is predictable but threatening**. Players should be able to infer enemy intent through observation.

---

## AI Behavior Patterns

```
AIBehavior: enum
  AGGRESSIVE    # Prioritize attacking, charge toward target
  DEFENSIVE     # Guard within area, only counter-attack when approached
  SUPPORT       # Prioritize healing/buffing allies
  HIT_AND_RUN   # Attack then disengage
  BOSS          # Special action pattern (fixed skill rotation)
```

```
EnemyUnit extends Unit:
  ai_behavior: AIBehavior
  target_priority: "nearest" | "lowest_hp" | "highest_threat" | "specific_class"
  patrol_zone: Rect2i | null    # Guard area for DEFENSIVE mode
```

---

## AI Decision Flow

For each enemy unit's action:

```
1. Enumerate all viable combinations:
   - Reachable destination cells (within BFS range)
   - Available skills at each destination
   - Attackable targets for each skill

2. Score each combination:
   score = expected_damage × 1.0
         + kill_bonus × 3.0         # Extra points for securing a kill
         + terrain_score × 0.5      # Points for moving to favorable terrain
         + behavior_weight           # Adjusted by AIBehavior
         - danger_penalty × 0.8     # Penalty for moving into enemy attack range

3. Behavior weight adjustments:
   AGGRESSIVE:  attack_score ×1.5, danger_penalty ×0.3
   DEFENSIVE:   penalty for leaving patrol_zone, bonus for defensive positions
   SUPPORT:     heal/buff_score ×2.0, attack_score ×0.3
   HIT_AND_RUN: bonus for moving away from target after attacking

4. Execute highest-scoring combination
   If no target is attackable → move toward nearest target (AGGRESSIVE) or wait in place (DEFENSIVE)
```

---

## Wave System

Enemies do not all appear at once; they join the battlefield in conditional waves.

```
WaveConfig:
  waves: Array[Wave]

Wave:
  trigger: WaveTrigger
  enemies: Array[EnemySpawn]
  announcement: String       # Entry announcement text

WaveTrigger:
  type: "turn" | "enemy_count" | "hp_threshold" | "immediate"
  value: int
  # "turn": Triggered after the Nth action round
  # "enemy_count": Triggered when enemies on field ≤ value
  # "hp_threshold": Triggered when Boss HP ≤ value%
  # "immediate": Appears at battle start

EnemySpawn:
  template_id: String      # References enemy template
  position: Vector2i       # Entry position
  initial_delay: int     # Turns skipped after entry (0 = act immediately, 1 = act next turn)
```

### Example - A Normal Battle

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
      "announcement": "Reinforcements have arrived!",
      "enemies": [
        { "template_id": "goblin_melee", "position": [9,7], "initial_delay": 0 },
        { "template_id": "goblin_shaman", "position": [8,8], "initial_delay": 0 }
      ]
    }
  ]
}
```

---

## Enemy Template

```json
{
  "id": "goblin_melee",
  "name": "Goblin Warrior",
  "base_stats": {
    "HP": 40, "STR": 10, "MAG": 2,
    "DEF": 5, "RES": 3,
    "DEX": 6, "SPD": 9, "LCK": 2,
    "MOV": 3, "VIS": 2
  },
  "growth_rates": {},
  "skills": ["slash"],
  "ai_behavior": "AGGRESSIVE",
  "target_priority": "nearest",
  "exp_reward": 15,
  "drop_table": [
    { "type": "gold", "amount": 10, "chance": 100 },
    { "type": "potion", "id": "potion_small_heal", "chance": 10 }
  ]
}
```

> 示例掉落表原有 `skill` 条目已移除（2026-07-02 用户裁决：技能不做掉落，来自职业固定模板 / 天赋 / 遗物；见 run-loop.md Reward System）。

---

## Enemy Tier and Affix System

> **2026-07-02 用户裁决（run-loop 门模式讨论）+ 2026-07-03 词条制修订**：敌人分五层阶梯；**词条 Affix = 类似人物被动的一种技能（不是 buff、不是 debuff）**；**特殊词条与基础词条分池、区别对待**。本节为骨架定稿；词条池条目与取值曲线为 [占位]/[提案]。

### Tier Ladder

| Tier | Where it appears | Affix count | Notes |
|------|------------------|-------------|-------|
| Normal | All battle types | 0 | 不具备词条 |
| Lesser Elite | 频率不低，混编在波次中 | 1-3 基础 | 普通房的日常变数 |
| Greater Elite | 较稀有，多作为**普通房收尾敌人** | 3-5 基础 | 普通房也有纹理梯度 |
| Elite Chief | **仅精英房出现**（门上骷髅标） | **大精英规格（3-5 基础）+ 1 特殊**，合计 4-6 | **特殊词条进房前可见、基础不可见**；奖励品质/数量更好 |
| Act Boss | Stage 8 固定 | 随难度 | **传奇敌人 + 独有机制系统**（每幕一套定制） |

- **词条数量在区间内按难度两轴取值**：开局难度档（类 Hades 热度，系统后置）× 幕数递进（Act 1 取下限 → Act 3 取上限——解决「Act 1 精英房应显著弱于 Act 3、且不只是数值」）。取值曲线 [占位]。
- **精英风险构成**：磨损（恢复不满额、只随开局难度档变动，见 run-loop.md）+ 相性赌（基础词条进房前不可见；特殊词条可见=可在 Prep 针对性换装对策）。

### Affix Design Notes

- **实现口径（2026-07-03 用户明确）**：词条=**类似人物被动的技能**——不走 buff/debuff 结构（ADR-002 不适用），需要敌方单位的**被动技能挂载点**（我方已有心眼这类被动先例）。词条以 JSON 声明式定义（`data/affixes/`），normal 层恒为空。
- **两池分开、区别对待（2026-07-03 用户裁决）**：**基础词条池**=单位被动（示例方向：反击强化、先手部署、受治疗减半、~~控制区扩大~~（随 ZOC 机制全面删除作废，2026-07-06）；~~拆建筑~~ 随城镇 v1 不做、建筑不作可攻击目标而移除，2026-07-04）；**特殊词条池**=房间签名级、更大更醒目的机制（接近 Hades 房间修饰的存在感），仅精英房头目持有。
- **可见性与可读性**：特殊词条在门上进房前可见 [已定]；基础词条进房前不可见、入场后战斗内点选敌人以图标+说明可读 [提案]——玩家要能围绕词条布阵对策，相性赌才「可对冲」。Prep「View Intel」只显示特殊词条与常规敌情。
- **池规模**：v1 基础池约 12-15 个 [占位] + 特殊池 6-8 个 [占位]；v0 基础 5 个左右 + 特殊 1-2 个验证手感 [占位]。

### Schema Extension

```
EnemyTemplate 新增字段（2026-07-03 词条制）:
  tier: "normal" | "lesser_elite" | "greater_elite" | "elite_chief" | "act_boss"
  base_affixes: Array[affixId]    # 基础词条（被动技能）；数量按 tier 区间 x 难度两轴取值；normal 恒为空
  special_affix: affixId | null   # 仅 elite_chief：特殊词条，进房前可见；与基础词条分池（data/affixes/base 与 data/affixes/special）
```

> **v0 词条引擎已实装（2026-07-04，分支 `claude/runloop-v0-door-loop`）**：被动挂载点按方案 A（与心眼同构：spawn 后注入 → 缓存字段 → `get_effective_stat` / `damage_calculator` 读，不走 BuffEffect）实装于 `Ship_of_Theseus/scripts/units/unit.gd`（`apply_affixes`）+ `scripts/core/tactical_manager.gd`（`_apply_affixes` 时机分发器）+ `damage_calculator.gd`（affix 乘区）；波次数据 `data/waves/` 的 enemy entry 带 `affixes`/`special_affix`/`stat_scale`，`spawn_unit` 后注入。**无词条单位零影响**（心眼式门控，剑圣 81 断言实证）。v0 词条池 5 基础（`data/affixes/base`）+ 2 特殊（`data/affixes/special`）[占位]。**词条效果状态**：数值增强 stat_scale / afs_frenzy 低血增伤 / af_heal_resist 受治疗减半 / af_counter_boost 反击强化 / af_vanguard 首回合速度 / afs_bulwark 减伤光环 = **已真实生效**；~~af_zone_expand 控制区扩大~~ 随 ZOC 机制全面删除作废（2026-07-06 用户裁决，Godot 侧移除待 SoT 组执行）；**af_siege 攻城已废弃移除**（2026-07-04 用户裁决：城镇 v1 不做 → 建筑不作可攻击目标，相关职业与词条随之移除）。回归 `tests/test_affix_system.gd` + `test_affix_effects.gd`。实装进度详见记忆 `runloop-v0-session-log`。

---

## Boss Design Direction

Act Bosses are **legendary-tier** enemies (see Enemy Tier and Affix System above): affix count scales with difficulty, and each has a **unique mechanic system**（2026-07-02 用户裁决；每幕一套定制内容）. Bosses use a special AI mode with fixed skill rotations or phase changes:

```
BossAI:
  phases: Array[BossPhase]

BossPhase:
  hp_threshold: int          # HP percentage to enter this phase
  skill_rotation: Array[String]  # Fixed skill rotation
  behavior_override: AIBehavior
  summon_wave: Wave | null   # Summon reinforcements on phase transition
```

Boss readability is important — players should be able to learn the Boss's pattern within a few attempts.

---

Related documents:
- [[grid-and-map|02 - Grid and Map]] — Enemy placement positions on maps
- [[skills-and-range|04 - Skill and Range]] — Skill definitions used by enemies
- [[run-loop|07 - Run Loop]] — Battle difficulty progression within a Run
