# Ship of Theseus 知识库入口

本知识库（KB）保存 SoT 的现行规则、开发约定、决策与研究。它同时是 Obsidian vault。每个目录都有 `README.md` 索引，逐条列出文档和状态：

- **现行**：可以作为工作依据。
- **草稿**：还在讨论，不作为依据。
- **已取代**：被别的文档替换，索引写明取代者。
- **历史**：只作记录。

KB 之外的权威：结构化玩法事实（技能、天赋、规则表、装备、遗物）在设计库；当前可执行行为在游戏代码；任务范围与进度在 GitHub Issue 和 PR。分工见仓库根目录的 `AGENTS.md`「权威路由」。

## 先读这三处

| 要知道什么 | 读哪里 |
|---|---|
| 现行规则：设计时必须遵守的约束 | [00-rules](00-rules/README.md) |
| 进度与开发约定：任务在哪里跟踪、怎么提交和发布 | [02-Development](02-Development/README.md) |
| 决策登记：做过哪些裁决、为什么 | [03-decisions](03-decisions/README.md) |

## 按任务类型

| 任务 | 先读 |
|---|---|
| 设计或审查职业、技能、回忆、天赋、装备、遗物 | [设计规则面索引](00-rules/design-rules-index.md)，再读它路由到的分册；然后读设计库的现行规则与记录 |
| 改战斗、技能、伤害或资源的实现 | [规则总目录](01-Game-Design/rules-catalog.md) 与 [战斗计算系统](01-Game-Design/Core-Systems/battle-calculation.md)；规则原文以设计库为准 |
| 改敌人 AI | [敌人与 AI 系统](01-Game-Design/Core-Systems/enemy-and-ai.md) |
| 改人物棋子或地形表现 | [04-Assets](04-Assets/README.md) 中的验收准则 |
| 叙事与世界观 | [Narrative](01-Game-Design/Narrative/README.md) |
| 外部参考调研 | [参考作品索引](05-Research/references.md) |
| 工作树、分支、lane、CI | [02-Development](02-Development/README.md) |

## 全部目录

| 文档 | 状态 | 说明 |
|---|---|---|
| [00-rules/](00-rules/README.md) | 现行 | 现行设计规则 |
| [01-Game-Design/](01-Game-Design/README.md) | 现行 | 定性设计（目录名被设计库挂载，不可改名） |
| [02-Development/](02-Development/README.md) | 现行 | 开发流程、协作约定与进度位置 |
| [03-decisions/](03-decisions/README.md) | 现行 | 决策登记 |
| [04-Assets/](04-Assets/README.md) | 现行 | 美术与素材 |
| [05-Research/](05-Research/README.md) | 现行 | 研究与参考 |
| [90-archive/](90-archive/README.md) | 历史 | 已退役的体系与旧版本，只作记录 |

## 维护

- 改动规则、决策或进度的任务，在同一个 PR 里更新对应的现行文档，并在索引里标出它取代了什么。
- 检查：`python -B .mercury/packs/kb/scripts/kb_check.py docs`，CI 契约测试也会运行它。
- 约定全文：`.mercury/packs/kb/docs/kb-conventions.md`。
