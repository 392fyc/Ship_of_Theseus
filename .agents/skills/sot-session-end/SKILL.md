---
name: sot-session-end
description: "End a Ship of Theseus development session with active-memory sync first, then optional KB sync, and manual handoff only on explicit user request."
---

# SOT Session End

## Protocol

### Step 1: Generate State Snapshot
Gather: tasks completed, files modified, decisions made, issues found, next actions.
格式以要点为主，不追求 narrative 文本。
默认不自动 handoff；只有用户明确要求时才执行 handoff 流程。

### Step 2: Update Active Memory（优先）
先读取 `D:\Mercury\Mercury\.mercury\memory\index.jsonl`，按项目 bucket 查找会话锚点后，写入：

`D:\Mercury\Mercury\.mercury\memory\projects\<project-bucket>\session-checkpoint.md`

不得直接写入 `D:\Mercury\Mercury\.mercury\memory\` 根目录。

### Step 3: Update KB（仅限本次需要）
若会话对 KB 有实际修改，执行：
1. 定位相关 KB 文件路径
2. 读取 `03-AI-Context` 当前条目
3. 写回修改后的状态
4. 回读确认

### Step 4: Sync Task Checkboxes
Read `02-Development/Tasks/Phase{N}-Tasks.md`，更新完成项：`[ ]` → `[x]`。

### Step 5: Handoff（Manual only）
只在用户明确触发时执行：
- 生成可直接粘贴的会话起始指令（聊天直接可粘贴）
- 写持久 handoff 文档（`~/.Codex/projects/<project>/memory/project_session{N}_handoff.md`）

不得在未获用户明确要求时执行 handoff 或自动创建/更新上述持久文档。

禁止自动：
- 自动创建新 Codex 任务上下文
- 在 PreCompact 里触发 handoff:auto
- 自动切换任务状态
