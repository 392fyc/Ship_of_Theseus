# Spec Kit 外层技术验证计划

> 本计划只验证 Spec Kit 能否成为可替换的 SoT 外层流程。验证不修改 Ship 玩法代码或数据，不读取或写入设计库与 KB 业务内容，不安装社区扩展。

**目标：** 用固定版本 `specify-cli==1.0.1` 在一次性临时项目中验证 Codex 集成、最小 workflow、运行恢复和完整切除，再据此重写剩余 harness 计划。

**工作区：** 独立 worktree 分支 `codex/spec-kit-outer-harness`。所有临时运行内容放在 worktree 根下的 `.spec-kit-spike-temp` 一次性目录；验证结束后完整删除。仓库内只保存方案、计划和验证结论。

**验证原则：** 只验证外层流程所需能力，不验证 Spec Kit 的全部命令，不建立生产 workflow，不写三库业务数据。

## Task 1：确认版本与生成边界

**允许写入：** 无仓库文件写入。

1. 核对 PyPI `specify-cli 1.0.1` 与 GitHub `v1.0.1` 的发布时间和版本一致。
2. 用 `uvx --from specify-cli==1.0.1 specify version` 验证固定版本可运行。
3. 在一次性临时目录初始化 Codex 集成。
4. 记录生成文件，只检查文件位置和类型，不读取或传入任何业务数据。

**通过条件：** CLI 版本准确；所有生成文件都位于临时项目根内；没有用户凭据或绝对业务仓路径写入生成内容。

## Task 2：验证最小 workflow

**允许写入：** 一次性临时项目。

创建一个仅含控制信息的本地 workflow，输入只允许三个固定值：`ship`、`designlib`、`kb`。该 workflow：

1. 记录选定的权威名称；
2. 通过固定分支生成不同的只读提示；
3. 在人工确认点暂停；
4. 恢复后结束，并留下运行状态。

不得调用 Codex 执行业务任务，不得用自由文本拼接 shell 命令，不得访问三个业务仓。

验证命令仅覆盖：

- 通过 `workflow add --dev` 执行结构校验；
- workflow add/list/resolve；
- workflow run/status/resume；
- workflow remove。

**通过条件：** workflow 能安装、运行、在确认点暂停、恢复和结束；状态只存在临时项目；非法权威值被拒绝或无法进入业务分支。

**执行注记：** `specify-cli 1.0.1` 实际没有独立的 `workflow validate` 子命令，因此按真实 CLI 改用 `workflow add --dev`。空白确认输入在当前非交互终端会直接按拒绝结束；使用 `on_reject: retry` 并显式传入 `reject` 后可以可靠暂停，再以 `approve` 恢复完成。

## Task 3：执行切除测试

**允许写入：** 一次性临时项目。

1. 移除本地 workflow。
2. 删除 Spec Kit 在临时项目生成的目录。
3. 检查临时项目外没有新增 Spec Kit 文件。
4. 对三个业务仓只运行 `git status --short` 和基线文件清单比较。
5. 删除一次性临时目录。

**通过条件：** 切除不需要修改任何业务仓；原有 `sot-*` skills 与 `AGENTS.md` 不受影响；不留下运行中进程或用户级持久安装。

## Task 4：重写剩余 harness 计划

**仓库文件：**

- 修改：`docs/superpowers/plans/2026-08-22-mercury-harness-convergence.md`
- 修改：`dev_doc/mercury-harness-convergence-design-2026-08.md`
- 新建：`docs/superpowers/plans/2026-08-22-spec-kit-harness-migration.md`
- 新建：`docs/superpowers/specs/2026-08-22-spec-kit-outer-harness-validation.md`

根据实际验证结果：

1. 写明 Spec Kit 可用能力、限制和切除证据。
2. 把旧 harness 计划标记为被新计划取代，不继续执行原有复杂状态机。
3. 列出应该删除或简化的旧校验器、JSON Schema、测试和代理提示。
4. 只保留最小 Mercury 合同、一次独立核对、按风险分层的验证和领域小框架入口。
5. 将未完成 State 工作重新拆成独立、可收束的小任务，不在本次验证中继续实现。

## Task 5：独立核对

安排一个只读核对者，只检查：

- 是否符合用户批准的外层/小框架分层；
- 是否有业务数据写入或跨仓越界；
- 技术验证证据是否支持采用结论；
- 旧 harness 删除清单是否真正降低维护面；
- 切除测试是否完整。

核对者最多返回 3 个当前范围内的阻断问题，不提出新功能，不扩大测试矩阵。若需要一次修正，只处理这 3 项；再次出现范围扩张时立即中止并向用户报告。

## 最终验证

只运行与本次控制层变化直接相关的检查：

```powershell
python -m unittest discover -s .codex/project/tests -p "test_*.py" -v
git diff --check
git status --short --branch
git diff --name-only b5af863422a43981f9b6737d018be4b30c41f221..HEAD
```

不运行 Godot、设计库或 KB 的完整测试，因为本次没有修改这些系统。不得 push、部署或写生产数据。
