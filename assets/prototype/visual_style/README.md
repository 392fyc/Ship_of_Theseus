# 视觉素材统一质感 Playground

该目录用于原型阶段的素材一致性检查，不作为正式生产入库。清单驱动五类样本槽：`ui`、`portrait`、`map_token`、`terrain`、`vfx`，顺序固定不变。五个经用户逐文件批准的精确 PNG 原文件已经进入 `samples/`；每个 `source_path` 都指向对应仓内文件，`source_size` 记录原文件尺寸，`display_size` 仅用于检查窗口，不等同生产规格。

`approved_preview` 保存用户实际审查文件的文件名、SHA256 和像素尺寸。仓内 PNG 的实际字节必须与该 SHA256 完全一致；若字节发生变化，该文件不再属于这次精确批准。裁切、重编码、透明清理或其他衍生文件都必须重新取得视觉确认，或建立明确且能绑定衍生文件身份的审批记录。

运行方向：`F` 切换纹理过滤方式、`R` 切换检查画布尺寸、`P` 截图。内部承载检查 UI 的是 `SubViewport`，截图直接来自当前检查画布，不会直接写回仓库；文件只写入 `user://visual_style_playground/`，文件名包含毫秒时间戳与递增序号，连续截图不覆盖。

## 样本规则（五类）

- `ui`
  - 风格：略微精细、深色哥特像素化插画。
  - 底部操作栏固定在底部，从左到右依次是角色区、职业资源区、技能栏、遗物栏和结束回合区。
  - 角色区保留占位容器；职业资源区默认为空，后续按职业特性定制样式和内容。
  - 技能栏水平平铺 5 个技能：4 个等大的主动技能和 1 个相对更小的被动技能；不设独立普通攻击或移动按钮。
  - 遗物栏位于技能栏右侧，共 8 格，按 2 行×4 列排列。
  - 不设常驻顶部提示面板；这不禁止运行时在鼠标悬停等交互中显示临时提示。
  - 必须支持 `bottom_action_bar`、`panel` 和按钮三态，并预留 `NinePatch` 兼容。
  - 禁止烘焙文字，透明层保留，`nearest` 采样。
  - 与其他类型共用三档检查尺寸 `1280×720 / 1920×1080 / 2560×1440`。

- `portrait`
  - 第三版统一质感参考。
  - 变体必须恰含 `single_weapon`、`dual_weapon`。
  - 真实握持语义，允许剑形；透明；`nearest` 采样。

- `map_token`
  - 变体必须恰含 `single_weapon`、`dual_weapon`。
  - 方向必须声明 `NW`、`NE`、`SW`、`SE`。
  - 当前准入文件是 `1536×1024` 的方向/单双武器代表板，Playground 按 `140×93` 等比例显示；它不是一张 `48×48` 战棋帧，也不满足真实 48×48 可读性验收。
  - 类型级 `frame_size` 仍冻结为 `48×48`，作为 Task 4 的独立产出与验收目标；透明；`nearest` 采样。
  - 静态待机，不含战斗动画。

- `terrain`
  - `tile_size` 为 `64×32`，比例 `2:1`。
  - 变体至少有 `base_ground`、`transparent_overlay`，支持地表与覆盖物分离。
  - 透明；`nearest` 采样。
  - 支持无缝衔接。

- `vfx`
  - 变体必须恰含 `slash`、`movement`、`range`、`status`。
  - 采用静态关键帧或参考板，像素核心用 `nearest`，柔和光晕若出现需独立。
  - 不含完整循环、粒子系统或战斗动画。

## 清单准入与三道门

`sample_manifest.json` 中，每个样本都必须同时满足三道门后才可被标记为可用：

1. `approval_status`：`approved`，表示文件本身已通过用户确认；否则是待确认状态。
2. `provenance_status`：`verified`，表示来源可追溯与可核验；否则是来源未核验。
3. `rights_status`：`verified`，表示使用权依据可核验；`review_required` 与 `unverified` 都不允许加载。

此外还要求 `source_path` 为仓库内 `res://` 合法路径、资源类型为 `Texture2D` 且与清单尺寸匹配。`source_path` 为空时，`status_text` 会显示“待提供”，并按实时门控结果追加待确认、来源未核验或使用权复核等提示。`provenance_status` 为 `verified` 时 `provenance` 必须有非空说明；`rights_status` 为 `verified` 时 `rights_basis` 必须有非空说明；`review_required` 只计入“使用权需要复核”。空槽请使用空字符串，不要用 `pending` 充当依据。

`approved_preview` 用文件名、SHA256 和像素尺寸绑定用户已审查的仓外原文件；`source_path` 指向它在本原型目录中的逐字节副本。两者必须通过 SHA256 保持同一身份，不能用清单中的批准状态替代实际字节核验。当前五个文件的来源、使用权和用户批准均已核验，Playground 仍会独立检查路径、资源类型与实际尺寸。

## 说明边界

- `sample_manifest.json` 的字段与运行时状态用于原型审查，并不等于生产交付标准。
- `review_required` 不可直接加载，必须完成复核后改为 `verified`。
- 当前五个精确 PNG 的使用权依据是 KB `04-Assets/visual-style-decisions.md@f111e2377c162b83cf29e46ccba3744231029651` 第 45 行记录的 2026-08-27 用户授权，该依据只覆盖 `approved_preview.sha256` 绑定的原文件；清单以 `@f111e237:L45` 作为同一依据的紧凑显示引用。
- 原型准入不等于正式生产准入；衍生文件和后续购买素材仍分别执行视觉、来源与使用权确认。
