# Tool Handoff Template

> Fill this template from Mercury `.mercury/memory` and GitHub/Git evidence, then paste the startup instruction into the next tool.
> Goal: provide only the current state needed to continue without follow-up context questions.

---

## Handoff Summary

- **Date**: {{date}}
- **From**: {{from_tool}} (Claude / Cursor / Codex / Antigravity)
- **To**: {{to_tool}}
- **Reason**: {{reason}} (context limit / task type change / end of day / other)

---

## Current Task Status

**Current objective**:
{{current_task_description}}

**Current confirmed conclusions**:
- {{conclusion_1}}
- {{conclusion_2}}

**Open work**:
- {{todo_1}}
- {{todo_2}}

## Critical Context - Required Reading

**Mercury active-memory anchor**:
- `.mercury/memory/{{current_anchor}}`

**GitHub/Git task and acceptance evidence**:
- {{issue_branch_commit_or_acceptance_link}}

**Necessary ADR, Research, archive, or design links**:
- `{{evidence_path_1}}`
- `{{evidence_path_2}}`

**Real outstanding issues / known bugs**:
- {{issue_1}}

## Startup Instructions for Next Tool

> Copy the following and paste to {{to_tool}} as the first message:

```
Read the current Mercury active-memory anchor:
- .mercury/memory/{{current_anchor}}

Use GitHub/Git for task, progress, and acceptance state:
- {{issue_branch_commit_or_acceptance_link}}

Read only these necessary evidence sources:
- {{evidence_path_1}}

Current confirmed conclusions:
- {{conclusion_1}}

Real open issues:
- {{issue_1}}

Continue with:
- {{todo_1}}
```

- [ ] The startup instruction contains only current conclusions, real open issues, next actions, and necessary evidence links.

## How to Use

1. Replace the `{{}}` placeholders from the current Mercury anchor and GitHub/Git evidence.
2. Remove empty fields and any superseded, rejected, deleted, or completed process details.
3. Paste "Startup Instructions for Next Tool" into the new tool.
4. Update Mercury active memory if the current state changed; record task and acceptance state in GitHub/Git.

---

*Template version: v2.0 · 2026-08-23*
