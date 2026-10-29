---
name: sot-kb-write
description: "Read, search, and edit SoT KB records in the repository's docs/ vault inside a task worktree, delivering them in the same pull request as the related work, without turning the KB into task or active-memory authority."
---

# SoT KB 读写

KB 是本仓库的 `docs/` 目录，同时是 Obsidian vault，承载叙事、定性设计、用户裁决、ADR、研究和工作记录。它不是任务与验收权威，也不是活跃记忆权威：前者属于 GitHub/Git，后者属于配置的活跃记忆根（默认游戏仓主 Git 工作树的 `.sot/memory`）。`docs/01-Game-Design/rules-catalog.md` 只作检索镜像，结构化玩法事实以设计库为准。

KB 原为独立仓库 ShipOfTheseus-KB，2026-10-29 起以当前快照并入本仓库 `docs/`（Issue #90）；更早的逐文件历史留在已归档的旧仓库中。

## 一起推进

KB 承担本项目 docs 的职责：每次作业把文档和其他内容一起推进。

- 任务产生的定性设计、用户裁决、研究结论或工作记录，与对应的代码、数据或配置改动在**同一个任务工作树**中修改、在同一个 PR 中交付。
- 只改文档的任务同样走任务分支与 PR，不在主工作树写入。
- 没有 KB 写入授权时，在汇报中列出待入册的裁决原话、日期和目标分册，不写入。

## 读取与检索

- 任务工作树内：直接读取 `docs/` 下的文件，或用 `rg` 等工具在 `docs/` 内检索。读的是本任务分支的版本。
- Obsidian MCP（`mcp__obsidian__search_simple`、`mcp__obsidian__vault_read` 等）映射的是主工作树的 `docs/`，反映主工作树检出的已合并内容，可用于跨文档检索和查看反向链接。它不包含任务分支上尚未合并的修改。

## 写入

1. 在 `scripts/codex/sot-worktree.ps1 -Action Create -Repository ship` 创建的任务工作树中工作；分支、标签与 PR 规则见 `docs/lane-collaboration.md`。
2. 用文件编辑工具修改 `docs/` 下的 Markdown。先读后改；新建文件前先检索同名或同主题文档，避免重复入口。
3. 不使用 Obsidian MCP 的 `vault_write`、`vault_patch`、`vault_append` 等写入工具：它们写入的是主工作树，主工作树停在受保护分支，写入会留下无人负责的未提交改动。
4. 保持 vault 内链接有效：Obsidian wiki 链接与相对链接都以 `docs/` 为根；移动或重命名文件时同步更新引用它的文档。
5. 文本文件使用 UTF-8（无 BOM）与 LF。不要用 PowerShell 的 `Set-Content` / `Out-File` 写 KB 文件。
6. 与相关改动一起提交，经 `scripts/codex/sot-publish.ps1` 发布并开 PR；合并后按[工作树生命周期](../../../docs/worktree-lifecycle.md)退役工作树与分支。

## 用户在 Obsidian 中的直接修改

用户可以在 Obsidian 中直接编辑主工作树的 `docs/`。这会在主工作树留下未提交改动。收录时：

1. 在主工作树用 `git status --porcelain -- docs` 列出改动，只取 `docs/` 下的文件；其他路径的改动不碰。
2. 新建任务工作树，把这些文件逐个复制过去，核对 SHA-256 一致后提交、发布、开 PR。
3. PR 合并、主工作树快进到包含这些提交之后，主工作树中的这些文件自然变为干净；在此之前不要丢弃主工作树中的改动。

## 知识放在能被找到的地方

- 用户对设计的裁决写进负责该主题的原则分册（入口为 `docs/03-AI-Context/design-rules-index.md`），附日期与原话；只写 ADR 或工作记录不够。
- 研究按标题归入参考作品索引 `docs/05-Research/references.md`。
- 新页面改变了代理的开工入口时，同一改动中更新 `design-rules-index.md` 的路由。

## 安全约束

- 不把结构化玩法数据复制成第二权威，不把 GitHub 任务状态或活跃记忆迁入 KB。
- 不写入 token、密码、私钥、个人信息或匹配到的秘密文本；Obsidian 插件的 `data.json` 含密钥，已被 Git 忽略，不得提交。
- `docs/.obsidian/` 只提交共享配置；`workspace*.json`、`cache`、`graph.json` 与插件 `data.json` 是本机状态。
