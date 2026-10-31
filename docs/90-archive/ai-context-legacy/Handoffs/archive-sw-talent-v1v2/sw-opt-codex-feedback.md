# Swordsman Talent Tree v1 — Codex CLI Feedback (Round 2)

> Source: Main Agent parallel audit of commit `bfb74e9` on `codex/sw-talent-optimize`
> Date: 2026-03-15 | Priority: apply all changes, re-commit to same branch

---

## Audit Summary

Your submission passed 5/6 dimensions. Overall quality is high — well-structured gauge loops, full deep-dive compliance, clean action_cost coverage. The following are targeted fixes, not a full redo.

---

## MUST FIX — Design Ruling Changes

### Fix 1: Silver Rose Must Become an Intermittent Traversable Bridge

**Current state**: `cm_M11`, `cm_M13`, `cm_M16`, `cm_M20` are all dead-end nodes (out_degree=0). They are side rewards, not actual bridges — a player cannot traverse from Blade Master side to Sword Cultivator side via Silver Rose.

**New ruling**: Silver Rose must be a **traversable path** with these constraints:

1. **Intermittent connectivity**: Bridge nodes connect to BOTH sides, but not at every level. Some bridge nodes are entry-only (dead end), others have outgoing edges to the opposite side. The bridge should NOT form a complete parallel path — it is shorter and has gaps.

2. **Shorter than main paths**: The Silver Rose chain should cover roughly Lv 11-16 (or similar partial range), NOT extend all the way to Lv 20. Players near terminal nodes (Lv 18-20) should NOT be able to hop across via bridge to cherry-pick the other side's powerful nodes.

3. **Detour cost for cross-path access**: Crossing via Silver Rose must cost 1-2 extra levels compared to staying on your own path. A Blade Master player who crosses to pick up a Sword Cultivator Lv 13 node should arrive at it at effective Lv 14-15, not Lv 13.

4. **Keep OR prerequisites on entry**: Entry to Silver Rose still uses `|` (OR) — accessible from either side. But outgoing edges from bridge nodes should connect to the opposite side's inner track at a HIGHER level than same-side equivalent.

**Implementation sketch** (adapt as needed):
- `cm_M11`: entry bridge (keep as-is, dead end is fine for the hook)
- `cm_M13`: traversable — add outgoing edge to `ss_B14` AND `sc_A14` (or equivalent inner-track nodes one level deeper)
- `cm_M16`: traversable — add outgoing edge to opposite inner track at Lv 17-18
- `cm_M20`: keep as dead end (too close to terminals, should NOT enable cross-path)

The key principle: **the bridge enables mid-tree cross-pollination (Lv 13-17) but NOT late-tree cherry-picking (Lv 18-20).**

### Fix 2: Add 1-2 Reaction Action Skills

**Current state**: The entire tree has zero `reaction_action` skills. Action type diversity is skewed (10 standard, 2 swift, 2 move, 0 reaction).

**New ruling**: Add **1-2 reaction_action** active skill nodes. Recommendations:

- **Blade Master path**: A counter-attack enhancement or parry skill fits the fast-blade identity. Consider converting an existing passive (e.g., one of the Lv 17-18 nodes) or adding a new node. Candidate: a "Blade Flash Counter" reaction that triggers on being attacked, dealing reduced damage but generating Sword Intent.

- **Sword Cultivator path** (optional, max 1): A flying sword interception or formation reaction. E.g., "Sword Screen" — when an ally in formation range is attacked, reaction to reduce damage.

Constraints:
- Total reaction_action across the whole tree: **1-2 nodes maximum**
- Must have `action_cost: "reaction"` field
- Should feel distinct from passive procs — the player actively chooses to use their reaction

---

## SHOULD FIX — Audit Findings

### Fix 3: Lv 18-20 Rhythm Flatness

The Lv 18-19-20 segment on both factions runs as purely isolated parallel lines with zero convergence. Three straight levels breaks the star-burst rhythm.

**Suggestion**: Add at least one M-line convergence or interaction point between Lv 18-19. This could be a shared requirement for one of the Lv 20 terminal nodes, or a new M-line node at Lv 19 that requires both A18+B18.

### Fix 4: `sw_M2` (敏锐) — Weakest Yet Most Mandatory

`sw_M2` is required by 3+ downstream nodes but has the weakest effect of the three Lv 2 options ("first to act: +8% crit rate" — conditional and unreliable).

**Suggestion**: Strengthen the effect to match its structural importance. E.g., "+8% crit rate on first attack each combat" (remove the speed condition) or change to a more universally useful effect.

### Fix 5: `detour_center_22` (破极之躯) Risk/Reward

"+20% phys/mag DEF but cannot be healed externally" is extremely punishing in a team-based tactical RPG. The no-healing drawback may make this node a trap rather than a meaningful trade-off.

**Suggestion**: Soften to "external healing effectiveness -50%" instead of complete removal, or add a self-sustain component (e.g., lifesteal on hit).

---

## NICE TO HAVE

### Fix 6: `ss_B20_qual` Type Inconsistency

`ss_B20_qual` (極意·修羅一閃) is typed as `trait` but modifies an active skill (expanding 剣意释放 to fan-shaped AoE). Other Lv 20 terminals are `active_skill`. Consider aligning the type.

### Fix 7: Blade Master A-Line Late Gauge Generation

The A-line (dual-blade speed) has only one Sword Intent generation node (`ss_A18` at Lv 18). A pure A-line build has 8 levels (Lv 10-18) with no dedicated gauge income beyond base `sw_adv_saint` passive generation. Consider adding an earlier A-line generation source around Lv 13-15.

---

## Deliverables

1. Revised `data/talent-tree/sw_matrix_true_path.json` in your worktree
2. Updated rationale documenting all Round 2 changes
3. Commit to `codex/sw-talent-optimize` with message: `design(P2-TALENT): round-2 fixes per main agent audit`

## Quality Checklist (Round 2)

- [ ] Silver Rose has at least 2 traversable bridge nodes with outgoing edges to opposite side
- [ ] Silver Rose does NOT enable cross-path access beyond Lv ~17
- [ ] 1-2 reaction_action nodes exist with proper `action_cost: "reaction"` field
- [ ] Lv 18-20 has at least one convergence/interaction point
- [ ] `sw_M2` effect strengthened or reworked
- [ ] JSON validates, no orphan nodes, no duplicate IDs
- [ ] All changes documented in rationale

---

*Generated: 2026-03-15 | Main Agent audit feedback | Target: Codex CLI*
