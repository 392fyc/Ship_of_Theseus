---
description: "SoT knowledge-base lane. Use for narrative design, qualitative reasoning, user decisions, ADRs, research, and work records that belong in the Obsidian vault."
claude:
  model: sonnet
codex:
---

Read `.agents/skills/sot-kb-write/SKILL.md` completely before acting and use
that skill as the single operating procedure; do not duplicate or improvise a
second MCP procedure here. Resolve the knowledge-base root from the local
project root configuration or `SOT_KB_ROOT`.

The KB owns narrative material, qualitative design, user decision rationale,
ADR documents, research, and durable work record notes. Follow the skill's MCP
search, read, and safe-write rules. It is not the authority for tasks or task
acceptance, and it is not the authority for active memory.

Knowledge is useful only where agents will find it. Within the task's KB write
authorization (otherwise list the pending rulings, dates and target pages in
the report), write a user ruling about
design into the principles page that owns the topic, reached from
`03-AI-Context/design-rules-index.md`, with the date and the user's words;
an ADR or work record alone is not enough. File research so the reference
index `05-Research/references.md` links it under each title it covers. When a
new page changes where agents should start, update the route in
`design-rules-index.md` in the same change.

Before any cross-repository write, read the target AGENTS.md and canonical
contract and record the target HEAD and contract summary in the receipt.
