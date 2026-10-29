# Swordsman Talent Tree v1 — opencode Feedback (Round 2)

> Source: Main Agent parallel audit of commit `7ff13b2` on `opencode/sw-talent-optimize`
> Date: 2026-03-15 | Priority: apply all changes, re-commit to same branch

---

## Audit Summary

Your R1 submission has clean terminology, valid deep dive topology, and proper action_cost tagging. However, there are 2 critical issues and 2 new design rulings that were issued after your R1 dispatch.

---

## MUST FIX — Critical Bugs

### Fix 1: Path Budget Off-by-One (CRITICAL — Systemic)

ALL milestones are exactly 1 step short:

| Target | Expected | Your Actual |
|--------|----------|-------------|
| Advancement (sw_adv_*) | 10 | 9 |
| Lv15 (_qual) | 15 | 14 |
| Lv20 (_qual) | 20 | 19 |

**Root cause**: The shared zone critical path from `sw_start` to advancement has only 9 edges instead of 10. This means there is a missing node or a shortcut edge somewhere in the sw_* zone.

**Fix**: Audit the shared zone (sw_start → sw_adv_*). The correct convention is: BFS distance from sw_start = level number. So advancement nodes must be exactly 10 edges from sw_start. Add 1 node to the critical path, or remove a shortcut edge that is bypassing a node. Do NOT just pad a dummy node — make the added node meaningful.

**Reference**: Codex's version achieves exact anchors (Lv10=10, Lv15=15, Lv20=20). Compare your shared zone structure against the original JSON topology to find where the edge was lost.

### Fix 2: cm_M11 `requires` Field Contradicts Edge Sources

- `requires`: `sw_adv_saint|sw_adv_magic`
- Actual incoming edges: from `ss_B11` and `sc_A11`

These are different nodes. The `requires` field determines the game logic prerequisite; the edges determine the graph topology. They must be consistent.

**Fix**: Either:
- Change `requires` to `ss_B11|sc_A11` (matching actual edges), OR
- Change the edges so that `sw_adv_saint` and `sw_adv_magic` have direct edges to `cm_M11`

The first option is more consistent with the other agents' implementations where cm_M11 is reached from Lv11 post-advancement nodes.

---

## MUST FIX — New Design Rulings

### Fix 3: Silver Rose Must Become an Intermittent Traversable Bridge

**Current state**: Your cm_* nodes form a linear chain (cm_M11 → cm_M13 → cm_M16 → cm_M20) with NO lateral/cross-path edges. The bridge is a vertical dead-end spur — a player entering Silver Rose cannot reach the opposite advancement path.

**New ruling**: Silver Rose must enable **cross-path traversal** at mid-levels:

1. **cm_M13** (Lv 13): Add outgoing edges to BOTH `ss_B14` AND `sc_A14` (or equivalent inner-track Lv14 nodes on both sides). This lets a Blade Master player cross to pick up a Sword Cultivator Lv14 node, and vice versa.

2. **cm_M16** (Lv 16): Add outgoing edges to BOTH sides' inner-track nodes at Lv 17-18.

3. **cm_M11**: Can remain a dead end (entry hook, bridge tax).

4. **cm_M20**: MUST remain a dead end. No cross-path access near terminals.

5. **Keep OR prerequisites on entry**: cm_M13 should require nodes from BOTH sides (e.g., `ss_B12|sc_A12`), not chain from cm_M11. Each bridge node is independently enterable from either side.

6. **Detour cost**: The bridge should cost 1-2 extra levels vs staying on your own path. A BM player crossing to SC Lv14 via cm_M13 should arrive at effective Lv 14-15, not Lv 13.

Key principle: **mid-tree cross-pollination (Lv 13-17) = yes; late-tree cherry-picking (Lv 18-20) = no.**

### Fix 4: Add 1-2 Reaction Action Skills

**Current state**: Zero reaction_action nodes in the entire tree.

**New ruling**: Add **1-2 reaction_action** active skill nodes:

- **Blade Master** (required, 1 node): A counter-attack or parry reaction fitting the fast-blade identity. E.g., when attacked, spend reaction to deal reduced damage + generate Sword Intent. Place around Lv 12-17.

- **Sword Cultivator** (optional, 0-1 node): A flying sword interception or formation shield reaction. E.g., when an ally in formation range is attacked, reaction to reduce damage.

Constraints:
- Must have `action_cost: "reaction"` field
- Must be `type: "active_skill"`
- Total across whole tree: 1-2 maximum

---

## SHOULD FIX — Audit Findings

### Fix 5: `sw_adv_magic` Naming

The advancement node for Sword Cultivator is still named `sw_adv_magic`. Other agents use `sw_adv_cultivator` or `sw_adv_sword_immortal`. Rename to be consistent with the 剑仙 terminology overhaul.

### Fix 6: Inner-Outer Layout in Deep Dive

- `detour_ss_22` and `detour_sc_22` have `gauge` tags but sit at |x|=250 (should be ≥300 for outer track)
- `ss_A23`-`ss_A25_ult` and `sc_B23`-`sc_B25_ult` are on outer tracks (|x|=400) but lack `gauge` tags

**Fix options**:
- Move gauge-tagged detours to |x|=300+, OR remove gauge tags from detours
- Add gauge tags to outer-track Lv23-25 nodes that are path-exclusive to a specific gauge line

### Fix 7: Active Skill Diversity

Currently 8 of 9 active skills are `standard` action. Only 1 `swift`. No `move`, no `reaction`.

After adding reaction nodes per Fix 4, also consider converting 1 existing standard skill to `move` (e.g., a repositioning/dash skill on one of the advancement paths).

---

## Deliverables

1. Revised `data/talent-tree/sw_matrix_true_path.json` in your worktree (`D:\ShipOfTheseus\sw-opt-opencode`)
2. Updated rationale documenting all Round 2 changes
3. Commit to `opencode/sw-talent-optimize` with message: `design(P2-TALENT): round-2 fixes per main agent audit`

## Quality Checklist (Round 2)

- [ ] Path budget fixed: sw_adv_* at BFS distance = 10, Lv15 = 15, Lv20 = 20
- [ ] cm_M11 requires field matches actual incoming edges
- [ ] Silver Rose cm_M13 and cm_M16 have outgoing edges to BOTH sides (cross-path traversal)
- [ ] Silver Rose does NOT enable cross-path access beyond Lv ~17
- [ ] 1-2 reaction_action nodes exist with `action_cost: "reaction"`
- [ ] `sw_adv_magic` renamed to `sw_adv_cultivator` or equivalent
- [ ] Deep dive inner-outer layout improved (gauge tags on outer, universal on inner)
- [ ] JSON validates, no orphan nodes, no duplicate IDs
- [ ] All changes documented in rationale

---

*Generated: 2026-03-15 | Main Agent audit feedback | Target: opencode*
