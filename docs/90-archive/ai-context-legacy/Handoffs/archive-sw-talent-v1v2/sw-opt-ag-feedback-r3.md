# Swordsman Talent Tree v1 — AntiGravity Feedback (Round 3)

> Source: Main Agent parallel audit of R2 submission on `antigravity/sw-talent-optimize`
> Date: 2026-03-15 | Priority: CRITICAL fix required before merge consideration

---

## R2 Verdict: 6/7 R2 fixes applied correctly. 1 CRITICAL systemic bug remains.

Your R2 fixes were well-executed: type corrections, coordinate collision, ss_M12 reaction, sc_A16 gauge regen, sw_R6/sc_B13 improvements — all verified. However, a **critical path budget bug** was NOT addressed in R2 and must be fixed now.

---

## MUST FIX — CRITICAL

### Fix 1: Path Budget Off-by-One (Systemic)

ALL milestones are exactly 1 step short of their expected level anchor:

| Target | Expected | Your Actual |
|--------|----------|-------------|
| sw_adv_saint | 10 | **9** |
| sw_adv_sword_immortal | 10 | **9** |
| Lv15 _qual nodes | 15 | **14** |
| Lv20 _qual nodes | 20 | **19** |

This is not a convention issue — the Codex version achieves exact anchors (Lv10=10, Lv15=15) with the same counting method (BFS edges from sw_start).

**Root cause**: Your shared zone (sw_start → advancement) has only 9 edges on the critical path instead of 10. Somewhere a node was bypassed or an edge was added that creates a shortcut.

**How to fix**:
1. Trace the shortest path from `sw_start` to `sw_adv_saint` — list every node on the path
2. Compare against the original JSON or Codex's shared zone structure
3. Identify the missing hop — either add a node to the critical path or remove a shortcut edge
4. Verify: after fix, BFS(sw_start → sw_adv_saint) must equal exactly 10

**Do NOT just insert a dummy filler node.** If a node was accidentally removed or an edge was accidentally added, restore the correct topology.

---

## SHOULD FIX

### Fix 2: Deep Dive Inner-Outer Layout (4 Violations)

| Node | Issue |
|------|-------|
| `detour_ss_22` | has `gauge` tag but |x|=200 (should be ≥300 for outer track) |
| `detour_sc_22` | has `gauge` tag but |x|=200 (should be ≥300 for outer track) |
| `ss_A23` | no `gauge` tag but |x|=400 (outer track reserved for gauge-specific) |
| `sc_B23` | no `gauge` tag but |x|=400 (outer track reserved for gauge-specific) |

**Fix**: Move gauge-tagged detours to |x|≥300, OR add gauge tags to outer-track Lv23+ nodes.

### Fix 3: Consider Adding a Second Reaction Node

You currently have 1 reaction node (`ss_M12` 闪刃反击). The ruling allows up to 2. Consider adding 1 more on the Sword Cultivator side — e.g., a flying sword interception reaction around Lv 15-17. This is optional but would improve action type diversity.

### Fix 4: `sword_immortal` vs `sword_cultivator` Tag Inconsistency

Deep dive sc_* nodes use `sword_immortal` tag while Lv11-20 sc_* nodes use `sword_cultivator`. If this is intentional lore progression (cultivator → immortal at deep dive), document it. If not, unify.

---

## Deliverables

1. Revised `data/talent-tree/sw_matrix_true_path.json`
2. Commit to `antigravity/sw-talent-optimize` with message: `design(P2-TALENT): round-3 fix path budget off-by-one`

## Quality Checklist (Round 3)

- [ ] BFS(sw_start → sw_adv_saint) = exactly 10
- [ ] BFS(sw_start → sw_adv_sword_immortal) = exactly 10
- [ ] BFS(sw_start → any Lv15 _qual) = exactly 15
- [ ] BFS(sw_start → any Lv20 _qual) = exactly 20
- [ ] Deep dive inner-outer layout fixed (or documented as intentional)
- [ ] JSON validates, no orphan nodes

---

*Generated: 2026-03-15 | Main Agent audit feedback | Target: AntiGravity*
