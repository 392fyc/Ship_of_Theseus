# GHA-3 实用 HUD 专用原子素材提示合同

状态：六个原始候选已由内置 `imagegen` 生成；血瓶壳选择 A、菱形框选择 A、沙漏选择 B，经机械清理后已接入 Theme／场景，等待完整回归、独立审查与用户视觉审核。本文件只定义 32×32 血瓶按钮外壳、44×44 结束操作菱形框和 18×24 沙漏图形。

## 共用生成模式与参考

- 生成模式：仅使用当前 Codex 会话的内置 `imagegen`，每个候选单独调用；不使用外部 API key，不购买素材。
- 同族参考：`assets/ui/skins/hud/skill_slot_surface_v1.png`、`assets/ui/skins/hud/character_panel_surface_v1.png`。
- 布局参考：`dev_doc/ui-art-research/hud-ghv3-utility-slice/evidence/hud_utility_slice_1280x720.png`；只理解目标尺寸、层级与周围密度，不复制画廊文字或 mock 内容。
- 统一方向：略微精细的像素化暗黑哥特界面；黑紫锻铁／深色石材主体，克制旧金细边，低亮度、低装饰密度。
- 视角：单个孤立组件，正面平视，无透视，严格居中，无场景背景。
- 像素密度：以 32×32、44×44、18×24 的原生显示可读性为准；禁止粗大马赛克块，也禁止缩小后消失的微型噪点。
- 透明要求：组件外部必须真实透明；血瓶壳和菱形框的内部窗口也必须真实透明；最终机械派生保留完整 1px 透明安全边。

## 统一禁止项

不得生成文字、数字、字母、`END`、瓶子、液体、武器、防具、遗物、技能图标、职业徽记、次数、冷却、治疗量、发光状态、选中状态、棋盘、角色、场景背景、投影画布或水印。

不得把血瓶壳与血瓶内容图标合并，不得把菱形框与沙漏合并，不得生成整张结束按钮或整段 HUD。所有交互、tooltip、禁用、悬停、按下和结束语义继续由 Godot 运行时表达。

## 血瓶按钮外壳 A

- Use case: `stylized-concept`
- Asset type: isolated small square potion utility button shell
- 目标显示尺寸：32×32。
- 唯一消费者：`hud_structure_prototype.tres::HudPotionButton32/styles/*`。
- Primary request: 单个极简正方形按钮外壳，四边闭合，中心为尽可能大的透明内容窗口；在 32×32 下仍能看清细边和四角。
- Style/medium: 与同族中性槽一致的黑紫锻铁／石材薄边，只在四角加入非常克制的旧金像素刻点。
- Constraints: 外部和中心真实透明；无瓶子、液体、字样、状态或内容。
- Avoid: 厚框、宝石、圆形框、突出尖刺、复杂浮雕、粗大像素、写实三维渲染。

## 血瓶按钮外壳 B

与 A 的尺寸、消费者和禁止项相同。唯一方向差异是进一步减少四角装饰，以细锻铁双线和单层旧金刻线为主，作为更安静的小尺寸对照。

## 结束操作菱形框 A

- Use case: `stylized-concept`
- Asset type: isolated diamond-shaped end-action frame
- 目标显示尺寸：44×44；外层点击区为 52×52。
- 唯一消费者：`EndTurnButton/DiamondFrame`。
- Primary request: 单个中空菱形框，轮廓明显大于 18×24 沙漏但中心保持透明；缩至 44×44 后四个尖端完整，且不触碰 52×52 点击区边缘。
- Style/medium: 黑紫锻铁内层配克制旧金外缘，细像素、低浮雕、四向平衡。
- Constraints: 外部和中心真实透明；只有菱形框，无沙漏、文字、圆形底板、发光状态。
- Avoid: 实心徽章、厚重宝石、四尖接触画布边缘、粗大像素、复杂纹章。

## 结束操作菱形框 B

与 A 的尺寸、消费者和禁止项相同。唯一方向差异是减少旧金面积，以更细的暗色双层菱形和少量旧金磨损点表达，作为更安静的对照。

## 沙漏图形 A

- Use case: `stylized-concept`
- Asset type: isolated vertical hourglass emblem
- 目标显示尺寸：18×24。
- 唯一消费者：`EndTurnButton/HourglassEmblem`。
- Primary request: 单个竖直沙漏，顶部与底部横梁清楚，上下玻璃轮廓能在 18×24 下辨认，少量暖金沙粒作为视觉中心。
- Style/medium: 旧金金属轮廓、暗色玻璃和低亮度琥珀沙，略微精细像素风。
- Constraints: 外部真实透明；只有沙漏，不含菱形框、按钮底板、文字、光环或状态。
- Avoid: 钟表、计时数字、圆形表盘、写实玻璃、过细线条、粗大八位机像素。

## 沙漏图形 B

与 A 的尺寸、消费者和禁止项相同。唯一方向差异是使用更简洁、更宽一像素的轮廓，减少内部玻璃细节，优先保证 18×24 原生尺寸可读性。

## 候选、清理与选择规则

- 六次首轮生成分别保存到 `raw/` 下的 `potion-button-shell-a/b.png`、`end-action-diamond-frame-a/b.png`、`end-action-hourglass-emblem-a/b.png`。
- 每次编辑只修复一个明确客观缺陷；所有原始候选和内置生成运行标识均保留。
- 本地机械清理只允许真实透明提取、透明外边裁切、居中、目标尺寸派生和 1px 安全边，不新增或重绘装饰。
- 最终候选分别保存到 `assets/ui/skins/hud/potion_button_shell_v1.png`、`end_action_diamond_frame_v1.png`、`end_action_hourglass_emblem_v1.png`。
- 选择只比较职责纯度、同族一致性、原生尺寸可读性、透明窗口和边缘空隙；更多装饰不构成优势。
- 自动测试和 Theme 接入通过不等于用户最终视觉批准。

## 本轮选择

- 血瓶壳选择 A：32×32 下四边闭合且比 B 更清楚，中心内容区仍足够大；B 的边线缩小后过浅。
- 菱形框选择 A：44×44 下保持完整菱形轮廓和暗金层次，四尖未接触 52×52 点击区；B 的双细线在暗背景下偏弱。
- 沙漏选择 B：18×24 下顶部、底部、腰部和沙粒比 A 更容易在菱形内辨认；通过 `TextureRect.self_modulate` 做轻度统一提亮，没有修改素材内容。
- 三项最终文件均由现有清理脚本完成透明提取、裁切、居中、目标尺寸派生和 1px 透明安全边；没有新增或重绘装饰。
