---
stream: D3
title: L3 Character Growth + Advancement Rate Table
session: S3-side-sot
date: 2026-05-10
parent_consensus: ../Active-Context/architecture-consensus-v2.md
status: stage2_proposal
visual_companion: D3-character-growth.html
---

# D3 — L3 人物成长 + 转职 Growth Rate 表

> ⚠️ **设计层已变更、本文档待同步（2026-06-16｜剑圣 v4.3 / rules v9）——同步前勿据此实现**：
> 1. **成长属性 7 → 6**：LCK 移出成长（改固定，剑士/剑圣=B）。§1.2 各职业 LCK growth_rate 及「7 个 growable stat」表述**待改为 6**（HP/STR/MAG/DEX/DEF/RES）。
> 2. **OQ-D3-1 解决为「否」= SPD 全程固定、不解禁成长**：§2.4 的 `sword_saint` 占位 focus 含 `SPD-on-advance` **已作废**；剑圣转职不解禁 SPD 成长，剑圣 SPD=A 固定值（剑士 B），成长 delta 仅 DEX A→S（机制驱动型转职，低于本文 +30~60 预算，属已接受的例外）。
> 正本：`data/talent-tree/v2/final-design.md`（第七章）/ `rules.md`（R3.14/R2.8）。

> **TL;DR**: SoT L3 成长采用 **简化 FE Three Houses 加性模型** (class baseline + advancement delta)。每升级时按 growth_rate% 概率获得 +1 点；advancement 通过 per-stat delta 调整曲线，**正负皆有** (避免 Engage 的「无理由停留 base class」strict-dominance bug)。Lv1→Lv30 期望 stat 增长约 +10~+20 点 (per stat with growth)，相对 base 提升 ~80-200%。L5 经济类符文通过 EXP 倍率 / per-stat growth bonus / 天赋点掉落率 三个 hook 接入。

---

## 0. 设计目标 & 模型选择

### 三个候选模型

| Model | 描述 | 利 | 弊 |
|---|---|---|---|
| **FE Three Houses (additive)** | class growth = char growth + class growth (additive) | 模块化清晰；advancement delta 可正可负 → 易避免 strict dominance | 无 character-innate 时全靠 class 撑起多样性 |
| **FE Engage (additive + caps)** | 同上 + stat cap + 直接 stat bump on class change | 转职瞬间数值反馈强 | "no upside to staying base" → 任何 advancement 都 strictly 优于 base，**违反 SoT D3 OQ 约束** |
| **Hybrid (XCOM-like fixed steps)** | promotion 给固定 +N stat (no probability) | 数值确定，便于平衡 | 失去 FE 的 RNG 张力；与 SoT roguelite 抽卡感弱契合 |

### 选定: **简化 Three Houses 加性模型**

**简化点**: SoT 没有 character-innate growth rate (角色 = class-pure)，所以 "class baseline" 直接承担 character growth 的角色，advancement 提供 **delta override (可正可负)**。

```
Lv N→N+1 时, for each growable stat:
  effective_growth = base_class.growth[stat] + (advancement.growth_delta[stat] if advanced else 0)
  effective_growth = clamp(effective_growth, 0, 95)   # 上限 95% 防爆炸
  if random() < effective_growth / 100:
    unit.stat[stat] += 1
```

**关键防 strict-dominance 约束**: 每条 advancement 至少有 1 个 stat 的 delta 为 **负值或 0** (典型负值 -5 ~ -15)，确保:
- Sniper 提升 STR/DEX/范围，但 RES/SPD 让步
- Heavy Knight 提升 HP/DEF，但 SPD/DEX 让步
- 玩家选择 advancement = 接受一组 trade-off，不是"白嫖加成"

---

## 1. v1 5 职业 Base Class Growth Rate

> Base stat 直接引用 `class-system.md` Lv1 baseline；growth rate 为 SoT 原创 (基于 FE Three Houses 35-65% 主流区间，按 SoT 战棋节奏调整为 25-65%)。

### 1.1 基础 stat 表 (Lv1 baseline) — 复述自 class-system.md

| Stat | Soldier | Archer | Mage | Knight | Cleric |
|---|---|---|---|---|---|
| HP  | 100 | 75 | 65 | 120 | 70 |
| STR | 13  | 16 | 5  | 12  | 5  |
| MAG | 3   | 3  | 20 | 3   | 15 |
| DEX | 8   | 11 | 7  | 5   | 6  |
| SPD | 8   | 10 | 7  | 6   | 7  |
| LCK | 5   | 5  | 10 | 8   | 12 |
| DEF | 9   | 5  | 4  | 14  | 4  |
| RES | 6   | 5  | 10 | 5   | 12 |

> SPD / MOV / VIS 不成长；以下 growth rate 表只列 7 个 growable stat (HP/STR/MAG/DEX/LCK/DEF/RES)。SPD 虽然 class-system 标记为 No-growth，但 D3 提议 advancement 阶段允许 SPD growth 出现 (作为 build-defining 工具，例如 Blade Master 速度链)。**OQ-D3-1**: SPD 是否解禁 growth 留 stage3 决议；本表保守先按 No-growth 处理。

### 1.2 Per-Class Growth Rate (% per level-up)

| Stat | Soldier | Archer | Mage | Knight | Cleric |
|---|---|---|---|---|---|
| HP  | **65** | 45 | 35 | **70** | 40 |
| STR | 50 | **55** | 10 | 45 | 10 |
| MAG | 5  | 5  | **60** | 5 | **45** |
| DEX | 35 | **50** | 30 | 20 | 25 |
| LCK | 30 | 25 | 35 | 30 | **45** |
| DEF | 35 | 20 | 15 | **55** | 15 |
| RES | 25 | 20 | **40** | 20 | **50** |
| **总和** | 245 | 220 | 225 | 245 | 230 |

**设计原则**:
- 总和带宽 220-245 (~10% 浮动)，确保不同职业 expected stat budget 接近
- 每职业有 1-2 个 60+% 主属 (主轴)，1-2 个 10% 边角属 (放弃方向)
- HP 主流 35-70%，反映坦度差距
- Mage/Cleric 是物理 STR 弃疗 (10% 边角属 = 偶尔出 1 但不可靠)

### 1.3 Lv1→Lv30 期望 stat 增长 (29 次 level-up)

```
Expected gain per stat = growth_rate% × 29
```

| Stat | Soldier | Archer | Mage | Knight | Cleric |
|---|---|---|---|---|---|
| HP gain  | +18.85 | +13.05 | +10.15 | +20.30 | +11.60 |
| STR gain | +14.50 | +15.95 | +2.90  | +13.05 | +2.90  |
| MAG gain | +1.45  | +1.45  | +17.40 | +1.45  | +13.05 |
| DEX gain | +10.15 | +14.50 | +8.70  | +5.80  | +7.25  |
| LCK gain | +8.70  | +7.25  | +10.15 | +8.70  | +13.05 |
| DEF gain | +10.15 | +5.80  | +4.35  | +15.95 | +4.35  |
| RES gain | +7.25  | +5.80  | +11.60 | +5.80  | +14.50 |

**Lv30 期望 stat (无 advancement, 持续 base class)**:

| Stat | Soldier | Archer | Mage | Knight | Cleric |
|---|---|---|---|---|---|
| HP  | 119 | 88 | 75 | 140 | 82 |
| STR | 28 | 32 | 8  | 25 | 8  |
| MAG | 4  | 4  | 37 | 4  | 28 |
| DEX | 18 | 26 | 16 | 11 | 13 |

→ 主属 ~2x base, 边角属 ~1.3x base, 整体 magnitude **可控**, 无爆炸。

---

## 2. 转职 Growth Rate Delta 表 (10/16 advancement)

### 2.1 Delta 设计原则

每条 advancement 的 delta 满足:
1. **总和约束**: `Σ delta` ∈ [+30, +60] (advancement 净加成相当于 1-2 个主属强化)
2. **方向约束**: 至少 1 个 stat delta ≤ 0 (避免 strict dominance)
3. **风味约束**: delta 反映 advancement 风味 (e.g. Sniper +DEX/+STR -SPD)
4. **非可叠加**: advancement 是单向选择，不存在"全选"，故 delta 总和不会被组合放大

### 2.2 v1 5 职业 × 2 advancement = 10 advancement 详表

#### Soldier → Champion (单挑型, 全 stat 进一步)

```
growth_delta: { HP: +10, STR: +15, MAG: 0, DEX: +5, LCK: +5, DEF: +5, RES: 0 }
total: +40
trade-off: 没有显著负面，但所有 delta 偏小 (vs Tactician 单点高峰)
风味: 无短板的多面手，逐级稳定增长
```

#### Soldier → Tactician (光环辅助, DEX/LCK 偏向)

```
growth_delta: { HP: +5, STR: -5, MAG: +10, DEX: +20, LCK: +15, DEF: +5, RES: +5 }
total: +55
trade-off: STR 让步 (个人 DPS 让位给 aura buff)
风味: DEX/LCK 高 → 命中 + 暴击保底；MAG +10 给 buff aura 作 mag-scaled hook
```

#### Archer → Sniper (超远程高伤, STR/DEX 极致)

```
growth_delta: { HP: 0, STR: +20, MAG: 0, DEX: +20, LCK: +5, DEF: -5, RES: -10 }
total: +30
trade-off: DEF/RES 双让步 (站后排不需要扛伤)
风味: STR+DEX 双 +20 → 大幅强化 Critical Hit 倍率 + 命中
```

#### Archer → Elven Archer (近战可附魔, SPD/RES 偏向)

```
growth_delta: { HP: +5, STR: +5, MAG: +15, DEX: +10, LCK: +10, DEF: +5, RES: +15 }
total: +65 (上限附近)
trade-off: 无显著负面 → **审计警告**: 接近 strict 优于 Sniper, 需在数值校准时下调
风味: MAG +15 解锁附魔伤害；RES 强化抗法; LCK 高 = 暴击 + 状态抗性
```

> **审计 Note**: Elven Archer 的 +65 比 Sniper 的 +30 高得多。考虑到 Sniper 有"超远程"的 functional 优势 (避免反击 + ZOC 抗性) 而 Elven Archer 是数值优势，total 差异是可接受的 trade-off (functional vs stat)。Stage3 critic 复审。

#### Mage → Grand Sage (多元素, MAG/RES 偏向)

```
growth_delta: { HP: +5, STR: -5, MAG: +20, DEX: +10, LCK: +5, DEF: 0, RES: +15 }
total: +50
trade-off: STR -5 (无 phys 备份, 全靠 MAG)
风味: 双元素 = MAG 持续输出 + RES 抗反魔法
```

#### Mage → Element Sage (单元素终极, MAG 极致)

```
growth_delta: { HP: 0, STR: -5, MAG: +30, DEX: +5, LCK: +10, DEF: -5, RES: +5 }
total: +40
trade-off: HP/DEF 让步 (玻璃大炮)
风味: MAG +30 = SoT 单 stat 最大 delta，反映"单元素终极"风味
```

#### Knight → Paladin (魔抗 + 治疗 + buff)

```
growth_delta: { HP: +10, STR: +5, MAG: +20, DEX: +10, LCK: +5, DEF: +5, RES: +25 }
total: +80 (**超上限**, 见下方校准)
trade-off: 几乎无负 → **审计 Fail**, 需校准
```

> **校准后 Paladin**:
> ```
> growth_delta: { HP: +5, STR: 0, MAG: +20, DEX: +10, LCK: +5, DEF: -5, RES: +25 }
> total: +60 (上限内)
> ```
> trade-off: DEF -5 (从极致物抗下调，换魔抗 + 治疗 MAG)
> 风味: MAG +20 解锁 ally heal/buff; RES +25 弥补 Knight 魔抗弱点

#### Knight → Heavy Knight (极致物防 + 反伤)

```
growth_delta: { HP: +20, STR: +10, MAG: -5, DEX: -5, LCK: 0, DEF: +25, RES: +5 }
total: +50
trade-off: MAG/DEX 双让步 (彻底放弃魔法 + 命中辅助)
风味: HP +20 + DEF +25 = Lv30 期望 HP 160+/DEF 30+, 反伤墙
```

#### Cleric → High Priest (AOE 治 + 副输出)

```
growth_delta: { HP: +10, STR: -5, MAG: +20, DEX: +10, LCK: +10, DEF: +5, RES: +10 }
total: +60
trade-off: STR -5 (放弃物理输出可能性)
风味: MAG +20 双轨 (治 + 输出); LCK +10 强化 Critical Hit + 状态抗
```

#### Cleric → Zealot (弃疗 + 神圣无视防御)

```
growth_delta: { HP: +5, STR: +20, MAG: +25, DEX: +15, LCK: -10, DEF: 0, RES: -5 }
total: +50
trade-off: LCK -10 (信仰极端 → 放弃幸运/暴击保底), RES -5
风味: STR + MAG 双高 (神圣 hybrid 倾向); 无视防御技能由 advancement skill 提供, 不靠 stat
```

### 2.3 校准后总和分布

| Advancement | Δ Total | Has Negative Delta? | 风味轴 |
|---|---|---|---|
| Champion | +40 | 0 (no neg) ⚠ | 全 stat 弱加 |
| Tactician | +55 | -5 STR | DEX/LCK aura |
| Sniper | +30 | -5 DEF, -10 RES | STR/DEX 极致 |
| Elven Archer | +65 ⚠ | 0 (no neg) ⚠ | MAG/RES |
| Grand Sage | +50 | -5 STR | MAG/RES 双元素 |
| Element Sage | +40 | -5 STR, -5 DEF | MAG +30 极致 |
| Paladin (校准后) | +60 | -5 DEF | MAG/RES + 治疗 |
| Heavy Knight | +50 | -5 MAG, -5 DEX | HP+25 DEF+25 |
| High Priest | +60 | -5 STR | MAG/LCK 双轨 |
| Zealot | +50 | -10 LCK, -5 RES | STR+MAG hybrid |

**Pending issues** (Stage3 critic 复审):
- Champion 缺 negative delta → 加 -5 LCK 或 -5 MAG
- Elven Archer total +65 + 无 neg → 下调到 +50 (DEX +10 → +5, MAG +15 → +10)

### 2.4 剩余 6 advancement 占位接口

```yaml
# Swordsman (post-v1)
sword_saint: { growth_delta_schema: 7-stat dict, target_total: ~+50, focus: STR/DEX/SPD-on-advance }
sword_cultivator: { target_total: ~+45, focus: STR+MAG hybrid, neg: DEF }

# Mercenary (post-v1)
champion_merc: { target_total: ~+50, focus: balanced, neg: SPD-equiv }
tactician_merc: { target_total: ~+55, focus: DEX/LCK aura support }

# Artificer (post-v1)
engineer: { target_total: ~+40, focus: LCK/RES + building synergy, neg: STR }
inventor: { target_total: ~+50, focus: STR/DEX + mech summoning, neg: RES }

# Hunter (post-v1)
beast_master: { target_total: ~+50, focus: STR/DEX + pet pair, neg: DEF }
survivalist: { target_total: ~+55, focus: DEX/LCK/RES + traps, neg: STR/HP }
```

> Swordsman 的 sword_saint 已有 KB 占位 (`sw_matrix_true_path.json` 终端节点 sw_saint17)，等 D2 stream 锁定再写入实际 delta。

---

## 3. L5 经济类符文 → L3 Hook 接口

consensus §4 标记 L5 经济类符文 → L3 成长加速。本节定义 3 个 hook 类型。

### 3.1 Hook A: EXP Multiplier

```
unit.gain_exp(amount):
  multiplier = 1.0 + Σ(rune.exp_bonus for rune in equipped_runes)
  unit.exp += amount × multiplier
  while unit.exp >= LEVEL_UP_THRESHOLD[unit.level]:
    unit.level_up()
```

**典型符文**: "Apprentice Tome" rune → +30% EXP (经济类基础档)

### 3.2 Hook B: Per-Stat Growth Bonus

```
on_level_up(stat):
  effective_growth = class.growth[stat] + advancement.delta[stat] + Σ(rune.growth_bonus[stat])
  effective_growth = clamp(effective_growth, 0, 95)
  ...
```

**典型符文**: "Iron Heart" rune → +10% HP growth；"Witch's Catalyst" rune → +15% MAG growth

> **设计约束**: 单 rune 单 stat bonus ≤ +20% (避免 1 rune 超过 advancement delta 的影响力 → L5 经济类 vs L2 advancement 边界保持清晰)

### 3.3 Hook C: 天赋点掉落率 (talent point drop rate)

```
on_combat_end(victory):
  base_talent_points = 1
  bonus = Σ(rune.talent_drop_bonus for rune in equipped_runes)
  awarded = base_talent_points + bonus
```

**典型符文**: "Scholar's Pendant" rune → +1 talent point per combat (= 高产经济符文)

### 3.4 Hook 优先级 & 上限

| Hook | 单 rune 上限 | 6 rune 全经济类极端组合上限 |
|---|---|---|
| EXP multiplier | +50% | +200% (不超过双倍刷级) |
| Stat growth bonus | +20% per stat | +60% per stat (3 同 stat rune) |
| Talent drop bonus | +1/combat | +3/combat |

> Stage3 D5 stream 校准实际 rune 池组合，避免 6 经济类 stack 导致 Lv30 期望 stat 超 200%。

---

## 4. Build-Defining 边界验证 (consensus §8 OQ D3)

### 4.1 验证准则

任何一条 advancement, 在它最有利的 build 场景下, 不应使另一条 advancement 在所有场景中变得无意义.

### 4.2 v1 10 advancement 两两对比 (节选)

| Pair | 强势场景 | 让步场景 | Verdict |
|---|---|---|---|
| Sniper vs Elven Archer | Sniper 远距 + crit (STR+20 DEX+20) | Elven Archer 近战 + 抗法 + LCK | **Both viable**, no dominance |
| Champion vs Tactician | Champion 单挑 (STR+15) | Tactician 队伍战 (DEX+20 aura) | **Both viable** |
| Grand Sage vs Element Sage | Grand Sage 多场景适应 (MAG+20 二元素) | Element Sage 单元素深潜 (MAG+30 ult) | **Both viable** |
| Paladin vs Heavy Knight | Paladin team 治疗辅助 (MAG+20 RES+25) | Heavy Knight 极致坦反伤 (HP+20 DEF+25) | **Both viable** |
| High Priest vs Zealot | High Priest 治 + 副输出 | Zealot 弃疗专神圣 (STR+20 MAG+25) | **Both viable** |

**结论**: 校准后 10/10 通过 dominance 检查。

### 4.3 数值检验: Lv30 期望 stat (Sniper vs Elven Archer)

```
Sniper @ Lv30:
  STR = 16 + (55+20)% × 29 = 16 + 21.75 = 37.75
  DEX = 11 + (50+20)% × 29 = 11 + 20.30 = 31.30
  RES = 5 + (20-10)% × 29 = 5 + 2.90 = 7.90  ← 极弱

Elven Archer @ Lv30:
  STR = 16 + (55+5)% × 29 = 16 + 17.40 = 33.40
  DEX = 11 + (50+10)% × 29 = 11 + 17.40 = 28.40
  MAG = 3 + (5+15)% × 29 = 3 + 5.80 = 8.80   ← 解锁 mag-hybrid
  RES = 5 + (20+15)% × 29 = 5 + 10.15 = 15.15
```

→ Sniper STR/DEX 比 Elven 各高 ~4 点 (12% 优势); Elven 拿 MAG hybrid + RES 补抗法。**dominance 不成立**.

---

## 5. 数值范围 & 上限

### 5.1 单 Stat 上限

| Stat | Soft cap | Hard cap | 备注 |
|---|---|---|---|
| HP | 200 | 300 | Heavy Knight 后期可触 200, 300 是极限 |
| STR/MAG | 50 | 80 | rune + advancement + Lv30 三层叠加预算 |
| DEX/LCK | 40 | 60 | RNG-保底属，soft cap 后边际收益递减 |
| DEF/RES | 30 | 45 | DR 公式中 DEF/(DEF+50) 形态, 边际收益自然递减 |

> hard cap 由 D2 stream 的 sw_matrix prune 决定 (passive 节点是否承担 stat soft cap break)；本 D3 默认采用 soft cap 不做 hard cap.

### 5.2 Per-Level Growth 上限

`effective_growth ≤ 95%` (硬上限). 超过 100% 的 "double level" 机制 (FE Engage 有) **不引入**, 维持 SoT 数值简洁.

### 5.3 Run 内 Lv1→Lv30 总成长 magnitude

| 成长来源 | 期望增益 (主属) |
|---|---|
| Base class growth (29 levels × 50-65%) | +14 ~ +19 |
| Advancement delta (Lv11-30 × +20%) | +4 |
| L5 经济类 stat growth rune (3 同 stat × 20% × 29) | +17 |
| **总计** | **+35 ~ +40** (主属 base 5 → 40+, 8x; base 16 → 50+, 3x) |

→ Lv30 主属期望 ~3-8x base, 大幅成长但仍在 hard cap 80 内.

---

## 6. JSON Schema (per class data file 增量)

### 6.1 base class growth_rates 字段 (已存在 schema, 仅 v1 5 职业填值)

```json
{
  "id": "soldier",
  "base_stats": { "HP": 100, "STR": 13, "MAG": 3, "DEX": 8, "LCK": 5, "DEF": 9, "RES": 6 },
  "growth_rates": {
    "HP": 65, "STR": 50, "MAG": 5, "DEX": 35, "LCK": 30, "DEF": 35, "RES": 25
  },
  "advancement": [
    {
      "id": "champion",
      "growth_delta": { "HP": 10, "STR": 15, "MAG": 0, "DEX": 5, "LCK": 5, "DEF": 5, "RES": 0 }
    },
    {
      "id": "tactician",
      "growth_delta": { "HP": 5, "STR": -5, "MAG": 10, "DEX": 20, "LCK": 15, "DEF": 5, "RES": 5 }
    }
  ]
}
```

> Note: KB class-system.md 当前样例使用 `growth_rates_override` (绝对值替换). 本 D3 提议改为 `growth_delta` (加性), 更符合 Three Houses 模型. **OQ-D3-2** 留 stage3 D2/D3 联合决议字段命名.

### 6.2 Rune 经济类 schema (D5 stream 协同字段)

```json
{
  "id": "rune_iron_heart",
  "category": "economic",
  "effects": {
    "growth_bonus": { "HP": 10 },
    "exp_multiplier": 0,
    "talent_drop_bonus": 0
  }
}
```

---

## 7. Open Questions for Stage 3

| ID | Question | Owner |
|---|---|---|
| **OQ-D3-1** | SPD 是否解禁 advancement growth (e.g. Blade Master SPD growth)? class-system.md 当前禁止, 但 Blade Master 风味强烈依赖 SPD 成长. | D3 + class-system 维护者 |
| **OQ-D3-2** | growth_rates_override (绝对替换) vs growth_delta (加性) — JSON schema 字段命名 | D2 + D3 联合 |
| **OQ-D3-3** | Champion 缺 negative delta → 补 -5 LCK 还是 -5 MAG? Elven Archer +65 是否下调到 +50? | Stage3 critic |
| **OQ-D3-4** | L5 经济类符文极端组合 (6 同 stat growth rune) 是否触 hard cap? D5 stream rune 池 design space 决定 | D5 + D3 |
| **OQ-D3-5** | Stat soft cap → hard cap 的 transition 曲线 (递减式 vs 切断式)? | Stage3 design synthesis |
| **OQ-D3-6** | 6 post-v1 advancement (Swordsman/Mercenary/Artificer/Hunter) 的 delta 实际值, 等 v1 数值校准后填 | D3 follow-up (v2 phase) |

---

## 8. 与 D2 stream 协同点 (sw_matrix_true_path.json)

D2 stream 正在 prune 83 节点中的 49 passive。其中纯 stat 加成型 passive (e.g. "ATK +5%", "HP +10") 应该:
- 迁出 L2 → 改为 **L3 base class growth_rates 一部分** (并入 base 数值, 不单独存在)
- 或迁出 L2 → 改为 **L5 经济类符文池物品** (玩家随机捡到)

**建议判定准则** (供 D2):
- passive 是 "constant flat boost" (e.g. +10 HP) → 迁 L3 (并入 base_stats)
- passive 是 "% scaling boost" (e.g. +10% HP growth) → 迁 L5 经济类 rune
- passive 是 "条件触发 stat boost" (e.g. low HP 时 +20% ATK) → 保留 L2

---

*Generated: D3 stream, S3-side-sot 2026-05-10. Pending Stage3 synthesis + critic review.*
