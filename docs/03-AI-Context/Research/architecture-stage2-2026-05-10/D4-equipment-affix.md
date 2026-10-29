---
stream: D4
title: L4 Equipment + Affix Design Space
session: S3-side-sot
date: 2026-05-10
parent_consensus: ../Active-Context/architecture-consensus-v2.md
status: stage2_proposal
visual_companion: D4-equipment-affix.html
---

# D4 — L4 装备 + 词缀设计空间

> **TL;DR**: L4 = 武器 + 防具. 9 武器 type + 4 防具 type. 4 rarity tier (Common / Uncommon / Rare / Unique). 5 词缀大类 (stat / on-hit / on-crit / conditional / set-flavor). **核心硬约束: 任何 L4 词缀效果 ≤ ±15% 单一 stat 或 ≤ 1 个有限触发条件; 不允许"改变职业形态"的效果 (后者归 L5 流派类符文)**. 单 run 期望 ~12-18 件装备 (random drop + town stable + boss reward). town 给玩家 mid-tier 稳定底, drop 给峰值惊喜, boss 给 unique flavor.

可视化: [D4-equipment-affix.html](D4-equipment-affix.html)

---

## 1. 设计目标 + 硬约束 (consensus 派生)

### 来自 consensus v2 的硬约束

| 约束 | 出处 | D4 兑现方式 |
|---|---|---|
| L4 不承担 build-defining | §1, §7 (locked term) | 任何词缀效果数值 + 触发深度有上限 (§4) |
| L4 与 L5 协同但不重复 | §4 跨层耦合矩阵 | 词缀只做"风味放大"(火武器 × 燃烧符文), 不做"形态改变" (§5) |
| L4 run-reset | §1 reset 列 | 每 run 装备清零, town 提供 mid-tier 稳定基线避免空仓库 |
| 玩家不会基于装备构筑 | 用户原话 | 词缀深度 cap (§4) + cost curve 让玩家不能 farm 出 build-defining 词条 |

### 用户原话拆解

| 用户原话 | 设计映射 |
|---|---|
| "多数装备: 附加额外收益, 没有也不影响玩法" | Common / Uncommon = 仅 stat 词缀, 卸下能玩 |
| "少数: 较强增益, 中等影响玩法" | Rare / Unique = on-hit / conditional 词缀, 改变战术取舍但不改变 build 路线 |
| "玩家不会基于装备构筑" | 词缀池随机 + run-reset → 不能围绕特定词缀规划; town 仅保证"有装备", 不保证"有词缀" |

### 设计目标三角

1. **战术层 (per-fight)**: Rare/Unique 词缀提供战斗中的 micro-decision (e.g. "对低血敌人 +20% damage" → 集火低血)
2. **风味层 (per-run)**: Unique 装备给 run 一个"性格" (e.g. 冰之弓 + run 拿到燃烧符文 → 矛盾感, 玩家选择装备 vs 符文)
3. **空白层 (per-build)**: 不承担 build-defining → 玩家任何 build 在零装备下都能跑

---

## 2. 武器类型矩阵

### 2.1 武器类型清单 (9 种)

| ID | 武器 type | 攻击属性 | 攻击方式 | 射程 | 基础 might | proficiency 风格 |
|---|---|---|---|---|---|---|
| `sword` | Sword | physical | melee | 1 | 中 (8-12) | 平衡, 支持 follow-up |
| `axe` | Axe | physical | melee | 1 | 高 (10-16) | 重击, 偶发 area |
| `spear` | Spear | physical | melee | 1-2 | 中 (8-12) | 刺击, range 2 反制 |
| `bow` | Bow | physical | ranged | 2-3 | 中 (7-11) | 标准弓, ZOC 受控 |
| `crossbow` | Crossbow | physical | ranged | 2-4 | 高 (9-13) | 长射程, SPD penalty |
| `tome` | Tome | magical | ranged/area | 1-3 | 中 (基础+魔法 amplification) | 魔法主, 元素载体 |
| `staff` | Staff | magical | ranged | 1-2 | 中 (基础+治疗 amplification) | 神圣/治疗向 |
| `dagger` | Dagger | physical | melee | 1 | 低 (5-8) | 高 CRIT, 高 SPD |
| `dual_sword` | Dual Sword (off-hand) | physical | melee | 1 | 低 (50%) | Blade Master 专属, 见 class-system |

**注**: shield (盾牌) 不算武器 type, 算防具特殊 slot — Knight 副手. dual_sword 不在普通掉落池中 (Blade Master 解锁后专属铁匠铺给).

### 2.2 武器 × 职业 proficiency 矩阵 (v1 5 职业)

> v1 = Soldier(=Mercenary) / Archer / Mage / Knight / Cleric. 数据来源: class-system.md.

| 武器 \ 职业 | Soldier | Archer | Mage | Knight | Cleric |
|---|---|---|---|---|---|
| sword | Y | — | — | Y | — |
| axe | Y | — | — | Y | — |
| spear | Y | — | — | Y | — |
| bow | Y | Y | — | — | — |
| crossbow | Y | — | — | — | — |
| tome | — | — | Y | — | — |
| staff | — | — | — | — | Y |
| dagger | Y | — | — | — | — |
| dual_sword | — | — | — | — | — |

**Y** = 可装备, **—** = 不可装备. (8 base class 完整版扩展见 §2.3)

### 2.3 8 base class 扩展 (v2 阶段)

| 武器 \ 职业 | Sword | Merc | Arch | Artif | Mage | Knight | Hunter | Priest |
|---|---|---|---|---|---|---|---|---|
| sword | Y | Y | — | — | — | Y | Y | — |
| axe | — | Y | — | — | — | Y | — | — |
| spear | — | Y | — | — | — | Y | — | — |
| bow | — | Y | Y | — | — | — | Y | — |
| crossbow | — | Y | — | — | — | — | — | — |
| tome | — | — | — | — | Y | — | — | — |
| staff | — | — | — | — | — | — | — | Y |
| dagger | Sword=Y | Y | — | — | — | — | Y | — |
| dual_sword | Blade Master only | — | — | — | — | — | — | — |
| (artif-tool) | — | — | — | TBD | — | — | — | — |

**Swordsman = 仅 sword + dagger + dual_sword** (与 class-system.md "Swords only" 一致, dagger 视为短剑亚 type, dual_sword 是 Blade Master 解锁).

> **Open Question (Stage 3)**: Artificer 武器 type 在 class-system.md 标 TBD. D4 提议: 引入 `artif-tool` (扳手/手摇钻类), physical melee 1, 低 might 高 SPD, 兼具修建筑功能. 待 D5 + D2 确认.

---

## 3. 防具类型矩阵

### 3.1 防具类型清单 (4 种)

| ID | 防具 type | DEF 基础 | RES 基础 | SPD penalty | 备注 |
|---|---|---|---|---|---|
| `light` | Light Armor (皮甲/法袍) | 低 (1-3) | 中 (2-5) | 0 | 法师/弓手/牧师默认 |
| `medium` | Medium Armor (锁子甲) | 中 (3-6) | 中 (2-4) | -1 SPD | Mercenary / Hunter |
| `heavy` | Heavy Armor (板甲) | 高 (6-10) | 低 (1-3) | -2 SPD | Knight 专属 |
| `shield` | Shield (副手, 不挤占主武器槽) | +DEF (3-6) | — | -1 SPD | Knight only, 副手槽 |

**注**: shield 与 main hand weapon 是不同 slot. Knight 装备 shield 不影响 main hand sword/axe/spear. 其他职业 shield slot 为空.

### 3.2 防具 × 职业 proficiency 矩阵 (v1 5 职业)

| 防具 \ 职业 | Soldier | Archer | Mage | Knight | Cleric |
|---|---|---|---|---|---|
| light | Y | Y | Y | — | Y |
| medium | Y | Y | — | Y | — |
| heavy | — | — | — | Y | — |
| shield | — | — | — | Y | — |

> Knight 不可装备 light (角色定位); Mage 不可装备 medium/heavy (lore + balance).

### 3.3 8 base class 扩展

| 防具 \ 职业 | Sword | Merc | Arch | Artif | Mage | Knight | Hunter | Priest |
|---|---|---|---|---|---|---|---|---|
| light | Y | Y | Y | Y | Y | — | Y | Y |
| medium | Y | Y | Y | — | — | Y | Y | — |
| heavy | — | Y | — | — | — | Y | — | — |
| shield | — | — | — | — | — | Y | — | — |

---

## 4. 稀有度 tier + 词缀槽

### 4.1 4 tier 框架

| Tier | 颜色 | 词缀槽 | 词缀强度 cap | Drop 频率 (run 内) | 来源 |
|---|---|---|---|---|---|
| **Common** (普通) | 白 | 0 | base stat only | ~50% | 普通战斗 / 商店 Lv1 |
| **Uncommon** (优秀) | 绿 | 1 (随机 stat) | ≤ ±10% 单 stat | ~30% | 普通战斗 / 商店 Lv1-2 |
| **Rare** (稀有) | 蓝 | 2 (1 stat + 1 effect) | ≤ ±15% 单 stat / ≤ 1 触发条件 | ~15% | Elite / 商店 Lv2-3 / 事件 |
| **Unique** (传奇/暗金) | 橙 | 1 fixed effect + 1 fixed stat | 固定预设组合, 仍受 §4.3 上限 | ~5% | Boss / 隐藏事件 / 商店 Lv3 顶层 |

**期望分布 (per run, ~12-18 装备总掉落)**:
- Common: ~6-9 (基础垫底)
- Uncommon: ~4-5
- Rare: ~2-3
- Unique: ~0-2 (Boss 钩子)

### 4.2 词缀槽规则

```
Common:    [base might / DEF only]
Uncommon:  [base] + [1 prefix-或-suffix]
Rare:      [base] + [1 prefix] + [1 suffix]
Unique:    [base override] + [fixed prefix] + [fixed suffix] + (optional flavor tag)
```

**prefix vs suffix 拆分** (借鉴 PoE):
- prefix = stat 类 (+STR, +HP, +DEF)
- suffix = effect 类 (on-hit, conditional, on-crit)
- 互斥池: 同一 affix slot 不能装同类两次

### 4.3 词缀强度硬上限 (D4 核心硬约束)

> **任何 L4 词缀必须满足以下 BOTH**:
>
> 1. **数值上限**: 单词缀对单 stat 的修改 ≤ ±15% (Rare) / ≤ ±20% (Unique 固定词条)
> 2. **触发深度上限**: ≤ 1 个有限触发条件 (e.g. "on-crit", "vs 低血敌人", "回合开始时"), 禁止链式触发 (禁止 "on-crit 触发 on-hit 再触发 conditional")
>
> **违反上限 = 转移到 L5 流派类符文管辖**.

数值锚点 (与 class-system §Equipment Bonus Reference By Stage Progress 对齐):

| Stage | 武器 base might | Common 总加成 | Rare 词缀总加成 | Unique 总加成 |
|---|---|---|---|---|
| Early (1-5) | +2~4 | ≤ +5% stat | ≤ +12% stat + 1 effect | ≤ +15% stat + 1 effect (固定) |
| Mid (6-15) | +5~8 | ≤ +8% stat | ≤ +15% stat + 1 effect | ≤ +18% stat + 1 effect |
| Late (16-25) | +9~14 | ≤ +10% stat | ≤ +15% stat + 1 effect | ≤ +20% stat + 1 effect |
| Endgame (26-30) | +12~18 | ≤ +12% stat | ≤ +15% stat + 1 effect | ≤ +20% stat + 1 effect |

> 上限不随 stage 同比扩张, 因为 L4 不能参与 endgame build-defining. endgame 数值膨胀靠 L3 成长 + L5 符文承担.

---

## 5. 词缀类型分类 (5 大类)

### 5.1 五大类总览

| 大类 | 性质 | 例子 | 强度 |
|---|---|---|---|
| **Stat Boost** (基础加成) | 直接修改 stat | +5 STR, +10% HP, -1 SPD penalty | 低-中 |
| **On-Hit** (击中触发) | 攻击命中时触发, 受 hit-rate 限制 | "10% 概率燃烧 1 回合", "每次命中 +1 HP 吸取" | 中 |
| **On-Crit** (暴击触发) | 暴击时触发, 受 crit-rate 限制 | "暴击 +20% damage", "暴击命中后下回合 +SPD" | 中 |
| **Conditional** (条件触发) | 满足战术条件触发 | "对低血敌人 +15% damage", "森林地形 +HIT", "回合开始时 +1 SPD" | 中-高 |
| **Set/Flavor** (套装/风味) | Unique 专属, 固定预设组合 | "冰之弓: ranged + 25% 概率结冰" | 中-高 |

### 5.2 各类词缀深度上限 (硬约束 §4.3 派生)

| 大类 | 数值上限 | 触发深度 | 禁止行为 |
|---|---|---|---|
| Stat Boost | ≤ ±15% (单 stat) | 0 (常驻) | 禁止同时加 3+ stat (那是 set bonus = L5 域) |
| On-Hit | ≤ 15% chance, ≤ 1 turn duration | 1 (on_hit) | 禁止 on_hit 触发 on_hit 链 |
| On-Crit | ≤ +20% damage, ≤ 1 turn duration | 1 (on_crit) | 禁止 on_crit 触发流派 (e.g. 暴击转换 ATK 为 MAG = L5) |
| Conditional | ≤ ±15%, 1 触发条件 | 1 (conditional) | 禁止多重 AND 条件 |
| Set/Flavor | Unique 固定预设, 仍 ≤ 上面 4 类 cap | 最多 1 触发 + 1 stat | 禁止"改变 base attack type" (e.g. 武器把 melee 改 ranged = L5 流派类符文域) |

### 5.3 50 词缀模板示例 (10 per category, run 池)

> 详细列表见 §附录 A. 这里仅列每类各 2 例:

| 大类 | 例 1 | 例 2 |
|---|---|---|
| Stat | "锋利的" +10% phys_atk | "坚固的" +8 HP |
| On-Hit | "燃烧的" 10% 烧 1 回合 (5 dmg/turn) | "吸血的" on-hit 回 5 HP |
| On-Crit | "致命的" 暴击 +15% dmg | "迅捷的" 暴击后 +1 SPD 1 回合 |
| Conditional | "猎手的" 对低血 (<30%) +15% dmg | "山地的" 山地地形 +5 DEF |
| Set/Flavor | "Frostfang Bow" ranged + 20% 结冰 1 回合 | "Sage's Tome" tome + 火元素法术 +10% might |

---

## 6. 与 L5 符文的边界 (build-defining 红线)

### 6.1 红线定义

> **L4 装备词缀**: 在已确定的职业形态内, 提供数值/小幅触发的微调.
> **L5 流派类符文**: 改变职业的形态/玩法模式 (consensus §7 锁死定义).

### 6.2 边界判定矩阵 (一票否决)

| 效果范畴 | L4 允许? | L5 流派类允许? | 判定理由 |
|---|---|---|---|
| +X% stat (X ≤ 15) | ✓ | ✓ (经济类) | 量级安全, L4 = 单装备, L5 = 6 格累加 |
| 元素属性附加 (火/冰) | ✓ (Unique 限定) | ✓ | L4 = 单一元素载体 (一把火剑); L5 = 元素生态 (燃烧扩散 = L5 流派类) |
| 改变 base attack range | ✗ | ✓ | 改变形态 → L5 |
| 改变 base damage type (phys → mag) | ✗ | ✓ | 改变形态 → L5 |
| 解锁新 skill | ✗ | ✓ | L5 流派类典型行为 |
| on-crit 触发 follow-up | ✗ | ✓ | 链式触发 → L5 流派类 |
| 改变 action 经济 (extra action) | ✗ | ✓ | 形态级改动 → L5 |
| Conditional buff (single) | ✓ | ✓ | L4 浅, L5 深 |

### 6.3 协同矩阵 (L4 × L5 风味放大, consensus §4 已锁)

| L4 装备 | L5 符文 | 协同效果 (玩家感知) |
|---|---|---|
| 火属性 tome (Unique) | 燃烧扩散符文 (流派类) | 火 tome 点燃 → 符文扩散 → 风味放大 |
| 冰之弓 (Unique) | 冻结即时结算符文 (流派类) | 冰弓 freeze → 符文即时秒杀 |
| 吸血武器 (Rare) | 经济类 +HP 符文 | 双重续航, stay-within-class-model |
| 锋利武器 (Rare, +10% atk) | 经济类 +ATK 符文 | 数值叠加, 无新机制 |

**关键判定**: L4 是"载体" (carrier), L5 是"生态" (ecosystem). L4 单装备只放大 1 步, L5 把这 1 步复制成系统.

---

## 7. 生成规则

### 7.1 Run 内装备获取 timeline

```
Run start (Stage 1)
├── L1 起始装备: 1 武器 + 1 防具 (Common, 由 class 决定 base type)
│
├── Stages 1-10 (Act 1)
│   ├── 普通战斗 drop: ~3-5 件 (Common 60%, Uncommon 35%, Rare 5%)
│   ├── Elite drop: ~1-2 件 (Uncommon 50%, Rare 45%, Unique 5%)
│   ├── Town shop Lv1-2: 稳定供应 Common + Uncommon, 价格固定
│   └── Boss drop: 1 件 Rare 或 Unique (Boss 钩子)
│
├── Stages 11-20 (Act 2): drop quality 上调一档
│
├── Stages 21-30 (Act 3): Unique drop 概率 ~10%
│
└── 单 run 期望 ~12-18 件总掉落 (含 town 购入)
    ├── Common: ~6-9
    ├── Uncommon: ~4-5
    ├── Rare: ~2-3
    └── Unique: ~0-2
```

### 7.2 Town 系统的"稳定供应"角色

> **用户原话**: "town 给玩家稳定性"

设计兑现:

| Town 建筑 | 角色 | 反 build-defining 设计 |
|---|---|---|
| Weapon Shop Lv1 | Common 武器, 全 type 全职业可用, 价格固定 | 玩家保底装备 |
| Weapon Shop Lv2 | Uncommon 武器, 词缀**随机**滚 (玩家不能挑词缀) | 防止 farm 特定词缀 |
| Weapon Shop Lv3 | Rare 武器, 每 stage 限购 1 件 + 词缀**随机** | 防止 stack rare |
| Armor Shop (同上 3 tier) | 同上 | 同上 |
| (NO Reroll Workbench) | — | **不引入 reroll 机制** (违反"不基于装备构筑"原则) |

### 7.3 Boss reward 的"风味钩子"角色

> Boss drop = 每 Act Boss 固定 unique 池中随机 1 件. unique 不能 farm (Boss 一 run 一次).

每 Act 设计 ~3-4 个 unique 池, run 选 1:
- Act 1 Boss: ~3 unique (低 stage tier)
- Act 2 Boss: ~3 unique (mid stage tier)
- Act 3 Final Boss: ~4 unique (endgame tier, 含跨 run 解锁版本待 L1 D1 决定)

### 7.4 反 farm 设计

| 反 farm 机制 | 出处 |
|---|---|
| 词缀**随机**滚, 玩家不能选 | §7.2 |
| 不引入 reroll workbench | §7.2 |
| Unique 来源限定 (Boss/事件), 不进 drop 池 | §7.3 |
| run-reset 词缀池 | consensus §1 |
| Town 限购 (Lv3 Rare 每 stage 1 件) | §7.2 |

**所有以上机制综合保证**: 玩家**无法**预先围绕特定词缀规划 build → 验证 consensus "L4 不承担 build-defining".

---

## 8. 业内 reference 对照

### 8.1 Path of Exile (借鉴: prefix/suffix 互斥 + tier)

- **采纳**: prefix (stat) / suffix (effect) 互斥池, 防止同类 stack
- **采纳**: tier 数值范围, 高 tier 数值更大
- **不采纳**: 6 mod / item — D4 cap 在 2 词缀 (Rare) 防止深度爆炸
- **不采纳**: crafting / divine orb 重 roll — 违反"装备不构筑"原则
- 来源: [PoE Wiki - Modifier](https://www.poewiki.net/wiki/Modifier), [Mobalytics PoE 2 Item Modifiers](https://mobalytics.gg/poe-2/guides/poe-2-item-modifiers-explained)

### 8.2 Diablo 2 Unique Items (借鉴: Unique 固定词条 + Boss 钩子)

- **采纳**: Unique 词条 fixed (玩家不能 reroll), 每件 unique 是设计师手工组合
- **采纳**: Unique 是 build flavor, 不是 build core (D2 build 仍以 skill tree 为主, 类似 SoT L2 + L5)
- **不采纳**: D2 set bonus 6 件套 — set bonus 复杂度过高且容易 build-defining, D4 砍掉
- 来源: [Maxroll D2 Uniques](https://maxroll.gg/d2/items/unique-items), [D2 Wiki Uniques](https://diablo-archive.fandom.com/wiki/Unique_Items_(Diablo_II))

### 8.3 Dead Cells (借鉴: gear level + affix slot 上限 + roguelite reset)

- **采纳**: affix 数与 gear level 关联, 高 level 词缀槽多
- **采纳**: minor affix (绿 stat) / major affix (effect) 分类 — 对应 D4 stat / on-hit-on-crit 分类
- **采纳**: roguelite reset, 不存在跨 run 装备
- **不采纳**: Dead Cells 6 affix 上限 — D4 cap 在 2 (Rare 等级), 因为 SoT 是 turn-based 战棋, 数值复杂度容忍度低
- **不采纳**: Legendary 颜色无关性 (scales with highest stat) — D4 unique 仍受 base proficiency 限制
- 来源: [Dead Cells Wiki - Affixes](https://deadcells.wiki.gg/wiki/Affixes), [Dead Cells Wiki - Gear](https://deadcells.wiki.gg/wiki/Gear)

### 8.4 Borderlands Legendary (借鉴: unique = 风味 + 玩法变体, 但不构筑 build)

- **采纳**: legendary "red text" 风味描述 + 1 显著效果, 不串多个机制
- **采纳**: 同 base type 但有特色 (e.g. "燃烧弓" vs "标准弓")
- **不采纳**: BL legendary 触发链 (e.g. 击杀回弹) — 违反 D4 触发深度 ≤ 1 上限
- 注: Borderlands 中 legendary 实际上 **是** build-defining (多数 endgame build 围绕 legendary), 这是 D4 **明确反对** 的方向. D4 借的是"风味命名 + 单一显著效果"的形态, 不借"围绕 legendary 构筑"的核心循环.

### 8.5 Hades Boon (反向参考: 我们 NOT 这么做)

- Hades boon = 强 build-defining (Hades 主玩法循环). 我们 NOT 这样, 这部分给 L5 流派类符文.
- 反过来说: D4 装备 ≈ Hades 的 weapon aspect (固定 4 个/武器, 不可换, run 内不变), 不是 boon.

---

## 9. 数据 schema (草案)

### 9.1 装备 JSON

```json
{
  "id": "frost_fang_bow",
  "name": "Frostfang Bow",
  "tier": "unique",
  "slot": "main_hand",
  "weapon_type": "bow",
  "base_might": 9,
  "base_stats": { "phys_atk": 9, "hit": 5, "crit": 8 },
  "range": { "min": 2, "max": 3 },
  "attack_method": "ranged",
  "element_type": "physical",
  "proficiency_required": ["bow"],
  "affixes": [
    { "id": "frostbite_chance", "type": "on_hit", "chance": 20, "effect": "freeze", "duration": 1 },
    { "id": "spd_bonus", "type": "stat", "stat": "SPD", "value": 1 }
  ],
  "flavor_text": "The string is colder than the arrows it draws."
}
```

### 9.2 词缀 JSON

```json
{
  "id": "sharpened",
  "name": "Sharpened",
  "category": "stat",
  "slot": "prefix",
  "stat": "phys_atk",
  "value_range": { "min": 5, "max": 10 },
  "applicable_types": ["sword", "axe", "spear", "dagger", "bow", "crossbow"],
  "tier_cap": "rare"
}
```

### 9.3 文件结构

```
data/
├── equipment/
│   ├── weapons/
│   │   ├── common/      # tier=common 模板
│   │   ├── uncommon/
│   │   ├── rare/
│   │   └── unique/      # 手工设计的 Unique
│   ├── armors/          # 同上结构
│   └── affixes/
│       ├── stat.json
│       ├── on_hit.json
│       ├── on_crit.json
│       ├── conditional.json
│       └── flavor.json   # Unique 专属
```

---

## 10. Stage 3 留待问题 (open questions)

| OQ | 描述 | 优先级 |
|---|---|---|
| **OQ-D4-1** | Artificer 武器 type? 提议 `artif-tool`, 待 D2 + D5 确认 | P1 |
| **OQ-D4-2** | shield slot 是否给 Knight 之外开放 (e.g. Mercenary 副手 shield)? D4 现版本仅 Knight, 待 v2 扩展 | P2 |
| **OQ-D4-3** | Unique 跨 run 解锁 (类似 D2 Annihilus / Anni 永久) — 是否破坏 horizontal-only? D1 须确认 | P1 |
| **OQ-D4-4** | "改变 attack_method" (e.g. ranged 武器临时变 melee) 算 L4 还是 L5? D4 提议 L5 (形态改动), 但 Elven Archer "近战可用弓" 是 L2 talent 解锁的, 边界模糊 | P1 |
| **OQ-D4-5** | 词缀 50 条具体平衡数值, 留 stage 3 数值组 prototype | P2 |
| **OQ-D4-6** | Town shop reroll 是否完全禁? D4 现禁, 但允许 "限购 1 次/stage 的命定 rare" 是否 OK? | P2 |
| **OQ-D4-7** | dual_sword 是否进 unique 池, 还是仅由 Blade Master talent 给? D4 现倾向后者 (与 class-system 一致) | P2 |

---

## 附录 A: 50 词缀模板 (示意, 非最终平衡)

### A.1 Stat Boost (10 个, prefix)

| ID | Name | Stat | Value | applicable_types |
|---|---|---|---|---|
| sharp_p | "锋利的" | phys_atk | +5~10 | melee/ranged 武器 |
| keen_p | "敏锐的" | DEX | +1~3 | 武器 |
| heavy_p | "沉重的" | STR | +1~3 | melee 武器 |
| arcane_p | "奥术的" | mag_atk | +5~10 | tome / staff |
| swift_p | "迅捷的" | SPD | +1~2 | 武器 |
| sturdy_p | "坚固的" | HP | +5~10 | 防具 |
| guardian_p | "守护的" | DEF | +2~5 | medium/heavy 防具 |
| warding_p | "护佑的" | RES | +2~5 | light 防具 + shield |
| vigorous_p | "充沛的" | HP | +8~15 | 防具 |
| precise_p | "精准的" | hit | +3~8 | 武器 |

### A.2 On-Hit (10 个, suffix)

| ID | Name | Trigger | Effect | applicable_types |
|---|---|---|---|---|
| burning_s | "燃烧的" | on_hit | 10% chance burn 1 turn (3-5 dmg/turn) | 武器 |
| chilling_s | "冰寒的" | on_hit | 10% chance -2 SPD 1 turn | 武器 |
| shocking_s | "电击的" | on_hit | 10% chance stun 0.5 turn | 武器 |
| vampiric_s | "吸血的" | on_hit | restore 3-5 HP | melee 武器 |
| poisoning_s | "剧毒的" | on_hit | 15% chance poison 2 turns | 武器 |
| draining_s | "汲取的" | on_hit | 5% chance -1 stat 1 turn | 武器 |
| sundering_s | "破甲的" | on_hit | 10% chance -2 DEF 1 turn | melee 武器 |
| silencing_s | "沉默的" | on_hit | 5% chance silence 1 turn | tome / staff |
| dazing_s | "眩晕的" | on_hit | 5% chance -hit 1 turn | 武器 |
| bleeding_s | "流血的" | on_hit | 10% chance bleed 2 turns | melee 武器 |

### A.3 On-Crit (10 个, suffix)

| ID | Name | Trigger | Effect | applicable_types |
|---|---|---|---|---|
| deadly_s | "致命的" | on_crit | +15% damage on this crit | 武器 |
| swift_strike_s | "迅击的" | on_crit | +1 SPD next turn | 武器 |
| chained_s | "连锁的" | on_crit | +1 follow-up chance (cap 100%) this turn | melee 武器 |
| pyric_s | "炽热的" | on_crit | guarantee burn 1 turn | 武器 |
| crushing_s | "粉碎的" | on_crit | -3 DEF on target 1 turn | melee 武器 |
| piercing_s | "穿透的" | on_crit | ignore 50% DEF this crit | ranged 武器 |
| empowered_s | "赋能的" | on_crit | +5 next attack damage | 武器 |
| critical_focus_s | "专注的" | on_crit | +5 crit_rate next turn | 武器 |
| shocking_crit_s | "雷霆的" | on_crit | guarantee stun 0.5 turn | 武器 |
| exhausting_s | "消耗的" | on_crit | -1 SPD on target 1 turn | 武器 |

### A.4 Conditional (10 个, suffix)

| ID | Name | Condition | Effect |
|---|---|---|---|
| hunter_s | "猎手的" | target HP < 30% | +15% damage |
| executioner_s | "处刑的" | target HP < 50% | +10% crit rate |
| forest_s | "山林的" | self in forest | +5 DEF |
| highland_s | "高山的" | self on mountain | +5 hit |
| ambusher_s | "伏击的" | first attack of turn | +10% damage |
| morning_s | "晨光的" | turn 1-3 | +5 ATK |
| desperate_s | "绝望的" | self HP < 30% | +15% damage |
| guardian_s | "守护的" | adjacent ally | +3 DEF |
| solo_s | "孤胆的" | no adjacent ally | +5 ATK |
| holy_s | "神圣的" | vs undead/demon enemy | +20% damage |

### A.5 Set/Flavor (10 个, Unique 专属固定组合)

| ID | Name | Slot | Fixed Effect | Tier |
|---|---|---|---|---|
| frost_fang_bow | "Frostfang Bow" | bow | ranged + 20% freeze 1 turn + SPD +1 | mid |
| sage_tome | "Sage's Tome" | tome | tome + fire/ice/air spell +10% might | mid |
| oath_blade | "Oath Blade" | sword | sword + on_kill +5 HP heal + DEX +2 | early |
| guardian_aegis | "Guardian Aegis" | shield | shield + adjacent ally +2 DEF + DEF +3 | mid |
| stalker_bow | "Stalker Bow" | bow | bow + stealth approach +20% dmg first hit + SPD +1 | mid |
| holy_staff | "Cleric Staff of Light" | staff | staff + heal +20% + RES +3 | mid |
| berserker_axe | "Berserker's Axe" | axe | axe + self HP <50% +20% dmg + STR +2 | late |
| dragoon_spear | "Dragoon Spear" | spear | spear + range 1-3 (1 extra) + STR +1 | late |
| arcane_dagger | "Arcane Dagger" | dagger | dagger + crit triggers minor mag_atk burst + DEX +2 | mid |
| bulwark_plate | "Bulwark Plate" | heavy | heavy + adjacent ally damage taken -10% + HP +10 | late |

---

## 11. Token / 预算 / Self-check

- **Token 估算**: 本 stream 约 25k token (含 reads + 2 file write + searches)
- **范围验证**: ✓ 仅写 2 个目标文件; ✗ 无 git 操作; ✗ 未改 class-system.md
- **consensus 一致性**: ✓ §1 L4 不 build-defining; ✓ §4 L4 × L5 协同矩阵; ✓ §7 build-defining locked term
- **可视化伴侣**: D4-equipment-affix.html (3 SVG 图)

---

*Generated: S3-side-sot Stage 2, Stream D4. 2026-05-10. By Mercury core `design`.*
