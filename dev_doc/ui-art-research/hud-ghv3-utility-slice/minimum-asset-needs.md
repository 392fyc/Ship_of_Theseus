# GHV-3 Gate 3：最小素材需求

## 结论

结构画廊已经证明装备栏、遗物栏和通用槽可以复用现有已验收中性表面。本阶段不需要为每个区域重新生成一张整图，也不需要生成任何内容图标。下一素材批次只保留三个拥有唯一消费者的原子职责。

## 已安全复用，不生成新图

| 消费者 | 复用表面 | Godot 接线 | 结论 |
| --- | --- | --- | --- |
| `EquipmentHudPanel` 128×108 | `character_panel_surface_v1.png` | `HudEquipmentPanel/styles/panel`，6px 九宫格 | 通过；缩至 128×108 后边角未挤压槽位 |
| `RelicGrid` 278×108 | `character_panel_surface_v1.png` | `HudRelicPanel/styles/panel`，6px 九宫格 | 通过；拉宽后长边保持安静，8 格网格未被遮挡 |
| 武器／防具槽 52×52 | `skill_slot_surface_v1.png` | `HudSlotButton52/styles/*` | 通过；无技能语义或文字烘焙，可作为中性槽壳 |
| 遗物槽 40×40 | `skill_slot_surface_v1.png` | `HudSlotButton44/styles/*` | 通过；Theme 变体名保持兼容，实际显示缩至 40×40 后仍为正方形且与外围框留有净距 |

这些复用只涉及中性外壳。运行时图标、空槽覆盖层、焦点、按下和禁用状态仍由独立节点与 Theme 调制承担。

## 下一批必须专门制作的三个原子职责

1. `potion_button_shell`：32×32，透明背景，只包含全职业固定血瓶按钮的外壳；不得烘焙瓶子、次数、冷却、文字或治疗量。它替换 `HudPotionButton32/styles/*` 的结构占位。
2. `end_action_diamond_frame`：44×44，透明背景，只有菱形金属／石质边框和内部透明区；边框不得占满 52×52 点击区域。
3. `end_action_hourglass_emblem`：18×24，透明背景，只有清楚的沙漏图形；与菱形框分别生成和接线，四边至少保留 5px 视觉空隙。

三个职责均需继承当前暗黑哥特、略微精细、低亮度金属与旧羊皮金色点缀的统一质感。候选由 Codex 内置图像生成能力产生，不使用外部 API key；任何购买素材仍必须先由用户确认。

## 明确排除

- 武器、防具、血瓶内容、遗物内容图标；
- 面板整图、装备栏整图、遗物栏整图或整段底部 HUD；
- `END`、`WPN`、`ARM`、`RELIC`、次数、冷却等文字；
- 遗物玩法容量改动；8 格仍只表示视觉槽壳，生产上限保持 6；
- 职业资源 HUD、战斗动画和生产数据接线。
