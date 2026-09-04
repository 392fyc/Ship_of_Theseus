# GHA-4 HUD 数值字体候选显示合同

状态：官方字体素材、独立对照画廊和 GHV-5 实景预览已通过主任务技术检查、人工检查与独立审查；等待用户视觉审核。

## 候选素材

- 字体：IBM Plex Mono SemiBold，静态 TTF，字重 600。
- 版本：`@ibm/plex-mono@2.5.0`，字体版本 `IBM PLEX MONO V2.5`。
- 许可：SIL Open Font License 1.1；原样许可文本与字体同目录保存。
- 官方 ZIP SHA-256 已核对为 `6d23f01257663d8cc49a0d64c22ced630b79e0e2a0ac08a0da86e9a38bbc481c`。
- 项目内 TTF SHA-256：`f04d7c488ddf7d1fa99f2574efc3406ea4cbe17bb1af3a1ab960f84d0c96a172`。
- 项目内许可文本 SHA-256：`91c25c350d3cac39da2736d74f7ba37ef648f5237a4e330a240615bc8d8c4360`。

## 渲染边界

- Godot 4.6.3 将字体加载为 `FontFile`；内部家族名为 `IBM Plex Mono SmBld`，样式 `SemiBold`，字重 600。
- MSDF 与 mipmap 关闭，使用灰度抗锯齿、Light hinting、Auto 子像素定位和 Godot 的传统动态字体栅格化；本候选不烘焙数值，不把文字转成图片。
- 普通短值 `34/100` 使用 8px。
- 五个 13 字符压力样本统一使用 7px：`000000/000000`、`666666/666666`、`888888/888888`、`999999/999999`、`123456/654321`。
- 数字辨识样本 `0 1 6 7 8 9 /` 使用 8px 和独立 100px 检查框，不伪装成 58px 实际值框。
- 实际值框宽度保持 58px、右对齐、1px 深色描边。测试确认候选文本实际宽度没有依赖 `clip_text` 隐藏字符。
- 实测 13 字符数值在 8px 下宽 63px，会超过 58px 值框，因此必须沿用 GHV-5 的 7px 长值回退。

## 两种预览

1. 字体对照画廊：左右两列使用相同文字、几何、字号、颜色、描边和右边界；左列不覆盖字体，右列只覆盖 IBM Plex Mono。
2. GHV-5 实景预览：只复用一个既有 GHV-5 长值状态画廊，只给 XP、HP、SH 三个运行时 Label 添加候选字体局部覆盖。

## 受保护边界

- 不修改共享 `hud_structure_prototype.tres` 的字体配置。
- 不修改 `HudValueMeter` 的 8px／7px逻辑、GHV-5 场景、脚本或三张既有截图。
- 不替换身份栏中文字体、技能冷却数字、快捷键、移动值或其他 HUD 字体。
- 不修改正式 `BottomDashboard`、`SkillBar`、`ActionResourceBar`、行动规则或遗物容量。
- 用户确认前，本字体仍是开发候选；正式 Theme 接入与导出包许可可见性属于后续任务。
