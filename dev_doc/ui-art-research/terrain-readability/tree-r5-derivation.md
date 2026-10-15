# 树图 R5 RGB 派生记录

状态：`forest-tree-v3b.png` 已按修订后的颜色选区从原 v3 重新派生。文中的 T3 数字是 TASK112 同帧原图上的离线估算；树冠/暗侧 JSON 来源绑定由主代理整理，独立批准交审查者，R5 实际采集交 Dot。

## 来源与不变项

- 父图：`assets/prototype/battlefield_courtyard/forest-tree-v3.png`，SHA256 `616f54a6816f026d0154c390460ea4b90fdf3ddcbc8b782dcf295feffbf0be52`，尺寸 `1536×1024`。
- 新图只改 RGB。父图和派生图 alpha 逐像素全等，alpha 字节 SHA256 均为 `cd88a9d9d8d1ffda4e45ef01de55e0366bd0213966642d000d4433a944ea34ee`；Atlas 区域外 RGBA 全等；alpha `<4` 的 RGB 保持父图原值。Atlas 区域为 `[286,33,964,950]`。
- 使用 TASK112 原件 `semantic_tree_region_map.png`（`964×950`，SHA256 `c83e5fb0a8baa5143067fd6bdb88723dd62ca18579dd362df86d9903d2390e7e`）报告冻结码 7/8 的贴图统计。码 0 是语义几何的补集，含叶片和柔边，不是木材材质分割；派生脚本没有用语义码决定木色。RGB 木色选区只依据原 v3 像素颜色和 alpha，能跨越码 7/8。
- 冻结几何依据：树语义记录 SHA256 `19629f720a67c42cdd18d8ab69b388e9e696ec58e3676321820f5912015281a3`，树冠区域记录 SHA256 `d344c1a5c5e0560295588341e0cddf35a3c1840bd64772a45da146824dd7668c`，复核记录 SHA256 `5c291a71bb6d70efe6d5c81255b125318346f9e41228d6db926ef32cf7ca9250`。这些记录用于绑定已审查的采样几何；本次没有改动它们。

## RGB 处理参数

1. 把 R4 树调制 `[1.088777,1.281212,0.602625,1]` 烘焙到全张可见 Atlas 的 RGB，按 sRGB 编码通道相乘、截到 `[0,255]` 并取整。实际场景的调制应由主代理设为中性 `[1,1,1,1]`。
2. 为使码 0 中未分类的叶缘仍按叶面处理，对可见 Atlas 像素统一应用树叶高光软膝：`L>50` 时 `50+(L-50)*0.45`；`C>45` 时 `45+(C-45)*0.25`；色相保持，只有超出 sRGB 色域才降低彩度。本候选没有触发色域回退。冠区没有整体降低中间调彩度。
3. 木色权重在原 v3 RGB（R4 调制之前）计算：`R-G` 用 `[2,15]` 平滑渐入；原 Lab 色相在 `[10,24]` 渐入、`[24,76]` 保持、`[76,92]` 渐出；低彩度只降低色相判断置信度（C 从 2 到 12 渐入，置信度为 0 时保留 0.7 的中性色相权重），不单独判木；原 alpha `[4,64]` 平滑渐入。木色综合色权重再经 `smoothstep(0.05,0.85,w)`，减弱半透明边缘及不确定颜色，避免把色晕抬成不透明褐边。
4. 木色目标 Lab 色相先收在 `[63°,82°]`，彩度上限 `19.2`，为 8-bit 量化留余量；明度不做硬夹。高置信木色样本（权重 `>=0.85` 且 alpha `>=128`）的调制后 L* 第 2、50、98 百分位分别为 `18.5088、33.6999、62.9923`，用单调三次 Hermite 曲线映到 `26、30、31.5`，区间外接指数软尾，渐近偏移 `0.15`。曲线保留局部明暗顺序，没有把亮部统一夹到同一明度。构建脚本逐像素检查高置信选区的 L* 在 20–32、C*≤20；C*>2 的像素色相必须在 60°–85°，C*≤2 的无定义色相单独计数。
5. 原 v3 Lab 度量函数来自 `tests/claude_review/claude_review_checks.py`。脚本只对该辅助源码把工作树 CRLF 规范化为 LF 后核对 Git canonical SHA256 `c2c387df4bf4212fdc80f386233ff4e0b66768417ef69730f62079bc44a0f14a`；父 PNG、输出 PNG 与区域图仍按原始文件字节计算 SHA。

原尺寸直接查看新旧图：树干和枝条仍能看到暗槽与亮面纹理；树冠外缘没有随几何多边形切出的褐色叶片块。下表是贴图采样统计，不是引擎截图指标：

| 贴图区域 | 像素数 | L* p5 / p50 / p95 / 最大 | C* p50 / p95 / 最大 | hue p5 / p50 / p95 | `L>55 且 C>50` 占比 |
| --- | ---: | --- | --- | --- | ---: |
| 树冠码 7 | 211378 | 14.528 / 33.395 / 58.469 / 70.451 | 36.465 / 50.024 / 53.587 | 63.963° / 116.629° / 120.663° | 5.02% |
| 暗侧码 8 | 36415 | 16.812 / 30.562 / 52.537 / 63.923 | 34.303 / 47.500 / 51.788 | 108.398° / 118.291° / 120.943° | 0.77% |
| 高置信木色选区（色相按 C*>2） | 62448 | 26.862 / 30.006 / 31.284 / 31.803 | 19.165 / 19.525 / 19.659 | 61.835° / 63.747° / 70.572° | 0% |

码 7 达到贴图目标：L* p95 `58.469<=60`、最大 `70.451<=72`、C* p95 `50.024<=52`、亮且艳占比 `5.02%<=8%`、中位 L* `33.395>=33`。暗侧码 8 中位 L* `30.562` 低于冠区。木色高置信选区 L* 最大为 `31.803`、C* 最大为 `19.659`；C*>2 的色相范围为 `60.819°–80.570°`，C*≤2 无定义色相像素为 `0`。原尺寸直接复核保留了树干/枝根的暗槽和明暗起伏，曲线没有硬夹平亮部。输出 PNG SHA256 为 `4139562f7d0e6adafb18d0f7b73750dae480f4f20abce179f1540ae4bd53d856`，大小 `1573612` 字节。

## Godot 导入描述

`forest-tree-v3b.png.import` 的 UID 为 `uid://d78vkc4kut7q`，共 12 位，使用字母表 `abcdefghijklmnopqrstuvwxy012345678`。按 Godot 4.6 `ResourceUID` 的 base-34 规则解码为 `278668311132216188`，重新编码得到同一 UID；数值小于 `0x7fffffffffffffff`。在全仓 `.import` 文件的 UID 字段中，新 UID 仅本文件一处；文档中的同一字符串只用于记录。资源路径 MD5 后缀为 `dc10bbc65d96aa0191b149ed3dd1455a`；除 UID 和新资源路径外，导入参数与 v3 相同，`mipmaps/generate=false`。Nearest 是场景节点属性，不属于 `.import`；主代理的 `courtyard_board_view.gd` 在树根和 Sprite2D 上设置 nearest。文本文件使用 LF。没有运行 Godot 或生成导入缓存。

## TASK112 同帧 T3 离线估算

输入为 TASK112 readback/originals 下的 `task112_runner/output/10x10_1280x720/10x10_1280x720`。本轮先列出的原件文件名如下：

`capture-manifest.json`、`contact_shadow.png`、`exclusions.png`、`grid.png`、`ground_types.png`、`ground_without_shadow.png`、`ground.png`、`instance_ids.png`、`main.png`、`part_ids.png`、`portrait-hud.png`、`props.png`、`reconstruction.png`、`semantic_coverage.png`、`semantic_pair.png`、`semantic_tree_region_map.png`、`semantic_write_probe.png`、`semantic-sidecar-manifest.json`、`tree_crown_union.png`。

关键输入原字节 SHA256：capture manifest `c24791a279510bf13301a183829d1a548dff6af656666d1a85cba9cb046a32be`；sidecar manifest `2ff34cc8759447a7acaf3825260797ba9514950948902a53251ca42870a09c7c`；`main.png` `ea2977e3afa063205f1847b90a3fb3a00e2ada9493db4888a2825cfb666f460b`；`props.png` `96e6cef0bbbb091f3fd370acefd94069463d705065ca529fa324fc682215aa19`；`semantic_pair.png` `4967f75f5c51aba566cd3ef1c442a07508af5fa1082786dced85645bff9f7247`；区域图见前节。复用冻结文件 `terrain_readability_metrics.py` SHA256 `b024161fb309ce7410015dfa8a998fbd3363692461031d28cd4cb3ff149f7ac7`、`validate_terrain_semantic_sidecar.py` SHA256 `416e83e250bc2c2d178ee1f319958c324ea0e421a1b61a9abb20a3a612518f96` 和 Lab helper canonical SHA256 `c2c387df4bf4212fdc80f386233ff4e0b66768417ef69730f62079bc44a0f14a`。冻结原图 T3 基线为 `12/12 PASS`。

估算调用现有 `validate_sidecar_binding`、原件读回和遮挡掩膜函数，随后直接调用同一冻结 `measure_t3_trees(..., measurement_version="v3")`；没有重建完整 source gate，也没有新增测量工具。输入的语义像素、coverage、树实例、外环参考和几何变换均保持 TASK112 原值。对每个可见树屏幕像素，按 sidecar 中实际 Sprite2D 变换映回 Atlas texel，将 `(v3b RGB - 原 v3 RGB × R4 RGB 调制)` 乘原树贴图 alpha 与 sidecar 记录的 alpha 调制链，加到原 `main.png` 并按 8-bit 取整；再把临时画面数组传给冻结 T3 函数。模型映射到 `10547` 个有效可见树标签像素（alpha>127、排除对象遮挡，并按记录的 Sprite2D 与画布变换逆映射），`5623` 个屏幕像素的 RGB 经 8-bit 取整后有变化。alpha 按源 texel alpha 乘记录的 CanvasItem modulate/self_modulate 链计算；与 sidecar coverage 红通道对照，MAE 为 `0.00000186`，最大绝对差为 `1/255`。作为调制/量化残差提示，在 `props.png` 中对 `7891` 个原树 alpha `>=0.98` 的样本比较旧调制 RGB，MAE 为每通道 `0.611`，绝对误差 p95 为 `2.0`；这不是预测误差上界。

| 树实例 | 基线 ΔL* / ΔE00 | 预测 ΔL* / ΔE00 | 基线 / 预测 T3 |
| --- | ---: | ---: | --- |
| tree@0.00,0.00 | 14.110700 / 18.395611 | 13.762689 / 18.215900 | PASS / PASS |
| tree@0.00,1.00 | 11.364764 / 16.673797 | 10.660555 / 16.387830 | PASS / PASS |
| tree@0.00,8.00 | 14.254075 / 18.142068 | 12.990737 / 17.536853 | PASS / PASS |
| tree@0.00,9.00 | 13.107005 / 17.441085 | 12.192620 / 17.017139 | PASS / PASS |
| tree@1.00,0.00 | 12.342992 / 17.283969 | 11.334552 / 16.839771 | PASS / PASS |
| tree@1.00,9.00 | 12.573783 / 17.142721 | 11.840301 / 16.810673 | PASS / PASS |
| tree@8.00,0.00 | 24.960411 / 26.454595 | 24.954332 / 26.029607 | PASS / PASS |
| tree@8.00,9.00 | 13.535219 / 18.016257 | 12.547435 / 17.582975 | PASS / PASS |
| tree@9.00,0.00 | 9.606282 / 15.564741 | 8.756921 / 15.219127 | PASS / PASS |
| tree@9.00,1.00 | 18.964904 / 21.878622 | 18.964904 / 21.781595 | PASS / PASS |
| tree@9.00,8.00 | 16.905002 / 20.047449 | 15.651501 / 19.376536 | PASS / PASS |
| tree@9.00,9.00 | 15.381900 / 19.200941 | 14.232911 / 18.628355 | PASS / PASS |

同帧离线预测为 `12/12 PASS`。最紧行仍是 `tree@9.00,0.00`，预测 ΔL* `8.756921`、ΔE00 `15.219127`。该行距离阈值不大，色彩导入、纹理过滤和真实场景混合都没有由这次离线估算覆盖；最终验收值以 Dot 的 R5 实际采集为准。
