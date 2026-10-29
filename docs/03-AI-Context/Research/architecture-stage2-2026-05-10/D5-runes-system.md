---
stream: D5
title: L5 Runes 6-Slot System Spec
session: S3-side-sot
date: 2026-05-10
parent_consensus: ../Active-Context/architecture-consensus-v2.md
status: stage2_proposal
visual_companion: D5-runes-system.html
---

# D5 — L5 符文系统 6 格 Spec (Stage 2 Proposal)

> 父 consensus: `architecture-consensus-v2.md` §1 row 5 / §4 矩阵 / §7 名词表 / §8 OQ D5
> 本文回答 5 大开放问题 + 提交 6 格机制规格 + 经济类/流派类 archetype 示例 + 业内 reference + L2/L5 边界
> **状态标记**: `locked` (consensus 已锁) / `proposed` (本 stream 提议, 待 Stage 3 用户确认) / `rejected` (评估后弃用)

---

## 0. TL;DR

- **6 格 = 硬上限 (proposed lock)**, 不可扩展。理由: 行业证据 (Hades 16-25 选择, MT Champion 5 spec, RoR2 无显式 cap 但实际堆叠产生不可读 build) 一致显示 build 可读性临界点在 5-7 项。
- **2 archetype**: 经济类 (Economic, 12 个示例) + 流派类 (Stylistic, 14 个示例)。前者数值传递, 后者改变 L2 节点行为。
- **Rarity = 3 tier**: Common / Rare / Mythic。高 tier 不是更大数值, 而是更复合 / 更罕见的条件触发或负向 trade-off (Hades 模式: tier 不变 effect kind, 只放大数值 + 解锁 unique condition)。
- **L2 vs L5 边界**: **L2 = 解锁基础流派能力本身, L5 流派类 = 已有流派的 modifier / 风味反转**。例: L2 mage 的 `mg_fire_basic` passive 解锁"火元素普攻"; L5 "扩散燃烧符文" 让该 passive 的 burn debuff 在敌人死亡时溅射相邻 1 格。
- **获取**: Town 兑换 (稳定, 玩家可计划) + Stage 内事件 (RNG, 含 boss 保底) + run 起始 1 个 (L1 已锁)。Run 内典型获取 4-6 个, 6 格满 = 用户必须取舍一次以上。
- **Reroll/Scrap/合成**: `reroll = proposed`(town 服务, 限次), `scrap = locked-in` (满 6 格替换必须丢弃旧的, 不堆叠), `合成 = rejected` (与 town 经济兑换重叠)。

---

## 1. 6 槽机制详化

### 1.1 6 格是否硬上限

**结论 (proposed)**: 6 = 硬上限, run 内任何方式都不能扩到 7+。

**论证**:
1. **行业 cap 数据点** (本 stream §6 详解):
   - Hades 1 Mirror = 16 大类但每类 A/B 互斥 → 等效 ~16 次决策, 但任意时刻激活仅 16 个 binary 状态
   - Hades 2 Arcana = Grasp 池 cap (Grasp 容量从 ~10 起, 解锁可扩到 ~25, 每张 Arcana 占 1-3 Grasp) → 玩家典型激活 5-8 张
   - Monster Train Champion spec = 3-5 升级点, 永远 ≤5
   - Slay the Spire boss relic = 1 boss = 1 boss relic, 4 boss = 4 boss relic; 总 relic 中位 run 末期 ~10-15 (含 starter)
   - Risk of Rain 2 = **无 cap**, item 数量可达 50+, 这是反例 → 后期 build 不可读, 玩家流派 collapse 为"快即正义"
   - Noita perks max = 5 (主线), 完美呼应 6 格区间
2. **决策密度模型**: SoT run 长度 ~3 act × 10 stage = 30 stage, 玩家典型获取 4-6 个符文 (§4.5)。6 格意味着至少进行 1 次显式取舍, 但不会"塞满到无感"。7+ 会导致末期符文之间互相稀释 build identity。
3. **UI 可读性**: 6 = 2×3 / 3×2 grid, 战斗 HUD 一眼可读; 7+ 必须改为 list/tooltip 模式, 在战棋上下文 (本身已有兵棋盘 UI) 是负担。

**反方观点 (考虑后否决)**:
- "Meta 解锁第 7 格" → 违反 horizontal-only 原则 (consensus §7)。否决。
- "高 tier 符文 = 占 2 格 (类似 Backpack Hero polyomino)" → 增加复杂度, 与 SoT 战棋本体已有的网格放置认知冲突。否决, 但保留为 v2 演进备选。

### 1.2 槽属性

每格在 build 中是**等价无序**的, 不区分主/副格, 不区分类型槽位 (经济类和流派类同槽位竞争)。这与 PoE 的 colored socket 模型刻意区分。

**理由**: 槽位若分类型 (e.g. "3 经济格 + 3 流派格"), 玩家会被锁死配比, 无法做"5 流派 + 1 经济"的极端 build, 流失流派表达力。

| 槽位特性 | 决策 | 状态 |
|---|---|---|
| 6 格无序 | locked-in | proposed |
| 同类型可堆叠 (e.g. 2 个经济类 EXP+) | 允许; 经济类线性叠加, 流派类**不允许同符文重复**, 不同流派符文可组合 | proposed |
| 槽位无颜色/类型限制 | locked-in | proposed |

### 1.3 替换 / Reroll / Scrap

**满 6 格后获得新符文**:
```
玩家选择:
  (a) 丢弃当前 6 格中任意 1 个 (旧符文销毁, 不进背包不返还资源)
  (b) 拒绝新符文 (新符文消失)
```
不允许"暂存背包"——这与 STS Relic 一致, 避免玩家攒符文池等 boss 才决定。

| 操作 | 时机 | 资源消耗 | 状态 |
|---|---|---|---|
| 替换 (满格丢弃) | 任何时刻获取新符文 | 0 (旧符文直接销毁) | locked-in |
| Town Reroll | Prep Phase, 在 Rune Altar 前 | Gold, 涨价曲线 (1st=50G, 2nd=100G, 3rd=200G per stage) | proposed |
| Scrap (主动销毁) | Prep Phase | 0, 但返还少量"符文碎片" (用于 town 兑换的 sub-resource) | proposed |
| 合成 (2 低 tier → 1 高 tier) | — | — | rejected (与 town 兑换功能重叠, 增复杂度无收益) |

**理由 reroll 不在战斗中**: 战棋本体决策点已多 (移动 / 行动 / 技能 / 阵型 / building), 战斗内再加 reroll = 决策疲劳。

### 1.4 信息可见性

- **新符文获取时**: 完整 tooltip, 包含与已持符文的 synergy 高亮 (e.g. 玩家已有"火属性符文", 新符文为"扩散燃烧" → tooltip 高亮"与你的火属性符文协同")
- **Lv 10 转职决策点**: 提供"Rune Synthesis Preview"——显示当前 6 格对各 advancement 路径的 fitness 评分。这是 consensus §3 的"Lv10 看符文池决定方向"机制的 UI 实例化。
- **战斗中**: 6 格小图标 HUD 常驻; 触发型符文激活时高亮 + 文字 popup。

---

## 2. 经济类 Archetype (Economic Runes)

**定义** (consensus §7 locked): 提升 EXP / 属性 / 天赋点。中等影响。**基于原职业模型, 不脱离**。

**设计原则 (proposed)**:
1. **Stay-within-class-model**: 经济类符文只放大已有曲线, 不引入新机制。剑士拿"力量 +X 符文"还是剑士行为, 不会突然变成法师。
2. **数值 mid-impact**: 单个经济类符文期望提供 1.05-1.15× run 总输出/生存, 6 格全经济上限约 1.4-1.6×。这远低于流派类符文的 build-defining 效应, 但累积仍可观。
3. **互不冲突**: 多个经济类符文加法叠加 (与 Hades 2 Arcana 的"独立加成"模式一致), 不互斥。
4. **High-uptime**: 经济类符文 effect 是 always-on 或 per-level/per-stage 的稳定输出, 不依赖 trigger condition。
5. **L4 装备 boundary**: 经济类符文是 run-reset 但 stage 间稳定, 区别于 L4 装备 (random RNG drop)。

### 2.1 经济类示例 (12 个, 全 proposed unless noted)

| ID | 名称 | 类型 | 效果 | Tier | 状态 |
|---|---|---|---|---|---|
| eco_exp_01 | 学者之碑 | EXP | 战斗结算 EXP +15% | Common | proposed |
| eco_exp_02 | 战魂残片 | EXP | 击杀精英 +50 EXP, 击杀 boss +200 EXP | Rare | proposed |
| eco_atk_01 | 力量铭文 | 属性 | STR +3 (per character) | Common | proposed |
| eco_atk_02 | 法力铭文 | 属性 | MAG +3 (per character) | Common | proposed |
| eco_def_01 | 守护铭文 | 属性 | DEF +2, RES +2 | Common | proposed |
| eco_spd_01 | 疾风铭文 | 属性 | SPD +2, DEX +1 | Common | proposed |
| eco_hp_01 | 生命之泉 | 属性 | Max HP +10%, 战斗结算回满 HP | Rare | proposed |
| eco_tp_01 | 训练之书 | 天赋点 | 升级时额外获得 1 天赋点 (每 3 级触发, run 内最多 5 次) | Rare | proposed |
| eco_tp_02 | 觉醒之灵 | 天赋点 | Lv10 转职时立即 +3 天赋点 | Rare | proposed |
| eco_gold_01 | 商人之印 | 经济 | Gold 收益 +25%, 商店折扣 -10% | Common | proposed |
| eco_growth_01 | 命运之书 | L3 成长 | 当前 run 内, 每次升级 stat growth +5% (与 L3 FE growth 模式叠加) | Mythic | proposed |
| eco_universal_01 | 元素回声 | 复合 | 所有属性 +1, EXP +5%, 天赋点+1 (一次性, run 起始触发) | Mythic | proposed |

**rejected 候选** (此处记录避免后续重新讨论):
- ❌ "无限堆叠 +DMG 符文" — 违反 Stay-within-class-model, 实际是"小流派符文", 应归类到流派类
- ❌ "复活护符" — L1 复活机制独立处理, 不混入 L5
- ❌ "buff 持续时间 +X turn" — 这本质是流派类 modifier (改变 buff 行为), 应归到流派类

### 2.2 经济类数值范围

| Tier | 单符文期望 run-output 增益 | 数量分布 (按权) | run 末期 6 格全经济上限 |
|---|---|---|---|
| Common | +5% 到 +10% | 60% 池权 | 6 × ~7.5% = ~45% (additive) ≈ 1.45× |
| Rare | +10% 到 +20% | 30% 池权 | — |
| Mythic | +20% 到 +30% 或 unique | 10% 池权 | — |

**6 格全经济类的上限验证**: 1.45× 远低于全流派类 build 的潜在 2-3× (流派类有"质变倍率"特征), 因此玩家选择全经济类 = 安全 / 稳健流派, 选择全流派类 = 高 ceiling 高复杂度 build。两端都 viable, 这是设计目标。

---

## 3. 流派类 Archetype (Stylistic Runes)

**定义** (consensus §7 locked): 改变职业形态/玩法模式。大影响。等价 L2 重要节点。

**设计原则 (proposed)**:
1. **Modifies existing L2 mechanic**: 流派类符文必须**钩在某个已有 L2 节点行为上**, 改变其工作方式 (e.g. 燃烧扩散, 冰冻链, 闪电跳跃)。这是 L2/L5 边界的核心机制 (§5)。
2. **Build-defining**: 单个流派类符文足以改变玩家 run 内的策略思考方式 (e.g. 拿到"扩散燃烧"后玩家会主动让前排 mage 站近一些施放范围燃烧)。
3. **Conditional uptime**: 流派类符文通常有 trigger condition, 不是 always-on。这与经济类形成鲜明对比。
4. **Combo potential**: 流派类符文之间应有显式 combo (e.g. "燃烧扩散" + "敌人着火时降 RES" + "燃烧 tick × 2") = 火法 build 的 nuclear option。
5. **Clear identity gating**: 每个流派类符文绑定 1-2 个 class tag (mage / archer / etc.), 跨 tag 拿到也能用但威力打折 (proposed: 跨 tag 时 effect × 0.6, 防止 1 符文激活 4 个角色 build)。

### 3.1 流派类示例 (14 个, 全 proposed)

| ID | 名称 | 主 class tag | 钩接的 L2 节点 | 改变 | Tier | 状态 |
|---|---|---|---|---|---|---|
| sty_mg_01 | 扩散燃烧 | mage | `mg_fire_basic` (火元素普攻 burn) | 敌人因 burn 死亡时, 燃烧 debuff 溅射相邻 1 格敌人 (1 round) | Rare | proposed |
| sty_mg_02 | 即时燃烧 | mage | `mg_fire_basic` (火元素普攻 burn) | Burn 不再 DoT, 命中时直接结算所有剩余燃烧伤害 | Rare | proposed |
| sty_mg_03 | 冰封连锁 | mage | `mg_ice_chain` (冰元素技能) | 冰冻效果在敌人之间 chain (相邻敌人间, 最多 3 段) | Mythic | proposed |
| sty_mg_04 | 闪电跳跃 | mage | `mg_lightning_bolt` | 闪电技能命中后跳跃到最近敌人 (距离 ≤3, 最多 2 跳, 跳跃伤害递减 50%) | Mythic | proposed |
| sty_mg_05 | 法力虹吸 | mage | (general MAG attack) | 击杀回 25% MP, 同 round 下次施法 cost -1 | Common | proposed |
| sty_ar_01 | 穿透箭雨 | archer | `ar_aimed_shot` | 普攻穿透直线第一个非建筑敌人, 第二个敌人受 60% 伤害 | Rare | proposed |
| sty_ar_02 | 标记猎杀 | archer | `ar_eagle_eye` | 命中敌人施加"标记" (1 round), 队友攻击标记目标 +20% DMG | Mythic | proposed |
| sty_ar_03 | 多重射击 | archer | `ar_piercing_arrow` | 普攻分裂 3 箭 (主 100% DMG, 副 50% DMG × 2 to adjacent) | Rare | proposed |
| sty_kn_01 | 反伤铁壁 | knight | `kn_iron_wall` | 受到攻击时反弹 30% 物理伤害 (同 round 一次) | Rare | proposed |
| sty_kn_02 | 冲锋共鸣 | knight | `kn_heavy_strike` | 冲锋类技能击中后, 邻接队友获得 +1 standard action 充能 | Mythic | proposed |
| sty_cl_01 | 圣光过载 | cleric | `cl_holy_smite` | Holy 技能命中亡灵 / 邪恶 tag 敌人时 crit (固定 1.5×) | Rare | proposed |
| sty_cl_02 | 链式祷告 | cleric | `cl_heal` | 单体治疗变 chain (主 100%, 副 50% to adjacent ally) | Rare | proposed |
| sty_so_01 | 集结呐喊 | soldier | `so_rally` | Rally buff duration +1 round, 范围 +1 格 | Common | proposed |
| sty_universal_01 | 反击连环 | universal | (any retaliation) | 反击 (counter) 命中后 +1 standard action (run 内首次触发限定) | Mythic | proposed |

**rejected 候选**:
- ❌ "改变护甲伤害公式符文" — 这是核心规则改动, 应归全局 mod (L1 难度档位), 不是 build choice
- ❌ "无限连击符文" — 违反 CLAUDE.md "反击/追击不触发连锁"硬约束
- ❌ "暴击格挡同时触发" — 违反 CLAUDE.md "格挡和暴击互斥"硬约束

### 3.2 流派类组合 (Combo) 示例

**Mage 火法 nuclear**:
- `sty_mg_01` 扩散燃烧 + `sty_mg_02` 即时燃烧 + `sty_mg_05` 法力虹吸 + `eco_atk_02` 法力铭文 + `eco_universal_01` 元素回声 + (1 free)
- 效果: 敌人成片着火 → 即时高伤秒杀 → 死亡溅射 → 击杀回 MP → 下次施法更便宜
- 对应转职决策 (consensus §3): Lv10 玩家见此符文池, 应走 "Pyromancer" advancement (强化 fire stack DMG) 而非 "Frost King" (冰流派, 与火池冲突)

**Archer 标记狙击**:
- `sty_ar_02` 标记猎杀 + `sty_ar_01` 穿透箭雨 + `sty_ar_03` 多重射击 + `eco_atk_01` 力量铭文 + (2 free)
- 对应转职: "Sharpshooter" (单体高伤) 而非 "Beast Master" (召唤流)

---

## 4. Rarity Tier 系统

### 4.1 Tier 定义 (proposed)

| Tier | 池占比 | 经济类: 数值幅度 | 流派类: 复合度 |
|---|---|---|---|
| Common | 60% | 中低 (+5-10% scope) | 单一 modifier (e.g. 范围 +1 格) |
| Rare | 30% | 中 (+10-20% scope) | 双 modifier 或 trigger 复合 (e.g. 击杀触发 + 扩散) |
| Mythic | 10% | 高 (+20-30%) 或 unique mechanic | 含 unique mechanic + 弱负面 trade-off (e.g. "标记猎杀 + 自身 MP 上限 -10") |

**Mythic 必须含 trade-off** (proposed, 借鉴 STS Boss Relic 模式): Mythic 不是 Rare 的纯放大, 而是 build-defining 的关键节点 + 玩家必须围绕它构筑队伍。

### 4.2 Tier 与获取来源映射

| 来源 | Common 权重 | Rare 权重 | Mythic 权重 |
|---|---|---|---|
| Run 起始 (L1) | 100% | 0% | 0% |
| Town 兑换 Lv1 | 70% | 30% | 0% |
| Town 兑换 Lv3 (升级后) | 30% | 60% | 10% |
| Stage 普通战 random | 60% | 35% | 5% |
| Stage 精英战 random | 30% | 60% | 10% |
| Stage Boss 保底 | 0% | 50% | 50% |
| Stage Special Event | 30% | 50% | 20% |

**Stage 3 act 期望分布**: 4-6 符文中 ~3 Common + ~2 Rare + ~0.5 Mythic (中位 run)

---

## 5. L2 流派类节点 vs L5 流派类符文 边界

> Consensus §8 OQ D5 核心问题: 都是 build-defining, 怎么不重叠?

### 5.1 边界提议 (proposed)

| 维度 | L2 流派类节点 | L5 流派类符文 |
|---|---|---|
| **角色** | 解锁 / 引入 基础流派能力本身 | 修饰 / 反转 / 放大 已有 L2 流派 |
| **示例** | `mg_fire_basic` 解锁"火元素普攻 (含 burn DoT)" | `sty_mg_01` 改变 burn 的传播方式 |
| **持久度** | run 内永久 (升级了不会消失) | run 内永久 (装上 6 格不会掉) |
| **粒度** | 类内固定结构, 同 class 任何玩家走相同 advancement 都看到这个节点 | 跨 class 共池, 同 advancement 不同 run 拿到不同符文池 |
| **决策时机** | 主动加点 (玩家 + 天赋点) | 半被动 (从池子选择 / 不选) |
| **数值角色** | 提供 base mechanic 的数值参数 (DMG, range, duration) | 提供 modifier 倍率或行为变质 |
| **没了它** | 角色没有这个流派能力 | 角色仍有这个流派能力, 但玩法平淡 |

### 5.2 边界例证

**Case A: Mage 火流派**
- L2 节点 `mg_fire_basic` (passive): "普攻造成 fire DMG, 命中附 burn 1 (debuff: -1 HP / round, 3 round)"
  - 没这个节点 → mage 没有火元素能力, 玩"冰流派"或"雷流派"
- L5 流派类符文 `sty_mg_01` "扩散燃烧": "burn 死亡时溅射相邻 1 格敌人"
  - 没这个符文 → 你仍是火法, 但单体伤害, 没群体扩散
- L5 流派类符文 `sty_mg_02` "即时燃烧": "burn 不再 DoT, 命中时直接结算所有剩余燃烧伤害"
  - 没这个符文 → 你仍是火法, 但靠 DoT 慢烧, 不是爆发流

**Case B: Archer 反例 (符文不能脱离 L2 节点)**
- 玩家走 archer, **未点** `ar_eagle_eye` (标记类 L2 节点) → 拿到 `sty_ar_02` "标记猎杀" 符文怎么办?
- 处理 (proposed): 流派类符文要求至少 1 个 prerequisite L2 node 已激活, 否则符文 effect 失效但占格 (UI 灰显)。Lv 10 转职决策点是检查这个的最佳时刻 — 玩家可基于 6 格符文反向调整 advancement 选择。

### 5.3 验证: 是否真不重叠?

**潜在重叠**: L2 节点也可以是"扩散燃烧" → 重叠风险。
**解决**: D2 stream (L2 simplification) 规定 L2 节点只承担**核心机制定义** (mechanic kind + base numbers); 任何"reaction modifier" / "behavior change" 类节点应被 prune 出 L2, 迁入 L5 池。这是 D5 → D2 的 handoff 信号。

**潜在重叠**: L5 经济类符文 (e.g. STR+3) vs L4 装备词缀 (e.g. STR+5) → 数值类型重叠。
**解决**: L5 经济类是**class-model-aligned** (e.g. STR for melee, MAG for caster); L4 装备词缀是**slot-bound** (头/胸/手/武器), 数值更高但取决于 RNG 装备。L5 更稳定 / 可计划; L4 更随机 / 可堆叠。设计上 mutually compatible。

---

## 6. 业内 Reference 深研

### 6.1 7 款游戏对照表

| 游戏 | 系统 | 总数量 | "6 格类似 cap" | 同 SoT 6 格的对照 | Key Takeaway |
|---|---|---|---|---|---|
| Slay the Spire 1/2 | Relic | STS1 ~150, STS2 ~287 EA | 无显式 cap, run 末期 ~10-15 | SoT 比 STS **严格更紧凑**, 6 格强迫取舍 | STS 用"无 cap + boss 大 trade-off relic"制造取舍; SoT 用"6 格 cap"制造取舍 |
| Hades 1 | Boons + Mirror | Boons ~70-80, Mirror 16 类 | Boons 末期 ~12-18, Mirror 1 选 1 (A/B 互斥) | Hades Boon 5 rarity, SoT 3 rarity | rarity 不变 effect kind, 只放大数值 → SoT 借用此模式 |
| Hades 2 | Boons + Daedalus + Arcana | Arcana 25 张, Boons 类似 1 代规模 | Arcana Grasp pool ~10 起 cap | Arcana Grasp 类比 SoT 6 格, 两者都用"容量限制"逼取舍 | SoT 6 格 = "Arcana w/o Grasp 弹性" 简化版 |
| Inscryption | Sigils | 79 sigils | 单卡 ≤ 2-3 sigil, 卡组 20 张 → 池广 | Sigil 是卡牌 modifier, SoT 流派类符文是 L2 节点 modifier — 同构 | "Modifier 而非新机制"是降低复杂度的关键策略 |
| Noita | Perks + Spells | Perks ~70, Spells ~400 | Perks max 5 主线, Wand cap 26 | Noita 5 perks 几乎等价 SoT 6 格 | 5-7 cap 区间是 build 可读性临界 |
| Risk of Rain 2 | Items | 100+ items | **无 cap** (反例), 后期 50+ stack | RoR2 是 SoT 想避免的方向 | 无 cap → build identity collapse → SoT 必须有 cap |
| Cult of the Lamb | Tarot Cards | 85 cards | 单 run 卡数中等 (~6-10), 同卡不重复 | "同卡不重复" 模式适合 SoT 流派类 (符文不能堆 2 个一样) | locked-in proposed |

**额外 (非主请求, 但相关)**:
| Backpack Hero | Polyomino items | ~200 items | 3×3-5×5 grid, 形状取舍 | 形状取舍是 v2 演进方向, v1 SoT 不采用 | 反对纳入: 增加战棋 + grid 双重网格的认知负担 |
| Path of Exile 2 | Runes + Sockets | ~150 runes | 装备 socket 数量 (1-6) | PoE socket 与装备绑定, SoT 6 格独立于 L4 装备 | SoT 设计**刻意解耦** L4/L5, 避免 PoE 的 socket-link 复杂度 |

### 6.2 跨游戏共识

1. **Build-defining 系统的有效 cap 落在 5-12 范围内**, 7+ 必须有强力 trade-off 机制 (STS boss relic 的负面)。SoT 6 格落在最优区间。
2. **Rarity tier 不应改变 effect 类型, 只放大数值或解锁 unique condition** (Hades 模式)。SoT 采用 3 tier 而非 5 tier 是因为 SoT pool 较小 (预估 v1 pool ~50, 远小于 STS 287)。
3. **同符文不可重复 / Cult of the Lamb 模式** 是流派类符文的合理约束; 经济类可放宽允许重复 (本 stream 取折中: 流派类不重复, 经济类同 ID 可重复, 但同 ID stack ≤ 2)。
4. **解锁池而非数值强化** (Dead Cells 模式) 与 SoT meta horizontal-only 完全一致 — Stage 3 ADR 应明确写入。

### 6.3 引用 URL (≥ 8 个)

1. [Slay the Spire Relics Wiki](https://slay-the-spire.fandom.com/wiki/Relics)
2. [Slay the Spire 2 Relic Tier List 2026 — Switchblade Gaming](https://www.switchbladegaming.com/strategy-games/slay-the-spire-2-relic-tier-list/)
3. [Hades Boons Wiki](https://hades.fandom.com/wiki/Boons)
4. [Hades 2 Boons Wiki](https://hades.fandom.com/wiki/Boons/Hades_II)
5. [Hades 2 Daedalus Hammer — FextraLife](https://hades2.wiki.fextralife.com/Daedalus+Hammer)
6. [Inscryption Sigils Wiki](https://inscryption.fandom.com/wiki/Sigils)
7. [Noita Wand Capacity / Perks Wiki](https://noita.wiki.gg/wiki/Wands)
8. [Noita Extra Wand Capacity Perk](https://noita.wiki.gg/wiki/Extra_Wand_Capacity)
9. [Risk of Rain 2 Item Stacking Wiki](https://riskofrain2.fandom.com/wiki/Item_Stacking)
10. [Cult of the Lamb Tarot Cards Wiki](https://cult-of-the-lamb.fandom.com/wiki/Tarot_Cards)
11. [Backpack Hero Grokipedia overview](https://grokipedia.com/page/Backpack_Hero)
12. [Path of Exile 2 Runes & Sockets — TheGamer](https://www.thegamer.com/path-of-exile-2-poe2-runes-soul-cores-talismans-sockets-effects-guide/)
13. [Hades Mirror of Night — TheGamer](https://www.thegamer.com/hades-mirror-of-night-roguelite-progression/)
14. [Frostilyte: Arcana Cards meta in Hades 2](https://frostilyte.ca/2025/04/09/arcana-cards-meta-progression-in-hades-2-have-me-hooked/)

---

## 7. Town 经济兑换 Cost Curve

### 7.1 期望 run 内 town 兑换数量

**约束** (run-loop.md): 3 act × 10 stage = 30 stage, 每 stage 间有 Prep Phase。Town 在 Prep Phase 提供 "Rune Altar" 服务 (新 functional building, town-building.md 待 update — 不在本 stream scope, handoff)。

**目标分布**:
- Run 起始 (L1 赠): 1 个 (固定)
- Stage 普通战 random drop: 期望 1-2 个 / run (每 normal battle 5% drop)
- Stage 精英战: 期望 1 个 / run (每 elite ~30% drop)
- Stage Boss 保底: 1-3 个 (act 1/2/3 各 1, 100% drop, 每 act boss 后强制 1 选 1 from 3)
- Stage Special Event: 期望 0.5 个 / run
- **Town 兑换**: 期望 **1-2 个** / run (玩家主动决策的稳定补充)

**Run 末期总符文获取**: 4-6 个 (中位), 5-7 个 (上四分位), 极端可达 8-9 → 因此 6 格 cap 强制至少 1-3 次取舍, 这正是 build identity 决策密度的来源。

### 7.2 Town Rune Altar 兑换 cost (proposed)

```
Rune Altar (Functional Building, 待 town-building.md update)
  Lv1: 200G to build
    - 兑换 1 random Common rune (cost: 100G + 1 鞋文碎片 / per stage limit 1)
  Lv2: 400G to upgrade
    - Common 兑换可见 3 选 1 (cost: 150G)
    - Rare 兑换 random (cost: 300G + 3 符文碎片 / per stage limit 1)
  Lv3: 800G to upgrade
    - Common/Rare 都可见选择
    - Mythic 兑换 random (cost: 600G + 1 Mythic 残片 / 全 run limit 1, 通过 boss 击败积累)
```

### 7.3 Cost Curve 视觉化 (HTML §5 折线图)

| Stage | 累积 Gold (中位) | 玩家可负担兑换次数 (Lv1 Altar 已建) |
|---|---|---|
| Stage 5 (Act 1 中段) | 250G | 0 (建 Altar 占用) |
| Stage 10 (Act 1 boss) | 500G | 1-2 次 |
| Stage 15 (Act 2 中段) | 1100G | 2-3 次 |
| Stage 20 (Act 2 boss) | 1700G | 3-4 次 |
| Stage 25 (Act 3 中段) | 2400G | 4-5 次 (但玩家通常已升 Altar Lv3, 留 Mythic 兑换) |
| Stage 30 (Final Boss) | 3200G | — |

**取舍 vs Town Building 经济**: 玩家面临经典 town-building.md §"Strategic Depth" 的两难——把 200-1400G 投入 Rune Altar 还是 Watchtower / Weapon Shop。这是本系统设计目标 — Rune Altar 是 town 经济的**新决策轴**, 不是固定上锁服务。

---

## 8. UI 概念 (HTML §1 草图)

```
6 格 Layout (proposed): 2 row × 3 col, 显示在战斗 HUD 右下
  ┌─────┬─────┬─────┐
  │ R1  │ R2  │ R3  │
  ├─────┼─────┼─────┤
  │ R4  │ R5  │ R6  │
  └─────┴─────┴─────┘

每格元素:
  - 中央 icon (经济类 = 几何符号; 流派类 = 元素图腾)
  - 左下角 tier 标识 (○ Common / ◇ Rare / ★ Mythic)
  - 右上角 stack 数 (经济类同 ID 可 stack, 流派类不可)
  - hover 显示完整 tooltip + synergy 高亮
```

详见 HTML 视觉。

---

## 9. Open Questions for Stage 3

1. **Q-D5-1 (高优)**: 流派类符文的"cross-class fallback × 0.6" 数值是否合理? 测试方案: Mage 拿到 archer 符文实战 viable 程度模拟。
2. **Q-D5-2**: Mythic 必带负面 trade-off 是否过度? 是否允许"纯正面 Mythic" 占 Mythic 池 30%? 参考 STS rare relic 多数无 trade-off。
3. **Q-D5-3**: Run 起始 L1 赠送 1 符文是 random 还是玩家从 3 选 1? D1 stream handoff 给定后定。
4. **Q-D5-4**: Town Rune Altar 是否要求**必须先建** weapon/armor shop (作为 prerequisite)? 还是独立? 影响 town tech tree 平衡。
5. **Q-D5-5**: 同 ID 经济类符文 stack ≤ 2 是否够? 还是 stack ≤ 3 让"全力量流"成立? 平衡 issue。
6. **Q-D5-6 (与 D2 强 handoff)**: D2 stream 在 prune L2 时, 哪些"behavior modifier 类 passive" 应迁出 L2 进入 L5 流派类池? 本 stream §5.3 提议的边界规则需要 D2 配合执行。
7. **Q-D5-7 (与 D1 强 handoff)**: L1 meta 解锁池里, "解锁更多 rune 进入随机池" 是否是主要的 horizontal 解锁内容? L1 解锁数量 / 节奏需要 D1 协调。

---

## 10. Handoff

### 给主 agent / Stage 3 Synthesis

- **不立 ADR** (consensus §6 stream rule); Stage 3 用户确认后再立 `02-Development/Decisions/adr-2026-05-XX-runes-system.md` 或 `01-Game-Design/Core-Systems/runes-system.md`。
- 关键 locks (用户确认后): 6 格硬上限 / 2 archetype / 3 tier / L2 base + L5 modifier 边界 / town reroll + scrap, 拒绝合成。
- 不修改 town-building.md, 但 handoff: 应新增 "Rune Altar" functional building 章节 (Stage 3 落地)。

### 给 D2 stream (L2 simplification)

§5.3 提议的"L2 = base mechanic, L5 = modifier" 边界规则需要 D2 在 prune 决策中执行。具体是: D2 应识别 talent-tree-design.md §4.2 中的"behavior modifier passive" 类节点, 迁入本 stream 的流派类池 (§3.1 表为初始 14 个示例, D2 prune 时可补充)。

### 给 D1 stream (L1 meta)

L1 horizontal 解锁的内容应包括"扩展 rune pool"——具体哪些 rune 是初始可用 vs meta 解锁后入池, 需要 D1 提议解锁数量曲线 (e.g. 初始 30 rune 可用, 完成 1 run 解锁 +5, 直到 ~50 rune 全开)。

### 给 D4 stream (L4 装备)

§5.3 末段提议 L4 装备词缀 (e.g. STR+5) 与 L5 经济类符文 (e.g. STR+3) 在数值类型上重叠但**机制定位不同** (L4 = slot-bound RNG, L5 = run-stable plan)。D4 设计装备词缀深度上限时需考虑此分工边界。

---

*Generated: S3-side-sot 2026-05-10. Stream D5 (Mercury core design). Authority: stage2_proposal — 待 Stage 3 用户确认后转 locked。*
