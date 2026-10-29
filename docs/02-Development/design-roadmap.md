# Design Retrospective and Future Direction

> This document summarizes the decision-making process across the entire design, current system status, and future development direction.

---

## 1. Project Positioning

**TRPG + Roguelite**, targeting single-player / 1-4 player multiplayer.

Core differentiation: the **differentiated talent tree architecture** — an independent node topology per class, irreversible class advancement, and two-tier Meta/Run choice — is the primary mechanism for build depth.

---

## 2. Design Process Review

### Phase 1: System Framework Setup

The initial phase established framework documents for the core modules: Turn System, Grid and Map, Battle Calculation, Skill and Range, Class System, Talent Tree, Enemy and AI, Run Loop, Data Architecture, and Network Architecture. They carry numbers 01-10 in exactly that order (renumbered 2026-07-11 to follow the progression battle core → character → opponent and flow → technical). 另有 Development Milestones 文档同期建立，未进 01-10 编号序列。

**Key Decisions**:
- Turn-based + speed rotation (not pure CTB), ensuring clear action pacing
- Square grid ≤10x10, no elevation
- Data-driven (JSON) architecture
- Multiplayer uses GameAction command sync model

### Phase 2: Per-Document Audit and Refinement

Starting from 01, auditing and supplementing details document by document, establishing cross-references and consistency between documents.

#### 01 - Turn System Audit
- Added **vocabulary definitions**: Clarified distinction between "unit turn start/end" and "turn start/end"
- **Buff/Debuff timing rules** confirmed: Effect trigger = unit turn start, duration decrement = unit turn end
- **Initiative system**: +1/+2 two-tier priority, overrides speed for forced ordering
- **Same-speed resolution**: decided by difficulty — enemy side first on Old Days Reprise, player side first on every difficulty below it (R3.1)
- **Turn order UI**: Dedicated UI showing queue, status markers, dynamic update rules

#### 02 - Grid and Map Audit
- **Three-layer structure** established: Base terrain → Special terrain (stacked) → Building (overrides base terrain)
- Base terrain expanded from 3 to **9 types** (added Mountain/Peak/Shallow Water/Deep Water/Lava/Swamp)
- ~~**Peak (PEAK)** becomes the only terrain that blocks attack lines~~（攻击线地形阻挡已取消，2026-07-11 用户裁决）
- Special terrain reclassified into 4 categories (Buff/Debuff/Trap/Teleporter), faction effect rules clarified
- **Building interaction**: Ownership rules (player-built = own side only / map preset = both sides), occupation mechanics, durability system (fixed deduction by damage type, outside the standard damage formula), Ruins rules
- ~~**Zone of Control (ZOC)**: Movement -2 when adjacent to enemy in cardinal directions, prevents units from freely disengaging; Sniper talent can resist~~（ZOC 机制已全面删除，2026-07-06 用户裁决）

#### 03 - Battle Calculation Audit - Core, Multi-Round
- **Damage formula** confirmed as FE-style additive base + multiplicative outer layers: Base damage x Skill multiplier x Special terrain modifier x Crit modifier x Relic modifier x Final damage adjustment
- **Hit/Crit uses additive derivation**: hit from DEX vs. avoid from SPD; crit avoidance from LCK. Transparent to players, suitable for attribute-visible TRPG
- **Block removed from base attribute flow**: mitigation effects now belong to Talent/Equipment/Relic special effects, not the universal combat pipeline
- **Distance falloff removed**: Removed after discussion, simplifying the formula
- **Damage type dual-axis system**: Element type (physical/magical/pure/hybrid) x Attack method (melee/ranged/area)
- ~~**Counter-attack system** added: Non-area attacks allow the defender to counter-attack~~（分两步移除：2026-07-11 用户裁决去掉引擎级自动反击、改为配置型；2026-07-12 用户裁决把反击系统整体移除，覆盖此前「配置型反击」口径。移除的是引擎预设的反击框架，不是反击机制本身——反击仍可由天赋 / 敌方特性 / 技能 / 遗物在各自条目内定义）
- ~~**Follow-up system** added: Speed advantage triggers follow-up ((atk.speed - def.speed) x 10% chance), universal to all classes, Swordsman line deeply specializes~~（追击系统已移除；速度的第二效果改为出手顺序 R3.1）
- **Two-stage additional effects**: Post-hit effects vs. post-damage effects
- **Debuff and resistance interaction formula**
- Base damage uses additive buffering: the additive layer is max(0, ·) for physical and magical, and the final damage also floors at 0; pure damage ignores defense
- **Hybrid resolves the two branches separately, then averages**（2026-08-03 用户裁决）: physical and magical are each computed under R1.1 with their own max(0, ·) floor, and the two results are averaged — this is *not* the same as subtracting an averaged defense once, because the floors differ

#### 05 - Class System Audit - Major Rework
- Expanded from 4 base classes to **8 base + 16 class advancement directions**
- 9 complete class positioning designs: Swordsman, Mercenary, Archer, Artificer, Mage (four elemental branches), Knight, Hunter, Cleric
- v1 test 5 classes currently used in the playable prototype: Soldier/Archer/Mage/Knight/Cleric
- Astrologer reserved for future expansion (day/night system)
- **Talent Tree system** established: Resets each Run, Meta unlocks range, earn points during Run to unlock nodes
- Class advancement happens at Lv5 as a level event (costs no talent point), irreversible once chosen

#### 01 - Turn System: Action Resource System
- **Action economy system introduced**: Inspired by BG3's Movement/Action/Bonus Action, splitting each turn's operations into structured action resources
- **Five action type tags**: \[Move Action\]/\[Standard Action\]/\[Swift Action\]/\[Reaction Action\]/\[Free Action\]
- **Turn resource pool**: Movement (move attribute) + Attack Opportunity (1) + Swift Action (1)
- **Cast timing constraints**: Skills can be restricted to before/after move, before/after attack
- **Skill data structure extended**: Added `action_cost` and `timing_constraint` fields
- **Design philosophy supplement**: Action resources = strategic depth — more skills is not always better, limited resources force choices
- **01-turn-system.md standalone document established**

#### 08 - Meta Progression Principles Established
- **Core design principle written in**: Meta = horizontal unlocks (more choices) not vertical power (stat boosts)
- Prohibit situations where insufficient Meta causes core mechanics to be missing
- Talent tree initially contains 1 complete class advancement playstyle, clearing unlocks the 2nd
- Convenience upgrades limited to economy and information aspects only

#### 11 - Town Building Linked Update
- ~~**6 battlefield buildings** fully designed (Watchtower/Fortress/Barricade/Life Spring/Ballista/Magic Tower)~~
- ~~Four building subtypes (Universal/Restricted/Blocking/Range)~~
- ~~**Durability system**: Fixed deduction by damage type, does not use the standard formula~~
- ~~Repair mechanism: Costs gold during Preparation Phase~~

（城镇建设已完全移出 v1，2026-07-11，d9edf3f，文档移入根级 v2/；其中**战场建筑**部分仍在 v1 生效，正典见 grid-and-map.md §建筑、battle-calculation.md 战场建筑修正表、run-loop.md §建筑解锁。「四种子类型」与 grid-and-map 的「两种交互模式」口径不一致，尚未裁决，已登记 doc-drift-ledger D-9。）

---

## 3. Current Document Status

| Document | Status | Audit Depth |
|------|------|---------|
| 01 - Turn System | Audit Complete | Deep audit, multiple additions; **Action Resource System** added, standalone document established |
| 02 - Grid and Map | Audit Complete | Fully rewritten |
| 03 - Battle Calculation | Audit Complete | Fully rewritten, multi-round refinement |
| 04 - Skill and Range | Updated with 03/05 | Structure and fields updated, no independent audit |
| 05 - Class System | Audit Complete | Fully rewritten, major expansion |
| 06 - Talent Tree | In Progress | Design direction confirmed, design tools completed, document needs refinement |
| 07 - Enemy and AI | Partially Updated | Enemy tier ladder and affix system written in alongside the door model; AI scoring section still pending audit |
| 08 - Run Loop | Audit Complete | Door model finalized 2026-07-02/03 and rewritten (doors / Preparation Phase / fixed shop insertions / rewards); Meta section rewritten earlier |
| 09 - Data Architecture | Updated with 02 | Map JSON updated, rest pending audit |
| 10 - Network Architecture | Pending Audit | Initial draft untouched |
| Development Milestones | Pending Audit | Initial draft untouched, needs update per new systems |
| Vision System | Pending Creation | Reserved |
| module-relations | Continuously Updated | Synced to ADR-005 / ADR-008 after acceptance audit |
| README | Continuously Updated | Synced after each audit |
| Design Toolset | Completed | Talent Tree Editor / Equipment Designer / Map Designer / Damage Simulator |

---

## 4. Confirmed Core Design Decisions

### Battle Mechanics

| Decision | Content |
|------|------|
| Damage Formula | FE-style additive base damage with multiplicative outer layers (Base x Skill x Terrain x Crit x Relic x Final adjustment) |
| Hit/Crit | Additive model, fully transparent to player |
| Damage Types | Dual-axis: Element type (physical/magical/pure/hybrid) x Attack method (melee/ranged/area) |
| Block | Removed as a base attribute; any mitigation effects are implemented as Talent/Equipment/Relic specials |
| Counter-attack | No engine-level auto counter-attack; counterplay is defined per-entry by Reaction talents / skills / relics / enemy traits |
| Follow-up | **已移除**（原：(atk.speed − def.speed) x 10% 概率、全职业通用；速度的第二效果改为出手顺序 R3.1） |
| Distance Falloff | None (removed) |
| Base Damage Floor | Additive layer floors at 0 — physical/magical use max(0, ·); final damage also floors at 0, so a hit can resolve to 0 damage against high enough DEF/RES; pure damage ignores defense |
| Hybrid Base Damage | Physical and magical are each computed under R1.1 with their own max(0, ·) floor, then the two results are averaged（2026-08-03 用户裁决）—— **not** a single subtraction of averaged defense |
| Buff/Debuff | Effect trigger = unit turn start, duration decrement = unit turn end |
| Initiative | +1/+2 two tiers, overrides speed ordering |
| Same Speed | Decided by difficulty: enemy side acts first on Old Days Reprise; player side acts first on every difficulty below it. Ties within a side follow spawn order (player 1P-4P, enemy by spawn) |
| Action Resources | Per turn: Movement (move) + Attack Opportunity (1) + Swift Action (1); five action type tags |
| Skill Action Types | \[Move Action\]/\[Standard Action\]/\[Swift Action\]/\[Reaction Action\]/\[Free Action\], same-type mutually exclusive |

### Character Growth

| Decision | Content |
|------|------|
| Class Count | 8 base + 16 advancements (v1 tests 5) |
| Talent Tree | Resets each Run, Meta unlocks range |
| Class Advancement Trigger | Reached at Lv5 — a level event, costs no talent point; irreversible once chosen |
| Growth Sources | Talent Tree (skeleton) + Random equipment/relics/skills (flesh) |
| Non-Growing Attributes | LCK/MOV only change via external means; the other seven (HP/STR/MAG/DEX/SPD/DEF/RES) are growth attributes |

### Roguelite Framework

| Decision | Content |
|------|------|
| Meta Principle | Horizontal unlocks (more choices) ≠ Vertical power (stat boosts) |
| Talent Region | Initially contains 1 complete class advancement playstyle, clearing unlocks the 2nd |
| Convenience Upgrades | Limited to economy/information aspects, no combat stat impact |
| Building Repair | **已移除**（随城镇建设移出 v1，2026-07-11；门模式下的准备阶段只含恢复 / 运输队替换 / 情报） |

### Map and Buildings

| Decision | Content |
|------|------|
| Three-Layer Structure | Base terrain → Special terrain (stacked) → Building (overrides base terrain) |
| Base Terrain | 9 types (Plain/Forest/Mountain/Peak/Wall/Shallow Water/Deep Water/Lava/Swamp) |
| Attack Line Blocking | **已取消**（2026-07-11 用户裁决；原：仅 Peak 阻挡、Wall 不阻挡）—— 攻击线不受任何地形阻挡（R4.3），远程攻击/技能只做射程检查；Peak 仅保留移动阻挡 |
| Building Durability | Fixed deduction by damage type, does not use standard formula |
| Building Destruction | Becomes Ruins, base terrain effects not restored |
| Zone of Control - ZOC | **已全面删除**（2026-07-06 用户裁决；原：离开时移动−2、不叠加） |

---

## 5. Future Development Directions

### Priority 1: System Design Refinement - Current Phase

**Documents pending audit**:
1. **04 - Skill and Range**: Independent audit, confirm whether skill system supports all skill requirements for 8 classes + 16 advancements
2. **07 - Enemy and AI**: Needs AI decision logic updated based on damage types, new terrain, and per-entry Reaction-type counterplay (talents / enemy traits)
3. **09 - Data Architecture**: Update JSON structures for classes/advancements/talent tree
4. **10 - Network Architecture**: Confirm sync requirements for new systems (talent tree, etc.)
5. **Development Milestones**: Re-evaluate development plan based on new system scope

**Documents pending creation/refinement**:
1. **06 - Talent Tree** (most important): Talent node design, tree structure, advancement node placement, point economy, Meta unlock range. Design tools ready (tools/talent-tree-editor.html)
2. **Vision System**: Vision range, fog of war, building vision bonuses

### Completed Support Infrastructure

**Design Toolset** (tools/ directory):
- **Talent Tree Editor**: Canvas graph editor with FSBridge local directory read/write, Dijkstra auto-level calculation, DAG validation, import/export, i18n
- **Equipment Designer**: Equipment attribute design and preview
- **Map Designer**: Three-layer terrain grid editing
- **Damage Simulator**: Formula verification and numerical testing
- **Shared Module** (shared.js): Unified game constants, i18n system, formula functions

### Priority 2: Numerical Reverse Engineering

After system design refinement, perform numerical-level work:

1. **Determine multiplicative layer caps**: Maximum value each system (talent/equipment/relic/building/buff) can affect for each layer
2. **Anchor baseline**: Select reference scenario (e.g., "Lv1 Soldier's basic attack skill vs. regular minion"), reverse-engineer base values
3. **Growth curve verification**: Use damage simulator to verify whether damage multiplier after build completion within a Run is in a healthy range
4. **Build viability**: Verify whether all 9 Roguelite build archetypes have sufficient numerical space

### Priority 3: Content Population

1. **Specific skill design**: Complete skill lists for 8 classes x 16 advancements
2. **Relic system**: Initial relic pool + Meta-unlocked relic design
3. **Enemy templates**: Normal/Elite/Boss specific designs
4. **Map stages**: Actual map configurations and wave designs
5. **Balance iteration**: Continuous numerical adjustment based on prototype testing

### Future Version Reserves

| Feature | Description |
|------|------|
| Astrologer | 9th class, day/night system |
| Vision System | Fog of war, vision range, scouting mechanics |
| More Advancement Branches | Add 3rd, 4th advancement directions to existing classes |
| Cross-Class Skills | Relics/events allow obtaining other class skills |
| Advanced Buildings | Artificer-exclusive special building types |
| PvP Mode | Versus mode utilizing existing TRPG system |

---

## 6. Design Philosophy Summary

1. **Normal difficulty should feel satisfying, high difficulty should have depth**: Multi-layer system supports build diversity, completed builds provide clear power fantasy
2. **Meta horizontal not vertical**: Unlock more choices, not stronger stats
3. **Talent is the skeleton, randomness is the flesh**: Player-controlled directional planning + Roguelite random surprises
4. **Attributes fully transparent**: Additive hit/crit model, players can precisely calculate tactics
5. **Differentiated talent trees are the core differentiator**: An independent node topology per class plus irreversible class advancement makes build depth come from structural choice, not from stacking stats
6. **Class advancement is directional choice not pure stat boost**: Each advancement opens different playstyle approaches
7. **Iterative balance**: The benefit of Roguelite is that you can create OP builds, and also design powerful enemies to counter them
