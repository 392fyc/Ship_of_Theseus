# GHV-3 装备／遗物／结束区显示合同

## 范围

本纵向切片只验证装备栏、全职业固定血瓶入口、8 格遗物视觉网格和结束回合／结束移动按钮的声明式结构与显示接口。它不接入生产 `BottomDashboard`，不修改装备、遗物、血瓶或行动流程的玩法规则，也不生成内容图标。

## 当前生产事实与 mock 边界

| 内容 | 本期状态 | 边界 |
| --- | --- | --- |
| 武器槽内容 | `mock-only` | `content_id`、图标、占用状态和 tooltip 只供画廊验证；不读取生产装备账本 |
| 防具槽内容 | `mock-only` | 与武器槽相同，不建立装备刷新链 |
| 遗物槽内容 | `mock-only` | 只向视觉槽注入测试内容；不读取角色遗物或运输队数据 |
| 血瓶内容 | `mock-only` | 只验证全职业通用独立按钮入口、图标接口、tooltip 和 enabled；不建立物品刷新链 |
| 结束回合语义 | 现有真实接口 | 生产 `BottomDashboard` 已有 `end_turn_requested`，`TacticalManager` 已有对应请求入口 |
| 结束移动语义 | 现有真实接口 | 生产 `BottomDashboard` 已有 `end_move_requested`，移动阶段由 `TacticalManager` 单独处理 |

本期唯一允许的数据方向是“明确标注的画廊 mock → 纯显示数据 → 新组件 `apply_view()`”。新组件不得读取、缓存或修改 `Unit`、`RunState`、`GameAction`、`TacticalManager`、`RunManager` 或 `BottomDashboard`。

## 8 个视觉槽与 6 个玩法槽

- 遗物栏必须声明 2 行×4 列、共 8 个 40×40 正方形视觉槽壳。这是当前 HUD 布局数量，只用于空间与皮肤验证。
- 当前玩法上限仍由 `RunState.RELIC_SLOT_MAX = 6` 控制。该常量及其满槽拦截规则属于受保护生产行为。
- 任何新显示数据、组件字段、方法参数或测试命名都不得把 8 表述为遗物玩法容量，也不得新增 `relic_capacity`、`relic_slot_max`、`gameplay_limit` 等字段。
- 视觉组件可以接收不超过 8 项的 mock 槽显示数据；这不代表生产角色能够装备 8 件遗物。

## 纯显示数据

### `HudSlotViewData`

- `slot_id`：视觉槽语义标识，例如 `weapon`、`armor` 或画廊遗物槽标识。
- `content_id`：仅用于 mock 内容身份与无玩法含义的点击回传。
- `icon_texture`：运行时内容纹理接口。
- `tooltip_text`：运行时说明。
- `occupied`：空槽或 mock 占用的显示状态。
- `enabled`：按钮可用显示状态。

此类型不得包含遗物玩法容量，也不得持有玩法对象。

### `HudPotionViewData`

- `content_id`、`icon_texture`、`tooltip_text`、`enabled` 只承担独立血瓶按钮的显示绑定。
- 不得新增次数、堆叠数、补充、冷却、治疗量、使用消耗、商店映射或其他玩法字段。

### `HudEndTurnViewData`

- `action_kind` 只接受 `end_turn` 或 `end_move`。
- `visible`、`enabled` 和 `tooltip_text` 只控制当前结束入口的显示与交互可用性。
- 显示数据不创建 `GameAction`，不调用战术管理器，也不合并两种结束语义。

## 组件与信号合同

- `HudSlotButton` 只绑定图标、tooltip、占用和 enabled，并发出无玩法含义的槽位请求。
- `PotionButton` 独立于装备槽，发出 `potion_requested`；禁用时不得发出请求。信号不携带次数、治疗量或冷却参数。
- `EquipmentHudPanel` 只把武器、防具和血瓶显示数据转交三个声明式子组件。
- `RelicGrid` 只声明并更新 8 个视觉槽壳，不暴露玩法容量接口。
- `EndTurnControl` 必须保留 `end_turn_requested` 与 `end_move_requested` 两个信号。`action_kind=end_turn` 时只发出前者，`action_kind=end_move` 时只发出后者；隐藏、禁用或无效语义不得触发。
- `EndTurnButton` 内的菱形框和沙漏图形保持为两个独立运行时层；正式树不显示 `END` 等审核文字。

## 固定几何

- 装备栏：128×108。
- 武器槽：52×52，位置 `(10, 46)`；防具槽：52×52，位置 `(66, 46)`。
- 血瓶按钮：32×32，位置 `(86, 10)`，位于装备栏内部右上角。
- 遗物栏：278×108；`VisualGrid` 为 250×88，位置 `(14, 10)`。
- 遗物视觉槽：2 行×4 列，每格 40×40；横向间距 30，纵向间距 8。
- 人物画像、装备、血瓶和遗物内框从组件边界至少内缩 10px，即在外围 6px 绘制边缘之外保留至少 4px 透明净距。
- 结束区：76×108；52×52 按钮位于 `(12, 28)`。
- 结束按钮菱形框必须明显大于沙漏且两者边缘不接触。

说明文字不参与以上空间计算。`EQUIPMENT`、`WPN`、`ARM`、`RELIC`、`END` 等审核文字不得进入正式可见树。
