# 本轮离线分析步骤

输入只使用TASK117的原始PNG、capture-manifest、semantic-sidecar-manifest，以及TASK115同场景地面控制图。原件逐文件SHA256见original-readback-verification.json；没有重新运行游戏。

1. 冻结validate_terrain_semantic_sidecar.py的v3模式、validate_terrain_acceptance_v2.py、C4/C8在1487份精确来源上离线重算。实际命令和原来源在main-runtime-verification.json。浮点末位容差1e-12，最大观察差2.1316282072803006e-14，状态与非浮点字段一致。
2. analysis/local-edge-diagnostic.csv逐边复现正式U1的weights/inner/outer和半径4局部中位数；边数与正式逐实例行一致。analysis/diagnostic-perimeter-overlay.png只作分析：绿=局部差≥10，红=已测但不足10，黄=不可测且保留分母。它不作为原图或新验收掩膜。
3. internal-seam-proof.json使用两处原始像素、记录的Polygon2D多边形与变换，验证像素中心确在同实例不透明面内；材质PNG最小alpha255，primitive/modulate/self_modulate/祖先modulate的alpha乘积为1。它说明最上层半透明线的coverage不能直接代表整个实例的不透明占据，不修改正式状态。
4. material-analysis.json的T4仅在原contact_shadow有效且原渲染props alpha≤0.5的可见地面像素测量，扣除网格和界面。使用实际捕获的柱脚六边形及wall_side底部两顶点作线段，按最近底部线段分配样本，量最远样本至底部的距离；不复写生产阴影几何。阴影差与半格判据调用冻结contact_shadow。最初基于语义可见像素的试算在发现内部接缝洞后退出当前结论；当前样本以渲染props alpha排除物体，供Claude独立复核。
5. T5比较与TASK115完全相同的ground_types掩膜，ground_without_shadow的921600个像素RGBA逐字节相同；冻结ground_stability返回均值漂移0。
6. 柱子盲看覆盖全部三根：按原语义token/coverage包围盒外扩24像素，从同帧main.png原尺寸裁切，不缩放、不滤色、不加名称。两位读者未收到预期物体类别；结果见blind-reviews.portable.json。原文字节保存在仓库外证据根，版本化抄录仅把file字段规范为basename，措辞不变。

原PNG、冻结规则、阈值与候选生产源码均未改写。修复内部接缝问题须先获得独立审查意见，再固定新版本与来源；TASK117结果保持冻结。
