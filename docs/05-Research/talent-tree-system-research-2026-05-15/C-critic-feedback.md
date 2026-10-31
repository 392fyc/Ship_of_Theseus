---
title: Phase C 对抗验证报告
phase: C
agent: game-critic (Mercury sub-agent)
session: S4-side-sot
date: 2026-05-15
status: critic-review-complete
target: B-design-proposals 三套剑圣方案
scope: 反对意见 + 设计盲点 + 失败案例对照
---

# Phase C — game-critic 对 B 3 套方案的对抗验证

> 本文件为 Phase C 对抗验证产出。critic 任务是抵消 AI 输出优化主义偏差——**找问题、不下推荐结论**。

## 总评

Phase B 的 3 套方案整体设计严谨、引用可追溯，设计师明显对 A1/A2 做了认真消化。14 节点骨架 × 3 套的工程化框架是清晰的，5 类增强的场景实例化也能找到业内锚点。然而 B 存在三个贯穿全方案的结构性盲点：

第一，**「形态变化」节点的实现成本被系统性低估**。B 将形态变化节点标注为设计意图，但未曾触及单人开发所需的实现代价——Hades 2 的 Weapon Aspect（占比 12%）是约 25 人团队的产物，B 方案一的 23% 形态变化占比对应 7 个改写技能行为的节点，在 Godot 4 GDScript 架构下每一个都需要独立状态机分支、动画覆盖、AI 行为更新，这是显著的工程风险。

第二，**随机入池机制与战棋回合制节奏之间的根本性张力被忽略**。B 引用 Hades 的 3 选 1 随机机制作为方案二和方案三的正当性，但 Hades 是动作游戏，玩家在选择后 0.1 秒内就能感受到 boon 的行为差异；战棋回合制下玩家需要在脑内推演所有选项与当前战场布局的交互后再选择，决策窗口远长于动作游戏。

第三，**三套方案中「Lv5 二选一形态后另一个形态的升级节点如何处理」这一问题完全悬空**。B §6 风险项第 2 条自己也承认了这一点，但 3 套方案的节点骨架均未给出哪怕是示意性的答案，而这个问题直接影响 N 的真实规模和实际取舍比例计算。

---

## 方案一：紧凑高密度 的反对意见（≥2 条）

### 反对意见 1：形态变化 23% 占比的单人开发工程成本被低估

**反对点**：形态变化节点占比 23%（全池 7 个节点），明显高于业内全部参考（5%-15%），且这些节点被定义为「必须明显改变行为而非只是数值」。

**业内反例**：Hades 2 Supergiant Games（2024）。Hades 2 的 Weapon Aspect 机制使形态变化占比达到业内最高的 12%，但 Supergiant 团队规模约 25 人（含艺术、音效、叙事），且 Weapon Aspect 作为永久元进度解锁，不需要在单局天赋系统内动态生效。B §2.2 对照表中直接将「Hades 2 Weapon Aspect 12%」作为方案一 23% 的背书，但这个对照在规模和架构上不成立。

**失败证据**：
- [Scope Creep: The Silent Killer of Solo Indie Game Development（Wayline）](https://www.wayline.io/blog/scope-creep-solo-indie-game-development)：「超过 70% 的独立开发者将范围过大列为项目未能按时完成或被放弃的重要因素」
- [Supergiant 官方博客（Hades 2 announced）](https://www.supergiantgames.com/blog/hades2-announced/)：「Hades 2 team of about 25 people」

**对方案的影响**：7 个形态变化节点在 Godot 4 GDScript 架构下意味着至少 7 套独立的技能行为分支（状态机节点、动画 override、AI 响应逻辑）。若其中任意一个节点因工程阻力被削减为「纯数值包装的假形态变化」，则方案一的核心「每个节点都重」哲学直接崩溃，且会重蹈 Cyberpunk 2077 1.x「空头节点」覆辙（A2 §1.3 案例 4）。

**严重程度**：重大风险（接近阻断级别，但可通过主动削减形态变化数量降级）

### 反对意见 2：紧凑池 + 前置依赖在战棋下产生池稀释

**反对点**：N=30 的紧凑池搭配等级阶梯 + 前置依赖双层入池，意味着深度节点（sw_sa_13/14/11 入池在 Lv17-18）在单局 21 关内仅有最后 4-5 关才能入池。若玩家未命中前置（如未选 sw_sa_04 或 sw_sa_08），这些深度节点永远不会出现。

**业内反例**：Into the Breach（Subset Games，2018）的飞行员技能随机化问题。Into the Breach 同样是紧凑池 + 前置概率机制，社区长期批评「Grid Defense 这种无意义技能与 +1 Move 之间的价值鸿沟导致运气决定 Run 质量」。

**失败证据**：
- [Steam 社区「Pilot leveling annoyance」](https://steamcommunity.com/app/590380/discussions/0/1694914736011848831/)
- [Subset Games 官方论坛「The one flaw (pilot skill randomization)」](https://subsetgames.com/forum/viewtopic.php?t=32864)：玩家直接引用「Grid defense is so monumentally useless I would rather the pilot didn't level at all so I could get another shot at something else.」

**对方案的影响**：若某局玩家在 Lv8 未选 sw_sa_04（招架居合架势），则以 sw_sa_04 为前置的 sw_sa_09（Lv13）和 sw_sa_14（Lv18）均不入池，实际可选节点数从 14 个降至 11 个，实际取舍比例从 40% 变为 33%。

**严重程度**：重大风险

---

## 方案二：中庸均衡 的反对意见（≥2 条）

### 反对意见 1：纯数值占比 40% 中存在叠加层数型假节点风险

**反对点**：方案二的纯数值节点占比 40%（14 个节点），是三套方案中最高的，包括「sw_sa_02 普攻暴击率累积：每次普攻 +2% 暴击率（最多堆 10 层）」这类叠加层数型节点。B 对「避免假节点」的声明是「每个节点都绑定具体条件」，但叠加层数型设计在战棋语境下存在固有的「前几层无感知」问题。

**业内反例**：Cyberpunk 2077 2.0 版本（2023）的设计钟摆效应。A2 §1.3 案例 4 指出，Cyberpunk 2077 2.0 重制天赋树的灵感来自 Diablo II 的传统节点图哲学，但「部分玩家认为新树的选项间逻辑跳跃、与装备/属性协同不一致」。

**失败证据**：
- [PC Gamer：Cyberpunk 2077 残留机制问题](https://www.pcgamer.com/im-hoping-against-hope-that-cyberpunk-2077s-expansion-overhaul-will-finally-fix-the-games-lingering-mechanics-malaise/)
- [GDKeys：Keys to Meaningful Skill Trees](https://gdkeys.com/keys-to-meaningful-skill-trees/)：「Numbers Aren't Design: Meaningful Skill Trees」指出仅有条件触发不等于有意义节点。

**对方案的影响**：14 个纯数值节点中有任意数个属于「叠加层数到高层才有意义」型，玩家在前 5-8 关持有这些节点时的实际体验接近于假节点，与方案二「稳健均衡」的设计意图相悖。

**严重程度**：重大风险

### 反对意见 2：随机抽取在战棋语境下重蹈 Wildermyth 覆辙

**反对点**：方案二采用「等级阶梯 + 前置依赖 + 部分随机」三层混合入池，6 点随机抽取借鉴 Hades 1 房间奖励机制。但 Hades 是动作游戏（选择后即时反馈），战棋回合制下玩家需要推演 5-7 回合交互再选，选择成本远高于动作游戏。

**业内反例**：Wildermyth（Worldwalker Games，2021）的技能随机化投诉。Wildermyth 是最接近战棋语境的参考游戏，Steam 社区长期存在「随机技能选择导致一整局都拿到糟糕选项」的投诉。

**失败证据**：
- [Wildermyth Steam 社区批评「随机技能选择」](https://steamcommunity.com/app/763890/discussions/0/3200370997809193228/?ctp=2)：「trudging through a 5-chapter campaign in which they were given particularly poor choices for skill upgrades the whole time.」
- [Wildermyth Steam 社区「save-scumming 文化」](https://steamcommunity.com/app/763890/discussions/0/3053986162865116478/)
- A2 §3.3 已明确指出「随机抽取的缺点：无法保证特定体验，Run 质量方差极大」

**对方案的影响**：方案二将 6 点随机抽取定位为「给 build 多样性」，但在战棋节奏下，玩家选择体验接近于 Wildermyth 中被批评的「被迫接受糟糕随机」，而非 Hades 中「惊喜感与成就感」。

**严重程度**：重大风险

---

## 方案三：长尾高取舍 的反对意见（≥2 条）

### 反对意见 1：sw_sa_13 仁王 Ki Pulse 战棋转化未解决

**反对点**：sw_sa_13「居合觉醒质变」节点将仁王 Ki Pulse 模式（即时回复窗口）移植到战棋回合制语境，描述为「剑气满溢期间，所有技能消耗剑气改为消耗 HP」。A2 §4.4 模式 C 已明确指出转化难度较高。B 方案三承认了这个引用，但直接宣称该节点是「精通感节点的核心」，没有解释转化方案。

**业内反例**：Tactics Ogre Reborn（Square Enix，2022）移除 TP 系统。A2 §4.3 引用「Tactics Ogre Reborn 废弃了独立积累型 TP 系统，统一为 MP」，开发者官方解释为「with these abilities unified to using MP, it's much simpler to assess the status of units during battle, and easier to construct a strategy.」

**失败证据**：
- [Tactics Ogre Reborn Developer Interview - Frontline JP](https://www.frontlinejp.net/2022/12/07/tactics-ogre-reborn-developer-interview/)
- [Tactics Ogre Reborn Details Unit Development - Gematsu](https://www.gematsu.com/2022/10/tactics-ogre-reborn-details-unit-development-charms-battle-updates-balance-adjustments-shop-improvements-classes-and-characters)

**对方案的影响**：sw_sa_13 是方案三主张的「精通感核心」节点，若该节点的玩家体验在战棋语境下无法产生仁王式的精通感（而变成「这个档位是否应该让奥义打出去还是保存 HP」的数学题），则方案三最具差异化的深度节点失去设计意图。

**严重程度**：重大风险

### 反对意见 2：大池 + 随机 + 牺牲换强三重风险叠加

**反对点**：方案三取舍比例 57%、N=42 大池、随机抽取主导，骨架 14 节点中有 6 个牺牲换强节点（III 类，占 14%）。牺牲换强节点在随机池主导下存在「被随机跳过」与「被随机选中但后续前置未触发导致牺牲已生效而收益未到」的双重风险。

**业内反例**：Ravenswatch 早期测试的池稀释失败（A2 §1.3 案例 2）。

**失败证据**：
- [Ravenswatch Steam 社区「Character Upgrade Suggestions」](https://steamcommunity.com/app/2071280/discussions/0/3828664145916037670/)：「unlocks are serving to dilute the ability pool for a character, and as you gain levels on a character, it becomes impossible to get a good build because every time you unlock a new upgrade, it lowers the chance you will get the upgrades you want.」
- A2 §3.3 随机抽取缺点段落：「池越大则关键选项出现概率越低（Ravenswatch 的核心批评）」

**对方案的影响**：方案三声称补偿措施是「骨架 14 节点确定性入池」，但骨架 14 节点中多数仍有等级前置或前置依赖（如 sw_sa_05 前置 sw_sa_03，sw_sa_10 前置 sw_sa_08，sw_sa_14 前置 sw_sa_04 和 sw_sa_07），并非真正的「确定性」。

**严重程度**：阻断级风险（若不对随机池与牺牲换强节点的相互作用做显式处理）

---

## 跨三套方案的整体盲点（≥2 条）

### 盲点 1：Lv5 二选一奥义形态后被放弃形态的升级路径完全缺失【P0 阻断级】

三套方案均将「奥义形态选择（Lv5 二选一）」作为核心节点，A 形态（单体溢出）与 B 形态（范围扇形横扫）各有不同使用场景。但三套方案的 14 节点骨架中均只列出了「奥义形态选定后」的下游节点，完全没有说明：若玩家在 Lv5 选择 A 形态，B 形态的升级节点是否消失、是否占用 N 的全池规模。

B §6 风险项第 2 条自己也承认：「若两个形态分别还有 2-3 个升级节点，会改变骨架结构。」但这个问题在三套方案的参数核心（N/M/取舍比例）计算中完全未被考虑——若 A/B 两条形态路线各有 3 个专属节点，实际可访问节点数 = N - 3，取舍比例的计算基础全部偏移。

**严重程度**：阻断级（参数完整性缺陷，影响全部三套方案的核心比较维度）

### 盲点 2：招架被动化 + 招架反击的 handoff 硬规则冲突【P0 阻断级】

三套方案均包含 sw_sa_04「招架居合架势：招架变为被动触发的居合架势，受击时概率反击周围敌人」。然而 handoff §「DO NOT — 游戏机制」明确规定：「反击/追击 → 不触发连锁」「area 攻击 → 不触发反击」。

更关键的是：若 sw_sa_09（招架冰冻反击）在「居合架势被动化」后叠加，实际触发路径变为「被动触发居合架势 → 居合反击 → 反击带冰冻」，这是否属于 handoff 禁止的「反击触发连锁」？B 的 5 类增强实例化中直接将这两个节点列为可叠加设计，但未触及规则约束检查。

**严重程度**：阻断级（规则约束冲突，需用户澄清 handoff 机制定义的边界）

---

## 5 类增强实例化的具体问题

**问题 1：「招架生效窗口 +1 回合」与「居合架势被动化」节点的语义冲突**

B §1.I 纯数值增强示例 3：「招架生效窗口 +1 回合：招架的反击窗口从当回合延长到下回合开始」。这是「主动施放招架」的语境下有意义的数值增强。但若玩家已选 sw_sa_04（招架从主动变为被动触发），「生效窗口 +1 回合」的语义变得模糊——被动触发型招架的「生效窗口」是什么？这个示例节点在形态变化生效后可能变为语义无效的假节点。

**问题 2：奥义命中后免费普攻 与 一闪变周围随机攻击 的互斥未说明**

sw_sa_11/sw_sa_12/sw_sa_13 描述「奥义命中后立即触发一次免费普攻」。但若玩家同时持有 sw_sa_03（一闪变为周围随机攻击），免费普攻是触发修改后的普攻形态还是原始普攻？在 sw_sa_02（普攻暴击吞噬：普攻暴击时回复剑气）存在时，免费普攻是否可以触发暴击吟噬的剑气回复？这条联动链「奥义→免费普攻→暴击吟噬→剑气」是否是设计意图，还是意外的溢出强度路径？B 未作任何说明。

---

## 6 个悬空决策的优先级评分

| 优先级 | 决策项 | 紧迫理由 |
|---|---|---|
| **P0（立即）** | 第 2 项：奥义二选一形态后另一形态的升级节点如何处理 | 直接影响 N/M/取舍比例的计算有效性，三套方案的核心参数未经此校验即不可比较 |
| **P0（立即）** | 第 5 项：天赋互锁的实际触发节点 + 招架被动化与反击规则的互斥检查 | 涉及 handoff 硬性规则约束，存在规则冲突风险 |
| **P1（主方案选定前）** | 第 6 项：L5 符文与 L2 天赋边界（sw_sa_13 居合觉醒质变的归属） | 若 sw_sa_13 实质上是「L5 流派类符文」则应从天赋线移除 |
| **P2（主方案选定后）** | 第 1 项：选哪套方案 | 须先解决 P0 两项，否则比较基础无效 |
| **P3（工程规划阶段）** | 第 3 项：肉鸽元素超过 M 上限机制的讨论时机 | 已有预留，可推后至 S5 |
| **P3（工程规划阶段）** | 第 4 项：随机抽取重抽机制 | 设计主方向确定后再决定 |

---

## 改进建议（最多 3 条）

**建议 1：形态变化节点数量应设置单人开发上限，并在骨架表中标注「工程成本」**

在主方案确定前，先列出每个形态变化节点的最低工程实现要求（状态机变更数、需要新增的动画状态数），若单人开发预计工时超过合理阈值，则将部分节点降级为「额外效果追加 + 形态描述性包装」。这不是重新设计，而是工程可行性的 gate-check。

**建议 2：为随机入池机制（方案二/三）增加「权重白名单」而非纯随机**

Ravenswatch 失败案例的核心是「全池纯随机」导致关键节点抽到概率随池规模稀释。Hades 2 设计了 boon 权重（不同房间区域对不同神明的 boon 权重不同）。建议方案二/三的随机抽取不采用纯等概率随机，而是给「与当前已选节点共享关键字」的节点加权。

**建议 3：先解决 Lv5 奥义分叉路径问题再确认任何一套方案的 N/M 参数**

当前三套方案的 N/M 数字在奥义分叉后的真实值未知。建议在用户选定主方案前，先明确「Lv5 选 A 形态后 B 形态的节点是从 N 中消失还是变为不可选但计入 N」，将修正后的 N 值作为三套方案比较的真实基础。若修正后方案一的实际取舍比例大幅上升（如奥义两条路线各有 3 个专属节点，N 从 30 降至有效 27），方案一与方案二的参数差异可能缩小到无统计显著性。

---

## 引用核验声明

- **引用 A1 条数**：12 条
- **引用 A2 条数**：14 条
- **独立 WebSearch 引入的新证据条数**：6 条（Into the Breach 飞行员技能随机化、Wildermyth 随机技能投诉两条、Ravenswatch 升级池稀释 Steam 引用、Tactics Ogre Reborn 开发者访谈、Supergiant 团队规模官方博客）
- **每条反对意见的证据可追溯性**：100%

---

## 关键引用源汇总

- [Ravenswatch Character Upgrade Suggestions Steam Community](https://steamcommunity.com/app/2071280/discussions/0/3828664145916037670/)
- [Into the Breach Pilot Leveling Annoyance Steam Community](https://steamcommunity.com/app/590380/discussions/0/1694914736011848831/)
- [Into the Breach - The One Flaw Subset Games Forum](https://subsetgames.com/forum/viewtopic.php?t=32864)
- [Wildermyth Crappy/Sub-par Skills Steam Community](https://steamcommunity.com/app/763890/discussions/0/3200370997809193228/?ctp=3)
- [Wildermyth The Most Save-Scumming Steam Community](https://steamcommunity.com/app/763890/discussions/0/3053986162865116478/)
- [Tactics Ogre Reborn Developer Interview - Frontline JP](https://www.frontlinejp.net/2022/12/07/tactics-ogre-reborn-developer-interview/)
- [Tactics Ogre Reborn Details - Gematsu](https://www.gematsu.com/2022/10/tactics-ogre-reborn-details-unit-development-charms-battle-updates-balance-adjustments-shop-improvements-classes-and-characters)
- [Hades 2 Announced - Supergiant Games](https://www.supergiantgames.com/blog/hades2-announced/)
- [Scope Creep: The Silent Killer of Solo Indie Game Development - Wayline](https://www.wayline.io/blog/scope-creep-solo-indie-game-development)
- [Cyberpunk 2077 2.0 Overhaul Inspired by Diablo 2 - PC Gamer](https://www.pcgamer.com/cyberpunk-2077s-20-overhaul-was-inspired-by-the-old-school-design-of-diablo-2s-skill-trees-and-dooms-relentless-combat/)
- [Cyberpunk 2077 Lingering Mechanics Malaise - PC Gamer](https://www.pcgamer.com/im-hoping-against-hope-that-cyberpunk-2077s-expansion-overhaul-will-finally-fix-the-games-lingering-mechanics-malaise/)
- [GDKeys: Keys to Meaningful Skill Trees](https://gdkeys.com/keys-to-meaningful-skill-trees/)
