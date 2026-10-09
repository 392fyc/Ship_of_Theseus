# T3 树体语义输入扩展

## 目标与范围

本任务为冻结 V6 采集入口增加独立的作者语义输入与摘要绑定审查读取。它只提供树暗侧及独立描边存在/缺席的来源记录，不执行 T3 数值测量，也不判定材质或美术验收。TERRAIN-READABILITY-01 与 Milestone 仍未完成。

新增入口 `tests/claude_review/capture_terrain_readability_v6_regions.gd` 继承 V6，保留冻结采集时序、画面、地图、相机、排除量化、阈值、C4/C8、图像角色和 V6 manifest schema。V6 及更早版本、生产代码、素材、地图与指标验证器均保持冻结。

## 输入与批准门槛

作者输入位于 `tests/claude_review/terrain_readability_tree_semantics.json`，schema 为 `terrain-readability-tree-semantics/1`。它绑定源纹理路径和 SHA-256、atlas 区域、局部像素坐标空间及冻结树冠注释路径和 SHA-256，并声明非空暗侧多边形、outline 多边形数组与 `outline_semantics.present/reason`。作者 `review_status` 必须维持 `pending_author_review`。

独立审查摘要位于 `tests/claude_review/terrain_readability_tree_semantics_review.json`，schema 为 `terrain-readability-tree-semantics-review/1`。读取时对文件原始字节计算 SHA-256，并从同一字节快照解析 JSON。仅当摘要 verdict 为 `PASS`，且 annotation、texture、base-crown 三项摘要分别匹配当前输入字节时才合并新区域。批准范围必须严格匹配声明：outline 缺席时为 `dark_side_geometry` 与 `outline_absence`；outline 存在时为 `dark_side_geometry` 与 `outline_geometry`。任何缺失、过期摘要、错误哈希、额外审批范围、无效几何或空暗侧都拒绝合并。

多边形须有至少三个不同顶点、非零面积、有限坐标且落在 atlas 局部边界内；自交几何拒绝。outline 声明为缺席时数组必须为空，随后只有显式 `outline_absence` 审查才可记录为 `absent_authoritatively`。outline 声明存在但无多边形时，outline 保持 `NOT_TESTED`；空数组本身不代表缺席。

## 掩膜与记录

新增暗侧掩膜使用继承的源纹理 alpha 路径，并在原 atlas 像素格上与冻结 crown 多边形掩膜求交，避免暗侧掩膜落在既有树冠之外。选择依据只使用作者几何、源 alpha 与已审查的语义输入，不从颜色或亮度阈值推断区域。

manifest 保留 V6 schema，并增加 `tree_semantic_input`，记录作者输入、独审摘要、源纹理和基础树冠的仓库相对路径、摘要、状态、批准范围、polygon 数量和暗侧交集规则。`candidate.source_sha256` 与 manifest `sources` 对每个存在的新增源码和输入文件分别记录 SHA-256。缺失文件在状态中明确标记，不会被写成批准证据。树部件当帧记录写明分类来源、审查摘要和交集规则；树接触阴影仍为 `NOT_TESTED`。

完整 T3、树冠对比数值和素材结论始终为 `NOT_RUN_BY_CAPTURE`。数值判定交给冻结指标流程；采集器不输出 T3 PASS。

## 检查边界与后续

`tests/claude_review/test_terrain_readability_tree_semantics.gd` 只运行无窗口语义正反例，覆盖真实作者输入、缺失输入、过期/错误摘要、错误批准范围、空暗侧、无效几何、outline 缺席与空 present outline，以及暗侧掩膜与 crown/source alpha 的像素级交集。测试内的 PASS 摘要是内存夹具，只验证绑定逻辑，不代替独立审查文件。

本任务不运行 GUI、原生像素采集或云端调用。独立代码审查通过后，像素六组、旧墙/树负例和完整 T3 数值仍需按既有流程单独完成；任何阶段都不得把结构测试或来源分类升级为图像验收或 Milestone 完成。
