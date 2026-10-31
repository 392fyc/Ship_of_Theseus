---
session: S2-side-sot
date: 2026-05-10
status: validation_complete
purpose: Mage talent tree direction (3-element-exclusion + trapezoid topology) sanity check before phase 2 (faction designs + JSON expansion)
chain: game-researcher (haiku) → game-analyst (sonnet) → game-critic (sonnet) — Mercury core agents A→B→C dogfood in cross-repo lane
direction_under_review: 03-AI-Context/Handoffs/mage-talent-tree-design-brief.md (2026-03-14, PRE-S67)
sources_of_truth:
  - 01-Game-Design/game-design-doc.md
  - 01-Game-Design/Characters/class-system.md
  - 01-Game-Design/Characters/talent-tree-design.md
  - data/talent-tree/mg_pentagram.json (existing 48-node skeleton, found via Grep)
  - 05-Research/sot-viability-2026-04-22/S67-FINAL-SYNTHESIS.md
verdict_summary: "Direction VIABLE, but 4 hard issues block phase 2 ship. SP-1 fix-now (JSON cycle bug), SP-2 guard (Sorlock risk), SP-3 promote (runtime missing P0), SP-4 demote (single-id polymorphic skill)."
---

# Mage Talent Tree Validation Synthesis

> **Verdict**: Direction (3-element-exclusion + trapezoid + dual advancement) is **viable** as a Mage class identity vehicle, **conditional on** addressing 4 explicit issues before phase 2 ship.
>
> Run via Mercury `game-researcher` → `game-analyst` → `game-critic` chain in S2-side-sot, 2026-05-10. Total runtime ~10min wall. 30+ external sources cited. Analyst Grep'd actual SoT codebase and surfaced **two findings the original brief did not anticipate**.

---

## TL;DR Decision Tree

```
Phase 2 (faction designs + gauge specs + full JSON) ship gate
├── SP-1 mg_*_19 cycle bug         → blocker (fix-now, JSON-level, ~30 min)
├── SP-3 talent runtime missing    → blocker (promote to P0, cross-class)
├── SP-2 Grand Sage Sorlock risk   → guard (design constraint before phase 2)
└── SP-4 mg_ult_element polymorph  → demote (split to 3 nodes, simpler)

CCR-1 JSON-only without inspector  → infra debt, surfaces in all 5 v1 classes
CCR-2 互斥 + Lv10 + roguelite run  → UX risk, validate via prototype
```

---

## Ship Direction (held vs revised)

### Held from 2026-03-14 brief

- ✅ **Trapezoid topology** (3 origin → 2 advancement → post-advancement pool) — researcher confirms no exact precedent (genre gap), analyst confirms `mg_pentagram.json` already implements 48-node skeleton with reasonable hub fan-out (post `mg_sh_3_hub` weakness flagged)
- ✅ **3-element exclusion** as origin mechanic — aligns with S67 pillar C "differentiated talent tree architecture"
- ✅ **Class Advancement Lv10 不可逆 per-run** — consistent with class-system.md global rule, roguelite run-reset absorbs commitment cost
- ✅ **Single-element 节点禁作 hub** constraint — analyst confirms current JSON mostly compliant; minor weakness at `mg_sh_3_hub` (out-edge=2)

### Revised from brief (critic's three-tier)

- 🔴 **SP-4 demote**: `mg_ult_element` "自动根据起源转换技能形式 (末日流星/绝对零度/风神之眼)" — split to 3 independent nodes `mg_ult_fire` / `mg_ult_ice` / `mg_ult_air`, each unlocked by Element Sage's respective origin path. Eliminates DataLoader polymorphic-skill refactor + tooltip ambiguity
- 🟡 **SP-2 guard**: Grand Sage path needs **explicit design constraint** to prevent Sorlock-equivalent dominant build. Candidate constraints:
  - Lock out at least one Element Sage exclusive terminal
  - Fusion gauge with high upkeep cost (3-element triggers consume 1 of each gauge fully)
  - Cap on gauge access (Grand Sage uses fusion-only gauge, no per-element gauge access)
- 🟢 **SP-1 fix-now**: Replace circular `mg_f_19/mg_i_19/mg_a_19` requires with standard convergence node pattern: `mg_trial_convergence` requires `mg_f_18, mg_i_18, mg_a_18`, then `mg_*_19` requires `mg_trial_convergence`. JSON-level fix, ~30 min
- 🔼 **SP-3 promote to P0**: Talent runtime is **shared infrastructure across 5 v1 classes** (8 v2 roadmap). Must ship before any class talent tree is testable. Minimal v1: passive/trait/active node activation + exclusive_group namespace + no gauge condition effects yet (P2)

### Reordered phase-2 task graph

```
Original brief phase 2 plan:
  AntiGravity drafts faction designs + gauge specs → human review → JSON → editor validate → approve

Revised post-validation phase 2 plan:
  P0 (cross-class): talent runtime MVP
       └── DataLoader.gd: var talent_trees: Dictionary
       └── Unit.gd: skill_unlocks_set + exclusive_groups: Dictionary
       └── basic node activation (no gauge condition effects)
       └── exclusive_group namespace = "<class_id>:<group>" prefix
  P0 (Mage-specific):
       └── fix mg_*_19 circular dependency (convergence node pattern)
       └── split mg_ult_element to mg_ult_fire/ice/air (3 nodes)
       └── design Grand Sage hard constraint (fusion gauge cost OR locked-out exclusive terminal)
  P1 (Mage-specific):
       └── faction designs (Fire / Ice / Air Element Sage + Grand Sage) post-advancement details
       └── gauge specs (Hellfire / Frost / Gale; fusion gauge if Grand Sage path takes that route)
       └── JSON full skeleton expansion
       └── onboarding UI: origin choice + endgame preview
  P2 (later):
       └── gauge condition effects (>60 threshold modifiers etc.)
       └── damage_calculator.gd element tag hook
```

---

## Hard Findings (analyst Grep evidence)

These were not anticipated by the 2026-03-14 brief. Analyst surfaced them by Grepping actual SoT code:

### 1. `mg_pentagram.json` already exists (48 nodes, 66 edges)

- Path: `D:/ShipOfTheseus/Ship_of_Theseus/data/talent-tree/mg_pentagram.json`
- Implements: origin (3) + L2 element (3) + shared mid (14) + advancement (2) + post-adv ring (8) + hub (2) + gauge_core/extend (6) + ultimate prep + ultimate (6) = 48 total
- Status: **structure complete, numeric values pending**, **circular dependency bug** in mg_f_19 / mg_i_19 / mg_a_19 requires fields
- This is the largest of the 5 v1-class talent trees (Swordsman `sw_a.json` is ~30% smaller)

### 2. Talent runtime is completely absent

Grep `talent` across all `.gd` files: **zero hits**. Specifically:
- `data_loader.gd` loads `data/talent-tree/` directory but **no `talent_trees: Dictionary` declaration** (relics + buildings have target dicts; talent does not)
- `unit.gd` has `skill_ids: Array[String]` but no `exclusive_group` / `gauge` / `talent_unlocks` fields
- `game_action.gd` has no element tag awareness
- `damage_calculator.gd` has no element tag hook

**Implication**: All 5 v1-class talent tree JSONs (`mg_*`, `sw_*`, etc.) are pure design documents. The class-system v1 milestone delivery requires building this runtime first; Mage-specific work is downstream of it.

### 3. mg_*_19 circular dependency

```json
"mg_f_19": { "requires": "mg_f_18, mg_i_19" }    // needs Ice 19
"mg_i_19": { "requires": "mg_i_18, mg_f_19, mg_a_19" }  // needs Fire 19, Air 19
"mg_a_19": { "requires": "mg_a_18, mg_i_19, mg_g_19" }  // needs Ice 19
```

DAG topological sort fails. Standard BFS/DFS resolution would loop infinitely or hit cycle assertion. Critic backed this with [Game Developer dependency-graph article](https://www.gamedeveloper.com/programming/dependency-graphs-in-games) confirming it as standard fail mode.

**Standard fix pattern** (per [Tutsplus talent tree primer](https://gamedevelopment.tutsplus.com/articles/lets-spec-into-talent-trees-a-primer-for-game-designers--gamedev-6691)): introduce `mg_trial_convergence` node that requires `mg_f_18, mg_i_18, mg_a_18`; `mg_*_19` then each require `mg_trial_convergence` only. This expresses the AND-gate intent (need to learn all 3 elements before deep magic) without requiring nodes to reference each other.

---

## Soft Findings

### Genre precedent gap (researcher Q2)

Trapezoid (3-entry → 2-middle → large-pool) topology has **no clear named precedent** in talent/skill tree literature. Closest analogies:
- FFX Sphere Grid (grid + key sphere gates, but multi-source/sink not 3→2 funnel)
- FE3H promotion tree (multi-source/multi-sink branch tree, not funnel)
- FF Tactics job system (slot-based active job, not exclusive lock)

**Implication**: SoT Mage trapezoid is either genuine novelty (positive: differentiation per S67 pillar C) or hidden risk (negative: untested pattern). Given Class Advancement is 1→2 elsewhere in SoT, the 3→2 funnel is Mage-unique within SoT itself, which is consistent with per-class topology principle.

### Octopath v1 → v2 reversal warning (researcher Q1, critic CCR-2)

Octopath Traveler v1 had global sub-job exclusivity. The sequel (Octopath 2) **explicitly removed it** — published evidence of designer reversal. The cause cited: new-player confusion + repetition fatigue across multiple playthroughs.

**SoT mitigation candidates**:
- Origin choice UI must show endgame preview (which terminal magic each origin leads to)
- NG+ or meta horizontal unlock should grant "have already seen all 3 origins" reduction in confusion
- Roguelite run-reset is structurally similar to Slay the Spire's "low single-run investment" mitigation that researcher cites — SoT 30-stage run is medium-length, not low-investment

### BG3 Sorlock risk (researcher Q4, critic SP-2 evidence)

BG3 Sorlock multiclass is documented as "epitome of highest-tier spellcasting" by multiple guide sites. The mechanism: dual resource pool (Spell Slots + Warlock Pact slots) with no exclusivity cost. SoT Grand Sage similarly accesses 3 elements + 3 gauges with no obvious cost — **without explicit constraint, Element Sage becomes strictly inferior choice**.

**Counter-precedent**: Pillars of Eternity 2 multiclass locks out top-tier (Power Level 8/9) abilities, preserving single-class identity. This is the design pattern SP-2 guard would adopt for SoT.

---

## Confidence

| Layer | Confidence | Notes |
|-------|------------|-------|
| Researcher findings (genre precedents) | 4/5 | 30+ URLs across 9+ games, BG3/PoE2/FFT/FE3H/Octopath all cited |
| Analyst Grep evidence (codebase facts) | 5/5 | Direct SoT codebase Grep, mg_pentagram.json verified |
| Analyst 4-axis evaluation | 3/5 | LOC estimates ±40% (talent runtime absent baseline); coupling analysis 4/5 |
| Critic fail-mode evidence (URLs) | 4/5 | 17 sources, BG3/ESO/PoE2/Banner Saga 2 postmortems cited |
| Three-tier classification | 4/5 | SP-1 + SP-3 unambiguous; SP-2 + SP-4 design judgement, prototype recommended |
| Adoption Order recommendation | 3/5 | Depends on solo-dev time budget unknown to chain |

**Strongest evidence**: SP-1 cycle bug (data, not opinion); SP-3 runtime absence (Grep, not assertion).

**Weakest evidence**: Q-A4 (run-local exclusion vs meta-level unlock interaction) — meta layer entirely absent from current SoT codebase, so chain could not validate the brief's claim that "meta horizontal unlock 补偿 single-run 不可逆 cost".

---

## What This Validation Did NOT Cover

- **数值平衡** (HP/MAG/AC/SPD per element / per advancement): out of scope for direction validation; needs prototype + playtesting
- **Faction details** (Grand Sage / Element Sage post-advancement skill list): brief requested these as phase 2 deliverable; this validation was sanity check before phase 2 starts
- **Other 7 classes' interaction**: critic CCR-1 noted "5 classes均无可测试状态" but did not validate per-class designs
- **Multiplayer stability** (R2 4p 等待时长): S67-FINAL R2 risk; not Mage-specific
- **Save/load integration**: talent unlocks persistence across runs — meta layer absent

---

## Decision Points for User

User confirmation required before phase 2 starts:

1. **SP-2 Grand Sage hard constraint pick** (which design constraint locks out Sorlock-equivalent dominance):
   - (a) Locked-out Element Sage exclusive terminal (Grand Sage cannot reach `mg_ult_fire/ice/air`, must take fusion-only path)
   - (b) Fusion gauge with high upkeep (3-element trigger fully drains all 3 gauges)
   - (c) Gauge access cap (Grand Sage uses fusion-only gauge, no per-element gauge access)
   - (d) Explicit choice deferred to phase 2 prototype

2. **SP-4 mg_ult_element pick**:
   - Confirm split to `mg_ult_fire` / `mg_ult_ice` / `mg_ult_air` (3 independent nodes)?
   - Or keep "auto-transform" with DataLoader polymorphic-skill refactor (higher cost, ESO tooltip risk)?

3. **SP-3 talent runtime priority**:
   - Confirm "promote to P0 cross-class shared infrastructure"?
   - Or accept Mage-specific runtime first (delays the other 4 v1 classes)?

4. **Phase 2 dispatcher**:
   - AntiGravity (Gemini 3.1 Pro) — original assignee, weekly-refresh limit per memory
   - Claude Code Main Agent — substitute per memory escalation rule
   - Codex CLI / opencode — alternative for code-side work
   - Mercury core `design` agent — fresh option (cross-cwd available)

5. **Mage brief Status field update**:
   - Current: `Status: in_progress_phase1` (line 5 of brief)
   - Direction validated → `Status: phase1_complete_pending_user_decisions` ?

---

## Provenance

- **chain dispatch**: Mercury core agents from user-scope `~/.claude/agents/{game-researcher,game-analyst,game-critic}.md`
- **chain runtime**: 2026-05-10 S2-side-sot session, ~10 min wall (researcher 169s + analyst 215s + critic 236s)
- **token cost**: ~120k total (researcher 36k / analyst 46k / critic 40k)
- **outputs**:
  - `01-researcher-output.md` — full Q1-Q5 findings + handoffs (audit trail)
  - `02-analyst-output.md` — full 4-axis + 4 SP + adoption order (audit trail)
  - `03-critic-output.md` — full SP evidence + CCR + three-tier (audit trail)
- **first cross-repo lane game-* dogfood**: validates Mercury chain works from SoT cwd via cross-cwd user-scope agents

---

*Generated 2026-05-10 by S2-side-sot main agent (Claude Code Opus 4.7), Mercury cross-repo lane.*
