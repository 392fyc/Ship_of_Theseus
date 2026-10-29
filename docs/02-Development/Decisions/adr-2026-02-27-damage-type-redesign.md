# ADR-004 - Damage Type System Redesign

**Date**: 2026-02-27
**Status**: Accepted
**Decision Maker**: Human Supervisor

---

## Current-State Notice - added 2026-08-03

**This is a historical record. Do not implement from it, and do not quote its formulas as current.** The decision text below is preserved exactly as it was ruled on 2026-02-27. What survives from this ADR is its *architecture* - the four attribute types (physical / magical / pure / hybrid), the physical/magical attack split, and the `pure_atk_source` field. Its *formulas* were replaced wholesale by ADR-005's additive base layer and are now governed by the rule table (design library `/rules`; KB index `01-Game-Design/rules-catalog.md`; system document `01-Game-Design/Core-Systems/battle-calculation.md`).

| Statement in this ADR | Where | Current state |
|---|---|---|
| `Block: YES` on physical / magical / hybrid; `Block: NO` on pure | §C | **Block no longer exists.** It was removed as a base attribute by ADR-005 and then deleted outright on 2026-07-06, talent and relic layers included. There is no block step anywhere in damage resolution. The swordsman's parry is a separate mechanic and is unaffected ("parry is not block"). |
| Pure crit "off by default; if enabled, fixed x1.5, unaffected by crit multiplier bonuses"; the same claim repeated in §D | §C, §D | **Pure damage does not participate in the crit chain at all** - no crit roll, no crit zone, and no per-skill switch that can enable one (R1.1 / R1.3). Neither `crit_damage_bonus` (additive) nor "crit multiplier xN" (multiplicative) applies to it. |
| `weapon_hybrid_power = (phys_power + mag_power) / 2`, and hybrid `base = (phys_atk + mag_atk) * weapon_hybrid_power - min(def * armor_resist, magic_def * magic_resist)` | §C, the "Hybrid Design Intent" worked example, and the closing Trade-offs section | **Superseded by ADR-006 (2026-08-03).** Hybrid now runs the physical and magical branches separately, each with its own `max(0, ...)` floor, and averages the two results. Note that all four fields this formula reads - `phys_power`, `mag_power`, `armor_resist`, `magic_resist` - **no longer exist in the codebase**; ADR-005 replaced them with a single additive `weapon_might`. The sentence "hybrid takes the average weapon power" derives from this line; the Godot repository's agent rule files quoted it until 2026-08-03 and now read "one `weapon_might`, two branches, averaged result". ADR-006 rejects the `min(DEF, RES)` direction outright, so the closing Trade-offs line "the 'take lower defense' direction was correct" no longer holds. |
| Hybrid "Skill multipliers are typically lower than same-tier physical/magical skills" | §C, restated in the "Hybrid Design Intent" closing line ("dedicated skill multipliers are limited") | **No longer has a basis.** That note was compensation for the free `abs(DEF - RES) / 2` surcharge carried by the old `min` defence term; ADR-006 removed the surcharge, so the note carries no force. Whether hybrid skills need any multiplier offset at all is now an ordinary per-skill balancing question, left open by ADR-006 ("What this ADR does not settle"). |
| Multiplicative base layer generally: `base = atk * power - def * resist` for physical, magical and pure | §C | **Replaced by the additive base layer.** Current: physical `max(0, STR + weapon_might - DEF)`, magical `max(0, MAG + weapon_might - RES)`, pure `max(0, [source] + weapon_might)` ignoring all defence, plus a derived pure form that converts a percentage of a preceding physical/magical final damage (R1.1). |
| Attribute and field names `phys_atk` / `mag_atk` / `def` / `magic_def` | Throughout | Renamed by ADR-005 to `STR` / `MAG` / `DEF` / `RES`. The split itself is preserved; only the names changed. |

Still current from this ADR: the four-type taxonomy, `holy` renamed to `pure`, the `pure_atk_source` field (`"phys"` / `"mag"` / `"sum"`), and the removal of the crit rate cap (R1.3 keeps crit rate uncapped, floor 0).

---

## Background

The original design used a single `attack` attribute shared between physical and magical damage types. After introducing the `hybrid` damage type, it became necessary to clearly separate physical attack power and magical attack power to support the design intent of hybrid attacks "benefiting from both physical and magical attribute bonuses."

The original `hybrid` formula (take lower defense, single attack attribute) made hybrid permanently inferior to pure-type damage, providing no design value.

The `holy` type was renamed to `pure` (pure damage) for more neutral semantics, and a new `pure_atk_source` field was added so skills can flexibly declare which attack attribute to use.

---

## Decision

### A. Attack Attribute Split

| Old Field | New Field | Affected Damage Types |
|---|---|---|
| `attack` | `phys_atk` | physical, hybrid |
| `magic` | `mag_atk` | magical, hybrid |

Both attributes scale with level, with growth rates varying by class:
- Physical classes: high phys_atk growth, low mag_atk growth
- Magical classes: the reverse
- Hybrid classes: balanced growth for both

### B. Weapon Power Split

| Old Field | New Field | Description |
|---|---|---|
| `weapon_power` | `phys_power` | Physical weapon power (most physical weapons have this field) |
| (none) | `mag_power` | Magical weapon power (catalysts have this field, others default to 1.0) |

Most weapons only have one of the two power values, with the other defaulting to 1.0. Dual-scaling weapons with two non-1.0 power values exist but are rare.

### C. Final Formulas for Four Damage Types

```
physical:
  base = phys_atk * phys_power - def * armor_resist
  Crit: YES (with crit multiplier bonuses)  Block: YES

magical:
  base = mag_atk * mag_power - magic_def * magic_resist
  Crit: YES (with crit multiplier bonuses)  Block: YES

pure (formerly holy):
  base = [pure_atk_source] * weapon_power  (ignores all defense)
  pure_atk_source declared in skill JSON:
    "phys" -> uses phys_atk
    "mag"  -> uses mag_atk
    "sum"  -> uses phys_atk + mag_atk (rare high-power skills)
  Crit: off by default; if enabled, fixed x1.5, unaffected by crit multiplier bonuses
  Block: NO  Terrain modifier: YES

hybrid:
  weapon_hybrid_power = (phys_power + mag_power) / 2
  base = (phys_atk + mag_atk) * weapon_hybrid_power
         - min(def * armor_resist, magic_def * magic_resist)
  Crit: YES (with crit multiplier bonuses)  Block: YES
  Skill multipliers are typically lower than same-tier physical/magical skills
```

### D. Critical Hit Rate Cap Removal

- Removed the original 50% cap, changed to uncapped (min 0%, no max)
- Enemy high crit is controlled through encounter design templates, not relying on a system cap
- If pure damage has crit enabled, fixed 1.5x, unaffected by "crit multiplier bonus" affixes

---

## Hybrid Design Intent - Detailed Explanation

```
Example: phys_atk=10, mag_atk=8, physical weapon (phys_power=1.3, mag_power=1.0), enemy def=3, magic_def=5

Physical class (phys_atk only): 10 * 1.3 - 3 = 10.0
Magical class (mag_atk only): 8 * 1.0 - 5 = 3.0
Hybrid class (dual-scaling): (10+8) * (1.3+1.0)/2 - min(3,5) = 18 * 1.15 - 3 = 17.7
```

**Key property: hybrid yields consistent returns regardless of attribute distribution**
- phys_atk=9, mag_atk=9 -> (9+9)*1.15-3 = 17.7 (same)
- phys_atk=15, mag_atk=3 -> (15+3)*1.15-3 = 17.7 (same)

Hybrid ensures that builds which "happen to have dual-scaling attributes" waste no attribute points.
Trade-off: weapon power is averaged, and dedicated skill multipliers are limited.

---

## Impact Scope

| File | Change |
|---|---|
| `scripts/units/unit_stats.gd` | `atk` -> `phys_atk` + `mag_atk` |
| `data/classes/*.json` (5 files) | `"attack"` -> `"phys_atk"` + `"mag_atk"` |
| `data/enemies/*.json` (3 files) | Same as above |
| Weapon JSON (to be created) | `"weapon_power"` -> `"phys_power"` + `"mag_power"` |
| `scripts/core/damage_calculator.gd` | Implement with new formulas in M5 (new file) |
| `01-Game-Design/Core-Systems/battle-calculation.md` | Full formula documentation update |

---

## Trade-offs

**Reasons for choosing this approach**:
- Hybrid dual-attribute bonuses come from the character's actual two attribute types, making values intuitive and controllable
- Weapon power averaging prevents dual-high-power weapons from being overpowered
- Pure's `pure_atk_source` field lets skills flexibly specify the attribute source without adding new character attributes
- Uncapped crit rate encourages specialized crit builds, deepening Roguelite affix choices

**Reasons for abandoning the original hybrid formula - min defense with single atk**:
- With a single atk, hybrid = physical against low physical defense targets, = magical against low magic defense targets, providing no unique value
- The "take lower defense" direction was correct, but requires dual-attribute bonuses to form a distinct identity
