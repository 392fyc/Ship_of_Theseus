# 正式行动资源条切换设计

**状态：** 已批准；1B 完成并通过审查后自动实施。

**Task ID：** `HUD-PROD-1C-ACTION-RESOURCE-STRIP-CUTOVER`

**前置条件：**

- `HUD-PROD-1A-CANDIDATE-BASELINE-FREEZE` 已完成，候选提交为 `ffadf60a126e668b15732cf691ddf2b8a31d5439`。
- `HUD-PROD-1B-MULTI-ACTION-RUNTIME` 已实现并通过审查，正式载荷能提供实际容量与剩余量。

## 1. Milestone 与本 Task 的阶段成果

`HUD-PROD-1` 的阶段目标是把通过候选验证的底部 HUD 组件逐项接入正式战斗界面，同时维持明确的数据、布局和输入合同。

本 Task 只有一个主交付物：正式 `BottomDashboard` 使用冻结候选 `ActionResourceStrip` 显示真实行动资源，旧 `ActionResourceBar` 完全退出生产路径。

人物栏、装备栏、技能栏、遗物栏、结束回合区和整套候选组合仍不在本 Task 迁移。本 Task 完成不等于 `HUD-PROD-1` Milestone 完成。

## 2. 当前事实与约束

- 正式调用链保持为 `TacticalManager.get_dashboard_data()` → `dashboard_state_changed` → `TacticalScene._refresh_dashboard()` → `BottomDashboard.update_state(Dictionary)`。
- `BottomDashboard` 继续是正式底栏的唯一门面，其六个既有信号、`update_state(Dictionary)` 和 `get_content_top_y()` 对外合同保持不变。
- 1B 后的 `action_resources` 已能表达容量 1 至 3 和实际剩余量；1C 不再从“已用”布尔值反推行动点。
- 移动仍是一次机会，`movement_remaining` 表示当前单位的非负移动力数值；移动机会失效后数值保留，只把足迹和数值灰化。
- 候选必须从 `scenes/tactical/hud/action_resource_strip.tscn` 实例化，不能复制节点树，也不能只对脚本调用 `.new()`。
- 冻结候选的场景、脚本、Theme、PNG 与 `test_hud_*` 合同不得由生产接入反向改写。
- 本 Task 不购买或生成素材，不设计职业资源 HUD，也不新增额外行动点来源。

## 3. 生产结构

正式节点关系为：

```text
TacticalScene
└─ UILayer
   └─ BottomDashboard
      ├─ 既有人物、装备、技能、遗物和结束回合区域
      └─ ActionResourceStrip（冻结候选场景的唯一实例）
```

`BottomDashboard` 以私有 `_action_resource_strip` 保存实例。正式节点树中不得同时存在旧、新两条行动资源栏。

候选是纯显示组件，只接收新的 `HudActionResourceViewData`。门面不得把 `Unit`、`TacticalManager` 或完整状态字典传给候选组件。

## 4. 正式状态合同

`action_resources` 必须包含以下六个字段：

| 字段 | 类型与合法范围 | 显示用途 |
| --- | --- | --- |
| `movement_remaining` | 整数，至少为 0 | 足迹旁的移动力数值 |
| `movement_available` | 布尔值 | 足迹与移动力是否使用正常色 |
| `standard_capacity` | 整数，1 至 3 | 绿色圆点总数 |
| `standard_remaining` | 整数，0 至标准容量 | 仍可用的绿色圆点数 |
| `swift_capacity` | 整数，1 至 3 | 橘黄色三角总数 |
| `swift_remaining` | 整数，0 至迅捷容量 | 仍可用的橘黄色三角数 |

门面逐字段建立一个新的 `HudActionResourceViewData`，再调用候选的 `apply_view()`。可用点保持正常色，已经消费的点使用冻结候选的灰化样式；不显示“可用／已用”文字，不使用斜杠。

1B 为旧界面临时保留的 `movement_used`、`standard_used`、`swift_used` 在本 Task 从正式载荷中删除。`BottomDashboard` 不读取这些旧键，活动代码和测试也不得继续建立该合同。

## 5. 显示门控与异常输入

只有以下条件同时成立时显示资源条：

1. 整体 HUD 可见；
2. 当前是玩家信息态；
3. `show_actions=true`；
4. `action_resources` 是字典；
5. 六个字段全部存在、类型正确且处于第 4 节的合法范围。

任何条件不满足时立即隐藏资源条，不保留上一次的可见内容。生产门面先验证再构建 ViewData，不能依赖候选的 `normalize()` 静默修正错误的玩法载荷；候选的限制函数只作为显示层最后防线。

状态适配只读取传入字典，不修改输入、玩法对象或候选共享资源。

## 6. 布局、鼠标与焦点

- 候选尺寸保持 `274×40`。
- 继续位于技能栏上方，与技能栏水平中心一致，垂直净距精确为 6 像素。
- `get_content_top_y()` 在资源条可见时包含其顶边，隐藏时不包含。
- 正式资源条所在矩形需要阻止点击穿透到棋盘；根节点使用 `MOUSE_FILTER_STOP`，不修改候选场景源文件。
- 资源条不取得键盘焦点，不新增按钮、鼠标提示或点击行为。
- 真实命中测试覆盖矩形中心和四边附近，确保候选内部容器不会产生局部穿透。

## 7. 五种必要自动测试状态

正式门面自动测试至少覆盖：

1. 默认容量 1，移动、标准、迅捷全部可用；
2. 移动失效、标准为 0、迅捷仍可用；
3. 标准容量 2，剩余 1；
4. 标准容量 3，剩余 1；
5. 迅捷容量 3，剩余 2 和剩余 0。

第 3 至第 5 项使用测试夹具调用 1B 的初始化入口，不修改职业、天赋、装备或技能数据。资源条总尺寸不得因为容量或剩余量变化而变化，各分区的完整类边框和整体边框保持冻结候选样式。

第 10.3 节的两张截图是对默认态和复杂部分消费态的代表性视觉证据，不承担逐一证明上述五种数据状态的职责；五态的精确字段、点数和尺寸由自动测试断言。

## 8. 旧实现退役

正式切换后删除 `scripts/ui/action_resource_bar.gd`，并删除或取代只验证旧文字、斜杠和 `_segments` 私有结构的 `tests/test_action_resource_bar.gd`。

删除前用 `rg` 确认旧脚本的所有活动引用。更新后正式代码和活动测试不得再引用：

```text
ActionResourceBarScript
ActionResourceBar
_segments
movement_used（作为 HUD 字段）
standard_used
swift_used
```

这里的“引用”指读取、写入或构造旧 HUD 合同。1B 的
`tests/test_multi_action_resources.gd` 继续保留这些名称作为
`get_property_list()`／`has_method()` 的负向接口探针；该测试不读取旧字段，
不建立旧 HUD 合同，也不属于本 Task 的修改范围。静态检查必须把这种负向
字面量与真实运行消费者分开判断。

历史规格和 Git 历史不回写；现行合同以本规格、1B 规格和冻结候选清单为准。

## 9. Task Card

- **单一主交付物：** 一个本地提交中的正式 `ActionResourceStrip` 叶子切换。
- **目标仓库：** `Ship_of_Theseus`。
- **目标分支／工作树：** `codex/issue-18-action-resource-bar`／现有独立工作树。
- **起始 HEAD：** 1B 经审查后的提交，实施计划编写时记录完整值。
- **规模／子代理预算级别：** `M`／`M`。
- **实施方式：** 先写失败测试，再完成门面适配与旧实现删除；完成后由独立 reviewer 和独立视觉 reviewer 审查，最多允许一次集中纠正。
- **治理合同：**
  - `AGENTS.md`：只迁移已确定的 HUD 叶子，保护设计库、KB、冻结候选和用户既有改动；Task 未经验收不得表述为 Milestone 完成。
  - `.codex/project/mercury-task-contract.md`：保持单一交付物、精确允许与禁止路径、最多三项验收条件；实现和视觉证据完成后独立审查，阻断项只允许一次集中纠正。
- **相邻问题：** 其他底栏组件迁移、职业资源 HUD、素材生成、素材购买、额外行动点获取条件均不处理。
- **实施计划精确路径：** `docs/superpowers/plans/2026-09-05-hud-action-resource-strip-production-cutover.md`。

允许修改：

- `scripts/core/tactical_manager.gd`，只删除三个过渡 HUD 键
- `scripts/ui/bottom_dashboard.gd`
- 删除 `scripts/ui/action_resource_bar.gd`
- 删除或取代 `tests/test_action_resource_bar.gd`
- `tests/test_action_resource_dashboard.gd`
- `tests/test_action_resource_runtime.gd`
- `tests/test_tactical_inject_smoke.gd`
- `tests/capture_action_resource_bar_tactical.gd`
- 新增 `tests/test_action_resource_strip_production_cutover.gd`
- 新增 `dev_doc/ui-art-research/hud-prod-1c-action-resource-cutover/evidence/action_resources_default_1280x720.png`
- 新增 `dev_doc/ui-art-research/hud-prod-1c-action-resource-cutover/evidence/action_resources_multi_point_1280x720.png`
- 新增 `dev_doc/ui-art-research/hud-prod-1c-action-resource-cutover/evidence/visual-verdict.json`
- 本规格与对应实施计划

上述新测试不匹配候选 manifest 的 `tests/test_hud_*.gd` 规则，新证据目录也不属于冻结清单的递归目录或精确文件。

必须保持不变：

- `scripts/core/game_action.gd`
- `scripts/units/**`
- `data/**`
- `scripts/core/enemy_ai.gd` 与存档系统
- `scripts/tactical/tactical_scene.gd`
- `scenes/tactical/TacticalScene.tscn`
- `scenes/tactical/bottom_dashboard.tscn`
- `scripts/ui/skill_bar.gd`
- 冻结候选 `scripts/ui/hud/**`、`scenes/tactical/hud/**`、Theme、PNG、候选证据与 `test_hud_*`
- 设计库、KB、Mercury 及任务前已有的三个跟踪修改

## 10. TDD 与验证证据

### 10.1 先失败的切换测试

新增 `test_action_resource_strip_production_cutover.gd`。旧实现下必须因以下事实失败：正式叶子不是候选 `.tscn`、不能直接显示容量 2 至 3、仍依赖旧三布尔字段。

实现后该测试固定：候选场景身份、唯一实例、初始隐藏、六个正式字段的直接映射、输入不变、缺失与畸形字段隐藏、布局、鼠标遮挡和无键盘焦点。

### 10.2 正式链与候选回归

至少运行：

- `test_action_resource_strip_production_cutover.gd`
- `test_action_resource_dashboard.gd`
- `test_action_resource_runtime.gd`
- `test_tactical_inject_smoke.gd`
- `test_skillbar_v3_ui.gd`
- `test_hud_action_resource_strip.gd`
- `test_hud_bottom_composition.gd`
- `test_hud_bottom_composition_gallery.gd`
- `test_hud_bottom_dynamic_states_gallery.gd`
- `test_hud_production_baseline_manifest.gd`

manifest 验证必须保持 218 项、2687/0，候选清单 SHA-256 必须保持 `584B1C9648BDF68396F37623DBD9BFDF268CB0F32574FC34F35FEE011D2E0956`，证明生产接入没有反向改写冻结候选。

### 10.3 真实视觉证据

在 Godot 4.6.3 的真实 `TacticalScene` 中生成两张 1280×720 原始截图：

1. 默认容量 1，三类资源均可用；
2. 测试注入标准容量 3、剩余 1，迅捷容量 3、剩余 2，移动已失效。

截图必须显示足迹与移动力、绿色圆点、橘黄色三角、已消费点的灰化、三个相同的分区类边框、整体边框，以及与技能栏 6 像素的净距。不得出现“可用／已用”文字、斜杠或 M/A/S 状态字样。

先由独立视觉 reviewer 检查原始截图和运行时节点尺寸，再交用户确认。

## 11. 完成条件

1. **正式切换成立：** `BottomDashboard` 只实例化一个冻结候选 `ActionResourceStrip`，直接消费六个真实字段；旧实现、旧三布尔 HUD 合同和活动引用全部删除，对外门面合同保持。
2. **状态、布局与回归成立：** 容量 1、2、3 及部分消费状态准确显示；异常载荷隐藏；274×40、6 像素净距、浮窗避让、鼠标遮挡和无焦点通过测试；冻结 manifest 仍为 218 项、2687/0、SHA-256 不变。
3. **视觉与独立审查成立：** 两张精确路径的真实 TacticalScene 截图通过独立视觉审查并由用户确认；独立代码 reviewer 批准精确差异；本 Task 只形成本地提交。

## 12. 失败与回退

- 若候选场景不能在正式根下实例化，修正门面适配或测试，不复制候选节点树。
- 若布局或输入边界不通过，只修正本 Task 的正式实例属性与门面布局；不得改写冻结候选来掩盖接入问题。
- 若六字段缺少真实运行来源，停止并返回 1B，不得在界面中伪造固定容量。
- 本 Task 不保留新旧双实现开关；回退依赖单一 Git 提交边界。
