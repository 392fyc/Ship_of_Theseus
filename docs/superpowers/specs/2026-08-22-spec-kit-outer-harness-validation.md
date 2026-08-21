# Spec Kit 外层技术验证结果

**验证日期：** 2026-08-22

**独立 worktree：** `codex/spec-kit-outer-harness`

**起点：** `b5af863422a43981f9b6737d018be4b30c41f221`

**业务数据写入：** 无

## 结论

技术验证通过，但正式采用方式需要比 Spec Kit 默认初始化更轻。

推荐采用：

- 用户级只安装一个固定版本的 CLI；
- 在 `Ship_of_Theseus` 只保存一个 SoT 自有的本地 workflow；
- 通过本地 YAML 路径运行，不执行默认 `specify init`；
- Spec Kit 只保存流程状态和人工确认点，不直接调度 Codex 子代理；
- Mercury 继续使用 Codex 原生协作能力分派主代理与子代理。

这样既使用了 Spec Kit 的 workflow 和恢复能力，又不引入默认完整 SDD 流程、10 个生成 skill 和大量模板。

## 验证环境

- PyPI 最新版：`specify-cli 1.0.1`，上传时间 2026-08-21。
- GitHub 最新发布：`v1.0.1`，发布时间 2026-08-21。
- 实际命令：`uvx --from specify-cli==1.0.1 specify version`。
- 实际返回：CLI `1.0.1`、Python `3.13.12`、Windows AMD64。
- 验证结束后 `uv tool list` 返回没有持久安装的工具，说明 `uvx` 只留下可复用缓存，没有创建用户级 tool 安装。

## 默认初始化审计

在一次性目录运行：

```powershell
uvx --from specify-cli==1.0.1 specify init --here --force --non-interactive --integration codex --script ps
```

命令成功，但生成范围明显大于 SoT 外层需求：

- 共 42 个文件；
- 10 个 `speckit-*` skills；
- 完整的默认 `specify → plan → tasks → implement` workflow；
- constitution、spec、plan、tasks 模板与 PowerShell 脚本。

这些内容本身没有错误，但整体接入会把 Spec Kit 默认方法嵌入 SoT，并增加升级和切除成本。因此正式方案不提交默认初始化产物，也不依赖默认 workflow。

## 自有 workflow 验证

临时 workflow 只包含：

- `authority` 输入，枚举为 `ship`、`designlib`、`kb`；
- 一个固定 shell 输出步骤；
- 一个绑定 `approval` 输入的人工确认点；
- 一个固定结束步骤。

验证结果：

| 检查 | 结果 |
| --- | --- |
| `workflow add --dev` | 成功 |
| `workflow list` | 能同时看到默认 workflow 与临时 workflow |
| `workflow resolve` | 正确显示 3 个步骤均来自本地基础层 |
| 非法 `authority=invalid` | 拒绝，退出码 1 |
| 明确 `approval=reject` 且 `on_reject: retry` | 状态变为 `paused` |
| `workflow status --json` | 正确返回暂停步骤和运行状态 |
| `workflow resume ... approval=approve` | 成功完成 |
| 完成后的状态 | 3 个步骤均为 `completed` |

### 确认点限制

在当前非交互终端里，空白确认输入没有自动暂停，而是按拒绝结束。只有显式传入 `approval=reject` 并使用 `on_reject: retry`，才能可靠进入可恢复的暂停状态。

因此正式 workflow 必须：

- 使用具名的 `verdict_input`；
- 枚举允许值；
- 非交互运行时显式传入决定；
- 不依赖空白输入自动暂停。

## 校验能力限制

`specify-cli 1.0.1` 的 `workflow` 命令没有独立的 `validate` 子命令，尽管官方文档部分段落仍提到该命令。实际可用的结构校验入口是 `workflow add --dev`、`workflow run` 和 `workflow resolve`。

正式计划不得写一个实际不存在的 `workflow validate` 命令。需要静态检查时，以临时项目中的 `workflow add --dev` 作为校验。

## 安全与写入边界

- workflow 输入采用固定枚举；没有把自由文本拼入 shell。
- 生成的文本文件中没有发现业务仓绝对路径。
- 没有发现 API token、私钥或 NAS sudo 密码类别的内容。
- 所有 Spec Kit 命令都在独立 worktree 内的一次性目录执行。
- 未运行设计库 API、KB 工具、Godot 或生产部署命令。
- 独立 worktree 的正式变化仅为控制层文档和计划。

## 切除测试

切除验证结果：

1. `workflow remove sot-outer-spike` 成功删除已安装 workflow 目录。
2. 已有运行记录没有随 workflow 一起删除，3 个运行目录仍存在。
3. 删除整个一次性项目后，生成的 skills、默认 workflow 和运行记录全部消失。
4. 一次性项目外没有 Spec Kit 项目文件。
5. 用户级 `uv tool` 没有持久的 `specify-cli` 安装。

由此得到正式切除规则：

- `workflow remove` 只适合移除 workflow 本体；
- 完整切除还必须删除 `.specify/workflows/runs` 或整个项目运行目录；
- SoT 正式方案应把运行目录列入 `.gitignore`，不得把历史运行状态提交进仓库；
- 不使用默认初始化后，切除不会触及 `AGENTS.md`、`sot-*` skills、Ship 玩法代码、设计库或 KB。

## 采用判定

**判定：通过，按最小本地 workflow 方案采用。**

不采用以下内容：

- 默认完整 SDD workflow；
- 默认生成的 10 个 `speckit-*` skills；
- 社区 extension 或 catalog workflow；
- 让 Spec Kit 直接运行 Codex 实现任务；
- 把 Spec Kit 当成权限沙箱或业务权威。

保留以下内容：

- 固定版本 CLI；
- 一个 SoT 自有外层 workflow；
- 输入枚举、人工确认点、运行状态和恢复能力；
- 可完整删除的运行目录。
