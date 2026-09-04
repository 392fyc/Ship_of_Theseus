# GHV-4 底部 HUD 整体组合证据

状态：9 张 Godot 截图已刷新；GHV-10 将五技能设为默认审核入口并通过独立审查，等待用户视觉审核。

## 首要审核文件

- 默认五技能 1 倍图：`hud_bottom_composition_5skills_1280x720.png`
- 六技能兼容图：`hud_bottom_composition_6skills_1280x720.png`
- 七技能 1 倍图：`hud_bottom_composition_7skills_1280x720.png`

## 截图矩阵

| 技能数 | 1280×720 | 1920×1080 | 2560×1440 |
|---|---|---|---|
| 5 | `hud_bottom_composition_5skills_1280x720.png` | `hud_bottom_composition_5skills_1920x1080.png` | `hud_bottom_composition_5skills_2560x1440.png` |
| 6 | `hud_bottom_composition_6skills_1280x720.png` | `hud_bottom_composition_6skills_1920x1080.png` | `hud_bottom_composition_6skills_2560x1440.png` |
| 7 | `hud_bottom_composition_7skills_1280x720.png` | `hud_bottom_composition_7skills_1920x1080.png` | `hud_bottom_composition_7skills_2560x1440.png` |

三档分别以 1×、1.5×、2×缩放同一 1280×720 逻辑画布。截图捕获器只有在五区、行动条、棋子和技能数量的场景结构就绪，并且这些关键区域连续两帧存在足够可见像素后才保存，防止首次纹理提交不完整。

## 主任务人工检查

- 5、6、7 技能 1 倍图均包含完整五区、行动条、400 格棋盘和剑圣比例锚点。
- 技能栏外框宽度不变，只调整内部槽位数量与尺寸；不存在的技能没有显示为空槽。
- 行动资源条与技能栏居中，条底与底栏顶部存在 6 像素空隙。
- 底栏左右各 32 像素、底部 16 像素安全边距清晰可见。
- 棋盘延伸到 HUD 后方；当前不依赖棋盘旋转或缩放来回避遮挡。
- 技能、装备、血瓶和遗物内容图标均未生成；截图中的文字和数值全部为运行时节点。
