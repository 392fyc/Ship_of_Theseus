# SoT authority routing

Ship_of_Theseus 是日常 SoT 开发的 Codex 默认工作根。开始工作前，先按事实类型选择权威位置；跨仓写入时再读取目标仓的 `AGENTS.md` 和其中指定的活合同。

| 事实类型 | 权威位置 | 使用边界 |
|---|---|---|
| Structured gameplay target facts（结构化玩法目标事实） | SoT 设计库 | 通过 `sot-designlib` lane 使用现有 API 或仓库 snapshot；设计目标不由游戏当前实现反推。 |
| Current executable behavior（当前可执行行为） | Ship_of_Theseus 游戏仓 | 代码、场景、测试和运行结果描述当前实现事实。 |
| Narrative、定性设计和裁决理由 | ShipOfTheseus-KB | 保存叙事、qualitative design、用户裁决、ADR、研究与工作记录，不承载任务状态。 |
| 任务与验收 | GitHub/Git | Issue、PR、commit、测试证据和 receipt 是任务进度与验收权威。 |
| 活跃记忆 | Mercury `.mercury/memory` | 保存当前跨任务记忆与 manual handoff；KB 的旧 session bundle 只作历史材料。 |

## 跨仓写入记录

写入另一仓库前，receipt 必须记录目标仓 `target HEAD`，以及本次实际读取的 `AGENTS.md` / canonical contract summary。设计库读取还要记录 `schema_version`、来源 snapshot 或 commit，以及规范化内容的 SHA256 摘要。
