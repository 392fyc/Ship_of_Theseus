---
name: sot-session-end
description: "Close a Ship of Theseus Codex session by updating available active memory and GitHub/Git evidence, with manual handoff only when the user explicitly requests it."
---

# SoT Session End

## 1. 收集结束状态

汇总已完成任务、修改文件、裁决、验证证据、受保护 dirty、遗留风险与下一步。任务与验收状态回写 GitHub/Git，不写入 KB 的旧任务清单作为第二权威。

## 2. 更新活跃记忆

优先使用 `SOT_MEMORY_ROOT`，然后使用本地 roots 配置 `[roots].memory_root`；两者均未配置时，按 `sot-session-start` 的规则确定游戏仓主 Git 工作树默认路径：

1. 环境变量 `SOT_MEMORY_ROOT`。
2. 当前仓库被忽略的 `.codex/project/sot-roots.local.toml` 中 `[roots].memory_root`。
3. 均未配置时，使用游戏仓主 Git 工作树下的 `.sot/memory`；通过 Git common directory 与 `git worktree list --porcelain` 识别主工作树，不以任务 worktree 作为项目记忆根。

若根目录可用，先读取 `<memory-root>/index.jsonl`，再按项目 bucket 更新：

`<memory-root>/projects/<project-bucket>/session-checkpoint.md`

若记忆根或索引缺失，报告未保存 checkpoint 并继续结束会话；普通结束流程不得为填补缺失而迁移旧数据。若显式配置指向旧 Mercury bucket（`.mercury/memory`），该根仅可只读，未经用户明确授权不得写入或迁移。

## 3. 按需更新 KB

只有本次产生叙事、定性设计、用户裁决、ADR、研究或工作记录时才更新 KB。使用 `sot-kb-write` 的先读、并发保护、写后回读流程；不把活跃会话状态迁入 KB。

## 4. Handoff（Manual only）

默认不得自动 handoff。只有 user 明确要求时，才同时生成：

1. 聊天中可直接粘贴的新会话起始指令。
2. 持久文档，写入 `<memory-root>/projects/<project-bucket>/` 下的明确命名 markdown 文件。

manual handoff 前先确认项目 bucket，并让文档包含当前提交、受保护 dirty、验收证据、未完成风险与下一任务入口。若默认 `.sot/memory` 尚不存在，可仅为用户明确要求的持久 handoff 创建所需目录和文档；不得自动复制旧 Mercury bucket。若用户配置的目标根不可用或只读，仍在聊天中提供起始指令，并明确报告持久文档未能保存。

禁止自动创建新 Codex 任务、自动切换任务状态、在压缩或会话结束事件中隐式触发 handoff。

## 工作树收尾

结束会话不自动删除工作树。记录实际路径、HEAD、分支、PR/任务状态以及需保留的 dirty、untracked、ignored 内容；检查是否已有集成后的新提交。已授权退役具体工作树时，按 [工作树生命周期](../../../docs/worktree-lifecycle.md) 逐文件归档并核验，保留 refs，使用非 force Git 清理。年龄、无开放 PR 或 PR 已关闭不能单独判定可删除。
