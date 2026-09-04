# GHV-2 角色栏最小素材需求

状态：Gate 3 候选，等待独立审查；本文件只确定图片职责，不代表已经生成或获得用户最终视觉批准。

依据：

- 显示合同：`dev_doc/ui-art-research/hud-ghv2-character-slice/display-contract.md`
- 真实组件：`CharacterHudPanel`、`HudValueMeter`
- 极值画廊与三档截图：`dev_doc/ui-art-research/hud-ghv2-character-slice/evidence/`
- 分层方法：`dev_doc/ui-art-research/godot-hud-asset-layer-methodology-2026-09-02.md`

## Gate 3 判定

| 可见职责 | 精确消费者 | 是否随内容或状态变化 | Theme 是否足够达到正式质感 | 判定 | 理由 |
|---|---|---|---|---|---|
| 角色栏中性外壳 | `CharacterHudPanel` 的 `styles/panel` | 外壳不随角色或数值变化 | 不足 | **需要图片候选** | 226×108 的主框需要与已通过的技能槽、行动资源条形成同一暗黑哥特像素材质；图片只承担边框与中性底面，不含字段或状态 |
| 头像框中性外壳 | `HudPortraitFrame` 的 `styles/panel` | 头像内容会变化，框本身不变 | 不足 | **需要图片候选** | 72×82 头像窗口是独立语义区域；正式金属或石质边角难以用当前单线平色框表达，唯一消费者明确 |
| 名称、等级、经验和数值文字 | `HudIdentityLabel`、`HudLevelLabel`、`HudMeterValueLabel` | 持续随运行时数据变化 | 足够 | **继续由 Theme 与 Label 表达** | 字体、描边、字号和截断必须实时排版；不得生成带字图片。后续字体选择属于字体资源，不属于图像生成批次 |
| 经验、HP、护盾轨道背景 | `HudExperienceMeter`、`HudHpMeter`、`HudShieldMeter` 的 `styles/background` | 比例不改变轨道，三者高度仅为 8 或 11 像素 | 足够 | **继续由 Theme 表达** | 尺寸很小，1 像素边线和纯暗底已经能稳定表达；复杂纹理会挤压文字并产生缩放噪点 |
| 经验、HP、护盾填充 | 三个 `ProgressBar` 的 `styles/fill` | 随数值逐帧变化 | 足够 | **继续由运行时控件表达** | 填充长度必须精确反映比例；颜色和可用性由 Theme 控制，禁止烘焙固定比例 |
| HP／护盾共同外框 | `HudSurvivalFrame` 的 `styles/panel` | 关系不变 | 足够 | **继续由 Theme 表达** | 120×28 内主要职责是说明两条数值同属生存属性；当前细边框已能表达，不新增第三张相近外壳 |
| 头像内容 | `PortraitTexture` | 随角色改变 | 不适用 | **作为独立内容接口保留** | 头像是角色内容素材，不是本批通用皮肤；本里程碑不生成具体人物头像 |
| 头像 fallback 字符 | `PortraitFallback` | 随显示数据改变 | 足够 | **继续由 Label 表达** | 仅在头像缺失时用于诊断或回退，必须由显式输入决定，不进入头像框图片 |

## 下一图片批次

只包含两项无文字、无头像、无数值、无填充、无交互状态的中性表面：

1. `character_panel_surface_v1`：目标消费者为 226×108 `CharacterHudPanel/styles/panel`。
2. `portrait_frame_surface_v1`：目标消费者为 72×82 `HudPortraitFrame/styles/panel`。

两项候选应先以当前 Codex 会话内置图像生成能力产出高分辨率材质方向，再由本地机械流程完成透明清理、目标尺寸派生、1 像素透明安全边和导入验证。不得调用外部 API key；不得购买素材。是否采用 NinePatch 由候选接入 226×108 与 72×82 后的边角、中心纹理和最小尺寸实测决定，不预先设置项目级过滤规则。

## 明确不进入本批

- 职业名、玩家名、等级、经验、HP、护盾数值；
- 任意固定比例的经验、HP、护盾图片；
- 角色头像、职业头像或人物原画；
- HP 与护盾各自独立的装饰框；
- 画廊标题、状态说明、诊断背景；
- 生产 `BottomDashboard` 的接线或新的玩法数据来源。

