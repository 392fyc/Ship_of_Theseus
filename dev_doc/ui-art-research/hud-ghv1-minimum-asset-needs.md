# GHV-1 HUD 最小素材需求

状态：Gate 3 候选，等待用户审核；尚未授权开始本批素材生成。

依据：

- 已批准方法：`dev_doc/ui-art-research/godot-hud-asset-layer-methodology-2026-09-02.md`
- 真实组件：`SkillSlotButton`、`ActionResourceStrip`
- 自动测试：技能槽 33 项、行动资源条 28 项、画廊 73 项
- 三档 Godot 实机证据：`dev_doc/ui-art-research/hud-ghv1-vertical-slice-evidence/`
- 结构视觉判定：93／100，只代表职责拆层通过，不代表正式材质通过

本表只收录已有明确 Godot 消费者的职责。Godot 的 `Theme` 可以为不同控件状态提供 StyleBox、颜色、字体和常量；`StyleBoxTexture` 是基于纹理的九宫格 StyleBox，边框可在不同尺寸下保留，且同一纹理可通过 `modulate_color` 形成状态差异。参考：[Godot GUI skinning](https://docs.godotengine.org/en/stable/tutorials/ui/gui_skinning.html)、[StyleBoxTexture](https://docs.godotengine.org/en/stable/classes/class_styleboxtexture.html)。

## 消费者清单与三向判定

| 可见职责 | 精确消费者 | 内容或状态是否变化 | 占位 Theme 是否足够达到正式质感 | 判定 | 当前理由 |
|---|---|---|---|---|---|
| 技能槽中性外壳与精细边角 | `scenes/tactical/hud/skill_slot_button.tscn::SkillSlotButton`；Theme 类型 `SkillSlotButton` 的 `normal`、`hover`、`pressed`、`disabled` | 槽位在 64×64 与 58×58 间变化；交互状态运行时变化 | 不足 | **需要图片** | 精细哥特金属或石质边角无法仅靠平色边框表达；一张无文字、无图标、无状态烘焙的中性外壳可被多种状态共用 |
| 行动资源条中性外壳 | `scenes/tactical/hud/action_resource_strip.tscn::ActionResourceStrip`；Theme 类型 `ActionResourceStrip/styles/panel` | 容量变化时外壳职责不变；未来布局宽度可能调整 | 不足 | **需要图片** | 当前平色外框只能证明结构，不能承担正式暗黑哥特材质；外壳必须与内部点、文字完全分离 |
| 技能槽 hover／pressed／disabled 色彩差异 | `SkillSlotButton` 的同名 Theme 状态 | 运行时变化 | 足够 | **继续由 Theme 表达** | 共用中性外壳图片，通过不同 `StyleBoxTexture.modulate_color`、边框或叠色表达，不为每个状态复制图片 |
| 键盘快捷键角标底板 | `%HotkeyBadge`；Theme 类型 `HudHotkeyBadge` | 快捷键文字变化 | 足够 | **继续由 Theme 表达** | 16×16 尺寸很小，清晰的 1 像素边框和底色优先；复杂纹理会挤压字符识别空间 |
| 快捷键、次数、移动数值字体 | `%HotkeyText`、`%ChargeText`、`%MovementValue` | 数值与按键持续变化 | 足够 | **继续由 Theme 表达** | 字符必须由 Label 和字体资源实时排版，禁止烘焙到图片 |
| 焦点轮廓 | `SkillSlotButton/styles/focus` | 键盘或手柄焦点运行时变化 | 足够 | **继续由 Theme 表达** | 焦点是可访问性反馈，需覆盖在普通、悬停、按下状态之上并保持可调 |
| 技能实际图标 | `%IconRect.texture` | 随技能内容变化 | 不适用 | **继续由运行时内容注入** | 它是技能内容素材，不是组件外壳；本阶段只保留接口，不生成或嵌入具体技能图标 |
| 技能选择态 | `%SelectedOverlay`；Theme 类型 `SkillSlotSelectedOverlay` | 运行时变化 | 不适用 | **继续由运行时图层表达** | 必须独立覆盖在任意技能图标和外壳之上，不能烘焙进中性底图 |
| 技能冷却态 | `%CooldownShade`、`%CooldownTurnsLabel`；Theme 类型 `HudCooldownShade`、`HudCooldownTurnsLabel` | 整数剩余回合数运行时变化 | 不适用 | **继续由运行时图层表达** | 回合制中直接显示居中整数；大于零时使用半透明近黑暗层压低亮度并保留图标辨识度，归零时两层隐藏，不使用比例色块或固定图片状态 |
| 技能次数 | `%ChargeText` | 数值运行时变化 | 不适用 | **继续由运行时图层表达** | 由 Label 绑定数值；图片只会产生错误的固定次数 |
| 移动足迹 | `%FootprintGlyph`；`HudActionResourceGlyph.Kind.FOOTPRINT` | 可用／不可用运行时变化 | 不适用 | **继续由运行时图层表达** | 第二轮 Godot 实机图已能以向上的单脚轮廓辨认；灰化只需共享颜色状态，不需要另做耗尽图片 |
| 标准行动圆点 | `%StandardPips` 动态子节点；`Kind.STANDARD` | 容量 1—3、剩余量运行时变化 | 不适用 | **继续由运行时图层表达** | 圆形简单且需要按容量动态创建；耗尽态保留原形并统一灰化 |
| 迅捷行动三角 | `%SwiftPips` 动态子节点；`Kind.SWIFT` | 容量 1—3、剩余量运行时变化 | 不适用 | **继续由运行时图层表达** | 三角简单且需要按容量动态创建；耗尽态保留原形并统一灰化 |
| 三个资源区的相对位置与间距 | `%MovementCluster`、`%StandardZone`、`%SwiftZone` 及其 Container 常量 | 随容器布局计算 | 足够 | **继续由 Theme／Container 表达** | 三区使用固定语义区域和留白，不引入装饰分隔柱图片 |

## 本 Gate 允许提交审核的图片需求

仅有两项，均为无文字、无图标、无运行时状态的中性表面：

1. 技能槽中性外壳表面：唯一消费者是 `SkillSlotButton` 的 Button 状态 StyleBox。
2. 行动资源条中性外壳表面：唯一消费者是 `ActionResourceStrip/styles/panel`。

两项都只是素材职责，不是已经冻结的文件名、像素边距或导入参数。候选接入方式为 `StyleBoxTexture`；是否采用九宫格、各边纹理边距和单项过滤方式，必须在素材实际生成后由 58×58、64×64 及 274×40 原生尺寸测试决定。不得据此设置项目级统一过滤规则。

## 明确拒绝进入图片批次

- `ACTIVE`、`PASSIVE`、`P` 或“可用”“已用”等类别／状态文字；
- 行动资源之间的装饰分隔柱；
- 耗尽斜杠；
- 5、6、7 技能各自独立的外框图片；
- normal、hover、pressed、disabled 各自一套重复外壳图片；
- 冷却剩余回合数字、选择框、快捷键字符、次数和移动数值；
- 画廊标题、板块说明和 476×108 诊断背景。画廊背景只服务验证，没有生产场景唯一消费者；
- 具体技能、武器、装备、遗物和职业资源图标。它们不属于 GHV-1 两个纵向切片。

## 下一 Gate

用户确认本表后，下一批只为上述两个中性表面各生成少量方向候选，并分别放入真实 `SkillSlotButton` 与 `ActionResourceStrip` 组件测试。不得直接生成整张 HUD，不得恢复已废止的旧原子素材批量计划；任何素材购买仍需用户在购买前单独确认。
