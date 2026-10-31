---
session: S67
date: 2026-04-23
status: FINAL (基于 SoT KB 真实架构重写)
supersedes:
  - B1.2-talent-roguelite-decoupling.md (错误类比部分)
  - B2.1-talent-modifier-patterns.md (错误类比部分)
  - R2-analyst-viability.md (基于"永久节点图"假设)
  - R3-critic-failmodes.md (基于"永久节点图"假设)
  - R2-v2-analyst-viability.md (基于"永久节点图"假设)
  - R3-v2-critic-failmodes.md (基于"永久节点图"假设)
  - S67-SYNTHESIS.md (前版基于 subagent 推测, 未读 KB)
source_of_truth:
  - 01-Game-Design/game-design-doc.md
  - 01-Game-Design/Characters/class-system.md
  - 01-Game-Design/Progression/run-loop.md
  - 01-Game-Design/Characters/talent-tree-design.md
---

# S67 Final Synthesis: 基于 KB 真实架构的战略评估

## 前序多轮失效原因

S66 + S67 前 4 个 checkpoint (B3 / R2-v2 / R3-v2 / 前版 synthesis) 都基于 subagent 推测或 session handoff 片段脑补 SoT 架构，未读 SoT KB。结果累积了以下**全部需要撤回**的事实错误：

| 错误主张 | KB 真实 |
|---------|---------|
| SoT 是"永久固定节点图天赋树" | Run-reset 天赋树 + Meta 层横向解锁池 |
| 永久节点跨 run 需平衡 → Tier 2 成本爆炸 | Run 内只点 ~25 点，平衡边界是 run 内 build |
| "4p 同时出招" | **Speed-based turn order**（按速度降序单位序） |
| "每职业独特能量系统" | **BG3 式统一 Action Economy** (Move/Standard/Swift) + **Advancement 层独特 Gauge** |
| "Co-op 深度耦合" | GameAction 同步弱耦合（当前行动者 broadcast） |

所有基于以上错误的结论（Tier 2 STOP / Path D 主选 / Path E 备选 / "行业空白 = 雷")**全部撤回**。

## SoT 真实架构（KB 直接引用）

### Turn & Action System (`game-design-doc.md` §1)

- **Speed-based turn order**: 每回合所有单位按 `speed` 降序行动
  - Initiative priority 0/+1/+2 可覆盖速度
  - 同速: 低难度玩家先 / 高难度敌方先
  - Not CT (charge time) accumulation
- **BG3 式 Action Economy** (每回合每单位):
  - 1 Movement 点 (移动 OR `[Move Action]` 技能二选一)
  - 1 Attack Opportunity (普攻 OR `[Standard Action]` 二选一)
  - 1 Swift Action (`[Swift Action]` 轻技能)
  - Reaction (条件触发)
  - Free (无消耗)
- **设计 rationale**: 防止"一回合甩完所有技能" —— 同类技能互相竞争

### Class System (`class-system.md`)

- **8 base classes** × 2 advancement = **16 paths** (Mage 有 4 含元素互斥)
- **v1 测试用 5 职业**: Soldier / Archer / Mage / Knight / Cleric
- Class Advancement: 由特殊天赋节点触发，**一旦选择不可逆**
- **Gauge 在 advancement 层**（不是 base class 层）:
  - Blade Master: Sword Intent 剑意 (0-100 energy，累积+衰减+阈值分段)
  - Sword Cultivator: Sword Essence 剑髓 (MP 式自然回复+消耗)
  - Mage 三元素: Hellfire / Frost / Gale (0-100，互斥)
  - 其它 advancement gauge 待定
- **Follow-up Attack (FE 系)**: `(attacker.SPD - defender.SPD) × 10%`，所有职业适用，剑士线深耕
- **Counter-attack**: 非 area 攻击，射程够 + 活 + 未失能就反击
- **Build = Class + Advancement + Talent Tree + Equipment + Random Skills/Relics**

### Talent Tree (`talent-tree-design.md`)

- **Five-Staff 拓扑**: 5 条 x 轴轨道 (-400/-200/0/+200/+400)
- **Level 锚点**:
  - Lv 10 Class Advancement (分岔起点)
  - Lv 15 Minor threshold (gauge 成型)
  - Lv 20 Major threshold `_qual` (faction 终极技能)
  - Lv 22-25 Terminal anchor (实际终极落点)
  - Lv 30 上限
- **Bridge Tax**: 跨 faction 节点延迟终极 1-2 级（核心权衡 "Specialization vs Synergy"）
- **Dijkstra 自动计算** node level (每 node cost=1, edges 决定拓扑)
- **Budget**: Lv 1-10 共享 ~17 cost + Lv 11-30 单极主链 ~20-22 cost
- **平均玩家 Lv 25 点 ~25 点 = 共享 + 1 个 side path**

### Roguelite Integration (`talent-tree-design.md` §7)

- **双层决策架构**:
  - **Meta 层**: 天赋树永久解锁（horizontal only, 解锁更多树区）
  - **Run 内**: 从已解锁池主动选择激活（非随机推送）
- **天赋 vs 建筑资源竞争** = KB 标注的 core differentiator
  - ⚠️ **S67 用户澄清 (2026-04-23)**: S66 Q3 原意非"彻底去除 Town Building"，实际为 "Town Building 保留作经济+商店兜底，但从 core differentiator 降级"；差异化主推替换为"战棋内差异化天赋树架构"（Five-Staff 拓扑 + Class Advancement 不可逆）

### Meta Progression (`run-loop.md` §Meta Progression)

- **硬原则**: Meta = horizontal unlocks, NEVER vertical power
  - ✓ 解锁新 class / advancement / relic / building
  - ✓ 便利升级（经济/信息层，不影响战力）
  - ✗ 起始 HP/attack 增益
  - ✗ 核心机制锁在 meta 后
- **便利升级上限示例**: starting_gold +10/lvl (max 3), shop_discount -5%/lvl (max 2), extra_reroll +1 (max 2), map_preview 解锁

### Multiplayer (`game-design-doc.md` §1.3, §8)

- 1-4p (单人控 1-4，多人每人控 1)
- **GameAction 同步**: 所有操作封装为 GameAction；单人直执行，多人广播后执行
- Turn-order 系统下，**只有当前行动者需同步** —— 不是同步出招
- Godot High-Level Multiplayer API, Host-Client

## Last Spell 重新对标（基于 B3.2 数据 + KB 真实架构）

| 维度 | Last Spell | SoT (KB) |
|------|-----------|----------|
| Turn system | 单人轮流 | **Speed-based multi-unit turn order** |
| Action economy | (未查) | **BG3 式** (Move/Std/Swift 三类竞争) |
| Run 内天赋结构 | 8 列 × 5 层分层解锁（**线性无分支**） | **Five-Staff 5 轨道 + Bridge Tax + Dijkstra 前置** |
| Run 内天赋投入 | 10 点 (Lv 11) | **~25 点** (Lv 25 平均) |
| Advancement | 无 | **Lv 10 不可逆分岔**，16 paths 含 Mage 4 元素互斥 |
| Gauge | 无 | **Advancement 层独特 gauge**（Sword Intent / Sword Essence / 三元素等） |
| Random 机制 | **升级时盲随机**（3 选 1 与 build 无关） | **Run 内主动从池选**（非推送） |
| Meta 原则 | 数值升级 + 解锁天赋选项 | **Horizontal ONLY**，硬原则 |
| Co-op | 无 (Steam PC 版) | **1-4p GameAction 同步** (按速度序) |
| Run 结构 | 1 城市 × 12 夜 (塔防) | **3 Acts × 10 stages + Prep 阶段** |

**SoT 在每一个对标维度都比 Last Spell 深一个档次**。Last Spell 玩家吐槽的三个痛点，SoT 架构已内建解法：

| Last Spell 痛点 | SoT 解法 |
|----------------|---------|
| 天赋单调（8 列线性无分支） | Five-Staff + Bridge Tax + Advancement 不可逆 |
| 随机过强（升级盲推） | Run 内玩家**主动**从已解锁池选激活 |
| 人物成长单调（meta 只给数值） | Meta horizontal unlocks (新 class/advancement/relic/building) |

## SoT 真实差异化空白（vs 所有同类参考系）

基于 B3.2 样本（Last Spell 85% / DD2 80% / Gordian Quest 75% / Iratus 70% / For the King 2 70%）+ KB 真实架构比对：

1. **Five-Staff 5 轨道 + Bridge Tax 拓扑** —— 所有参考系都是线性分层（Last Spell）/ micro-deckbuild（DD2）/ 卡牌池（Gordian）/ 4 独立树无桥（Iratus）。**"跨 faction 延迟终极"这个权衡机制是 SoT 独有**
2. **Advancement 层独特 Gauge** —— 所有参考系统一资源（AP / mana / card energy）。SoT 每 advancement 有独立 gauge（Sword Intent 累积/衰减、Sword Essence MP 式、Hellfire/Frost/Gale 三元素互斥），**build identity 在资源系统层就分化**
3. **Run 内主动池选 vs 盲随机推送** —— Last Spell / DD2 / For the King 2 都是游戏推你选项。SoT 玩家在 meta 层看得到整棵树，run 内主动规划路径，这是**从 deckbuilder 哲学回到 ARPG build planning 哲学**的回归
4. **Action Economy 三类型竞争移植到战棋** —— BG3 的 Move/Standard/Swift 竞争机制在战棋 roguelite 里没有先例。Last Spell 只有 AP/MP；其它 deckbuilder 只有 card energy。**"同类技能互相竞争"带来 build balancing 义务**（不能堆 Standard）
5. **Speed-based turn order + FE-Additive + Follow-up × 10%** —— Last Spell 轮流制无速度差；FE 系在 roguelite 里没人做。SoT 继承 FE 血脉并扩展（Follow-up 是**所有职业**参与的追击系统，剑士线深耕）

## 真实风险清单（基于 KB 真实内容）

替代 R2-v2 的"Tier 2 STOP"虚假风险：

### R1: Dual-layer 学习曲线 (HIGH)

玩家面对 **5 层选择系统**：
1. Class 选择
2. Meta 层天赋树解锁区
3. Run 内从池选激活节点
4. Class Advancement 不可逆分岔
5. Advancement 独特 Gauge 机制

新手流失点密集。Last Spell 2 层就被吐槽"还要玩法主推重做"，SoT 5 层是**深度教学设计压力**。

### R2: Speed-based turn order 在 4p 的等待时长 (HIGH)

低速职业 (Knight SPD 6, Mage 7, Cleric 7) 玩家在 4p + 多敌人场景每回合等 4-10 个单位走完。Sunderfolk (`B1.3`) 已证 4p 战棋 co-op 市场天花板低，等待时长会放大这个弱点。

Mitigation: 同步 AI 敌方行动播放（不等待玩家确认）？预览下一轮顺序？

### R3: Class Advancement 不可逆 × Run-reset 张力 (MEDIUM)

Lv 10 分岔后本 run 锁定 20+ 轮战斗；下 run 可换。这个设计理论 elegant（roguelite 试错），但对不可逆选择的**心理承担感**要求高。

玩家可能在 Lv 10 出现"要不要刷到出我想要的再分岔"的反逻辑行为。

### R4: Follow-up Attack 全体参与的速度竞赛平衡 (MEDIUM)

所有职业都参与 `(attacker.SPD - defender.SPD) × 10%` 追击。低速职业 (Knight SPD 6, Mage SPD 7) 会被高速 (Swordsman 12, Archer 10, Hunter 10) 打，需要**其它维度补偿**（KB class-system 已列补偿框架：高单击/高防御/控制/安全射程）。

风险：具体补偿数值未定，8 职业 × 16 advancement 都要满足补偿自洽 = 平衡工程量。

### R5: GameAction 同步 + Speed-based turn order 的多人网络 (MEDIUM)

Speed-based 意味着每回合 host 重新计算 turn order 再 broadcast；行动者切换频繁 + buff/debuff timing 复杂 (trigger start / decrement end / apply immediate)。Godot HL MP API 官方 async 模式需验证是否能支撑。

### R6: 8 × 16 × Gauge × Talent Tree 的设计工程量 (HIGH, 但 run-reset 部分缓解)

即使 run-reset 不需跨 run 平衡，每 gauge 独立规则（上限/衰减/阈值）+ Five-Staff 拓扑（剑士已有 deep-dive-rules + 5 版 JSON） × 16 advancement = 真实设计周数不少。

Mitigation (用户已在做):
- 天赋节点用**方向性描述**代替精确数值
- 数值节点解耦到 roguelite 成长层
- 转职差异化用独立 gauge 承担（"特殊职业资源"机制）

### R7: Lv 25 平均 vs Lv 30 上限的终极体验分布 (LOW)

Bridge Tax 让跨 faction build 延迟 1-2 级 → Lv 28+ 才能兑现跨路线 ult。但一个 run = 3 Acts × 10 stages = 30 stage，期望 3-5 level-ups per run → Lv 25 = 多 run 累计。

意味着**第一 run 永远摸不到 Lv 28+ 的跨路线终极** —— 除非每 run 获得 8+ 级。需验证 EXP 曲线。

## 真正的卡点：Design Philosophy 排序

GDD §13 列了 7 条 Design Philosophy，但**未排序**。这是剑士 7 版 JSON 换设计轴（cycle / matrix / onhit / overwatch / starburst）的根因 —— 每版在试不同 philosophy 优先级。

7 条 philosophy (GDD):
1. Fun at normal, depth at hard
2. Meta horizontal not vertical
3. Talents skeleton + randomness flesh
4. Full attribute transparency (FE additive)
5. **Town Building core differentiator ⚠️ (S67 用户决策: 降级为经济+商店兜底，core differentiator 由主推 C 继任)**
6. Class Advancement directional choice
7. Action resources strategic depth

去除 #5 后，真正的 pillar 候选：

| 候选主推 | 对应机制 | 剑士试过的版本 |
|---------|---------|---------------|
| **A. Action Economy 资源博弈** | BG3 Move/Std/Swift 竞争 | sw_cycle (循环触发) |
| **B. Speed-based 追击系** | FE Follow-up 深耕 | sw_overwatch (速度差)? |
| **C. Bridge Tax 分化哲学** | Five-Staff + 跨 faction 延迟 | sw_matrix (矩阵路径) |
| **D. Gauge 多样 build identity** | Advancement 独特资源 | sw_starburst (爆发 burst) |
| **E. Dual-layer meta-run 决策** | 解锁池 → 激活选 | sw_onhit_v3? |

**用户需要做的选择**: 这 5 个候选**选 1 个做主推，2 个次推，其余撤**。Last Spell 商业成功证明"一个清晰主推 + 玩家能一句话描述"在这个品类有市场空间。

## S67 用户决策 (2026-04-23)

### 决策 1: 主推锁定 = C (战棋内差异化天赋树架构)

**措辞**: "以战棋为载体，用差异化天赋树（Five-Staff 拓扑 + Bridge Tax + Class Advancement 不可逆分岔）作为核心 build 决策机制"

次推候选保留: A (Action Economy 博弈) 与 D (Gauge 多样) 作为支撑机制，不作差异化宣传 pillar。

### 决策 2: Town Building 保留但降级

**非彻底去除**。Town Building 保留为经济+商店系统兜底（即使 Artificer 未出场 v1 也保留）。从 "core differentiator" 降级为"经济循环组件"。

**KB 编辑范围（待用户授权执行）**:
- `game-design-doc.md` Line 18 Project Overview Core Differentiator: 替换为主推 C 表述
- `game-design-doc.md` Line 308 Philosophy #5: "Town Building is the core differentiator" → "Differentiated talent trees are the core differentiator"
- `talent-tree-design.md` §7.2 Lines 223-226: "town building integrated" 描述调整，核心差异化归位天赋树
- `Progression/town-building.md` Line 7: "core differentiating gameplay" 降级措辞
- **其它 11 个文档 Town Building 引用不动**（genre / core loop / Artificer / building durability / grid / network / preparation phase 全保留）

### 决策 3: 剑士权威版本 = JSON (sw_matrix_true_path)

- 权威实现: `data/talent-tree/sw_matrix_true_path.json` (L/M/R 3 路)
- 前置文档 `talent-tree-design.md` §4.1 Five-Staff 5 轨道**已过时**
- 处理方式（待用户确认 a/b/c）:
  - (a) 过时标注 warning box，保留设计哲学（推荐）
  - (b) 重写 §4.1 基于 matrix 真实拓扑
  - (c) 删除 §4 + §5，只留通用哲学
- **未来简化方向**: 天赋树仅保留关键功能性节点，通用数值节点迁至 roguelite 层（relic / equipment / meta 成长）—— 降低学习门槛 + 设计难度 + 平衡难度
- 其它 6 版 JSON (sw_a / sw_cycle_v3 / sw_onhit_v3 / sw_overwatch_v3 / sw_starburst / sw_a_deep) 归入探索历史

### 决策 4: v1 职业范围保持不变

v1 测试 5 职业 (Soldier/Archer/Mage/Knight/Cleric) 不变，剑士/Hunter/Artificer 后加。剑士 matrix 设计先行，但不影响 v1 MVP 路径。

## 下一步行动

### 已完成
- [x] S67 B3.2 落盘 (Last Spell + 同类样本, 真实数据)
- [x] S67-FINAL 落盘（本文，基于 KB 真实架构 + 用户 4 决策）
- [x] 旧 S67 文档 (B3 / R2-v2 / R3-v2 / S67-SYNTHESIS) 保留作历史；本 FINAL 是权威

### 已落地（2026-04-23 ~ 2026-04-23 内）

**KB 编辑（GDD + talent-tree-design + town-building.md 3 份文档）— 全部 ✅**:
- ✅ GDD Line 18 Core Differentiator 替换为 S67 推荐措辞 — commit `41c6ac6` `docs(S67): adopt differentiated talent tree architecture as core differentiator`
- ✅ GDD Line 308 Philosophy #5 替换 — "Town Building is the core differentiator" → "Differentiated talent trees are the core differentiator: Per-class talent topology + Bridge Tax + irreversible Class Advancement force build specialization; Town Building provides economy floor, not differentiation" — commit `41c6ac6`
- ✅ town-building.md Line 7 降级措辞 — "Town Building is the economy and shop system floor of this game's v1; the core differentiator is the talent tree architecture" — commit `41c6ac6`
- ✅ talent-tree-design.md §4.1 Five-Staff 处理方式 = **(b)** — §4 重写为 "Per-Class Topology Implementations (Reference JSON)" + §4.3 历史参考保留 deprecated 标注 + §7.2 economic decisions 调整 "core differentiator is the talent tree architecture itself" — commit `41c6ac6`
- ✅ post-v1 cleanup: legacy Five-Staff / 4-element / Sword Cultivator 内容移除 — commit `b88ce85` `docs(S68): post-v1 cleanup`
- ✅ follow-up: Sword Cultivator (剑仙) 恢复 + archer Five-Staff 坐标移除 — commit `c86b517` `docs(S68): follow-up cleanup`

**S1-side-sot ledger 漏记此事件，由 S2-side-sot 2026-05-10 backfill 到 `current-session.md`**

### 可选补充调研（pending — 未触发）

- Speed-based turn order 在 4p multiplayer 等待时长缓解方案（Triangle Strategy / Tactics Ogre / FFT 怎么做）
- BG3 Action Economy 移植到战棋 roguelite 的 UI/UX 教学曲线（尤其新手）
- FE Follow-up 系在 4p co-op 里的玩家认知负担（FE: Three Hopes / FE: Engage 多人模式数据）

## 信度声明

- **KB 架构引用**: 信度 5/5（直接读文档，已交叉核对 GDD / class-system / run-loop / talent-tree-design）
- **Last Spell 对比**: 信度 4/5（B3.2 数据扎实，但用户个人对 Last Spell 的评价是 n=1）
- **真实风险清单**: 信度 3/5（R1/R2 高置信；R4-R6 需数值原型验证）
- **Philosophy 排序建议**: 信度 2/5（5 候选穷尽性未验，且排序权归用户）

## Sources

真实来源全部为 SoT KB:
- `01-Game-Design/game-design-doc.md` (v1.0 GDD)
- `01-Game-Design/Characters/class-system.md`
- `01-Game-Design/Progression/run-loop.md`
- `01-Game-Design/Characters/talent-tree-design.md`
- `01-Game-Design/Characters/talent-tree-deep-dive-rules.md` (未完整读，deep dive 补充)
- `data/talent-tree/sw_*.json` (7 版本 + 3 rationale)

B3.2 外部引用见 `B3.2-lastspell-and-tactical-roguelite-samples.md`
