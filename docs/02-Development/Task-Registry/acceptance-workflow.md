# Acceptance Workflow

## Purpose

This document defines the mandatory blind-acceptance loop for all new implementation work.

## Roles

| Role | Responsibility |
|---|---|
| Main Agent | Create bundles, update registry, advance authoritative status |
| Dev Agent | Implement code and complete only the implementation receipt in its own Task Bundle |
| Acceptance Agent | Perform blind acceptance and write only the Acceptance Bundle |
| Human | Resolve priority conflicts and approve emergency reprioritization |

## Handoff Sequence

1. Main Agent creates a Task Bundle and dispatches it.
2. Dev Agent implements only within `allowed_write_scope`.
3. Dev Agent completes `implementation_receipt` and stops at `implementation_done`.
4. Main Agent reviews bundle completeness and advances the task to `acceptance_ready`.
5. Main Agent creates or activates the paired Acceptance Bundle.
6. Acceptance Agent performs blind acceptance using only the allowed inputs.
7. Acceptance Agent writes `result`, `evidence`, `gaps`, and `followup_action`.
8. Main Agent updates registry status and decides whether docs sync or issue routing is required.

## Blind Acceptance Rules

Allowed inputs:

- Task Bundle input fields
- Referenced design and ADR documents listed in the Task Bundle
- Codebase
- Runtime environment and test tooling

Forbidden inputs:

- Dev Agent narrative summary outside the Task Bundle
- Ad hoc chat explanations from the Dev Agent
- Direct status decisions made by the Dev Agent
- Registry mutation by the Acceptance Agent

## Result Semantics

| Result | Meaning | Registry Direction |
|---|---|---|
| `pass` | Acceptance criteria satisfied | `verified` |
| `partial` | Some criteria satisfied, gaps remain | return to task flow |
| `fail` | Acceptance criteria not met | return to task flow |
| `blocked` | Acceptance cannot proceed due to external blocker | create or link Issue Bundle |

## Registry Transition Rules

| Step | Actor | Allowed Transition |
|---|---|---|
| Dispatch | Main Agent | `drafted -> dispatched` |
| Start work | Main Agent or Dev Agent | `dispatched -> in_progress` |
| Dev completion | Dev Agent | `in_progress -> implementation_done` |
| Acceptance handoff | Main Agent | `implementation_done -> acceptance_ready` |
| Acceptance pass | Main Agent | `acceptance_ready -> verified` |
| Docs sync | Main Agent | `verified -> docs_synced` |
| Git sync | Main Agent | `docs_synced -> closed` (git commit is a precondition) |
| Blocker | Main Agent | `* -> blocked` |
| Cancellation | Main Agent or Human | `* -> cancelled` |

## Failure Routing

### Partial

- Keep the original Task Bundle open.
- Record concrete gaps in the Acceptance Bundle.
- Main Agent returns the task to `in_progress` or `dispatched`.
- Do not create an Issue Bundle unless the gap exceeds the current task scope.

### Fail

- Keep the original Task Bundle open.
- Record failed checks and missing acceptance evidence.
- Main Agent returns the task to `in_progress`.
- Create an Issue Bundle only if the failure reveals a broader process, environment, or design problem.

### Blocked

- Acceptance Agent records the blocker in the Acceptance Bundle.
- Main Agent creates or links an Issue Bundle.
- Main Agent sets the task to `blocked` until triage is complete.
- `P0` and `P1` issues may interrupt the active queue.

## Issue Routing Rules

| Priority | Action |
|---|---|
| `P0` | Interrupt now |
| `P1` | Resolve in current phase |
| `P2` | Schedule to milestone |
| `P3` | Archive as known issue |

When resolving or archiving an issue, sync status across Issue Bundle, phase registry, and global index per `issue-triage-policy.md` Issue Closure Sync.

## Docs Sync Rule

- Acceptance pass does not close work by itself.
- Main Agent must verify every path in `docs_must_update`.
- Only after required docs are synced may the task move from `verified` to `docs_synced`.

## Git Sync Rule

Git commit is a mandatory precondition for task closure. No human intervention required.

**Responsibility**: Main Agent executes git staging and commit for both repos. This is metadata bookkeeping (staging existing files + writing commit messages), not code modification.

**Timing**: After all registry and docs are updated, before marking `closed`.

**Procedure**:

1. **Game Repo** (`Ship_of_Theseus`): Stage the files listed in `implementation_receipt.changed_files` together with the bundle, registry, and session files changed under `docs/` (the KB, merged into this repository on 2026-10-29). Commit.
2. **Commit message format**: `{type}({task_id}): {one-line summary}`
3. Push is NOT part of this rule. Push timing is decided by Human.

**Commit type prefixes**:

| Prefix | Use |
|---|---|
| `feat` | Game feature implementation |
| `fix` | Bug fix |
| `chore` | Tooling, config, registry, workflow |
| `data` | JSON/resource data files |
| `docs` | Documentation-only changes |

**Preconditions for `closed`**: `docs_synced` + git commits completed for both repos.

**Procedural reference**: See `03-AI-Context/Handoffs/git-sync-procedure.md` for detailed commands and scenarios.
