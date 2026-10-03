# Mercury Harness 模板消费约定

SoT 负责游戏仓、设计库 app/tests/scripts、KB 和 SoT 领域 workflow。领域 agent、配置、技能和 workflow 属于 SoT，可以在 SoT 仓独立维护。

Mercury 只维护通用 Harness 模板 upstream 清单：

- `.codex/agents/mercury-*`
- `.codex/rules/mercury-*`
- `.codex/project/mercury-*`
- `.codex/mercury-template.lock`

SoT 侧不得创建、修改或发起上述路径的内容变更，也不通过本地补丁绕过 Mercury 源头。需要调整通用模板时，SoT 只提供需求与证据，由 Mercury 发起 Issue/PR；上游合并后，由 generator 单向生成并消费 SoT 产物。SoT 的领域 agent、配置、技能和 workflow 不因这条上游边界而转交 Mercury 管理。

当任务涉及通用 Harness 的所有权或任务合同，且生成文件已安装时，按需读取 `.codex/project/mercury-harness-ownership.md` 与 `.codex/project/mercury-task-contract.md`。这些消费合同由 Mercury generator 安装；缺失时不手工仿造，也不阻断不依赖它们的 SoT 领域工作。

本约定不改变设计库与 KB 的现有权威及安全流程，也不授权写入真实记忆或迁移历史 Mercury bucket。
