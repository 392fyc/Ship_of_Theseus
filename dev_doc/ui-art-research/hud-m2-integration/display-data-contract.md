# M2 显示数据合同

`HudM2DashboardViewAdapter.build(state, icon_textures)` 将
`TacticalManager.get_dashboard_data()` 的 `Dictionary` 转换为 M2 组合可直接传入
`apply_character`、`apply_skills`、`apply_action_resources`、`apply_equipment`、
`apply_relics` 与 `apply_end_action` 的显示对象。它不修改输入，也不创建 UI。

返回 `Dictionary` 的固定键：

- `visible`: 原载荷的可见性；`character`: `HudM2CharacterViewData`。
- `skills`: 按原 `skills` 数组顺序的 `HudM2SkillSlotViewData` 数组。
- `action_resources`: 合法时为 `HudActionResourceViewData`，否则为 `null`；
  `action_resources_valid` 同步说明可否显示行动条。
- `weapon`、`armor`: `HudM2SlotViewData`；`potion`: `HudPotionViewData`；
  `relics`: 八个 `HudM2SlotViewData`。
- `end_action`: `HudEndTurnViewData`。

人物只读取 `unit_name`、`unit_label`、`hp`、`hp_max`、`stats` 与 `stats_delta`。
`unit_name` 显示为职业或单位记录名，不填充玩家姓名。属性依次为
`STR/MAG/DEX/SPE/DEF/RES/LCK/MOV`，其中 `SPE` 对应源键 `spd`；每项只在源值为整数时
显示，增量可为负数。缺少等级、经验、护盾、头像或库存来源时保持缺值或不可用状态，
不写入默认等级、经验、生命上限、样例名称或虚构内容。数值零保留为零。

技能只使用 `resource_cost_display.amount` 与 `resource_cost_display.resource_name`，且仅接受
1 至 999 的整数和非空名称；不会读取 `qi_cost` 或 `mark_cost`。`is_passive` 与
`active_capable` 分别映射；若后者未提供，则按既有语义取 `not is_passive`。纯被动不显示
键位、动作或费用。调用方可通过 `icon_textures[skill_id]` 提供 `Texture2D`，适配器不加载
图库或按 ID 查资源。玩家行动态中，最多前四个可主动技能按原始顺序依次得到 `1` 至 `4`；
敌方或无行动态不获得可触发键位。不可用和冷却技能保留原始主动技能编号，但由 `enabled`
或冷却状态拒绝激活，因此可用性变化不会令后续技能改号。名称、描述、冷却、选中状态和
不可用原因保留到视图对象。

行动资源必须包含六个字段：`movement_remaining`（非负整数）、`movement_available`（布尔）、
`standard_capacity`/`swift_capacity`（1 至 3 整数）以及不超过相应容量的非负剩余值。任一
字段缺失或非法时，`action_resources` 为 `null`，宿主应隐藏行动条。只有玩家行动态才显示它。
结束移动按钮优先于结束回合按钮，并读取各自的 `visible` 与 `disabled`。

职业资源持有量、上限与印记不映射到本合同对象；原始载荷保持不变，后续位置设计另行处理。

当前装备和遗物采用统一的预留展示政策：武器、护甲与八个遗物槽均返回有 `slot_id`
的通用 `HudM2SlotViewData`，`content_id=""`、`icon_texture=null`、`empty_kind=""`、
`occupied=false`、`enabled=false`、`locked=false`。槽位不显示装备图片、类型轮廓或锁，
也不产生请求。即使原始 `weapon_display` 含有效 ID、名称，且调用方提供对应纹理，
本适配器仍返回预留空槽；它不修改这份原始载荷，也不改变战斗武器事实。

预留展示同样用于 `p3-fixtures.json` 的全部状态。`apply_equipment`、`apply_relics`、
`HudM2SlotViewData` 与槽位请求信号继续作为通用接口保留，后续真实装备接入单独实现。
药剂沿用当前独立状态：运行时缺来源时不可用，展示夹具中的血瓶仍保留图片、禁用状态
和既有交互事件。
