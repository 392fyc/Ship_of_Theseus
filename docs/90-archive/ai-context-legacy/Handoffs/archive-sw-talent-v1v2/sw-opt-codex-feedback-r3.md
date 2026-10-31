# Swordsman Talent Tree v1 — Codex CLI Feedback (Round 3 — Minor Polish)

> Source: Main Agent parallel audit of R2 commit `fed1076` on `codex/sw-talent-optimize`
> Date: 2026-03-15 | Priority: LOW — polish items only, no blockers

---

## R2 Verdict: PASS — Merge Candidate

Your R2 submission is the **strongest of three parallel versions**. All critical checks pass:
- ✅ Path anchors: Lv10=10, Lv15=15, Lv20=20 (exact)
- ✅ Silver Rose: cm_M13 + cm_M16 traversable, cm_M20 dead end
- ✅ Reaction: 2 nodes (ss_A17 + sc_M16)
- ✅ All R2 fixes verified (sw_M2, detour_center_22, ss_B20_qual, convergence nodes)
- ✅ No terminology residue, no coordinate collisions, no orphans

**This version is the current merge candidate.** The following are polish items — address if time permits, otherwise document for future pass.

---

## NICE TO HAVE — Polish Items

### Item 1: Deep Dive Outer-Track Gauge Tags

Outer-track nodes at Lv23-25 (`ss_A23`, `ss_A24`, `ss_A25_ult`, `sc_B23`, `sc_B24`, `sc_B25_ult`) are path-exclusive to a gauge line but lack explicit `gauge`/`sword_intent`/`sword_essence` tags. Adding these would improve automated validation and make the inner-outer layout rule machine-verifiable.

### Item 2: Bridge Dijkstra Artifact Documentation

The rationale doc already notes that bridge edges create exclusive-ignorant Dijkstra shortcuts (ss_B20_qual=19, sc_A20_qual=19 instead of 20). Consider adding a one-liner to the JSON file header or a separate `KNOWN_ISSUES.md` noting that the talent-tree-editor's shortest path calculation does not account for `exclusive` mutual exclusion, so displayed paths at Lv19-20 may show 1 level lower than actual gameplay.

### Item 3: cm_M11 Dead End vs Entry Hook

cm_M11 is the only bridge node with zero outgoing edges. If this is intentional (bridge tax / stat pickup), add a `"notes"` field explaining why. If it was meant to chain to cm_M13, add the edge.

### Item 4: Blade Master A-Line Early Gauge Income

A-line has only one dedicated Sword Intent generation node (`ss_A18`) at Lv 18. A pure A-line build path is 8 levels (Lv 10-18) with no gauge generation beyond the base advancement passive. Consider whether an earlier generation source around Lv 13-15 would improve A-line playability. This is a balance consideration, not a structural bug.

---

## No Re-Commit Needed

Unless you choose to address Items 1-4, no additional commit is required. Your R2 is accepted as-is for merge consideration.

---

*Generated: 2026-03-15 | Main Agent audit feedback | Target: Codex CLI*
