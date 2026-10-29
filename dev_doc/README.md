# dev_doc — 设计文档已迁移至 KB（单一真源）

> **2026-06-24 起，本目录的设计文档（01–12 / game-design-doc / design-roadmap / class-system / module-relations 等）已移除。**
> 设计**正本（canonical）**统一在 KB，即本仓库的 [`docs/`](../docs/)（Obsidian vault；原独立仓库 ShipOfTheseus-KB 于 2026-10-29 并入）。
> 移除前经**逐文件审计**确认：KB 是这些 dev_doc 的 canonical 超集/等价，原 dev_doc 的"独有"内容均为**已被 KB 主动取代的旧设计**（旧属性模型 / holy→pure / 格挡乘区 / 追击 / 魔法师旧四系等），无有效内容丢失。

## 正本位置（KB 内路径，点击打开）

| 主题 | KB 路径 |
|---|---|
| 回合系统 | [`01-Game-Design/Core-Systems/turn-system.md`](../docs/01-Game-Design/Core-Systems/turn-system.md) |
| 网格与地图 | [`01-Game-Design/Core-Systems/grid-and-map.md`](../docs/01-Game-Design/Core-Systems/grid-and-map.md) |
| 战斗计算 | [`01-Game-Design/Core-Systems/battle-calculation.md`](../docs/01-Game-Design/Core-Systems/battle-calculation.md) |
| 敌人与 AI | [`01-Game-Design/Core-Systems/enemy-and-ai.md`](../docs/01-Game-Design/Core-Systems/enemy-and-ai.md) |
| 技能与射程 | [`01-Game-Design/skills-and-range.md`](../docs/01-Game-Design/skills-and-range.md) |
| 职业系统 | [`01-Game-Design/Characters/class-system.md`](../docs/01-Game-Design/Characters/class-system.md) |
| 天赋树 | [`01-Game-Design/Characters/talent-tree.md`](../docs/01-Game-Design/Characters/talent-tree.md)（设计源已转 **SoT 设计库** sot.fyc-space.uk / NAS DB）|
| Run 循环 | [`01-Game-Design/Progression/run-loop.md`](../docs/01-Game-Design/Progression/run-loop.md) |
| 城镇建设 | `01-Game-Design/Progression/town-building.md`（现行 KB 中已无此文件） |
| 数据架构 | [`01-Game-Design/Technical/data-architecture.md`](../docs/01-Game-Design/Technical/data-architecture.md) |
| 联机 | [`01-Game-Design/Technical/network.md`](../docs/01-Game-Design/Technical/network.md) |
| 里程碑 | [`02-Development/Milestones/current-milestone.md`](../docs/02-Development/Milestones/current-milestone.md) |
| 路线图 | [`02-Development/design-roadmap.md`](../docs/02-Development/design-roadmap.md) |
| 游戏设计总纲 | [`01-Game-Design/game-design-doc.md`](../docs/01-Game-Design/game-design-doc.md) |
| 模块关系 | [`03-AI-Context/module-relations.md`](../docs/03-AI-Context/module-relations.md) |

KB 在任务工作树的 `docs/` 中随任务修改，流程见 `/sot-kb-write`（禁 PowerShell 写入，BOM 问题）。

## 仍保留在 repo 的

- `skillbar-design/` —— 剑圣技能栏 v3 UI 设计稿（`skillbar-spec.md` + `skillbar-mockup.html`），批4 锁定参考，KB 暂无对应。
- [Penpot 云端设计接手入口](ui-art-research/penpot/README.md) —— 基础 HUD 的当前定版版本、画板定位、预览及素材清单。
