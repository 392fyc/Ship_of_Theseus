---
name: sot-session-start
description: "Initialize a Ship of Theseus Codex session from optional active memory, then load task, design-library, and KB context only as needed."
---

# SoT Session Start

## 1. 定位活跃记忆

按以下优先级解析活跃记忆根：

1. 环境变量 `SOT_MEMORY_ROOT`。
2. 当前仓库被忽略的 `.codex/project/sot-roots.local.toml` 中 `[roots].memory_root`。
3. 均未配置时，使用游戏仓主 Git 工作树下的 `.sot/memory`。

解析默认游戏仓路径时，结合当前仓的 Git common directory 与 `git worktree list --porcelain`，定位拥有该 common directory 的非 bare 主工作树。当前任务 worktree 只用于本次操作，不得作为项目记忆路径或 bucket 身份，以免同一项目在不同 worktree 中分裂。无法确定主工作树时，不猜测兄弟目录。

旧 Mercury bucket（`.mercury/memory`）仅在用户显式通过 `SOT_MEMORY_ROOT` 或 `[roots].memory_root` 指向时允许只读访问。迁移内容或将其作为写入目标都需要用户明确授权。

## 2. 加载会话锚点

1. 若解析出的根目录和 `index.jsonl` 存在，读取索引并按当前项目 bucket 查找最近会话。
2. 按需读取该 bucket 下的 `MEMORY.md` 与 `session-checkpoint.md`。

记忆根、索引或项目 bucket 缺失时，明确报告“活跃记忆缺失”及缺失位置，然后继续处理不依赖该记忆的任务；不得伪造锚点或猜测本机路径。这些文件是活跃记忆权威；不得用 KB 的旧会话 bundle 或 current-session 文档覆盖它们。

## 3. 加载任务与事实

- 任务范围和验收状态从 GitHub/Git 读取。
- 需要结构化玩法目标事实时使用 `sot-designlib`。
- 需要叙事、定性设计、用户裁决、ADR、研究或工作记录时，通过 `sot-kb-write` 的搜索与读取流程访问 KB。
- 需要当前可执行行为时读取本游戏仓代码、数据与测试。
- 涉及通用 Harness 所有权或任务合同且文件已安装时，按需读取 `.codex/project/mercury-harness-ownership.md` 与 `.codex/project/mercury-task-contract.md`；它们由 Mercury generator 单向生成，缺失时不仿造。

## 4. 汇报启动摘要

```text
Session initialized.
Milestone: <name>
Active task: <issue and status>
Next action: <next>
Blockers: <items or none>
Active-memory anchor: <project bucket and checkpoint, or missing with reason>
Loaded authorities: <Git/designlib/game/KB selections>
```

会话启动不得自动生成 handoff、创建新 Codex 任务或改写任务状态。

## 工作区定位

日常入口是游戏主仓；从任务工作树启动时，先确认当前 HEAD/分支与任务。游戏主仓由 `SOT_SHIP_ROOT`、再由 `[roots].ship_root` 解析；其他仓与任务组也按环境变量优先、本地 roots 回退。禁止从任务工作树父目录猜跨仓位置。需要查看已有任务树时使用游戏根的 `scripts/codex/sot-worktree.ps1 -Action List`；布局与收尾规则见 [工作树生命周期](../../../docs/worktree-lifecycle.md)。
