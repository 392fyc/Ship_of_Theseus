# UIUX-R6-STONE-20261015

## 阶段成果与完成条件

在已批准 U1、树方案 A 与新的墙柱明度目标下，形成旧墙、鼓石断柱和地面接触阴影的 R6 候选。完成当前 Task 需要明确候选源码及素材、独立实现审查、Dot 单组原生采集与原件核验，并按正式 T1/T2/T6/C9 与视觉/接地要求给出结果。只有单组门槛满足后才进入六组定稿；实际 FAIL 和 NOT_TESTED 保留。

## 写入范围

- scripts/ui/playground/courtyard_board_view.gd：只改墙材质取样、墙脚绘制与柱体造型。
- assets/prototype/battlefield_courtyard/visual_profile.json：只改墙柱材质路径与着色/接地参数。
- assets/prototype/battlefield_courtyard/masonry-wall-limestone-r6.png 及其 .import。
- assets/prototype/battlefield_courtyard/coping-limestone-r6.png 及其 .import。
- tests/claude_review/capture_terrain_readability_r6.gd 与 terrain_mask_draw_layer_r6.gd：新版本只复用生产墙脚几何，保留原采集入口。
- dev_doc/ui-art-research/terrain-readability/runs/2026-10-15-r6-stone/：当前候选、生成、审查与证据记录。

## 视觉与数值要求

墙柱侧面 L* 34–38、hue 70–85°、C* 5–9；顶面与断口 L* 44–50，同时比侧面亮至少 8、比地面亮至少 10。泥污带为下部 15–20%，比侧面暗 4–6，仍比地面亮至少 10。墙顶风化 IQR 至少 5，每段至少一处缺角。柱体至少 8 边，左上受光，2–3 道鼓石接缝，不规则断顶含两级以上高差，确定性最高与最矮高度差至少 20%，宽底座半埋，接触阴影比地面暗 8–12，宽度不超过半格。两名独立盲测者须从 720p 局部图识别为残柱/柱廊遗迹。

## 冻结项

树图及树着色、地表材质与接壤、水深、网格、相机、占格、玩法、原采集链及原阈值不变。使用 Compatibility。生产改动不涉及基础剑士资源或剑圣技能。不发布、不创建 PR。

## 生成与采样说明

两张新纹理由 image_gen 生成，保存原始 PNG 字节；对边不是像素级周期纹理。引擎使用单面内部取样，避免把不连续边界循环到面内。只读颜色估算用于设置初始参数，最终颜色以 Dot 原生 PNG 为准。
