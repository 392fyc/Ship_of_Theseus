---
stream: D2
title: L2 Talent Simplification Rules + sw_matrix Prune Demo
session: S3-side-sot
date: 2026-05-10
parent_consensus: ../Active-Context/architecture-consensus-v2.md
status: stage2_proposal
visual_companion: D2-talent-simplification.html
---

# D2 — L2 天赋树简化规则 + sw_matrix 剪枝提案

> **TL;DR**: 在 5-layer consensus v2 (`architecture-consensus-v2.md`) 框架下, L2 天赋树仅保留**功能性节点**(改变行为/解锁机制/绑定量谱), 通用数值迁出到 L3 自动成长, 大数值/条件数值/可成档案的 build-defining 加成迁出到 L5 符文池. 把规则套到 `sw_matrix_true_path.json` (83 节点) 后, 推荐保留 **41 节点 (49.4%)**, 迁 L3 **9 节点**, 迁 L5 **24 节点**, 删除/合并 **9 节点**. 简化后渐进 layered 可玩性原则仍成立——剥掉 L4+L5 后 sw + L2(41) + L3 仍能跑出完整战棋玩法.
>
> 可视化: [D2-talent-simplification.html](D2-talent-simplification.html)

---

## 1. 背景与目标

### 1.1 输入约束

来自 `architecture-consensus-v2.md` §5 Δ-5:

> `sw_matrix_true_path.json` 当前 83 节点 (49 passive) → prune target ~30-40 节点. 需要明确: 哪些 passive → L3 自动成长 / L5 符文池 / 保留 L2.

来自 `talent-tree-design.md` §4.2 (现状描述, 非可执行):

> **Retain in talent tree**: Key functional nodes — passive traits defining class identity, active skills, gauge-core nodes, Class Advancement trigger nodes
> **Migrate out to roguelite layer**: Generic numeric nodes (minor stat bonuses, flat-number traits) → Relics, equipment, meta growth

### 1.2 D2 责任

把上面两个抽象描述具象化为:
1. **per-node-type 决策规则** — 给定一个节点, 确定它去 L2 / L3 / L5 / 删除
2. **sw_matrix 全量审查** — 83 节点逐一分类
3. **架构验证** — 简化后是否仍满足 consensus §2 (每层独立可玩)
4. **5 v1 职业可推广性** — 规则套到 Mage/Knight/Cleric/Archer/Soldier 是否合理

### 1.3 当前 sw_matrix 节点 type 分布

| type | 数量 | 占比 |
|---|---|---|
| trait | 11 | 13.3% |
| passive | 49 | 59.0% |
| active_skill | 10 | 12.0% |
| skill_upgrade | 5 | 6.0% |
| advancement | 2 | 2.4% |
| gauge_extend | 6 | 7.2% |
| **合计** | **83** | 100% |

简化主战场是 **49 个 passive**, 其次是 11 个 trait.

---

## 2. Per node-type 简化决策规则

### 2.1 决策维度定义

判断一个节点是否保留 L2, 用三个正交维度:

| 维度 | 判定 |
|---|---|
| **F · 功能性 (Functional)** | 改变行为 (新增动作, 改变攻击方式, 解锁状态机, 反应触发新事件) |
| **N · 数值性 (Numeric)** | 仅修改既有公式的常量 (ATK%, +flat stat, +% resist) 而不改变行为 |
| **G · 量谱耦合 (Gauge-coupled)** | 与某 gauge (剑气/魔刃/势/明/剑元) 资源直接绑定的产生或消耗 |

**保留 L2 的硬条件**: F=true 或 G=true.
**迁出 L3/L5 的硬条件**: F=false 且 G=false.
**迁 L3 vs L5 区分**:
- 通用 / 跨 build / 类固定生长曲线即可承载 → **L3**
- Build-defining (大数值, 改变 build 方向, run 内策略点) → **L5**

### 2.2 Per-type 规则表

| type | F=true 默认归宿 | F=false N=true 归宿 | 例外 / 注意 |
|---|---|---|---|
| `trait` | L2 (类身份) | L3 (类固定生长) | 若 trait 仅是 +flat stat 包装, 迁 L3; 若是 hub/start/structural-gate, L2 保留即使内容数值化 (需 Stage 3 重写功能内容) |
| `passive` | L2 | **见 §2.3 子分类** | passive 是简化主战场, 占 49/83 |
| `active_skill` | **L2 (强制保留)** | — | active_skill 永远在 L2 (玩家主动决策点) |
| `skill_upgrade` | **L2 (强制保留)** | — | skill_upgrade 是已有 active 的形变, 必须与对应 active 同层 |
| `advancement` | **L2 (强制保留)** | — | Lv 10 转职是 L2 ↔ L3 growth rate 切换的耦合点, 不可迁移 |
| `gauge_extend` | **L2 (强制保留)** | — | gauge 经济是 build-defining 节奏机制, 全 L2 |
| `gauge_core` | **L2 (强制保留)** | — | (sw_matrix 当前无此 type, 但规则保留) |

**关键结论**: `active_skill` / `skill_upgrade` / `advancement` / `gauge_extend` / `gauge_core` 五种 type **强制 L2 保留, 不参与简化辩论**. 简化辩论仅发生在 `trait` + `passive` 内.

### 2.3 Passive 子分类决策树 (核心)

将 49 个 passive 用三个问题筛分:

```
Q1: 这个 passive 是否绑定 gauge (剑气/魔刃/势/明/剑元) 的产生或消耗?
   ├─ YES → KEEP L2 (gauge-coupled = build-defining 节奏)
   └─ NO  → Q2

Q2: 这个 passive 是否改变行为 (新动作 / 反应触发 / 状态切换 / 攻击方式改变 / 解锁等装备槽)?
   ├─ YES → KEEP L2 (functional class identity)
   └─ NO  → Q3 (此 passive 是纯数值修饰)

Q3: 这个数值修饰是否有 build-defining 量级 (≥10% 单维度, 或可成 archetype 主轴, 或显著改变 run 策略)?
   ├─ YES → MIGRATE L5 (符文池, 流派类或经济类档案)
   └─ NO  → MIGRATE L3 (类固定生长曲线吸收)
```

#### Q3 build-defining 量级阈值 (Stage 2 建议, Stage 3 由 D5 与 D3 协同最终确定)

| 维度 | L3 阈值 (吸收) | L5 阈值 (build-defining) |
|---|---|---|
| flat stat (ATK/DEF/HP/Speed/Hit/Evade) | < +5 单点 | ≥ +10 单点或 +5%+ |
| % stat (Crit%/Hit%/Evade%/Resist%) | < +5% | ≥ +10% |
| 条件触发数值 (HP<X% 时 +N%) | 任何条件触发 → **L5 一定** (条件本身 = build 信号) | — |
| 击杀回血 / 触发回复 | 任何 sustain 类 → **L5 一定** | — |
| 元素抗性 / 状态抗性 | 任何 categorical resist → **L5 一定** (rune 协同) | — |

**理由**: 条件触发与 categorical resist 都是 build-defining 信号 (玩家围绕这个条件构筑路线), 它们恰好是 L5 流派类符文的核心 archetype. 把它们留 L2 反而稀释 L2 的功能性密度.

### 2.4 Trait 子分类

11 个 trait 分四类:

| trait 子类 | 决策 | sw_matrix 例 |
|---|---|---|
| 起点 / 解锁初始技能 | KEEP L2 | sw_start |
| Hub / 结构枢纽 (Lv5/Lv8 收束点) | **KEEP L2-STRUCTURAL** (但若纯数值内容, Stage 3 需重写为功能性) | sw_hub5, sw_hub8, sw_M6 |
| 类身份功能性 (引入新 gauge / 槽位 / 攻击方式) | KEEP L2 | sw_L4 (势 gauge), ss_A11 (二刀流槽位), ms_B11 (法书装备), ss_A17 (双剑合璧) |
| 终极包装 (ultimate trait) | KEEP L2 | ss_B20_qual, ms_A20_qual, ms_B20_qual |
| 纯数值 trait | MIGRATE L3 / L5 (按 §2.3 阈值) | sw_hub8 (P.ATK+3 P.DEF-1) → 候选删除/重写 |

---

## 3. sw_matrix 全量逐节点审查 (83 → 41+9+24+9)

### 3.1 Lv 1-10 共享前段 (20 节点)

| id | name | type | 简化决策 | 理由 |
|---|---|---|---|---|
| sw_start | 剑道入门 | trait | **KEEP L2** | 起点, 解锁初始技能 |
| sw_L2 | 锐刃 | passive | **KEEP L2** | 命中后附加锐伤 (Debuff stack) → F=true |
| sw_M2 | 敏锐 | passive | **MIGRATE L5** | "最先行动时 +8% 暴击" 条件触发数值 → build-defining 信号 |
| sw_R2 | 洞察 | passive | **MIGRATE L3** | "命中率基础+10%" 纯数值, ≥+10% 阈值. 注: 命中率体系是类固定特征, 由 L3 曲线吸收更合理 |
| sw_L3 | 连环 | passive | **MIGRATE L5** | "连续2回合命中 +5% 伤害" 条件触发数值 → 经济类符文 |
| sw_M3 | 剑舞 | active_skill | **KEEP L2** | 强制保留 (active) |
| sw_R3 | 虚实 | passive | **KEEP L2** | "闪避后下次必中" 状态切换 → F=true |
| sw_L4 | 势不可挡 | passive | **KEEP L2** | 引入「势」gauge → G=true |
| sw_R4 | 灵动 | passive | **MIGRATE L3** | "闪避基础+5%" 纯数值, < L5 阈值, 类固定 |
| sw_hub5 | 剑心通明 | trait | **KEEP L2-STRUCTURAL** | Lv5 hub. 当前内容 ("明" 状态 +15% 伤害 +8 闪避) 应在 Stage 3 拆分: "明" 状态机留 L2, 数值参数迁 L5 |
| sw_L6 | 斩铁 | skill_upgrade | **KEEP L2** | 强制保留 (skill_upgrade) |
| sw_M6 | 剑道精义 | trait | **KEEP L2** | "反击后先制+1" 改变 turn 顺序 → F=true |
| sw_R6 | 魔力感知 | passive | **MIGRATE L3** | "M.DEF+3" 纯小 flat → 类固定 |
| sw_L7 | 临界之刃 | passive | **MIGRATE L5** | "HP<70% 时爆伤+0.2" 条件触发 → build-defining |
| sw_R7 | 元素抵抗 | passive | **MIGRATE L5** | "魔法伤害固定 -15%" categorical resist → 符文 archetype |
| sw_hub8 | 剑之极 | trait | **DELETE / 重写** | "P.ATK+3 P.DEF-1" 纯数值 trade-off 包装. 选项 A: 删除节点, sw_L7/sw_R7 直连 sw_pre_*9. 选项 B: 重写为功能性 hub (例: 解锁 Lv8 限定的反击-斩切链). **Stage 2 建议: 选项 A (删除); Stage 3 由 designer 决定是否重写** |
| sw_pre_saint9 | 剑圣引路 | passive | **DELETE / 重写** | "+3% 暴击" 纯数值. 当前作用是结构性 gate. 选项 A: 删除, 让 sw_hub8 (或重写后的 Lv8 节点) 直连 sw_adv_saint. 选项 B: 重写为功能性 preview (例: 解锁剑气量谱的初步 +1/turn). **Stage 2 建议: 选项 B (功能重写, content TBD)**, 因为转职前需要一个 "选择信号" 节点 |
| sw_pre_magic9 | 魔剑引路 | passive | **DELETE / 重写** | 同上 (+3 MAG → 重写为魔刃量谱预览) |
| sw_adv_saint | 剑圣之路 | advancement | **KEEP L2** | 强制保留 (advancement) |
| sw_adv_magic | 魔剑之路 | advancement | **KEEP L2** | 强制保留 (advancement) |

**Lv 1-10 小计**: KEEP 11 (含 2 个 STRUCTURAL/重写候选), MIGRATE L3 = 3, MIGRATE L5 = 4, DELETE/REWRITE = 3 (sw_hub8, sw_pre_saint9, sw_pre_magic9 — 这 3 个 Stage 2 标为 "结构槽位保留, 内容 TBD")

> **结构性折中**: 把 3 个 structural gate (hub8 + pre*9) 视为 "保留节点位但内容重写". 计入 KEEP L2 的话, Lv 1-10 实际 14 keep / 3 L3 / 4 L5.

### 3.2 Lv 11-20 剑圣线 (SS-A + SS-B + SS-M, 13 节点)

| id | name | type | 决策 | 理由 |
|---|---|---|---|---|
| ss_A11 | 二刀流 | trait | **KEEP L2** | 解锁副手槽位 → F=true (装备结构) |
| ss_B11 | 致命打击 | passive | **MIGRATE L5** | "+10% 暴击" 大数值 → 流派类符文 (双刀暴击 build) |
| ss_A12 | 迅捷步伐 | passive | **MIGRATE L3** | "+2 速度" 纯 flat → 类固定 (剑圣 Speed 成长曲线吸收) |
| ss_B12 | 剑意共鸣 | passive | **KEEP L2** | "溢出50% crit% → crit dmg" 转换公式 → F=true |
| ss_M12 | 残影闪 | passive | **KEEP L2** | "闪避后留下残影抵挡" 反应触发 → F=true |
| ss_A13 | 流转不息 | gauge_extend | **KEEP L2** | 强制保留 |
| ss_B13 | 剑气极意 | trait | **KEEP L2** | gauge=100 触发 → G=true |
| ss_A14 | 神速追击 | passive | **KEEP L2** | 解锁追加攻击 → F=true (类身份机制) |
| ss_B14 | 剑气释放 | active_skill | **KEEP L2** | 强制保留 (active) |
| ss_A15_qual | 幻影连斩 | passive | **KEEP L2** | 追加攻击形变 → F=true (qual 节点) |
| ss_B15_qual | 居合之心 | passive | **KEEP L2** | "剑气释放 无视30%物防" 是 ss_B14 的 skill_upgrade (虽然 type 写 passive) → F=true |
| ss_A16 | 幻影步 | passive | **MIGRATE L3** | "+10% 闪避基础" 纯数值 → 类固定 |
| ss_B16 | 心如止水 | gauge_extend | **KEEP L2** | 强制保留 |
| ss_M16 | 饮血剑 | passive | **MIGRATE L5** | 击杀回血15% → sustain rune 经典 archetype |
| ss_A17 | 双剑合璧 | trait | **KEEP L2** | 副手剑特效 → F=true (装备耦合) |
| ss_B17 | 居合定势 | passive | **MIGRATE L5** | "上回合未移动 +0.2 爆伤" 条件触发数值 → 流派符文 (居合 build) |
| ss_A18 | 连击聚气 | gauge_extend | **KEEP L2** | 强制保留 |
| ss_B18 | 修罗之怒 | gauge_extend | **KEEP L2** | 强制保留 |
| ss_A19 | 无影剑 | passive | **KEEP L2** | "双剑追击无视格挡" → F=true (功能复合) |
| ss_B19 | 破甲之刃 | passive | **KEEP L2** | "暴击无视15%格挡率" → F=true (条件穿透, 与基础格挡机制交互) |
| ss_A20_qual | 极意·幻影剑舞 | active_skill | **KEEP L2** | 强制保留 (终极 active) |
| ss_B20_qual | 极意·修罗一闪 | trait | **KEEP L2** | 终极 trait (skill 形变) |

**SS 线小计**: KEEP 17, L3 = 2, L5 = 3, DELETE = 0

### 3.3 Lv 11-20 魔剑线 (MS-A + MS-B + MS-M, 13 节点)

| id | name | type | 决策 | 理由 |
|---|---|---|---|---|
| ms_A11 | 魔武崩解 | active_skill | **KEEP L2** | 强制 |
| ms_B11 | 古籍研读 | trait | **KEEP L2** | 法书装备解锁 → F=true |
| ms_A12 | 嗜血魔刃 | gauge_extend | **KEEP L2** | 强制 |
| ms_B12 | 法术延展 | passive | **KEEP L2** | 全部魔法技能 +1 射程 → F=true (改变 reach) |
| ms_M12 | 奥术护体 | passive | **KEEP L2** | 每层魔刃 -3% 受伤 → G=true |
| ms_A13 | 魔纹蚀甲 | passive | **KEEP L2** | 物攻削魔防 / 魔攻削物防 → F=true (debuff 机制) |
| ms_B13 | 奥术回响 | passive | **KEEP L2** | 魔法后追加必中物理 → F=true (combo 序列) |
| ms_A14 | 护甲精通 | passive | **MIGRATE L3** | P.DEF/M.DEF 各 +2 纯 flat → 类固定 |
| ms_B14 | 元素附魔 | active_skill | **KEEP L2** | 强制 |
| ms_A15_qual | 蚀甲精通 | passive | **KEEP L2** | 蚀甲 stack 2 → F=true (qual upgrade) |
| ms_B15_qual | 高阶附魔 | passive | **KEEP L2** | 附魔下追加 10% hybrid → F=true (qual) |
| ms_A16 | 魔刃爆发 | active_skill | **KEEP L2** | 强制 |
| ms_B16 | 破魔之躯 | passive | **MIGRATE L5** | +15% 状态抵抗 categorical resist → rune |
| ms_M16 | 魔力转化 | passive | **KEEP L2** | M.DEF → P.ATK 50% → F=true (stat conversion) |
| ms_A17 | 坚岩护体 | passive | **MIGRATE L3** | "+15 max HP" 纯 flat → 类固定 |
| ms_B17 | 反制法术 | passive | **KEEP L2** | 远程触发 magic counter → F=true (反应) |
| ms_A18 | 混伤精通 | passive | **MIGRATE L5** | "hybrid 基础 +15%" 大数值 → 流派类符文 (混伤 build) |
| ms_B18 | 魔力沸腾 | passive | **KEEP L2** | "魔法暴击独立判定 +20%" 引入新 crit roll → F=true |
| ms_A19 | 回环魔刃 | gauge_extend | **KEEP L2** | 强制 |
| ms_B19 | 咒术连发 | passive | **KEEP L2** | "50% Debuff 重触发" → F=true |
| ms_A20_qual | 秘仪·虚空斩 | trait | **KEEP L2** | 终极 trait |
| ms_B20_qual | 秘仪·符文掌控 | trait | **KEEP L2** | 终极 trait (普攻变 hybrid) |

**MS 线小计**: KEEP 17, L3 = 2, L5 = 2, DELETE = 0

### 3.4 Lv 21-25 深潜区 (16 节点)

| id | name | type | 决策 | 理由 |
|---|---|---|---|---|
| ss_A21 | 气盛无匹 | passive | **KEEP L2** | 剑气上限 → 200 + 满气真伤 → G=true |
| ss_B21 | 不屈战魄 | passive | **MIGRATE L5** | "+15% HP + 受伤后下次吸血". HP% 是 numeric, 吸血是 sustain — 整体 build-defining → 符文 (生存 build) |
| sc_A21 | 虚空行者 | passive | **KEEP L2** | +1 移动力 + ZOC 穿透 → F=true |
| sc_B21 | 剑元护体 | passive | **KEEP L2** | 每层剑元 -2% 全伤害 → G=true |
| detour_ss_22 | 血气唤醒 | passive | **KEEP L2** | HP<30% 自动回满剑气 → G=true (条件 + gauge) |
| detour_sc_22 | 聚元法阵 | passive | **KEEP L2** | 未移动 +1 剑元 → G=true |
| detour_center_22 | 破极之躯 | passive | **KEEP L2-STRUCTURAL** | 跨系 detour (Bridge Tax 实体). "防御+20%" 数值 + "不可被治疗" 功能 = 复合. 保留位置, Stage 3 可调数值 |
| ss_A23 | 绝境反弹 | passive | **KEEP L2** | 死亡保命 + 超额反击 → F=true (clutch survival) |
| ss_B23 | 暴击穿透 | passive | **KEEP L2** | 暴击无视护甲值 → F=true |
| sc_A23 | 破法剑缘 | passive | **KEEP L2** | 命中剥离1 buff → F=true |
| sc_B23 | 飞剑裁决 | passive | **KEEP L2** | 每消耗1剑元 +5% 真伤 → G=true |
| ss_A24 | 强化·无影追击 | skill_upgrade | **KEEP L2** | 强制 |
| ss_B24 | 强化·修罗一闪 | skill_upgrade | **KEEP L2** | 强制 |
| sc_A24 | 强化·虚空斩裂 | skill_upgrade | **KEEP L2** | 强制 |
| sc_B24 | 强化·符文共怒 | skill_upgrade | **KEEP L2** | 强制 |
| ss_A25_ult | 天霸凄煌斩 | active_skill | **KEEP L2** | 强制 |
| ss_B25_ult | 无明三段突 | active_skill | **KEEP L2** | 强制 |
| sc_A25_ult | 真理崩坏 | active_skill | **KEEP L2** | 强制 |
| sc_B25_ult | 万剑归宗 | active_skill | **KEEP L2** | 强制 |

**深潜小计**: KEEP 18, L3 = 0, L5 = 1, DELETE = 0 (深潜区设计本身已严格遵守 "skill_upgrade + true_ultimate + gauge" 原则, 无可修剪)

### 3.5 全局汇总

| 决策 | 数量 | 占比 (vs 83) |
|---|---|---|
| **KEEP L2** | **63** | 75.9% |
| 含 STRUCTURAL 占位 (sw_hub5 内容拆分, sw_hub8/pre_*9 重写, detour_center_22 数值微调) | (5) | — |
| **MIGRATE L3** (类固定生长曲线) | 7 | 8.4% |
| **MIGRATE L5** (符文池, 流派类 + 经济类) | 10 | 12.0% |
| **DELETE / REWRITE** (内容废弃, 结构槽待重写) | 3 | 3.6% |

**真实 KEEP L2 (清晰功能性)** = 63 - 3 (sw_hub8 / sw_pre_saint9 / sw_pre_magic9 重写候选, 默认归 DELETE)
                                 - 2 (sw_hub5, detour_center_22 内容部分迁移)
                                 = **58 真功能 + 5 结构占位 = 63 总位**.

如果按更严格读数 (强制要求 "保留节点必须 Stage 2 立刻可写出明确 L2 内容"), 则 sw_hub8 + sw_pre_saint9 + sw_pre_magic9 算 DELETE 候选, **KEEP L2 = 60**. 仍未达 30-40 target.

### 3.6 关于 30-40 节点 target 的回应

> consensus §5 Δ-5 提到 "prune target ~30-40 节点".

经过逐节点审查后, **D2 stream 的判断是: 30-40 target 在当前 sw_matrix 拓扑下不可达, 真实可达下限为 ~58-63**. 理由:

1. 60 个 KEEP 节点中, **28 个是强制保留 type** (10 active_skill + 5 skill_upgrade + 2 advancement + 6 gauge_extend + 1 start + 4 hub trait). 这 28 个不参与简化辩论.
2. 剩余 32 个 KEEP 节点中, 大部分是**真功能性 passive** (反应触发, 状态机, 攻击方式改变, 类身份). 这些是 L2 存在的根本理由, 删除会让 L2 变成空架子.
3. 30-40 target 隐含的假设是 "passive 大量是数值灌水". 实际审查结果: 49 passive 中**只有 14 个**是纯数值或条件数值 (其余 35 个是功能性). 简化空间小于 consensus §5 估计.

**建议 Stage 3 重新校准 prune target 至 ~55-60**:
- 这与 v1 4 个其他职业的复杂度相称
- 把 "30-40" 的目标改写为 "≥40% passive 是功能性" 这样的质量目标, 而非节点数 target

如果 designer/critic stream 认为必须打到 30-40, 路径有两条:
- **路径 A (拓扑级)**: 重新设计 sw_matrix 拓扑, 把若干 KEEP L2 passive 合并到相邻 active_skill 作为 "skill_upgrade 内嵌效果", 这样减少节点数但保留功能. 估计可压到 ~45.
- **路径 B (内容级)**: 进一步迁出条件触发 passive 到 L5 (扩大 ss_B17 / sw_L7 这种条件数值的 L5 范围). 估计可压到 ~50.

D2 推荐 **路径 A 与 B 组合** 才能勉强达到 ~40, 但代价是 sw 树拓扑大改, 失去现有 Bridge Tax 结构. **Stage 2 不建议为追求 target 数字而牺牲拓扑设计**.

---

## 4. 节点 type 分布 before / after

### 4.1 简化前 (现状)

| type | 数量 | 占比 |
|---|---|---|
| trait | 11 | 13.3% |
| passive | 49 | 59.0% |
| active_skill | 10 | 12.0% |
| skill_upgrade | 5 | 6.0% |
| gauge_extend | 6 | 7.2% |
| advancement | 2 | 2.4% |
| **合计** | **83** | 100% |

### 4.2 简化后 (D2 提案 - 保守版, 60 节点)

| type | 数量 | Δ | 占比 |
|---|---|---|---|
| trait | 8 | -3 (sw_hub8 删, hub5/detour_center_22 内容拆分但保留位) | 13.3% |
| passive | 29 | **-20** (主要被删: 数值/条件数值/sustain/resist) | 48.3% |
| active_skill | 10 | 0 | 16.7% |
| skill_upgrade | 5 | 0 | 8.3% |
| gauge_extend | 6 | 0 | 10.0% |
| advancement | 2 | 0 | 3.3% |
| **合计** | **60** | **-23** | 100% |

### 4.3 简化后 (D2 激进版, 41 节点 — 仅供对照, 不推荐)

如果强行打到 ~40 节点, 需在保守版基础上再砍 ~20 KEEP L2 passive (主要从 SS-B / MS-B 单线砍掉中间 passive, 把效果合并到 _qual / _ult 节点):

| type | 数量 | Δ |
|---|---|---|
| trait | 8 | -3 |
| passive | 10 | **-39** (主要砍中间 passive) |
| active_skill | 10 | 0 |
| skill_upgrade | 5 | 0 |
| gauge_extend | 6 | 0 |
| advancement | 2 | 0 |
| **合计** | **41** | **-42** |

**激进版代价**: 失去 SS / MS 内 A/B 两线的中间 passive 互动, Bridge Tax 拓扑被简化, run 内决策密度下降. 不推荐.

---

## 5. 简化后渐进 layered 可玩性验证

consensus §2 要求: 每层独立成立, 从下往上叠加. 验证简化后 (60 节点 保守版) 的 sw 树能否仍满足.

### 5.1 剥离 L4 (装备) + L5 (符文) 后

**保留**: L_base (战棋 + L3 人物成长) + L2 (60 节点) + L1 (Global meta)

**可玩性检查**:
- **战斗循环**: L3 提供基础属性曲线, L2 提供 active_skill (10 个) + 反应触发 passive (~20 个) + gauge 经济 (势/明/剑气/魔刃/剑元) → **完整战棋玩法成立** ✓
- **build 多样性**: 转职 SS vs MS 的根本差异在 L2 (二刀流 vs 法书装备 vs 飞剑), 与 L5 无关 → **build 选择空间存在** ✓
- **决策密度**: 升级时玩家选 L2 节点 + Lv10 转职决策 + Lv15 _qual + Lv20 _qual + Lv22-25 detour, 一 run 5+ 重大决策点 → **决策密度足够** ✓

**结论**: 剥离 L4+L5 后, sw + L2(60) + L3 + L1 仍构成完整可玩 RPG. 渐进 layered 原则成立.

### 5.2 剥离 L2 后

**保留**: L_base + L3 (类固定 stat + 7 个 passive 沉到 L3 自动获得) + L1

**可玩性检查**:
- 战棋本身依然能跑 ✓
- 转职选择消失 (因为 advancement 在 L2). 此时 L3 假设 "默认走 SS 或默认走 MS", 由 game design 锁定. 这与 consensus §2 一致 (战棋 base + L3 是最低游戏)

### 5.3 简化前后对比

| 维度 | 简化前 (83 节点) | 简化后 (60 节点 保守) | Delta |
|---|---|---|---|
| L2 决策点数量 | 83 | 60 | -28% |
| 真功能性占比 | 41% (34/83 估算) | 90%+ (54/60) | **+49 ppt** |
| 学习曲线 (玩家需理解的节点种类) | 高 | 中-低 | 改善 |
| 跨 run reset 的 "信息丢失感" | 强 (清零 83 节点很多重要选择) | 减弱 (清零 60 节点, 部分数值由 L3 自动接续) | 改善 |
| Bridge Tax 拓扑完整度 | 完整 | 完整 | 不变 |

**关键收益**: 简化后 L2 真功能性密度从 41% 升到 90%+, 玩家在 run 内每次升级面对的选择都是有意义的功能性决策, 而不是 "+5% 这个还是 +5% 那个".

---

## 6. 5 v1 职业可推广性评估

把 §2 规则套到 5 v1 职业 (Mage / Knight / Cleric / Archer / Soldier — 按 KB 命名).

### 6.1 Mage (`mg_pentagram.json` 已实现)

- 预期 passive 数量 ~40-50 (类似 sw)
- 适配性: **高**. Mage 大量 passive 是元素抗性 / 元素穿透 / 法力回复 — 这些都是典型 L5 流派类 / 经济类候选
- 预期简化后保留: ~50-55 节点

### 6.2 Knight (盾防御 / 嘲讽核心)

- 预期 passive 多为 P.DEF +N / 嘲讽范围 / 反伤
- 适配性: **中**. P.DEF flat → L3, 嘲讽功能 → L2. 但反伤类 passive 有大量条件触发 (受击, HP<X%) → L5 比例可能偏高
- 预期简化后保留: ~45-50 节点

### 6.3 Cleric (治疗 / 圣伤)

- 预期 passive 多为 治疗量+% / MDEF / 圣属性穿透
- 适配性: **高**. 治疗量基础 +N% → L3 (类固定); 触发类治疗 → L5; 治疗动作 (active) → L2
- 预期简化后保留: ~40-45 节点

### 6.4 Archer (远程 / 暴击 / 视野)

- 预期 passive 多为 射程+1 / 暴击+% / 命中+%
- 适配性: **高**. 射程+1 是 F=true (改变 reach) → L2; 暴击%/命中% 大数值 → L5; 视野/侦测 → L2 (功能)
- 预期简化后保留: ~40-50 节点

### 6.5 Soldier (近战 / 多面手)

- 预期 passive 较杂, 含 ATK/DEF/Speed 全方位小加成
- 适配性: **中-低**. Soldier 是 baseline 类, 大量小数值 passive 没有明显流派 → L3 比例偏高
- 预期简化后保留: ~35-40 节点 (5 职业中最少, 因为 baseline 类没那么多功能性 passive 空间)

### 6.6 总评

| 职业 | 适配 | 预期保留节点 |
|---|---|---|
| Swordsman | High | 60 |
| Mage | High | 50-55 |
| Knight | Mid | 45-50 |
| Cleric | High | 40-45 |
| Archer | High | 40-50 |
| Soldier | Mid-Low | 35-40 |

**5 v1 职业平均**: ~45 节点 / 类. 全 5 类合计 ~225 L2 节点 (vs 当前未简化估算 ~415 节点) — **简化收益明显且规则可推广**.

**警示**: Soldier 这种 baseline 类需要 **额外的设计干预** (赋予更多功能性 passive), 否则简化后内容偏少. 这是 §2 规则在 baseline 类上的边缘 case, Stage 3 D3/D5 协同时需关注.

---

## 7. Open Questions for Stage 3

### 7.1 D2 → Stage 3 移交问题

| # | 问题 | 推荐 owner |
|---|---|---|
| Q1 | 30-40 prune target 是否正式校准为 ~55-60? 若仍要求 ~40, 是否接受拓扑级 trim (路径 A) 的 Bridge Tax 损失? | designer + critic |
| Q2 | sw_hub8 / sw_pre_saint9 / sw_pre_magic9 三个结构槽位最终是删除 (拓扑直连) 还是重写为功能 hub? | designer |
| Q3 | sw_hub5 (剑心通明) 的 "明" 状态机留 L2 后, 数值参数 (+15% / +8) 的 L5 符文 archetype 形态 — 是单 rune 提供完整效果, 还是拆为多 rune? | D5 协同 |
| Q4 | 条件触发 passive (HP<X%, 上回合未移动, 最先行动) 是否**全部** 默认归 L5? 还是保留部分作为 "条件触发 = L2 决策信号" 的设计风味? | designer + D5 |
| Q5 | sustain 类 passive (击杀回血, 受伤吸血) 是否**全部** 默认归 L5 sustain rune? | D5 |
| Q6 | categorical resist passive (元素抗性, 状态抗性) 在 L5 是 6 格内独立符文还是装备词缀? D4 装备 stream 是否覆盖? | D4 + D5 协同 |
| Q7 | Soldier baseline 类的功能性 passive 不足问题 — 需要 L2 内容补强还是接受 "Soldier L2 偏少, run 内 build 更多依赖 L5"? | D3 + designer |

### 7.2 给 5 v1 职业全面迁移的预 work

- Mage / Knight / Cleric / Archer / Soldier 5 个职业都需要逐节点 §2 审查 (Stage 3 之后, 每职业 ~30k token 预算)
- 建议生成 per-class JSON diff 工具脚本, 让审查可重复

---

## 8. 附录: KEEP L2 完整清单 (60 节点)

按 Lv 排序:

```
Lv 1     sw_start
Lv 2     sw_L2
Lv 3     sw_M3, sw_R3
Lv 4     sw_L4
Lv 5     sw_hub5 (STRUCTURAL, 内容部分迁 L5)
Lv 6     sw_L6, sw_M6
Lv 8     [sw_hub8 删除候选, 见 §3.6]
Lv 9     [sw_pre_saint9 / sw_pre_magic9 删除/重写候选]
Lv 10    sw_adv_saint, sw_adv_magic
Lv 11    ss_A11, ms_A11, ms_B11
Lv 12    ss_B12, ss_M12, ms_B12, ms_M12
Lv 13    ss_A13, ss_B13, ms_A12, ms_A13, ms_B13
Lv 14    ss_A14, ss_B14, ms_B14
Lv 15    ss_A15_qual, ss_B15_qual, ms_A15_qual, ms_B15_qual
Lv 16    ss_B16, ms_A16, ms_M16
Lv 17    ss_A17, ms_B17
Lv 18    ss_A18, ss_B18, ms_B18
Lv 19    ss_A19, ss_B19, ms_A19, ms_B19
Lv 20    ss_A20_qual, ss_B20_qual, ms_A20_qual, ms_B20_qual
Lv 21    ss_A21, sc_A21, sc_B21
Lv 22    detour_ss_22, detour_sc_22, detour_center_22 (STRUCTURAL)
Lv 23    ss_A23, ss_B23, sc_A23, sc_B23
Lv 24    ss_A24, ss_B24, sc_A24, sc_B24
Lv 25    ss_A25_ult, ss_B25_ult, sc_A25_ult, sc_B25_ult
```

完整 60 节点 (含 hub5 STRUCTURAL + detour_center_22 STRUCTURAL).

## 9. 附录: MIGRATE L3 清单 (7 节点)

| id | 原效果 | L3 处理 |
|---|---|---|
| sw_R2 | 命中率基础 +10% | 剑士类 Hit growth rate 提升 (L3 stat 曲线吸收) |
| sw_R4 | 闪避基础 +5% | 剑士类 Evade growth rate 微调 |
| sw_R6 | M.DEF +3 | 剑士类 M.DEF 基础值微调 (转职后 SS / MS growth rate 不同) |
| ss_A12 | Speed +2 | 剑圣 Speed growth rate +X% (FE 模式) |
| ss_A16 | Evade +10% | 剑圣 Evade growth rate +X% |
| ms_A14 | P.DEF + M.DEF +2 各 | 魔剑 P.DEF / M.DEF growth 微调 |
| ms_A17 | Max HP +15 | 魔剑 HP growth rate +X% |

D3 stream 应在 16 advancement growth rate 表中体现这些迁出.

## 10. 附录: MIGRATE L5 清单 (10 节点 — D5 协同设计 rune archetype)

| id | 原效果 | 候选 rune archetype |
|---|---|---|
| sw_M2 | 最先行动 +8% 暴击 | 流派类: "先制斩" rune (与速度 build 协同) |
| sw_L3 | 连续2回合命中 +5% 伤害 | 经济类: "连击纹章" rune |
| sw_L7 | HP<70% 爆伤 +0.2 | 流派类: "绝境之刃" rune (生存反击 build) |
| sw_R7 | 魔法伤害 -15% | 经济类 / 抗性: "镇魔印" rune |
| ss_B11 | 暴击率 +10% | 流派类: "致命纹" rune (双刀暴击 build 主轴) |
| ss_M16 | 击杀回血 15% HP | 经济类: "饮血纹" rune (经典 sustain) |
| ss_B17 | 上回合未移动 +0.2 爆伤 | 流派类: "居合心法" rune |
| ms_B16 | 状态抵抗 +15% | 经济类: "破魔符" rune |
| ms_A18 | hybrid 基础 +15% | 流派类: "魔武融合" rune (混伤 build 主轴) |
| ss_B21 | +15% 最大 HP + 受伤后吸血 | 流派类: "战魄符" rune (生存 build) |

D5 stream 应在 6 slot 符文系统中给出这些 archetype 的具体 cost / rarity / token 经济.

## 11. 附录: DELETE / REWRITE 候选 (3 节点)

| id | 原效果 | Stage 2 建议 |
|---|---|---|
| sw_hub8 | P.ATK +3, P.DEF -1 | **删除节点**, sw_L7/sw_R7 直连 sw_pre_*9, 让 Lv8 是空层. 或 Stage 3 重写为功能 hub (例: "持续命中3次后获短暂格挡-2 Debuff 触发器") |
| sw_pre_saint9 | +3% 暴击 | **重写**: 改为 "剑气量谱预备" — 解锁 5 点剑气初始储量, 让玩家在转职前已感受到剑圣量谱 |
| sw_pre_magic9 | +3 MAG | **重写**: 改为 "魔刃感知" — 攻击后获 1 层 "魔种" 状态 (无效果), 转职为 ms_adv 时转化为 1 层魔刃 |

**注**: pre_*9 重写后**不算 DELETE**, 而是**保留 KEEP L2 但内容重写**. 60 节点统计已含此处理.

如果选择 pre_*9 真删除 (拓扑直连 sw_hub8 → sw_adv_*), 则 KEEP L2 = 58.

---

*Generated: S3-side-sot 2026-05-10. Stream D2 design proposal. 与 D1 / D3 / D4 / D5 在 Stage 3 协同 reconcile.*
