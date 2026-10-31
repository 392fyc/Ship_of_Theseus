# 07 - Run Loop and Stage Structure

> Back to [Overview](./README.md)

## Overview

> **结构确定（2026-06-30，用户裁决）：3 Acts × 8 Stages（含每 Act 末的 Boss 战）**，即每 Act = 7 个常规/精英/事件关 + 1 Boss。原 ~10 因**预期等级下调 + 时间成本**降为 8（3×7 / 3×8 中取 8）。

> **2026-07-02 门模式定稿（提案第三轮并回本文，取代第二轮线性方案）**：① 地图采用 **Hades 门模式**——每关结算后出 **2–3 扇门**（下限暂定 2，2026-07-03）、门上前置预告奖励类型；全幕地图不可见，幕进度与 Boss 位置可见（进度条，[提案]）。五类奖励门=**金币/经验/装备/遗物/特殊事件**（2026-07-03 商店退出门池）；**商店改固定插入**——每幕两次（幕中＋Boss 前），嵌入对应 Prep、不占门不占关；**天赋点与技能退出掉落池**（天赋点基本只来自等级提升，技能来自职业模板/天赋/遗物）。② **每个角色独立获得门奖励** + 每图固定金币经验 + 队伍不满 4 人有补偿 [占位]。③ **敌人词条制五层阶梯**（2026-07-03：小精英 1–3 / 大精英 3–5 / 精英房头目=大精英规格+1 特殊词条；特殊进房前可见、基础不可见、两池分开；词条=类似人物被动的技能，见 [06 - Enemy and AI](../Core-Systems/enemy-and-ai.md)）。④ **恢复并入 Prep**（2026-07-03）：量**不随幕变动、只随开局难度档变动**、可按角色拒绝；新增**运输队**大背包（非装备状态的装备/遗物，Prep 可替换、战斗内锁定）。⑤ 沿用：遗物 Relic 正典（ADR-010）、≤10 分钟/场快节奏、v1/v2 均不碰城镇。**D-B（奖励呈现机制 A/B/C）已由门模式关闭**——选择挪到战前选门。设计正本：`Ship_of_Theseus/dev_doc/runloop-design/runloop-reward-map-proposal.md`（第三轮，配对 HTML 可视化）。

> **v0 最小门循环已实装（2026-07-04，分支 `claude/runloop-v0-door-loop`）**：本节门模式设计已落地为可运行的 v0——门生成器（遗物保底按出现计数）/ 1 幕 × 8 关状态机 + 替身 Boss / 每角色独立奖励结算 + 每图固定金币经验（天赋点只来自升级）/ 敌人词条引擎（被动挂载点，与心眼同构）/ 门流程 UI（RunScene 宿主 + DoorSelect + 战斗注入）/ Prep（HP 跨关继承 + 恢复磨损 + 运输队 Convoy + 查看情报）/ 固定商店（幕中 + Boss 前两个 Prep，买卖金币守恒作排水渠）。代码在 `Ship_of_Theseus/scripts/roguelite/`（RunManager / RunState / RewardResolver / DoorGenerator / BattleAssembler / run_scene / door_select）+ `scripts/tactical/tactical_scene.gd` 注入模式；数据在 `data/{affixes,waves,relics,equipment,runloop}/`。验证：20 套 headless 回归约 1251 断言全绿 + 综合端到端 128 断言整轮协同贯通。**所有数值参数均为 [占位]**（门权重 / 遗物保底 N=3 模拟偏紧 / 恢复量 50% / 固定金币经验 / 商店价格等），待调参；调参基准见 `dev_doc/runloop-design/runloop-pacing-benchmark.md`（业界参考稿：保底放宽 4-5、恢复降 20-35% 或限频、事件门 ≥15-20% 换气、遗物池 ≥24）。手动测试清单 `Ship_of_Theseus/tests/门循环手动测试清单.md`（编辑器打开 RunScene.tscn 跑一整幕）。**v0 迭代补充（#12/#13，2026-07-04）**：事件门升级为真 choices/outcomes/effects + 伏击战斗（buff/item 效果占位待遗物装备系统）；词条 vanguard 首回合速度 / bulwark 减伤光环真实生效（~~zone_expand 控制区~~ 随 ZOC 机制全面删除作废，2026-07-06，Godot 侧移除待 SoT 组执行）。**af_siege 攻城词条已废弃移除**（城镇 v1 不做 → 建筑不作可攻击目标，相关职业与词条随之移除）。**v0 未做**：装备 / 遗物效果执行器（等设计库，占位保留作参考）；二三幕 + 幕 Boss 独有机制 + 热度系统。实装进度详见记忆 `runloop-v0-session-log`。

A single Run consists of **3 Acts**, each containing **8 Stages** (including the Act-ending Boss Battle at Stage 8, fixed). Stages are chosen through **door offers** (Hades style): after each Stage the player picks the next one from **2-3 doors** (min 2, provisional, 2026-07-03), each showing its reward type up front (elite rooms also show the chief's special affix). Between Stages there is a **Preparation Phase** that includes recovery (declinable per character), Convoy-based equipment/Relic swapping, and intel; **shops are fixed insertions** (once mid-act + once pre-Boss, embedded in those two Preparation Phases — not doors, not Stages, 2026-07-03). Pacing target: **10 minutes or less per Stage** (faster as the party grows); a full Run is expected to take **3+ hours**.

---

## Overall Run Structure

```
One Run:
  +-- Character Selection (solo: pick 1-4, multiplayer: each picks 1)
  |
  +-- [Act 1] (8 Stages incl. Boss)
  |   +-- [Prep] -> [Battle 1] -> [Prep] -> [Battle 2] -> ...
  |   +-- May encounter Elite Battles mid-way
  |   +-- [Act Boss Battle]
  |
  +-- [Act 2] (increased difficulty, 8 Stages incl. Boss)
  |   +-- [Prep] -> [Battle 1] -> [Prep] -> [Battle 2] -> ...
  |   +-- Elite Battle frequency increases
  |   +-- [Act Boss Battle]
  |
  +-- [Act 3] (highest difficulty, 8 Stages incl. Boss)
  |   +-- [Prep] -> [Battle 1] -> [Prep] -> [Battle 2] -> ...
  |   +-- Elite Battles
  |   +-- [Final Boss Battle]
  |
  +-- Run Complete / Total Party Wipe -> Settlement
```

---

## Stage Flow

Each Stage consists of **Preparation Phase -> Battle Phase**.

### Preparation Phase

Players prepare before entering the next battle:

```
Available actions during Preparation Phase (2026-07-03 revision):
  1. Recovery         -- Restore HP; amount set by run-start difficulty only
                         (constant within a Run); declinable per character [提案]
  2. Convoy Swap      -- Swap Equipment/Relics with the Convoy storage
                         (大背包运输队; holds unequipped items; locked during battle)
  3. Shopping         -- Buy Equipment/potions (costs Gold); available only at the
                         two fixed shop Preps per Act: mid-act + pre-Boss (2026-07-03)
  4. Skill Adjustment -- Swap/learn skills
  5. Battlefield Layout -- Place/adjust battlefield Building positions
  6. View Intel       -- Preview enemy info for the next battle (optional);
                         elite special affix always visible, base affixes hidden pre-room
  7. Confirm Departure -- Enter battle; warns once if someone is unrecovered
                         and not at full HP [提案]
```

> **2026-07-02 用户裁决**：原列表中「Town Building / Building Repair」两项**移除**——城镇系统 v1、v2 均不做，整体后置到 run-loop 里程碑之外（战场建筑的战斗内机制不受影响）。首个实装版（v0）准备阶段至少含 Recovery / Convoy Swap / View Intel / Confirm Departure 四项（2026-07-03 恢复与运输队并入后），其余随系统逐步开放。

See -> [11 - Town Building](./11-town-building.md)（deferred：run-loop v1/v2 不含城镇）

### Battle Phase

Standard tactical battle; rewards are granted upon victory.

```
After battle (2026-07-03 door-model order):
  1. Fixed Gold + EXP settle (per-map fixed amounts [占位]; EXP may trigger
     level-ups -> Talent Points)
  2. Door reward settles PER CHARACTER (each character independently receives
     the reward of the door that was chosen for this Stage)
  3. Door choice: pick the next Stage from 2-3 doors (reward type visible up front;
     elite rooms also show the chief's special affix)
  4. Enter next Preparation Phase (recovery + Convoy swaps happen there)
```

---

## Stage Types

2026-07-02 门模式定稿：关卡不再有固定类型配比表。**门的奖励标签**与**房间难度**是两条正交的轴：

| Axis | Values |
|------|--------|
| Door reward label | Gold / EXP / Equipment / Relic / Special Event（Shop 已退出门池，2026-07-03） |
| Room difficulty | Normal room / Elite room (skull mark + chief's **special affix shown on the door**; see 06-enemy-and-ai) / Boss (Stage 8, fixed) |

- **Elite room**: better reward quality or more quantity; some high rarity tiers may be elite-and-boss-only [提案].
- **Shop (2026-07-03 ruling)**: no longer a door type — **fixed insertions twice per Act**（mid-act + pre-Boss, embedded in those two Preparation Phases）; consumes neither a door nor a Stage.（此裁决根治了验证发现的「商店门返回语义/免费重掷」漏洞。）
- **Special Event door**: non-combat (may trigger an ambush battle); counts as a Stage; **must never appear on two consecutive Stages** (hard generation constraint).
- Type weights / elite-room rates / per-act gradients are generation parameters [占位]（第二轮的固定配比表作废）。

> 旧「Elite Encounters 2 / 2–3 / 3」与第二轮配比表均为分级概念提出前的占位，已被敌人阶梯 + 门生成参数取代（见 Difficulty Scaling 注）。

### Door Offer - Example

```
After Stage 3 victory, offer (2 doors):
  Door A: Gold      (normal room)
  Door B: Relic     (elite room -> chief: greater-elite spec + 1 special affix
                     shown on the door; higher quality reward)
```

*Door composition is rolled by the generator under the constraints above; reward types within one offer should differ [提案].*

---

## Door Model - Stage Map and Preview

> 2026-07-02 用户裁决：采用 **Hades 门模式**，取代第二轮的「线性先行 + 分支后置」两案。奖励类型前置预告为用户点名特性。细节出处：设计正本第三轮 §2 / §4 / §5。

### Loop

```
Battle victory -> reward settle -> 2-3 doors (reward type visible; elite rooms
  also show the chief's special affix) -> pick door
  -> Preparation Phase (recovery [declinable] + Convoy swap + intel)
  -> next battle ... Stage 8 = Boss (fixed, always visible on the act progress bar)
```

- 全幕地图**不可见**（Hades 式单步选择）；**幕进度条**保住节奏预期下限：当前第 N/8 关 + Boss 位置恒可见 [提案]。
- 门数：**2–3 扇（下限暂定 2，2026-07-03**——消灭模拟中约 1/3 的零选择门组）；组内分布细节 [占位]。
- SoT 无独立「休息/篝火」节点——休息与准备内嵌在关间恢复 + Preparation Phase。

### Generation Constraints

- **硬约束 [已定]**：① 特殊事件门不得连续出现；② Stage 8 固定 Boss；③ 商店不走门——每幕固定两次插入（幕中＋Boss 前的 Prep，2026-07-03）。
- **遗物保底**：**按出现计数 [已定]**（2026-07-03，触发与重置都看「遗物门是否出现过」、与是否被选无关——防连续强制刷屏）；连续 N 关未出现则强制供应，N [占位 N=3，1000 幕模拟显示偏紧、待调]。原「Boss 前保证商店选项」条款删除（固定插入已保证）。
- **同组门奖励类型互不相同 [提案]**（沿用「同叉不同类」防假选择思想）。

### Preview and Intel

- 门上奖励类型**必显**（Hades 门符号模式）——类型可见、具体内容随机，保留期待感。
- **词条可见性规则（2026-07-03 用户裁决）**：精英房头目的**特殊词条进房前可见**（门上明码标价的头牌威胁，可在 Prep 经运输队针对性换装）；**基础词条进房前不可见**（相性赌保留），入场后战斗内点选可读 [提案]。
- **Meta hook**: 基础预览免费；`map_preview` 便利升级解锁更深情报——奖励品质档提示、**部分基础词条**预览 [提案]。只加情报不加战力，守 horizontal-only 红线。

### Recovery in Preparation Phase

（2026-07-03 用户裁决：恢复并入 Prep；**量不随幕变动、只随开局难度档变动**，run 内恒定）

- **恢复是 Prep 的一个主动动作**；玩家可主动拒绝（背水流构筑）[已定]。
- 恢复量：基础难度约 50% 最大生命 [占位]；更高热度档更低（热度系统第一个具体旋钮，曲线 [占位]）；基数建议最大生命百分比 [提案]。
- 执行细节 [提案]：恢复/拒绝**按角色**；确认出发时若有人未恢复且非满血弹一次提示（取代原「默认开启」）；拒绝本身不另给奖励（背水收益来自低血触发的天赋/遗物）；连带需求——天赋/遗物池须含**低血阈值触发**条目。
- 磨损逻辑（两轴解耦）：恢复**不满额** + HP 跨关继承 → 精英房血量代价跨关发酵；幕间压力全部交给敌方成长轴（倍率+词条数），恢复压力交给玩家自选难度档。

---

## Reward System

### Battle Rewards

（2026-07-02 门模式定稿：按房间难度结算；旧表的「Talent Points 按关卡类型发放」与「skills 掉落」已废弃）

| Room type | Fixed settle | Per-character door reward | Notes |
|-----------|--------------|---------------------------|-------|
| Normal room | Fixed Gold + EXP（数额 [占位]，按幕倍率） | 1 份该门类型的奖励 | |
| Elite room | Same fixed settle | 品质更高或数量更多 | 房内头目=大精英规格+1 特殊词条（见 06-enemy-and-ai） |
| Boss (Stage 8) | Large fixed settle | **固定包：Gold + EXP + Equipment + 特殊 Relic** | 品质概率高于精英；通往下一幕 |

- **EXP**: character leveling (stat growth values)；升级产出**天赋点**。
- **Talent Points**: 基本只来自等级提升（经济类遗物可加成，2026-07-02 定稿）；**不再是掉落**；每 run 清零。
- **Skills are not drops**: 职业固定模板 / 天赋 / 遗物（2026-07-02 定稿）。
- **Per-character drops**: 每个角色独立获得门奖励；队伍不满 4 人有额外补偿 [占位]。
- 调参期待定 [提案]：EXP 全队共享池 vs 按角色独立（与不满 4 人补偿同天平）。

### Reward Mapping to 5-Layer Architecture

（2026-07-02 第三轮修订；Relic 术语按 ADR-010，L5 = 遗物 Relic 6 槽/角色；估算值为 [占位]）

| Reward | Layer | Source | Notes |
|--------|-------|--------|-------|
| Gold | Cross-layer economy | 每图固定 + Gold door + Events | x1.0/1.3/1.6 per Act; sinks = shop/consumables |
| EXP | L3 growth + 间接驱动 L2 | 每图固定 + EXP door | 升级给属性成长并产出天赋点；升级次数/run [占位] |
| Talent Points | L2 (reset per Run) | **Via level-ups (from EXP)**；经济类遗物可加成 | **Not a drop**（2026-07-02）；与架构「L2 决策时机=每升级」一致 |
| Equipment | L4 (not build-defining) | Equipment door / shop / Boss package | **武器+防具两槽**（2026-07-02）；渐进品阶、run-reset |
| Skill | Class ability | **Not a drop**: class fixed template / talents / Relics | 2026-07-02 定稿 |
| Relic | L5 6-slot per character (build-defining) | Relic door / shop / Events / Boss 特殊 Relic | 池 20+ 起（用户预期下限）；6 槽硬上限 |
| Potion | Inventory | Shop / Events | 应急恢复 + 金币排水 |
| Permanent buff | Run-scoped character state | Special Events | e.g. Blessing Altar |

（L1 Meta 解锁属跨 run 横向层，不在每场战斗奖励里发。）

### Reward Pacing and Guards

（2026-07-02 第三轮修订；数值为 [占位]/[提案]）

- **Three-act gradient**: Act 1 慷慨的构筑窗口（遗物/装备门权重更高 [占位]）→ Act 2 收缩（普通房降质、精英房保持）→ Act 3 完成（补完构筑而非开新方向；装备门的意义=更高品阶替换，与两槽渐进契合）。
- **Anti-inflation**: 天赋点通胀由**等级曲线**统一管理（掉落口径取消后仅剩一个水龙头；「总供给 ≤ 可解锁节点数的 60–75%」[占位] 仍作预算参照）；Relic 6 槽/角色硬上限（多余只能换）；金币持续排水渠（商店/药水）。
- **Anti-starvation**: 门保底规则（见 Door Model 段的 Generation Constraints [提案]）；事件做「构筑补救窗口」（花金币定向取缺失维度的奖励）。

### Reward Selection

> **D-B 已关闭（2026-07-02 门模式定稿）**：奖励选择从「战后选奖励」挪到「**战前选门**」——选门即选奖励类型，一次决策两重意义（选路=选奖励）。原 Option A（固定+三选一）/ B（全三选一）/ C（固定+随机）三案**全部废弃**，留此存档。

Multiplayer / multi-character reward distribution:
- **Each character independently receives the door reward**（2026-07-02 定稿）——无需战后逐人选择与计时器。
- Door choice（选哪扇门）是队伍级决策；多人时的表决方式待多人系统设计时定 [提案]。

---

## Special Events

Non-combat Stages that offer risk/reward choices.

```
Event:
  id: String
  title: String
  description: String
  choices: Array[EventChoice]

EventChoice:
  text: String
  outcomes: Array[EventOutcome]

EventOutcome:
  weight: int
  effects: Array[Effect]
  description: String
```

### Event Examples

- **Mysterious Merchant**: Sells rare items at extremely high prices
- **Abandoned Mine**: Exploration may yield large amounts of Gold or trigger an ambush
- **Blessing Altar**: Spend Gold/HP in exchange for permanent buffs

---

## Difficulty Scaling

| Element | Act 1 | Act 2 | Act 3 |
|---------|-------|-------|-------|
| Enemy HP | x1.0 | x1.5 | x2.0 |
| Enemy Attack | x1.0 | x1.3 | x1.6 |
| Wave Count | 1-2 | 2-3 | 2-3 |
| Enemy tier mix and affix counts | 区间下限 | 中段 | 区间上限（见 06-enemy-and-ai） |
| Gold Reward | Base | x1.3 | x1.6 |

> **恢复不在本表**（2026-07-03 用户裁决）：恢复量**不随幕变动**，只随开局难度档变动、run 内恒定——见 Recovery in Preparation Phase 小节。

> **旧行「Elite Encounters 2 / 2–3 / 3」已删（2026-07-02 用户判定）**：属精英分级概念提出前的早期占位，由敌人五层阶梯（06-enemy-and-ai）+ 门生成参数（elite_room_weight 等 [占位]）取代。
>
> **难度两轴（2026-07-02）**：本表是**幕数递进轴**；另有**开局难度档**（类 Hades 热度，系统细节后置、v1 固定基础难度留接口）。热度奖励设计须守 meta 横向红线（不给纵向战力）。

---

## Meta Progression - Cross-Run Persistence

### Core Design Principle

**Meta unlocks = horizontal expansion of choices, NOT vertical numerical power increases.**

At any level of Meta Progression, the content already unlocked can support a complete core gameplay experience. The following situation must never occur: "Due to missing Meta unlocks, core mechanics are absent, and mid-to-late Run the player discovers insufficient power with no way to compensate."

| Allowed | Prohibited |
|---------|------------|
| Second Class Advancement not unlocked, but the first Class Advancement's full gameplay is available | A core combo mechanic is missing because a certain Talent Tree node is not unlocked |
| Advanced Relics not unlocked, but the existing Relic pool is sufficient to build an effective BD | Base stats are below normal levels because Meta rank is too low |
| Newly unlocked Classes provide new gameplay, not stronger numbers | Later-unlocked Classes are strictly stronger than earlier ones |

### Meta Unlock Categories

```
MetaProgress:
  total_runs: int
  best_run: int                        # Farthest Act/Stage reached

  # Horizontal unlocks (more choices)
  unlocked_classes: Array[String]      # New Classes (5 initial in v1, more unlocked via completion conditions)
  unlocked_talent_areas: Dict[String, Array[String]]  # Unlocked Talent Tree areas per Class
  unlocked_relics: Array[String]       # Relic pool expansion
  unlocked_buildings: Array[String]    # New Building types
  unlocked_building_levels: Dict[String, int]  # Building level caps

  # Convenience upgrades (do not affect core power)
  convenience_upgrades: Dict[String, int]
```

### Detailed Unlock Descriptions

#### Talent Area Unlocks

Each Class's Talent Tree is divided into multiple areas. Initially unlocked areas **contain one Class Advancement path's complete core gameplay**. After completing a Run, more areas unlock, opening a second Class Advancement option.

```
Initial state (Swordsman as example):
  Unlocked: Base area + Sword Saint path area
  -> Player can experience the full Sword Saint gameplay (crit/speed/combos)

After 1 completion:
  Newly unlocked: Magic Swordsman path area
  -> Player gains a new Class Advancement option, but Sword Saint path is not stronger
```

**Rule**: For Classes with two Class Advancements, usually only 1 completion is needed to unlock all Class Advancement options.

#### Relic Unlocks

The Relic pool gradually expands with Meta Progression. However, the initial Relic pool already covers core needs for various BD directions.

```
Initial Relic pool:
  Contains base Relics for each archetype (attack/defense/speed/support, etc.)
  -> Sufficient to build an effective BD

Meta unlocks:
  Add more Relics, providing more combination possibilities
  -> Horizontal expansion, not "stronger versions of base Relics"
```

#### Building Unlocks

Core Buildings are provided initially (e.g., Watchtower, Barricade). Meta Progression unlocks new Building types and higher level caps for existing Buildings.

```
Initial state:
  Buildable: Watchtower Lv1, Barricade Lv1, Life Spring Lv1
  -> Basic battlefield control is available

Meta unlocks:
  New Buildings: Fortress, Ballista, Magic Tower
  Level caps: Watchtower Lv2 -> Lv3, ...
```

#### Class Unlocks

v1 starts with 5 Classes (Mercenary/Archer/Mage/Knight/Cleric); remaining Classes are unlocked through specific conditions.

```
Unlock condition examples (pending):
  Swordsman: First completion
  Artificer: Use 3 different Buildings in a Run
  Hunter: Defeat 50 enemies in a Run
```

#### Convenience Upgrades

A small number of convenience improvements that do not affect core combat power, purchased with cross-Run currency.

```
ConvenienceUpgrade examples:
  "starting_gold": +10 per level (max 3)     # Slightly more starting Gold
  "shop_discount": -5% per level (max 2)      # Shop discount
  "extra_reroll": +1 per level (max 2)        # Reward reroll count
  "map_preview": Unlock Stage preview info    # Intel category
```

**Note**: Does not include "starting HP bonus", "starting attack bonus", or other upgrades that directly affect combat numbers. Convenience upgrades should be limited to the economic and informational layers.

---

## Data Structures

### Act Definition - Legacy

> **早期结构，仅存档参考**：run 生成已由下方 Door Generation Data Structures 驱动（2026-07-02 门模式定稿）。曾于第二轮往 type 枚举补过 "shop" 关卡类型——2026-07-03 定稿商店为**固定插入**（不占门不占关），shop 不再是关卡类型，已回退。

```
Chapter:
  id: String
  name: String
  stages: Array[Stage]
  boss: Stage
  difficulty_multiplier: float

Stage:
  id: String
  type: "battle" | "elite" | "boss" | "event"   # legacy
  map_id: String              # Corresponding battle map (for battle types)
  event_id: String | null     # Corresponding event (for event types)
  enemy_config: String        # Enemy configuration/wave ID
  rewards: RewardConfig
  preview: String             # Stage preview info (legacy)
```

### Door Generation Data Structures

（2026-07-02 第三轮并入，**取代第二轮的 MapGraph 线性骨架**；2026-07-03 增补 RunConfig/Convoy、恢复挪 run 级、词条制字段。骨架示例 `Ship_of_Theseus/data/runloop/run_config.json` + `act1_config.json`，已通过 headless 冒烟测试。上方 Chapter/Stage 为早期结构，保留作参考——run 生成改由下列结构驱动。）

```
RunConfig:                               # run 级（2026-07-03 新增）
  difficulty: String                     # 开局难度档（热度，系统后置；v0 = "base"）
  recovery: { percent_max_hp: int [占位], declinable: true }
                                         # 只随难度档变动，run 内恒定、不随幕变动

Convoy:                                  # 运输队大背包（运行时状态，2026-07-03 新增）
  equipment: Array[itemId]               # 非装备状态的装备
  relics: Array[relicId]                 # 非装备状态的遗物；Prep 可替换、战斗内锁定
                                         # 遗物替换限制（自由/限次/成本）为调参旋钮 [占位]，v0 先自由

ActConfig:
  act: int
  stage_count: int                       # 8
  boss_stage: int                        # 8, fixed
  boss: { map_id, enemy_config, reward } # fixed package: Gold+EXP+Equipment+special Relic
  door_gen: DoorGenConfig

DoorGenConfig:
  door_count: { min: 2, max: 3 }         # min=2 [已定·暂定]（2026-07-03）
  type_weights: { gold, exp, equipment, relic, event }   # [占位]；商店已退出门池（2026-07-03）
  elite_room_weight: int                 # [占位]
  constraints:
    events_non_consecutive: true         # [已定]
    same_offer_types_distinct: true      # [提案]
  pity:
    relic_drought_stages: int            # [占位 N=3，模拟显示偏紧待调]
    count_by: "appearance"               # [已定]（2026-07-03）按出现计数、非按选中
  fixed_shops:                           # [已定]（2026-07-03）商店固定插入
    mid_act_after_stage: int             # 幕中一次，定位 [占位]
    pre_boss: true                       # Boss 前一次（嵌入对应 Prep）
  battle_pools: { normal: [waveId], elite: [waveId] }   # data/waves
  map_pool: [mapId]                      # data/maps
  event_pool: [eventId]                  # data/events
  fixed_reward_per_stage: { gold, exp }  # [占位]
  party_size_bonus: { ... }              # [占位] 不满4人补偿

DoorOption (runtime-generated):
  reward_type: "gold" | "exp" | "equipment" | "relic" | "event"   # 商店已退出门池（2026-07-03）
  elite_room: bool
  battle: { map_id, enemy_config } | null
  event_id: String | null
  preview: { icon, rarity_hint }         # rarity_hint 由 map_preview 便利升级解锁

RewardDrop:
  kind: "gold" | "exp" | "equipment" | "relic" | "potion"
        # 2026-07-02: 无 "talent_point"/"skill"（退出掉落池）; 无 "rune"（ADR-010）
        # 经济类遗物加天赋点走遗物效果字段，不走掉落 kind
  rarity: "common" | "rare" | "epic" | "legendary" | null
  ref_id: String | null                  # points into data/relics, data/equipment, ...
  weight: int                            # weighted draw (pity / dedup)

EnemyTemplate 扩展（详见 06-enemy-and-ai；2026-07-03 词条制）:
  tier: "normal" | "lesser_elite" | "greater_elite" | "elite_chief" | "act_boss"
  base_affixes: Array[affixId]           # 基础词条（被动技能）：小精英1-3 / 大精英与头目3-5；进房前不可见
  special_affix: affixId | null          # 仅 elite_chief：特殊词条，进房前可见；与基础词条分池
```

---

Related documents:
- [11 - Town Building](./11-town-building.md) -- Town Building design（deferred：2026-07-02 裁决 run-loop v1/v2 不含城镇）
- [12 - Talent Tree](./12-talent-tree.md) -- Talent nodes and Class Advancement triggers (pending)
- [06 - Enemy and AI](./06-enemy-and-ai.md) -- Battle difficulty and Boss design
- [05 - Class System](./05-class-system.md) -- Character growth and Builds
- [10 - Development Milestones](./10-milestones.md) -- Phase 5 implements Run loop
