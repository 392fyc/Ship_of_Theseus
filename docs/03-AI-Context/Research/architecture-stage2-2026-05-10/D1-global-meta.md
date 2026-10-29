---
stream: D1
title: L1 Global Meta Layer Spec
session: S3-side-sot
date: 2026-05-10
parent_consensus: ../Active-Context/architecture-consensus-v2.md
status: stage2_proposal
visual_companion: D1-global-meta.html
---

# D1 — L1 Global 解锁池 Spec

> **TL;DR**: L1 是 run-外永久层，唯一原则 "horizontal-only, never vertical"。本 spec 给出 6 大类解锁池 (Class / Advancement Area / Building / Rune Pool / Equipment Catalogue / QoL & Run-Start)，每类配 cap、解锁源、horizontal 验证。复活机制定为 **稀有资源 + 单 run 1 次 + run-reset**；run 起始符文 = **3 选 1 玩家可选**。
>
> 可视化: [D1-global-meta.html](D1-global-meta.html)

---

## 0. 设计前提与硬约束 (来自 Stage 1 共识)

| 约束 | 出处 |
|---|---|
| L1 = run-外永久 horizontal-only 解锁池 | consensus §1 row 1 |
| Meta 不允许提供 vertical power | GDD §7.2 / run-loop.md §Meta Progression / S67 |
| 任何 Meta 等级下，已解锁内容必须支撑完整核心玩法 | run-loop.md (hard rule) |
| L1 能向其它层输出: 解锁更多 class / 轻微初始 stat / 解锁更多装备种类 / run 起始赠 1 符文 | consensus §4 跨层耦合矩阵 |
| 不允许: 起始 HP/ATK 直接加成、核心机制锁后 | run-loop.md §Meta `Prohibited` 列 |

**用户已确认要落地的 5 类项目** (本 spec 的种子需求):

1. 职业解锁
2. 提升一些收益 (economy multiplier 类)
3. 给予轻微初始属性
4. 允许玩家复活
5. run 起始赠与 1 个肉鸽道具 (符文)

本 spec 在此基础上做完整化、分类化、cap 化。

---

## 1. L1 解锁池分类树 (6 大类)

```
L1 Global 解锁池
├── A. Class & Advancement Pool   (职业 + 转职区域)         ← horizontal 主干
├── B. Rune Pool                  (符文池扩充, L5 喂料)     ← horizontal 主干
├── C. Building & Town Pool       (建筑类型 + 等级 cap)     ← horizontal 主干
├── D. Equipment Catalogue        (装备种类 + 词缀池扩充)   ← horizontal 支线
├── E. QoL & Economy Multipliers  (便利性 + 经济倍率)       ← 经济/信息层
└── F. Run-Start Loadout          (起始符文/符文选项/复活)  ← 起始仪式
```

每个大类 = 一棵子树, 互不影响 vertical power, 仅扩选项空间.

### 1.1 大类总览表

| 大类 | 缩写 | Cap (v1 起步) | 解锁源主类型 | horizontal 风险等级 |
|---|---|---|---|---|
| A. Class & Advancement Pool | CL | 8 class × 平均 2 advancement = 16 path | 完成特定 run / boss kill | 低 |
| B. Rune Pool | RU | 经济类 ~30 + 流派类 ~50 (与 D5 同步) | run 内累积、boss drop、town craft 解锁 | 中 (必须严守与 L5 流派 cap 同步) |
| C. Building & Town Pool | BD | 战场建筑 6→12 类 + 等级 cap +1 | 累计资源 / Act 通关里程 | 低 |
| D. Equipment Catalogue | EQ | 词缀池 / 暗金模板, 与 D4 同步 | 击杀稀有敌、Act 通关 | 中 (词缀必须 ≤15% 单效, 见 D4) |
| E. QoL & Economy Multipliers | QL | 8-10 项, 每项 max 3 阶 | town 货币购买 | 高 (最容易越界, 必须严控) |
| F. Run-Start Loadout | RS | 复活 1 阶 + 起始符文 1 阶 + 选项数 +1 | 一次性里程奖励 | 中 (复活若 free 即 vertical) |

---

## 2. 各大类详细规格

### 2.1 大类 A — Class & Advancement Pool

**定义**: 解锁更多职业 + 解锁某职业的额外 advancement 子区。

**v1 起步状态**: 5 class (archer / cleric / knight / mage / soldier), 每个仅 1 个 advancement 子区已解锁 (运行 hash 选定).

**解锁项 cap**:
- 职业总数: 8 (5 起步 + 3 解锁)
- 每职业 advancement 子区: 平均 2 个 (上限 3, 与 D2 talent prune 同步)

**解锁源**:
| 解锁项 | 解锁条件 (示例, 待 acceptance 校验) |
|---|---|
| Swordsman | 任一 class 首通 Act 3 |
| Hunter | 单 run 内击杀 ≥ 50 个敌 |
| Artificer | 单 run 内使用 ≥ 3 个不同建筑 |
| {class}_advancement_2 子区 | 该 class 首通一次完整 run |
| {class}_advancement_3 子区 (若存在) | 该 class 通关 Act 3 boss with advancement_2 active |

**Horizontal-only 验证**:
- ✓ 新 class 提供新玩法形态, 不强于已解锁 class (设计 contract: power-budget-equivalent)
- ✓ 第二 advancement 子区 = 新方向, 不是第一 advancement 的强化版 (talent-tree-design.md §1.4 budget framework 保证: 单 run cost 预算无法同时跑两个子区, 玩家必须二选一)
- ✗ 红线: 严禁 "advancement_2 = advancement_1 + 5%" 这种纯加强变体
- ✗ 红线: 严禁 "解锁后才能补足 base 战棋的某种攻击类型" (例如 Mage 没有 magic_atk → 必须 meta 解锁, 这就是 vertical 锁后)

**示例 (5-10 项)**:

| ID | 名称 | 类型 | 备注 |
|---|---|---|---|
| `cl_unlock_swordsman` | 解锁剑士 | class | 7 武器系全 | 
| `cl_unlock_hunter` | 解锁猎人 | class | 召唤兽体系 |
| `cl_unlock_artificer` | 解锁工匠 | class | 建筑联动专精 |
| `cl_archer_path_b` | 弓手·神射手分支 | advancement | 第二 advancement 子区 |
| `cl_archer_path_c` | 弓手·游荡者分支 | advancement | 第三 advancement (深度解锁) |
| `cl_mage_path_b` | 法师·元素学派分支 | advancement | 第二 advancement |
| `cl_cleric_path_b` | 牧师·圣战祭司分支 | advancement | 第二 advancement |
| `cl_knight_path_b` | 骑士·圣骑分支 | advancement | 第二 advancement |
| `cl_soldier_path_b` | 战士·狂战分支 | advancement | 第二 advancement |

---

### 2.2 大类 B — Rune Pool (符文池)

**定义**: 扩充 L5 符文库的可抽池. 与 D5 spec 强耦合, 本 spec 仅定义 L1 角度的 "解锁喂料" 入口.

**v1 起步池**: 经济类 ~10 + 流派类 ~15 (起步即足够构筑一套有效 build, 满足 horizontal hard rule).

**Cap**:
- 经济类符文池上限: ~30
- 流派类符文池上限: ~50
- 与 D5 talk: D5 决定 rarity tier, 本 D1 只关心 "解锁哪些 ID 进入 run-内可抽池"

**解锁源**:
| 触发 | 入池范围 |
|---|---|
| Act 1 boss 首杀 | 解锁 5 个新经济类 |
| Act 2 boss 首杀 | 解锁 5 个新经济类 + 5 个新流派类 |
| Act 3 boss 首杀 | 解锁 5 个新流派类 |
| 累计完成 N 次 run | 每 N=3 解锁 1 个流派类 (匀速曲线, 防孤立 lockout) |
| 在 run 内 "见过但未捡" 的符文累计 X 次 | 解锁该符文进永久池 (Hades 1 借鉴: 让玩家自然探索) |

**Horizontal-only 验证**:
- ✓ 新符文 = 新组合空间, 不是 "更强版本"
- ✓ rarity tier (D5 决定) 必须保证 common 池就能搭出 viable build
- ✗ 红线: 严禁 "高级符文 = 低级符文 +X%" 单调 vertical 阶梯
- ✗ 红线: 严禁某 build (e.g. "燃烧扩散流") 的核心组件被锁在 meta 解锁后

**示例**:

| ID | 名称 | archetype | 备注 |
|---|---|---|---|
| `ru_eco_exp_pulse` | EXP 脉冲 | 经济 | 战斗结算 +X EXP |
| `ru_eco_talent_seed` | 天赋种子 | 经济 | run 内 +1 天赋点 (1 次/Act) |
| `ru_eco_stat_focus` | 属性聚焦 | 经济 | 转职后属性 +1 |
| `ru_arc_burn_spread` | 燃烧扩散 | 流派 | 燃烧周围 1 格扩散 (改变 L2 燃烧节点) |
| `ru_arc_burn_instant` | 即时燃烧 | 流派 | 燃烧立即结算 (改变 L2 燃烧节点) |
| `ru_arc_freeze_chain` | 冰冻连锁 | 流派 | 冰冻可链式触发 |
| `ru_arc_crit_thunder` | 暴击雷击 | 流派 | 暴击附带 AoE |
| `ru_arc_overwatch_loop` | 守望循环 | 流派 | 反应攻击不消耗资源上限 |

---

### 2.3 大类 C — Building & Town Pool

**定义**: 战场建筑类型 + 等级 cap 解锁. (与 GDD §10 town building 一致.)

**v1 起步**: 6 战场建筑 (Watchtower / Fortress / Barricade / Life Spring / Ballista / Magic Tower), 全部 Lv1 可造.

**Cap**:
- 战场建筑总类: 6 → 12 (解锁 6 类 advanced)
- 每建筑等级 cap: Lv1 → Lv3 (但 Lv2/3 必须为 horizontal 改方向, 不是纯数值升)

**关键设计取舍**: 等级 cap 从 Lv1 升到 Lv2/3 的本质必须是 "解锁该建筑的另一种 mode/形态", 不是 "Watchtower Lv2 = Lv1 但 ATK +30%".
- 例: Watchtower Lv2 = "可指向远程嘲讽" (新功能), 不是 "ATK +30%"
- 例: Life Spring Lv2 = "改为持续治疗一格区域" (改方向), 不是 "回血 +1"

如不能保证, 退回 Lv1 only, 改为 "建筑类型扩充" 而非 "等级 cap 扩充".

**解锁源**:
| 触发 | 解锁 |
|---|---|
| Act 1 通关 1 次 | 1 个新战场建筑类型 |
| Act 2 通关 1 次 | 1 个新战场建筑类型 |
| Act 3 通关 1 次 | 1 个新战场建筑类型 |
| 累计建造该建筑 N 次 | 该建筑等级 cap +1 (限 horizontal 形态 Lv2/3) |

**Horizontal-only 验证**:
- ✓ 新建筑 = 新战术工具 (e.g. Magic Tower 处理 magic_atk, Ballista 处理远程压制)
- ✓ 等级 cap 改方向 = 新形态选项, 不是数值堆砌
- ✗ 红线: "Lv2 = Lv1 数值 +X%" 必须禁止 (这正是 run-loop.md `Prohibited` 列点名的反例)

**示例**:

| ID | 名称 | 类型 | 备注 |
|---|---|---|---|
| `bd_unlock_traptower` | 陷阱塔 | building | 触发型 AoE 减速 |
| `bd_unlock_warhall` | 战争厅 | building | 队伍 buff 光环 (run 内单一) |
| `bd_unlock_runeforge` | 符文熔炉 | building | town 内: 兑换 rune (与 L5 同步) |
| `bd_unlock_relayhub` | 中继站 | building | 跨格传送 (战术工具) |
| `bd_lvcap_watchtower_l2` | 望塔 Lv2 形态 | level_cap | 远程嘲讽方向 |
| `bd_lvcap_lifespring_l2` | 生命泉 Lv2 形态 | level_cap | 区域 HoT 方向 |

---

### 2.4 大类 D — Equipment Catalogue

**定义**: 装备种类 + 词缀模板池扩充. **与 D4 spec 强耦合**, 本 spec 仅定义 L1 角度的 "解锁哪些进 drop pool".

**v1 起步**: 6 武器类型 + 4 防具类型, 词缀池约 ~20 词缀模板.

**Cap**:
- 武器类型: 6 → 10 (新增 advancement-specific 武器, 与 talent-tree-design.md §1 advancement names 同步)
- 防具类型: 4 → 6
- 词缀模板池: ~20 → ~50 (与 D4 同步)

**关键约束 (来自 D4 边界, 此处仅引用)**: 装备 **不承担 build-defining**. 单词缀效果 ≤ 15% stat boost, ≤ 1 个有限触发条件.

**解锁源**:
| 触发 | 解锁 |
|---|---|
| 击杀指定稀有敌 (named elite) | 该敌的标志武器进 drop pool |
| Act boss 首杀 | 该 act 关联词缀模板进池 |
| 累计找到 X 件传说装备 | +1 词缀复合槽位 (D4 决定具体 cap) |

**Horizontal-only 验证**:
- ✓ 新装备 = 新攻击类型 / 新形态 (例: 双手剑解锁 → 玩家有 sweep AoE 选项)
- ✓ 新词缀 = 新随机性维度 (不是 "+5% ATK" 的更强版 "+10% ATK")
- ✗ 红线: 严禁解锁 "传说级词缀 = 史诗级词缀的强化版"
- ✗ 红线: 装备词缀绝对 ≤ 15% stat boost (D4 hard cap)

**示例**:

| ID | 名称 | 类型 | 备注 |
|---|---|---|---|
| `eq_unlock_greatsword` | 双手剑 | weapon_type | sweep AoE 攻击形态 |
| `eq_unlock_crossbow` | 十字弓 | weapon_type | 高伤低速远程 |
| `eq_unlock_polearm` | 长枪 | weapon_type | 2-range melee 形态 |
| `eq_unlock_buckler` | 圆盾 | armor_type | block + counter 形态 |
| `eq_aff_burning` | 燃烧词缀 | affix | 攻击附加 burn 1 turn (≤15% 阈值) |
| `eq_aff_chilled` | 寒冷词缀 | affix | 攻击附加 -1 速 1 turn |

---

### 2.5 大类 E — QoL & Economy Multipliers

**定义**: 便利性 + 经济倍率. **此类最危险**, 必须严控阶数与上限.

**v1 起步**: 0 (全部需玩家解锁).

**Cap**:
- 项目数: 8-10 项
- 每项最高阶: 3 (与 run-loop.md §Convenience Upgrades 一致)
- **总数值预算**: 起始 gold 总加成 ≤ +30, 商店折扣总 ≤ -10%, EXP 倍率 ≤ +10% (软上限, 即使 max 全开也不破坏 base 战棋)

**解锁源**:
- town 货币购买 (跨 run 累计资源)
- 严禁通过 run 内行为直接解锁 vertical 数值倍率 (经济类倍率必须慢解锁, 防玩家爆 grind)

**Horizontal-only 验证 (本类最严)**:
- ✓ 起始 gold +N: 信息/经济层, 不直接增战力, 玩家仍要做 prep 决策
- ✓ shop discount: 同上, 经济摩擦减少, 不增战力
- ✓ extra reroll: 信息层
- ✓ map preview: 信息层
- ⚠ EXP 倍率 +10%: 边缘 case. 论证: 单 run 内 EXP 加速 → 玩家可能稍早转职, 但因 L2 reset 完全清零 + 只解锁 horizontal 选项, 不增加 ceiling. **决策: 保留, 但严格 cap +10% 总, 写入 acceptance 校验**
- ✗ 红线: 严禁 "起始 HP +N" / "起始 ATK +N"
- ✗ 红线: 严禁 "敌人 ATK -N%" (这是隐式 vertical buff)
- ✗ 红线: 严禁 "天赋点起始 +N" (这等于跳过 L2 共享段, 破坏 Bridge Tax 设计)

**示例**:

| ID | 名称 | 类型 | 阶数 | 备注 |
|---|---|---|---|---|
| `ql_starting_gold` | 起始金币 | economy | 3 (+10/阶) | 经济层 |
| `ql_shop_discount` | 商店折扣 | economy | 2 (-5%/阶) | 经济层 |
| `ql_extra_reroll` | 奖励重抽 | info | 2 (+1/阶) | 信息层 |
| `ql_map_preview` | 关卡预览 | info | 1 | 信息层 |
| `ql_event_preview` | 事件预览 | info | 1 | 信息层 |
| `ql_exp_curve_smooth` | EXP 曲线平滑 | economy | 1 (+10%) | **边缘**, 严格 cap |
| `ql_relic_slot_intel` | 符文情报 | info | 1 | 战前看到本场掉落 hint |
| `ql_inventory_size` | 物品栏扩容 | qol | 2 (+2/阶) | 纯 QoL, 0 战力 |

---

### 2.6 大类 F — Run-Start Loadout

**定义**: run 起始时的 "仪式输入" — 复活机制 + 起始符文 + 起始符文选项数.

**v1 起步**: 无复活, 无起始符文.

**Cap**:
- 复活: 1 阶 (永久解锁, 但每 run 仅可使用 1 次, 见 §3)
- 起始符文 slot: 1 阶 (永久解锁, 从 0 → 1)
- 起始符文选项数: 1-3 阶 (从 1 选 1 → 3 选 1)

**解锁源**:
| 解锁项 | 条件 |
|---|---|
| 复活 (单 run 1 次) | 累计 X 次失败 run, 或 Act 1 首通 |
| 起始符文 slot | Act 2 首通 |
| 起始符文选项 +1 (2 选 1) | 累计完成 N=5 次 run |
| 起始符文选项 +2 (3 选 1) | 累计完成 N=15 次 run |

**Horizontal-only 验证**:
- ✓ 复活 (限定 1 次/run, 消耗稀有资源): 不是 "免死", 而是 "一次回血窗口" — 见 §3 详化
- ✓ 起始符文 = 给玩家 1 个 build 锚点, 但仅 1 个, 仍需 run 内补足. 池子来自 B 大类, 无 vertical 强度
- ✓ 选项数扩展: 信息/选择层 horizontal 强化, 不增数值
- ✗ 红线: 严禁 "起始符文可选稀有度高于 run 内随机抽到的最高稀有度"
- ✗ 红线: 严禁 "复活后保留全部资源 + 复活无限制"

---

## 3. 复活机制详化 (consensus §8 OQ)

> Open question: 复活是 free? 消耗稀有资源? 单次 run 内可用次数?

**决策提案**:

| 维度 | 决策 | 理由 |
|---|---|---|
| 消耗 | **稀有资源** (临时命名 `revive_token`) | free 等于隐式 vertical, 必须有 cost gate |
| 来源 | run 外永久持有 1 个 (L1 解锁奖励), run 内 boss 杀获额外 +1 (单 run 上限 2 持有, 可用 1 次) | 跨 run 不积压 (run 结束即 reset 持有), 防 hoarding |
| 触发 | 队伍全灭瞬间, 弹窗 "是否使用 revive_token" (玩家手动确认) | 不自动, 防止误用 |
| 复活后状态 | 全队 HP 50%, **保留 talent / 装备 / 符文 / 资源**, 但 Act 进度 -1 stage (回到上一关卡完成态) | "回血窗口" 而不是 "免死按钮" — 玩家失去本 stage 的 reward, 不是无损 |
| 单 run 上限 | **1 次** | 严格. 即使持有 2 个 token 也只能用 1 个/run |
| 与 multiplayer 协议 | 任一玩家可发起, 全队同意才生效 | 防单人 troll |

**Horizontal-only 验证**:
- ✓ 复活不是 "提升战力", 是 "缓冲容错"
- ✓ stage -1 的代价 = 损失奖励, 玩家 build 没有变更, 战力 ceiling 不变
- ✗ 反例 (避免): "复活后队伍获得永久 buff" (这就是 vertical), "复活无限次" (打破挑战曲线)

**与 Hades 1 Death Defiance 对比**:
- Hades 1: Mirror 解锁 1-3 次 Death Defiance, 死后回血 50%, 无 stage 倒退
- 本设计: 1 次/run, **有 stage 倒退**. 比 Hades 更严, 更贴合 SoT 战棋长 run (Acts × Stages) 容错需求, 但禁止 "无损 retry"

---

## 4. Run 起始符文详化 (consensus §8 OQ)

> Open question: 玩家可选 vs 随机推送? cost 如何?

**决策提案**: **3 选 1, 玩家选择, 来自玩家已解锁 Rune Pool**.

**详化**:

| 维度 | 决策 |
|---|---|
| 数量 | 1 个起始符文 slot (永久, L1 解锁) |
| 选项数 | 1 阶 = 1 选 1, 2 阶 = 2 选 1, 3 阶 = 3 选 1 |
| 池子来源 | 玩家已解锁 Rune Pool (大类 B), 经济类 + 流派类各 50% 权重 |
| 稀有度筛选 | run-start 起始符文 **稀有度 ≤ common-uncommon** (D5 决定具体 tier 名), 严禁稀有及以上, 防 power spike |
| 玩家可重抽 | 否 (1 次推送, 选 1 即定终, 重抽属于 run 内 reroll, 由其它机制处理) |
| 跨职业 | 是 — 起始符文与所选 class 无 hard binding, 但池子可加入 "class affinity weight" |
| 与 L2 转职互动 | 起始符文 = 玩家本 run build 锚点之一, 在 Lv 10 转职时玩家会参考它 (见 consensus §3 决策路径) |

**Horizontal-only 验证**:
- ✓ 玩家可选 → 增加决策密度, 不增数值
- ✓ 稀有度上限 ≤ uncommon → 不破坏 run 内符文获取曲线
- ✓ 池子限定为已解锁池 → meta 解锁 = 横向更多选项, 不是更强符文
- ✗ 红线: 严禁起始符文为 "exclusive to run-start" 的特殊符文 (这就是 vertical "more powerful" )

**与 Hades 2 Arcana Cards 对比** (此机制核心借鉴对象):
- Hades 2: 玩家用 Grasp 资源装多张 Arcana, 类似 SoT 的 6 格符文系统 (D5 范畴)
- 本设计 (起始符文): 仅 1 张起始, 余下 5 格在 run 内填. 比 Arcana 更轻, 起始仅作 "build seed" 而非完整 loadout — 适合 SoT 长 run + 战棋决策密度

---

## 5. Horizontal-only 边界对比表 (好例 vs 反例)

> 此表用于 Stage 3 critic 一致性扫描.

### 5.1 大类级好例 vs 反例

| 大类 | 好例 (horizontal) | 反例 (vertical, 必须禁) |
|---|---|---|
| A. Class | 解锁 Hunter (新玩法 — 召唤兽体系) | 解锁 "强化版 Knight" (+ 5% HP) |
| A. Advancement | 第二 advancement = 新方向 | 第二 advancement = 第一的 +X% 加强变体 |
| B. Rune | 新流派类符文 = 新组合空间 | 高级符文 = 低级符文 + 数值 |
| C. Building | 新建筑 = 新战术工具 | 同建筑 Lv2 = Lv1 + 数值 |
| C. Building level cap | Lv2 = 改方向 (新形态) | Lv2 = ATK +30% |
| D. Equipment | 新武器类型 = 新攻击形态 (e.g. greatsword → sweep) | 新装备 tier = 旧装备数值堆叠 |
| D. Affix | 新词缀 = 新效果维度 | 高级词缀 = 低级词缀 + 数值阶梯 |
| E. QoL | 起始 gold +10 (经济摩擦减少) | 起始 ATK +1 (战力直加) |
| E. Economy | EXP +10% (软上限, 仍守 ceiling) | 起始天赋点 +5 (跳过 L2 Bridge Tax 设计) |
| F. Run-Start | 起始符文 ≤ uncommon | 起始符文 = 独占稀有强化版 |
| F. Revive | 1/run + stage -1 | 无限复活 / 复活无损 |

### 5.2 跨层冲突点 (必须 Stage 3 critic 校验)

1. **L1 解锁 EXP +10% × L5 经济类符文 EXP +X%**: 双倍效应是否破 ceiling?
   - 论证: L5 经济类符文是 run-reset (consensus §1), L1 EXP +10% 是永久. 复合上限 = L1 (10%) × L5 (max 25%) = ~37.5% ceiling. 与 base 战棋 EXP 曲线对比 → 仍在容忍区, 但需 D3 给 stat curve 后做实测.
2. **L1 起始符文 × L5 6 格池**: 起始符文是否占用 L5 一格?
   - 决策: **占用**. L5 6 格中第一格 = run-start preset, 其余 5 格 run 内填. 玩家无法 dump 起始符文.
3. **L1 advancement 解锁 × L2 talent prune**: 第二 advancement 的 talent 子区是否进 sw_matrix?
   - 决策: 进 D2 sw_matrix prune 范围, 但起始仅 advancement_1 子区可见. advancement_2 解锁后, run 内若选 advancement_2 才进可见 prune 子图.

---

## 6. 业内 Reference 评估

### 6.1 Hades 1 — Mirror of Night

**机制**: 永久解锁 + 二选一 buff (e.g. dash 多 1 次 / dash 伤害 +X%). Death Defiance 1-3 次复活.

**适合借鉴**:
- ✓ 二选一结构提供决策密度 (但 SoT 因有 6 类, 不直接照搬)
- ✓ Death Defiance 概念 → SoT 复活机制简化版

**避免**:
- ✗ Mirror 中 "ATK +X%" 类型 buff 是 vertical, SoT 严禁
- ✗ Linear 解锁顺序 (每个玩家以同样顺序点亮) — SoT 应保持各类独立

**Sources**: [Frostilyte: Arcana Cards & Meta-Progression](https://frostilyte.ca/2025/04/09/arcana-cards-meta-progression-in-hades-2-have-me-hooked/)

### 6.2 Hades 2 — Arcana Cards (核心参考)

**机制**: 玩家选择激活 Arcana Cards, 受 Grasp 资源限制. Cards 大幅改变玩法 (charge attack 慢时间 / cast 无敌窗口).

**适合借鉴**:
- ✓ 玩家有 agency 选择激活哪些 — SoT 起始符文 3 选 1 直接借鉴
- ✓ Grasp 限制 = 6 格 + 起始 1 格 限制等价
- ✓ 早期 Arcana 已有 impact → SoT v1 起步池必须保证 viable build

**避免**:
- ✗ Arcana 中部分 vertical 数值 buff (e.g. "全伤害 +X%") — SoT 必须把这些放进 L5 经济类 run-reset 池, 不能进 L1 永久层

**Sources**: [Hades 2 Arcana Tier List](https://mobalytics.gg/hades-2/tier-lists/arcana-cards), [Hades Wiki Arcana](https://hades.fandom.com/wiki/Arcana_Cards)

### 6.3 Rogue Legacy 2 — Manor + Labor Costs

**机制**: Manor 永久升级树, Labor Costs 在 Lv 20+ 引入通胀, 让升级成本随等级 ramp.

**适合借鉴**:
- ⚠ Manor 通胀作为 "soft cap" 思路: 若 SoT 大类 E 经济倍率被玩家 farm, 可加渐进成本曲线, 但 **不强制必要** — SoT 已有阶数 cap, 不需要额外通胀
- ✓ Manor 中 "信息/经济类" upgrade 大量, 可借鉴种类多样性

**避免**:
- ✗ Manor 中 vertical "HP +N / ATK +N / MP +N" 是 SoT 严禁项. Rogue Legacy 2 的 vertical Manor 是其 metroidvania 节奏所需, **SoT 不需要也禁止**
- ✗ Living Safe 等机制对 SoT 不适用 (我们没有 "失去未花金币" 问题)

**Sources**: [Rogue Legacy 2 Wiki: Upgrades](https://rogue-legacy-2.fandom.com/wiki/Upgrades), [Steam: Labor rates](https://steamcommunity.com/app/1253920/discussions/0/3201496916526019951/)

### 6.4 Dead Cells — Collector + Boss Cells

**机制**:
- Collector: blueprint 解锁 → 武器进 drop pool (horizontal)
- Boss Cells: 5 阶难度叠加, 每阶累积 modifier (vertical 难度, 但与 meta 解锁不绑)

**适合借鉴**:
- ✓ Collector 模型 = SoT 大类 D (装备 catalogue) 的直接参考: 击杀稀有敌 → 蓝图入袋 → 交付解锁 → 进 drop pool (而不是直接装备)
- ✓ blueprint 解锁需要 cells (稀有资源) → SoT 用 town 货币 + run 完成度

**避免**:
- ✗ Boss Cells 难度叠加方式 = vertical 难度. SoT 战棋如要做难度阶梯, 应学 STS Ascension, 不学 Dead Cells (理由见 §6.5)
- ✗ Dead Cells 玩家批评 "解锁更多反而某些 build 更难抽到" → SoT 必须做好 weight 调控, 起始池 viable build 不被新解锁稀释

**Sources**: [Dead Cells Wiki: Blueprints](https://deadcells.fandom.com/wiki/Blueprints), [Dead Cells Wiki: The Collector](https://deadcells.fandom.com/wiki/The_Collector), [Dead Cells Custom Mode](https://deadcells.fandom.com/wiki/Custom_Mode)

### 6.5 Slay the Spire — Ascension + 解锁

**机制**:
- Ascension 1-20: 每阶累积 modifier, 玩家通关解锁下一阶
- 卡池解锁: 用某 class 累计 X 点经验, 解锁该 class 的新卡进可抽池

**适合借鉴 (核心)**:
- ✓ STS 是 "horizontal not vertical" 的 **黄金标准** — 解锁卡池 = 抽池更宽, 不增 ceiling
- ✓ Ascension = 难度阶梯独立于解锁池, 如 SoT 后续要做难度选项, 应学 STS (难度阶梯独立, 不与解锁绑)
- ✓ STS 玩家批评 "解锁更多卡反而某些 build 抽不到" → 与 Dead Cells 同警示, weight 调控关键

**避免**:
- ✗ STS Ascension 解锁逻辑 = "通 N 才能玩 N+1" — 这种 lockout 与 SoT 的 "玩家自由选择难度" 哲学是否一致, 留 Stage 3 决定 (本 spec 不强行规定难度阶梯)

**Sources**: [STS Wiki: Ascension](https://slay-the-spire.fandom.com/wiki/Ascension), [Steam: STS Meta progression](https://steamcommunity.com/app/646570/discussions/2/1696043263503477251/), [Slay the Spire 2 Ascension Guide](https://games.gg/slay-the-spire-2/guides/slay-the-spire-2-all-ascension-levels/)

---

## 7. 解锁源汇总表

| 触发事件 | 解锁产物 (示例 ID) |
|---|---|
| Act 1 boss 首杀 | `cl_archer_path_b` (advancement) + 5 经济符文 + `bd_unlock_traptower` |
| Act 2 boss 首杀 | `cl_unlock_swordsman` + 5 经济 + 5 流派 + `bd_unlock_warhall` |
| Act 3 boss 首杀 | `cl_{class}_path_c` (深度) + 5 流派 + `bd_unlock_runeforge` |
| 单 run 击杀 ≥ 50 | `cl_unlock_hunter` |
| 单 run 用 ≥ 3 建筑 | `cl_unlock_artificer` |
| 累计 N=3 run | +1 流派符文 (匀速曲线) |
| 累计 N=5 run | 起始符文选项 +1 (2 选 1) |
| 累计 N=15 run | 起始符文选项 +2 (3 选 1) |
| 累计失败 X run 或 Act 1 首通 | 复活解锁 |
| 累计找到 X 件传说装备 | 词缀复合槽 +1 (D4 决定) |
| town 货币购买 | E 大类 QoL/经济倍率 (按阶解锁) |

---

## 8. v1 起始可玩性自检 (run-loop.md hard rule)

> "在 Meta Progression 任何等级下, 已解锁内容必须支撑完整核心玩法"

**v1 起步状态自检** (假设玩家 0 累计 run, 0 解锁):

| 系统 | v1 起步可玩? | 理由 |
|---|---|---|
| L_base 战棋 | ✓ | 5 class 已可玩, 6 武器, 4 防具 |
| L2 天赋 | ✓ | 每 class 第一 advancement 子区完整, talent-tree-design.md §1.4 budget framework 保证 cost ≤ 25 可达 advancement_1 终点 |
| L3 成长 | ✓ | 类固定 + Lv 10 转职 growth 切换 (D3 范围) |
| L4 装备 | ✓ | 6 武器 + 4 防具 + ~20 词缀池 → 多样组合 |
| L5 符文 | ✓ | 经济 ~10 + 流派 ~15 起步池 → 至少 3 套 viable build |
| 复活 | ✗ (但非必须) | 起步无复活, 玩家容错低 — 这是 design intent (难度起点) |
| 起始符文 | ✗ (但非必须) | 起步无起始符文 — run 内全部从 random 抽 |

**结论**: v1 起步 5/7 系统满足 hard rule, 复活 + 起始符文为 "增益型" 解锁, 不锁后核心玩法. ✓ 通过 hard rule.

---

## 9. Open Questions for Stage 3 Critic

1. **大类 E 中 EXP +10% 是否真 horizontal?**
   合理性论证已在 §2.5 给出, 但需 critic 模拟实际 run 数据后确认 ceiling 不破. 备选: 全砍, 改为信息层项替换.

2. **大类 C 建筑 Lv2/3 的 "改方向" 设计成本是否过高?**
   要求每个建筑 Lv2 = 新形态而非 + 数值, 设计成本翻倍. 是否退守 "Lv1 only, 全部解锁靠新建筑类型"?

3. **复活 stage -1 是否真的够 "punish" 防 spam?**
   Hades 1 无 stage 倒退, SoT 选择 stage -1, 是否对 Act 3 后期惩罚不足? 是否需要 "Act -1" 升级版?

4. **解锁源中 "累计 run 数" 类触发是否会让中期玩家陷入 grind?**
   需要 Stage 3 模拟 run 完成度曲线, 验证 N=3/5/15 的间距是否合理.

---

## 10. 附录: ID 命名规范

```
{prefix}_{kind}_{name}

prefix: cl (class) / ru (rune) / bd (building) / eq (equipment) / ql (qol) / rs (run-start)
kind:   unlock / aff (affix) / lvcap (level cap) / path (advancement) / arc (archetype)
name:   人类可读, snake_case, 英文
```

示例: `cl_unlock_swordsman`, `ru_arc_burn_spread`, `bd_lvcap_watchtower_l2`, `ql_starting_gold`, `rs_revive_token`.

---

*Generated: S3-side-sot 2026-05-10. Stream D1. Mercury core `design`. Token estimate: ~28k. Next: Stage 3 synthesis & critic.*
