# 2026-02 至 03 编排器角色文档归档（2026-10-30）

> 本目录是历史归档，不属于现行规则或任务状态。代理的职责、边界与交付流程以仓库根的 `AGENTS.md`、`CLAUDE.md` 和 Mercury 生成的角色为准，任务与验收以 GitHub/Git 为准，活跃记忆以配置的活跃记忆根为准。

这些文件记录 2026-02 至 03 的多代理编排方式（角色版本 v1.0 写于 2026-02-26，opencode 代理加入于 2026-03-14）：一个常驻的主代理窗口只做调度，把任务分派给 Design、Implementation、Batch、Analysis 与 opencode 等代理；每个代理启动时先读 `03-AI-Context/Active-Context/current-session.md`，结束时改写它。`current-session.md` 已归档在 [[_archive/03-ai-context-stale-2026-07-18/current-session|03-ai-context-stale-2026-07-18]]，这套流程随之失效。用户裁决整套退役，不改写（Issue #102）。文件按原样移入，未作修改。

| 文件 | 原路径 | 内容 |
|---|---|---|
| `00-main-agent.md` | `03-AI-Context/Agent-Roles/` | 主代理（调度中心）角色声明与启动提示 |
| `01-design-agent.md` | `03-AI-Context/Agent-Roles/` | 设计代理角色声明 |
| `02-implementation-agent.md` | `03-AI-Context/Agent-Roles/` | 实现代理角色声明 |
| `03-batch-agent.md` | `03-AI-Context/Agent-Roles/` | 批量生成代理角色声明 |
| `04-analysis-agent.md` | `03-AI-Context/Agent-Roles/` | 长上下文分析代理角色声明 |
| `05-opencode-agent.md` | `03-AI-Context/Agent-Roles/` | opencode 并行实现代理（经 GitHub Copilot） |
| `agent-role-protocol.md` | `03-AI-Context/Agent-Roles/` | 角色身份声明、边界与交接身份规则 |
| `main-agent-startup.md` | `Templates/` | 主代理会话的起始指令模板 |
