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

1. 在 `scripts/codex/sot-worktree.ps1 -Action Create -Repository ship` 创建的任务工作树中工作；分支、标签与 PR 规则见 `docs/02-Development/lane-collaboration.md`。
2. 用文件编辑工具修改 `docs/` 下的 Markdown。先读后改；新建文件前先检索同名或同主题文档，避免重复入口。
3. 不使用 Obsidian MCP 的 `vault_write`、`vault_patch`、`vault_append` 等写入工具：它们写入的是主工作树，主工作树停在受保护分支，写入会留下无人负责的未提交改动。
4. 保持 vault 内链接有效：新写的链接一律用相对路径的 Markdown 链接（`[显示名](../00-rules/README.md)`），不用 `[[wikilink]]`，也不以 `/` 开头；`docs/.obsidian/app.json` 已设为 Obsidian 写 Markdown 相对链接。已有的 wikilink 仍会被检查，改到它所在的段落时顺手换成 Markdown 链接。移动或重命名文件时同步更新引用它的文档。`docs/` 内提到 `docs/` 以外的仓库文件（代码、数据、脚本）时写代码格式的仓库相对路径，不写 Markdown 链接：Obsidian 只能打开 vault 内的文件。反过来，仓库其他位置引用 KB 时用指向 `docs/` 的相对链接。
5. 文本文件使用 UTF-8（无 BOM）与 LF。不要用 PowerShell 的 `Set-Content` / `Out-File` 写 KB 文件。
6. 与相关改动一起提交，经 `scripts/codex/sot-publish.ps1` 发布并开 PR；合并后按[工作树生命周期](../../../docs/02-Development/worktree-lifecycle.md)退役工作树与分支。

## 用户在 Obsidian 中的直接修改

用户可以在 Obsidian 中直接编辑主工作树的 `docs/`，Obsidian 改设置或更新插件时也会改动 `docs/.obsidian/` 下已跟踪的文件。这些都会在主工作树留下未提交改动。收录时：

1. 在主工作树用 `git -c core.quotePath=false status --porcelain --untracked-files=all -- docs` 列出改动（逐个文件列出、中文路径不转义），只取 `docs/` 下的文件；其他路径的改动不碰。`docs/.obsidian/` 下的改动先问用户是否要提交，不要就留在原处，不丢弃。
2. 新建任务工作树，把要收录的文件逐个复制过去，记下每个文件的 SHA-256，核对一致后提交、发布、开 PR。
3. PR 合并后，主工作树不会自动变干净：这些路径有本地改动或是未跟踪文件，Git 会拒绝快进。处理时只动暂存区、不碰工作树，避免抹掉用户在这期间的新输入：
   1. 先确认本会话允许对主工作树执行 `git merge --ff-only`；不允许时，把第 3、4 子步骤连同核对结果一起交给用户执行，代理不只做一半。然后 `git fetch`，确定快进目标 T（受保护分支在 origin 上的末端）。
   2. 逐个比对 `git hash-object -- docs/<路径>` 与 `git rev-parse T:docs/<路径>`；用户删除的文件，确认它在 T 中也不存在。两边都是 Git 对象哈希，不经 PowerShell 管道或重定向导出内容。
   3. 全部一致时执行 `git restore --source=T --staged -- <这些路径>`：只把 T 的版本写入暂存区，不加 `--worktree`。
   4. 快进主工作树到 T。暂存区已等于 T，Git 保留工作树中的文件原样，不改写它们。
   5. 用 `git status -- docs` 回读：正常时这些路径全部干净；比对之后用户又改过的，会作为未暂存改动留下而不会丢；快进失败（例如 T 中同一文件后来又被改过）就停下报告，并写明暂存区已写成 T 的版本、工作树未动，可用 `git restore --staged -- <路径>` 撤回暂存。
4. 任何一个不一致（例如用户在复制之后又改过），就停下来报告给用户，不对任何路径执行 restore、删除、stash 或 reset。

## 目录、状态与删除

KB 按 Mercury KB 约定（`.mercury/packs/kb/docs/kb-conventions.md`）组织：

- 唯一入口是 `docs/README.md`；每个目录有 `README.md` 索引，逐条列出文档和状态，状态只有「现行」与「草稿」。新建文档时在所在目录的索引里登记一行。
- KB 只保留现行内容，没有归档目录。改动让某份文档、某条规则或某行决策过时或出错时，在同一个 PR 里删除它，并删除或改写所有指向它的链接；不要标「已取代」后留着，检索会把它当现行内容读到。
- 旧内容必须保留可引用时（例如用户原话所在的文档被删），引用固定提交的永久链接 `https://github.com/392fyc/Ship_of_Theseus/blob/<提交>/docs/<路径>`。
- 提交前运行 `python -B .mercury/packs/kb/scripts/kb_check.py docs`，退出码必须为 0；PR 描述写 `KB:` 一行，列出更新或删除的 KB 文档。

## 知识放在能被找到的地方

- 用户对设计的裁决写进负责该主题的原则分册（入口为 `docs/00-rules/design-rules-index.md`），附日期与原话；只写 ADR 或工作记录不够。
- 研究按标题归入参考作品索引 `docs/05-Research/references.md`。
- 新页面改变了代理的开工入口时，同一改动中更新 `design-rules-index.md` 的路由。

## 安全约束

- 不把结构化玩法数据复制成第二权威，不把 GitHub 任务状态或活跃记忆迁入 KB。
- 不写入 token、密码、私钥、个人信息或匹配到的秘密文本；Obsidian 插件的 `data.json` 含密钥，已被 Git 忽略，不得提交。
- `docs/.obsidian/` 只提交共享配置；`workspace*.json`、`cache`、`graph.json` 与插件 `data.json` 是本机状态。
