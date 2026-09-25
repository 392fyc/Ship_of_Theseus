# 基础战斗 HUD 的 Godot 接入与验收

## 当前范围

本接入基于已合入 `develop` 的 [Penpot 定版资料](../penpot/2026-09-24-hud/README.md)和远端参考分支 `origin/codex/ui-m2-reference-20260924`。底部五区与行动条复用参考实现；剑和印记按定版布局接入正式 `TacticalScene`。

| 组件 | 画板坐标 `[x,y,w,h]` | 当前实现 |
| --- | --- | --- |
| 底部五区 | 人物 `[32,596,226,108]`、装备 `[266,596,128,108]`、技能 `[402,596,476,108]`、遗物 `[886,596,278,108]`、结束行动 `[1172,596,76,108]` | 统一边框，装备与遗物只保留接口 |
| 行动条 | `[503,550,274,40]` | 与底部边框连接；已消耗字形保留轮廓 |
| 横剑 | `[32,520,366,56]` | 无框、无底板；剑柄在左，剑刃在右；剑气裁切填充，50及以下青蓝、51及以上红宝石色；剑尖右侧以 32 像素描边数字显示当前值 |
| 印记 | `[886,520,278,56]` | 无框、无底板；三个独立布尔状态驱动原创纹章，持有时为金、青、珊瑚红，未持有时为灰色空心；三枚纹章沿原中心均布，显示高度 52，底缘距下方边框 24 |

剑的透明图层与摘要在 [定版素材来源清单](../../../assets/ui/skins/hud_freeze/source-manifest.json)；原创纹章的生成来源、摘要和裁切范围在 [纹章来源清单](../../../assets/ui/skins/hud_mark_crest/source-manifest.json)；数字字体的来源在 [字体来源清单](../../../assets/fonts/source_sans_pro/source.json)。布局、皮肤、状态适配和运行行为分别位于 `assets/ui/layouts/`、`assets/ui/themes/`、`scripts/ui/hud/m2/`、`scripts/core/tactical_manager.gd`。行动资源的显示数据从现有单次行动状态映射，战斗结算规则没有改动。

基础剑士的五张技能图标已使用用户定版的正式素材并接入战斗界面；生成来源、源图与运行图摘要见 [基础剑士图标清单](../myrmidon-skill-icons/source-manifest.json)，接入记录见 [合并请求 #27](https://github.com/392fyc/Ship_of_Theseus/pull/27)。发行包中运行图与开发源图的纳入范围仍需独立检查。

## 实机图

以下是剑气与印记接入时的专项截图，由 Godot 4.6.3 的真实窗口和正式 `TacticalScene` 生成。初始状态图来自真实场景；其余条件图使用同一场景及管理器载荷的显示副本，不代表在战斗中实际取得这些资源。包含正式技能图标、人物头像和行动资源栏的现行整屏画面见 [整屏验收记录](../hud-final-acceptance/README.md)。

- [1280×720 初始状态](crest-candidate/production-000.png)及 [1920×1080 缩放](crest-candidate/production-1920-000.png)
- 剑气数字：[0](number-candidate/qi-0.png)、[65](number-candidate/qi-65.png)、[100](number-candidate/qi-100.png)
- 纹章点亮：[三枚均持有](crest-candidate/marks-111.png)；[三枚均未持有](crest-candidate/marks-000.png)；其余六态和摘要见 [窗口捕获清单](crest-candidate/capture-manifest.json)

用 `tests/capture_hud_crest_candidate.gd` 可重现当前纹章截图；用 `tests/capture_hud_number_candidate.gd` 可重现数字边界图。当前八态的逐像素差异只出现在对应纹章范围。原接入基线截图保存在 `evidence/`，用于回溯定版素材，不代表当前纹章与数字视觉。

## 接入时验证与现行验收

- `dev_doc/ui-art-research/penpot/2026-09-24-hud/verify.py`：18 项资料、11 张预览通过。
- 本机 Penpot 插件已打开目标页面。原样运行 `verify-cloud.js` 后，文件、页面、主画板、剑、印记、命名版本和修订号 215 均通过；结果保存在 [云端只读核验](evidence/cloud-check.json)。另只读确认八态画板存在。
- `tests/test_hud_freeze_resources.gd`：33 项通过，覆盖真实数据、剑气边界、印记八态、通用费用与职业回退。
- `tests/test_hud_m2_dashboard_view_adapter.gd`：39 项通过；`tests/test_hud_m2_runtime_dashboard.gd`：103 项通过；`tests/test_hud_m2_skill_action.gd`：175 项通过。
- `tests/test_action_resource_dashboard.gd`：24 项通过；`tests/test_action_resource_runtime.gd`：102 项通过；`tests/test_harness_load.gd`：42 项通过。
- 当前纹章窗口捕获 12 张、数字窗口捕获 4 张；另以 `--headless --import` 检查资源导入，均无脚本错误。
- 独立只读复核确认第一版纹章已在正式场景中默认启用，资源缺失时可回退，八态差异仅在对应纹章区域；12 张纹章和 4 张数字截图的尺寸、摘要均与清单一致。原接入基线复核记录见 [归档结果](evidence/independent-review.json)。
- 当前整屏验收的六张正式场景截图、七组检查结果及用户视觉确认见 [整屏验收记录](../hud-final-acceptance/README.md)。

## 验收与分发边界

用户已确认第一版原创纹章、其约 20% 的放大尺寸与 32 像素剑气数字可以定版，正式场景默认显示。基础剑士五张技能图标已定版并进入正式战斗界面；发行包资源纳入与排除检查另行完成。集成与合并状态以 Git 和 GitHub 的实际记录为准。

生成素材工具的本机能力与适用范围记录在 [工具流核验](toolchain-assessment.md)。
