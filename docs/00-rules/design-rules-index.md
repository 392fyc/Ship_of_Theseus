# 设计规则面索引(Design Rules Index)

> **读者 = 设计 SoT 内容的 agent**。这是设计工作的入口页:先过本页确认真源与文档地图,再读 [[content-design-general|内容设计通则]] 与对应实体分册,然后才动手设计。本页放 `00-rules/`,不进设计书面板、不同步 NAS。

## 开工路由

Ship 仓库的 AGENTS.md 与各领域角色都指向本页。按任务类型读下列文档,读完再动手;派发子代理时,把要读的文档写进派发提示。

| 任务 | 必读 | 另读 |
|---|---|---|
| 职业、技能 | [[content-design-general\|通则]]、[[skill-design-principles\|技能设计要点]] | [[01-Game-Design/Characters/class-system\|职业系统]]、[[architecture-consensus-v2\|五层架构共识]] |
| 回忆天赋、回忆节点 | 通则、[[talent-design-principles\|天赋设计要点]] §12（含“回忆点、专属节点与回忆的定位”）、技能设计要点 §6 的资源节奏裁决与 §8 | [[01-Game-Design/Characters/kensei-memory-upgrades\|剑圣回忆升级]] |
| 普通天赋 | 通则、天赋设计要点全文(用户裁决集中在 §1、§4、§5、§9、§13) | 先确认对应职业的技能与回忆已经成立(§13) |
| 装备、遗物 | 通则、对应分册 | — |
| 规则数值 | 通则 §3、§4,设计库规则表 | [[01-Game-Design/Core-Systems/battle-calculation\|战斗结算]] |
| 外部参考调研 | [[05-Research/references\|参考作品索引]] | 索引链接的已有调研 |

**依据约定**:设计结论标出依据,写到 KB 分册的页面与小节、设计库规则编号,或用户裁决原话。没有依据的数值标“[占位]”或“推断”。与本页路由到的原则冲突时,写明冲突并交用户裁决,不静默违反。

**裁决回写**:用户对设计的新裁决,当轮写进负责该主题的分册,注明日期与原话;提案目录、ADR 与工作记录只保存过程,不能代替分册。

## 真源(设计依据的权威优先级)

生产设计库读接口免 token:`http://192.168.0.254:8400`。

| 真源 | endpoint | 内容 |
|---|---|---|
| **规则表** | `/api/rules` | R1.x 战斗计算 / R2.x 人物系统 / R3.x 回合系统 / R4.x 棋盘系统;`status=锁定` 才可作为设计依据,草稿仅供参考 |
| **tag 注册表** | `/api/tags` | 共 12 条,不分层;每条带非空的 definition 与 boundary(boundary 为写接口必填),挂 tag 前两者都要读 |
| **资源注册表** | `/api/resources` | 职业特色资源(剑气 / 剑意印记),锚 R1.6;写 effect 文本前对齐名称与 definition |
| **状态注册表** | `/api/states` | 状态定义,分增益 / 负面 / 条件三类 |
| **判定注册表** | `/api/judgments` | 带成败结果的判定;成败可被效果挂靠(trigger 的「〈判定〉成功时 / 失败时」) |
| **职业** | `/api/classes` | tier / promotes_from / stat_tiers / weapon_types |
| **实体库** | `/api/talents` `/api/skills` `/api/equipment` `/api/relics` | 现有内容语料,设计前扫同池条目防撞名撞机制 |

术语表 `/api/terms` 已于 2026-07-29 用户裁决清零并收窄为纯引用层(只保留指向三张注册表的链接,不再存放事实本身),不再作为设计依据,故不列在上表——机制术语改查上面三张注册表。

KB 侧 [[01-Game-Design/rules-catalog|规则总目录]] 只是索引镜像,非权威;叙述性设计文档(01-Game-Design)与规则表冲突时,以规则表为准。

## 文档地图

| 文档 | 覆盖范围 |
|---|---|
| [[content-design-general\|内容设计通则]] | 跨实体通用纪律：真源次序 / 层定位 / 数值模式 / 措辞代数 / tag 与机制名 / 自然中文文风 / 命名 / 状态字段 / 有效评估材料 / 双轨字段 / 供给审阅 / 裁决权边界 / 机制约定与反例 |
| [[talent-design-principles\|天赋设计要点]] | 天赋：数值模式案例 / 池边界 / 避饱和维度 / 剑气高低状态轴 / rules 字段挂法 / 命名案例 / 稀有度强度标尺 / trigger 措辞规范与默认跟随主事件 / 职业强化类天赋协作蓝本 / 回忆技能升级协作蓝本 / 伤害增益分层 / 普通天赋池的组织 |
| [[skill-design-principles\|技能设计要点]] | 技能：双维度分类 / 行动资源与时机 / 射程范围 / 数值落层 / 职业资源联动 |
| [[equipment-design-principles\|装备设计要点]] | 装备：L4 定位 / 武器参数框架 / 槽位 / 稀有度分级 / 占位纪律 / 移植取材 |
| [[relic-design-principles\|遗物设计要点]] | 遗物：L5 定位 / 两类 archetype / 结构字段 / 设计约束 |
| [[architecture-consensus-v2\|五层架构共识 v2]] | L1-L5 build 架构（user-confirmed, consensus_locked），层定位的权威 |
| [[02-Development/doc-drift-ledger\|文档漂移台账]] | 已知未修的文档漂移条目（不是规则，是待办） |
| [[05-Research/references\|参考作品索引]] | 火纹、XCOM、The Last Spell、永铃回响等参考作品:KB 已有调研、可借鉴点、与 SoT 规则的差异、缺口 |

## 裁决权一句话

设计裁决(具体数值定稿 / 枚举合法集 / 规则条文增删改 / 新职业线 / 新机制轴 / 供给腾位)归用户;agent 负责机制骨架、结构、命名候选、验证与草稿。细则见 [[content-design-general|通则]] §11。
