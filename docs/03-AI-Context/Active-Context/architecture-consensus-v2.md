---
title: SoT 5-Layer Architecture Consensus v2
session: S3-side-sot
date: 2026-05-10
status: consensus_locked
supersedes:
  - "S67 §7.1 reset semantics: 'Meta 永久解锁 + run partial activation' is wrong; L2 = full reset, meta = L1 (separate pool)"
amended:
  - "2026-07-02 ADR-010: L5 terminology Rune -> Relic (user ruling D-A, run-loop proposal round 2). Rune deprecated as term; 6-slot mechanics unchanged. See 02-Development/Decisions/adr-2026-07-02-relic-canonical-rune-deprecated.md"
  - "2026-08-03 (user ruling): class advancement happens at Lv5 and costs no talent point. §3 Run decision path updated accordingly. Run structure is 3 Acts x 8 Stages = 24 stages, expected end level Lv25-30 (class-system.md). Talent organisation is currently a flat card pool (design library /api/talents). See 01-Game-Design/Characters/talent-tree.md"
visual_companion: architecture-consensus-v2.html
authority: user-confirmed (S3-side-sot, 2026-05-10)
applies_to:
  - 01-Game-Design/game-design-doc.md
  - 01-Game-Design/Characters/class-system.md
  - 01-Game-Design/Characters/talent-tree-design.md
  - 01-Game-Design/Progression/run-loop.md
  - 02-Development/Decisions/adr-2026-07-02-relic-canonical-rune-deprecated.md (ADR-010, L5 terminology)
---

# Ship of Theseus — 5-Layer Architecture Consensus v2

> **TL;DR**: SoT build/growth 由 5 层组成（L1 Global / L2 天赋 / L3 人物成长 / L4 装备 / L5 遗物 6 格），每层独立可玩。L2 完全 reset, 不是 partial activation. L5 遗物是核心 build-defining 机制之一（与 L2 重要节点等价）。L4 装备不构筑 build。
>
> 可视化版: [architecture-consensus-v2.html](architecture-consensus-v2.html)

> **术语修订 2026-07-02（ADR-010）**：L5 原名「符文 Rune」，经用户裁决（run-loop 提案第二轮 D-A）统一为**「遗物 Relic」**——Relic 为正典、Rune 判废案（仅存于历史/研究归档）。6 槽机制、经济类/流派类 archetype、build-defining 定位均不变，本文其余结论不受影响。原 Δ-2 的「旧 relic 概念待 D5 并入或弃用」由该裁决解决：同一系统、以 Relic 为名。本文以下术语已同步。

---

## 1. 五层架构总览

| 层 | 实体 | 重置 | 影响 | 决策时机 |
|---|---|---|---|---|
| **L1 Global 成长** | 职业解锁 / 收益增益 / 起始属性 / 复活 / run 起始赠送 1 遗物 | ✗ 永久 | 小 | run 外 |
| **L2 局内职业天赋** | per-class 天赋池，每 run **完全清零，从 Lv1 重新开始** | ✓ 全清 | 深 | run 内每升级 |
| **L3 人物成长** | 类固定 stat 曲线，**转职后 growth rate 改变** (FE 模式) | ✗ 类固定 | 中 | 自动；受 L5 经济类遗物加成 |
| **L4 装备 (武器 + 防具)** | 暗金/词缀模式，**不承担 build-defining** | ✓ run-reset | 小→中 | run 内随机捡到 |
| **L5 遗物 Relic 6 格** ⭐ | 经济类（EXP/属性/天赋点）+ 流派类（改变职业形态） | ✓ run-reset | 中→大 | run 内奖励/商店/事件（城镇渠道暂缓） |

详见 HTML 第 1 节 layer cards.

---

## 2. 渐进式 Layered 可玩性原则

**设计验证准则**: 每层独立可玩，从下往上叠加。任一上层被剥离，下层仍能跑.

```
战棋 (base, 含 L3 人物成长 + 属性 + 成长曲线 + 伤害计算 + 行动经济)
  ↓ 加 L2 天赋 → 仍成立
  ↓ 加 L4 装备 + L5 遗物 → 完整目标玩法
```

**意义**:
- L_base 战棋本身必须能玩（即使去掉 L2/L4/L5）
- L2 天赋 + 战棋必须能玩（即使去掉 L4/L5）
- 这是设计验证 + 开发顺序的强约束

---

## 3. Run 决策路径

```
Run 起始 (L1 已锁定)
  → 选职业 + 初期战斗策略
     ↓
  Lv 1-4: 战斗 / 升级（L2 前段，每级 1 点）
     ↓
  ★ Lv 5 转职 (第一重要决策点)
     - 看本 run 已持遗物池
     - 选转职方向（下位 → 上位，设计库 promotes_from 为准）
     - 触发 L3 growth rate 切换 (FE 模式)
     - 转职本身不占天赋点；另有奥义形态二选一，占 1 点
       （后半句来自 B-design-proposals §0.1，该研究档 scope 自述「仅剑圣，不含剑仙」，
         是否推广到全部职业未经裁决）
     ↓
  Lv 6 起: L2 天赋加点 + L5 遗物组合（主决策密度）
     ↓
  L4 装备: 随机捡到，决策密度低
```

> 关卡结构 = 3 Acts × 8 Stages = 24 关，预期终局等级 **Lv25-30**（真源 [[../../01-Game-Design/Characters/class-system|职业系统]]）。天赋的组织形态与转职节奏详见 [[../../01-Game-Design/Characters/talent-tree|天赋树系统]]。

**关键**: 转职时玩家需要看遗物池决定方向 — 即 **L5 遗物池 ↔ L2 转职选择** 是核心 build-defining 耦合.

---

## 4. 跨层耦合矩阵

| 输出层 ↓ \ 接收层 → | L1 | L2 | L3 | L4 | L5 |
|---|---|---|---|---|---|
| **L1 Global** | — | 解锁更多 class | 轻微初始 stat | 解锁更多装备种类 | run 起始赠 1 遗物 |
| **L2 天赋** | — | — | 转职触发 growth 切换 | 解锁特定攻击类型 / proficiency | — |
| **L3 成长** | — | 提供投点起点 stat | — | 装备需求 stat 阈值 | — |
| **L4 装备** | — | — | 装备词缀微 stat | — | 装备/遗物协同 (火属性武器 × 燃烧遗物) |
| **L5 遗物** | — | — | **经济类遗物 → EXP/属性/天赋点** ⭐ | — | — |

**强耦合点**:
- **L5 流派类 → L2 节点行为变质** (扩散燃烧、即时结算 = 改变 L2 已有节点的工作方式)
- **L5 经济类 → L3 成长加速** (中等影响但 stay-within-class-model)
- **L4 × L5 协同** (火武器 × 燃烧遗物 = 风味放大)

---

## 5. KB Delta（共识落地需要写/改）

### Δ-1: S67 §7.1 reset 语义错误（待修正）

**原文**: "天赋树使用永久解锁 + run 内主动池选激活"
**修正**: L2 天赋树 **每 run 完全清零，从 Lv1 重新开始**；meta layer = L1（独立池），不是 L2 的子集。

影响文件: `01-Game-Design/Characters/talent-tree-design.md` §7.1, `03-AI-Context/Research/sot-viability-2026-04-22/S67-FINAL-SYNTHESIS.md` (note: S67-FINAL 历史档案，附 deprecation notice，不重写)

### Δ-2: 遗物系统全新立档

新文件: `01-Game-Design/Core-Systems/relics-system.md`（原计划名 `runes-system.md`，按 ADR-010 更名；仍待落地）

需包含: 6 slot 机制 / 经济类 archetype / 流派类 archetype / 与 L4 装备的边界 / 与 L2 天赋的耦合接口.

~~旧 relic 概念: D5 决定并入或弃用.~~ **已解决（2026-07-02 ADR-010）**: 同一系统，Relic 为正典名、Rune 废案；原 D5 的「并入或弃用」问题就此关闭。

### Δ-3: L4 装备约束新立

硬约束: **装备不构筑核心 build**（暗金随机 + run-reset → 玩家无法围绕装备规划）.

影响文件: `01-Game-Design/Core-Systems/equipment.md`（如已存在）或新立 + GDD §装备章节.

### Δ-4: L3 转职 growth rate 切换

FE 模式: 不同 advancement 有不同 per-level growth rate + 即时属性增减.

影响文件: `01-Game-Design/Characters/class-system.md` §成长 + 16 advancement growth rate 表.

### Δ-5: L2 → L3/L5 节点迁移目录

`data/talent-tree/sw_matrix_true_path.json` 当前 83 节点（49 passive） → prune target ~30-40 节点.

需要明确: 哪些 passive → L3 自动成长 / L5 遗物池 / 保留 L2.

输出: `talent-tree-design.md` §4.2 改写为可执行版（per node-type 处理表 + 阈值）.

---

## 6. Team 派发计划

### Stage 1: 共识落地（Claude Main 自承）

- ✅ 本文件 (`architecture-consensus-v2.md`)
- ✅ 可视化 (`architecture-consensus-v2.html`)
- 用作所有 Stage 2 stream 的共享输入

### Stage 2: 5 Design Streams（并行，Mercury core `design` × 5）

| Stream | 任务 | 关键输出 |
|---|---|---|
| **D1** | L1 Global 解锁池 spec | 解锁项分类 + 数量上限 + 每项 horizontal-only 验证（Hades / Rogue Legacy 2 / Dead Cells reference） |
| **D2** | L2 简化规则 + sw_matrix prune 提案 | 每 node-type 处理清单 + 83 → target 节点的 prune demo |
| **D3** | L3 stat 曲线 + 转职 growth rate 表 | 5 v1 职业 × 16 advancement growth 矩阵（FE Three Houses 参考） |
| **D4** | L4 装备 + 词缀设计空间 | 武器/防具类型矩阵 + 词缀深度上限 (非 build-defining 数值边界) |
| **D5** ⭐ | L5 遗物 6 格系统 | 6 slot 机制 + 经济类/流派类 archetype + 业内 reference (STS Relic / Hades Boon / Inscryption / Noita)。术语按 ADR-010 用 Relic |

### Stage 3: Synthesis + Critic + Acceptance

| Agent | 任务 |
|---|---|
| Mercury `design` | 5 层耦合 spec + run 决策密度模拟 + reconcile Mage 5 决策点 |
| Mercury `critic` | 对抗性漏洞扫描 |
| Mercury `acceptance` | 与 GDD / class-system / S67 (locked parts) 一致性检查 |

**预算**: Stage 2 ~125k tokens (5 × 25k), Stage 3 ~60k. 合计 **~200k tokens**.

---

## 7. 名词表 (provisional)

| 术语 | 含义 | 状态 |
|---|---|---|
| **遗物 (Relic)** | L5 6 格内的物品。两类 archetype。原名「符文 Rune」，2026-07-02 ADR-010 定 Relic 为正典、Rune 废案 | 术语 locked（ADR-010）；archetype 细节 D5 后定 |
| **经济类遗物** | 提升 EXP / 属性 / 天赋点。中等影响。基于原职业模型 | locked |
| **流派类遗物** | 改变职业形态/玩法模式。大影响。等价 L2 重要节点 | locked |
| **渐进式 Layered 可玩性** | 每层独立成立，从下往上叠加 | locked (架构原则) |
| **Build-defining** | 玩家围绕此构筑路线的核心机制。L2 + L5 流派类承担；L4 装备**不**承担 | locked |
| **horizontal-only** | L1 meta 解锁原则：仅扩宽选项，绝不增加 vertical power | locked (与 S67 一致) |

---

## 8. Open Questions (留待 Stage 2 各 stream 解决)

每个 stream 拿到本 consensus 后需自行决定的开放问题:

- **D1**: 复活机制是否 free？还是消耗稀有资源？run 起始赠送的遗物是否玩家可选 vs 随机?
- **D2**: 49 passive 中纯数值传统加成 (e.g. ATK+5%) 是不是全迁出 L2? 哪些条件触发型 passive 保留 L2?
- **D3**: 16 advancement growth rate 怎么 balance 不让某 advancement strictly dominant? 用 FE Three Houses 还是 FE Engage 的 growth 模型？
- **D4**: 装备词缀深度上限到底多少 (e.g. 单词缀效果 ≤ 15% stat boost, ≤ 1 个有限触发条件)? Build-defining 的硬性边界?
- **D5**: 6 格之外有 reroll 机制吗? 遗物是否有 rarity tier? 遗物获取的 cost curve（商店/事件定价；城镇渠道暂缓）? 流派类遗物 vs 流派类 L2 节点 怎么不冲突?

---

*Generated: S3-side-sot 2026-05-10. Authority: user confirmed. Modifications require user re-confirmation.*
*Amended: 2026-07-02 per ADR-010 (L5 terminology Rune -> Relic, user ruling). L5 决策时机原写「town 经济稳定 + run 内事件」，因城镇系统在 run-loop v1/v2 暂缓（2026-07-02 裁决）改为「run 内奖励/商店/事件（城镇渠道暂缓）」——是暂缓、非从 L5 设计永久移除；此连带修订已在 ADR-010 中声明。*
