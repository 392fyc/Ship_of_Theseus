# Task Registry System

## Purpose

This directory is the authoritative status source for agent work.

## Authority Rules

| Artifact | Authority | Notes |
|---|---|---|
| `global-index.yaml` | Main Agent | Global cross-phase index |
| `phase-1-registry.yaml` | Main Agent | Authoritative Phase 1 state |
| `Task Bundles` | Main Agent + assigned Dev Agent | Dev Agent may update only its own receipt and allowed write scope |
| `Acceptance Bundles` | Acceptance Agent | Blind acceptance output only |
| `Issue Bundles` | Main Agent | Global issue intake and triage |
| `current-session.md` | Main Agent | Minimal ledger only |

## Status Lifecycle

| Status | Meaning |
|---|---|
| `drafted` | Defined but not yet dispatched |
| `dispatched` | Assigned and ready for execution |
| `in_progress` | Active implementation or review |
| `implementation_done` | Dev work completed, awaiting acceptance handoff |
| `acceptance_ready` | Main Agent has prepared acceptance |
| `verified` | Acceptance passed |
| `docs_synced` | Required KB updates completed |
| `closed` | Work fully finished |
| `blocked` | Cannot proceed without unblock action |
| `cancelled` | Intentionally stopped |

## Working Rules

- New implementation work must start from a Task Bundle.
- Authoritative task state must be updated in registry YAML, not in overview pages.
- `Phase1-Tasks.md` is a navigation hub, not a status ledger.
- `current-session.md` is a compact ledger and must stay under 100 lines.
- Issues enter the global index first; they join a phase registry only after triage attaches them to that phase.
- Blind acceptance flow is defined in `90-archive/task-system-legacy/Task-Registry/acceptance-workflow.md`.

## 目录索引

| 文档 | 状态 | 说明 |
|---|---|---|
| [acceptance-workflow.md](acceptance-workflow.md) | 历史 | Acceptance Workflow |
| [governance-audit-checklist.md](governance-audit-checklist.md) | 历史 | Governance Audit Checklist |
| [issue-triage-policy.md](issue-triage-policy.md) | 历史 | Issue Triage Policy |

非 Markdown 附件：`global-index.yaml`、`phase-1-registry.yaml`、`phase-2-registry.yaml`。
