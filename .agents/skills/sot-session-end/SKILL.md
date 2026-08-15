---
name: sot-session-end
description: "Close a Ship of Theseus Codex session by updating Mercury active memory and GitHub/Git evidence, with manual handoff only when the user explicitly requests it."
---

# SoT Session End

## 1. 收集结束状态

汇总已完成任务、修改文件、裁决、验证证据、受保护 dirty、遗留风险与下一步。任务与验收状态回写 GitHub/Git，不写入 KB 的旧任务清单作为第二权威。

## 2. 更新 Mercury 活跃记忆

按以下顺序解析 Mercury 根目录：

1. 环境变量 `MERCURY_ROOT`。
2. 当前仓库被忽略的 `.codex/project/sot-roots.local.toml` 中 `[roots].mercury_root`。
3. 均未配置时停止并报告，不猜测本机路径。

先读取 `<mercury-root>/.mercury/memory/index.jsonl`，再按项目 bucket 更新：

`<mercury-root>/.mercury/memory/projects/<project-bucket>/session-checkpoint.md`

不得直接把项目 checkpoint 写到 `.mercury/memory` 根目录。

## 3. 按需更新 KB

只有本次产生叙事、定性设计、用户裁决、ADR、研究或工作记录时才更新 KB。使用 `sot-kb-write` 的先读、并发保护、写后回读流程；不把活跃会话状态迁入 KB。

## 4. Handoff（Manual only）

默认不得自动 handoff。只有 user 明确要求时，才同时生成：

1. 聊天中可直接粘贴的新会话起始指令。
2. 持久文档，写入 `<mercury-root>/.mercury/memory/projects/<project-bucket>/` 下的明确命名 markdown 文件。

manual handoff 前先确认项目 bucket，并让文档包含当前提交、受保护 dirty、验收证据、未完成风险与下一任务入口。

禁止自动创建新 Codex 任务、自动切换任务状态、在压缩或会话结束事件中隐式触发 handoff。
