---
name: sot-session-start
description: "Initialize a Ship of Theseus Codex session from Mercury active memory, then load task, design-library, and KB context only as needed."
---

# SoT Session Start

## 1. 定位 Mercury 活跃记忆

按以下顺序解析 Mercury 根目录：

1. 环境变量 `MERCURY_ROOT`。
2. 当前仓库被忽略的 `.codex/project/sot-roots.local.toml` 中 `[roots].mercury_root`。
3. 均未配置时停止读取活跃记忆并明确提示，不猜测本机路径。

活跃记忆根为 `<mercury-root>/.mercury/memory`。

## 2. 加载会话锚点

1. 读取 `.mercury/memory/index.jsonl`。
2. 按当前项目 bucket 查找最近会话。
3. 按需读取该 bucket 下的 `MEMORY.md` 与 `session-checkpoint.md`。

这些文件是活跃记忆权威；不得用 KB 的旧会话 bundle 或 current-session 文档覆盖它们。

## 3. 加载任务与事实

- 任务范围和验收状态从 GitHub/Git 读取。
- 需要结构化玩法目标事实时使用 `sot-designlib`。
- 需要叙事、定性设计、用户裁决、ADR、研究或工作记录时，通过 `sot-kb-write` 的搜索与读取流程访问 KB。
- 需要当前可执行行为时读取本游戏仓代码、数据与测试。

## 4. 汇报启动摘要

```text
Session initialized.
Milestone: <name>
Active task: <issue and status>
Next action: <next>
Blockers: <items or none>
Active-memory anchor: <project bucket and checkpoint>
Loaded authorities: <Git/designlib/game/KB selections>
```

会话启动不得自动生成 handoff、创建新 Codex 任务或改写任务状态。
