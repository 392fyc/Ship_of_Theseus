# Multi-Action Resource Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make standard and swift action resources real 1-to-3 point counters while every current unit still starts at one point, then expose actual capacity and remaining values to the production HUD payload.

**Architecture:** `Unit` is the only owner of capacities, remaining points, and the monotonic per-turn standard-spend counter. `GameAction` validates and consumes those fields; `TacticalManager` controls phase progression and translates them into six real HUD fields. The pre-1C HUD receives three derived compatibility keys at the dictionary boundary only—no legacy action-state booleans remain on `Unit`.

**Tech Stack:** Godot 4.6.3, GDScript, JSON gameplay inputs, standalone `SceneTree` regression scripts, PowerShell test runner.

**Spec:** `docs/superpowers/specs/2026-09-05-multi-action-resource-runtime-design.md`

## Global Constraints

- Use Godot `4.6.3.stable.official.7d41c59c4`; resolve the executable from ignored local configuration or the current process, never write a machine path into tracked files.
- `standard_capacity` and `swift_capacity` default to `1` and clamp to `1...3`; corresponding remaining values stay in `0...capacity`.
- Every standard or swift action consumes exactly one matching point. The first standard point spent immediately invalidates movement, but remaining standard points stay usable.
- `before_attack` means `standard_spent_this_turn == 0`; `after_attack` means `standard_spent_this_turn > 0`, independent of exhaustion or any future restoration.
- Remove the `swift_limit == -1` bypass. Zero-cost behavior is represented only by `action_cost: "free"`.
- Do not implement a standard or swift restore API, an extra-capacity acquisition rule, battle save migration, enemy multi-action planning, or any content source above one point.
- Do not modify `scripts/ui/**`, `scenes/**`, frozen candidate files, Theme/PNG assets, KB, design-library records, Mercury, or the three pre-existing tracked dirty files.
- Tests exercise real `Unit`, `GameAction`, `TacticalManager`, and `TacticalScene` behavior. Do not test source text and do not mock these components.
- Work only in `codex/issue-18-action-resource-bar`, starting from `ffadf60a126e668b15732cf691ddf2b8a31d5439`. Produce one final local commit and stage only paths named in this plan.

## File Responsibility Map

| Path | Responsibility |
| --- | --- |
| `scripts/units/unit.gd` | Own counter invariants, per-turn spend history, reset, consumption, and availability queries |
| `scripts/core/game_action.gd` | Validate costs/timing and consume one point; standard costs also invalidate movement |
| `scripts/core/tactical_manager.gd` | Remove `swift_limit`, wait for standard exhaustion before phase transition, and emit the 1B HUD payload |
| `tests/test_multi_action_resources.gd` | Focused counter, timing, reset, free-action, and removed-bypass behavior |
| `tests/test_action_resource_runtime.gd` | Real TacticalScene proof that the first of two standard actions does not advance the turn |
| `tests/test_action_resource_dashboard.gd` | Real six-field payload plus the temporary dictionary-only compatibility keys |
| `tests/test_action_cost_free.gd` | Free actions leave all counter resources unchanged |
| Six named `data/skills/*.json` files | Remove the obsolete local `swift_limit: 1` key and nothing else |
| Named swordfighter, harness, and capture tests | Replace deleted Unit booleans with authoritative counter behavior |

---

### Task 1: Deliver the Multi-Action Runtime Foundation

**Files:**

- Create: `tests/test_multi_action_resources.gd`
- Modify: `scripts/units/unit.gd:43-50,487-556,815-818`
- Modify: `scripts/core/game_action.gd:73-219`
- Modify: `scripts/core/tactical_manager.gd:184-203,880-898,1228-1245,1600-1630,2195-2214,3425-3452`
- Modify: `data/skills/archer_eagle_eye.json`
- Modify: `data/skills/cleric_bless.json`
- Modify: `data/skills/knight_iron_wall.json`
- Modify: `data/skills/mage_mana_shield.json`
- Modify: `data/skills/soldier_rally.json`
- Modify: `data/skills/swordsman_zhaojia.json`
- Modify: `tests/test_action_resource_runtime.gd`
- Modify: `tests/test_action_resource_dashboard.gd`
- Modify: `tests/test_action_cost_free.gd`
- Modify: `tests/capture_action_resource_bar_tactical.gd`
- Modify: `tests/test_harness_load.gd`
- Modify: `tests/test_swordsman_skillbar.gd`
- Modify: `tests/test_swordsman_runtime_path.gd`
- Modify: `tests/test_swordsman_qa_impl.gd`
- Modify: `tests/test_swordsman_p0_fixes.gd`
- Modify: `tests/test_swordsman_integration.gd`
- Include: `docs/superpowers/specs/2026-09-05-multi-action-resource-runtime-design.md`
- Include: `docs/superpowers/plans/2026-09-05-multi-action-resource-runtime.md`

**Interfaces:**

- Produces: `Unit.configure_action_resource_capacities(standard_value: int, swift_value: int) -> void` for initialization and tests only.
- Produces: public integers `standard_capacity`, `standard_remaining`, `standard_spent_this_turn`, `swift_capacity`, `swift_remaining`.
- Produces: `Unit.has_spent_standard_resource() -> bool`, `Unit.can_take_normal_attack() -> bool`, and zero-argument `Unit.can_use_swift_skill() -> bool`.
- Produces: HUD keys `movement_remaining`, `movement_available`, `standard_capacity`, `standard_remaining`, `swift_capacity`, `swift_remaining`.
- Preserves until 1C: dictionary keys `movement_used`, `standard_used`, `swift_used`, derived inside `TacticalManager.get_dashboard_data()` only.
- Removes: Unit fields `has_moved`, `has_attacked`, `has_used_swift`, `standard_used`, `swift_used`; `_sync_legacy_action_flags()`; `restore_standard_resource()`; `restore_swift_resource()`; the full `swift_limit` runtime/data path.

- [ ] **Step 1: Create the focused failing counter test**

Create `tests/test_multi_action_resources.gd` using the existing `SceneTree` assertion pattern and a real `Unit` instantiated from `scenes/tactical/Unit.tscn`. Include these literal behaviors:

```gdscript
_eq("默认标准容量为 1", unit.standard_capacity, 1)
_eq("默认标准剩余为 1", unit.standard_remaining, 1)
_eq("默认迅捷容量为 1", unit.swift_capacity, 1)
_eq("默认迅捷剩余为 1", unit.swift_remaining, 1)

unit.configure_action_resource_capacities(2, 3)
_eq("标准容量可设为 2", unit.standard_capacity, 2)
_eq("标准剩余随配置回满", unit.standard_remaining, 2)
_eq("迅捷容量可设为 3", unit.swift_capacity, 3)
_eq("迅捷剩余随配置回满", unit.swift_remaining, 3)

_check("首次标准消费前允许 before_attack",
    bool(GameAction.validate_timing_constraint(unit, "before_attack").get("ok", false)))
GameAction.consume_action_cost(unit, "standard")
_eq("首次标准消费只减一点", unit.standard_remaining, 1)
_eq("首次标准消费立即关闭移动", unit.movement_used, true)
_eq("首次标准消费累计一次", unit.standard_spent_this_turn, 1)
_check("剩余一点时普通攻击仍可用",
    bool(GameAction.can_use_normal_attack(unit).get("ok", false)))
_check("首次标准消费后拒绝 before_attack",
    not bool(GameAction.validate_timing_constraint(unit, "before_attack").get("ok", false)))
_check("首次标准消费后允许 after_attack",
    bool(GameAction.validate_timing_constraint(unit, "after_attack").get("ok", false)))

GameAction.consume_action_cost(unit, "standard")
GameAction.consume_action_cost(unit, "standard")
_eq("标准点不会低于零", unit.standard_remaining, 0)
_eq("无点时累计消费不增加", unit.standard_spent_this_turn, 2)

for index: int in 4:
    GameAction.consume_action_cost(unit, "swift")
_eq("迅捷点不会低于零", unit.swift_remaining, 0)

unit.reset_action_resources()
_eq("回合开始标准回满", unit.standard_remaining, 2)
_eq("回合开始迅捷回满", unit.swift_remaining, 3)
_eq("回合开始清零标准消费历史", unit.standard_spent_this_turn, 0)
_eq("回合开始恢复移动", unit.movement_used, false)

unit.configure_action_resource_capacities(0, 4)
_eq("标准容量下限为 1", unit.standard_capacity, 1)
_eq("迅捷容量上限为 3", unit.swift_capacity, 3)
```

Add the removed-bypass and free-action cases:

```gdscript
unit.configure_action_resource_capacities(1, 1)
unit.consume_swift_resource()
var legacy_swift: Dictionary = {
    "id": "legacy_swift_probe",
    "action_cost": "swift",
    "timing_constraint": "any",
    "swift_limit": -1,
}
_check("旧 -1 字段不能绕过耗尽的迅捷点",
    not bool(GameAction.validate_skill_usage(unit, legacy_swift).get("ok", false)))

var before_free: Array[int] = [
    unit.standard_remaining,
    unit.swift_remaining,
    unit.standard_spent_this_turn,
]
GameAction.consume_action_cost(unit, "free")
_eq("free 不改变三项计数", [
    unit.standard_remaining,
    unit.swift_remaining,
    unit.standard_spent_this_turn,
], before_free)
```

Add a final interface-removal check using the real `Unit` instance. Inspect
`get_property_list()` and `has_method()` and assert that these names are absent:

```gdscript
var removed_properties: Array[String] = [
    "standard_used", "swift_used", "has_moved", "has_attacked", "has_used_swift",
]
var removed_methods: Array[String] = [
    "_sync_legacy_action_flags", "restore_standard_resource", "restore_swift_resource",
]
```

This is a runtime interface assertion, not a source-text assertion.

- [ ] **Step 2: Change production-facing tests before production code**

In `test_action_resource_dashboard.gd`, configure the real current unit and assert the complete 1B payload:

```gdscript
current_unit.configure_action_resource_capacities(2, 3)
current_unit.consume_standard_resource()
current_unit.consume_swift_resource()
var data: Dictionary = tactical_manager.get_dashboard_data()
var resources: Dictionary = data.get("action_resources", {})
_eq("移动力数值来自当前单位", resources.get("movement_remaining"),
    maxi(0, current_unit.stats.mov))
_eq("移动仍可用", resources.get("movement_available"), true)
_eq("标准容量真实透传", resources.get("standard_capacity"), 2)
_eq("标准剩余真实透传", resources.get("standard_remaining"), 1)
_eq("迅捷容量真实透传", resources.get("swift_capacity"), 3)
_eq("迅捷剩余真实透传", resources.get("swift_remaining"), 2)
_eq("旧标准键由耗尽状态派生", resources.get("standard_used"), false)
_eq("旧迅捷键由耗尽状态派生", resources.get("swift_used"), false)
```

Reset the unit before the existing old-resource-bar visibility checks. Those checks continue using all three temporary compatibility keys until 1C.

In `test_action_resource_runtime.gd`, configure `standard=2` on the real current unit. After the first real attack assert:

```gdscript
const INPUT_ACTION_PHASE: int = 2

_eq("首次攻击后标准剩余一点", unit.standard_remaining, 1)
_eq("首次攻击后累计消费一次", unit.standard_spent_this_turn, 1)
_eq("首次攻击后移动失效", unit.movement_used, true)
_eq("首次攻击后仍在行动阶段", tactical_manager.input_state,
    INPUT_ACTION_PHASE)
_check("首次攻击后第二次普通攻击仍可用",
    bool(GameAction.can_use_normal_attack(unit).get("ok", false)))
```

Build and execute a second real attack against the existing high-HP adjacent dummy. Assert `standard_remaining == 0` and normal attack validation fails. Do not weaken any damage, survival, signal, or map-badge assertion.

In `test_action_cost_free.gd`, replace old booleans with literal before/after assertions for `standard_remaining`, `swift_remaining`, and `standard_spent_this_turn`.

- [ ] **Step 3: Migrate remaining test fixtures before production code**

Apply only these behavior-preserving changes in the named harness, swordfighter, and capture tests:

- a full action reset becomes `reset_action_resources()` when resetting movement and reaction is harmless for that fixture;
- where a fixture needs a fresh standard or swift allowance, rebuild its action-resource state with `reset_action_resources()` or `configure_action_resource_capacities()` before reconstructing any intentionally consumed movement, swift, standard, or reaction state; do not directly refill one remaining counter because that can silently rewrite `before_attack` / `after_attack` history;
- default-capacity exhaustion becomes `consume_standard_resource()` or `consume_swift_resource()`;
- reads become literal remaining-value assertions or `remaining == 0` checks;
- `capture_action_resource_bar_tactical.gd` derives the old bar's expected spent flags from `standard_remaining == 0` and `swift_remaining == 0`.

Do not change unrelated combat expectations. Do not generate visual evidence in 1B; the modified capture script is parser-checked here and is exercised windowed in 1C.

- [ ] **Step 4: Run RED and record the expected failures**

Run independently:

```powershell
& $env:GODOT_EXE --headless --path $projectRoot --script res://tests/test_multi_action_resources.gd
& $env:GODOT_EXE --headless --path $projectRoot --script res://tests/test_action_resource_dashboard.gd
& $env:GODOT_EXE --headless --path $projectRoot --script res://tests/test_action_resource_runtime.gd
```

Expected before production edits:

- the focused test exits non-zero because the capacity API and counter fields do not exist;
- the dashboard test exits non-zero because the six real fields are absent;
- the runtime test exits non-zero because it cannot configure or observe two standard points.

Syntax or fixture failures do not count as RED. Correct only test code and rerun until each failure is caused by missing production behavior.

- [ ] **Step 5: Implement the final Unit counter model**

Replace the old action-state declarations with:

```gdscript
var movement_used: bool = false
var standard_capacity: int = 1
var standard_remaining: int = 1
var standard_spent_this_turn: int = 0
var swift_capacity: int = 1
var swift_remaining: int = 1
var reaction_available: bool = true
```

Implement the final methods:

```gdscript
func configure_action_resource_capacities(
        standard_value: int, swift_value: int) -> void:
    standard_capacity = clampi(standard_value, 1, 3)
    swift_capacity = clampi(swift_value, 1, 3)
    reset_action_resources()

func reset_action_resources() -> void:
    movement_used = false
    standard_remaining = standard_capacity
    standard_spent_this_turn = 0
    swift_remaining = swift_capacity
    reaction_available = true

func consume_standard_resource() -> void:
    if standard_remaining <= 0:
        return
    standard_remaining -= 1
    standard_spent_this_turn += 1

func consume_swift_resource() -> void:
    if swift_remaining <= 0:
        return
    swift_remaining -= 1

func has_spent_standard_resource() -> bool:
    return standard_spent_this_turn > 0

func can_take_normal_attack() -> bool:
    return standard_remaining > 0

func can_use_swift_skill() -> bool:
    return swift_remaining > 0

func are_active_resources_exhausted() -> bool:
    return movement_used and standard_remaining == 0 and swift_remaining == 0
```

Delete `has_moved`, `has_attacked`, `has_used_swift`, `standard_used`, `swift_used`, both standard/swift restore methods, `_sync_legacy_action_flags()`, and every call to that sync method.

Keep the short summary's existing presentation scope while deriving it from final fields:

```gdscript
parts.append("M✓" if not movement_used else "M×")
parts.append("A✓" if standard_remaining > 0 else "A×")
parts.append("S✓" if swift_remaining > 0 else "S×")
```

- [ ] **Step 6: Implement GameAction cost and timing semantics**

Use the Unit queries in normal attack and action-cost validation:

```gdscript
static func can_use_normal_attack(unit: Unit) -> Dictionary:
    if unit == null:
        return {"ok": false, "reason": "No acting unit"}
    if not unit.can_take_normal_attack():
        return {"ok": false, "reason": "Standard Action already used"}
    return {"ok": true, "reason": ""}

static func validate_action_cost(unit: Unit, action_cost: String,
        reaction_trigger_met: bool = false) -> Dictionary:
    if unit == null:
        return {"ok": false, "reason": "No acting unit"}
    match action_cost:
        "move":
            if unit.movement_used:
                return {"ok": false, "reason": "Movement already used"}
        "standard":
            if not unit.can_take_normal_attack():
                return {"ok": false, "reason": "Standard Action already used"}
        "swift":
            if not unit.can_use_swift_skill():
                return {"ok": false, "reason": "Swift Action already used"}
        "reaction":
            if not unit.reaction_available:
                return {"ok": false, "reason": "Reaction already used"}
            if not reaction_trigger_met:
                return {"ok": false, "reason": "Reaction trigger not met"}
        "free":
            pass
        _:
            return {"ok": false, "reason": "Unknown action_cost: %s" % action_cost}
    return {"ok": true, "reason": ""}
```

`validate_skill_usage()` calls the new three-argument validator and never reads `swift_limit`:

```gdscript
var action_cost_result: Dictionary = validate_action_cost(
    unit, action_cost, reaction_trigger_met)
```

Replace attack timing branches with:

```gdscript
"before_attack":
    if unit.has_spent_standard_resource():
        return {"ok": false, "reason": "Must use before attacking"}
"after_attack":
    if not unit.has_spent_standard_resource():
        return {"ok": false, "reason": "Must use after attacking"}
```

Remove `swift_limit` from `consume_action_cost()` and always consume one swift point:

```gdscript
static func consume_action_cost(unit: Unit, action_cost: String) -> void:
    if unit == null:
        return
    match action_cost:
        "move":
            unit.consume_movement_resource()
        "standard":
            unit.consume_standard_resource()
            unit.consume_movement_resource()
        "swift":
            unit.consume_swift_resource()
        "reaction":
            unit.consume_reaction_resource()
        "free":
            pass
```

Keep `consume_normal_attack()` consuming one standard point plus movement.

- [ ] **Step 7: Implement TacticalManager progression and the 1B HUD bridge**

Emit all real fields and the temporary dictionary-only compatibility keys:

```gdscript
"action_resources": {
    "movement_remaining": maxi(0, info_unit.stats.mov),
    "movement_available": not info_unit.movement_used,
    "standard_capacity": info_unit.standard_capacity,
    "standard_remaining": info_unit.standard_remaining,
    "swift_capacity": info_unit.swift_capacity,
    "swift_remaining": info_unit.swift_remaining,
    "movement_used": info_unit.movement_used,
    "standard_used": info_unit.standard_remaining == 0,
    "swift_used": info_unit.swift_remaining == 0,
},
```

Change `_resolve_post_action_phase()` to test `current_unit.standard_remaining == 0`. If standard points remain, return to `ACTION_PHASE`; only exhaustion can enter the existing swift phase or end the turn.

Remove `swift_limit` from `_build_skill_entry()`, `_build_skill_action()`, and `_execute_skill_action()`. The execution call becomes:

```gdscript
GameAction.consume_action_cost(user, action_cost)
```

Do not change any other skill entry, action payload, targeting, damage, cooldown, sword-qi, or mark field.

- [ ] **Step 8: Remove obsolete local skill keys**

Delete only the line containing `"swift_limit": 1` from each of the six named JSON files. Do not reformat the files. Confirm no class, talent, equipment, or skill data receives a capacity field or a value above one.

- [ ] **Step 9: Run the focused GREEN suite**

Run every script independently:

```powershell
$tests = @(
  'test_multi_action_resources.gd',
  'test_action_resource_runtime.gd',
  'test_action_resource_dashboard.gd',
  'test_action_resource_bar.gd',
  'test_action_cost_free.gd',
  'test_harness_load.gd',
  'test_swordsman_skillbar.gd',
  'test_swordsman_runtime_path.gd',
  'test_swordsman_qa_impl.gd',
  'test_swordsman_p0_fixes.gd',
  'test_swordsman_integration.gd',
  'test_swordsman_resources.gd',
  'test_unit_map_token_visual.gd'
)
foreach ($test in $tests) {
  & $env:GODOT_EXE --headless --path $projectRoot --script "res://tests/$test"
  if ($LASTEXITCODE -ne 0) { throw "Failed: $test" }
}
```

Expected: every script exits `0`. The baseline cleanup warning from `test_action_cost_free.gd` may remain; no new warning class is allowed.

- [ ] **Step 10: Verify static migration boundaries**

Run:

```powershell
rg -n '\b(has_moved|has_attacked|has_used_swift|_sync_legacy_action_flags|restore_standard_resource|restore_swift_resource)\b' scripts data
rg -n '\b(has_moved|has_attacked|has_used_swift|_sync_legacy_action_flags|restore_standard_resource|restore_swift_resource)\b' tests
rg -n '\bswift_limit\b' scripts data
rg -n '\b(standard_used|swift_used)\b' scripts data tests
```

Expected:

- the first command has no hits;
- the second command only finds the removed-interface negative-probe literals in `tests/test_multi_action_resources.gd`, asserted through `get_property_list()` and `has_method()`;
- the third command has no hits; the deliberate compatibility-rejection probe remains in `tests/test_multi_action_resources.gd` only;
- `standard_used` and `swift_used` occur only as quoted, temporary HUD dictionary keys in `TacticalManager`, the old `ActionResourceBar`, and their pre-1C UI tests. They do not occur as `Unit` property access.

Run `git diff --check`. It must report no whitespace errors in task-owned files.

- [ ] **Step 11: Verify Godot import and the frozen candidate baseline**

Run:

```powershell
& $env:GODOT_EXE --headless --editor --path $projectRoot --quit
& $env:GODOT_EXE --headless --path $projectRoot --script res://tests/test_hud_production_baseline_manifest.gd
```

Expected: editor import exits `0`; manifest test reports `2687` passed, `0` failed, `218` entries, and SHA-256 `584B1C9648BDF68396F37623DBD9BFDF268CB0F32574FC34F35FEE011D2E0956`.

The editor import is the 1B parser check for the modified capture script. Do not run a windowed capture or create new screenshots until 1C.

- [ ] **Step 12: Create the single Task commit**

Confirm the three protected tracked dirty files are still unstaged. Stage only the declared production, data, test, specification, and plan paths, then commit once:

```powershell
git add -- scripts/units/unit.gd scripts/core/game_action.gd scripts/core/tactical_manager.gd data/skills/archer_eagle_eye.json data/skills/cleric_bless.json data/skills/knight_iron_wall.json data/skills/mage_mana_shield.json data/skills/soldier_rally.json data/skills/swordsman_zhaojia.json tests/test_multi_action_resources.gd tests/test_action_resource_runtime.gd tests/test_action_resource_dashboard.gd tests/test_action_cost_free.gd tests/capture_action_resource_bar_tactical.gd tests/test_harness_load.gd tests/test_swordsman_skillbar.gd tests/test_swordsman_runtime_path.gd tests/test_swordsman_qa_impl.gd tests/test_swordsman_p0_fixes.gd tests/test_swordsman_integration.gd docs/superpowers/specs/2026-09-05-multi-action-resource-runtime-design.md docs/superpowers/plans/2026-09-05-multi-action-resource-runtime.md
git commit -m "feat: add multi-action resource runtime"
```

Record the RED evidence, GREEN summaries, exact commit, unchanged protected paths, and the three remaining dictionary-only HUD compatibility keys in the SDD report and ledger. Do not push, create a PR, merge, or publish.
