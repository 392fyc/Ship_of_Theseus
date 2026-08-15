---
name: sot-kb-write
description: "Use Codex Obsidian MCP tools to create, patch, and update Ship of Theseus KB documents safely, with safe defaults and explicit verification."
---

# SOT KB Write（Codex 原生）

KB Location: `D:\ShipOfTheseus\ShipOfTheseus-KB\`（当前仅作为设计与开发知识库，非活跃项目记忆权威）

## Decision Tree

### 1. 文件追加（append）
`mcp__obsidian__vault_append` — 对有增量日志类内容可用。

### 2. 结构化补丁（推荐）
先读取文档映射，再以 `ifMatch` 做条件性 patch。
- `mcp__obsidian__vault_get_document_map`
- `mcp__obsidian__vault_patch`

### 3. 覆盖整文件（优先）
先读后写，覆盖前后都做回读。
- `mcp__obsidian__vault_read`
- `mcp__obsidian__vault_write`

### 4. 全新建文件
`mcp__obsidian__vault_write`，新文件无先读要求，但推荐先确认目录上下文。

### 5. 先定位再写
1. `mcp__obsidian__search_simple("term")` 定位文件
2. `mcp__obsidian__vault_read("file.md")` 读取
3. 再做 patch 或 overwrite

## 工作约束（必须）

- 先读后写：任何非空文件更新都要先读再写，结构化 patch 不做单步盲改。
- 结构化 patch 先读 `vault_get_document_map`，并结合 `ifMatch` 做并发保护。
- 覆盖写入必须 `vault_read` 先后 `vault_read` 再校验，避免静默损坏。
- 不在会话输出中写入或回传密钥、密码、Token，遇到敏感字段一律跳过。

## DO NOT

| Method | Why Not |
|---|---|
| `mcp__obsidian__vault_append` 用于会话状态 | 无界增长 |
| 不带 `ifMatch` 的 `vault_patch` | 并发时可能覆盖他人更新 |
| `vault_write` 覆盖已有文件时不回读 | 无法发现读写不一致 |
