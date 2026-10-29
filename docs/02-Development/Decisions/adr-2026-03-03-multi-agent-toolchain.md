# ADR-007: Multi-Agent Toolchain Optimization

- Status: Approved
- Date: 2026-03-03
- Context: Optimize SOT development workflow across multiple AI agents, MCP servers, skills, and automation hooks

---

## Decision Summary

Establish a structured multi-agent ecosystem with clear role boundaries, shared knowledge base, automated workflow hooks, and reusable skill system. Six modules cover the full optimization scope.

---

## Module A: Agent Ecosystem Matrix

### Roles

| Agent | Role | Core Strength |
|-------|------|---------------|
| Claude Code | Main Agent - primary | Orchestration, design, KB management, dispatch instructions |
| AntiGravity | Main Agent - backup | Manager Surface for multi-agent orchestration, Gemini 3.1 Pro, asset work |
| Cursor | Sub Agent - development | IDE integration, Godot MCP exclusive, Playground WYSIWYG, GDScript implementation |
| Codex CLI | Sub Agent - development + research | Terminal native, sandbox isolation, batch ops, GPT-5.3-Codex, codebase research |
| AntiGravity (Gemini) | Sub Agent - assets + research | Animation/music asset generation via Gemini 3.1 Pro or web plugins (nanoBanana etc.) |

### Main Agent Boundaries

- NO large-scale file rewrites
- NO direct project code modifications
- NO self-spawning Sub Agents via tools — "dispatch to Sub Agents" means instructing external tools (Cursor, Codex CLI, AntiGravity), not spawning Claude internal agents
- Dispatch only: design, plan, review, KB management, issue instructions to human operator for relay to Sub Agents
- Backup activation: when Claude subscription quota is tight, AntiGravity takes over orchestration

### Task Assignment Principles

| Task Type | Assigned To | Reason |
|-----------|-------------|--------|
| GDScript implementation | Cursor | IDE integration, Godot MCP exclusive access |
| Godot editor interaction / debugging | Cursor | Only agent connected to Godot MCP (single-client constraint) |
| Playground visual proposals | Cursor | WYSIWYG in Godot editor |
| Batch JSON generation, script migration | Codex CLI | Sandbox safety, GPT-5.3-Codex, good at large batch changes |
| Codebase research, analysis | Codex CLI or AntiGravity | Avoid burning Claude token budget on large file reads |
| Game asset creation (sprites, animation, music) | AntiGravity (Gemini 3.1 Pro) or Gemini web + plugins | Gemini multimodal strength; nanoBanana or similar plugins for animation/audio |
| Parallel independent tasks | AntiGravity | Native support for 5 concurrent agents |

---

## Module B: Godot MCP Integration

### Source

Repository: https://github.com/satelliteoflove/godot-mcp
Package: @satelliteoflove/godot-mcp (npm, v2.15.0+)

### Technical Spec

| Item | Detail |
|------|--------|
| Install method | Install npm package globally or via npx; copy `addons/godot_mcp` to project `addons/` dir; enable plugin in Project Settings - Plugins |
| Protocol | stdio transport (Claude Code <-> MCP Server via stdio); Godot addon communicates via WebSocket on port 6550 |
| Capabilities | 40+ tools: scenes, nodes, scripts, resources, filesystem, debugging, TileMap, physics, navigation, audio, UI, signals |
| Cleanup | No cleanup needed; this is the correct package. Re-install if previously uninstalled. |

### Agent Configuration

| Agent | Config Method |
|-------|--------------|
| Claude Code | Add MCP server config to `.mcp.json` in project root (stdio type, command: npx, args: ["-y", "@satelliteoflove/godot-mcp"]) |
| Cursor | One-click config button from the plugin panel |
| Codex CLI | CLI command config provided by the plugin |
| AntiGravity | Manual HTTP MCP endpoint config |

### Degradation Strategy

When Godot editor is not running, MCP calls return connection failure. Agents must gracefully skip Godot-related operations without blocking other workflows.

### Single-Client Constraint

Godot MCP does not support multiple simultaneous clients. Only ONE agent may connect at a time.

- **Exclusive client**: Cursor
- All other agents (Claude Code, Codex CLI, AntiGravity) must NOT connect to Godot MCP
- When Godot editor interaction is needed, delegate to Cursor
- Claude Code `.mcp.json` retains the godot-mcp config for reference, but Claude Code should not actively use it during Cursor sessions

---

## Module C: Web Research Workflow

### Research Task Levels

| Level | Trigger | Boundary Rules | Example |
|-------|---------|----------------|---------|
| L1 Precise Query | Clear target: version, API usage, specific tool | Max 3 searches, stop on find | "Godot 4.6 TileMap API", model version check |
| L2 Directed Survey | Clear scope: asset search, solution comparison | Max 5 searches + 3 page fetches, must output structured comparison table | "itch.io GBA-style sprite packs, commercial license" |
| L3 Open Research | Broad scope: competitive analysis, design reference | Must define deliverable format + termination criteria, Main Agent approval required before execution | "TRPG turn order UI design references" |

### Convergence Rules - All Agents

Every research task must include:
1. **Objective**: What specific question to answer
2. **Deliverable**: Output format - table, list, or conclusion
3. **Termination criteria**: When to stop searching
4. **Upper bound**: Max search count + max page fetch count

Research tasks without termination criteria must be rejected. Agent must request Main Agent to supplement before executing.

### Version Query Rule - All Agents

Any operation involving version numbers:
1. WebSearch for latest version first
2. Cross-verify with at least 2 sources or official page
3. Only then may reference the version in subsequent work

Applies to: AI models, engine versions, SDK versions, plugin versions.

---

## Module D: Hooks Automation

### Hook 1: PreCompact - Force Session State Save

| Field | Value |
|-------|-------|
| Event | PreCompact |
| Type | prompt |
| Purpose | Last chance to save session state before context compression |

```json
{
  "PreCompact": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "prompt",
          "prompt": "Context is about to be compacted. You MUST use /sot-session-end to save current session state to KB before compaction proceeds. Skip only if no substantive work was done this session."
        }
      ]
    }
  ]
}
```

### Hook 2: sot-session-end Skill Enhancement

Not a hook but a skill upgrade. Add a new step to the existing `sot-session-end` skill:

**New step**: After writing session state, automatically compare completed work against `Phase1-Tasks.md` checkbox states. If discrepancies found, sync checkboxes to match actual completion status.

This ensures KB task sync happens whenever session-end is triggered, whether manually or via PreCompact hook.

### Rejected Alternative

Stop hook with prompt check on every response: rejected due to excessive token overhead with no proportional benefit.

---

## Module E: Git Management Rules

### Branch Strategy

```
develop (main dev branch)
  +-- feature/phase1-impl (long-running feature branch)
        +-- cursor/pkg-e-battle-ui (Cursor work branch)
        +-- codex/batch-json-gen (Codex CLI work branch)
        +-- ag/parallel-task-xxx (AntiGravity work branch)
  +-- fix/conflict-resolution-xxx (neutral merge branch)
```

### Rules

| Rule | Detail |
|------|--------|
| No PR | Personal work merges directly to feature branch, no PR process |
| Sub Agent isolation | Each Sub Agent task creates independent branch or worktree, named `{agent}/{task-name}` |
| Parallel safety | Different Agents never work on the same branch |
| Merge authority | Sub Agent notifies Main Agent on completion; Main Agent decides merge timing |
| Conflict resolution | Independent session only. Never use conflicting Agents. New session pulls both branches, neutral merge, review, then merge to target |
| Worktree cleanup | Merge executor responsible for cleaning up worktrees after merge |

### Conflict Resolution Flow

```
Sub Agent A (branch: cursor/pkg-e) ---+
                                       +--> New Session (neutral) --> review --> merge to feature/phase1-impl
Sub Agent B (branch: codex/pkg-d) ---+
```

---

## Module F: Cross-Agent Skill System

### Skill Repository Structure in KB

```
ShipOfTheseus-KB/03-AI-Context/Skills/
  +-- universal/                         (rules for ALL agents)
  |     +-- version-check.md
  |     +-- web-research.md
  |     +-- git-workflow.md
  +-- claude-code/                       (Claude Code specific)
  |     +-- sot-session-start.md
  |     +-- sot-session-end.md
  |     +-- sot-kb-write.md
  +-- cursor/                            (Cursor specific)
  |     +-- playground-build.md
  |     +-- godot-implementation.md
  +-- codex/                             (Codex CLI specific)
        +-- batch-data-gen.md
```

### Sync Mechanism

| Source of Truth | Distribution Target | Method |
|-----------------|---------------------|--------|
| KB `Skills/universal/` | `.claude/skills/`, `.cursorrules`, `AGENTS.md` | Main Agent manual sync or Sub Agent task |
| KB `Skills/claude-code/` | `.claude/skills/` | Direct reference |
| KB `Skills/cursor/` | `.cursor/rules/` | Convert to `.mdc` format |
| KB `Skills/codex/` | `AGENTS.md` | Append to relevant section |

### New Skill Creation Flow

1. Sub Agent discovers reusable pattern during task execution
2. On task completion, Main Agent reviews and decides whether to extract as skill
3. Write to KB source of truth, then distribute to corresponding Agent configs

### Context7 Integration

Not a separate module. Added as a universal rule:

"When uncertain about Godot API usage, query Godot 4.6 official docs via Context7. Never guess based on training data."

---

## Implementation Priority

| Priority | Item | Effort |
|----------|------|--------|
| P0 | Godot MCP addon install + connection test | Sub Agent task, ~1 session |
| P0 | PreCompact hook configuration | Small config change |
| P0 | sot-session-end skill enhancement for KB sync | Skill file edit |
| P1 | Universal skills creation in KB (version-check, web-research, git-workflow) | Sub Agent task |
| P1 | Cursor/Codex skill distribution + config sync | Sub Agent task |
| P2 | AntiGravity Main Agent backup protocol doc | When AntiGravity is set up |
| P2 | Full agent config matrix tested end-to-end | Integration test |

---

*Approved: 2026-03-03 | Modules A-F confirmed by human controller*
