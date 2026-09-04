# GHV-9 字体与承载区域统一放大证据

状态：15 张 Godot 截图已刷新并通过独立审查，等待用户视觉审核。

## 首要审核文件

- 角色信息五状态：`../../hud-ghv2-character-slice/evidence/hud_character_slice_1280x720.png`
- 默认五技能完整底栏：`../../hud-ghv4-bottom-composition/evidence/hud_bottom_composition_5skills_1280x720.png`
- 长名称、极大数值、冷却与次数：`../../hud-ghv5-bottom-dynamic-states/evidence/hud_bottom_dynamic_capacity_2_early_lock_1280x720.png`

## 当前截图摘要

- 角色信息 3 张：1280×720、1920×1080、2560×1440。
- 底部组合 9 张：5／6／7 技能分别覆盖上述三个分辨率。
- 动态状态 3 张：正常、移动提前失效与移动耗尽，均为 1280×720。

代表图 SHA-256：

- 角色信息：`c627f03821bb3046ebe06a2c30412440a5bb1dfe84f437dd352522e0f69b70b7`
- 默认五技能完整底栏：`fc33d4bf4c9c078a5cb8cdbe89f44691269019de444ea18af8ef0f21ad0e7971`
- 长值动态状态：`8460746fb04b4a6908bc30370e110d255e9e82ff90ccc9d85864581e4180d3bb`

截图内容只使用现有外框素材与运行时 mock；本任务没有生成或购买新图像素材。

独立审查结论：视觉评分 93／100，无当前范围阻塞项。用户审核时优先检查长职业名的省略效果，以及早锁状态中的冷却数字 `2`、次数 `3` 和移动值 `7`。
