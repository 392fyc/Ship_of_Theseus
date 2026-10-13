# 地形测量 v3：S5 与 N1

## 版本与兼容

校验器接受 `--measurement-version v1|v2|v3`，默认仍为 `v1`。只有显式选择 `v3` 时，case、pilot、batch 和命令行摘要才记录 `measurement_version: "v3"`；`v1` 与 `v2` 的输出字段和测量结果维持原状。

离线复算对 TASK92 的 `validate_case` 与 `validate_pilot` 结果分别和既有 v1、v2 报告逐对象比较，四项均完全相等。TASK94 也分别以冻结的 v1 源码和 S1–S4 v2 实现重新运行，当前 `v1`、`v2` 的 case 与 pilot 结果各自逐对象完全相等。比较收据和完整 JSON 位于本轮离线证据目录。

## S5：同帧不透明环境地面

T2、T3 仍从 `ground_types.png` 的精确调色板读取已分类地表；水类按类别名或 semantic 含 `water` 排除。v3 另外把同时满足下列条件的像素标作 `environment_ground`：

1. 当前实例或连接组的半径 4 外环内；
2. `ground_types.png` 的 alpha 恰为 `0`，表示没有类别标记；
3. 同坐标 `ground.png` 的 alpha 恰为 `255`；
4. 通过现有 coverage、排除、网格和阴影样本筛选。

`ground.png` 只提供“该位置有完全不透明地面”的判据。测量亮度仍由同坐标 `main` 图像提供，地面颜色不从 `ground.png` 读取。半透明地面 alpha（例如 254）与透明地面均不成为环境地面样本。

alpha 为零且地面完全不透明的未分类像素，按本轮 v3 规格作为 `environment_ground`。未来水域需要在 `ground_types` 中获得明确水类标记，以便继续排除。

## L1：T2 地表白名单

v3 的 T2 只接受 `plain`、`forest`、`paving`、`wall`、`swamp` 五类，以及上节定义的 `environment_ground`。名称或 semantic 明确为 `lava`、`peak`、`mountain` 的地类不入样；水类仍排除。T3 沿用 `plain`、`forest`／草地语义参照并增加 `environment_ground`；`paving`、`wall`、`swamp` 不会因此自动成为树冠草地参照。

## N1：T3 未测原因与外环计数

v3 的每个 T3 树实例结果保存以下外环计数：

- `outer_ring_total_pixels`
- `outer_ring_prop_covered_pixels`
- `outer_ring_excluded_pixels`
- `outer_ring_grid_pixels`
- `outer_ring_contact_shadow_pixels`
- `outer_ring_ground_shadow_difference_pixels`
- `outer_ring_unclassified_pixels`
- `outer_ring_usable_ground_pixels`

`outer_ring_unclassified_pixels` 计数外环中 `ground_types.png` alpha 为零的像素；其中一部分也会是 `environment_ground`。每个字段分别与相同的外环相交，因此道具覆盖、HUD/排除、网格、未分类等计数可以重叠，不构成互斥分区。若冻结或 sidecar 前置未通过，像素计数写为 `null`，表示没有测量，不能解释为零。

未测 T3 行的 `not_tested_reason_categories` 与 `not_tested_reasons` 按实例列出原因，类别为 `source`、`geometry`、`alignment`、`no_outer_ring_reference`、`outline`。同一实例可能有多个原因。v3 batch 在 `T3_not_tested_reason_summary` 中报告总实例数、按原因计数和逐 case 计数；原因计数可以重叠。完整六组原件可用后，batch 汇总以实际六组结果为准。

## L2：参照范围

v3 每条 T2/T3 实例记录都写 `reference_scope`：墙体使用其捕获连接组的外环并标为 `group`，柱体使用各自外环并标为 `instance`；树木使用树丛共用外环并标为 `group`。单成员连接组仍按组范围报告。该字段不改变顶面、侧面或树冠本身的逐实例数值。

## 不变项

测量半径仍为 4；物体有效像素仍按 coverage alpha `>127` 选取，地面参照要求 coverage alpha `=0`。alpha 小于 `0.98` 的不确定样本继续保留并只打原有不确定标记。T2/T3 阈值、统计函数和周长分母均未调整。v3 复用现有 v2 T2 循环与 T3 测量流程，没有复制平行测量实现。冻结的树冠对齐比较保持原样。

## 离线核验

TASK92 与 TASK94 各自提供的输入目录均含一个 `10x10 / 1280x720` pilot 清单；它们不是六组原件。两个 pilot 的冻结与 sidecar 前置均通过。TASK92 v3 得到 7 条墙、3 条柱、12 条树记录；TASK94 v3 同样得到 7 条墙、3 条柱、12 条树记录。每条树结果都包含全部外环诊断字段并标记树丛参照范围。TASK92 树结果为 12 条 `FAIL`，TASK94 树结果为 12 条 `PASS`；这是冻结样本的指标输出，不代表美术接受。

完整的 v1/v2/v3 JSON、输入清单 SHA256、TASK94 原源码恢复校验摘要、兼容性比较和行数汇总，保存在本轮指定的仓库外离线证据目录。TASK94 源码使用与候选 `dabfebab5ae3a3fc48dd0b461c0a255b9d5890d9` 对应的原精确快照；恢复清单记录 1396/1396 文件字节与 SHA256 匹配。原始捕获清单未被修改。本轮没有运行 Godot。
