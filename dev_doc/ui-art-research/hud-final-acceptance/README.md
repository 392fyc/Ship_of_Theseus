# 基础战斗界面整屏验收

本次从已合并的 `develop` 版本启动 Godot 4.6.3 正式 `TacticalScene`，检查行动资源栏、技能、人物、剑气和印记在同一画面的关系。现行视觉依据是用户定版的 [2026-09-24 Penpot 整体画布](../penpot/2026-09-24-hud/README.md)；其中行动栏采用足迹、圆形和三角形。对应 [行动资源栏任务](https://github.com/392fyc/Ship_of_Theseus/issues/18)。

## 实机画面

| 状态 | 1280×720 | 1920×1080 |
| --- | --- | --- |
| 行动资源可用 | [整屏](evidence/available-1280.png) | [整屏](evidence/available-1920.png) |
| 移动与标准行动已消耗，迅捷行动可用 | [整屏](evidence/mixed-1280.png) | — |
| 三种行动资源已消耗 | [整屏](evidence/spent-1280.png) | — |
| 鼠标悬停人物头像 | [整屏](evidence/hover-1280.png) | [整屏](evidence/hover-1920.png) |

截图由 [正式场景捕获脚本](../../../tests/capture_hud_final_acceptance.gd)在可见 Godot 4.6.3 窗口生成。[捕获清单](evidence/capture-manifest.json)记录同一批次的文件名、尺寸和 SHA256 摘要。消耗态通过当前单位的资源接口更新正式场景，再由场景刷新界面。脚本确认行动资源栏可见、位于技能栏正上方且按设计坐标相隔 6 像素；截图尺寸与窗口尺寸一致。头像鼠标悬停时不再叠加键盘焦点外框；1280×720 常态与悬停态的头像框区域逐像素一致，键盘聚焦仍保留焦点提示。

## 本次检查

| 检查 | 结果 |
| --- | --- |
| `test_action_resource_bar.gd` | 75 过，0 失败 |
| `test_action_resource_dashboard.gd` | 24 过，0 失败 |
| `test_action_resource_runtime.gd` | 102 过，0 失败 |
| `test_hud_freeze_resources.gd` | 33 过，0 失败 |
| `test_hud_m2_runtime_dashboard.gd` | 117 过，0 失败 |
| `test_hud_m2_dashboard_view_adapter.gd` | 41 过，0 失败 |
| `test_myrmidon_skill_icons.gd` | 0 失败 |

行动资源运行检查覆盖回合开始、移动、标准攻击和迅捷技能后的界面刷新。地图棋子脚下没有行动资源字母提示。属性卡悬停态在人物栏上方，与剑气槽分开。用户已于 2026-09-26 确认修正后的头像框，以及初始、混合消耗、全消耗和头像悬停画面的整屏位置与可读性可以验收。
