# Phase 2 Overview: Battle System Depth

> Goal: Complete Layer 2 combat mechanics, implement talent tree runtime, validate with mini run loop.
> Status truth lives in registry YAML, not in this overview page.

## Authority Map

| Artifact | Role |
|---|---|
| `90-archive/task-system-legacy/Task-Registry/phase-2-registry.yaml` | Authoritative Phase 2 status |
| `90-archive/task-system-legacy/Task-Registry/global-index.yaml` | Global cross-phase index |
| `03-AI-Context/Active-Context/current-session.md` | Current session ledger |
| `02-Development/Task-Bundles/` | New implementation work intake |
| `02-Development/Acceptance-Bundles/` | Blind acceptance output |
| `02-Development/Issue-Bundles/` | Interrupt and triage lane |

## Phase Snapshot

| Item | Status | Notes |
|---|---|---|
| M8 | `completed` | Action Economy — TASK-P2-BATT-001 closed, ACC-P2-BATT-001 passed |
| M9 | `completed` | Targeting System — TASK-P2-TARG-001 verified, ACC-P2-TARG-001 passed |
| M10 | `completed` | Buff/Debuff Runtime — TASK-P2-BUFF-001 verified, ACC-P2-BUFF-001 passed |
| M11 | `completed` | Combat Resolution Depth — TASK-P2-CRES-001 verified, ACC-P2-CRES-001 passed |
| M12 | `not_started` | AI and Content Expansion |
| M13 | `not_started` | Talent Tree Runtime |
| M14 | `not_started` | Mini Run Validation |

## Milestone Dependency Graph

```
M8 (Action Economy) ──┬──→ M10 (Buff/Debuff) ──┐
                      │                          ├──→ M11 (Combat Depth) ──→ M12 (AI) ──┐
M9 (Targeting) ───────┘                          │                                       ├──→ M14 (Mini Run)
                                                 └──→ M13 (Talent Runtime) ─────────────┘
                                                        ↑
                                             P2-TALENT (human talent design)
                                             P2-CLASS  (human class selection)
```

M8 and M9 can be developed in parallel. M10 depends on M8 turn timing. M11 merges all three. M12 and M13 depend on M11. M14 is the capstone.

## Parallel Human Workstreams

| ID | Workstream | Owner | Feeds Into |
|---|---|---|---|
| P2-ART | Art asset pipeline | Human | M12 (enemy visuals) / M14 (run experience) |
| P2-CLASS | Demo class selection - Swordsman +2 | Human | M13 (talent tree data) |
| P2-TALENT | Talent tree template design | Human + Design Agent | M13 (JSON data) |

## Deferred Issues from P1

| Issue | Priority | Scheduled At |
|---|---|---|
| ISSUE-2026-03-08-001 (legacy page drift) | Sev-2 | M8 startup |
| ISSUE-2026-03-09-003 (mcp_logger traceback) | Sev-3 | M12 |

## Linked Decisions

- `ADR-001` Grid Coordinate System
- `ADR-002` Buff Debuff Structure (lands in M10)
- `ADR-004` Damage Type Redesign
- `ADR-005` Attribute System V1
- `ADR-009` Action Economy Implementation (new, created at M8)

## Operating Rules

- New work must begin with a Task Bundle.
- Dev-agent completion is not final closure; registry closure requires acceptance and docs sync.
- Acceptance results must be stored in Acceptance Bundles.
- Interrupts and unexpected bugs must enter the Issue Bundle lane before reprioritization.
- Blind acceptance follows `90-archive/task-system-legacy/Task-Registry/acceptance-workflow.md`.
- Governance checks follow `90-archive/task-system-legacy/Task-Registry/governance-audit-checklist.md`.
- This page is a hub and summary only. It must not hold authoritative per-item progress.

### Dev Agent Escalation Protocol

During milestone implementation, modifications fall into two categories:

| Scope | Handling | Example |
|---|---|---|
| Small impact, simple implementation | Dev Agent executes directly, records in task bundle implementation_receipt, reports to Main Agent | Fix a typo in JSON schema, adjust a minor UI offset |
| Large impact, cross-system | Dev Agent escalates to Main Agent for scope assessment and potential new task creation | Change to GameAction architecture, new ADR needed |

The boundary is judged by the Dev Agent. When in doubt, escalate.

## References

- `90-archive/task-system-legacy/Templates/task-bundle.template.yaml`
- `90-archive/task-system-legacy/Templates/acceptance-bundle.template.yaml`
- `90-archive/task-system-legacy/Templates/issue-bundle.template.yaml`
- `90-archive/task-system-legacy/Task-Registry/acceptance-workflow.md`
- `90-archive/task-system-legacy/Task-Registry/issue-triage-policy.md`
- `90-archive/task-system-legacy/Task-Registry/governance-audit-checklist.md`
- `90-archive/task-system-legacy/Task-Registry/phase-2-registry.yaml`
- `03-AI-Context/Active-Context/current-session.md`
- `01-Game-Design/game-design-doc.md`
- `01-Game-Design/Characters/talent-tree.md`
- `01-Game-Design/Characters/talent-tree-design.md`
