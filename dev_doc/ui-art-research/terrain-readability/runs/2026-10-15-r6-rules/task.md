# R6 规则实施：U1 与树方案 A

## 阶段成果

地形可读性 R6：规则经独立审查固定后，按修正明度制作暖调旧墙、鼓石残柱与接地；Dot 单组通过再进入六组定稿。树图冻结。

## 本 Task

用户明确采纳 U1 与树方案 A。新增版本入口实现组外边界周长的 T1/T6，以及树的 C9。旧 T1 v1、metrics、sidecar v1–v3、TASK115原件及生产素材不改。先用 TASK115 离线重新测量，以独立审查、明确范围提交和提交回读结束本 Task。不推送或建 PR。

## 验收

- U1：分母仅为实例属于组外轮廓的四邻接边；同组接缝不计；未知遮挡、排除边仍保留。半径与阈值不改。
- T6：原720p σ=2模糊，全局组环明度差>=10；采样几何覆盖仍适用。
- 树 T1/T6 只作诊断。门槛继续含T3和独立视觉审查；新增C9：Machado2009、严重度1.0红/绿色盲，部件7–9中位Lab与组外环中位Lab的ΔE00>=10，至少80%树在两模拟下均达标。
- C9 的空间与矩阵用一手来源固定，模拟只在测量内存中进行，不输出改写截图。NOT_TESTED不算通过。
- 正反单测：组内接缝、未知遮挡、80%覆盖分母、无组外边界、图边和细小掩膜、模拟空间/矩阵/中性灰、双模拟及80%树分母。
- TASK115原件离线结果、旧v3结果不变、全文件摘要和独立复算。

## 写入范围

- tests/claude_review/terrain_contour_v2.py
- tests/claude_review/terrain_cvd_machado.py
- tests/claude_review/validate_terrain_acceptance_v2.py
- tests/claude_review/test_terrain_acceptance_v2.py
- 本目录下的裁决、来源、基线、报告、测试、审查和回执。
