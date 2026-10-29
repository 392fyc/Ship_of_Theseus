# Swordsman Talent Tree v1 Optimization - Unified Agent Prompt

> Workstream: P2-TALENT | All Agents | Created: 2026-03-15
> Status: ready_to_dispatch

---

## Task Overview

You are optimizing the Swordsman class talent tree (`data/talent-tree/sw_matrix_true_path.json`). This is a **design review + revision** task. Your output is a revised JSON file + a design rationale document explaining all changes.

**Important**: `sw_matrix_true_path.json` is the current working version — use it as your starting point, but do NOT treat it as a template to blindly follow. Identify problems and propose solutions independently.

---

## Mandatory Reading - Read These BEFORE Starting

Read all of the following files in full. Do not skip any.

### Design Rules (Authority Documents)
1. `D:\ShipOfTheseus\ShipOfTheseus-KB\01-Game-Design\Characters\talent-tree-deep-dive-rules.md` — **Primary authority** for deep dive zone (Lv 19-25) topology rules, class lore, gauge definitions, and action economy
2. `D:\ShipOfTheseus\ShipOfTheseus-KB\01-Game-Design\Characters\talent-tree-design.md` — Design philosophy, level anchors, budget framework, Staff notation layout, Bridge Tax, node types
3. `D:\ShipOfTheseus\ShipOfTheseus-KB\01-Game-Design\Characters\talent-tree.md` — System spec, gauge definitions (Sword Intent / Sword Essence), crit rate rules (NO cap), node type definitions
4. `D:\ShipOfTheseus\ShipOfTheseus-KB\01-Game-Design\Characters\class-system.md` — Swordsman class stats, advancement paths (Blade Master / Sword Cultivator), counter-attack and follow-up systems
5. `D:\ShipOfTheseus\ShipOfTheseus-KB\01-Game-Design\Core-Systems\battle-calculation.md` — Damage/accuracy/crit formulas, effective stat calculations
6. `D:\ShipOfTheseus\ShipOfTheseus-KB\01-Game-Design\Core-Systems\turn-system.md` — Action economy (move/standard/swift/reaction/free)
7. `D:\ShipOfTheseus\ShipOfTheseus-KB\01-Game-Design\skills-and-range.md` — Skill data structure, action_cost field

### Current Implementation (Starting Point)
8. `D:\ShipOfTheseus\Ship_of_Theseus\data\talent-tree\sw_matrix_true_path.json` — Current swordsman talent tree JSON (to be optimized)

### Tools
9. `D:\ShipOfTheseus\Ship_of_Theseus\tools\talent-tree-editor.html` — Visual editor for validation (load JSON here to verify Dijkstra paths and level anchors)
10. `D:\ShipOfTheseus\Ship_of_Theseus\tools\shared.js` — Game constants and formulas

---

## Known Issues to Fix

The following problems have been identified through design audit. You MUST address all of them.

### Issue 1: Terminology - Magic Swordsman to Sword Cultivator
- All `ms_*` prefix nodes use outdated "魔剑" (Magic Blade) terminology
- `sw_adv_magic` description says "「魔刃」量谱(0-5层)" — wrong
- Tags still say `magic_swordsman`
- **Fix**: Rename to 剑仙 (Sword Cultivator), update tags to `sword_cultivator` or `sword_immortal`, update gauge references to 剑元 (Sword Essence, MP-like)

### Issue 2: Crit Rate Cap Removed
- `ss_B12` (剑意共鸣) says "溢出50%上限的暴击率等额转化为暴伤加成"
- **Rule change**: Crit rate has NO hard cap. This node's design premise is invalid.
- **Fix**: Redesign this node with a different mechanic that fits the Iai Shura (居合修罗) identity

### Issue 3: Sword Cultivator Identity Overhaul
- Current right-side (ms_*) nodes use an outdated "Magic Blade" (魔刃层数/物魔循环) design
- The new lore (deep-dive-rules §7.2.3) defines Sword Cultivator as:
  - **Core**: Bonded Flying Sword (本命飞剑) — ranged hybrid attacks
  - **Gauge**: Sword Essence (剑元) — MP-like, natural regen, steady consumption
  - **Faction A (万法剑道)**: Long-range kiting, flying sword auto-pursuit, skill synergy
  - **Faction B (诛仙四剑)**: Sword Formation territory control — "陷"(slow) → "戮"(damage) → "绝"(immunity) → ultimate evolution
- **Fix**: Redesign ALL ms_* nodes (Lv 11-20) to reflect the new Sword Cultivator identity. Rename prefix from `ms_` to `sc_` (consistent with deep dive nodes)

### Issue 4: Silver Rose Central Axis Missing
- Design doc (talent-tree-design.md §4.4) describes Bridge nodes at the central axis (x=0):
  - Rose Initiation (cm_M11), Weakness Insight (cm_M13), Thorned Waltz (cm_M16), Rose Finale (cm_M20)
  - These are the "Bridge Tax" toll stations connecting Blade Master and Sword Cultivator paths
- The current JSON has NO central axis Bridge nodes between Lv 11-20
- **Fix**: Add Silver Rose Swordplay bridge nodes along the central axis. Use `requires` with `|` (OR) separator. Ensure they follow Bridge Tax design (cost 1-2 levels of depth for horizontal access)

### Issue 5: Deep Dive Zone Audit (Lv 21-25)
- Verify compliance with deep-dive-rules §3:
  - §3.1: Detour nodes must have `detour` tag and NO out-edges (current detour nodes look correct)
  - §3.2: No same-level bidirectional bridges (check edges between ss_B21↔sc_A21 area)
  - §3.3: Only diagonal single-direction edges or dead-end hubs allowed for cross-line connections
  - §3.4: Inner-outer layout — gauge-specific (剑气/剑元) nodes on outer tracks (x=-400/+400), universal nodes on inner tracks (x=-100/+100)
  - §3.5: Deep dive should be mainly `skill_upgrade` nodes, with new active skills as rare milestones
- Current diagonal edges: `ss_B21→sc_A23` and `sc_A21→ss_B23` — verify these comply with §3.3 (should be N→N+2 single-direction)

### Issue 6: Node Budget Verification
- Design doc says: shared area ~16 nodes, post-advancement branch ~9 nodes each
- Current shared area: 20 nodes (sw_start through sw_adv_saint/magic) — verify if this is intentional or bloated
- Verify total path lengths against level anchors:
  - Lv 10 = advancement (shortest path cost = 10)
  - Lv 15 = minor threshold (_qual nodes)
  - Lv 20 = major threshold (Lv 20 _qual terminal)
  - Lv 22-25 = true ultimate anchor

### Issue 7: Action Economy Tags
- Active skill nodes need `action_cost` field or tag indicating move/standard/swift/reaction
- Current JSON lacks this metadata
- deep-dive-rules §7.1 specifies the action types — ensure all active skills are tagged
- Remember: max 1 move + 1 standard + 1 swift per turn; too many active skills = unusable bloat

---

## Design Constraints (Hard Rules)

1. **All node cost = 1** (no exceptions)
2. **No hardcoded combat values** — all numbers must be derivable from game formulas or expressed as percentages/ratios
3. **Crit rate has NO hard cap** — do not design nodes assuming a cap exists
4. **Block and Crit are mutually exclusive** — a single attack cannot both block and crit
5. **Pure damage ignores block; pure crit = fixed 1.5x** (not affected by crit damage bonuses)
6. **Hybrid damage** uses phys_atk + mag_atk simultaneously, weapon multiplier averaged
7. **Counter-attacks and follow-ups do NOT chain** (no counter-of-counter, no follow-up-of-follow-up)
8. **Area attacks do NOT trigger counter-attacks**
9. **ZOC does NOT stack** (fixed -2 movement penalty, triggered only when leaving control zone)
10. **Distance has NO decay** (no damage falloff at range)

---

## Output Deliverables

### Deliverable 1: Revised JSON
- File: `data/talent-tree/sw_matrix_true_path.json` (overwrite in place)
- Must pass validation in `tools/talent-tree-editor.html`
- All nodes must have: id, name, type, cost(=1), x, y, desc, tags, exclusive, requires, notes
- Edges must form a valid DAG

### Deliverable 2: Design Rationale (Markdown)
- File: write to your agent's working notes or commit message
- For each changed/added/removed node, explain WHY
- Include a summary table: node_id | change_type (added/modified/removed) | rationale
- Highlight any design decisions that deviate from or extend the design documents

### Deliverable 3: Path Budget Verification
- Show Dijkstra shortest paths from sw_start to each terminal node
- Verify level anchors are hit correctly
- Show total node count per zone (shared / blade master / sword cultivator / silver rose / deep dive)

---

## Worktree and Branch Rules

Each agent has a **dedicated worktree** — an isolated full copy of the repo. You MUST work inside your assigned worktree, not the main repo.

### Worktree Assignments

| Agent | Worktree Path | Branch |
|-------|--------------|--------|
| Codex CLI | `D:\ShipOfTheseus\sw-opt-codex` | `codex/sw-talent-optimize` |
| opencode | `D:\ShipOfTheseus\sw-opt-opencode` | `opencode/sw-talent-optimize` |
| AntiGravity | `D:\ShipOfTheseus\sw-opt-ag` | `antigravity/sw-talent-optimize` |

### How to Use Your Worktree

1. **All file reads/writes** use your worktree path as root. Example for Codex CLI:
   - Read: `D:\ShipOfTheseus\sw-opt-codex\data\talent-tree\sw_matrix_true_path.json`
   - Write: `D:\ShipOfTheseus\sw-opt-codex\data\talent-tree\sw_matrix_true_path.json`
   - Editor: `D:\ShipOfTheseus\sw-opt-codex\tools\talent-tree-editor.html`

2. **KB files are read-only references** — read them from the KB path (`D:\ShipOfTheseus\ShipOfTheseus-KB\...`) but do NOT write to KB.

3. **Git operations** — your worktree is already on the correct branch. Just commit when done:
   ```bash
   cd D:\ShipOfTheseus\sw-opt-codex   # (use YOUR worktree path)
   git add data/talent-tree/sw_matrix_true_path.json
   git commit -m "design(P2-TALENT): optimize swordsman talent tree"
   ```

4. **Do NOT** run `git checkout`, `git switch`, or `git worktree` commands — the branch is pre-configured.

### File Scope Rules

- **Allowed writes**: `data/talent-tree/` only (inside your worktree)
- Do NOT modify `tools/`, `scripts/`, or any KB files
- Commit message format: `design(P2-TALENT): {summary}`

---

## Quality Checklist (Self-Verify Before Submitting)

- [ ] All "魔剑"/"magic_swordsman"/"魔刃" terminology replaced with 剑仙/sword_cultivator/剑元
- [ ] ss_B12 redesigned (no crit cap overflow mechanic)
- [ ] All Sword Cultivator (Lv 11-20) nodes reflect Flying Sword / Sword Essence / Formation identity
- [ ] Silver Rose Bridge nodes added (cm_M11, cm_M13, cm_M16, cm_M20 or equivalent)
- [ ] Bridge nodes use `requires` with `|` (OR) separator
- [ ] Deep dive zone complies with deep-dive-rules §3 (diagonal edges, detour tags, inner-outer layout)
- [ ] No same-level bidirectional bridges in deep dive
- [ ] Active skills have action_cost tags (move/standard/swift/reaction)
- [ ] No more than ~3 active skills per advancement path (action economy constraint)
- [ ] Path budget verified: Lv 10=advancement, Lv 15=threshold, Lv 20=major threshold, Lv 22-25=ultimate
- [ ] JSON loads and validates in talent-tree-editor.html
- [ ] All design changes documented with rationale

---

*Generated: 2026-03-15 | Claude Code Main Agent | For dispatch to: AntiGravity, Codex CLI, opencode, Claude Code*
