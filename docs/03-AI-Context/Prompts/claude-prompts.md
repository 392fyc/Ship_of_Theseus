# Claude Dedicated Prompt Library

> High-frequency prompt templates for Claude Pro, saving token consumption.

---

## Session Start - Relay Mode
```
Read `03-AI-Context/Active-Context/current-session.md` from Obsidian,
understand current project progress, then continue with: [specific task]
```

## Design Discussion - Write to Doc
```
We just discussed and confirmed the following: [summary]
Please use the patch_content tool to organize the above conclusions and write them
into the [section name] section of `01-Game-Design/[document-path].md` in Obsidian.
```

## Session End - Update Progress
```
This session is about to end. Please use the patch_content tool to update
`03-AI-Context/Active-Context/current-session.md`,
recording today's progress, confirmed decisions, and next actions.
```

## Talent Tree Design Dedicated
```
Referencing the existing framework in `01-Game-Design/Characters/talent-tree.md`,
design the Talent Tree for [class name]. Requirements:
- Node count: [X] nodes
- Branch count: [Y] branches
- Ultimate form: [description]
Write to the corresponding section of the document when done.
```

## System Audit Dedicated
```
Read all documents under `01-Game-Design/Core-Systems/`,
check for numerical or logical conflicts between the following systems: [system list]
Record any issues found in a new document under `02-Development/Decisions/`.
```
