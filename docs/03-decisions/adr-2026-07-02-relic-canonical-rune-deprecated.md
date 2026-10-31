# ADR-010 - Relic Canonical Terminology and Rune Deprecation

**Date**: 2026-07-02
**Status**: Accepted
**Decision Maker**: Human Supervisor

---

## Background

The 5-layer architecture consensus (`03-decisions/architecture-consensus-v2.md`, 2026-05-10, consensus_locked) named the L5 build-defining layer "Rune 符文 6 slots", with delta note Δ-2 stating "旧 relic 概念: D5 决定并入或弃用" (the old Relic concept would be merged or deprecated by design stream D5). D5 was never executed: neither `runes-system.md` nor any Rune ADR was ever written.

Meanwhile the older canonical design documents (`01-Game-Design/Progression/run-loop.md`, `01-Game-Design/Characters/class-system.md`) consistently use "Relic 遗物" for the same L5 concept. This left two names for one system - the largest terminology gap in the KB, flagged as decision D-A in the run-loop reward and map design proposal (2026-07-02, `Ship_of_Theseus/dev_doc/runloop-design/runloop-reward-map-proposal.md`).

## Decision

User ruling 2026-07-02 (D-A of the run-loop proposal):

1. **Relic 遗物 is the canonical term.** Relic is the intended roguelite gameplay concept; it is one single system.
2. **Rune 符文 is deprecated as a term.** It survives only as a historical name inside research documents that were deleted from the KB on 2026-10-31 and remain at fixed commits.
3. **Mechanics are unchanged.** L5 remains: 6 slots hard cap, run-reset, build-defining, two archetypes (economy-type and playstyle-type), L1 grants 1 starting item per run. Only the name changes.
4. The never-written system spec file planned by Δ-2 is renamed: `runes-system.md` becomes `relics-system.md` (still pending).
5. Data layer naming: `data/relics/`, `RewardDrop.kind = "relic"`. No `"rune"` kind exists.

This ADR records an authorized amendment to a consensus_locked document (user granted the re-confirmation required by architecture-consensus-v2).

## Consequences

Files updated 2026-07-02 together with this ADR:

- `03-decisions/architecture-consensus-v2.md` - all L5 Rune terminology replaced with Relic; amendment note added; delta Δ-2 resolved.
- `03-decisions/architecture-consensus-v2.html` - visual companion terminology synced.
- `01-Game-Design/Core-Systems/battle-calculation.md` - crit damage bonus source list wording synced (Rune to Relic).
- `01-Game-Design/Progression/run-loop.md` - already used Relic; no terminology change needed (map and reward sections updated separately by the run-loop proposal round 2).
- Repo artifacts `Ship_of_Theseus/dev_doc/runloop-design/runloop-reward-map-proposal.md` and `.html` - proposal round 2 unified to Relic, `RewardDrop.kind` uses `"relic"`.

Collateral wording change declared here (beyond pure terminology): in `architecture-consensus-v2.md/.html`, the L5 acquisition timing cell originally read "town 经济稳定 + run 内事件"; because the town system is deferred for run-loop v1/v2 (user ruling 2026-07-02), it now reads "run 内奖励/商店/事件（城镇渠道暂缓）". This defers the town acquisition channel; it does not permanently remove it from the L5 design.

Deliberately NOT updated (these documents keep their original wording and were deleted from the KB on 2026-10-31; permanent links to the last commit that held them):

- Stage 2 runes proposal [D5-runes-system.md](https://github.com/392fyc/Ship_of_Theseus/blob/30e3c5e5d57e9a74f01d19ca948c869512f66a0c/docs/90-archive/architecture-stage2-2026-05-10/D5-runes-system.md) (deleted from the KB 2026-10-31; permanent link to the last commit that held it).
- Frozen design snapshot [swordsman-final-design-v4.html](https://github.com/392fyc/Ship_of_Theseus/blob/30e3c5e5d57e9a74f01d19ca948c869512f66a0c/docs/90-archive/sw-design-drafts-2026-07-28/swordsman-final-design-v4.html) (deleted from the KB 2026-10-31; permanent link to the last commit that held it).

Follow-up (pending, not blocked by this ADR):

- Write `01-Game-Design/Core-Systems/relics-system.md` when the L5 content spec is designed (slot economics, archetype catalog, rarity tiers - the open questions formerly assigned to D5).
