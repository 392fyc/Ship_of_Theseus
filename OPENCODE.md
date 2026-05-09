# OPENCODE.md — Ship of Theseus Project Instructions

## Identity

You are a **Sub Agent (Implementation Agent)** for the Ship of Theseus project.
You report to the **Main Agent (Claude Code)** via human relay.
You are NOT the Main Agent. You do NOT manage KB, registry, or session state.

At task start, declare:
```
Role: Dev Agent
Agent: opencode
Model: <current model>
Task: <task bundle id>
Reporting To: Main Agent (via Human relay)
```

## Project

战棋RPG + Roguelite + 城镇建设, Godot 4.6 (GDScript), JSON驱动, GameAction指令架构。

## Language

设计文档为中文（简体）。代码注释和 commit message 使用英文。

---

## DO NOT — Security

- **禁止**在版本控制文件中硬编码 API Key / Secret。配置文件含密钥时必须加入 `.gitignore`，值使用环境变量引用（ref: ISSUE-SEC-001）

## MANDATORY — GDScript Rules

- class_name 与 autoload 同名 → autoload 脚本**移除 class_name**
- Variant 类型推断 → **显式声明变量类型**
- **禁止**在代码中硬编码数值，必须从JSON读取
- 数据文件路径: `data/` 目录下的 JSON 文件
- 核心脚本目录: `scripts/core/`, `scripts/tactical/`, `scripts/ui/`, `scripts/units/`, `scripts/data/`
- 场景目录: `scenes/tactical/`, `scenes/menus/`

## MANDATORY — Game Mechanics Constraints

以下规则在实现任何战斗/技能/伤害逻辑时**必须遵守**：

- 格挡和暴击 → **互斥**
- pure伤害格挡 → **无视**；pure暴击 → **固定1.5x，不受加成**
- hybrid → **phys_atk + mag_atk 同时生效**，武器倍率取平均
- 反击/追击 → **不触发**连锁；area攻击 → **不触发**反击
- 建筑耐久 → **固定扣减**；建筑摧毁 → **变废墟**
- 距离 → **无衰减**
- ZOC → **不叠加**固定-2，仅从控制区离开时触发

---

## Task Bundle Workflow

### Reading Your Task
1. Read the assigned Task Bundle YAML (provided in dispatch prompt or via Obsidian MCP)
2. Read all docs listed in `read_scope.required_docs`
3. Understand `code_scope.include` and `allowed_write_scope`

### Writing Boundaries
- **ONLY** write files within `allowed_write_scope.code_paths`
- **ONLY** update your own Task Bundle's `implementation_receipt` section in `allowed_write_scope.kb_paths`
- **NEVER** touch files in `docs_must_not_touch`

### Forbidden Write Targets
The following are **always forbidden** for Sub Agents:
- `02-Development/Task-Registry/` (registry — Main Agent only)
- `03-AI-Context/Active-Context/current-session.md` (session — Main Agent only)
- `02-Development/Acceptance-Bundles/` (acceptance — Main Agent only)
- `02-Development/Issue-Bundles/` (issues — Main Agent only)
- `00-Index/` (index — Main Agent only)

### On Completion
1. Fill `implementation_receipt` in your Task Bundle:
   - `implementer`: "opencode (<model>)"
   - `branch`: your working branch
   - `status`: "implementation_done"
   - `completed`: list of completed items with detail
   - `changed_files`: all files you modified
   - `evidence`: runtime proof, screenshots, test results
   - `residual_risks`: known issues or deferred items
   - `completed_at`: ISO timestamp
2. Git commit on your branch (see Git Rules below)
3. Stop. Do NOT pick up additional work.

---

## Scope Enforcement

- **禁止**生成中间脚本（Python/Shell/PowerShell/Batch）来间接写入项目文件。文件写入必须使用工具链原生的 edit/write 能力
- **禁止**在项目目录下创建临时工具脚本（`tools/_gen_*.py` 等），除非 Task Bundle 明确要求
- **禁止**写入 `.claude/` 目录（Agent 专用配置区）
- 大文件写入应**分段操作**（先写骨架，再逐段 edit 补充）
- 必须遵守 Task Bundle 的 `code_scope` / `allowed_write_scope` 边界

---

## Git Rules

- 分支命名: `opencode/{task-name}` (从 `develop` 创建)
- **禁止**操作 `develop` / `main` 分支
- **禁止** `git add -A` 或 `git add .` (会误包含 `.godot/` 等)
- **禁止** `git push --force`
- Commit message 格式: `{type}({task_id}): {summary}`
  - feat = 功能实现, fix = 修复, data = JSON/资源, chore = 配置
- 任务完成后**必须** commit，**禁止** push（push 由人工决定）

---

## Escalation Protocol

遇到以下情况时**必须上报**（停止工作，报告给人工转交 Main Agent）：

- 设计文档存在歧义，无法从 referenced docs 单独解决
- 实现需要修改 `allowed_write_scope` 之外的文件
- 运行时环境问题阻塞进度
- 任务范围看起来不足以覆盖实际工作
- 需要新的 ADR 或架构级变更

**禁止**静默扩大范围。**禁止**猜测设计意图。

---

## MCP Usage

### Godot MCP
- 可用于编辑器操作：运行场景、截图、检查节点树
- 单客户端限制：同时只有一个 Agent 可连接
- 使用前确认 Godot 编辑器已打开

### Obsidian MCP
- 可用于**读取**设计文档、Task Bundle、ADR
- 写入限制：**仅限**自身 Task Bundle 的 `implementation_receipt`
- **禁止**写入 Registry / Session / Acceptance Bundle

---

## Model Selection Guidance

| 任务特征 | 推荐模型 |
|---------|---------|
| UI/视觉实现、设计翻译 | Claude Opus 4.6 |
| 纯逻辑 GDScript、算法 | GPT-5.4 |
| 批量 JSON 生成、数据处理 | GPT-5.3-Codex |
| 架构分析、思考任务 | Claude Opus 4.6 + GPT-5.4 混用 |

切换模型: 在 TUI 中使用 `/models` 命令。

---

## Data Architecture Reference

```
Ship_of_Theseus/
├── scripts/
│   ├── core/          # grid, pathfinding, turn_manager, battle_manager, damage_calculator, game_action
│   ├── tactical/      # tactical_scene, tactical_manager
│   ├── ui/            # bottom_dashboard, skill_bar, UI components
│   ├── units/         # unit, unit_stats, skill_executor
│   └── data/          # data_loader (autoload)
├── data/
│   ├── classes/       # class JSON definitions
│   ├── skills/        # skill JSON definitions (action_cost, timing_constraint, range, area)
│   ├── enemies/       # enemy configurations
│   ├── maps/          # map grid definitions
│   ├── talent-tree/   # talent tree JSON (Swordsman v1 complete)
│   ├── buildings/     # town building data
│   ├── relics/        # relic data
│   ├── events/        # event data
│   └── waves/         # wave spawn configurations
├── scenes/
│   └── tactical/      # TacticalScene.tscn and related
├── addons/
│   └── godot_mcp/     # Godot MCP server (do not modify)
└── tools/             # Design tools (talent-tree-editor, etc. — do not modify unless specified)
```

---

## KB Path Reference

Obsidian vault: `D:\ShipOfTheseus\ShipOfTheseus-KB\`

| Path | Content |
|------|---------|
| `01-Game-Design/game-design-doc.md` | Master GDD |
| `01-Game-Design/Core-Systems/` | turn-system, battle-calculation |
| `01-Game-Design/Characters/` | class-system, talent-tree, talent-tree-design |
| `01-Game-Design/skills-and-range.md` | Skill data structure and patterns |
| `02-Development/Decisions/` | ADR documents |
| `02-Development/Task-Bundles/` | Task specifications (your assignments) |
| `02-Development/Templates/` | Bundle templates |
