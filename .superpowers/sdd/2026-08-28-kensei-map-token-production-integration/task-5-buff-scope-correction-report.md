# Task 5 Buff/Debuff 范围修正回执

## 变更

- `kensei_map_token` 的 `overhead_layout` 移除 `status_badge_y`；保留血条 `bottom=-58` 和伤害/弹出信息 `anchor=-82`。
- `MapTokenView` 不再要求状态图标坐标；`Unit` 移除 VA-4 配置覆盖，既有 Buff/Debuff 标签继续使用 `STATUS_BADGE_Y=-58`。
- 第三张 TacticalScene 截图不再注入 Buff 或断言专用状态锚点；只覆盖相邻单位纵向遮挡、血条与伤害弹字。
- 规格与计划将 Buff/Debuff 血条关联样式及位置列为后续专门 UI/视觉设计裁决事项。

## 验证

- 测试先行：更新后的资产、组件和 Unit 状态基线断言在实现前分别以预期失败退出。
- 聚焦 Godot 测试：`test_kensei_map_token_asset` 33/0、`test_map_token_view` 71/0、`test_unit_map_token_visual` 27/0、`test_tactical_map_token_integration` 14/0。
- 全量 Godot 回归：Godot `4.6.3.stable.official.7d41c59c4` 运行 `tests/test_*.gd`，40/40 退出码 0；完整输出见 `task-5-buff-scope-correction-full-regression.log`，SHA256 `15ccbbf0be034a2ffa6728f9b90dc8b2de61b6343b7e56d86137f08e6bb0b3c1`。
- 截图：headless 快速失败退出码 1；窗口模式退出码 0，批次 `user://visual_style_playground/kensei_map_token_tactical/batch_1787927940/`，三张 PNG 均为 `1280×720`。
- 静态检查：提交前运行 `git diff --check`。

本次修正后的规格与计划仅把血条、生命值文字与战斗文字弹出信息列为 VA-4 正向完成条件。通用 Buff/Debuff 状态系统保留，但其样式和位置不属于本阶段交付。

## 提交与剩余事项

- Commit：本报告所在的 VA-4 范围修正提交。
- 不发布、不推送。
- 仍需独立审查；截图生成不等同于用户视觉验收，后者由用户单独裁决。
