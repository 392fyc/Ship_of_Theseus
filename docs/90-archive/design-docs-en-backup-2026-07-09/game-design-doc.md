# Tactical RPG Roguelite — Core System Design Document - GDD

> This document is a high-level summary of all module design documents. For detailed rules, refer to the corresponding module documents (01~12).
> When conflicts arise with module documents, the module documents take precedence.

## Project Overview

| Attribute | Decision |
|-----------|----------|
| Genre | Tactical RPG + Roguelite + Town Building |
| Engine | Godot 4 (GDScript) |
| Grid | Square grid, ≤10×10, no elevation |
| Turn System | Speed-based turn order (sorted by speed descending) |
| Players | Single-player 1 / Multiplayer 1-4 |
| Multiplayer Mode | Each player controls characters, GameAction command sync |
| Core Loop | Run structure of 3 acts × 10 stages + Town Building |
| Data Architecture | JSON-driven (all content in JSON, code only handles logic) |
| Core Differentiator | Differentiated talent tree architecture (per-class topology + irreversible Class Advancement + dual-layer meta/run selection) is the primary build-depth mechanism. Town Building remains as economy/shop floor. |

---

## 1. Turn System - 01-turn-system.md

### Speed-Based Turn Order

Each turn, all units act in descending `speed` order. Not a CT accumulation model.

- **Initiative Priority**: 0 (normal) / +1 / +2, higher priority overrides speed and goes first
- **Same-Speed Resolution**: Lower difficulty = player first, highest difficulty = enemy first
- **Buff/Debuff Timing**: Effect trigger = unit turn start, duration decrement = unit turn end, application = immediate

### Action Resource System

Each unit has **structured action resources** per turn, inspired by BG3's action economy:

| Resource | Allowance | Description |
|----------|-----------|-------------|
| Movement | `move` attribute | Normal movement OR \[Move Action\] skill (choose one) |
| Attack Opportunity | 1 time | Normal attack OR \[Standard Action\] skill (choose one) |
| Swift Action | 1 time | \[Swift Action\] skill, does not consume other resources |

**Action Type Tags** (all active skills must be tagged):

| Tag | action_cost | Consumes | Typical Use |
|-----|------------|----------|-------------|
| \[Move Action\] | `"move"` | Movement | Displacement skills (charge/evasive step) |
| \[Standard Action\] | `"standard"` | Attack Opportunity | Attack/powerful buffs and debuffs |
| \[Swift Action\] | `"swift"` | Swift Action (1/turn) | Stance switch/light buffs |
| \[Reaction Action\] | `"reaction"` | None (conditional trigger) | Counter-attack enhancement/on-hit reaction |
| \[Free Action\] | `"free"` | None | Info viewing/aura toggle |

**Design Rationale**: Prevents "cast all skills in one turn" — different skills compete for the same resources, preserving the tactical value of normal attacks and movement.

### Multiplayer Adaptation

- Under turn-order system, only 1 unit acts at a time; only the current actor's GameAction needs syncing
- All operations are encapsulated as GameActions; executed directly in single-player, broadcast then executed in multiplayer

---

## 2. Grid and Map - 02-grid-and-map.md

### Three-Layer Structure

```
Layer 1: Base Terrain (9 types, always present)
Layer 2: Special Terrain (stacked on base terrain)
Layer 3: Buildings (override base terrain effects, become Ruins when destroyed)
```

### Base Terrain

| ID | Terrain | Move Cost | Passable | Blocks Attack Line |
|----|---------|-----------|----------|--------------------|
| 0 | Plain | 1 | ✓ | ✗ |
| 1 | Forest | 2 | ✓ | ✗ |
| 2 | Mountain | 2 | ✓ | ✗ |
| 3 | Peak | — | ✗ | **✓ (only one)** |
| 4 | Wall | — | ✗ | ✗ |
| 5 | Shallow Water | 2 | ✓ | ✗ |
| 6 | Deep Water | — | ✗ | ✗ |
| 7 | Lava | 2 | ✓ | ✗ |
| 8 | Swamp | 3 | ✓ | ✗ |

### Pathfinding

- BFS calculates movement range, A* calculates path
- Traps do not affect pathfinding

---

## 3. Battle Calculation - 03-battle-calculation.md

### Damage Formula - FE Additive - ADR-005

```
Base Damage = max(1, STR + weapon_might - DEF)   [physical]
            = max(1, MAG + weapon_might - RES)   [magical]
Final Damage = Base Damage × skill_multiplier × terrain_modifier × crit_modifier × relic_modifier
```

> See `01-Game-Design/Core-Systems/battle-calculation.md` for details

### Hit - Crit - Block - ADR-005

```
Hit Rate = weapon_hit + DEX×2 + LCK/2 - (SPD×2 + LCK/2 + terrain_evade)  (20%~100%)
Crit Rate = weapon_crit + DEX/2 - LCK  (1.5x; pure fixed 1.5x, unaffected by bonuses)
Block = Removed (now from Talent Tree/equipment/relic special effects, not a base attribute)
```

### Damage Type Dual-Axis - ADR-004

**Attribute Type** (determines defense calculation):

| Type | Defense | Crit/Block |
|------|---------|------------|
| physical | DEF | ✓ |
| magical | RES | ✓ |
| pure | Ignores defense | ✗ |
| hybrid | TBD (ADR-006) | ✓ |

**Attack Method**: `melee` (1 cell) / `ranged` (>1 cell) / `area` (AOE)

### Resolution Order

```
1. Hit check → miss skips to end
2. Crit check
3. Calculate damage → 4. Apply damage → 5. On-hit effects → 6. After-damage effects
7. Counter-attack (attack_type != area, alive, in range, not disabled) → steps 1-6, no counter/follow-up
8. Follow-up Attack ((attacker.SPD - defender.SPD) × 10%, 0%~100%, requires original hit) → steps 1-6, no counter/follow-up
```

---

## 4. Skill and Range - 04-skills-and-range.md

### Skill Data Structure

```json
{
  "id": "string",
  "action_cost": "move|standard|swift|reaction|free",
  "timing_constraint": "any|before_move|after_move|before_attack|after_attack",
  "element_type": "physical|magical|holy|hybrid",
  "attack_type": "melee|ranged|area",
  "power": 100,
  "range": { "type": "diamond|line|cross|self", "min": 1, "max": 1 },
  "area": { "type": "single|diamond|line|cross|square", "size": 0 },
  "cooldown": 0,
  "effects": [{ "type": "string", "chance": 0, "timing": "on_hit|after_damage" }]
}
```

- `action_cost`: Action resource type (→ 01-turn-system.md Action Resource System)
- `timing_constraint`: Cast timing constraint (default `"any"`, can restrict to before/after move or attack)

### Debuff Application Formula

```
Actual application rate = skill_effect.chance × (1 - defender.resistance / 100)
```

---

## 5. Class System - 05-class-system.md

### Class Architecture

- **8 Base Classes**: Swordsman, Mercenary, Archer, Artificer, Mage, Knight, Hunter, Cleric
- **16 Class Advancement Paths**: 2 per base class (Mage has 4 elemental branches)
- v1 playable prototype currently uses 5 classes: Soldier/Archer/Mage/Knight/Cleric
- **Non-growth attributes**: speed, move, vision
- Class Advancement triggered via special Talent Tree nodes, irreversible once chosen

### Counter-attack System

```
Conditions: attack_type != "area" AND target alive AND not disabled AND in range
Method: Normal attack (full resolution), does not trigger secondary counter-attack or follow-up
```

### Follow-up Attack System

```
Probability: (attacker.speed - defender.speed) × 10%  (0%~100%)
Conditions: Attacker alive AND original attack hit
Method: Normal attack (full resolution), does not trigger counter-attack or secondary follow-up
Timing: After counter-attack
```

Available to all classes; Swordsman line is the primary beneficiary.

### Build Composition

```
UnitBuild = Class + Talent Tree (skeleton) + Equipment + Random Skills/Relics (flesh)
```

---

## 6. Enemy and AI - 06-enemy-and-ai.md

### AI Behavior Patterns

| Pattern | Description |
|---------|-------------|
| AGGRESSIVE | Prioritize attacking nearest/lowest HP target |
| DEFENSIVE | Guard area, only counter-attack when approached |
| SUPPORT | Prioritize healing/buffing allies |
| HIT_AND_RUN | Attack then disengage |
| BOSS | Fixed skill rotation |

### Wave System

Enemies enter in waves triggered by conditions (turn count/remaining count/Boss HP threshold).

---

## 7. Run Loop and Meta - 07-run-loop.md

### Run Structure

```
One Run = 3 Acts × 10 Stages (including battles/events/elites/bosses)
Preparation Phase → Battle → Reward Selection → Town Building → Next Stage
```

### Meta Progression Principles

**Core Principle: Meta = Horizontal Unlocks (more choices), NEVER vertical power increases**

- ✓ Unlock new classes/advancements/relics/buildings
- ✓ Convenience upgrades (economy/information layer)
- ✗ Starting HP/attack bonuses
- ✗ Core mechanics locked behind meta progression

---

## 8. Network Architecture - 08-network.md

- Godot High-Level Multiplayer API, Host-Client model
- All operations encapsulated as GameActions, broadcast sync in multiplayer
- Overlay layer design: does not alter game logic, can be completely ignored in single-player

---

## 9. Data Architecture - 09-data-architecture.md

```
data/
├── classes/    # Class definitions
├── skills/     # Skill definitions
├── enemies/    # Enemy templates
├── maps/       # Map configurations
├── relics/     # Relic definitions
├── buildings/  # Building definitions
├── waves/      # Wave configurations
└── events/     # Event configurations
```

Adding new game content = adding new JSON files, no code changes needed.

---

## 10. Town Building - 11-town-building.md

- **6 Battlefield Buildings**: Watchtower/Fortress/Barricade/Life Fountain/Ballista/Magic Tower
- **Four subtypes**: Universal/Restricted/Blocking/Area
- **Building Durability**: Fixed deduction by damage type, does not use normal damage formula
- **Occupation mechanic**: Eligible units automatically occupy by standing on building
- Destroyed buildings become Ruins; repaired during preparation phase for gold

---

## 11. Talent Tree - 12-talent-tree.md, WIP

- Resets each Run, paths re-selected
- Meta unlocks available options, talent points earned during Run unlock nodes
- Includes passive traits, active skills, Class Advancement nodes
- Initial talent area contains one advancement's complete core gameplay
- **Design tool completed**: tools/talent-tree-editor.html (Canvas graph editor)

---

## 12. System Layers

```
Layer 4 (Meta):      07-Run Loop    ←→  11-Town Building
Layer 3 (Character): 05-Class System ←→  06-Enemy & AI  ←→ 12-Talent Tree
Layer 2 (Battle):    01-Turn System  →  04-Skills       →  03-Battle Calculation
Layer 1 (Base):      02-Grid & Map
Layer 0 (Data):      09-Data Architecture
Overlay:             08-Network Architecture (does not alter game logic)
```

Development order bottom-up: Layer 0/1 → Layer 2 → Layer 3 → Layer 4 → Overlay

---

## 13. Design Philosophy

1. **Fun at normal difficulty, depth at hard difficulty**: Multi-multiplier system supports build diversity
2. **Meta is horizontal, not vertical**: Unlock more choices, not stronger stats
3. **Talents are the skeleton, randomness is the flesh**: Controllable direction planning + Roguelite random surprises
4. **Full attribute transparency**: Additive model for hit/crit, players can calculate precisely
5. **Differentiated talent trees are the core differentiator**: Per-class talent topology + Bridge Tax + irreversible Class Advancement force build specialization; Town Building provides economy floor, not differentiation
6. **Class Advancement is directional choice, not power increase**: Each advancement opens a different playstyle
7. **Action resources are strategic depth**: Limited action resources per turn (movement/attack/swift) force players to choose between skills — more skills is not always better
