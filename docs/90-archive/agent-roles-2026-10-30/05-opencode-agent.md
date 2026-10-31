# opencode Agent - Parallel Code Implementation

> Tool: opencode (Go-based terminal AI agent)
> API: GitHub Copilot (Pro/Pro+)
> Models: Claude Opus 4.6 (design/UI), GPT-5.4 (code logic), GPT-5.3-Codex (batch/small)
> MCP: Godot MCP + Obsidian MCP
> Role: Parallel implementation agent, same level as Codex CLI
> Status: Active (since 2026-03-14)
> Replaces: GitHub Copilot CLI (retired)

---

## Role Definition

opencode is a parallel code implementation agent alongside Codex CLI. It can be dispatched simultaneously with Codex CLI on different tasks for dual-track parallel development.

### Strengths
- Multi-model flexibility: Claude Opus 4.6 for design-aware implementation, GPT for raw code logic
- MCP integration: Godot editor + Obsidian KB access
- TUI with session management and LSP integration
- Can handle both visual/UI and logic tasks depending on model selection

### Task Assignment Guidelines

| Task Type | Model | Priority vs Other Agents |
|---|---|---|
| GDScript implementation | GPT-5.4 | Equal to Codex CLI |
| UI/visual implementation | Claude Opus 4.6 | Secondary to AntiGravity |
| Design-to-code translation | Claude Opus 4.6 | Primary (Main Agent model parity) |
| Batch JSON generation | GPT-5.3-Codex | Equal to Codex CLI |
| Godot editor interaction | Any | Equal to Codex CLI / AntiGravity |

---

## Configuration

### Project Config
- `opencode.json` in project root
- `OPENCODE.md` as instructions file (auto-loaded via `instructions` config key)

### MCP Servers
- Godot MCP: absolute path to `addons/godot_mcp/godot_mcp_lazy_server.mjs`
- Obsidian MCP: via uvx mcp-obsidian, localhost:27123

### Authentication
- GitHub Copilot device flow (`/connect` in TUI)
- Credentials stored globally

---

## Dispatch Format

When dispatching a task to opencode, Main Agent provides:

```
[From: Main Agent (Claude Code / Claude Opus 4.6)]
[To: Dev Agent (opencode / <model>)]
[Task: <task bundle id>]
[Priority: <priority>]

<task prompt with full context>
```

### Prompt Must Include
1. Task Bundle path (KB or inline)
2. Required reading docs
3. Code scope boundaries
4. Definition of Done items
5. Branch name: `opencode/{task-name}`
6. Explicit constraints from OPENCODE.md

---

## Boundary Summary

| Permitted | Forbidden |
|---|---|
| Write code within `allowed_write_scope` | Touch registry, session, acceptance bundles |
| Fill own Task Bundle `implementation_receipt` | Modify other task bundles |
| Read KB docs via Obsidian MCP | Write to KB outside own bundle |
| Use Godot MCP for editor interaction | Push to remote |
| Commit on isolated branch | Operate on develop/main branches |
| Escalate ambiguities upward | Silently expand scope |

---

## Relationship to Other Agents

| Agent | Relationship |
|---|---|
| Codex CLI | Peer (parallel implementation, different tasks simultaneously) |
| AntiGravity | Peer (AntiGravity primary for visual, opencode secondary) |
| Claude Code Main Agent | Reports to (via human relay) |

---

*Created: 2026-03-14 | Agent version: opencode v1.2.26*
