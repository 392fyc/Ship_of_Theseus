# Harness Engineering Survey

## 1. Executive Summary

- This survey compares two primary sources: Anthropic's [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) and OpenAI's [Harness Engineering: leveraging Codex in an agent-first world](https://cookbook.openai.com/articles/harness_engineering_for_codex).
- The strongest shared message is that long-running agent systems fail when state lives mainly in chat history. Durable external artifacts are the harness.
- For SoT, the practical split is: markdown for human-readable guidance and plans, JSON for machine-updated checkpoints and mutable run state.
- Neither article makes YAML the preferred format for live agent state. This recommendation is an inference from Anthropic favoring JSON scratchpads and OpenAI favoring markdown interfaces.
- Context budget is best preserved by reducing re-explanation costs: external task ledgers, repo legibility, short root instructions, and frequent handoff summaries.
- Anthropic contributes the stronger patterns for pause-safe execution, context resets, and recovery from blocking events.
- OpenAI contributes the stronger patterns for making the repo itself legible to agents: clear file layout, obvious commands, short `AGENTS.md`, linked deeper docs, and deterministic harness surfaces.
- SoT already has good primitives: `AGENTS.md`, `current-session.md`, task bundles, acceptance bundles, issue bundles, and a KB authority model.
- The main gap is not missing process objects; it is state shape. Current state is mostly human-readable markdown/YAML, but not yet optimized for frequent machine checkpointing and low-cost sub-agent resumption.
- Highest-value next move: keep the existing governance model, but add a machine-readable checkpoint layer and stricter sub-agent handoff contracts.
- Second-highest move: shrink root instructions into a table-of-contents style interface and push operational detail into linked docs.
- Third-highest move: formalize a pause/resume protocol for blocked tools, permission edges, and long research or implementation runs.
- The recommended direction is an agent-first mixed-format system, not a single-format standard.

## 2. Pattern Catalog

| Pattern | Source Article | Description | SoT Applicability (1-5) | Adaptation Notes |
|---|---|---|---:|---|
| Split artifacts by readership | Both articles; format recommendation is an inference | Keep human-facing instructions and plans in markdown, but store mutable execution state in stricter machine-readable files. Anthropic explicitly mentions JSON scratchpads; OpenAI emphasizes markdown as the interface layer. | 5 | Keep `AGENTS.md` and KB docs in markdown. Add JSON companions for checkpointable state such as dispatch progress, pause metadata, and resume tokens. Avoid using YAML for frequently rewritten scratch state. |
| External task ledger instead of prompt memory | Anthropic | Long runs are more reliable when the agent tracks tasks and subgoals outside the conversation context. | 5 | SoT already has task, acceptance, and issue bundles. Extend this with lightweight per-run checkpoint files so sub-agents do not need to reconstruct state from chat. |
| Repo legibility as context compression | OpenAI | The clearer the repo layout, commands, and document entry points, the less context the agent must spend on orientation each run. | 5 | Treat the repo and KB as the primary UI for agents. Keep file naming predictable, reduce hidden workflow knowledge, and keep command entry points obvious. |
| Short root instructions, deep linked docs | OpenAI | `AGENTS.md` should work as a concise table of contents, not as the place where every policy is repeated. | 5 | SoT's current `AGENTS.md` is informative but dense. Move operational detail into linked KB/runbook pages and keep the root file optimized for rapid agent bootstrapping. |
| Reset-and-handoff loops | Anthropic | When context grows, stop, summarize, persist state, and resume from a fresh context rather than carrying large histories forward. | 5 | Define a formal handoff artifact for long tasks and multi-turn sub-agent work. Reuse it across research, implementation, acceptance, and doc-sync steps. |
| Pause-safe checkpoints at blocking boundaries | Anthropic | Agents should save enough state before permission prompts, long-running tools, or likely interruptions so progress survives stalls. | 4 | Add a standard checkpoint before escalated shell commands, long research passes, and any handoff back to the Main Agent. |
| Deterministic harness surfaces | OpenAI | Agents work better when commands, outputs, and test paths are stable and unsurprising. Harness quality is partly operational determinism. | 4 | Standardize wrapper outputs, expected artifact names, and verification commands. Avoid hidden side effects and ambiguous command families. |
| Explicit sub-agent contracts | Both articles; coordination framing is an inference | Sub-agents should receive narrow objectives, explicit allowed writes, expected outputs, and a clear completion artifact. | 5 | SoT already has bundle-based governance. Tighten each dispatch with write scope, success evidence, checkpoint expectations, and resume semantics. |
| Separate implementation from review/cleanup | Anthropic, with supporting alignment from OpenAI's emphasis on legibility | Long runs benefit from a distinct review/synthesis pass instead of assuming the implementation pass leaves clean state behind. | 4 | Preserve SoT's acceptance lane and consider a lightweight final synthesis checklist for research and design work as well as code work. |
| Artifact-first recovery over chat replay | Both articles | Recovery should start from durable artifacts, logs, and summaries rather than replaying long chat transcripts. | 5 | Prefer restoring from `current-session`, bundle artifacts, and future checkpoint JSON over asking a successor agent to infer history from conversation text. |

### Mapping to the Four Axes

| Axis | Key Takeaway |
|---|---|
| AXIS-1: Agent-first document format | Use markdown for instructions, plans, and navigation; use JSON for volatile machine state; avoid YAML for frequently rewritten scratch state. |
| AXIS-2: Context window budget management | Externalize task state, shorten root docs, make the repo legible, and normalize summary-based resets. |
| AXIS-3: Task dispatch and state persistence | Dispatch through narrow contracts and persist pause/resume checkpoints at defined boundaries. |
| AXIS-4: Harness design for sub-agent coordination | Coordinate through artifacts with clear authority, explicit write scope, and completion receipts instead of conversational relay. |

## 3. Recommended Actions

| Priority | Action | Axis | Effort | Impact | Notes |
|---|---|---|---|---|---|
| 1 | Add a machine-readable checkpoint companion to the current markdown session flow | AXIS-1, AXIS-2, AXIS-3 | M | H | Example scope: run id, task id, status, last completed step, blocked reason, next step, allowed writes, resume token, verification target. |
| 2 | Define a standard sub-agent handoff packet template | AXIS-3, AXIS-4 | M | H | Include objective, authority source, read set, write scope, expected artifacts, checkpoint cadence, and completion receipt format. |
| 3 | Refactor `AGENTS.md` into a short entry document with linked runbooks | AXIS-1, AXIS-2 | M | H | Keep project rules discoverable, but move long operational detail into linked docs so agent boot cost stays low. |
| 4 | Introduce mandatory pause/resume checkpoints before blocking operations | AXIS-2, AXIS-3 | L | H | Especially before approval-gated shell commands, long web research, or context-heavy synthesis tasks. |
| 5 | Standardize deterministic wrapper outputs and verification commands | AXIS-2, AXIS-4 | M | M | The harness should tell every sub-agent exactly how success is observed and where logs or receipts are written. |
| 6 | Add a final synthesis checklist for non-code work | AXIS-3, AXIS-4 | L | M | Research and design tasks should also produce cleanup-ready artifacts, not only code tasks. |

### Effort / Impact Matrix

| Impact \ Effort | Low Effort | Medium Effort |
|---|---|---|
| High Impact | Action 4 | Actions 1, 2, 3 |
| Medium Impact | Action 6 | Action 5 |

## 4. Inapplicable Patterns

| Pattern | Rationale for Exclusion |
|---|---|
| Single-format standard for every artifact | The two articles together point toward mixed-format harnesses. SoT already has distinct human and machine audiences, so forcing one format would reduce clarity. |
| Chat-history replay as the default recovery path | Both articles imply the opposite direction. For SoT, replaying long chats would be slower and less reliable than restoring from KB and bundle artifacts. |
| Fully autonomous long-running execution without governance checkpoints | Anthropic discusses longer autonomy, but SoT's Main Agent governance, acceptance lane, and issue triage make unrestricted background autonomy a poor fit. |
| Using git state as the primary execution ledger | Git is important, but SoT's authoritative workflow state lives in KB and bundle artifacts. Git alone does not encode task authority, acceptance, or issue triage. |

## 5. Open Questions for Main Agent

1. Should SoT keep `current-session.md` as the human ledger and add a parallel JSON checkpoint file, or replace the session artifact entirely with a dual-rendered system?
2. Which artifact should become the single source of truth for in-flight sub-agent execution state: task bundles, a new checkpoint file, or a future dispatch registry?
3. Where should volatile checkpoint artifacts live: KB, repo-local hidden directory, or the shared user-level automation root?
4. What checkpoint cadence is acceptable before the overhead outweighs the resilience benefit?
5. Should the same handoff protocol be used for research, implementation, acceptance, and doc-sync, or should research/design tasks get a lighter variant?
6. Is the current `AGENTS.md` expected to remain a full policy document, or is the project ready to move to a table-of-contents style root file?

## Source Notes

- Anthropic article accessed on 2026-03-10: [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- OpenAI article accessed on 2026-03-10: [Harness Engineering: leveraging Codex in an agent-first world](https://cookbook.openai.com/articles/harness_engineering_for_codex)
