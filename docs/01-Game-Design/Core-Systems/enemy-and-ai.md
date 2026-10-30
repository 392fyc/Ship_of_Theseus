# 07 - 敌人与 AI 系统

> 返回 [[game-design-doc|GDD]]

## 概览

面向小规模战场的 AI 系统(≤10×10,敌人分波入场)。设计原则:**评分系统从简,行为可预测但有威胁**。玩家应能通过观察推断敌人意图。

---

## AI 行为模式

```
AIBehavior: enum
  AGGRESSIVE    # Prioritize attacking, charge toward target
  DEFENSIVE     # Guard within area, only attack when approached
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

## AI 决策流程

针对每个敌方单位的行动:

```
1. Enumerate viable movement-and-skill plans:
   - Reachable destination cells (within BFS range)
   - Available skills at each destination
   - Legal target set for evaluating each skill, without locking one target yet

2. Score each movement-and-skill plan under the unit's normal logic:
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

4. Choose the highest-scoring destination and intended skill

5. Choose the target from that skill's legal target set:
   - If the skill selects an enemy unit and at least one legal target has Taunt,
     restrict the candidates to legal Taunt targets, then apply the normal target priority
   - Otherwise apply the normal target priority to the full legal target set
   - Skills targeting a cell, direction, area, self, ally, or no target ignore Taunt

6. Execute the chosen plan
   If no target is attackable → move toward nearest target (AGGRESSIVE) or wait in place (DEFENSIVE)
```

嘲讽只改变已经选定的移动与技能所使用的单位目标，不重新决定移动或技能。先选择单位再展开范围的技能仍受嘲讽影响；目标锁定后，即使嘲讽在结算前消失也不重新选目标。对嘲讽免疫的单位按原逻辑选择目标。完整口径见 R1.18。

### 现行实现：普通攻击与攻击技能的加权打分

上面的流程是目标设计。引擎里目前只实现了其中普通攻击的部分，代码在 `scripts/core/enemy_ai.gd`，权重在 `data/ai/target_scoring.json`。各项取舍由用户在 2026-10-30 的方案页上选定，都选了推荐项。

- **得分** = 命中率 × 有效伤害 × `damage_weight` + 击杀概率 × `kill_bonus`；目标是〔影〕时再加 `decoy_bonus`。
  - 有效伤害：伤害超过目标剩余耐久（生命加护盾）的部分不算。
  - 击杀概率：普通伤害够击杀时等于命中率；只有暴击才够击杀时，等于命中率 × 暴击率。
  - 命中率、暴击率、伤害和暴击伤害都取伤害预告的同一套上下文与公式，所以 AI 的估算和玩家看到的预告一致。
  - 上面第 2 步的 `kill_bonus × 3.0` 没有给出量级。现行取「击杀相当于 10 点伤害」，这是占位值。
- **站位**：敌人比较原地和所有可达空格上的每个可打目标，选总分最高的一组。即使射程内已经有目标，也照样比较移动后的出手，所以敌人会多走一步去收掉残血。本回合已经移动过时只比较原地。站位本身的地形分和危险扣分首期不做（第 2 步的另两项）。
- **〔影〕**：〔影〕每次挨打固定只掉 1 点生命，期望伤害很低，所以另加诱饵分 6（推断），让敌人愿意打它。诱饵分有上限：〔影〕剩 2 点以上时得分是 1 + 6 = 7；命中率 80%、剩 6 点生命、7 点伤害的目标得分是 0.8 × 6 + 0.8 × 10 = 12.8，敌人先打它。命中率低或只有暴击才能击杀的目标得分可能低于 7，这时敌人会打〔影〕。
- **嘲讽**：先按得分定下站位，再在该站位射程内的嘲讽单位里按得分选目标（R1.18）。
- **同分**：依次比较能否击杀、移动消耗、目标剩余生命、目标所在格（先比 y 再比 x），最后比站位格。全程不掷骰，玩家可以预判敌人打谁。
- **攻击技能**：普攻与技能组里的攻击技能放在一起比较，选得分最高的位置、攻击与目标。
  - 单体技能沿用上面的得分。
  - 范围技能（AOE）的得分是范围内每个目标的「命中率 × 有效伤害 × `damage_weight`」之和，不加击杀分和诱饵分。不在目标格上的单位按技能的溅射比例（`splash_damage_pct`）预告，与实际结算一致。
  - 单体得分和 AOE 得分直接比较。
  - 冷却、行动点和使用时机沿用玩家施放的同一套校验。冷却中的技能不参与比较。
  - 嘲讽只作用于先选单位的技能；以格子或方向为目标的技能不受嘲讽影响（R1.18）。
  - 同分时普攻在前，技能按技能组顺序。
  - AI 决策时单位还没移动；技能的范围和方向在移动之后按当时的位置重新构建。如果移动没有发生、目标格已不是合法的施放方式，这次技能跳过。
- **功能技能**（没有伤害的增益、减益与治疗）：可用就用。
  - 按技能组顺序，第一个有合法施放方式的标准动作技能取代这回合的攻击；迅捷技能在最终站位上另外各用一次，排在主动作之前。已有主动作时，迅捷技能只在主动作的站位施放。
  - 减益：优先打这个敌人攻击时会选的目标，其次按范围内目标的攻击得分之和；走几步能够得着也算可用。选单位的减益在站位定下后优先嘲讽单位（R1.18）。
  - 治疗：只在有人缺血时用，按实际补回的生命之和选。
  - 选单位的单体友方增益（护盾术）给生命比例最低的友军；范围或自身增益按「还没有这些状态」的友军人数选，人数为 0 时不用。
  - 同分时移动少的优先，再比站位格与目标格（先 y 后 x）。
  - 没有伤害但作用于敌方的技能（诅咒）在数据里写 `target_relation: "enemy"`，引擎按敌对效果施加（过状态抵抗），不掷命中。
- **没有普攻的单位**：数据写 `"basic_attack": false`（牧师）。没有可用技能时不攻击，走到离最近友军最近的格子待命；相同时离玩家单位远的优先。
- **命中修正**：状态的 `stat_key` 写 `HIT` 时加在攻击者的命中上（R1.2「攻击者的命中加减」），诅咒用它降低 20。
- **尚未实现**：`ai_behavior` 和 `target_priority` 不读，反击风险不计。有普攻但打不到任何人时，敌人走向最近的玩家单位。
- **参照**：火纹 8 也是多项相加。资料来源是社区反编译 fireemblem8u 的 `src/cp_battle.c`，函数 `AiComputeCombatScore`。各项是：伤害（封顶 40，能击杀时直接给 50）、对方生命低、友军邻近、职业、回合数，再减去自己预计受到的伤害、所在格的危险和自己生命低。「对方生命低」只是其中一项。

### 用户裁决：普通敌人的技能组与技能使用（2026-10-31）

用户原话：「敌人和我们一样有一套技能组。大部分敌人技能组里只有一个攻击技能，AI只决定能攻击复数单位时打谁，从什么位置打。如果是AOE，怎么打最大化。而两个攻击技能一般指，例如一个单位同时可以近战或者远程，那此时攻击距离都满足时，AI决定该单位是使用近战还是使用远程。而增益，减益类指的是，单位额外拥有这种技能，这种技能一般有冷却时间。单位会倾向于能使用该类技能时优先使用该类技能。」

逐项收束的结论：

| 问题 | 裁决 |
|---|---|
| AOE 怎么算「最大化」 | 只比总期望伤害，不加击杀分 |
| 近战和远程都够得着时用哪个 | 比得分，用高的 |
| 增益、减益技能怎么「优先」 | 可用就用。占用标准行动点的，用了这回合就不攻击；迅捷技能用完照常攻击 |
| 减益给谁、要不要移动 | 移动后够得着也算可用；目标取这个敌人攻击时会选的那一个 |
| 友军增益与治疗 | 可用就用。增益选覆盖友军最多的落点；治疗只在有友军缺血时用，给实际补回生命最多的那一个 |
| 牧师没事可做时 | 靠近友军待命 |
| 护盾术给谁 | 生命比例最低的友军 |
| Boss 与精英 | 不按常规敌人做，以后单独做（「Boss和精英是特殊个体，有特殊行动」） |
| 站位的危险扣分 | 仍以后做 |

用户定的哥布林技能组（数值未给出的部分由 Claude 推定，标「占位」）：

| 敌人 | 技能组 |
|---|---|
| 战士 `goblin_melee` | 攻击（近战） |
| 弓手 `goblin_archer` | 攻击（远程） |
| 勇士 `goblin_brave` | 攻击（近战）、攻击（远程，`goblin_brave_throw`） |
| 法师 `goblin_mage` | 攻击（1–2 格）、AOE（射程 1–2，范围为 2 的菱形，`goblin_mage_burst`） |
| 萨满 `goblin_shaman` | 攻击（1–2 格）、诅咒（命中 −20，持续 1 回合，冷却 4，标准，`goblin_curse`） |
| 牧师 `goblin_priest` | 治疗（1 格，`goblin_priest_heal`）、护盾术（单体，1–2 格，冷却 4，迅捷，`goblin_priest_shield`） |

「法术不可回避」不是设计：用户 2026-10-31 问「谁说过法术不可回避了？？」。这个说法由代理在设计库 #59 写进〔临摹〕，又在 #80 照搬进〔若即〕，已在设计库 #81 删除。现在「不可回避」只指技能数据里明确写了的攻击（目前就是必中）。

---

## 波次系统

敌人不会一次性全部出现,而是按条件分波加入战场。

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

### 示例 - 一场普通战斗

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

## 敌人模板

```json
{
  "id": "goblin_melee",
  "name": "Goblin Warrior",
  "base_stats": {
    "HP": 40, "STR": 10, "MAG": 2,
    "DEF": 5, "RES": 3,
    "DEX": 6, "SPD": 9, "LCK": 2,
    "MOV": 3
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

> 掉落表不含技能——技能来自职业固定模板 / 天赋 / 遗物（见 run-loop.md Reward System）。

---

## 敌人层级与词条系统

> 敌人分五层阶梯；**词条 Affix = 类似人物被动的一种技能（不是 buff、不是 debuff）**；**特殊词条与基础词条分池、区别对待**。本节为骨架定稿；词条池条目与取值曲线为 [占位]/[提案]。

### 层级阶梯

| Tier | Where it appears | Affix count | Notes |
|------|------------------|-------------|-------|
| Normal | All battle types | 0 | 不具备词条 |
| Lesser Elite | 频率不低，混编在波次中 | 1-3 基础 | 普通房的日常变数 |
| Greater Elite | 较稀有，多作为**普通房收尾敌人** | 3-5 基础 | 普通房也有纹理梯度 |
| Elite Chief | **仅精英房出现**（门上骷髅标） | **大精英规格（3-5 基础）+ 1 特殊**，合计 4-6 | **特殊词条进房前可见、基础不可见**；奖励品质/数量更好 |
| Act Boss | Stage 8 固定 | 随难度 | **传奇敌人 + 独有机制系统**（每幕一套定制） |

- **词条数量在区间内按难度两轴取值**：开局难度档（系统后置）× 幕数递进（Act 1 取下限 → Act 3 取上限——解决「Act 1 精英房应显著弱于 Act 3、且不只是数值」）。取值曲线 [占位]。
- **精英风险构成**：磨损（恢复不满额、只随开局难度档变动，见 run-loop.md）+ 相性赌（基础词条进房前不可见；特殊词条可见=可在 Prep 针对性换装对策）。

### 词条设计说明

- **实现口径**：词条=**类似人物被动的技能**——不走 buff/debuff 结构（ADR-002 不适用），需要敌方单位的**被动技能挂载点**（我方已有心眼这类被动先例）。词条以 JSON 声明式定义（`data/affixes/`），normal 层恒为空。
- **两池分开、区别对待**：**基础词条池**=单位被动（示例方向：先手部署、受治疗减半）；**特殊词条池**=房间签名级、更大更醒目的机制，仅精英房头目持有。
- **可见性与可读性**：特殊词条在门上进房前可见 [已定]；基础词条进房前不可见、入场后战斗内点选敌人以图标+说明可读 [提案]——玩家要能围绕词条布阵对策，相性赌才「可对冲」。Prep「View Intel」只显示特殊词条与常规敌情。
- **池规模**：v1 基础池约 12-15 个 [占位] + 特殊池 6-8 个 [占位]；v0 基础 5 个左右 + 特殊 1-2 个验证手感 [占位]。

### Schema 扩展

```
EnemyTemplate 新增字段:
  tier: "normal" | "lesser_elite" | "greater_elite" | "elite_chief" | "act_boss"
  base_affixes: Array[affixId]    # 基础词条（被动技能）；数量按 tier 区间 x 难度两轴取值；normal 恒为空
  special_affix: affixId | null   # 仅 elite_chief：特殊词条，进房前可见；与基础词条分池（data/affixes/base 与 data/affixes/special）
```

> **v0 词条引擎已实装**：被动挂载点按方案 A（与心眼同构：spawn 后注入 → 缓存字段 → `get_effective_stat` / `damage_calculator` 读，不走 BuffEffect）实装于 `Ship_of_Theseus/scripts/units/unit.gd`（`apply_affixes`）+ `scripts/core/tactical_manager.gd`（`_apply_affixes` 时机分发器）+ `damage_calculator.gd`（affix 乘区）；波次数据 `data/waves/` 的 enemy entry 带 `affixes`/`special_affix`/`stat_scale`，`spawn_unit` 后注入。**无词条单位零影响**（心眼式门控，剑圣 81 断言实证）。v0 词条池 5 基础（`data/affixes/base`）+ 2 特殊（`data/affixes/special`）[占位]。**词条效果状态**：数值增强 stat_scale / afs_frenzy 低血增伤 / af_heal_resist 受治疗减半 / af_vanguard 首回合速度 / afs_bulwark 减伤光环 = **已真实生效**。回归 `tests/test_affix_system.gd` + `test_affix_effects.gd`。实装进度详见记忆 `runloop-v0-session-log`。

---

## Boss 设计方向

Act Boss 是**传奇层级**敌人（见上文「敌人层级与词条系统」）：词条数量随难度递增，且每个 Boss 都有**独有机制系统**（每幕一套定制内容）。Boss 采用特殊 AI 模式，带固定技能循环或阶段切换:

```
BossAI:
  phases: Array[BossPhase]

BossPhase:
  hp_threshold: int          # HP percentage to enter this phase
  skill_rotation: Array[String]  # Fixed skill rotation
  behavior_override: AIBehavior
  summon_wave: Wave | null   # Summon reinforcements on phase transition
```

Boss 的可读性很重要——玩家应能在几次尝试内摸清 Boss 的行为模式。

---

相关文档:
- [[grid-and-map|02 - Grid and Map]] — 敌人在地图上的摆放位置
- [[skills-and-range|04 - Skill and Range]] — 敌人使用的技能定义
- [[run-loop|08 - Run Loop]] — 一次 Run 内的战斗难度递进
