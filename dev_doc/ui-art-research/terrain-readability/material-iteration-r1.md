# 地形道具可读性：第一轮候选

## 阶段成果与完成条件

TERRAIN-READABILITY-01 的目标是让树木、墙体、石柱和碎石在棋盘上容易辨认。定稿须同一素材候选完成 10×10、25×25 与三档分辨率的六组前置检查、适用的 T1–T6、独立审查和用户整体视觉验收。第一轮候选只解决道具与地面的明度层次；本文件不代表最终验收。

## 当前任务

基线为 `ecf0521f438b2999854c7de61a13a8935b1715ea`。TASK92 的 10×10/720p 原件用于校准：旧墙有 4 个完整数值 FAIL，完整旧树有 5 个；未测实例继续保留。Main 原件消费及独立审查通过后，进入本轮素材迭代。

1. 将现有道具着色移入 `visual_profile.json`，为墙柱的顶面、受光侧和背光侧分别设值，调整树木、灌木与碎石的颜色。
2. 独立审查呈现改动与冻结项，固定完整候选后，通过既有 dot-link 流程交给 Dot 云端采集首组。复用现有正式场景、采集器和校验器。
3. 取回原 PNG 和逐实例测量，确认改善方向并记录未达标项，再决定下一轮或六组验收。新素材预计转为 PASS 时，仍以 TASK92 的旧素材负例作为校准依据，不要求新素材再次失败。

## 允许修改与冻结项

本轮生产修改仅限 `scripts/ui/playground/courtyard_board_view.gd` 和 `assets/prototype/battlefield_courtyard/visual_profile.json` 中的道具呈现参数。记录位于本目录。保持原贴图、alpha、裁切、几何、位置、尺寸、接地关系和采样设置；地表纹理、接壤渐变、水深、网格、玩法与测试阈值均冻结。Godot 执行只在 Dot 云端。本任务不推送、不建 PR。

## 依据与实施方向

- 实际源码的墙顶使用 `_ground`，侧面使用 `_masonry`。两者已有独立 Polygon2D，可以分别提亮；记录此事实供 Claude 后续审查使用。
- 墙柱形成顶亮、受光侧中、背光侧暗的层次。顶部左上受光边使用细浅线，保持原描边宽度。树冠偏暖黄绿，碎石提高剪影对比，保持尺寸。
- 道具着色采用 RGBA 数组，RGB 允许大于 1，alpha 保持原值。Godot 4.6 的 [Color 文档](https://docs.godotengine.org/en/4.6/classes/class_color.html)说明部分属性（例如 CanvasItem.modulate）支持超过 1 的值；[CanvasItem 着色说明](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/canvas_item_shader.html)说明颜色与纹理相乘。Compatibility 下最终画面的亮部截平、颜色层次和可读性均须在本轮云端原图中检查。
- 第一轮保留完整原始轮廓和树冠语义标注，不引入自定义材质，继续使用冻结采集器支持的 CanvasItem 颜色路径。

## 验收边界

首组逐项检查墙柱 T2、完整树冠 T3、原图整体观感与高光截平；C4、C8 及同帧前置照常执行。T1、T4、T5、T6 和六组覆盖仍是定稿所需工作；首组不得替代它们。测不到的实例保持 NOT_TESTED。完整基础战斗 UI 和原 P0/CR-01 Milestone 继续保持未完成。
