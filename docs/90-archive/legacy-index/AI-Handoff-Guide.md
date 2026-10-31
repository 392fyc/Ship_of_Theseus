# AI Tool Handoff Guide

> This document defines the handoff workflow and authority routing for multi-AI collaboration.

## Agent Roles

Agent roles, boundaries, and delivery rules are defined by the repository-root `AGENTS.md` and `CLAUDE.md` and by the roles Mercury generates. The 2026-02 to 03 orchestrator role documents and their identity protocol were retired on 2026-10-30; see [[90-archive/agent-roles-2026-10-30/README|the archive]].

## Important Premise - MCP is Independent of Working Directory

Obsidian MCP is configured at user level and remains available even when the active workspace is the game code repository.

## Workflow Roles

| Role | Tool | Write Scope |
|---|---|---|
| Main Agent | Claude or equivalent | Coordinate work; update Mercury active memory and GitHub/Git task evidence |
| Dev Agent | Codex CLI / opencode / AntiGravity | Code, allowed docs, and Git evidence within assigned scope |
| Acceptance Agent | Independent review agent | Read-only verification plus acceptance evidence in GitHub/Git |
| Analysis Agent | AntiGravity / Codex CLI / opencode | Read-only analysis unless explicitly assigned a write scope |

KB remains the authority for narrative, qualitative design, user decisions, ADRs, research, and work records; it is not the authority for active memory or task status.

## Standard Handoff Sequence

1. Main Agent reads the current Mercury `.mercury/memory` anchor and the relevant GitHub/Git task evidence.
2. Main Agent dispatches the approved scope, acceptance criteria, authority links, and target branch.
3. Dev Agent changes only the assigned scope and records implementation evidence in Git.
4. An independent Acceptance Agent verifies the criteria and records acceptance evidence in GitHub/Git.
5. Main Agent updates Mercury active memory with only the current state and necessary evidence links.

## Mandatory Read Order

### Main Agent
1. Current Mercury `.mercury/memory` anchor
2. Relevant GitHub/Git issue, branch, commit, and acceptance evidence
3. Only the ADR, Research, archived record, or design documents required by the current task

### Dev Agent
1. Assigned task scope and acceptance criteria from GitHub/Git or the approved task brief
2. Current target branch and worktree state
3. Only task-referenced ADR and design documents

### Acceptance Agent
1. Acceptance criteria from the assigned GitHub/Git task or approved brief
2. Candidate diff, commit, and runtime environment
3. Only evidence and authority documents required by the criteria
4. Existing GitHub/Git verification records, if any

## Write Rules

| Role | Must Write | Must Not Write |
|---|---|---|
| Main Agent | Mercury active memory and GitHub/Git coordination evidence | Development code unless explicitly assigned |
| Dev Agent | Assigned code/docs and Git implementation evidence | Mercury memory, unrelated KB records, acceptance approval |
| Acceptance Agent | GitHub/Git acceptance evidence | Development code, Mercury memory, implementation history rewrites |

## Dispatch Requirements

Every new implementation dispatch must identify:

- target agent and model
- GitHub/Git task or approved brief
- target branch and allowed write scope
- acceptance criteria and required evidence
- necessary authority links

## Session Continuity Guard

Handoff 只携带当前已确认结论、真实未决问题、下一步和必要证据链接。已被取代、否决、删除或已经完成的过程不进入起始指令；需要追溯时只链接 ADR、Research、明确归档记录或 Git 证据。

Before switching tools or sessions:

1. Update the current Mercury `.mercury/memory` anchor.
2. Confirm task, progress, and acceptance state in GitHub/Git.
3. Produce a startup prompt containing only the current state described above.
