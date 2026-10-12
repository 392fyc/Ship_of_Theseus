# 地形可读性测量口径 S1–S4

## 版本选择

校验器支持 `--measurement-version v1|v2`，默认 `v1`。`v1` 保留原输出字段、逐实例外环和 pilot 判定行为。`v2` 只调整本文件列出的参照面、连接组和柱侧部件选择；冻结测量函数及其阈值不变。

在 TASK92 冻结输入上的全量 `validate_case` 与 `validate_pilot` 对照中，默认 `v1`、显式 `v1` 和基线 `dabfebab5ae3a3fc48dd0b461c0a255b9d5890d9` 的完整结果逐对象深度相等。原生 Python 离线复算报告与 JSON 位于 `<仓库外证据根>/sot-measurement-v2-20261012/`。

## S1：墙与柱使用所有非水地表参照

`v2` 的 T2 参照来自各 wall/pillar 当前语义实例掩膜外侧半径 4 像素环，与冻结 `ground_types` palette 中非水地表类别的交集。按类别名或 semantic 值含 `water` 的 palette 类排除。实例行写入 `reference_surface_pixels`、`reference_surface_categories`（每类包含名称、semantic、像素数）和 `water_pixels_excluded_from_reference`。地表参照亮度写入 `reference_surface_l`；`v2` 不把这类样本命名为 paving。

有效样本仍要求 `coverage.A=0`、未被冻结地面排除掩膜挡住，并通过现有同坐标可见性条件。`semantic="wall"` 可能描述墙格下方地面图层中的墙类地表；只有 coverage 标记为空的坐标能成为参照，因此墙绘制面本身不进入地面样本。

## S2：相连墙组使用并集外环

每个 wall 先读取捕获清单中的整数 `cell=[x,y]`，并由当前 `semantic_pair` token 与 `semantic_coverage` 构造可见实例掩膜。两个实例只有同时满足以下条件才连边：

1. 捕获 cell 的 Manhattan 距离为 1；
2. 可见语义掩膜重叠，或存在 Chebyshev 距离不超过 1 的像素接触（8 邻域）。

以该连边图的传递连通分量作为墙组。组按成员 cell 的最小 y、最小 x、stable ID 排序，编号为 `wall-group-01` 等。分组判定使用完整可见实例掩膜，不用样本搜索半径扩张。

采样时，各成员当前可见掩膜先分别扣除既有对象排除，再求组并集；该并集半径 4 外环作为每个成员的共同地表参照范围。这样墙组内部接缝不会被误算为外侧地面。每条成员行保留自己的顶面和侧面中位数。组记录含成员 stable ID、捕获 cell、可见掩膜像素数、排除后测量掩膜像素数、连接规则和状态。

## S3：树丛共用草地外环，树冠数值仍逐树计算

树的分组成墙组相同，使用捕获 cell Manhattan 邻接与当前可见部件掩膜接触的双重条件。树掩膜只纳入部件码 7、8、9（树冠、暗侧、轮廓）。连通分量按 cell 的 y、x、stable ID 排序为 `tree-clump-01` 等。

每个树丛的成员掩膜扣除既有对象排除后求并集，以其半径 4 外环和冻结草地/森林 palette 交集作为所有成员的共同草地参照。每棵树仍单独计算自己的树冠、暗侧、轮廓像素和树冠中位数；只有外环草地参考范围按树丛共享。`T3` 的冻结阈值与 outline 检查保持原值。

## S4：柱侧面仅统计 code 4

`v2` pillar 顶面仍只使用 code 3；侧面只使用 code 4。`pillar_base` code 5 不纳入侧面样本。`v1` 仍按既有定义把 code 4 与 code 5 合并为侧面。

## 固定项

- 测量半径保持 4；连接分组只看捕获 cell 和当前可见掩膜接触，不使用该半径决定成员。
- 样本 alpha 条件保持 `coverage.R > 127`（alpha > 0.5）；alpha < 0.98 仍计入样本，并只保留原有不确定标记。
- 单位、界面、高亮、网格、其他道具、接触阴影、地面阴影差分和冻结排除掩膜沿用现有规则。
- `terrain_readability_metrics.py` 中的 T2/T3 阈值、统计函数、周长分母均未改动。
- 数值负例门在 `v1` 使用原 `paving_pixels`/`paving_l` 字段；在 `v2` 使用 `reference_surface_pixels`/`reference_surface_l`。缺样本或缺字段仍为 `NOT_TESTED`，不会靠缺值建立数值 FAIL。

## TASK92 冻结样本离线结果

校验器从本候选工作树导入；数据原件位于 `<仓库外证据根>/sot-task92-pilot-20261012/originals/approved-continuation/terrain_task92/output/10x10_1280x720/10x10_1280x720/`。source-root 使用精确冻结源码快照 `<仓库外证据根>/sot-task92-pilot-20261012/task92-frozen-source`，来源提交为 `ecf0521f438b2999854c7de61a13a8935b1715ea`。两版 frozen V6/V5 与 sidecar 前置均通过。执行使用科学 Python 离线；未运行 Godot。

| 版本 | 类型 | 行数 | 数值 FAIL | 数值 PASS | NOT_TESTED |
|---|---|---:|---:|---:|---:|
| v1 | wall | 7 | 4 | 0 | 3 |
| v1 | pillar | 3 | 1 | 0 | 2 |
| v1 | tree | 12 | 5 | 0 | 7 |
| v2 | wall | 7 | 7 | 0 | 0 |
| v2 | pillar | 3 | 3 | 0 | 0 |
| v2 | tree | 12 | 9 | 0 | 3 |

`v2` pilot 门的旧 wall、pillar、完整 tree 数值 FAIL 数分别为 7、3、9；tree 仍有 3 行 `NOT_TESTED`，均因并集外环中没有可用草地样本。素材迭代门在数值墙 FAIL 与完整树 FAIL 同时成立后为 `OPEN_FOR_MATERIAL_ITERATION_REVIEW`，这只记录 pilot 门输出，不代表素材审批或美术验收完成。

`v2` 的墙组为 6 成员组和 1 个单例；树为 4 个三成员树丛。完整 stable ID、cell、像素数、逐行测量和每个 `NOT_TESTED` 理由见 `<仓库外证据根>/sot-measurement-v2-20261012/report.md` 与同目录下的 `task92-v1.json`、`task92-v2.json`。

TASK94 尚未在本文测量；该轮正式输入仍待对应 manifest 和掩膜原件齐备后再复核。
