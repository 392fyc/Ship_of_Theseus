# 01 - Turn System

> Back to [[game-design-doc|GDD]]

## Overview

Speed-based turn order system. Each turn, all units act in descending `speed` order. Not a CT accumulation model. Each unit has **structured action resources** per turn, with skills and operations categorized by consumption type, creating strategic choices within each turn.

---

## Speed-Based Turn Order

At the start of each turn, all surviving units are sorted by `speed` descending to generate the action queue.

### Initiative Priority

| Priority | Description |
|----------|-------------|
| +2 | Highest priority, ignores speed and is forced to front of queue |
| +1 | Secondary priority, placed after +2 but before normal units |
| 0 | Normal (default), sorted by speed |

Within the same priority level, units are still sorted by `speed` descending.

### Same-Speed Resolution

When two units have the same speed and same priority:
- **Lower difficulty**: Player units act first
- **Highest difficulty**: Enemy units act first

### Buff and Debuff Timing Rules

| Timing | Trigger |
|--------|---------|
| Effect trigger | At **unit turn start** (e.g., DOT damage, regeneration) |
| Duration decrement | At **unit turn end** (remaining turns -1) |
| Effect application | **Immediate** (affects attributes upon application) |

**Terminology**:
- **Unit turn start/end**: When a specific unit begins/ends its action phase
- **Turn start/end**: When the entire action queue's cycle begins/ends

---

## Action Resource System

### Design Philosophy

Inspired by Baldur's Gate 3's action economy (Movement / Action / Bonus Action), each unit's turn is split into multiple **action resources**. Skills and operations each consume different resources, forcing players to make tactical decisions within limited resources.

**Core Goals**:
- Prevent "cast all skills in one turn" mindless rotations — different skills compete for the same resources
- Preserve the tactical value of movement and normal attacks — advanced skills have opportunity costs
- Create class differentiation — certain classes excel at utilizing specific resource types
- Allow "pure caster" builds to exist, but not as the universal state

### Turn Resource Pool

Each unit receives the following resources at the start of their turn:

| Resource | Default Allowance | Description |
|----------|-------------------|-------------|
| **Movement** | Determined by `move` attribute | Used for normal movement and \[Move Action\] skills |
| **Attack Opportunity** | 1 time | Used for normal attack and \[Standard Action\] skills |
| **Swift Action** | 1 time (or unlimited) | Used for \[Swift Action\] skills, does not consume Movement/Attack resources. Includes former 'Free' actions. |

### Action Type Tags

All active skills and operations must be tagged with one of the following action types:

#### Move Action — action_cost move

Consumes this turn's **Movement** (partial or full). After use, normal movement is no longer possible, but attacks can still be performed.

- Typical use: Displacement skills (charge, evasive step, teleport)
- Design constraint: Remaining movement is zeroed after use
- Mutually exclusive with normal movement: Normal movement also consumes movement, cannot use \[Move Action\] skill after already moving

```
Examples:
  Swordsman "Lunge Strike": [Move Action] Move 2 cells toward target
  Archer "Backstep": [Move Action] Move 1 cell backward and gain Evasion +10 (1 turn)
  Knight "Charge": [Move Action] Charge straight toward target, dealing AOE damage along the path
```

#### Standard Action — action_cost standard

Consumes this turn's **Attack Opportunity**. After use, **Move and Standard resources are both consumed** (default behavior). The turn ends unless Swift resources remain or special abilities (e.g., Canto/Re-Action) apply.

- Typical use: Attack skills, powerful buffs/debuffs
- Mutually exclusive with normal attack: Cannot normal attack after using \[Standard Action\] skill, and vice versa
- Design principle: This is the most "expensive" action resource; \[Standard Action\] skills should be noticeably stronger than normal attacks
- Default resource cascade: Executing a Standard Action also consumes remaining Movement, enforcing the "move then act" phase order

```
Examples:
  Mage "Fireball": [Standard Action] Ranged AOE magical damage
  Cleric "Group Heal": [Standard Action] Heal all allies within range
  Swordsman "Ten Thousand Swords": [Standard Action] High-multiplier single-target attack
```

#### Swift Action — action_cost swift

**Does not consume** Movement or Attack Opportunity. 
- **Standard Swift** (`swift_limit: 1`, default): Limited to **1 use** per turn. Typical use: Stance switching, short-duration buffs, light debuffs.
- **Unlimited Swift** (`swift_limit: -1`): No per-turn usage limit. Typical use: Manual toggle of passive auras, information viewing.

- Flexible timing: Can be used at any point before/after movement or attack

```
Examples:
  Swordsman "Quick Draw": [Swift Action] Switch attack stance, next attack crit rate +15% (1/turn)
  Mage "Mana Infusion": [Swift Action] Next magical attack damage +20% (1/turn)
  Tactician "Aura Switch": [Swift Action] Switch between attack aura and defense aura (Unlimited)
  Hunter "Scout": [Swift Action] View target unit's detailed attributes (Unlimited)
```

#### Reaction Action — action_cost reaction

**Does not consume active turn resources**. Passively triggered by specific conditions, occurs during other units' turns or specific events.

- Typical use: Counter-attack enhancement, on-hit reactions, ally coordination
- Limitation mechanism: May consume a dedicated gauge (e.g., Sword Intent), or have per-turn usage limits
- Cannot be actively cast: Must meet trigger conditions to activate

```
Examples:
  Sword Saint "Sword Intent Counter": [Reaction Action] When hit by melee, spend 1 Sword Intent to counter (power 80%)
  Knight "Protect": [Reaction Action] Take damage in place of adjacent ally when attacked
  Cleric "Divine Grace": [Reaction Action] Automatically apply shield when ally HP drops below 20%
```

### In-Turn Action Flow (Phased Order)

```
Unit Turn Start
  │
  ├─ Buff/Debuff trigger (unit turn start effects)
  │
  ├─ Move Phase
  │   ├─ Normal movement OR [Move Action] skill    ← Consumes Movement (choose one)
  │   ├─ [Swift Action] (if timing allows)          ← Can be used before/after move
  │   └─ Skip move (proceed directly to Action Phase)
  │
  ├─ Action Phase
  │   ├─ Normal attack OR [Standard Action] skill   ← Consumes Attack Opportunity + Movement
  │   ├─ [Swift Action] (if timing allows)           ← Can be used before/after attack
  │   └─ Skip attack (end turn or use remaining Swift)
  │
  ├─ Swift Phase (if Swift resources remain after Move+Standard consumed)
  │   └─ Use remaining [Swift Action] skills
  │
  ├─ Manually end turn / auto-end when all resources exhausted
  │
  └─ Buff/Debuff duration decrement (unit turn end)
```

**Phased Order**: Actions follow a **Move → Attack → End** phase progression (Fire Emblem-style):
- Move first, then attack/skill (standard SRPG flow)
- Skip move to attack/skill immediately (forfeits remaining movement by default)
- Swift actions can be interspersed at any phase before turn end
- Special talents/skills (e.g., Canto) can override default phase restrictions
- Only move without attacking (end turn early via manual End Turn)

### Skill Cast Timing Constraints

Some skills, in addition to action type, can have **cast timing constraints**:

| Constraint | Field Value | Description |
|-----------|-------------|-------------|
| No constraint | `"any"` | Default, can be cast at any time during action phase |
| Before move | `"before_move"` | Must be cast before moving this turn |
| After move | `"after_move"` | Must be cast after having moved this turn |
| Before attack | `"before_attack"` | Must be cast before attacking this turn |
| After attack | `"after_attack"` | Must be cast after having attacked this turn |

```
Examples:
  Archer "Aim": [Swift Action, before_attack] Must be used before attacking
  Swordsman "Chase Strike": [Standard Action, after_move] Must be used after moving
  Knight "Shield Wall": [Swift Action, before_move] Sacrifice mobility for defensive posture
```

---

## Action Resources and Build Design

### Strategic Depth of Skill Count

The action resource system naturally limits the number of skills usable per turn:

| Resource | Per-Turn Allowance | Usable Skill Count |
|----------|-------------------|-------------------|
| Movement | 1 time (move or Move Action skill) | At most 1 \[Move Action\] |
| Attack Opportunity | 1 time (normal attack or Standard Action skill) | At most 1 \[Standard Action\] |
| Swift Action | 1 time (or unlimited) | At most 1 standard \[Swift Action\] (plus any unlimited ones) |
| Reaction Action | Conditional trigger | Depends on trigger conditions and gauge |

**Maximum 3 active skills per turn** (1 move + 1 standard + 1 swift), plus normal movement and normal attack being replaced by skills. This ensures:

- **More skills is not always better**: Bringing 5 \[Standard Action\] skills = can only use 1 per turn, rest are wasted
- **Build decisions matter**: Choosing which skills to bring = choosing how to allocate action resources
- **Normal attack/movement has value**: When not using skills, normal attack/movement is available, no "idle turns"

### Class Action Pattern Tendencies

| Class Tendency | Typical Pattern | Description |
|---------------|-----------------|-------------|
| Melee DPS | Move → Standard Action skill | Approach target then use high-damage skill |
| Ranged Turret | Swift buff → Standard Action skill | No movement needed, focus on amplifying output |
| High-Mobility Skirmisher | Move Action skill → Normal attack | Displacement skill to approach/disengage then normal attack |
| Defensive Tank | Swift defense → Normal attack + Reaction Action | Simple active turn, relies on Reaction Actions |
| Support | Swift buff → Standard Action heal/buff | One buff and one heal per turn |
| Pure Caster - special | Move Action → Standard Action → Swift Action | All three resources used for skills, sacrificing normal attack and normal movement |

### Re-Action Ability - Reserved

Certain talents/relics may grant "re-action" ability, granting extra attack opportunity or movement after \[Standard Action\]. This is an advanced mechanic requiring strict control:

- Re-action does not refresh Swift Action count
- Extra attack opportunity from re-action is limited to normal attacks (cannot use \[Standard Action\] skills again)
- Maximum 1 re-action trigger per turn

---

## Multiplayer Adaptation

- Under turn-order system, only 1 unit acts at a time; only the current actor's GameAction needs syncing
- All operations are encapsulated as GameActions; executed directly in single-player, broadcast then executed in multiplayer
- Action resource state (remaining movement, whether attacked, whether swift action used) syncs as turn state

---

## Turn Order UI - Reserved

- Dedicated UI showing current action queue
- Marks unit status (Buff/Debuff icons, HP bars)
- Dynamically updates queue when speed changes (Buff/Debuff affecting speed)
- Current actor highlighted, preview next N actors

---

## Common Pitfalls

- Swift Action and Standard Action stacking → **Allowed**, they consume different resources
- Move Action and normal movement stacking → **Not allowed**, choose one
- Standard Action and normal attack stacking → **Not allowed**, choose one
- Multiple standard Swift Actions per turn → **Not allowed**, limited to 1. Unlimited Swift skills are exempt
- Attacking without moving → **Allowed**, but Move resource is also consumed by default (no post-attack movement unless special talent)
- Undo after moving → **Allowed** until an attack or skill is committed; then move is locked
- Reaction Action triggering during own turn → **Allowed**, Reaction Action is not limited to specific timing
- Using Standard Action skill after re-action → **Not allowed**, re-action only allows normal attack
- Unit with Initiative +2 acting twice per turn → **No**, initiative only affects action order

---

Related documents:
- [[battle-calculation|03 - Battle Calculation]] — Attack resolution flow (hit → crit → damage → counter-attack)
- [[skills-and-range|04 - Skill and Range]] — `action_cost` and `timing` fields in skill data structure
- [[class-system|05 - Class System]] — Class action pattern tendencies
- [[talent-tree|12 - Talent Tree]] — Talent nodes tagged with action resource labels
