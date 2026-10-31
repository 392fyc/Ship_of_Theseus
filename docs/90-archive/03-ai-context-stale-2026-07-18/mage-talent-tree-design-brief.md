# Mage Talent Tree Design Brief

> Workstream: P2-TALENT | Agent: AntiGravity (Gemini 3.1 Pro)
> Collaborative design task with human. Output: talent tree JSON + gauge definitions.
> Created: 2026-03-14 | Updated: 2026-03-14 | Status: in_progress_phase1

---

## Task Summary

Design the Mage class talent tree using a **3-element origin + 2-advancement trapezoid** topology.
The old 4-advancement-path conflict is resolved: elements are reduced to 3 (Fire, Ice, Air),
with a unique element exclusion mechanic and 2 advancement paths.

**Reference gold standard**: Swordsman talent tree v1 (`data/talent-tree/sw_starburst.json`)
loaded in `tools/talent-tree-editor.html`.

---

## Design Direction - DECIDED

### Topology: Trapezoid

```
     [Fire]  [Ice]  [Air]        <- Origin layer (3 nodes, mutually exclusive)
       \      |      /
        \     |     /
         \    |    /
    [Grand Sage] [Element Sage]  <- Advancement layer (2 nodes)
         \    |    /
      ┌──────────────────┐
      │  Three-element   │       <- Post-advancement talent area
      │  ring + generic  │          (element nodes interspersed with
      │     nodes        │           universal magic nodes)
      └──────────────────┘
```

### Element Exclusion Mechanic

- Player picks ONE origin element node (Fire / Ice / Air) at the start
- Once chosen, **all nodes of the other two elements are excluded** (cannot be lit)
- This exclusion persists through pre-advancement and into post-advancement
- Exception: Grand Sage advancement removes the exclusion

### Advancement Paths (2 nodes)

**Grand Sage (大贤者)**
- Element Affinity: removes element exclusion from origin choice
- Player can freely light nodes of any element (still requires valid path in tree graph)
- Ultimate capability: fuse all three elements for special fusion magic

**Fire/Ice/Air Sage (火/冰/气之贤者)**
- Advancement effect varies based on origin element chosen
- Post-advancement node access remains restricted to chosen element + generic nodes
- Ultimate capability: master-level single-element terminal magic

### Post-Advancement Area Rules

- Three element lines weave around the post-advancement area
- Generic/universal magic nodes are interspersed between element-specific nodes
- **CRITICAL**: Single-element nodes MUST NOT be hub nodes (must not be the only path)
  - This ensures Element Sages (restricted to one element) are never blocked
  - Grand Sages can traverse freely since exclusion is lifted
- Grand Sage terminal: triple-element fusion magic (requires nodes from all 3 elements)
- Element Sage terminal: element-specific ultimate magic

### Superseded Options

The previous A/B/C options are superseded by this decision:
- Old Option A (reduce to 2 paths) - rejected: loses element variety
- Old Option B (keep 4 paths) - rejected: too much content, Wind/Lightning undesigned
- Old Option C (2+2 sub-spec) - rejected: replaced by cleaner 3-element exclusion model
- Old 4 elements (Fire/Wind/Lightning/Water) replaced by 3 elements (Fire/Ice/Air)

---

## Reference Materials

The design agent MUST read the following before starting:

### Mandatory Reads
- `01-Game-Design/Characters/talent-tree-design.md` - Full design philosophy, requires syntax, budget framework, Staff notation
- `01-Game-Design/Characters/talent-tree.md` - System spec, node types, gauge definitions
- `01-Game-Design/Characters/class-system.md` - Mage class stats, 4 advancement paths, skill descriptions
- `01-Game-Design/skills-and-range.md` - Skill data structure with action_cost

### Reference Data
- `data/talent-tree/sw_starburst.json` - Swordsman v1 talent tree (load in talent-tree-editor.html)
- `tools/talent-tree-editor.html` - Visual editor for validation
- `tools/shared.js` - Game constants and formulas

---

## Design Deliverables

### 1. Trapezoid Layout Design
- Design the 3 origin nodes with element exclusion logic
- Place Grand Sage and Element Sage advancement nodes
- Ensure pre-advancement paths from all 3 origins reach both advancement nodes
- Document node connectivity forming the trapezoid shape

### 2. Faction Design per Branch
For each post-advancement faction:
- Tactical role and combat philosophy
- Core mechanics (unique to the faction)
- Action pattern (typical turn sequence using action economy)
- Terminal ability (Lv 20 ultimate skill)

### 3. Gauge Definitions
For each advancement path, define:
- Gauge name, type (energy 0-100 / stacks 0-N / dual-state)
- Gain conditions
- Decay/loss conditions
- Interval effects or stack effects
- Design keywords

Fire Sage (Hellfire) gauge already defined in talent-tree.md (may need adaptation for new 3-element model).
Water Sage (Tide) gauge from old design - evaluate if Ice element inherits or needs redesign.
Air element gauge: needs new design from scratch.
Grand Sage: may need a unique fusion gauge or shared gauge mechanic.

### 4. Talent Tree JSON
Following the Swordsman v1 format:
- All nodes with: id, name, type, x, y, cost(=1), edges, requires, description
- Tags for detour/bridge nodes
- Validate in talent-tree-editor.html (Dijkstra paths, level anchors)

### 5. Node Budget Verification
- Shared pre-advancement area: ~16 nodes
- Post-advancement branches: ~9 nodes each
- Level anchors: Lv10=advancement, Lv15=minor threshold, Lv20=ultimate, Lv30=deep boundary
- Verify with Dijkstra shortest path calculation in editor

---

## Constraints

- All node `cost: 1` (no exceptions)
- Node types must use the defined set: trait/passive/active_skill/skill_upgrade/gauge_core/gauge_extend/advancement/stat_minor
- Active skills must specify action_cost (move/standard/swift/reaction/free)
- Bridge nodes use `requires` with `|` (OR) separator
- Trapezoid topology: 3 origin nodes (top) → 2 advancement nodes (middle) → post-advancement area (bottom)
- Single-element nodes MUST NOT be hub/chokepoint nodes (ensure no element-locked dead ends)
- Element exclusion: origin choice locks out other elements; Grand Sage lifts this restriction
- Mage stat profile: High MAG, lowest HP/DEF/MOV - design should leverage range and AOE

---

## Collaboration Protocol

1. Direction decided: 3-element trapezoid with exclusion mechanic (this document)
2. AntiGravity drafts detailed faction designs + gauge specs for Fire/Ice/Air + Grand Sage
3. Human reviews and iterates
4. AntiGravity designs post-advancement node layout (ensuring no single-element chokepoints)
5. Human reviews topology
6. AntiGravity produces JSON, validates in editor
7. Human final approval

All design artifacts go to `data/talent-tree/` in the game repo.
Design documentation updates go to `01-Game-Design/Characters/` in the KB repo.

---

## Agent Instructions

- Model: Gemini 3.1 Pro (AntiGravity)
- Branch: `antigravity/mage-talent-design`
- This is a DESIGN task, not implementation. Output is JSON data + design documentation.
- Work iteratively with the human. Do not finalize without human approval.
- Use talent-tree-editor.html to validate all JSON output.
- Respect the established Swordsman talent tree as the structural template.
