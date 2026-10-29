# Attribute System First Integration Analysis Task

> ⚠️ **ARCHIVED** — This file is a historical analysis archive (2026-02-27, Antigravity). Decision conclusions have been written to ADR-005 (`02-Development/Decisions/adr-2026-02-27-attribute-system-v1.md`). Do not modify this file; use ADR-005 as the authoritative reference.

**Trigger Condition**: Execute after M5 battle loop verification is complete
**Execution Tool**: Antigravity (Gemini, full document context)
**Expected Timing**: M5 verification complete → before M6 starts

---

## Task Background

The current attribute system is a prototype design, a simplified model built on ADR-001~004.
After M5 completes, real battle data will be generated for the first time, used to verify whether the attribute design meets expected game feel.

**Unresolved Fundamental Questions**:
1. Is the phys_atk / mag_atk dual-attribute architecture appropriate for this game's positioning?
2. How do attribute growth methods (linear? probabilistic? fixed values?) integrate with the Roguelite layer?
3. Can the numerical ranges for hit/crit/block produce a "calculated feel" rather than a "pure RNG feel"?
4. At which layer should Town Building's influence on attributes be applied (base attribute bonus vs final damage multiplier)?

---

## Antigravity Prompt (Use After M5 Verification)

```
You are the Design Agent for Ship of Theseus.
Task: Perform the first integration analysis of the current character attribute system, outputting structured design recommendations.

## Your Working Directory
D:\ShipOfTheseus\ShipOfTheseus-KB\

## Required Reading (in order)
1. 01-Game-Design/Core-Systems/battle-calculation.md (current damage formula)
2. 01-Game-Design/Core-Systems/turn-system.md (turn system)
3. 01-Game-Design/Characters/ (class system related documents)
4. 02-Development/Decisions/adr-2026-02-27-damage-type-redesign.md (ADR-004)
5. 02-Development/Tasks/attr-system-deduction-task.md (this file, for task background)
6. 03-AI-Context/Active-Context/current-session.md (M5 test data)

## M5 Test Data (read the following fields from current-session.md)
- Baseline TTK for soldier vs goblin_melee (under hit conditions)
- Expected TTK (accounting for hit rate)
- Subjective evaluation of crit/block trigger frequency
- Measured gap between hybrid damage values vs physical

## Analysis Framework

### Part 1 - Current System Diagnosis
Evaluate the current prototype attribute system (phys_atk/mag_atk/def/magic_def/hit/evade/crit/block/speed/move) across these dimensions:

| Dimension | Goal | Current State | Issues |
|---|---|---|---|
| Attribute count | Player can intuitively understand | | |
| Growth depth | Noticeable difference from Lv1~Lv10 | | |
| Crit/Block RNG impact | Results within expectations, occasional surprises | | |
| Roguelite modifier space | Each Run feels noticeably different | | |
| 2-player co-op balance | Skill gap can compensate for attribute gap | | |

### Part 2 - Fire Emblem Comparison

**Fire Emblem (FE7/FE8 standard formula) attribute system**:
- Primary attributes: STR/MAG, SKL (Skill), SPD (Speed), LCK (Luck), DEF, RES
- Secondary derivations:
  - Hit rate = weapon hit + SKL×2 + LCK×0.5
  - Crit rate = weapon crit + SKL/2 (FE8)
  - Evasion = SPD×2 + LCK
  - Damage = STR/MAG + weapon might - DEF/RES (direct subtraction)
- Characteristics:
  - No armor resistance coefficient — attributes subtract directly
  - LCK affects both hit and crit avoidance
  - Speed determines follow-up attacks (triggers at speed gap ≥4)

**Differences from this game's current system**:
- This game: phys_atk + mag_atk dual primary attributes (FE uses one or the other)
- This game: armor_resist coefficient (no equivalent in FE)
- This game: block (FE has no block mechanic)
- This game: resistance status resistance (FE uses Luck instead)
- This game: hybrid damage type (FE has none, relies on weapon triangle)

Analysis: Which differences are this game's core competitive advantages? Which add complexity without clear benefit?

### Part 3 - Three Proposal Analysis

Generate three attribute proposals, each containing:
- Complete attribute list (name, meaning, growth properties)
- Damage formula (how physical/magical/hybrid/pure each calculate)
- Hit/crit/block calculation methods
- Typical build paths under this proposal (2 examples)
- Interface design with Town Building / Roguelite modifiers
- Pros and cons analysis

**Proposal A (FE-simplified)**: Use Fire Emblem as base, minimize changes to accommodate this game's hybrid type and block mechanic
**Proposal B (Current prototype extended)**: Refine existing phys_atk/mag_atk foundation, fix known issues
**Proposal C (Roguelite-first)**: Reduce attributes to bare minimum, Roguelite modifiers carry most differentiation

### Part 4 - Recommended Proposal + Implementation Path

Based on the above analysis, provide:
1. Recommended proposal (can be hybrid)
2. Difference list from current prototype (which files need modification)
3. Modification cost assessment (low/medium/high)
4. Key decision points recommended for ADR-005

## Output Format
Create a new file adr-2026-MM-DD-attribute-system-v1.md under 02-Development/Decisions/
and append an analysis summary to the end of this file (attr-system-deduction-task.md).
```

---

## M5 Test Data (Godot Verified, 2026-02-27)

### Unit Base Attributes (Tested)
| Unit | phys_atk | def | hit | evade | crit | block | speed | HP |
|---|---|---|---|---|---|---|---|---|
| soldier | 10 | 9 | 80 | — | 8 | — | 8 | 100 |
| goblin_melee | 7 | 7 | — | 7 | — | 0 | 7 | 82 |

### Tested Battle Data
| Direction | Single Base Damage | Hit Rate | TTK (all hit) | TTK (expected) |
|---|---|---|---|---|
| soldier → goblin | **3** | **73%** | 28 turns | **39.0 turns** |
| goblin → soldier | **0** ⚠️ | 64% | ∞ | **TTK=999** |

### Key Findings
1. **Zero-damage cliff**: goblin(phys_atk=7) vs soldier(def=9), 7-9=-2 → max(0,-2) = 0, completely unable to deal damage
2. **TTK severely too long**: soldier→goblin expected TTK=39 turns, FE standard is 3-8 turns, gap of 5~13x
3. **Follow-up attack never triggers**: speed difference only 1 (soldier=8, goblin=7), follow-up probability=10%, not the main TTK problem
4. **Crit impact minimal**: crit=8, low probability, negligible improvement to TTK
5. **Defense/attack ratio**: goblin def/soldier phys_atk = 7/10 = 70% (target 40-60%); soldier def/goblin phys_atk = 9/7 = **129%** (far above cap, causes zero damage)

### User Analysis Anchors (Human Supervisor Confirmed)
1. **Zero-damage floor**: Consider `base = max(1, atk × power - def × resist)` to guarantee at least 1 damage
2. **Defense/attack ratio target**: def/atk in 40%-60% range → damage ≈ 40%-60% of atk → TTK ≈ 5-8 turns
3. **weapon_power intervention**: Introducing weapon multiplier changes formula to `atk × 1.2 - def × 1.0`, alleviates over-defense problem (similar to FE weapon might buffer)
4. **Terrain and movement calibration**: move=3 is too low for dense forest maps, needs recalibration

### FE8 Comparison (Weapon Might Buffer Effect)
FE8: soldier(STR=7) using Iron Lance(might=8) attacks goblin(DEF=5): `7+8-5 = 10` damage
FE8 core insight: **weapon might acts as a baseline buffer, ensuring damage occurs even when STR < DEF** — this game's phys_power can serve the same role

---

## Reference Materials

### Fire Emblem Attribute Range Reference (FE8, Lv1 Initial)
| Class | STR | MAG | SKL | SPD | DEF | RES | LCK |
|---|---|---|---|---|---|---|---|
| Soldier | 7 | 0 | 5 | 5 | 5 | 0 | 3 |
| Mage | 1 | 7 | 4 | 6 | 2 | 5 | 4 |
| Knight | 9 | 0 | 4 | 3 | 9 | 0 | 2 |
| Cleric | 0 | 5 | 2 | 3 | 0 | 4 | 5 |

FE8 damage formula: `ATK - DEF = direct subtraction (minimum 0)`, no armor resistance coefficient layer.

---

*Created: 2026-02-27 | Status: ✅ M5 data embedded, ready to trigger | Owner: Antigravity*

---

## Analysis Summary (2026-02-27, Antigravity)

Recommended Proposal A (FE-simplified). Attributes 14→10, aligned with Three Houses/Engage. Base layer addition (STR+might-DEF) + multiplier layer with relic independent multiplier. Remove block → talent/equipment/relic effect. LCK merges crit avoidance + status resistance. SPD/MOV do not grow. Probabilistic growth + floor guarantee. TTK≈3 turns. See ADR-005 for details.
