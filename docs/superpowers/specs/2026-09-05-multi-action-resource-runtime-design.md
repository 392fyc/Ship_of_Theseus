# 多行动点运行时设计

**状态：** 已批准，进入实施计划与测试先行实现。

**Task ID：** `HUD-PROD-1B-MULTI-ACTION-RUNTIME`

**前置基线：** `HUD-PROD-1A-CANDIDATE-BASELINE-FREEZE`，候选提交 `ffadf60a126e668b15732cf691ddf2b8a31d5439`。

## 1. Milestone 与本 Task 的阶段成果

`HUD-PROD-1` 的阶段目标是把通过候选验证的底部 HUD 组件逐项接入正式战斗界面，并让正式数据合同能表达实际玩法状态。

当前任务序列如下：

| Task | 阶段成果 | 当前状态 |
| --- | --- | --- |
| `HUD-PROD-1A` | 冻结已通过的候选组件、素材和验证清单 | 已完成，提交 `ffadf60a` |
| `HUD-PROD-1B` | 建立标准与迅捷行动点的 1 至 3 点运行时模型 | 实施中 |
| `HUD-PROD-1C` | 用真实容量与剩余量切换正式行动资源条 | 规格已批准，等待 1B |

本 Task 只有一个主交付物：可由战斗结算真实消费的多行动点运行时基础。它不负责行动资源条的正式视觉切换，也不等于 `HUD-PROD-1` Milestone 完成。

## 2. 设计权威与已确认规则

设计库活库的锁定规则已在本轮更新并逐条回读：

- `R3.2`，id `15`，`updated_by=codex`，`updated_at=2026-09-04T21:00:28.592312`；规范化 SHA-256 为 `c9941a1be216086770b118eb4ad71d6b1e342c5952b2641dc70ce9c1e4640064`。
- `R3.3`，id `16`，`updated_by=codex`，`updated_at=2026-09-04T21:00:43.159353`；规范化 SHA-256 为 `0214c882a77d0159432e8fb0d5764d17f12fecec8e84f7bf0f075b34d4f169f8`。
- 完整 `/api/rules` 为 `unversioned`、29 条，写后规范化 SHA-256 为 `43eaec334b7e54c37ba9780c10a66c00255a0b198650f4d2f67da02f0f3eb205`。
- 既有导出器完成两轮一致性读取；独立临时导出的 `rules.json` 文件 SHA-256 为 `79994D8B251CD42A9F0C197D237C62FDE5EA93BEFCFC08F0715DE7CBCD7342EE`。

本 Task 必须实现以下现行规则：

1. 标准行动点和迅捷行动点的默认容量均为 1，合法容量均为 1 至 3；当前职业、天赋、装备和技能不授予额外容量。
2. 每个对应动作消费 1 点；单位回合开始时恢复至各自容量。第一次消费标准行动点就使剩余移动失效，但只要仍有标准行动点，就仍可继续执行标准动作。
3. `before_attack` 表示本回合尚未消费标准行动点，`after_attack` 表示本回合已经消费至少 1 点；判据不取决于标准行动点是否耗尽。
4. 迅捷动作不绕过迅捷行动点。真正不消费行动资源的技能使用 `action_cost: "free"`。
5. “再行动”具体恢复哪一种资源、恢复多少，由未来效果文字决定；本 Task 不预设统一恢复量。

额外行动点的获得条件仍未设计。本 Task 只建立运行能力和测试注入入口，不向任何正式内容发放第 2 或第 3 点。

## 3. 运行时状态模型

`Unit` 使用以下字段作为唯一权威状态：

| 字段 | 类型与默认值 | 约束与含义 |
| --- | --- | --- |
| `movement_used` | `bool = false` | 本回合的移动机会是否已经失效 |
| `standard_capacity` | `int = 1` | 标准行动点容量，限制在 1 至 3 |
| `standard_remaining` | `int = 1` | 当前剩余标准行动点，限制在 0 至容量 |
| `standard_spent_this_turn` | `int = 0` | 本回合实际消费的标准行动点累计数；只在回合重置时清零 |
| `swift_capacity` | `int = 1` | 迅捷行动点容量，限制在 1 至 3 |
| `swift_remaining` | `int = 1` | 当前剩余迅捷行动点，限制在 0 至容量 |
| `reaction_available` | `bool = true` | 现行反应机会，语义不变 |

`standard_spent_this_turn` 与剩余量分开保存。这样未来某个明确效果恢复标准行动点后，`after_attack` 仍然保持为真，不会因为剩余量回升而错误回到 `before_attack`。

`Unit` 提供一个只供单位初始化和自动测试使用的容量配置入口，同时设置两类容量、把剩余量回满并把本回合累计消费清零。输入统一限制到 1 至 3。正式职业数据本期不调用该入口；战斗中途改变容量的规则也不在本期定义。

## 4. 消费、刷新与查询合同

### 4.1 回合开始

现有 `reset_action_resources()` 保留为唯一满额刷新入口：

- `movement_used=false`；
- 两类 `remaining` 恢复到各自 `capacity`；
- `standard_spent_this_turn=0`；
- `reaction_available=true`。

它由现有回合开始路径调用，不新增存档或部署数据来源。

### 4.2 标准行动

- 校验条件是 `standard_remaining > 0`。
- 成功消费时只减 1，不能降到 0 以下，并把 `standard_spent_this_turn` 增加 1。
- 普通攻击和 `action_cost: "standard"` 的技能都在同一次成功提交中令 `movement_used=true`。
- 消费后若仍有标准行动点，`TacticalManager` 返回 `ACTION_PHASE`；不得提前进入迅捷阶段或结束回合。
- 标准行动点耗尽后，才按现行逻辑进入仍有可用迅捷技能的阶段，或结束回合。

### 4.3 迅捷、移动、反应与免费动作

- 迅捷动作校验 `swift_remaining > 0`，成功时减 1，不能降到 0 以下；它不消费移动或标准行动点。
- 移动仍是一次机会，移动距离来自 `stats.mov`；本 Task 不改为逐格扣减。
- 反应动作继续使用 `reaction_available` 和现有触发校验。
- `free` 在两类行动点满额、部分消费或耗尽时都不校验、不消费这些行动点。

现有未被调用的 `restore_standard_resource()` 与 `restore_swift_resource()` 删除。任何未来恢复动作必须由已确认的效果明确给出资源类型与数量后再新增接口，不能借旧方法暗设“恢复 1 点”或“恢复至满额”。

### 4.4 技能时机

`GameAction.validate_timing_constraint()` 使用唯一判据：

- `before_attack`：`standard_spent_this_turn == 0`；
- `after_attack`：`standard_spent_this_turn > 0`。

移动前后时机、冷却、剑气、印记和反应触发条件保持现行语义。

## 5. 旧布尔状态与 `swift_limit` 退役

`standard_used`、`swift_used`、`has_moved`、`has_attacked`、`has_used_swift` 以及 `_sync_legacy_action_flags()` 从 `Unit` 删除。生产逻辑和活动测试不得再直接读写这些名称，避免“已经消费过”和“已经耗尽”继续共用一个布尔值。

`get_action_status_summary()` 保持现有 `M/A/S` 简短摘要的表现范围：移动按 `movement_used` 判断，标准和迅捷按对应 `remaining > 0` 判断。它不承担部分点数展示；精确数量只由正式行动资源条显示。因此本 Task 不需要修改 `TurnOrderBar`。

为了让尚未迁移的旧行动资源条在 1B 与 1C 之间继续工作，`TacticalManager.get_dashboard_data()` 临时输出三个兼容键：

```gdscript
"movement_used": info_unit.movement_used
"standard_used": info_unit.standard_remaining == 0
"swift_used": info_unit.swift_remaining == 0
```

这些键只是界面传输层派生值，不得回写 `Unit`。它们在 `HUD-PROD-1C` 与旧资源条一起删除。

本规格取代 `2026-08-29-action-resource-bar-design.md` 中关于三个布尔值就是行动资源权威模型的旧结论；旧文件仅作为历史记录保留，不再进入现行实现依据。

`swift_limit == -1` 的整条运行旁路退役：

- `Unit.can_use_swift_skill()` 不再接收该参数；
- `GameAction` 的校验和消费函数不再接收或透传该参数；
- `TacticalManager` 不再把它写入技能条目、执行调用或 `GameAction.data`；
- 六个本地技能 JSON 中冗余的 `swift_limit: 1` 删除。设计库活库的 23 个技能均没有该字段，因此这一步删除的是本地旧运行参数，不改写结构化设计事实。

即使外部测试字典仍夹带 `swift_limit: -1`，运行时也必须忽略它：迅捷点为 0 时仍拒绝迅捷动作。零成本只能由 `action_cost: "free"` 表示。

## 6. HUD 过渡载荷

1B 同时让正式 `action_resources` 输出 1C 所需的真实字段：

```text
movement_remaining
movement_available
standard_capacity
standard_remaining
swift_capacity
swift_remaining
```

其中 `movement_remaining` 取非负 `stats.mov`，`movement_available` 为 `not movement_used`；行动点字段直接来自 `Unit`。在 1B 内保留第 5 节的三个旧兼容键，仅供旧 `ActionResourceBar` 使用。

本 Task 不修改 `BottomDashboard`、候选 `ActionResourceStrip` 或任何 HUD 素材。

## 7. 存档、敌方 AI 与内容边界

- 当前运行存档不保存回合中的行动资源，`RunState`、`BattleAssembler` 和存档格式均不修改。
- 当前敌方没有大于 1 的容量来源，敌方 AI 每回合只规划一次攻击的限制不影响现行内容；允许敌方获得额外点之前，必须另开 Task 设计多次目标选择与行动规划。
- 不新增容量字段到职业、天赋、装备、技能或设计库实体；额外点数的开启条件保持未决。
- 不设计“再行动”的默认恢复数量。

## 8. Task Card

- **单一主交付物：** 一个本地提交中的多行动点运行时基础。
- **目标仓库：** `Ship_of_Theseus`。
- **目标分支／工作树：** `codex/issue-18-action-resource-bar`／现有独立工作树。
- **起始 HEAD：** `ffadf60a126e668b15732cf691ddf2b8a31d5439`。
- **规模／子代理预算级别：** `M`／`M`。
- **实施方式：** 先写失败测试，再做最小实现；完成后由独立 reviewer 审查精确差异，最多允许一次集中纠正。
- **治理合同：**
  - `AGENTS.md`：玩法目标事实先读取设计库；只在任务工作树修改声明范围，保护用户既有改动；Task 未经验收不得表述为 Milestone 完成。
  - `.codex/project/mercury-task-contract.md`：保持单一交付物、精确允许与禁止路径、最多三项验收条件；实现后独立审查，阻断项只允许一次集中纠正。
- **相邻问题：** HUD 正式切换、额外点获取条件、再行动效果、敌方多行动规划、战斗中途存档均不处理。
- **实施计划精确路径：** `docs/superpowers/plans/2026-09-05-multi-action-resource-runtime.md`。

允许修改：

- `scripts/units/unit.gd`
- `scripts/core/game_action.gd`
- `scripts/core/tactical_manager.gd`
- `data/skills/archer_eagle_eye.json`
- `data/skills/cleric_bless.json`
- `data/skills/knight_iron_wall.json`
- `data/skills/mage_mana_shield.json`
- `data/skills/soldier_rally.json`
- `data/skills/swordsman_zhaojia.json`
- 新增 `tests/test_multi_action_resources.gd`
- `tests/test_action_resource_runtime.gd`
- `tests/test_action_resource_dashboard.gd`
- `tests/test_action_cost_free.gd`
- `tests/capture_action_resource_bar_tactical.gd`
- `tests/test_harness_load.gd`
- `tests/test_swordsman_skillbar.gd`
- `tests/test_swordsman_runtime_path.gd`
- `tests/test_swordsman_qa_impl.gd`
- `tests/test_swordsman_p0_fixes.gd`
- `tests/test_swordsman_integration.gd`
- 本规格与对应实施计划

必须保持不变：

- `scripts/core/enemy_ai.gd`
- `scripts/core/run_state.gd`、部署组装与全部存档合同
- 除上述六个冗余键删除外的 `data/**`
- `scripts/ui/**`、`scenes/**`、Theme、PNG 与冻结候选清单
- 设计库、KB、Mercury 及本任务开始前的三个跟踪修改

## 9. 验证范围

先新增 `tests/test_multi_action_resources.gd`，让旧实现因容量、逐点消费、时机和 `swift_limit` 旁路而失败。实现后至少运行：

- `test_multi_action_resources.gd`
- `test_action_resource_runtime.gd`
- `test_action_resource_dashboard.gd`
- `test_action_cost_free.gd`
- 所有因旧布尔字段迁移而修改的剑士、剑圣、调试与捕获测试
- `test_swordsman_resources.gd` 及动作结算的现有受影响测试
- Godot 4.6.3 无头编辑器导入检查

每个脚本用以下形式独立运行并保留退出码与末尾摘要：

```powershell
& $env:GODOT_EXE --headless --path $projectRoot --script res://tests/<test-file>.gd
```

若 `Unit`、`GameAction` 或 `TacticalManager` 的公开调用面导致其他既有测试编译失败，运行全部 `tests/*.gd`，但不得把范围外失败转成未经批准的改动。

## 10. 完成条件

1. **计数模型成立：** 默认容量保持 1；容量 1、2、3 均可逐点消费且不下溢，回合开始按各自容量回满；正常内容没有大于 1 的来源。
2. **真实流程成立：** 容量为 2 时，第一次标准动作立即关闭移动但仍能执行第二次；标准点耗尽后才转入迅捷阶段或结束回合；`before_attack` 与 `after_attack` 按本回合累计消费判断。
3. **旁路与过渡合同完成：** `swift_limit` 不再绕过消费，`free` 仍为零成本；正式 HUD 载荷提供六个真实字段，并只为 1C 前的旧界面保留三个派生兼容键；受影响测试和独立审查通过。

## 11. 失败与回退

- 若需要为正式内容加入额外容量来源，停止并拆出新的设计裁决与 Task。
- 若需要定义再行动恢复量或战斗中途容量变化，停止并回到设计库与用户裁决，不在实现中猜测。
- 本 Task 只创建本地提交，不推送、不创建 PR、不合并。回退依赖单一提交边界，不保留双运行模型。
