---
checkpoint: B3
session: S67
date: 2026-04-23
researcher: game-researcher (Mercury subagent)
status: RAW_DATA_COMPLETE
supersedes_partial: B1.2, B2.1（的 Hades/MT/STS 类比部分）
---

# B3 调研结果：严格定义下的"天赋树 × roguelite"样本

## 严格定义（S67 强制）

**"天赋树" (strict definition)** 必须同时满足：
1. **节点图 (node graph)** —— 不是单点升级列表
2. **分支依赖 (branch prerequisites)** —— 解锁节点 A 需要前置节点 B/C
3. **build 路线分化 (build divergence)** —— 走 A 分支 vs B 分支产出完全不同的玩法（不是通用加成堆叠）

**永久 (permanent)** = meta 层（跨 run 保留），非 run-internal random pickup。

## Ban List（S66 错误类比，禁止作为"小天赋树参考系"）

| 对象 | 实际类型 | 为何不符合 |
|------|----------|------------|
| Hades 1/2 Mirror of Night | meta-buff 池 | 通用加强所有玩法，不分化 |
| Hades 1/2 Boons | run 内随机 pickup | run 重置，非 meta |
| Hades 2 Arcana Cards | meta buff 池（选择性启用） | 非节点图 |
| Monster Train Champion Spec | deckbuilder champion 卡牌路线 | 非节点图天赋树 |
| Slay the Spire Relics/Cards | deckbuilder 机制 | 无节点图 |
| Balatro Jokers | item collection | 无节点图 |
| Dead Cells mutation/scroll | run 内选项 | 非 meta 节点图 |

## T1 候选逐个 Verdict

### ✅ PASS (严格定义达标)

| 游戏 | 架构 | Meta 层 |
|------|------|---------|
| **Talented** (Steam 2435090) | infinite randomized talent tree + roguelite (20 夜存活) | 6 职业解锁 + talent 库解锁 |

**关键注意**：Talented 的天赋树是 **run-generated random tree**（每 run 重新生成），不是"固定永久树"。meta 层只保留"新 talent 进入下次 run 的池"和"职业解锁"。**与 SoT 设想的"固定永久职业节点图"架构并不完全对齐**。

严格来说，"固定永久节点图天赋树 × roguelite"的样本数 = **0**。

- 来源：
  - https://store.steampowered.com/app/2435090/Talented/
  - https://www.youtube.com/watch?v=PK9Dk-jABqo

### ⚠️ EDGE (接近但未验证)

| 游戏 | 状态 | 未决点 |
|------|------|--------|
| **Sol Cesto** | Teeth 系统（概率修改器），非节点图 | Teeth 架构可视为"路径树"边缘情况？否 |
| **Wildermyth: Omenroad DLC** | 2024 新增 roguelite 模式 | DLC 天赋树是否节点图未验证 |

Wildermyth Omenroad 是**唯一未完全排除**的候选，需玩家验证或官方文档细节。搜索未找到确证。

### ❌ FAIL (不符合严格定义)

| 游戏 | FAIL 原因 |
|------|-----------|
| Rogue Legacy 2 | Manor 是 list menu，无节点图 |
| Othercide | Memories 是 run 内 skill mod，非 meta 节点图 |
| Hadean Tactics | deckbuilder autobattler |
| Children of Morta | run 内升级 + Shrine 建筑升级 |
| Loop Hero | Traits/Talents 是 buff 列表 + Camp 建筑升级 |
| Inscryption / Griftlands / Cultist Simulator | deckbuilder |
| ROGUERIA: Roguelikes X Tactics | skill 学习系统，非节点图；开发停滞 |
| Battle Brothers | 非 roguelite（战术 RPG campaign） |
| Chronicon | 非 roguelite（传统 ARPG） |

## T2 行业空白证据

- **Reddit**: `site:reddit.com/r/roguelikes "talent tree" "tactical" permanent` → 0 匹配
- **Steam 交集 tag** (`tactical roguelite`): Sol Cesto, ROGUERIA, Rogue Tactics, A Bit of Tactics, Tic Tactic... 其中**无一个同时具备"节点图天赋树 + roguelite 循环"**
- **GDC / Gamasutra**: "meta-progression" 讨论普遍指 Hades Mirror/Boons / StS unlock / Rogue Legacy Manor，**无人讨论"permanent node-graph talent tree × tactical roguelite"**

## T3 替代路径样本（如 SoT 走 ARPG 式永久 + 战棋 run）

| 样本 | 架构 | 适配度 |
|------|------|--------|
| **Striving for Light** | ARPG buildcrafting + infinite skill tree + roguelite | 非战棋（射击+自动战斗） |
| **Rogue Command** | RTS + roguelite + meta talent tree | 非战棋（RTS） |
| **Battle Brothers** | 永久 Perks/Talents + 战棋 | 非 roguelite（campaign 固定） |
| **Chronicon / Grim Dawn / PoE / Last Epoch** | ARPG 天赋树典范 | 非 roguelite |

**组合 "战棋 + 永久节点图天赋树 + run 循环" 样本 = 0**。

## 核心结论汇总

| 组合 | 样本数 | 代表 |
|------|--------|------|
| **严格定义固定永久节点图天赋树 × roguelite** | **0** | — |
| Talented 式 run-generated tree × roguelite | 1 | Talented |
| Tactical roguelite (无永久天赋树) | 5+ | Sol Cesto, ROGUERIA, Rogue Tactics |
| ARPG 天赋树 (非 roguelite) | 10+ | Chronicon, Grim Dawn, PoE, Last Epoch |
| Roguelite + meta-buff 列表 (非节点图) | 20+ | Hades, Rogue Legacy 2, Loop Hero |
| Permanent talent tree × Tactics (非 roguelite) | 1-2 | Battle Brothers |

**硬事实**：SoT 设想的"战棋 + 多职业 + 固定永久节点图天赋树 + roguelite + 4p co-op"组合在 Steam 行业**真实参考系 = 0**。

## 解释该空白的反向理由（推测，需 analyst/critic 验证）

1. **工程成本**：每职业 30-40 节点 × 8 职业 = 240-320 永久节点；每节点需数值 + UI + 平衡测试
2. **设计成本**：固定永久树 vs run-random tree，前者需 solo dev 级穷尽分支平衡；用户剑士 7 JSON 版本已量化压力
3. **玩家留存**：战棋 roguelite 长尾弱（Sunderfolk 一年 CCU 90% 衰减），永久天赋树投入需匹配留存曲线
4. **市场验证**：deckbuilder roguelite 已证赚钱，节点图 roguelite 无先例 → 发行商/开发者规避风险

## Handoff（给 game-analyst R2-v2）

**开放问题**：
1. Talented 的"infinite run-generated tree"是否可作为 SoT 的**架构参考**（即 SoT 改用 run-generated tree 而非固定永久树）？
2. 在真样本 = 0 的情况下，Tier 2 (30-40 节点 × 8 职业) 是 CAUTION 还是 STOP？
3. 替代路径"ARPG 式永久节点图 + 战棋 run + 轻量 Relic"样本也 = 0，但风险是否低于 Tier 2？
4. Wildermyth Omenroad 是否值得 SoT 团队 100-200 USD 购入 + 实测验证作为参考系？

**对抗性视角（给 game-critic R3-v2）**：
1. Talented 的 meta 层是否只有皮肤/挑战 unlock 而无 gameplay 影响？（决定它是真 roguelite 还是 cosmetic roguelite）
2. 战术 roguelite 几乎没人做永久天赋树，是因为工程/设计/留存/市场中的**哪一条**？
3. SoT 走"行业空白"究竟是**先行者优势**还是**所有人绕开的雷**？

## Sources (B3 引用)

- [Talented on Steam](https://store.steampowered.com/app/2435090/Talented/)
- [Talented by TurtleFox Games - Itch.io](https://turtlefoxgames.itch.io/talented)
- [They Turned Infinite Talent Trees Into A Roguelite! - YouTube](https://www.youtube.com/watch?v=PK9Dk-jABqo)
- [Sol Cesto Skill Tree Guide](https://www.sol-cesto.wiki/guide/sol-cesto-skill-tree)
- [Sol Cesto Wiki](https://www.sol-cesto.wiki/)
- [TheGG: Sol Cesto v1.0](https://thegg.net/press-releases/the-tactical-roguelite-sol-cesto-has-just-reached-v1-0-via-steam/)
- [Rogue Legacy 2 Wiki: Upgrades](https://rogue-legacy-2.fandom.com/wiki/Upgrades)
- [Wildermyth Omenroad - YouTube](https://www.youtube.com/watch?v=fFdAt8DhfNA)
- [Wildermyth Wiki: Ability](https://wildermyth.com/wiki/Ability)
- [Othercide Wiki: Memories](https://othercide.fandom.com/wiki/Memories_(mechanic))
- [Hadean Tactics on Steam](https://store.steampowered.com/app/1260590/Hadean_Tactics/)
- [Children of Morta Wiki: Skill List](https://childrenofmorta.fandom.com/wiki/Skill_List)
- [Loop Hero Talents Guide](https://steamcommunity.com/sharedfiles/filedetails/?id=3451333701)
- [ROGUERIA on Steam](https://store.steampowered.com/app/1408590/ROGUERIA_Roguelikes_X_Tactics/)
- [Battle Brothers Wiki: Talents](https://battlebrothers.fandom.com/wiki/Talents)
- [Chronicon Wiki: Classes](https://chronicon.fandom.com/wiki/Classes)
- [Striving for Light on Steam](https://store.steampowered.com/app/1646790/Striving_for_Light/)
- [Rogue Command - YouTube](https://www.youtube.com/watch?v=uw4iCmqS23E)
- [Progression Systems in Roguelite Games - Theseus.fi Thesis](https://www.theseus.fi/bitstream/10024/881994/2/Kammonen_Eino.pdf)

## 未验证 / Weak Evidence

- Wildermyth Omenroad 天赋树架构细节（仅 YouTube 视频提及）
- Reddit 讨论 0 结果可能是搜索索引问题而非真空白（低概率）
- GDC 2024+ post-mortem（搜索覆盖率有限）
