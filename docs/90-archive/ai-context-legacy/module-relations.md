# Module Dependency Graph - Agent Version

> This file provides structured module dependency information for Vibe Coding Agents.
> When modifying any module, you must check whether its upstream dependencies and downstream dependents need synchronized updates.

---

## Dependency Table

Each module lists: what it depends on (upstream changes may affect this module), and what depends on it (modifying this module requires checking downstream).

```yaml
modules:

  01-turn-system:
    description: "Turn-based speed rotation system, controls action order and turn advancement. Defines vocabulary (unit turn start/end vs turn start/end), initiative priority, same-speed resolution rules, Buff/Debuff timing rules, action resource system (Movement/Attack Opportunity/Swift Action)"
    depends_on: []
    depended_by:
      - 02-grid-and-map:  "Turn advancement triggers terrain effects/building effects"
      - 03-battle-calculation: "Unit turn timing determines Buff/Debuff trigger and decrement timing"
      - 04-skills-and-range: "Turn advancement triggers cooldown recovery; Effect duration decrement rules defined in 01; Skill action_cost and timing_constraint defined by action resource system"
      - 05-class-system: "Class action pattern tendencies constrained by action resource system; Build skill selection must balance action resource allocation"
      - 06-talent-tree: "Talent node skills must be tagged with action resource labels"
      - 07-enemy-and-ai: "AI decides during its own turn; AI must understand action resource constraints to plan skill usage order"
      - 10-network: "GameAction encapsulates all action commands; Action resource state needs syncing"
    key_exports:
      - current_round        # Current round number
      - action_queue         # Action order queue (with initiative sorting)
      - current_actor        # Current acting unit
      - priority_system      # Initiative priority (0/+1/+2)
      - timing_definitions   # Unit turn start/end vs turn start/end definitions
      - buff_debuff_timing   # Effect trigger = unit turn start, duration decrement = unit turn end
      - action_resource_system  # Action resources: Movement/Attack Opportunity(1)/Swift Action(1)
      - action_cost_types    # Action type tags: move/standard/swift/reaction/free
      - timing_constraints   # Cast timing constraints: any/before_move/after_move/before_attack/after_attack

  02-grid-and-map:
    description: "Grid system three-layer structure (Base terrain → Special terrain → Building), 9 base terrain types, pathfinding (attack lines are not blocked by terrain). Vision system pending separate document"
    depends_on:
      - 01-turn-system: "Turn start triggers terrain effects"
    depended_by:
      - 03-battle-calculation: "Terrain modifiers affect damage and hit"
      - 04-skills-and-range: "Range calculation based on grid distance; skills can create/alter special terrain"
      - 07-enemy-and-ai: "AI needs to read map for pathfinding and position evaluation"
      - 08-run-loop: "Stage configuration specifies map ID"
    key_exports:
      - grid               # Grid data (three layers: base terrain, special terrain, building)
      - get_movable_cells() # BFS movement range
      - find_path()        # A* pathfinding
      - get_cell_effects() # Get final stacked effects on a cell

  03-battle-calculation:
    description: "Damage formula (FE-style additive base + multiplicative outer layers), four-layer hit/crit chains (R1.2/R1.3; LCK only in crit-avoid), damage type declared by skill/talent/relic, attack resolution flow (hit → crit → damage → additional effects, on-hit / after-damage timing per R1.4; no engine-level auto counter-attack, counterplay is defined per-entry by Reaction talents / skills / relics / enemy traits), unit turn timing"
    depends_on:
      - 02-grid-and-map: "Terrain attribute bonuses (added to attributes), special terrain modifier (independent layer)"
      - 04-skills-and-range: "Skill multiplier, additional effects, timing_constraint"
      - 05-class-system: "Unit attribute values, growth rules (7 growth stats; LCK/MOV fixed, R2.1), class tags and skill access"
    depended_by:
      - 07-enemy-and-ai: "AI scoring needs to estimate damage/hit/crit"
    key_exports:
      - calculate_damage()    # Damage calculation (additive base + multiplicative outer layers; hybrid: physical and magical each floored at max(0,·) then averaged - R1.1)
      - calculate_hit()       # Hit determination (four-layer chain, final rate clamp(1,100); LCK not in the hit chain - R1.2)
      - calculate_crit()      # Crit determination (DEX-derived crit rate vs LCK-derived crit avoid; pure damage does not participate in crit determination - R1.1/R1.3)
      - attack_settlement()   # Full resolution flow (hit → crit → damage → two-stage additional effects)
      - damage_type_system    # Dual-axis classification: element type(physical/magical/pure/hybrid) x attack method(melee/ranged/area)

  04-skills-and-range:
    description: "Skill definitions (including action_cost action resource tags, timing_constraint cast timing constraints), range patterns, AOE area, cooldown system"
    depends_on:
      - 01-turn-system: "Turn advancement recovers cooldown; skill action_cost and timing_constraint definitions come from action resource system"
      - 02-grid-and-map: "Range based on grid distance calculation"
      - 09-data-architecture: "Load skill data from JSON"
    depended_by:
      - 03-battle-calculation: "Skill multiplier participates in damage formula"
      - 05-class-system: "Class defines available skill list"
      - 07-enemy-and-ai: "AI selects which skill to use; must plan skill usage based on action resource constraints"
    key_exports:
      - get_range_cells()   # Calculate cells within skill range
      - get_area_cells()    # Calculate AOE affected area
      - skill_data          # Skill data dictionary (includes action_cost, timing_constraint fields)

  05-class-system:
    description: "8 base classes + 16 advancements. Class determines attributes/weapon restrictions/initial skills/class_tags. Build = Class + Talent Tree + Random skills + Equipment + Relics"
    depends_on:
      - 03-battle-calculation: "Attributes participate in damage/hit/crit formulas"
      - 04-skills-and-range: "Skill definitions and element_type/attack_type"
      - 06-talent-tree: "Talent tree provides passive traits, core skills, advancement triggers"
      - 09-data-architecture: "Load class data from JSON"
    depended_by:
      - 07-enemy-and-ai: "AI adjusts priority based on target class"
      - 08-run-loop: "Class selection affects Run start; leveling and talent point acquisition"
    key_exports:
      - class_definitions    # 8 base classes + 16 advancement definitions
      - class_tags           # Class tags (for building occupation, skill restrictions, etc.)
      - build_structure      # UnitBuild data structure

  06-talent-tree:
    description: "Talent tree system (per-class node graphs; swordsman-line matrix landed). Resets fully each Run (L2), Meta unlocks range (L1). Contains passive traits, active skills, advancement nodes. Design principles: talent-tree.md; talent entities: design library /api/talents"
    depends_on:
      - 05-class-system: "Each class has an independent talent tree"
      - 08-run-loop: "Meta progression (meta_progress, horizontal unlocks) unlocks talent tree range"
    depended_by:
      - 05-class-system: "Talent tree provides passives/skills/advancement"
      - 08-run-loop: "Earn talent points during Run, talent tree resets each Run"
    key_exports:
      - talent_tree_definitions  # Per-class talent tree structures
      - talent_point_system      # Talent point acquisition and allocation
      - advancement_trigger      # Advancement node trigger logic

  07-enemy-and-ai:
    description: "AI behavior patterns, scoring decisions, wave entry, Boss mode, enemy tier ladder and the affix system (affix = a passive-skill-like trait, not a buff/debuff; base and special affix pools are separate)"
    depends_on:
      - 01-turn-system: "Triggers decision during AI unit's turn"
      - 02-grid-and-map: "Reads map for pathfinding and position evaluation"
      - 03-battle-calculation: "Estimates damage for scoring"
      - 04-skills-and-range: "Evaluates available skills and range"
      - 09-data-architecture: "Loads enemy templates and wave configs from JSON"
    depended_by:
      - 08-run-loop: "Stage configuration references enemy waves"
    key_exports:
      - ai_decide_action()  # AI decision outputs GameAction
      - wave_manager        # Wave management (trigger reinforcements)
      - affix_system        # Enemy affixes (base pool / special pool), declared per enemy entry in wave data

  08-run-loop:
    description: "Overall Run structure (3 Acts x 8 Stages, Act boss fixed at Stage 8), Hades-style door selection between stages, Preparation Phase (recovery / Convoy swap / intel), fixed shop insertions, rewards (gold / EXP / equipment / relics / events; talent points come from level-ups and are not in the drop pool), Meta Progression (horizontal unlock principle: more choices not stronger stats)"
    depends_on:
      - 06-talent-tree: "Talent point allocation during Run; talent tree resets each Run"
    depended_by:
      - 02-grid-and-map: "Stage specifies map ID"
      - 05-class-system: "Rewards provide skills/equipment; class unlocks"
      - 06-talent-tree: "Meta progression (meta_progress) unlocks talent tree range"
      - 07-enemy-and-ai: "Stage specifies enemy configuration"
      - 10-network: "Sync Preparation Phase operations during multiplayer"
    key_exports:
      - run_state           # Current Run progress state
      - current_stage       # Current stage
      - gold                # Run currency (door rewards / fixed per-stage payout / shop)
      - convoy              # Convoy storage: unequipped equipment and relics, swappable during Preparation Phase
      - meta_progress       # Cross-Run permanent progress (horizontal unlocks)
      - talent_points       # Currently available talent points
    design_principle: "Meta = horizontal unlocks (more choices) not vertical power (stat boosts). At any Meta progress level, available options support the complete core gameplay."

  09-data-architecture:
    description: "JSON data-driven, data loader, project directory structure"
    depends_on: []
    depended_by:
      - 02-grid-and-map: "Loads map JSON"
      - 04-skills-and-range: "Loads skill JSON"
      - 05-class-system: "Loads class JSON"
      - 07-enemy-and-ai: "Loads enemy templates and wave JSON"
    key_exports:
      - data_loader         # Global data loader
    note: "09 is the infrastructure layer. Any new data type must be registered here."

  10-network:
    description: "Network architecture, GameAction sync, Host-Client model"
    depends_on:
      - 01-turn-system: "Encapsulates action commands"
      - 08-run-loop: "Syncs Preparation Phase operations and reward selections"
    depended_by: []
    key_exports:
      - broadcast_action()  # Broadcast GameAction
      - sync_state()        # State synchronization
    note: "10 is an overlay layer, does not change game logic, only handles transport. Can be completely ignored in single-player."

  milestones:
    description: "Development milestones, Phase divisions, task checklist. No longer part of the numbered 01-10 design doc series; lives at 90-archive/task-system-legacy/Milestones/current-milestone.md"
    depends_on:
      - all: "Covers development plans for all modules"
    depended_by: []
    note: "Milestones is a planning document, any system change may require updating the corresponding Phase."

```

---

## Change Impact Quick Reference

When you need to modify a module, check this table to determine which documents need review:

| Modified Content | Directly Affected Documents |
|---------|--------------|
| Turn flow/speed mechanics/initiative/same-speed rules | 01, 02(terrain effect triggers), 03(unit turn timing), 04(cooldown and effect duration), 07(AI action timing), 10(sync) |
| Action resource system/action type tags | 01(definition), 04(skill action_cost field), 05(class action patterns/build planning), 06(talent node tags), 07(AI skill usage planning) |
| Buff/Debuff timing rules | 01(definition), 03(resolution flow), 04(Effect definition) |
| Terrain/map structure | 02, 03(terrain modifier), 07(AI pathfinding), 09(map JSON) |
| Damage/hit formula | 03, 07(AI damage estimation) |
| Add/modify skills | 04, 03(skill multiplier), 05(class available skills), 07(AI skill selection), 09(skill JSON) |
| Class/advancement | 05, 02(class_tags matching Restricted buildings), 03(attribute formula), 06(talent tree class branches), 07(AI adjusts priority by target class) |
| Talent tree | 06, 05(passives/skills/advancement), 08(talent point acquisition/Run reset/Meta unlock progress) |
| Enemy/AI behavior and affixes | 07, 08(stage enemy configuration), 09(enemy and affix JSON) |
| Run structure/stage flow/door model | 08, 02(map), 07(enemy waves), 10(multiplayer sync) |
| Multiplayer mechanics | 10, 01(action commands), 08(Preparation Phase sync) |
| Data format changes | 09, plus all modules using that data |
| Battlefield buildings | 02(three-layer stacking/occupation/ruins/durability), 03(durability deducted by damage type, outside the standard formula), 05(Restricted buildings matching class_tags), 08(Meta unlocks building types) |
| Development plan adjustments | Milestones (90-archive/task-system-legacy/Milestones/current-milestone.md) |

---

## System Layers

```
Layer 4 (Meta):       08-Run Loop
                           ↓
Layer 3 (Character):  05-Class System + 06-Talent Tree  ←→  07-Enemy and AI
                           ↓
Layer 2 (Battle):     01-Turn  →  04-Skill  →  03-Battle Calculation
                           ↓
Layer 1 (Foundation): 02-Grid and Map
                           ↓
Layer 0 (Data):       09-Data Architecture

Overlay (Optional):   10-Network Architecture (does not change game logic, transport layer only)
Planning:             Development Milestones (90-archive/task-system-legacy/Milestones/current-milestone.md)
```

**Development order should be bottom-up**: Layer 0/1 → Layer 2 → Layer 3 → Layer 4 → Overlay

---

## Agent Usage Guide

1. **Before modifying**: Query this file to confirm impact scope
2. **During modification**: Modify core module first, then synchronize updates to all depended_by documents
3. **Adding new module**: Register depends_on and depended_by in this file, and update README product catalog
4. **Data format changes**: Must synchronize updates to JSON Schema in 09-data-architecture
5. **Verification**: After modification, traverse the "Change Impact Quick Reference" table to confirm no omissions
