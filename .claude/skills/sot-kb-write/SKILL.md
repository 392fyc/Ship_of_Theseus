---
name: sot-kb-write
description: "Reliably write to the Ship of Theseus Obsidian knowledge base. Use this skill whenever you need to create, update, patch, or append content to any KB document in the Obsidian vault. This skill provides a decision tree for choosing the most reliable write method based on the operation type, avoiding known failure modes with obsidian_patch_content and PowerShell. Trigger whenever writing to ShipOfTheseus-KB, updating design docs, creating ADRs, or modifying any markdown file in the vault."
---

# SOT KB Write

Reliable write operations for the Ship of Theseus Obsidian knowledge base.

## When to Use

- Any write operation to files in `D:\ShipOfTheseus\ShipOfTheseus-KB\`
- Creating new KB documents
- Updating existing design docs, ADRs, task lists
- Patching content under specific headings
- Appending new sections to existing files

## KB Location

All KB files are in the Obsidian vault:
```
D:\ShipOfTheseus\ShipOfTheseus-KB\
```

## Decision Tree

Choose the write method based on operation type:

### 1. Append to End of File

**Tool**: `obsidian_append_content(filepath, content)`

Always safe. No heading lookup needed. Use when adding new sections at the bottom.

```
obsidian_append_content("path/to/file.md", "\n---\n\n## New Section\n\nContent here.\n")
```

### 2. Patch Under a Specific Heading

**Pre-check**: Is the heading English-only with simple punctuation?

**Safe headings** (use `obsidian_patch_content`):
- `## Battle Calculation System` — plain English
- `## ADR-005: Attribute System` — English with colon and hyphen
- `### v1 Test Classes` — English with number

**Unsafe headings** (use Read + Edit fallback):
- `## Attribute Baseline (Level 1)` — parentheses cause failures
- `## 属性基线` — Chinese characters
- `## Block Effect (格挡效果)` — mixed language
- `## 【Core System】` — brackets

**If safe**:
```
obsidian_patch_content(
  filepath: "path/to/file.md",
  target_type: "heading",
  target: "Heading Text",     // exact heading text without ## prefix
  operation: "append",        // or "prepend" or "replace"
  content: "New content"
)
```

**If unsafe** (fallback):
```
1. Read tool:  D:\ShipOfTheseus\ShipOfTheseus-KB\path\to\file.md
2. Edit tool:  (find the exact old_string, replace with new_string)
```

### 3. Replace Entire File

**Tool**: Read + Write (absolute path)

```
1. Read tool:  D:\ShipOfTheseus\ShipOfTheseus-KB\path\to\file.md
2. Write tool: D:\ShipOfTheseus\ShipOfTheseus-KB\path\to\file.md
   (with complete new content)
```

The `Read` call is **required** before `Write` — the Write tool will reject the operation otherwise.

### 4. Create New File

**Tool**: `Write` (absolute path)

```
Write tool: D:\ShipOfTheseus\ShipOfTheseus-KB\path\to\new-file.md
(with full content)
```

No prior `Read` needed for new files.

### 5. Search Then Write

For finding content before modifying:

```
1. obsidian_simple_search("search term")    // find which file and context
2. obsidian_get_file_contents("file.md")    // read full content
3. Read tool + Edit tool                     // make targeted edit
```

## Heading Format Standard

All KB headings must follow this format:

```markdown
# English Title Only

Content in English.

## Another English Heading

More content.
```

Rules:
- Headings are **English only** — no Chinese characters in headings
- No `> 中文标题` subtitle lines
- Body content in English
- Keep punctuation in headings simple: hyphens `-`, colons `:`, numbers are OK
- Avoid parentheses `()`, brackets `[]`, and special Unicode in headings

## Methods NOT to Use

| Method | Why Not |
|---|---|
| `obsidian_patch_content` on Chinese headings | Fails silently or throws `invalid-target` |
| `obsidian_patch_content` on headings with `()` | Fails with `invalid-target` |
| PowerShell `Set-Content` / `Out-File` | UTF-8 BOM issues corrupt Obsidian files |
| `Write` without prior `Read` | Tool rejects the operation |
| `Edit` without prior `Read` | Tool rejects the operation |
| `obsidian_append_content` for session state | Causes unbounded growth (use full rewrite) |

## Reading KB Files

For completeness, the read methods (most to least reliable):

| Method | Use Case |
|---|---|
| `obsidian_get_file_contents(filepath)` | Primary — works with all content types |
| `obsidian_simple_search(query)` | Find content across vault |
| `obsidian_complex_search(query)` | Advanced JsonLogic queries |
| `Read` tool (absolute path) | Fallback when MCP unavailable |

## Quick Reference: Common Paths

```
03-AI-Context/Active-Context/current-session.md    — Session state
02-Development/Tasks/Phase1-Tasks.md               — Task tracking
01-Game-Design/Core-Systems/battle-calculation.md   — Damage formulas
01-Game-Design/Characters/class-system.md           — Class data
01-Game-Design/Core-Systems/enemy-and-ai.md         — Enemy templates
02-Development/Decisions/                           — ADR files
```
