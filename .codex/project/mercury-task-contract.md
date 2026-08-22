# Portable task card and receipt

Use one task card for one primary deliverable. It is a portable boundary for a
Main agent, an implementation worker, and one independent reviewer. Project
contracts override this generic card where they are stricter.

## Task card

Before work starts, the Main agent records:

- one bounded objective and one primary deliverable;
- target repository, target branch or worktree, and exact starting HEAD;
- allowed write paths and forbidden paths;
- governing contracts, with a short summary of each;
- adjacent problems explicitly not handled by this task;
- size: `S`, `M`, or `L`; and a sub-agent budget level. Main agents never set a
  token budget. The level is qualitative: `S` is local, `M` is one clear
  multi-file deliverable, and `L` is an unsplittable complex core problem;
- no more than three observable acceptance conditions;
- focused verification commands, plus the conditions that require affected or
  full verification; and
- whether one consolidated correction is allowed after the reviewer reports
  blocking work.

The card is a boundary, not a backlog. The worker stops and reports to the Main
agent when the work exceeds its declared size, needs another deliverable,
requires more write paths, or conflicts with a governing contract. A reviewer
finding, test discovery, or adjacent concern does not automatically expand the
task. The Main agent must split or issue a new card when scope changes.

## Verification and review

Run focused verification by default. Run affected verification only when the
task card says that the change reaches a named dependent surface, and run full
verification only when the card's explicit full-test condition is met (for
example, a shared framework, migration, public interface, or release change).
Do not run broader tests merely for reassurance.

After implementation, one independent, read-only reviewer checks the exact
candidate against this card and the governing contracts. The reviewer may
report at most three current-scope blockers. If correction is allowed, the
worker makes at most one consolidated correction, restricted to those blockers,
then returns the result for the Main agent to close or split. There is no
automatic second correction cycle. A high-risk small framework task may define
its own blind acceptance check; it is not a global requirement.

## Minimal implementation receipt

Return a concise machine-readable object containing:

```json
{
  "task_id": "stable identifier",
  "status": "completed|blocked|failed",
  "target_repository": "logical repository identity",
  "target_branch": "assigned branch",
  "target_head_before": "full commit identifier",
  "candidate_head": "full commit identifier or null",
  "contract_summary": [{"contract": "path or identifier", "summary": "governing points"}],
  "changed_files": ["repository-relative path"],
  "verification": [{"command": "command", "result": "pass|fail|skipped", "evidence": "observation"}],
  "criteria_evidence": [{"criterion": "observable condition", "result": "pass|fail|partial", "evidence": ["citation or result"]}],
  "protected_state": [{"subject": "protected scope", "result": "unchanged|changed|unverified", "evidence": "observation"}],
  "residual_risks": [],
  "escalation_reason": null
}
```

Use repository-relative paths. Record fresh evidence, including failed or
skipped checks, without secrets or local machine details. The worker supplies
evidence but never approves its own delivery.
