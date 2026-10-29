# 04 - Skill and Range System

> Back to [[game-design-doc|GDD]]

## Overview

Each weapon/skill has independent range patterns and effect areas, combined with cooldowns and additional effects to create rich tactical choices.

---

## Skill Data Structure

```
Skill:
  id: String
  name: String
  element_type: "physical" | "magical" | "holy" | "hybrid"  # Attribute type (determines defense calculation)
  attack_type: "melee" | "ranged" | "area"                  # Attack method (determines special interactions)
  power: int              # Skill multiplier (100 = base, 150 = 1.5x)
  hit_bonus: int          # Additive bonus to derived Hit (weapon_hit + DEX*2 + LCK*0.5)
  crit_bonus: int         # Additive bonus to derived Crit (weapon_crit + DEX/2)
  range: RangePattern     # Castable range
  area: AreaPattern       # Effect area after hit
  cooldown: int           # Cooldown (wait N turns after use before reuse)
  action_cost: "move" | "standard" | "swift" | "reaction"  # Action resource consumed
  timing_constraint: "any" | "before_move" | "after_move" | "before_attack" | "after_attack"
  swift_limit: int = 1    # Per-turn usage limit for Swift skills (1 = standard, -1 = unlimited)
  effects: Array[Effect]  # Additional effects
  effect_timing: "on_hit" | "after_damage"  # Effect trigger timing (default on_hit)
  pre_move: bool = false          # Whether usable before movement
  post_attack_move: bool = false  # Whether movement is allowed after use (requires class support)
  description: String
```

### Attribute Type and Attack Method Notes

- **element_type**: Determines which defense calculation the damage formula uses. See → [[battle-calculation|03 - Battle Calculation]] Damage Type System
- **attack_type**: Declared by the skill, not affected by actual attack distance
  - `melee`: Skill range is only 1 cell
  - `ranged`: Skill range > 1 cell (still ranged even if actually attacking a target 1 cell away)
  - `area`: Skill has AOE range (still area even if only hitting a single target)
- **hit_bonus**: Applies after ADR-005 derived Hit calculation (`weapon_hit + DEX*2 + LCK*0.5`)
- **crit_bonus**: Applies after ADR-005 derived Crit calculation (`weapon_crit + DEX/2`)

### Skill Classification (Design-Library Layer, 2026-07-08)

The design library additionally classifies each skill along **two orthogonal dimensions**, independent from the engine-side `action_cost` taxonomy above:

- **`skill_type`** — what the skill *does* (attack / mobility / buff / support / control). Support covers healing.
- **`resource_type`** — what per-turn action resource the skill consumes (standard / swift / move / reaction / none). "None" is reserved for a fully passive skill with no active-trigger cost (not yet used by any real skill).

These two fields live on the design library's `Skill` record (Chinese enum values, used for design narrative/review) and are a **separate taxonomy from the engine-side `action_cost` field above** (English values, consumed by Godot). Do not conflate the two — a skill's `resource_type` and its engine `action_cost` should describe the same real-world resource, but they are independently-maintained fields, not a single shared enum.

Current 5-skill roster (Kensei line) classified under this scheme:

| Skill | skill_type | resource_type |
|-------|-----------|----------------|
| Slash (斩击) | Attack | Standard |
| Iaijutsu (居合) | Attack | Standard |
| Batto (拔刀) | Attack | Standard |
| Flash Step (一闪) | Mobility | Move |
| Parry (招架) | Buff (self-targeted) | Swift |

Parry is classified as Buff rather than a standalone "Stance/Reaction" category — its `range.type = self` already fully expresses "target is always self"; no separate skill_type is needed for that constraint.

### Timing Constraint

- `any`: No timing restriction
- `before_move`: Can only be used before the unit spends movement for the turn
- `after_move`: Can only be used after the unit has moved
- `before_attack`: Can only be used before the unit spends its standard attack opportunity
- `after_attack`: Can only be used after the unit has attacked

See → [[battle-calculation|03 - Battle Calculation]] Unit Turn Sequence

---

## Range Pattern

Defines "how far away can the skill target".

```
RangePattern:
  type: "diamond" | "line" | "cross" | "square" | "self"
  min_range: int    # Minimum range
  max_range: int    # Maximum range
```

### Type Description

**diamond** — Most common, Manhattan distance

```
min=1, max=2:        min=2, max=3:
  . X .              . . X . .
  X X X              . X . X .
  . X .              X . . . X
  X X X              . X . X .
  . X .              . . X . .
                     (center not selectable)
```

**line** — Choose one of four cardinal directions

```
max=3:
  . . . X            X
  . . . .            .
  X . ★ .    or      ★
  . . . .            .
  . . . X            X
```

**cross** — All four cardinal directions simultaneously

```
max=2:
    X
    X
  X X ★ X X
    X
    X
```

**self** — Self position only (buff/heal skills)

---

## Area Pattern

Defines "how large an area is affected around the hit point".

```
AreaPattern:
  type: "single" | "diamond" | "line" | "cross" | "square"
  size: int
```

- **single**: Only the target cell
- **diamond(1)**: Target cell + 4 adjacent = 5 cells
- **diamond(2)**: 13-cell diamond area
- **line(2)**: A line extending 2 cells from cast direction
- **square(1)**: 3×3 square centered on target = 9 cells

---

## Skill Examples

| Skill | Type/Method | Range | Area | CD | Description |
|-------|-------------|-------|------|----|-------------|
| Slash | physical/melee | diamond 1-1 | single | 0 | Basic melee attack |
| Heavy Strike | physical/melee | diamond 1-1 | single | 1 | 150% multiplier |
| Quick Slash | physical/melee | diamond 1-1 | single | 0 | 80% multiplier, no cooldown |
| Shot | physical/ranged | diamond 2-4 | single | 0 | Basic ranged attack |
| Snipe | physical/ranged | diamond 3-5 | single | 2 | Ultra long range, high hit |
| Fireball | magical/area | diamond 2-4 | diamond(1) | 2 | 5-cell AOE |
| Ice Spell | magical/ranged | diamond 1-3 | single | 1 | Applies slow |
| Heal | holy/ranged | diamond 0-3 | single | 1 | Restores HP |
| Healing Aura | holy/area | self | diamond(2) | 3 | Large area heal |
| Lunge Strike | physical/melee | line 2-3 | single | 1 | Move to target and attack |

---

## Additional Effects

```
Effect:
  type: String          # Effect type
  chance: int           # Base trigger probability (%), affected by target LCK
  duration: int         # Duration in turns (decremented at unit turn end)
  value: int            # Effect value
  timing: "on_hit" | "after_damage"  # Trigger timing (default on_hit)

Actual application rate = chance × max(0.1, 1 - defender.LCK / 100)

Common effect types:
  "burn"         - Takes value damage at unit turn start
  "poison"       - Takes value damage at unit turn start (usually longer duration)
  "slow"         - SPD reduced by value (affects next turn order)
  "haste"        - SPD increased by value (affects next turn order)
  "stun"         - Checked at unit turn start, skips action
  "freeze"       - Skips action, removed early when attacked
  "defense_up"   - DEF increased by value
  "defense_down" - DEF decreased by value
  "priority_up"  - Initiative priority +value (1 or 2), affects next turn order
```

### Two Effect Timing Types

| Timing | Description | Example |
|--------|-------------|---------|
| on_hit | Triggers on hit regardless of damage | Debuff application (slow, poison), mark effects |
| after_damage | Triggers after damage resolution | Lifesteal (based on actual damage), kill-triggered effects |

See → [[battle-calculation|03 - Battle Calculation]] Attack Resolution Flow

---

## Skill Data File Example

```json
{
  "id": "fireball",
  "name": "Fireball",
  "element_type": "magical",
  "attack_type": "area",
  "power": 120,
  "hit_bonus": 10,
  "crit_bonus": 0,
  "range": { "type": "diamond", "min": 2, "max": 4 },
  "area": { "type": "diamond", "size": 1 },
  "cooldown": 2,
  "action_cost": "standard",
  "timing_constraint": "any",
  "effects": [
    { "type": "burn", "chance": 30, "duration": 3, "value": 10 }
  ],
  "description": "Hurl a fireball at the target, explosion radius 1 cell, chance to apply burn"
}
```

---

Related documents:
- [[battle-calculation|03 - Battle Calculation]] — How skill multipliers participate in the damage formula
- [[turn-system|01 - Turn System]] — How SPD determines action order
