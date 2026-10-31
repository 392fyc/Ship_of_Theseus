# ADR-005 - Attribute System First-Round Integration Simulation

**Date**: 2026-02-27
**Status**: Draft (pending Human Supervisor approval)
**Decision Maker**: Antigravity (Design Agent) -> Human Supervisor final decision
**Prerequisites**: ADR-004 (Four Damage Types Redesign), M5 playtest data
**Reference Frame**: Fire Emblem Three Houses, Fire Emblem Engage

---

## Current-State Notice - added 2026-08-03

**This is a historical record. Do not implement from it.** The decision text below is preserved exactly as it stood in 2026-02-27 - an ADR records what was decided at the time, so nothing in it has been rewritten. Several of its statements have since been overridden by locked rules. Where this document and the rule table disagree, **the rule table wins** (authoritative source: design library `/rules`; KB index: `01-Game-Design/rules-catalog.md`; system document: `01-Game-Design/Core-Systems/battle-calculation.md`).

| Statement in this ADR | Where | Current state |
|---|---|---|
| Header reads `Status: Draft (pending Human Supervisor approval)` | Header | Stale label. The footer of this same file records supervisor approval, the 2026-02-27 revision confirmation section closed the minimum revision set, ADR-009 lists ADR-005 as a prerequisite, and most of the design is live in the engine. The field is left as written rather than back-dated. |
| `Vision (VIS)` listed as an attribute; "10 attributes total" | §3 Option A, §3 comparison table, §4.1, §4.5, §5 mapping table, §5 key decision 1 | **VIS has been deleted.** The roster is nine attributes (R2.1). |
| "7 growing (HP/STR/MAG/DEX/**LCK**/DEF/RES), 3 fixed (**SPD**/MOV/VIS)" | §4.1, §4.5 | **All three membership claims are now wrong.** SPD grows, LCK is fixed, VIS does not exist. Current split: 7 growing (HP/STR/MAG/DEX/SPD/DEF/RES) + 2 fixed (LCK/MOV) (R2.1). The illustrative `growth_rate` percentages in §4.5 also predate the R2.3 tier scale (C=40% / B=50% / A=60% / S=75%), which is now the authoritative conversion for growth tiers. |
| "Zero-damage floor: All calculations use `max(1, ...)`", and the `max(1, ...)` in the physical/magical pseudocode | §4.2, and the first consensus bullet of the dual-round review section | **The floor is 0, not 1.** The additive layer uses `max(0, ...)` and the final damage may legitimately resolve to 0 against a high enough defence (R1.1). |
| hybrid TBD block, "unresolved until ADR-006 is finalized"; the four open hybrid questions in §5; the hybrid row of the 2026-02-27 revision confirmation table | §4.2, §5, revision confirmation | **Settled.** See ADR-006 (2026-08-03, `adr-2026-08-03-hybrid-damage-formula.md`): two floored branches, arithmetic mean. All four open questions are answered there. |
| `Hit = weapon_hit + DEX*2 + LCK*0.5`; `Avoid = SPD*2 + LCK*0.5 + terrain`; `clamp(Hit - Avoid, 20, 100)`; LCK described as granting "minor accuracy" | §4.1, §4.3, §5 mapping table | **LCK does not participate in the hit chain**, and the lower bound is 1, not 20: `base_hit = weapon_hit + DEX*2`, `avoid = SPD*2 + terrain_evade_bonus`, final rate `clamp(1, 100)` (R1.2). LCK's only two combat touchpoints are crit evasion and debuff resistance (R2.1). |
| "Crit Damage = 1.5x (Pure fixed 1.5x, not affected by bonuses)"; "Pure crit fixed x1.5 - Preserved" | §4.3, §5 ADR-004 compatibility table | **Pure damage does not participate in the crit chain at all** - no crit roll, no crit zone, and no skill-level switch that lets it in (R1.1 / R1.3). |
| Attack resolution step 7 "Counter-attack Check"; step 8 "Follow-up Attack Check"; the follow-up probability model `speed_diff x 10%` declared official intent | §1 problem 3, §2 directive 6, §4.3, §4.4, and the corresponding revision-confirmation row | **Both mechanics are gone.** No unit counter-attacks for being attacked (ruled 2026-07-11); the speed-difference follow-up attack is likewise no longer part of the design. The resolution flow now ends at step 6 (`battle-calculation.md`). |
| Block moved from base attribute to "Talent/Equipment/Relic special effect" | §2 directive 2, §4.7, §5 key decision 3 | **Block was deleted outright on 2026-07-06**, including from the talent and relic layers - it is not a relocated mechanic, it no longer exists. The swordsman's parry is a separate mechanic and is unaffected ("parry is not block"). |
| Weapon JSON carrying `"damage_type"`, `"range"` and `"stat_bonus"`; the "Stat Bonus" column of the weapon tier table; `tome_might` as the magical-side weapon parameter | §4.2, §4.7, §4.8 | **Narrowed by R1.7.** A weapon supplies exactly three parameters - `weapon_might` / `weapon_hit` / `weapon_crit` - and nothing else: weapons do not declare a damage type (the skill does) and do not manage range; stat keys belong to the affix layer. `tome_might` no longer exists either; the magical branch reads the same `weapon_might`. |

---

## 1 - Background

M5 battle loop verification produced the first batch of playtest data (soldier vs goblin_melee), exposing five structural problems with the current prototype attribute system:

| # | Problem | Data |
|---|---------|------|
| 1 | Zero-damage cliff | def(9) >= phys_atk(7) -> damage=0, low-ATK enemies cannot deal any damage |
| 2 | Severely excessive TTK | soldier->goblin expected TTK=39 turns (FE standard 3-8 turns) |
| 3 | Low Follow-up Attack probability - prototype baseline | speed difference only 1, probability 10% (prototype values); new design increases SPD gap for improvement, probability model (speed_diff x 10%) confirmed as official design intent, future weight modifiers may be layered on but core algorithm remains unchanged |
| 4 | ATK/DEF ratio imbalance | soldier def / goblin atk = 9/7 = 129% (target range 40%-60%); this ADR establishes the algorithm framework, specific values pending future calibration |

**Root Cause**: In the current formula `base = atk x power - def x resist`, phys_power defaults to 1.0. As a multiplicative coefficient it cannot provide a "base-layer buffer". FE's weapon_might is an **additive base** - even when STR < DEF, positive damage can still be dealt.

---

## 2 - Decision Drivers

### Human Supervisor Directives

1. Convert attribute system to FE's STR/MAG/DEX/SPD/LCK/DEF/RES
2. **Remove Block as a base attribute** - Block becomes a Talent/Equipment/Relic special effect
3. Add **Luck (LCK)** attribute, merging crit_evade + resistance
4. Reference values from **Three Houses + Engage**
5. Add extra **multiplicative zones** on top of FE's additive base (providing scaling space for Roguelite)
6. Follow-up Attack uses **probability model** (speed_diff x 10%) as official design intent; future weight modifiers may be layered on, core algorithm remains unchanged
7. **Crit multiplier stays at x1.5** (can be enhanced by Talents/Relics)
8. **Do not introduce Attack Speed (AS) / weapon weight system** to avoid excessive weapon design complexity
9. **SPD/MOV do not grow** - adjusted only through initial values + Class Advancement + Talents + Relics + Equipment
10. **Probability-based growth + pity mechanic** to prevent extreme bad luck
11. Hybrid damage type to be reviewed after base model is finalized
12. Three cultivation pillars: **Talents + Equipment (weapons/armor) + Relics (Roguelite)**

### FE Three Houses / Engage Reference Formulas

```
Damage = STR/MAG + Weapon Might - DEF/RES (additive direct subtraction)
Accuracy = Weapon Hit + DEX*2 + LCK/2 - (SPD*2 + LCK/2 + terrain)
Crit Rate = Weapon Crit + DEX/2 - LCK (crit evasion)
Follow-up Attack = Three Houses AS_diff>=4 guaranteed trigger (this game keeps probability model)
Crit Damage = 3x (this game keeps 1.5x)
```

---

## 3 - Three-Option Comparison

### Option A - FE Streamlined - Recommended, direction confirmed by Human Supervisor

- Attributes converted to FE system (STR/MAG/DEX/SPD/LCK/DEF/RES/HP/MOV/VIS), 10 total
- Damage base layer additive (`STR + weapon_might - DEF`), outer layer retains multiplicative zones plus new Relic independent multiplicative zone
- Accuracy/Crit/Evasion derived from DEX/SPD/LCK, no longer independent attributes
- Remove Block base attribute, add LCK (merging crit evasion + status resistance)
- Probability-based growth + pity mechanic, SPD/MOV do not grow

### Option B - Current Prototype Extension

- Keep phys_atk/mag_atk naming, introduce weapon_might additive buffer
- Only merge crit_evade + resistance -> luck, attributes reduced from 14 to 13
- Formula changed to additive but attribute names unchanged

### Option C - Roguelite Priority - Minimalist

- Unified ATK/DEF/SPD/LCK etc. 7 attributes
- No physical/magical differentiation, hybrid loses meaning
- Affixes carry all differentiation

### Comparison Table

| Dimension | A - FE Streamlined ★ | B - Prototype Extension | C - Roguelite Priority |
|-----------|----------------------|------------------------|----------------------|
| Attribute count | **10** | 13 | 7 |
| Damage formula | STR + might - DEF (additive) | phys_atk + might - DEF (additive) | ATK + might - DEF (additive) |
| Accuracy/Crit | DEX/LCK derived | Independent hit/crit + luck | LCK derived |
| Rename cost | High (full rename) | Low (only merge 2 attributes) | Medium (merge multiple attributes) |
| Hybrid support | ✅ STR+MAG dual attributes preserved | ✅ Fully compatible | ❌ Unified ATK no differentiation |
| Talent Tree compatibility | ✅ Blade Master(STR)/Sword Cultivator(MAG) dual poles effective | ✅ Fully compatible | ❌ Dual poles lose foundation |
| Roguelite affixes | Medium-High (multiplicative zone + attribute dual layer) | Medium | High (but extremely hard to balance) |
| ADR-004 compatibility | ✅ Dual attributes preserved (renamed) | ✅ Fully compatible | ❌ Architecture conflict |
| FE experience referenceable | ✅ Direct benchmarking | ⚠️ Partial benchmarking | ❌ No benchmarking |
| TTK verification | ≈ 3 turns ✅ | ≈ 4 turns ✅ | ≈ 2 turns ⚠️ |

---

## 4 - Recommended Option Detailed Design

### 4.1 Attribute List

| Attribute | Abbrev | Meaning | Grows | Change Source - non-growing attributes |
|-----------|--------|---------|-------|---------------------------------------|
| Strength | STR | Physical attack power | ✅ | — |
| Magic | MAG | Magical attack power | ✅ | — |
| Dexterity | DEX | Accuracy + Crit derivation | ✅ | — |
| Speed | SPD | Action order + Evasion derivation + Follow-up Attack | ❌ | Initial fixed + Class Advancement + Talents + Relics + Equipment |
| Luck | LCK | Crit evasion + status resistance + minor accuracy | ✅ | — |
| Defense | DEF | Physical defense | ✅ | — |
| Resistance | RES | Magical defense | ✅ | — |
| Health | HP | Health points | ✅ | — |
| Movement | MOV | Movement range / tiles | ❌ | Initial fixed + Class Advancement + Talents + Relics + Equipment |
| Vision | VIS | Vision range | ❌ | Initial fixed + Buildings + Skills + Relics |

**10 attributes total**: 7 growing (HP/STR/MAG/DEX/LCK/DEF/RES), 3 fixed (SPD/MOV/VIS).

### 4.2 Damage Formula - Dual-Layer Structure

#### Layer 1 - Base Damage - Additive, FE Style

```
physical:  base = max(1, STR + weapon_might - target.DEF)
magical:   base = max(1, MAG + tome_might - target.RES)
hybrid:    # ⚠️ TBD — pending independent ADR review, do not reference in implementation
           # Known constraints: dual attributes (STR+MAG) both participate, defense takes min(DEF, RES)
           # Open issues: hybrid_might definition / dual attribute stacking strength / class growth allocation / extreme disparity falloff
           # This entry is considered unresolved until ADR-006 is finalized
pure:      base = [source] + weapon_might (ignores defense, affected by terrain modifier)
           source = STR / MAG / STR+MAG (declared by skill)
```

**Zero-damage floor**: All calculations use `max(1, ...)`.

#### Layer 2 - Multiplicative Formula - Existing Structure + New Relic Zone

```
Final Damage = base x skill_multiplier x terrain_modifier x crit_modifier x relic_modifier x final_adjustment

  skill_multiplier  = skill.power / 100
  terrain_modifier  = special terrain independent multiplier (e.g. "damage x0.8")
  crit_modifier     = 1.5x on crit (can be enhanced by Talents/Relics), 1.0x on non-crit
  relic_modifier    = ★NEW★ Roguelite Relic independent multiplicative zone
  final_adjustment  = Building damage reduction, Buff damage increase, etc.
```

### 4.3 Accuracy / Crit / Evasion / Follow-up Attack

```
Hit Rate = clamp(Hit - Avoid, 20, 100)
  Hit   = weapon_hit + DEX*2 + LCK*0.5
  Avoid = SPD*2 + LCK*0.5 + terrain_evade_bonus

Crit Rate = max(0, Crit - Dodge)
  Crit  = weapon_crit + DEX/2
  Dodge = LCK
  Crit Damage = 1.5x (Pure fixed 1.5x, not affected by bonuses)

Status Resistance: Debuff application rate = skill_chance x max(0.1, 1 - target.LCK/100)

Follow-up Attack Probability = (attacker.SPD - defender.SPD) x 10% (0%~100%)
# Design declaration: The probability model is the official intent (not a temporary solution).
# Future weight modifiers may be layered on top (e.g. Talents/Relics increasing follow-up rate),
# but "speed_diff x 10%" as the core formula remains unchanged.
```

### 4.4 Attack Resolution Flow

```
1. [Hit Check] Hit - Avoid -> random -> Miss ends resolution
2. [Crit Check] Crit - Dodge -> random -> crit_modifier=1.5
3. [Damage Calculation] base x skill_multiplier x terrain x crit x relic x final_adjustment
4. [Apply Damage] HP reduction, check for kill
5. [Post-Hit Effects] Debuff application (affected by LCK)
6. [Post-Damage Effects] Lifesteal, kill rewards, Relic triggers, etc.
7. [Counter-attack Check] (rules unchanged)
8. [Follow-up Attack Check] SPD_diff x 10% -> follow-up runs steps 1-6
```

### 4.5 Growth System

#### Probability-Based Growth

```
On level up, each growing attribute (HP/STR/MAG/DEX/LCK/DEF/RES) is independently checked:
  if random() < growth_rate[stat]: stat += 1

SPD / MOV / VIS do not participate in level-up growth.

growth_rate example (soldier):  HP:50% STR:45% MAG:10% DEX:40% LCK:30% DEF:35% RES:15%
growth_rate example (mage):     HP:35% STR:10% MAG:50% DEX:35% LCK:35% DEF:15% RES:40%
```

#### Pity Mechanic

```
Each attribute maintains a hidden fail_count:
  Check failed -> fail_count += 1; check succeeded -> fail_count = 0
  fail_count >= pity_threshold -> forced +1, counter reset

pity_threshold:
  growth_rate >= 40%:  pity = 3 (guaranteed after 3 consecutive failures)
  growth_rate 20%-39%: pity = 5
  growth_rate < 20%:   pity = 8
```

### 4.6 TTK Numerical Verification

| Unit | HP | STR | DEX | SPD | LCK | DEF | Weapon Might | Hit |
|------|----|----|-----|-----|-----|-----|-------------|-----|
| soldier | 28 | 8 | 6 | 7 | 4 | 6 | 5 (Iron Sword) | 90 |
| goblin | 22 | 6 | 3 | 5 | 1 | 4 | 3 (Rusty Axe) | 75 |

| Direction | base | Hit Rate | Crit Rate | Follow-up Rate | TTK (expected) | Evaluation |
|-----------|------|----------|-----------|----------------|----------------|------------|
| soldier->goblin | 9 | 94% | 2% | 20% | **≈ 3 turns** | ✅ Within target 3-8 |
| goblin->soldier | 3 | 66% | 0% | 0% | **≈ 15 turns** | ✅ Weak differential reasonable |

> **Numerical Calibration Statement**: The data in this section is for algorithm verification purposes, confirming formula structural correctness (additive buffer effective, TTK convergence range reasonable). Specific values (HP/STR/DEF/Might) are subject to independent calibration during the game balancing phase and do not affect the algorithmic conclusions of this ADR.
> Reference anchor: goblin HP=26, weapon_might=4 -> TTK≈4-5 turns (can serve as starting point for the balancing phase).

### 4.7 Three Cultivation Pillar Interfaces

| Cultivation Source | Affected Layer | Example |
|-------------------|---------------|---------|
| **Talent Tree** | Passive abilities + minor stats + active skills + Block effects | "Sword Intent Focus" ATK+12%; "Iron Wall" melee damage reduction 30% |
| **Equipment** (weapons + armor) | weapon_might + accuracy/crit + DEF/RES + stat bonuses | Iron Sword: might=5, hit=90, DEX+2 |
| **Relics** (Roguelite) | Independent multiplicative zone + mechanic changes + Block effects | "Burning Heart" fire damage x1.2; "Iron Shield" 30% chance to reduce damage by 50% |

### 4.8 Weapon Design Framework

| Tier | Might | Hit | Stat Bonus | Special Effect | Acquisition |
|------|-------|-----|-----------|----------------|-------------|
| Tier 0 (Rusty) | 2-3 | 70-75 | None | None | Starting/drop |
| Tier 1 (Iron) | 4-6 | 85-90 | +2~4 stats | None | Shop/basic smithing |
| Tier 2 (Steel) | 7-9 | 80-85 | +3~5 stats | Basic effect | Intermediate smithing |
| Tier 3 (Silver) | 10-12 | 75-80 | +4~6 stats | Enhanced effect | Advanced smithing/rare |
| Tier S (Legendary) | 12-15 | 85+ | Special | Unique mechanic | Story/extreme difficulty |

Weapon JSON structure (no weight field):
```json
{
  "id": "iron_sword", "name": "Iron Sword",
  "damage_type": "physical", "attack_type": "melee",
  "might": 5, "hit": 90, "crit": 0, "range": [1],
  "stat_bonus": { "DEX": 2 },
  "tier": 1, "forge_level": 0, "forge_might_bonus": 0
}
```

---

## 5 - Impact Scope

### Key Decision Points

| # | Decision | Content | Rationale |
|---|----------|---------|-----------|
| 1 | Attribute system restructure | 14->10 attributes, FE naming | Reduce cognitive load, DEX/LCK high reuse |
| 2 | Damage formula changed to additive + multiplicative zones | base=STR+might-DEF, outer layer retains multiplicative zones | Additive solves zero-damage/TTK; multiplicative zones for Roguelite scaling |
| 3 | Remove Block, add Luck | block->Talent/Equipment/Relic effect; LCK merges crit evasion + status resistance | Block becomes a Build choice rather than universal attribute |
| 4 | SPD/MOV do not grow | Fixed + Class Advancement/Talents/Relics/Equipment | Every point of change is an explicit tactical decision |
| 5 | Relic independent multiplicative zone | Damage formula adds relic modifier zone | Roguelite effects independent, predictable, balanceable |
| 6 | Probability growth + pity | FE probability growth + fail_count pity | Replayability + prevent extreme bad luck |

### Files Requiring Modification

| File | Change | Cost |
|------|--------|------|
| `scripts/units/unit_stats.gd` | Attribute rename + add DEX/LCK + remove hit/evade/crit/crit_evade/block/resistance + pity mechanic | **High** |
| `scripts/core/damage_calculator.gd` | Formula rewrite + remove Block + add Relic multiplicative zone + accuracy/crit derivation | **High** |
| `scripts/core/battle_manager.gd` | Remove Block check step | Low |
| `data/classes/*.json` (5 files) | Attribute name update + growth_rate fields | Medium |
| `data/enemies/*.json` (3 files) | Attribute name update | Low |
| Weapon JSON (to be created) | Add might/hit/crit/stat_bonus structure | Medium |
| Armor JSON (to be created) | DEF/RES bonus structure | Low |
| `01-Game-Design/Core-Systems/battle-calculation.md` | Full rewrite | **High** |

**Overall modification cost: High**

### Old to New Attribute Mapping

| Old Attribute | New Attribute | Notes |
|--------------|--------------|-------|
| phys_atk | STR | Renamed |
| mag_atk | MAG | Renamed |
| physical_defense | DEF | Renamed |
| magical_defense | RES | Renamed |
| hit | — | Removed, derived from DEX*2 + LCK*0.5 + weapon_hit |
| evade | — | Removed, derived from SPD*2 + LCK*0.5 |
| crit | — | Removed, derived from DEX/2 + weapon_crit |
| crit_evade | LCK | Merged (crit evasion = LCK) |
| block | — | Removed as base attribute (converted to Talent/Equipment/Relic special effect) |
| resistance | LCK | Merged (status resistance formula adjusted) |
| speed | SPD | Renamed, does not grow |
| move | MOV | Renamed, does not grow |
| vision | VIS | Renamed |

### Compatibility with ADR-004

| ADR-004 Decision | Status | Notes |
|-----------------|--------|-------|
| phys_atk / mag_atk split | ✅ Preserved (renamed STR/MAG) | Dual attribute architecture unchanged |
| Four damage types | ✅ Preserved | physical/magical/hybrid/pure |
| phys_power / mag_power | ❌ Replaced | -> weapon_might / tome_might (additive) |
| armor_resist / magic_resist | ❌ Removed | Additive formula does not need them |
| Crit rate uncapped | ✅ Preserved | |
| Pure crit fixed x1.5 | ✅ Preserved | |

### Hybrid Follow-Up Review Items - No Decision Yet

1. Is `(STR + MAG) + hybrid_might - min(DEF, RES)` dual attribute direct addition too strong?
2. How to balance STR/MAG growth allocation for hybrid classes?
3. How to define hybrid_might - take average or independent field?
4. What is hybrid efficiency when STR and MAG have extreme disparity?

---

*Created: 2026-02-27 | Revised: 2026-02-27 | Design Agent (Antigravity x Claude Opus + Gemini 3.1 Pro dual-round review) | Status: ✅ Approved, ready for execution phase*

## Dual-Round Review Comparison Summary - 2026-02-27

### Consensus
- **Zero-damage floor mechanism**: Introducing `max(1, ...)` was verified as a self-consistent solution to the prototype's "zero-damage cliff".
- **Shortened TTK expectation**: The 3-15 turn TTK verification data from the new formula is logically self-consistent.
- **Remove Block**: Completely removed from base attributes; mechanic transferred to Talent and Equipment systems with no gaps.
- **Introduce LCK**: Takes over accuracy, crit evasion, status resistance - formula definitions are complete and implementation-ready.
- **Remove AS/weapon weight**: No residuals found in weapon design framework, thoroughly implemented.
- **SPD/MOV do not grow**: Precisely removed from attribute growth table, preventing mechanic bloat.
- **Overall architecture compatibility**: Good alignment with ADR-004 prerequisites (four damage type split).

### Divergences
| Divergence | Input A Position - Original ADR | Input B Finding - Review | Divergence Type | Which Side Is More Rigorous |
|---|---|---|---|---|
| **ATK/DEF ratio exceeds target bounds** | Target upper limit is 60% | Section 4.6 verification case: defender DEF=6 vs attacker ATK(6+3)=9, ATK/DEF ratio reaches 66.7%, exceeding its own established benchmark | Numerical contradiction | Input B (numbers reveal inconsistent strictness) |
| **Hybrid deferred mechanic prematurely solidified** | Declared hybrid deferred, "how to determine average pending future review" | Section 4.2 not only established hybrid dual-scaling, but explicitly hardcoded `take average` (STR+MAG+might/2) formula | Logic/process contradiction | Input B (unresolved items should not invade base formula) |
| **Crit insignificance problem lacks solution** | Crit multiplier kept at x1.5 as-is (no adjustment) | Background listed "crit feels insignificant" as core pain point, yet solution forcefully retains extremely low crit rate and multiplier without providing a fix | Logic contradiction | Input B (raising a problem without solving it is a broken chain) |
| **Follow-up Attack mechanic lacks substantive improvement** | Directly copied original model `speed_diff x 10%` | Identified low probability gap as non-triggering during announcement, yet mechanism has zero changes, only cosmetically improved by inflating base attribute differences in examples | Ambiguity/omission | Input B (pain point not addressed at the mechanic level) |

### Decision Priority Assessment
- RED - **Must be resolved before execution**:
  1. **ATK/DEF ratio (>60%) exceeds control bounds**: Directly impacts base numerical balance (TTK reverse-derivation foundation). If keeping the example, must relax to 70% declaration; if strictly holding 60%, must readjust section 4.6 examples.
  2. **Hybrid formula premature solidification**: If section 4.2 is passed to the code layer, it will produce `hybrid_might` and other insufficiently analyzed new attribute inputs or even code coupling - this is a code interface intrusion issue.
- YELLOW - **Recommended to clarify before execution**:
  1. **Crit insignificance**: Damages playstyle consistency. Recommend reconsidering multiplier or declaring in document that this pain point is split off for separate ADR discussion.
  2. **Follow-up Attack model remains theoretical**: Long-term, equal-speed matchups still will not trigger follow-up attacks initially. The document needs an endorsement statement saying "this aligns with the new expectations".

### Final Status
**Pending revision (contains core intrusive deviations)**

**Minimum revision set (must be resolved before execution, 4 items total):**
1. [Numerical] Readjust section 4.6 base example unit values (ensure `DEF / (ATK+MIGHT) <= 60%`), or revise the 60% ATK/DEF ratio hard limit statement in chapter 1.
2. [Interface] Remove the definitive formula details containing `hybrid_might` from section 4.2, replace with pseudocode or explicitly label as deferred placeholder to prevent leakage.
3. [Logic] Modify or remove the "crit insignificance" wording from chapter 1 as a must-solve issue, or establish a fix in section 4.3.
4. [Logic] Remove the chapter 1 claim criticizing poor follow-up attack experience, and redefine the characterization of the "conservative speed-difference probability model".


## Revision Completion Confirmation - 2026-02-27, Human Supervisor

Minimum revision set has been fully executed. ADR-005 enters executable state:

| Revision Item | Decision | Status |
|---|---|---|
| ATK/DEF ratio exceeding bounds | Values are for verification purposes, subject to independent calibration during balancing phase, does not affect algorithmic conclusions; calibration statement added to section 4.6 | ✅ |
| Hybrid formula intrusion | Section 4.2 hybrid content entirely replaced with TBD pseudocode, labeled as unresolved until ADR-006 is finalized | ✅ |
| Crit insignificance | Accepted x1.5 as official design; removed the item from background problem list, maintaining consistency | ✅ |
| Follow-up Attack probability model | Officially declared "speed_diff x 10%" as core intent, not a temporary solution; future weight modifiers may be layered on | ✅ |
