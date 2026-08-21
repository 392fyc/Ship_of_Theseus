# Portable task, evidence, and receipt contract

This contract defines the minimum information exchanged between an orchestrator,
an implementation worker, and independent reviewers. A project may add fields or
stricter gates, but it must not silently weaken these requirements.

Project rules are stricter than a generic orchestration skill when the two
differ. The project rules govern the task.

## Authority order

Interpret acceptance sources in this descending order:

1. project safety, single-writer, and destructive-operation contracts;
2. the frozen ReviewBundle;
3. specification sections referenced by the ReviewBundle;
4. the implementation receipt, which is only an evidence index;
5. progress ledgers and historical decisions, which govern only when the frozen
   ReviewBundle cites them by stable identifier.

Implementation self-assessment, concerns in a receipt, and reviewer scope
discoveries do not create acceptance criteria.

## Task bundle

Before implementation begins, record:

- `task_id` and a bounded `objective`;
- independently testable `acceptance_criteria`;
- `target_repository`, `target_branch`, and exact starting `target_head`;
- `allowed_write_paths` and `forbidden_paths`;
- governing `contracts`, each with a path or stable identifier and a concise
  `contract_summary` captured before the first write;
- required `verification_commands` and protected state that must remain unchanged;
- dependencies, known constraints, and escalation conditions.

The implementer must stop when the target HEAD, branch, or governing contract no
longer matches the bundle and the difference can affect the result.

## Frozen ReviewBundle

Before dispatch, validate the ReviewBundle with
`.codex/project/validate_harness_bundle.py`. It binds `task_id`,
`bundle_revision`, `target_head`, one `primary_deliverable`, `change_kinds`,
stable `acceptance_criteria`, `allowed_write_paths`, `forbidden_paths`,
`impact_cone`, `test_policy`, `max_repair_rounds`, and `bundle_sha256`.

Each acceptance criterion must name a finite, non-empty `paths` and `cases`
matrix. The bundle becomes frozen after validation. Changing its revision,
digest, criteria, paths, impact cone, or test policy requires a new review
record; old evidence and ReviewResult records do not carry forward implicitly.

## Convergence gate

Do not dispatch a bundle with multiple independent primary deliverables, more
than one high-risk change kind, an unbounded criterion, convenience scope, or no
clear one-round endpoint. Split or redesign it first. High-risk change kinds are
`database_schema`, `data_migration`, `public_api`, `deployment`, and
`cross_repository_write`.

## Finding classification

Every finding records `id`, `criterion_id`, `introduced_by_candidate`,
`in_scope`, `severity`, `category`, `disposition`,
`directly_caused_by_remediation`, `evidence`, and `correction` as defined by
`review-result.schema.json`.

Only these findings may use the `blocking` disposition:

- a failure of a frozen criterion identified by `criterion_id`;
- a candidate-introduced `public_regression`, `security`, `data_loss`, or
  `protected_scope` defect.

`minor`, `existing_issue`, `adjacent_risk`, `maintainability`,
`test_enhancement`, non-required test hardening, and scope discoveries are
`follow_up` by default. They remain visible but do not produce
`needs_changes`. Only `blocking` findings change the verdict.

## RemediationChecklist

After the `initial` review, freeze all blocking finding IDs into one
RemediationChecklist. The implementer may adopt only those IDs during the one
consolidated remediation. In `remediation` review, inspect only unresolved
checklist items, the repair diff, and its directly affected regression surface.
Do not add an ordinary blocking finding outside the checklist. A new blocking
finding is permitted only for a remediation-caused Critical breakage that
invalidates passing evidence or changes a new public interface.

`max_repair_rounds` must equal `1`. After the remediation review, any remaining
blocking work must end the current loop: split, redesign, or report the task.
Never begin a second open remediation round.

## Tiered verification

The ReviewBundle declares all three test tiers and any `full_triggers`:

- initial implementation runs `focused` and `affected` tests;
- remediation runs only reproduction and directly affected tests;
- after the RemediationChecklist closes, run `full` once.

Full evidence may be reused by immediately following acceptance only when
`candidate_head`, `dependency_fingerprint`, `test_config_fingerprint`, and
`environment_fingerprint` all match. If a declared full trigger changes, or
code changes after full evidence is collected, close the changes and collect
the required affected evidence before the one final full run.

## Evidence contract

Evidence is a reproducible observation, not an assertion. Each item records:

- the acceptance criterion it supports;
- the command, test, file-and-line citation, or runtime request used;
- the observed result and exit status when applicable;
- the target HEAD or candidate revision on which it was collected;
- collection time when the underlying state is mutable;
- limitations, skipped checks, and whether the result is direct evidence or an
  explicitly labelled inference.

Sensitive matches, credentials, and private content must never be copied into a
receipt. Report their category, affected scope, and disposition instead.

## Implementation receipt

Return a machine-readable object with at least these fields:

```json
{
  "task_id": "stable identifier",
  "status": "completed|blocked|failed",
  "target_repository": "logical repository identity",
  "target_branch": "assigned task branch",
  "target_head_before": "full commit identifier",
  "candidate_head": "full commit identifier or null for an uncommitted candidate",
  "bundle_revision": 1,
  "bundle_sha256": "lowercase SHA256 of the frozen ReviewBundle",
  "contract_summary": [
    {"contract": "path or identifier", "summary": "governing points"}
  ],
  "changed_files": ["repository-relative path"],
  "verification": [
    {"command": "reproducible command", "result": "pass|fail|skipped", "evidence": "concise observation"}
  ],
  "criteria_evidence": [
    {"criterion": "criterion text", "result": "pass|fail|partial", "evidence": ["citation or command result"]}
  ],
  "protected_state": [
    {"subject": "protected path or repository", "result": "unchanged|changed|unverified", "evidence": "concise observation"}
  ],
  "follow_up_findings": [],
  "accepted_risks": [],
  "residual_risks": [],
  "escalation_reason": null
}
```

Use repository-relative paths and logical repository identities. Do not store
local absolute paths, secrets, tokens, service ports, or transient process state.

## Review and acceptance

Implementation review checks the exact candidate diff in either `initial` or
`remediation` mode and returns a schema-valid ReviewResult bound to the frozen
`bundle_revision` and `bundle_sha256`. Acceptance is a later blind pass against
the frozen bundle and receives no implementation reasoning. Both must state the
exact candidate reviewed and provide fresh or validly reused evidence for their
verdict.

Completion requires all criteria to pass, required verification to succeed, the
receipt to be complete, protected state to remain unchanged, and every blocking
finding to be resolved. Follow-up findings and accepted risks remain visible but
do not fail acceptance. A blocked or skipped check remains visible in the final
receipt and cannot be converted into a passing claim.
