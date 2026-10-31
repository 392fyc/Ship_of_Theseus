# ADR-009: Action Economy Implementation Architecture

- Status: Approved
- Date: 2026-03-12
- Context: Define the code architecture for implementing the BG3-style Action Economy system specified in GDD Section 1 (Turn System)
- Prerequisites: [ADR-005 (Attribute System)](https://github.com/392fyc/Ship_of_Theseus/blob/30e3c5e5d57e9a74f01d19ca948c869512f66a0c/docs/03-decisions/adr-2026-02-27-attribute-system-v1.md) (deleted from the KB 2026-10-31; permanent link), ADR-008 (Scene Naming - TacticalScene/TacticalManager)
- Task Reference: TASK-P2-BATT-001

---

## Decision Summary

Implement per-unit per-turn action resource tracking directly on `unit.gd`, with validation gates in `tactical_manager.gd` before skill execution. Add `timing_constraint` field to all skill JSONs. Build a new SkillPanel UI scene for skill selection with availability feedback.

---

## Decision 1: Resource State Location

### Options Considered

| Option | Description | Pros | Cons |
|--------|-------------|------|------|
| A - unit.gd direct | Add resource bools to unit.gd | Simple, co-located with cooldown state | unit.gd grows larger |
| B - ActionResourceManager | New autoload/manager class | Clean separation | Extra indirection, over-engineered for 4 bools |
| C - turn_manager.gd dict | Store in turn manager keyed by unit | Centralized turn state | Awkward ownership, unit cannot self-query |

### Decision: Option A - unit.gd direct

Resource state belongs to the unit, just like HP and cooldowns. Four boolean flags plus reset method is minimal. Co-location with `skill_cooldowns` keeps all per-unit-per-turn state in one place.

```
# unit.gd additions
var movement_used: bool = false
var standard_used: bool = false
var swift_used: bool = false
var reaction_available: bool = true

func reset_action_resources() -> void:
    movement_used = false
    standard_used = false
    swift_used = false
    reaction_available = true
```

`reset_action_resources()` called at unit turn start, alongside existing buff tick logic.

---

## Decision 2: Validation Gate Location

### Options Considered

| Option | Description |
|--------|-------------|
| A - tactical_manager.gd | Validate before dispatching GameAction |
| B - game_action.gd | Validate inside GameAction execution |
| C - Dual gate | Pre-check in tactical_manager, enforce in game_action |

### Decision: Option C - Dual gate

- **Pre-check** in `tactical_manager.gd`: determines which skills to grey out in UI, prevents invalid skill selection from reaching GameAction pipeline
- **Enforce** in `game_action.gd`: hard validation before execution, safety net against programmatic misuse (AI, scripts)

This follows the existing pattern where `tactical_manager.gd` already reads `action_cost` (line ~494) and `game_action.gd` processes commands.

---

## Decision 3: timing_constraint Field Strategy

### Schema Addition

All 15 skill JSONs gain a new field:

```json
{
  "timing_constraint": "any"
}
```

Valid values: `"any"` | `"before_move"` | `"after_move"` | `"before_attack"` | `"after_attack"`

### Default Value

`"any"` for 13 of 15 skills. Only 2 skills have non-default constraints:
- `archer_eagle_eye`: `"before_attack"` (aim before shooting)
- `knight_iron_wall`: `"before_move"` (sacrifice mobility for defense)

### Validation Logic

timing_constraint is checked AFTER action_cost validation passes:

```
match timing_constraint:
    "any": pass
    "before_move": assert movement_used == false
    "after_move": assert movement_used == true
    "before_attack": assert standard_used == false
    "after_attack": assert standard_used == true
```

---

## Decision 4: Normal Move/Attack Resource Consumption

Normal movement and normal attack must also consume resources to enforce mutual exclusion with skills.

| Action | Resource Consumed |
|--------|-------------------|
| Normal move (grid movement) | `movement_used = true` |
| Normal attack | `standard_used = true` |
| Move Action skill | `movement_used = true` |
| Standard Action skill | `standard_used = true` |
| Swift Action skill | `swift_used = true` |

Integration points:
- Normal move: in `tactical_manager.gd` movement handling, set `unit.movement_used = true`
- Normal attack: in `tactical_manager.gd` attack handling, set `unit.standard_used = true`
- Skill use: in validation gate, consume appropriate resource

---

## Decision 5: Bottom Dashboard UI Architecture (Revised per TASK-P2-BATT-002)

### Architecture: Bottom Dashboard + Primary Menu + Skill Bar

| Component | Spec |
|-----------|------|
| Bottom Dashboard | Screen bottom HUD, contains character info + action menu |
| Primary Action Menu | [Attack] [Skill] [Item] [End Turn] — core interaction buttons |
| Skill Bar | Hidden by default; slides out horizontally from [Skill] button |
| Scene paths | `scenes/tactical/bottom_dashboard.tscn`, `scenes/tactical/skill_bar.tscn` |
| Script paths | `scripts/ui/bottom_dashboard.gd`, `scripts/ui/skill_bar.gd` |

### Dynamic Phase Filtering

Skill Bar filters skills by current phase:
- Move Phase: highlight Move + Swift skills; Standard skills greyed/disabled
- Action Phase: highlight Standard + Swift skills; Move skills greyed/disabled
- Unavailable skills remain visible with tooltip showing reason

### UI State Machine (S0-S6)

See `action-economy-ui-spec.md` for complete state diagram.

### Unavailability Reasons (priority order)

1. Phase mismatch: "当前处于移动阶段，请先完成移动"
2. Cooldown active: "冷却中 (X 回合后恢复)"
3. Resource spent: "攻击机会已使用" / "已失去移动机会"
4. Timing constraint: "需要在移动前使用" / "需要在攻击后使用"

---

## Decision 6: action_cost Value Normalization

Current `knight_charge.json` uses `"movement"` instead of the canonical `"move"`. Normalize to match GDD specification.

Canonical enum: `"move"` | `"standard"` | `"swift"` | `"reaction"`

`"free"` merged into `"swift"` with `swift_limit: -1` (unlimited). See TASK-P2-BATT-002 design spec.

All runtime code must use these exact string values. No aliases.

---

## Decision 7: Turn Flow Integration (Revised — Phased Model)

Revised from "freely ordered" to FE-style **phased turn flow** per TASK-P2-BATT-002.

```
Unit Turn Start
  |-- reset_action_resources()
  |-- buff/debuff tick (existing)
  |
  |-- Move Phase (S1)
  |   |-- Dashboard slides up; [Attack] greyed/disabled
  |   |-- Available: normal move, Move Cost skills, Swift skills
  |   |-- End: move to tile / click self / [End Move] button
  |   |-- Undo Move available until attack/skill committed
  |
  |-- Action Phase (S2)
  |   |-- [Attack] + Standard skills unlocked
  |   |-- Available: [Attack], Standard skills, Swift skills
  |   |-- Execute Standard → consumes Standard + Move resources (cascade)
  |   |-- Combat Forecast shown before attack confirmation
  |
  |-- Swift Phase (S5, if Standard+Move consumed but Swift remains)
  |   |-- Only [Skill(Swift)] + [End Turn] visible
  |
  |-- End Turn (S6)
  |   |-- Manual: [End Turn] button at any phase
  |   |-- Auto: all resources consumed + no available Swift (configurable)
  |   |-- cooldown decrement, buff duration decrement
```

### Resource Cascade Rule

Standard Action (attack or Standard skill) consumes **both** Standard AND Move resources. This enforces "move → act → end" rhythm. Canto/Hit-and-Run talents can override by preserving/returning Move resource.

### Undo Move

Player can revert position after moving but before committing attack/skill. Right-click/ESC/[Cancel] in Action Phase (S2) returns unit to pre-move position and restores Move resource.

---

## Impact Scope

| File | Change | Severity |
|------|--------|----------|
| `scripts/units/unit.gd` | Add 4 resource bools + reset method | Low |
| `scripts/core/tactical_manager.gd` | Pre-check gate, normal move/attack resource consumption | Medium |
| `scripts/core/game_action.gd` | Enforce gate for action_cost + timing_constraint | Medium |
| `scripts/ui/skill_panel.gd` | **NEW** - Skill Panel UI logic | Medium |
| `scenes/tactical/skill_panel.tscn` | **NEW** - Skill Panel scene | Medium |
| `scenes/tactical/tactical_scene.tscn` | Add SkillPanel as child | Low |
| `scripts/tactical/tactical_scene.gd` | Wire SkillPanel signals | Low |
| `data/skills/*.json` (15 files) | Add timing_constraint, fix knight_charge action_cost | Low |

### No Changes Required

- `scripts/core/turn_manager.gd` - turn order logic unchanged
- `scripts/core/damage_calculator.gd` - damage formula unchanged
- Cooldown system in `unit.gd` - already functional, only needs UI wiring

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| AI not respecting resource constraints | Enforce gate in game_action.gd catches all callers |
| SkillPanel performance with many skills | Current max 3 skills per class, no performance concern |
| timing_constraint complexity for players | Only 2 of 15 skills have non-"any" constraints initially |
| Future reaction implementation | reaction_available bool is placed but reaction trigger logic is deferred to M11 |

---

*Created: 2026-03-12 | Main Agent (Claude Code) | Approved for TASK-P2-BATT-001 implementation*
