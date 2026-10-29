---
agent: game-researcher
model: haiku
tools: WebSearch, Read
runtime_seconds: 169
total_tokens: 36891
tool_uses: 16
session: S2-side-sot
date: 2026-05-10
purpose: Q1-Q5 genre precedent research for Mage 3-element-exclusion + trapezoid topology
---

# 研究报告：战棋 RPG 天赋树设计先例 - 元素互斥 + 梯形拓扑 + Grand Sage 通才解禁

## Scope（调研边界）

**问题重述**：为 Ship of Theseus (Godot 4 战棋 RPG + Roguelite) 的 Mage 职业天赋树 trapezoid 拓扑 (3 origin → 2 advancement → pool) 做 genre sanity check。

**游戏扫描**（按优先级）:
1. Final Fantasy Tactics (Job system + JP gating)
2. Fire Emblem: Three Houses (Class promotion, dual advancement)
3. Baldur's Gate 3 (Subclass selection)
4. Octopath Traveler (Sub-job mutual exclusivity evolution)
5. Bravely Default II (Dual job system)
6. D&D 5e (Multiclass + Sorcerer/Warlock mechanics)
7. Pathfinder 1e (Prestige classes + Archetype restrictions)
8. Disgaea (Evilities system)
9. Final Fantasy X (Sphere Grid topology)

**Web 来源**：12 条主线查询 + 交叉验证。

**边界**：未详尽扫 Path of Exile 被动树技术细节；未扫 Into the Breach/XCOM 2 的天赋树。

---

## Findings

### Q1：元素/sub-class/职业互斥设计的 genre 先例

#### 案例 A：Final Fantasy Tactics - Job 系统（二元素专精 + 跨职技能池）

- **机制**：Character 只能同时拥有 1 个 Main Job + 1 个 Sub Job。装备 Sub Job 的技能需满足该 Job 已学 JP 解锁条件。
- **互斥形式**：非一对一互斥，而是 slot-based。
- **先例模式**：允许多 Job 学习，但同时只能激活 2 个，不锁定未来切换。
- **来源**：[Final Fantasy Tactics jobs | Final Fantasy Wiki](https://finalfantasy.fandom.com/wiki/Final_Fantasy_Tactics_jobs)；[Job system abilities | Final Fantasy Wiki](https://finalfantasy.fandom.com/wiki/Final_Fantasy_Tactics_abilities)

#### 案例 B：Fire Emblem: Three Houses - Class Promotion Tree

- **机制**：多层级晋升树（Beginner → Intermediate → Advanced → Master）。
- **互斥形式**：晋升**可逆**（Seal 重新参加考试）；Mastery 永久解锁后技能可跨 class 携带。
- **与 SoT 区别**：FE3H 强调灵活性 vs SoT 的不可逆性 per-run。
- **来源**：[Classes - Fire Emblem: Three Houses](https://www.fe3h.com/classes)；[Fire Emblem Three Houses Class Guide | RPG Site](https://www.rpgsite.net/feature/8752-fire-emblem-three-houses-class-guide-best-classes-class-change-certification-requirements-skills-abilities-and-class-mastery)

#### 案例 C：Baldur's Gate 3 - Subclass Selection（无互斥）

- **机制**：每个 Class 选 1 个 Subclass，Subclass 之间无互斥。Multiclass 允许 4+ classes 同时持有。
- **互斥形式**：0 个互斥，允许 Sorcerer + Warlock 同时融合。
- **启示**：现代 CRPG 倾向解除互斥，改为 resource-gating（法术槽消耗）而非路径锁定。
- **来源**：[Subclasses | Baldurs Gate 3 Wiki](https://baldursgate3.wiki.fextralife.com/Subclasses)；[Multiclass in BG3](https://www.siliconera.com/how-to-multiclass-in-baldur-gates-3/)

#### 案例 D：Octopath Traveler - Sub-job 互斥演变

- **版本 1 机制**：每个 sub-job 全局仅一个玩家可装备。
- **版本 2 (续作)**：移除互斥，多个 unit 可共享相同 sub-job。
- **启示**：设计者在第一部中采用互斥来 enforce 差异化，但在续作因玩家反馈解除（推测为新手困惑 / 多周目重复感）。
- **来源**：[Jobs | Octopath Traveler Wiki](https://octopathtraveler.fandom.com/wiki/Jobs)；[Octopath Traveler Job System Explained | Fandom](https://www.fandom.com/articles/octopath-traveler-job-system-explained)

#### 案例 E：Bravely Default II - 双 Job 系统（slot-based）

- **机制**：Main Job + Sub Job 各占一个 slot，Sub Job 的 Specialities 需特定 Ability 解锁。
- **互斥形式**：通过 Active/Inactive slot 状态而非永久互斥来管理多路径。
- **来源**：[Bravely Default 2 Jobs Guide | The Gamer](https://www.thegamer.com/bravely-default-2-jobs-sub-jobs-guide/)；[Bravely Default II Jobs | Fandom](https://bravelydefault.fandom.com/wiki/Bravely_Default_II_Jobs)

#### 案例 F：D&D 5e (无硬互斥, Spell Slot 资源竞争)

- **机制**：Sorcerer 与 Warlock Multiclass 无学派互斥。
- **互斥形式**：通过 action economy & Sorcery Point / Spell Slot 消耗引入成本。
- **来源**：[Warlock Multiclassing Guide: D&D 5e | Flutes Loot](https://www.flutesloot.com/warlock-multiclass-guide-dnd-5e/)；[Multiclassing - 5th Edition SRD](https://5thsrd.org/rules/multiclassing/)

#### 案例 G：Pathfinder 1e - Archetype 相容性

- **机制**：Monk 的不同 Archetype 部分不相容。
- **互斥形式**：基于特性冲突而非学派或绝对禁止。
- **来源**：[PF1 Monk Archetypes Guide | rpgbot](https://rpgbot.net/pathfinder/characters/classes/monk/archetypes/)；[Monk Archetype Combinations | Paizo Forums](https://paizo.com/threads/rzs2mn6v)

#### 案例 H：Disgaea 系列 - Evilities (无硬互斥)

- **机制**：Unique + Common Evilities，受 Slot Cost 限制。
- **互斥形式**：0 个硬互斥；所有限制来自 Slot 容量 & 数值成本。
- **来源**：[Evility | Disgaea Wiki](https://disgaea.fandom.com/wiki/Evility)；[Disgaea 5 Evilities | Fandom](https://www.fandom.com/wiki/List_of_Disgaea_5_Evilities)

---

### Q2：Trapezoid (3-2-many) 拓扑的天赋树先例

**关键发现**：Web search 与 canon 中**未找到明确的 3-entry → 2-middle → large-pool 拓扑先例**。

#### 近似案例 A：FFX Sphere Grid（多路径格子）

- 多条平行路径，中途交汇（非 3-2 模式）
- Key Sphere Gates 作为通过关卡，但每个节点都可达（一旦解锁）
- 无元素互斥；无 advancement layer
- **启示**：FFX 设计中**避免硬 chokepoint** — 任何路径都不是唯一关键通过点。
- **来源**：[Sphere Grid | Final Fantasy Wiki](https://finalfantasy.fandom.com/wiki/Sphere_Grid)；[FFX Sphere Grid Guide | EIP Gaming](https://eip.gg/ffx-x2/guides/sphere-grid/)

#### 近似案例 B：Fire Emblem: Three Houses 分支树

- 多个初始 class → 分散的 Intermediate（无强制汇聚） → Advanced（部分收敛）
- **与 trapezoid 区别**：底层宽，中层不必经历，顶层收敛程度低。

#### 搜索弱点

- Path of Exile 被动树文献中**未提及 hub 避免的设计约束**
- "Talent tree topology 3-2-many" 未成为标准模式术语
- 大多数设计遵循 1→3→N 或 N→N，而非 3→2 夹点

---

### Q3：互斥 origin choice 的玩家流失问题 & 新手困惑

#### 案例 A：Fire Emblem Casual Mode (permadeath toggle as retention fix)

- **问题**：FE 原本的 permadeath 导致新玩家重复重置；FE: Awakening 销量危机（目标 250k 销量，系列生存线）。
- **解决方案**：Casual Mode 导入。
- **结果**：销量从危机转向成功；数十万新玩家因选项而 onboard。
- **启示**：一次性不可逆选择需配套 respec 或 retry 机制。
- **来源**：[Casual Mode | Fire Emblem Wiki](https://fireemblem.fandom.com/wiki/Casual_Mode)；[FE: Awakening & Series Survival | Medium](https://untimelygamer.medium.com/fire-emblem-three-houses-still-doesnt-know-how-to-handle-death-175a95138ec7)

#### 案例 B：Octopath Traveler sub-job 互斥→开放演变

- **第一部问题**：新手不知道后期 sub-job 分配战略，前期选择影响全队；二周目重复感。
- **续作**：明确移除全局互斥。
- **启示**：互斥被设计者在续作显式修正。
- **来源**：[Jobs | Octopath Traveler II Wiki](https://octopathtraveler.fandom.com/wiki/Jobs_(Octopath_Traveler_II))；[Octopath Job Combinations | RPG Site](https://www.rpgsite.net/feature/7478-octopath-traveler-job-combinations-how-to-make-the-best-subclass-choice)

#### 案例 C：Roguelite Respec 标准 mitigation

- Windrose / Talented / Striving for Light 都允许中途 respec
- **设计目的**：避免早期选择锁定后期乐趣
- **来源**：[Windrose Wiki | Respec](https://thegameswiki.com/windrose/wiki/respec)；[Talented on Steam](https://store.steampowered.com/app/2435090/Talented/)

#### 案例 D：Slay the Spire run-local 不可逆 & 玩家适应

- **机制**：每次卡池选择不可逆，但前期提供充足试错。
- **成功原因**：信息充足 + 失败即 run end + 多周目自然 reset。
- **启示**：不可逆需配 (1) 信息透明 (2) 低损失 (3) 多周目鼓励。
- **来源**：[Slay the Spire Strategy Guide](https://www.slaythespire.gg/guides/strategy)；[StS 2 Systems Lab | Breach.gg](https://breach.gg/blog/slay-the-spire-2-weekly-2026-03-13)

---

### Q4：解互斥能力 (Grand Sage 模式) 的设计先例 & 通才 vs 专精

#### 案例 A：Mystic Theurge - 双系通才 (D&D Prestige Class)

- **机制**：Cleric 3 / Wizard 3 → Prestige Class，10 级双施。
- **通才劣势**：Caster Level 被分割，Spell DC 偏低，early-mid game "很痛"
- **结论**：通才不是 dominant；专精法师在战斗 DPS 上仍更强
- **来源**：[Mystic Theurge | d20PFSRD](https://www.d20pfsrd.com/classes/prestige-classes/core-rulebook/mystic-theurge/)；[Mystic Theurge Guide | rpgbot](https://rpgbot.net/pathfinder/characters/prestigeclasses/mystic_theurge/)

#### 案例 B：FFT 跨职技能池 (不对等权衡)

- **机制**：Main Job A / Sub Job B 时，可用 A 的 action command + B 的任意已学 ability。
- **权衡**：Sub Job ability 需已通过 JP 投入解锁，但**装备限制、能力池固定**。
- **启示**：装备/能力 slot 限制强制权衡，避免通才绝对优势。

#### 案例 C：BG3 Wizard 跨学派法术 (弱互斥)

- **机制**：Wizard 选学派获得学派特性，但**可学任何学派的法术**。
- **权衡**：学派特性仅对该学派的法术生效，奖励专攻。
- **来源**：[BG3 Classes | bg3.wiki](https://bg3.wiki/wiki/Classes)

---

### Q5：Post-advancement "Single-element 节点不能作 hub"

#### 案例 A：FFX Sphere Grid 避免唯一关键通路

- **约束**：每个"锁定"节点周围设计有多个替代路径
- **实现方式**：格子网络 + 多向连接（最多 7 方向）
- **启示**：通过网格密度 enforce 没有 chokepoint 的约束。

#### 案例 B：BG3 / FFT 的 ability pool 设计 (hub 分散)

- **观察**：两者都避免单点技能成为必须。
- **约束实现**：通过充足的替代品库，让单个节点不成关键。

#### 案例 C：Path of Exile 被动树（未找到公开 hub-avoidance 约束证据）

- PoE 可能不强制此约束，通过试错 & 平衡补丁 enforce。

#### 工程启示总结

1. **约束实现方式**：拓扑级（FFX 格子）/ 内容级（冗余性）/ 数据级（不保证）
2. **SoT trapezoid 实现**：JSON adjacency 设计时显式检查（BFS 验证任意单点移除后的连通性）

---

## Edge Cases / Known Failures

1. **Octopath Traveler v1 → v2 的互斥反向（设计失效警告）**
   - 第一部全局 sub-job 互斥 → 续作明确移除
   - 证据强度：中等（设计迭代证实，但无量化留存率数据）

2. **BG3 的"无互斥"极端（对 SoT 的反向）**
   - Sorcerer/Warlock Sorlock 是流行强构筑
   - 若 Grand Sage 路线无额外成本，可能成为 dominant strategy

3. **FFX Sphere Grid 的 key sphere 边界情况**
   - 若 Key Sphere 被 miss，可能产生意外锁定

---

## Uncited / Weak Evidence

1. Trapezoid (3→2→pool) 标准术语的 GDC 演讲 / 博客 — 搜索未返回明确文档
2. Path of Exile 的 hub deadlock-free guarantee — 未找到 GGG 官方文档
3. Mystic Theurge dominant strategy 量化数据 — 基于玩家讨论而非官方平衡报告
4. Roguelite respec 对新手留存的量化影响 — 无 A/B 测试

---

## Handoff to Game-Analyst

**开放问题（4-axis 评估）**：

1. **Q-A1**: Grand Sage 通才 vs Element Sage 专精的成本权衡是否够深？候选权衡维度：法术槽容量、cool-down、融合技能的额外成本（需双元素节点）

2. **Q-A2**: 互斥 origin choice 的新手 onboarding 流程
   - SoT 中玩家在第一次面对 Fire/Ice/Air 选择时是否能看到完整 endgame tree？
   - 是否考虑 NG+ 鼓励？

3. **Q-A3**: 单元素节点成为 chokepoint 的风险模型
   - 多少替代路径出边来避免锁定？
   - 建议：对 JSON 图做 BFS 连通性检查

4. **Q-A4**: Run-local 互斥 vs Meta-level unlock 的交互
   - "meta 永久解锁更多树区"是否足以补偿"单 run 中不可逆互斥"的损失？

---

## Handoff to Game-Critic

**初步可疑点（寻找 fail mode 证据）**：

1. **互斥机制导致的新手流失风险（Octopath v1 前科）**
   - 假说：若无 endgame info / respec / NG+ 鼓励，新玩家会因"早期盲选后期悔恨"而不玩二周目
   - 检验方向：Steam review 评论是否提及"被锁定后悔"；玩家测试中的元素选择分布

2. **Grand Sage 通才成为 dominant strategy（BG3 Sorlock 前科）**
   - 假说：若 Grand Sage 在 damage/utility 上无明显劣势，高端玩家会全部走 Grand Sage
   - 检验方向：speedrun / high-level 构筑对比；不同 run 中的选择比例

3. **Single-element hub chokepoint 的潜在设计缺陷**
   - 假说：拓扑上没有单元素成为唯一通路，但功能上某个元素的"必需技能"可能被隐藏在一个单节点中
   - 检验方向：遍历 JSON 逐元素统计核心技能的重复度

4. **Trapezoid 夹点 (advancement layer) 的过度 gating 风险**
   - 假说：如果 Grand Sage / Element Sage 的 unlock 条件过严苛，可能导致大量 player 无法触达
   - 检验方向：平均多少关卡/投资点数 player 才触发 advancement 选择？

---

## 来源（按 appearance 顺序）

- [FFT jobs | Final Fantasy Wiki](https://finalfantasy.fandom.com/wiki/Final_Fantasy_Tactics_jobs)
- [FFT abilities | Final Fantasy Wiki](https://finalfantasy.fandom.com/wiki/Final_Fantasy_Tactics_abilities)
- [Classes - Fire Emblem: Three Houses](https://www.fe3h.com/classes)
- [FE3H Class Guide | RPG Site](https://www.rpgsite.net/feature/8752-fire-emblem-three-houses-class-guide-best-classes-class-change-certification-requirements-skills-abilities-and-class-mastery)
- [Subclasses | BG3 Wiki](https://baldursgate3.wiki.fextralife.com/Subclasses)
- [Multiclass in BG3 | Siliconera](https://www.siliconera.com/how-to-multiclass-in-baldur-gates-3/)
- [Jobs | Octopath Traveler Wiki](https://octopathtraveler.fandom.com/wiki/Jobs)
- [Octopath Job System Explained | Fandom](https://www.fandom.com/articles/octopath-traveler-job-system-explained)
- [Jobs | Octopath Traveler II](https://octopathtraveler.fandom.com/wiki/Jobs_(Octopath_Traveler_II))
- [Octopath Job Combinations | RPG Site](https://www.rpgsite.net/feature/7478-octopath-traveler-job-combinations-how-to-make-the-best-subclass-choice)
- [Bravely Default 2 Jobs | The Gamer](https://www.thegamer.com/bravely-default-2-jobs-sub-jobs-guide/)
- [BD2 Jobs | Fandom](https://bravelydefault.fandom.com/wiki/Bravely_Default_II_Jobs)
- [D&D 5e Warlock Multiclass | Flutes Loot](https://www.flutesloot.com/warlock-multiclass-guide-dnd-5e/)
- [5e SRD Multiclassing](https://5thsrd.org/rules/multiclassing/)
- [Sphere Grid | Final Fantasy Wiki](https://finalfantasy.fandom.com/wiki/Sphere_Grid)
- [FFX Sphere Grid Guide | EIP Gaming](https://eip.gg/ffx-x2/guides/sphere-grid/)
- [Sphere Grid | Shapes.inc](https://shapes.inc/fandom/final-fantasy-x/sphere-grid)
- [Casual Mode | Fire Emblem Wiki](https://fireemblem.fandom.com/wiki/Casual_Mode)
- [FE3H Death Handling | Medium](https://untimelygamer.medium.com/fire-emblem-three-houses-still-doesnt-know-how-to-handle-death-175a95138ec7)
- [Windrose Wiki | Respec](https://thegameswiki.com/windrose/wiki/respec)
- [Talented on Steam](https://store.steampowered.com/app/2435090/Talented/)
- [StS Strategy Guide](https://www.slaythespire.gg/guides/strategy)
- [StS 2 Systems Lab | Breach.gg](https://breach.gg/blog/slay-the-spire-2-weekly-2026-03-13)
- [Mystic Theurge | d20PFSRD](https://www.d20pfsrd.com/classes/prestige-classes/core-rulebook/mystic-theurge/)
- [Mystic Theurge Guide | rpgbot](https://rpgbot.net/pathfinder/characters/prestigeclasses/mystic_theurge/)
- [BG3 Classes | bg3.wiki](https://bg3.wiki/wiki/Classes)
- [Evility | Disgaea Wiki](https://disgaea.fandom.com/wiki/Evility)
- [Disgaea 5 Evilities | Fandom](https://disgaea.fandom.com/wiki/List_of_Disgaea_5_Evilities)
- [PF1 Monk Archetypes | rpgbot](https://rpgbot.net/pathfinder/characters/classes/monk/archetypes/)
- [Monk Archetype Combinations | Paizo Forums](https://paizo.com/threads/rzs2mn6v)
- [PoE Passive Tree | PoE Official](https://www.pathofexile.com/passive-skill-tree)
- [PoE2DB Passive Tree](https://poe2db.tw/us/)
- [Skill Trees | Accession](https://accession.polynomial.co.uk/article/skill-trees)
- [Skill Trees | gamedesigning.org](https://gamedesigning.org/learn/skill-trees/)
- [Skill Trees in TTRPGs | ttrpg-games.com](https://www.ttrpg-games.com/blog/skill-trees-in-ttrpgs-basics-and-design/)
- [Best Skill Tree Designs | The Gamer](https://www.thegamer.com/best-skill-tree-designs-in-video-games/)
