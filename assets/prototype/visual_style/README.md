# 视觉素材统一质感 Playground

该目录用于原型阶段的素材一致性检查，不作为正式生产入库。清单驱动五类样本槽：`ui`、`portrait`、`map_token`、`terrain`、`vfx`，顺序固定不变。素材文件不在此目录内导入；`source_path` 暂时留空表示待提供。

## 样本规则（五类）

- `ui`
  - 风格：略微精细、深色哥特像素化插画。
  - 必须支持 `bottom_action_bar`、`tooltip`，并预留 `NinePatch` 兼容。
  - 禁止烘焙文字，透明层保留，`nearest` 采样。
  - 与其他类型共用三档检查尺寸 `1280×720 / 1920×1080 / 2560×1440`。

- `portrait`
  - 第三版统一质感参考。
  - 变体必须恰含 `single_weapon`、`dual_weapon`。
  - 真实握持语义，允许剑形；透明；`nearest` 采样。

- `map_token`
  - 变体必须恰含 `single_weapon`、`dual_weapon`。
  - 方向必须声明 `NW`、`NE`、`SW`、`SE`。
  - `source_size` 与 `frame` 为 `48×48`，透明；`nearest` 采样。
  - 静态待机，不含战斗动画。

- `terrain`
  - `tile_size` 为 `64×32`，比例 `2:1`。
  - 变体至少有 `base_ground`、`transparent_overlay`，支持地表与覆盖物分离。
  - 透明；`nearest` 采样。

- `vfx`
  - 变体必须恰含 `slash`、`movement`、`range`、`status`。
  - 采用静态关键帧或参考板，像素核心用 `nearest`，柔和光晕若出现需独立。
  - 不含完整循环、粒子系统或战斗动画。

## 清单准入与三道门

`sample_manifest.json` 中，每个样本都必须同时满足三道门后才可被标记为可用：

1. `approval_status`：`approved`，表示文件本身已通过用户确认；否则是待确认状态。
2. `provenance_status`：`verified`，表示来源可追溯与可核验；否则是来源未核验。
3. `rights_status`：`verified`，表示使用权依据可核验；`review_required` 和 `unverified` 都不允许加载。

此外还要求 `source_path` 为仓库内 `res://` 合法路径、资源类型为 `Texture2D` 且与清单尺寸匹配。清单里仍允许保留空槽显示为待提供，但会显示“待提供、待用户确认、来源未核验、使用权依据未核验”。

## 说明边界

- `sample_manifest.json` 的字段与运行时状态用于原型审查，并不等于生产交付标准。
- `review_required` 不可直接加载，必须完成复核后改为 `verified`。
- 原型出现 `Codex` 生成结果并不代表已通过使用权核验；使用前仍需完成来源与许可依据确认。
- 生成的临时图像仅写入运行态临时目录，不进入仓库。
