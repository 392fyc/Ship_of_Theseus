# 08 - 运行循环与关卡结构

> 返回 [总览](../game-design-doc.md)

## 概览

> **结构确定（2026-06-30，用户裁决）：3 Acts × 8 Stages（含每 Act 末的 Boss 战）**，即每 Act = 7 个常规/精英/事件关 + 1 Boss。原 ~10 因**预期等级下调 + 时间成本**降为 8（3×7 / 3×8 中取 8）。

> **2026-07-02 门模式定稿（提案第三轮并回本文，取代第二轮线性方案）**：① 地图采用 **Hades 门模式**——每关结算后出 **2–3 扇门**（下限暂定 2，2026-07-03）、门上前置预告奖励类型；全幕地图不可见，幕进度与 Boss 位置可见（进度条，[提案]）。五类奖励门=**金币/经验/装备/遗物/特殊事件**（2026-07-03 商店退出门池）；**商店改固定插入**——每幕两次（幕中＋Boss 前），嵌入对应 Prep、不占门不占关；**天赋点与技能退出掉落池**（天赋点基本只来自等级提升，技能来自职业模板/天赋/遗物）。② **每个角色独立获得门奖励** + 每图固定金币经验 + 队伍不满 4 人有补偿 [占位]。③ **敌人词条制五层阶梯**（2026-07-03：小精英 1–3 / 大精英 3–5 / 精英房头目=大精英规格+1 特殊词条；特殊进房前可见、基础不可见、两池分开；词条=类似人物被动的技能，见 [06 - Enemy and AI](../Core-Systems/enemy-and-ai.md)）。④ **恢复并入 Prep**（2026-07-03）：量**不随幕变动、只随开局难度档变动**、可按角色拒绝；新增**运输队**大背包（非装备状态的装备/遗物，Prep 可替换、战斗内锁定）。⑤ 沿用：遗物 Relic 正典（ADR-010）、≤10 分钟/场快节奏。**D-B（奖励呈现机制 A/B/C）已由门模式关闭**——选择挪到战前选门。设计正本：`Ship_of_Theseus/dev_doc/runloop-design/runloop-reward-map-proposal.md`（第三轮，配对 HTML 可视化）。

> **v0 最小门循环已实装（2026-07-04，分支 `claude/runloop-v0-door-loop`）**：本节门模式设计已落地为可运行的 v0——门生成器（遗物保底按出现计数）/ 1 幕 × 8 关状态机 + 替身 Boss / 每角色独立奖励结算 + 每图固定金币经验（天赋点只来自升级）/ 敌人词条引擎（被动挂载点，与心眼同构）/ 门流程 UI（RunScene 宿主 + DoorSelect + 战斗注入）/ Prep（HP 跨关继承 + 恢复磨损 + 运输队 Convoy + 查看情报）/ 固定商店（幕中 + Boss 前两个 Prep，买卖金币守恒作排水渠）。代码在 `Ship_of_Theseus/scripts/roguelite/`（RunManager / RunState / RewardResolver / DoorGenerator / BattleAssembler / run_scene / door_select）+ `scripts/tactical/tactical_scene.gd` 注入模式；数据在 `data/{affixes,waves,relics,equipment,runloop}/`。验证：20 套 headless 回归约 1251 断言全绿 + 综合端到端 128 断言整轮协同贯通。**所有数值参数均为 [占位]**（门权重 / 遗物保底 N=3 模拟偏紧 / 恢复量 50% / 固定金币经验 / 商店价格等），待调参；调参基准见 `dev_doc/runloop-design/runloop-pacing-benchmark.md`（业界参考稿：保底放宽 4-5、恢复降 20-35% 或限频、事件门 ≥15-20% 换气、遗物池 ≥24）。手动测试清单 `Ship_of_Theseus/tests/门循环手动测试清单.md`（编辑器打开 RunScene.tscn 跑一整幕）。**v0 迭代补充（#12/#13，2026-07-04）**：事件门升级为真 choices/outcomes/effects + 伏击战斗（buff/item 效果占位待遗物装备系统）；词条 vanguard 首回合速度 / bulwark 减伤光环真实生效（~~zone_expand 控制区~~ 随 ZOC 机制全面删除作废，2026-07-06，Godot 侧移除待 SoT 组执行）。**v0 未做**：装备 / 遗物效果执行器（等设计库，占位保留作参考）；二三幕 + 幕 Boss 独有机制 + 热度系统。实装进度详见记忆 `runloop-v0-session-log`。

单次 Run 由 **3 个 Act** 组成，每个 Act 含 **8 个 Stage**（含固定位于 Stage 8 的 Act 收尾 Boss 战）。Stage 通过**门选项**（Hades 风格）选择：每关结束后玩家从 **2–3 扇门**（下限 2，暂定，2026-07-03）中挑选下一关，每扇门前置显示其奖励类型（精英房还会显示头目的特殊词条）。关与关之间有一个**准备阶段**（Preparation Phase），含恢复（可按角色拒绝）、基于运输队 Convoy 的装备/遗物替换、以及情报；**商店为固定插入**（幕中一次 + Boss 前一次，嵌入这两个准备阶段——不占门、不占关，2026-07-03）。节奏目标：**每关 10 分钟或更短**（队伍变大后更快）；一整局 Run 预期耗时 **3 小时以上**。

---

## 整体运行结构

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

> **叙事接口中性（2026-07-28）**：以上 `Act 1 / 2 / 3` 是**逐幕增难的机制结构**、不绑任何叙事命名。哪个 Act 对应哪个世界 / 水域、每 run 从叙事幕池抽哪几幕、是否随机，全部由所选 **Narrative 方案**（Plan-1 世界池 / Plan-2 水域集，见 `../Narrative/README.md`）提供；机制层保持中性，**支持每 run 从叙事幕池随机抽 3 幕**，无需为「固定命名幕」做任何改动。此注记消解 Narrative 两方案曾挂的「固定 3 幕 → 随机抽幕 机制层同步」待办。[已澄清]

---

## 关卡流程

每个 Stage 由**准备阶段（Preparation Phase）→ 战斗阶段（Battle Phase）**组成。

### 准备阶段

玩家在进入下一场战斗前进行准备：

```
Available actions during Preparation Phase (2026-07-03 revision):
  1. Recovery         -- Restore HP; amount set by run-start difficulty only
                         (constant within a Run); declinable per character [提案]
  2. Convoy Swap      -- Swap Equipment/Relics with the Convoy storage
                         (大背包运输队; holds unequipped items; locked during battle)
  3. Shopping         -- Buy Equipment/potions/Relics (costs Gold); available only at the
                         two fixed shop Preps per Act: mid-act + pre-Boss (2026-07-03)
  4. Skill Adjustment -- Swap/learn skills
  5. Battlefield Layout -- Place/adjust battlefield Building positions
  6. View Intel       -- Preview enemy info for the next battle (optional);
                         elite special affix always visible, base affixes hidden pre-room
  7. Confirm Departure -- Enter battle; warns once if someone is unrecovered
                         and not at full HP [提案]
```

> **2026-07-02 用户裁决**：首个实装版（v0）准备阶段至少含 Recovery / Convoy Swap / View Intel / Confirm Departure 四项（2026-07-03 恢复与运输队并入后），其余随系统逐步开放。


### 战斗阶段

标准战棋战斗；胜利后发放奖励。

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

## 关卡类型

2026-07-02 门模式定稿：关卡不再有固定类型配比表。**门的奖励标签**与**房间难度**是两条正交的轴：

| 轴 | 取值 |
|------|--------|
| 门奖励标签 | 金币 / 经验 / 装备 / 遗物 / 特殊事件（商店已退出门池，2026-07-03） |
| 房间难度 | 普通房 / 精英房（骷髅标记 + 头目**特殊词条显示在门上**；见 06-enemy-and-ai）/ Boss（Stage 8，固定） |

- **精英房**：更好的奖励品质或更大数量；某些高稀有度档位可能仅限精英与 Boss [提案]。
- **商店（2026-07-03 裁决）**：不再是门类型——**每 Act 固定插入两次**（幕中 + Boss 前，嵌入这两个准备阶段）；既不占门也不占关。（此裁决根治了验证发现的「商店门返回语义/免费重掷」漏洞。）
- **商店售卖内容（2026-07-28 用户裁定）**：商店售卖**装备 / 药水 / 遗物 Relic**（对齐下方奖励来源表 Relic 行含 `shop`）。原 Preparation Phase 的 `Shopping` 动作只写 `Equipment/potions`、与来源表矛盾，已同步补 `Relics`——两处口径统一。[已定]
- **特殊事件门**：非战斗（可能触发伏击战斗）；计为一个 Stage；**绝不能在连续两关出现**（硬性生成约束）。
- 类型权重 / 精英房比率 / 逐 Act 梯度为生成参数 [占位]（第二轮的固定配比表作废）。

> 旧「Elite Encounters 2 / 2–3 / 3」与第二轮配比表均为分级概念提出前的占位，已被敌人阶梯 + 门生成参数取代（见 Difficulty Scaling 注）。

### 门选项 - 示例

```
After Stage 3 victory, offer (2 doors):
  Door A: Gold      (normal room)
  Door B: Relic     (elite room -> chief: greater-elite spec + 1 special affix
                     shown on the door; higher quality reward)
```

*门的构成由生成器在上述约束下随机生成；同一组选项内的奖励类型应各不相同 [提案]。*

---

## 门模式 - 关卡地图与预览

> 2026-07-02 用户裁决：采用 **Hades 门模式**，取代第二轮的「线性先行 + 分支后置」两案。奖励类型前置预告为用户点名特性。细节出处：设计正本第三轮 §2 / §4 / §5。

### 循环

```
Battle victory -> reward settle -> 2-3 doors (reward type visible; elite rooms
  also show the chief's special affix) -> pick door
  -> Preparation Phase (recovery [declinable] + Convoy swap + intel)
  -> next battle ... Stage 8 = Boss (fixed, always visible on the act progress bar)
```

- 全幕地图**不可见**（Hades 式单步选择）；**幕进度条**保住节奏预期下限：当前第 N/8 关 + Boss 位置恒可见 [提案]。
- 门数：**2–3 扇（下限暂定 2，2026-07-03**——消灭模拟中约 1/3 的零选择门组）；组内分布细节 [占位]。
- SoT 无独立「休息/篝火」节点——休息与准备内嵌在关间恢复 + Preparation Phase。

### 生成约束

- **硬约束 [已定]**：① 特殊事件门不得连续出现；② Stage 8 固定 Boss；③ 商店不走门——每幕固定两次插入（幕中＋Boss 前的 Prep，2026-07-03）。
- **遗物保底**：**按出现计数 [已定]**（2026-07-03，触发与重置都看「遗物门是否出现过」、与是否被选无关——防连续强制刷屏）；连续 N 关未出现则强制供应，N [占位 N=3，1000 幕模拟显示偏紧、待调]。原「Boss 前保证商店选项」条款删除（固定插入已保证）。
- **同组门奖励类型互不相同 [提案]**（沿用「同叉不同类」防假选择思想）。

### 预览与情报

- 门上奖励类型**必显**（Hades 门符号模式）——类型可见、具体内容随机，保留期待感。
- **词条可见性规则（2026-07-03 用户裁决）**：精英房头目的**特殊词条进房前可见**（门上明码标价的头牌威胁，可在 Prep 经运输队针对性换装）；**基础词条进房前不可见**（相性赌保留），入场后战斗内点选可读 [提案]。
- **Meta hook**: 基础预览免费；`map_preview` 便利升级解锁更深情报——奖励品质档提示、**部分基础词条**预览 [提案]。只加情报不加战力，守 horizontal-only 红线。

### 准备阶段中的恢复

（2026-07-03 用户裁决：恢复并入 Prep；**量不随幕变动、只随开局难度档变动**，run 内恒定）

- **恢复是 Prep 的一个主动动作**；玩家可主动拒绝（背水流构筑）[已定]。
- 恢复量：基础难度约 50% 最大生命 [占位]；更高热度档更低（热度系统第一个具体旋钮，曲线 [占位]）；基数建议最大生命百分比 [提案]。
- 执行细节 [提案]：恢复/拒绝**按角色**；确认出发时若有人未恢复且非满血弹一次提示（取代原「默认开启」）；拒绝本身不另给奖励（背水收益来自低血触发的天赋/遗物）；连带需求——天赋/遗物池须含**低血阈值触发**条目。
- 磨损逻辑（两轴解耦）：恢复**不满额** + HP 跨关继承 → 精英房血量代价跨关发酵；幕间压力全部交给敌方成长轴（倍率+词条数），恢复压力交给玩家自选难度档。

---

## 奖励系统

### 战斗奖励

（2026-07-02 门模式定稿：按房间难度结算；旧表的「Talent Points 按关卡类型发放」与「skills 掉落」已废弃）

| 房间类型 | 固定结算 | 每角色门奖励 | 备注 |
|-----------|--------------|---------------------------|-------|
| 普通房 | 固定 Gold + EXP（数额 [占位]，按幕倍率） | 1 份该门类型的奖励 | |
| 精英房 | 同固定结算 | 品质更高或数量更多 | 房内头目=大精英规格+1 特殊词条（见 06-enemy-and-ai） |
| Boss（Stage 8） | 大额固定结算 | **固定包：Gold + EXP + Equipment + 特殊 Relic** | 品质概率高于精英；通往下一幕 |

- **EXP**：角色升级（属性成长数值）；升级产出**天赋点**。
- **Talent Points**: 基本只来自等级提升（经济类遗物可加成，2026-07-02 定稿）；**不再是掉落**；每 run 清零。
- **技能不是掉落**：职业固定模板 / 天赋 / 遗物（2026-07-02 定稿）。
- **每角色掉落**：每个角色独立获得门奖励；队伍不满 4 人有额外补偿 [占位]。
- 调参期待定 [提案]：EXP 全队共享池 vs 按角色独立（与不满 4 人补偿同天平）。

### 奖励到五层架构的映射

（2026-07-02 第三轮修订；Relic 术语按 ADR-010，L5 = 遗物 Relic 6 槽/角色；估算值为 [占位]）

| 奖励 | 层 | 来源 | 备注 |
|--------|-------|--------|-------|
| Gold | 跨层经济 | 每图固定 + Gold door + Events | x1.0/1.3/1.6 per Act; sinks = shop/consumables |
| EXP | L3 growth + 间接驱动 L2 | 每图固定 + EXP door | 升级给属性成长并产出天赋点；升级次数/run [占位] |
| Talent Points | L2 (reset per Run) | **Via level-ups (from EXP)**；经济类遗物可加成 | **Not a drop**（2026-07-02）；与架构「L2 决策时机=每升级」一致 |
| Equipment | L4 (not build-defining) | Equipment door / shop / Boss package | **武器+防具两槽**（2026-07-02）；渐进品阶、run-reset |
| Skill | Class ability | **Not a drop**: class fixed template / talents / Relics | 2026-07-02 定稿 |
| Relic | L5 6-slot per character (build-defining) | Relic door / shop / Events / Boss 特殊 Relic | 池 20+ 起（用户预期下限）；6 槽硬上限 |
| Potion | Inventory | Shop / Events | 应急恢复 + 金币排水 |
| Permanent buff | Run-scoped character state | Special Events | e.g. Blessing Altar |

（L1 Meta 解锁属跨 run 横向层，不在每场战斗奖励里发。）

### 奖励节奏与护栏

（2026-07-02 第三轮修订；数值为 [占位]/[提案]）

- **Three-act gradient**: Act 1 慷慨的构筑窗口（遗物/装备门权重更高 [占位]）→ Act 2 收缩（普通房降质、精英房保持）→ Act 3 完成（补完构筑而非开新方向；装备门的意义=更高品阶替换，与两槽渐进契合）。
- **Anti-inflation**: 天赋点通胀由**等级曲线**统一管理（掉落口径取消后仅剩一个水龙头；「总供给 ≤ 可解锁节点数的 60–75%」[占位] 仍作预算参照）；Relic 6 槽/角色硬上限（多余只能换）；金币持续排水渠（商店/药水）。
- **Anti-starvation**: 门保底规则（见 Door Model 段的 Generation Constraints [提案]）；事件做「构筑补救窗口」（花金币定向取缺失维度的奖励）。

### 奖励选择

> **D-B 已关闭（2026-07-02 门模式定稿）**：奖励选择从「战后选奖励」挪到「**战前选门**」——选门即选奖励类型，一次决策两重意义（选路=选奖励）。原 Option A（固定+三选一）/ B（全三选一）/ C（固定+随机）三案**全部废弃**，留此存档。

多人 / 多角色奖励分配：
- **Each character independently receives the door reward**（2026-07-02 定稿）——无需战后逐人选择与计时器。
- Door choice（选哪扇门）是队伍级决策；多人时的表决方式待多人系统设计时定 [提案]。

---

## 特殊事件

提供风险/回报抉择的非战斗关卡。

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

### 事件示例

- **神秘商人**：以极高价格出售稀有物品
- **废弃矿井**：探索可能获得大量金币或触发伏击
- **祝福祭坛**：消耗金币/HP 换取永久增益

---

## 难度缩放

| 要素 | Act 1 | Act 2 | Act 3 |
|---------|-------|-------|-------|
| Enemy HP | x1.0 | x1.5 | x2.0 |
| Enemy Attack | x1.0 | x1.3 | x1.6 |
| Wave Count | 1-2 | 2-3 | 2-3 |
| 敌人阶梯组合与词条数量 | 区间下限 | 中段 | 区间上限（见 06-enemy-and-ai） |
| Gold Reward | Base | x1.3 | x1.6 |

> **恢复不在本表**（2026-07-03 用户裁决）：恢复量**不随幕变动**，只随开局难度档变动、run 内恒定——见 Recovery in Preparation Phase 小节。

> **旧行「Elite Encounters 2 / 2–3 / 3」已删（2026-07-02 用户判定）**：属精英分级概念提出前的早期占位，由敌人五层阶梯（06-enemy-and-ai）+ 门生成参数（elite_room_weight 等 [占位]）取代。
>
> **难度两轴（2026-07-02）**：本表是**幕数递进轴**；另有**开局难度档**（类 Hades 热度，系统细节后置、v1 固定基础难度留接口）。热度奖励设计须守 meta 横向红线（不给纵向战力）。

---

## Meta 进度 - 跨 Run 持久化

### 核心设计原则

**Meta 解锁 = 选择的横向扩展，而非纵向数值战力提升。**

在 Meta 进度的任何层级，已解锁的内容都能支撑一套完整的核心玩法体验。以下情况绝不能发生：「由于缺少 Meta 解锁，核心机制缺失，玩家在 Run 中后期发现战力不足且无法弥补。」

| 允许 | 禁止 |
|---------|------------|
| 第二转职未解锁，但第一转职的完整玩法可用 | 由于某个天赋树节点未解锁，导致某个核心连招机制缺失 |
| 高级遗物未解锁，但现有遗物池足以构筑有效的 BD | 由于 Meta 等级太低，基础属性低于正常水平 |
| 新解锁的职业提供新玩法，而非更强的数值 | 后解锁的职业严格强于先解锁的职业 |

### Meta 解锁类别

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

### 详细解锁说明

#### 天赋区域解锁

每个职业的天赋树分为多个区域。初始解锁的区域**包含一条转职路线的完整核心玩法**。完成一次 Run 后，更多区域解锁，开放第二个转职选项。

```
Initial state (Swordsman as example):
  Unlocked: Base area + Sword Saint path area
  -> Player can experience the full Sword Saint gameplay (crit/speed/combos)

After 1 completion:
  Newly unlocked: Magic Swordsman path area
  -> Player gains a new Class Advancement option, but Sword Saint path is not stronger
```

**规则**：对于拥有两个转职的职业，通常只需完成 1 次即可解锁所有转职选项。

#### 遗物解锁

遗物池随 Meta 进度逐步扩展。但初始遗物池已覆盖各类 BD 方向的核心需求。

```
Initial Relic pool:
  Contains base Relics for each archetype (attack/defense/speed/support, etc.)
  -> Sufficient to build an effective BD

Meta unlocks:
  Add more Relics, providing more combination possibilities
  -> Horizontal expansion, not "stronger versions of base Relics"
```

#### 建筑解锁

初始提供核心建筑（如哨塔 Watchtower、路障 Barricade）。Meta 进度解锁新的建筑类型以及现有建筑更高的等级上限。

```
Initial state:
  Buildable: Watchtower Lv1, Barricade Lv1, Life Spring Lv1
  -> Basic battlefield control is available

Meta unlocks:
  New Buildings: Fortress, Ballista, Magic Tower
  Level caps: Watchtower Lv2 -> Lv3, ...
```

#### 职业解锁

v1 起始有 5 个职业（Mercenary/Archer/Mage/Knight/Cleric）；其余职业通过特定条件解锁。

```
Unlock condition examples (pending):
  Swordsman: First completion
  Artificer: Use 3 different Buildings in a Run
  Hunter: Defeat 50 enemies in a Run
```

#### 便利升级

少量不影响核心战力的便利改进，用跨 Run 货币购买。

```
ConvenienceUpgrade examples:
  "starting_gold": +10 per level (max 3)     # Slightly more starting Gold
  "shop_discount": -5% per level (max 2)      # Shop discount
  "extra_reroll": +1 per level (max 2)        # Reward reroll count
  "map_preview": Unlock Stage preview info    # Intel category
```

**注**：不包含「初始 HP 加成」「初始攻击加成」等直接影响战斗数值的升级。便利升级应限于经济层与情报层。

---

## 数据结构

### Act 定义 - Legacy

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

### 门生成数据结构

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

相关文档：
- [天赋树](../Characters/talent-tree.md) -- 天赋节点与转职触发条件 (pending)
- [敌人与 AI](../Core-Systems/enemy-and-ai.md) -- 战斗难度与 Boss 设计
- [职业系统](../Characters/class-system.md) -- 角色成长与构筑
- [开发里程碑](../../02-Development/Milestones/current-milestone.md) -- Phase 5 实现运行循环
