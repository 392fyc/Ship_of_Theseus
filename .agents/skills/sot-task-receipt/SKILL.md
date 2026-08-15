---
name: sot-task-receipt
description: "向主代理返回结构化子代理交付回执，包含 objective、status、changed_files、verification、commit、push、residual_risks。"
---

# SOT Task Receipt

## 适用时机

当一个子任务在此仓完成时，返回给主代理的固定结构如下：
- `objective`: 本次目标
- `status`: `done | blocked`
- `changed_files`: `[]` 或路径列表（repo-relative）
- `verification`: 已执行的验证命令与结果要点
- `commit`: 提交 SHA 或 `not committed`
- `branch`: 当前提交分支
- `push`: `true/false` 与远端引用
- `residual_risks`: 风险数组
- `protected_dirty`: 本次执行中不得改变但需识别的用户保护项清单（可空）

要求：
- 明确写 `branch`，并说明仅执行当前 task scope。
- 回执用于消息发送，**不得**自测为合格即自批准。
- 交付方只要执行任务即可，不得自行改 acceptance 状态。

## 示例
```text
{
  "objective": "Rebuild SoT skill contracts to Codex native primitives",
  "status": "done",
  "changed_files": [
    ".agents/skills/sot-kb-write/SKILL.md",
    "tests/codex/test_sot_skill_contracts.py"
  ],
  "verification": [
    "python -m pytest tests/codex/test_sot_skill_contracts.py -q"
  ],
  "commit": "abcdef123456",
  "branch": "task/571-codex-native-contracts",
  "push": true,
  "residual_risks": [],
  "protected_dirty": []
}
```
