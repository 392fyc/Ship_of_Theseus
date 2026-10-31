# 05 - Class System

> ⚠️ **设计层已变更、本文档待同步（2026-06-16｜剑圣 v4.3 / rules v9）——同步前勿据此实现**：
> 1. **追击系统已移除**（R1.4，方案2）：速度第二效果改为「出手顺序」。本文 Myrmidon / Kensei 的「Follow-up Attack 深度专精」与「Follow-up Attack System」节**已作废**，Kensei 方向待以出手顺序系统重定。
> 2. **属性体系现行口径见规则 R2.1（2026-07-08）**：九属性 = 7 成长（HP/STR/MAG/DEX/SPD/DEF/RES）+ 2 固定（LCK/MOV）——本文属性表 LCK 的 Growth=Yes **已作废**（LCK 固定，2026-07-07 裁决；剑士/剑圣初始 LCK=B）；SPD 已改成长（2026-07-08 裁决，档位见下方剑士线标定）；VIS 视野随 v1 移除退出属性体系。成长率档位标尺见规则 R2.3。
> 正本：设计库规则表（生产 `/rules` 页）+ [[../rules-catalog|规则总目录]]；本章「属性档位标尺与剑士线标定」节为剑士线成长标定权威。

> Return to [[./README.md|Overview]]

## Overview

8 base classes, each with 2 Class Advancement paths. Classes determine base attributes, weapon restrictions, and initial skills. Growth is achieved through the **Talent Tree** (reset each Run) + **random rewards** (equipment/relics/extra skills) to create build diversity.

Class Advancement is triggered by special nodes in the Talent Tree; once chosen, it cannot be changed.

---

## Class Data Structure

```
Class:
  id: String
  name: String
  base_stats: UnitStats
  stat_growth: UnitStats            # Per-stat growth RATES（概率成长百分比；ADR-005 / 规则表 R2.2）
  innate_skills: Array[String]      # Starting skill IDs
  equip_types: Array[String]        # Equippable weapon/armor types
  class_tags: Array[String]         # Class tags (used for building occupation checks, etc.)
  move_type: "foot" | "armored" | "mounted"
  advancement: Array[AdvancedClass] # Class Advancement paths
```

---

## v1 Test Classes - 5

The following 5 classes are used in the v1 phase to test core combat values and mechanics:

| Class | Test Coverage |
|-------|--------------|
| Soldier | Physical damage, melee/ranged hybrid, balanced stat baseline |
| Archer | Ranged physical, Critical Hit/accuracy, range mechanics |
| Mage | Magical damage, AOE, elemental effects |
| Knight | Physical defense, durability, taunt mechanics |
| Cleric | Healing, holy damage, support mechanics |

*Myrmidon, Artificer, and Hunter will be added after v1 core mechanics are validated.*

---

## All Classes - 8 Base + 16 Advanced

### Myrmidon

| Attribute | Description |
|-----------|-------------|
| Core Role | High-mobility melee; Critical Hit/speed/Evasion type; core beneficiary of the Follow-up Attack system |
| Weapon Restriction | **Swords only** |
| Stat Profile | High accuracy, Critical Hit, speed, Evasion; average defense |
| Starting Skills | 斩击 / 一闪 / 招架 / 居合 / 拔刀（剑气-印记-心眼资源引擎，2026-06-21 已实装并验证，见下方注） |
| Attack Range | Melee (1 tile) |

**Class Advancement Paths**:

| Advanced Class | Direction | Core Changes |
|----------------|-----------|--------------|
| **Kensei** | Physical specialization | Extreme Critical Hit and speed; deep specialization in Follow-up Attack system (probability boost, Follow-up Attack bonus effects, etc.) |
| **Sword Immortal** (剑仙) | Physical + magic hybrid | Bonded Flying Sword (ranged hybrid attack); Sword Essence gauge (MP-like); Sword Formation territory control; late-game scaling powerhouse |

> **底座实装状态（2026-06-21）**：剑圣 5 基础技能（斩击 / 一闪 / 招架 / 居合 / 拔刀）+ 剑气 0-10 / 印记心道势 / 心眼 资源引擎已实装并通过 headless 回归验证（112 断言）。全 JSON 驱动、每职业隔离；「招架 ≠ 格挡」（不复活格挡子系统）。上方「核心追击受益者」与 Kensei「追击深度专精」随追击系统移除作废，速度第二效果改为出手顺序。详见 [[swordsman-engine-verification-2026-06-21]]。（2026-07-07 裁决：剑气重标定 0-100、存量获取/消耗 ×10、心眼每 10 点=+1% 暴击向下取整、速度阈值 ≥70；引擎侧换算待 SoT 组执行。）

---

### Mercenary

| Attribute | Description |
|-----------|-------------|
| Core Role | Versatile balanced physical fighter, melee/ranged capable |
| Weapon Restriction | **All except magic weapons** (swords/axes/spears/bows/crossbows, etc.) |
| Stat Profile | Balanced in all areas except magic, no obvious weaknesses |
| Starting Skills | Power Strike, Throw (ranged physical single-target) |
| Attack Range | Depends on equipped weapon |

**Class Advancement Paths**:

| Advanced Class | Direction | Core Changes |
|----------------|-----------|--------------|
| **Champion** | Solo combat enhancement | All stats further improved; strengthened solo combat capability |
| **Tactician** | Aura support | Gains buff auras, providing stat bonuses to self and nearby allies |

---

### Archer

| Attribute | Description |
|-----------|-------------|
| Core Role | Pure ranged physical damage dealer |
| Weapon Restriction | **Bows** |
| Stat Profile | High Critical Hit, decent speed and Evasion; low defense; average accuracy (needs Talent Tree/skills to supplement) |
| Starting Skills | Shot, Aim (greatly boosts next attack's accuracy and Critical Hit) |
| Attack Range | Ranged (**cannot melee**) |

**Class Advancement Paths**:

| Advanced Class | Direction | Core Changes |
|----------------|-----------|--------------|
| **Sniper** | Ultra-long range / high damage | Can equip bows with longer range; high damage output |
| **Elven Archer** | Melee-capable / enchanted arrows / Evasion | Unlocks melee capability; arrows enchant with debuffs; high Evasion for tanking |

---

### Artificer

| Attribute | Description |
|-----------|-------------|
| Core Role | Building operations / battlefield control, non-direct combat type |
| Weapon Restriction | (TBD) |
| Stat Profile | Weak personal combat ability; core value lies in battlefield control |
| Starting Skills | Repair (restore Building Durability), Temporary Enhancement (add temporary effects to buildings) |
| Special Ability | Can repair buildings in combat and add temporary effects to combat buildings |

**Class Advancement Paths**:

| Advanced Class | Direction | Core Changes |
|----------------|-----------|--------------|
| **Engineer** | Building enhancement / income | Further strengthens combat buildings; can construct temporary income buildings (gold/experience/random equipment) |
| **Inventor** | Mech summoning / frontline combat | Can construct special combat buildings: Mechs; uses talents and bonus effects to strengthen mechs for frontline combat |

---

### Mage

| Attribute | Description |
|-----------|-------------|
| Core Role | Three elemental schools of magic (Fire/Ice/Air), high damage + magical effects |
| Weapon Restriction | **Magic weapons** (staves/magical foci, etc.) |
| Stat Profile | High Magical Attack; low HP/physical defense/movement |
| Starting Skills | Fireball, Frost |
| Attack Range | Both melee and ranged (depends on skill) |

**Element System - Three Origins, Mutual Exclusion**:

The Mage talent tree features 3 element origin nodes (Fire/Ice/Air). Unlocking one origin **locks out** the other two (mutual exclusion). Each element has its own gauge, skill set, and tactical identity.

| Element | Tactical Identity | Gauge |
|---------|-------------------|-------|
| **Fire** | AOE burst, burn DOT, sustained heat | Hellfire (energy 0-100) |
| **Ice** | Control, slow/freeze, positional denial | Frost (energy 0-100) |
| **Air** | Mobility, speed manipulation, chain hits | Gale (energy 0-100) |

**Class Advancement Paths - Two Directions**:

| Advanced Class | Direction | Core Changes |
|----------------|-----------|--------------|
| **Grand Sage** (大贤者) | Multi-element mastery | Removes element exclusion — unlocks a second element origin. Broader but shallower; can mix two elemental kits |
| **Element Sage** (X之贤者) | Single-element ultimate | Locks into chosen element permanently. Deeper specialization; unlocks ultimate-tier abilities for that element |

> See [[01-Game-Design/Characters/talent-tree-deep-dive-rules|deep-dive-rules]] and mage-talent-tree-design-brief for detailed topology and gauge design.

---

### Knight

| Attribute | Description |
|-----------|-------------|
| Core Role | Physical defense core, taunt / durability specialist |
| Weapon Restriction | Melee weapons + **can equip shields** (shields may carry mitigation-oriented special effects) |
| Stat Profile | High HP/physical defense; low speed/magic defense |
| Starting Skills | Shield Bash, Provoke (taunt surrounding enemies) |
| Talent Exclusion | Mounted (high mobility) vs Heavy armor + shield (high defense), choose one — cannot pick both |

**Class Advancement Paths**:

| Advanced Class | Direction | Core Changes |
|----------------|-----------|--------------|
| **Paladin** | Magic defense / healing / buffs | Compensates for magic defense weakness; gains ally healing and buff abilities |
| **Heavy Knight** | Extreme physical defense / taunt / reflect damage | Physical resistance further increased; actively draws enemy attacks; damages enemies when hit |

---

### Hunter

| Attribute | Description |
|-----------|-------------|
| Core Role | Melee/ranged hybrid, flexible response |
| Weapon Restriction | **Bow + melee weapon** |
| Stat Profile | High Evasion/magic resistance; decent speed; average attack/defense |
| Starting Skills | Shot, Close Slash |
| Attack Range | Both melee and ranged |

**Class Advancement Paths**:

| Advanced Class | Direction | Core Changes |
|----------------|-----------|--------------|
| **Beast Master** | Pet synergy | Gains a dedicated pet; commands pet for coordinated attacks |
| **Survivalist** | Traps / Evasion / magic resistance | Places traps to restrict enemies; high Evasion + magic resistance to pin down specific enemies |

---

### Priest

| Attribute | Description |
|-----------|-------------|
| Core Role | Healing core, basic magic attacks |
| Weapon Restriction | **Staves** |
| Stat Profile | High magic defense/status resistance; low physical attack/physical defense; average Magical Attack |
| Starting Skills | Heal, Holy Bolt (holy damage single-target) |
| Attack Range | Primarily ranged |

**Class Advancement Paths**:

| Advanced Class | Direction | Core Changes |
|----------------|-----------|--------------|
| **High Priest** | AOE healing + secondary damage | AOE healing and damage; special mechanic allows both damage and healing each turn |
| **Zealot** | Abandon healing / holy damage | Gives up healing capability; gains holy damage that ignores defense for stable, efficient output |

---

## Build Composition

A character's build is composed of the following elements:

```
UnitBuild:
  class: Class                     # Base class
  advanced_class: AdvancedClass | null  # Post-advancement class (null if not advanced)
  level: int                       # Current level
  talent_tree: TalentTreeState     # Talent Tree state (reset each Run)
  active_skills: Array[Skill]      # Active skill slots (talent unlocks + random acquisition)
  passive_effects: Array[Passive]  # Passive effects (unlocked via Talent Tree)
  weapon: Weapon                   # Weapon
  armor: Armor                     # Armor
  accessory: Accessory | null      # Accessory (TBD)
  relics: Array[Relic]             # Relics (Roguelite random acquisition)
```

### Build Diversity Sources

| Source | Type | Description |
|--------|------|-------------|
| Talent Tree | Controllable | Reset each Run, player chooses path. Provides passive traits, core skills, Class Advancement |
| Random Skill Rewards | Semi-random | Combat rewards/shops provide extra skills, expanding available skill pool |
| Equipment | Semi-random | Weapons/armor/accessories, affecting stats and special effects |
| Relics | Random | Core Roguelite random element, providing unique passive effects |
| Buildings | Controllable | Battlefield/functional bonuses from Town Building |

**Talent Tree = Skeleton** (determines character direction and Class Advancement), **Random elements = Flesh** (fills in the specific build on top of the skeleton).

The same Archer into Sniper may form completely different playstyles in different Runs due to obtaining different relics and skills.

### Action Resource Planning in Builds

When choosing skills, consider **action resource allocation** (see 01-turn-system.md). Each turn has only 1 Move Action, 1 attack opportunity, and 1 Swift Action; skills of the same type compete with each other:

- Bringing multiple \[Standard Action\] skills = can only choose 1 per turn, requiring battlefield-based decision-making
- Bringing multiple \[Swift Action\] skills = can only use 1 per turn, requiring optimal timing selection
- \[Reaction Action\] skills do not consume active resources, and are an important source of build depth
- **A healthy build** should balance skill distribution across different action types rather than concentrating everything on \[Standard Action\]

---

## Roguelite Archetype Mapping

The following archetypes can be achieved through different class + talent + random element combinations:

| Archetype | Typical Classes | Core Mechanics | Action Resource Focus |
|-----------|----------------|----------------|----------------------|
| Single-turn burst damage | Kensei, Element Sage (Fire), Zealot | High-multiplier skills / charge-up / high-cooldown | Swift Action buff then Standard Action |
| High-speed Follow-up - multi-hit | Kensei, Myrmidon | Speed difference into Follow-up Attack probability, Kensei talent deep specialization | Standard Action + Reaction Action |
| Extra action | Myrmidon, Soldier | Special talents/relics grant multiple actions in a single turn | Standard Action x2 (re-act) |
| Support buff machine | Grand Sage, Tactician, High Priest | Buff allies to boost various multiplier zones | Swift Action buff then Standard Action buff |
| Strategic control | Engineer, Inventor, Survivalist | Buildings/traps/summons control battlefield | Move Action + Standard Action |
| Ranged artillery | Sniper | Ultra-long range, prevents Counter-attack | Swift Action aim then Standard Action |
| Hit-and-run | Elven Archer, Hunter, Soldier | Attack then move, guerrilla-style combat | Move Action + basic attack |
| Defensive / reflect | Heavy Knight | High defense + taunt + reflect damage | Swift Action defense + Reaction Action |
| DOT / Debuff | Elven Archer, Element Sage (Fire/Ice) | Enchanted arrows / burn DOT / freeze control / sustained damage | Standard Action + Swift Action enchant |

---

## Leveling and Growth

Characters gain experience and level up through combat during a Run:

```
Level-up:
  each growable stat: if random() < growth_rate[stat] → stat += 1   # 概率成长 + pity 保底（ADR-005 / 规则表 R2.2）
  Gain talent points (used to unlock nodes in the Talent Tree)
```

- 预期一局(Run)结束时人物等级 **25-30**(2026-07-07 用户裁决;原「每 Run 3-5 次升级」为错误记录,按当前 3 幕 × 8 关模型修正)
- speed/luck/move/vision do not grow with level-ups（LCK 固定，2026-07-07 正式裁决）
- stat_growth may change after Class Advancement (advanced classes have their own growth rates)

### 属性档位标尺与剑士线标定（2026-07-07 用户裁决）

成长率档位**固定单值**（规则表 R2.3 唯一换算）：**C=40% / B=50% / A=60% / S=75%**；SS 不设更高单次率——每次升级以 S（75%）判定两次（期望 +1.5、至多 +2）。不设弃轴档，最低档 = C。

| 属性 | 剑士 | 剑圣 | 换算（剑圣） |
|---|---|---|---|
| DEX | A | **S** | 75%（唯一转职提档 A→S） |
| HP | B | B | 50% |
| STR | B | B | 50% |
| DEF | B | B | 50% |
| MAG | C | C | 40%（不设弃轴，最低 C；2026-07-07 由弃轴改 C） |
| RES | C | C | 40% |
| SPD | B | A | 60%（SPD 改成长后旧固定值档字母平移为成长率档，2026-07-08 裁决） |
| LCK / MOV | 固定 | 固定 | 不成长（VIS 已随 v1 视野移除退出属性体系） |

Σ成长率（剑圣）= 3.65 → 每级平均 +3.65 属性点，升级全空概率约 0.45%（另有 pity 保底）。各属性初始值均为占位待定。引擎侧 `data/classes/swordsman.json` 的 growth_rates 为测试占位值，待按本表更新（DEX 75 / HP 50 / STR 50 / DEF 50 / SPD 60 / MAG 40 / RES 40）。

---

## Attribute Baseline - Level 1

*The following is the ADR-005-aligned Level 1 baseline used to express class positioning. Values remain subject to prototype calibration. The current playable prototype uses Soldier/Archer/Mage/Knight/Cleric as its 5 demo classes.*

*DEX and LCK replace the former HIT/CRIT and crit-evasion/status-resistance axes in this table.*

| Attribute | Myrmidon | Mercenary | Archer | Artificer | Mage | Knight | Hunter | Cleric | Growth |
|-----------|-----------|-----------|--------|-----------|------|--------|--------|--------|--------|
| HP | 90 | 100 | 75 | 80 | 65 | 120 | 85 | 70 | Yes |
| STR | 14 | 13 | 16 | 8 | 5 | 12 | 13 | 5 | Yes |
| MAG | 5 | 3 | 3 | 8 | 20 | 3 | 5 | 15 | Yes |
| DEX | 12 | 8 | 11 | 6 | 7 | 5 | 9 | 6 | Yes |
| SPD | 12 | 8 | 10 | 6 | 7 | 6 | 10 | 7 | No |
| LCK | 5 | 5 | 5 | 8 | 10 | 8 | 10 | 12 | No（固定，2026-07-07 裁决） |
| DEF | 7 | 9 | 5 | 6 | 4 | 14 | 6 | 4 | Yes |
| RES | 5 | 6 | 5 | 7 | 10 | 5 | 9 | 12 | Yes |
| MOV | 3 | 3 | 3 | 3 | 2 | 3 | 4 | 2 | No |
| VIS | 3 | 3 | 4 | 3 | 3 | 3 | 4 | 3 | No |

**Design Rationale**:
- **Myrmidon**: High SPD/DEX, crit-oriented, average DEF/RES, moderate STR
- **Mercenary / current prototype Soldier slot**: Balanced STR/DEX/DEF, no weaknesses but no extremes
- **Archer**: High STR/DEX, moderate SPD, low DEF, long VIS
- **Artificer**: Weak direct combat, higher RES/LCK to survive frontline building operations
- **Mage**: Extremely high MAG, lowest HP/DEF, lowest MOV
- **Knight**: Highest HP/DEF, low SPD/RES
- **Hunter**: High SPD/RES, melee/ranged hybrid, long VIS
- **Cleric**: Highest RES/LCK, weak physical stats

---

## Counter-attack System

Except for area-type attacks, a unit that is attacked can **Counter-attack** the attacker if their attack range is sufficient.

```
Counter-attack Conditions:
  1. The attacking skill/attack has attack_type != "area" (area attacks do not trigger Counter-attack)
  2. The defender is alive
  3. The defender's currently equipped weapon/skill range can reach the attacker's position
  4. The defender is not in an incapacitated state (stunned/frozen, etc.)

Counter-attack Rules:
  - Counter-attack uses the defender's basic attack (not skills)
  - Maximum 1 Counter-attack per being attacked
  - Counter-attack goes through the full attack resolution flow (accuracy -> Critical Hit -> damage -> bonus effects)
  - Counter-attack does not consume action counts and does not affect the unit's normal turn actions
```

**Tactical Implications**:
- Ranged artillery (e.g., Sniper) can attack outside Counter-attack range for safe output
- Melee attacking melee characters always faces Counter-attack, increasing offensive risk
- Knight's high durability + Counter-attack = excellent frontline deterrence
- Heavy Knight's reflect damage trait can deal additional damage when attacked + Counter-attacking

---

## Follow-up Attack System（已移除）

> **追击系统已从设计移除（2026-06-16 裁决；2026-07-07 正文同步）**：速度第二效果改为「出手顺序」（见 turn-system / 规则表 R3.1）。以下原始设计（概率模型/低速补偿表）作废留档：

Units with speed advantage have a chance to launch an additional attack after attack resolution. This system is **universal to all classes**.

```
Follow-up Attack Probability = (attacker.speed - defender.speed) x 10%

  Range: minimum 0%, maximum 100%
  When attacker speed <= defender speed, Follow-up Attack probability is 0%

Follow-up Attack Conditions:
  1. Attacker is alive
  2. Original attack hit (no Follow-up Attack check on Miss)
  3. Follow-up Attack probability check succeeds

Follow-up Attack Rules:
  - Follow-up Attack uses the attacker's basic attack
  - Goes through full attack resolution flow (accuracy -> Critical Hit -> damage -> bonus effects)
  - Follow-up Attack does not trigger Counter-attack
  - Follow-up Attack does not trigger a second Follow-up Attack
  - Follow-up Attack resolves after Counter-attack
```

### Design Concept

Inspired by Fire Emblem's Follow-up Attack system. Speed difference serves as an additional multiplier advantage, giving high-speed units the benefit of multi-hit attacks. To balance this advantage, low-speed units receive compensation in other dimensions:

| Low-Speed Compensation | Typical Classes | Description |
|------------------------|-----------------|-------------|
| High single-hit damage | Mage | High skill multipliers, AOE coverage |
| High defense / mitigation specials | Knight | Mitigates opponent's Follow-up Attack damage |
| Control / Debuff | Cleric, Artificer | Reduces opponent output through status effects |
| Safe ranged output | Archer | Range advantage avoids being followed up on |

### Myrmidon Line Extensions - Reserved

Myrmidon is the core beneficiary class of the Follow-up Attack system (highest speed among all classes, SPD=12). Future Talent Tree development will create dedicated mechanics around Follow-up Attacks:
- Additional Follow-up Attack probability bonuses
- Follow-up Attack triggers special effects (e.g., gaining a buff after Follow-up Attack hits)
- Follow-up Attack damage modifiers (e.g., increased Follow-up Attack Critical Hit rate)
- Kensei advancement deeply specializes the Follow-up Attack system

*Specific details will be refined as class talents are gradually developed. Calculation details for the Follow-up Attack and Counter-attack systems will also be supplemented in parallel.*

---

## Class Data File Example

```json
{
  "id": "swordsman",
  "name": "Myrmidon",
  "base_stats": {
    "HP": 90, "STR": 14, "MAG": 5,
    "DEF": 7, "RES": 5,
    "DEX": 12, "SPD": 12, "LCK": 5,
    "MOV": 3, "VIS": 3
  },
  "growth_rates": {
    "HP": 50, "STR": 40, "MAG": 0,
    "DEF": 20, "RES": 10,
    "DEX": 35, "LCK": 15
  },
  "innate_skills": ["slash", "evasion_slash"],
  "equip_types": ["sword"],
  "class_tags": ["melee", "sword"],
  "move_type": "foot",
  "advancement": [
    {
      "id": "sword_saint",
      "name": "Kensei",
      "talent_node_id": "swordsman_adv_a",
      "growth_rates_override": {
        "STR": 4, "DEX": 3
      },
      "unlocked_tags": ["critical_master", "speed_chain"]
    },
    {
      "id": "sword_cultivator",
      "name": "Sword Immortal",
      "talent_node_id": "swordsman_adv_b",
      "growth_rates_override": {
        "STR": 2, "MAG": 3, "RES": 1
      },
      "unlocked_tags": ["hybrid_damage", "sword_essence"]
    }
  ]
}
```

---

## Equipment System - Demo

### Slot Structure

| Slot | Description | Universal |
|------|-------------|-----------|
| Main Hand (two-handed weapon) | Sword / Bow / Tome | Yes - each class restricted to corresponding weapon |
| Off Hand | **Only usable after Kensei unlocks "Dual Wield" talent**, equips a second sword | No - Kensei exclusive |
| Armor | Provides defense/HP/resistance | Yes |
| Accessory | Various effects | Yes |

### Weapon Types

| Weapon | Used By | Base Stat Tendency | Notes |
|--------|---------|-------------------|-------|
| Sword | Myrmidon line | ATK, HIT, CRIT | Two-handed weapon |
| Bow | Archer line | ATK, CRIT, range parameter | Two-handed weapon; Elven Archer at range 1 becomes melee |
| Tome | Mage line | MAG, HIT, skill amplification | Two-handed weapon |

### Dual Wielding - Kensei Exclusive

- **Unlock Method**: "Dual Wield" node in Kensei's Talent Tree branch after Class Advancement
- **Off-hand Sword Stats**: Only gains 50% of off-hand sword's ATK
- **Off-hand Special Effects**: Later nodes can unlock 50% effectiveness of off-hand special effects, but with negative side effects (e.g., stat reduction)
- **Core Benefit**: Comes from talent nodes (40% chance for extra attack at 50% power, etc.), not equipment stacking

### Equipment Bonus Reference - By Stage Progress

| Stage | Weapon ATK Bonus | Armor DEF Bonus |
|-------|------------------|-----------------|
| Early (stages 1-5) | +2~4 | +1~2 |
| Mid (stages 6-15) | +5~8 | +3~5 |
| Late (stages 16-25) | +9~14 | +5~8 |
| Endgame (stages 26-30) | +12~18 | +7~10 |

---

## Future Extensions - Reserved

- **Astrologer**: To be added when the day/night system is introduced, gaining different skill effects from day/night changes
- **More advancement branches**: Existing classes may receive 3rd and 4th Class Advancement paths in the future
- **Cross-class skills**: Relics/special events may allow acquiring skills from other classes

---

Related documents:
- [[./03-battle-calculation.md|03 - Battle Calculation]] — How attributes participate in damage/accuracy/Counter-attack formulas
- [[./04-skills-and-range.md|04 - Skills and Range]] — Skill definitions and damage types
- [[./12-talent-tree.md|12 - Talent Tree]] — Talent nodes, spectrum system, Class Advancement triggers
- [[./07-run-loop.md|07 - Run Loop]] — Skill/relic acquisition paths
- [[./11-town-building.md|11 - Town Building]] — Artificer and building system interactions
