# GHA-5 开发 HUD 数值字体主题接入计划

## Milestone

`GHA-5-HUD-NUMERIC-FONT-THEME-INTEGRATION`

阶段成果：将已完成候选评估的 IBM Plex Mono SemiBold 仅接入开发 HUD 主题中的 `HudMeterValueLabel`，并以刷新后的角色区、完整底栏和动态状态证据证明字体变化没有破坏现有布局。

完成条件：

- `HudMeterValueLabel` 从共享开发主题继承 IBM Plex Mono SemiBold，身份、等级、快捷键等其他文字不被替换。
- `ValueMeter` 不持有局部字体覆盖；短值保持 8px，十三字符长值使用可逆的 7px 覆盖。
- GHV-2、GHV-4、GHV-5 的受影响截图全部重新生成，证据哈希同步更新。
- 相关自动测试全部通过，正式 `BottomDashboard`、玩法状态与遗物容量保持不变。
- 独立审查通过；用户视觉确认仍作为进入正式 HUD 接线前的门槛。

## Tasks

- [x] Task 1：先写主题接入测试并确认未接入时失败。
- [x] Task 2：仅在 `HudMeterValueLabel` 主题变体中声明字体资源。
- [x] Task 3：运行聚焦测试，确认字体继承、字号回退和隔离范围。
- [x] Task 4：刷新 GHV-2、GHV-4、GHV-5 截图与哈希证据。
- [x] Task 5：运行完整 HUD 测试与保护范围检查。
- [x] Task 6：由独立审查者核对规格、视觉证据和变更边界。

## 范围边界

- 本阶段只修改开发原型 Theme、测试和证据文件。
- 不修改正式 `scripts/ui/bottom_dashboard.gd`、`scripts/ui/skill_bar.gd`、`scripts/ui/action_resource_bar.gd`。
- 不接入真实战术状态，不生成技能、武器或其他内容图标。
- 不将开发原型接入正式场景；在用户视觉确认前保持可逆。
