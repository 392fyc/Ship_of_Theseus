# 柱体 R9 像素补验

## 范围与产物

R9 继承冻结的 R7 静态采集和 V3 验收算法，保留既有静态采集结构；本轮只运行 10×10、1280×720 单组。该组的 19 张 PNG 清单、sidecar 绑定和 T1–T6 阈值不变。新增的凹槽与遮挡结果只写入独立补验字段和文件，不并入 T1–T6 图像。

R9 入口在 `tests/claude_review/capture_terrain_readability_r9.gd`。它先完成 R7 静态采集，再于 command 3 的同一采集进程生成 O1。每个正式案例目录另存 `r9-o1-A.png`、`r9-o1-B.png`、`r9-o1-C.png`、`r9-o1-D.png` 和 `r9-o1.json`，共 5 件补充原件；它们不进入原 19 张静态 PNG 清单。补验报告由 `tests/claude_review/validate_terrain_pillar_r9.py` 生成，旧 V3 根结构与结果同时保留。命令行退出码只反映采集前置条件，领域 FAIL/NOT_TESTED 留在 JSON 中，使 runner 能继续执行后续 T4 命令。

## G1：实际凹槽像素

1. 对 sidecar 列出的三根柱子逐根处理，从每根的 `draw_leaf_inputs` 找到 `R9Groove1` 至 `R9Groove4`。`r9_groove_index` 与 `r9_groove_u` 只用于识别槽位及第三槽，不据此颜色或源码值判定通过。
2. 将 Line2D 局部点按其 `global_transform`、main viewport 的 `canvas_transform` 和 `final_transform` 变换到原生 main 像素。每个实际像素行取中心线最近像素；以同一行左右各 1、2 像素的四个实际柱面像素中位数为参照。
3. 直接从原始 main PNG 读取中心与柱面像素，转成 CIELAB L*。对每行计算“柱面中位数减槽中心”的差，再取各有效行中位数。中心及四个侧样本都必须属于该柱的有效不透明 occupancy token；其他槽的真实 Line2D 光栅命中、外来遮挡、空/非柱像素及图像边界逐项计为排除原因。缺少槽输入、同帧或候选绑定时为 NOT_TESTED。
4. 外侧三槽分别要求差值 6–8 L*；`u≈0.62` 的第三槽单独要求至少 4 L*。报告每槽数值、有效行数、排除数和实际变换线宽。真实石纹照常参与像素中位数，不因纹理存在而排除；旁侧纹理 IQR 只作诊断。另以 `semantic_pair` 的 `pillar_side` 部件、coverage alpha>127 和同 token occupancy，从 main 原图测柱侧 L* IQR，单独报告是否达到 5，不改变 V3 T2。

## O1：四状态同帧遮挡测量

四个独立 viewport 在一次 `RenderingServer.frame_post_draw` 后同步读回：A 为原正式场景的柱与单位，B 为原重建 session 中隐藏最高柱但保留单位，C 为正式克隆场景保留柱并隐藏单位，D 为正式克隆场景隐藏柱与单位。四个状态共用设置后的单位格 `(0,3)`、悬停格 `(0,3)`、相同分辨率、窗口尺寸和相机变换；JSON 记录真实与请求格、frame id、读回前后 draw/process 计数、viewport、变换、图像 SHA256 与实际 alpha。实际 alpha 由既有 `_update_board_visibility_context` 与 `CourtyardBoardView._process` 产生，不直接设值。

单位本体范围取真实 `Unit.get_overhead_body_rect_screen()`。在 A–C 中逐像素对比有单位和隐藏单位画面，在 B–D 中用同样方法得到无柱分母。RGB 任一通道差大于 2，或 alpha 差大于 1，计为单位贡献像素；A–C 与 B–D 的贡献数之比至少 60% 才通过。空分母、帧/窗口/尺寸/变换不一致、缺少原图或真实位置不符时为 NOT_TESTED。

名称 Label、HP Label、正式 DamageForecaster 与单位头顶真实预测数字都记录实际节点、文字、原生像素矩形和 CanvasLayer。预测值由 TacticalManager 的正式攻击预览路径产生，并与头顶 Label 文本核对。若文字矩形与最高柱不透明 occupancy 有交集，当前没有实际文字像素对照，因此该文字项为 NOT_TESTED；更高 CanvasLayer 或按字体宽度得到的 `text_complete` 不足以证明像素可读。矩形无交集时保留现有验收路径。缺任一节点或读回时为 NOT_TESTED。

## 离线检查和边界

使用带 NumPy 与 Pillow 的 Python 运行 `python -B tests/claude_review/test_terrain_pillar_r9.py` 做纯 Python 合成图像检查，覆盖凹槽阈值、第三槽、其他槽混淆、缺输入、正常纹理像素、O1 60% 边界、帧/变换拒绝、缺失 O1 证据、领域 G1 失败仍以采集前置 rc=0 结束，以及采集前置失败返回非零。该检查不启动 Godot，也不证明候选运行时采集成功；实际游戏画面、O1 四图和生产遮挡 alpha 仍须由 command 3 生成并交独立审查。

R9 T6 余量另报每根柱子的 V3 `median_delta_l`，以及相对旧阈值 10、R9 目标 10.5 的数值距离；有限数值在 V3 状态为 PASS 或 FAIL 时都按至少 10.5 的目标单独判定，并保留 V3 原状态和值。只有数值缺失、非有限或 V3 T6 为 NOT_TESTED 时，R9 余量才为 NOT_TESTED。冻结 V3 的 T6 状态与 10 阈值保持原样。所有补验 FAIL 与 NOT_TESTED 都保留具体状态和原因，不自动转成通过。
