# 可复用地形库与残垣庭院候选

当前包含九类地形的可复用拼接库、地图工作台，以及荒草中庭、积水花园、断墙回廊三张可玩场景。深浅水渐变 v6 和地形拼接库当前外观均已由用户批准，分别记录在 `water-depth-approved.json` 与 `terrain-kit-approved.json`。地形依据及规则缺口见 `terrain-design-reference.md`。

地图创作入口为 `scenes/playground/terrain_painter.tscn`。可以直接摆放地形、选择墙与山峰变体、撤销、保存和加载 JSON。点击右上“开始试战”，当前地图即可进入正式战斗；“返回编辑”保留地图、笔刷和撤销记录。使用方式、组合限制和研究依据见 `dev_doc/ui-art-research/visual-review/terrain-kit.md`；功能接入说明见同目录下的 `terrain-runtime-integration.md`，交付证据见 `terrain-runtime-receipt.json`。

工作台地图仅支持正方形。右上设置边长（10 至 25 格）后点击“调整大小”：扩大保留已有内容并补平原，缩小裁去范围外内容，均可撤销。保存、加载与正式试战共用此限制。尺寸功能的当前证据见 `terrain-map-size-receipt.json`。

## 打开与操作

在 Godot 4.6 打开 `scenes/playground/battlefield_courtyard.tscn`，运行当前场景。

- 左上三个场景按钮切换地图，并重新开始该场战斗。
- 点击移动格，使用已定版底部技能和结束行动。
- 中键或空地拖动平移；滚轮围绕鼠标指向位置缩放；“居中”恢复适合当前窗口的视野。
- “格线”“范围”“提示”分别控制棋盘线、移动及技能范围、地形悬停卡。关闭后可直接审看地形外观。
- “灰盒 / 成品”查看同一地图的几何与材质；“重开”复位。

## 地形辨识

| 正式类型 | 当前候选表现 |
| --- | --- |
| 平原 PLAIN | 开阔短草与裸土，院内道路仅作为部分平原格的铺地外观 |
| 森林 FOREST | 清楚的树干、分枝、树冠和根部，树下为苔土 |
| 山地 MOUNTAIN | 低矮岩地与连续碎石坡，沿用可通行地形 |
| 山峰 PEAK | 相邻相连的裸岩或覆苔山体，沿用不可通行地形 |
| 墙 WALL | 有高度、厚度与砌石立面的墙体，墙段连成院墙或房间 |
| 浅水 SHALLOW_WATER | 较明亮的青绿色水面与临岸区域 |
| 深水 DEEP_WATER | 深暗水域、不可见水底，与浅滩形成清楚边界 |
| 熔岩 LAVA | 冷却岩壳、热裂隙及周围焦土 |
| 沼泽 SWAMP | 不规则水洼、湿土与低植被 |

森林闪避的具体数值在设计书中仍待定。候选读取现有运行数据，但提示只显示“提高闪避”。浅水／深水的 Wet、墙／深水的特殊职业通行例外尚未接入；美术候选不补定这些规则。墙体不阻挡攻击线，与建筑摧毁后的 Ruins 不同。

## 三种空间

| 场景 | 场内路线 | 场外环境 |
| --- | --- | --- |
| 荒草中庭 | 草地、林地与中央墙体，贯穿院落的主路和横路 | 旧院墙与入口连接道路，两侧及前景形成林带 |
| 积水花园 | 浅滩渡口、深水和沿岸路径 | 水道贯穿场内并向两端延伸，上游桥道、两岸遗迹与树林连接 |
| 断墙回廊 | 连贯墙段、墙间开口和林地组织通路 | 两侧屋舍的墙体与地基连接中央通廊，建筑尺度决定边缘形状 |

路线和空间组织属于候选方案，尚未完成正式遭遇数值平衡。场外环境没有可点击逻辑格。

## 分层与动态

- 三图均为 8×8，64×32 菱形逻辑格，默认镜头 1.36 倍。占格、寻路、移动消耗和技能复用正式 Grid、Pathfinding、TacticalManager 与 GameAction。
- 地表与岸沿独立绘制；树木和墙体挂到与单位共用的前后排序层。墙体立面由引擎几何构建，林木由透明素材构建。
- 前景物体覆盖当前行动范围时适度淡化；遮住单位或鼠标指向格时进一步淡化，离开后平滑恢复。关闭范围可查看完整林木。轻微树冠摆动和水纹随引擎时间变化。
- 镜头在当前适配倍率的 0.75–1.45 倍之间缩放；拖动位移按倍率换算。缩放不改变玩法范围。
- 基础剑士继续使用已定版头像、技能、剑气和行动资源界面，不显示印记。地图单位仍为既有文字棋子；角色动画不属于本候选。
- 切图释放旧战斗与环境物体，并恢复旧地图注册；退出恢复 DataLoader 原状态。材质仅用于候选场景。

## 相邻地形决定外观

`courtyard_board_view.gd` 与 `scripts/ui/terrain/` 共用地形数据。地表在共享世界坐标中混合边和角；墙体根据相邻格连接轮廓与墙脚。场内地形和场外墙段使用同一套计算，场外部分仍不参与寻路。

| 相邻关系 | 当前表现 |
| --- | --- |
| 水与草地、裸土 | 小幅不规则的湿土与苔草接入水面，保持土岸质感 |
| 水与铺石平原、墙 | 原石面延续到水边，透明湿暗只作用于接触位置 |
| 浅水与深水 | 连续水材质和深度色调过渡 |
| 墙与墙 | 共用端点的直墙、转角、分叉；连接处不重复绘制端面 |
| 墙与草地、森林、铺石、水 | 随邻地变化的覆土、苔根、石基或湿墙脚 |
| 森林或铺石与开阔草地 | 苔土与破边过渡 |

积水花园的场外水道逐列继承最近边缘行的宽度和深浅水。断墙回廊用同一份建筑数据描述房间地面、门洞和墙段；墙体坐落于建筑边缘。不同高度的相接墙段共享连接处高度。

水岸不用连续等宽的高亮描边。湿土边缘只在格边附近数像素内变化；石砌岸允许保留建筑硬边。六格局部样例与整条水道都要检查岸边是否自然、是否存在贴片感。

修改逻辑地形后调用 `refresh_terrain_visuals()`，地表、相邻边缘、山体与墙体物件随之更新。九类地形的 45 种组合登记在 `terrain_catalog.json`，41 种有效、4 种熔岩直接接壤组合排除，含对角接触。固定样例已扩展到全体合法异类组合及多地形转角；运行检查不等于所有可能地图的美术均已获认可。

## 素材和来源

素材由内置 imagegen 生成，以已批准的地形样本为风格参考；水面 v5 根据本项目笔触、配色与职责约束重新生成。原始图像逐字节保留，透明物体通过运行时 AtlasTexture 读取区域。地表按连续世界坐标映射，水深色调、岸沿、水纹、墙体几何和遮挡淡化由 Godot 渲染。当前共用水面采用 `water-surface-v5.png`，只提供水面笔触，不把水底石子和局部浅滩画进材质；旧图以非活跃来源保留。

`source-manifest.json` 保存每个素材的完整提示词、摘要、当前使用状态和只读规则来源。`visual_profile.json` 保存素材区域、落脚偏移及镜头；`courtyard_layouts.json` 保存地形、铺路外观、建筑轮廓、场外墙段和出生位置。三张可玩场景继续接受整屏回归；地形库另有 32 种异类接壤、代表性边角和三张创作示例的专项验证。当前外观已经批准；新创作地图仍需检查地形可辨性与遮挡，样例未穷举所有布局。

## 方法依据

- [Into the Breach 开发复盘，GDC 2019](https://media.gdcvault.com/gdc2019/presentations/Into%20the%20Breach%20Postmortem%20Final.pdf)：先确定可读性和单屏约束，再安排布局。
- [Tactical Breach Wizards 关卡制作，GDC 2025](https://gdcvault.com/play/1035595/Level-Design-Summit-The-Unusual)：小型手工关卡分别有明确的路线主题。
- [Blockmesh 与光照，GDC 2018](https://gdcvault.com/play/1025529/Level-Design-Workshop-Invisible-Intuition)：用简化形体检查布局，加入美术后再次试玩。
- [Riot 的画面可读性实践](https://www.riotgames.com/en/news/valorant-shaders-and-gameplay-clarity)：维护环境、角色与交互标记的明度层次。
- [Godot 4.6 TileMaps](https://docs.godotengine.org/en/4.6/tutorials/2d/using_tilemaps.html) 与 [CanvasItem](https://docs.godotengine.org/en/4.6/classes/class_canvasitem.html)：分层与独立显示状态。候选以 CanvasItem 适配现有 Grid。
- [Godot 4.6 Terrain Sets](https://docs.godotengine.org/en/4.6/tutorials/2d/using_tilesets.html#creating-terrain-sets-autotiling)：根据相邻边与角选择地形变体。本候选将邻接原则应用于既有 Grid 的绘制层。

以上资料用于制作方法；具体主题、坐标、空间构图和美术参数是本轮候选。

## 验证入口

逻辑及交互检查：

```text
godot --headless --path <project> --script res://tests/test_battlefield_courtyard.gd
```

统一实际画面采集：

```text
godot --path <project> --rendering-method gl_compatibility --script res://tests/capture_courtyard_visual_review.gd -- --output=<absolute-output-directory>
```

一次运行保存三场景 × 两分辨率 × 常态／范围图，共 12 张原始 PNG；固定随机种子和 2 秒动画时刻，每个状态连续两帧必须完全一致。`capture-manifest.json` 记录尺寸、状态、帧号、图片、源代码及所引用素材摘要；采集期间来源有变化即报错。当前截图标记为未获认可的候选，不自动成为回归比较基线。

水岸与水深的明确预期及错误对照：

```text
godot --path <project> --rendering-method gl_compatibility --script res://tests/test_courtyard_water_visual_contract.gd -- --output=<absolute-output-directory>
```

检查采用独立规格 `dev_doc/ui-art-research/visual-review/water-visual-contract.json`。连续深区的核心用于身份与完整色调校准；中央浅水、石岸实色亮带、深水画成浅水颜色的错误样本需要被相应检查拒绝。任一未被拦截时不允许报告该检查有效。单格的平缓低洼表现由下方连续性检查独立验证。

连续水深及代表性水域检查：

```text
godot --path <project> --rendering-method gl_compatibility --script res://tests/test_courtyard_water_depth_continuity.gd -- --output=<absolute-output-directory>
```

代表图使用多格相连的深水盆地与外围浅水。渲染按连续坐标混合深浅色调，场内外与转角共用一个深度场；不改变任何格子的玩法类型。独立的多点曲线检查过渡宽度、交界突跳和颜色变化方向，并用硬切与旧窄色带校准。中心较暗本身不足以判定过渡合格。

水与石材的单张、重复及实用尺寸检查：

```text
godot --path <project> --rendering-method gl_compatibility --script res://tests/capture_courtyard_material_intake.gd -- --output=<absolute-output-directory>
```

来源身份检查与原生 PNG 采集是自动步骤；材质语义和重复效果需要实际看图后记录，不能由“生成成功”推定质量通过。

邻接变化检查与六格实际对照图：

```text
godot --path <project> --rendering-method gl_compatibility --script res://tests/test_courtyard_terrain_adjacency.gd -- --output=<absolute-output-directory>
```

检查湿土岸／石岸／深浅过渡、墙端／直线／转角、不同墙高的共用顶点、场内外连接，以及修改相邻格后的实际物件刷新与释放。

固定 24 帧／秒、8 秒模拟的真实渲染序列：

```text
godot --path <project> --rendering-method gl_compatibility --fixed-fps 24 --script res://tests/capture_battlefield_environment_motion.gd -- --layout=overgrown --output=<absolute-output-directory>
```

动态采集按引擎帧生成 192 张原始 PNG，包含镜头变化、森林悬停、一次合法移动和隐藏辅助标记，并验证对应森林格的实际树冠淡化，另支持 `--layout=flooded`。逐帧写盘耗时不作为视频播放时长；可以按 24 帧／秒编码原始序列。headless 模式拒绝生成替代影像。

后续视觉迭代使用 [美术自检流程](../../../dev_doc/ui-art-research/visual-review/README.md)。测试结果、视觉审查、已知限制与发布状态见 `candidate-receipt.json`。功能通过不代替图像检查或用户视觉验收。
