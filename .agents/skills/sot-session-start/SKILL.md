---
name: sot-session-start
description: "Initialize a Ship of Theseus session by loading project-native memory first, then reading KB context only when needed."
---

# SOT Session Start

## Protocol

### Step 1: 先加载项目活跃记忆（唯一权威）
1. 读取 `D:\Mercury\Mercury\.mercury\memory\index.jsonl`
2. 按当前项目 bucket 查询最近会话
3. 按需读取 `MEMORY.md` 与 `session-checkpoint.md`（若存在）

### Step 2: 获取任务上下文（必要时）
仅在本次工作需要设计约束时读取 KB，路径可见性仍指向：
`D:\ShipOfTheseus\ShipOfTheseus-KB\03-AI-Context\Active-Context\`
优先读取当前任务文件与相关上下文，再回到项目记忆作为主状态源。

### Step 3: Present Summary
```
Session initialized.
Milestone: [name]
Active Task: [task + status]
Next Action: [queued next]
Blockers: [any or "none"]
Active-Memory Anchor: [project bucket + checkpoint]
```

### Step 4: Suggest Relevant Docs
只在任务确需上下文时读取相关设计文档。常见入口：
- Combat/damage → `01-Game-Design/Core-Systems/battle-calculation.md`
- Class/attributes → `01-Game-Design/Characters/class-system.md`
- Architecture → `02-Development/Decisions/` (relevant ADR)

## 记忆优先级
- 1) `D:\Mercury\Mercury\.mercury\memory\`（活动记忆，单一真源）
- 2) `D:\ShipOfTheseus\ShipOfTheseus-KB\`（设计与开发知识库，辅助）
