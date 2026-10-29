# GPT Codex CLI Dedicated Prompt Library

> 三仓协作默认从 `Ship_of_Theseus` 游戏仓启动。本文中的 `<ship_root>` 和 `<designlib_root>` 分别取自对应 `SOT_*_ROOT` 环境变量，或当前工作目录中被忽略的 `.codex/project/sot-roots.local.toml`；KB 是游戏仓（或其任务工作树）的 `docs/`。任务工作树建在各仓库根的 `.worktrees/<任务名>`，不能从任务目录的父级推断另一个仓库。游戏代码与 KB 文档都在游戏任务工作树修改。以游戏仓现行 `AGENTS.md`、项目技能及 `docs/02-Development/Scripts/agent-runtime-layout.md` 为操作依据。

> High-frequency prompt templates for OpenAI Codex CLI (terminal invocation), suited for bulk code generation tasks.

---

## Batch Code Generation - Read Spec from Docs
```
Read the design spec from:
docs\01-Game-Design\[document].md

Generate GDScript code for Godot 4 implementing:
[feature description - English works better]

Follow these conventions:
- Data-driven: load from JSON files in res://data/
- File: res://scripts/[system-name]/[filename].gd
```

## Legacy Code Migration
```
Migrate the following code to match the new data architecture
defined in:
docs\01-Game-Design\Technical\data-architecture.md

Source files: [file path list]
Target structure: JSON-driven, separate data from logic
```

## Parallel Tasks - tmux Multi-Panel
```
# Panel 1: Non-core feature generation (no human intervention needed)
codex "Read docs/01-Game-Design/Progression/run-loop.md,
implement the complete save/load system for run progress in GDScript"

# Panel 2: UI base layer generation
codex "Read docs/01-Game-Design/Characters/class-system.md,
generate the inventory UI base layer with item slots and drag-drop"
```

## Session End - Update Progress
```
Update the file:
docs\03-AI-Context\Active-Context\current-session.md
(该文件已退役，本模板仅作历史参考；当前会话状态写在活跃记忆根的 lane checkpoint，见 AGENTS.md「活跃记忆根」)

Mark as completed: [task name]
Add to next actions: [next step]
```
