# dev_doc — 设计文档已迁移至 KB（单一真源）

> **2026-06-24 起，本目录的设计文档（01–12 / game-design-doc / design-roadmap / class-system / module-relations 等）已移除。**
> 设计**正本（canonical）**统一在 Obsidian KB Vault：`D:\ShipOfTheseus\ShipOfTheseus-KB\`
> 移除前经**逐文件审计**确认：KB 是这些 dev_doc 的 canonical 超集/等价，原 dev_doc 的"独有"内容均为**已被 KB 主动取代的旧设计**（旧属性模型 / holy→pure / 格挡乘区 / 追击 / 魔法师旧四系等），无有效内容丢失。

## 正本位置（KB 相对路径）

| 主题 | KB 路径 |
|---|---|
| 回合系统 | `01-Game-Design/Core-Systems/turn-system.md` |
| 网格与地图 | `01-Game-Design/Core-Systems/grid-and-map.md` |
| 战斗计算 | `01-Game-Design/Core-Systems/battle-calculation.md` |
| 敌人与 AI | `01-Game-Design/Core-Systems/enemy-and-ai.md` |
| 技能与射程 | `01-Game-Design/skills-and-range.md` |
| 职业系统 | `01-Game-Design/Characters/class-system.md` |
| 天赋树 | `01-Game-Design/Characters/talent-tree.md`（设计源已转 **Codex 卡片工具** sot.fyc-space.uk / NAS DB）|
| Run 循环 | `01-Game-Design/Progression/run-loop.md` |
| 城镇建设 | `01-Game-Design/Progression/town-building.md` |
| 数据架构 | `01-Game-Design/Technical/data-architecture.md` |
| 联机 | `01-Game-Design/Technical/network.md` |
| 里程碑 | `02-Development/Milestones/current-milestone.md` |
| 路线图 | `02-Development/design-roadmap.md` |
| 游戏设计总纲 | `01-Game-Design/game-design-doc.md` |
| 模块关系 | `03-AI-Context/module-relations.md` |

KB 读写走 `obsidian_*` MCP 或 `/sot-kb-write`（禁 PowerShell 写入，BOM 问题）。

## 仍保留在 repo 的

- `skillbar-design/` —— 剑圣技能栏 v3 UI 设计稿（`skillbar-spec.md` + `skillbar-mockup.html`），批4 锁定参考，KB 暂无对应。
