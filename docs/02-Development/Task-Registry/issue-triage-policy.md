# Issue Triage Policy

## Purpose

This document defines how newly discovered issues enter, interrupt, or stay outside the active milestone flow.

## Intake Rule

- Every newly discovered non-trivial issue must be recorded as an Issue Bundle before it changes the active queue.
- Discovery sources may be human review, Main Agent review, Dev Agent work, Acceptance Agent work, or automated detection.
- No direct reprioritization is allowed from chat alone.

## Priority Definitions

| Severity | Meaning | Required Action |
|---|---|---|
| `Sev-0` | Actively blocks safe progress or invalidates current acceptance | Interrupt now |
| `Sev-1` | Does not fully block progress but must be resolved in the current phase | Resolve in current phase |
| `Sev-2` | Important but may be scheduled into milestone planning | Schedule to milestone |
| `Sev-3` | Known issue or weak signal | Archive as known issue |

## Decision Rules

| Decision | When to Use |
|---|---|
| `interrupt_now` | `Sev-0` blocker, broken source of truth, invalid runtime environment, or severe regression |
| `attach_to_current_task` | The issue is small and sits fully inside the current task scope |
| `schedule_to_milestone` | The issue is valid but should be handled in the normal queue |
| `archive_as_known_issue` | The issue is recorded but intentionally deferred |

## Authority

| Action | Owner |
|---|---|
| Create Issue Bundle | Main Agent |
| Propose Issue | Dev Agent / Acceptance Agent / Human |
| Change Active Queue | Main Agent |
| Approve `Sev-0` interruption | Human or Main Agent |
| Close Issue | Main Agent |

## Triage Questions

1. Does this issue invalidate current code acceptance?
2. Does this issue corrupt KB truth or dispatch safety?
3. Can the issue be solved fully inside the current Task Bundle without widening scope?
4. Is the issue environmental rather than implementation-specific?
5. What is the lowest priority that still preserves delivery quality?

## Issue Closure Sync

When an issue status changes to `resolved` or `archived`, Main Agent must update all three locations atomically:

1. **Issue Bundle** — set `status` and `resolution_status` in the YAML file.
2. **Phase registry** — remove the issue ID from `active_issue_ids`; add entry to `resolved_issues`.
3. **Global index** — update `status` in `issue_index`; remove from phase `active_issue_ids`.

Failure to sync all three creates state drift detectable only by governance audit.

## Phase Attachment Rule

- All issues enter `global-index.yaml` first.
- An issue is added to `phase-1-registry.yaml` only after triage explicitly attaches it to that phase.
- `Sev-2` and `Sev-3` issues may remain global only.

## Examples

- `Sev-0`: acceptance environment cannot run; registry truth is overwritten; active branch is unusable
- `Sev-1`: acceptance found a core regression in the active feature
- `Sev-2`: workflow drift risk, missing automation, non-blocking design inconsistency
- `Sev-3`: speculative future cleanup or weakly evidenced concern
