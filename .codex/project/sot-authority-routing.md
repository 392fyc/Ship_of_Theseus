# SoT authority routing

Ship_of_Theseus 是日常 SoT 开发的 Codex 默认工作根。开始工作前，先按事实类型选择权威位置；跨仓写入时再读取目标仓的 `AGENTS.md` 和其中指定的活合同。

| 事实类型 | 权威位置 | 使用边界 |
|---|---|---|
| Structured gameplay target facts（结构化玩法目标事实） | SoT 设计库 | 通过 `sot-designlib` lane 使用现有 API 或仓库 snapshot；设计目标不由游戏当前实现反推。 |
| Current executable behavior（当前可执行行为） | Ship_of_Theseus 游戏仓 | 代码、场景、测试和运行结果描述当前实现事实。 |
| Narrative、定性设计和裁决理由 | ShipOfTheseus-KB | 保存叙事、qualitative design、用户裁决、ADR、研究与工作记录，不承载任务状态。 |
| 任务与验收 | GitHub/Git | Issue、PR、commit、测试证据和 receipt 是任务进度与验收权威。 |
| SoT 领域所有权 | SoT | 维护游戏仓、设计库 app/tests/scripts、KB 与领域 agent、配置、技能和 workflow。 |
| 通用 Harness 模板 upstream | Mercury | 只拥有 `.codex/agents/mercury-*`、`.codex/rules/mercury-*`、`.codex/project/mercury-*`、`.codex/mercury-template.lock`；SoT 不得修改或发起内容变更，由 Mercury 发起 Issue/PR 后单向生成消费。 |
| 活跃记忆 | 配置的记忆根，默认游戏仓主 Git 工作树 `.sot/memory` | 按 `SOT_MEMORY_ROOT`、`[roots].memory_root`、主工作树默认路径解析；任务 worktree 不改变项目记忆身份。旧 Mercury bucket 仅可显式配置后只读访问，迁移需用户授权。 |

涉及通用 Harness 所有权或任务合同的会话，在文件已安装时按需读取 `.codex/project/mercury-harness-ownership.md` 与 `.codex/project/mercury-task-contract.md`。消费入口与单向生成约束见 `docs/mercury-harness-consumption.md`。

## 跨仓写入记录

写入另一仓库前，receipt 必须记录目标仓 `target HEAD`，以及本次实际读取的 `AGENTS.md` / canonical contract summary。设计库读取还要记录 `schema_version`、来源 snapshot 或 commit，以及规范化内容的 SHA256 摘要。
