---
name: sot-session-start
description: "Initialize a Ship of Theseus development session by reading the KB state. Use this skill whenever a new session begins, the user says 'session start', '开始会话', 'read session', or asks about current project status. Also trigger when CLAUDE.md instructs to read current-session.md at session start. This skill ensures every AI agent starts with the correct project context."
---

# SOT Session Start

Initialize a Ship of Theseus development session by loading project state from the Obsidian knowledge base.

## When to Use

- Every new conversation/session (CLAUDE.md mandates reading current-session.md)
- User says "session start", "开始会话", "read session state"
- User asks "what's the current status" or "where did we leave off"
- Any time you need to understand the current project state

## Protocol

### Step 1: Read Current Session State

```
obsidian_get_file_contents("03-AI-Context/Active-Context/current-session.md")
```

This is the **primary** tool for reading KB files. It is the most reliable method and works with all heading formats, Unicode, and special characters.

**Fallback** (only if obsidian MCP is unavailable):
```
Read tool: D:\ShipOfTheseus\ShipOfTheseus-KB\03-AI-Context\Active-Context\current-session.md
```

### Step 2: Identify Current Phase and Read Task File

From `current-session.md`, identify the current phase number (e.g. "M7" belongs to Phase 1).

Then read the corresponding task file:
```
obsidian_get_file_contents("02-Development/Tasks/Phase{N}-Tasks.md")
```

Phase-to-file mapping:
- Phase 1 (M1~M7): `Phase1-Tasks.md`
- Phase 2+: `Phase{N}-Tasks.md` (created when that phase begins)

If the task file doesn't exist yet, read the roadmap instead:
```
obsidian_get_file_contents("02-Development/Milestones/current-milestone.md")
```

Extract: current milestone section, task statuses (checkbox states), any unlocked tasks.

### Step 3: Present State Summary

After reading both files, present a concise summary to the user:

```
Session initialized.
- Milestone: [current milestone name]
- Active Task: [current task + status]
- Next Action: [what's queued next]
- Blockers: [any identified blockers, or "none"]
```

### Step 4: Suggest Relevant Docs

Based on the active task, suggest which design docs to read. Use this mapping:

| Task involves | Read |
|---|---|
| Damage / combat numbers | `01-Game-Design/Core-Systems/battle-calculation.md` |
| Class / attribute data | `01-Game-Design/Characters/class-system.md` |
| Enemy behavior / AI | `01-Game-Design/Core-Systems/enemy-and-ai.md` |
| Turn order / actions | `01-Game-Design/Core-Systems/turn-system.md` |
| Grid / pathfinding / terrain | `01-Game-Design/Core-Systems/grid-and-map.md` |
| Skills / abilities | `01-Game-Design/skills-and-range.md` |
| Architecture decisions | `02-Development/Decisions/` (relevant ADR) |
| Run loop / roguelite | `01-Game-Design/Progression/run-loop.md` |
| Town building | `01-Game-Design/Progression/town-building.md` |
| UI / visual work | Check for active Playground tasks |

Only read docs that are relevant to the current task — do not read everything.

## Important Notes

- `current-session.md` should be under 100 lines. If it's bloated, flag this to the user.
- All KB files are in the Obsidian vault at `D:\ShipOfTheseus\ShipOfTheseus-KB\`
- Use `obsidian_get_file_contents` as the primary read method, not `Read` tool or `cat`
- For searching across KB: use `obsidian_simple_search("query")`
