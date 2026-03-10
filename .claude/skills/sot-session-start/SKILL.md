---
name: sot-session-start
description: "Initialize a Ship of Theseus development session by reading KB state. Trigger on session start, '开始会话', or when asking about project status."
---

# SOT Session Start

## Protocol

### Step 1: Read Session State
```
obsidian_get_file_contents("03-AI-Context/Active-Context/current-session.md")
```
Fallback: `Read D:\ShipOfTheseus\ShipOfTheseus-KB\03-AI-Context\Active-Context\current-session.md`

### Step 2: Read Task File
From session state, identify current phase → read `02-Development/Tasks/Phase{N}-Tasks.md`

### Step 3: Present Summary
```
Session initialized.
- Milestone: [name]
- Active Task: [task + status]
- Next Action: [queued next]
- Blockers: [any or "none"]
```

### Step 4: Suggest Relevant Docs
Only read docs relevant to current task. Common paths:
- Combat/damage → `01-Game-Design/Core-Systems/battle-calculation.md`
- Class/attributes → `01-Game-Design/Characters/class-system.md`
- Architecture → `02-Development/Decisions/` (relevant ADR)
