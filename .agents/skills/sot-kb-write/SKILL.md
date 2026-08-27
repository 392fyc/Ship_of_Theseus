---
name: sot-kb-write
description: "Use Codex Obsidian MCP tools to search, read, create, patch, and verify SoT KB records without turning the KB into task or active-memory authority."
---

# SoT KB 安全读写

KB 是独立知识库，承载叙事、定性设计、用户裁决、ADR、研究和工作记录。它不是任务与验收权威，也不是活跃记忆权威：前者属于 GitHub/Git，后者属于 Mercury `.mercury/memory`。KB 中 `01-Game-Design/rules-catalog.md` 只作检索镜像，结构化玩法事实以设计库为准。

Obsidian MCP 的 vault 逻辑根用于文档读写。KB 权威不按 worktree 分裂，所有读写都进入同一个固定 Obsidian vault。按以下顺序解析该固定 vault 及其 Git 仓库根：环境变量 `SOT_KB_ROOT`，然后是游戏仓被忽略的 `.codex/project/sot-roots.local.toml` 内 `[roots].kb_root`。两者都不存在时仍可进行只读 MCP 检索，但不得执行跨仓写入。

## 固定 vault 与分支交接

Git 分支提供任务隔离，Obsidian vault 不提供任务隔离。开始 KB 写入前必须依次完成：

1. 确认 MCP 实际映射的 vault 与解析出的固定 KB 根是同一仓库，并记录 Git common directory、当前分支、HEAD 与工作区状态。
2. 确认固定 vault 的工作区干净；存在未提交改动、受保护改动或其他活跃任务占用时停止并协调。
3. 在固定 vault 中检出目标任务分支。若分支已被其他 worktree 检出，只能在确认该 worktree 干净且无人使用后，将其置于 detached HEAD 来解除占用；不得为释放分支而自动移除 worktree，无法确认时停止。
4. 通过 MCP 读取、带 `ifMatch` 修改并回读。写入内容与固定 vault 当前检出的任务分支必须始终对应。
5. 从固定 vault 当前任务分支调用受控发布入口。任务合并后，把固定 vault 切回受保护的默认分支，并仅以 fast-forward 更新到合并后的权威 HEAD。

禁止为任务 worktree 另开第二个 Obsidian vault，禁止临时更换 MCP endpoint 或端口，禁止先写固定 vault 再复制到 worktree，禁止使用 `--ignore-other-worktrees`、stash、reset、自动移除 worktree 或丢弃现有改动来绕过分支占用。

## 跨仓写入前置记录

写入前先完成并保留以下证据：

1. 从已解析的 KB 仓库根读取目标 `AGENTS.md`（若存在）。
2. 读取相关 canonical：通用入口可先查 `01-Game-Design/rules-catalog.md`，具体文档则先取目标文档 map 和附近上下文。
3. 获取并记录 KB 仓当前 `target_head`；无法获取时停止写入，不以 `unavailable` 代替。
4. 用一段简短的 `contract_summary` 说明本次可写范围、权威边界与并发保护方式。

## 选择操作

### 搜索与读取

1. `mcp__obsidian__search_simple` 定位候选文档。
2. `mcp__obsidian__vault_read` 读取目标全文或所需范围。

### 结构化补丁（默认）

1. 用 `mcp__obsidian__vault_get_document_map` 获取文档映射与版本信息。
2. 用 `mcp__obsidian__vault_patch` 携带 `ifMatch` 提交补丁。
3. 用 `mcp__obsidian__vault_read` 回读变更位置并核对。

### 整文件与新建

- 已存在的文档禁止使用 `mcp__obsidian__vault_write` 整体覆盖；该接口没有 `ifMatch`，先读后写仍可能静默覆盖并发更新。需要大范围修改时拆成带版本条件的结构化 patch；无法安全表达时停止并报告。
- `mcp__obsidian__vault_write` 只用于新文件：先搜索同名或同主题文档，再确认目标路径不存在，并使用带 Issue 标识的唯一文件名。无法排除同名并发创建时停止，不执行写入。
- 新文件写入后立即用 `mcp__obsidian__vault_read` 回读并核对完整内容。
- 仅对有边界的增量日志使用 `mcp__obsidian__vault_append`；不得用它保存会话状态或无限增长的活跃记忆。

## 发布任务分支

固定 KB vault 检出目标任务分支后，从该固定 vault 调用当前 Ship 工作根的 `scripts/codex/sot-publish.ps1`。KB 仓无需提供同名脚本；不得误报发布阻断，也不得改用原始 `git push`。

## 安全约束

- 已有文档必须先读后 patch；任何写入都必须独立回读。
- patch 必须使用 `ifMatch`；冲突时重新读取，不覆盖他人更新。
- 不把结构化玩法数据复制成第二权威，不把 GitHub 任务状态或 Mercury 活跃记忆迁入 KB。
- 不输出 token、密码、私钥、个人信息或匹配到的秘密文本。
- 写入真实 KB 必须有任务授权；能力验证优先使用 dry-run、fixture 或可逆临时对象。
