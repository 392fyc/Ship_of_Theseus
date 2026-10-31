---
agent: game-analyst
model: sonnet
tools: Read, Glob, Grep
runtime_seconds: 215
total_tokens: 46471
tool_uses: 15
session: S2-side-sot
date: 2026-05-10
purpose: 4-axis 可行性评估 + 4 suspect points handoff to critic; surfaces hard findings via SoT codebase Grep
---

# 可行性报告: Mage trapezoid + 3-element-exclusion 天赋树设计

## Summary

Mage 的 trapezoid + 元素互斥设计在 SoT 当前阶段属于**概念完整度领先于实现基础**的设计方向。`mg_pentagram.json` 已提供 48 节点 / 66 边的完整骨架（含 advancement / gauge / ring 全层），是现有 5 职业中规模最大的天赋树，超出 `sw_a.json` 约 30%。整体可行性范围：**medium-low 至 medium-high**，区间宽度源于三个尚未解决的运行时实现缺口（元素互斥逻辑、量谱系统、大贤者解封路径），以及 solo dev 在 R6 工程量已被标记 HIGH 背景下的时间预算压力。

---

## 4-Axis Evaluation

### Axis 1: Cost (estimate range)

**可行性: medium-low 至 medium**

**节点数量化基准（基于 mg_pentagram.json 实测）**:

| 层级 | 节点数 | 说明 |
|------|--------|------|
| origin 层 (Lv1) | 3 | 互斥起点 |
| L2 元素专属 | 3 | |
| 共享中道 (Lv3-10) | 14 | mg_sh_* 系列 |
| advancement 节点 | 2 | grand / element |
| post-adv ring | 4×2 层 = 8 | f/i/a/g 通道 |
| hub 节点 (五芒节点 I/II) | 2 | |
| gauge_core / extend | 6 | |
| 终极前置+终极 | 6 | |
| **总计** | **48 节点, 66 边** | |

**实现缺口分析（对照现有代码库）**:

1. **元素互斥运行时**: `unit.gd` 当前仅有 `skill_ids: Array[String]`，无任何 `exclusive_group` 锁定逻辑。需新增节点激活互斥组的写入/阻断机制。估算 150-250 LOC。

2. **天赋树运行时系统**: `data_loader.gd` 加载了 `data/talent-tree/` 但代码库中**未发现任何 talent tree runtime 脚本**（Grep `talent` 全 `.gd` 无结果）。`mg_pentagram.json` 是纯设计文档，尚无对应的激活/解锁/持久化逻辑。这是最大的隐性 cost。估算新建天赋树运行时：**Medium-Large（400-900 LOC，1-2 新 scene）**。

3. **gauge 系统（热量/极寒/风力）**: 三套独立量谱。每套量谱 ≈ 100-150 LOC。3 套 = 300-450 LOC。当前 `buff_effect.gd` 仅支持 stat_mod 型 buff，无法直接承载"热量>60 时改变 AoE 形状"这类条件分支效果。

4. **JSON 平衡点数**: 现有 `mg_*.json` 只定义结构，无具体数值。48 个节点的数值填充 + 3 职业终极技能 JSON 定义 = 约 2-3 天设计时间。

**R6 对接评估**: S67 已标记 R6 (8×16 工程量 HIGH)。Mage 天赋树实现（含 runtime）预计消耗 Solo dev **3-6 周**。若天赋树 runtime 作为共享基础设施优先实现，则 Mage 专属部分降至 1.5-3 周。

---

### Axis 2: Art Debt

**可行性: medium 至 medium-high**

**必需 UI 资产**（无法复用）:

| 资产类型 | 数量 | 备注 |
|---------|------|------|
| 元素 origin 图标 (Fire/Ice/Air) | 3 | 差异化视觉必须 |
| 元素互斥锁定状态指示 UI | 1 套 | 锁定节点的"变灰+锁图标"状态 |
| gauge UI（热量/极寒/风力 进度条） | 3 | 每套量谱 1 个 gauge widget |
| advancement 节点专用视觉 | 2 | Grand Sage / Element Sage 差异化 |
| 元素特效粒子（非必须但期望有） | 3 套 | 可推迟至 polish 阶段 |

**可复用部分**: 天赋树节点背景框、连线、通用选中高亮——若参照 `sw_a.json` 已有视觉系统，可大量复用。

**风险点**（对应 S67 R1）: 3 元素的颜色编码若在天赋树 UI 以外未与 skill 图标、战斗 HUD 统一，会产生 visual language 断裂。

**art debt 总量**: none-to-some + heavy（3 gauge widget + 粒子特效若列入 v1 scope）。建议将粒子特效移至 P2，v1 只做色块标记。

---

### Axis 3: Coupling

**可行性: medium-low**（耦合风险为四轴中最高）

**现有系统边界分析**:

```
GameAction.gd      → 无天赋树感知
TacticalManager.gd → 无 talent/class_advancement 引用
Unit.gd            → skill_ids[] + skill_cooldowns{}，无 exclusive_group / gauge 字段
DataLoader.gd      → 已加载 talent-tree 目录，但 target dict 未声明
```

**需要新增的耦合点**:

1. **Unit → TalentRuntime 引用**: 节点激活/解锁状态需在 Unit 上持久化。影响所有 5 职业。
2. **GameAction / SkillExecution → element tag 感知**: mg_l2_fire "火系伤害+5%" 要求技能执行层能读取 unit 的激活 tag。
3. **元素互斥 → 天赋树 UI → DataLoader**: `exclusive: "origin_element"` 字段需要 runtime 读取、校验、写入三端一致性。
4. **gauge 系统 → TurnManager 生命周期**: 热量衰减依赖 `turn_ended` signal。已存在 signal，但连接方（gauge manager）不存在。
5. **跨职业泄漏风险**: `exclusive: "origin_element"` 若写入通用 talent runtime，其他 7 职业复用同一 runtime 时需要确保命名空间隔离（如 `<class_id>:<group>` 前缀）。

**coupling 等级: heavy**（触及 Unit / DataLoader / GameAction 执行链 / TurnManager 生命周期 4 个核心系统）

---

### Axis 4: Payoff

**可行性: medium-high 至 high**（payoff 为四轴中最强，但依赖实现完整度）

**具体决策面新增**:

| 决策点 | 频率 | 备注 |
|--------|------|------|
| Run 开始时选 Fire/Ice/Air | 每 run 1 次，不可逆 | 最高权重决策 |
| Lv10 选 Grand Sage vs Element Sage | 每 run 1 次，不可逆 | 第二高权重决策 |
| 量谱管理 | 每回合 1-3 次 | 持续性微决策 |
| post-adv ring 节点选择 | run 中持续 | 点数分配决策 |
| 终极前置三元素试炼跨连接路径 | 特殊 | mg_f_19 requires mg_i_19 的循环依赖结构 |

**与 SoT pillar C 一致度**: 高。trapezoid + 元素互斥是 5 职业中拓扑最具辨识度的设计。

**"一句话 pitch" 测试**: "选定你的元素，Lv10 决定是成为三元素融合的全知法神，还是单元素的绝对专精者——两条路都通向终局，但地图中途你无法改变主意。" 可行，但需要 gauge 系统实装才能让 pitch 在实际游玩中兑现。

---

## Open Questions Evaluation (Q-A1 ~ Q-A4)

### Q-A1: Grand Sage 通才 vs Element Sage 专精的成本权衡是否够深？

**评估**: 当前设计中权衡**不对称且偏向 Grand Sage**，存在优化设计风险。

具体数据：
- `mg_ult_grand` 终极前置条件：`mg_f_19, mg_i_19, mg_a_19`
- `mg_f_19` requires `mg_f_18, mg_i_19`（循环）
- `mg_i_19` requires `mg_i_18, mg_f_19, mg_a_19`（循环）
- `mg_a_19` requires `mg_a_18, mg_i_19, mg_g_19`（循环）

这三个 prep 节点在 JSON 中形成了**相互循环依赖的 requires 字段**，在图遍历层面无法拓扑排序。

Element Sage 终极条件 `mg_ult_element` requires `mg_f_19|mg_i_19|mg_a_19`（OR），门槛低于 Grand Sage 的 AND 条件。但若 Grand Sage 获得"解互斥"的自由度，其后期强度大概率碾压专精路线。

**suspect point S1**: Grand Sage 的终局前置逻辑在 JSON 层面存在循环依赖 bug。

---

### Q-A2: 新手 onboarding 流程

**评估**: 当前设计对 onboarding 的投入为零。

对应 researcher finding（Octopath v1 互斥被续作移除）：全局互斥的新手困惑是已验证的设计反向信号。SoT 的互斥发生在 Lv1，此时玩家对 Fire/Ice/Air 的终局效果完全无感知。

Slay the Spire 反例：不可逆可行的条件是早期信息透明 + 单 run 低投入感。SoT 的 run 长度 30 场战斗，投入感不低。

**suspect point S2**: 若 onboarding UI 未在 v1 实装，元素互斥的不可逆性对新手等同于隐形惩罚。

---

### Q-A3: Single-element 节点 chokepoint 风险

**评估**: 当前设计已部分规避 hub risk，但 mg_sh_3_hub 和 mg_sh_6_hub 是潜在单点瓶颈。

实测 hub 节点出边数：
- `mg_sh_3_hub`: 出边 2（mg_sh_4l, mg_sh_4r）——偏低
- `mg_sh_6_hub`: 出边 3（mg_sh_7l/m/r）——合理
- `mg_sh_14_hub / mg_sh_17_hub`: 出边 4——良好

`mg_sh_3_hub` 若移除，mg_l2_* 到 mg_sh_4* 的路径断裂。这是**严格的单入 hub**。

`post-adv` 的 single-element 节点（mg_f_12, mg_i_12, mg_a_12）出边各仅 1 条，Element Sage 路线在 post-adv 前六节点构成 4 条严格线性管道。这不是 chokepoint 问题，而是**post-adv 阶段决策密度低**。

---

### Q-A4: Run-local 互斥 vs Meta-level unlock 交互

**评估**: 设计意图清晰，但 meta 层在代码库中完全缺失，评估只能停留在概念层。

`data_loader.gd` 加载了 `relics` 和 `buildings`，但无 meta-unlock → talent-node 的映射结构。

当前能确认的是：meta 层实现缺失是 Q-A4 无法完整评估的根本原因。

---

## Suspect Points → game-critic

**SP-1: mg_f_19 / mg_i_19 / mg_a_19 循环依赖 (高优先级)**
- **假说**: 三个终局前置节点的 `requires` 字段互相引用，形成拓扑不可排序的循环图。若标准 BFS/DFS 解析，会陷入无限循环或直接报错。
- **检验方向**: 确认设计意图是 AND-gate，若是则 requires 应改为独立前置而非互相引用。

**SP-2: Grand Sage 解互斥后是否存在 Sorlock-equivalent dominant 策略**
- **假说**: Grand Sage 路线 Lv10 后可访问所有 3 元素技能 + 3 套 gauge，理论上组合空间远超 Element Sage。
- **检验方向**: 计算 Grand Sage lv22 最优构筑与 Element Sage lv22 最优构筑在 DPS/场均伤害的上界比值。

**SP-3: 天赋树 runtime 缺失对 v1 实装时间轴的实际影响**
- **假说**: 5 职业天赋树均为纯 JSON 设计文档，代码库中无 talent runtime。
- **检验方向**: 评估是否应将"5 职业基础天赋树 runtime"作为独立 P0 任务。

**SP-4: Element Sage 终局技能"自动根据起源转换技能形式"的数据驱动可行性**
- **假说**: `mg_ult_element` 描述为"自动根据起源转换技能形式"，意味着一个节点 ID 对应 3 种不同的技能效果。当前 DataLoader 无"条件变形"机制。
- **检验方向**: 确认实现方式（1 个 condition branches vs 3 个独立 skill JSON + runtime 分派）。

---

## Adoption Order Recommendation

**P0 — 天赋树 Runtime 基础设施（跨职业共享）**
- DataLoader 声明 `var talent_trees: Dictionary`
- 基础节点激活/去激活逻辑
- exclusive_group 命名空间隔离（class_id 前缀）
- 预估工程量：Medium（300-500 LOC，1 新 scene）

**P1 — Mage 元素互斥逻辑 + advancement 框架**
- origin 节点选中 → 锁定另外两条 origin 的 UI 状态
- mg_adv_grand / mg_adv_element 的不可逆 exclusive 执行
- 修正 mg_*_19 循环依赖
- 预估工程量：Small-Medium（150-300 LOC）

**P1 — 基础 gauge widget（共享组件）**
- 单一 gauge widget 组件，供三元素复用
- 预估工程量：Small（80-150 LOC）

**P2 — gauge 条件效果 + Grand Sage 三元素融合 runtime**
- damage_calculator.gd 接入 element tag 查询
- 三套量谱各自的阈值触发效果
- mg_ult_element 的条件变形 skill 分派
- 预估工程量：Large（600-900 LOC）

**P2 — onboarding UI（元素选择时的 endgame 预览）**
- 选 origin 时展示该元素路线的终局技能描述
- 预估工程量：Small-Medium

---

## Confidence

**信度分级: 3/5（中等）**

| 维度 | 信度 | 原因 |
|------|------|------|
| Axis 1 Cost LOC 估算 | 2/5 | talent runtime 完全缺失，实际工程量范围区间宽（±40%） |
| Axis 2 Art Debt | 3/5 | 天赋树 UI 脚本未找到，无法确认复用基线 |
| Axis 3 Coupling | 4/5 | 基于实际代码 Grep 结果，缺口已明确定位 |
| Axis 4 Payoff | 3/5 | 设计文档完整，但 gauge 机制无实测数据支撑 |
| Open Questions | 2/5 (Q-A1) / 1/5 (Q-A4) | 部分问题需要设计修正才能重新评估 |

**主要不确定性区域**:
1. meta 层（roguelite unlock）的实现状态
2. Grand Sage 三元素融合的数值平衡
3. mg_f_19 循环依赖是否为有意设计
4. Solo dev 可用时间窗口

**移交 critic 的乐观偏差热点**:
- Axis 4 Payoff 评 medium-high 至 high，主要基于设计意图而非实测决策密度
- Adoption Order 默认 talent runtime 为"中等工程量"，若需与 save/load 集成可能跨入 Large 区间
- SP-2 的 Grand Sage dominant 风险在 Adoption Order 中未体现为 blocker

---

**相关文件路径**:
- `D:\ShipOfTheseus\Ship_of_Theseus\data\talent-tree\mg_pentagram.json`
- `D:\ShipOfTheseus\Ship_of_Theseus\data\talent-tree\sw_a.json`
- `D:\ShipOfTheseus\Ship_of_Theseus\scripts\data\data_loader.gd`
- `D:\ShipOfTheseus\Ship_of_Theseus\scripts\units\unit.gd`
- `D:\ShipOfTheseus\Ship_of_Theseus\scripts\core\game_action.gd`
- `D:\ShipOfTheseus\Ship_of_Theseus\data\classes\mage.json`
