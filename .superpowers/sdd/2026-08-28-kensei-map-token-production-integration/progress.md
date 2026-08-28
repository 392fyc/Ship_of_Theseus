# SDD ledger — plan: docs/superpowers/plans/2026-08-28-kensei-map-token-production-integration.md

Spec authority: `docs/superpowers/specs/2026-08-28-kensei-map-token-production-integration-design.md`
Execution branch: `codex/va4-kensei-map-token`
Merge base: `15b5d15d022d9b60e6487e7884b62961ed1825f5`
Preflight HEAD: `c257e3217c192a97260eecdd82a7865a40005235`

## Preflight shared files and interfaces

| Producer task | Consumer task | Produced / consumed contract | Finding |
|---|---|---|---|
| Task 2 | Task 3A | `DataLoader.visual_profiles[profile_id]`, production PNG, profile schema | Consistent: Task 3A validates and renders the exact profile admitted by Task 2. |
| Task 2 | Task 3B | `kensei.map_token_profile_id` and `DataLoader.visual_profiles` | Consistent: Task 3B activates the production view only for a class whose profile resolves. |
| Task 2 | Task 5 | Exact production PNG identity and kensei-only binding | Consistent: capture uses the real scene path and therefore the admitted runtime asset, not a duplicate renderer. |
| Task 3A | Task 3B | Five `MapTokenView` public methods | Consistent: every method consumed by `Unit` is explicitly produced and tested in Task 3A. |
| Task 3A | Task 5 | Configured `MapTokenView` rendering state | Consistent: capture consumes the component through the production `Unit` scene. |
| Task 3B | Task 4 | `Unit.setup(..., initial_facing)` and final combat-text anchor | Consistent: Task 4 preserves the default argument while adding the explicit facing and anchor call sites. |
| Task 3B | Task 5 | Production `Unit`, facing state, single/dual state, HUD layout | Consistent: capture exercises the public state methods and real HUD nodes specified by Task 3B. |
| Task 4 | Task 5 | Real `TacticalScene`, `UnitLayer`, and final-anchor `DamagePopup` APIs | Consistent: Task 5 instantiates the real scene and calls the final-anchor API without reproducing rendering logic. |
| Task 4 | Task 6 | Integration tests and runtime scene changes | Consistent: Task 6 requires the focused and full regression evidence produced by the implementation. |
| Task 5 | Task 6 | Three capture PNGs, full regression, independent review, user visual acceptance | Consistent: Task 6 lists these as explicit publication gates. |

## Preflight internal consistency

| Task | Tests / outputs against implementation and files | Finding |
|---|---|---|
| Task 2 | Asset test covers byte identity, dimensions, alpha, schema, pivots, loader and kensei binding; listed files supply each assertion. | Consistent. |
| Task 3A | Component tests cover valid and invalid profiles plus all eight frame states; the new component owns all tested properties. | Consistent. |
| Task 3B | Unit tests cover production activation, placeholder fallback, HUD anchors, weapon row, facing priority and death; scene and script files provide those behaviors. | Consistent. |
| Task 4 | Popup and tactical tests cover legacy/final anchors, `UnitLayer`, spawn compatibility, initial facing and forecast anchors; listed production files own each behavior. | Consistent. |
| Task 5 | Capture script must use real `TacticalScene`, save three 1280×720 files, then run focused and full regression; no duplicated renderer is requested. | Consistent. |
| Task 6 | Candidate checks, controlled publish, PR evidence, merge and post-merge verification follow only after visual acceptance and clean independent review. | Consistent. |

Preflight result: no contradiction with the spec, Global Constraints, test rubric, or later consumer interfaces.

Baseline: Godot `4.6.3.stable.official.7d41c59c4`; fresh-worktree import completed; all 36 pre-existing `tests/test_*.gd` passed before implementation.

Task 2: dispatched implementer `/root/va4_task2_implement` at base `c257e3217c192a97260eecdd82a7865a40005235`.
Task 2: implementer `DONE_WITH_CONCERNS`, commit `dfeb15be8e7549b5d8ab8064743a6ad4066e1fb3`; focused 32/0, related 430/0 and 252/0. Godot rewrote `project.godot` line endings but normalized content matched HEAD; refreshing the index produced a clean tree with no staged diff.
Task 2: independent review dispatched as `/root/va4_task2_review` with package `review-c257e32..dfeb15b.diff`.
Task 2: review found 1 Important issue: the fixed test contract requires integer array literals for `frame_grid` and `source_frame_size`; current test uses float literals. Review also requested fresh Godot 4.6 focused evidence.
Task 2: fix round 1/5 (Godot focused evidence addressed; exact assertions still open; commit `00652604b6e5075675f2a5d0f22568c117fd87ce`). Re-review found `_integer_array()` truncates fractional values and therefore weakens the exact contract.
Task 2: fix round 2/5 (direct integer-literal comparison restored, but Godot 4.6.3 focused test failed 30/2; commit `62177a034e049f7d862b3dffb22b6ee04ce1a30f`).
Task 2: Ruling: compare `frame_grid` and `source_frame_size` directly against float arrays `[4.0, 2.0]` and `[384.0, 512.0]`, with no coercion — Godot 4.6.3 parses JSON numbers as floats, while the binding spec requires exact numeric dimensions but not Variant integer types — if wrong, the test contract would encode Godot's runtime representation rather than the plan's literal integer syntax and would need a later test-only revision.
Task 2: fix round 3/5 (exact direct float-array assertions; focused 32/0; commit `b5c4327aa24f565ebebd936e6ea9dde5a2a65df3`). Scoped re-review: all findings addressed, no new Critical/Important breakage.
Task 2: complete (commits `c257e32..b5c4327`, review clean).
Task 3: dispatched implementer `/root/va4_task3_implement` at base `b5c4327aa24f565ebebd936e6ea9dde5a2a65df3`.
Task 3: implementer DONE, commits `90450946bd61689afed8b9f961f70fb297e1a731` and `f1d16a452cfaac7b35ecc462d4e51638f219b00f`; component 55/0, unit 26/0, state registry 65/0.
Task 3: independent review dispatched as `/root/va4_task3_review` with package `review-b5c4327..f1d16a4.diff`.
Task 3: review found 2 Important issues: non-finite overhead layout values are accepted; texture setup bypasses Godot ResourceLoader and decodes a new PNG per unit. Minor findings: no nonexistent-texture test; expected negative fixtures emit unqualified ERROR logs.
Task 3: runtime hash strategy for fix: Task 2's asset test remains the build-time exact-byte gate; `MapTokenView` uses ResourceLoader for export-safe cached textures and, only when the raw source path is directly readable, compares a cached actual SHA against the profile.
Task 3: fix round 1/5 (3 Important/Minor findings addressed, 0 Critical/Important open; commits `f1d16a4..64b264e`). Re-review: component 73/0, unit 26/0, asset 32/0; no new breakage.
Task 3: minor (deferred): deliberate invalid-profile fixtures emit production `push_error` diagnostics even though assertions pass and exit code is 0; final whole-branch review must triage whether test-only diagnostic capture is worth adding.
Task 3: complete (commits `b5c4327..64b264e`, review clean).
Task 4: dispatched implementer `/root/va4_task4_implement` at base `64b264e67ae35a52e4fca8053a149d40afd8aeb9`.
Task 4: implementer DONE, commit `45a6fe745bed68ae193d387e7e45c8507d6e2c84`; 9/9 affected tests passed, 399 assertions and 0 failures.
Task 4: independent review dispatched as `/root/va4_task4_review` with package `review-64b264e..45a6fe7.diff`.
Task 4: review passed spec and approved code quality; 0 Critical/Important findings.
Task 4: minor (deferred): end-to-end coverage does not directly assert every final-anchor public popup path, main/offhand hit and MISS position, skill forecast exact world, or legacy three-argument default SE; final review must triage.
Task 4: minor (deferred): two affected legacy fixtures emit expected warnings; test exits and assertions remain clean.
Task 4: complete (commits `64b264e..45a6fe7`, review clean).
Task 5: dispatched implementer `/root/va4_task5_implement` at base `45a6fe745bed68ae193d387e7e45c8507d6e2c84`.
Task 5: implementer DONE, commit `2245da30c830e2e38688a725f8138cf54b124b8f`; three 1280×720 captures in batch `batch_1787862460`; full regression 40/40.
Task 5: capture environment concern: Windows Godot 4.6.3 `--headless` did not emit `RenderingServer.frame_post_draw`; successful evidence used the same console binary in windowed rendering mode.
Task 5: independent review dispatched as `/root/va4_task5_review` with package `review-45a6fe7..2245da3.diff` and the three PNG paths.
Task 5: review found 2 Important issues: the advertised headless capture hangs instead of failing, and the 40/40 regression summary lacks an auditable full-output artifact. Minor: third capture does not assert facing/offhand setup success.
Task 5: Ruling: Windows visual capture uses the same Godot 4.6.3 console in windowed rendering mode; headless is a non-rendering validation path that must fail fast, and the tracked plan's Task 5 command is updated accordingly — the spec requires real root-viewport evidence, not a headless display driver — if wrong, automated environments without a Windows display cannot regenerate the screenshots and would need a separate GPU-backed capture service.
Task 5: fix round 1/5 (all 3 findings addressed; commit `ffff3f77e2f571eecfe7d1b3a98b894def3933e2`). Re-review confirmed headless fast-fail, synchronized plan contract, third-capture guards, and auditable full regression log SHA256 `9f6a2486fc2ef26c398a44893d8c37565278f28c583cfe580800914c2a24296b`; no new Critical/Important breakage.
Task 5: technical implementation and independent review complete; new capture batch `batch_1787863054`, full regression 40/40. Awaiting user visual acceptance before completion and Task 6.
Task 5: user visual acceptance passed on 2026-08-28.
Task 5: complete (commits `45a6fe7..ffff3f7`, review clean and user accepted).
Task 6: in progress; final whole-branch review precedes controlled publication.
Final review: `Ready to merge: With fixes`; 1 Important blocker: the third capture shows M/A/S action badges but no real Buff-driven overhead status icon at `status_badge_y=-84`. Deferred minors remain non-blocking: incomplete end-to-end anchor/default-SE coverage and expected negative-fixture diagnostics.
Final fix wave: in progress; must add a real Buff to the third capture, assert the status label and Y=-84, regenerate evidence, rerun focused/full tests, and obtain renewed user visual acceptance.
Final fix wave: commit `dd12358c4c422bf93e25481da7ea29925bc3705e`; scoped re-review passed the Important finding with no new Critical/Important breakage. New batch `batch_1787914830`, full regression 40/40. Awaiting renewed user acceptance of the third image only.
Ruling: VA-4 不为 Buff/Debuff 预留正式的血条关联样式或锚点；正式棋子配置只负责血条 `bottom=-58` 与伤害/弹出信息 `anchor=-82`。既有通用状态显示保留 `STATUS_BADGE_Y=-58` 基线，不作为 VA-4 视觉验收。错误成本：若此判断错误，VA-4 将不预留正式 Buff/Debuff 锚点，未来专门里程碑需另行设计与接入。
Final review fix round 1/5：规格和计划的 VA-4 正向完成条件仅覆盖血条、生命值文字与战斗文字弹出信息；通用 Buff/Debuff 状态系统仅作为保留保护，不定义样式或位置。Godot `4.6.3.stable.official.7d41c59c4` 全量回归 `40/40`；可审计日志为 `task-5-buff-scope-correction-full-regression.log`，SHA256 `15ccbbf0be034a2ffa6728f9b90dc8b2de61b6343b7e56d86137f08e6bb0b3c1`。
