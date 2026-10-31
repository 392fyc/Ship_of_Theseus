# Mercury Harness 消费约定

SoT 负责游戏仓、设计库 app/tests/scripts、KB 和 SoT 领域 workflow。领域 agent、配置、技能和 workflow 属于 SoT，可以在 SoT 仓独立维护。

Mercury 只维护它装载到本仓库的通用 Harness 路径，每个文件的哈希记录在 `.mercury/lock.json`：

- `.mercury/packs/`、`.mercury/lock.json`
- `.codex/agents/mercury-*`、`.claude/agents/mercury-*`
- `.codex/rules/mercury-*`
- `.agents/skills/mercury-*`、`.claude/skills/mercury-*`
- `.github/workflows/mercury-*.yml`
- `AGENTS.md` 与 `CLAUDE.md` 中 `MERCURY:BEGIN` 与 `MERCURY:END` 之间的受管段

`.mercury/config.json` 由 SoT 维护：它选择 pack，设置集成分支、必需检查、只读守卫的写入脚本等参数，并声明关联库（设计库的职责、定位、快速利用方式与规则，渲染进受管段；KB 在本仓库 `docs/`，不再是关联库）。

SoT 自有的领域角色与技能放在 Mercury 项目区，与上面的受管路径分开：

- 清单 `.mercury/local.json` 与角色来源 `.mercury/local/roles/<角色>.md` 由 SoT 维护；技能正文留在清单声明的目录（`.agents/skills/sot-*/`，Claude 专用的 `sot-art-review` 在 `.claude/skills/sot-art-review/`）。
- Mercury 安装器据此生成 `.claude/agents/<角色>.md`、`.codex/agents/<角色>.toml` 和 `.claude/skills/<技能>/SKILL.md` 入口，并在 `.mercury/lock.json` 的 `local` 一节记录哈希。生成物被手改时安装器停止。
- 新建、修改、退役：改清单或来源，再从已发布的 Mercury 提交运行 `apply`。退役只删除锁里记录过的生成物。Mercury 更新 PR 不会改动项目区。

SoT 侧不得创建、修改或发起上述受管路径的内容变更，也不通过本地补丁绕过 Mercury 源头；手改受管文件会让下一次装载停止。需要调整通用 Harness 时，SoT 只提供需求与证据，由 Mercury 发起 Issue/PR；Mercury 发布到 `master` 后，由 `Mercury update` 工作流开更新 PR 单向生成并消费 SoT 产物，或在修改 `.mercury/config.json` 后从已发布的 Mercury 提交运行安装器。SoT 的领域 agent、配置、技能和 workflow 不因这条上游边界而转交 Mercury 管理。

当任务涉及通用 Harness 的所有权或任务合同时，按需读取 `.mercury/packs/core/docs/mercury-harness-ownership.md` 与 `.mercury/packs/core/docs/mercury-task-contract.md`。这些消费合同由 Mercury 安装；缺失时不手工仿造，也不阻断不依赖它们的 SoT 领域工作。

本约定不改变设计库与 KB 的现有权威及安全流程，也不授权写入真实记忆或迁移历史 Mercury bucket。
