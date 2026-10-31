---
checkpoint: R3
title: SoT 类型成立性 critic 对抗验证
date: 2026-04-23
agent: game-critic
verdict: MODIFY
tier_recommendation: Tier 2
confidence: 3
---

# 对抗验证：SoT 类型成立性 R3

## 总结

- **提案解读**：战棋 + 4p co-op + 多职业复杂天赋树 + roguelite，Godot 4，solo dev
- **analyst 偏好选项**：载体 A（小型战棋）+ Tier 2（30-40 节点）天赋树起步
- **Critic 裁决：MODIFY** — 载体 A 方向站得住，但 4p co-op 作为 Day 1 核心锚点将平衡成本推入 solo dev 危险区；天赋规模 Tier 2 是当前最不坏的选项，但需要严格前置条件；Town Building 被去除后 SoT 差异化被严重削弱。

---

## 任务 1：天赋规模三档硬核判定

### Tier 1（75 节点/职业）— STOP

**证据 1 — Wolcen：复杂被动轮的技术性死亡**

Wolcen: Lords of Mayhem 拥有超大被动技能轮（360 度环形 + 多圈层），开发团队（约 15 人，远超 solo dev）在 2020 年发布后持续 4 年无法修复平衡。2024 年开发商宣布："challenges that are insurmountable without a complete technology overhaul"，9 月停服关闭多人。核心诊断是"foundational architectural decisions"导致平衡迭代无法收敛。技能复杂度是主要技术债来源之一。

- URL：[PC Gamer — Wolcen ends development](https://www.pcgamer.com/games/rpg/wolcen-lords-of-mayhem-ends-development-with-multiplayer-to-shut-down-in-september/)
- URL：[Game Developer — Wolcen loses multiplayer support](https://www.gamedeveloper.com/business/wolcen-lords-of-mayhem-loses-multiplayer-and-dev-support-in-september)
- **Wolcen 团队 15 人仍崩溃，SoT solo dev 面对 600+ 节点平衡面，无参照路径**

**证据 2 — 行业最强 roguelite 主动规避大天赋树**

B1.2 已确认：Hades 2（Supergiant，约 20 人）的 Arcana 仅 25 张；Monster Train（Gambrinous，约 10 人）Champion spec 仅 5 个决策点；Othercide（Lightbulb Crew，约 15 人）直接放弃持久天赋树改用技能解锁。这三支团队有能力做大树但主动不做——这是信号而非偶然。无一例"solo dev + 复杂天赋树 + roguelite 平衡成功"的可引用案例。

- URL：[Othercide Interview — GamingBolt](https://gamingbolt.com/othercide-interview-art-style-classes-battles-and-more)
- URL：[Hades Mirror of Night — TheGamer](https://www.thegamer.com/hades-mirror-of-night-roguelite-progression/)

**量化补充：用户已经展示的迭代成本**

剑士目录 7 个 JSON 版本 + 多份 rationale.md，法师仅 1 个 JSON——仅 1.5 职业已消耗设计资源接近天花板。SoT 目标 8 职业 × 16 路径 × 75 节点 = 约 1200 节点等效平衡面。**即使节奏维持，solo dev 到完成 8 职业约需 40+ 月纯设计迭代，不含实现。**

**裁决：STOP。前置条件不存在（没有 solo dev 成功案例）。**

---

### Tier 2（30-40 节点/职业）— CAUTION（附严格前置条件）

**证据 1 — Hades 系列的"感知深度 > 实际节点数"原理有效**

Hades 1 Mirror of Night（16 大类互斥选项）被大量玩家评为"升级感恰到好处"；Hades 2 Arcana（25 张，有容量约束）延续口碑。Supergiant 用约 25 个有意义决策点实现了玩家感知"复杂构筑"的效果。这是 Tier 2 可行性的核心依据。

- URL：[Arcana Cards & Meta-Progression in Hades 2 — Frostilyte Writes](https://frostilyte.ca/2025/04/09/arcana-cards-meta-progression-in-hades-2-have-me-hooked/)

**证据 2 — Monster Train（约 10 人团队）的 Tier 2 级规模可控**

Monster Train 每 Champion 5 个升级选择点，深度感来自路径互斥而非节点数量。游戏 89% 好评，Monster Train 2 同样 89% 好评。规模可控 + 有意义决策 = 可落地样本。

- URL：[Monster Train Wiki — Champions](https://monster-train.fandom.com/wiki/Champions)

**CAUTION 原因：solo dev 实现成本**

8 职业 × 35 节点 = 280 节点，每节点仍需 balance pass。用户 1.5 职业已暴露迭代漂移风险（7 个 JSON 版本），若不解决"节点设计规范化"问题，Tier 2 仍可能向 Tier 1 膨胀。

**前置条件清单（必须全部满足才能 GO）：**
1. 单职业 Tier 2 完整原型完成，经过 5-10 次 run 内测验证后，再开第 2 职业
2. 建立节点类型白名单（gauge_core / gauge_extend / active_skill / advancement），禁止 stat_minor 类填充节点
3. Bridge Tax 经济学在 Tier 2 规模下验证有效（节点稀少时约束力是否仍存在）

---

### Tier 3（20-25 节点/职业）— CAUTION（差异化失败风险高）

**证据 1 — Banner of the Maid 的"系统太浅"衰减**

Banner of the Maid（战棋 roguelite，小团队）823 → 82 CCU，90% 衰减。玩家反馈中"战斗重复感强"是主要负面标签。战棋 roguelite 若职业差异化主要依赖基础技能而非构筑深度，重复感迅速暴露。

- URL：[Banner of the Maid — Steam](https://store.steampowered.com/app/994730/Banner_of_the_Maid/)

**证据 2 — Hadean Tactics 的 99.5% 衰减曲线**

2045 → 10 CCU（99.5% 衰减），发布 3 天达峰值，随后持续跌落。Hadean Tactics 是战棋+卡牌 roguelite，本身有卡牌构筑深度，但仍发生极速衰减。若 SoT 天赋深度降至 Tier 3，在"卡牌层都无法防住衰减"的情况下，SoT 无其他保留机制。

- URL：[Hadean Tactics — Steam Charts](https://steamcharts.com/app/1260590)
- URL：[Hadean Tactics — Steambase](https://steambase.io/games/hadean-tactics/steam-charts)

**Tier 3 的唯一合理用途**：作为最早期单职业 demo 的测试规模，不应作为正式发布规模。

**裁决：CAUTION。只有 Tier 2 满足前置条件后才合理；若前置条件无法满足，比 Tier 3 更危险的只有 Tier 1。**

---

## 任务 2：攻击 Analyst 3 偏差热点

### 偏差 1：载体 A 因"最直觉战棋"而被偏好——4p 战棋协作动力学真的有趣吗？

**攻击结论：偏差确实存在，且被低估。**

PC Gamer 的专题文章"Co-op and turn-based tactics just don't mix"（2018 年，至今仍被引用）直接描述了战棋 + co-op 的结构性问题：一方行动时，另一方的朋友在玩 Picross；Wargroove Double Trouble DLC 中"只有一名玩家能建造单位，另一名无事可做"。

- URL：[PC Gamer — Co-op and turn-based tactics just don't mix](https://www.pcgamer.com/co-op-and-turn-based-tactics-just-dont-mix/)

Into the Breach 官方 Steam 讨论区：社区明确表示 co-op"会变成一人发号施令，其他人点击执行"。

- URL：[Into the Breach Steam Discussion — No Multiplayer](https://steamcommunity.com/app/590380/discussions/0/1692662484258483661/)

Analyst 用"锚点匹配度高"作为核心理由，但"匹配度高"是系统设计层，"4p 协作是否有趣"是体验层。后者更难量化但更重要。Q1 答将 4p 锁定为 Day 1 核心锚点，这个偏差的后果从"可选风险"升为"阻塞级风险"。

---

### 偏差 2：Tier 2 是"中庸陷阱"还是甜点？

**攻击结论：偏差被部分夸大；Tier 2 仍是最合理区间，但 analyst 未给出"如何避免两头不靠"的具体机制。**

Hades 2 Arcana（25 张）的成功提供了反向证据：25 个节点不等于"两边都不满足"，关键在于每个节点是否有意义。Monster Train 的 5 个 Champion spec 决策点同样被玩家评为"深度足够"。

- URL：[Monster Train Steam Guide — Champion Stat Progression](https://steamcommunity.com/sharedfiles/filedetails/?id=2110877058)

但 Tier 2 的真正风险不是"规模本身"，而是"Five-Staff 布局保留时节点稀疏导致结构空洞感"。30-40 节点硬套 75 节点设计的树形结构，将产生大量视觉上稀疏、决策上空洞的节点位置。Analyst 未指出这个具体失败模式。

**前置要求**：Tier 2 必须重新设计树的拓扑，而非简单裁剪现有 75 节点树。

---

### 偏差 3：ARPG 被弃用是否过早？

**攻击结论：Analyst 判断正确，偏差不存在。**

"ARPG 外壳 + 轻量装备"的中间路径在理论上可行，但实操中仍面临：实时战斗同步成本（Godot 4 生产级案例缺失）+ 美术量（即使轻量也需要大量实时特效 + 怪物库）。Wolcen（15 人团队）做出的"轻量化 ARPG"仍最终崩溃。"轻量 ARPG"的上限是"战棋"——即已回到载体 A。弃用理由充分。

- URL：[Wolcen ends development — PC Gamer](https://www.pcgamer.com/games/rpg/wolcen-lords-of-mayhem-ends-development-with-multiplayer-to-shut-down-in-september/)

---

## 任务 3：验证 6 Guard

**Guard 1：战棋 co-op 一人独断**

风险真实程度：**高**。两条独立证据收敛：(1) Into the Breach Steam 讨论区社区共识；(2) PC Gamer 专题文章用 Wargroove Double Trouble DLC 实例证明"资源不对等导致一方空转"。Q1 将 4p 锁定为核心后，这条风险从 Guard 变为 Day 1 设计约束。

- URL：[PC Gamer — Co-op and turn-based tactics just don't mix](https://www.pcgamer.com/co-op-and-turn-based-tactics-just-dont-mix/)

**Guard 4：Sunderfolk 3.5 周单点数据窗口期**

风险已被验证为真实。最新数据（2026 年 4 月）：Sunderfolk 峰值 CCU 890（2025 年 4 月 27 日）→ 当前约 91 CCU，一年内衰减 **90%**。这与 Hadean Tactics（99.5%）、Banner of the Maid（90%）构成战棋 roguelite 衰减曲线的一致模式。Sunderfolk 的 94% 好评率说明质量不是问题——战棋 roguelite 本身的长尾留存弱点才是结构性问题。

- URL：[Sunderfolk Steam Charts — Steambase](https://steambase.io/games/sunderfolk/steam-charts)
- URL：[Sunderfolk — SteamDB Charts](https://steamdb.info/app/2414270/charts/)

**Guard 2（天赋树 roguelite 解耦）、Guard 3（4p 平衡非线性）、Guard 5（设计漂移）、Guard 6（决策密度冲突）**：B1.2 / B2.1 证据充分，本报告 Tier 1 STOP 裁决已提供追加证据。

---

## 任务 4：STS 式路线资源替代 Town Building 可行性

**结论：条件性可行，但需正视差异化代价。**

**有成功样本**：Slay the Spire 的路径分支（精英/事件/宝箱路线）是资源选择机制的可行参考，但它的资源是卡牌 + 遗物，不是 Gold sink 意义上的经济张力。Othercide 的路径选择（选择拯救哪个 Daughter）同样提供资源取舍，但也没有经济层。

- URL：[Othercide Review — RPGFan](https://www.rpgfan.com/review/othercide/)

**失去 Town Building 后的差异化空洞**：SoT 与 Sunderfolk 的区别曾是"天赋深度 + Town Building 经济层"。去掉 Town Building 后，若 Gold 仅通过 STS 路线分支决定，SoT 本质上变成：战棋底层 + roguelite run + 多职业天赋树。这与 Sunderfolk（战棋 + co-op + 轻量职业系统）的产品差距缩小，与 Into the Breach（战棋 + roguelite + 极简天赋）的产品差距同样缩小。

**反面样本**：Hadean Tactics 去掉了建造层（仅保留卡牌 roguelite + 战棋），结果 99.5% 衰减，长尾留存无法维持。这是"去掉差异化机制后沦为普通战棋 roguelite"最直接的同类失败案例。

- URL：[Hadean Tactics — Steam](https://store.steampowered.com/app/1260590/Hadean_Tactics/)

**判定**：STS 式路线替代 Gold sink 是可行的短期 MVP 方案，但必须明确：失去 Town Building 后，SoT 必须从其他维度补充差异化（天赋深度、co-op 协作机制创新、中国文化叙事），否则产品将在战棋 roguelite 红海中无特征。

---

## 任务 5：Final Verdict — MODIFY

**不选 GO 的原因**：4p co-op 作为 Day 1 锚点 + Tier 2 天赋树 + solo dev 的组合，当前未满足任何一条前置条件，无法直接 GO。

**不选 STOP 的原因**：载体 A 方向有充分正向证据（Sunderfolk 94% 好评、战棋 co-op 市场蓝海），问题在于执行范围，不在于方向本身。

**MODIFY 的决定性证据（5 条）**：

1. **4p co-op 必须从 Day 1 系统设计角度解决"一人独断"问题**，否则战棋 co-op 结构性劣势将在首批评测中暴露。Wargroove Double Trouble DLC 已经示范了这个失败模式。[PC Gamer 专题](https://www.pcgamer.com/co-op-and-turn-based-tactics-just-dont-mix/)

2. **Sunderfolk 一年后 90% CCU 衰减**确认战棋 roguelite 的长尾留存是结构性弱点，不是质量问题。SoT 需要预置长尾保活机制（挑战模式、跨 run 叙事进度等），不能依赖 co-op 粘性。[Steambase](https://steambase.io/games/sunderfolk/steam-charts)

3. **Tier 1（75 节点）是 STOP**，基于 Wolcen 团队 15 人仍无法收敛的直接类比，以及"行业最强 roguelite 团队主动回避大树"的行业共识信号。[PC Gamer — Wolcen](https://www.pcgamer.com/games/rpg/wolcen-lords-of-mayhem-ends-development-with-multiplayer-to-shut-down-in-september/)

4. **Tier 2 可行，但必须重新设计拓扑**（不能裁剪现有树），且需单职业完整原型验证后才能扩展第 2 职业。[Hades 2 Arcana 参考](https://frostilyte.ca/2025/04/09/arcana-cards-meta-progression-in-hades-2-have-me-hooked/)

5. **Town Building 去除后差异化缺口必须填补**。Hadean Tactics 是"去差异化后衰减"的最直接同类案例，SoT 必须在天赋深度、co-op 协作创新或叙事层三选一补充。[Hadean Tactics Steam](https://store.steampowered.com/app/1260590/Hadean_Tactics/)

**MODIFY 具体要求**：
- **修改 1**：将"4p Day 1"降格为"2p Day 1，4p v1.1"，或在 Day 1 设计中加入每职业"不可替代决策域"机制
- **修改 2**：Tier 1 放弃，Tier 2 以重新拓扑的方式实现（非裁剪现有树）
- **修改 3**：去除 Town Building 后必须明确另一条差异化主轴

---

## 反例（同等机制成功案例）

- **Divinity: Original Sin 2**（95% 好评 / 82K 评价）：4p turn-based co-op 成功，但非格子战棋——其成功来自投票决策系统 + 完整叙事 + 15 人团队。SoT 规模无法复制，但"每玩家不可替代决策权"的机制设计值得借鉴。[Steam](https://store.steampowered.com/app/435150/Divinity_Original_Sin_2__Definitive_Edition/)
- **Gloomhaven Digital**（82% 好评 / 10K 评价）：格子战棋 + 4p co-op 有市场，但每局 20-90 分钟 + 无随机匹配 + sticky 小组倾向——留存模式与 roguelite 不同。[Couch Co-op Chronicles](https://couchcoopchronicles.com/gloomhaven-digital/)

---

## 未覆盖区域

- Godot 4 生产级格子战棋 + 4p 网络同步的实际工时数据，无公开样本
- "8 职业 × Tier 2 Tier × roguelite run 平衡"在 solo dev 环境下的月度工时估算，无直接参照
- SoT 中国文化叙事层对留存的独立贡献，未在本次调研中量化

---

## 推荐人工审查问题

1. 2p co-op Day 1 + 4p v1.1 这条分阶段路径，是否与你对产品的核心愿景冲突？
2. Tier 2 的"重新设计拓扑"意味着放弃 Five-Staff 布局或大幅重构——这是否接受？
3. 在 Town Building 缺席的情况下，你认为 SoT 与 Sunderfolk 的核心差异是什么？这个差异是否能在 1 句话内说清楚？

---

## Sources

- [PC Gamer — Wolcen ends development](https://www.pcgamer.com/games/rpg/wolcen-lords-of-mayhem-ends-development-with-multiplayer-to-shut-down-in-september/)
- [Game Developer — Wolcen loses multiplayer support](https://www.gamedeveloper.com/business/wolcen-lords-of-mayhem-loses-multiplayer-and-dev-support-in-september)
- [PC Gamer — Co-op and turn-based tactics just don't mix](https://www.pcgamer.com/co-op-and-turn-based-tactics-just-dont-mix/)
- [Into the Breach Steam Discussion — No Multiplayer](https://steamcommunity.com/app/590380/discussions/0/1692662484258483661/)
- [Sunderfolk Steam Charts — Steambase](https://steambase.io/games/sunderfolk/steam-charts)
- [Sunderfolk — SteamDB Charts](https://steamdb.info/app/2414270/charts/)
- [Hadean Tactics — Steam](https://store.steampowered.com/app/1260590/Hadean_Tactics/)
- [Hadean Tactics — Steam Charts](https://steamcharts.com/app/1260590)
- [Hadean Tactics — Steambase](https://steambase.io/games/hadean-tactics/steam-charts)
- [Banner of the Maid — Steam](https://store.steampowered.com/app/994730/Banner_of_the_Maid/)
- [Hades Mirror of Night — TheGamer](https://www.thegamer.com/hades-mirror-of-night-roguelite-progression/)
- [Arcana Cards & Meta-Progression in Hades 2 — Frostilyte Writes](https://frostilyte.ca/2025/04/09/arcana-cards-meta-progression-in-hades-2-have-me-hooked/)
- [Monster Train Wiki — Champions](https://monster-train.fandom.com/wiki/Champions)
- [Monster Train Steam Guide — Champion Stat Progression](https://steamcommunity.com/sharedfiles/filedetails/?id=2110877058)
- [Othercide Interview — GamingBolt](https://gamingbolt.com/othercide-interview-art-style-classes-battles-and-more)
- [Othercide Review — RPGFan](https://www.rpgfan.com/review/othercide/)
- [Gloomhaven — Couch Co-op Chronicles](https://couchcoopchronicles.com/gloomhaven-digital/)
- [Divinity: Original Sin 2 — Steam](https://store.steampowered.com/app/435150/Divinity_Original_Sin_2__Definitive_Edition/)
- [Slay the Spire 2 Review Bombing — Kotaku](https://kotaku.com/slay-the-spire-2-steam-review-bomb-balance-patch-prepared-doormaker-2000680603)
- [Slay the Spire 2 Co-op 4-player balance — Steam](https://steamcommunity.com/app/2868840/discussions/0/802341528343295534/)
