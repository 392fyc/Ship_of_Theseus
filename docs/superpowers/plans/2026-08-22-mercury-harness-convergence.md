# Mercury Harness Convergence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. The project-specific Mercury review contract defined by this plan overrides any generic multi-round review loop. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a project-local, machine-checkable task and review contract that freezes acceptance scope, permits one remediation round, and schedules full regression only after remediation closes.

**Architecture:** Two small layers share one contract. A standard-library Python validator and two JSON schemas enforce frozen ReviewBundle and ReviewResult structure; the Mercury task, developer, reviewer, and acceptance prompts define how people and agents use those records. The validator does not interpret prose and does not create a new task service.

**Tech Stack:** Markdown, TOML, JSON Schema documents, Python 3 standard library (`argparse`, `hashlib`, `json`, `tomllib`, `unittest`).

**Spec:** `dev_doc/mercury-harness-convergence-design-2026-08.md`

## Global Constraints

- Work only in the isolated branch `codex/harness-convergence` starting from spec commit `29ef4a1be3a9d71838e2d33673ddb51e72e96266`.
- Do not modify Ship gameplay code, data, scenes, assets, KB, design-library files, production systems, or third-party plugin caches.
- The task bundle has exactly one `primary_deliverable` and `max_repair_rounds` must equal `1`.
- A task containing more than one high-risk change kind is rejected. High-risk kinds are `database_schema`, `data_migration`, `public_api`, `deployment`, and `cross_repository_write`.
- Only a frozen criterion failure or a candidate-introduced public regression, security defect, data-loss defect, or protected-scope violation may be blocking.
- Minor, existing, adjacent, maintainability, and non-required test-hardening findings are follow-up work.
- Initial implementation runs focused and affected tests. A remediation runs only reproduction and directly affected tests. Full regression runs once after remediation closes.
- One remediation review is the end of the current task loop. Remaining blocking work must be split, redesigned, or reported; it must not start a second open repair round.
- Use repository-relative paths in records. Never write secrets, credentials, local roots, or transient runtime details to bundles or reviews.
- `bundle_sha256` is mandatory; review validation rejects a missing digest and never substitutes a digest computed during review.
- Repository path fields reject every `^[A-Za-z]:` drive prefix, including drive-relative Windows paths.

---

### Task 1: Machine-Checkable Bundle and Review Validation

**Files:**
- Create: `.codex/project/task-bundle.schema.json`
- Create: `.codex/project/review-result.schema.json`
- Create: `.codex/project/validate_harness_bundle.py`
- Create: `.codex/project/tests/test_validate_harness_bundle.py`

**Interfaces:**
- Produces: `bundle_digest(bundle: dict[str, object]) -> str`
- Produces: `validate_bundle(bundle: dict[str, object]) -> list[str]`
- Produces: `validate_review(review: dict[str, object], bundle: dict[str, object]) -> list[str]`
- Produces CLI:
  - `python .codex/project/validate_harness_bundle.py bundle PATH`
  - `python .codex/project/validate_harness_bundle.py review BUNDLE_PATH REVIEW_PATH`
- Exit `0` means valid. Exit `2` means invalid input or contract violation and prints one concise error per line to stderr.

- [ ] **Step 1: Write the failing validator tests**

Create `.codex/project/tests/test_validate_harness_bundle.py` with `unittest`. Define one valid bundle fixture containing:

```python
VALID_BUNDLE = {
    "schema_version": 1,
    "task_id": "example.task",
    "bundle_revision": 1,
    "target_head": "a" * 40,
    "primary_deliverable": "one bounded behavior",
    "change_kinds": ["harness_contract"],
    "acceptance_criteria": [
        {
            "id": "AC-1",
            "statement": "The bounded behavior is observable.",
            "paths": [".codex/project/example.json"],
            "cases": ["valid", "invalid"],
        }
    ],
    "allowed_write_paths": [".codex/project/example.json"],
    "forbidden_paths": ["data", "scripts"],
    "impact_cone": [".codex/project"],
    "test_policy": {
        "focused": ["python -m unittest focused"],
        "affected": ["python -m unittest affected"],
        "full": "python -m unittest discover",
        "full_triggers": ["dependency_change", "test_config_change"],
        "reuse_keys": [
            "candidate_head",
            "dependency_fingerprint",
            "test_config_fingerprint",
            "environment_fingerprint"
        ],
    },
    "max_repair_rounds": 1,
}
```

Tests must assert that `validate_bundle()` rejects:

- missing or duplicate criterion IDs;
- empty `paths` or `cases`;
- multiple values in `primary_deliverables` if that forbidden compatibility key appears;
- two high-risk change kinds;
- `max_repair_rounds != 1`;
- missing focused, affected, full, full triggers, or reuse keys;
- absolute paths and parent traversal in path fields;
- a stale `bundle_sha256`.

Define a valid initial review fixture. Tests must assert that `validate_review()`:

- accepts follow-up-only results with verdict `pass`;
- rejects Minor marked blocking;
- rejects `existing_issue`, `adjacent_risk`, `maintainability`, or `test_enhancement` marked blocking;
- rejects ordinary Important blocking without a frozen criterion ID;
- accepts candidate-introduced `public_regression`, `security`, `data_loss`, or `protected_scope` blocking without a criterion ID;
- requires `needs_changes` exactly when blocking findings exist;
- rejects bundle revision or digest mismatch;
- in `remediation` mode, rejects a new ordinary blocking finding outside `remediation_finding_ids`;
- in `remediation` mode, accepts a new candidate-introduced Critical caused directly by the remediation diff.

- [ ] **Step 2: Run the focused tests and preserve RED**

Run:

```powershell
python -m unittest discover -s .codex/project/tests -p "test_validate_harness_bundle.py" -v
```

Expected: import failure because `validate_harness_bundle.py` does not exist.

- [ ] **Step 3: Add the two JSON Schema documents**

`task-bundle.schema.json` must require every field shown in `VALID_BUNDLE`, plus `bundle_sha256`. Criterion items require `id`, `statement`, non-empty `paths`, and non-empty `cases`. `additionalProperties` is `false` at every owned object level.

`review-result.schema.json` must require:

```text
schema_version, task_id, bundle_revision, bundle_sha256, candidate_head,
review_mode, remediation_finding_ids, checks_performed, findings,
residual_risks, verdict
```

Each finding requires:

```text
id, criterion_id, introduced_by_candidate, in_scope, severity, category,
disposition, directly_caused_by_remediation, evidence, correction
```

Allowed values:

- severity: `critical`, `important`, `minor`
- category: `criterion_failure`, `public_regression`, `security`, `data_loss`, `protected_scope`, `existing_issue`, `adjacent_risk`, `maintainability`, `test_enhancement`, `evidence_invalidated`
- disposition: `blocking`, `follow_up`, `accepted_risk`
- review mode: `initial`, `remediation`
- verdict: `pass`, `needs_changes`, `blocked`

- [ ] **Step 4: Implement the validator**

Implement these constants and helpers in `.codex/project/validate_harness_bundle.py`:

```python
HIGH_RISK_CHANGE_KINDS = {
    "database_schema",
    "data_migration",
    "public_api",
    "deployment",
    "cross_repository_write",
}
NON_BLOCKING_CATEGORIES = {
    "existing_issue",
    "adjacent_risk",
    "maintainability",
    "test_enhancement",
}
DIRECT_BLOCKING_CATEGORIES = {
    "public_regression",
    "security",
    "data_loss",
    "protected_scope",
}
```

`bundle_digest()` computes SHA256 over compact UTF-8 JSON with sorted keys after removing `bundle_sha256` from a shallow copy.

`validate_bundle()` performs structural checks needed by the tests without importing `jsonschema`. It checks types strictly (`bool` is not an integer), unique IDs, safe repository-relative paths, exactly one repair round, at most one high-risk change kind, non-empty finite criteria cases, all three test tiers, required digest presence, and digest equality. Any `^[A-Za-z]:` drive prefix is unsafe.

`validate_review()` first calls `validate_bundle()`, then verifies task/revision/digest binding without temporary digest fallback, required `checks_performed` and `residual_risks`, finding IDs, criterion references, disposition rules and verdict consistency. In remediation mode, a blocking ID must be in `remediation_finding_ids`, except a new `critical` finding with `introduced_by_candidate=true` and `directly_caused_by_remediation=true`. Public regression, security, and data-loss exceptions require `in_scope=true`; `protected_scope` may block with `in_scope=false` because it represents crossing a protected boundary.

The CLI reads UTF-8 JSON, prints errors to stderr, and exits `2` on malformed JSON, missing files, or validation errors.

- [ ] **Step 5: Run focused tests**

Run:

```powershell
python -m unittest discover -s .codex/project/tests -p "test_validate_harness_bundle.py" -v
python -m py_compile .codex/project/validate_harness_bundle.py .codex/project/tests/test_validate_harness_bundle.py
```

Expected: all tests pass and compilation exits `0`.

- [ ] **Step 6: Commit Task 1**

```powershell
git add .codex/project/task-bundle.schema.json .codex/project/review-result.schema.json .codex/project/validate_harness_bundle.py .codex/project/tests/test_validate_harness_bundle.py
git commit -m "feat(harness): validate bounded review bundles"
```

### Task 2: Mercury Agent and Task Contracts

**Files:**
- Modify: `.codex/project/mercury-task-contract.md`
- Modify: `.codex/agents/mercury-dev.toml`
- Modify: `.codex/agents/mercury-reviewer.toml`
- Modify: `.codex/agents/mercury-acceptance.toml`
- Create: `.codex/project/tests/test_mercury_contracts.py`

**Interfaces:**
- Consumes: Task 1 ReviewBundle and ReviewResult fields and CLI.
- Produces: one authoritative precedence, review classification, one-round remediation, and tiered-test policy shared by all Mercury roles.

- [ ] **Step 1: Write contract consistency tests**

Create `.codex/project/tests/test_mercury_contracts.py` using `tomllib` and `unittest`. Tests load all three TOML agent definitions and the Markdown contract, then assert:

- every role names `bundle_revision` and `bundle_sha256`;
- developer instructions name `max_repair_rounds` and forbid adopting out-of-scope discoveries;
- reviewer instructions name both `initial` and `remediation` modes, every required finding field, and state that only `blocking` changes the verdict;
- reviewer instructions forbid adding ordinary blocking findings outside the remediation checklist;
- acceptance instructions state that follow-up findings do not fail acceptance;
- task contract defines the five-level authority order from the spec;
- task contract defines focused, affected, and full scheduling;
- task contract states one remediation round and requires split, redesign, or report afterward;
- none of the four contracts contains an instruction to run full regression during every repair round or to continue up to five repair rounds.

- [ ] **Step 2: Run the consistency tests and preserve RED**

Run:

```powershell
python -m unittest discover -s .codex/project/tests -p "test_mercury_contracts.py" -v
```

Expected: failures because the current contracts do not mention frozen bundles or convergence rules.

- [ ] **Step 3: Update the portable task contract**

Extend `.codex/project/mercury-task-contract.md` with these sections, using the exact field names from Task 1:

- `Authority order`
- `Frozen ReviewBundle`
- `Convergence gate`
- `Finding classification`
- `RemediationChecklist`
- `Tiered verification`
- `Review and acceptance`

Keep the existing evidence and receipt requirements. Add `follow_up_findings`, `accepted_risks`, `bundle_revision`, and `bundle_sha256` to the receipt example. State that project rules are stricter than a generic orchestration skill when the two differ.

- [ ] **Step 4: Update the three agent contracts**

`mercury-dev.toml`:

- require a validated ReviewBundle before writes;
- stop on bundle mismatch;
- run focused and affected tests for initial implementation;
- run only reproduction and directly affected tests during remediation;
- adopt only IDs in the fixed remediation checklist;
- never start a second remediation round.

`mercury-reviewer.toml`:

- require `initial` or `remediation` mode;
- return the structured fields required by `review-result.schema.json`;
- return non-empty `checks_performed` and required `residual_risks` on every verdict;
- bind each ordinary blocking finding to a frozen criterion;
- route existing, adjacent, maintainability, test-hardening, Minor and scope discoveries to follow-up;
- in remediation mode inspect only checklist items, the repair diff and directly affected regression surface;
- allow a new blocking item only for remediation-caused Critical breakage.
- allow remediation-caused `protected_scope` Critical findings with `in_scope=false`; other direct categories retain the `in_scope=true` requirement.

`mercury-acceptance.toml`:

- receive the frozen bundle rather than implementation reasoning;
- verify exact bundle revision and digest;
- treat follow-up and accepted risk as visible but non-failing;
- fail only a frozen criterion or direct candidate regression/safety/data/protected-scope breach;
- reuse full evidence only when all four reuse keys match.

- [ ] **Step 5: Run all harness tests and checks**

Run:

```powershell
python -m unittest discover -s .codex/project/tests -p "test_*.py" -v
python -m py_compile .codex/project/validate_harness_bundle.py .codex/project/tests/test_validate_harness_bundle.py .codex/project/tests/test_mercury_contracts.py
git diff --check
git status --short
```

Expected: all harness tests pass; compilation and diff check exit `0`; only the planned `.codex` files and this plan/spec are changed relative to `f2618db`.

- [ ] **Step 6: Commit Task 2**

```powershell
git add .codex/project/mercury-task-contract.md .codex/agents/mercury-dev.toml .codex/agents/mercury-reviewer.toml .codex/agents/mercury-acceptance.toml .codex/project/tests/test_mercury_contracts.py
git commit -m "feat(harness): enforce convergent review flow"
```

### Task 3: Independent Harness Acceptance

**Files:**
- No product files may change.
- A review receipt may be written only under an ignored temporary directory.

**Interfaces:**
- Consumes: exact branch diff `f2618db..HEAD`, the spec, plan, schemas, validator output, and test output.
- Produces: structured acceptance verdict with blocking and follow-up findings separated.

- [ ] **Step 1: Build a valid sample bundle and review pair in a temporary directory**

Use a temporary directory outside tracked paths. Populate one valid bundle, calculate its digest with `bundle_digest()`, then create:

- an initial ReviewResult containing only a Minor follow-up and verdict `pass`;
- a remediation ReviewResult whose only blocking ID is in `remediation_finding_ids` and verdict `needs_changes`.

Both ReviewResult records include non-empty `checks_performed` and required
`residual_risks`.

Run both through the CLI. Expected exit code is `0`.

- [ ] **Step 2: Run final harness verification once**

```powershell
python -m unittest discover -s .codex/project/tests -p "test_*.py" -v
python -m py_compile .codex/project/validate_harness_bundle.py .codex/project/tests/test_validate_harness_bundle.py .codex/project/tests/test_mercury_contracts.py
git diff --check
git status --short --branch
git diff --name-only f2618db..HEAD
```

No Godot gameplay regression run is required because the candidate changes only project-local harness documents, TOML prompts, JSON schemas, and a standalone Python validator. The inability to locate a Godot console on this machine remains recorded but is not converted into a harness failure.

- [ ] **Step 3: Dispatch one independent reviewer**

Provide only:

- objective and frozen acceptance criteria from this plan;
- baseline `f2618db` and candidate HEAD;
- changed-file list;
- raw harness test and CLI results;
- spec and exact diff.

The reviewer may perform one initial review. If blocking findings exist, freeze one RemediationChecklist, perform one consolidated repair, and run one incremental re-review. Any second expansion attempt ends this plan and is reported to the user.

- [ ] **Step 4: Record completion**

Completion requires:

- validator and contract tests passing;
- clean diff check;
- no gameplay/data/cross-repository files changed;
- independent review has no blocking finding;
- all follow-up findings are visible in the receipt.
