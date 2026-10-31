# ADR-006 - Hybrid Damage Formula

**Date**: 2026-08-03
**Status**: Accepted
**Decision Maker**: Human Supervisor
**Prerequisites**: ADR-004 (Damage Type System Redesign), ADR-005 (Attribute System First-Round Integration Simulation)
**Rule Anchors**: R1.1 (damage chain), R1.7 (weapon parameter framework), R1.8 (formula layering and modifier algebra)

---

## Background

`hybrid` is one of the four attribute-type damage categories. It was specified twice and settled neither time.

**ADR-004 (2026-02-27)** defined it as

```
weapon_hybrid_power = (phys_power + mag_power) / 2
base = (phys_atk + mag_atk) * weapon_hybrid_power - min(def * armor_resist, magic_def * magic_resist)
```

ADR-005 then rebuilt the base layer as FE-style additive damage, which removed `phys_power`, `mag_power`, `armor_resist` and `magic_resist` from the system entirely. None of the inputs of that formula exist any more; the only part of it still quoted in downstream documents is the phrase "hybrid takes the average weapon power", which no longer refers to anything.

**ADR-005 (2026-02-27)** did not put a replacement in its place. Its dual-round review classified the hybrid formula as an unresolved item that had invaded the base formula, and the agreed minimum revision set replaced §4.2's hybrid entry with a TBD comment block, "considered unresolved until ADR-006 is finalized".

**ADR-006 was never written.** The number was reserved on 2026-02-27 and the file was never created. The TBD has been quoted ever since - by `01-Game-Design/Core-Systems/battle-calculation.md`, by `01-Game-Design/game-design-doc.md`, and by a `TBD (ADR-006)` comment in the Godot damage calculator - for five months, all of them pointing at a document that did not exist.

What did get written into the engine, behind that TBD comment, is the exact shape ADR-005 had put a question mark on. ADR-005's first open follow-up question reads: "Is `(STR + MAG) + hybrid_might - min(DEF, RES)` dual attribute direct addition too strong?" - and the stub answered `min(DEF, RES)`. Nothing was ever built on top of it, because no content uses the hybrid type at all (see Migration Cost).

This ADR closes the TBD.

---

## Decision

Hybrid runs the physical branch and the magical branch **separately - each one a complete R1.1 additive-layer calculation carrying its own `max(0, ...)` floor** - and takes the **arithmetic mean** of the two results.

```
hybrid:
  physical_branch = max(0, STR + weapon_might - DEF_eff)
  magical_branch  = max(0, MAG + weapon_might - RES_eff)
  base_damage     = (physical_branch + magical_branch) / 2
```

Binding notes:

1. **This is not "subtract an averaged defence once".** `max(0, (STR + MAG)/2 + weapon_might - (DEF_eff + RES_eff)/2)` is a different formula. The two agree only while neither branch is clipped by its floor; they diverge exactly in the case that matters, a target that walls one damage type completely. Do not "simplify" the implementation into the single-subtraction form.
2. **One `weapon_might`, entering both branches unchanged.** There is no `hybrid_might` field and no averaging of two weapon power values. R1.7 makes `weapon_might` the single weapon-side damage parameter and weapons do not distinguish damage type, so both branches read the same number.
3. **`DEF_eff` / `RES_eff` are the defence values actually facing each branch** - base terrain defence bonus already added (R4.2, layer 1), penetration already applied at the consumption point (`Q_eff = Q x (1 - sum ignore%) - sum ignore points`, R1.8). Each branch resolves its own side: an effect that ignores physical defence touches the physical branch only, and likewise for the magical branch.
4. **Rounding follows R1.8.** The division by 2 produces a legitimate half-integer intermediate. Intermediates are not rounded; only the final damage is floored, at the outermost layer, after the multiplicative zones.
5. **The result is an ordinary `base_damage`.** It enters the layer-2 multiplicative chain (skill / terrain / crit / relic / final) with no special casing. Hybrid participates in the crit chain the same way physical and magical do - the exclusion in R1.1 / R1.3 applies to pure damage only.

---

## Rationale

### Why the `min(DEF, RES)` shape was rejected

The proposal on the table before this ruling was `(STR + MAG)/2 + weapon_might - min(DEF, RES)`: average the two attack attributes, then subtract the target's weaker defence. It was rejected on an identity that holds independently of any numerical calibration. (The engine stub and ADR-005's open question use the same defence term but add the two attributes at full weight, without the `/2`; that variant is strictly stronger again, so everything below applies to it as well.)

Write the two branch values before the floor as `P = STR + might - DEF` and `M = MAG + might - RES`. Then

```
  (STR + MAG)/2 + might - min(DEF, RES)
=  (P + M)/2 + (DEF + RES)/2 - min(DEF, RES)
=  (P + M)/2 + |DEF - RES| / 2
```

The first term is the average that was actually wanted. The second term, `|DEF - RES| / 2`, is a pure surcharge that arrives for free and grows without limit as the target's two defences drift apart.

The degenerate case makes the size of the problem concrete. When `STR = MAG` - the attribute profile of the very classes hybrid exists for - the rejected shape collapses to

```
max(0, STR + might - min(DEF, RES)) = max( max(0, P), max(0, M) )
```

that is, **exactly the better of the two pure branches**, and this holds precisely, the `max(0, ...)` floor included. Hybrid would deliver the best single-type result at all times while paying nothing for it. A damage type whose price is zero for its own target audience is not a trade-off; it is a strictly dominant option, and every dual-attribute class would take it unconditionally.

### What the adopted shape changes

The defect is entirely in the defence term, not in the idea of averaging. Averaging the two finished branches removes the `|DEF - RES| / 2` surcharge and leaves the price of choosing hybrid at

```
better pure branch - hybrid = |physical_branch - magical_branch| / 2
```

Under the rejected shape the same comparison, with `DEF = RES` held fixed to isolate the player side, gives `|STR - MAG| / 2`. The difference between the two cost terms is what settles it:

| | Rejected shape | Adopted shape |
|---|---|---|
| Cost term | `abs(STR - MAG) / 2` | `abs(DEF - RES) / 2` |
| It hangs on | The player's own attribute spread | The target's defence spread |
| Cost at the intended build (`STR = MAG`) | `0` | `abs(DEF - RES) / 2` |
| Can the player remove it | Yes - it dissolves itself the further the build commits to hybrid, and is exactly zero at the build the type exists for | No - the term belongs to the enemy and the player cannot touch it |
| Extreme enemies | Cost stays zero, payoff grows | Cost and payoff grow together |

The adopted shape gives hybrid a real and permanent identity: it is the option that never gets fully walled - a target that stops one damage type outright still takes half of the other branch - and it pays for that by never being the best answer against a target that is soft in exactly one defence.

### Worked examples

The free-surcharge case (`weapon_might = 5`, `STR = MAG = 12`, target `DEF = 4` / `RES = 10`):

| Line | Result |
|---|---|
| physical branch | `max(0, 12 + 5 - 4)` = **13** |
| magical branch | `max(0, 12 + 5 - 10)` = **7** |
| Adopted hybrid | `(13 + 7) / 2` = **10** |
| Rejected shape | `12 + 5 - min(4, 10)` = **13** - identical to the pure physical line, i.e. free |

Floor case, showing why the single-subtraction rewrite is not equivalent (`weapon_might = 4`, `STR = MAG = 6`, target `DEF = 2` / `RES = 30`):

| Line | Result |
|---|---|
| physical branch | `max(0, 6 + 4 - 2)` = **8** |
| magical branch | `max(0, 6 + 4 - 30)` = **0** (floored) |
| Adopted hybrid | `(8 + 0) / 2` = **4** |
| Subtracting an averaged defence once | `max(0, 6 + 4 - 16)` = **0** |

Half of one working branch versus nothing at all. Whenever both branches stay above their floor the two expressions coincide, which is why the difference is easy to miss and why note 1 above is binding.

### Migration cost

Zero. The `hybrid` enum value is currently used by **no card at all** - measured 2026-08-03 across the design library's full inventory of 39 talent cards and 11 skill cards. Nothing in content has to be re-tuned, and the engine stub can be replaced outright rather than migrated.

---

## Answers to ADR-005's four open hybrid questions

| # | ADR-005 §5 question | Answer |
|---|---|---|
| 1 | Is `(STR + MAG) + hybrid_might - min(DEF, RES)` dual attribute direct addition too strong? | Yes, on both counts, and it is rejected. The adopted shape neither adds the two attributes at full weight nor takes the lower defence. |
| 2 | How to balance STR/MAG growth allocation for hybrid classes? | Not a formula question. Growth allocation is per-class calibration on the R2.3 tier scale and lives in `01-Game-Design/Characters/class-system.md`. The formula is neutral to it: it reads whatever STR and MAG the class ends up with. |
| 3 | How to define `hybrid_might` - average or independent field? | The question is void. There is no `hybrid_might`. R1.7 leaves exactly one weapon damage parameter, `weapon_might`, and both branches read it unchanged. |
| 4 | What is hybrid efficiency under extreme STR/MAG disparity? | Determined by the shape, no extra rule needed. Each branch floors at 0 independently, so a dead branch contributes 0 rather than a negative number, and hybrid degrades smoothly to half of the live branch. There is no cliff and no falloff clause. |

---

## What this ADR does not settle

- **Enemy DEF/RES spread.** Ruled 2026-08-03: **not set this round.** The order of work is player-side modelling first, then reverse-deriving enemy numbers from the resulting strength evaluation. Until that happens there is no authoritative scale for how far apart an enemy's two defences may sit, so no document should invent one. This ADR fixes the *shape* of the hybrid formula; it does not calibrate it.
- **Hybrid skill multipliers.** ADR-004 noted that hybrid skill multipliers "are typically lower than same-tier physical/magical skills". That was compensation for the free `|DEF - RES| / 2` surcharge, which no longer exists, so the note carries no force. Whether hybrid skills need any multiplier offset at all is an ordinary per-skill balancing question, left open here.
- **Which classes use hybrid.** No class is assigned the type by this ADR.

---

## Consequences

Downstream statements that were parked on the TBD and now have an answer:

| Location | What it said while the TBD stood | Required state |
|---|---|---|
| `01-Game-Design/Core-Systems/battle-calculation.md` | hybrid row reads "TBD, pending ADR-006, code must not reference it" | Replaced by the formula above, written in the same form as the physical/magical rows |
| `01-Game-Design/game-design-doc.md` | hybrid row reads "TBD (ADR-006)" | Same |
| Godot `scripts/core/damage_calculator.gd`, `_calc_base_damage()` | stub computing `min(DEF, RES)`, guarded by a "TBD (ADR-006)" comment | Each branch floored inside the `"hybrid"` arm and then averaged. The floors must stay inside the arm: the function's shared tail floor would compute "average first, floor afterwards", which is a different formula |
| ADR-005 §4.2 and §5 | hybrid TBD block; four open questions | Superseded by this ADR; a pointer is recorded in ADR-005's current-state notice |
| Agent rule files quoting ADR-004's "hybrid takes the average weapon power" | Refers to `phys_power` / `mag_power`, fields that no longer exist | Restated as "one `weapon_might`, two branches, averaged result" |

Deliberately not changed: ADR-004 and ADR-005 keep their original decision text. They are historical records; both carry a current-state notice at the top pointing here.

---

*Created: 2026-08-03 | Main Agent (Claude Code) | Human Supervisor ruling, closes the ADR-006 placeholder opened 2026-02-27*
