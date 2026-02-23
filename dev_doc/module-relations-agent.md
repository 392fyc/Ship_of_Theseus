# 模块关系图（Agent版本）

> 本文件为 Vibe Coding Agent 提供结构化的模块依赖信息。
> 修改任何模块时，必须检查其【被依赖方】和【依赖方】是否需要同步更新。

---

## 依赖关系表

每个模块列出：它依赖谁（修改上游时本模块可能受影响），以及谁依赖它（修改本模块时需检查下游）。

```yaml
modules:

  01-turn-system:
    description: "回合+速度轮动系统，控制行动顺序和回合推进。定义词汇（角色回合开始/结束 vs 回合开始/结束）、先制优先级、同速处理规则、Buff/Debuff时机规则"
    depends_on: []
    depended_by:
      - 02-grid-and-map:  "回合推进触发地形效果/建筑效果"
      - 03-battle-calculation: "角色回合时序决定Buff/Debuff触发和扣减时机"
      - 04-skills-and-range: "回合推进触发冷却恢复；Effect的duration扣减规则定义在01"
      - 06-enemy-and-ai: "AI在自己行动时决策"
      - 08-network: "GameAction封装所有行动指令"
    key_exports:
      - current_round        # 当前回合数
      - action_queue         # 行动顺序队列（含先制排序）
      - current_actor        # 当前行动单位
      - priority_system      # 先制优先级（0/+1/+2）
      - timing_definitions   # 角色回合开始/结束 vs 回合开始/结束的定义
      - buff_debuff_timing   # 效果触发=角色回合开始, 持续扣减=角色回合结束

  02-grid-and-map:
    description: "网格系统三层结构（基础地形→特殊地形→建筑）、9种基础地形、攻击线阻挡（PEAK）、寻路。视野系统待独立文档"
    depends_on:
      - 01-turn-system: "回合开始时触发地形效果"
      - 11-town-building: "战场建筑放置在网格上，覆盖基础地形效果"
    depended_by:
      - 03-battle-calculation: "地形修正影响伤害和命中；攻击线阻挡影响可攻击目标"
      - 04-skills-and-range: "射程计算基于网格距离；攻击线检查；技能可创建/改变特殊地形"
      - 06-enemy-and-ai: "AI需要读取地图进行寻路和位置评估"
      - 07-run-loop: "关卡配置指定地图ID"
    key_exports:
      - grid               # 网格数据（三层：基础地形、特殊地形、建筑）
      - get_movable_cells() # BFS移动范围
      - find_path()        # A*寻路
      - get_cell_effects() # 获取格子上叠加后的最终效果
      - check_attack_line() # 检查攻击线是否被PEAK阻挡

  03-battle-calculation:
    description: "伤害公式（乘区分层）、命中/暴击（加法）、格挡判定、伤害类型双轴（属性类型×攻击方式）、攻击结算流程（命中→格挡→暴击→伤害→附加效果→反击→追击）、追击系统（速度差×10%概率）、角色行动时序"
    depends_on:
      - 02-grid-and-map: "地形属性加成（加到属性上）、特殊地形修正（独立乘区）、攻击线阻挡"
      - 04-skills-and-range: "技能倍率、附加效果、pre_move/post_attack_move标记"
      - 05-class-system: "角色属性值、职业基础格挡率、成长规则（speed/move/block不成长）"
      - 11-town-building: "建筑减伤在最终伤害增减乘区；建筑耐久独立结算"
    depended_by:
      - 06-enemy-and-ai: "AI评分需要预估伤害/命中/暴击"
    key_exports:
      - calculate_damage()    # 伤害计算（乘区分层）
      - calculate_hit()       # 命中判定（加法模型，20%~100%）
      - calculate_crit()      # 暴击判定（加法+抵抗率，0%~50%）
      - calculate_block()     # 格挡判定（职业固定+装备/技能，与暴击互斥）
      - attack_settlement()   # 完整结算流程（命中→格挡→暴击→伤害→两阶段附加效果→反击→追击）
      - calculate_pursuit()   # 追击判定（(atk.speed - def.speed)×10%，0%~100%）
      - damage_type_system    # 双轴分类：属性类型(physical/magical/holy/hybrid) × 攻击方式(melee/ranged/area)

  04-skills-and-range:
    description: "技能定义、射程模式、AOE范围、冷却系统"
    depends_on:
      - 01-turn-system: "回合推进恢复冷却"
      - 02-grid-and-map: "射程基于网格距离计算"
      - 09-data-architecture: "从JSON加载技能数据"
    depended_by:
      - 03-battle-calculation: "技能倍率参与伤害公式"
      - 05-class-system: "职业定义可用技能列表"
      - 06-enemy-and-ai: "AI选择使用哪个技能"
    key_exports:
      - get_range_cells()   # 计算技能射程内的格子
      - get_area_cells()    # 计算AOE影响范围
      - skill_data          # 技能数据字典

  05-class-system:
    description: "8基础职业+16转职。职业决定属性/武器限制/初始技能/class_tags。反击系统。追击系统（全职业通用，剑士系深度特化）。Build = 职业+天赋树+随机技能+装备+遗物"
    depends_on:
      - 03-battle-calculation: "属性参与伤害/命中/格挡/反击公式"
      - 04-skills-and-range: "技能定义和element_type/attack_type"
      - 12-talent-tree: "天赋树提供被动特性、核心技能、转职触发"
      - 09-data-architecture: "从JSON加载职业数据"
    depended_by:
      - 06-enemy-and-ai: "AI根据目标职业调整优先级；反击系统影响AI决策"
      - 07-run-loop: "职业选择影响Run开局；升级和天赋点获取"
      - 11-town-building: "限制型建筑需匹配class_tags"
    key_exports:
      - class_definitions    # 8基础职业+16转职定义
      - class_tags           # 职业标签（用于建筑占据、技能限制等）
      - counter_attack_system # 反击系统规则
      - pursuit_system       # 追击系统规则（速度差×10%概率，全职业通用）
      - build_structure      # UnitBuild数据结构

  12-talent-tree:
    description: "天赋树系统（待建）。每次Run重置，Meta解锁范围。包含被动特性、主动技能、转职节点"
    depends_on:
      - 05-class-system: "每个职业有独立的天赋树"
      - 10-milestones: "Meta进度解锁天赋树范围"
    depended_by:
      - 05-class-system: "天赋树提供被动/技能/转职"
      - 07-run-loop: "Run中获得天赋点，天赋树每次Run重置"
    key_exports:
      - talent_tree_definitions  # 各职业天赋树结构
      - talent_point_system      # 天赋点获取和分配
      - advancement_trigger      # 转职节点触发逻辑

  06-enemy-and-ai:
    description: "AI行为模式、评分决策、分批入场、Boss模式"
    depends_on:
      - 01-turn-system: "在AI单位行动时触发决策"
      - 02-grid-and-map: "读取地图进行寻路和位置评估"
      - 03-battle-calculation: "预估伤害用于评分"
      - 04-skills-and-range: "评估可用技能和射程"
      - 09-data-architecture: "从JSON加载敌人模板和波次配置"
    depended_by:
      - 07-run-loop: "关卡配置引用敌人波次"
    key_exports:
      - ai_decide_action()  # AI决策输出GameAction
      - wave_manager        # 波次管理（触发增援）

  07-run-loop:
    description: "Run整体结构（3大关×10小关）、准备阶段、奖励（经验+天赋点+战利品）、Meta进度（横向解锁原则：更多选择而非更强数值）"
    depends_on:
      - 11-town-building: "准备阶段调用城镇建设和修复"
      - 12-talent-tree: "Run中天赋点分配；天赋树每次Run重置"
    depended_by:
      - 02-grid-and-map: "关卡指定地图ID"
      - 05-class-system: "奖励提供技能/装备；职业解锁"
      - 06-enemy-and-ai: "关卡指定敌人配置"
      - 08-network: "联机时同步准备阶段操作"
    key_exports:
      - run_state           # 当前Run进度状态
      - current_stage       # 当前关卡
      - town_state          # 城镇建设状态（含金币）
      - meta_progress       # 跨Run永久进度（横向解锁）
      - talent_points       # 当前可用天赋点
    design_principle: "Meta = 横向解锁（更多选择）而非纵向强化（数值提升）。玩家在任何Meta进度下，已有选项都能支撑完整核心玩法。"

  08-network:
    description: "联机架构、GameAction同步、Host-Client模型"
    depends_on:
      - 01-turn-system: "封装行动指令"
      - 07-run-loop: "同步准备阶段操作和奖励选择"
    depended_by: []
    key_exports:
      - broadcast_action()  # 广播GameAction
      - sync_state()        # 状态同步
    note: "08是叠加层，不改变游戏逻辑，只负责传输。单机时可完全忽略。"

  09-data-architecture:
    description: "JSON数据驱动、数据加载器、项目目录结构"
    depends_on: []
    depended_by:
      - 02-grid-and-map: "加载地图JSON"
      - 04-skills-and-range: "加载技能JSON"
      - 05-class-system: "加载职业JSON"
      - 06-enemy-and-ai: "加载敌人模板和波次JSON"
      - 11-town-building: "加载建筑JSON"
    key_exports:
      - data_loader         # 全局数据加载器
    note: "09是基础设施层。新增任何数据类型时需在此注册。"

  10-milestones:
    description: "开发里程碑、Phase划分、任务清单"
    depends_on:
      - all: "覆盖所有模块的开发计划"
    depended_by: []
    note: "10是计划文档，任何系统变更都可能需要更新对应Phase。"

  11-town-building:
    description: "城镇建设：功能建筑(5种)+战场建筑(6种)、建造/升级/扩建、耐久系统（按伤害类型固定扣减）、占据机制（通用/限制/阻挡/范围型）、修复机制"
    depends_on:
      - 07-run-loop: "准备阶段触发城镇建设和修复"
      - 09-data-architecture: "从JSON加载建筑数据"
    depended_by:
      - 02-grid-and-map: "战场建筑作为网格第3层，覆盖基础地形效果"
      - 03-battle-calculation: "战场建筑提供战斗修正（减伤/命中/射程等）；建筑耐久使用独立结算"
      - 05-class-system: "功能建筑提供购物/技能调整；限制型建筑需匹配职业标签"
    key_exports:
      - town_state          # 当前城镇状态（含所有建筑实例）
      - get_battlefield_buildings() # 获取需放置到地图的战场建筑列表
      - building_durability_system  # 建筑耐久按伤害类型固定扣减
```

---

## 修改影响速查

当你需要修改某个模块时，查看此表确定需要检查哪些文档：

| 修改内容 | 直接影响的文档 |
|---------|--------------|
| 回合流程/速度机制/先制/同速规则 | 01, 02(地形效果触发), 03(角色回合时序), 04(冷却和效果持续), 06(AI行动时机), 08(同步) |
| Buff/Debuff时机规则 | 01(定义), 03(结算流程), 04(Effect定义) |
| 地形/地图结构 | 02, 03(地形修正/攻击线), 06(AI寻路), 09(地图JSON) |
| 伤害/命中公式 | 03, 06(AI预估伤害) |
| 新增/修改技能 | 04, 03(技能倍率), 05(职业可用技能), 06(AI技能选择), 09(技能JSON) |
| 职业/转职/反击/追击 | 05, 03(反击结算/追击结算/属性公式), 06(AI决策含反击和追击), 11(class_tags匹配建筑), 12(天赋树职业分支) |
| 天赋树 | 12(待建), 05(被动/技能/转职), 07(天赋点获取/Run重置), 10(Meta解锁进度) |
| 敌人/AI行为 | 06, 07(关卡敌人配置), 09(敌人JSON) |
| Run结构/关卡流程 | 07, 02(地图), 06(敌人波次), 08(联机同步), 11(准备阶段) |
| 联机机制 | 08, 01(行动指令), 07(准备阶段同步) |
| 数据格式变更 | 09, 以及使用该数据的所有模块 |
| 城镇建设/建筑 | 11, 02(三层叠加/占据/废墟), 03(战斗修正/耐久结算), 05(限制型建筑匹配职业), 07(准备阶段修复) |
| 开发计划调整 | 10 |

---

## 系统分层

```
Layer 4 (Meta层):     07-Run循环  ←→  11-城镇建设
                           ↓
Layer 3 (角色层):     05-职业系统  ←→  06-敌人与AI
                           ↓
Layer 2 (战斗层):     01-回合  →  04-技能  →  03-伤害计算
                           ↓
Layer 1 (基础层):     02-网格与地图
                           ↓
Layer 0 (数据层):     09-数据架构

叠加层 (可选):        08-联机架构（不改变游戏逻辑，仅传输层）
计划层:               10-开发里程碑
```

**开发顺序应自下而上**：Layer 0/1 → Layer 2 → Layer 3 → Layer 4 → 叠加层

---

## Agent使用指南

1. **修改前**：查询本文件确认影响范围
2. **修改时**：先改核心模块，再同步更新所有 depended_by 文档
3. **新增模块**：在本文件中注册 depends_on 和 depended_by，并更新 README 产品目录
4. **数据格式变更**：务必同步更新 09-data-architecture 中的 JSON Schema
5. **验证**：修改完成后，遍历"修改影响速查"表确认无遗漏
