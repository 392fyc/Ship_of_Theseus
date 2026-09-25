# 人物属性卡与剑圣头像

## 本次交付范围

- 仅头像区域悬停或键盘聚焦时，显示人物属性卡；鼠标进入属性卡时保持展开，离开后收起。
- 属性卡在人物栏上方，避开剑气槽。八项属性来自现有战斗状态；括号内显示当前修正，不改变任何属性计算。
- 剑圣头像使用用户从原画裁切与重新生成版中选定的重新生成素材。Godot 的 `AtlasTexture` 选择显示区域；其他职业继续使用现有回退图形。

头像源文件、字节摘要、显示区域和审核状态见[素材清单](../../../assets/ui/portraits/source-manifest.json)。[生成提示词](generation-prompt.md)记录参考图与修改要求。用户已确认属性卡的位置、中文字与字号，以及重新生成头像的正式画面。头像使用线性过滤减轻缩小时的锯齿。

## 当前 Godot 实机画面

- [1280×720 常态](../hud-final-acceptance/evidence/available-1280.png) · [1280×720 头像悬停](../hud-final-acceptance/evidence/hover-1280.png)
- [1920×1080 常态](../hud-final-acceptance/evidence/available-1920.png) · [1920×1080 头像悬停](../hud-final-acceptance/evidence/hover-1920.png)

当前画面由 `tests/capture_hud_final_acceptance.gd` 在正式 `TacticalScene` 中生成。头像鼠标悬停时只展开属性卡，不叠加键盘焦点外框；1280×720 常态与悬停态的头像框区域逐像素一致。键盘聚焦仍显示焦点提示。像素尺寸与逐文件摘要见 [整屏捕获清单](../hud-final-acceptance/evidence/capture-manifest.json)。

## 原画对照存档

用户选择重新生成版时对照的[原画裁切细节](candidate/portrait-detail-4x.png)、[原画正式画面](candidate/hover-1280.png)及[当时生成版的四倍细节](candidate/portrait-detail-4x-generated.png)保留在[原候选截图清单](candidate/capture-manifest.json)中。用 `--original` 运行 `tests/capture_hud_character_panel.gd` 可重现原画对照画面。

## 当前检查

- `tests/test_hud_m2_runtime_dashboard.gd`：117 项通过，检查头像悬停范围、属性卡与剑气槽不重叠、鼠标垂直和斜向移入属性卡、键盘聚焦及焦点外框、真实属性数据及头像贴合画框。
- `tests/test_hud_m2_dashboard_view_adapter.gd`：41 项通过，检查剑圣头像绑定及其他职业不误用。
- `--headless --import` 完成，未见脚本错误。
