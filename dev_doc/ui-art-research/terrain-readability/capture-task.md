# 同帧掩膜采集 Task

## 本项交付

在 `codex/ui-ux/terrain-mask-capture` 上，从 `787d294fdcac1375543fd517d7940b2d5b304c90` 实现测试侧采集入口、原件校验和分类标注。正式地形、素材、批准布局和玩法保持现行值。本项完成条件是采集实现通过独立源码审查，并在 Dot 的真实原图上证明同步视口与正式场景对齐；只有无窗口测试通过时，仍未完成。

写入范围：新增 `tests/claude_review/capture_terrain_readability*`、采集入口直属辅助文件、`terrain_readability_crown_regions.json`、`validate_terrain_readability_capture.py` 及其必要测试、本目录的采集说明和回执。不得改已有冻结采集器、测量阈值、生产代码或美术素材。

当前结果：源码独立审查通过，允许仅本地冻结候选；六组无窗口结构、七项回读测试与 C8 源码检查通过。Task 仍为 BLOCKED，缺少 Dot 真实图像校准。验证、独立审查原件引用与回执分别见 `capture-verification.json`、`capture-independent-review.json`、`capture-task-receipt.json`。

## 执行顺序

1. 完成并独立审查同帧采集器。一个 `frame_post_draw` 后读取所有视口图像与状态，中间不等待新帧。输出主场景与重建对照；本地仅执行无窗口代码检查。
2. Dot 在 10×10、25×25 的初始 fit 镜头下，分别采集 1280×720、1920×1080、2560×1440。每个组合各有树、墙、柱、碎石至少三个实例；数量和可测数量分开记录。
3. 本地取回原 PNG、完整日志、环境与逐文件摘要，核对来源、同帧对应、重建对照和掩膜；执行 C4/C8，再测现有素材的 T1–T6。首先确认现状墙顶 T2、树冠 T3 的失败能由真实数据检出。缺失掩膜导致的 NOT_TESTED 不能冒充负例校准成功。
4. 基线经独立审查后，才调整道具素材。保留原地面、接壤渐变、水深与 C7 要求，再执行同样六组合与独立原图审查。用户视觉验收单独记录。

## 分类依据

墙柱的顶面、侧面与接触阴影来自现行绘制部件及源码映射；不得按画面亮暗猜类别。树冠采用绑定原 PNG 与 Atlas 区域的测试侧几何标注，标注须经过原图叠加审查。空暗侧或轮廓数组不自动表示该项通过。

实例 ID 保留纹理 alpha、姿态、层级和相机变换。互相遮挡、单位、HUD 与网格必须计入有效掩膜；混色边缘不猜归属。过小、图边裁切或没有足够内核的实例按现行测量工具返回 NOT_TESTED，不放大镜头规避。

树冠的 `crown_geometry` 已通过独立原图叠加审查，批准只涵盖几何分类。暗侧、位图描边仍为 NOT_TESTED。完整 T3 沿用现有测量库状态；若已测对比条件 FAIL，则可单列这一必要条件的失败，不能把未提供的轮廓数组当作已核实的零轮廓。

## 固定用例与运行入口

测试用例 `calibration_courtyard` 由正式 `courtyard` 派生：仅将原图坐标 (8,7) 的 `pillar` 外观变体改为 `ruined`，保留地形类型、地表、相机与素材，使柱和碎石各达到三个实例。25×25 使用 x%10、y%10 重复原地形、铺地和派生变体；清单记录覆盖坐标及派生地图摘要。这是固定的校准用例，后续候选必须复用，不能改称原庭院原样。

```text
godot --headless --path <任务工作树> --script res://tests/claude_review/capture_terrain_readability.gd -- --headless-check --out=<仓外绝对目录> --map-sizes=10,25 --resolutions=1280x720,1920x1080,2560x1440
```

正式云端采集使用同一入口，去掉 `--headless` 和 `--headless-check`，显式使用 Compatibility；每个地图/分辨率组合可单独启动进程。回读命令为：

```text
python tests/claude_review/validate_terrain_readability_capture.py <六份capture-manifest.json> --source-root <冻结源码> --candidate <完整提交SHA> --out <仓外回读结果.json>
```

无窗口记录中，1920、2560 请求对应的 Window 纹理元数据分别为 2880×1620、5120×2880。无窗口模式没有真实渲染，不据此判断云端实际像素尺寸；正式采集与回读必须拒绝不匹配的原图，不能裁切或缩放成目标尺寸后冒充原生图。

## Dot 前置

2026-10-08 本次签名只读 STATUS（seq 31，request `9f248013-1204-414e-b7ec-a7628b68236a`）投递返回 `Some requested entity was not found: thread not found`。原生会话读取没有返回轮次；当前会话列表及归档没有该 YC。备用事件插件返回需重新认证。上述结果只确认当前路由不可用，不能证明原会话、原始文件或配对身份已丢失。

没有执行新的 Godot 云端任务、创建替代去重账本、换钥或把测试转到本机。原 seq 30 的账本与桌面前置记录保留；本次未能从 YC 核实它们的当前状态。路由恢复后先核对持续授权、协议和原子请求登记，再投递经过审查冻结的候选。

## 技术依据

Godot 的 [RenderingServer 文档](https://docs.godotengine.org/en/4.6/classes/class_renderingserver.html)说明 `frame_post_draw` 用于全部视口完成更新后的读取；headless 关闭渲染，因此本地无窗口检查不能证明图像正确。[SubViewport 文档](https://docs.godotengine.org/en/4.6/classes/class_subviewport.html)提供独立渲染目标；复制准确性仍由正式画面原像素对照判定。

本项不发布、不建 PR。TERRAIN-READABILITY-01、基础战斗 UI 及 P0/CR-01 Milestone 均保持未完成。
