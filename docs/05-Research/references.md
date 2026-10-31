# 参考作品索引

本页汇总 KB 对各参考作品已经做过的调研，供设计、调研、审查代理动手前先查。先在本页找到目标作品，读已有笔记，再在其基础上补充，不要从头再查。新调研写完后，在本页对应作品下加一条链接和一句话结论，规则见文末维护约定。入口见 [[00-rules/design-rules-index|设计规则面索引]]。

本页只记录 KB 笔记里写过的内容，没有补充任何作品机制。笔记里的游戏机制描述是写作者当时的调研结论，使用前请回到原笔记核对出处。

## 使用前须知

- SoT 没有通用的追击系统，也没有反击系统。KB 现行规则写明任何单位不因受到攻击而进行反击，见 [[01-Game-Design/Core-Systems/battle-calculation|战斗结算]] 的反击系统一节和 [[01-Game-Design/Characters/class-system|职业系统]] 的反击系统一节；`01-Game-Design` 下检索不到追击规则。
- 因此火纹的追击、先手、后手、追击排他不能直接套用。几份较早的笔记仍按存在追击系统来写，引用其中的火纹结论时必须先过滤，详见火纹一节。
- SoT 没有普通攻击（见 [[00-rules/skill-design-principles|技能设计要点]]），无冷却的基础攻击技能承担持续出手。几篇笔记围绕“普攻权重”展开，借用其结论时对应到无冷却的基础技能。
- 时间线靠前的调研有被后续笔记取代的情况。`S67-FINAL-SYNTHESIS.md` 的 frontmatter 声明取代：B1.2、B2.1 的错误类比部分；R2、R3、R2-v2、R3-v2（基于“永久节点图”假设）；整份 S67-SYNTHESIS（前版基于推测，未读 KB）。B3.2 的 frontmatter 声明取代 B3。引用这些文件的结论前先看取代说明。

## 用户常驻参考

用户点名的常驻参考：火纹（2026-10-24），XCOM、The Last Spell、永铃回响（2026-10-28）。

### 火纹

**KB 已有笔记**

- [[05-Research/swordsman-talent-v2-research/tactical-rpg-skill-systems-survey|战棋 RPG 技能天赋系统调研]]（2026-03-15）：专题。第 2 节分析风花雪月，第 3 节分析 Engage，总结表里把追击排他和资源约束归到火纹。
- [[05-Research/swordsman-talent-v2-research/attack-action-weight-analysis|普通攻击权重分析]]：专题。第 2.1 节分析火纹的追击排他，第 2.4 节分析 Engage 的被动层叠加。
- [[05-Research/swordsman-talent-v2-research/action-economy-comparison|行动经济设计对比]]：把风花雪月和 Engage 的移动、攻击、反击、再行动列入对比表。
- [[90-archive/architecture-stage2-2026-05-10/D3-character-growth|D3 人物成长]]：专题。比较 FE Three Houses 加性模型、FE Engage 加性加上限、XCOM 式固定步长，选定简化的 Three Houses 加性模型。
- [[03-decisions/adr-2026-02-27-attribute-system-v1|属性系统 v1 决策]]：以 Fire Emblem Three Houses 和 Engage 为参照系，方案 A 为 FE 精简。
- [[90-archive/task-system-legacy/Tasks/attr-system-deduction-task|属性系统推演任务]]：第 2 部分为火纹对比，列出本项目与 FE 的差异，并给出 FE8 初始属性范围。
- [[03-decisions/adr-2026-08-03-hybrid-damage-formula|混合伤害公式决策]]：说明 ADR-005 把基础层改成 FE 式加性伤害。
- [[05-Research/sot-viability-2026-04-22/B1.1-player-acceptance|B1.1 玩家接受度]]：模式 A 和模式 D 讨论火纹 Heroes 去 RNG 与主线含 RNG 的玩家分裂。
- [[05-Research/mage-talent-validation-2026-05-10/01-researcher-output|法师天赋验证 研究员输出]]：风花雪月的转职分支树拓扑；Casual Mode 作为永久死亡的留存修复案例。
- [[05-Research/mage-talent-validation-2026-05-10/03-critic-output|法师天赋验证 评审输出]]：CCR-2 以风花雪月的不可逆转职技能引发的焦虑，类比 SoT 的两次不可逆选择。
- [[05-Research/talent-tree-system-research-2026-05-15/A2-design-survey-raw|天赋树调研 A2]]：风花雪月战技消耗武器耐久，Gambit 每战固定使用次数。
- [[05-Research/sot-viability-2026-04-22/B1.3-tactics-coop-samples|B1.3 战棋合作样本]]：Fire Emblem Warriors Three Hopes 的本地双人合作形态，列为战棋邻近。
- [[04-Assets/ai-sprite-pipeline|AI 精灵管线]]：美术风格参照，与机制无关。

**已记录的可借鉴点与教训**

- 数值体系：伤害公式采用 FE 式加性基础层，外层叠乘区。出处：adr-2026-02-27-attribute-system-v1。原因记录为乘法基础层没有基础缓冲，加性层即使攻击低于防御也能保证有伤害。
- 人物成长：采用简化的 Three Houses 加性模型，避开 Engage 里没有理由停留在基础职业的问题。出处：D3-character-growth。D3 顶部有后续修订提示，以该文件头部说明为准。
- 去 RNG 的玩家分裂：火纹 Heroes 去 RNG 被一部分玩家称为改进，也有玩家认为降低了张力。出处：B1.1。
- 不可逆选择需配套重试：一次性不可逆选择要配套 respec 或 retry。出处：mage-talent-validation 01。
- 不可逆转职技能在社区里持续产生“是否选错了”的焦虑，SoT 需提供足够的 UI 提示。出处：mage-talent-validation 03 的 CCR-2。
- 战技类消耗：武器耐久作为战技的资源约束。出处：tactical-rpg-skill-systems-survey。
- 被动叠加：Engage 的纹章被动在普攻时触发，让普攻成为效果触发器。出处：attack-action-weight-analysis 第 2.4 节。
- 属性联动：用户点名火纹 if 剑圣的〔流星〕、Engage 戒指的再移动，重点是与属性联动，而不是单纯百分比加伤害。出处：[[00-rules/talent-design-principles|天赋设计要点]] §1。

**与 SoT 规则的差异**

- 追击、先手、后手、反击不适用。tactical-rpg-skill-systems-survey 与 attack-action-weight-analysis 里的追击排他、追击概率、反击触发链等结论，都建立在存在追击系统的前提上，与现行规则不符。引用这两篇的火纹结论时，只保留与追击无关的部分，例如资源约束、被动层叠加。
- `S67-FINAL-SYNTHESIS.md` 也写有 Follow-up Attack 公式，并称 SoT 继承 FE 血脉。这类表述同样需要按现行规则核对后再用。
- 武器三角：笔记标注本项目无武器三角，不适用。
- 同速裁定：现行规则由难度决定同速时的先手方，见 `turn-system.md`。这与火纹的先手后手概念无关，不要混用。

**缺口**

- 没有专门的火纹机制调研：没有核对过系列各作的战斗结算、转职、个人技能与职业技能的实际规则。
- 追击排他的替代方案没人研究。SoT 没有追击，普攻与技能的竞争平衡需要另寻参照。
- 火纹的二代继承只在 B3.2 的空白提案里被点名，没有展开。

### XCOM

**KB 已有笔记**

- [[05-Research/swordsman-talent-v2-research/tactical-rpg-skill-systems-survey|战棋 RPG 技能天赋系统调研]]：专题。第 1 节分析 XCOM 2 War of the Chosen，包含双路线技能树、AP 与 Training Center、Overwatch。
- [[05-Research/swordsman-talent-v2-research/attack-action-weight-analysis|普通攻击权重分析]]：第 2.2 节把 XCOM 2 的行动经济稀缺作为保持普攻地位的策略。
- [[05-Research/swordsman-talent-v2-research/action-economy-comparison|行动经济设计对比]]：记录 XCOM 2 的 AP、Overwatch 消耗所有 AP、蓝色行动不结束回合。
- [[05-Research/sot-viability-2026-04-22/B1.1-player-acceptance|B1.1 玩家接受度]]：模式 B 专段，XCOM 2 高 RNG 引发玩家反弹，作为反面案例。
- [[05-Research/sot-viability-2026-04-22/B1.3-tactics-coop-samples|B1.3 战棋合作样本]]：XCOM 2 原生多人 2022 年从 Steam 下架，仅有社区 Tactical Co-Op Mod。
- [[90-archive/architecture-stage2-2026-05-10/D3-character-growth|D3 人物成长]]：XCOM 式固定步长成长作为备选方案之一，被判定失去 FE 的 RNG 张力。
- [[05-Research/sot-viability-2026-04-22/R3-v2-critic-failmodes|R3 v2 评审]]：引用 Midnight Suns 创意总监的观点，并指出战棋玩家身份认同不含卡牌。
- [[90-archive/ai-context-legacy/Handoffs/archive-sw-talent-v1v2/sw-talent-tree-v2-design-prompt|剑士天赋树 v2 设计任务 存档]]：研究任务表把 XCOM 2 列为重点；方案 B 引入 Overwatch 待机攻击。

**已记录的可借鉴点与教训**

- 行动经济稀缺天然保护普攻：技能与普攻共用行动点，普攻始终是零消耗选项。出处：survey 第 1 节、attack-action-weight-analysis 第 2.2 节。
- Overwatch 的价值：放弃主动攻击换取反应式射击，让不使用技能的回合也有战术价值。survey 建议转化为剑士的架势系统。出处：survey、v2-design-philosophy、sw-talent-tree-v2-design-prompt。
- 高 RNG 会引发大规模反弹：百分比命中下 95% 以上命中仍连续失手。结论是可预测性与公开难度调整是玩家接受度的关键。出处：B1.1 模式 B。
- 合作形态：老牌战棋如 XCOM 避免合作，新作与续作加强合作。出处：B1.3。

**与 SoT 规则的差异**

- 概率射击：survey 记录本项目命中有底线、暴击无上限，对 XCOM 的概率射击标注为不适用。
- 行动点：survey 与 attack-action-weight-analysis 记录的本项目行动经济为每回合一次移动加一次标准加一次迅捷，与 XCOM 的每回合两个 AP 不同。该记录写于 2026-03，现行规则以 `turn-system.md` 和设计库规则表为准。
- 反应：XCOM 的 Overwatch 是消耗行动点的待机状态；SoT 的受击方对抗手段由 Reaction 类天赋、技能和遗物各自定义，见 class-system 反击系统一节。

**缺口**

- 没有研究过 XCOM 的战斗结算、掩体、任务节奏、战略层与战术层的关系。
- mage-talent-validation 01 自述未扫 XCOM 2 的天赋树。
- Overwatch 的讨论局限在普攻权重问题下，没有对 SoT 反应类的专门调研。

### The Last Spell

**KB 已有笔记**

- [[05-Research/sot-viability-2026-04-22/B3.2-lastspell-and-tactical-roguelite-samples|B3.2 Last Spell 与同类战棋 Roguelite 样本]]：专题，本作品最完整的一篇。依据用户点名 Last Spell 是最接近 SoT 的参考系而补做。包含商业规模、run 内天赋树架构、Oraculum meta 层、随机性痛点与玩家证据、合作状态。
- [[05-Research/sot-viability-2026-04-22/S67-FINAL-SYNTHESIS|S67 最终综合]]：专题。Last Spell 重新对标一节，逐维度对照并给出痛点与 SoT 解法。
- [[05-Research/swordsman-talent-v2-research/tactical-rpg-skill-systems-survey|战棋 RPG 技能天赋系统调研]]：第 6 节，武器决定技能、AP、随机天赋升级、普攻连击。
- [[05-Research/swordsman-talent-v2-research/attack-action-weight-analysis|普通攻击权重分析]]：第 2.3 节，普攻随精准属性 scaling。
- [[05-Research/swordsman-talent-v2-research/action-economy-comparison|行动经济设计对比]]：行动经济对比表中的 Last Spell 一行。
- [[90-archive/ai-context-legacy/Handoffs/archive-sw-talent-v1v2/sw-talent-tree-v2-design-prompt|剑士天赋树 v2 设计任务 存档]]：研究任务表中的 Last Spell 一行。

**已记录的可借鉴点与教训**

- 规模：Steam 估计拥有者 50 万至 100 万，好评率 92%。出处：B3.2。
- 架构：run 内天赋树每局重置，分 8 列，T1 到 T5 按已投点数分层解锁，列内无分支依赖；meta 层 Oraculum 只扩展可选池，不持久化天赋。出处：B3.2。
- 痛点：升级时天赋随机抽取，与当前 build 无关；属性加成随机分配，选了毒素路线却没有毒素属性加成就无法成型。负评聚焦“差一点就更好”，而不是不能玩。出处：B3.2。
- 借鉴方向：B3.2 给出 SoT 的差异化点为分支转职、结构化随机、合作。
- 普攻 scaling：让普攻有成长性是保持其竞争力的关键。出处：survey、attack-action-weight-analysis。
- 合作：Steam PC 版无官方合作。出处：B3.2。

**与 SoT 规则的差异**

- 节奏：Last Spell 是单人轮流制，无速度差；SoT 为速度序多单位回合。出处：S67-FINAL。
- 行动点：Last Spell 的多 AP 与 SoT 行动经济不同，survey 标注不适用。
- 天赋：S67-FINAL 的对比表引用的是 KB 当时的 SoT 设计，结构与数字请对照最新设计正本。

**缺口**

- 战斗层本身没有调研：城镇防守循环、昼夜节奏、AP 与地图结构，只有 survey 里一小段。
- 城镇建设与 meta 的关联：B3.2 讲了 Oraculum，但没有把它与 SoT 的城镇建设一一比对。
- B3.2 的数据时点是 2026-04，之后的版本变化没有跟进。
- survey 里的 Last Spell 机制描述未见来源链接，使用前建议另行核对。

### 永铃回响

**KB 已有笔记**

没有专题调研，只有两处顺带提及，而且两处所在的文件都已被 S67-FINAL 取代。

- [[05-Research/sot-viability-2026-04-22/R2-analyst-viability|R2 分析师可行性]]：称永铃回响是 B2.2 的正面参考，作为 A 路径高度契合的证据，但仍处 demo 阶段，无商业验证数据。
- [[05-Research/sot-viability-2026-04-22/S67-SYNTHESIS|S67 综合]]：载体 A 小型战棋方向合理，举例 Sunderfolk、Into the Breach、永铃回响。

**已记录的可借鉴点与教训**

- 只有一个结论：被当作小型战棋方向合理的佐证，且无商业数据。

**缺口**

- 完全没有机制调研，这是本页最大的缺口：战斗规则、与 SoT 的对照、可借鉴点都需要从头建立。
- 来源不清：R2 称其出自 B2.2，但 B2.2 全文没有这个名字，原始调研记录可能缺失。
- 新调研应先确认作品的基本事实，KB 里没有任何一手资料。

## 其他参考作品

### 战棋类

**Into the Breach**

- [[05-Research/sot-viability-2026-04-22/B2.1-talent-modifier-patterns|B2.1 修饰器模式]] 的 Pattern F：专题。确定性预览加小网格固定修饰器；每个机甲两个装备槽；深度来自预览信息的决策复杂性，不来自组合爆炸。
- [[05-Research/sot-viability-2026-04-22/B1.1-player-acceptance|B1.1]]：被作为确定性受玩家称赞的案例。
- [[05-Research/sot-viability-2026-04-22/B1.3-tactics-coop-samples|B1.3]] 与 [[05-Research/sot-viability-2026-04-22/R3-critic-failmodes|R3]]：单人，社区认为合作会变成一人发号施令。
- [[05-Research/sot-viability-2026-04-22/B2.2-carrier-feasibility-acd|B2.2]]：单人战棋 roguelite 的标杆。
- [[05-Research/swordsman-talent-v2-research/tactical-rpg-skill-systems-survey|战棋 RPG 技能天赋系统调研]] 第 7 节：极简行动经济、位移核心、完美信息；可借鉴攻击附带位移。
- [[05-Research/talent-tree-system-research-2026-05-15/C-critic-feedback|天赋树调研 C 评审]]：飞行员技能随机化的社区批评，作为紧凑池加随机的反例。
- 要点：SoT 与它同为小网格，但它是完美信息，SoT 有概率与未知敌人。缺口：无单独的战斗规则调研。

**Sunderfolk**

- [[05-Research/sot-viability-2026-04-22/B1.3-tactics-coop-samples|B1.3]]：2 至 4 人在线合作。
- [[05-Research/sot-viability-2026-04-22/B2.2-carrier-feasibility-acd|B2.2]]：合作战棋的成功样本；其职业系统偏扁平。
- [[05-Research/sot-viability-2026-04-22/R3-critic-failmodes|R3]]：峰值在线人数一年衰减约 90%，视为长尾留存的结构性弱点。
- [[05-Research/sot-viability-2026-04-22/R2-analyst-viability|R2]]：指出数据窗口仅 3.5 周。
- 缺口：玩法机制与角色专属行动权没有专门调研。

**Wargroove 与 Advance Wars**

- [[05-Research/sot-viability-2026-04-22/B1.3-tactics-coop-samples|B1.3]]：Wargroove 1 与 2 为合作样本；Advance Wars Re-Boot Camp 无合作。
- [[05-Research/sot-viability-2026-04-22/B1.1-player-acceptance|B1.1]]：Wargroove 的单一正解反弹，说明确定性不保证玩家满意。
- [[05-Research/sot-viability-2026-04-22/R3-critic-failmodes|R3]]：合作中一方空转，作为合作资源不对等的失败案例。

**Triangle Strategy**

- [[05-Research/sot-viability-2026-04-22/B1.1-player-acceptance|B1.1]]：Conviction 投票基于累积数值，非概率骰子。
- [[05-Research/sot-viability-2026-04-22/B1.3-tactics-coop-samples|B1.3]]：纯单人。

**Final Fantasy Tactics 与 Tactics Ogre**

- [[05-Research/mage-talent-validation-2026-05-10/01-researcher-output|法师天赋验证 研究员输出]]：FFT 的 Main Job 加 Sub Job 为槽位式互斥，靠槽位限制强制权衡。
- [[05-Research/talent-tree-system-research-2026-05-15/A2-design-survey-raw|天赋树调研 A2]]：FFT 的 TP 为队伍共享、分段阈值；Tactics Ogre Reborn 废弃独立 TP 并入 MP。
- [[05-Research/talent-tree-system-research-2026-05-15/B-design-proposals|天赋树调研 B]]：剑气多档阈值借鉴 FFT TP。
- [[05-Research/talent-tree-system-research-2026-05-15/C-critic-feedback|天赋树调研 C 评审]]：以 Tactics Ogre Reborn 去 TP 为反例，质疑独立累积资源条的认知负担。
- [[05-Research/sot-viability-2026-04-22/B1.1-player-acceptance|B1.1]]：战斗速度争议，随机波动被放大。

**Divinity Original Sin 2**

- [[05-Research/sot-viability-2026-04-22/B1.3-tactics-coop-samples|B1.3]]：4 人分角色合作，非格子。
- [[05-Research/sot-viability-2026-04-22/R3-critic-failmodes|R3]]：成功源于投票决策、完整叙事与大团队，不能直接类比。

**Banner Saga**

- [[05-Research/mage-talent-validation-2026-05-10/03-critic-output|法师天赋验证 评审输出]]：战斗能力缺少专用工具导致手改 JSON 的事后总结，仅作工程与流程教训。

### Roguelite 类

**Hades 与 Hades 2**

- [[05-Research/talent-tree-system-research-2026-05-15/A1-game-data-raw|天赋树调研 A1]]：专题，Hades 1 与 Hades 2 的游戏数据。另见 [[05-Research/talent-tree-system-research-2026-05-15/A2-design-survey-raw|A2]] 第 2.2 节对 Arcana Cards 的分析，以及 [[05-Research/talent-tree-system-research-2026-05-15/B-design-proposals|B]] 的方案一。
- [[05-Research/sot-viability-2026-04-22/B1.2-talent-roguelite-decoupling|B1.2]] 模式 A：Mirror of Night 与 Arcana Cards。
- [[05-Research/sot-viability-2026-04-22/B2.1-talent-modifier-patterns|B2.1]] Pattern B：Boon 池、Duo Boon、空槽位强制补呈现。
- [[90-archive/architecture-stage2-2026-05-10/D1-global-meta|D1 全局 meta]] 第 6.1 与 6.2 节：Arcana 的玩家选择激活可借鉴；Mirror 的纵向成长 SoT 禁止。
- [[90-archive/architecture-stage2-2026-05-10/D5-runes-system|D5 符文系统]]：Grasp 容量限制对应 SoT 6 格。
- [[90-archive/architecture-stage2-2026-05-10/D4-equipment-affix|D4 装备词缀]] 第 8.5 节：Hades 的 Boon 是反向参考。
- [[01-Game-Design/Progression/run-loop|run-loop]]：地图采用 Hades 门模式。
- 教训：[[05-Research/talent-tree-system-research-2026-05-15/C-critic-feedback|C 评审]]指出 Hades 是动作游戏，选择后即刻反馈，战棋要推演多回合，三选一随机的成本更高。

**Slay the Spire**

- [[05-Research/sot-viability-2026-04-22/B1.2-talent-roguelite-decoupling|B1.2]] 模式 B：Ascension 为难度开关，meta 与 run 几乎零耦合。
- [[05-Research/sot-viability-2026-04-22/B2.1-talent-modifier-patterns|B2.1]] Pattern D：遗物海量池加数据驱动平衡。
- [[90-archive/architecture-stage2-2026-05-10/D1-global-meta|D1]] 第 6.5 节：横向而非纵向成长的标杆，解锁只拓宽抽池不抬上限。
- [[05-Research/talent-tree-system-research-2026-05-15/A2-design-survey-raw|A2]] 第 2.1 节，以及 B 的方案三。

**其他只被顺带提及的作品**

| 作品 | 笔记 | 要点 |
|---|---|---|
| Monster Train | [[05-Research/sot-viability-2026-04-22/B2.1-talent-modifier-patterns\|B2.1]] Pattern C；[[05-Research/sot-viability-2026-04-22/B1.2-talent-roguelite-decoupling\|B1.2]] 模式 C | 冠军三条升级路径，每次只呈现两个 |
| Wildfrost | [[05-Research/sot-viability-2026-04-22/B2.2-carrier-feasibility-acd\|B2.2]] | 只在样本表中 |
| Balatro | [[05-Research/sot-viability-2026-04-22/B3-strict-talent-tree-samples\|B3]]；B2.2 | 归为物品收集，无节点图 |
| Darkest Dungeon 2 | [[05-Research/sot-viability-2026-04-22/B3.2-lastspell-and-tactical-roguelite-samples\|B3.2]] | 样本表一行 |

## 维护约定

- 新调研文件放 `05-Research/`，按主题建子目录，例如已有的 `swordsman-talent-v2-research/`。涉及某作品的整篇或成节分析，文件名带作品名更易检索。
- 与具体任务绑定的调研放 `05-Research/<主题>-<日期>/`，并登记到 `05-Research/README.md` 的索引。
- 调研写完后，在本页对应作品下追加一条链接，写法是 `[[路径不带.md|显示名]]`，后面跟一句话说明该文说了什么；同时在该作品的可借鉴点、差异、缺口三栏里补充或划掉相应条目。
- 新作品先在本页新增小节；只有顺带提及的作品，加进对应分组的表格，升级为专题时再单独成节。
- 区分专题和顺带提及，不要把顺带提及写成已研究。
- 每条结论注明出自哪篇笔记。一篇笔记的前提与现行规则冲突时，在本页标出，不要默默沿用。
- 标题禁止使用括号和方括号。
