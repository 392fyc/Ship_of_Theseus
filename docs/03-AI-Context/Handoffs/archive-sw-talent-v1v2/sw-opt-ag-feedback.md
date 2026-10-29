# Swordsman Talent Tree v1 — AntiGravity Feedback (Round 2)

> Source: Main Agent parallel audit of `antigravity/sw-talent-optimize`
> Date: 2026-03-15 | Priority: apply all changes, re-commit to same branch

---

## Audit Summary

Your submission passed 4/6 dimensions with good rhythm and full deep-dive compliance. However, **Action Economy failed** (3 missing fields, 3 mislabeled types, 1 path over budget). Several targeted fixes are needed before this version is merge-eligible.

---

## MUST FIX — Critical Bugs

### Fix 1: Three Nodes Missing `action_cost` Field

These `active_skill` nodes have no `action_cost`:

| Node ID | Name | Expected Fix |
|---------|------|-------------|
| `sc_A11` | 飞剑缠绕 | **Retype to `passive`** — desc says "攻击被减速或定身的敌人时，伤害+15%", this is a conditional damage passive, NOT an active skill |
| `sc_B14` | 阵地充能 | **Retype to `passive`** (or `gauge_extend`) — desc says "位于自己剑阵中时，每回合额外恢复10点剑元", this is a passive regen effect |
| `sc_A16` | 回旋剑影 | **Retype to `passive`** — desc says "攻击命中后，50%概率拉扯敌人", this is a proc-on-hit passive |

All three should become `type: "passive"`. Remove from the active skill count.

### Fix 2: Sword Cultivator B-Line Has 4 Standard Actions (EXCEEDS LIMIT)

After fixing the mislabels above, the SC B-line still has: `sc_B12` (standard) + `sc_B15_qual` (standard) + `sc_B20_qual` (standard) + `sc_B25_ult` (standard) = **4 standard_action**.

Rule: max 3 standard_action skills per single build path.

**Fix options** (pick one):
- Make `sc_B12` (剑阵-陷) a `swift` action — deploying a basic trap formation is fast
- Make `sc_B15_qual` (剑阵-戮) a `skill_upgrade` of `sc_B12` instead of a separate active skill — the "upgrade" replaces the base, so they share the skill slot
- Remove one standard_action from the B-line entirely

### Fix 3: Coordinate Collision `sc_A12` / `sc_M12`

Both nodes have coordinates (x=200, y=920). They will overlap in the visual editor.

**Fix**: Move `sc_M12` to x=300 or another distinct position.

---

## MUST FIX — Design Ruling Changes

### Fix 4: Silver Rose Must Become an Intermittent Traversable Bridge

**Current state**: `cm_M11`, `cm_M13`, `cm_M16`, `cm_M20` are all dead-end nodes (out_degree=0). They function as side reward detours, not actual bridges.

**New ruling**: Silver Rose must be a **traversable path** with these constraints:

1. **Intermittent connectivity**: Some bridge nodes have outgoing edges to the opposite side's inner track. The bridge is NOT a complete parallel path — it has gaps and is shorter than main advancement paths.

2. **Shorter than main paths**: The traversable portion of Silver Rose should cover roughly Lv 11-16 (partial range), NOT extend to Lv 20. Players near terminal nodes (Lv 18-20) must NOT be able to hop across via bridge to cherry-pick the other side's powerful late nodes.

3. **Detour cost**: Crossing via Silver Rose costs 1-2 extra levels compared to staying on your own path. A Blade Master crossing to grab a SC Lv 13 node arrives at effective Lv 14-15.

4. **Keep OR prerequisites on entry**: Entry uses `|` (OR). But outgoing edges from bridge nodes connect to the opposite side at a HIGHER level.

**Implementation sketch**:
- `cm_M11`: entry node, dead end is OK (hook/introduction)
- `cm_M13`: **traversable** — add outgoing edges to `ss_B14` AND `sc_A14` (or equivalent inner-track nodes, one level deeper than same-side access)
- `cm_M16`: **traversable** — add outgoing edges to opposite inner track at Lv 17-18
- `cm_M20`: keep as dead end (too close to terminals, cross-path access forbidden here)

Key principle: **mid-tree cross-pollination (Lv 13-17) = yes; late-tree cherry-picking (Lv 18-20) = no.**

### Fix 5: Add 1-2 Reaction Action Skills

**Current state**: Zero `reaction_action` skills in the entire tree.

**New ruling**: Add **1-2 reaction_action** nodes:

- **Blade Master** (recommended): A counter/parry reaction fitting the fast-blade identity. E.g., "Blade Flash Counter" — when attacked, spend reaction to deal reduced damage + generate Sword Intent.
- **Sword Cultivator** (optional, max 1): A flying sword interception or formation shield reaction. E.g., "Sword Screen" — reaction to protect ally in formation range.

Constraints:
- Total: 1-2 nodes maximum across the whole tree
- Must have `action_cost: "reaction"` field
- Must be genuine active choices, not passive procs

---

## SHOULD FIX — Audit Findings

### Fix 6: Sword Essence A-Line Gauge Starvation

The SC A-line (flying sword) has **no dedicated gauge generation** nodes. All generation is on B-line (`sc_B14` in-formation regen) or shared (`sc_M16` cap increase). A pure A-line player at Lv 20 faces `sc_A20_qual` costing 100 Essence with only natural regen as income.

**Suggestion**: Add at least one A-line Essence generation node around Lv 13-15. E.g., "飞剑击杀回收" — flying sword kill returns partial Essence cost.

### Fix 7: `sw_R6` (魔力感知) — Very Weak

M.DEF+3 at Lv 6 is the weakest node at this tier by a wide margin compared to `sw_L6` (+15% damage on debuffed target) and `sw_M6` (+1 initiative on counter). It's a stepping stone to `sw_R7` but feels like filler.

**Suggestion**: Upgrade to a more meaningful effect that fits the magical awareness theme. E.g., "first hit each combat reveals enemy resistances" or "M.DEF+3 and magic damage taken reveals attacker for 1 turn."

### Fix 8: `sc_B13` (剑阵延展) — Hyper-Narrow

"+1 turn duration" is only relevant for formation builds. A mixed or A-line player passing through here gets nothing.

**Suggestion**: Broaden to include a secondary universal benefit. E.g., "+1 turn duration for formations; OR +5% damage to slowed enemies" (useful even without formations).

---

## Deliverables

1. Revised `data/talent-tree/sw_matrix_true_path.json` in your worktree (`D:\ShipOfTheseus\sw-opt-ag`)
2. Updated design rationale documenting all Round 2 changes
3. Commit to `antigravity/sw-talent-optimize` with message: `design(P2-TALENT): round-2 fixes per main agent audit`

## Quality Checklist (Round 2)

- [ ] `sc_A11`, `sc_B14`, `sc_A16` retyped to `passive` (not `active_skill`)
- [ ] SC B-line has ≤3 standard_action skills
- [ ] `sc_A12` / `sc_M12` coordinate collision fixed
- [ ] Silver Rose has at least 2 traversable bridge nodes with outgoing edges to opposite side
- [ ] Silver Rose does NOT enable cross-path access beyond Lv ~17
- [ ] 1-2 reaction_action nodes exist with proper `action_cost: "reaction"` field
- [ ] SC A-line has at least one gauge generation node
- [ ] JSON validates, no orphan nodes, no duplicate IDs, no coordinate collisions
- [ ] All changes documented in rationale

---

*Generated: 2026-03-15 | Main Agent audit feedback | Target: AntiGravity*
