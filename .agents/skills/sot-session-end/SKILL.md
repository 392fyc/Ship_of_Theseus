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

若根目录可用，先读取 `<memory-root>/index.jsonl`，再更新本会话所属 lane（由 `sot-session-start` 确定）的 checkpoint：

`<memory-root>/projects/<project-bucket>/lanes/<lane>/session-checkpoint.md`

lane 未确定时先问用户，不写入其他 lane 的目录。checkpoint 由同一 lane 的多个 agent 共享，按 [多 Lane 多 Agent 协作](../../../docs/lane-collaboration.md) 的版本条件写入：把新内容写到临时文件，用 `scripts/codex/sot-memory.ps1 -Action Write -Path lanes/<lane>/session-checkpoint.md -SourceFile <临时文件> -ExpectedSha256 <会话启动读取时记下的哈希>` 一次完成比较、原子替换与登记；被拒绝时文件未改动，重读、合并后重试，不直接覆盖。非主导宿主只记录自己的作业与结论，不改写主导宿主的正式判断。尚未启用 lane 的旧项目才使用 `<memory-root>/projects/<project-bucket>/session-checkpoint.md`。

若记忆根或索引缺失，报告未保存 checkpoint 并继续结束会话；普通结束流程不得为填补缺失而迁移旧数据。若显式配置指向旧 Mercury bucket（`.mercury/memory`），该根仅可只读，未经用户明确授权不得写入或迁移。

## 3. 按需更新 KB

只有本次产生叙事、定性设计、用户裁决、ADR、研究或工作记录时才更新 KB。使用 `sot-kb-write` 的先读、并发保护、写后回读流程；不把活跃会话状态迁入 KB。

## 4. Handoff（Manual only）

默认不得自动 handoff。只有 user 明确要求时，才同时生成：

1. 聊天中可直接粘贴的新会话起始指令。
2. 持久文档，写入本 lane 目录下本宿主自己的文件 `<memory-root>/projects/<project-bucket>/lanes/<lane>/handoff-<harness>.md`（harness 为 `claude` 或 `codex`），不覆盖其他宿主或其他 lane 的 handoff。首次创建用 `sot-memory.ps1 -Action Write ... -CreateNew`，之后带读取时的哈希写入。

起始指令与文档都标 `[LANE=<lane>]`，接手会话据此继承 lane。manual handoff 前先确认项目 bucket 与 lane，并让文档包含当前提交、受保护 dirty、验收证据、未完成风险与下一任务入口。若默认 `.sot/memory` 尚不存在，可仅为用户明确要求的持久 handoff 创建所需目录和文档；不得自动复制旧 Mercury bucket。若用户配置的目标根不可用或只读，仍在聊天中提供起始指令，并明确报告持久文档未能保存。

禁止自动创建新 Codex 任务、自动切换任务状态、在压缩或会话结束事件中隐式触发 handoff。

## 工作树收尾

检查游戏仓与设计库主工作区：`git -C <主工作区> status --porcelain`。主工作区不做开发；有未提交改动时，在本 lane 的 checkpoint 中登记路径与疑似归属并报告用户，不替其他 lane 丢弃或提交（`.sot/` 下的活跃记忆与 lane 工作区被忽略，不计入）。

会话结束本身不构成删除工作树的依据。记录实际路径、HEAD、分支、PR/任务状态以及需保留的 dirty、untracked、ignored 内容；检查是否已有集成后的新提交。PR 已合并时，按 [工作树生命周期](../../../docs/worktree-lifecycle.md)「PR 合并后」一节直接清理工作树与本地分支；未合入时按「未合入就废弃」一节列出清单，等用户确认。年龄、无开放 PR 或 PR 已关闭不能单独判定可删除。
