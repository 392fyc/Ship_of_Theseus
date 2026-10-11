# 地形验收前置修复

## 阶段目标

先获得可靠的地形验收前置与旧素材负例，再处理树木、墙体与地板难以区分的问题。完成条件：新候选独立审查；Dot 云端 10×10/720p 前置通过，旧墙 T2 和完整旧树 T3 有数值完整的真实 FAIL；素材随后按 Claude 方向迭代，并由同一候选的六组原图验证。UI/P0 的其他未完成事项不扩展本 Task。

## 当前 Task 与开始依据

用户直接要求继续 SoT、先修地形验收前置、再处理材质。TASK85 已精确消费并关闭，原五项 FAIL 保留。基线为 `dc78a8c035da10e095f92f06fe7a9204e124ac02`。本 Task 修复采集和测量前置，包含新候选独立审查、签名投递、云端运行、精确原件消费与结果回执；采样修复不等于材质修复。

写入范围：

- `tests/claude_review/capture_terrain_readability_v6_regions_semantic_sidecar.gd`
- `tests/claude_review/validate_terrain_semantic_sidecar.py`
- `tests/claude_review/test_terrain_semantic_sidecar.py`
- `dev_doc/ui-art-research/terrain-readability/semantic-sidecar-task.md`
- 本运行目录的报告与审查记录。

## 修复与验收

1. RGBA8 覆盖标记容许正 alpha 量化为零，仍保持零浮点 alpha discard、R>127 样本门槛及错误标签拒收。
2. 保留 exact255 完全不透明锚点。树补充锚点由完整源清单和原生像素中心独立确定四边形归属、排除其他道具保守 bounds，核对精确 RGB 和相同 alpha。错配、未知标签替换、缺几何及无锚点都失败；不猜混色。
3. 地面阴影只排除地面外环；单位/HUD/高亮与网格仍排除物体有效像素。每类至少三实例、T1–T6 公式及阈值保留。
   冠层外树干的合法 unknown 按已绑定源分类图及实际 Sprite 几何逐像素核对后保持遮挡；冠内 unknown、类别错配和源投影缺失仍拒收。原 TASK85 离线诊断发现的 3806 个非冠层像素及其中遮挡冠层并集的 38 像素只用于缺陷定位，原批结论保持。
4. 正式取消选择清除范围子节点；单位和高亮父层仍可见，生产遮挡逻辑、初始镜头及所有素材保留。
5. Python 检查验证上述实际缺陷与拒收路径。Godot 导入、结构核对、原生试点、C4/C8 全部由 YC 云电脑完成，个人电脑不启动 Godot。
6. 试点前置失败停止后五组；前置通过而负例未成立可继续采集，但素材门关闭。只有真实旧墙 T2 和完整旧树 T3 FAIL 才进入素材 Task。六组定稿来自同一素材候选。

独立审查与用户视觉验收分开记录。不推送、不建 PR。不改生产代码、纹理、地图、玩法或 Mercury 通用文件。原始日志、PNG、环境元数据、逐文件 SHA256 与新签名绑定交付；仓外原件用 `<仓库外证据根>` 定位。
