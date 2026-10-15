# 地形素材 R5 修订

## 目标与范围

阶段成果为 TERRAIN-READABILITY-01 的素材可读性与视觉一致性。定稿要求同一候选通过既定六组原图、T1–T6、独立审查和用户视觉验收。本 Task 先完成 R5 候选与 10×10/1280×720 单组原图复核，依据结果再安排定稿批次。

起点 `91457ab460565d20e61a8c609e5eb7cf46112895`。本轮依据为 Claude 的 2026-10-15 复核和人类同轮反馈：墙体材质接近地板；柱子突兀且用途不明。后者要求墙柱一并修正。

允许写入建筑与树图的呈现代码、`visual_profile.json`、新版本纹理及其导入参数、只更新来源绑定的树冠/暗侧标注与独立审查记录，以及本任务文档。地表材质、接壤、水深、网格、相机、规则、逻辑占格、旧纹理字节及冻结采集器/指标代码保持当前批准范围。

## 实施

1. 墙与柱使用专用石灰岩立面、平整压顶石。墙顶和柱顶经 `_coping` 路由，地面继续使用原 `_ground`。墙侧保留横向砌块，压顶石减少高频裂纹，冷灰色与褐色铺地分离。
2. 柱子保留所在格和原有最大显示边界，改为宽柱脚、收分柱身、残缺的外扩柱头。用于表达已经失去横梁的庭院柱廊残迹。
3. 树图按明确人类授权使用确定性 Python 调色，派生 `forest-tree-v3b.png`，RGB 独立分区处理，alpha/atlas/轮廓坐标不变。具体参数与来源见 `tree-r5-derivation.md`。旧 v3 原件保留。
4. 沿用采集器分类约定：立面文件名包含 `masonry-wall`；压顶石不包含该片段。柱脚是首个 Polygon2D，侧面居中，柱顶是最后一个。线条留在实际实例中，冻结采集器对柱线条按 unknown 保留，不伪装为顶面或侧面。

## 验收

- 树冠 L* p95≤60、最大≤72、C* p95≤52，L*>55 且 C*>50 的像素比例≤8%，中位 L*≥33；12 棵树 T3 仍全部通过。枝干/根 hue 60–85°、C*≤20、L*20–32。
- 墙柱沿用 T2：顶面至少比相邻可见地面高 10 L*，侧面至少比顶面低 8 L*。专用材质是否可辨、柱子是否读成庭院残柱，由原图视觉审查另判。
- C4/C8、尺寸与源码绑定、逐图同帧、RGBA 配准、crown-union mismatch=0，继续复用冻结采集工具和 v3 指标。
- 固定三档和两种边长的定稿批次暂缓；本轮先审单组。range_covered 把移动范围内树丛淡化到32%的 UX 问题只登记为后续项。

## 石材生成与处理

使用内置 `imagegen`；参考原件仅用于立面像素笔触语言。原生成 PNG 直接存入新文件，没有裁切、缩放、重新编码或覆盖旧纹理。两张均为1254×1254、全不透明，明确导入参数与素材一起入库，Polygon2D 使用节点自身的 Nearest 和 Repeat。原始生成值通过 profile 的 RGB 调制进入低饱和旧石范围；纹理统计只作选参，不算引擎验收。

| 文件 | SHA256 | 用途 |
| --- | --- | --- |
| masonry-wall-limestone-r5.png | cddddb6299c2f947ece89db5af4485f1414657967593389c142c3633bdcfb4cb | 墙侧、柱侧，显示大小由现有建筑几何与UV确定 |
| coping-limestone-r5.png | 3e99d2766d104e5f480f8a8f320ff8183cb6d57ded352607ee7879e0a00e6bd9 | 墙顶、柱顶、柱脚，使用独立石材及平面UV |

立面风格参考：`assets/prototype/battlefield_courtyard/masonry-wall-v2.png`。压顶石为新生成，没有输入参考图。UID文本的编码范围核对了 [Godot 4.6 ResourceUID 源码](https://github.com/godotengine/godot/blob/4.6/core/io/resource_uid.cpp)，实际重新导入是否保留绑定由云端校验。

### 立面提示词

Use case: stylized-concept. Generate a production albedo texture for weathered pale limestone masonry in a small-scale 2D isometric tactical RPG ruined courtyard. The reference is ONLY for hand painted pixel-art texture language, not its brown value or noisy pattern. Create a square, completely flat orthographic material texture filling the entire image edge to edge, opaque, seamless horizontal and vertical tiling. Broad horizontally coursed rectangular limestone blocks, 5 staggered courses, roughly 4 blocks across. Soft cool gray with subtle sage undertone, clean light-gray worn planar faces, slightly rounded chipped arrises, restrained short cracks and shallow dark gray mortar seams. Stones must clearly read as architectural blocks, distinct from dark brown ground paving. Very low surface noise, no large diagonal scratches, no strong black grout, no moss except tiny sparse dark moss in a few joints. Consistent broad neutral illumination with very subtle upper-left face bevel shading; no cast shadows, perspective, object silhouette, background, grid, borders, decorative symbols, text, labels or typography. Keep medium lightness around Lab L*=43 and upper faces below 62, variation in planar face lightness at most about 12. Subtle pixel clustering consistent with the reference at small display scale. This image is a reusable stone wall and column material, not a finished wall or ground tile.

### 压顶石提示词

Use case: stylized-concept. Asset: seamless opaque square albedo material for the coping stones on top of a low ruined courtyard wall, for a hand-painted pixel-cluster 2D isometric tactics game. A FLAT orthographic view of the material only. Fill the entire canvas to every edge with pale cool-gray limestone, no background and no perspective. Three broad horizontal courses of large long rectangular dressed coping stones. The blocks have smooth worn flat faces, very low contrast fine limestone pores, a few tiny corner chips, narrow shallow mortar joints; no diagonal scraping pattern, no large repeated dark cracks, no grass, no stains across the faces. Original restrained painted texture, clean silhouettes at a display size of 20 pixels. Gray sage stone with warm off-white edge wear; face lightness about Lab L*=48, no brilliant white or black seams, no metallic shine. Very soft ambient illumination, minimal baked shading. Seamless repeat horizontally and vertically. No finished wall, props, labels, text, frame, symbols, grid, image borders or decorative motif.
