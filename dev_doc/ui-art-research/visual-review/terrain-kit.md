# 可复用地形拼接库

## 阶段目标与完成条件

让地图作者只选择地形及外观，直接拼出能复用的战场。生成的地图 JSON 与手工摆放使用同一份数据格式、合法性检查和 Godot 绘制规则。地形交界由邻居决定，修改地图后自动更新，不要求作者逐条补边。

本阶段的必要作业：固定已批准水深；登记九类地形的组合及排除理由；实现地表边角与障碍变体；提供可操作的地图工作台；完成实际图形、编辑交互及独立审查。当前地形库外观已获用户批准。工作台进入正式战斗的功能说明和完成条件见 `terrain-runtime-integration.md`。正式关卡发布、战斗数值、完整地图产品及新玩法不在本次交付范围。

## 已固定的水深

用户已批准 `water-depth-v6` 的深浅水连续过渡。`water-depth-approved.json` 保存裁决、两张原生参考图摘要、四个绘制函数摘要、纹理摘要和参数。接壤系统沿用它；水深函数、纹理和参数保持相同。当前岸线及其他地形外观的批准记录见 `terrain-kit-approved.json`。

## 使用方式

在 Godot 打开 `scenes/playground/terrain_painter.tscn`，运行当前场景。

1. 左侧选择地形；平原、墙、山峰可以选择外观。
2. 在地图上用左键绘制或拖拽连续绘制，右键取样。邻边、角点、墙端和山体会自动重建。
3. 用“撤销”恢复上一步，用格线开关检查占格与无格线外观。
4. 选择残垣庭院、湿地山麓或火山隘口作为起点。
5. 保存为 JSON；以后可加载继续编辑。保存内容是地形和外观，素材与边角无需重复导出。
6. 点击“开始试战”，使用正式战斗中的基础剑士与枪兵检验地图。随时“返回编辑”继续修改；“重新试战”恢复当前地图的初始站位和状态。

地图只支持正方形，默认 10×10。右上设置边长（10 至 25 的整数）并点击“调整大小”。扩大保留原坐标的内容，新格补平原；缩小裁去超出新边界的格子、铺石和外观；两种调整均可撤销。保存、加载与试战使用同一尺寸限制。工作台只编辑基础地形外观，不编辑单位、剧情或战斗规则。

## 已批准外观预览

以下均为同一验证批次的 Godot 原始截图：

- [工作台](reviews/2026-09-27/terrain-kit-v1/painter/terrain-painter-workbench-1280x720.png)
- 接壤组合：[第 1 组](reviews/2026-09-27/terrain-kit-v1/kit/terrain-pairs-01.png)、[第 2 组](reviews/2026-09-27/terrain-kit-v1/kit/terrain-pairs-02.png)、[第 3 组](reviews/2026-09-27/terrain-kit-v1/kit/terrain-pairs-03.png)、[第 4 组](reviews/2026-09-27/terrain-kit-v1/kit/terrain-pairs-04.png)
- [转角与多种地形交会](reviews/2026-09-27/terrain-kit-v1/kit/terrain-corners.png)
- [五种障碍外观](reviews/2026-09-27/terrain-kit-v1/kit/terrain-obstacles.png)
- 三张可编辑示例：[残垣庭院](reviews/2026-09-27/terrain-kit-v1/kit/terrain-example-courtyard.png)、[湿地山麓](reviews/2026-09-27/terrain-kit-v1/kit/terrain-example-wetland.png)、[火山隘口](reviews/2026-09-27/terrain-kit-v1/kit/terrain-example-highland.png)

拼接与编辑功能已通过运行检查和独立审查。用户已批准当前地形、墙柱与山峰外观，允许继续功能实装；本轮功能接入保持这些绘制来源不变。

## 地形与外观

| 正式类型 | 外观与接壤 |
| --- | --- |
| 平原 | 草土或石板路；石板路仍是平原 |
| 森林 | 树木、林下苔土及根部过渡 |
| 山地 | 低矮岩地与碎石坡；仍沿用可通行的 MOUNTAIN |
| 山峰 | 裸岩或覆苔山体；相邻时接成山脊，沿用 PEAK |
| 墙 | 砌石连墙、风化残墙、石柱；石柱独立，墙段自动连接 |
| 浅水、深水 | 共用已批准连续水深，陆侧按湿土或石岸收口 |
| 熔岩 | 冷却岩壳与裂隙，周围先形成焦黑边缘 |
| 沼泽 | 湿土、低植被与不规则浅洼 |

山体立面是外观，不引入海拔、攻击线遮挡或新的移动规则。残墙和石柱沿用 WALL，不表示可摧毁建筑或 Ruins 状态。

## 组合覆盖

九类共有 45 种无方向组合，包含 9 种同类相连；当前 41 种有效，包括 32 种异类接壤。两侧交换类型不会改变合法性。转角、三种和四种地形交会由共享世界坐标混合，避免在角点叠出多层色带。

当前库排除熔岩直接接森林、浅水、深水和沼泽，包含对角接触。创作工具会指出冲突坐标与原因；可用至少一格裸地或岩地隔开。该限制服务于当前场景库，不宣称自然界不存在相关现象。熔岩遇水的冷却、蒸汽或森林燃烧需要另一套明确的场景表达。

数据合同是 `assets/prototype/battlefield_courtyard/terrain_catalog.json`。`terrain_examples.json` 提供三张可继续编辑的地图。

组合记录可以共用一种表现方式，例如湿土岸或碎石坡，不要求每对地形独立生成图片。合同中的 `transition_defaults`、`transition_styles` 及单组合 `style` 依次决定岸线宽度、临水湿暗、熔岩冷却边等实际材质参数；石板路的窄岸由 `variant_styles` 提供。墙脚、坡面和林下覆盖随相应地形生成。已批准的浅水到深水仍使用冻结的水深函数。

## 技术消费约定

地图保存 `width`、`height`、`terrain`、`paving`、`terrain_variants`。其中 `terrain_variants` 用 `x,y` 键记录外观；只接受所属地形的变体。导入先验证行列、整数、范围、外观归属和全部相邻关系，再替换当前地图。失败时保留原地图。

生成地图的调用方先执行 `TerrainCatalog.validate_map(data)`，通过后交给 `Grid.initialize(data)` 和 `CourtyardBoardView.configure(grid, profile, data)`。手工编辑器也走这一条路径。地表材质只用世界坐标采样，山坡共享顶点高度，墙体共享端点；不按放置顺序随机决定外观。

`validate_map` 要求完整的 10×10 至 25×25 方形地图。局部接壤素材检查使用 `validate_layout` 接受小片段，创作、导入、保存和试战不使用该片段入口。尺寸功能的证据见 `terrain-map-size.md` 与 `terrain-map-size-receipt.json`。

## 参考方法与适配

- [Tiled Terrain Brush](https://doc.mapeditor.org/en/stable/manual/terrain/)按边与角处理相邻图块，并在编辑后调整邻格。本项目采用相同的作者工作方式；现有 Godot 棋盘采用共享坐标材质混合，避免为九类地形穷举整张过渡图片。
- [Godot 4.6 Terrain Sets](https://docs.godotengine.org/en/4.6/tutorials/2d/using_tilesets.html)说明地形与邻接位的关系；本项目继续消费现有 Grid，不迁移玩法数据。
- [Nintendo 官方火纹页面](https://www.nintendo.com/en-gb/Games/Nintendo-Switch-games/Fire-Emblem-Three-Houses-1175482.html)的战场与地形图用于观察连续坡岸、道路及战场分区。墙体采用端头、转角、墙脚和破损轮廓的模块组织；这是本项目的适配方案，没有复制官方素材，也没有把官方截图当作墙脚实现说明。
- [Nintendo《Fire Emblem Engage》官方页面](https://www.nintendo.com/au/games/nintendo-switch/fire-emblem-engage/)的战场编辑图显示按格放置的石柱与地板，可用作石柱落地关系参考；官方图不足以验证本项目的墙体转角样式。

新岩面使用内置 imagegen 生成，完整提示词、原始来源与 SHA256 见 `terrain-kit-sources.json`。所有地形连接和墙山轮廓由运行时生成。

## 检查职责

- `test_terrain_kit.gd`：45 组合登记、32 合法异类原生图、转角与多重交会、五种障碍变体、三地图、约束拒绝、固定输入重建一致。
- `test_terrain_painter.gd`：实际鼠标绘制、拖拽、取样、撤销、错误导入回滚、保存回读与手工/直接加载一致。
- `test_terrain_map_size.gd`：边长设置、扩大补平原、缩小裁边与撤销、25×25 边角操作、尺寸拒绝、保存加载及两分辨率下的正式试战往返。
- 原有水岸、水深连续性、邻接、三场景整屏和战斗交互检查继续运行；错误样本必须仍被拒绝。
- 实际看图检查水面是否仍水平、岩坡是否吞掉窄地形、墙脚是否悬浮、转角是否裂开、是否存在刺眼边框和明显重复纹样。测试数量与截屏数量不能代替看图。

实际运行结果和独立审查以 `terrain-kit-receipt.json` 及其证据目录为准。

当前图形覆盖为每种合法异类的一种直边布局及八组代表性边角、窄道和多地形交会；没有穷举所有地图布局。新场景仍须在无格线整图和实际占格视图中检查遮挡与地形可辨性。
