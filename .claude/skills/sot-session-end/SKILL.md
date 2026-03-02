---
name: sot-session-end
description: "End a Ship of Theseus development session by writing the session state to the KB. Use this skill when the session is ending, the user says 'session end', '会话结束', 'handoff', 'save session', or when context is running low and state needs to be preserved. Also trigger when the user asks to update current-session.md or prepare for handoff to another AI tool."
---

# SOT Session End

Write a compact session state snapshot to the KB for handoff to the next session or AI tool.

## When to Use

- Session is ending (user says "session end", "会话结束", "handoff")
- Context window is getting full and state needs preservation
- Switching to a different AI tool (Cursor, Codex, Antigravity)
- User asks to "save session" or "update current-session.md"

## Protocol

### Step 1: Gather Session Data

Review what was accomplished in this session:
- Tasks completed
- Files modified (code and KB docs)
- Decisions made
- Issues discovered
- What's next

### Step 2: Generate State Snapshot

Use this exact template. Keep the total under 100 lines. Be ruthlessly concise.

```markdown
## Status
- **Date**: YYYY-MM-DD
- **Milestone**: [milestone name + status emoji]
- **Active Task**: [current task description]
- **Tool**: [which AI tool wrote this]

## Milestone Progress
| Milestone | Status |
|---|---|
| M1-M6 | Done |
| M7 | [status] |

## Task Status
| Task | Status | Notes |
|---|---|---|
| [task name] | [icon] | [one-line note] |

Status icons: Done, In Progress, Unlocked, Blocked, Not Started

## Architecture Notes
| Rule | Detail |
|---|---|
| [component] | [constraint or pattern] |

Only include rules that future sessions MUST know. Remove stale rules.

## ADR Registry
| ADR | Topic | Status |
|---|---|---|
| ADR-NNN | [topic] | [status] |

## Next Actions
1. [immediate next step]
2. [follow-up]
```

### Step 3: Write to KB

**Use this method** (most reliable):

```
1. Read tool:  D:\ShipOfTheseus\ShipOfTheseus-KB\03-AI-Context\Active-Context\current-session.md
2. Write tool: D:\ShipOfTheseus\ShipOfTheseus-KB\03-AI-Context\Active-Context\current-session.md
   (with the new content)
```

**Why this method**: The `Read` + `Write` combination is the most reliable write method. It avoids `obsidian_patch_content` heading-matching failures and PowerShell encoding issues. The `Read` call is required before `Write` — the Write tool will error without it.

**Do NOT use**:
- `obsidian_patch_content` — heading matching is fragile for full-file rewrites
- PowerShell scripts — encoding issues with UTF-8 content
- `obsidian_append_content` — appending causes dimensional explosion (the core problem we're solving)

### Step 4: Verify

After writing, read the file back to confirm:
```
obsidian_get_file_contents("03-AI-Context/Active-Context/current-session.md")
```

Verify it's under 100 lines and contains all critical state.

## Critical Rules

1. **NEVER append** — always replace the entire file. Appending causes unbounded growth.
2. **Under 100 lines** — if your snapshot exceeds this, cut non-essential content. Historical session data lives in git history, not in current-session.md.
3. **No narrative** — use tables and bullet points, not paragraphs.
4. **Architecture notes are for constraints only** — don't document how things work, document what future sessions must NOT do wrong.
5. **Frontmatter**: Keep the YAML frontmatter at the top if one exists in the file.
