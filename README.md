# Ship of Theseus — Godot 工程仓库

> **本仓库不放设计文档。** 设计**正本（canonical）**统一在 Obsidian KB Vault：`D:\ShipOfTheseus\ShipOfTheseus-KB\`
> 2026-06-24 起，原先的设计总纲（本文件旧版）与 `dev_doc/` 下的 01–12 系列分册（回合系统 / 战斗计算 / 职业系统 / 天赋树 等）已全部迁往 KB；仓库内只保留**工程实现**、**工程文档**与**开发工具**。
> 查设计规则请走 KB（`obsidian_*` MCP 或 `/sot-kb-write`）；各设计主题对应的 KB 路径见 [dev_doc/README.md](./dev_doc/README.md)。

## 项目

| 项目属性 | 内容 |
|---|---|
| 类型 | 战棋 RPG + Roguelite + 城镇建设 |
| 引擎 | Godot 4.6（GDScript）|
| 数据 | JSON 驱动，数值不写死在代码里，一律从 `data/` 读 |
| 架构 | GameAction 指令架构 |
| 主场景 | `scenes/tactical/TacticalScene.tscn` |
| autoload | `DataLoader`（`scripts/data/data_loader.gd`）、`MCPGameBridge` |

## 目录结构

| 路径 | 内容 |
|---|---|
| `scripts/core/` | 战斗核心：`tactical_manager.gd` / `turn_manager.gd` / `damage_calculator.gd` / `grid.gd` / `cell.gd` / `pathfinding.gd` / `range_calculator.gd` / `area_calculator.gd` / `enemy_ai.gd` / `game_action.gd` |
| `scripts/units/` | 单位：`unit.gd` / `unit_stats.gd` / `buff_effect.gd` |
| `scripts/ui/` | 战斗 UI：底部信息操作栏、技能栏、剑气条、伤害飘字、伤害预测、出手顺序条；`playground/` 为视觉原型控件 |
| `scripts/roguelite/` | run 循环：`run_manager.gd` / `door_generator.gd` / `reward_resolver.gd` / `battle_assembler.gd` + 场景脚本 |
| `scripts/tactical/` | `tactical_scene.gd`（战斗场景入口，含测试用 harness 按键）|
| `scripts/data/` | `data_loader.gd`（autoload，负责载入 `data/` 下的 JSON）|
| `scenes/` | `tactical/`（主场景 / 单位 / 底栏）、`roguelite/`（run 场景 / 选门）、`playground/` 与 `dev/`（UI 原型）|
| `data/` | JSON 数据：`classes/` `skills/` `weapons/` `equipment/` `relics/` `affixes/` `enemies/` `waves/` `events/` `buffs/` `maps/` `terrain/` `runloop/` |
| `tests/` | headless 回归套件、实验脚本、人工测试清单，见「测试」一节 |
| `tools/` | 浏览器端设计工具，见下 |
| `dev_doc/` | 工程与研究文档，见下 |
| `assets/` | 美术与音频素材 |
| `addons/godot_mcp/` | Godot MCP 插件（编辑器侧启动，端口 6550）|

> `scripts/ai/`、`scripts/network/`、`scriptsui/`、`scenes/menus/`、`scenes/battle/`、`data/buildings/`、`data/talent-tree/`、`assets/audio/` 等目录目前是空占位，尚未开工。

## 开发工具 `tools/`

四个设计工具 + 一个入口页 + 一份共享库，均为纯前端，浏览器直接打开即可，无需构建；数据存在浏览器 localStorage。

| 文件 | 用途 |
|---|---|
| `index.html` | 工具套件入口页，附本地数据状态 |
| `talent-tree-editor.html` | 天赋树编辑器：拓扑编辑、DAG 校验、路径成本分析、Mermaid / PNG 导出 |
| `equipment-designer.html` | 装备设计器：武器 / 护甲 / 饰品的数值与预览卡片 |
| `map-designer.html` | 地图设计器：地形 / 特殊地形 / 建筑 / 出生点 / 建造区域分层绘制 |
| `damage-simulator.html` | 伤害模拟器：单次计算 + 1000 次随机模拟 + 天赋节点价值对比 |
| `shared.js` | 四个工具共享的常量、公式与 localStorage / 多语言辅助 |

> 工具里的公式是**离线调校用的近似复刻，不是发布逻辑**。发布逻辑以 `scripts/` + `data/` 为准，规则条文以 KB 与 SoT 设计库（sot.fyc-space.uk）为准。

## 工程文档 `dev_doc/`

| 目录 | 内容 |
|---|---|
| `skillbar-design/` | 剑圣底部信息操作栏 v3 设计规格 + 配对视觉稿，实装锁定参考 |
| `runloop-design/` | run 循环门模式方案、节奏基准、v0 实装计划 |
| `relic-equip-designlib-research/` | 遗物 / 装备接入 SoT 设计库的字段规格研究 |
| `narrative-restoration-degree/` | 「世界之理复原度」给 Mercury 组的机制协调请求 |
| `ui-art-research/` | 战斗 UI 美术方向研究稿：气质选定（冷石皮肤 + 信息密度排版）与 HUD 排版稿 v3，`skillbar-design/` 的上游 |
| `plan1-cleanup/` | Plan-1 叙事文档的删减清单与用词清单 |

## 测试

headless 跑法（退出码 0 = 全过）：

```
<Godot_console.exe> --headless --path D:/ShipOfTheseus/Ship_of_Theseus --script res://tests/<文件>.gd
```

- `tests/test_*.gd` —— 回归套件，改动后应全绿。
- `tests/exp_*.gd` —— 一次性实验 / 测量脚本（耗时长、打印多），不并入标准回归套件。
- `tests/*.md` —— 人工测试清单（剑圣 / 门循环）与实验结论留档。渲染、鼠标交互与手感类验证 headless 测不到，走人工清单。

## 协作规则

- `CLAUDE.md`（Claude Code）/ `AGENTS.md`（外部 Sub Agent）/ `OPENCODE.md`（opencode）/ `.cursorrules`（Cursor）：各工具链的硬规则，含机制红线与 GDScript 禁则。改动机制前先看这四份。
- 分支命名 `{agent}/{task-name}`，个人作业无 PR 流程。
