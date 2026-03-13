---
name: sot-session-end
description: "End a Ship of Theseus development session by writing session state to KB. Trigger on session end, '会话结束', 'handoff', 'save session', or when context is running low."
---

# SOT Session End

## Protocol

### Step 1: Generate State Snapshot
Gather: tasks completed, files modified, decisions made, issues found, next actions.
Format as tables + bullets, **under 100 lines**, no narrative paragraphs.

### Step 2: Write to KB
```
1. Read:  D:\ShipOfTheseus\ShipOfTheseus-KB\03-AI-Context\Active-Context\current-session.md
2. Write: D:\ShipOfTheseus\ShipOfTheseus-KB\03-AI-Context\Active-Context\current-session.md
```

### Step 3: Sync Task Checkboxes
Read `02-Development/Tasks/Phase{N}-Tasks.md`, update `[ ]` → `[x]` for completed tasks.

### Step 4: Verify
`obsidian_get_file_contents("03-AI-Context/Active-Context/current-session.md")` — confirm under 100 lines.

### Step 5: Git Sync (Mandatory)
Execute KB repo git-sync per `03-AI-Context/Handoffs/git-sync-procedure.md` "KB Repository Sync" section.
- **Trigger**: "Before session end → Mandatory → Main Agent" (git-sync-procedure.md Trigger Timing)
- Scope: `D:\ShipOfTheseus\ShipOfTheseus-KB\` — all files modified during this session
- Message format: `session: close {session-id}`
- This step is a **precondition** for session closure — see `acceptance-workflow.md` Git Sync Rule.

## Critical Rules

1. **NEVER append** — always full replace. Appending = unbounded growth.
2. **Under 100 lines** — historical data lives in git history.
3. **No narrative** — tables and bullets only.
4. Architecture notes = constraints only (what NOT to do wrong).
