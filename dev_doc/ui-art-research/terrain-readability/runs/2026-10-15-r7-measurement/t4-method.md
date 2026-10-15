# TASK117 地形接地阴影 T4 诊断

## 适用范围与冻结记录

本记录按已采纳的 Claude T4 补充方法，对 TASK117 的旧 R6 捕获做一次重新测量。它只说明这组旧捕获在新 T4 条件下的数值；R7 正式结论仍需使用 R7 新捕获重新运行。R6 的旧 `material-analysis.json`、`internal-seam-proof` 和其他原件保持原样，本次结果不继承旧 PASS。

测量工具为 `tests/claude_review/terrain_contact_shadow_v2.py`，单元测试为同目录下的 `test_terrain_contact_shadow_v2.py`，逐对象机器结果见本目录的 `t4-task117-diagnostic.json`。诊断在 `2026-10-15T13:34:26.743345+00:00` 生成；此时间也作为本次 T4 源码与输出的冻结点，诊断内记录了源码字节 SHA256。旧捕获候选是 `6ec8a9ffe1ce56005737d1036904d88d1c08a54a`，清洁状态字段为 `dirty=false`、`working_tree_candidate=false`。旧捕获清单没有记录候选冻结的墙钟时间，因此不推定其时间；上面的时间是 T4 重测时间。诊断 JSON 的 `evidence_scope` 按实际输入记录 candidate commit、case、fixture 和 frame，并注明单组测量不代表整体验收；本 TASK117 记录仍以 `t4-task117-diagnostic.json` 和本方法文档标题识别。

## 测量依据

捕获画面为 `10x10_1280x720`，尺寸 `1280×720`，渲染器为 `gl_compatibility`，公共帧号为 `45`。语义清单的 SHA256 绑定捕获清单的原始字节；本次用到的八张 PNG 均由捕获清单逐张校验 SHA256、尺寸和帧号。`ground` 与 `ground_without_shadow` 在同一帧、相同原始像素坐标逐像素配对；每个阴影像素的 L* 变化都从这两个图相同的 `(x,y)` 位置取得。

阴影候选像素要求 `contact_shadow` alpha 大于 0.5、两张地面图 alpha 大于 250/255，并且 `props`、`grid`、`exclusions` 的 alpha 均不大于 0.5。所有坐标保持捕获原尺寸，没有缩放。遮挡和阴影像素均通过 PNG 字节哈希绑定到捕获清单。

接地几何来自捕获的语义绘制叶片和对应实例部件记录：柱体按 `pillar_base` 部件角色选取真实 `Polygon2D` 六边形底座外缘；墙体取每个 `wall_side` 四边形捕获多边形的第 2 至第 3 顶点底边，并按端点去重。墙边端点去重后共移除 19 条重复线段。几何先使用捕获的叶片全局变换，再应用主画布变换；捕获的格宽为 `58.880001 px`，半格为 `29.440001 px`。语义实例的仿射格宽拟合最大残差为 `5.68e-13 px`。

每条实际接地线段按弧长均匀离散：将该线段分成 `ceil(长度 / 0.5px)` 份，在各份中点取样，段内点间距不超过 `0.5px`；每点以 `线段长度 / 分段数` 作为弧长权重。这个分母只由捕获几何生成，不读取阴影遮罩或已通过的阴影像素。对每个几何样点，沿由多边形中心确定的外法线探测 `1px`：探测位置须落在画面内、同时属于两张同帧地面图，且不被不透明道具、格线或排除遮罩覆盖，才计为可见接地边。逐对象 JSON 固定记录自身道具、其他道具、无法归属的道具、单位/UI 排除区、格线、地面缺失、画面外和可见边八类计数与弧长，包括零值。这样定义了“可见边”：从捕获接地几何向外侧地面探测仍可见的边弧；被物体自身覆盖的几何区间和其他不透明物体覆盖区间不进入可见面分母。

阴影宽度是合格阴影像素中心到该物体捕获接地几何的最近欧氏距离。对象归属由其对全部候选接地几何的最近距离确定。冻结的 `terrain_readability_metrics.contact_shadow` 原公式保持不变：使用相同配对像素计算明暗变化，并以宽度 p90 执行 8–12 L*、不超过半格的规则；另外报告最大宽度。最低边距须不超过 `1px`。可见接地边上距合格阴影样本不超过 `2px` 的弧长比例须至少为 `0.60`。合格阴影像素少于 20 个时结果为 `NOT_TESTED`。

## 旧 R6 捕获重新计算结果

以下数值由工具对 10 个原始墙柱实例逐项计算。`覆盖率` 的分母是独立测得的可见接地边弧长；不是阴影像素数量。所有行均至少有 20 个合格像素，且工具根据冻结公式和新增接地/覆盖保护生成状态。

| 实例 | 状态 | 像素数 | 暗度 L* | 宽度 p90 px | 宽度最大值 px | 最小边距 px | 可见边覆盖率 |
|---|---:|---:|---:|---:|---:|---:|---:|
| pillar@1.00,4.00 | PASS | 95 | 9.5382 | 2.6575 | 4.0008 | 0.0392 | 0.8621 |
| pillar@1.00,7.00 | PASS | 64 | 8.7163 | 2.7711 | 4.2832 | 0.0117 | 0.8370 |
| pillar@8.00,4.00 | PASS | 100 | 9.1283 | 2.7872 | 4.1110 | 0.1054 | 0.8650 |
| wall@3.00,1.00 | PASS | 27 | 8.7750 | 2.4597 | 3.3541 | 0.1163 | 1.0000 |
| wall@3.00,2.00 | PASS | 124 | 8.7068 | 2.9069 | 3.3541 | 0.1699 | 1.0000 |
| wall@4.00,1.00 | PASS | 67 | 9.0474 | 1.9051 | 1.9051 | 0.1163 | 1.0000 |
| wall@5.00,1.00 | PASS | 45 | 8.3045 | 1.9051 | 1.9051 | 0.1163 | 1.0000 |
| wall@6.00,1.00 | PASS | 22 | 9.1658 | 2.6207 | 3.0679 | 0.3846 | 1.0000 |
| wall@6.00,2.00 | PASS | 114 | 9.3450 | 2.6207 | 3.0679 | 0.1699 | 1.0000 |
| wall@8.00,7.00 | PASS | 26 | 8.1803 | 2.7280 | 3.1752 | 0.0447 | 1.0000 |

合计 `PASS=10`、`FAIL=0`、`NOT_TESTED=0`。所有暗度落在 8–12 L*；所有 p90 宽度均远低于 `29.44px` 半格上限；最大宽度也逐项报告，但不替换原 p90 宽度判据。最小边距为 `0.0117–0.3846px`，可见边覆盖率为 `0.8370–1.0000`。

## 可复现命令

在游戏仓工作树根目录的 PowerShell 中运行。通过环境变量提供打包 Python 和只读捕获目录；捕获目录须含两份 manifest 及清单引用的 PNG。命令使用 `-B`，不写 Python 字节码缓存。

```powershell
$repo = (Get-Location).Path
$python = $env:SOT_BUNDLED_PYTHON
$captureDir = $env:SOT_TASK117_CAPTURE_DIR
$output = Join-Path $repo 'dev_doc/ui-art-research/terrain-readability/runs/2026-10-15-r7-measurement/t4-task117-diagnostic.json'
& $python -B (Join-Path $repo 'tests/claude_review/terrain_contact_shadow_v2.py') `
  --capture (Join-Path $captureDir 'capture-manifest.json') `
  --semantic (Join-Path $captureDir 'semantic-sidecar-manifest.json') `
  --png-dir $captureDir `
  --output $output
```

单元测试命令：

```powershell
$repo = (Get-Location).Path
$python = $env:SOT_BUNDLED_PYTHON
& $python -B (Join-Path $repo 'tests/claude_review/test_terrain_contact_shadow_v2.py') -v
```

## 字节 SHA256

哈希均为 SHA-256 原始文件字节摘要。逐对象遮挡分类和所有候选源码文件摘要也保存在诊断 JSON 中。

| 文件 | SHA256 |
|---|---|
| TASK117 捕获清单 `capture-manifest.json` | `e99d04c68e012c84f15857fd20f67d85accec662be07507340d951c99e47c264` |
| 语义清单 `semantic-sidecar-manifest.json` | `73f1e1c47b21d7d4c00ede5fe85b1e3cef3d0db565103959abe78cbb63a36584` |
| 主图 `main.png` | `67e6a6fb4de0ef016f9016f0178118b6feb1936c1c0f54c01758a86e3b9c6ce4` |
| 阴影遮罩 `contact_shadow.png` | `286e3745250bb778ed4df9ed8e8d0c6c34e454718bca0e2c3dc11f72e49fa718` |
| 排除区 `exclusions.png` | `335f61e448535baa18415dee14f94ba2e980abb96e2e4c88669d691038ae8959` |
| 格线 `grid.png` | `cf4a78afa2352a825d1c44d4c2f8a5473f74c885b2ddf288d172b72925dcc8f7` |
| 地面 `ground.png` | `396ef2ec8880a0f3febdf503f15b8f5dc34e4d736efbd590ac8a7c468dd03f3b` |
| 无阴影地面 `ground_without_shadow.png` | `7be27272402bc5aef508e6502a22fca24ff95d94b2abe2c04bf8553fc16840bf` |
| 实例标识 `instance_ids.png` | `6d541c0eb46eedb5c2f20647362b89095214387bd889df9e5d4fe8ac3756ff85` |
| 道具遮挡 `props.png` | `a3826fc306959d48eddabe67143e4dae060a38e656a185e141426ea1ba7b6e87` |
| T4 测量工具 `terrain_contact_shadow_v2.py` | `1e385a0368b981f65faccd8ba64be000d825ec026c0e827ab505e84954d2221b` |
| 冻结测量公式 `terrain_readability_metrics.py` | `5fd1e4594ef9c9388c6013fb61bc6315f83cfa7c59e4a5dec812ca289f65dabd` |
| L* 转换 `claude_review_checks.py` | `be32bf35c7d51d50242e0dcfa11fe79f4d2b931fa4101483fee58686dd651165` |
| T4 诊断 JSON | `d4152119470676f91de38ad61673094a4067621701883eedb99c2b33ad31333c` |

## 误差与边界

几何变换和点到线段距离在原始像素坐标中按浮点数计算；弧长样点间距最多 `0.5px`，并以每段真实长度权重恢复弧长。遮挡判定仍需映射到栅格像素：使用像素中心及 `floor` 像素索引，因此边界的可见/遮挡分类约有一个像素量级的栅格定位误差。L* 来自 8 位 PNG 色彩样本，也受原始色彩量化影响。工具报告逐项实际值，不对阈值附近值额外四舍五入后判定；表格仅为阅读显示做四位小数舍入。

本结果只覆盖旧 R6 单帧旧候选，不能代替 R7 新原图诊断，也不是 Godot 运行或里程碑验收。实现与单元测试冻结后仍需由 Main 独立审查及集成。
