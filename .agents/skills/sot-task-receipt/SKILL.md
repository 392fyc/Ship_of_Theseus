---
name: sot-task-receipt
description: "Return a Mercury-compatible SoT task receipt with changed scope, verification, cross-repository source evidence, and protected state."
---

# SoT Task Receipt

本技能扩展 `.codex/project/mercury-task-contract.md`，不得替换或削弱其中的 implementation receipt。子任务结束时返回一个机器可读对象，至少包含 Mercury 基础字段：

- `task_id`: 稳定任务标识。
- `status`: `completed | blocked | failed`。
- `target_repository`: 逻辑仓库身份。
- `target_branch`: 当前任务分支。
- `target_head_before`: 实现前目标仓完整提交。
- `candidate_head`: 候选完整提交；尚未提交时为 `null`。
- `contract_summary`: 已读取合同及适用边界的对象数组。
- `changed_files`: 仓库相对路径列表。
- `verification`: 命令、`pass | fail | skipped` 结果和精简证据的对象数组。
- `criteria_evidence`: 每项验收标准的结果与证据。
- `protected_state`: 受保护路径或仓库的 `unchanged | changed | unverified` 结果及证据。
- `residual_risks`: 未解决风险列表。
- `escalation_reason`: 无阻断时为 `null`，否则写明原因。

SoT 跨仓或设计库任务再增加以下字段：

- `target_head`: 跨仓读取或写入目标的 HEAD；非 Git 目标写 `unavailable`。
- `source_schema_version`: 设计库 API 或快照声明的 `schema_version`；无声明写 `unversioned`。
- `source_snapshot_or_commit`: 事实读取所用快照相对路径、来源提交或 API 版本标识。
- `normalized_digest`: 规范化完整来源的 SHA256 摘要；不适用时说明原因。
- `publication`: 是否推送及远端逻辑引用；未发布时明确写 `published: false`。

## 约束

- 明确写出任务写入范围与实际 changed files；范围外文件即使 dirty 也不得夹带。
- 回执中的验证必须是本次新执行的证据，不用旧结果替代。
- 不在回执中输出秘密匹配文本、token、绝对本机路径或个人凭据。
- 实现者不得自行批准交付；规格审查、代码审查和 acceptance 由独立审查者完成。

## 示例

```json
{
  "task_id": "TASK-000",
  "status": "completed",
  "target_repository": "Ship_of_Theseus",
  "target_branch": "codex/example",
  "target_head_before": "<full sha>",
  "candidate_head": null,
  "contract_summary": [{"contract": "AGENTS.md", "summary": "Codex project boundary"}],
  "changed_files": ["AGENTS.md"],
  "verification": [{"command": "python -m pytest tests/codex/test_sot_skill_contracts.py -q", "result": "pass", "evidence": "all focused tests passed"}],
  "criteria_evidence": [{"criterion": "Codex project contract", "result": "pass", "evidence": ["AGENTS.md"]}],
  "protected_state": [{"subject": "project.godot", "result": "unchanged", "evidence": "protected main status matched baseline"}],
  "residual_risks": [],
  "escalation_reason": null,
  "target_head": "<full sha>",
  "source_schema_version": "unversioned",
  "source_snapshot_or_commit": "snapshots/rules.json@<full sha>",
  "normalized_digest": "sha256:<digest>",
  "publication": {"published": false, "remote_ref": null}
}
```
