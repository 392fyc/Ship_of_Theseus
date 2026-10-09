# TERRAIN-READABILITY 语义 sidecar 工具

## 当前状态

这是本机工具候选。Python 合成测试和 headless 结构检查只能验证代码路径，不能证明原生像素配准、美术结果或 T1–T6 批次验收。原生采集前须先完成独立审查。只有 TASK52 全部 208 件原件完成消费、独立审查完成、最终签名回执可核验且读回状态确为 `closed`、`count=1` 后，才可启动新的云端任务；不能提前投递。此文档不表示材质迭代门或美术验收已开放。

## 范围与数据契约

入口 `capture_terrain_readability_v6_regions_semantic_sidecar.gd` 继承冻结 V6 tree-region 入口。原有 12 张 capture 图、V6 清单、candidate/source 摘要、同帧流程、C4/C8、T2/T3 阈值和原有排除定义保持不变。两个额外视口分别输出 `semantic_pair.png` 与 `semantic_coverage.png`，不加入冻结采集器的 `_passes` 或 12 图字典。

- `semantic_pair.png` 为 RGBA8：RGB 是稳定的非零 24 位实例令牌，A 是非零部件码；零 token/零部件码表示背景。未知可见道具保留独立令牌和非零 `unknown` 部件码，并继续遮挡先前绘制内容。
- `semantic_coverage.png` 的 R 是原始有效 source alpha 字节，A=255 表示该像素被非零 alpha 的对象绘制覆盖；G/B 为零。标签 A 是类别码，不是透明度。source alpha 为零时 shader `discard`，不会擦除后层标签。
- 墙顶/墙侧/墙线与柱体部分依据实际 `Polygon2D`/`Line2D` 节点分类。树冠、暗侧和轮廓来自冻结 V6 的 crown annotation 与已绑定作者语义/独审输入，暗侧几何继续与原 crown 及 AtlasTexture alpha 相交。outline 只有在显式独审批准 `outline_absence` 时才记为权威缺席；空 polygon 数组不构成缺席证据。
- 复制节点保持原排序、变换、调制、纹理过滤、repeat 与 alpha 来源。每个树源 Sprite 只绘制一次：shader 的 `COLOR.a` 沿原 Sprite2D `TEXTURE` 与其原 filter/repeat/mipmap 路径读取 source alpha；coverage 模式直接复制此值，完全不采样类别图。树部件类别由独立 RGBA8 类别图提供，R 存部件码、A 标记有分类的 atlas 区域，使用 `filter_nearest`、`repeat_disable` 且不生成 mipmap。shader 从原 Atlas `UV` 换算像素坐标，再减去原 Atlas region 起点并除以 region 尺寸，得到 region-local UV。类别图零码或 UV 越出 region 时回退到非零 unknown 码；原纹理 alpha=0 仍 discard。类别图在源区域像素中心按已审查 crown/dark-side/outline polygon 生成，dark-side 只有在 crown polygon 内才编码，不读取亮度或颜色。无法复现的自定义材质、`_draw` 或 alpha 路径必须明确失败为 `NOT_TESTED`，不得默默跳过对象。
- 同一 `frame_post_draw` 回调内读取旁路图并记录原图帧状态、Window/Viewport/Image 尺寸、canvas/final transform 与逐图 SHA。sibling manifest 绑定最终 `capture-manifest.json` 原字节摘要、候选、源码与树语义输入摘要。变换相同不是像素配准证明；validator 还要求同坐标精确 RGBA、唯一 legacy opaque ID 锚点和原 props alpha 覆盖。

## 测量入口

`validate_terrain_semantic_sidecar.py` 先运行冻结 V6/V5 验证，再核对旁路清单、逐图字节和 SHA、候选/source/input 原字节、同帧/尺寸、标签和 coverage、alpha>0.5 覆盖、唯一精确 legacy 像素锚点、冻结可见实例数以及遮挡/排除掩膜。未通过前置时 T2/T3 都是 `NOT_TESTED`。

前置通过后，测量只使用正式 main 原图坐标的 RGB 转 Lab 结果和同坐标语义像素：

- 每个 wall、pillar 均输出一行 T2。顶面、侧面来自语义部件标签；相邻铺地取实例原 alpha>0.5 可见掩膜的欧氏半径 4 外环与冻结 `ground_types` paving 类的交集。其他道具（含 unknown）、单位/HUD、grid、contact shadow 以及同位置有阴影差异的地面像素全部排除。每行包括三个样本数、三个 L* 中位数、指标状态及 alpha 不确定像素数。
- 每棵树均输出一行完整 T3。最终 canopy 掩膜包含 crown、dark-side 和已审查 outline 像素；暗侧同时单独传给冻结 `foliage_outline`。外围草地来自该最终 canopy 的欧氏半径 4 外环与冻结 `ground_types` grass/forest 类的交集，并扣除所有道具（含 unknown）、单位/HUD、grid、contact shadow 和冻结排除。outline 检查通过且树语义/源摘要完整后，调用冻结 `foliage_outline` 与 `foliage`。输出冠层、暗侧、outline、外围草地样本数，alpha 不确定数，outline 检查以及完整 T3 数值和状态。
- `coverage.R > 127` 是严格 alpha>0.5 样本门槛。alpha 0.95/0.96 会进入 T2/T3；alpha<0.98 只计为不确定像素，不会整实例或整块墙侧被拒绝。T2 直接调用冻结 `terrain_readability_metrics.planes`；该冻结函数不执行 .98 阈值筛选。
- 旧墙 T2 与旧树完整 T3 负例须分别有真实、数值完整的冻结指标 `FAIL` 才可记为 `ESTABLISHED`。所有 wall/tree 实例行都会留在逐案例报告中；状态、样本不足和负例摘要不得挑选个别实例隐藏其他行。任何输入、像素配准或样本不足都保留 `NOT_TESTED`，不能用来成立负例。
- 10×10/720p 是首个前置门；其失败时停止剩余五组采集。前置通过后若旧墙/旧树负例尚未成立，其余采集可以继续，但材质迭代门仍关闭。完整六组必须来自同一个候选；此工具只测 T2/T3，不代表 T1、T4、T5、T6、C7 或视觉审查完成。

具体样本口径以 `measurement.md` 和冻结 `terrain_readability_metrics.py` 为准；本工具不改指标实现、阈值、周长分母或旧排除定义。

Atlas 映射依据 Godot 4.6 的 [CanvasItem shader 文档](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/canvas_item_shader.html)：`UV` 是归一化纹理坐标，fragment 输入 `COLOR` 是默认 `TEXTURE` 与顶点/节点颜色的乘积；[AtlasTexture 源码](https://github.com/godotengine/godot/blob/4.6-stable/scene/resources/atlas_texture.cpp#L148-L153)将 AtlasTexture 绘制委托给底层 atlas，[region 换算源码](https://github.com/godotengine/godot/blob/4.6-stable/scene/resources/atlas_texture.cpp#L180-L208)把源坐标偏移到 atlas region；[Sprite2D 源码](https://github.com/godotengine/godot/blob/4.6-stable/scene/2d/sprite_2d.cpp#L148-L158)把 Sprite2D 的源矩形交给纹理的 `draw_rect_region`。工具据此使用 `atlas_pixel = UV * atlas_size` 和 `region_local_uv = (atlas_pixel - atlas_region.position) / atlas_region.size`。Atlas region 必须与已绑定标注一致且落在整数源像素边界。此映射的合成测试只验证换算和结构契约；类别图与实际 Godot 渲染像素的逐像素对齐仍待原生验收。

## 分阶段运行方式

采集必须使用 Compatibility 渲染的原生窗口。先导入资源，再通过 V6 继承入口执行 headless 结构核对。结构核对仍可一次覆盖六组；原生模式每个进程只接受一个地图尺寸和一个分辨率。validator 默认 `--phase=batch`，pilot 读回应显式传 `--phase=pilot`。

```text
godot --headless --editor --path . --quit
godot --headless --path . --script res://tests/claude_review/capture_terrain_readability_v6_regions_semantic_sidecar.gd -- --headless-check --map-sizes=10,25 --resolutions=1280x720,1920x1080,2560x1440 --v3-diagnostic=<external-diagnostics/structure-v3.json> --v5-diagnostic=<external-diagnostics/structure-v5.json>
```

先运行单独的 10×10/720p pilot，再立即读回该 manifest。只有 pilot validator 返回 0 且报告 `preconditions=PASS`、`remaining_five_capture_action=CONTINUE` 才能启动后续五个独立原生进程。pilot 前置失败时停止；pilot 前置通过但负例缺失、数值不完整或没有 FAIL 时仍可继续采集，`material_gate` 保持 `CLOSED`。

```text
godot --path . --script res://tests/claude_review/capture_terrain_readability_v6_regions_semantic_sidecar.gd -- --out=<external-output/pilot-10x10-720> --map-sizes=10 --resolutions=1280x720 --v3-diagnostic=<external-diagnostics/pilot-v3.json> --v5-diagnostic=<external-diagnostics/pilot-v5.json>
python -X utf8 -B tests/claude_review/validate_terrain_semantic_sidecar.py <external-output/pilot-10x10-720/10x10_1280x720/capture-manifest.json> --phase=pilot --source-root . --candidate <full-candidate-HEAD> --out <external-output/pilot-readback.json>
```

pilot 读回 `STOP` 或退出码非零时，不运行下列五条命令。通过 pilot 前置后，每条命令各启一个新原生进程，并使用独立输出目录及诊断文件：

```text
godot --path . --script res://tests/claude_review/capture_terrain_readability_v6_regions_semantic_sidecar.gd -- --out=<external-output/10x10-1080> --map-sizes=10 --resolutions=1920x1080 --v3-diagnostic=<external-diagnostics/10x10-1080-v3.json> --v5-diagnostic=<external-diagnostics/10x10-1080-v5.json>
godot --path . --script res://tests/claude_review/capture_terrain_readability_v6_regions_semantic_sidecar.gd -- --out=<external-output/10x10-1440> --map-sizes=10 --resolutions=2560x1440 --v3-diagnostic=<external-diagnostics/10x10-1440-v3.json> --v5-diagnostic=<external-diagnostics/10x10-1440-v5.json>
godot --path . --script res://tests/claude_review/capture_terrain_readability_v6_regions_semantic_sidecar.gd -- --out=<external-output/25x25-720> --map-sizes=25 --resolutions=1280x720 --v3-diagnostic=<external-diagnostics/25x25-720-v3.json> --v5-diagnostic=<external-diagnostics/25x25-720-v5.json>
godot --path . --script res://tests/claude_review/capture_terrain_readability_v6_regions_semantic_sidecar.gd -- --out=<external-output/25x25-1080> --map-sizes=25 --resolutions=1920x1080 --v3-diagnostic=<external-diagnostics/25x25-1080-v3.json> --v5-diagnostic=<external-diagnostics/25x25-1080-v5.json>
godot --path . --script res://tests/claude_review/capture_terrain_readability_v6_regions_semantic_sidecar.gd -- --out=<external-output/25x25-1440> --map-sizes=25 --resolutions=2560x1440 --v3-diagnostic=<external-diagnostics/25x25-1440-v3.json> --v5-diagnostic=<external-diagnostics/25x25-1440-v5.json>
python -X utf8 -B tests/claude_review/validate_terrain_semantic_sidecar.py <all-six/capture-manifest.json paths> --phase=batch --source-root . --candidate <same-full-candidate-HEAD> --out <external-output/batch-readback.json>
```

pilot 材质迭代门只读该 pilot 自身前置与逐实例数值：旧墙 T2 和完整旧树 T3 均有真实、数值完整的 FAIL 时才开放审查。负例行不会跨案例拼接。`--phase=batch` 另行要求六组完整覆盖及同一候选的六组前置全部 PASS；它不会改写 pilot 材质门，也不代表 T1–T6、美术或原生像素验收通过。所有原生命令都必须显式给出仓外 `--v3-diagnostic` 与 `--v5-diagnostic` 路径；没有 `--v6-diagnostic`。Headless 结构模式不输出可用于测量的图像。

## 本地检查边界

`test_terrain_semantic_sidecar.py` 使用小型合成 RGBA 样本验证字节令牌、冲突拒收、alpha=0 不覆盖、unknown 遮挡、coverage 独立通道、Atlas UV→region-local UV 的非零偏移映射、alpha 0.95/0.96 样本纳入、冻结 T2/T3 函数调用、同帧/尺寸/SHA 绑定、精确像素对齐和数值负例证据门。测试同时检查类别图不会修改 source-alpha 值，也不会插入新的 draw item。合成样本不是采集图，也不构成原生像素或美术验收。原生逐像素配准仍须在正式 capture 批次核实。
