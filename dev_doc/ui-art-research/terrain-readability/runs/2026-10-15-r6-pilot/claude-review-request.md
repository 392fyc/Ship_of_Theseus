# Claude 审查请求：R6 单组原图、测量内部接缝问题与残柱辨识

## 固定候选与审查入口

- 实现分支：codex/ui-ux/terrain-material-r6。提交：6ec8a9ffe1ce56005737d1036904d88d1c08a54a；Git tree：74fedd57ac90868f5ff2a921a57ccbfc6e73f3fa。
- 证据分支：codex/ui-ux/terrain-r6-evidence，基于同一候选；本目录为证据与诊断，生产文件没有修改。
- TASK117：request d3b69232-7c81-47d2-9c0c-6819b04388ea，task2926b2b8-69d1-4c1f-87d5-27f34a258391。原图只来自 calibration_courtyard 10×10、1280×720、Compatibility 的同一次采集。
- 先读 main-consumption.json、main-runtime-verification.json、result.original.json。完整595原件与17张PNG的精确索引见 full-original-map.original.json / original-readback-verification.json。固定原件Page：page_f09313a7cd488191be077e3a0bbff4e6。
- 全屏原图：captures/main.png；SHA256 67e6a6fb4de0ef016f9016f0178118b6feb1936c1c0f54c01758a86e3b9c6ce4。画面1280×720，查看时请保留原尺寸。
- 生成提示词、参考、素材SHA/尺寸/显示与过滤设置、加工步骤见相邻2026-10-15-r6-stone运行目录的既有清单；本次没有生成或加工素材。Penpot画板没有更新。

## 1. 先审测量问题 R6-MASK-INTERNAL-SEAM-01

本次冻结正式结果仍为 FAIL_U1_NUMERICAL_ACCEPTANCE，未改写。墙T1=1PASS/5FAIL/1NOT_TESTED，墙T6=6PASS/1NOT_TESTED；柱T1、T6各3FAIL。

但失败点叠图 analysis/diagnostic-perimeter-overlay.png 中，部分红线落在柱子鼓石横缝和墙体顶侧折线内部。internal-seam-proof.json 以两处原像素和实际 draw_leaf_inputs 证明：

- pillar@1,4 的(445,283)：props alpha=255；pair token1/part255；coverage R122。其像素中心被同实例alpha1的实际石面Polygon2D包含。
- wall@4,1 的(620,274)：props alpha=255；pair token21/part6；coverage R107。同样有同实例不透明底面。
- terrain_semantic_sidecar.gdshader 使用 blend_disabled，把R写成最后一次绘制的 source alpha；原alpha>0.5规则随后把这些线条像素当成实例外部。T1/T6因而将内部孔洞边计入外轮廓，并可把自身线色当作外环。

请求核对：保留现有 source-alpha 图与不确定性规则，另提供有同实例绘制顺序依据的合成占据掩膜，供U1外轮廓使用，是否准确执行已批准的“组外边界”？修复必须保留真正孔洞、其他实例/未知物遮挡与不可测边分母，不能直接降alpha阈值或无依据填洞。原TASK117输出全部冻结。请明确修复范围与所需负例。

## 2. 审柱子辨识与墙面风化

两名独立读者仅见三张720p原像素局部，未获知物体名称；完整可移植记录见 blind-reviews.portable.json，裁切来源见 blind-sample-provenance.json。两人都给中等确信，仍有石桩、墓碑或竖立石块等替代解释，故按原盲测门槛记FAIL。请看 analysis/sample-1.png 至 sample-3.png 与同帧全图，给出有边界的后续造型修改意见。

当前实际侧面L*约34.9–36.6，顶面约47.6–49.2；T2墙7/7与柱3/3通过。不要因为受内部接缝影响的T1/T6再整体提亮。部分顶面L*四分位距低于5，完整逐部件数据在material-analysis.json，请确认需修的具体实例/压顶纹理。

## 3. 审接地与地面控制

material-analysis.json中的T4沿实际采集的底部多边形量宽，使用渲染props的alpha排除物体像素；不是复写生产阴影公式。10个墙柱的诊断值：阴影暗8.18–9.54L*，宽1.91–4.29像素，均满足冻结contact_shadow函数；请求审查该取样方法和结果。T5地面控制图921600像素RGBA与TASK115完全相同，均值漂移0。

wall@8,7仍被树遮挡到只剩67个有效像素、没有2像素内核，正式NOT_TESTED保留；不得移除该实例或用调亮掩盖遮挡。

## 冻结项与下一步

用户已采纳U1和树方案A；树图/树着色、地面/接壤/水深/网格/镜头/占格/玩法、各数值阈值全部冻结。树T3=12/12PASS，C9=11/12PASS并保留tree@9,0单树失败，树T1/T6照常诊断。

请分别给出测量修复意见、墙柱视觉意见；原件交付独审与用户视觉批准分开记录。未满足单组门槛前不安排六组。此次不推送、不建PR。
