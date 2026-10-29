# Governance Audit Checklist

## Purpose

This checklist is the recurring audit guard for KB truth, workflow discipline, and state alignment.

## Audit Cadence

- Run after every accepted task closure.
- Run before switching Main Agent sessions after major routing work.
- Run before milestone review or phase summary updates.

## Registry Integrity

- `global-index.yaml` exists and links the active phase registry.
- Active phase registry exists and reflects current phase reality.
- No overview page is carrying authoritative status that disagrees with registry YAML.
- Every active Task or Acceptance Bundle referenced in session state is present on disk.

## Session Ledger Integrity

- `current-session.md` is under 100 lines.
- `current-session.md` contains only ledger fields and references.
- Every active or blocked ID listed in session ledger exists in registry or bundle artifacts.
- `Next Queue` reflects the true next operational steps.

## Task Flow Integrity

- Every new implementation item has a Task Bundle.
- No Dev Agent updated registry YAML directly.
- No task is marked `verified` without an Acceptance Bundle result.
- No task is marked `closed` before `docs_synced`.

## Acceptance Integrity

- Acceptance Agent outputs exist only inside Acceptance Bundles.
- `result` is one of `pass`, `partial`, `fail`, or `blocked`.
- `partial` and `fail` tasks have been routed back into task flow.
- `blocked` tasks have an Issue Bundle or an explicit triage note.

## Docs Sync Integrity

- Every path in `docs_must_update` was actually updated before closure.
- Index pages still describe the current workflow model.
- `Phase1-Tasks.md` remains a hub and not a live checkbox board.
- `AI-Handoff-Guide.md` and `Dashboard.md` still point to current workflow entry points.

## Issue Integrity

- Every non-trivial interrupt was recorded as an Issue Bundle.
- `P0` and `P1` issues have explicit triage decisions.
- Global issue index entries point to real issue files.
- Phase registry only includes issues that were explicitly attached to the phase.
- Every resolved or archived issue has consistent status across Issue Bundle, phase registry, and global index.

## Follow-Up Rule

- If any checklist item fails, create or update an Issue Bundle.
- Do not silently patch the process without recording the governance failure.
