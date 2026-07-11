# 剑圣 底部信息操作栏 设计规格 v3

> 配对视觉稿：`skillbar-mockup.html`（同目录，浏览器打开看 L→R 五区排版 + 区域框质感 + 剑气空格边 + 伤害预测器两态）
> 范围：仅 UI 设计稿。**不改任何 `.gd` / `.tscn` / 游戏 JSON**，实现在用户审阅通过后另做。
> 数据契约硬约束（公开 API 红线，重设计只重写视觉构建、不动签名）：
> - `BottomDashboard`：`class_name BottomDashboard`；信号 `attack_requested` / `skill_toggle_requested` / `skill_selected(skill_id)` / `end_turn_requested` / `end_move_requested` / `cancel_requested`；方法 `update_state(state)`。
> - `SkillBar`：`class_name SkillBar`；信号 `skill_selected(skill_id)`；方法 `update_entries(entries, selected_skill_id)` / `set_expanded(expanded)`。
> - 冷却 / 置灰 / 资源条 / 伤害预测 均从 `update_state` 的 `state` 字典读取，不新增对外签名。

---

## 0. v3 相对 v2 的改动总览

| 项 | v2 | v3（本稿） |
|----|----|-----------|
| 整体布局 | 单底板四段：资源 → 被动 → 主动 → 操作（道具+结束）| **L→R 五区硬布局：① 个人信息 → ② 资源栏 → ③ 技能栏（居中）→ ④ 物品 2×3 → ⑤ 结束** |
| 资源栏位置 | 夹在被动槽左侧，紧凑 | **独立成区，位于个人信息与技能栏之间，加宽更舒展** |
| 物品栏 | 6 格横铺，56px（DOTA 背包式 1 行）| **2 行 × 3 列 = 6 格，格 38px（比被动 48 更小，DOTA 式）** |
| 比例 | 物品区占比偏大 | **物品图标 / 物品区宽度缩小，省下宽度给资源栏** |
| 区域分隔 | 细金竖线 + 粗竖线 | **每区一块「暗黑哥特边框面板」（Diablo IV 式金属/石质双色描边 + 噪点 + 角饰）** |
| 剑气空格 | 空格无边、只靠槽底 | **空格始终绘制可见细边框（任意充能量都能数出 10 段）** |
| 剑气宽度 | 170px | **182px（加宽）** |
| 印记方块 | 18px | **24px（满态 28 高，加大）** |
| 伤害预测 | 仅命中%/暴击%/单次伤害（forecast 面板）| **新增伤害预测器：伤害类型徽标 + 数值，多段 x × y（总值），保留命中/暴击%** |

---

## 1. 定位与总体排版（L→R 五区，硬布局）

固定在屏幕底部的横向信息操作栏。**从左到右五区，顺序硬性固定**：

```
┌─────────┐┌──────────┐┌──────────────────────┐┌─────────┐┌──────┐
│① 个人信息 ││② 资源栏    ││③ 技能栏（居中）          ││④ 物品2×3 ││⑤ 结束 │
│ 头像/名/  ││ 剑气条     ││ 1斩击 2一闪 3招架↔拔刀  ││ 6格38px  ││ 回合  │
│ 等级/HP/  ││ + 印记     ││ 4居合 ┊ 被动·心眼(小)   ││（缩小）  ││（红）  │
│ 属性      ││（加宽）    ││                        ││          ││       │
└─────────┘└──────────┘└──────────────────────┘└─────────┘└──────┘
```

- **每区一块独立「暗黑哥特边框面板」**（见 §3），取代 v2 的竖线分隔；区与区之间留 ~8px 间隙。
- 区序固定，不随状态重排。技能栏中 4 主动槽顺序固定 1→2→3→4，被动·心眼在主动槽右侧、用一条框内细分隔线隔开。
- 物品 2×3 紧贴技能栏右侧；结束回合在最右、单独成红框区。

### 与现有面板的关系
- v3 把 v2 中分散的「左下信息面板 / 资源行 / 右下操作壳」整合为一条 L→R 五区栏的概念布局。实装时可沿用现有 `_info_panel`（① 个人信息）、新增/移动资源栏为 ②、`SkillBar` 重排为 ③、操作壳改为 ④ 物品网格、`_end_button` 独立为 ⑤；具体落点见 §10。
- 现有左下信息面板的内容（头像 / 名 / 等级 / HP / XP / 属性）= ① 个人信息区，保持其数据来源不变。

---

## 2. 布局尺寸（像素）

| 元素 | 尺寸 | 说明 |
|------|------|------|
| 主动技能槽 | **56 × 56** | 圆角 4（沿用 `set_corner_radius_all(4)`）；4 槽，键 1-4 |
| 被动槽（心眼）| **48 × 48** | 比主动小 8px，居中于槽区，无键位 |
| **物品格（v3 缩小）** | **38 × 38** | 比被动 48 更小（用户要求「比被动技能图标还小」）；2 行 × 3 列 |
| 物品格间距 | **6px** | 行/列同；复用 `ACTION_BAR_GAP = 6` |
| 槽间距（技能段同段）| **6px** | 复用 `ACTION_BAR_GAP` |
| 结束按钮 | 52 × 52 | 维持现有 `ACTION_BTN_SIZE = 52`；红框区内居中，最右 |
| **剑气分段条（v3 加宽）** | **182 × 16**，10 格 | 每格内宽 15.2px、步进 18.2px；含阈值线 + 空格边 |
| **印记方块（v3 加大）** | **24 × 24**（满态 28 高）| 心 / 道 / 势三块，比 v2 的 18 更舒展 |
| 键位角标 | 14 × 13，字号 9 | 左上角 |
| 资源消耗角标 | 高 12，宽自适应，字号 8（双资源 7.5）| 右下角 |
| swap「换」角标 | 14 × 12，字号 8 | 左下角（仅拔刀态）|
| 物品数量角标 | 13 × 11，字号 7 | 右下角（随 38px 格缩小）|
| 冷却数字 | 字号 18-22，描边 3 | 槽中心 |
| 区域框内边距 | 10px | 框内壁到内容 |
| **伤害预测器（浮窗）** | ~180 × 78 | 浮于目标上方，带指向三角 |

整条栏建议高度约 **118-126px**（含框边 + 内边距 + 56 槽 + 标题行）。

### 2.1 比例再平衡（v3 核心调整）
- **物品区收窄**：单格 56→38px，6 格从 v2 的「1 行横铺 ~380px」压成「2×3 网格 ~130px」，宽度收益显著。
- **资源栏增宽**：剑气条 170→182px，印记块 18→24px，资源区独立成框、内边距充足，整体读屏更舒展。
- 设计依据：剑气/印记是剑圣每回合的核心读屏对象（决定能否拔刀/居合），应给更多视觉权重；物品在战棋节奏里使用频率低，可缩。

---

## 3. 区域框质感规范（暗黑哥特 / Diablo IV 参考）— v3 新增

不再用单纯细线分隔。**每个功能区一块带质感的框（panel/frame）**，参考 Diablo IV 的暗黑哥特、金属/石质描边、暗底带微噪点/渐变面板；但落在「较清晰的像素画风」框架内（像素化描边 + 有限调色板，不糊成拟真）。

### 3.1 四层叠加结构（从底到顶）
| 层 | 值 | 说明 |
|----|-----|------|
| ① 外缘 | fill `#080a12` | 最暗矩形，比内壁大 ~2px，制造凹陷/嵌入感 |
| ② 内壁渐变 | 上 `#141621` → 中 `#0e1019` → 下 `#0a0c14`（竖直）| 模拟自上而下受光 |
| ③ 噪点纹理 | `#1a1d2a` 稀疏点阵（6px 周期，每周期 3 点，透明 .35–.5）| 石质颗粒；像素风克制，密度低不糊 |
| ④ 双色描边 | 受光边（顶 + 左）`#9c8347`（透明 .55）；背光边（底 + 右）`#3a3018`（透明 .9）| 金属/石质高光 + 阴影，制造立体感 |
| ⑤ 四角角饰 | 5×5 方块，左上 `#b8942f` → 右上/左下 `#7a6428` → 右下 `#4a3c18` | 金属铆钉/角饰，按受光方向递暗 |

### 3.2 描边规范
- **受光边**：框的顶边 + 左边，用亮暗金 `#9c8347`，透明度 .55。
- **背光边**：框的底边 + 右边，用深褐金 `#3a3018`，透明度 .9（更实，制造「下沉阴影」）。
- 圆角半径 4-5px；像素化描边宽度 1px（放大样可 1.4px）。
- **结束区变体**：同结构，受光边换红 `#e02e2e`(.45)、背光边 `#4a1416`，角饰红，强调「危险/终结」语义。

### 3.3 GDScript 落地提示
- StyleBoxFlat 单一边框色无法做「顶左亮 / 底右暗」双色。实现双色描边有两条路：
  - 路 A（推荐，低成本）：用 StyleBoxFlat 主描边取背光色 `#3a3018`，叠一个透明背景 + 仅顶/左有色边的覆盖 StyleBox 或用一个自定义 `_draw` 控件画两条受光边线。
  - 路 B：每区框做成自定义 `Control._draw`（参考既有 `HPShieldBar` / `XPBar` 内部类画法），完全自绘四层 + 噪点 + 角饰，质感最可控。
- 噪点纹理：`_draw` 里用稀疏 `draw_rect(1×1)` 循环，或预生成一张小 noise `Texture` 平铺。密度务必低（像素风克制），否则糊。

---

## 4. 调色板（hex，全部对齐现有 GDScript 常量；新增见标注）

| 用途 | hex | 来源常量 |
|------|-----|---------|
| 底板背景 | `#0a0c17` | `COLOR_PANEL_BG` |
| 金色边/标签 | `#b8942f` | `COLOR_GOLD` |
| 亮金（持有印记/选中/阈值达标线/总值）| `#e0bf48` | 印记持有色 |
| 主文本 | `#e6dbc7` | `COLOR_TEXT_MAIN` |
| 次文本 | `#8c8f99` | `COLOR_TEXT_SUB` |
| 弱文本/置灰 | `#5c5c66` | `TEXT_DIM` |
| 标准技能（橙）斩击/居合/拔刀 | `#fa730f` | `COST_COLORS.standard` |
| 移动技能（蓝）一闪 | `#3b82f5` | `COST_COLORS.move` |
| 迅捷技能（绿）招架 | `#10b884` | `COST_COLORS.swift` |
| 剑气 &lt;7 淡蓝（未达标）| `#5fa8d8` | 新增（建议常量 `COLOR_SWORD_QI_LOW`）|
| 剑气 ≥7 紫·达标 | `#a855f7` | 新增（`COLOR_SWORD_QI_HIGH`）|
| 剑气 ≥7 亮紫（刚跨档/满槽）| `#c98bff` | 新增 |
| 剑气槽底 | `#0c1320`（达标切 `#100a1c`）| 新增 |
| **剑气空格底（v3）** | `#0a1019` | **新增**（未充满空格的底色）|
| **剑气空格边·未达标（v3）** | `#314257` | **新增**（始终可见细边）|
| **剑气空格边·达标（v3）** | `#5b3f7a` | **新增**（达标态偏紫细边）|
| 危险/资源不足红 | `#e02e2e` | 接近 `end` 按钮红 |
| 物品空格虚线边 | `#3a3640` | 新增（暗灰占位）|
| 冷却遮罩 | `rgba(6,9,14,.66)` | `OVERLAY_COLOR` |
| **框外缘（v3）** | `#080a12` | **新增** |
| **框内壁渐变（v3）** | `#141621`→`#0e1019`→`#0a0c14` | **新增** |
| **框噪点（v3）** | `#1a1d2a` | **新增** |
| **框受光边（v3）** | `#9c8347`(.55) | **新增**（≈ COLOR_PANEL_BORDER 哑光档）|
| **框背光边（v3）** | `#3a3018`(.9) | **新增** |
| **框角饰（v3）** | `#b8942f` → `#4a3c18` | **新增** |

### 4.1 伤害预测器配色 = 复用 `damage_popup.gd` 既有四类（不另发明）
| 伤害类型 | hex | 来源常量 |
|---------|-----|---------|
| 物理 physical | `#ffffff`（白）| `DamagePopup.COLOR_PHYS` |
| 魔法 magical | `#aa88ff` | `DamagePopup.COLOR_MAGIC` |（holy 类型已移除 2026-07-11，类型轴只有 physical/magical/pure/hybrid）
| 纯 pure | `#ffd700` | `DamagePopup.COLOR_PURE` |
| 混合 hybrid | `#ff8c00` | `DamagePopup.COLOR_HYBRID` |
| 治疗 heal | `#4ce64c`（绿）| `DamagePopup.COLOR_HEAL` |
| 未命中/无效 | `#999999` | `DamagePopup.COLOR_MISS` |

> 关键约束：伤害预测器的类型配色**必须**与飘字 `damage_popup.gd` 一致——预测「物理白」打出来也是「物理白」飘字，玩家颜色记忆连贯，且避免与 HP 红 / 护盾蓝 / XP 紫撞色。

### 4.2 剑气两色不撞色（沿用 v2 论证）
现有条带色：HP 红 `#cc2626` 系、护盾蓝 `#5ba0eb`、XP 暗紫 `#6647b3`。剑气淡蓝 `#5fa8d8` 偏青且形态是 10 格分段（护盾是右贴边半透明叠层），双重区分；剑气达标紫 `#a855f7`/`#c98bff` 明显比 XP 暗紫更鲜亮，且空间分离（XP 在个人信息区、剑气在资源区）。达标用紫制造蓝→紫色相突变，强调「过线 = 质变」。

---

## 5. 各主动槽状态视觉规则

互斥优先级：**冷却中 > 不可用 > 选中 > 常态**（同 v2，不变）。

| 状态 | 触发字段 | 视觉 |
|------|---------|------|
| 常态可用 | `available=true`，`cooldown=0` | 槽边=技能资源色透明 .55；图标全亮；键位角标亮；资源消耗角标淡蓝 |
| 冷却中 | `cooldown>0` | 叠加 `OVERLAY_COLOR` 全槽遮罩 + 中心大号回合数 + 「回合」小字；图标转暗灰 |
| 不可用置灰 | `available=false` 且非冷却 | 整槽去饱和（底 `#0d0a14`，边 `#46474d`）；图标 `#5c5c66`；**缺口资源角标变红**；`reason` 进 tooltip |
| 选中高亮 | `selected_skill_id == skill_id` | 金加粗边（`#e0bf48` 1.6px）+ 外发光；**指向目标时显示伤害预测器（见 §9）** |

资源消耗角标内容规则（值来自 entry 字段，见 §10.2）：仅气 `"%d气"`；气+印记 `"%d印+%d气"`（拔刀「3印+2气」）；0 气回能 `"+1气"`（淡蓝）。

被动槽（心眼）：固定 48px，左上角标 `P`（灰，无键位），不可点、无冷却、无选中态。tooltip：`每点剑气+1%暴击；剑气≥7 时速度+1`。

---

## 6. 键位 1-4 行为（同 v2，不变）

| 键 | 槽 | 技能 | id | `action_cost` | 资源 | 备注 |
|----|----|------|----|--------------|------|------|
| 1 | 槽1 | 斩击 | `swordsman_zhanji` | standard | 0 气，命中 +1 气 | **=基础攻击** |
| 2 | 槽2 | 一闪 | `swordsman_yishan` | move | 1 气，cd3，位移 | |
| 3 | 槽3 | 招架↔拔刀 | `swordsman_zhaojia`↔`swordsman_badao` | swift/standard | 招架 1 气 cd1；拔刀 3印+2气 cd2 | swap 见 §7 |
| 4 | 槽4 | 居合 | `swordsman_juhe` | standard | 6 气，cd3，必中必暴 | |

按键 = 等价点击该槽：`available=true` → 走点击同路径（→ `BottomDashboard.skill_selected(skill_id)`）；否则无反应。self 类（招架）点击后直接执行。斩击（键 1）承接基础攻击（见 §10.5）。被动槽无键位。

---

## 7. slot swap（招架 ↔ 拔刀）行为（同 v2，不变）

**后端已实现 swap 逻辑**。UI 只渲染后端 `display_id`：满 3 印记时槽 3 的 `skill_id` 直接是 `swordsman_badao`。
- 招架态：绿边、`1气`、标题「招架」。
- 拔刀态：橙边、`3印+2气`、标题「拔刀」+ 金色「换」角标（左下）。
- 拔刀施放后后端下一帧把槽 3 变回招架，UI 自动跟随。
- 满印记提示：印记三块同时点亮 + 微放大（§8.2），与槽 3 变拔刀形成双重信号。

---

## 8. 资源栏规则（剑气 + 印记）— v3 加宽 + 空格边强化

数据来源（`update_state` 的 state 顶层键，现已存在）：
- `sword_qi`（int，<0 表示非剑圣→整区隐藏）、`sword_qi_max`（int）
- `marks`（Dictionary，键 `心`/`道`/`势` → bool）
- 阈值参数：`sword_qi_config.speed_threshold`（=7）、`speed_bonus`（=1）；未透传则 UI 写死 7 / +1。

### 8.1 剑气 — 10 格分段条 + 空格始终可见边 + 颜色突变 + 阈值线（v3 核心）
- **空格始终绘制可见细边框（v3 关键改动）**：
  - v2 空格无独立边、只靠槽底；v3 给每个空格画底 `#0a1019` + 1px 细边。
  - 细边色随达标态切换：未达标 `#314257`、达标 `#5b3f7a`（偏紫）。
  - 效果：任意充能量（含 0）下，玩家都能一眼数出 10 段。
- **填充格颜色突变（整条切换，不逐格渐变）**：
  - `sword_qi < 7`：所有已填格 = 淡蓝 `#5fa8d8`，槽底 `#0c1320`，数字淡蓝。
  - `sword_qi >= 7`：所有已填格 = 紫 `#a855f7`，当前最高格用亮紫 `#c98bff`；槽底切暗紫 `#100a1c`、槽缘描边紫 .55，数字亮紫。
- **阈值线**（固定画在第 7 格右缘 x≈126.4，与当前值无关）：
  - 未达标：灰虚线 `#46474d` + 下方小字「阈值 7」。
  - 达标：金实线 `#e0bf48` 1.4px + 上指箭头（三角）+ 「速度+1」标注。
- **尺寸**：条宽 182px、10 格，每格内宽 15.2px、步进 18.2px。
- 数字 `当前/上限`，颜色随达标态（淡蓝→亮紫）。

### 8.2 印记 — 心 / 道 / 势 三方块（v3 加大到 24px）
- 持有：金框金字 `#e0bf48`；未持有：灰框灰字 `#5c5c66`。
- 满 3 印记：三框微放大（24→28 高）+ 加粗，作为「拔刀就绪」前置提示。
- 可加 `2/3` 计数小字辅助。

资源栏作为独立区（位于个人信息与技能栏之间），随技能栏一同显隐（`sword_qi<0` 时整区隐藏；非剑圣职业该区不显示）。

---

## 9. 伤害预测器（v3 新增 — 核心）

技能选中（`selected_skill_id` 非空）+ 鼠标指向合法目标单位时显示。

### 9.1 内容
1. **伤害类型**：颜色徽标（小圆点）+ 类型文字（物理/魔法/纯/混合/治疗），颜色复用 `damage_popup.gd`（见 §4.1）。
2. **预计伤害数值**：
   - **单段**（`hit_count==1`）：直接显数值，如 `物理 · 24`。
   - **多段**（`hit_count>1`）：标 `x × y（总值）`，x=段数/命中数、y=单段伤害、括号=总值，如 `物理 3 × 12（36）`。
     - 文案规则：`"%d × %d（%d）" % [hit_count, per_hit_damage, hit_count * per_hit_damage]`。
     - 配色：x 段数与 y 单段用类型色，「×」用次文本灰 `#8c8f99`，括号总值用亮金 `#e0bf48`（醒目）。
   - **治疗**：用 `+%d`（如 `治疗 · +16`），无命中/暴击行。
3. **命中% / 暴击%**：保留现有 `hit_percent` / `crit_percent`，下方一行（命中灰、暴击橙 `#fa730f`）。

### 9.2 位置（二选一，本稿给抉择建议）
- **主用（推荐）：浮于目标单位上方** — 带向下指向小三角，锚到目标格头顶。选目标时玩家视线在目标格，就近显示最省眼动，符合战棋手感。
  - 实现需世界坐标 → 屏幕坐标跟随（目标格 → CanvasLayer 坐标）；可放在 `popup_layer` 或独立 CanvasLayer 控件。
- **备选：并入现有 forecast 面板** — 零新增定位逻辑，把伤害类型徽标 + x×y 文案插进现有 `_update_forecast` 的「预计伤害」行。
  - 现有 `_forecast_panel` 在左下、固定位（见 `bottom_dashboard.gd` `_layout_dashboard`），改 `_forecast_body` 文案即可。
- **建议**：主用「浮于目标上方」；现有左下 forecast 面板保留为「悬停敌方信息」次要展示，二者不冲突。若浮窗跟随实现成本高，退备选方案。

### 9.3 视觉规范
- 浮窗用暗黑哥特框（§3 同款，缩小版 ~180×78），暗底 + 双色描边 + 指向三角。
- 暴击概率 >0 时，可在数值旁加小「！」或暴击橙描边提示「本击可能暴击」（可选）。
- 不可用/无法命中（hit 0%）时，伤害数值置灰 `#999999`，或显示「无效」。

---

## 10. 给 GDScript 实现的接线建议

> 实现阶段才做。**核心红线：`update_state` 签名 + 6 信号 + `SkillBar` 三方法签名不变。**

### 10.1 复用既有 state 字段（多数无需新增后端数据）
- 每槽：`skills[i]` 含 `skill_id`/`name`/`action_cost`/`timing_constraint`/`cooldown`/`available`/`reason`/`selected`/`slot_origin_id`。
- 资源：顶层 `sword_qi`/`sword_qi_max`/`marks`（+ 可选 `sword_qi_config`）。
- 个人信息：`unit_name`/`char_name`/`level`/`hp`/`hp_max`/`shield`/`xp`/`stats`/`stats_delta`（现 `_info_panel` 已用）。
- forecast：顶层 `forecast`（`tactical_manager._combat_forecast`），现含 `hit_percent`/`crit_percent`/`damage`/`terrain_*`（`counter_expected` 与 counter_* 字段已随自动反击移除 2026-07-11）。

### 10.2 资源消耗角标 = 路 2（数据驱动，沿用 v2）
在 `_build_skill_entry()` 新增透传 `qi_cost`/`mark_cost`/`requires_marks`（取自技能 JSON）。仅加 entry 键，不改任何签名。角标文案由这三字段拼装（见 §5）；缺失时回退常量表 `SKILL_COST_HINT`。

### 10.3 伤害预测器数据需求（v3 关键 — 后端字段补充，加法不破坏现有返回）
**现状**：`DamageCalculator.preview_attack(attacker, defender, action_data)` 返回 `hit_percent` / `crit_percent` / **单次** `damage` / `terrain_*`（`counter_expected` 已随自动反击移除 2026-07-11）。**无段数、无单段伤害、无伤害类型透传到 UI**（伤害类型在 `action_data.damage_type`，但 forecast 字典未带出）。

**建议新增字段（全部加法，旧消费者兼容）**：

`preview_attack` 返回字典新增：
| 字段 | 类型 | 含义 | 缺省 |
|------|------|------|------|
| `hit_count` | int | 段数 / 命中次数 | 1（单段）|
| `per_hit_damage` | int | 单段伤害（= 现 `damage` 当 hit_count==1）| = `damage` |
| `total_damage` | int | 总伤害（= hit_count × per_hit_damage）| = `damage` |
| `damage_type` | String | 物理/魔法/纯/混合/治疗 | 取自 `action_data.damage_type` |
| `is_heal` | bool | 是否治疗（用 `+N` 显示，无命中/暴击）| false |

> 兼容性：现有 `damage` 字段**保留不删**（= total_damage，旧代码继续读）。单段技能 `hit_count=1` 时三个伤害字段等值，UI 走「直接显数值」分支。
> 多段来源：当前 `preview_attack` 只算一次 base damage；多段（如未来连击/多次命中技）需后端在 `action_data` 提供 `hit_count`（来自技能 JSON 的多段定义，如 `multi_hit` / `hit_times`），`preview_attack` 据此填 `hit_count` 与 `per_hit_damage`（单段值不变，total = 段数 × 单段）。

`tactical_manager._build_attack_forecast_for_hover()` 的 forecast 字典对应新增透传：
```gdscript
# 在现有 return 字典中加（不动现有键）：
"hit_count": int(preview.get("hit_count", 1)),
"per_hit_damage": int(preview.get("per_hit_damage", preview.get("damage", 0))),
"total_damage": int(preview.get("total_damage", preview.get("damage", 0))),
"damage_type": str(preview.get("damage_type", "physical")),
"is_heal": bool(preview.get("is_heal", false)),
```
技能目标预测（`SKILL_TARGETING` 分支，`_build_attack_forecast_for_hover` 同级的技能版）同理补这几个字段。

UI 侧（`bottom_dashboard.gd`）`_update_forecast` 或新增的浮窗控件据此拼 x×y 文案 + 类型徽标色（§9.1），颜色查表对应 `damage_popup.gd` 配色（§4.1）。

### 10.4 视觉构建落点
- **区域框（§3）**：每区框用自定义 `_draw` 控件或 StyleBox 组合实现暗黑哥特质感（路 A/路 B 见 §3.3）。建议封装一个 `_make_goth_frame(size, accent_variant)` 复用到五区。
- **① 个人信息**：沿用现有 `_info_panel` / `_build_info_panel`，外层套暗黑哥特框。内容数据不变。
- **② 资源栏**：现 `_sword_qi_row`（纯文本，在 `_build_stats_area` 内）抽出为独立区，剑气段重写为分段条 + 空格边 + 阈值线（自定义 `_draw`，参考 `HPShieldBar`/`XPBar` 画法）；`_update_sword_qi_display` 内部改为按 `speed_threshold` 切色 + 画空格边 + 画阈值线（方法名/调用点不变）。印记块加大到 24px。
- **③ 技能栏（`SkillBar`）**：重写内部 `_build_ui`/`_build_skill_card` 为横排 4 主动 + 被动小图标；**保留** `class_name SkillBar` + `signal skill_selected(skill_id)` + `update_entries(entries, selected_skill_id)` + `set_expanded(expanded)` 签名不变。
- **④ 物品 2×3**：操作段内新增 `_build_item_grid()`（2 行 × 3 列，6 个 38px 格，GridContainer columns=3），复用 `ITEM_PLACEHOLDERS`（5 条 + 1 空 = 6 格）。现有 `_item_popup` 弹窗可弃用或保留为二级菜单（见 §11 待拍板）。
- **⑤ 结束**：现 `_end_button`（52px）独立成红框区，最右。
- **伤害预测器（§9）**：主用浮窗 → 新增独立控件（CanvasLayer / popup_layer 子节点），`update_state` 时按 forecast 字典刷新；备选 → 改 `_update_forecast` 的 `_forecast_body` 文案。

### 10.5 删按钮对信号入口的影响（沿用 v2）
- `attack_requested` 信号保留（API 不变）。斩击槽承接攻击：推荐点斩击槽走 `skill_selected("swordsman_zhanji")` 统一技能路径；若基础攻击有独立分支则斩击槽 emit `attack_requested`（实装时确认 `request_attack_targeting` 入口）。
- `skill_toggle_requested` 信号保留（API 不变），方案 A 下无 UI 触发点（不再有「技能」开关按钮），内部不再 emit。
- `_update_buttons` 中 `attack_*`/`skill_*` 分支随按钮移除停用（保留 `item_*`/`end_*`）。

### 10.6 新增键位 1-4（Godot InputMap，沿用 v2）
在 `project.godot` `[input]` 新增 `skill_slot_1..4` → `KEY_1..4`。接线放 `tactical_scene.gd` 的 `_unhandled_input`：`is_action_pressed("skill_slot_N")` → `_trigger_skill_slot(N-1)` → 取第 N 个 entry，`available` 则走点击同路径。槽序对应 `swordsman.json.skill_ids` 前 4 项；槽 3 swap 由后端 `display_id` 决定。仅玩家回合 + 技能段可用时响应。

---

## 11. 待用户拍板的取舍

1. **伤害预测器位置**：主用「浮于目标上方」（推荐，眼动最省，但需世界→屏幕坐标跟随）vs 备选「并入现有 forecast 面板」（零新增定位，改文案即可）。本稿默认主用浮窗 + 保留左下面板为悬停信息。
2. **物品点击二级菜单**：一级 2×3 常驻已定。点格后是否弹二级菜单（使用/查看/丢弃）未定 —— 选项 a 点格直接使用（最快，误触风险）；选项 b 点格弹轻量 popover（多一步，安全）。视觉稿默认「2×3 常驻 + 不画二级菜单」，二级行为留接口。
3. **多段伤害数据来源**：x×y 需后端 `preview_attack` 提供 `hit_count` / `per_hit_damage`（§10.3）。当前无多段技能定义 —— 若短期内剑圣无多段技，UI 可先全走单段分支（`hit_count=1`），后端字段加好备用；待引入多段技再启用 x×y 显示。请确认是否现在就要后端补这两字段，还是 UI 先按单段实现、字段后补。
4. **区域框双色描边实现路径**：路 A（StyleBox 组合，成本低、双色描边略受限）vs 路 B（全自绘 `_draw`，质感最佳、代码量大）。建议路 B 用于资源栏/技能栏等核心区，路 A 用于个人信息等次要区。

---

## 12. 参考来源

- Diablo IV UI / HUD 面板质感：暗黑哥特、金属/石质描边、暗底渐变 + 微噪点、嵌入式面板框、角部金属饰件。
- DOTA 2 HUD：技能键位角标左上、消耗右下、冷却中心遮罩数字、置灰表不可用、背包格子常驻横铺（v3 改 2×3 网格）。
- LOL：被动小图标 + 四主动横排，被动无键位。

本设计取上述交集落到本项目：L→R 五区 + 每区暗黑哥特框 + 键位左上 + 消耗右下 + 冷却中心遮罩 + 被动小图标无键位 + 物品 2×3 缩小 + 资源栏加宽 + 伤害预测器（类型徽标 + x×y）。

Sources:
- [Diablo IV — Official Site](https://diablo4.blizzard.com/)
- [Dota 2 — 7.00 New HUD](https://www.dota2.com/700/hud/)
- [Head-up Display — Dota 2 Wiki (Fandom)](https://dota2.fandom.com/wiki/Head-up_Display)
- [Template: Ability bar — League of Legends Wiki](https://wiki.leagueoflegends.com/en-us/Template:Ability_bar)
