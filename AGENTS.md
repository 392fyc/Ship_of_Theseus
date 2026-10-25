# Ship of Theseus — Codex 项目入口

本仓库是 SoT 日常开发的默认 Codex 工作根。Codex 从仓库根启动，优先读取本文件、项目级 `.codex/` 配置与 `.agents/skills/` 中的项目技能。

## 工作区位置与生命周期

日常 Codex 从游戏主仓 `Ship_of_Theseus` 进入。三个主仓平级，任务工作树只建在所属仓库根的 `.worktrees/<task>/`（被 Git 忽略），不在仓库外另建目录组。任务工作树不得用父目录猜测设计库、KB 或游戏主仓；先用环境变量，再回退到被忽略的本地 roots 配置，缺少配置时停止猜测。

游戏主仓由 `SOT_SHIP_ROOT` / `[roots].ship_root` 解析；任务组由 `[worktrees].ship_root`、`designlib_root`、`kb_root` 或对应 `SOT_*_WORKTREE_ROOT` 解析。使用 `scripts/codex/sot-worktree.ps1` 列出、检查和创建游戏/设计库任务树。KB 继续使用固定 vault 的任务分支，不能另开任务 vault。PR 合并后立即删除 worktree 与本地分支（远端分支由 GitHub 合并后自动删除）；未合入就废弃的分支列出清单，经用户确认后连同远端一并删除；`main`、`master`、`develop` 与默认分支永不删除。删除前核对 dirty、untracked、ignored 与实际合入证据，不按年龄或关闭 PR 单独判定。详见 [工作树生命周期](docs/worktree-lifecycle.md)。

## Language

设计文档与用户沟通使用简体中文；代码标识符、命令、接口和专有名词按项目既有约定保留英文。

## 产物清晰度

- 现行设计、代码注释、handoff 和任务卡只保存当前有效结论、必要约束、真实未决问题、证据与下一步。
- 持久化审查以完整命题为单位；历史记录进入 ADR、Research、明确归档区或 Git 历史，并退出默认读取链。
- 范围外发现只登记位置、类别和所需权威，不扩展当前任务。

## 用户问题与前提

- 直接回答用户实际提出的问题，不得擅自补写、替换或否定用户没有表达过的前提。
- 禁止使用“你问的不是……而是……”“你需要的不是……而是……”等句式替用户重新定义问题；即使后续内容本身正确，这种虚构前提的回答也不允许。
- 需要指出理解差异时，先逐字依据用户已经给出的信息说明差异；缺少必要信息时，明确指出缺少哪一项。不得先假设用户持有某种观点，再对该假设进行纠正。
- 复述用户意图只用于核对已明确的要求，不得把代理自己的方案、分类或判断伪装成用户原有意图。

## Project

战棋 RPG + Roguelite + 城镇建设，Godot 4.6（GDScript），JSON 驱动，采用可序列化的 `GameAction` 指令架构。

## 权威路由

- 结构化玩法目标事实（天赋、技能、规则、装备、遗物及相关结构化数据）→ `SoT-fyc-space` 设计库。
- 当前可执行运行行为与已经落地的实现事实 → 本 `Ship_of_Theseus` 游戏仓。
- 叙事、定性设计、用户裁决、ADR、研究和工作记录 → 独立 KB。
- 任务范围、进度与验收证据 → GitHub/Git。
- 活跃记忆与会话锚点 → 配置的活跃记忆根；未配置时使用游戏仓主 Git 工作树中的 `.sot/memory`。

权威之间冲突时，先按上述类型确定唯一来源，不在第二处复制或反向覆盖。KB 中的规则目录仅供检索，结构化规则仍以设计库为准。

## SoT 与 Mercury Harness 所有权

- SoT 自主维护游戏仓、设计库 app/tests/scripts、KB，以及领域 agent、配置、技能和 workflow。上述领域入口可以在 SoT 仓内直接维护。
- Mercury 只拥有通用 Harness 模板 upstream 清单路径：`.codex/agents/mercury-*`、`.codex/rules/mercury-*`、`.codex/project/mercury-*` 和 `.codex/mercury-template.lock`。SoT 侧不得创建、修改或发起这些路径的内容变更。
- 需要调整通用模板时，SoT 只提供需求与证据，由 Mercury 发起 Issue/PR；上游合并后再单向生成并消费 SoT 产物。不得在 SoT 反向修改生成源或锁文件。
- 会话涉及通用 Harness 所有权或任务合同且对应文件已安装时，按需读取 `.codex/project/mercury-harness-ownership.md`、`.codex/project/mercury-task-contract.md` 与 `.codex/project/mercury-lane-contract.md`。这些合同由 Mercury generator 安装；文件缺失时不仿造、不阻断无关领域工作。

## 活跃记忆根

按 `SOT_MEMORY_ROOT`、当前仓被忽略的 `.codex/project/sot-roots.local.toml` 中 `[roots].memory_root`、游戏仓主 Git 工作树的 `.sot/memory` 顺序解析。确定主工作树时使用当前仓共享的 Git common directory 与 `git worktree list --porcelain`，不得把任务 worktree 路径用作项目记忆根或 bucket 身份。默认记忆目录或索引缺失时如实报告，并继续可独立完成的工作。旧 Mercury bucket 只有在显式配置为 `memory_root` 时才可只读访问；迁移必须由用户授权。

## 多 Lane 多 Agent 协作

- lane 是用户声明的工作路线，不是 agent。一条 lane 至多 1 个 Codex 会话与 1 个 Claude Code 会话，外加其他 worker；其中主导宿主掌握正式判断，另一宿主可介入审查等作业但不取代主导地位，主导宿主只在创建 lane 时或用户要求时改变。agent 介入已有 lane 不另开 lane。lane 只凭用户声明创建、改派或关闭，会话以 `[LANE=<代号>]` 确定 lane，没有时询问用户，不按工作内容推断。
- 注册簿是活跃记忆 bucket 下的 `LANES.md`；各 lane 只改自己的小节与 `lanes/<代号>/` 目录，handoff 按宿主分文件，共享记忆文件按读取时的 sha256 做版本条件写入。
- 主工作区不做开发；Issue / PR 加 `lane:<代号>` 标签，分支用 `<agent>/<lane>/<任务>`。跨 lane 消息不是用户授权；交叉影响开协调 Issue 由用户裁决。
- 被禁止的裸命令使用受控入口：发布 `sot-publish.ps1`、同步基准 `sot-sync.ps1`、工作树 `sot-worktree.ps1`、共享记忆 `sot-memory.ps1 -Action Write`。完整协议见 [多 Lane 多 Agent 协作](docs/lane-collaboration.md)。

## 跨仓读取与写入

- 读取或修改设计库、KB、Mercury 前，使用项目本地 roots 配置或环境变量解析目标，不在版本控制文件中写本机绝对路径。
- KB 只有一个固定的 Obsidian vault 入口，由 `SOT_KB_ROOT` 或项目本地 roots 中的 `kb_root` 解析；不得把任务 worktree 另开为第二个 vault，也不得为任务临时切换 MCP endpoint。KB 的任务隔离由固定 vault 内检出的 Git 分支提供。
- 写入 KB 前，必须确认固定 vault 的 Git 工作区干净，并把固定 vault 切换到目标任务分支。若该分支已被其他 worktree 占用，只能在确认对方干净且无人使用后，将其置于 detached HEAD 解除占用；不得为释放分支而自动移除 worktree。否则停止并协调，不得用 `--ignore-other-worktrees`、第二 vault、stash、reset 或丢弃改动绕过。合并完成后，将固定 vault 切回并快进到受保护的默认分支，再删除已合入的本地任务分支。
- 跨仓写入前必须读取目标仓 `AGENTS.md`（若存在）与目标 canonical 合同，并在交付回执中记录目标 HEAD 和合同摘要。
- 不覆盖目标主工作树的受保护改动；代码与结构化设计库变更只在目标仓独立 worktree 中完成，KB 按上述固定 vault 分支流程执行。
- 设计库与 KB 的具体安全读写流程分别由 `sot-designlib` 和 `sot-kb-write` 技能定义。

## Security

- 禁止在版本控制文件、日志、回执或聊天输出中写入 API key、secret、token、私钥、密码或其他凭据。
- 本机 roots、凭据和运行时连接参数只能来自被忽略的本地配置或受保护环境变量。
- 秘密扫描只报告类别、文件范围与处置结果，不输出匹配文本。

## GDScript 约束

- `class_name` 与 autoload 同名时，autoload 脚本移除 `class_name`。
- `Variant` 推断不明确时显式声明变量类型。
- 禁止在代码中硬编码玩法数值；从 JSON 或对应权威数据读取。
- 信号使用过去式命名，例如 `signal damage_dealt`。
- 游戏操作封装为可序列化的 `GameAction`。

## 玩法事实核对

修改战斗、技能、伤害或资源规则前，使用 `sot-designlib` 读取设计库现行记录，并记录来源快照或提交与规范化摘要。规则未列出的因素不得自行补入公式；需要新增设计裁决时，将问题交给用户并把裁决理由写入 KB。

## 工作层级与连续推进

- `Milestone` 是用户要取得的阶段成果；`Task` 是其中一项可独立验收的工作；`Subtask` 是完成某个 Task 所需的实现、审查或验证步骤。
- 完成 Task 不等于完成 Milestone。Task 结束时应报告该项结果和 Milestone 当前状态，不得把局部完成表述为阶段成果已经完成。
- 只有全部必需 Task 均已验收，并且没有已知的必需工作遗留时，才可宣布 Milestone 完成。
- 制定计划时必须先写明 Milestone 的阶段成果与完成条件，再列出所含 Task；实现、独立审查、PR 合并、必要的迁移或部署、生成式快照和合并后核验，只要属于该阶段的交付路径，就必须作为明确 Task 纳入完成条件。
- 创建 PR 只表示相应 Task 进入集成阶段，不等于 Task 已合并，更不等于 Milestone 完成。既定路线包含审查、合并或发布时，Main 必须继续到相应结果经过核验，不能停在 PR URL。
- Milestone 内仍有已知且未阻塞的下一个 Task，并且其范围与顺序已由用户或获批计划确定时，Main 必须自动继续，无需再次确认。
- 只有 Milestone 已完成、继续工作确实需要用户作出新的裁决或授权，或用户明确要求暂停时，Main 才停止推进并交还控制权。
- 连续推进只适用于已知工作；不得自行增加新的 Task 来延长 Milestone，也不得借推进之名扩大既定范围。

## Git 与交付

- 不直接提交或推送到 `develop`、`main`、`master`。
- Ship 与设计库从目标仓任务 worktree 调用 Ship 根的 `scripts/codex/sot-publish.ps1`；KB 从固定 vault 当前检出的任务分支调用同一入口。该入口通过 `SOT_DESIGNLIB_ROOT` 与 `SOT_KB_ROOT` 授权跨仓发布。不得因目标仓没有同名脚本而判定发布阻断，也不得改用原始 `git push`。
- 只修改任务声明的文件范围，不夹带用户已有 dirty 文件。
- 实现者不得自我批准；提交前由独立审查者核对规格与证据。
- 子任务结束时使用 `sot-task-receipt` 返回结构化回执。
