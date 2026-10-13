# 树冠掩膜保留 AtlasTexture 采样坐标

## 目标

`tree_crown_union` 的 alpha 掩膜继续使用树原图的完整 atlas 尺寸，并经由与源 `AtlasTexture` 相同的 `region`、`margin` 和 `filter_clip` 采样。这样语义掩膜和可见树冠都从相同 atlas 坐标取样。校验记录同时给出完整 atlas 尺寸、`AtlasTexture.get_image()` 返回的区域尺寸和区域内非透明像素数。

## 已核实的背景

TASK96 的原图离线诊断发现一个差异像素：`tree_crown_union` 比源语义覆盖少 1 像素。差异投影到原 atlas 的 x 坐标约为 873.9995，邻接 atlas 像素 alpha 分别为 152 和 44，分类码均为树冠 7。TASK96 的正式结果保持原状，诊断报告也继续保留；本文件只说明新采集器的候选修正。

现有采集器先从完整树图取出 `AtlasTexture.region`，生成区域大小的 `ImageTexture`，再把它交给 `Sprite2D`。区域被切成独立纹理后，树冠掩膜的 UV/过滤采样路径不再与源树图相同。此处是基于现有采集代码与该像素坐标的解释；新采集器尚未经过 Godot 运行核实。

Godot 4.6 的 `AtlasTexture::get_image()` 源码先读取底层 atlas，再返回 `_get_region_rect()` 对应的裁剪图；`Image.blit_rect()` 按源矩形复制像素，要求源图与目标图格式相同。新实现让两图均为 RGBA8，并可分别验证全幅底图和区域读取结果。源码：[atlas_texture.cpp](https://github.com/godotengine/godot/blob/4.6/scene/resources/atlas_texture.cpp)；接口说明：[Image.blit_rect](https://docs.godotengine.org/en/stable/classes/class_image.html#class-image-method-blit-rect)。这些来源只证明 API 行为，不证明本项目新采集器已在运行时通过。

## 新采集器的处理

`capture_terrain_readability_v6_atlas.gd` 继承现有 v6 语义侧车采集器，不改动冻结脚本、测量器或素材。它先调用父方法得到已与源 alpha 和已审查树冠几何相交的区域掩膜，然后把区域掩膜按源 atlas 区域偏移写入同尺寸、其余透明的 RGBA8 图。新建的 `AtlasTexture` 使用该完整图作为底图，并逐项复制源树的 `region`、`margin` 与 `filter_clip`。

验证器保留父层级结构和材质检查，并额外核对源/掩膜完整 atlas 尺寸相等、三个 `AtlasTexture` 属性相同、`AtlasTexture.get_image()` 的尺寸等于源 region 尺寸，然后只统计该区域中的非透明像素。非树冠标记继续使用原采集器的区域纹理路径。

manifest 会明确记录本次运行入口 `capture_terrain_readability_v6_atlas.gd` 及从该入口到冻结 v6 基类的继承链。capture candidate 会绑定入口字段和继承链内各脚本的字节摘要；语义 sidecar 复制同一 candidate 与摘要。新采集器和本说明也会进入 manifest 的 source hashes 与 candidate digest。若任一文件缺失，候选记录会中止，避免结果漏记本次采集器版本。

## 离线核对与尚未证明的事项

仓库内的 Python 契约检查验证新脚本声明了完整 atlas 图、原 region 属性复制、区域 `get_image()` 校验与 source hash 绑定；小型像素 fixture 使用诊断坐标，核对 atlas x=873/874 转为 region-local x=587/588 时 alpha 值和全幅坐标保持一致。

此离线检查不能替代 Godot 运行。仍需云端运行新子脚本，并确认实际 `AtlasTexture.get_image()` 尺寸、区域 alpha 像素数、语义投影差异及 T3 测量结果。TASK96 已冻结文件和一像素差异均保留，不放宽阈值，也不删除样本。