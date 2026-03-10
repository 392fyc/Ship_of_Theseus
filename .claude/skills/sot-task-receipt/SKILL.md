---
name: sot-task-receipt
description: "在 Ship of Theseus 项目中，任何 Sub Agent 完成实现后，都应使用此 skill 填写 Task Bundle 的 implementation_receipt。触发于“任务完成”“填写 receipt”“implementation_receipt”“handoff”“完成 TASK-*”等收尾语境；即使用户只说交付、回填或收尾，也要使用。"
---

# SOT Task Receipt

## 适用时机

- 实现已经完成，准备向 Main Agent 交付。
- 当前工作需要填写或校验 `implementation_receipt`。
- 任务涉及 `TASK-*.yaml`，且需要留下实现凭据。

## 工作顺序

1. 先读当前 Task Bundle，确认 `definition_of_done`、`required_evidence`、`allowed_write_scope`。
2. 收集本次实现事实：实际分支、实际改动文件、可复核证据、未解决风险。
3. 只填写当前 Task Bundle 的 `implementation_receipt` 区域。
4. 写完后自查一遍，再停止并通知 Main Agent。

## 字段填写规范

### `implementer`

- 填实际执行代理和模型，例如 `Codex CLI (GPT-5)`、`Claude Code (Opus)`。
- 不要填人名、团队名或空泛描述。

### `branch`

- 填实际 git 分支名。
- 若任务在 `develop` 或 detached 状态完成，照实填写，不要编造特性分支。

### `summary`

- 用 2-4 条短句概括“做了什么”和“关键实现决策”。
- 写结果，不写聊天过程；避免“我查看了”“我认为”这类过程叙述。

### `changed_files`

- 列出本次实际修改或新建的文件。
- 仓库内路径使用 repo-relative 路径。
- 若确实改了仓库外文件，使用绝对路径并标明是外部运行时配置。

### `evidence`

- 写可复核证据，不写空泛结论。
- 优先包含：文件存在性、静态检查、命令结果、运行结果、日志摘要、截图或模板对照结论。
- 证据应能直接支撑 `definition_of_done` 或 `required_evidence`。

### `docs_updated`

- 列出本次实际更新的文档路径。
- 若没有文档更新，写空数组 `[]`，不要写“无”。

### `residual_risks`

- 只写尚未解决、但不阻塞本次交付的风险、限制或后续注意事项。
- 若没有剩余风险，写空数组 `[]`。

### `completed_at`

- 使用带时区偏移的 ISO 8601 时间戳，例如 `2026-03-10T17:34:01.4230781+09:00`。
- 以实际完成回填时刻为准。

## 约束

- 不修改 registry、session 文件、acceptance bundles。
- 默认只回填 `implementation_receipt`；是否推进其他状态，遵循当前 dispatch 或 Main Agent 指令。
- 不要伪造未执行的测试、运行结果或文件改动。

## Receipt 质量检查清单

- `implementation_receipt` 的 8 个字段全部已填写。
- 没有 `null`、`TBD`、`TODO` 或占位文本残留。
- `summary` 与 `evidence` 不重复，各自承担“结果”与“证明”职责。
- `changed_files`、`docs_updated` 的路径可被仓库或 KB 实际定位。
- 空字段使用 `[]`，而不是自然语言占位。
- `residual_risks` 仅记录未解项，不把已完成事项写成风险。
- 内容与 `definition_of_done`、`required_evidence` 一一对应。
- 写完后停止，不自行改 registry 或 acceptance 状态。
