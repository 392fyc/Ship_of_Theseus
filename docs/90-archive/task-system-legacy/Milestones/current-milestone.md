# Development Milestones

> Back to [[game-design-doc|GDD]]

## Overview

Progress by milestones; each phase ends with a playable deliverable. The first 5 phases are fully single-player development; Phase 6 adds multiplayer.

**Core Principle**: Validate gameplay with color blocks first; only invest in art after confirming the core loop is fun.

---

## Phase 1: Grid Prototype - 1-2 Weeks

**Goal**: Build an interactive grid system in Godot.

- [ ] Godot 4 project initialization
- [ ] TileMap building 10x10 grid
- [ ] Click cell to highlight
- [ ] Place units (color blocks / simple sprites)
- [ ] Click to select unit, BFS calculate and display movement range
- [ ] Click target cell, A* pathfinding and move unit
- [ ] Different terrain movement costs (color-coded terrain)
- [ ] Units cannot overlap (occupation check)

**Acceptance Criteria**: Can place multiple units on the grid, select and move them, terrain affects movement range.

---

## Phase 2: Turn and Battle - 2-3 Weeks

**Goal**: Complete turn-based speed rotation system + basic attacks.

- [ ] Turn system (TurnManager: turn advancement + speed sorting)
- [ ] Turn order preview UI (sidebar showing upcoming units)
- [ ] Unit action flow: select → move → attack/wait → end
- [ ] Basic attack (melee, adjacent single target)
- [ ] Damage calculation formula implementation
- [ ] Hit/evasion/crit determination
- [ ] Damage number display (DamagePopup)
- [ ] Unit death (removed when HP reaches 0)
- [ ] Win/lose determination (one side eliminated)
- [ ] Basic enemy AI (AGGRESSIVE: rush nearest target and attack)

**Acceptance Criteria**: Players and AI enemies take turns acting, can fight a complete battle to victory or defeat.

---

## Phase 3: Skills and Range - 2-3 Weeks

**Goal**: Skill system, range display, AOE area.

- [ ] JSON data loader (DataLoader)
- [ ] Skill data definitions (at least 6-8 skills)
- [ ] Range pattern rendering (diamond/line/cross)
- [ ] Attack target selection UI (select target within range)
- [ ] AOE area preview (show affected cells before casting)
- [ ] AOE damage execution (resolve against all units in area)
- [ ] Skill cooldown system
- [ ] Action menu (move / skill list / wait)
- [ ] Terrain modifier and special terrain effects implementation

**Acceptance Criteria**: Units can use skills with different ranges and areas, cooldown system works correctly.

---

## Phase 4: Class and AI Polish - 2-3 Weeks

**Goal**: 4 playable classes, AI with tactical depth.

- [ ] 4 base class data
- [ ] Per-class initial skill differences
- [ ] Basic equipment system (weapons affect attributes)
- [ ] AI behavior pattern expansion (DEFENSIVE/SUPPORT/HIT_AND_RUN)
- [ ] AI scoring system refinement (consider terrain, kills, positioning)
- [ ] Enemy wave entry (Wave System)
- [ ] 3-5 enemy templates
- [ ] 1 simple Boss (fixed skill rotation)
- [ ] Initial battle difficulty balancing

**Acceptance Criteria**: 4 classes feel distinctly different, AI has basic tactical behavior, Boss has learnable patterns.

---

## Phase 5: Roguelite Framework + Town Building - 4-6 Weeks

**Goal**: Complete single Run experience including town building.

- [ ] Run manager (RunManager: 3 Acts x 8 Stages structure)
- [ ] Preparation Phase UI (town building / shopping / skill adjustment / deploy)
- [ ] Town building system (construct / upgrade / expand)
- [ ] Functional building implementation (Weapon Shop, Potion Shop, Training Ground)
- [ ] Battlefield building implementation (Life Fountain, Watchtower, Barricade)
- [ ] Battlefield building placement (designated positions within restricted zone)
- [ ] Battlefield building interaction with battle system (special terrain cell effects)
- [ ] Battle rewards (gold + loot)
- [ ] Experience and leveling
- [ ] Special event stages (2-3)
- [ ] Complete Act 1 (8 stages, Boss included at stage 8)
- [ ] Run failure (party wipe) → return to main menu
- [ ] Basic Meta Progression (permanent currency + unlocks)

**Acceptance Criteria**: Can fully experience a single Run of Act 1, including Preparation Phase town building, multiple battles, Boss fight.

---

## Phase 6: Multiplayer - 4-6 Weeks

**Goal**: 1-4 player LAN multiplayer playable.

- [ ] GameAction serialization / deserialization
- [ ] Godot MultiplayerAPI / ENet connection
- [ ] Host-Client architecture setup
- [ ] Character selection (each picks 1 class)
- [ ] Action synchronization (current actor operates → broadcast → execute)
- [ ] Non-acting player waiting UI
- [ ] Action timeout handling (60 second auto-wait)
- [ ] Reward selection sync (each selects independently)
- [ ] Shop/event multiplayer handling
- [ ] Random number seed synchronization
- [ ] Disconnection detection + AI takeover
- [ ] Multiplayer lobby (create / join room)

**Acceptance Criteria**: 2-4 players can complete a Run over LAN multiplayer.

---

## Future - Priority TBD

- [ ] Art replacement (GBA pixel art sprites)
- [ ] Battle animations (attack / skill effects)
- [ ] Sound effects and BGM
- [ ] More classes (unlock system)
- [ ] More stages / enemies / bosses
- [ ] More relics and events
- [ ] Act 2, Act 3 content
- [ ] Public network multiplayer solution
- [ ] Difficulty selection
- [ ] Achievement system

---

## Time Estimate Summary

| Phase | Estimated Time | Cumulative |
|-------|---------|------|
| Phase 1: Grid Prototype | 1-2 weeks | 2 weeks |
| Phase 2: Turn and Battle | 2-3 weeks | 5 weeks |
| Phase 3: Skills and Range | 2-3 weeks | 8 weeks |
| Phase 4: Class and AI | 2-3 weeks | 11 weeks |
| Phase 5: Roguelite + Town Building | 4-6 weeks | 17 weeks |
| Phase 6: Multiplayer | 4-6 weeks | 23 weeks |

*Estimates assume Vibe Coding assistance; actual timeline may vary due to engine learning curve and debugging.*

---

Related documents:
- Each Phase's corresponding system documents: see [[game-design-doc|GDD]]
