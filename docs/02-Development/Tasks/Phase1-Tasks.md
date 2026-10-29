# Phase 1 Overview: Runnable Skeleton

> Phase 1 is closed. See `02-Development/Task-Registry/phase-1-registry.yaml` for authoritative status.
> Goal: Maintain the first playable TRPG battle demo as the Phase 1 baseline.
> Status truth lives in registry YAML, not in this overview page.

## Authority Map

| Artifact | Role |
|---|---|
| `02-Development/Task-Registry/phase-1-registry.yaml` | Authoritative Phase 1 status |
| `02-Development/Task-Registry/global-index.yaml` | Global cross-phase index |
| `03-AI-Context/Active-Context/current-session.md` | Current session ledger |
| `02-Development/Task-Bundles/` | New implementation work intake |
| `02-Development/Acceptance-Bundles/` | Blind acceptance output |
| `02-Development/Issue-Bundles/` | Interrupt and triage lane |

## Phase Snapshot

| Item | Status | Notes |
|---|---|---|
| M0 | `closed` | Architecture decisions accepted |
| M1 | `closed` | Data layer accepted |
| M1.5 | `in_progress` | Art asset baseline remains exploratory |
| M2 | `closed` | Grid system accepted |
| M3 | `closed` | Unit system accepted |
| M4 | `closed` | Turn system accepted |
| M5 | `closed` | Battle calculation accepted |
| M6 | `closed` | Runnable demo foundations accepted |
| M7 | `closed` | Runnable demo polish accepted |

## Linked Decisions

- `ADR-001` Grid Coordinate System
- `ADR-002` Buff Debuff Structure
- `ADR-003` Unit Cell Reference
- `ADR-004` Damage Type Redesign
- `ADR-005` Attribute System V1
- `ADR-007` Multi-Agent Toolchain
- `ADR-008` Sprite Layer Architecture

## Operating Rules

- New work must begin with a Task Bundle.
- Dev-agent completion is not final closure; registry closure requires acceptance and docs sync.
- Acceptance results must be stored in Acceptance Bundles.
- Interrupts and unexpected bugs must enter the Issue Bundle lane before reprioritization.
- Blind acceptance follows `02-Development/Task-Registry/acceptance-workflow.md`.
- Governance checks follow `02-Development/Task-Registry/governance-audit-checklist.md`.
- This page is a hub and summary only. It must not hold authoritative per-item progress.

## References

- `02-Development/Templates/task-bundle.template.yaml`
- `02-Development/Templates/acceptance-bundle.template.yaml`
- `02-Development/Templates/issue-bundle.template.yaml`
- `02-Development/Task-Registry/acceptance-workflow.md`
- `02-Development/Task-Registry/issue-triage-policy.md`
- `02-Development/Task-Registry/governance-audit-checklist.md`
- `02-Development/Scripts/README.md`
- `02-Development/Scripts/agent-runtime-layout.md`
- `02-Development/Scripts/new-task-bundle.ps1`
- `02-Development/Scripts/new-acceptance-bundle.ps1`
- `02-Development/Scripts/new-issue-bundle.ps1`
- `02-Development/Task-Bundles/TASK-P1-SKILL-001.yaml`
- `02-Development/Acceptance-Bundles/ACC-P1-SKILL-001.yaml`
- `02-Development/Issue-Bundles/ISSUE-2026-03-08-001.yaml`
- `02-Development/Task-Registry/README.md`
- `02-Development/Task-Registry/phase-1-registry.yaml`
- `03-AI-Context/Active-Context/current-session.md`
- `02-Development/Tasks/task-scene-rename-isometric-refactor.md`
- `02-Development/Tasks/task-viewport-angle-playground.md`
