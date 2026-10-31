# Script Entry Points

## Purpose

Project-level wrappers use the vault root two levels up, which is the game repository's docs/ (SOT_KB_ROOT is retired). Shared legacy generators are optional; current workflow enters through the game repository AGENTS.md. See agent-runtime-layout.md for the layout.

## Wrapper Files

- `new-task-bundle.ps1`
- `new-acceptance-bundle.ps1`
- `new-issue-bundle.ps1`

## Shared Tool Root

- `$HOME/.agents/ship-kb-tools/` (optional legacy generators; invoke only when installed)

## Usage

- `powershell -File 90-archive/task-system-legacy/Scripts/new-task-bundle.ps1 -PhaseId P1 -Track SKILL -Sequence 2 -Title "Example"`
- `powershell -File 90-archive/task-system-legacy/Scripts/new-acceptance-bundle.ps1 -PhaseId P1 -Track SKILL -Sequence 2`
- `powershell -File 90-archive/task-system-legacy/Scripts/new-issue-bundle.ps1 -Sequence 2 -Title "Example" -Summary "Example summary"`

## Rules

- Reusable logic belongs in the shared user-level tool root.
- Project-level wrappers must only supply project defaults and stable paths.
- Do not place reusable automation into sandbox-specific temp directories.

## 目录索引

| 文档 | 状态 | 说明 |
|---|---|---|

非 Markdown 附件：`new-acceptance-bundle.ps1`、`new-issue-bundle.ps1`、`new-task-bundle.ps1`。
