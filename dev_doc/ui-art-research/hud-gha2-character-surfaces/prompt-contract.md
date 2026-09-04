# GHA-2 角色栏中性表面提示合同

状态：四个原始候选已生成；角色栏与头像框均选择 A，经机械清理后接入 Theme，等待三档证据、独立审查与用户视觉审核。本文只定义 `CharacterHudPanel` 和 `HudPortraitFrame` 的中性外壳。

## 共用生成模式与参考

- 生成模式：仅使用当前 Codex 会话的内置 `imagegen`，每个候选单独调用；不使用外部 API key，不购买素材。
- 主要同族参考：`assets/ui/skins/hud/skill_slot_surface_v1.png` 与 `assets/ui/skins/hud/action_resource_strip_surface_v1.png`。
- 材质方向参考：`dev_doc/ui-art-research/hud-r1-material-sample-v1/hud-r1-material-direction-v1.png`。
- 统一方向：略微精细的像素化暗黑哥特游戏界面；黑紫锻铁／深色石材主体，克制的磨损旧金细边，低装饰密度。
- 像素密度：适合 226×108 与 72×82 原生显示尺寸的细像素；避免粗大马赛克块和低分辨率八位机观感。
- 视角：孤立组件、正面平视、无透视、严格居中，无场景背景。
- 透明要求：组件外部和中心内容窗口必须是真实透明；最终机械派生必须保留 1 像素透明安全边。

## 统一禁止项

不得生成文字、数字、字母、职业名、玩家名、等级、经验值、HP、护盾值、头像、人物剪影、职业徽记、技能图标、武器、固定轨道、固定填充、资源点、发光状态、选中状态、场景背景、棋盘、投影画布或水印。

角色栏图片不得烘焙内部字段的相对位置、分隔栏、经验／HP／护盾轨道或头像内容；头像框图片不得烘焙头像、fallback 字符或职业标识。所有这些职责继续由现有运行时节点、显示数据和 Theme 表达。

## 角色栏中性外壳 A

- Use case: `stylized-concept`
- Asset type: isolated horizontal character HUD panel frame texture
- 目标尺寸：226×108。
- 唯一消费者：`hud_structure_prototype.tres::CharacterHudPanel/styles/panel`。
- Primary request: 单个宽横向角色栏中性外壳，保持 226:108 比例；四边闭合、长边平直、边框薄，中心为完整透明内容区，适合 NinePatch 接入。
- Input images: Image 1 和 Image 2 是已经接入的同族技能槽与行动资源条，只参考黑紫铁／石材、克制旧金细线和细像素密度；Image 3 只作为总体材质方向，不复制整张 HUD。
- Style/medium: 略微精细的像素化暗黑哥特锻铁与深色石材，少量自然磨损旧金角件。
- Composition/framing: 低装饰密度薄框；角部层次弱，中心窗口尽可能宽，不划分头像、名称或数值区域。
- Constraints: 外部与中心真实透明；无内容、无状态、无内部布局、无水印。
- Avoid: 粗大像素、厚重浮雕、尖刺、宝石焦点、中央徽记、复杂花纹、写实摄影、三维场景渲染。

## 角色栏中性外壳 B

与 A 具有相同目标尺寸、消费者、参考和禁止项。唯一方向差异是：在不增加内部布局的前提下略微强化四角与短边连接处的黑紫金属层次，旧金仍只作为克制细刻线；长边保持安静，透明内容区不得缩小到影响现有 226×108 组件。

## 头像框中性外壳 A

- Use case: `stylized-concept`
- Asset type: isolated portrait frame texture
- 目标尺寸：72×82。
- 唯一消费者：`hud_structure_prototype.tres::HudPortraitFrame/styles/panel`。
- Primary request: 单个略高于宽的角色头像框中性外壳，保持 72:82 比例；四边闭合、正面平视、中心为完整透明头像窗口。
- Input images: 使用与角色栏 A 相同的三项参考；必须与角色栏 A 的边宽、黑紫材质和旧金密度组成同一套组件。
- Style/medium: 略微精细的像素化暗黑哥特锻铁／石材薄框，低装饰密度。
- Composition/framing: 严格居中，四角对称或近似对称，透明头像窗口尽可能大；无底座、无铭牌。
- Constraints: 外部与头像窗口真实透明；无头像、无剪影、无 fallback 字符、无职业徽记、无状态、无水印。
- Avoid: 圆形框、厚重浮雕、尖刺、宝石、人物五官、亮色光晕、粗大像素、写实摄影、三维场景渲染。

## 头像框中性外壳 B

与 A 具有相同目标尺寸、消费者、参考和禁止项。唯一方向差异是：与角色栏 B 配对，略微强化四角和上下短边的金属层次，但边框不得挤压 72×82 内的透明头像窗口，不得出现徽记焦点或状态含义。

## 候选、清理与选择规则

- 四次首轮生成分别保存为：
  - `raw/character-panel-surface-a.png`
  - `raw/character-panel-surface-b.png`
  - `raw/portrait-frame-surface-a.png`
  - `raw/portrait-frame-surface-b.png`
- 后续每次图像编辑只修复一个明确的客观缺陷，并保留全部原始候选和内置生成运行标识。
- 本地机械清理只允许提取真实透明度、裁切透明外边、居中、派生目标尺寸和保留 1 像素安全边；不得新增、重绘或补充装饰。
- 最终候选分别保存到 `assets/ui/skins/hud/character_panel_surface_v1.png` 与 `assets/ui/skins/hud/portrait_frame_surface_v1.png`。
- 选择只比较职责纯度、同族一致性、原生尺寸可读性、透明窗口面积和 NinePatch 稳定性；不得因为候选带有更多内容而加分。
- Theme 接入与自动测试通过不等于最终视觉批准；两张候选仍须由用户审核。

## 本轮选择

- 角色栏选择 A：其边框更薄、透明内容区更大，226×108 下不会与名称、等级、经验、HP 或护盾争夺空间。B 的强化角部完整保留为对照，但不接入。
- 头像框选择 A：其边宽与角色栏 A 一致，72×82 下保留更大的透明头像窗口。B 的边中铆接与角部层次缩小后偏重，完整保留但不接入。
- 两个 A 候选均使用 `clean_neutral_checkerboard.gd` 机械提取透明度、裁切和目标尺寸派生；最终文件拥有完整 1 像素透明外缘，中心内容窗口为真实透明。
