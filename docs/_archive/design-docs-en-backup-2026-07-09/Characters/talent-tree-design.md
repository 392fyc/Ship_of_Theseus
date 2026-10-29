# Talent Tree Design Theory

> This document records the **universal** talent tree design philosophy and structural rules (§1–§3, §6–§7). Per-class topology implementations are authoritative in `data/talent-tree/*.json`.
>
> ⚠️ **Authoritative source for per-class topologies**: `data/talent-tree/*.json`. The previous Myrmidon Five-Staff 5-track layout (formerly §4–§5, since removed) is **superseded** by `data/talent-tree/sw_matrix_true_path.json` (L/M/R 3-track). See §4 for the JSON index and future simplification direction.
>
> Related docs: [[01-Game-Design/Characters/talent-tree|Talent Tree System Spec]] · [[01-Game-Design/Core-Systems/turn-system|Action Resource System]]

---

## 1. Core Design Philosophy

### 1.1 Level Equals Node - 1 Node = 1 Cost = 1 Level

Abandon manual level fields; **node level is automatically calculated via Dijkstra shortest path from the start node**.

- Each node `cost: 1` (the only legal value)
- Node level = cumulative cost of shortest path from Start node
- Calculated and displayed in real-time via `computeShortestPaths()` in the talent tree editor

### 1.2 Level Anchors

| Level | Milestone | Design Intent |
|-------|-----------|---------------|
| Lv 10 | Class Advancement | Bipolar divergence starting point; choose Kensei / Sword Immortal |
| Lv 15 | Minor Threshold | Gauge system takes shape; faction begins forming |
| Lv 20 | Major Threshold (`_qual`) | Faction ultimate skill threshold; highest quality-change point |
| Lv 22-25 | Terminal Anchor Zone | Terminal abilities unlock here (see deep-dive-rules §2) |
| Lv 30 | Ultimate Boundary | Deepest layer nodes; theoretical upper limit |

### 1.3 Horizontal Bridge Cost - Bridge Tax

Cross-faction nodes (Bridge) deviate from the shortest path, causing **ultimate skills to be delayed by 1-2 levels**, forming the core trade-off:

> **Specialization Breakthrough** (follow the main-line shortest path straight to the terminal) vs **Mechanical Synergy** (horizontally unlock adjacent faction nodes, sacrificing depth for breadth)

### 1.4 Budget Framework

| Investment Phase | Cost Budget | Description |
|------------------|-------------|-------------|
| Shared Early Investment (Lv 1-10) | ~17 cost | Mandatory path; all Myrmidons must pass through |
| Single Extreme Main Chain (Lv 11-30) | ~20-22 cost | Deepest path from class advancement to terminal |
| Horizontal Exploration Budget | Remaining cost | Cross-axis unlocking of other branches; determined by level cap |

Average players (Lv 25 / 25 points) can exactly complete the shared zone + one full side path; expert players (Lv 28-30) can explore cross-axis.

---

## 2. requires Field Syntax Convention

The `requires` field in talent tree JSON supports two logical operators:

| Separator | Meaning | Example | Interpretation |
|-----------|---------|---------|----------------|
| `,` (comma) | **AND** | `"requires": "node_a,node_b"` | Requires both node_a and node_b unlocked |
| `\|` (pipe) | **OR** | `"requires": "node_a\|node_b"` | Requires only node_a or node_b unlocked |

**Typical Applications**:
- When a Bridge node connects two mutually exclusive advancement paths, use `|` separator (OR logic)
- Regular prerequisite nodes use `,` separator (AND logic) or rely directly on edges

**Distinction Between edges and requires**:
- `edges` defines graph connectivity (Dijkstra path calculation depends on edges)
- `requires` defines additional unlock prerequisites (can be empty — edges alone can express dependencies)
- Bridge nodes need both edges (to ensure correct path calculation) and requires (to ensure correct unlock conditions)

---

## 3. Action Resource Economics

Active skill nodes (`active_skill`) in the talent tree are tagged with action cost types, integrated with the turn system:

| Action Type | Tag | Cost | Per-Turn Limit | Typical Scenario |
|-------------|-----|------|----------------|------------------|
| Move Action | `action_cost: "move"` | Movement points | Cannot normal-move after use | Displacement skills (Charge, Evasion Step) |
| Standard Action | `action_cost: "standard"` | Attack opportunity | Cannot normal-attack after use | Attack skills, powerful buffs |
| Swift Action | `action_cost: "swift"` | No main resource | 1 per turn | Stance switching, short-duration buffs |
| Reaction Action | `action_cost: "reaction"` | Condition-triggered | Depends on trigger conditions and gauge | Counter-attack enhancement, on-hit response |
| Free Action | `action_cost: "free"` | No cost | Unlimited | Information viewing, state toggling |

**Key Design Constraint**: A maximum of 3 skills can be actively used per turn (1 Move + 1 Standard + 1 Swift), combined with the substitution relationship of normal movement and normal attack, forming intra-turn tactical choices.

---

## 4. Per-Class Topology Implementations (Reference JSON)

### 4.1 Authoritative Sources

Per-class talent tree topologies (node layout, edges, requires) are defined in JSON files under `data/talent-tree/`. This document (§1–§3, §6–§7) describes **universal** rules that apply across all classes; per-class specifics live in JSON only.

| Class | Authoritative File | Topology |
|-------|--------------------|----------|
| Myrmidon | `data/talent-tree/sw_matrix_true_path.json` | L/M/R 3-track |
| Mage | `data/talent-tree/mg_pentagram.json` | (pending topology description) |
| Other 6 Classes | — | Pending |

Earlier Myrmidon JSON versions (`sw_a`, `sw_cycle_v3`, `sw_onhit_v3`, `sw_overwatch_v3`, `sw_starburst`, `sw_a_deep`) are exploratory history and **non-authoritative**.

### 4.2 Future Simplification Direction (All Classes)

All talent trees will undergo systematic simplification in future iterations:

- **Retain in talent tree**: Key functional nodes — passive traits defining class identity, active skills, gauge-core nodes, Class Advancement trigger nodes
- **Migrate out to roguelite layer**: Generic numeric nodes (minor stat bonuses, flat-number traits) → Relics, equipment, meta growth

**Goals**:
- Lower player learning curve (fewer nodes to understand per run)
- Lower design cost (fewer nodes to balance per class × 16 advancement paths)
- Lower balance complexity (generic stats handled by roguelite randomness, not per-class balance)

### 4.3 Historical Reference: Deprecated Myrmidon Five-Staff Design

The original Myrmidon Five-Staff 5-track layout (-400 / -200 / 0 / +200 / +400) is preserved in version-control history as **design intent reference** but is **not the authoritative topology**. Current implementation follows `data/talent-tree/sw_matrix_true_path.json` (L/M/R 3-track).

Kensei / Sword Immortal advancement names and Gauge concepts (Sword Intent for Kensei; Sword Essence for Sword Immortal) remain valid as class identity; only the 5-track node layout has been simplified.

---

## 6. Node Type Supplement

### 6.1 Single-Track Nodes - Detour

| Property | Description |
|----------|-------------|
| Definition | A branch node with in-edges (pointed to by some node), no out-edges, and not a terminal; reachable but cannot continue — a strategic spur off the main path |
| Tags | Must include `"detour"` tag |
| Design Intent | Has value but does not advance the main chain; players must actively "backtrack" spending cost |
| Existing Example | `ss_iso15` (Heartless Deflection) — on evasion failure, spend Sword Intent to reduce damage |
| Data Rules | No new fields needed; identified only by tags; editor can display special styling based on this |

### 6.2 Complete Node Type Table

| type Value | Description | Example |
|------------|-------------|---------|
| `trait` | Trait/characteristic; permanent passive | Sword Mastery Basics, Sword Heart Clarity |
| `passive` | Condition-triggered passive | Sharp Edge, Chain, Unstoppable Force |
| `active_skill` | Active skill | Sword Dance, Sword Energy Release |
| `skill_upgrade` | Existing skill upgrade | Keen Wound, Piercing Shot |
| `gauge_core` | Gauge core unlock | Sword Energy Embodiment, Focus |
| `gauge_extend` | Gauge extension/upgrade | Sword Intent Fusion, Trajectory Mastery |
| `advancement` | Class advancement node (mutually exclusive) | Path of the Kensei, Path of the Sword Immortal |
| `stat_minor` | Minor stat bonus | ATK+2, CRIT+3% |

---

## 7. Roguelite Integration

### 7.1 Per-Run Partial Unlock

- The talent tree uses a **permanent unlock** system at the Meta layer (Demo version), but within a Roguelite run, only some nodes are available per run
- During the reward phase after each battle, players choose which nodes to activate for the current run from their unlocked pool
- This creates a dual-layer choice of "Meta layer picks direction / in-run picks Build"

### 7.2 Economic Decisions

Talent tree node unlocking competes with town building investment for the same resource pool:
- **Invest in Talents**: Individual character becomes stronger; high returns for the current run
- **Invest in Buildings**: Team-wide / permanent benefits; accumulates across runs
- This resource contention is a supporting depth mechanic; the core differentiator is the talent tree architecture itself (per-class topology + Class Advancement + dual-layer meta/run selection, see §1–§3 + JSON authoritative files in §4.1), with town building providing economy/shop floor

---

## Open Questions

> The following questions were confirmed in the 2026-02-26 session; see Task C audit conclusions for details.

1. ~~Bridge node requires logic~~ -> **Confirmed as OR (pipe separator)**
2. ~~Deep Dive node cost=8~~ -> **Confirmed expanded into 8 independent cost=1 nodes**

---

*Created: 2026-02-26 · Design Agent (Claude)*
