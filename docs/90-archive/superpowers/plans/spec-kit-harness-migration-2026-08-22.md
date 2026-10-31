# Spec Kit 外层与 Mercury Harness 精简计划

> 本计划取代 `2026-08-22-mercury-harness-convergence.md`。执行时只处理控制层；State、技能、天赋、设计库快照、KB 和 Godot 内容各自另开有边界的小任务。

**目标：** 用一个最小 Spec Kit workflow 替代当前过重的全局 harness 状态机，同时强化主代理和子代理的任务边界、规模判断和停止条件。

**采用依据：** `docs/superpowers/specs/2026-08-22-spec-kit-outer-harness-validation.md`

## 总体约束

- 正式 CLI 固定为 `specify-cli==1.0.1`，只安装在 Windows 当前用户的 `uv tool` 环境。
- 项目内只保留一个 SoT 自有 workflow 源文件；不执行或提交默认 `specify init` 产物。
- workflow 不直接运行 Codex prompt，不调用设计库或 KB，不执行业务 shell 命令。
- Mercury 保留权威路由、任务拆分、子代理分发和风险升级。
- 主会话不设置 token 预算。
- 子代理只接收一个主要交付物、允许写入范围、停止条件和与规模相称的预算级别。
- 每项任务最多一次汇总式修正；再次出现扩展范围时中止，而不是继续增加测试。

## Task 1：落最小 Spec Kit 外层 workflow

**预计规模：** S

**建议执行者：** 一个实现子代理或主代理直接完成

**允许文件：**

- 新建：`.codex/project/workflows/sot-outer.yml`
- 修改：`.gitignore`
- 新建：`.codex/project/tests/test_sot_outer_workflow.py`

workflow 只完成四件事：

1. 接收 `authority`、`task_size`、`approval` 三个枚举输入；
2. 输出固定的路由和规模提示；
3. 在开始写入前进入显式确认点；
4. 确认后结束并保留运行状态。

不得包含 loop、fan-out、fan-in、agent prompt、业务命令或自由文本 shell 插值。

测试只覆盖：

- 用固定版本在临时项目执行 `workflow add --dev`；
- 三个输入枚举拒绝非法值；
- `reject + retry` 可暂停；
- `approve` 可恢复完成；
- `.specify/workflows/runs/` 被忽略。

不建立新的 Python workflow 解释器，不测试 Spec Kit 内部所有字段。

## Task 2：删除旧全局状态机

**预计规模：** M

**建议执行者：** 一个实现子代理

**允许文件：**

- 删除：`.codex/project/task-bundle.schema.json`
- 删除：`.codex/project/review-result.schema.json`
- 删除：`.codex/project/validate_harness_bundle.py`
- 删除：`.codex/project/tests/test_validate_harness_bundle.py`
- 删除：`.codex/project/tests/test_mercury_contracts.py`
- 修改：`.codex/project/mercury-task-contract.md`
- 修改：`.codex/agents/mercury-dev.toml`
- 修改：`.codex/agents/mercury-reviewer.toml`
- 删除：`.codex/agents/mercury-acceptance.toml`

删除以下外层机制：

- bundle revision 和强制 SHA；
- 验收项的路径×用例矩阵；
- impact cone；
- 完整测试复用指纹；
- 10 字段 finding 记录；
- initial/remediation 两套 ReviewResult；
- 独立 acceptance 角色的第二次重复验收；
- 绑定上述字段的 45 个自定义测试。

保留并改写为一页任务卡：

- 目标与交付物；
- 目标仓、起始提交和允许写入范围；
- 不处理的相邻问题；
- 3 条以内可观察验收条件；
- 聚焦验证命令；
- 何时需要受影响测试或完整测试；
- 任务规模 S/M/L；
- 子代理预算级别；
- 停止和升级条件；
- 一次独立核对。

`mercury-reviewer` 最多返回 3 个当前范围内的阻断问题。普通改进、既有问题和额外测试建议进入后续清单，不改变当前结论。

删除独立 `mercury-acceptance` 后，高风险小框架仍可自行要求盲验收；这不再是所有任务的全局必经步骤。

## Task 3：强化子代理分发合同

**预计规模：** S

**允许文件：**

- 修改：`.codex/project/mercury-task-contract.md`
- 修改：`.codex/agents/mercury-dev.toml`
- 修改：`.codex/agents/mercury-reviewer.toml`

每次下发必须包含：

- 单一主要交付物；
- 明确允许和禁止写入范围；
- 只读前置材料；
- S/M/L 规模；
- 子代理预算级别；
- 最多允许的测试层级；
- 最多一次汇总式修正；
- “发现规模偏差、需要新增交付物、需要扩大文件范围时立即停止”的指令；
- “不得因为审查者建议而自动接纳范围外工作”的指令。

预算级别不在主会话启用，只写入子代理任务：

- `S`：短任务，目标是单文件或少量局部变化；
- `M`：标准任务，一个清楚的多文件交付物；
- `L`：只有无法再拆分的复杂核心问题才使用。

具体 token 数值不固化进长期合同。模型升级、上下文变化或实践数据变化时，只调整本地分发配置，不修改外层 workflow。

## Task 4：切除演练与独立核对

**预计规模：** S

**允许文件：** 控制层和临时目录，不改业务文件。

执行两条路径：

### 启用路径

1. `uv tool install specify-cli==1.0.1`。
2. 在临时目录通过 `workflow add --dev` 校验 SoT workflow。
3. 运行一次暂停与恢复。
4. 核对运行记录只在 `.specify/workflows/runs/`。

### 切除路径

1. `uv tool uninstall specify-cli`。
2. 删除 `.specify/workflows/runs/`。
3. 临时移除 SoT workflow 源文件后，确认原有 `AGENTS.md` 与 `sot-*` skills 仍可独立使用。
4. 恢复 workflow 源文件，仅用于完成候选提交。

独立核对者只检查方案目标、实际 diff、启用/切除证据和无业务写入。最多 3 个阻断问题，不扩大测试范围。

## Task 5：按新协议恢复剩余 State 工作

Harness 精简独立通过后，再处理先前暂停的 State 工作。不得把以下项目重新合并成一个大任务。

### 5A：冻结并核对既有 B1 提交

- 只核对既有候选 `20901bff772e5cd38b0c7c2ec0d640fa1970284b` 与原范围；
- 不新增完整性变体；
- 一个只读核对者，最多 3 个阻断问题；
- 通过后结束，不顺带开始 B2。

### 5B：部署探针 B2

- 只处理 `scripts/deploy.sh`、`tests/test_deploy_state_migration_contract.py`、`tests/test_state_schema.py`；
- 先判定现有脏文件需要保留、合并还是废弃；
- 只验证 State 顶层字段探针和部署前失败顺序；
- 不回到 State API、链接模型或导入逻辑。

### 5C：确定性快照往返

- 单独任务；
- 不包含 State UI、菱形示意图或 KB 文档。

### 5D：State 编辑界面

- 单独任务；
- 页面和 API 编辑边界按既有 `/skills` 只读合同处理。

### 5E：距离与范围菱形示意图

- 单独视觉任务；
- 只改预览模板、CSS、说明文案和对应聚焦测试；
- 不改距离或范围计算语义。

若任何子任务再次出现第二个主要交付物、第四个阻断建议或新增测试矩阵，主代理必须中止该子任务并向用户报告规模偏差。

## 最终验证范围

Harness 迁移只运行：

```powershell
python -m unittest discover -s .codex/project/tests -p "test_sot_outer_workflow.py" -v
python -c "import tomllib, pathlib; [tomllib.loads(p.read_text(encoding='utf-8')) for p in pathlib.Path('.codex/agents').glob('mercury-*.toml')]"
git diff --check
git status --short --branch
```

不运行 Godot、设计库或 KB 全量测试。只有 Task 5 中相应小任务自己的风险条件满足时，才运行各自受影响或完整测试。
