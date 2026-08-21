# Mercury 任务收束 Harness 设计

## 背景

State 权威与连携任务暴露了一个重复出现的流程问题：任务实现本身已经接近完成，但审查范围、修复范围和测试范围会在每一轮继续增长。Task 3 经历三轮修复和四次审查；Task 4 在首次审查后继续扩充允许文件。期间多次运行约 1150 项完整测试。

根因不是单一审查者过严，而是当前 harness 同时存在以下缺口：

1. 任务起点冻结了代码提交，却没有冻结验收条目、允许路径和影响范围。
2. “实质问题”没有明确分级，候选缺陷、既有缺陷、测试强化建议和相邻风险可能全部阻断。
3. 初次审查和修复复审使用近似相同的开放检查范围。
4. 每个子任务和最终集成阶段都要求完整测试，造成重复验证。
5. 复合验收条目使用“所有”“任意异常”“完全一致”等开放表述，却没有列出有限路径和等价类。
6. 计划、任务说明、实现报告、进度台账和审查意见都可能事实性地增加验收要求。

## 目标

在不降低安全、数据完整性和用户验收要求的前提下，使实现任务具备明确终点：

- 审查只能依据冻结的任务包和候选直接影响范围作出阻断判断。
- 一次初审后形成固定修复清单；一次集中修复和一次增量复审后必须结束本任务循环。
- 定点测试、受影响测试和完整测试按风险分层调度。
- 新发现不会消失，但非阻断事项进入可追踪的后续清单，不继续扩大当前任务。
- 大型任务在派发前被拆分，而不是等到审查阶段再被动扩项。

## 非目标

- 不修改第三方 Superpowers 插件缓存或其全局行为。
- 不建立新的任务管理服务、数据库或网络接口。
- 不取消独立审查和盲验收。
- 不允许以“加快速度”为理由忽略安全问题、数据损坏、公开回归或明确验收失败。
- 不把现有 State 功能修复混入本次 harness 改动。

## 方案

采用项目级收束合同。项目的 `.codex` 配置覆盖本项目内的派发、审查和验收行为；第三方技能仍可提供工作流，但不得扩大冻结任务包，也不得强制项目进入多轮开放审查。

### 1. 冻结 ReviewBundle

每个实现任务在派发前生成一个机器可校验的 ReviewBundle。至少包含：

- `task_id` 与不可复用的 `bundle_revision`；
- 起始提交和候选提交；
- 一个 `primary_deliverable`；
- 带稳定编号的 `acceptance_criteria`；
- `allowed_write_paths`、`forbidden_paths` 与 `impact_cone`；
- 每条验收项的有限路径矩阵或输入等价类；
- `test_policy`；
- `max_repair_rounds=1`；
- 任务包规范化后的摘要值。

验收项不得只写“覆盖所有路径”或“拒绝任意异常”。需要覆盖集合时，必须列出有限矩阵，例如：

- `delete.rule_api`
- `delete.skill_api`
- `delete.talent_purge`
- `schema.missing_column`
- `schema.wrong_primary_key`
- `schema.wrong_foreign_key`
- `schema.wrong_nullability`
- `schema.wrong_type`
- `schema.extra_semantic_unique`

审查者可以指出矩阵遗漏，但不能用后来增加的条目反向判定旧任务包失败。

### 2. 派发前复杂度门

ReviewBundle 生成后先经过收束检查。以下任一情况必须先拆分任务：

- 存在两个互不依赖的主要交付物；
- 同一任务同时包含两个以上高风险变化种类：数据库结构、数据迁移、公开接口、部署流程、跨仓写入；
- 验收项无法绑定到有限路径矩阵或输入等价类；
- 允许路径只是为了“顺便修正”相邻问题而增加；
- 无法在一次集中修复内说明明确终点。

界面实现可以同时包含模板、样式和直接对应的页面测试；这些属于同一个主要交付物，不按三个任务计算。测试文件不单独计入高风险变化种类。

收束检查失败时，不派发实现者。控制方必须拆分任务或向用户重新确认范围。

### 3. 审查发现的固定分类

每个 finding 必须包含：

- `criterion_id`：对应冻结验收项；没有对应项时写 `null`；
- `introduced_by_candidate`：是否由当前候选引入；
- `in_scope`：是否位于允许路径或影响范围；
- `severity`：`critical`、`important`、`minor`；
- `disposition`：`blocking`、`follow_up`、`accepted_risk`；
- 直接证据和最小修正建议。

只有以下问题可以标为 `blocking`：

1. 明确违反冻结验收项；
2. 候选直接引入公开行为回归；
3. 候选直接造成安全问题、数据损坏或不可恢复操作；
4. 候选违反受保护路径、秘密管理或单写边界。

以下问题默认进入 `follow_up`：

- 既有问题；
- 与当前修复无关的相邻风险；
- 维护性建议；
- 非冻结验收项要求的测试强化；
- 需要新增设计裁决、实体、接口或独立迁移的范围发现；
- `minor` 级问题。

`needs_changes` 只由至少一项 `blocking` finding 产生。存在 follow-up 不妨碍进入盲验收，但必须出现在最终回执中。

### 4. 固定修复清单与单轮收束

初次审查可以检查完整候选，但必须服从冻结任务包。控制方随后一次性生成 RemediationChecklist：

- 只收录 blocking findings；
- 每项保存原 finding ID、验收项编号、修复范围和复现命令；
- 清单生成后不可增加普通 Important 或 Minor。

实现者进行一次集中修复。增量复审只检查：

- RemediationChecklist 中尚未关闭的项目；
- 本轮修复 diff；
- 修复直接影响的回归面。

只有修复新引入 Critical、使既有通过证据失效，或修改新的公开接口时，才允许增加 blocking finding。其他新发现一律进入 follow-up。

一次增量复审后仍有 blocking 项时，本任务停止继续修复。控制方只能：

- 把任务拆成新的有界任务；
- 判定原计划错误并重新设计；
- 向用户报告明确阻断。

不再允许同一任务连续五轮开放修复。

### 5. 测试分层

ReviewBundle 必须声明三层测试：

1. `focused`：直接证明验收条目的最小测试；
2. `affected`：受修改接口影响的现有测试；
3. `full`：完整回归。

调度规则：

- 初次实现：运行 focused 和 affected；
- 修复轮：只运行失败复现测试和直接受影响测试；
- RemediationChecklist 关闭后：运行一次 full；
- 若紧接最终验收，且候选提交、依赖锁、测试配置和环境摘要均未变化，最终验收复用该 full 证据；
- full 后代码发生变化，只先运行直接受影响测试；所有修复收束后再运行一次最终 full。

依赖文件、全局测试配置、启动框架、数据库启动前置流程或通用 fixture 发生变化时，可以提前要求 full，但必须在 ReviewBundle 的 `full_triggers` 中明确登记，不能由审查者临时扩大。

### 6. 权威优先级

验收来源按以下顺序解释：

1. 项目安全、单写和破坏性操作合同；
2. 冻结 ReviewBundle；
3. ReviewBundle 明确引用的规格段落；
4. 实现报告，仅作为证据索引；
5. 进度台账和历史裁决，只有被新 ReviewBundle 以稳定编号引用时才形成约束。

实现者自评、报告中的疑虑和 reviewer 的范围发现都不能自动生成新验收项。

## 项目文件

实现阶段修改以下项目级文件：

- `.codex/project/mercury-task-contract.md`：加入冻结任务包、finding 分类、修复轮次和测试分层合同；
- `.codex/agents/mercury-dev.toml`：要求实现者服从任务版本、测试层级和一次修复预算；
- `.codex/agents/mercury-reviewer.toml`：要求结构化 finding，并限制初审与增量复审的边界；
- `.codex/agents/mercury-acceptance.toml`：只按冻结验收项判定，follow-up 不得冒充失败；
- `.codex/project/task-bundle.schema.json`：ReviewBundle 的结构合同；
- `.codex/project/review-result.schema.json`：finding 和 verdict 的结构合同；
- `.codex/project/validate_harness_bundle.py`：只使用 Python 标准库的轻量校验器；
- `.codex/project/tests/test_validate_harness_bundle.py`：收束规则测试。

校验器不理解自然语言，也不替代控制方判断。它只保证版本、编号、有限矩阵、风险种类、测试层级、修复预算和 finding disposition 不被遗漏或互相矛盾。

## 数据流

1. 控制方根据用户确认范围生成 ReviewBundle。
2. 校验器检查结构、复杂度和测试策略；失败则不派发。
3. 实现者按冻结任务包修改并返回证据。
4. 初审 reviewer 返回结构化 ReviewResult。
5. 控制方把 blocking findings 固定为 RemediationChecklist。
6. 实现者执行一次集中修复。
7. 增量 reviewer 只核对清单和修复 diff。
8. 清单关闭后运行一次 full，并生成盲验收包。
9. follow-up 和 accepted risk 写入最终回执，不重新打开当前任务。

## 失败处理

- Bundle 校验失败：停止派发，报告具体字段或复杂度冲突。
- Reviewer 找不到 criterion ID：只能作为 follow-up，除非有候选直接引入的安全、数据损坏或公开回归证据。
- 增量复审出现范围外新发现：记录 follow-up，不增加修复轮。
- 一次修复后仍有 blocking：停止当前任务，拆分或重新设计。
- 完整测试失败：若由候选引入，作为 blocking；若为可复现的既有失败，记录基线证据并单独处理。

## 验证方案

校验器测试至少覆盖：

- 缺少稳定 criterion ID 时拒绝；
- 开放式验收项没有有限矩阵时拒绝；
- 同一任务包含多个独立主要交付物时拒绝；
- 同时包含两个以上高风险变化种类时拒绝；
- `max_repair_rounds` 不等于 1 时拒绝；
- 缺少 focused、affected 或 full 策略时拒绝；
- Minor、既有问题和范围外问题不能标为 blocking；
- 无 criterion ID 的普通 Important 不能阻断；
- 候选直接引入的安全、数据损坏或公开回归允许无 criterion ID 阻断；
- 增量复审不得加入与修复 diff 无关的普通 blocking；
- 只有 follow-up 的 ReviewResult 可以进入盲验收；
- bundle revision 或摘要不匹配时拒绝复用旧审查结果；
- 相同提交和环境摘要下允许复用完整测试证据。

## 当前 State 任务的恢复方式

Harness 通过独立验收后，当前未提交的 Task 4 修复保持原样，不重新实现。控制方基于首次审查生成新的冻结任务包：

- 原首次审查中有直接复现证据且属于既定连携合同的项目进入固定修复清单；
- activation-point 更新路径已经存在并通过定点测试，作为证据关闭，不形成新功能；
- 物理结构测试扩充中与冻结矩阵一致的部分保留，矩阵外继续枚举的变体不再扩展；
- 当前修复只允许一次增量复审；
- 清单关闭后运行一次完整测试。

随后剩余工作重新拆分为单一交付物任务：确定性快照往返、合同完整度报告、State 编辑界面、菱形示意图。每项分别通过收束检查，不再把导入导出、报告、界面和视觉修正放入同一任务包。

