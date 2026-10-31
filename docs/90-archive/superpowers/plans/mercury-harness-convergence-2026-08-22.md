# Mercury Harness Convergence Plan（已取代）

**状态：** 不再执行。

本计划原本通过冻结任务包、双重 JSON Schema、摘要绑定、验收项矩阵、分层测试指纹和两阶段审查来约束任务收束。实际执行证明，这些机制让控制层本身成为持续扩展的实现项目，并没有及时阻止审查范围和测试范围增长。

用户已决定采用更轻的外层：

- Spec Kit 只保存最小外层 workflow 与运行状态；
- Mercury 负责权威路由、任务拆分和子代理约束；
- 具体工作由独立的小框架提供严格流程；
- 外层不保留复杂 ReviewBundle/ReviewResult 状态机；
- 一次任务最多一次汇总式修正，再次扩张即中止。

后续实施只参考：

- 采用方案：`docs/superpowers/specs/2026-08-22-spec-kit-outer-harness-adoption.md`
- 技术验证：`docs/superpowers/specs/2026-08-22-spec-kit-outer-harness-validation.md`
- 新计划：`docs/superpowers/plans/2026-08-22-spec-kit-harness-migration.md`

旧计划中的未完成步骤、测试要求和审查轮次均不再具有执行效力。

过渡期兼容说明：在新计划 Task 2 删除旧合同校验器和对应测试之前，历史同步测试仍会检查字面字段 `protected_scope` 与 `in_scope=false`。这两项只用于保持当前控制层测试可运行，不恢复原状态机的执行效力。
