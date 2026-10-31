# 设计规则面索引(Design Rules Index)

> **读者 = 设计、调研或审查 SoT 内容的代理**。这是设计工作的入口页：先按下面的路由读规则总表的对应节，再读实体指引，然后读设计库现行记录，最后才动手。派发子代理时，把要读的节与指引写进派发提示（[总表](rules.md) P01）。

## 三份东西各管什么

| 文档 | 管什么 | 地位 |
|---|---|---|
| [设计规则总表](rules.md) | 现在必须怎么做：每条规则一行，带编号、级别和来源决策 | 设计纪律的唯一正本 |
| [决策登记](../03-decisions/register.md) | 每条规则来自哪次决策、在哪里能找到原话 | 只列现行决策 |
| 各实体指引（下表） | 术语解释、写法示例、案例、设计方法、检查清单 | 三级内容，只解释总表，不另立规则 |

系统结算规则（伤害、命中、暴击、触发次数、行动点、冷却等）的正本是设计库规则表，总表与指引都不复述；离线目录见 [规则总目录](../01-Game-Design/rules-catalog.md)，逐字原文在设计库仓库 `snapshots/rules.json`。

## 开工路由

| 任务 | 先读总表的节 | 再读指引 | 另读 |
|---|---|---|---|
| 职业、技能 | G、W、S、N | [技能设计指引](skill-design-principles.md)、[内容设计通用指引](content-design-general.md) | [职业系统](../01-Game-Design/Characters/class-system.md)、[五层架构共识](../03-decisions/architecture-consensus-v2.md) |
| 回忆天赋、回忆节点 | G、W、M、N、P | [天赋设计指引](talent-design-principles.md) §回忆、[技能设计指引](skill-design-principles.md) | [剑圣回忆升级](../01-Game-Design/Characters/kensei-memory-upgrades.md) |
| 普通天赋 | G、W、T、N | [天赋设计指引](talent-design-principles.md) | 先确认对应职业的技能与回忆已经成立（T16） |
| 装备 | G、W、E、N | [装备设计指引](equipment-design-principles.md) | — |
| 遗物 | G、W、L、N | [遗物设计指引](relic-design-principles.md) | [五层架构共识](../03-decisions/architecture-consensus-v2.md) |
| 规则数值 | N，以及设计库规则表 | [内容设计通用指引](content-design-general.md) §数值 | [战斗计算](../01-Game-Design/Core-Systems/battle-calculation.md)（展开说明，与规则表冲突时以规则表为准） |
| 外部参考调研 | — | [参考作品索引](../05-Research/references.md) | 索引链接的已有调研 |

**依据与冲突**：设计结论指到总表编号、决策登记编号、设计库规则编号或用户裁决原话；没有依据的数值标「[占位]」或「推断」（P03）。与总表冲突时写明冲突的编号交用户裁决，不静默违反（P04）。

**新裁决怎么记**：改总表对应规则（没有就新增一行），在决策登记登记来源，删除被推翻的行（P05）。不在指引里追加带日期的裁决或原话；提案目录与工作记录只保存过程。

## 设计库里要读的东西

读取按 `sot-designlib` 技能执行（地址、版本记录与摘要都在那里）。设计前要读：

| 内容 | 接口 | 读它为了什么 |
|---|---|---|
| 规则表 | `/api/rules` | 系统结算规则正本；只有锁定条目作依据 |
| tag 注册表 | `/api/tags` | 挂 tag 前读每条的 definition 与 boundary（W16） |
| 资源、状态、判定注册表 | `/api/resources`、`/api/states`、`/api/judgments` | 卡面措辞与机制名对齐（W15）；状态会持续增加，每次重新读取，不在 KB 硬编码清单 |
| 职业 | `/api/classes` | 确认职业存在、`tier`、`promotes_from`、`stat_tiers`、`weapon_types`（P02） |
| 实体 | `/api/talents`、`/api/skills`、`/api/equipment`、`/api/relics` | 同池现状，防撞名撞机制（P02）；条数与取值以接口为准，KB 不记数目 |

## 文档地图

| 文档 | 覆盖范围 |
|---|---|
| [设计规则总表](rules.md) | 全部设计纪律，按 G、W、T、S、M、E、L、N、P 分节 |
| [内容设计通用指引](content-design-general.md) | 跨实体的方法：五层定位、数值模式与乘区、字段职责示例、双轨字段、审计范围 |
| [天赋设计指引](talent-design-principles.md) | 天赋与回忆：数值层示例、池边界、trigger 挑法、命名案例、稀有度示例、回忆的双层设计与兼容矩阵、自检清单 |
| [技能设计指引](skill-design-principles.md) | 技能字段面、射程与范围读法、转职分层示例、同槽形态 |
| [装备设计指引](equipment-design-principles.md) | 装备定位、武器参数、槽位、特效字段现状、取材方法 |
| [遗物设计指引](relic-design-principles.md) | 遗物定位、两类 archetype、字段现状 |
| [五层架构共识 v2](../03-decisions/architecture-consensus-v2.md) | L1–L5 构筑架构，层定位的权威 |
| [文档漂移台账](../02-Development/doc-drift-ledger.md) | 已知未修的文档漂移（待办，不是规则） |
| [参考作品索引](../05-Research/references.md) | 火纹、XCOM、The Last Spell、永铃回响等参考作品的已有调研与差异 |
