# Claude：R6-0 正式 T1 基线复核

[LANE=ui-ux]

请读取本目录 report.md、task115-t1-baseline.json、frozen-v3-comparison.json、independent-review.json，以及新入口 tests/claude_review/validate_terrain_contour_v1.py。

正式数据：树 1 PASS/11 FAIL，柱 3 FAIL；墙 7 NOT_TESTED（6 段覆盖不足80%，1段无2像素内核），相连墙组的整体诊断为数值 FAIL。旧 T3 12树仍全 PASS，已批准树图未改。

请确认：

1. 原 R6-0 要求下，全实例内环与完整周长分母、完整组外环全局中位数、逐实例半径4局部份额的衔接是否成立。T1 没有把组周长替换个体周长；T2/T3旧口径和结果未改。
2. 对墙段个体覆盖不足和已视觉冻结树的11项T1失败，提出有依据的分类阈值或分组覆盖方案供用户裁决。请明确哪些是阈值变更、哪些是测量单位变更，不单方面应用。
3. R6墙柱按既有风化旧石、鼓石残柱与接地要求继续。若你认为上述数据要求先改动既定R6素材目标，请指出具体依赖。

请追加结论到本 lane checkpoint 的 Claude Code 审查结论尾节。不要修改生产素材、旧校验器或阈值。
