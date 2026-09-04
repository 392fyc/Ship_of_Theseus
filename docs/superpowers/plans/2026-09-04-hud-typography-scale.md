# GHV-9 底部 HUD 字体与承载区域统一放大任务卡

## Milestone

在不改变 1280×720 底部 HUD 外框、五区宽度和棋盘安全区的前提下，提高全部现有动态文字的实机辨识度，并同步重分配文字承载区域。

## 当前 Task

- `task_id`: `GHV-9-HUD-TYPOGRAPHY-SCALE`
- 主要交付：角色信息、技能状态和行动资源的统一字号层级及对应容器几何。
- 目标仓库：`Ship_of_Theseus`
- 目标分支：`codex/issue-18-action-resource-bar`
- 起始提交：`94e10f36757ad247dec0b779cd8859c5c02e61ea`
- 规模：`M`；允许一次基于独立审查结果的集中修正。

## 写入边界

允许修改：

- `assets/ui/themes/hud_structure_prototype.tres`
- `scenes/tactical/hud/character_hud_panel.tscn`
- `scenes/tactical/hud/value_meter.tscn`
- `scenes/tactical/hud/skill_slot_button.tscn`
- `scenes/tactical/hud/action_resource_strip.tscn`
- `scripts/ui/hud/value_meter.gd`
- 对应 HUD 测试、开发画廊、截图证据与本任务记录

禁止修改：

- 生产战斗场景、玩法规则、角色数据、技能数据、存档结构
- 既有 HUD 外框总尺寸、五区宽度、棋盘安全边距
- 设计库、KB 与 Mercury 仓

## 不在本 Task 处理

- 新技能、武器、遗物或状态图标素材
- 职业专属资源 HUD
- 字体家族替换及玩法接线

## 验收条件

1. 职业名、等级、经验、HP、护盾、快捷键、次数、冷却与移动力按批准层级统一放大；长数值可逆回退且完整显示。
2. 角色信息行、数值条、快捷键角标、次数区与移动力数值区同步放大或重排，没有挤压、越界或改变底部 HUD 总尺寸。
3. 聚焦测试、受影响 HUD 测试、Godot 截图和独立只读审查均通过；受保护玩法路径保持不变。

## 验证

- 聚焦：角色信息、数值条、字体接入、技能槽、行动资源条、动态状态画廊。
- 受影响：底部组合及其三组截图画廊。
- 若共享 Theme 变更造成其他 HUD 测试失败，运行现有 HUD 全套测试；不扩展到无关玩法测试。
