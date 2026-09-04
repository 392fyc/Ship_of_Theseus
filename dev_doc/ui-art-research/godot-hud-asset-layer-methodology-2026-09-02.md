# Godot HUD 素材制作与层级拆解方法

**状态：** GHM-1 现行方法，用户于 2026-09-02 审核通过  
**日期：** 2026-09-02  
**适用范围：** Ship of Theseus 战斗 HUD 的设计、素材生成、Godot 4.6 组件实现与验收  
**后续入口：** 先实现 `SkillSlotButton` 与 `ActionResourceStrip` 的 Godot 结构样机；通过纵向切片前不批量生成 HUD 素材

## 1. 短里程碑与完成条件

GHM-1 的阶段成果不是一批新素材，而是一套可以先用一个真实控件验证、再安全扩展到整套 HUD 的制作方法。

完成条件：

- 清除当前样板中无设计依据的 `ACTIVE`、`PASSIVE` 可见文字和行动资源装饰分隔柱；
- 以 Godot 4.6 官方能力和现有工程为依据，明确场景、控件、Theme、运行时绘制与图片素材各自的职责；
- 给出统一的拆分判据，避免整图导入，也避免把每个描边、底色和状态拆成独立图片；
- 给出从 Penpot 到 Godot 实机验收的逐关流程，并以 `SkillSlotButton`、`ActionResourceStrip` 验证该流程可执行；
- 旧原子素材规格与机器合同暂停执行，等本方法审核后再据此重写，不让两套规则并行生效。

## 2. 当前工程诊断

### 2.1 已经存在的正确基础

- 工程已使用 Godot 4.6，逻辑分辨率为 1280×720，拉伸模式为 `canvas_items`：`project.godot:20,29-31`。
- 战术场景已经把底部 HUD 作为独立界面分支接入，游戏状态由上层传入；高层职责方向可以保留。
- 已确认的布局与视觉裁决继续有效，例如底部安全边距、固定容纳 5—7 个技能、装备区内的小型血瓶按钮、行动资源语义、动态数值不得烘焙等。

### 2.2 需要纠正的实现形态

- `scenes/tactical/bottom_dashboard.tscn` 和 `skill_bar.tscn` 都只有一个带脚本的根 `Control`；实际节点树主要由 `scripts/ui/bottom_dashboard.gd:404` 和 `skill_bar.gd:263` 在运行时逐个 `new()` 创建。
- `bottom_dashboard.gd` 约 1363 行，并在同一脚本内定义 `ActionGlyph`、`HPShieldBar`、`XPBar`、`MarkBlock` 等绘制类；布局、材质、显示数据和交互职责没有形成可在编辑器中检查的边界。
- `skill_bar.gd:48` 把技能槽写成脚本内部类，`skill_bar.gd:79` 又以 `is_passive` 直接禁止输入。项目已经裁决“被动技能可能有主动效果”，因此 `passive` 与 `active_capable` 必须是两个独立行为字段，不能靠视觉类别推导交互能力。
- 大量实例级 `add_theme_*_override` 把同一种视觉规则分散在代码中。Godot 官方指出，当相同外观需要复用时，逐控件覆盖会很难管理，应使用 Theme 类型变体。

### 2.3 旧原子化方案的问题

旧方案选择“Theme 优先的混合方案”这个方向没有错，但过早固定了图片文件、尺寸、NinePatch 边距和组件数量，尚未用 Godot 中的一个完整交互控件证明这些边界。

具体风险：

- 一张 48×48 槽框九宫格被预定用于 64、56、52、44、32 等多档尺寸，却没有先验证边角在最小尺寸是否仍能容纳内容和保持材质比例；
- `passive`、`active_capable` 被放进运行时视觉覆盖状态，导致无设计依据的英文标签进入样板；
- Penpot 组件、PNG 文件和 Godot 场景被假定为一一对应，容易制造大量只有一层描边或底色的“伪原子”；
- 批量生产被安排在真实 Godot 控件试制之前，若边距、过滤方式或状态层次不成立，会整批返工。

因此，新的起点应是“真实控件纵向切片”，而不是“先列完整素材清单”。

## 3. 官方能力依据

| 设计问题 | Godot 4.6 能力 | 对本项目的含义 |
| --- | --- | --- |
| 界面布局 | `Control` 分为内容控件与布局控件；`Container` 接管子控件定位，并可嵌套形成响应式结构 | 用 `.tscn` 和 `Container` 声明结构，不在脚本中手算整个 HUD 的坐标 |
| 可复用皮肤 | 项目级 `Theme`、Theme 预览、Theme 类型变体 | 共用字体、间距、按钮状态和槽框由 Theme 管理，不复制实例覆盖 |
| 可拉伸材质边框 | `StyleBoxTexture` 与 `NinePatchRect` 使用 3×3 九宫格，仅拉伸或平铺中部和边缘 | 只有经过最小、最大尺寸试验的结构材质才输出 NinePatch |
| 按钮交互 | `Button` 自带图标以及常态、悬停、按下、禁用、焦点等 Theme 状态 | 技能槽和结束回合应继承标准按钮输入与焦点行为，不重写普通点击判断 |
| 动态数值条 | `TextureProgressBar` 具有底图、进度图、上层边框和九宫格拉伸 | HP、SH、XP 的框、填充和运行时数值可以分层，不需要生成固定数值图片 |
| 动态几何 | `_draw()` 与 `queue_redraw()` | 只用于资源点等真正随数据改变且现有控件难表达的轻量图形，不用于重建整套 HUD |
| 可复用游戏概念 | 场景是声明式节点组合，脚本补充行为；官方建议游戏特有概念用场景表示 | `SkillSlotButton` 等具备独立状态和交互的概念应是可实例化子场景 |
| 轻量配置 | `RefCounted` 和 `Resource` 比 Node 更轻，Resource 可序列化并在检查器中编辑 | 显示数据不必变成节点；皮肤配置可用 Resource，运行时视图数据可用有类型的轻量对象 |
| 图片导入 | 2D 默认适合无损压缩；过滤模式在 `CanvasItem` 上选择 | 保留透明 PNG，无损导入；过滤方式按素材类别和实机缩放结果决定 |
| 多分辨率 | `canvas_items` 支持高分辨率 2D；分数缩放会让纯像素边缘不均匀 | 不能把“全局 nearest”当成统一答案，必须在 1280×720、1920×1080、2560×1440 实机比较 |

官方资料：

- [Godot 4.6 UI 总览](https://docs.godotengine.org/en/4.6/tutorials/ui/)
- [Godot 4.6 Containers](https://docs.godotengine.org/en/4.6/tutorials/ui/gui_containers.html)
- [Godot 4.6 Theme 编辑器](https://docs.godotengine.org/en/4.6/tutorials/ui/gui_using_theme_editor.html)
- [Godot 4.6 Theme 类型变体](https://docs.godotengine.org/en/4.6/tutorials/ui/gui_theme_type_variations.html)
- [Godot 4.6 StyleBoxTexture](https://docs.godotengine.org/en/4.6/classes/class_styleboxtexture.html)
- [Godot 4.6 NinePatchRect](https://docs.godotengine.org/en/4.6/classes/class_ninepatchrect.html)
- [Godot 4.6 Button](https://docs.godotengine.org/en/4.6/classes/class_button.html)
- [Godot 4.6 TextureProgressBar](https://docs.godotengine.org/en/4.6/classes/class_textureprogressbar.html)
- [Godot 4.6 场景与脚本的选择](https://docs.godotengine.org/en/4.6/tutorials/best_practices/scenes_versus_scripts.html)
- [Godot 4.6 场景组织](https://docs.godotengine.org/en/4.6/tutorials/best_practices/scene_organization.html)
- [Godot 4.6 避免把所有数据都做成节点](https://docs.godotengine.org/en/4.6/tutorials/best_practices/node_alternatives.html)
- [Godot 4.6 图片导入](https://docs.godotengine.org/en/4.6/tutorials/assets_pipeline/importing_images.html)
- [Godot 4.6 多分辨率](https://docs.godotengine.org/en/4.6/tutorials/rendering/multiple_resolutions.html)
- [Godot 官方 Control Gallery](https://github.com/godotengine/godot-demo-projects/tree/master/gui/control_gallery)

### 3.1 实现路线比较

| 路线 | 视觉质量 | 动态状态与本地化 | 多尺寸 | 修改成本 | 结论 |
| --- | --- | --- | --- | --- | --- |
| 整块 HUD 位图 | 单张图容易统一 | 文字、数值、技能数量和状态难以独立变化 | 拉伸和不同纵横比容易破坏像素与边框 | 任一局部变化都要重出整图 | 禁止作为生产方案，只能作为概念参考图 |
| 每个描边、底色、角标都拆成小位图 | 可以复用少量纹理 | 状态可组合，但层数和素材数量迅速膨胀 | 每个最小尺寸都要维护边距与缩放规则 | “原子”过细会让 Penpot、清单和 Godot 同时复杂化 | 不采用图片原子数量驱动的方案 |
| 全部用脚本自绘并运行时创建节点 | 动态性高 | 数据接入方便 | 可以按坐标计算 | 美术难在编辑器中调整，代码同时承担布局、皮肤和行为 | 只保留给少量资源点等真正动态几何 |
| 只用 Theme／StyleBox，不使用专用图片 | 结构清晰、状态复用好 | 动态和本地化友好 | 容器与 Theme 易适配 | 难表现本项目需要的旧金、黑紫、细像素材质与专用徽记 | 作为结构样机和通用状态基础，不作为完整视觉方案 |
| 场景 + Theme + 选择性图片 + 运行时图层 | 能保留专用材质和统一状态系统 | 动态字段与图标可独立替换 | 容器、NinePatch 和分类过滤共同适配 | 需要先做纵向切片，但扩展后返工最少 | **本项目采用** |

选择最后一条路线不是要求每个概念都拆出四份文件，而是按职责选择最小充分实现。例如普通纯色描边只需要 Theme；需要旧金纹理的边框才增加一张 NinePatch；技能图标仍是单独内容图片；快捷键和冷却始终由运行时节点显示。

## 4. 现行分层方法

本项目采用“Godot 场景先行、Theme 驱动、素材按需生成”的混合方案。一个可见元素按职责落入以下四类之一。

| 类别 | 适合内容 | 生产形式 | 不应包含 |
| --- | --- | --- | --- |
| 内容图片 | 头像、技能图标、武器／防具／遗物／血瓶图标、专用徽记 | 单独透明 PNG 或 SVG；保持可替换 | 槽框、快捷键、冷却、次数、文字、数值、交互状态 |
| 皮肤图片 | 需要独特像素材质且纯 Theme 无法表现的面板边框、槽框、装饰纹理 | 通过实机尺寸验证后输出 NinePatch 或独立边框纹理 | 业务数据、按钮文字、固定填充值 |
| 引擎皮肤与布局 | 间距、内边距、底色、描边、字体、常态／悬停／按下／禁用／焦点 | `Theme`、Theme 类型变体、`StyleBoxFlat`、`Container` | 游戏规则和具体技能内容 |
| 运行时图层 | HP／SH／XP 填充、冷却剩余回合数、次数、快捷键、选择反馈、行动资源余量 | `TextureProgressBar`、`Label`、标准 `Control`；必要时小型自绘控件 | 烘焙数值、整套状态图片序列 |

“原子”的定义改为：**一个能够独立替换、独立美术指导、且有明确运行时消费者的视觉职责**。它不等于一张 PNG，也不等于一个 Godot 节点。

### 4.1 是否拆成独立子场景

满足以下任一条件时，优先拆成可实例化子场景：

1. 在两个及以上位置复用；
2. 自己拥有输入、焦点、状态切换或信号；
3. 有两个及以上需要独立验证的视觉状态；
4. 需要单独的截图测试或 Theme 预览；
5. 有独立的图片、Theme 或显示数据合同。

单纯用来对齐的一层 `MarginContainer`、`CenterContainer`、`Label` 或覆盖层不因“看起来像组件”而单独建场景，继续作为所属组件的子节点。这样既避免 1300 行脚本，也避免数十个无行为小场景。

### 4.2 建议的运行时层级

```text
BottomCombatHud.tscn
├─ CharacterHudPanel.tscn
├─ EquipmentHudPanel.tscn
│  └─ PotionButton.tscn
├─ SkillShelf.tscn
│  └─ SkillSlotButton.tscn × 5—7
├─ RelicGrid.tscn
│  └─ RelicSlotButton.tscn × 8
├─ ActionResourceStrip.tscn
└─ EndTurnButton.tscn
```

`ValueMeter.tscn` 只有在 XP、HP、SH 的结构和状态验证后确实共享时才抽取。`ActionPipGroup.tscn` 只有在标准行动和迅捷行动以外仍需复用或单独测试时才抽取；否则保留为 `ActionResourceStrip` 内部节点。

建议的 Theme 类型变体先控制在：`HudPanel`、`HudSlotButton`、`SkillSlotButton`、`RelicSlotButton`、`PotionButton`、`EndTurnButton`、`HudValueLabel`、`HudHotkeyLabel`。只有 7 技能实机试验确认必须改变皮肤而不只是尺寸时，才增加 `SkillSlotButtonCompact`。

### 4.3 产物职责与权威

| 产物 | 负责内容 | 不负责内容 | 形成时间 |
| --- | --- | --- | --- |
| Penpot 正式文件 | 玩家可见区域、外部几何、相对位置、视觉方向、代表性状态画板 | 最终节点树、脚本行为、图片导入参数 | Gate 1 |
| Godot `.tscn` | 语义节点树、Container、锚点、尺寸约束、焦点邻接、子场景实例 | 最终图标内容和战斗规则 | Gate 2 起 |
| Godot `Theme`／Theme 类型变体 | 通用字体、颜色、间距、StyleBox、标准交互状态 | 角色、技能、装备等具体内容 | Gate 2 起，Gate 5 定稿 |
| PNG／SVG | 内容图标、通过证明的材质边框、专用徽记 | 文字、数值、冷却、选择、快捷键、资源余量 | Gate 4 |
| 素材清单 | 来源、使用权、SHA256、逻辑尺寸、消费者、NinePatch 边距、过滤候选 | 决定组件层级 | Gate 3 裁决后创建 |
| 显示数据对象 | 当前名称、数值、图标引用、可用／耗尽／选中等显示状态 | 皮肤和布局 | Gate 0；引擎实现时有类型化 |
| 状态画廊／测试场景 | 空值、极值、5／6／7 技能、按钮全状态、三档分辨率与过滤对照 | 生产素材来源 | Gate 2 建立，后续持续扩展 |

发生冲突时，按职责回到唯一权威：位置问题改 Penpot 与 `.tscn` 的对应约束；状态皮肤改 Theme；具体图形改对应 PNG／SVG；数据含义改显示数据合同。不得为了绕开正确权威，在另一层叠加补偿偏移、覆盖图片或硬编码状态。

### 4.4 组件、场景与素材的关系

三者是多对多关系，不是文件名的一一映射：

- 一个 Penpot `SkillSlot` 可以对应一个 `SkillSlotButton.tscn`、一个 Theme 类型变体、零或一张槽框 NinePatch，以及任意技能内容图标；
- 一个共享槽框 NinePatch 可以被技能、装备、遗物三类 Theme 变体使用，但前提是各自最小尺寸实测通过；
- 一个 `CharacterHudPanel.tscn` 可以包含多个内部 Container 和 Label，却不需要为每个内部节点建立 Penpot 组件或图片；
- 一个整数剩余回合数 Label 与半透明近黑暗层可以服务全部技能槽；暗层压低亮度但保留图标辨识度，不为冷却状态生成图片或比例色块。

只有当映射通过 Gate 3 后，才把它写入素材清单。Gate 1 的图层命名不得提前变成批量生产任务。

## 5. 设计到引擎的工作流

### Gate 0：业务与显示数据合同

- 先列运行时字段、边界值和交互含义；
- `passive` 只描述技能类别，`active_capable` 只描述能否主动触发；
- 可激活条件由 `active_capable`、禁用、冷却等独立字段共同决定，不从被动类别推导；
- 不设计无业务来源的可见标签。

### Gate 1：职责布局

- 在 Penpot 中确认区域相对位置、可用尺寸、对齐、空状态和 5／6／7 技能数量；
- Penpot 组件按玩家能识别的职责命名，不追求与每个 Godot 节点或 PNG 一一对应；
- 此 Gate 不生成正式图片。

### Gate 2：Godot 结构样机

- 先用 `.tscn`、`Container`、占位 `StyleBoxFlat` 和标准控件完成一个纵向切片；
- 脚本只负责接收显示数据、切换状态和发出信号，不用脚本逐个创建静态节点树；
- 在 Theme 预览中检查常态、悬停、按下、禁用、焦点和极值状态。

### Gate 3：素材边界裁决

逐项询问：

1. 纯 Theme 能否在全部目标尺寸保持预期质感？能则不生成图片。
2. 该纹理是否在多个尺寸复用？是则做 NinePatch 候选，并先验证四边边距与最小尺寸。
3. 该内容是否会随角色、技能或装备改变？会则只能是独立内容图片。
4. 该画面是否随数值或交互状态改变？会则优先由运行时控件表达。
5. 移除该图片后，是否仍能明确说明它的唯一消费者？不能则说明拆分还不成熟。

只有通过以上判断的项目才进入正式素材清单。

### Gate 4：素材生产

- 先做同一控件的一套最小素材，不批量生产全 HUD；
- GPT-Image-2 通过当前 Codex 会话内置图像生成能力使用，不调用外部 API key；
- 图像生成负责材质与图形候选，本地机械流程负责透明、裁切、尺寸、NinePatch 边界、色彩和清单校验；
- 用户在购买任何素材前确认；已批准购买素材会成为后续本地生成链的风格锚点；
- 每个正式图片保存来源、使用权、尺寸、透明通道、SHA256、消费者和过滤候选。

### Gate 5：Godot 纵向切片验证

- 把最小素材接入一个真实子场景和项目 Theme；
- 运行 1280×720、1920×1080、2560×1440；
- 对同一素材类别比较 `nearest` 与 `linear`，不设置一条全局规则后跳过实机观察；
- 检查透明边、NinePatch 角部、文字基线、快捷键居中、鼠标与手柄焦点、5／6／7 技能、空值与极值。

过滤初始候选：

| 素材类别 | 首选候选 | 必须复核的情况 |
| --- | --- | --- |
| 原生尺寸绘制的硬边像素框与像素字形 | nearest | 1920×1080 的 1.5 倍缩放是否出现线宽不均 |
| 高分辨率生成后缩小的头像与内容图标 | linear | 是否失去关键像素轮廓 |
| 光效、柔边高亮、半透明遮罩 | linear | 是否产生糊边或色带 |
| NinePatch 材质 | nearest 与 linear 都测 | 平铺接缝、角部清晰度、中心纹理是否变形 |

### Gate 6：扩展与验收

- 纵向切片通过后，才把已证明的合同扩展到同族组件；
- 每一族先做功能／技术检查，再做独立视觉检查，最后由用户审核实机截图；
- 新发现的控件差异先回到 Gate 3，不靠新增无依据图片补洞。

## 6. 两个纵向切片示例

### 6.1 `SkillSlotButton`

建议节点职责：

```text
SkillSlotButton : Button
├─ IconRect : TextureRect
├─ CooldownShade : Control
├─ CooldownTurnsLabel : Label
├─ SelectedOverlay : Control
├─ HotkeyBadge : PanelContainer
│  └─ HotkeyText : Label
└─ ChargeText : Label
```

- `Button` 与 `SkillSlotButton` Theme 变体负责常态、悬停、按下、禁用、焦点和槽框；
- `IconRect` 只接收技能内容图标；
- 冷却剩余回合数字、次数、快捷键和选择均是运行时图层；
- `passive=true, active_capable=true` 仍可点击；样板不显示 `ACTIVE`／`PASSIVE` 英文标识；
- 5、6、7 个技能由 `SkillShelf` 的布局参数居中，不改变技能架外框尺寸；只有实机证明需要时才切换紧凑 Theme 变体。

### 6.2 `ActionResourceStrip`

建议节点职责：

```text
ActionResourceStrip : HBoxContainer
├─ MovementCluster : HBoxContainer
│  ├─ FootprintIcon : TextureRect
│  └─ MovementValue : Label
├─ StandardActionGroup : CenterContainer
└─ SwiftActionGroup : CenterContainer
```

- 三个语义区只用固定空白和自身形状分组，不使用装饰竖柱；
- 标准行动是绿色圆点，迅捷行动是橘黄色三角，实际拥有 1—3 个就创建并居中显示 1—3 个；不显示未解锁空位；
- 已消耗点使用同形灰化或空心状态，不能仅依靠颜色时增加明度／填充差异；
- 移动力由向上的足迹图标和可移动格数表示，结束移动阶段后整体灰化，不加斜杠；
- 若资源点仅为少量简单几何，可由一个轻量自绘子控件生成；若最终材质要求专用图形，再输出共享点形图片。是否拆成 `ActionPipGroup.tscn` 由纵向切片后的复用和测试需要决定。

## 7. 现行结论与待审核项

### 已固定

- 当前 Penpot 样板中的 `ACTIVE`、`PASSIVE` 可见文字和行动资源装饰分隔柱已移除；
- 不整图生成 HUD，不烘焙文字、数值、快捷键、冷却或资源余量；
- 内容图标、皮肤图片、引擎 Theme／布局和运行时图层分开；
- 批量素材生产必须晚于一个真实 Godot 纵向切片；
- 运行时结构以声明式 `.tscn` 为主，脚本负责行为和数据绑定；
- 素材购买仍需用户事前确认。

### 重新开放，不能沿用旧合同直接执行

- 每个 PNG 的精确清单、尺寸与 NinePatch 边距；
- Penpot 组件、Godot 子场景与图片文件之间的映射；
- 32—64 像素槽位是否共用一张九宫格；
- `nearest` 或 `linear` 的最终分类规则；
- `SkillSlotButtonCompact`、`ValueMeter`、`ActionPipGroup` 是否值得成为独立组件。

### 审核通过后的下一步

本方法已经通过。下一 Milestone 只实现两个结构样机：`SkillSlotButton` 与 `ActionResourceStrip`。先用占位 Theme 和现有临时图形验证节点层级、交互、数据状态与三档分辨率；通过后再生成对应的最小皮肤素材。不会立即重做整个底部 HUD。

## 8. 清理证据

- `dev_doc/ui-art-research/penpot-hud-r1-method-reset/01_skill_count_5_cleaned.png`
- `dev_doc/ui-art-research/penpot-hud-r1-method-reset/02_resource_states_cleaned.png`

两张导出图分别验证技能样板不再显示 `ACTIVE`／`PASSIVE`，以及行动资源三个语义区不再使用装饰分隔柱，同时保留快捷键、冷却剩余回合数、资源数量和居中关系。
