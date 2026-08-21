# Mercury Harness Convergence Design（已取代）

## 原方案为何停止

原方案尝试用统一的机器合同约束所有任务，逐步加入：

- 冻结任务包与摘要；
- 验收项路径和用例矩阵；
- 影响范围与完整测试复用指纹；
- 十字段审查问题记录；
- 实现审查与盲验收两个固定阶段；
- 大量针对合同文字和边界变体的测试。

这些机制提高了局部严谨度，但也让外层 harness 与当前代理模型、审查方式和测试策略高度耦合。State 任务中，审查建议不断转化为新实现和新测试，主代理没有在规模明显偏离时主动停止，说明原方案对“细节正确”约束较强，对“任务何时必须结束”约束反而不足。

## 新设计决定

外层改为宽松、可替换的 Spec Kit workflow，只保留：

1. 接收任务；
2. Mercury 权威路由与规模判断；
3. 有边界的执行；
4. 一次独立核对与结束。

严格字段、复杂验证和领域测试移入具体小框架，只在相应任务中启用。这样当模型、工具或底层流程变化时，可以直接切除或替换外层，而不需要同时重写引擎、设计库和 KB 的工作合同。

## 当前权威文件

- `docs/superpowers/specs/2026-08-22-spec-kit-outer-harness-adoption.md`
- `docs/superpowers/specs/2026-08-22-spec-kit-outer-harness-validation.md`
- `docs/superpowers/plans/2026-08-22-spec-kit-harness-migration.md`

本文只保留历史决策说明，不再作为实现规格。

过渡期兼容说明：在新计划 Task 2 删除旧合同校验器和对应测试之前，历史同步测试仍会检查字面字段 `protected_scope` 与 `in_scope=false`。这两项只用于保持当前控制层测试可运行，不恢复原状态机的设计地位。
