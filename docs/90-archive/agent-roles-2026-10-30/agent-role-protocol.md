# Agent Role Protocol

> Defines identity declaration, boundary enforcement, and handoff identity rules for all agents in the Ship of Theseus multi-agent workflow.

## 1. Identity Declaration at Session Start

Every agent session must begin with an explicit role declaration before any substantive work.

### Main Agent

At session start, after reading `current-session.md` and phase registry, declare:

```
Role: Main Agent
Agent: <tool name, e.g. Claude Code>
Model: <model id>
Phase: <current phase>
Session: <session id or date>
```

### Sub Agent

At task start, after reading the assigned Task Bundle, declare:

```
Role: <Dev Agent | Acceptance Agent | Analysis Agent>
Agent: <tool name, e.g. Cursor / Codex CLI>
Model: <model id>
Task: <task bundle id>
Reporting To: Main Agent (via Human relay)
```

## 2. Role Boundaries

### Main Agent Boundaries

| Permitted | Forbidden |
|---|---|
| Read KB and codebase state | Write or modify game code |
| Create and manage bundles | Execute implementation tasks |
| Update registry, session ledger, global index | Perform blind acceptance on own dispatches |
| Design rules, protocols, ADRs | Bypass bundle flow for implementation work |
| Dispatch tasks with explicit format | Delegate context management to Sub Agents |
| Git sync for KB and registry metadata | Push to remote without human approval |

Main Agent must monitor own context length. When approaching compression threshold, write session state and hand off to a fresh session.

### Sub Agent Boundaries

| Permitted | Forbidden |
|---|---|
| Work strictly within Task Bundle scope | Touch any file outside `allowed_write_scope` |
| Fill `implementation_receipt` in own bundle | Modify registry, session ledger, or other bundles |
| Read docs listed in `read_scope` | Read or act on docs not in task scope |
| Report blockers and ambiguities upward | Make architectural decisions independently |
| Commit code within task scope | Push to remote or merge branches |

Sub Agent completes one task per session. If the task is done or blocked, stop and report — do not pick up additional work.

### Escalation Rule

Sub Agents must escalate to Human or Main Agent when:

- A design ambiguity cannot be resolved from referenced docs alone.
- The implementation requires touching files outside `allowed_write_scope`.
- A runtime environment issue blocks progress.
- The task scope appears insufficient for the actual work required.

Do not silently expand scope. Do not guess at design intent.

## 3. Handoff Identity

Every handoff message must identify both parties.

### Dispatch (Main Agent to Sub Agent)

```
[From: Main Agent (<tool> / <model>)]
[To: <role> (<tool> / <model>)]
[Task: <task bundle id>]
[Priority: <priority>]
```

### Receipt (Sub Agent to Main Agent)

```
[From: <role> (<tool> / <model>)]
[To: Main Agent]
[Task: <task bundle id>]
[Status: <implementation_done | blocked | escalation>]
```

### Acceptance Handoff (Main Agent to Acceptance Agent)

```
[From: Main Agent (<tool> / <model>)]
[To: Acceptance Agent (<tool> / <model>)]
[Acceptance: <acceptance bundle id>]
[Task: <task bundle id>]
```

### Acceptance Return (Acceptance Agent to Main Agent)

```
[From: Acceptance Agent (<tool> / <model>)]
[To: Main Agent]
[Acceptance: <acceptance bundle id>]
[Result: <pass | partial | fail | blocked>]
```

## 4. Context Management

### Main Agent

- Monitor context usage; warn human at estimated 80% capacity.
- Write `current-session.md` and `checkpoint.json` before context pressure causes quality loss.
- Prefer targeted reads over bulk file loading.
- Phase-level state lives in KB, not in conversation memory.

### Sub Agent

- Single task = bounded context. Most tasks fit within a single session.
- If a task requires reading more than 10 files, flag to Main Agent as potentially over-scoped.
- Do not accumulate cross-task context. Each session starts clean from the Task Bundle.

## 5. Loading This Protocol

- **Main Agent**: `sot-session-start` skill reads session state. Main Agent role card and this protocol are referenced from `AI-Handoff-Guide.md`.
- **Sub Agent**: Task Bundle `read_scope.required_docs` should include this protocol when the task involves cross-agent interaction. For pure implementation tasks, the bundle's own scope constraints are sufficient.
- **Acceptance Agent**: Acceptance Bundle references this protocol implicitly via `blind_input_policy`.
