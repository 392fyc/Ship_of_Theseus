# 12 - Talent Tree System

> Return to [Overview](./README.md)

## Overview

The Talent Tree is the backbone of character builds, determining character direction and Class Advancement choices. The Demo version uses a **permanent unlock** system (not Roguelite reset).

### Core Design Principles

1. **Talent Points = Level** (Gain 1 Talent Point at Lv1, +1 Talent Point per level up)
2. **Starting nodes are not free**: Costs 1 point to unlock; there may be more than one starting node (multi-entry design)
3. **Lv25 anchor point**: After a normal 30-stage playthrough, a single character reaches approximately Lv25, totaling 25 Talent Points
4. **25 points completes exactly one path**: Shared area fully unlocked (16 points) + one side advancement branch fully unlocked (9 points) = 25 points
5. **Different classes have different topologies**: Topology shape reflects gameplay differences between classes

---

## Talent Point Economy

| Player Type | Expected Level | Talent Points | Unlockable Nodes |
|---------|---------|--------|----------|
| Casual Player | Lv25 | 25 pts | Full shared area + full single branch |
| Skilled Player | Lv28 | 28 pts | Above + 3 nodes from the other branch |
| Hardcore Player | Lv30+ | 30+ pts | Above + 5-6 nodes from the other branch |

### Allocation Pacing

| Phase | Stages | Level | Cumulative Talent Points | Milestone |
|------|------|-----|-----------|--------|
| Introduction | 1-5 | Lv5 | 5 pts | Starting node + first fork choice |
| Growth | 6-10 | Lv10 | 10 pts | Reach advancement node (shortest path = 10 pts) |
| Advancement | 10-11 | Lv10-11 | 11 pts | Complete Class Advancement choice |
| Development | 12-22 | Lv12-20 | 12-20 pts | Deep into post-advancement branch |
| Maturity | 23-30 | Lv21-25 | 21-25 pts | Build complete |

---

## Talent Tree Specifications

Each class's Talent Tree structure:

| Area | Node Count | Talent Point Cost |
|------|--------|-----------|
| Pre-advancement Shared Area | 16 nodes (incl. start + middle + advancement choice) | 16 pts |
| Post-advancement Branch A | 9 nodes | 9 pts |
| Post-advancement Branch B | 9 nodes | 9 pts |
| **Single Class Total** | **~34 nodes** | 25 pts to complete one full path |

### Shortest Advancement Path

All classes unified: **Start (1 pt) + 8 intermediate required nodes + 1 advancement node = 10 Talent Points**

---

## Gauge System

Each advancement direction has an independent Gauge mechanic, unlocked by the 2nd node after advancement (gauge_core).

### Gauge Overview

| Advanced Class | Gauge Name | Type | Core Mechanic | Design Keywords |
|---------|--------|------|---------|-----------|
| Kensei | Sword Intent | Energy value (0-100) | Crit/Evasion to gain → interval BUFF → spend to release | Maintain interval vs burst spending |
| Sword Immortal | Sword Essence | MP-like (natural regen / steady consumption) | Sustain flying sword skills and sword formations | Positional control + hybrid damage |
| Sniper | Focus | Energy value (0-100) | Standing still accumulates → movement/damage interrupts | Position choice = resource management |
| Elven Archer | Nature Resonance | Stacks (0-5) | Evasion/enchant/melee accumulate → enchant 100% trigger | Melee participation = stack source |
| Mage (per element) | Hellfire / Frost / Gale | Energy value (0-100) | Element skills accumulate → element-specific enhancement | See mage-talent-tree-design-brief |

### Gauge Design Principles

1. **Not just "fill up and unleash ultimate"** — each Gauge has a different gain/spend cycle
2. **Maintaining a certain interval has independent benefits** — not just numerical stacking
3. **Tightly bound to class identity** — Kensei = fast attack crit cycle, Element Sage = element mastery escalation
4. **Trade-off decisions exist** — e.g., Sword Intent: "maintain high Intent to enjoy sustained buffs" vs "spend it to pursue burst damage"

### Detailed Gauge Definitions

#### Sword Intent - Kensei

- Cap: 100, starts at 0
- **Gain**: Crit hit +15 / Successful evasion +10 / Speed-advantage attack +10 / Kensei signature counter-attack +20
- **Decay**: -5 at end of each character's turn (auto-decay, high-tempo resource)
- **Interval Effects**:
  - 0-29: No extra effect
  - 30-59 "Qi Surge": ATK +12%
  - 60-89 "Qi Peak": ATK +12%, CRIT +8%, Crit damage multiplier +0.2
  - 90-100 "Sword Intent Convergence": All of the above + unlock ultimate skill

#### Sword Essence - Sword Immortal

- Type: MP-like (natural regen / steady consumption)
- **Core Mechanic**: After class advancement, unequip conventional weapon → gain Bonded Flying Sword. Normal attack becomes ranged hybrid.
- **Usage**: Sustain flying sword skills, deploy sword formations, power ultimate abilities
- **Design Note**: See [[01-Game-Design/Characters/talent-tree-deep-dive-rules|deep-dive-rules §7.2.3]] for full Sword Immortal lore and mechanics

#### Focus - Sniper

- Range: 0-100, starts at 0
- **Gain**: Turn without moving +20 / Crit hit +15 / Marked target hit +10
- **Loss**: After moving -30 / After taking damage -20
- **Interval Effects**:
  - 0-39: None
  - 40-69 "Concentration": Range +1, Accuracy +5
  - 70-99 "Settled": Range +1, Accuracy +10, Crit damage +0.2
  - 100 "Absolute Focus": All of the above + next attack ignores 50% physical DEF

#### Nature Resonance - Elven Archer

- Stack system (0-5 stacks)
- **Gain**: Successful evasion +1 stack / Using enchanted arrow skill +1 stack / Melee attack hit +1 stack
- **Decay**: If no new stacks gained for 3 turns, all stacks are lost
- **Effect**: Each stack: EVA +3, enchant trigger chance +8%. At 5 stacks: next enchanted arrow 100% trigger

#### Mage Element Gauges

> Mage gauge design is undergoing revision for the 3-element system (Fire/Ice/Air). See [[01-Game-Design/Characters/talent-tree-deep-dive-rules|deep-dive-rules]] and mage-talent-tree-design-brief for the latest specifications.
>
> Each element has an independent energy gauge (0-100) with element-specific gain/decay/threshold mechanics. Grand Sage can manage two element gauges simultaneously; Element Sage has enhanced thresholds for their chosen element.

---

## Numerical Calibration Notes - Crit Rate Analysis

**Crit rate has no hard cap.** High-DEX classes can exceed 50% crit rate in late game, making crit-based builds scale continuously.

| Character @ Lv25 | Base CRIT | Effective Crit Rate |
|-----------|--------|----------|
| Kensei | 75 | ~57% |
| Sniper | 86 | ~65% |
| Elven Archer | 71 | ~54% |
| Sword Immortal | 60 | ~46% |
| Mage (avg) | 37 | ~30% |

**Design Implications**:
- "Crit rate +X%" talents remain valuable throughout the game for high-DEX classes
- **Crit damage multiplier +X** is still strong but no longer the only viable late-game crit investment
- Gauge crit-gain conditions (crit hit +N) trigger very reliably for Kensei / Sniper in late game
- Low-DEX classes (Mage, Knight) naturally have low crit rates, maintaining class differentiation

---

## Node Type Definitions

| Type | Description | Examples |
|------|------|------|
| trait | Trait/characteristic, permanent passive | Sword Fundamentals, Sword Mastery |
| passive | Conditionally triggered passive | Keen Sense, Chain, Unstoppable |
| active_skill | Active skill | Sword Dance, Flow, Marked Shot |
| skill_upgrade | Existing skill upgrade | Sharp Wound, Piercing Shot |
| gauge_core | Gauge core unlock | Sword Intent Embodiment, Focus |
| gauge_extend | Gauge extension/upgrade | Sword Intent Fusion, Trajectory Mastery |
| advancement | Advancement node (mutually exclusive) | Path of the Kensei, Path of the Sword Immortal (剑仙) |

---

## Tools

All design tools are located in the project root directory `tools/`, navigated via `index.html`.

- **Tool Navigation Page**: `tools/index.html` — Entry point for all design tools
- **Talent Tree Editor**: `tools/talent-tree-editor.html` — Visual editing and preview of all talent trees (includes DAG validation, path analysis, mutual exclusion visualization)
- **Equipment Designer**: `tools/equipment-designer.html` — Weapon/armor/accessory design
- **Map Designer**: `tools/map-designer.html` — 10x10 grid map editing
- **Damage Simulator**: `tools/damage-simulator.html` — Numerical verification tool
- **Shared Components**: `tools/shared.js` — Game constants, formulas, and data interfaces shared across tools

---

Related documents:
- [[03-battle-calculation|Battle Calculation]] — Damage/accuracy/crit formulas
- [[05-class-system|Class System]] — Class attributes, growth rates, advancement
- [[04-skills-and-range|Skills and Range]] — Skill data structures
