---
name: sot-kb-write
description: "Reliably write to the Ship of Theseus Obsidian knowledge base. Use when creating, updating, patching, or appending content to any KB document. Provides a decision tree for choosing the most reliable write method."
---

# SOT KB Write

KB Location: `D:\ShipOfTheseus\ShipOfTheseus-KB\`

## Decision Tree

### 1. Append to End of File
`obsidian_append_content(filepath, content)` — Always safe.

### 2. Patch Under a Heading
**Safe** (English-only, no `()` `[]`): use `obsidian_patch_content(filepath, target_type="heading", target="Heading Text", operation, content)`

**Unsafe** (Chinese, parentheses, brackets): use Read + Edit fallback with absolute path.

### 3. Replace Entire File
Read + Write (absolute path). **Read required before Write.**

### 4. Create New File
Write (absolute path). No prior Read needed.

### 5. Search Then Write
1. `obsidian_simple_search("term")` → find file
2. `obsidian_get_file_contents("file.md")` → read
3. Read + Edit → targeted edit

## DO NOT

| Method | Why Not |
|---|---|
| `obsidian_patch_content` on Chinese/`()`/`[]` headings | Silent fail or `invalid-target` |
| PowerShell `Set-Content` / `Out-File` | UTF-8 BOM corrupts Obsidian |
| `Write` without prior `Read` (existing file) | Tool rejects |
| `obsidian_append_content` for session state | Unbounded growth |
