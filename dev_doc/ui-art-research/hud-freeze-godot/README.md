# 基础战斗 HUD 的 Godot 接入候选

## 当前范围

本候选基于已合入 `develop` 的 [Penpot 定版资料](../penpot/2026-09-24-hud/README.md)和远端参考分支 `origin/codex/ui-m2-reference-20260924`。游戏仓任务分支为 `codex/hud-freeze-godot-integration`。底部五区与行动条复用参考实现；剑和印记按定版布局接入正式 `TacticalScene`。

| 组件 | 画板坐标 `[x,y,w,h]` | 当前实现 |
| --- | --- | --- |
| 底部五区 | 人物 `[32,596,226,108]`、装备 `[266,596,128,108]`、技能 `[402,596,476,108]`、遗物 `[886,596,278,108]`、结束行动 `[1172,596,76,108]` | 统一边框，装备与遗物只保留接口 |
| 行动条 | `[503,550,274,40]` | 与底部边框连接；已消耗字形保留轮廓 |
| 横剑 | `[32,520,366,56]` | 无框、无底板；剑柄在左，剑刃在右；剑气裁切填充，50及以下青蓝、51及以上红宝石色；只显示当前数字 |
| 印记 | `[886,520,278,56]` | 无框、无底板；三个布尔状态选择八张同源透明状态图；战场默认构图给透明字形留出深色背景 |

剑和印记的透明图层与摘要在 [素材来源清单](../../../assets/ui/skins/hud_freeze/source-manifest.json)；数字字体的来源在 [字体来源清单](../../../assets/fonts/source_sans_pro/source.json)。布局、皮肤、状态适配和运行行为分别位于 `assets/ui/layouts/`、`assets/ui/themes/`、`scripts/ui/hud/m2/`、`scripts/core/tactical_manager.gd`。行动资源的显示数据从现有单次行动状态映射，战斗结算规则没有改动。

五张技能图标来自 M2 参考提交，当前是开发预览占位，不列为可随游戏正式分发的素材。逐文件摘要和未核实的来源、权利边界见 [占位素材清单](../../../assets/prototype/hud_m2/source-manifest.json)。游戏分发前必须换成有来源、使用权与摘要记录的正式图标。

## 实机图

截图由 Godot 4.6.3 的真实窗口和正式 `TacticalScene` 生成，目标显卡为 NVIDIA GeForce RTX 3070 Ti，使用 Vulkan 渲染。`production.png` 是场景初始真实状态；其余条件图使用同一场景及管理器载荷的显示副本，不代表在战斗中实际取得这些资源。

- [1280×720 整体](evidence/production.png)及 [1920×1080 缩放](evidence/production-1920.png)
- [人物属性悬浮](evidence/hover-character.png)与 [行动灰态](evidence/action-spent.png)
- 剑气边界：[0](evidence/fixture-0-111.png)、[1](evidence/fixture-1-111.png)、[50](evidence/fixture-50-111.png)、[51](evidence/fixture-51-111.png)、[100](evidence/fixture-100-111.png)
- 印记八态：[000](evidence/marks-000.png)、[001](evidence/marks-001.png)、[010](evidence/marks-010.png)、[011](evidence/marks-011.png)、[100](evidence/marks-100.png)、[101](evidence/marks-101.png)、[110](evidence/marks-110.png)、[111](evidence/marks-111.png)

用 `tests/capture_hud_freeze.gd` 可重现截图；尺寸与 SHA256 见 [窗口捕获清单](evidence/native-capture.json)。八态图两两比较时，差异只出现在右侧对应字形范围；剑气 50 与 51 的图差异只出现在左侧剑模块。默认相机把地图单位留在两个悬浮模块上方，战场背景取定版画布的深色底，印记直接绘制定版透明图，不添加外框或底板。实机视觉确认应同时查看 `production.png` 和 `marks-111.png`。

## 当前验证

- `dev_doc/ui-art-research/penpot/2026-09-24-hud/verify.py`：18 项资料、11 张预览通过。
- 本机 Penpot 插件已打开目标页面。原样运行 `verify-cloud.js` 后，文件、页面、主画板、剑、印记、命名版本和修订号 215 均通过；结果保存在 [云端只读核验](evidence/cloud-check.json)。另只读确认八态画板存在。
- `tests/test_hud_freeze_resources.gd`：33 项通过，覆盖真实数据、剑气边界、印记八态、通用费用与职业回退。
- `tests/test_hud_m2_dashboard_view_adapter.gd`：39 项通过；`tests/test_hud_m2_runtime_dashboard.gd`：103 项通过；`tests/test_hud_m2_skill_action.gd`：175 项通过。
- `tests/test_action_resource_dashboard.gd`：24 项通过；`tests/test_action_resource_runtime.gd`：102 项通过；`tests/test_harness_load.gd`：42 项通过。
- 窗口渲染生成 17 张截图，另以 `--headless --import` 检查资源导入，均无脚本错误。
- 独立只读复审对修订后的截图、素材摘要和改动范围给出通过结论；记录见 [独立审查结果](evidence/independent-review.json)。

## 集成前剩余条件

需要用户对 Godot 实机画面的确认、按项目发布流程集成，以及合并后核验。五张技能图标的正式分发来源仍待补齐。当前文件是待验收候选；完成这些条件后才能宣布本阶段完成。

生成素材工具的本机能力与适用范围记录在 [工具流核验](toolchain-assessment.md)。
